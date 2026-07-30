import Foundation
import Observation

// MARK: - SettingsPaneID

/// A settings pane addressable from a `whichspace://settings/<pane>` URL.
///
/// Raw values are lowercase because URL matching lowercases before lookup.
enum SettingsPaneID: String, CaseIterable {
    case general
    case spaces
    case switching
    case menuBar = "menubar"
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

    case iconSize = "icon-size"
    case iconPadding = "icon-padding"
    case uniqueIconsPerDisplay = "unique-icons-per-display"
    case localSpaceNumbers = "local-space-numbers"
    case separatorColor = "separator-color"
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
    case clickToSwitch = "click-to-switch"
    case verticalScroll = "vertical-scroll"
    case invertVerticalScroll = "invert-vertical-scroll"
    case horizontalScroll = "horizontal-scroll"
    case invertHorizontalScroll = "invert-horizontal-scroll"
    case scrollWrapAround = "scroll-wrap-around"
    case scrollSensitivity = "scroll-sensitivity"
    case scrollHaptics = "scroll-haptics"

    /// The anchor owning the row or section a link lands on. Emoji shares the
    /// Glyph section with symbol, so both point at the same place; keeping the
    /// section's own anchor fixed stops its identity churning as the catalog
    /// picker flips.
    var target: Self {
        self == .emoji ? .symbol : self
    }

    /// The pane the row lives on, letting a link name the setting alone.
    var pane: SettingsPaneID {
        switch self {
        case .launchAtLogin, .autoCheckUpdates, .autoInstallUpdates, .checkForUpdates, .backup:
            .general
        case .iconSize, .iconPadding, .uniqueIconsPerDisplay, .localSpaceNumbers, .separatorColor,
             .showAllDisplays, .showAllSpaces, .dimInactiveSpaces, .hideEmptySpaces,
             .hideSingleSpace, .hideFullscreenApps, .fullscreenLetter:
            .menuBar
        case .preview, .spaceLabel, .numberStyle, .symbol, .emoji, .symbolPosition, .symbolWrap,
             .symbolGap, .skinTone, .symbolColor, .symbolBackground, .foregroundColor,
             .backgroundColor, .invertColors, .badge, .badgePosition, .font, .sound, .customSounds:
            .spaces
        case .accessibility, .clickToSwitch, .verticalScroll, .invertVerticalScroll,
             .horizontalScroll, .invertHorizontalScroll, .scrollWrapAround, .scrollSensitivity,
             .scrollHaptics:
            .switching
        }
    }
}

// MARK: - SettingsHighlighter

/// Tracks the row a deep link asked to emphasize.
///
/// The highlight clears itself after a few seconds so it reads as a pointer
/// to a setting rather than a state the row is stuck in.
@MainActor
@Observable
final class SettingsHighlighter {
    /// How long a highlight stays lit before fading on its own
    static let duration: Duration = .seconds(3)

    private(set) var anchor: SettingsAnchor?

    @ObservationIgnored private var clearTask: Task<Void, Never>?

    /// Lights the given row, replacing any highlight already showing. Passing
    /// nil clears immediately, which is what a paneless link wants.
    func highlight(_ anchor: SettingsAnchor?) {
        clearTask?.cancel()
        self.anchor = anchor
        guard anchor != nil else {
            return
        }
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.duration)
            guard !Task.isCancelled else {
                return
            }
            self?.anchor = nil
        }
    }
}
