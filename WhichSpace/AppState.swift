import Cocoa
import Combine
import os.log

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    private static let logger = Logger(subsystem: "io.gechr.WhichSpace", category: "AppState")

    private(set) var currentSpace = 0
    private(set) var currentSpaceLabel = "?"
    private(set) var darkModeEnabled = false

    private let mainDisplay = "Main"
    private let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"
    private let conn = _CGSDefaultConnection()

    private var lastUpdateTime: Date = .distantPast
    private var mouseEventMonitor: Any?
    private var spacesMonitor: DispatchSourceFileSystemObject?

    private init() {
        updateDarkModeStatus()
        configureObservers()
        configureSpaceMonitor()
        updateActiveSpaceNumber()
    }

    // MARK: - Observers

    private func configureObservers() {
        let workspace = NSWorkspace.shared
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(updateActiveSpaceNumber),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: workspace
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updateDarkModeStatus),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateActiveSpaceNumber),
            name: NSApplication.didUpdateNotification,
            object: nil
        )

        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(updateActiveSpaceNumber),
            name: NSWorkspace.didActivateApplicationNotification,
            object: workspace
        )

        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard let self, Date().timeIntervalSince(self.lastUpdateTime) > 0.5 else {
                    return
                }
                self.updateActiveSpaceNumber()
            }
        }
    }

    // MARK: - Space Monitor

    private func configureSpaceMonitor() {
        spacesMonitor?.cancel()
        spacesMonitor = nil

        let path = spacesMonitorFile
        let fullPath = (path as NSString).expandingTildeInPath
        let queue = DispatchQueue.global(qos: .default)
        let fildes = open(fullPath.cString(using: String.Encoding.utf8)!, O_EVTONLY)
        if fildes == -1 {
            Self.logger.error("Failed to open file: \(path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fildes,
            eventMask: .delete,
            queue: queue
        )

        source.setEventHandler { [weak self] in
            let flags = source.data.rawValue
            if flags & DispatchSource.FileSystemEvent.delete.rawValue != 0 {
                Task { @MainActor in
                    self?.updateActiveSpaceNumber()
                    self?.configureSpaceMonitor()
                }
            }
        }

        source.setCancelHandler {
            close(fildes)
        }

        source.resume()
        spacesMonitor = source
    }

    // MARK: - Space Detection

    @objc func updateActiveSpaceNumber() {
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary],
              let activeDisplay = CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String
        else {
            return
        }

        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let spaces = display["Spaces"] as? [[String: Any]],
                  let displayID = display["Display Identifier"] as? String
            else {
                continue
            }

            guard displayID == mainDisplay || displayID == activeDisplay else {
                continue
            }

            guard let activeSpaceID = current["ManagedSpaceID"] as? Int else {
                continue
            }

            var localIndex = 0
            for space in spaces {
                guard let spaceID = space["ManagedSpaceID"] as? Int else {
                    continue
                }

                let isFullscreen = space["TileLayoutManager"] is [String: Any]
                if isFullscreen {
                    if spaceID == activeSpaceID {
                        lastUpdateTime = Date()
                        return
                    }
                    continue
                }

                localIndex += 1
                if spaceID == activeSpaceID {
                    currentSpace = localIndex
                    currentSpaceLabel = String(localIndex)
                    lastUpdateTime = Date()
                    return
                }
            }
        }

        currentSpace = 0
        currentSpaceLabel = "?"
    }

    @objc func updateDarkModeStatus() {
        let dictionary = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        if let interfaceStyle = dictionary?["AppleInterfaceStyle"] as? NSString {
            darkModeEnabled = interfaceStyle.localizedCaseInsensitiveContains("dark")
        } else {
            darkModeEnabled = false
        }
    }

    // MARK: - Helpers

    var currentIconStyle: IconStyle {
        SpacePreferences.iconStyle(forSpace: currentSpace) ?? .square
    }

    var currentSymbol: String? {
        SpacePreferences.sfSymbol(forSpace: currentSpace)
    }

    var currentColors: SpaceColors? {
        SpacePreferences.colors(forSpace: currentSpace)
    }

    func getAllSpaceIndices() -> Set<Int> {
        var indices = Set<Int>()
        guard let displays = CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary] else {
            return indices
        }

        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]] else {
                continue
            }

            var localIndex = 0
            for space in spaces {
                let isFullscreen = space["TileLayoutManager"] is [String: Any]
                if isFullscreen { continue }
                localIndex += 1
                indices.insert(localIndex)
            }
        }

        return indices
    }

    // MARK: - Icon Generation

    var statusBarIcon: NSImage {
        if let symbol = currentSymbol {
            SpaceIconGenerator.generateSFSymbolIcon(
                symbolName: symbol,
                darkMode: darkModeEnabled,
                customColors: currentColors
            )
        } else {
            SpaceIconGenerator.generateIcon(
                for: currentSpaceLabel,
                darkMode: darkModeEnabled,
                customColors: currentColors,
                style: currentIconStyle
            )
        }
    }
}
