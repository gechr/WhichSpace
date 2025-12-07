import Cocoa
import Defaults

// MARK: - Defaults Keys

extension Defaults.Keys {
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
    static let baseIconSize = 20.0
    static let defaultIconSize = baseIconSize * defaultSizeScale / 100.0
    static let baseFontSize = 14.0
    static let baseFontSizeSmall = 12.0
    static let baseFontSizeTiny = 8.0

    static let statusItemWidth = 24.0
    static let statusItemHeight = 22.0
    static let statusItemSize = CGSize(width: statusItemWidth, height: statusItemHeight)
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
    static let launchAtLogin = 100
    static let showAllSpaces = 101
    static let foregroundLabel = 200
    static let foregroundSwatch = 201
    static let colorSeparator = 202
    static let backgroundLabel = 203
    static let backgroundSwatch = 204
    static let gridSwatch = 210
    static let sizeRow = 310
}

// MARK: - Localization

enum Localization {
    static let applyColorToAll = NSLocalizedString("apply_color_to_all", comment: "")
    static let applyColorToAllConfirm = NSLocalizedString("apply_color_to_all_confirm", comment: "")
    static let applyColorToAllDetail = NSLocalizedString("apply_color_to_all_detail", comment: "")
    static let applyColorToAllTip = NSLocalizedString("apply_color_to_all_tip", comment: "")
    static let applyStyleToAll = NSLocalizedString("apply_style_to_all", comment: "")
    static let applyStyleToAllConfirm = NSLocalizedString("apply_style_to_all_confirm", comment: "")
    static let applyStyleToAllDetail = NSLocalizedString("apply_style_to_all_detail", comment: "")
    static let applyStyleToAllTip = NSLocalizedString("apply_style_to_all_tip", comment: "")
    static let applyToAll = NSLocalizedString("apply_to_all", comment: "")
    static let applyToAllConfirm = NSLocalizedString("apply_to_all_confirm", comment: "")
    static let applyToAllDetail = NSLocalizedString("apply_to_all_detail", comment: "")
    static let applyToAllTip = NSLocalizedString("apply_to_all_tip", comment: "")
    static let backgroundLabel = NSLocalizedString("background_label", comment: "")
    static let cancelButton = NSLocalizedString("cancel_button", comment: "")
    static let checkForUpdates = NSLocalizedString("check_for_updates", comment: "")
    static let checkForUpdatesTip = NSLocalizedString("check_for_updates_tip", comment: "")
    static let colorTitle = NSLocalizedString("color_menu_title", comment: "")
    static let foregroundLabel = NSLocalizedString("foreground_label", comment: "")
    static let invertColors = NSLocalizedString("invert_colors", comment: "")
    static let invertColorsTip = NSLocalizedString("invert_colors_tip", comment: "")
    static let launchAtLogin = NSLocalizedString("launch_at_login", comment: "")
    static let launchAtLoginTip = NSLocalizedString("launch_at_login_tip", comment: "")
    static let numberTitle = NSLocalizedString("number_menu_title", comment: "")
    static let okButton = NSLocalizedString("ok_button", comment: "")
    static let quit = NSLocalizedString("quit", comment: "")
    static let quitTip = NSLocalizedString("quit_tip", comment: "")
    static let resetAllButton = NSLocalizedString("reset_all_button", comment: "")
    static let resetAllSpacesConfirm = NSLocalizedString("reset_all_spaces_confirm", comment: "")
    static let resetAllSpacesDetail = NSLocalizedString("reset_all_spaces_detail", comment: "")
    static let resetAllSpacesToDefault = NSLocalizedString("reset_all_spaces_to_default", comment: "")
    static let resetAllSpacesToDefaultTip = NSLocalizedString("reset_all_spaces_to_default_tip", comment: "")
    static let resetButton = NSLocalizedString("reset_button", comment: "")
    static let resetColorConfirm = NSLocalizedString("reset_color_confirm", comment: "")
    static let resetColorDetail = NSLocalizedString("reset_color_detail", comment: "")
    static let resetColorToDefault = NSLocalizedString("reset_color_to_default", comment: "")
    static let resetColorToDefaultTip = NSLocalizedString("reset_color_to_default_tip", comment: "")
    static let resetSpaceConfirm = NSLocalizedString("reset_space_confirm", comment: "")
    static let resetSpaceDetail = NSLocalizedString("reset_space_detail", comment: "")
    static let resetSpaceToDefault = NSLocalizedString("reset_space_to_default", comment: "")
    static let resetSpaceToDefaultTip = NSLocalizedString("reset_space_to_default_tip", comment: "")
    static let resetStyleConfirm = NSLocalizedString("reset_style_confirm", comment: "")
    static let resetStyleDetail = NSLocalizedString("reset_style_detail", comment: "")
    static let resetStyleToDefault = NSLocalizedString("reset_style_to_default", comment: "")
    static let resetStyleToDefaultTip = NSLocalizedString("reset_style_to_default_tip", comment: "")
    static let showAllSpaces = NSLocalizedString("show_all_spaces", comment: "")
    static let showAllSpacesTip = NSLocalizedString("show_all_spaces_tip", comment: "")
    static let sizeTitle = NSLocalizedString("size_menu_title", comment: "")
    static let styleTitle = NSLocalizedString("style_menu_title", comment: "")
    static let symbolTitle = NSLocalizedString("symbol_menu_title", comment: "")
}
