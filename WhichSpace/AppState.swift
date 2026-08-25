import Cocoa
import Defaults

/// A single space entry combining ID, label, and local regular index.
struct SpaceEntry: Equatable {
    let id: Int
    let label: String
    /// Local regular-space index (nil for fullscreen entries)
    let regularIndex: Int?
    /// CGS Space UUID; Space renaming tools key their custom names by it
    let uuid: String?

    init(id: Int, label: String, regularIndex: Int?, uuid: String? = nil) {
        self.id = id
        self.label = label
        self.regularIndex = regularIndex
        self.uuid = uuid
    }
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

    /// The last foreground application that represents a user window. URL
    /// dispatch can temporarily activate WhichSpace, while Stage Manager can
    /// report its WindowManager agent as foreground; neither should replace
    /// the application whose window the user intends to move.
    @ObservationIgnored private(set) var lastUserApplicationPID: pid_t?

    /// The Space left behind on each display, keyed by display identifier and
    /// holding a CGS Space ID rather than a position, so the entry survives
    /// Spaces being added or removed around it. Only written when the Space
    /// changes while the same display stays active, so moving between displays
    /// leaves either display's history alone.
    private var lastVisitedSpaceID: [String: Int] = [:]

    /// How far the status item is currently degraded to keep it on the menu
    /// bar. Observed through `statusBarIcon`, so setting it re-renders.
    var shrinkLevel: IconShrinkLevel = .full

    /// Invoked when a new snapshot lands, meaning the Space, its display, or
    /// the display arrangement changed. Drives the status item back to full
    /// size so a layout that has room again gets it back.
    @ObservationIgnored var onSnapshotDidChange: (() -> Void)?

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

    /// Regular Spaces across every display in Desktop-number order, so index
    /// N-1 is the Space that global Desktop number N addresses. Each carries
    /// the display and 1-based fullscreen-inclusive entry position that key
    /// its stored label and badge. Fullscreen Spaces have no Desktop number,
    /// and the list caps at the numbered Mission Control shortcut range:
    /// Desktops past it are not addressable by global number on any surface.
    var globalDesktopEntries: [(displayID: String, position: Int, entry: SpaceEntry)] {
        let desktops = allDisplaysSpaceInfo.flatMap { display in
            display.entries.enumerated().compactMap { index, entry in
                entry.regularIndex.map {
                    (
                        number: display.globalStartIndex + $0 - 1,
                        displayID: display.displayID,
                        position: index + 1,
                        entry: entry
                    )
                }
            }
        }
        return desktops
            .sorted { $0.number < $1.number }
            .prefix(Layout.maxSpacesPerDisplay)
            .map { ($0.displayID, $0.position, $0.entry) }
    }

    /// Whether any display has more than one regular Space. A collection of
    /// single-Space displays still has nothing useful for the status item to
    /// switch between on any individual display.
    var hasMultipleRegularSpacesOnAnyDisplay: Bool {
        allDisplaysSpaceInfo.contains { $0.regularSpaceCount > 1 }
    }

    /// Spaces on every display with no qualifying windows, resolved from the
    /// same occupancy source the hideEmptySpaces filter renders from.
    /// Spanning all displays keeps the set valid whichever display a switch
    /// resolves as active, since skipping matches by ID membership. Queried
    /// on demand rather than cached: callers are per-keypress, and a stale
    /// answer would route a switch to a Space that just gained or lost its
    /// last window.
    func emptySpaceIDs() -> Set<Int> {
        let spaceIDs = allDisplaysSpaceInfo.flatMap { $0.entries.map(\.id) }
        return Set(spaceIDs).subtracting(displaySpaceProvider.spacesWithWindows(forSpaceIDs: spaceIDs))
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

        rememberUserApplication(workspace.frontmostApplication)

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
            for await notification in workspace.notificationCenter
                .notifications(named: NSWorkspace.didActivateApplicationNotification)
            {
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.rememberUserApplication(application)
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

    private func rememberUserApplication(_ application: NSRunningApplication?) {
        guard let application,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              application.bundleIdentifier != "com.apple.WindowManager"
        else {
            return
        }
        lastUserApplicationPID = application.processIdentifier
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

    /// Builds an immutable snapshot of the current space state from system
    /// data. The display order settings sit greyed out under the
    /// show-all-displays toggle, so turning it off suspends their effect on
    /// numbering rather than leaving a disabled row still changing the icon.
    private func buildSnapshot() -> SpaceSnapshot {
        SpaceSnapshotService.buildSnapshot(
            provider: displaySpaceProvider,
            localSpaceNumbers: store.localSpaceNumbers,
            displayOrder: store.showAllDisplays ? store.displayOrder : .system,
            preserveSystemSpaceNumbers: store.preserveSystemSpaceNumbers
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
        // Runs on equal snapshots too: a pending topology candidate is
        // confirmed by the next observation, which is usually a no-op apply
        reconcileSpaceOrders(with: newSnapshot)
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
        let oldSpaceID = snapshot.currentSpaceID
        let oldDisplayID = snapshot.currentDisplayID

        snapshot = newSnapshot
        lastUpdateTime = Date()
        renderer.spaceSnapshotDidChange()
        // Equal snapshots returned above, so this is a real Space or topology
        // change and not one of the notification bursts that arrive on every
        // app activation
        onSnapshotDidChange?()

        // Real CGS state for the active space has landed - stale switch
        // predictions are now wrong. Topology-only snapshot changes keep
        // predictions so mid-burst switches don't overshoot
        if newSnapshot.currentSpaceID != oldSpaceID {
            SpaceSwitcher.resetPredictions()
        }

        recordLastVisitedSpace(oldSpaceID: oldSpaceID, oldDisplayID: oldDisplayID)

        // Post notification if space changed on the same display
        postCurrentDisplaySpaceChangeIfNeeded(oldSpaceID: oldSpaceID, oldDisplayID: oldDisplayID)
    }

    /// A topology observed once that differs from the baseline in Space or
    /// display membership. Adopted as the new baseline only when the next
    /// snapshot shows it again, so a single transient partial CGS read
    /// cannot replace the baseline. Nil means no candidate is in flight,
    /// which an empty map cannot express.
    // swiftlint:disable:next discouraged_optional_collection
    private var pendingSpaceOrders: [String: [String]]?

    /// Tracks each display's Space order by CGS UUID and, when a snapshot
    /// shows the same Spaces in a different order (a Mission Control
    /// reorder), moves per-Space preferences so they follow their Spaces.
    /// Orders persist in defaults, so a reorder done while the app is not
    /// running reconciles on the next launch.
    ///
    /// CGS reads can race display reconfiguration and briefly drop Spaces or
    /// whole displays, so a snapshot whose membership differs from the
    /// baseline is only a candidate: it must be observed twice in a row
    /// before it replaces the baseline, and it never remaps. Only a pure
    /// reorder - same displays, same Space sets - remaps, and immediately: a
    /// partial read cannot fabricate one, and the settled baseline stays
    /// intact underneath any transient in between.
    ///
    /// The double observation is a heuristic, not a proof of completeness: a
    /// transient that survives two consecutive snapshots is adopted as a real
    /// membership change. A reorder raced by one is then lost - preferences
    /// stay at their old positions, the pre-tracking behavior - and, rarer
    /// still, a further partial read showing the adopted reduced set in a
    /// different order can remap against the poisoned baseline and move
    /// preferences wrongly until the user rearranges them. Both need the
    /// same incomplete CGS state to persist across multiple reads while the
    /// Spaces change underneath, and the values themselves are never lost.
    /// A snapshot in which any display's UUIDs are missing or ambiguous is
    /// discarded outright, changing neither the baseline nor the candidate.
    private func reconcileSpaceOrders(with newSnapshot: SpaceSnapshot) {
        guard !newSnapshot.allDisplaysSpaceInfo.isEmpty else {
            return
        }
        var current: [String: [String]] = [:]
        for display in newSnapshot.allDisplaysSpaceInfo {
            let uuids = display.entries.compactMap(\.uuid)
            guard uuids.count == display.entries.count,
                  !uuids.contains(""),
                  Set(uuids).count == uuids.count
            else {
                return
            }
            current[display.displayID] = uuids
        }
        let baseline = store.spaceOrders
        guard current != baseline else {
            pendingSpaceOrders = nil
            return
        }
        guard !baseline.isEmpty else {
            // Nothing recorded yet, so there is no reorder to detect - adopt
            // the first observation as the baseline
            store.spaceOrders = current
            pendingSpaceOrders = nil
            return
        }
        let isPureReorder = Set(current.keys) == Set(baseline.keys)
            && current.allSatisfy { displayID, uuids in
                guard let previous = baseline[displayID] else {
                    return false
                }
                // The count check guards a corrupted external baseline with
                // duplicates, which equal sets alone would let through
                return previous.count == uuids.count && Set(previous) == Set(uuids)
            }
        guard isPureReorder else {
            if pendingSpaceOrders == current {
                store.spaceOrders = current
                pendingSpaceOrders = nil
            } else {
                pendingSpaceOrders = current
            }
            return
        }
        pendingSpaceOrders = nil
        // A shared-scope position spans every display, so it can only follow
        // a reorder when a single display makes the association unambiguous
        let includeShared = current.count == 1
        for (displayID, uuids) in current {
            guard let previous = baseline[displayID], previous != uuids else {
                continue
            }
            var mapping: [Int: Int] = [:]
            for (index, uuid) in uuids.enumerated() {
                guard let previousIndex = previous.firstIndex(of: uuid), previousIndex != index else {
                    continue
                }
                mapping[previousIndex + 1] = index + 1
            }
            guard !mapping.isEmpty else {
                continue
            }
            SpacePreferences.remapPositions(
                mapping,
                display: displayID,
                includeShared: includeShared,
                store: store
            )
        }
        store.spaceOrders = current
    }

    /// Remembers the Space just left, so `previousSpaceNumber` can offer it as
    /// a switch target. A change of display is not a Space visit: the display
    /// being left keeps its current Space, and the display arrived at was left
    /// on the Space it is still showing, so neither history moves.
    private func recordLastVisitedSpace(oldSpaceID: Int, oldDisplayID: String?) {
        guard let oldDisplayID,
              oldSpaceID != 0,
              currentSpaceID != oldSpaceID,
              currentDisplayID == oldDisplayID
        else {
            return
        }
        lastVisitedSpaceID[oldDisplayID] = oldSpaceID
    }

    /// The 1-based `allSpaceEntries` position of the Space last visited on the
    /// current display, or nil when none has been recorded yet or the recorded
    /// Space has since been removed. Switching records the Space being left, so
    /// repeatedly switching here toggles between the two.
    var previousSpaceNumber: Int? {
        guard let entry = previousSpaceEntry,
              let index = allSpaceEntries.firstIndex(of: entry)
        else {
            return nil
        }
        return index + 1
    }

    /// The entry of the Space last visited on the current display, or nil
    /// when none has been recorded yet or the recorded Space has since been
    /// removed. Keyed by space ID, so switching to it is independent of the
    /// local or global numbering preference.
    var previousSpaceEntry: SpaceEntry? {
        guard let currentDisplayID,
              let spaceID = lastVisitedSpaceID[currentDisplayID]
        else {
            return nil
        }
        return allSpaceEntries.first { $0.id == spaceID }
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
        SpacePreferences.iconStyle(forSpace: currentSpace, display: currentDisplayID, store: store) ?? .fallback
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
        ) ?? .fallback
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
        guard let regularIndex else {
            // A fullscreen Space has no displayed number in either mode, so
            // it falls back to its entry position on the current display
            // rather than borrowing an unrelated Desktop's global number
            return currentSpace
        }
        if store.localSpaceNumbers {
            return regularIndex
        }
        return currentGlobalSpaceIndex > 0 ? currentGlobalSpaceIndex : currentSpace
    }

    /// The user-visible number for the Space at `number`, a 1-based
    /// fullscreen-inclusive position matching `allSpaceEntries` indexing.
    /// Generalises `currentSpaceDisplayNumber` to arbitrary Spaces, and defers
    /// to it for the current Space so both agree on the authoritative snapshot
    /// value. Out-of-range positions return `number` unchanged.
    func displayNumber(forSpace number: Int) -> Int {
        guard number != currentSpace else {
            return currentSpaceDisplayNumber
        }
        let index = number - 1
        guard allSpaceEntries.indices.contains(index) else {
            return number
        }
        let regularIndex = allSpaceEntries[index].regularIndex
        if store.localSpaceNumbers {
            return regularIndex ?? number
        }
        let globalStartIndex = allDisplaysSpaceInfo
            .first { $0.displayID == currentDisplayID }?.globalStartIndex ?? 1
        return globalStartIndex + max((regularIndex ?? 0) - 1, 0)
    }

    func getAllSpaceIndices() -> [Int] {
        guard !allSpaceEntries.isEmpty else {
            return []
        }
        return Array(1 ... allSpaceEntries.count)
    }

    // MARK: - Icon Generation (delegates to StatusBarRenderer)

    var statusBarIcon: NSImage {
        renderer.statusBarIcon(level: shrinkLevel)
    }

    /// Returns the layout of visible icons in the status bar for the current mode
    func statusBarLayout() -> StatusBarLayout {
        renderer.statusBarLayout(level: shrinkLevel)
    }

    /// Returns one entry per Space for the left-click picker menu (single-icon mode)
    func spacePickerEntries() -> [SpacePickerEntry] {
        renderer.spacePickerEntries()
    }
}
