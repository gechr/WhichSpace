//
//  SpaceMonitor.swift
//  WhichSpace
//
//  Created by George Christou.
//  Copyright © 2020 George Christou. All rights reserved.
//

import Foundation
import os.log

/// Actor that watches the system spaces plist and emits a tick whenever
/// cfprefsd replaces it. Consumers route ticks through
/// SpaceUpdateCoordinator so this fallback path shares the same debounce
/// and snapshot rebuild as every other space-change signal.
actor SpaceMonitor {
    private static let logger = Logger(subsystem: "io.gechr.WhichSpace", category: "SpaceMonitor")
    private static let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"

    private var fileMonitor: DispatchSourceFileSystemObject?
    private var continuation: AsyncStream<Void>.Continuation?
    private var retryTask: Task<Void, Never>?

    /// Creates an async stream that ticks on every spaces plist replacement
    func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        setContinuation(continuation)
        return stream
    }

    private func setContinuation(_ continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
        startMonitoring()

        continuation.onTermination = { @Sendable _ in
            Task {
                await self.handleTermination()
            }
        }
    }

    private func handleTermination() {
        continuation = nil
        stopMonitoring()
    }

    private func restartMonitoring() {
        stopMonitoring()
        startMonitoring(emitAfterOpening: true)
    }

    private func startMonitoring(retryAttempt: Int = 0, emitAfterOpening: Bool = false) {
        let path = Self.spacesMonitorFile
        let fullPath = (path as NSString).expandingTildeInPath
        guard let cPath = fullPath.cString(using: .utf8) else {
            Self.logger.error("Failed to get C string path for: \(path)")
            return
        }

        let fildes = open(cPath, O_EVTONLY)
        if fildes == -1 {
            // The plist is atomically replaced (delete + recreate), so a reopen
            // can race the recreate. Keep retrying at a capped rate while the
            // change stream is alive.
            guard continuation != nil else {
                return
            }
            let retryDelay = Self.retryDelay(forAttempt: retryAttempt)
            if retryAttempt == 0 {
                Self.logger.warning("Failed to open file, retrying: \(path)")
            } else {
                Self.logger.debug("File still unavailable, retrying: \(path)")
            }
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: retryDelay)
                guard !Task.isCancelled else {
                    return
                }
                await self?.retryMonitoring(
                    retryAttempt: min(retryAttempt + 1, 5),
                    emitAfterOpening: emitAfterOpening
                )
            }
            return
        }
        retryTask = nil
        if retryAttempt > 0 {
            Self.logger.info("Resumed monitoring: \(path)")
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
                await restartMonitoring()
            }
        }

        source.setCancelHandler {
            close(fildes)
        }

        source.resume()
        fileMonitor = source
        if emitAfterOpening {
            continuation?.yield()
        }
    }

    private func retryMonitoring(retryAttempt: Int, emitAfterOpening: Bool) {
        // The stream may have terminated while the retry was pending
        guard continuation != nil, fileMonitor == nil else {
            return
        }
        retryTask = nil
        startMonitoring(retryAttempt: retryAttempt, emitAfterOpening: emitAfterOpening)
    }

    private func stopMonitoring() {
        retryTask?.cancel()
        retryTask = nil
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    nonisolated static func retryDelay(forAttempt attempt: Int) -> Duration {
        let multiplier = 1 << min(max(attempt, 0), 5)
        return .milliseconds(min(100 * multiplier, 2000))
    }

    deinit {
        retryTask?.cancel()
        fileMonitor?.cancel()
    }
}
