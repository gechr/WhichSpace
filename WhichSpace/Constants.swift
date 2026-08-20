import Cocoa
import Defaults
import EmojiKit

// MARK: - Defaults Keys

extension Defaults.Keys {
    /// Global emoji picker skin tone preference (used by the emoji grid).
    /// Derived from the `KeySpecs` registry so backup and reset stay in sync.
    static let emojiPickerSkinTone = KeySpecs.emojiPickerSkinTone.key(suite: .standard)
}

// MARK: - Labels

enum Labels {
    static let fullscreen = "F"
}

// MARK: - Label Templates

enum LabelTemplate {
    /// Token replaced with the Space number; shown in placeholders and docs.
    static let spaceToken = "{#}"

    /// Longhand synonym for `spaceToken`; resolves identically but is not
    /// shown in the UI, so existing labels keep working.
    static let spaceTokenSynonym = "{number}"

    private static let spaceTokens = [spaceToken, spaceTokenSynonym]

    /// Resolves template tokens in a label string.
    /// `{#}` (and its synonym `{number}`) is replaced with the space number.
    static func resolve(_ label: String, space: Int) -> String {
        spaceTokens.reduce(label) {
            $0.replacingOccurrences(of: $1, with: String(space))
        }
    }

    /// Maximum label content length, excluding template tokens.
    /// Shared by the menu input field and the AppleScript setter.
    static let maxContentLength = 20

    /// Returns the content length of a label, excluding template tokens.
    /// Used for character limit validation in the input field.
    static func contentLength(_ label: String) -> Int {
        spaceTokens.reduce(label) {
            $0.replacingOccurrences(of: $1, with: "")
        }.count
    }

    /// Truncates a label so its content length fits `maxContentLength`,
    /// trimming from the end while preserving complete space tokens.
    /// When `ellipsis` is true and trimming occurred, appends "…" so the
    /// truncation is visible; the ellipsis counts toward the limit.
    static func truncate(_ label: String, ellipsis: Bool = false) -> String {
        guard contentLength(label) > maxContentLength else {
            return label
        }
        let limit = ellipsis ? maxContentLength - 1 : maxContentLength
        var text = label
        while contentLength(text) > limit {
            text = String(text.dropLast())
        }
        return ellipsis ? text + "…" : text
    }
}

// MARK: - Badge Templates

enum BadgeTemplate {
    /// Badge character that renders as the current Space number.
    static let spaceToken = "#"
}

// MARK: - App Info

enum AppInfo {
    static var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "WhichSpace"
    }

    /// Marketing version stamped into the bundle. Development builds carry a
    /// `git describe` suffix, e.g. 1.2.18-1-gfe06204-dirty.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static let repository = "https://github.com/gechr/WhichSpace"

    static var repositoryURL: URL? {
        URL(string: repository)
    }

    /// Release page for the running build, or the release list when the stamp
    /// does not name a tag.
    static var releaseURL: URL? {
        guard let tag = releaseTag(for: version) else {
            return URL(string: "\(repository)/releases")
        }
        return URL(string: "\(repository)/releases/tag/\(tag)")
    }

    /// Tag the given version was built from, so a development build still
    /// points at the release behind it. Returns nil when the stamp is not a
    /// version.
    static func releaseTag(for version: String) -> String? {
        var value = version
        if value.hasSuffix(dirtySuffix) {
            value.removeLast(dirtySuffix.count)
        }
        // The distance from the tag and the commit git describe resolved to
        // are trimmed separately from the tag's own hyphenated parts, so a
        // pre-release tag such as 1.3.0-rc.1 survives intact
        if let range = value.range(of: "-[0-9]+-g[0-9a-f]+$", options: .regularExpression) {
            value.removeSubrange(range)
        }
        guard value.first?.isNumber == true else {
            return nil
        }
        return "v\(value)"
    }

    private static let dirtySuffix = "-dirty"
}

// MARK: - Layout

enum Layout {
    /// Size scale (percentage)
    /// Slider default, leaving the icon at the base sizes below
    static let defaultSizeScale = 100.0
    /// Slider bounds, from a little under the base size to a little over
    static let sizeScaleRange = 60.0 ... 120.0

    /// Padding scale (percentage)
    /// Slider default, leaving the padding at `defaultHorizontalPadding`
    static let defaultPaddingScale = 100.0
    /// Slider bounds, from flush neighbours to double the default padding
    static let paddingScaleRange = 0.0 ... 200.0
    /// Padding scale applied while the icon is shrunk to fit, leaving a point
    /// between neighbouring icons rather than none
    static let shrunkPaddingScale = 25.0

    /// Gap between a combined symbol and label at the 100% slider position, in points
    static let maxSymbolGap = 12.0
    /// Default gap percentage (25% of the maximum = 3 points)
    static let defaultSymbolGapScale = 25.0
    /// Slider bounds, from no gap to the full `maxSymbolGap`
    static let symbolGapScaleRange = 0.0 ... 100.0

    /// Scroll-to-switch sensitivity (percentage)
    /// Slider default, leaving the trackpad threshold at its base value
    static let defaultScrollSensitivity = 100.0
    /// Slider bounds; higher divides the threshold, so less scrolling switches
    static let scrollSensitivityRange = 25.0 ... 200.0
    /// Slider bounds, mapping to the very light through maximum labels
    static let scrollHapticIntensityRange = 1 ... 6
    /// Slider default, the strong tap
    static let defaultScrollHapticIntensity = 4

    /// Space picker menu app icons
    /// App icons shown per picker row before the list is truncated
    static let defaultSpacePickerMaxAppIcons = 5
    /// Slider bounds, where 0 hides the app icons entirely
    static let spacePickerMaxAppIconsRange = 0 ... 10
    /// Point size of the app icons embedded in picker menu item titles
    static let spacePickerAppIconSize = 16.0

    /// Mission Control's per-display Space limit
    static let maxSpacesPerDisplay = 16

    /// Settings window
    /// Width of a pane's content column, inside the padding
    static let settingsPaneContentWidth = 540.0
    /// Inset between a pane's content and the window edge
    static let settingsPanePadding = 16.0
    /// Share of the screen height a settings pane may take before it scrolls
    static let settingsPaneMaxHeightRatio = 0.75
    /// Pane height cap when no screen is available to measure
    static let settingsPaneMaxHeightFallback = 800.0
    /// Vertical gap between the cards stacked in a pane
    static let settingsSectionSpacing = 12.0
    /// Inset from a card's edges to the row's controls
    static let settingsRowHorizontalPadding = 16.0
    /// Space above and below a row's controls
    static let settingsRowVerticalPadding = 8.0
    /// Font size of a row's title
    static let settingsRowFontSize = 13.0
    /// Width reserved for a row's leading symbol, so the titles line up
    static let settingsRowIconWidth = 24.0
    /// Extra leading inset for a row nested under the toggle that governs it
    static let settingsRowIndent = 16.0
    /// Font size of the explanatory line under a row's title
    static let settingsRowSubtitleFontSize = 11.0
    /// Width of a slider's track
    static let settingsSliderWidth = 140.0
    /// Font size of the value label beside a slider
    static let settingsSliderValueFontSize = 11.0
    /// Width reserved for a slider's value label, so the tracks line up
    static let settingsSliderValueWidth = 56.0
    /// Fraction of the track where a slider's default value sits, so defaults
    /// line up across rows whose ranges differ
    static let settingsSliderDefaultPosition = 0.5
    /// Width of the Space list column in the Spaces pane
    static let settingsSpaceListWidth = 140.0
    /// Height at which the Space list starts scrolling instead of growing
    static let settingsSpaceListMaxHeight = 800.0
    /// Height cap on the jump-to-Space recorder list in the Keyboard pane
    static let settingsJumpListMaxHeight = 250.0
    /// Trailing inset a scrolling list leaves for an overlay scroller
    static let settingsSpaceListScrollerWidth = 16.0
    /// Character cap on a custom Space name
    static let settingsSpaceNameMaxLength = 10
    /// Gap between the editor column and the preview card beside it
    static let settingsSpacesEditorGutter = 10.0
    /// Ideal height of the editor's scrolling stack, measured against the
    /// pinned preview card so the column's total holds steady as the card
    /// grows and the Space list keeps deciding how tall the window is
    static let settingsSpacesEditorBaseHeight = 576.0 - settingsSpacesPreviewMinHeight
    /// Total width of the Spaces pane, list column and editor together
    static let settingsSpacesPaneWidth = 680.0
    /// Floor for the preview card, whose stack of actions is one shorter on
    /// the Default Style entry; the card grows past it rather than clipping
    static let settingsSpacesPreviewMinHeight = 132.0
    /// Inset between the preview card and the pane's trailing edge
    static let settingsSpacesPreviewTrailingPadding = 10.0
    /// Size scale the preview icon is rendered at, three times the menu bar
    static let settingsSpacesPreviewScale = 300.0
    /// Slack either side of the icon at 100% padding
    static let defaultHorizontalPadding = statusItemWidth - baseSquareSize // 4.0pt

    /// Base sizes (at 100% scale)
    /// Side of the square icon, and the width every style is measured against
    static let baseSquareSize = 20.0
    /// Width of the polygon styles, a point wider so they read as the same size
    static let basePolygonSize = 21.0
    /// Label font size for a single digit
    static let baseFontSize = 14.0
    /// Label font size for two digits
    static let baseFontSizeSmall = 12.0
    /// Label font size for three digits or more
    static let baseFontSizeTiny = 8.0

    /// Width of the status item drawn for one Space
    static let statusItemWidth = 24.0
    /// Height of the menu bar's drawing area
    static let statusItemHeight = 22.0
    /// Canvas the icons are drawn into
    static let statusItemSize = CGSize(width: statusItemWidth, height: statusItemHeight)
    /// Slot between adjacent displays when every display is shown
    static let displaySeparatorWidth = 12.0
    /// Font size of the glyph separator styles, centred in that slot
    static let separatorGlyphFontSize = 12.0

    enum Icon {
        /// Corner rounding of the square style
        static let cornerRadius = 4.0
        /// Stroke width of the outlined styles
        static let outlineWidth = 1.5
        /// Corner rounding at a polygon's vertices
        static let polygonCornerRadius = 3.0
        /// Point size of an SF Symbol before the size scale is applied
        static let sfSymbolPointSize = 16.0
        /// Corner rounding for the triangle, larger to soften its sharper points
        static let triangleCornerRadius = 5.0
    }
}

enum HapticIntensityLabel {
    static func label(for intensity: Int) -> String {
        switch intensity {
        case 1:
            Localization.labelHapticVeryLight
        case 2:
            Localization.labelHapticLight
        case 3:
            Localization.labelHapticMedium
        case 4:
            Localization.labelHapticStrong
        case 5:
            Localization.labelHapticVeryStrong
        case 6:
            Localization.labelHapticMaximum
        default:
            Localization.labelOff
        }
    }
}

extension Comparable {
    /// Returns the value limited to the given closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
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
    static let separatorDark = NSColor(calibratedWhite: 0.5, alpha: 0.6)
    static let separatorLight = NSColor(calibratedWhite: 0.4, alpha: 0.6)

    static func defaultSeparator(darkMode: Bool) -> NSColor {
        darkMode ? separatorDark : separatorLight
    }

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
    static let accessibilityCurrentSpace = String(localized: "accessibility_current_space")
    static let actionCopyFrom = String(localized: "action_copy_from")
    static let actionCopyTo = String(localized: "action_copy_to")
    static let actionCheckForUpdates = String(localized: "action_check_for_updates")
    static let actionExportSettings = String(localized: "action_export_settings")
    static let actionImportSettings = String(localized: "action_import_settings")
    static let actionInvertColors = String(localized: "action_invert_colors")
    static let actionOpenSystemSettings = String(localized: "action_open_system_settings")
    static let actionQuit = String(localized: "action_quit")
    static let actionReset = String(localized: "action_reset")
    static let actionResetAllSpaces = String(localized: "action_reset_all_spaces")
    static let actionResetAllSpacesToDefault = String(localized: "action_reset_all_spaces_to_default")
    static let actionResetCurrentSpace = String(localized: "action_reset_current_space")
    static let actionRevealInactiveSpaces = String(localized: "action_reveal_inactive_spaces")
    static let actionSetAsDefault = String(localized: "action_set_as_default")
    static let alertAccessibilityDetail = String(localized: "alert_accessibility_detail")
    static let alertAccessibilityRequired = String(localized: "alert_accessibility_required")
    static let alertCustomSoundsDetail = String(localized: "alert_custom_sounds_detail")
    static let alertCustomSoundsTitle = String(localized: "alert_custom_sounds_title")
    static let alertExportFailed = String(localized: "alert_export_failed")
    static let alertImportFailed = String(localized: "alert_import_failed")
    static let alertSpaceSwipeGestureDetail = String(localized: "alert_space_swipe_gesture_detail")
    static let alertSpaceSwipeGestureTitle = String(localized: "alert_space_swipe_gesture_title")
    static let bannerAccessibilityDetail = String(localized: "banner_accessibility_detail")
    static let bannerDefaultStyleDetail = String(localized: "banner_default_style_detail")
    static let buttonCancel = String(localized: "button_cancel")
    static let buttonContinue = String(localized: "button_continue")
    static let buttonCopy = String(localized: "button_copy")
    static let buttonEnableSwipeGestures = String(localized: "button_enable_swipe_gestures")
    static let buttonOK = String(localized: "button_ok")
    static let buttonOpen = String(localized: "button_open")
    static let buttonReset = String(localized: "button_reset")
    static let buttonResetAll = String(localized: "button_reset_all")
    static let buttonSwap = String(localized: "button_swap")
    static let buttonUseClassicSwitching = String(localized: "button_use_classic_switching")
    static let colorBlack = String(localized: "color_black")
    static let colorBlue = String(localized: "color_blue")
    static let colorGreen = String(localized: "color_green")
    static let colorOrange = String(localized: "color_orange")
    static let colorPicker = String(localized: "color_picker")
    static let colorPurple = String(localized: "color_purple")
    static let colorRed = String(localized: "color_red")
    static let colorTransparent = String(localized: "color_transparent")
    static let colorWhite = String(localized: "color_white")
    static let colorYellow = String(localized: "color_yellow")
    static let confirmCopyFromSpace = String(localized: "confirm_copy_from_space")
    static let confirmCopyToAllDisplays = String(localized: "confirm_copy_to_all_displays")
    static let confirmCopyToAllSpaces = String(localized: "confirm_copy_to_all_spaces")
    static let confirmCopyToSpace = String(localized: "confirm_copy_to_space")
    static let confirmCopyToThisDisplay = String(localized: "confirm_copy_to_this_display")
    static let confirmSetDefaultStyle = String(localized: "confirm_set_default_style")
    static let confirmResetAllSpaces = String(localized: "confirm_reset_all_spaces")
    static let confirmResetDefault = String(localized: "confirm_reset_default")
    static let confirmResetSpace = String(localized: "confirm_reset_space")
    static let confirmResetSettings = String(localized: "confirm_reset_settings")
    static let detailCopyFromSpace = String(localized: "detail_copy_from_space")
    static let detailCopyToAllDisplays = String(localized: "detail_copy_to_all_displays")
    static let detailCopyToAllSpaces = String(localized: "detail_copy_to_all_spaces")
    static let detailCopyToSpace = String(localized: "detail_copy_to_space")
    static let detailCopyToThisDisplay = String(localized: "detail_copy_to_this_display")
    static let detailSetDefaultStyle = String(localized: "detail_set_default_style")
    static let detailResetAllSpaces = String(localized: "detail_reset_all_spaces")
    static let detailResetAllSpacesToDefault = String(localized: "detail_reset_all_spaces_to_default")
    static let detailResetDefault = String(localized: "detail_reset_default")
    static let detailResetSpace = String(localized: "detail_reset_space")
    static let detailResetSettings = String(localized: "detail_reset_settings")
    static let errorBackupDecodingFailed = String(localized: "error_backup_decoding_failed")
    static let errorBackupEncodingFailed = String(localized: "error_backup_encoding_failed")
    static let errorBackupFileReadFailed = String(localized: "error_backup_file_read_failed")
    static let errorBackupFileWriteFailed = String(localized: "error_backup_file_write_failed")
    static let errorBackupInvalidData = String(localized: "error_backup_invalid_data")
    static let errorScriptingAccessibilityRequired = String(localized: "error_scripting_accessibility_required")
    static let errorScriptingBadgeSingleCharacter = String(localized: "error_scripting_badge_single_character")
    static let errorScriptingExpectedSpaceNumber = String(localized: "error_scripting_expected_space_number")
    static let errorScriptingMoveFailed = String(localized: "error_scripting_move_failed")
    static let errorScriptingMoveUnsupported = String(localized: "error_scripting_move_unsupported")
    static let errorScriptingNoPreviousSpace = String(localized: "error_scripting_no_previous_space")
    static let errorScriptingNoSpaces = String(localized: "error_scripting_no_spaces")
    static let errorScriptingNoWindowToMove = String(localized: "error_scripting_no_window_to_move")
    static let errorScriptingSpaceIsFullscreen = String(localized: "error_scripting_space_is_fullscreen")
    static let errorScriptingSpaceOutOfRange = String(localized: "error_scripting_space_out_of_range")
    static let errorScriptingWindowIsFullscreen = String(localized: "error_scripting_window_is_fullscreen")

    static let labelAllDisplays = String(localized: "label_all_displays")
    static let labelAppearance = String(localized: "label_appearance")
    static let labelAllSpaces = String(localized: "label_all_spaces")
    static let labelAllSpacesAllDisplays = String(localized: "label_all_spaces_all_displays")
    static let labelAllSpacesThisDisplay = String(localized: "label_all_spaces_this_display")
    static let labelBackup = String(localized: "label_backup")
    static let labelBadgePosition = String(localized: "label_badge_position")
    static let labelBehavior = String(localized: "label_behavior")
    static let labelClick = String(localized: "label_click")
    static let labelDefault = String(localized: "label_default")
    static let labelDefaultStyle = String(localized: "label_default_style")
    static let labelDesktop = String(localized: "label_desktop")
    static let labelDesktopNumber = String(localized: "label_desktop_number")
    static let labelDisplayOrder = String(localized: "label_display_order")
    static let labelDisplays = String(localized: "label_displays")
    static let labelFont = String(localized: "label_font")
    static let labelGlyph = String(localized: "label_glyph")
    static let labelHapticLight = String(localized: "label_haptic_light")
    static let labelHapticMaximum = String(localized: "label_haptic_maximum")
    static let labelHapticMedium = String(localized: "label_haptic_medium")
    static let labelHapticStrong = String(localized: "label_haptic_strong")
    static let labelHapticVeryLight = String(localized: "label_haptic_very_light")
    static let labelHapticVeryStrong = String(localized: "label_haptic_very_strong")
    static let labelHorizontal = String(localized: "label_horizontal")
    static let labelInside = String(localized: "label_inside")
    static let labelJump = String(localized: "label_jump")
    static let labelLabelBackground = String(localized: "label_label_background")
    static let labelLabelForeground = String(localized: "label_label_foreground")
    static let labelLeft = String(localized: "label_left")
    static let labelMoveLeft = String(localized: "label_move_left")
    static let labelMoveRight = String(localized: "label_move_right")
    static let labelNever = String(localized: "label_never")
    static let labelNone = String(localized: "label_none")
    static let labelNumber = String(localized: "label_number")
    static let labelNumberBackground = String(localized: "label_number_background")
    static let labelNumberForeground = String(localized: "label_number_foreground")
    static let labelOff = String(localized: "label_off")
    static let labelOutside = String(localized: "label_outside")
    static let labelPickerAppIcons = String(localized: "label_picker_app_icons")
    static let labelPickerEmpty = String(localized: "label_picker_empty")
    static let labelPickerStyle = String(localized: "label_picker_style")
    static let labelPickerStyleBoth = String(localized: "label_picker_style_both")
    static let labelPickerStyleIcons = String(localized: "label_picker_style_icons")
    static let labelPickerStyleName = String(localized: "label_picker_style_name")
    static let labelPreview = String(localized: "label_preview")
    static let labelPrevious = String(localized: "label_previous")
    static let labelResetSettings = String(localized: "label_reset_settings")
    static let labelRight = String(localized: "label_right")
    static let labelSendLeft = String(localized: "label_send_left")
    static let labelSendRight = String(localized: "label_send_right")
    static let labelSensitivity = String(localized: "label_sensitivity")
    static let labelSkinTone = String(localized: "label_skin_tone")
    static let labelSeparator = String(localized: "label_separator")
    static let labelSeparatorBullet = String(localized: "label_separator_bullet")
    static let labelSeparatorDot = String(localized: "label_separator_dot")
    static let labelSeparatorLine = String(localized: "label_separator_line")
    static let labelSeparatorNone = String(localized: "label_separator_none")
    static let labelSeparatorSlash = String(localized: "label_separator_slash")
    static let labelSeparatorStyle = String(localized: "label_separator_style")
    static let labelSpaceNumber = String(localized: "label_space_number")
    static let labelSpaces = String(localized: "label_spaces")
    static let labelSwitch = String(localized: "label_switch")
    static let labelSymbol = String(localized: "label_symbol")
    static let labelSymbolBackground = String(localized: "label_symbol_background")
    static let labelSymbolForeground = String(localized: "label_symbol_foreground")
    static let labelSymbolPosition = String(localized: "label_symbol_position")
    static let labelSymbolWrap = String(localized: "label_symbol_wrap")
    static let labelStyleBox = String(localized: "label_style_box")
    static let labelStyleBoxOutline = String(localized: "label_style_box_outline")
    static let labelStylePill = String(localized: "label_style_pill")
    static let labelStylePillOutline = String(localized: "label_style_pill_outline")
    static let labelVertical = String(localized: "label_vertical")
    static let labelWindow = String(localized: "label_window")
    static let menuBadge = String(localized: "menu_badge")
    static let menuColor = String(localized: "menu_color")
    static let menuEmoji = String(localized: "menu_emoji")
    static let menuIcon = String(localized: "menu_icon")
    static let menuLabel = String(localized: "menu_label")
    static let menuNumber = String(localized: "menu_number")
    static let menuPadding = String(localized: "menu_padding")
    static let menuScroll = String(localized: "menu_scroll")
    static let menuSettingsWindow = String(localized: "menu_settings_window")
    static let menuSound = String(localized: "menu_sound")
    static let menuSymbol = String(localized: "menu_symbol")
    static let paneGeneral = String(localized: "pane_general")
    static let paneKeyboard = String(localized: "pane_keyboard")
    static let paneMenuBar = String(localized: "pane_menu_bar")
    static let paneMouse = String(localized: "pane_mouse")
    static let paneSpaces = String(localized: "pane_spaces")
    static let search = String(localized: "search")
    // Space-separated lists of settings-search synonyms, one per concept.
    // These are never displayed, so they carry the words people search with
    // rather than the wording the rows use.
    static let searchKeywordsBackup = String(localized: "search_keywords_backup")
    static let searchKeywordsColor = String(localized: "search_keywords_color")
    static let searchKeywordsDisplay = String(localized: "search_keywords_display")
    static let searchKeywordsEmoji = String(localized: "search_keywords_emoji")
    static let searchKeywordsFont = String(localized: "search_keywords_font")
    static let searchKeywordsFullscreen = String(localized: "search_keywords_fullscreen")
    static let searchKeywordsHaptics = String(localized: "search_keywords_haptics")
    static let searchKeywordsHide = String(localized: "search_keywords_hide")
    static let searchKeywordsHotkey = String(localized: "search_keywords_hotkey")
    static let searchKeywordsIcon = String(localized: "search_keywords_icon")
    static let searchKeywordsLabel = String(localized: "search_keywords_label")
    static let searchKeywordsPermission = String(localized: "search_keywords_permission")
    static let searchKeywordsPointer = String(localized: "search_keywords_pointer")
    static let searchKeywordsReset = String(localized: "search_keywords_reset")
    static let searchKeywordsSize = String(localized: "search_keywords_size")
    static let searchKeywordsSound = String(localized: "search_keywords_sound")
    static let searchKeywordsSpace = String(localized: "search_keywords_space")
    static let searchKeywordsStartup = String(localized: "search_keywords_startup")
    static let searchKeywordsUpdate = String(localized: "search_keywords_update")
    static let searchKeywordsWindow = String(localized: "search_keywords_window")
    static let soundCustom = String(localized: "sound_custom")
    static let soundSystem = String(localized: "sound_system")
    static let soundUser = String(localized: "sound_user")
    static let tipAllDisplays = String(localized: "tip_all_displays")
    static let tipBackup = String(localized: "tip_backup")
    static let tipBadgeInput = String(localized: "tip_badge_input")
    static let tipBadgePosition = String(localized: "tip_badge_position")
    static let tipBetaUpdates = String(localized: "tip_beta_updates")
    static let tipCheckForUpdates = String(localized: "tip_check_for_updates")
    static let tipClassicSwitching = String(localized: "tip_classic_switching")
    static let tipCopyFrom = String(localized: "tip_copy_from")
    static let tipCopyTo = String(localized: "tip_copy_to")
    static let tipClearBadge = String(localized: "tip_clear_badge")
    static let tipClearLabel = String(localized: "tip_clear_label")
    static let tipClickToSwitchSpaces = String(localized: "tip_click_to_switch_spaces")
    static let tipDimInactiveSpaces = String(localized: "tip_dim_inactive_spaces")
    static let tipDisplayOrder = String(localized: "tip_display_order")
    static let tipFont = String(localized: "tip_font")
    static let tipHasOwnStyle = String(localized: "tip_has_own_style")
    static let tipHideEmptySpaces = String(localized: "tip_hide_empty_spaces")
    static let tipHotkeyMoveLeft = String(localized: "tip_hotkey_move_left")
    static let tipHotkeyMoveRight = String(localized: "tip_hotkey_move_right")
    static let tipHotkeySendLeft = String(localized: "tip_hotkey_send_left")
    static let tipHotkeySendRight = String(localized: "tip_hotkey_send_right")
    static let tipHotkeySwitchLeft = String(localized: "tip_hotkey_switch_left")
    static let tipHotkeySwitchPrevious = String(localized: "tip_hotkey_switch_previous")
    static let tipHotkeySwitchRight = String(localized: "tip_hotkey_switch_right")
    static let tipHotkeysBehavior = String(localized: "tip_hotkeys_behavior")
    static let tipHideFullscreenApps = String(localized: "tip_hide_fullscreen_apps")
    static let tipHideSingleSpace = String(localized: "tip_hide_single_space")
    static let tipIconPadding = String(localized: "tip_icon_padding")
    static let tipIconSize = String(localized: "tip_icon_size")
    static let tipInvertColors = String(localized: "tip_invert_colors")
    static let tipLabelInput = String(
        format: String(localized: "tip_label_input"), LabelTemplate.maxContentLength
    )
    static let tipLastChecked = String(localized: "tip_last_checked")
    static let tipLaunchAtLogin = String(localized: "tip_launch_at_login")
    static let tipLocalSpaceNumbers = String(localized: "tip_local_space_numbers")
    static let tipPickerAppIcons = String(localized: "tip_picker_app_icons")
    static let tipPickerStyle = String(localized: "tip_picker_style")
    static let tipPreserveSystemSpaceNumbers = String(localized: "tip_preserve_system_space_numbers")
    static let tipQuit = String(localized: "tip_quit")
    static let tipCurrentSpace = String(localized: "tip_current_space")
    static let tipResetSettings = String(localized: "tip_reset_settings")
    static let tipResetSpaceToDefault = String(localized: "tip_reset_space_to_default")
    static let tipScrollEnabled = String(localized: "tip_scroll_enabled")
    static let tipScrollHapticFeedback = String(localized: "tip_scroll_haptic_feedback")
    static let tipScrollInverted = String(localized: "tip_scroll_inverted")
    static let tipScrollWrapAround = String(localized: "tip_scroll_wrap_around")
    static let tipSearch = String(localized: "tip_search")
    static let tipSensitivity = String(localized: "tip_sensitivity")
    static let tipSeparator = String(localized: "tip_separator")
    static let tipSeparatorStyle = String(localized: "tip_separator_style")
    static let tipSetDefaultStyle = String(localized: "tip_set_default_style")
    static let tipSkipEmptySpaces = String(localized: "tip_skip_empty_spaces")
    static let tipSettingsWindow = String(localized: "tip_settings_window")
    static let tipShowAllDisplays = String(localized: "tip_show_all_displays")
    static let tipShrinkToFit = String(localized: "tip_shrink_to_fit")
    static let tipShowAllSpaces = String(localized: "tip_show_all_spaces")
    static let tipSound = String(localized: "tip_sound")
    static let tipSoundSpace = String(localized: "tip_sound_space")
    static let tipSpacePlaceholder = String(localized: "tip_space_placeholder")
    static let tipSpacePlaceholderHotkey = String(localized: "tip_space_placeholder_hotkey")
    static let tipUseFForFullscreenApps = String(localized: "tip_use_f_for_fullscreen_apps")
    static let tipWindowSkipEmptySpaces = String(localized: "tip_window_skip_empty_spaces")
    static let toggleAutoCheckUpdates = String(localized: "toggle_auto_check_updates")
    static let toggleAutoInstallUpdates = String(localized: "toggle_auto_install_updates")
    static let toggleBetaUpdates = String(localized: "toggle_beta_updates")
    static let toggleClassicSwitching = String(localized: "toggle_classic_switching")
    static let toggleClickToSwitchSpaces = String(localized: "toggle_click_to_switch_spaces")
    static let toggleDimInactiveSpaces = String(localized: "toggle_dim_inactive_spaces")
    static let toggleHideEmptySpaces = String(localized: "toggle_hide_empty_spaces")
    static let toggleHideFullscreenApps = String(localized: "toggle_hide_fullscreen_apps")
    static let toggleHideSingleSpace = String(localized: "toggle_hide_single_space")
    static let toggleLaunchAtLogin = String(localized: "toggle_launch_at_login")
    static let toggleLocalSpaceNumbers = String(localized: "toggle_local_space_numbers")
    static let togglePreserveSystemSpaceNumbers = String(localized: "toggle_preserve_system_space_numbers")
    static let toggleScrollHapticFeedback = String(localized: "toggle_scroll_haptic_feedback")
    static let toggleScrollInverted = String(localized: "toggle_scroll_inverted")
    static let toggleScrollWrapAround = String(localized: "toggle_scroll_wrap_around")
    static let toggleShowAllDisplays = String(localized: "toggle_show_all_displays")
    static let toggleShowAllSpaces = String(localized: "toggle_show_all_spaces")
    static let toggleShrinkToFit = String(localized: "toggle_shrink_to_fit")
    static let toggleSkipEmptySpaces = String(localized: "toggle_skip_empty_spaces")
    static let toggleUseFForFullscreenApps = String(localized: "toggle_use_f_for_fullscreen_apps")
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
        "\u{1F3FB}",
        "\u{1F3FC}",
        "\u{1F3FD}",
        "\u{1F3FE}",
        "\u{1F3FF}",
    ]
    /// Variation Selector 16 - used to request emoji presentation
    private static let vs16: Unicode.Scalar = "\u{FE0F}"
    /// Zero Width Joiner - used in complex emoji sequences
    private static let zwj: Unicode.Scalar = "\u{200D}"

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

        // For ZWJ sequences, insert modifier after first modifier-base character,
        // but only if the result actually renders as a single emoji glyph.
        if stripped.unicodeScalars.contains(zwj) {
            let result = insertModifierAfterFirstBase(in: stripped, modifier: modifier)
            return renderEmoji(result) ? result : emoji
        }

        // Simple emoji - just append
        return stripped + modifier
    }

    /// Strips skin tone modifiers and variation selectors from emoji.
    /// VS16 is only stripped before the first ZWJ to preserve gender indicators.
    private static func stripModifiers(from emoji: String) -> String {
        let scalars = Array(emoji.unicodeScalars)
        let firstZWJ = scalars.firstIndex(of: zwj)
        var result: [Unicode.Scalar] = []
        for (offset, scalar) in scalars.enumerated() {
            if modifierScalars.contains(scalar) {
                continue
            }
            if scalar == vs16, firstZWJ == nil || offset < firstZWJ! {
                continue
            }
            result.append(scalar)
        }
        return String(String.UnicodeScalarView(result))
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

    /// Checks if an emoji string renders as a single glyph by comparing its width
    /// to a reference emoji. Broken ZWJ sequences render wider than a single emoji.
    private static func renderEmoji(_ string: String) -> Bool {
        let bounds = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let options: NSString.DrawingOptions = .usesLineFragmentOrigin
        let size = (string as NSString).boundingRect(with: bounds, options: options, context: nil).size
        let refSize = ("👍" as NSString).boundingRect(with: bounds, options: options, context: nil).size
        return size.width <= refSize.width * 1.1
    }

    /// Uses EmojiKit's size-based detection to determine if an emoji supports skin tones.
    /// This is more reliable than `isEmojiModifierBase` which has false positives.
    private static func canApplyModifier(to emoji: String) -> Bool {
        Emoji(emoji).hasSkinToneVariants
    }
}
