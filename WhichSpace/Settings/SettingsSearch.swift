import Foundation

// MARK: - SettingsSearchKeyword

/// A group of words a setting answers to that its own text never says.
///
/// Grouped by concept rather than written out per row, so one translated list
/// serves every row it applies to: "monitor" reaches the display toggle and
/// both separator rows without three near-identical strings to keep in step.
///
/// Each localized value is one space-separated list, matched as a single
/// blob. Scoring gives a bonus at a word start, so a term buried in the list
/// still ranks like a term at the front of it.
enum SettingsSearchKeyword: CaseIterable {
    case backup
    case color
    case display
    case emoji
    case font
    case fullscreen
    case haptics
    case hide
    case hotkey
    case icon
    case label
    case permission
    case pointer
    case reset
    case size
    case sound
    case space
    case startup
    case update
    case window

    var terms: String {
        switch self {
        case .backup:
            Localization.searchKeywordsBackup
        case .color:
            Localization.searchKeywordsColor
        case .display:
            Localization.searchKeywordsDisplay
        case .emoji:
            Localization.searchKeywordsEmoji
        case .font:
            Localization.searchKeywordsFont
        case .fullscreen:
            Localization.searchKeywordsFullscreen
        case .haptics:
            Localization.searchKeywordsHaptics
        case .hide:
            Localization.searchKeywordsHide
        case .hotkey:
            Localization.searchKeywordsHotkey
        case .icon:
            Localization.searchKeywordsIcon
        case .label:
            Localization.searchKeywordsLabel
        case .permission:
            Localization.searchKeywordsPermission
        case .pointer:
            Localization.searchKeywordsPointer
        case .reset:
            Localization.searchKeywordsReset
        case .size:
            Localization.searchKeywordsSize
        case .sound:
            Localization.searchKeywordsSound
        case .space:
            Localization.searchKeywordsSpace
        case .startup:
            Localization.searchKeywordsStartup
        case .update:
            Localization.searchKeywordsUpdate
        case .window:
            Localization.searchKeywordsWindow
        }
    }
}

// MARK: - SettingsSearchEntry

/// One searchable setting: the words a query is matched against, and the
/// anchor a hit navigates to.
///
/// Entries carry no state of their own - the anchor already knows its pane,
/// and the strings are the same `Localization` constants the rows render, so
/// a translated build searches in its own language for free.
struct SettingsSearchEntry: Identifiable, Equatable {
    let anchor: SettingsAnchor
    /// The card the row sits under, or the axis a paired row belongs to.
    /// Nil for rows whose card carries no header.
    let section: String?
    let title: String
    let subtitle: String?
    /// What the row is about, beyond the words it happens to use, so a query
    /// can name the thing rather than the setting.
    var keywords: [SettingsSearchKeyword] = []

    var id: SettingsAnchor {
        anchor
    }

    var pane: SettingsPaneID {
        anchor.pane
    }

    /// Where the row lives, for the line beneath a result's title.
    var breadcrumb: String {
        [pane.localizedName, section].compactMap(\.self).joined(separator: " › ")
    }

    /// Everything a query is matched against, each with the weight its field
    /// carries. The section outranks the description because it names the
    /// setting's group, which is how people search ("scroll", "colour"),
    /// while a description mentions a word only in passing. Both are matched
    /// so "scroll" finds the axis rows, whose own titles say only "Vertical"
    /// and "Horizontal".
    ///
    /// Keywords rank below a description: a synonym is a guess at what the
    /// user meant, so a row that says the word outright answers first. They
    /// still outrank the pane name, which every row on a pane shares.
    ///
    /// Weights are fixed per field rather than derived from position, so an
    /// entry that happens to carry a description is not scored above one that
    /// matched on the same field without one.
    var fields: [(text: String, weight: Int)] {
        var fields = [(text: title, weight: 40)]
        if let section {
            fields.append((text: section, weight: 30))
        }
        if let subtitle {
            fields.append((text: subtitle, weight: 20))
        }
        if !keywords.isEmpty {
            fields.append((text: keywords.map(\.terms).joined(separator: " "), weight: 15))
        }
        fields.append((text: pane.localizedName, weight: 10))
        return fields
    }
}

// MARK: - SettingsSearchIndex

/// Every setting a search can reach, and the query matching over them.
///
/// The list is written out rather than derived from the panes: SwiftUI views
/// cannot be enumerated, and a hand-kept table is the same shape the defaults
/// keys use. `SettingsSearchIndexTests` fails if an anchor is added without a
/// matching entry, so the two cannot drift apart silently.
enum SettingsSearchIndex {
    /// Anchors a search never offers, because landing on them shows nothing:
    /// `uniqueIconsPerDisplay` is a retired raw value redirecting elsewhere,
    /// `displays` names the Spaces pane's display picker, which appears only
    /// with several displays attached, and the section anchors name whole
    /// cards whose rows are each listed already.
    static let unlisted: Set<SettingsAnchor> = [
        .uniqueIconsPerDisplay, .displays, .behavior, .click, .scroll,
    ]

    /// How many results the field offers at once. Past this the list stops
    /// being scannable, and a query that vague is better narrowed.
    static let resultLimit = 8

    static let entries: [SettingsSearchEntry] = general + menuBar + spaces + mouse + keyboard

    /// Every setting, in the order the toolbar arranges the panes, for the
    /// field to offer before anything has been typed.
    ///
    /// Uncapped, unlike a query's results: this is an index to read down
    /// rather than a set of guesses to choose between, so a long list scrolls
    /// instead of stopping at the eight most promising rows.
    static var browseEntries: [SettingsSearchEntry] {
        entries
    }

    // MARK: - General

    private static let general: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            anchor: .launchAtLogin,
            section: nil,
            title: Localization.toggleLaunchAtLogin,
            subtitle: String(format: Localization.tipLaunchAtLogin, AppInfo.appName),
            keywords: [.startup]
        ),
        SettingsSearchEntry(
            anchor: .autoCheckUpdates,
            section: nil,
            title: Localization.toggleAutoCheckUpdates,
            subtitle: nil,
            keywords: [.update]
        ),
        SettingsSearchEntry(
            anchor: .autoInstallUpdates,
            section: nil,
            title: Localization.toggleAutoInstallUpdates,
            subtitle: nil,
            keywords: [.update]
        ),
        SettingsSearchEntry(
            anchor: .betaUpdates,
            section: nil,
            title: Localization.toggleBetaUpdates,
            subtitle: Localization.tipBetaUpdates,
            keywords: [.update]
        ),
        SettingsSearchEntry(
            anchor: .checkForUpdates,
            section: nil,
            title: Localization.actionCheckForUpdates,
            subtitle: String(format: Localization.tipCheckForUpdates, AppInfo.appName),
            keywords: [.update]
        ),
        SettingsSearchEntry(
            anchor: .backup,
            section: nil,
            title: Localization.labelBackup,
            subtitle: Localization.tipBackup,
            keywords: [.backup]
        ),
        SettingsSearchEntry(
            anchor: .resetSettings,
            section: nil,
            title: Localization.labelResetSettings,
            subtitle: Localization.tipResetSettings,
            keywords: [.reset, .backup]
        ),
    ]

    // MARK: - Menu Bar

    private static let menuBar: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            anchor: .showAllSpaces,
            section: Localization.labelSpaces,
            title: Localization.toggleShowAllSpaces,
            subtitle: Localization.tipShowAllSpaces,
            keywords: [.space, .hide]
        ),
        SettingsSearchEntry(
            anchor: .dimInactiveSpaces,
            section: Localization.labelSpaces,
            title: Localization.labelInactiveSpaceOpacity,
            subtitle: Localization.tipInactiveSpaceOpacity,
            keywords: [.space, .color]
        ),
        SettingsSearchEntry(
            anchor: .hideEmptySpaces,
            section: Localization.labelSpaces,
            title: Localization.toggleHideEmptySpaces,
            subtitle: Localization.tipHideEmptySpaces,
            keywords: [.space, .hide, .window]
        ),
        SettingsSearchEntry(
            anchor: .hideFullscreenApps,
            section: Localization.labelSpaces,
            title: Localization.toggleHideFullscreenApps,
            subtitle: Localization.tipHideFullscreenApps,
            keywords: [.space, .hide, .fullscreen]
        ),
        SettingsSearchEntry(
            anchor: .showAllDisplays,
            section: Localization.labelSpaces,
            title: Localization.toggleShowAllDisplays,
            subtitle: Localization.tipShowAllDisplays,
            keywords: [.display, .space, .hide]
        ),
        SettingsSearchEntry(
            anchor: .displayOrder,
            section: Localization.labelSpaces,
            title: Localization.labelDisplayOrder,
            subtitle: Localization.tipDisplayOrder,
            keywords: [.display, .space]
        ),
        SettingsSearchEntry(
            anchor: .preserveSystemSpaceNumbers,
            section: Localization.labelSpaces,
            title: Localization.togglePreserveSystemSpaceNumbers,
            subtitle: Localization.tipPreserveSystemSpaceNumbers,
            keywords: [.display, .space]
        ),
        SettingsSearchEntry(
            anchor: .separatorColor,
            section: Localization.labelSpaces,
            title: Localization.labelSeparator,
            subtitle: Localization.tipSeparator,
            keywords: [.display, .color]
        ),
        SettingsSearchEntry(
            anchor: .separatorStyle,
            section: Localization.labelSpaces,
            title: Localization.labelSeparatorStyle,
            subtitle: Localization.tipSeparatorStyle,
            keywords: [.display, .icon]
        ),
        SettingsSearchEntry(
            anchor: .iconSize,
            section: Localization.labelAppearance,
            title: Localization.menuIcon,
            subtitle: Localization.tipIconSize,
            keywords: [.size, .icon]
        ),
        SettingsSearchEntry(
            anchor: .iconPadding,
            section: Localization.labelAppearance,
            title: Localization.menuPadding,
            subtitle: Localization.tipIconPadding,
            keywords: [.size]
        ),
        SettingsSearchEntry(
            anchor: .localSpaceNumbers,
            section: Localization.labelAppearance,
            title: Localization.toggleLocalSpaceNumbers,
            subtitle: Localization.tipLocalSpaceNumbers,
            keywords: [.space, .display]
        ),
        SettingsSearchEntry(
            anchor: .fullscreenLetter,
            section: Localization.labelAppearance,
            title: Localization.toggleUseFForFullscreenApps,
            subtitle: Localization.tipUseFForFullscreenApps,
            keywords: [.fullscreen, .icon]
        ),
        SettingsSearchEntry(
            anchor: .shrinkToFit,
            section: Localization.labelBehavior,
            title: Localization.toggleShrinkToFit,
            subtitle: String(format: Localization.tipShrinkToFit, AppInfo.appName),
            keywords: [.size, .hide]
        ),
        SettingsSearchEntry(
            anchor: .hideSingleSpace,
            section: Localization.labelBehavior,
            title: Localization.toggleHideSingleSpace,
            subtitle: Localization.tipHideSingleSpace,
            keywords: [.hide, .space]
        ),
        SettingsSearchEntry(
            anchor: .spacePickerIcons,
            section: Localization.labelBehavior,
            title: Localization.labelPickerAppIcons,
            subtitle: Localization.tipPickerAppIcons,
            keywords: [.icon, .space, .window]
        ),
        SettingsSearchEntry(
            anchor: .spacePickerStyle,
            section: Localization.labelBehavior,
            title: Localization.labelPickerStyle,
            subtitle: Localization.tipPickerStyle,
            keywords: [.icon, .space]
        ),
    ]

    // MARK: - Spaces

    private static let spaces: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            anchor: .preview,
            section: nil,
            title: Localization.labelPreview,
            subtitle: Localization.tipCopyTo,
            keywords: [.icon]
        ),
        SettingsSearchEntry(
            anchor: .symbolColor,
            section: Localization.menuColor,
            title: Localization.labelSymbolForeground,
            subtitle: nil,
            keywords: [.color, .icon]
        ),
        SettingsSearchEntry(
            anchor: .symbolBackground,
            section: Localization.menuColor,
            title: Localization.labelSymbolBackground,
            subtitle: nil,
            keywords: [.color, .icon]
        ),
        SettingsSearchEntry(
            anchor: .foregroundColor,
            section: Localization.menuColor,
            title: Localization.labelNumberForeground,
            subtitle: nil,
            keywords: [.color]
        ),
        SettingsSearchEntry(
            anchor: .backgroundColor,
            section: Localization.menuColor,
            title: Localization.labelNumberBackground,
            subtitle: nil,
            keywords: [.color]
        ),
        SettingsSearchEntry(
            anchor: .invertColors,
            section: Localization.menuColor,
            title: Localization.actionInvertColors,
            subtitle: Localization.tipInvertColors,
            keywords: [.color]
        ),
        SettingsSearchEntry(
            anchor: .font,
            section: Localization.labelFont,
            title: Localization.labelFont,
            subtitle: Localization.tipFont,
            keywords: [.font, .size]
        ),
        SettingsSearchEntry(
            anchor: .numberStyle,
            section: Localization.menuNumber,
            title: Localization.menuNumber,
            subtitle: nil,
            keywords: [.icon, .space]
        ),
        SettingsSearchEntry(
            anchor: .spaceLabel,
            section: Localization.menuLabel,
            title: Localization.menuLabel,
            subtitle: Localization.tipLabelInput,
            keywords: [.label, .space]
        ),
        SettingsSearchEntry(
            anchor: .symbolPosition,
            section: Localization.menuLabel,
            title: Localization.labelSymbolPosition,
            subtitle: nil,
            keywords: [.icon, .label]
        ),
        SettingsSearchEntry(
            anchor: .symbolWrap,
            section: Localization.menuLabel,
            title: Localization.labelSymbolWrap,
            subtitle: nil,
            keywords: [.icon, .label]
        ),
        SettingsSearchEntry(
            anchor: .symbolGap,
            section: Localization.menuLabel,
            title: Localization.menuPadding,
            subtitle: nil,
            keywords: [.size, .icon]
        ),
        SettingsSearchEntry(
            anchor: .badge,
            section: Localization.menuBadge,
            title: Localization.menuBadge,
            subtitle: Localization.tipBadgeInput,
            keywords: [.label, .icon]
        ),
        SettingsSearchEntry(
            anchor: .badgePosition,
            section: Localization.menuBadge,
            title: Localization.labelBadgePosition,
            subtitle: Localization.tipBadgePosition,
            keywords: [.icon]
        ),
        SettingsSearchEntry(
            anchor: .symbol,
            section: Localization.labelGlyph,
            title: Localization.menuSymbol,
            subtitle: nil,
            keywords: [.icon]
        ),
        SettingsSearchEntry(
            anchor: .emoji,
            section: Localization.labelGlyph,
            title: Localization.menuEmoji,
            subtitle: nil,
            keywords: [.emoji, .icon]
        ),
        SettingsSearchEntry(
            anchor: .skinTone,
            section: Localization.labelGlyph,
            title: Localization.labelSkinTone,
            subtitle: nil,
            keywords: [.emoji]
        ),
        SettingsSearchEntry(
            anchor: .sound,
            section: Localization.menuSound,
            title: Localization.menuSound,
            subtitle: Localization.tipSound,
            keywords: [.sound]
        ),
        SettingsSearchEntry(
            anchor: .customSounds,
            section: Localization.menuSound,
            title: Localization.soundCustom,
            subtitle: nil,
            keywords: [.sound]
        ),
    ]

    // MARK: - Mouse

    private static let mouse: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            anchor: .accessibility,
            section: nil,
            title: Localization.alertAccessibilityRequired,
            subtitle: Localization.bannerAccessibilityDetail,
            keywords: [.permission]
        ),
        SettingsSearchEntry(
            anchor: .clickToSwitch,
            section: Localization.labelClick,
            title: Localization.toggleClickToSwitchSpaces,
            subtitle: Localization.tipClickToSwitchSpaces,
            keywords: [.pointer, .space]
        ),
        SettingsSearchEntry(
            anchor: .verticalScroll,
            section: Localization.menuScroll,
            title: Localization.labelVertical,
            subtitle: Localization.tipScrollEnabled,
            keywords: [.pointer]
        ),
        // The two invert rows share a title, so each takes its axis as the
        // section rather than the card they both sit on
        SettingsSearchEntry(
            anchor: .invertVerticalScroll,
            section: Localization.labelVertical,
            title: Localization.toggleScrollInverted,
            subtitle: Localization.tipScrollInverted,
            keywords: [.pointer]
        ),
        SettingsSearchEntry(
            anchor: .horizontalScroll,
            section: Localization.menuScroll,
            title: Localization.labelHorizontal,
            subtitle: Localization.tipScrollEnabled,
            keywords: [.pointer]
        ),
        SettingsSearchEntry(
            anchor: .invertHorizontalScroll,
            section: Localization.labelHorizontal,
            title: Localization.toggleScrollInverted,
            subtitle: Localization.tipScrollInverted,
            keywords: [.pointer]
        ),
        SettingsSearchEntry(
            anchor: .classicSwitching,
            section: Localization.labelBehavior,
            title: Localization.toggleClassicSwitching,
            subtitle: Localization.tipClassicSwitching,
            keywords: [.space, .hotkey]
        ),
        SettingsSearchEntry(
            anchor: .scrollWrapAround,
            section: Localization.labelBehavior,
            title: Localization.toggleScrollWrapAround,
            subtitle: Localization.tipScrollWrapAround,
            keywords: [.pointer, .space]
        ),
        SettingsSearchEntry(
            anchor: .scrollSensitivity,
            section: Localization.labelBehavior,
            title: Localization.labelSensitivity,
            subtitle: Localization.tipSensitivity,
            keywords: [.pointer]
        ),
        SettingsSearchEntry(
            anchor: .scrollHaptics,
            section: Localization.labelBehavior,
            title: Localization.toggleScrollHapticFeedback,
            subtitle: Localization.tipScrollHapticFeedback,
            keywords: [.haptics, .pointer]
        ),
    ]

    // MARK: - Keyboard

    private static let keyboard: [SettingsSearchEntry] = [
        // The direction rows share bare Left/Right/Previous titles, so each
        // takes the switch card as its section, mirroring the scroll invert rows
        SettingsSearchEntry(
            anchor: .hotkeySwitchPrevious,
            section: Localization.labelSwitch,
            title: Localization.labelPrevious,
            subtitle: Localization.tipHotkeySwitchPrevious,
            keywords: [.hotkey, .space]
        ),
        SettingsSearchEntry(
            anchor: .hotkeySwitchLeft,
            section: Localization.labelSwitch,
            title: Localization.labelLeft,
            subtitle: Localization.tipHotkeySwitchLeft,
            keywords: [.hotkey, .space]
        ),
        SettingsSearchEntry(
            anchor: .hotkeySwitchRight,
            section: Localization.labelSwitch,
            title: Localization.labelRight,
            subtitle: Localization.tipHotkeySwitchRight,
            keywords: [.hotkey, .space]
        ),
        SettingsSearchEntry(
            anchor: .hotkeySkipEmptySpaces,
            section: Localization.labelSwitch,
            title: Localization.toggleSkipEmptySpaces,
            subtitle: Localization.tipSkipEmptySpaces,
            keywords: [.hotkey, .space]
        ),
        SettingsSearchEntry(
            anchor: .hotkeySendLeft,
            section: Localization.labelWindow,
            title: Localization.labelSendLeft,
            subtitle: Localization.tipHotkeySendLeft,
            keywords: [.hotkey, .window, .space]
        ),
        SettingsSearchEntry(
            anchor: .hotkeySendRight,
            section: Localization.labelWindow,
            title: Localization.labelSendRight,
            subtitle: Localization.tipHotkeySendRight,
            keywords: [.hotkey, .window, .space]
        ),
        SettingsSearchEntry(
            anchor: .hotkeyMoveLeft,
            section: Localization.labelWindow,
            title: Localization.labelMoveLeft,
            subtitle: Localization.tipHotkeyMoveLeft,
            keywords: [.hotkey, .window, .space]
        ),
        SettingsSearchEntry(
            anchor: .hotkeyMoveRight,
            section: Localization.labelWindow,
            title: Localization.labelMoveRight,
            subtitle: Localization.tipHotkeyMoveRight,
            keywords: [.hotkey, .window, .space]
        ),
        SettingsSearchEntry(
            anchor: .hotkeyWindowSkipEmptySpaces,
            section: Localization.labelWindow,
            title: Localization.toggleSkipEmptySpaces,
            subtitle: Localization.tipWindowSkipEmptySpaces,
            keywords: [.hotkey, .window, .space]
        ),
        SettingsSearchEntry(
            anchor: .jump,
            section: nil,
            title: Localization.labelJump,
            subtitle: nil,
            keywords: [.hotkey, .space]
        ),
    ]

    // MARK: - Matching

    /// The settings a query names, best match first, capped at
    /// `resultLimit`. An empty or whitespace-only query matches nothing:
    /// there is nothing to rank, and the field offers `browseEntries`
    /// instead of guessing.
    static func results(for query: String) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }
        let scored = entries.compactMap { entry -> (entry: SettingsSearchEntry, score: Int)? in
            guard let score = score(entry, query: trimmed) else {
                return nil
            }
            return (entry, score)
        }
        // Ties keep index order, which groups a pane's rows the way the pane
        // itself does rather than shuffling them per keystroke
        return scored
            .enumerated()
            .sorted { ($0.element.score, $1.offset) > ($1.element.score, $0.offset) }
            .prefix(resultLimit)
            .map(\.element.entry)
    }

    /// How well an entry answers a query, or nil when it does not. Stronger
    /// fields win over weaker ones, and a word a field starts with beats one
    /// buried in it, so typing "hide" leads with the rows named "Hide ...".
    private static func score(_ entry: SettingsSearchEntry, query: String) -> Int? {
        var best: Int?
        for field in entry.fields {
            guard let range = field.text.range(
                of: query, options: [.caseInsensitive, .diacriticInsensitive]
            ) else {
                continue
            }
            var score = field.weight
            if range.lowerBound == field.text.startIndex {
                score += 5
            } else if field.text[..<range.lowerBound].last?.isLetter == false {
                score += 3
            }
            best = max(best ?? 0, score)
        }
        return best
    }
}
