import Cocoa
import Combine
import Defaults
import os.log

// MARK: - Display Space Provider Protocol

/// Protocol for abstracting CGS display space functions for testability
protocol DisplaySpaceProviding {
    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]?
    func copyActiveMenuBarDisplayIdentifier() -> String?
    func spacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int>
}

/// Default implementation using the actual CGS/SLS functions
struct CGSDisplaySpaceProvider: DisplaySpaceProviding {
    private let conn: Int32

    init() {
        conn = _CGSDefaultConnection()
    }

    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]? {
        CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary]
    }

    func copyActiveMenuBarDisplayIdentifier() -> String? {
        CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String
    }

    func spacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int> {
        // Get all windows (not just on-screen) to detect windows on other spaces
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // Collect all qualifying window IDs for a single batch query
        var windowIDs: [Int] = []

        for window in windowList {
            // Filter to regular windows (layer 0) - skip menu bar, dock, etc.
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            // Skip windows that are too small (likely utility/overlay windows)
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 5, height > 5
            else {
                continue
            }

            if let windowNumber = window[kCGWindowNumber as String] as? Int {
                windowIDs.append(windowNumber)
            }
        }

        guard !windowIDs.isEmpty else {
            return []
        }

        // Single batch call to get all spaces for all windows
        // Selector 0x7 = all spaces the windows are on
        guard let result = SLSCopySpacesForWindows(conn, 0x7, windowIDs as CFArray) else {
            return []
        }
        let spaces = result.takeRetainedValue() as? [Int] ?? []

        let spaceIDSet = Set(spaceIDs)
        return Set(spaces).intersection(spaceIDSet)
    }
}

/// Information about spaces on a single display
struct DisplaySpaceInfo: Equatable {
    let displayID: String
    let labels: [String]
    let spaceIDs: [Int]
    /// The global starting index for this display's spaces (1-based)
    var globalStartIndex = 1
}

/// Geometry for rendered status bar icons (used for hit testing)
struct StatusBarIconSlot: Equatable {
    let startX: Double
    let width: Double
    let label: String
    /// The numeric space to activate (nil for non-switchable items such as fullscreen apps)
    let targetSpace: Int?
}

@MainActor
@Observable
final class AppState {
    private struct CrossDisplaySpace {
        let displayID: String
        let localIndex: Int
        let globalIndex: Int
        let label: String
        let spaceID: Int
        let isActive: Bool
    }

    static let shared = AppState()

    private static let logger = Logger(subsystem: "io.gechr.WhichSpace", category: "AppState")

    private(set) var currentSpace = 0
    private(set) var currentSpaceLabel = "?"
    private(set) var currentDisplayID: String?
    private(set) var darkModeEnabled = false
    private(set) var allSpaceLabels: [String] = []
    private(set) var allSpaceIDs: [Int] = []

    /// Space info for all displays (used when showAllDisplays is enabled)
    private(set) var allDisplaysSpaceInfo: [DisplaySpaceInfo] = []
    /// The global space index of the current space across all displays (1-based)
    private(set) var currentGlobalSpaceIndex = 0

    private let mainDisplay = "Main"
    private let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"
    private let displaySpaceProvider: DisplaySpaceProviding
    let store: DefaultsStore

    private var lastUpdateTime: Date = .distantPast
    private var mouseEventMonitor: Any?
    private var spacesMonitor: DispatchSourceFileSystemObject?
    private var pendingUpdateTask: Task<Void, Never>?
    private static let debounceInterval: Duration = .milliseconds(50)

    // Cache for spacesWithWindows to avoid repeated expensive CGS calls
    private var cachedSpacesWithWindows: Set<Int> = []
    private var cachedSpacesWithWindowsTime: Date = .distantPast
    private var cachedSpacesWithWindowsSpaceIDs: [Int] = []
    private static let spacesWithWindowsCacheTTL: TimeInterval = 0.2

    private init() {
        displaySpaceProvider = CGSDisplaySpaceProvider()
        store = .shared
        updateDarkModeStatus()
        configureObservers()
        configureSpaceMonitor()
        performSpaceUpdate()
    }

    /// Internal initializer for testing with a custom display space provider
    init(displaySpaceProvider: DisplaySpaceProviding, skipObservers: Bool = false, store: DefaultsStore = .shared) {
        self.displaySpaceProvider = displaySpaceProvider
        self.store = store
        updateDarkModeStatus()
        if !skipObservers {
            configureObservers()
            configureSpaceMonitor()
        }
        performSpaceUpdate()
    }

    // MARK: - Test Helpers

    /// Forces an immediate space update without debounce
    func forceSpaceUpdate() {
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        performSpaceUpdate()
    }

    /// Sets space labels and current space directly for testing the rendering path
    func setSpaceState(
        labels: [String],
        currentSpace: Int,
        currentLabel: String,
        displayID: String? = nil,
        // swiftlint:disable:next discouraged_optional_collection
        spaceIDs: [Int]? = nil,
        // swiftlint:disable:next discouraged_optional_collection
        allDisplays: [DisplaySpaceInfo]? = nil,
        globalSpaceIndex: Int? = nil
    ) {
        allSpaceLabels = labels
        self.currentSpace = currentSpace
        currentSpaceLabel = currentLabel
        currentDisplayID = displayID
        allSpaceIDs = spaceIDs ?? Array(100 ..< 100 + labels.count)
        allDisplaysSpaceInfo = allDisplays ?? []
        currentGlobalSpaceIndex = globalSpaceIndex ?? currentSpace
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
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(updateActiveSpaceNumber),
            name: NSNotification.Name("NSWorkspaceActiveDisplayDidChangeNotification"),
            object: nil
        )

        // Mission Control / Exposé dismissal
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updateActiveSpaceNumber),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updateActiveSpaceNumber),
            name: NSNotification.Name("com.apple.exposeworkspacesdidchange"),
            object: nil
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
        // Cancel any pending update and schedule a new one
        pendingUpdateTask?.cancel()
        pendingUpdateTask = Task {
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else {
                return
            }
            performSpaceUpdate()
        }
    }

    private func performSpaceUpdate() {
        // Invalidate window cache on space change to get fresh window data
        invalidateSpacesWithWindowsCache()

        guard let displays = displaySpaceProvider.copyManagedDisplaySpaces(),
              let activeDisplay = displaySpaceProvider.copyActiveMenuBarDisplayIdentifier()
        else {
            return
        }

        // Collect space info from ALL displays
        var allDisplays: [DisplaySpaceInfo] = []
        var activeSpaceIDToFind: Int?
        var foundActiveDisplay = false

        // First pass: find the active space ID from the active display
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let displayID = display["Display Identifier"] as? String
            else {
                continue
            }
            if displayID == mainDisplay || displayID == activeDisplay {
                activeSpaceIDToFind = current["ManagedSpaceID"] as? Int
                break
            }
        }

        // Second pass: collect all displays' spaces
        for display in displays {
            guard let spaces = display["Spaces"] as? [[String: Any]],
                  let displayID = display["Display Identifier"] as? String
            else {
                continue
            }

            var regularSpaceIndex = 0
            var spaceLabels: [String] = []
            var spaceIDs: [Int] = []

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
                spaceIDs.append(spaceID)
            }

            if !spaceLabels.isEmpty {
                allDisplays.append(DisplaySpaceInfo(
                    displayID: displayID,
                    labels: spaceLabels,
                    spaceIDs: spaceIDs
                ))
            }
        }

        // Calculate global start indices
        var globalIndex = 1
        for index in 0 ..< allDisplays.count {
            allDisplays[index].globalStartIndex = globalIndex
            globalIndex += allDisplays[index].labels.count
        }

        allDisplaysSpaceInfo = allDisplays

        // Now find the active display and set current space info
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
            var spaceIDs: [Int] = []

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
                spaceIDs.append(spaceID)

                if spaceID == activeSpaceID {
                    let activeIndex = spaceLabels.count
                    currentSpace = activeIndex
                    currentSpaceLabel = label
                    currentDisplayID = displayID
                    lastUpdateTime = Date()
                    foundActiveDisplay = true

                    // Calculate global space index
                    if let displayInfo = allDisplays.first(where: { $0.displayID == displayID }) {
                        currentGlobalSpaceIndex = displayInfo.globalStartIndex + activeIndex - 1
                    } else {
                        currentGlobalSpaceIndex = activeIndex
                    }
                }
            }

            allSpaceLabels = spaceLabels
            allSpaceIDs = spaceIDs

            if foundActiveDisplay {
                return
            }
        }

        currentSpace = 0
        currentSpaceLabel = "?"
        currentDisplayID = nil
        currentGlobalSpaceIndex = 0
        allSpaceLabels = []
        allSpaceIDs = []
        allDisplaysSpaceInfo = []
    }

    @objc func updateDarkModeStatus() {
        let appearance = NSApp.effectiveAppearance
        darkModeEnabled = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Helpers

    var currentIconStyle: IconStyle {
        SpacePreferences.iconStyle(forSpace: currentSpace, display: currentDisplayID, store: store) ?? .square
    }

    var currentSymbol: String? {
        SpacePreferences.sfSymbol(forSpace: currentSpace, display: currentDisplayID, store: store)
    }

    var currentColors: SpaceColors? {
        SpacePreferences.colors(forSpace: currentSpace, display: currentDisplayID, store: store)
    }

    var currentFont: NSFont? {
        SpacePreferences.font(forSpace: currentSpace, display: currentDisplayID, store: store)?.font
    }

    func getAllSpaceIndices() -> [Int] {
        guard !allSpaceLabels.isEmpty else {
            return []
        }
        return Array(1 ... allSpaceLabels.count)
    }

    // MARK: - Icon Generation

    var showAllSpaces: Bool {
        store.showAllSpaces
    }

    var showAllDisplays: Bool {
        store.showAllDisplays
    }

    var statusBarIcon: NSImage {
        // Check current appearance directly each time
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Show all displays mode takes precedence (shows spaces from all displays with separators)
        if showAllDisplays, !allDisplaysSpaceInfo.isEmpty {
            return generateCrossDisplayIcon(darkMode: isDark)
        }

        // Show all spaces mode (shows all spaces from current display only)
        if showAllSpaces, !allSpaceLabels.isEmpty {
            return generateCombinedIcon(darkMode: isDark)
        }

        return generateSingleIcon(for: currentSpace, label: currentSpaceLabel, darkMode: isDark)
    }

    /// Returns the layout of visible icons in the status bar for the current mode
    func visibleIconSlots() -> [StatusBarIconSlot] {
        if showAllDisplays {
            let spacesPerDisplay = spacesToShowAcrossDisplays()
            guard !spacesPerDisplay.isEmpty else {
                return []
            }

            var slots: [StatusBarIconSlot] = []
            var xOffset: Double = 0
            var shortcutNum = 0

            for (displayIndex, displaySpaces) in spacesPerDisplay.enumerated() {
                if displayIndex > 0 {
                    xOffset += Layout.displaySeparatorWidth
                }

                for space in displaySpaces {
                    let isFullscreen = space.label == Labels.fullscreen
                    if !isFullscreen {
                        shortcutNum += 1
                    }
                    let target = isFullscreen ? nil : shortcutNum
                    slots.append(StatusBarIconSlot(
                        startX: xOffset,
                        width: Layout.statusItemWidth,
                        label: space.label,
                        targetSpace: target
                    ))
                    xOffset += Layout.statusItemWidth
                }
            }

            return slots
        }

        if showAllSpaces {
            let spacesToShow = spacesToShowForCurrentDisplay()
            guard !spacesToShow.isEmpty else {
                return []
            }

            // Count only non-fullscreen spaces to get keyboard shortcut numbers
            var shortcutNum = 0
            var slots: [StatusBarIconSlot] = []

            for (drawIndex, spaceInfo) in spacesToShow.enumerated() {
                let isFullscreen = spaceInfo.label == Labels.fullscreen
                if !isFullscreen {
                    shortcutNum += 1
                }
                let target = isFullscreen ? nil : shortcutNum
                slots.append(StatusBarIconSlot(
                    startX: Double(drawIndex) * Layout.statusItemWidth,
                    width: Layout.statusItemWidth,
                    label: spaceInfo.label,
                    targetSpace: target
                ))
            }
            return slots
        }

        return []
    }

    private func generateSingleIcon(for space: Int, label: String, darkMode: Bool) -> NSImage {
        let colors = SpacePreferences.colors(forSpace: space, display: currentDisplayID, store: store)
        let style = SpacePreferences.iconStyle(forSpace: space, display: currentDisplayID, store: store) ?? .square
        let font = SpacePreferences.font(forSpace: space, display: currentDisplayID, store: store)?.font

        // Fullscreen spaces just show "F" with the same colors
        if label == Labels.fullscreen {
            return SpaceIconGenerator.generateIcon(
                for: Labels.fullscreen,
                darkMode: darkMode,
                customColors: colors,
                customFont: font,
                style: style
            )
        }

        let symbol = SpacePreferences.sfSymbol(forSpace: space, display: currentDisplayID, store: store)

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
            customFont: font,
            style: style
        )
    }

    /// Returns cached spaces with windows, refreshing if cache is stale or space IDs changed
    private func getCachedSpacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int> {
        let now = Date()
        let cacheValid = cachedSpacesWithWindowsSpaceIDs == spaceIDs &&
            now.timeIntervalSince(cachedSpacesWithWindowsTime) < Self.spacesWithWindowsCacheTTL

        if !cacheValid {
            cachedSpacesWithWindows = displaySpaceProvider.spacesWithWindows(forSpaceIDs: spaceIDs)
            cachedSpacesWithWindowsTime = now
            cachedSpacesWithWindowsSpaceIDs = spaceIDs
        }
        return cachedSpacesWithWindows
    }

    /// Invalidates the spacesWithWindows cache (call on space change)
    private func invalidateSpacesWithWindowsCache() {
        cachedSpacesWithWindowsTime = .distantPast
        cachedSpacesWithWindowsSpaceIDs = []
    }

    /// Determines if a space should be shown based on filtering settings
    private func shouldShowSpace(label: String, spaceID: Int, nonEmptySpaceIDs: Set<Int>) -> Bool {
        // Hide full-screen applications if enabled
        if store.hideFullscreenApps, label == Labels.fullscreen {
            return false
        }
        // Hide empty spaces if enabled
        if store.hideEmptySpaces, !nonEmptySpaceIDs.contains(spaceID) {
            return false
        }
        return true
    }

    private func spacesToShowForCurrentDisplay() -> [(index: Int, label: String)] {
        let needsFiltering = store.hideEmptySpaces || store.hideFullscreenApps
        if needsFiltering {
            let nonEmptySpaceIDs: Set<Int>
            if store.hideEmptySpaces {
                nonEmptySpaceIDs = getCachedSpacesWithWindows(forSpaceIDs: allSpaceIDs)
            } else {
                nonEmptySpaceIDs = []
            }

            let filtered = allSpaceLabels.enumerated().filter { index, label in
                let spaceID = allSpaceIDs[index]
                let spaceIndex = index + 1
                let isActive = spaceIndex == currentSpace

                // Always show active space
                if isActive {
                    return true
                }

                return shouldShowSpace(label: label, spaceID: spaceID, nonEmptySpaceIDs: nonEmptySpaceIDs)
            }
            return filtered.map { (index: $0.offset, label: $0.element) }
        }

        return allSpaceLabels.enumerated().map { (index: $0.offset, label: $0.element) }
    }

    private func spacesToShowAcrossDisplays() -> [[CrossDisplaySpace]] {
        // Collect all space IDs for window detection
        let allSpaceIDsAcrossDisplays = allDisplaysSpaceInfo.flatMap(\.spaceIDs)
        let nonEmptySpaceIDs: Set<Int>
        if store.hideEmptySpaces {
            nonEmptySpaceIDs = getCachedSpacesWithWindows(forSpaceIDs: allSpaceIDsAcrossDisplays)
        } else {
            nonEmptySpaceIDs = []
        }

        var spacesPerDisplay: [[CrossDisplaySpace]] = []

        for displayInfo in allDisplaysSpaceInfo {
            var displaySpaces: [CrossDisplaySpace] = []

            for (arrayIndex, label) in displayInfo.labels.enumerated() {
                let localIndex = arrayIndex + 1
                let globalIndex = displayInfo.globalStartIndex + arrayIndex
                let spaceID = displayInfo.spaceIDs[arrayIndex]
                let isActive = globalIndex == currentGlobalSpaceIndex

                // Always show active space
                guard isActive || shouldShowSpace(label: label, spaceID: spaceID, nonEmptySpaceIDs: nonEmptySpaceIDs)
                else {
                    continue
                }

                displaySpaces.append(CrossDisplaySpace(
                    displayID: displayInfo.displayID,
                    localIndex: localIndex,
                    globalIndex: globalIndex,
                    label: label,
                    spaceID: spaceID,
                    isActive: isActive
                ))
            }

            if !displaySpaces.isEmpty {
                spacesPerDisplay.append(displaySpaces)
            }
        }

        return spacesPerDisplay
    }

    private func generateCombinedIcon(darkMode: Bool) -> NSImage {
        let spacesToShow = spacesToShowForCurrentDisplay()

        // If no spaces to show, show just the current space
        guard !spacesToShow.isEmpty else {
            return generateSingleIcon(for: currentSpace, label: currentSpaceLabel, darkMode: darkMode)
        }

        let totalWidth = Double(spacesToShow.count) * Layout.statusItemWidth
        let combinedImage = NSImage(size: NSSize(width: totalWidth, height: Layout.statusItemHeight))

        combinedImage.lockFocus()

        for (drawIndex, spaceInfo) in spacesToShow.enumerated() {
            let spaceIndex = spaceInfo.index + 1
            let isActive = spaceIndex == currentSpace
            let icon = generateSingleIcon(for: spaceIndex, label: spaceInfo.label, darkMode: darkMode)

            let xOffset = Double(drawIndex) * Layout.statusItemWidth
            let drawRect = NSRect(
                x: xOffset,
                y: 0,
                width: Layout.statusItemWidth,
                height: Layout.statusItemHeight
            )

            // Draw with reduced opacity for inactive spaces (if dimming is enabled)
            let alpha = isActive || !store.dimInactiveSpaces ? 1.0 : 0.35
            icon.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: alpha)
        }

        combinedImage.unlockFocus()
        return combinedImage
    }

    // Generates an icon showing all spaces across all displays with separators between displays
    // swiftlint:disable:next function_body_length
    private func generateCrossDisplayIcon(darkMode: Bool) -> NSImage {
        let spacesPerDisplay = spacesToShowAcrossDisplays()

        // If no spaces to show at all, return single icon
        guard !spacesPerDisplay.isEmpty else {
            return generateSingleIcon(for: currentSpace, label: currentSpaceLabel, darkMode: darkMode)
        }

        // Calculate total width: spaces + separators between displays
        let totalSpaces = spacesPerDisplay.reduce(0) { $0 + $1.count }
        let separatorCount = max(0, spacesPerDisplay.count - 1)
        let totalWidth = Double(totalSpaces) * Layout.statusItemWidth +
            Double(separatorCount) * Layout.displaySeparatorWidth

        let combinedImage = NSImage(size: NSSize(width: totalWidth, height: Layout.statusItemHeight))

        combinedImage.lockFocus()

        var xOffset: Double = 0

        for (displayIndex, displaySpaces) in spacesPerDisplay.enumerated() {
            // Draw separator before this display (except for the first)
            if displayIndex > 0 {
                drawDisplaySeparator(at: xOffset, darkMode: darkMode)
                xOffset += Layout.displaySeparatorWidth
            }

            // Draw each space for this display
            for space in displaySpaces {
                // Use global index for the label when in cross-display mode
                let globalLabel = space.label == Labels.fullscreen ? Labels.fullscreen : String(space.globalIndex)
                let icon = generateSingleIconForCrossDisplay(
                    globalIndex: space.globalIndex,
                    label: globalLabel,
                    displayID: space.displayID,
                    localIndex: space.localIndex,
                    darkMode: darkMode
                )

                let drawRect = NSRect(
                    x: xOffset,
                    y: 0,
                    width: Layout.statusItemWidth,
                    height: Layout.statusItemHeight
                )

                // Draw with reduced opacity for inactive spaces (if dimming is enabled)
                let alpha = space.isActive || !store.dimInactiveSpaces ? 1.0 : 0.35
                icon.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: alpha)

                xOffset += Layout.statusItemWidth
            }
        }

        combinedImage.unlockFocus()
        return combinedImage
    }

    /// Generates a single icon for cross-display mode, looking up preferences by display and local index
    private func generateSingleIconForCrossDisplay(
        globalIndex _: Int,
        label: String,
        displayID: String,
        localIndex: Int,
        darkMode: Bool
    ) -> NSImage {
        // Look up colors, style, and font using local index and display ID (for per-display customization)
        let colors = SpacePreferences.colors(forSpace: localIndex, display: displayID, store: store)
        let style = SpacePreferences.iconStyle(forSpace: localIndex, display: displayID, store: store) ?? .square
        let font = SpacePreferences.font(forSpace: localIndex, display: displayID, store: store)?.font

        // Fullscreen spaces just show "F" with the same colors
        if label == Labels.fullscreen {
            return SpaceIconGenerator.generateIcon(
                for: Labels.fullscreen,
                darkMode: darkMode,
                customColors: colors,
                customFont: font,
                style: style
            )
        }

        let symbol = SpacePreferences.sfSymbol(forSpace: localIndex, display: displayID, store: store)

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
            customFont: font,
            style: style
        )
    }

    /// Draws a vertical separator line between displays
    private func drawDisplaySeparator(at xOffset: Double, darkMode: Bool) {
        let separatorColor = store.separatorColor ?? (darkMode
            ? NSColor(calibratedWhite: 0.5, alpha: 0.6)
            : NSColor(calibratedWhite: 0.4, alpha: 0.6))
        separatorColor.setStroke()

        let centerX = xOffset + Layout.displaySeparatorWidth / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centerX, y: 3))
        path.line(to: NSPoint(x: centerX, y: Layout.statusItemHeight - 3))
        path.lineWidth = 1.0
        path.stroke()
    }
}
