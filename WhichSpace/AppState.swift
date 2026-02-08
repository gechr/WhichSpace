import Cocoa
import Defaults
import os.log

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
    /// Count of regular (non-fullscreen) spaces on this display
    let regularSpaceCount: Int
    /// The global starting index for this display's spaces (1-based)
    let globalStartIndex: Int

    init(
        displayID: String,
        entries: [SpaceEntry],
        globalStartIndex: Int = 1,
        regularSpaceCount: Int? = nil
    ) {
        self.displayID = displayID
        self.entries = entries
        self.globalStartIndex = globalStartIndex
        self.regularSpaceCount = regularSpaceCount ?? entries.compactMap(\.regularIndex).count
    }

    /// Convenience initializer from parallel arrays (used in tests and migration)
    init(
        displayID: String,
        labels: [String],
        spaceIDs: [Int],
        globalStartIndex: Int = 1,
        regularIndices: [Int?] = [],
        regularSpaceCount: Int? = nil
    ) {
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
        let entries = zip(zip(spaceIDs, labels), computedRegularIndices).map { pair, regularIndex in
            SpaceEntry(id: pair.0, label: pair.1, regularIndex: regularIndex)
        }
        self.init(
            displayID: displayID,
            entries: entries,
            globalStartIndex: globalStartIndex,
            regularSpaceCount: regularSpaceCount ?? computedRegularIndices.compactMap(\.self).count
        )
    }
}

// MARK: - Space Snapshot

/// Immutable snapshot of the current system space state, emitted by SpaceMonitor
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
    /// Posted when the active space changes. The notification object is the AppState instance.
    static let spaceDidChange = Notification.Name("io.gechr.WhichSpace.spaceDidChange")
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
    private static let debounceInterval: Duration = .milliseconds(50)

    /// Space info for all displays (used when showAllDisplays is enabled)
    private(set) var allDisplaysSpaceInfo: [DisplaySpaceInfo] = []
    private(set) var allSpaceEntries: [SpaceEntry] = []
    private(set) var currentDisplayID: String?
    /// The global space index of the current space across all displays (1-based)
    private(set) var currentGlobalSpaceIndex = 0
    private(set) var currentSpace = 0
    private(set) var currentSpaceID = 0
    private(set) var currentSpaceLabel = "?"
    private(set) var darkModeEnabled = false

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
    private var pendingUpdateTask: Task<Void, Never>?
    private var spaceMonitor: SpaceMonitor?
    private var spaceMonitorTask: Task<Void, Never>?

    init(store: DefaultsStore) {
        displaySpaceProvider = FallbackDisplaySpaceProvider()
        self.store = store
        updateDarkModeStatus()
        configureObservers()
        startSpaceMonitor()
        applySnapshot(buildSnapshot())
    }

    /// Internal initializer for testing with a custom display space provider
    init(displaySpaceProvider: DisplaySpaceProvider, skipObservers: Bool = false, store: DefaultsStore) {
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
            allSpaceEntries = zip(resolvedIDs, labels).map { SpaceEntry(id: $0, label: $1, regularIndex: nil) }
            self.currentSpace = currentSpace
            currentSpaceLabel = currentLabel
            currentDisplayID = displayID
            if let allDisplays {
                allDisplaysSpaceInfo = allDisplays
            } else if let displayID {
                let info = DisplaySpaceInfo(displayID: displayID, labels: labels, spaceIDs: resolvedIDs)
                allDisplaysSpaceInfo = [info]
            } else {
                allDisplaysSpaceInfo = []
            }
            currentGlobalSpaceIndex = globalSpaceIndex ?? currentSpace
        }
    #endif

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
                guard !Task.isCancelled, let self, Date().timeIntervalSince(self.lastUpdateTime) > 0.5 else {
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
        SpaceSnapshotService.buildSnapshot(
            provider: displaySpaceProvider,
            localSpaceNumbers: store.localSpaceNumbers
        )
    }

    /// Applies a space snapshot to update AppState properties
    private func applySnapshot(_ snapshot: SpaceSnapshot) {
        // Invalidate window cache on space change to get fresh window data
        renderer.invalidateSpacesWithWindowsCache()

        // Save previous values for space change detection
        let oldSpaceID = currentSpaceID
        let oldDisplayID = currentDisplayID

        // Apply snapshot to state
        allDisplaysSpaceInfo = snapshot.allDisplaysSpaceInfo
        allSpaceEntries = snapshot.allSpaceEntries
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
        guard let app = NSApp
        else { return }
        let appearance = app.effectiveAppearance
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
        guard !allSpaceEntries.isEmpty else {
            return []
        }
        return Array(1 ... allSpaceEntries.count)
    }

    // MARK: - Icon Generation (delegates to StatusBarRenderer)

    var showAllSpaces: Bool {
        renderer.showAllSpaces
    }

    var showAllDisplays: Bool {
        renderer.showAllDisplays
    }

    var statusBarIcon: NSImage {
        renderer.statusBarIcon
    }

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
        renderer.generatePreviewIcon(
            overrideStyle: overrideStyle,
            overrideSymbol: overrideSymbol,
            overrideForeground: overrideForeground,
            overrideBackground: overrideBackground,
            overrideSeparatorColor: overrideSeparatorColor,
            clearSymbol: clearSymbol,
            skinTone: skinTone
        )
    }

    /// Returns the layout of visible icons in the status bar for the current mode
    func statusBarLayout() -> StatusBarLayout {
        renderer.statusBarLayout()
    }
}
