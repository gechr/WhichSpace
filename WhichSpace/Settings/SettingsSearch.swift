import Foundation

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
    /// `displays` names the Spaces pane's display picker, which registers
    /// no anchor of its own and appears only with several displays attached,
    /// and the section anchors name whole cards whose rows are each listed
    /// already.
    static let unlisted: Set<SettingsAnchor> = [
        .uniqueIconsPerDisplay, .displays, .behavior, .click, .scroll,
    ]

    /// How many results the field offers at once. Past this the list stops
    /// being scannable, and a query that vague is better narrowed.
    static let resultLimit = 8

    static let entries: [SettingsSearchEntry] = general + menuBar + spaces + mouse + keyboard

    // MARK: - General

    private static let general: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            anchor: .launchAtLogin,
            section: nil,
            title: Localization.toggleLaunchAtLogin,
            subtitle: String(format: Localization.tipLaunchAtLogin, AppInfo.appName)
        ),
        SettingsSearchEntry(
            anchor: .autoCheckUpdates,
            section: nil,
            title: Localization.toggleAutoCheckUpdates,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .autoInstallUpdates,
            section: nil,
            title: Localization.toggleAutoInstallUpdates,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .checkForUpdates,
            section: nil,
            title: Localization.actionCheckForUpdates,
            subtitle: String(format: Localization.tipCheckForUpdates, AppInfo.appName)
        ),
        SettingsSearchEntry(
            anchor: .backup,
            section: nil,
            title: Localization.labelBackup,
            subtitle: Localization.tipBackup
        ),
        SettingsSearchEntry(
            anchor: .resetSettings,
            section: nil,
            title: Localization.labelResetSettings,
            subtitle: Localization.tipResetSettings
        ),
    ]

    // MARK: - Menu Bar

    private static let menuBar: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            anchor: .showAllSpaces,
            section: Localization.labelSpaces,
            title: Localization.toggleShowAllSpaces,
            subtitle: Localization.tipShowAllSpaces
        ),
        SettingsSearchEntry(
            anchor: .dimInactiveSpaces,
            section: Localization.labelSpaces,
            title: Localization.toggleDimInactiveSpaces,
            subtitle: Localization.tipDimInactiveSpaces
        ),
        SettingsSearchEntry(
            anchor: .hideEmptySpaces,
            section: Localization.labelSpaces,
            title: Localization.toggleHideEmptySpaces,
            subtitle: Localization.tipHideEmptySpaces
        ),
        SettingsSearchEntry(
            anchor: .hideFullscreenApps,
            section: Localization.labelSpaces,
            title: Localization.toggleHideFullscreenApps,
            subtitle: Localization.tipHideFullscreenApps
        ),
        SettingsSearchEntry(
            anchor: .showAllDisplays,
            section: Localization.labelSpaces,
            title: Localization.toggleShowAllDisplays,
            subtitle: Localization.tipShowAllDisplays
        ),
        SettingsSearchEntry(
            anchor: .separatorColor,
            section: Localization.labelSpaces,
            title: Localization.labelSeparator,
            subtitle: Localization.tipSeparator
        ),
        SettingsSearchEntry(
            anchor: .separatorStyle,
            section: Localization.labelSpaces,
            title: Localization.labelSeparatorStyle,
            subtitle: Localization.tipSeparatorStyle
        ),
        SettingsSearchEntry(
            anchor: .iconSize,
            section: Localization.labelAppearance,
            title: Localization.menuIcon,
            subtitle: Localization.tipIconSize
        ),
        SettingsSearchEntry(
            anchor: .iconPadding,
            section: Localization.labelAppearance,
            title: Localization.menuPadding,
            subtitle: Localization.tipIconPadding
        ),
        SettingsSearchEntry(
            anchor: .localSpaceNumbers,
            section: Localization.labelAppearance,
            title: Localization.toggleLocalSpaceNumbers,
            subtitle: Localization.tipLocalSpaceNumbers
        ),
        SettingsSearchEntry(
            anchor: .fullscreenLetter,
            section: Localization.labelAppearance,
            title: Localization.toggleUseFForFullscreenApps,
            subtitle: Localization.tipUseFForFullscreenApps
        ),
        SettingsSearchEntry(
            anchor: .shrinkToFit,
            section: Localization.labelBehavior,
            title: Localization.toggleShrinkToFit,
            subtitle: String(format: Localization.tipShrinkToFit, AppInfo.appName)
        ),
        SettingsSearchEntry(
            anchor: .hideSingleSpace,
            section: Localization.labelBehavior,
            title: Localization.toggleHideSingleSpace,
            subtitle: Localization.tipHideSingleSpace
        ),
    ]

    // MARK: - Spaces

    private static let spaces: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            anchor: .preview,
            section: nil,
            title: Localization.labelPreview,
            subtitle: Localization.tipCopyTo
        ),
        SettingsSearchEntry(
            anchor: .symbolColor,
            section: Localization.menuColor,
            title: Localization.labelSymbolForeground,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .symbolBackground,
            section: Localization.menuColor,
            title: Localization.labelSymbolBackground,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .foregroundColor,
            section: Localization.menuColor,
            title: Localization.labelNumberForeground,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .backgroundColor,
            section: Localization.menuColor,
            title: Localization.labelNumberBackground,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .invertColors,
            section: Localization.menuColor,
            title: Localization.actionInvertColors,
            subtitle: Localization.tipInvertColors
        ),
        SettingsSearchEntry(
            anchor: .font,
            section: Localization.labelFont,
            title: Localization.labelFont,
            subtitle: Localization.tipFont
        ),
        SettingsSearchEntry(
            anchor: .numberStyle,
            section: Localization.menuNumber,
            title: Localization.menuNumber,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .spaceLabel,
            section: Localization.menuLabel,
            title: Localization.menuLabel,
            subtitle: Localization.tipLabelInput
        ),
        SettingsSearchEntry(
            anchor: .symbolPosition,
            section: Localization.menuLabel,
            title: Localization.labelSymbolPosition,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .symbolWrap,
            section: Localization.menuLabel,
            title: Localization.labelSymbolWrap,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .symbolGap,
            section: Localization.menuLabel,
            title: Localization.menuPadding,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .badge,
            section: Localization.menuBadge,
            title: Localization.menuBadge,
            subtitle: Localization.tipBadgeInput
        ),
        SettingsSearchEntry(
            anchor: .badgePosition,
            section: Localization.menuBadge,
            title: Localization.labelBadgePosition,
            subtitle: Localization.tipBadgePosition
        ),
        SettingsSearchEntry(
            anchor: .symbol,
            section: Localization.labelGlyph,
            title: Localization.menuSymbol,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .emoji,
            section: Localization.labelGlyph,
            title: Localization.menuEmoji,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .skinTone,
            section: Localization.labelGlyph,
            title: Localization.labelSkinTone,
            subtitle: nil
        ),
        SettingsSearchEntry(
            anchor: .sound,
            section: Localization.menuSound,
            title: Localization.menuSound,
            subtitle: Localization.tipSound
        ),
        SettingsSearchEntry(
            anchor: .customSounds,
            section: Localization.menuSound,
            title: Localization.soundCustom,
            subtitle: nil
        ),
    ]

    // MARK: - Mouse

    private static let mouse: [SettingsSearchEntry] = [
        SettingsSearchEntry(
            anchor: .accessibility,
            section: nil,
            title: Localization.alertAccessibilityRequired,
            subtitle: Localization.bannerAccessibilityDetail
        ),
        SettingsSearchEntry(
            anchor: .clickToSwitch,
            section: Localization.labelClick,
            title: Localization.toggleClickToSwitchSpaces,
            subtitle: Localization.tipClickToSwitchSpaces
        ),
        SettingsSearchEntry(
            anchor: .verticalScroll,
            section: Localization.menuScroll,
            title: Localization.labelVertical,
            subtitle: Localization.tipScrollEnabled
        ),
        // The two invert rows share a title, so each takes its axis as the
        // section rather than the card they both sit on
        SettingsSearchEntry(
            anchor: .invertVerticalScroll,
            section: Localization.labelVertical,
            title: Localization.toggleScrollInverted,
            subtitle: Localization.tipScrollInverted
        ),
        SettingsSearchEntry(
            anchor: .horizontalScroll,
            section: Localization.menuScroll,
            title: Localization.labelHorizontal,
            subtitle: Localization.tipScrollEnabled
        ),
        SettingsSearchEntry(
            anchor: .invertHorizontalScroll,
            section: Localization.labelHorizontal,
            title: Localization.toggleScrollInverted,
            subtitle: Localization.tipScrollInverted
        ),
        SettingsSearchEntry(
            anchor: .classicSwitching,
            section: Localization.labelBehavior,
            title: Localization.toggleClassicSwitching,
            subtitle: Localization.tipClassicSwitching
        ),
        SettingsSearchEntry(
            anchor: .scrollWrapAround,
            section: Localization.labelBehavior,
            title: Localization.toggleScrollWrapAround,
            subtitle: Localization.tipScrollWrapAround
        ),
        SettingsSearchEntry(
            anchor: .scrollSensitivity,
            section: Localization.labelBehavior,
            title: Localization.labelSensitivity,
            subtitle: Localization.tipSensitivity
        ),
        SettingsSearchEntry(
            anchor: .scrollHaptics,
            section: Localization.labelBehavior,
            title: Localization.toggleScrollHapticFeedback,
            subtitle: Localization.tipScrollHapticFeedback
        ),
    ]

    // MARK: - Keyboard

    private static let keyboard: [SettingsSearchEntry] = [
        // The direction rows share bare Left/Right/Previous titles, so each
        // takes the switch card as its section, mirroring the scroll invert rows
        SettingsSearchEntry(
            anchor: .hotkeySwitchLeft,
            section: Localization.labelSwitch,
            title: Localization.labelLeft,
            subtitle: Localization.tipHotkeySwitchLeft
        ),
        SettingsSearchEntry(
            anchor: .hotkeySwitchRight,
            section: Localization.labelSwitch,
            title: Localization.labelRight,
            subtitle: Localization.tipHotkeySwitchRight
        ),
        SettingsSearchEntry(
            anchor: .hotkeySwitchPrevious,
            section: Localization.labelSwitch,
            title: Localization.labelPrevious,
            subtitle: Localization.tipHotkeySwitchPrevious
        ),
        SettingsSearchEntry(
            anchor: .hotkeySendLeft,
            section: Localization.labelWindow,
            title: Localization.labelSendLeft,
            subtitle: Localization.tipHotkeySendLeft
        ),
        SettingsSearchEntry(
            anchor: .hotkeySendRight,
            section: Localization.labelWindow,
            title: Localization.labelSendRight,
            subtitle: Localization.tipHotkeySendRight
        ),
        SettingsSearchEntry(
            anchor: .hotkeyMoveLeft,
            section: Localization.labelWindow,
            title: Localization.labelMoveLeft,
            subtitle: Localization.tipHotkeyMoveLeft
        ),
        SettingsSearchEntry(
            anchor: .hotkeyMoveRight,
            section: Localization.labelWindow,
            title: Localization.labelMoveRight,
            subtitle: Localization.tipHotkeyMoveRight
        ),
        SettingsSearchEntry(
            anchor: .jump,
            section: nil,
            title: Localization.labelJump,
            subtitle: nil
        ),
    ]

    // MARK: - Matching

    /// The settings a query names, best match first, capped at
    /// `resultLimit`. An empty or whitespace-only query matches nothing:
    /// the field offers suggestions only once there is something to go on.
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
