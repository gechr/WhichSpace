import Cocoa
import Defaults

// MARK: - Defaults Keys

extension Defaults.Keys {
    static let showAllSpaces = Key<Bool>("showAllSpaces", default: false)
    static let spaceColors = Key<[Int: SpaceColors]>("spaceColors", default: [:])
    static let spaceIconStyles = Key<[Int: IconStyle]>("spaceIconStyles", default: [:])
    static let spaceSFSymbols = Key<[Int: String]>("spaceSFSymbols", default: [:])
}

// MARK: - Labels

enum Labels {
    static let fullscreen = "F"
}

// MARK: - Layout

enum Layout {
    static let iconSize = 20.0
    static let statusItemWidth = 24.0
    static let statusItemHeight = 22.0
    static let statusItemSize = CGSize(width: statusItemWidth, height: statusItemHeight)
    static let menuFontSize = 13.0

    enum Icon {
        static let cornerRadius = 4.0
        static let fontSize = 14.0
        static let fontSizeSmall = 12.0
        static let fontSizeTiny = 8.0
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

// MARK: - Localization

enum Localization {
    static let applyColorToAll = NSLocalizedString("apply_color_to_all", comment: "")
    static let applyColorToAllTip = NSLocalizedString("apply_color_to_all_tip", comment: "")
    static let applyStyleToAll = NSLocalizedString("apply_style_to_all", comment: "")
    static let applyStyleToAllTip = NSLocalizedString("apply_style_to_all_tip", comment: "")
    static let applyToAll = NSLocalizedString("apply_to_all", comment: "")
    static let applyToAllTip = NSLocalizedString("apply_to_all_tip", comment: "")
    static let backgroundLabel = NSLocalizedString("background_label", comment: "")
    static let colorTitle = NSLocalizedString("color_menu_title", comment: "")
    static let foregroundLabel = NSLocalizedString("foreground_label", comment: "")
    static let invertColors = NSLocalizedString("invert_colors", comment: "")
    static let invertColorsTip = NSLocalizedString("invert_colors_tip", comment: "")
    static let launchAtLogin = NSLocalizedString("launch_at_login", comment: "")
    static let numberTitle = NSLocalizedString("number_menu_title", comment: "")
    static let resetColorToDefault = NSLocalizedString("reset_color_to_default", comment: "")
    static let resetColorToDefaultTip = NSLocalizedString("reset_color_to_default_tip", comment: "")
    static let resetAllSpacesToDefault = NSLocalizedString("reset_all_spaces_to_default", comment: "")
    static let resetAllSpacesToDefaultTip = NSLocalizedString("reset_all_spaces_to_default_tip", comment: "")
    static let resetSpaceToDefault = NSLocalizedString("reset_space_to_default", comment: "")
    static let resetSpaceToDefaultTip = NSLocalizedString("reset_space_to_default_tip", comment: "")
    static let resetStyleToDefault = NSLocalizedString("reset_style_to_default", comment: "")
    static let resetStyleToDefaultTip = NSLocalizedString("reset_style_to_default_tip", comment: "")
    static let showAllSpaces = NSLocalizedString("show_all_spaces", comment: "")
    static let styleTitle = NSLocalizedString("style_menu_title", comment: "")
    static let symbolTitle = NSLocalizedString("symbol_menu_title", comment: "")
}
