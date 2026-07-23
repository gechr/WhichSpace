import Cocoa
import Defaults

/// A single space entry combining ID, label, and local regular index.
struct SpaceEntry: Equatable {
    let id: Int
    let label: String
    /// Local regular-space index (nil for fullscreen entries)
    let regularIndex: Int?
}

/// Information about spaces on a single display
struct DisplaySpaceInfo: Equatable {
    let displayID: String
    let entries: [SpaceEntry]
    /// The currently active Space on this display.
    let activeSpaceID: Int?
    /// Count of regular (non-fullscreen) spaces on this display
    let regularSpaceCount: Int
    /// The global starting index for this display's spaces (1-based)
    let globalStartIndex: Int

    init(
        displayID: String,
        entries: [SpaceEntry],
        activeSpaceID: Int? = nil,
        globalStartIndex: Int = 1,
        regularSpaceCount: Int? = nil
    ) {
        self.displayID = displayID
        self.entries = entries
        self.activeSpaceID = activeSpaceID
        self.globalStartIndex = globalStartIndex
        self.regularSpaceCount = regularSpaceCount ?? entries.compactMap(\.regularIndex).count
    }

    /// Convenience initializer from parallel arrays (used in tests and migration)
    init(
        displayID: String,
        labels: [String],
        spaceIDs: [Int],
        activeSpaceID: Int? = nil,
        globalStartIndex: Int = 1,
        spaceIndices: [Int?] = [],
        regularSpaceCount: Int? = nil
    ) {
        let computedRegularIndices: [Int?]
        if !spaceIndices.isEmpty {
            computedRegularIndices = spaceIndices
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
        let entries = zip(zip(spaceIDs, labels), computedRegularIndices).map { pair, regularIndex in
            SpaceEntry(id: pair.0, label: pair.1, regularIndex: regularIndex)
        }
        self.init(
            displayID: displayID,
            entries: entries,
            activeSpaceID: activeSpaceID,
            globalStartIndex: globalStartIndex,
            regularSpaceCount: regularSpaceCount ?? computedRegularIndices.compactMap(\.self).count
        )
    }
}

// MARK: - Space Snapshot

/// Immutable snapshot of the current system space state
struct SpaceSnapshot: Equatable {
    let allDisplaysSpaceInfo: [DisplaySpaceInfo]
    let allSpaceEntries: [SpaceEntry]
    let currentDisplayID: String?
    let currentGlobalSpaceIndex: Int
    let currentSpace: Int
    let currentSpaceID: Int
    let currentSpaceLabel: String

    static let empty = Self(
        allDisplaysSpaceInfo: [],
        allSpaceEntries: [],
        currentDisplayID: nil,
        currentGlobalSpaceIndex: 0,
        currentSpace: 0,
        currentSpaceID: 0,
        currentSpaceLabel: "?"
    )
}

// MARK: - Space Change Notification

extension Notification.Name {
    /// Posted when the Space changes without the active display changing.
    /// The notification object is the AppState instance.
    static let currentDisplaySpaceDidChange = Notification.Name("io.gechr.WhichSpace.currentDisplaySpaceDidChange")
}

/// Geometry for rendered status bar icons (used for hit testing)
struct StatusBarIconSlot: Equatable {
    let startX: Double
    let width: Double
    let label: String
    /// The numeric space to activate (nil for fullscreen apps - use spaceID instead)
    let targetSpace: Int?
    /// The CGS space ID (used to find apps on fullscreen spaces)
    let spaceID: Int
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
    private var snapshot: SpaceSnapshot = .empty
    private(set) var darkModeEnabled = false

    /// Space info for all displays (used when showAllDisplays is enabled)
    var allDisplaysSpaceInfo: [DisplaySpaceInfo] {
        snapshot.allDisplaysSpaceInfo
    }

    var allSpaceEntries: [SpaceEntry] {
        snapshot.allSpaceEntries
    }

    var currentDisplayID: String? {
        snapshot.currentDisplayID
    }

    /// The global space index of the current space across all displays (1-based)
    var currentGlobalSpaceIndex: Int {
        snapshot.currentGlobalSpaceIndex
    }

    var currentSpace: Int {
        snapshot.currentSpace
    }

    var currentSpaceID: Int {
        snapshot.currentSpaceID
    }

    var currentSpaceLabel: String {
        snapshot.currentSpaceLabel
    }

    var allSpaceLabels: [String] {
        allSpaceEntries.map(\.label)
    }

    var allSpaceIDs: [Int] {
        allSpaceEntries.map(\.id)
    }

    /// Total count of regular (non-fullscreen) spaces across all displays
    var regularSpaceCount: Int {
        allDisplaysSpaceInfo.reduce(0) { $0 + $1.regularSpaceCount }
    }

    private let displaySpaceProvider: DisplaySpaceProvider

    let store: DefaultsStore

    /// Lazily created to avoid referencing `self` before init completes
    @ObservationIgnored private(set) lazy var renderer: StatusBarRenderer = .init(
        appState: self,
        displaySpaceProvider: displaySpaceProvider,
        store: store
    )

    private var lastUpdateTime: Date = .distantPast
    private var mouseEventMonitor: Any?
    private var notificationTasks: [Task<Void, Never>] = []
    private var pendingClickUpdateTask: Task<Void, Never>?
    private var spaceMonitor: SpaceMonitor?
    private var spaceMonitorTask: Task<Void, Never>?
    private var spaceUpdateCoordinator: SpaceUpdateCoordinator?

    init(store: DefaultsStore) {
        displaySpaceProvider = CGSDisplaySpaceProvider()
        self.store = store
        configureSpaceUpdateCoordinator()
        updateDarkModeStatus()
        configureObservers()
        startSpaceMonitor()
        applySnapshot(buildSnapshot())
    }

    /// Internal initializer for testing with a custom display space provider
    init(displaySpaceProvider: DisplaySpaceProvider, skipObservers: Bool = false, store: DefaultsStore) {
        self.displaySpaceProvider = displaySpaceProvider
        self.store = store
        configureSpaceUpdateCoordinator()
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
            pendingClickUpdateTask?.cancel()
            spaceUpdateCoordinator?.cancel()
            for task in notificationTasks {
                task.cancel()
            }
            if let monitor = mouseEventMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    // MARK: - Test Helpers

    /// Forces an immediate space update without debounce
    func forceSpaceUpdate() {
        spaceUpdateCoordinator?.cancel()
        applySnapshot(buildSnapshot())
    }

    // Sets space labels and current space directly for testing the rendering path
    #if DEBUG
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
            let resolvedIDs = spaceIDs ?? Array(100 ..< 100 + labels.count)
            let resolvedDisplays: [DisplaySpaceInfo]
            if let allDisplays {
                resolvedDisplays = allDisplays
            } else if let displayID {
                let info = DisplaySpaceInfo(displayID: displayID, labels: labels, spaceIDs: resolvedIDs)
                resolvedDisplays = [info]
            } else {
                resolvedDisplays = []
            }
            // Derive entries from DisplaySpaceInfo when available so regularIndex is computed correctly
            let resolvedEntries: [SpaceEntry] = if let currentDisplayInfo = resolvedDisplays
                .first(where: { $0.displayID == displayID })
            {
                currentDisplayInfo.entries
            } else {
                zip(resolvedIDs, labels).map { SpaceEntry(id: $0, label: $1, regularIndex: nil) }
            }
            let currentEntryIndex = currentSpace - 1
            let currentSpaceID = resolvedEntries.indices.contains(currentEntryIndex)
                ? resolvedEntries[currentEntryIndex].id
                : 0
            snapshot = SpaceSnapshot(
                allDisplaysSpaceInfo: resolvedDisplays,
                allSpaceEntries: resolvedEntries,
                currentDisplayID: displayID,
                currentGlobalSpaceIndex: globalSpaceIndex ?? currentSpace,
                currentSpace: currentSpace,
                currentSpaceID: currentSpaceID,
                currentSpaceLabel: currentLabel
            )
        }
    #endif

    // MARK: - Observers

    private func configureObservers() {
        let workspace = NSWorkspace.shared

        // WindowServer push notifications - the lowest-latency space-change
        // signal (NSWorkspace's notification derives from the same events
        // but arrives later; the plist file watch waits on cfprefsd)
        SpaceChangeNotifier.start { [weak self] reason in
            self?.handleSpaceUpdate(reason)
        }

        // Workspace notifications via async sequences.
        // Weak captures keep these long-lived tasks from retaining AppState,
        // so deinit (which cancels them) stays reachable.
        notificationTasks.append(Task { [weak self] in
            for await _ in workspace.notificationCenter
                .notifications(named: NSWorkspace.activeSpaceDidChangeNotification)
            {
                self?.handleSpaceUpdate(.activeSpace)
            }
        })

        notificationTasks.append(Task { [weak self] in
            for await _ in workspace.notificationCenter
                .notifications(named: NSWorkspace.didActivateApplicationNotification)
            {
                self?.handleSpaceUpdate(.fallback)
            }
        })

        notificationTasks.append(Task { [weak self] in
            for await _ in NotificationCenter.default
                .notifications(named: NSApplication.didChangeScreenParametersNotification)
            {
                self?.handleSpaceUpdate(.topology)
            }
        })

        notificationTasks.append(Task { [weak self] in
            for await _ in workspace.notificationCenter
                .notifications(named: NSNotification.Name("NSWorkspaceActiveDisplayDidChangeNotification"))
            {
                self?.handleSpaceUpdate(.fallback)
            }
        })

        // Distributed notifications via AsyncStream (no native async API)
        notificationTasks.append(Task { [weak self] in
            for await _ in Self.distributedNotifications(named: "AppleInterfaceThemeChangedNotification") {
                self?.updateDarkModeStatus()
            }
        })

        let dismissalNames = [
            "com.apple.screenIsUnlocked",
            "com.apple.exposeworkspacesdidchange",
        ]
        for name in dismissalNames {
            notificationTasks.append(Task { [weak self] in
                for await _ in Self.distributedNotifications(named: name) {
                    self?.handleSpaceUpdate(.fallback)
                }
            })
        }

        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }
                // Replace any pending click-triggered refresh so rapid clicks debounce
                self.pendingClickUpdateTask?.cancel()
                self.pendingClickUpdateTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, Date().timeIntervalSince(self.lastUpdateTime) > 0.5 else {
                        return
                    }
                    self.handleSpaceUpdate(.fallback)
                }
            }
        }
    }

    // MARK: - Distributed Notification Helper

    private static func distributedNotifications(named name: String) -> AsyncStream<Void> {
        AsyncStream { continuation in
            nonisolated(unsafe) let observer = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(name), object: nil, queue: .main
            ) { _ in
                continuation.yield()
            }
            continuation.onTermination = { @Sendable _ in
                DistributedNotificationCenter.default().removeObserver(observer)
            }
        }
    }

    // MARK: - Space Monitor

    private func startSpaceMonitor() {
        spaceMonitorTask?.cancel()
        let monitor = SpaceMonitor()
        spaceMonitor = monitor
        spaceMonitorTask = Task { [weak self] in
            let changes = await monitor.changes()
            for await _ in changes {
                // Route the plist watcher through the coordinator so its
                // ticks coalesce with every other space-change signal
                self?.handleSpaceUpdate(.fallback)
            }
        }
    }

    // MARK: - Space Detection

    func handleSpaceUpdate(_ reason: SpaceUpdateReason) {
        spaceUpdateCoordinator?.handle(reason)
    }

    private func configureSpaceUpdateCoordinator() {
        spaceUpdateCoordinator = SpaceUpdateCoordinator(
            onSnapshotUpdate: { [weak self] in
                guard let self else {
                    return
                }
                applySnapshot(buildSnapshot())
            },
            onWindowOccupancyUpdate: { [weak self] in
                self?.renderer.refreshSpacesWithWindows()
            }
        )
    }

    /// Builds an immutable snapshot of the current space state from system data
    private func buildSnapshot() -> SpaceSnapshot {
        SpaceSnapshotService.buildSnapshot(
            provider: displaySpaceProvider,
            localSpaceNumbers: store.localSpaceNumbers
        )
    }

    /// Applies a space snapshot to update AppState properties
    private func applySnapshot(_ newSnapshot: SpaceSnapshot) {
        // A snapshot without a current space, taken while spaces are known,
        // is a transient artifact of display reconfiguration (the CGS reads
        // race the change) - keep the previous state rather than flashing
        // "?" and poisoning space-change detection
        if newSnapshot.currentSpaceID == 0, !snapshot.allSpaceEntries.isEmpty {
            return
        }
        // Skip no-op applies so notification bursts (e.g. every app
        // activation) don't invalidate caches or re-render the icon. Window
        // layout may still have changed, so refresh that data in the
        // background (affects hideEmptySpaces)
        guard newSnapshot != snapshot else {
            lastUpdateTime = Date()
            renderer.refreshSpacesWithWindows()
            return
        }

        // Save previous values for space change detection
        let oldDisplaysSpaceInfo = snapshot.allDisplaysSpaceInfo
        let oldSpaceID = snapshot.currentSpaceID
        let oldDisplayID = snapshot.currentDisplayID

        snapshot = newSnapshot
        lastUpdateTime = Date()
        renderer.spaceSnapshotDidChange()

        // Real CGS state for the active space has landed - stale switch
        // predictions are now wrong. Topology-only snapshot changes keep
        // predictions so mid-burst switches don't overshoot
        if newSnapshot.currentSpaceID != oldSpaceID {
            SpaceSwitcher.resetPredictions()
        }

        // Apply default style to newly created spaces
        applyDefaultStyleToNewSpaces(previousDisplays: oldDisplaysSpaceInfo)

        // Post notification if space changed on the same display
        postCurrentDisplaySpaceChangeIfNeeded(oldSpaceID: oldSpaceID, oldDisplayID: oldDisplayID)
    }

    /// When an existing display gains new regular spaces, apply the stored default style to each
    /// new local space index if it doesn't already have preferences set.
    private func applyDefaultStyleToNewSpaces(previousDisplays: [DisplaySpaceInfo]) {
        // Skip on initial launch or if no default style is saved.
        guard !previousDisplays.isEmpty, SpacePreferences.hasDefaultStyle(store: store) else {
            return
        }

        let previousCounts = Dictionary(
            uniqueKeysWithValues: previousDisplays.map { ($0.displayID, $0.regularSpaceCount) }
        )

        for displayInfo in allDisplaysSpaceInfo {
            guard let oldCount = previousCounts[displayInfo.displayID],
                  displayInfo.regularSpaceCount > oldCount
            else {
                continue
            }

            let display = store.uniqueIconsPerDisplay ? displayInfo.displayID : nil
            // Preferences are keyed by array index + 1 (fullscreen-inclusive), so derive
            // each new regular space's key from its position in the entries array
            for (arrayIndex, entry) in displayInfo.entries.enumerated() {
                guard let regularIndex = entry.regularIndex, regularIndex > oldCount else {
                    continue
                }
                let newSpace = arrayIndex + 1
                guard !SpacePreferences.hasAnyPreference(forSpace: newSpace, display: display, store: store) else {
                    continue
                }

                SpacePreferences.applyDefaultStyle(toSpace: newSpace, display: display, store: store)
            }
        }
    }

    /// Posts currentDisplaySpaceDidChange when the space changes on the same display
    private func postCurrentDisplaySpaceChangeIfNeeded(oldSpaceID: Int, oldDisplayID: String?) {
        // Only notify if space changed on the same display (not when switching displays)
        let spaceChanged = currentSpaceID != oldSpaceID
        let sameDisplay = currentDisplayID == oldDisplayID

        // Skip on initial launch (oldSpaceID == 0 means no previous space)
        guard spaceChanged, sameDisplay, oldSpaceID != 0 else {
            return
        }

        NotificationCenter.default.post(name: .currentDisplaySpaceDidChange, object: self)
    }

    func updateDarkModeStatus() {
        guard let app = NSApp
        else { return }
        let appearance = app.effectiveAppearance
        darkModeEnabled = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Helpers

    var currentBadge: SpaceBadge? {
        SpacePreferences.badge(forSpace: currentSpace, display: currentDisplayID, store: store)
    }

    var currentIconStyle: IconStyle {
        SpacePreferences.iconStyle(forSpace: currentSpace, display: currentDisplayID, store: store) ?? .square
    }

    var currentSymbol: String? {
        SpacePreferences.symbol(forSpace: currentSpace, display: currentDisplayID, store: store)
    }

    var currentColors: SpaceColors? {
        SpacePreferences.colors(forSpace: currentSpace, display: currentDisplayID, store: store)
    }

    var currentCombinedSymbolLayout: CombinedSymbolLayout? {
        guard let symbol = currentSymbol,
              !symbol.containsEmoji,
              let label = SpacePreferences.label(
                  forSpace: currentSpace,
                  display: currentDisplayID,
                  store: store
              ),
              !label.isEmpty
        else {
            return nil
        }
        let labelStyle = SpacePreferences.labelStyle(
            forSpace: currentSpace,
            display: currentDisplayID,
            store: store
        ) ?? .square
        let wrap = SpacePreferences.symbolWrap(
            forSpace: currentSpace,
            display: currentDisplayID,
            store: store
        ) ?? .inside
        return labelStyle.combinedSymbolLayout(for: wrap)
    }

    var currentInvertedColors: SpaceColors {
        let defaults = IconColors.filledColors(darkMode: darkModeEnabled)
        let colors = currentColors ?? SpaceColors(
            foreground: defaults.foreground,
            background: defaults.background
        )
        return colors.inverted(for: currentCombinedSymbolLayout)
    }

    var currentFont: NSFont? {
        SpacePreferences.font(forSpace: currentSpace, display: currentDisplayID, store: store)?.font
    }

    /// The user-visible number for the current space (regular index in local
    /// mode, global index otherwise). Distinct from `currentSpace`, which is
    /// a fullscreen-inclusive array position used for preference keying.
    var currentSpaceDisplayNumber: Int {
        let index = currentSpace - 1
        let regularIndex = allSpaceEntries.indices.contains(index)
            ? allSpaceEntries[index].regularIndex
            : nil
        if store.localSpaceNumbers {
            return regularIndex ?? currentSpace
        }
        return currentGlobalSpaceIndex > 0 ? currentGlobalSpaceIndex : currentSpace
    }

    func getAllSpaceIndices() -> [Int] {
        guard !allSpaceEntries.isEmpty else {
            return []
        }
        return Array(1 ... allSpaceEntries.count)
    }

    // MARK: - Icon Generation (delegates to StatusBarRenderer)

    var statusBarIcon: NSImage {
        renderer.statusBarIcon
    }

    /// Sets preview overrides and returns the full status bar icon with previewed changes
    func generatePreviewIcon(
        overrideStyle: IconStyle? = nil,
        overrideLabelStyle: IconStyle? = nil,
        overrideSymbol: String? = nil,
        overrideForeground: NSColor? = nil,
        overrideBackground: NSColor? = nil,
        overrideSymbolColor: NSColor? = nil,
        overrideSymbolBackground: NSColor? = nil,
        overrideSymbolPosition: SymbolPosition? = nil,
        overrideSymbolWrap: SymbolWrap? = nil,
        overrideSeparatorColor: NSColor? = nil,
        clearSymbol: Bool = false,
        clearSymbolBackground: Bool = false,
        skinTone: SkinTone? = nil,
        overrideBadgePosition: BadgePosition? = nil
    ) -> NSImage {
        renderer.generatePreviewIcon(
            overrideStyle: overrideStyle,
            overrideLabelStyle: overrideLabelStyle,
            overrideSymbol: overrideSymbol,
            overrideForeground: overrideForeground,
            overrideBackground: overrideBackground,
            overrideSymbolColor: overrideSymbolColor,
            overrideSymbolBackground: overrideSymbolBackground,
            overrideSymbolPosition: overrideSymbolPosition,
            overrideSymbolWrap: overrideSymbolWrap,
            overrideSeparatorColor: overrideSeparatorColor,
            clearSymbol: clearSymbol,
            clearSymbolBackground: clearSymbolBackground,
            skinTone: skinTone,
            overrideBadgePosition: overrideBadgePosition
        )
    }

    /// Returns the layout of visible icons in the status bar for the current mode
    func statusBarLayout() -> StatusBarLayout {
        renderer.statusBarLayout()
    }

    /// Returns one entry per Space for the left-click picker menu (single-icon mode)
    func spacePickerEntries() -> [SpacePickerEntry] {
        renderer.spacePickerEntries()
    }
}
