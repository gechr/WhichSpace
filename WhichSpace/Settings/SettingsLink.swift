import Foundation
import Observation

// MARK: - SettingsPaneID

/// A settings pane addressable from a `whichspace://settings/<pane>` URL.
///
/// Raw values are lowercase because URL matching lowercases before lookup.
enum SettingsPaneID: String, CaseIterable {
    case general
    case spaces
    case mouse
    case keyboard
    case menuBar = "menubar"

    /// Resolves a URL pane name, accepting retired names from links already
    /// published: "switching" predates the Mouse rename.
    static func named(_ raw: String) -> Self? {
        if raw == "switching" {
            return .mouse
        }
        return Self(rawValue: raw)
    }

    /// The pane's toolbar title, for naming where a searched setting lives.
    var localizedName: String {
        switch self {
        case .general:
            Localization.paneGeneral
        case .spaces:
            Localization.paneSpaces
        case .mouse:
            Localization.paneMouse
        case .keyboard:
            Localization.paneKeyboard
        case .menuBar:
            Localization.paneMenuBar
        }
    }
}

// MARK: - SettingsAnchor

/// A single setting addressable from a `whichspace://settings` URL, so a link
/// can point at one row rather than a whole pane.
///
/// Raw values are the public vocabulary for those links. Case names can be
/// renamed freely, but changing a raw value breaks links already published.
enum SettingsAnchor: String, CaseIterable {
    case launchAtLogin = "launch-at-login"
    case autoCheckUpdates = "auto-check-updates"
    case autoInstallUpdates = "auto-install-updates"
    case checkForUpdates = "check-for-updates"
    case backup
    case resetSettings = "reset-settings"

    case iconSize = "icon-size"
    case iconPadding = "icon-padding"
    case shrinkToFit = "shrink-to-fit"
    /// Retired toggle; kept because raw values are published, redirecting
    /// to the Displays picker that replaced it.
    case uniqueIconsPerDisplay = "unique-icons-per-display"
    case displays
    case localSpaceNumbers = "local-space-numbers"
    case separatorColor = "separator-color"
    case separatorStyle = "separator-style"
    case showAllDisplays = "show-all-displays"
    case showAllSpaces = "show-all-spaces"
    case dimInactiveSpaces = "dim-inactive-spaces"
    case hideEmptySpaces = "hide-empty-spaces"
    case hideSingleSpace = "hide-single-space"
    case hideFullscreenApps = "hide-fullscreen-apps"
    case fullscreenLetter = "fullscreen-letter"

    case preview
    case spaceLabel = "space-label"
    case numberStyle = "number-style"
    case symbol
    case emoji
    case symbolPosition = "symbol-position"
    case symbolWrap = "symbol-wrap"
    case symbolGap = "symbol-gap"
    case skinTone = "skin-tone"
    case symbolColor = "symbol-color"
    case symbolBackground = "symbol-background"
    case foregroundColor = "foreground-color"
    case backgroundColor = "background-color"
    case invertColors = "invert-colors"
    case badge
    case badgePosition = "badge-position"
    case font
    case sound
    case customSounds = "custom-sounds"

    case accessibility
    case behavior
    case click
    case scroll
    case classicSwitching = "classic-switching"
    case clickToSwitch = "click-to-switch"
    case verticalScroll = "vertical-scroll"
    case invertVerticalScroll = "invert-vertical-scroll"
    case horizontalScroll = "horizontal-scroll"
    case invertHorizontalScroll = "invert-horizontal-scroll"
    case scrollWrapAround = "scroll-wrap-around"
    case scrollSensitivity = "scroll-sensitivity"
    case scrollHaptics = "scroll-haptics"

    case hotkeySwitchLeft = "switch-left"
    case hotkeySwitchRight = "switch-right"
    case hotkeySwitchPrevious = "switch-previous"
    case hotkeySendLeft = "send-left"
    case hotkeySendRight = "send-right"
    case hotkeyMoveLeft = "move-left"
    case hotkeyMoveRight = "move-right"
    case jump

    /// The anchor owning the row or section a link lands on. Emoji shares the
    /// Glyph section with symbol, so both point at the same place; keeping the
    /// section's own anchor fixed stops its identity churning as the catalog
    /// picker flips.
    var target: Self {
        switch self {
        case .emoji:
            .symbol
        case .uniqueIconsPerDisplay:
            .displays
        default:
            self
        }
    }

    /// The pane the row lives on, letting a link name the setting alone.
    var pane: SettingsPaneID {
        switch self {
        case .launchAtLogin, .autoCheckUpdates, .autoInstallUpdates, .checkForUpdates, .backup,
             .resetSettings:
            .general
        case .iconSize, .iconPadding, .shrinkToFit, .localSpaceNumbers, .separatorColor,
             .separatorStyle, .showAllDisplays, .showAllSpaces, .dimInactiveSpaces,
             .hideEmptySpaces, .hideSingleSpace, .hideFullscreenApps, .fullscreenLetter:
            .menuBar
        case .preview, .uniqueIconsPerDisplay, .displays, .spaceLabel, .numberStyle, .symbol,
             .emoji, .symbolPosition, .symbolWrap, .symbolGap, .skinTone, .symbolColor,
             .symbolBackground, .foregroundColor, .backgroundColor, .invertColors, .badge,
             .badgePosition, .font, .sound, .customSounds:
            .spaces
        case .accessibility, .behavior, .click, .scroll, .classicSwitching, .clickToSwitch,
             .verticalScroll, .invertVerticalScroll, .horizontalScroll, .invertHorizontalScroll,
             .scrollWrapAround, .scrollSensitivity, .scrollHaptics:
            .mouse
        case .hotkeySwitchLeft, .hotkeySwitchRight, .hotkeySwitchPrevious, .hotkeySendLeft,
             .hotkeySendRight, .hotkeyMoveLeft, .hotkeyMoveRight, .jump:
            .keyboard
        }
    }
}

// MARK: - SettingsFocus

/// What a deep link asks the window to do with the setting it names.
///
/// Both forms select the pane and scroll the row into view; only `highlight`
/// lights it up, so a link can land on a setting without the flash of
/// emphasis.
enum SettingsFocus: Equatable {
    case highlight(SettingsAnchor)
    case navigate(SettingsAnchor)

    /// The row the link points at, whichever form it took.
    var anchor: SettingsAnchor {
        switch self {
        case let .highlight(anchor), let .navigate(anchor):
            anchor
        }
    }

    /// Whether the row lights up once it is in view.
    var isEmphasized: Bool {
        switch self {
        case .highlight:
            true
        case .navigate:
            false
        }
    }
}

// MARK: - SettingsHighlighter

/// Tracks the row a deep link pointed at, and whether it asked for emphasis.
///
/// The focus clears itself after a few seconds so a highlight reads as a
/// pointer to a setting rather than a state the row is stuck in.
@MainActor
@Observable
final class SettingsHighlighter {
    /// How long a highlight stays lit before fading on its own
    static let duration: Duration = .seconds(3)

    private(set) var focus: SettingsFocus?

    /// The row a link pointed at, whether or not it lights up.
    var anchor: SettingsAnchor? {
        focus?.anchor
    }

    @ObservationIgnored private var clearTask: Task<Void, Never>?

    /// Whether the given row is the one a link asked to light up. Rows carry
    /// their own anchor, so they ask rather than compare.
    func isEmphasizing(_ anchor: SettingsAnchor?) -> Bool {
        guard let anchor, let focus, focus.isEmphasized else {
            return false
        }
        return focus.anchor.target == anchor
    }

    /// Points the window at a row, replacing whatever a previous link asked
    /// for. Passing nil clears immediately, which is what a paneless link
    /// wants.
    func point(at focus: SettingsFocus?) {
        clearTask?.cancel()
        self.focus = focus
        guard focus != nil else {
            return
        }
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else {
                return
            }
            self?.focus = nil
        }
    }
}
