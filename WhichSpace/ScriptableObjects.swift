import Cocoa

/// Resolves the system name of a display, for example "Built-in Retina
/// Display". CGS identifies displays by UUID string and `NSScreen` publishes
/// only a CoreGraphics display ID, so screens are matched by converting each
/// screen's display ID to its UUID. Nil when no attached screen claims the
/// UUID.
@MainActor
enum DisplayNameResolver {
    static func localizedName(for displayID: String?) -> String? {
        guard let displayID else {
            return nil
        }
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber,
                let uuid = CGDisplayCreateUUIDFromDisplayID(
                    CGDirectDisplayID(number.uint32Value)
                )?.takeRetainedValue()
            else {
                continue
            }
            if CFUUIDCreateString(nil, uuid) as String == displayID {
                return screen.localizedName
            }
        }
        return nil
    }
}

extension NSScriptClassDescription {
    /// The scripting description of the application class, the container
    /// every element specifier this app vends routes through.
    static var applicationDescription: NSScriptClassDescription? {
        NSScriptClassDescription(for: NSApplication.self)
    }
}

/// Scriptable stand-in for a display, backing the sdef `display` class.
/// Holds only the display's identity; the name and Space elements are looked
/// up live at access time so results follow the current snapshot.
@MainActor
final class ScriptableDisplay: NSObject {
    /// 1-based position in CGS display order, matching the display picker in
    /// the Settings Spaces pane.
    let index: Int
    let displayID: String
    private let appState: AppState
    private let store: DefaultsStore

    init(index: Int, displayID: String, appState: AppState, store: DefaultsStore) {
        self.index = index
        self.displayID = displayID
        self.appState = appState
        self.store = store
    }

    /// Usage: `tell application "WhichSpace" to get index of display 1`
    @objc var displayNumber: Int {
        index
    }

    /// Usage: `tell application "WhichSpace" to get name of every display`
    @objc var name: String {
        DisplayNameResolver.localizedName(for: displayID) ?? ""
    }

    /// The display's Space elements. A disconnected display yields an empty
    /// list, so indexing into it raises the standard invalid-index error.
    @objc var scriptableSpaces: [ScriptableSpace] {
        ScriptingHelpers.scriptableSpaces(
            onDisplay: displayID,
            container: .display(index: index),
            appState: appState,
            store: store
        )
    }

    override nonisolated var objectSpecifier: NSScriptObjectSpecifier? {
        guard let appDescription = NSScriptClassDescription.applicationDescription else {
            return nil
        }
        return NSIndexSpecifier(
            containerClassDescription: appDescription,
            containerSpecifier: nil,
            key: "scriptableDisplays",
            index: index - 1
        )
    }
}

/// Scriptable stand-in for a Space, backing the sdef `space` class. Holds
/// the (position, display) identity that keys stored labels and badges;
/// every get and set goes live to `SpacePreferences`, so the menu bar
/// re-renders through the usual defaults observation.
@MainActor
final class ScriptableSpace: NSObject {
    /// The container an element specifier routes through, so a Space
    /// obtained as `space N of display M` round-trips as that reference.
    enum Container: Sendable {
        case application
        case display(index: Int)
    }

    /// 1-based fullscreen-inclusive entry position on the owning display,
    /// the same position that keys stored preferences. Independent of the
    /// local or global numbering preference.
    let position: Int
    let displayID: String
    private let container: Container
    private let appState: AppState
    private let store: DefaultsStore

    init(
        position: Int,
        displayID: String,
        container: Container,
        appState: AppState,
        store: DefaultsStore
    ) {
        self.position = position
        self.displayID = displayID
        self.container = container
        self.appState = appState
        self.store = store
    }

    /// Usage: `tell application "WhichSpace" to get index of space 2`
    @objc var spaceNumber: Int {
        position
    }

    /// Reading returns the custom label if set, otherwise "1", "2", "F" for
    /// fullscreen. Assigning a non-empty string applies a custom label;
    /// assigning "" resets it. Over-long labels are truncated with a
    /// trailing ellipsis.
    /// Usage: `tell application "WhichSpace" to get label of space 2`
    /// Usage: `tell application "WhichSpace" to set label of space 2 to "Work"`
    @objc var label: String {
        get {
            ScriptingHelpers.resolveLabel(
                atEntry: position,
                displayID: displayID,
                appState: appState,
                store: store
            )
        }
        set {
            ScriptingHelpers.setLabel(newValue, at: (position, displayID), store: store)
        }
    }

    /// Reading returns the badge character ("#" resolved to the Space
    /// number), or "" when unset. Assigning a single character applies the
    /// badge; more than one character is an error and "" resets it.
    /// Usage: `tell application "WhichSpace" to get badge of space 2`
    /// Usage: `tell application "WhichSpace" to set badge of space 2 to "A"`
    @objc var badge: String {
        get {
            ScriptingHelpers.resolveBadge(
                atEntry: position,
                displayID: displayID,
                appState: appState,
                store: store
            )
        }
        set {
            do {
                try ScriptingHelpers.setBadge(newValue, at: (position, displayID), store: store)
            } catch {
                // KVC setters can't throw; report through the in-flight command
                let command = NSScriptCommand.current()
                command?.scriptErrorNumber = errOSACantAssign
                command?.scriptErrorString = error.localizedDescription
            }
        }
    }

    override nonisolated var objectSpecifier: NSScriptObjectSpecifier? {
        guard let appDescription = NSScriptClassDescription.applicationDescription else {
            return nil
        }
        switch container {
        case .application:
            return NSIndexSpecifier(
                containerClassDescription: appDescription,
                containerSpecifier: nil,
                key: "scriptableSpaces",
                index: position - 1
            )
        case let .display(displayIndex):
            guard let displayDescription = appDescription.forKey("scriptableDisplays") else {
                return nil
            }
            let displaySpecifier = NSIndexSpecifier(
                containerClassDescription: appDescription,
                containerSpecifier: nil,
                key: "scriptableDisplays",
                index: displayIndex - 1
            )
            return NSIndexSpecifier(
                containerClassDescription: displayDescription,
                containerSpecifier: displaySpecifier,
                key: "scriptableSpaces",
                index: position - 1
            )
        }
    }
}

extension ScriptingHelpers {
    /// Returns a scriptable stand-in for every display, in the configured
    /// display order, the same order as the display picker in the Settings
    /// Spaces pane.
    static func scriptableDisplays(appState: AppState, store: DefaultsStore) -> [ScriptableDisplay] {
        appState.allDisplaysSpaceInfo.enumerated().map { index, info in
            ScriptableDisplay(
                index: index + 1,
                displayID: info.displayID,
                appState: appState,
                store: store
            )
        }
    }

    /// Returns the current display's Space elements, backing app-level
    /// `space N`. An empty snapshot yields an empty list.
    static func scriptableSpaces(appState: AppState, store: DefaultsStore) -> [ScriptableSpace] {
        guard let displayID = appState.currentDisplayID else {
            return []
        }
        return scriptableSpaces(
            onDisplay: displayID,
            container: .application,
            appState: appState,
            store: store
        )
    }

    /// Returns the Space elements of the given display, in entry order.
    static func scriptableSpaces(
        onDisplay displayID: String,
        container: ScriptableSpace.Container,
        appState: AppState,
        store: DefaultsStore
    ) -> [ScriptableSpace] {
        guard let info = appState.allDisplaysSpaceInfo.first(where: { $0.displayID == displayID })
        else {
            return []
        }
        return info.entries.indices.map { index in
            ScriptableSpace(
                position: index + 1,
                displayID: displayID,
                container: container,
                appState: appState,
                store: store
            )
        }
    }

    /// Returns the current Space as an element on the current display, or
    /// nil while the snapshot is empty.
    static func currentScriptableSpace(appState: AppState, store: DefaultsStore) -> ScriptableSpace? {
        guard appState.currentSpace > 0, let displayID = appState.currentDisplayID else {
            return nil
        }
        return ScriptableSpace(
            position: appState.currentSpace,
            displayID: displayID,
            container: .application,
            appState: appState,
            store: store
        )
    }

    /// Returns the label of the Space at the given entry position on the
    /// given display: its custom label when set, with space tokens resolved
    /// against the displayed number, otherwise the displayed number itself
    /// ("F" for fullscreen), matching the menu bar in either numbering mode.
    /// Stored labels are reported even for fullscreen Spaces, where the menu
    /// bar renders the owning app instead. Out-of-range positions without a
    /// stored label yield "".
    static func resolveLabel(
        atEntry position: Int,
        displayID: String,
        appState: AppState,
        store: DefaultsStore
    ) -> String {
        let info = appState.allDisplaysSpaceInfo.first { $0.displayID == displayID }
        if let customLabel = SpacePreferences.label(
            forSpace: position,
            display: displayID,
            store: store
        ), !customLabel.isEmpty {
            return LabelTemplate.resolve(
                customLabel,
                space: displayedNumber(forEntryAt: position, on: info, store: store)
            )
        }
        guard let info, info.entries.indices.contains(position - 1) else {
            return ""
        }
        guard info.entries[position - 1].regularIndex != nil else {
            return info.entries[position - 1].label
        }
        return String(displayedNumber(forEntryAt: position, on: info, store: store))
    }

    /// Returns the badge stored for the Space at the given entry position on
    /// the given display, or "" when none. The number token resolves against
    /// the displayed number. The menu bar never renders a badge on fullscreen
    /// Spaces, but a stored one is still reported.
    static func resolveBadge(
        atEntry position: Int,
        displayID: String,
        appState: AppState,
        store: DefaultsStore
    ) -> String {
        guard let badge = SpacePreferences.badge(
            forSpace: position,
            display: displayID,
            store: store
        ) else {
            return ""
        }
        guard badge.character == BadgeTemplate.spaceToken else {
            return badge.character
        }
        let info = appState.allDisplaysSpaceInfo.first { $0.displayID == displayID }
        return String(displayedNumber(forEntryAt: position, on: info, store: store))
    }

    /// The user-visible number for an entry position on a display: the
    /// position itself for fullscreen Spaces, the display-local Desktop
    /// number with local numbering, and the global Desktop number otherwise.
    /// Used only to render label and badge number tokens; element indexing
    /// is always the entry position.
    private static func displayedNumber(
        forEntryAt position: Int,
        on info: DisplaySpaceInfo?,
        store: DefaultsStore
    ) -> Int {
        guard let info, info.entries.indices.contains(position - 1),
              let regularIndex = info.entries[position - 1].regularIndex
        else {
            return position
        }
        return store.localSpaceNumbers ? regularIndex : info.globalStartIndex + regularIndex - 1
    }
}

/// Extension exposing the element containers of the sdef object model.
extension NSApplication {
    /// The display elements, in the same order as the Settings display picker.
    /// Usage: `tell application "WhichSpace" to get name of every display`
    @MainActor @objc var scriptableDisplays: [ScriptableDisplay] {
        ScriptingHelpers.scriptableDisplays(
            appState: AppEnvironment.shared.appState,
            store: AppEnvironment.shared.store
        )
    }

    /// The current display's Space elements, backing app-level `space N`.
    /// Usage: `tell application "WhichSpace" to get label of space 2`
    @MainActor @objc var scriptableSpaces: [ScriptableSpace] {
        ScriptingHelpers.scriptableSpaces(
            appState: AppEnvironment.shared.appState,
            store: AppEnvironment.shared.store
        )
    }

    /// The current Space as an element.
    /// Usage: `tell application "WhichSpace" to get label of current space`
    @MainActor @objc var currentScriptableSpace: ScriptableSpace? {
        ScriptingHelpers.currentScriptableSpace(
            appState: AppEnvironment.shared.appState,
            store: AppEnvironment.shared.store
        )
    }
}
