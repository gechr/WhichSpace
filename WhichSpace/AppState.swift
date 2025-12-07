import Cocoa
import Combine
import Defaults
import os.log

@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    private static let logger = Logger(subsystem: "io.gechr.WhichSpace", category: "AppState")

    private(set) var currentSpace = 0
    private(set) var currentSpaceLabel = "?"
    private(set) var darkModeEnabled = false
    private(set) var allSpaceLabels: [String] = []

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

            var regularSpaceIndex = 0
            var spaceLabels: [String] = []
            var foundActiveSpace = false
            var activeIndex = 0

            for space in spaces {
                guard let spaceID = space["ManagedSpaceID"] as? Int else {
                    continue
                }

                let isFullscreen = space["TileLayoutManager"] is [String: Any]
                let label: String
                if isFullscreen {
                    label = Labels.fullscreen
                } else {
                    regularSpaceIndex += 1
                    label = String(regularSpaceIndex)
                }

                spaceLabels.append(label)

                if spaceID == activeSpaceID {
                    activeIndex = spaceLabels.count
                    currentSpace = activeIndex
                    currentSpaceLabel = label
                    lastUpdateTime = Date()
                    foundActiveSpace = true
                }
            }

            allSpaceLabels = spaceLabels

            if foundActiveSpace {
                return
            }
        }

        currentSpace = 0
        currentSpaceLabel = "?"
        allSpaceLabels = []
    }

    @objc func updateDarkModeStatus() {
        let appearance = NSApp.effectiveAppearance
        darkModeEnabled = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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

    func getAllSpaceIndices() -> [Int] {
        guard !allSpaceLabels.isEmpty else {
            return []
        }
        return Array(1 ... allSpaceLabels.count)
    }

    // MARK: - Icon Generation

    var showAllSpaces: Bool {
        Defaults[.showAllSpaces]
    }

    var statusBarIcon: NSImage {
        // Check current appearance directly each time
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if showAllSpaces, !allSpaceLabels.isEmpty {
            return generateCombinedIcon(darkMode: isDark)
        }
        return generateSingleIcon(for: currentSpace, label: currentSpaceLabel, darkMode: isDark)
    }

    private func generateSingleIcon(for space: Int, label: String, darkMode: Bool) -> NSImage {
        let colors = SpacePreferences.colors(forSpace: space)
        let style = SpacePreferences.iconStyle(forSpace: space) ?? .square

        // Fullscreen spaces just show "F" with the same colors
        if label == Labels.fullscreen {
            return SpaceIconGenerator.generateIcon(
                for: Labels.fullscreen,
                darkMode: darkMode,
                customColors: colors,
                style: style
            )
        }

        let symbol = SpacePreferences.sfSymbol(forSpace: space)

        if let symbol {
            return SpaceIconGenerator.generateSFSymbolIcon(
                symbolName: symbol,
                darkMode: darkMode,
                customColors: colors
            )
        }
        return SpaceIconGenerator.generateIcon(
            for: label,
            darkMode: darkMode,
            customColors: colors,
            style: style
        )
    }

    private func generateCombinedIcon(darkMode: Bool) -> NSImage {
        let totalWidth = Double(allSpaceLabels.count) * Layout.statusItemWidth
        let combinedImage = NSImage(size: NSSize(width: totalWidth, height: Layout.statusItemHeight))

        combinedImage.lockFocus()

        for (index, label) in allSpaceLabels.enumerated() {
            let spaceIndex = index + 1
            let isActive = spaceIndex == currentSpace
            let icon = generateSingleIcon(for: spaceIndex, label: label, darkMode: darkMode)

            let xOffset = Double(index) * Layout.statusItemWidth
            let drawRect = NSRect(
                x: xOffset,
                y: 0,
                width: Layout.statusItemWidth,
                height: Layout.statusItemHeight
            )

            // Draw with reduced opacity for inactive spaces
            let alpha = isActive ? 1.0 : 0.35
            icon.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: alpha)
        }

        combinedImage.unlockFocus()
        return combinedImage
    }
}
