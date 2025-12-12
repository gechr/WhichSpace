import Cocoa
import Defaults

// MARK: - Defaults Keys

extension Defaults.Keys {
    static let clickToSwitchSpaces = Key<Bool>("clickToSwitchSpaces", default: false)
    static let dimInactiveSpaces = Key<Bool>("dimInactiveSpaces", default: true)
    static let hideEmptySpaces = Key<Bool>("hideEmptySpaces", default: false)
    static let hideFullscreenApps = Key<Bool>("hideFullscreenApps", default: false)
    static let separatorColor = Key<Data?>("separatorColor", default: nil)
    static let showAllDisplays = Key<Bool>("showAllDisplays", default: false)
    static let showAllSpaces = Key<Bool>("showAllSpaces", default: false)
    static let spaceColors = Key<[Int: SpaceColors]>("spaceColors", default: [:])
    static let spaceIconStyles = Key<[Int: IconStyle]>("spaceIconStyles", default: [:])
    static let spaceSFSymbols = Key<[Int: String]>("spaceSFSymbols", default: [:])

    /// Size preferences
    static let sizeScale = Key<Double>("sizeScale", default: Layout.defaultSizeScale)
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
        static let triangleCornerRadius = 4.5
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

enum MenuTag {
    static let backgroundLabel = 1
    static let backgroundSwatch = 2
    static let clickToSwitchSpaces = 19
    static let colorSeparator = 3
    static let dimInactiveSpaces = 4
    static let foregroundLabel = 5
    static let foregroundSwatch = 6
    static let hideEmptySpaces = 7
    static let hideFullscreenApps = 17
    static let launchAtLogin = 8
    static let showAllDisplays = 13
    static let showAllSpaces = 9
    static let sizeRow = 10
    static let separatorColorDivider = 18
    static let separatorLabel = 15
    static let separatorSwatch = 16
    static let symbolColorSwatch = 11
    static let symbolLabel = 14
    static let uniqueIconsPerDisplay = 12
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
    static let labelSymbol = NSLocalizedString("label_symbol", comment: "")
    static let menuColor = NSLocalizedString("menu_color", comment: "")
    static let menuNumber = NSLocalizedString("menu_number", comment: "")
    static let menuSize = NSLocalizedString("menu_size", comment: "")
    static let menuStyle = NSLocalizedString("menu_style", comment: "")
    static let menuSymbol = NSLocalizedString("menu_symbol", comment: "")
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
    static let toggleShowAllDisplays = NSLocalizedString("toggle_show_all_displays", comment: "")
    static let toggleShowAllSpaces = NSLocalizedString("toggle_show_all_spaces", comment: "")
    static let toggleUniqueIconsPerDisplay = NSLocalizedString("toggle_unique_icons_per_display", comment: "")
    static let yabaiRequiredDetail = NSLocalizedString("yabai_required_detail", comment: "")
    static let yabaiRequiredTitle = NSLocalizedString("yabai_required_title", comment: "")
}
