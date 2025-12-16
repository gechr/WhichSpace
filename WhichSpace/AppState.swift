import Cocoa
import Defaults
import os.log

// MARK: - Display Space Provider Protocol

/// Protocol for abstracting CGS display space functions for testability
protocol DisplaySpaceProvider {
    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]?
    func copyActiveMenuBarDisplayIdentifier() -> String?
    func spacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int>
}

/// Default implementation using the actual CGS/SLS functions
struct CGSDisplaySpaceProvider: DisplaySpaceProvider {
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

        // Collect all qualifying window IDs
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
    /// Local regular-space index for each entry (nil for fullscreen entries)
    let regularIndices: [Int?]
    /// Count of regular (non-fullscreen) spaces on this display
    let regularSpaceCount: Int
    /// The global starting index for this display's spaces (1-based)
    var globalStartIndex = 1

    init(
        displayID: String,
        labels: [String],
        spaceIDs: [Int],
        globalStartIndex: Int = 1,
        regularIndices: [Int?] = [],
        regularSpaceCount: Int? = nil
    ) {
        self.displayID = displayID
        self.labels = labels
        self.spaceIDs = spaceIDs
        let computedRegularIndices: [Int?]
        if !regularIndices.isEmpty {
            computedRegularIndices = regularIndices
        } else {
            var count = 0
            computedRegularIndices = labels.map {
                if $0 == Labels.fullscreen {
                    return nil
                }
                count += 1
                return count
            }
        }
        self.regularIndices = computedRegularIndices
        self.regularSpaceCount = regularSpaceCount ?? computedRegularIndices.compactMap(\.self).count
        self.globalStartIndex = globalStartIndex
    }
}

// MARK: - Space Change Notification

extension Notification.Name {
    /// Posted when the active space changes. The notification object is the AppState instance.
    static let spaceDidChange = Notification.Name("io.gechr.WhichSpace.spaceDidChange")
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

    private static let debounceInterval: Duration = .milliseconds(50)
    private static let logger = Logger(subsystem: "io.gechr.WhichSpace", category: "AppState")
    private static let spacesWithWindowsCacheTTL: TimeInterval = 0.2

    /// Space info for all displays (used when showAllDisplays is enabled)
    private(set) var allDisplaysSpaceInfo: [DisplaySpaceInfo] = []
    private(set) var allSpaceIDs: [Int] = []
    private(set) var allSpaceLabels: [String] = []
    private(set) var currentDisplayID: String?
    /// The global space index of the current space across all displays (1-based)
    private(set) var currentGlobalSpaceIndex = 0
    private(set) var currentSpace = 0
    private(set) var currentSpaceID = 0
    private(set) var currentSpaceLabel = "?"
    private(set) var darkModeEnabled = false

    private let displaySpaceProvider: DisplaySpaceProvider
    private let mainDisplay = "Main"
    private let spacesMonitorFile = "~/Library/Preferences/com.apple.spaces.plist"

    let store: DefaultsStore

    private var cachedSpacesWithWindows: Set<Int> = []
    private var cachedSpacesWithWindowsSpaceIDs: [Int] = []
    private var cachedSpacesWithWindowsTime: Date = .distantPast
    private var lastUpdateTime: Date = .distantPast
    private var mouseEventMonitor: Any?
    private var pendingUpdateTask: Task<Void, Never>?
    private var spacesMonitor: DispatchSourceFileSystemObject?

    private init() {
        displaySpaceProvider = CGSDisplaySpaceProvider()
        store = .shared
        updateDarkModeStatus()
        configureObservers()
        configureSpaceMonitor()
        performSpaceUpdate()
    }

    /// Internal initializer for testing with a custom display space provider
    init(displaySpaceProvider: DisplaySpaceProvider, skipObservers: Bool = false, store: DefaultsStore = .shared) {
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
        if let allDisplays {
            allDisplaysSpaceInfo = allDisplays.map {
                DisplaySpaceInfo(
                    displayID: $0.displayID,
                    labels: $0.labels,
                    spaceIDs: $0.spaceIDs,
                    globalStartIndex: $0.globalStartIndex
                )
            }
        } else if let displayID {
            let info = DisplaySpaceInfo(displayID: displayID, labels: labels, spaceIDs: allSpaceIDs)
            allDisplaysSpaceInfo = [info]
        } else {
            allDisplaysSpaceInfo = []
        }
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

        // Display configuration changes (connect/disconnect/rearrange)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDisplayConfigurationChange),
            name: NSApplication.didChangeScreenParametersNotification,
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

        // Save previous values for space change detection
        let oldSpace = currentSpace
        let oldDisplayID = currentDisplayID

        guard let displays = displaySpaceProvider.copyManagedDisplaySpaces(),
              let activeDisplay = displaySpaceProvider.copyActiveMenuBarDisplayIdentifier()
        else {
            return
        }

        // Collect space info from ALL displays
        var allDisplays: [DisplaySpaceInfo] = []
        var foundActiveDisplay = false

        // First pass: find the active space ID from the active display
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let displayID = display["Display Identifier"] as? String
            else {
                continue
            }
            if displayID == mainDisplay || displayID == activeDisplay {
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
                    spaceIDs: spaceIDs,
                    regularSpaceCount: regularSpaceIndex
                ))
            }
        }

        // Calculate global start indices
        var globalIndex = 1
        for index in 0 ..< allDisplays.count {
            allDisplays[index].globalStartIndex = globalIndex
            globalIndex += allDisplays[index].regularSpaceCount
        }

        allDisplaysSpaceInfo = allDisplays

        // Now find the active display and set current space info
        // Prefer activeDisplay, only fall back to mainDisplay if activeDisplay not found
        let targetDisplayID = allDisplays.contains { $0.displayID == activeDisplay }
            ? activeDisplay
            : mainDisplay

        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let spaces = display["Spaces"] as? [[String: Any]],
                  let displayID = display["Display Identifier"] as? String
            else {
                continue
            }

            guard displayID == targetDisplayID else {
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
                    currentSpaceID = spaceID
                    currentDisplayID = displayID
                    lastUpdateTime = Date()
                    foundActiveDisplay = true

                    // Calculate global space index
                    if let displayInfo = allDisplays.first(where: { $0.displayID == displayID }) {
                        let regularPosition = max(regularSpaceIndex, 1)
                        if isFullscreen {
                            currentGlobalSpaceIndex = displayInfo.globalStartIndex + max(regularPosition - 1, 0)
                        } else {
                            currentGlobalSpaceIndex = displayInfo.globalStartIndex + regularPosition - 1
                        }
                    } else {
                        currentGlobalSpaceIndex = activeIndex
                    }

                    // Use local or global numbering based on preference
                    if !isFullscreen, !store.localSpaceNumbers {
                        currentSpaceLabel = String(currentGlobalSpaceIndex)
                    } else {
                        currentSpaceLabel = label
                    }
                }
            }

            allSpaceLabels = spaceLabels
            allSpaceIDs = spaceIDs

            if foundActiveDisplay {
                postSpaceChangeNotificationIfNeeded(oldSpace: oldSpace, oldDisplayID: oldDisplayID)
                return
            }
        }

        currentSpace = 0
        currentSpaceID = 0
        currentSpaceLabel = "?"
        currentDisplayID = nil
        currentGlobalSpaceIndex = 0
        allSpaceLabels = []
        allSpaceIDs = []
        allDisplaysSpaceInfo = []
    }

    /// Posts spaceDidChange notification if the space actually changed
    private func postSpaceChangeNotificationIfNeeded(oldSpace: Int, oldDisplayID: String?) {
        // Only notify if space or display actually changed
        let spaceChanged = currentSpace != oldSpace || currentDisplayID != oldDisplayID

        // Skip on initial launch (oldSpace == 0 means no previous space)
        guard spaceChanged, oldSpace != 0 else {
            return
        }

        NotificationCenter.default.post(name: .spaceDidChange, object: self)
    }

    @objc func updateDarkModeStatus() {
        let appearance = NSApp.effectiveAppearance
        darkModeEnabled = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    @objc private func handleDisplayConfigurationChange() {
        updateActiveSpaceNumber()
    }

    // MARK: - Helpers

    var currentIconStyle: IconStyle {
        SpacePreferences.iconStyle(forSpace: currentSpace, display: currentDisplayID, store: store) ?? .square
    }

    var currentSymbol: String? {
        SpacePreferences.symbol(forSpace: currentSpace, display: currentDisplayID, store: store)
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

    // MARK: - Preview Overrides

    /// Temporary overrides for previewing style changes (only applied to current space)
    /// Marked as @ObservationIgnored so setting them doesn't trigger icon regeneration
    @ObservationIgnored private var previewBackground: NSColor?
    @ObservationIgnored private var previewClearSymbol = false
    @ObservationIgnored private var previewForeground: NSColor?
    @ObservationIgnored private var previewSeparatorColor: NSColor?
    @ObservationIgnored private var previewSkinTone: SkinTone?
    @ObservationIgnored private var previewStyle: IconStyle?
    @ObservationIgnored private var previewSymbol: String?

    /// Sets preview overrides and returns the full status bar icon with previewed changes
    func generatePreviewIcon(
        overrideStyle: IconStyle? = nil,
        overrideSymbol: String? = nil,
        overrideForeground: NSColor? = nil,
        overrideBackground: NSColor? = nil,
        overrideSeparatorColor: NSColor? = nil,
        clearSymbol: Bool = false,
        skinTone: SkinTone? = nil
    ) -> NSImage {
        // Store overrides temporarily
        previewStyle = overrideStyle
        previewSymbol = overrideSymbol
        previewForeground = overrideForeground
        previewBackground = overrideBackground
        previewSeparatorColor = overrideSeparatorColor
        previewClearSymbol = clearSymbol
        previewSkinTone = skinTone

        // Generate the full status bar icon (which will use overrides for current space)
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let result: NSImage
        if showAllDisplays, !allDisplaysSpaceInfo.isEmpty {
            result = generateCrossDisplayIcon(darkMode: isDark)
        } else if showAllSpaces, !allSpaceLabels.isEmpty {
            result = generateCombinedIcon(darkMode: isDark)
        } else {
            result = generateSingleIcon(for: currentSpace, label: currentSpaceLabel, darkMode: isDark)
        }

        // Clear overrides
        previewStyle = nil
        previewSymbol = nil
        previewForeground = nil
        previewBackground = nil
        previewSeparatorColor = nil
        previewClearSymbol = false
        previewSkinTone = nil

        return result
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
                    let displayLabel = isFullscreen ? space.label :
                        (store.localSpaceNumbers ? space.label : String(space.globalIndex))
                    slots.append(StatusBarIconSlot(
                        startX: xOffset,
                        width: Layout.statusItemWidth,
                        label: displayLabel,
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

            // Get global start index for current display
            let globalStartIndex = allDisplaysSpaceInfo
                .first { $0.displayID == currentDisplayID }?.globalStartIndex ?? 1

            // Count only non-fullscreen spaces to get keyboard shortcut numbers
            var shortcutNum = 0
            var slots: [StatusBarIconSlot] = []

            for (drawIndex, spaceInfo) in spacesToShow.enumerated() {
                let isFullscreen = spaceInfo.label == Labels.fullscreen
                if !isFullscreen {
                    shortcutNum += 1
                }
                let target = isFullscreen ? nil : shortcutNum
                let localRegularIndex = allDisplaysSpaceInfo
                    .first { $0.displayID == currentDisplayID }?
                    .regularIndices[spaceInfo.index] ?? 0
                let globalIndex = globalStartIndex + max(localRegularIndex - 1, 0)
                let displayLabel = isFullscreen ? spaceInfo.label :
                    (store.localSpaceNumbers ? spaceInfo.label : String(globalIndex))
                slots.append(StatusBarIconSlot(
                    startX: Double(drawIndex) * Layout.statusItemWidth,
                    width: Layout.statusItemWidth,
                    label: displayLabel,
                    targetSpace: target
                ))
            }
            return slots
        }

        return []
    }

    private func generateSingleIcon(for space: Int, label: String, darkMode: Bool) -> NSImage {
        let isCurrentSpace = space == currentSpace
        var colors = SpacePreferences.colors(forSpace: space, display: currentDisplayID, store: store)
        var style = SpacePreferences.iconStyle(forSpace: space, display: currentDisplayID, store: store) ?? .square
        let font = SpacePreferences.font(forSpace: space, display: currentDisplayID, store: store)?.font

        // Apply preview overrides for current space
        if isCurrentSpace {
            if let previewStyle {
                style = previewStyle
            }
            let defaults = IconColors.filledColors(darkMode: darkMode)
            if let fg = previewForeground {
                let bg = colors?.background ?? defaults.background
                colors = SpaceColors(foreground: fg, background: bg)
            }
            if let bg = previewBackground {
                let fg = colors?.foreground ?? defaults.foreground
                colors = SpaceColors(foreground: fg, background: bg)
            }
        }

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

        // Check for preview symbol override first (current space only)
        if isCurrentSpace, let previewSymbol {
            let skinTone = previewSkinTone
                ?? SpacePreferences.skinTone(forSpace: space, display: currentDisplayID, store: store)
                ?? .default
            return SpaceIconGenerator.generateSymbolIcon(
                symbolName: previewSymbol,
                darkMode: darkMode,
                customColors: colors,
                skinTone: skinTone
            )
        }

        // Skip saved symbol if previewing a number style (previewClearSymbol)
        let symbol = (isCurrentSpace && previewClearSymbol)
            ? nil
            : SpacePreferences.symbol(forSpace: space, display: currentDisplayID, store: store)

        if let symbol {
            // Use per-space skin tone, defaulting to yellow  (rather than the global emoji picker preference)
            let skinTone = SpacePreferences
                .skinTone(forSpace: space, display: currentDisplayID, store: store) ?? .default
            return SpaceIconGenerator.generateSymbolIcon(
                symbolName: symbol,
                darkMode: darkMode,
                customColors: colors,
                skinTone: skinTone
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
                let localRegularIndex = displayInfo.regularIndices[arrayIndex] ?? 0
                let globalIndex = displayInfo.globalStartIndex + max(localRegularIndex - 1, 0)
                let spaceID = displayInfo.spaceIDs[arrayIndex]
                let isActive = spaceID == currentSpaceID

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

        // Get global start index for current display
        let globalStartIndex = allDisplaysSpaceInfo
            .first { $0.displayID == currentDisplayID }?.globalStartIndex ?? 1

        let totalWidth = Double(spacesToShow.count) * Layout.statusItemWidth
        let combinedImage = NSImage(size: NSSize(width: totalWidth, height: Layout.statusItemHeight))

        combinedImage.lockFocus()

        for (drawIndex, spaceInfo) in spacesToShow.enumerated() {
            let spaceIndex = spaceInfo.index + 1
            let isActive = spaceIndex == currentSpace
            let isFullscreen = spaceInfo.label == Labels.fullscreen
            let localRegularIndex = allDisplaysSpaceInfo
                .first { $0.displayID == currentDisplayID }?
                .regularIndices[spaceInfo.index] ?? 0
            let globalIndex = globalStartIndex + max(localRegularIndex - 1, 0)
            let displayLabel = isFullscreen ? spaceInfo.label :
                (store.localSpaceNumbers ? spaceInfo.label : String(globalIndex))
            let icon = generateSingleIcon(for: spaceIndex, label: displayLabel, darkMode: darkMode)

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
                let displayLabel: String
                if space.label == Labels.fullscreen {
                    displayLabel = Labels.fullscreen
                } else if !store.localSpaceNumbers {
                    displayLabel = String(space.globalIndex)
                } else {
                    displayLabel = space.label
                }
                let icon = generateSingleIconForCrossDisplay(
                    globalIndex: space.globalIndex,
                    label: displayLabel,
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
        // Check if this is the current space (same display and same local index)
        let isCurrentSpace = displayID == currentDisplayID && localIndex == currentSpace

        // When uniqueIconsPerDisplay is OFF, preview should apply to all spaces with same local index
        // (since they share settings). When ON, only apply to the exact current space.
        let shouldApplyPreview = localIndex == currentSpace
            && (displayID == currentDisplayID || !store.uniqueIconsPerDisplay)

        // Look up colors, style, and font using local index and display ID (for per-display customization)
        var colors = SpacePreferences.colors(forSpace: localIndex, display: displayID, store: store)
        var style = SpacePreferences.iconStyle(forSpace: localIndex, display: displayID, store: store) ?? .square
        let font = SpacePreferences.font(forSpace: localIndex, display: displayID, store: store)?.font

        // Apply preview overrides for affected spaces
        if shouldApplyPreview {
            if let previewStyle {
                style = previewStyle
            }
            let defaults = IconColors.filledColors(darkMode: darkMode)
            if let fg = previewForeground {
                let bg = colors?.background ?? defaults.background
                colors = SpaceColors(foreground: fg, background: bg)
            }
            if let bg = previewBackground {
                let fg = colors?.foreground ?? defaults.foreground
                colors = SpaceColors(foreground: fg, background: bg)
            }
        }

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

        // Check for preview symbol override first
        if shouldApplyPreview, let previewSymbol {
            let skinTone = previewSkinTone
                ?? SpacePreferences.skinTone(forSpace: localIndex, display: displayID, store: store)
                ?? .default
            return SpaceIconGenerator.generateSymbolIcon(
                symbolName: previewSymbol,
                darkMode: darkMode,
                customColors: colors,
                skinTone: skinTone
            )
        }

        // Skip saved symbol if previewing a number style (previewClearSymbol)
        let symbol = (shouldApplyPreview && previewClearSymbol)
            ? nil
            : SpacePreferences.symbol(forSpace: localIndex, display: displayID, store: store)

        if let symbol {
            // Use per-space skin tone, defaulting to yellow  (rather than the global emoji picker preference)
            let skinTone = SpacePreferences.skinTone(forSpace: localIndex, display: displayID, store: store) ?? .default
            return SpaceIconGenerator.generateSymbolIcon(
                symbolName: symbol,
                darkMode: darkMode,
                customColors: colors,
                skinTone: skinTone
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
        let separatorColor = previewSeparatorColor ?? store.separatorColor ?? (darkMode
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
