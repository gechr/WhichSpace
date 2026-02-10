import Cocoa
import Defaults
import EmojiKit

// MARK: - Defaults Keys

extension Defaults.Keys {
    /// Global emoji picker skin tone preference (used by ItemPicker UI)
    static let emojiPickerSkinTone = Key<SkinTone>("emojiPickerSkinTone", default: .default)
}

// MARK: - Labels

enum Labels {
    static let fullscreen = "F"
}

// MARK: - App Info

enum AppInfo {
    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "WhichSpace"
    }

    static var isHomebrewInstall: Bool {
        let caskroomPaths = [
            "/opt/homebrew/Caskroom/whichspace",
            "/usr/local/Caskroom/whichspace",
        ]
        return caskroomPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }
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
    case hideSingleSpace
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
    static let actionApplyColorToAll = String(localized: "action_apply_color_to_all")
    static let actionApplyStyleToAll = String(localized: "action_apply_style_to_all")
    static let actionApplyToAll = String(localized: "action_apply_to_all")
    static let actionCheckForUpdates = String(localized: "action_check_for_updates")
    static let actionExportSettings = String(localized: "action_export_settings")
    static let actionFont = String(localized: "action_font")
    static let actionImportSettings = String(localized: "action_import_settings")
    static let actionInvertColors = String(localized: "action_invert_colors")
    static let actionQuit = String(localized: "action_quit")
    static let actionResetAllSpacesToDefault = String(localized: "action_reset_all_spaces_to_default")
    static let actionResetColorToDefault = String(localized: "action_reset_color_to_default")
    static let actionResetFontToDefault = String(localized: "action_reset_font_to_default")
    static let actionResetSpaceToDefault = String(localized: "action_reset_space_to_default")
    static let actionResetStyleToDefault = String(localized: "action_reset_style_to_default")
    static let alertAccessibilityDetail = String(localized: "alert_accessibility_detail")
    static let alertAccessibilityRequired = String(localized: "alert_accessibility_required")
    static let alertExportFailed = String(localized: "alert_export_failed")
    static let alertImportFailed = String(localized: "alert_import_failed")
    static let buttonCancel = String(localized: "button_cancel")
    static let buttonContinue = String(localized: "button_continue")
    static let buttonLearnMore = String(localized: "button_learn_more")
    static let buttonOK = String(localized: "button_ok")
    static let buttonReset = String(localized: "button_reset")
    static let buttonResetAll = String(localized: "button_reset_all")
    static let confirmApplyColorToAll = String(localized: "confirm_apply_color_to_all")
    static let confirmApplyStyleToAll = String(localized: "confirm_apply_style_to_all")
    static let confirmApplyToAll = String(localized: "confirm_apply_to_all")
    static let confirmResetAllSpaces = String(localized: "confirm_reset_all_spaces")
    static let confirmResetColor = String(localized: "confirm_reset_color")
    static let confirmResetFont = String(localized: "confirm_reset_font")
    static let confirmResetSpace = String(localized: "confirm_reset_space")
    static let confirmResetStyle = String(localized: "confirm_reset_style")
    static let detailApplyColorToAll = String(localized: "detail_apply_color_to_all")
    static let detailApplyStyleToAll = String(localized: "detail_apply_style_to_all")
    static let detailApplyToAll = String(localized: "detail_apply_to_all")
    static let detailResetAllSpaces = String(localized: "detail_reset_all_spaces")
    static let detailResetColor = String(localized: "detail_reset_color")
    static let detailResetFont = String(localized: "detail_reset_font")
    static let detailResetSpace = String(localized: "detail_reset_space")
    static let detailResetStyle = String(localized: "detail_reset_style")
    static let errorBackupDecodingFailed = String(localized: "error_backup_decoding_failed")
    static let errorBackupEncodingFailed = String(localized: "error_backup_encoding_failed")
    static let errorBackupFileReadFailed = String(localized: "error_backup_file_read_failed")
    static let errorBackupFileWriteFailed = String(localized: "error_backup_file_write_failed")
    static let errorBackupInvalidData = String(localized: "error_backup_invalid_data")
    static let labelNumber = String(localized: "label_number")
    static let labelNumberBackground = String(localized: "label_number_background")
    static let labelNumberForeground = String(localized: "label_number_foreground")
    static let labelSeparator = String(localized: "label_separator")
    static let labelSkinTone = String(localized: "label_skin_tone")
    static let labelSymbol = String(localized: "label_symbol")
    static let menuColor = String(localized: "menu_color")
    static let menuEmoji = String(localized: "menu_emoji")
    static let menuNumber = String(localized: "menu_number")
    static let menuSettings = String(localized: "menu_settings")
    static let menuSize = String(localized: "menu_size")
    static let menuSound = String(localized: "menu_sound")
    static let menuStyle = String(localized: "menu_style")
    static let menuSymbol = String(localized: "menu_symbol")
    static let search = String(localized: "search")
    static let soundNone = String(localized: "sound_none")
    static let soundSystem = String(localized: "sound_system")
    static let soundUser = String(localized: "sound_user")
    static let tipApplyColorToAll = String(localized: "tip_apply_color_to_all")
    static let tipApplyStyleToAll = String(localized: "tip_apply_style_to_all")
    static let tipApplyToAll = String(localized: "tip_apply_to_all")
    static let tipCheckForUpdates = String(localized: "tip_check_for_updates")
    static let tipClickToSwitchSpaces = String(localized: "tip_click_to_switch_spaces")
    static let tipDimInactiveSpaces = String(localized: "tip_dim_inactive_spaces")
    static let tipExportSettings = String(localized: "tip_export_settings")
    static let tipFont = String(localized: "tip_font")
    static let tipHideEmptySpaces = String(localized: "tip_hide_empty_spaces")
    static let tipHideFullscreenApps = String(localized: "tip_hide_fullscreen_apps")
    static let tipHideSingleSpace = String(localized: "tip_hide_single_space")
    static let tipImportSettings = String(localized: "tip_import_settings")
    static let tipInvertColors = String(localized: "tip_invert_colors")
    static let tipLaunchAtLogin = String(localized: "tip_launch_at_login")
    static let tipLocalSpaceNumbers = String(localized: "tip_local_space_numbers")
    static let tipQuit = String(localized: "tip_quit")
    static let tipResetAllSpacesToDefault = String(localized: "tip_reset_all_spaces_to_default")
    static let tipResetColorToDefault = String(localized: "tip_reset_color_to_default")
    static let tipResetFontToDefault = String(localized: "tip_reset_font_to_default")
    static let tipResetSpaceToDefault = String(localized: "tip_reset_space_to_default")
    static let tipResetStyleToDefault = String(localized: "tip_reset_style_to_default")
    static let tipShowAllDisplays = String(localized: "tip_show_all_displays")
    static let tipShowAllSpaces = String(localized: "tip_show_all_spaces")
    static let tipUniqueIconsPerDisplay = String(localized: "tip_unique_icons_per_display")
    static let toggleClickToSwitchSpaces = String(localized: "toggle_click_to_switch_spaces")
    static let toggleDimInactiveSpaces = String(localized: "toggle_dim_inactive_spaces")
    static let toggleHideEmptySpaces = String(localized: "toggle_hide_empty_spaces")
    static let toggleHideFullscreenApps = String(localized: "toggle_hide_fullscreen_apps")
    static let toggleHideSingleSpace = String(localized: "toggle_hide_single_space")
    static let toggleLaunchAtLogin = String(localized: "toggle_launch_at_login")
    static let toggleLocalSpaceNumbers = String(localized: "toggle_local_space_numbers")
    static let toggleShowAllDisplays = String(localized: "toggle_show_all_displays")
    static let toggleShowAllSpaces = String(localized: "toggle_show_all_spaces")
    static let toggleUniqueIconsPerDisplay = String(localized: "toggle_unique_icons_per_display")
    static let yabaiRequiredDetail = String(localized: "yabai_required_detail")
    static let yabaiRequiredTitle = String(localized: "yabai_required_title")
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

    static let modifierScalars: Set<Unicode.Scalar> = [
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
