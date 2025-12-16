import Cocoa
import Defaults
import EmojiKit

// MARK: - Defaults Keys

extension Defaults.Keys {
    static let clickToSwitchSpaces = Key<Bool>("clickToSwitchSpaces", default: false)
    static let dimInactiveSpaces = Key<Bool>("dimInactiveSpaces", default: true)
    static let emojiPickerSkinTone = Key<SkinTone>("emojiPickerSkinTone", default: .default)
    static let hideEmptySpaces = Key<Bool>("hideEmptySpaces", default: false)
    static let hideFullscreenApps = Key<Bool>("hideFullscreenApps", default: false)
    static let localSpaceNumbers = Key<Bool>("localSpaceNumbers", default: false)
    static let separatorColor = Key<Data?>("separatorColor", default: nil)
    static let showAllDisplays = Key<Bool>("showAllDisplays", default: false)
    static let showAllSpaces = Key<Bool>("showAllSpaces", default: false)
    static let sizeScale = Key<Double>("sizeScale", default: Layout.defaultSizeScale)
    static let spaceColors = Key<[Int: SpaceColors]>("spaceColors", default: [:])
    static let spaceIconStyles = Key<[Int: IconStyle]>("spaceIconStyles", default: [:])
    static let spaceSymbols = Key<[Int: String]>("spaceSymbols", default: [:])
}

// MARK: - Labels

enum Labels {
    static let fullscreen = "F"
}

// MARK: - Layout

enum Layout {
    // Size scale (percentage)
    static let defaultSizeScale = 100.0
    static let sizeScaleRange = 60.0 ... 120.0

    // Base sizes (at 100% scale)
    static let baseSquareSize = 20.0
    static let basePolygonSize = 21.0
    static let defaultIconSize = baseSquareSize * defaultSizeScale / 100.0
    static let baseFontSize = 14.0
    static let baseFontSizeSmall = 12.0
    static let baseFontSizeTiny = 8.0

    static let statusItemWidth = 24.0
    static let statusItemHeight = 22.0
    static let statusItemSize = CGSize(width: statusItemWidth, height: statusItemHeight)
    static let displaySeparatorWidth = 12.0
    static let menuFontSize = 13.0

    enum Icon {
        static let cornerRadius = 4.0
        static let fullscreenSymbolPointSize = 23.0
        static let outlineWidth = 1.5
        static let polygonCornerRadius = 3.0
        static let sfSymbolPointSize = 16.0
        static let triangleCornerRadius = 5.0
    }
}

// MARK: - Icon Colors

enum IconColors {
    static let filledDarkForeground = NSColor(calibratedWhite: 0, alpha: 1)
    static let filledDarkBackground = NSColor(calibratedWhite: 0.7, alpha: 1)
    static let filledLightForeground = NSColor(calibratedWhite: 1, alpha: 1)
    static let filledLightBackground = NSColor(calibratedWhite: 0.3, alpha: 1)
    static let outlineDark = NSColor(calibratedWhite: 0.7, alpha: 1)
    static let outlineLight = NSColor(calibratedWhite: 0.3, alpha: 1)

    static func filledColors(darkMode: Bool) -> (foreground: NSColor, background: NSColor) {
        darkMode
            ? (filledDarkForeground, filledDarkBackground)
            : (filledLightForeground, filledLightBackground)
    }

    static func outlineColors(darkMode: Bool) -> (foreground: NSColor, background: NSColor) {
        let color = darkMode ? outlineDark : outlineLight
        return (color, color)
    }
}

// MARK: - Menu Item Tags

enum MenuTag: Int {
    case backgroundLabel = 1
    case backgroundSwatch
    case clickToSwitchSpaces
    case colorMenuItem
    case colorSeparator
    case dimInactiveSpaces
    case foregroundLabel
    case foregroundSwatch
    case hideEmptySpaces
    case hideFullscreenApps
    case invertColors
    case launchAtLogin
    case localSpaceNumbers
    case separatorColorDivider
    case separatorLabel
    case separatorSwatch
    case showAllDisplays
    case showAllSpaces
    case sizeRow
    case skinToneLabel
    case skinToneSwatch
    case symbolColorSwatch
    case symbolLabel
    case uniqueIconsPerDisplay
}

// MARK: - Localization

enum Localization {
    static let actionApplyColorToAll = NSLocalizedString("action_apply_color_to_all", comment: "")
    static let actionApplyStyleToAll = NSLocalizedString("action_apply_style_to_all", comment: "")
    static let actionApplyToAll = NSLocalizedString("action_apply_to_all", comment: "")
    static let actionCheckForUpdates = NSLocalizedString("action_check_for_updates", comment: "")
    static let actionFont = NSLocalizedString("action_font", comment: "")
    static let actionInvertColors = NSLocalizedString("action_invert_colors", comment: "")
    static let actionQuit = NSLocalizedString("action_quit", comment: "")
    static let actionResetAllSpacesToDefault = NSLocalizedString("action_reset_all_spaces_to_default", comment: "")
    static let actionResetColorToDefault = NSLocalizedString("action_reset_color_to_default", comment: "")
    static let actionResetFontToDefault = NSLocalizedString("action_reset_font_to_default", comment: "")
    static let actionResetSpaceToDefault = NSLocalizedString("action_reset_space_to_default", comment: "")
    static let actionResetStyleToDefault = NSLocalizedString("action_reset_style_to_default", comment: "")
    static let buttonCancel = NSLocalizedString("button_cancel", comment: "")
    static let buttonLearnMore = NSLocalizedString("button_learn_more", comment: "")
    static let buttonOK = NSLocalizedString("button_ok", comment: "")
    static let buttonReset = NSLocalizedString("button_reset", comment: "")
    static let buttonResetAll = NSLocalizedString("button_reset_all", comment: "")
    static let confirmApplyColorToAll = NSLocalizedString("confirm_apply_color_to_all", comment: "")
    static let confirmApplyStyleToAll = NSLocalizedString("confirm_apply_style_to_all", comment: "")
    static let confirmApplyToAll = NSLocalizedString("confirm_apply_to_all", comment: "")
    static let confirmResetAllSpaces = NSLocalizedString("confirm_reset_all_spaces", comment: "")
    static let confirmResetColor = NSLocalizedString("confirm_reset_color", comment: "")
    static let confirmResetFont = NSLocalizedString("confirm_reset_font", comment: "")
    static let confirmResetSpace = NSLocalizedString("confirm_reset_space", comment: "")
    static let confirmResetStyle = NSLocalizedString("confirm_reset_style", comment: "")
    static let detailApplyColorToAll = NSLocalizedString("detail_apply_color_to_all", comment: "")
    static let detailApplyStyleToAll = NSLocalizedString("detail_apply_style_to_all", comment: "")
    static let detailApplyToAll = NSLocalizedString("detail_apply_to_all", comment: "")
    static let detailResetAllSpaces = NSLocalizedString("detail_reset_all_spaces", comment: "")
    static let detailResetColor = NSLocalizedString("detail_reset_color", comment: "")
    static let detailResetFont = NSLocalizedString("detail_reset_font", comment: "")
    static let detailResetSpace = NSLocalizedString("detail_reset_space", comment: "")
    static let detailResetStyle = NSLocalizedString("detail_reset_style", comment: "")
    static let labelNumber = NSLocalizedString("label_number", comment: "")
    static let labelNumberBackground = NSLocalizedString("label_number_background", comment: "")
    static let labelNumberForeground = NSLocalizedString("label_number_foreground", comment: "")
    static let labelSeparator = NSLocalizedString("label_separator", comment: "")
    static let labelSkinTone = NSLocalizedString("label_skin_tone", comment: "")
    static let labelSymbol = NSLocalizedString("label_symbol", comment: "")
    static let menuColor = NSLocalizedString("menu_color", comment: "")
    static let menuEmoji = NSLocalizedString("menu_emoji", comment: "")
    static let menuNumber = NSLocalizedString("menu_number", comment: "")
    static let menuSize = NSLocalizedString("menu_size", comment: "")
    static let menuSound = NSLocalizedString("menu_sound", comment: "")
    static let menuStyle = NSLocalizedString("menu_style", comment: "")
    static let menuSymbol = NSLocalizedString("menu_symbol", comment: "")
    static let soundNone = NSLocalizedString("sound_none", comment: "")
    static let soundSystem = NSLocalizedString("sound_system", comment: "")
    static let soundUser = NSLocalizedString("sound_user", comment: "")
    static let search = NSLocalizedString("search", comment: "")
    static let tipApplyColorToAll = NSLocalizedString("tip_apply_color_to_all", comment: "")
    static let tipApplyStyleToAll = NSLocalizedString("tip_apply_style_to_all", comment: "")
    static let tipApplyToAll = NSLocalizedString("tip_apply_to_all", comment: "")
    static let tipCheckForUpdates = NSLocalizedString("tip_check_for_updates", comment: "")
    static let tipClickToSwitchSpaces = NSLocalizedString("tip_click_to_switch_spaces", comment: "")
    static let tipDimInactiveSpaces = NSLocalizedString("tip_dim_inactive_spaces", comment: "")
    static let tipFont = NSLocalizedString("tip_font", comment: "")
    static let tipHideEmptySpaces = NSLocalizedString("tip_hide_empty_spaces", comment: "")
    static let tipHideFullscreenApps = NSLocalizedString("tip_hide_fullscreen_apps", comment: "")
    static let tipInvertColors = NSLocalizedString("tip_invert_colors", comment: "")
    static let tipLaunchAtLogin = NSLocalizedString("tip_launch_at_login", comment: "")
    static let tipLocalSpaceNumbers = NSLocalizedString("tip_local_space_numbers", comment: "")
    static let tipQuit = NSLocalizedString("tip_quit", comment: "")
    static let tipResetAllSpacesToDefault = NSLocalizedString("tip_reset_all_spaces_to_default", comment: "")
    static let tipResetColorToDefault = NSLocalizedString("tip_reset_color_to_default", comment: "")
    static let tipResetFontToDefault = NSLocalizedString("tip_reset_font_to_default", comment: "")
    static let tipResetSpaceToDefault = NSLocalizedString("tip_reset_space_to_default", comment: "")
    static let tipResetStyleToDefault = NSLocalizedString("tip_reset_style_to_default", comment: "")
    static let tipShowAllDisplays = NSLocalizedString("tip_show_all_displays", comment: "")
    static let tipShowAllSpaces = NSLocalizedString("tip_show_all_spaces", comment: "")
    static let tipUniqueIconsPerDisplay = NSLocalizedString("tip_unique_icons_per_display", comment: "")
    static let toggleClickToSwitchSpaces = NSLocalizedString("toggle_click_to_switch_spaces", comment: "")
    static let toggleDimInactiveSpaces = NSLocalizedString("toggle_dim_inactive_spaces", comment: "")
    static let toggleHideEmptySpaces = NSLocalizedString("toggle_hide_empty_spaces", comment: "")
    static let toggleHideFullscreenApps = NSLocalizedString("toggle_hide_fullscreen_apps", comment: "")
    static let toggleLaunchAtLogin = NSLocalizedString("toggle_launch_at_login", comment: "")
    static let toggleLocalSpaceNumbers = NSLocalizedString("toggle_local_space_numbers", comment: "")
    static let toggleShowAllDisplays = NSLocalizedString("toggle_show_all_displays", comment: "")
    static let toggleShowAllSpaces = NSLocalizedString("toggle_show_all_spaces", comment: "")
    static let toggleUniqueIconsPerDisplay = NSLocalizedString("toggle_unique_icons_per_display", comment: "")
    static let yabaiRequiredDetail = NSLocalizedString("yabai_required_detail", comment: "")
    static let yabaiRequiredTitle = NSLocalizedString("yabai_required_title", comment: "")
}

// MARK: - Skin Tone

/// Represents a skin tone modifier for emojis.
/// - `default`: Yellow/no modifier (Simpson skin tone)
/// - `light` through `dark`: Fitzpatrick skin tone types 1-2 through 6
enum SkinTone: Int, CaseIterable, Codable, Defaults.Serializable {
    case `default` = 0
    case light = 1
    case mediumLight = 2
    case medium = 3
    case mediumDark = 4
    case dark = 5

    /// The Unicode skin tone modifier string, or nil for default (yellow)
    var modifier: String? {
        switch self {
        case .default:
            nil
        case .light:
            "\u{1F3FB}"
        case .mediumLight:
            "\u{1F3FC}"
        case .medium:
            "\u{1F3FD}"
        case .mediumDark:
            "\u{1F3FE}"
        case .dark:
            "\u{1F3FF}"
        }
    }

    /// Creates a SkinTone from a raw index, defaulting to .default if out of bounds
    init(rawValueOrDefault value: Int) {
        self = Self(rawValue: value) ?? .default
    }

    // MARK: - Static Properties

    static let modifiers: [String?] = Self.allCases.map(\.modifier)

    // MARK: - Emoji Modification

    private static let modifierScalars: Set<Unicode.Scalar> = [
        Unicode.Scalar(0x1F3FB)!,
        Unicode.Scalar(0x1F3FC)!,
        Unicode.Scalar(0x1F3FD)!,
        Unicode.Scalar(0x1F3FE)!,
        Unicode.Scalar(0x1F3FF)!,
    ]
    /// Variation Selector 16 - used to request emoji presentation
    private static let vs16 = Unicode.Scalar(0xFE0F)!
    /// Zero Width Joiner - used in complex emoji sequences
    private static let zwj = Unicode.Scalar(0x200D)!

    /// Applies a skin tone modifier to an emoji.
    /// - Parameters:
    ///   - emoji: The emoji to modify
    ///   - tone: The skin tone. If nil, uses the global default from Defaults.
    /// - Returns: The emoji with the skin tone applied
    static func apply(to emoji: String, tone: Self? = nil) -> String {
        let variant = tone ?? Defaults[.emojiPickerSkinTone]
        let stripped = stripModifiers(from: emoji)

        guard let modifier = variant.modifier else {
            // Yellow/default tone - return stripped emoji without any modifier
            return stripped
        }

        guard canApplyModifier(to: stripped) else {
            return emoji
        }

        // For ZWJ sequences, insert modifier after first modifier-base character
        if stripped.unicodeScalars.contains(zwj) {
            return insertModifierAfterFirstBase(in: stripped, modifier: modifier)
        }

        // Simple emoji - just append
        return stripped + modifier
    }

    /// Strips skin tone modifiers and variation selectors from emoji
    private static func stripModifiers(from emoji: String) -> String {
        String(emoji.unicodeScalars.filter { !modifierScalars.contains($0) && $0 != vs16 })
    }

    /// Inserts skin tone modifier after the first modifier-base character in a ZWJ sequence
    private static func insertModifierAfterFirstBase(in emoji: String, modifier: String) -> String {
        var result = ""
        var inserted = false

        for scalar in emoji.unicodeScalars {
            result.unicodeScalars.append(scalar)
            // Insert modifier right after the first modifier-base character
            if !inserted, scalar.properties.isEmojiModifierBase {
                result += modifier
                inserted = true
            }
        }

        return result
    }

    /// Uses EmojiKit's size-based detection to determine if an emoji supports skin tones.
    /// This is more reliable than `isEmojiModifierBase` which has false positives.
    private static func canApplyModifier(to emoji: String) -> Bool {
        Emoji(emoji).hasSkinToneVariants
    }
}
