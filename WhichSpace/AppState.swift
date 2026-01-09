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

// MARK: - Space Snapshot

/// Immutable snapshot of the current system space state, emitted by SpaceMonitor
struct SpaceSnapshot: Equatable {
    let allDisplaysSpaceInfo: [DisplaySpaceInfo]
    let allSpaceIDs: [Int]
    let allSpaceLabels: [String]
    let currentDisplayID: String?
    let currentGlobalSpaceIndex: Int
    let currentSpace: Int
    let currentSpaceID: Int
    let currentSpaceLabel: String

    static let empty = Self(
        allDisplaysSpaceInfo: [],
        allSpaceIDs: [],
        allSpaceLabels: [],
        currentDisplayID: nil,
        currentGlobalSpaceIndex: 0,
        currentSpace: 0,
        currentSpaceID: 0,
        currentSpaceLabel: "?"
    )
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

/// Layout of status bar icons with hit testing support
struct StatusBarLayout: Equatable {
    let slots: [StatusBarIconSlot]

    /// Returns the slot at the given x coordinate, or nil if none
    func slot(at x: Double) -> StatusBarIconSlot? {
        slots.first { slot in
            x >= slot.startX && x <= slot.startX + slot.width
        }
    }

    /// Returns the target space number at the given x coordinate, or nil if none or not switchable
    func targetSpace(at x: Double) -> Int? {
        slot(at: x)?.targetSpace
    }

    /// Total width of all slots
    var totalWidth: Double {
        guard let last = slots.last else {
            return 0
        }
        return last.startX + last.width
    }

    static let empty = Self(slots: [])
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

    /// Total count of regular (non-fullscreen) spaces across all displays
    var regularSpaceCount: Int {
        allDisplaysSpaceInfo.reduce(0) { $0 + $1.regularSpaceCount }
    }

    private let displaySpaceProvider: DisplaySpaceProvider
    private let mainDisplay = "Main"

    let store: DefaultsStore

    private var cachedSpacesWithWindows: Set<Int> = []
    private var cachedSpacesWithWindowsSpaceIDs: [Int] = []
    private var cachedSpacesWithWindowsTime: Date = .distantPast
    private var lastUpdateTime: Date = .distantPast
    private var mouseEventMonitor: Any?
    private var notificationTasks: [Task<Void, Never>] = []
    private var pendingUpdateTask: Task<Void, Never>?
    private var spaceMonitor: SpaceMonitor?
    private var spaceMonitorTask: Task<Void, Never>?

    private init() {
        displaySpaceProvider = CGSDisplaySpaceProvider()
        store = .shared
        updateDarkModeStatus()
        configureObservers()
        startSpaceMonitor()
        applySnapshot(buildSnapshot())
    }

    /// Internal initializer for testing with a custom display space provider
    init(displaySpaceProvider: DisplaySpaceProvider, skipObservers: Bool = false, store: DefaultsStore = .shared) {
        self.displaySpaceProvider = displaySpaceProvider
        self.store = store
        updateDarkModeStatus()
        if !skipObservers {
            configureObservers()
            startSpaceMonitor()
        }
        applySnapshot(buildSnapshot())
    }

    deinit {
        // Use assumeIsolated since AppState is MainActor-isolated and cleanup requires access
        MainActor.assumeIsolated {
            spaceMonitorTask?.cancel()
            pendingUpdateTask?.cancel()
            for task in notificationTasks {
                task.cancel()
            }
            if let monitor = mouseEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Test Helpers

    /// Forces an immediate space update without debounce
    func forceSpaceUpdate() {
        pendingUpdateTask?.cancel()
        pendingUpdateTask = nil
        applySnapshot(buildSnapshot())
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

        // Workspace notifications via async sequences
        notificationTasks.append(Task {
            for await _ in workspace.notificationCenter
                .notifications(named: NSWorkspace.activeSpaceDidChangeNotification)
            {
                updateActiveSpaceNumber()
            }
        })

        notificationTasks.append(Task {
            for await _ in workspace.notificationCenter
                .notifications(named: NSWorkspace.didActivateApplicationNotification)
            {
                updateActiveSpaceNumber()
            }
        })

        notificationTasks.append(Task {
            for await _ in NotificationCenter.default
                .notifications(named: NSApplication.didChangeScreenParametersNotification)
            {
                handleDisplayConfigurationChange()
            }
        })

        // Distributed notifications still use selector pattern (no async API)
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

    private func startSpaceMonitor() {
        spaceMonitorTask?.cancel()
        spaceMonitor = SpaceMonitor { [weak self] in
            await self?.buildSnapshot() ?? .empty
        }
        guard let spaceMonitor else {
            return
        }
        spaceMonitorTask = Task {
            for await snapshot in spaceMonitor.snapshots() {
                applySnapshot(snapshot)
            }
        }
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
            applySnapshot(buildSnapshot())
        }
    }

    /// Builds an immutable snapshot of the current space state from system data
    private func buildSnapshot() -> SpaceSnapshot {
        guard let displays = displaySpaceProvider.copyManagedDisplaySpaces(),
              let activeDisplay = displaySpaceProvider.copyActiveMenuBarDisplayIdentifier()
        else {
            return .empty
        }

        // Collect space info from ALL displays
        var allDisplays: [DisplaySpaceInfo] = []

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

        // Find the active display - prefer activeDisplay, fall back to mainDisplay
        let targetDisplayID = allDisplays.contains { $0.displayID == activeDisplay }
            ? activeDisplay
            : mainDisplay

        // Find current space info from the active display
        for display in displays {
            guard let current = display["Current Space"] as? [String: Any],
                  let spaces = display["Spaces"] as? [[String: Any]],
                  let displayID = display["Display Identifier"] as? String,
                  displayID == targetDisplayID,
                  let activeSpaceID = current["ManagedSpaceID"] as? Int
            else {
                continue
            }

            var regularSpaceIndex = 0
            var spaceLabels: [String] = []
            var spaceIDs: [Int] = []
            var snapshotCurrentSpace = 0
            var snapshotCurrentSpaceID = 0
            var snapshotCurrentSpaceLabel = "?"
            var snapshotGlobalSpaceIndex = 0

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
                    snapshotCurrentSpace = activeIndex
                    snapshotCurrentSpaceID = spaceID

                    // Calculate global space index
                    if let displayInfo = allDisplays.first(where: { $0.displayID == displayID }) {
                        let regularPosition = max(regularSpaceIndex, 1)
                        if isFullscreen {
                            snapshotGlobalSpaceIndex = displayInfo.globalStartIndex + max(regularPosition - 1, 0)
                        } else {
                            snapshotGlobalSpaceIndex = displayInfo.globalStartIndex + regularPosition - 1
                        }
                    } else {
                        snapshotGlobalSpaceIndex = activeIndex
                    }

                    // Use local or global numbering based on preference
                    if !isFullscreen, !store.localSpaceNumbers {
                        snapshotCurrentSpaceLabel = String(snapshotGlobalSpaceIndex)
                    } else {
                        snapshotCurrentSpaceLabel = label
                    }
                }
            }

            return SpaceSnapshot(
                allDisplaysSpaceInfo: allDisplays,
                allSpaceIDs: spaceIDs,
                allSpaceLabels: spaceLabels,
                currentDisplayID: displayID,
                currentGlobalSpaceIndex: snapshotGlobalSpaceIndex,
                currentSpace: snapshotCurrentSpace,
                currentSpaceID: snapshotCurrentSpaceID,
                currentSpaceLabel: snapshotCurrentSpaceLabel
            )
        }

        return .empty
    }

    /// Applies a space snapshot to update AppState properties
    private func applySnapshot(_ snapshot: SpaceSnapshot) {
        // Invalidate window cache on space change to get fresh window data
        invalidateSpacesWithWindowsCache()

        // Save previous values for space change detection
        let oldSpaceID = currentSpaceID
        let oldDisplayID = currentDisplayID

        // Apply snapshot to state
        allDisplaysSpaceInfo = snapshot.allDisplaysSpaceInfo
        allSpaceIDs = snapshot.allSpaceIDs
        allSpaceLabels = snapshot.allSpaceLabels
        currentDisplayID = snapshot.currentDisplayID
        currentGlobalSpaceIndex = snapshot.currentGlobalSpaceIndex
        currentSpace = snapshot.currentSpace
        currentSpaceID = snapshot.currentSpaceID
        currentSpaceLabel = snapshot.currentSpaceLabel
        lastUpdateTime = Date()

        // Post notification if space changed on the same display
        postSpaceChangeNotificationIfNeeded(oldSpaceID: oldSpaceID, oldDisplayID: oldDisplayID)
    }

    /// Posts spaceDidChange notification if the space changed on the same display
    private func postSpaceChangeNotificationIfNeeded(oldSpaceID: Int, oldDisplayID: String?) {
        // Only notify if space changed on the same display (not when switching displays)
        let spaceChanged = currentSpaceID != oldSpaceID
        let sameDisplay = currentDisplayID == oldDisplayID

        // Skip on initial launch (oldSpaceID == 0 means no previous space)
        guard spaceChanged, sameDisplay, oldSpaceID != 0 else {
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
    func statusBarLayout() -> StatusBarLayout {
        if showAllDisplays {
            let spacesPerDisplay = spacesToShowAcrossDisplays()
            guard !spacesPerDisplay.isEmpty else {
                return .empty
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

            return StatusBarLayout(slots: slots)
        }

        if showAllSpaces {
            let spacesToShow = spacesToShowForCurrentDisplay()
            guard !spacesToShow.isEmpty else {
                return .empty
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
            return StatusBarLayout(slots: slots)
        }

        return .empty
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
                style: style,
                sizeScale: store.sizeScale
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
                skinTone: skinTone,
                sizeScale: store.sizeScale
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
                skinTone: skinTone,
                sizeScale: store.sizeScale
            )
        }
        return SpaceIconGenerator.generateIcon(
            for: label,
            darkMode: darkMode,
            customColors: colors,
            customFont: font,
            style: style,
            sizeScale: store.sizeScale
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
                style: style,
                sizeScale: store.sizeScale
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
                skinTone: skinTone,
                sizeScale: store.sizeScale
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
                skinTone: skinTone,
                sizeScale: store.sizeScale
            )
        }
        return SpaceIconGenerator.generateIcon(
            for: label,
            darkMode: darkMode,
            customColors: colors,
            customFont: font,
            style: style,
            sizeScale: store.sizeScale
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
