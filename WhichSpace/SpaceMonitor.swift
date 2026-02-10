//
//  SpaceMonitor.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Foundation
import os.log

/// Actor that monitors system space changes and emits SpaceSnapshot values
actor SpaceMonitor {
    private static let logger = Logger(subsystem: "io.gechr.WhichSpace", category: "SpaceMonitor")
    private static let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"

    private var fileMonitor: DispatchSourceFileSystemObject?
    private var continuation: AsyncStream<SpaceSnapshot>.Continuation?
    private let snapshotBuilder: @Sendable () async -> SpaceSnapshot

    /// Creates a SpaceMonitor with a snapshot builder closure
    /// - Parameter snapshotBuilder: Called on file change to create the current SpaceSnapshot
    init(snapshotBuilder: @escaping @Sendable () async -> SpaceSnapshot) {
        self.snapshotBuilder = snapshotBuilder
    }

    /// Creates an async stream of space snapshots
    func snapshots() -> AsyncStream<SpaceSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: SpaceSnapshot.self)
        setContinuation(continuation)
        return stream
    }

    private func setContinuation(_ continuation: AsyncStream<SpaceSnapshot>.Continuation) {
        self.continuation = continuation
        startMonitoring()

        continuation.onTermination = { @Sendable _ in
            Task {
                await self.stopMonitoring()
            }
        }
    }

    private func restartMonitoring() {
        stopMonitoring()
        startMonitoring()
    }

    private func startMonitoring() {
        let path = Self.spacesMonitorFile
        let fullPath = (path as NSString).expandingTildeInPath
        guard let cPath = fullPath.cString(using: .utf8) else {
            Self.logger.error("Failed to get C string path for: \(path)")
            return
        }

        let fildes = open(cPath, O_EVTONLY)
        if fildes == -1 {
            Self.logger.error("Failed to open file: \(path)")
            return
        }

        let queue = DispatchQueue.global(qos: .default)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fildes,
            eventMask: .delete,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            let flags = source.data.rawValue
            guard flags & DispatchSource.FileSystemEvent.delete.rawValue != 0,
                  let self
            else {
                return
            }

            Task { [self] in
                await emitSnapshot()
                await restartMonitoring()
            }
        }

        source.setCancelHandler {
            close(fildes)
        }

        source.resume()
        fileMonitor = source
    }

    private func stopMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    private func emitSnapshot() async {
        let snapshot = await snapshotBuilder()
        continuation?.yield(snapshot)
    }

    deinit {
        fileMonitor?.cancel()
    }
}
