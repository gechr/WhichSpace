import AppKit
import Defaults

// MARK: - Backup

/// Represents the complete WhichSpace configuration for import/export.
struct Backup: Codable {
    let bundleId: String
    let version: String
    let settings: BackupSettings
    let spacePreferences: BackupSpacePreferences
    let displaySpacePreferences: [String: BackupSpacePreferences]
    /// Recorded hotkeys as name to encoded shortcut; empty when none were
    /// recorded, and omitted from the JSON in that case
    let hotkeys: [String: String]

    private enum CodingKeys: String, CodingKey {
        case bundleId, version, settings, spacePreferences, displaySpacePreferences, hotkeys
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encode(version, forKey: .version)
        try container.encode(settings, forKey: .settings)
        if !spacePreferences.isEmpty {
            try container.encode(spacePreferences, forKey: .spacePreferences)
        }
        let nonEmpty = displaySpacePreferences.filter { !$0.value.isEmpty }
        if !nonEmpty.isEmpty {
            try container.encode(nonEmpty, forKey: .displaySpacePreferences)
        }
        if !hotkeys.isEmpty {
            try container.encode(hotkeys, forKey: .hotkeys)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleId = try container.decode(String.self, forKey: .bundleId)
        version = try container.decode(String.self, forKey: .version)
        settings = try container.decode(BackupSettings.self, forKey: .settings)
        spacePreferences = try container.decodeIfPresent(BackupSpacePreferences.self, forKey: .spacePreferences)
            ?? BackupSpacePreferences()
        displaySpacePreferences = try container.decodeIfPresent(
            [String: BackupSpacePreferences].self,
            forKey: .displaySpacePreferences
        ) ?? [:]
        hotkeys = try container.decodeIfPresent([String: String].self, forKey: .hotkeys) ?? [:]
    }

    init(
        bundleId: String,
        version: String,
        settings: BackupSettings,
        spacePreferences: BackupSpacePreferences,
        displaySpacePreferences: [String: BackupSpacePreferences],
        hotkeys: [String: String] = [:]
    ) {
        self.bundleId = bundleId
        self.version = version
        self.settings = settings
        self.spacePreferences = spacePreferences
        self.displaySpacePreferences = displaySpacePreferences
        self.hotkeys = hotkeys
    }
}

// MARK: - BackupSettings

/// Global settings that apply to the entire app.
struct BackupSettings: Codable {
    var classicSpaceSwitching: Bool
    var clickToSwitchSpaces: Bool
    var dimInactiveSpaces: Bool
    var emojiPickerSkinTone: Int
    var fullscreenIconStyle: String?
    var hideEmptySpaces: Bool
    var hideFullscreenApps: Bool
    var hideSingleSpace: Bool
    var horizontalScrollEnabled: Bool
    var hotkeysSkipEmptySpaces: Bool
    var hotkeysWindowSkipEmptySpaces: Bool
    var includeBetaUpdates: Bool
    var invertHorizontalScroll: Bool
    var invertVerticalScroll: Bool
    var launchAtLogin: Bool
    var localSpaceNumbers: Bool
    var moveApplicationAlertSuppress: Bool
    var paddingScale: Double?
    var scrollHapticFeedback: Bool
    var scrollHapticIntensity: Int
    var scrollSensitivity: Double
    var scrollWrapAround: Bool
    var separatorColor: CodableColor?
    var separatorStyle: String?
    var showAllDisplays: Bool
    var showAllSpaces: Bool
    var shrinkIconToFit: Bool
    var sizeScale: Double
    var soundName: String
    var spacePickerMaxAppIcons: Int
    var spacePickerStyle: String?
    /// Present only in backups from versions with the per-display toggle;
    /// nil means both preference families are live data. Never encoded -
    /// the synthesized encoder omits nil optionals.
    // swiftlint:disable:next discouraged_optional_boolean
    var uniqueIconsPerDisplay: Bool?
    var verticalScrollEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case classicSpaceSwitching
        case clickToSwitchSpaces, dimInactiveSpaces, emojiPickerSkinTone, fullscreenIconStyle, hideEmptySpaces
        case hideFullscreenApps, hideSingleSpace, horizontalScrollEnabled, hotkeysSkipEmptySpaces
        case hotkeysWindowSkipEmptySpaces, includeBetaUpdates
        case invertHorizontalScroll, invertVerticalScroll, launchAtLogin, localSpaceNumbers
        // Raw value matches the legacy stored defaults key
        case moveApplicationAlertSuppress = "moveToApplicationsFolderAlertSuppress"
        case paddingScale
        case scrollHapticFeedback, scrollHapticIntensity, scrollSensitivity, scrollWrapAround
        case separatorColor, separatorStyle, showAllDisplays, showAllSpaces, shrinkIconToFit
        case sizeScale, soundName, spacePickerMaxAppIcons, spacePickerStyle, uniqueIconsPerDisplay
        case verticalScrollEnabled
    }

    /// Tolerates missing keys so backups exported by older app versions still import.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        classicSpaceSwitching = try container.decodeIfPresent(Bool.self, forKey: .classicSpaceSwitching) ?? false
        clickToSwitchSpaces = try container.decodeIfPresent(Bool.self, forKey: .clickToSwitchSpaces) ?? false
        dimInactiveSpaces = try container.decodeIfPresent(Bool.self, forKey: .dimInactiveSpaces) ?? true
        emojiPickerSkinTone = try container.decodeIfPresent(Int.self, forKey: .emojiPickerSkinTone)
            ?? SkinTone.default.rawValue
        fullscreenIconStyle = try container.decodeIfPresent(String.self, forKey: .fullscreenIconStyle)
        hideEmptySpaces = try container.decodeIfPresent(Bool.self, forKey: .hideEmptySpaces) ?? false
        hideFullscreenApps = try container.decodeIfPresent(Bool.self, forKey: .hideFullscreenApps) ?? false
        hideSingleSpace = try container.decodeIfPresent(Bool.self, forKey: .hideSingleSpace) ?? false
        horizontalScrollEnabled = try container.decodeIfPresent(Bool.self, forKey: .horizontalScrollEnabled) ?? false
        hotkeysSkipEmptySpaces = try container.decodeIfPresent(Bool.self, forKey: .hotkeysSkipEmptySpaces) ?? false
        hotkeysWindowSkipEmptySpaces = try container
            .decodeIfPresent(Bool.self, forKey: .hotkeysWindowSkipEmptySpaces) ?? false
        includeBetaUpdates = try container.decodeIfPresent(Bool.self, forKey: .includeBetaUpdates) ?? false
        invertHorizontalScroll = try container.decodeIfPresent(Bool.self, forKey: .invertHorizontalScroll) ?? false
        invertVerticalScroll = try container.decodeIfPresent(Bool.self, forKey: .invertVerticalScroll) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        localSpaceNumbers = try container.decodeIfPresent(Bool.self, forKey: .localSpaceNumbers) ?? false
        moveApplicationAlertSuppress = try container.decodeIfPresent(
            Bool.self, forKey: .moveApplicationAlertSuppress
        ) ?? false
        paddingScale = try container.decodeIfPresent(Double.self, forKey: .paddingScale)
        scrollHapticFeedback = try container.decodeIfPresent(Bool.self, forKey: .scrollHapticFeedback) ?? false
        scrollHapticIntensity = try container.decodeIfPresent(Int.self, forKey: .scrollHapticIntensity)
            ?? Layout.defaultScrollHapticIntensity
        scrollSensitivity = try container.decodeIfPresent(Double.self, forKey: .scrollSensitivity)
            ?? Layout.defaultScrollSensitivity
        scrollWrapAround = try container.decodeIfPresent(Bool.self, forKey: .scrollWrapAround) ?? false
        separatorColor = try container.decodeIfPresent(CodableColor.self, forKey: .separatorColor)
        separatorStyle = try container.decodeIfPresent(String.self, forKey: .separatorStyle)
        showAllDisplays = try container.decodeIfPresent(Bool.self, forKey: .showAllDisplays) ?? false
        showAllSpaces = try container.decodeIfPresent(Bool.self, forKey: .showAllSpaces) ?? false
        shrinkIconToFit = try container.decodeIfPresent(Bool.self, forKey: .shrinkIconToFit) ?? true
        sizeScale = try container.decodeIfPresent(Double.self, forKey: .sizeScale) ?? Layout.defaultSizeScale
        soundName = try container.decodeIfPresent(String.self, forKey: .soundName) ?? ""
        spacePickerMaxAppIcons = try container.decodeIfPresent(Int.self, forKey: .spacePickerMaxAppIcons)
            ?? Layout.defaultSpacePickerMaxAppIcons
        spacePickerStyle = try container.decodeIfPresent(String.self, forKey: .spacePickerStyle)
        uniqueIconsPerDisplay = try container.decodeIfPresent(Bool.self, forKey: .uniqueIconsPerDisplay)
        verticalScrollEnabled = try container.decodeIfPresent(Bool.self, forKey: .verticalScrollEnabled) ?? false
    }

    init(
        classicSpaceSwitching: Bool,
        clickToSwitchSpaces: Bool,
        dimInactiveSpaces: Bool,
        emojiPickerSkinTone: Int,
        fullscreenIconStyle: String?,
        hideEmptySpaces: Bool,
        hideFullscreenApps: Bool,
        hideSingleSpace: Bool,
        horizontalScrollEnabled: Bool,
        hotkeysSkipEmptySpaces: Bool,
        hotkeysWindowSkipEmptySpaces: Bool,
        includeBetaUpdates: Bool,
        invertHorizontalScroll: Bool,
        invertVerticalScroll: Bool,
        launchAtLogin: Bool,
        localSpaceNumbers: Bool,
        moveApplicationAlertSuppress: Bool,
        paddingScale: Double?,
        scrollHapticFeedback: Bool,
        scrollHapticIntensity: Int,
        scrollSensitivity: Double,
        scrollWrapAround: Bool,
        separatorColor: CodableColor?,
        separatorStyle: String?,
        showAllDisplays: Bool,
        showAllSpaces: Bool,
        shrinkIconToFit: Bool,
        sizeScale: Double,
        soundName: String,
        spacePickerMaxAppIcons: Int,
        spacePickerStyle: String?,
        verticalScrollEnabled: Bool
    ) {
        self.classicSpaceSwitching = classicSpaceSwitching
        self.clickToSwitchSpaces = clickToSwitchSpaces
        self.dimInactiveSpaces = dimInactiveSpaces
        self.emojiPickerSkinTone = emojiPickerSkinTone
        self.fullscreenIconStyle = fullscreenIconStyle
        self.hideEmptySpaces = hideEmptySpaces
        self.hideFullscreenApps = hideFullscreenApps
        self.hideSingleSpace = hideSingleSpace
        self.horizontalScrollEnabled = horizontalScrollEnabled
        self.hotkeysSkipEmptySpaces = hotkeysSkipEmptySpaces
        self.hotkeysWindowSkipEmptySpaces = hotkeysWindowSkipEmptySpaces
        self.includeBetaUpdates = includeBetaUpdates
        self.invertHorizontalScroll = invertHorizontalScroll
        self.invertVerticalScroll = invertVerticalScroll
        self.launchAtLogin = launchAtLogin
        self.localSpaceNumbers = localSpaceNumbers
        self.moveApplicationAlertSuppress = moveApplicationAlertSuppress
        self.paddingScale = paddingScale
        self.scrollHapticFeedback = scrollHapticFeedback
        self.scrollHapticIntensity = scrollHapticIntensity
        self.scrollSensitivity = scrollSensitivity
        self.scrollWrapAround = scrollWrapAround
        self.separatorColor = separatorColor
        self.separatorStyle = separatorStyle
        self.showAllDisplays = showAllDisplays
        self.showAllSpaces = showAllSpaces
        self.shrinkIconToFit = shrinkIconToFit
        self.sizeScale = sizeScale
        self.soundName = soundName
        self.spacePickerMaxAppIcons = spacePickerMaxAppIcons
        self.spacePickerStyle = spacePickerStyle
        self.verticalScrollEnabled = verticalScrollEnabled
    }
}

// MARK: - BackupSpacePreferences

/// Per-space preferences (badges, colors, styles, symbols, fonts, skin tones, sounds).
struct BackupSpacePreferences: Codable {
    var badges: [String: CodableBadge]
    var colors: [String: CodableSpaceColors]
    var fonts: [String: CodableSpaceFont]
    var iconStyles: [String: String]
    var labels: [String: String]
    var labelStyles: [String: String]
    var skinTones: [String: Int]
    var sounds: [String: String]
    var symbolGaps: [String: Double]
    var symbolPositions: [String: String]
    var symbols: [String: String]
    var symbolWraps: [String: String]

    private enum CodingKeys: String, CodingKey {
        case badges, colors, fonts, iconStyles, labels, labelStyles, skinTones, sounds,
             symbolGaps, symbolPositions, symbols, symbolWraps
    }

    var isEmpty: Bool {
        badges.isEmpty && colors.isEmpty && fonts.isEmpty && iconStyles.isEmpty
            && labels.isEmpty && labelStyles.isEmpty && skinTones.isEmpty && sounds.isEmpty
            && symbolGaps.isEmpty && symbolPositions.isEmpty && symbols.isEmpty && symbolWraps.isEmpty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !badges.isEmpty {
            try container.encode(badges, forKey: .badges)
        }
        if !colors.isEmpty {
            try container.encode(colors, forKey: .colors)
        }
        if !fonts.isEmpty {
            try container.encode(fonts, forKey: .fonts)
        }
        if !iconStyles.isEmpty {
            try container.encode(iconStyles, forKey: .iconStyles)
        }
        if !labels.isEmpty {
            try container.encode(labels, forKey: .labels)
        }
        if !labelStyles.isEmpty {
            try container.encode(labelStyles, forKey: .labelStyles)
        }
        if !skinTones.isEmpty {
            try container.encode(skinTones, forKey: .skinTones)
        }
        if !sounds.isEmpty {
            try container.encode(sounds, forKey: .sounds)
        }
        if !symbolGaps.isEmpty {
            try container.encode(symbolGaps, forKey: .symbolGaps)
        }
        if !symbolPositions.isEmpty {
            try container.encode(symbolPositions, forKey: .symbolPositions)
        }
        if !symbols.isEmpty {
            try container.encode(symbols, forKey: .symbols)
        }
        if !symbolWraps.isEmpty {
            try container.encode(symbolWraps, forKey: .symbolWraps)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        badges = try container.decodeIfPresent([String: CodableBadge].self, forKey: .badges) ?? [:]
        colors = try container.decodeIfPresent([String: CodableSpaceColors].self, forKey: .colors) ?? [:]
        fonts = try container.decodeIfPresent([String: CodableSpaceFont].self, forKey: .fonts) ?? [:]
        iconStyles = try container.decodeIfPresent([String: String].self, forKey: .iconStyles) ?? [:]
        labels = try container.decodeIfPresent([String: String].self, forKey: .labels) ?? [:]
        labelStyles = try container.decodeIfPresent([String: String].self, forKey: .labelStyles) ?? [:]
        skinTones = try container.decodeIfPresent([String: Int].self, forKey: .skinTones) ?? [:]
        sounds = try container.decodeIfPresent([String: String].self, forKey: .sounds) ?? [:]
        symbolGaps = try container.decodeIfPresent([String: Double].self, forKey: .symbolGaps) ?? [:]
        symbolPositions = try container.decodeIfPresent([String: String].self, forKey: .symbolPositions) ?? [:]
        symbols = try container.decodeIfPresent([String: String].self, forKey: .symbols) ?? [:]
        symbolWraps = try container.decodeIfPresent([String: String].self, forKey: .symbolWraps) ?? [:]
    }

    init(
        badges: [Int: SpaceBadge] = [:],
        colors: [Int: SpaceColors] = [:],
        fonts: [Int: SpaceFont] = [:],
        iconStyles: [Int: IconStyle] = [:],
        labels: [Int: String] = [:],
        labelStyles: [Int: IconStyle] = [:],
        skinTones: [Int: SkinTone] = [:],
        sounds: [Int: String] = [:],
        symbolGaps: [Int: Double] = [:],
        symbolPositions: [Int: SymbolPosition] = [:],
        symbols: [Int: String] = [:],
        symbolWraps: [Int: SymbolWrap] = [:]
    ) {
        self.badges = badges.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = CodableBadge(from: pair.value)
        }
        self.colors = colors.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = CodableSpaceColors(from: pair.value)
        }
        self.fonts = fonts.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = CodableSpaceFont(from: pair.value)
        }
        self.iconStyles = iconStyles.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value.rawValue
        }
        self.labels = labels.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value
        }
        self.labelStyles = labelStyles.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value.rawValue
        }
        self.skinTones = skinTones.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value.rawValue
        }
        self.sounds = sounds.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value
        }
        self.symbolGaps = symbolGaps.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value
        }
        self.symbolPositions = symbolPositions.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value.rawValue
        }
        self.symbols = symbols.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value
        }
        self.symbolWraps = symbolWraps.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value.rawValue
        }
    }

    private func convertDict<V, R>(_ dict: [String: V], transform: (V) -> R?) -> [Int: R] {
        dict.reduce(into: [:]) { result, pair in
            guard let key = Int(pair.key), let value = transform(pair.value) else {
                return
            }
            result[key] = value
        }
    }

    func toBadges() -> [Int: SpaceBadge] {
        convertDict(badges) { $0.toSpaceBadge() }
    }

    func toSpaceColors() -> [Int: SpaceColors] {
        convertDict(colors) { $0.toSpaceColors() }
    }

    func toSpaceFonts() -> [Int: SpaceFont] {
        convertDict(fonts) { $0.toSpaceFont() }
    }

    func toIconStyles() -> [Int: IconStyle] {
        convertDict(iconStyles) { IconStyle(rawValue: $0) }
    }

    func toLabels() -> [Int: String] {
        convertDict(labels) { $0 }
    }

    func toLabelStyles() -> [Int: IconStyle] {
        convertDict(labelStyles) { IconStyle(rawValue: $0) }
    }

    func toSkinTones() -> [Int: SkinTone] {
        convertDict(skinTones) { SkinTone(rawValue: $0) }
    }

    func toSounds() -> [Int: String] {
        convertDict(sounds) { $0 }
    }

    func toSymbolGaps() -> [Int: Double] {
        convertDict(symbolGaps) { $0.clamped(to: Layout.symbolGapScaleRange) }
    }

    func toSymbolPositions() -> [Int: SymbolPosition] {
        convertDict(symbolPositions) { SymbolPosition(rawValue: $0) }
    }

    func toSymbols() -> [Int: String] {
        convertDict(symbols) { $0 }
    }

    func toSymbolWraps() -> [Int: SymbolWrap] {
        convertDict(symbolWraps) { SymbolWrap(rawValue: $0) }
    }
}

// MARK: - CodableBadge

/// A badge (character + position) for JSON serialization.
struct CodableBadge: Codable {
    let character: String
    let position: String

    init(from badge: SpaceBadge) {
        character = badge.character
        position = badge.position.rawValue
    }

    func toSpaceBadge() -> SpaceBadge? {
        guard let pos = BadgePosition(rawValue: position) else {
            return nil
        }
        return SpaceBadge(character: character, position: pos)
    }
}

// MARK: - CodableColor

/// A color represented as RGBA components for JSON serialization.
struct CodableColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(from color: NSColor) {
        let rgbColor = color.usingColorSpace(.sRGB) ?? color
        red = rgbColor.redComponent
        green = rgbColor.greenComponent
        blue = rgbColor.blueComponent
        alpha = rgbColor.alphaComponent
    }

    func toNSColor() -> NSColor {
        // Match the sRGB space used during serialization for an exact round-trip
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - CodableSpaceColors

/// Space colors (foreground/background/symbol) for JSON serialization.
struct CodableSpaceColors: Codable {
    let foreground: CodableColor
    let background: CodableColor
    /// Optional so backups written before these colors existed still decode
    let symbol: CodableColor?
    let symbolBackground: CodableColor?

    init(from colors: SpaceColors) {
        foreground = CodableColor(from: colors.foreground)
        background = CodableColor(from: colors.background)
        symbol = colors.symbol.map { CodableColor(from: $0) }
        symbolBackground = colors.symbolBackground.map { CodableColor(from: $0) }
    }

    func toSpaceColors() -> SpaceColors? {
        SpaceColors(
            foreground: foreground.toNSColor(),
            background: background.toNSColor(),
            symbol: symbol?.toNSColor(),
            symbolBackground: symbolBackground?.toNSColor()
        )
    }
}

// MARK: - CodableSpaceFont

/// A font stored by name and size for JSON serialization.
struct CodableSpaceFont: Codable {
    let name: String
    let size: Double

    init(from font: SpaceFont) {
        name = font.font.fontName
        size = font.font.pointSize
    }

    func toSpaceFont() -> SpaceFont? {
        // NSFont(name:size:) does not support private system font names
        // (".AppleSystemUIFont", ".SFNS..."): the lookup sometimes returns
        // a fallback at the default size rather than failing. A size
        // mismatch marks that case, and the system font at the recorded
        // size is what the backup meant.
        if let font = NSFont(name: name, size: size), font.pointSize == size {
            return SpaceFont(font: font)
        }
        guard name.hasPrefix(".") else {
            return nil
        }
        return SpaceFont(font: NSFont.systemFont(ofSize: size))
    }
}

// MARK: - BackupError

enum BackupError: LocalizedError {
    case encodingFailed
    case decodingFailed(Error)
    case fileReadFailed(URL, Error)
    case fileWriteFailed(URL, Error)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            Localization.errorBackupEncodingFailed
        case let .decodingFailed(error):
            String(format: Localization.errorBackupDecodingFailed, error.localizedDescription)
        case let .fileReadFailed(url, error):
            String(format: Localization.errorBackupFileReadFailed, url.lastPathComponent, error.localizedDescription)
        case let .fileWriteFailed(url, error):
            String(format: Localization.errorBackupFileWriteFailed, url.lastPathComponent, error.localizedDescription)
        case .invalidData:
            Localization.errorBackupInvalidData
        }
    }
}

// MARK: - BackupManager

/// Handles encoding and decoding of WhichSpace configuration.
@MainActor
enum BackupManager {
    /// Default filename for exported backup.
    static let defaultFilename = "WhichSpaceSettings.json"

    /// Encodes the current settings to a JSON string. Hotkeys are passed in
    /// rather than read here: the hotkey library stores bindings in the host
    /// app's standard defaults domain, which keeps this function pure for
    /// tests running inside the real app.
    static func encode(
        store: DefaultsStore = AppEnvironment.shared.store,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider(),
        hotkeys: [String: String] = [:]
    ) throws -> String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            throw BackupError.encodingFailed
        }

        let settings = BackupSettings(
            classicSpaceSwitching: store.classicSpaceSwitching,
            clickToSwitchSpaces: store.clickToSwitchSpaces,
            dimInactiveSpaces: store.dimInactiveSpaces,
            emojiPickerSkinTone: store.emojiPickerSkinTone.rawValue,
            fullscreenIconStyle: store.fullscreenIconStyle.rawValue,
            hideEmptySpaces: store.hideEmptySpaces,
            hideFullscreenApps: store.hideFullscreenApps,
            hideSingleSpace: store.hideSingleSpace,
            horizontalScrollEnabled: store.horizontalScrollEnabled,
            hotkeysSkipEmptySpaces: store.hotkeysSkipEmptySpaces,
            hotkeysWindowSkipEmptySpaces: store.hotkeysWindowSkipEmptySpaces,
            includeBetaUpdates: store.includeBetaUpdates,
            invertHorizontalScroll: store.invertHorizontalScroll,
            invertVerticalScroll: store.invertVerticalScroll,
            launchAtLogin: launchAtLogin.isEnabled,
            localSpaceNumbers: store.localSpaceNumbers,
            moveApplicationAlertSuppress: store.moveApplicationAlertSuppress,
            paddingScale: store.paddingScale,
            scrollHapticFeedback: store.scrollHapticFeedback,
            scrollHapticIntensity: store.scrollHapticIntensity,
            scrollSensitivity: store.scrollSensitivity,
            scrollWrapAround: store.scrollWrapAround,
            separatorColor: store.separatorColor.map { CodableColor(from: $0) },
            separatorStyle: store.separatorStyle.rawValue,
            showAllDisplays: store.showAllDisplays,
            showAllSpaces: store.showAllSpaces,
            shrinkIconToFit: store.shrinkIconToFit,
            sizeScale: store.sizeScale,
            soundName: store.soundName,
            spacePickerMaxAppIcons: store.spacePickerMaxAppIcons,
            spacePickerStyle: store.spacePickerStyle.rawValue,
            verticalScrollEnabled: store.verticalScrollEnabled
        )

        let spacePreferences = BackupSpacePreferences(
            badges: store.spaceBadges,
            colors: store.spaceColors,
            fonts: store.spaceFonts,
            iconStyles: store.spaceIconStyles,
            labels: store.spaceLabels,
            labelStyles: store.spaceLabelStyles,
            skinTones: store.spaceSkinTones,
            sounds: store.spaceSounds,
            symbolGaps: store.spaceSymbolGaps,
            symbolPositions: store.spaceSymbolPositions,
            symbols: store.spaceSymbols,
            symbolWraps: store.spaceSymbolWraps
        )

        var displaySpacePreferences = [String: BackupSpacePreferences]()
        var displayIds = Set<String>()
        displayIds.formUnion(store.displaySpaceBadges.keys)
        displayIds.formUnion(store.displaySpaceColors.keys)
        displayIds.formUnion(store.displaySpaceFonts.keys)
        displayIds.formUnion(store.displaySpaceIconStyles.keys)
        displayIds.formUnion(store.displaySpaceLabels.keys)
        displayIds.formUnion(store.displaySpaceLabelStyles.keys)
        displayIds.formUnion(store.displaySpaceSkinTones.keys)
        displayIds.formUnion(store.displaySpaceSounds.keys)
        displayIds.formUnion(store.displaySpaceSymbolGaps.keys)
        displayIds.formUnion(store.displaySpaceSymbolPositions.keys)
        displayIds.formUnion(store.displaySpaceSymbols.keys)
        displayIds.formUnion(store.displaySpaceSymbolWraps.keys)

        for displayId in displayIds {
            displaySpacePreferences[displayId] = BackupSpacePreferences(
                badges: store.displaySpaceBadges[displayId] ?? [:],
                colors: store.displaySpaceColors[displayId] ?? [:],
                fonts: store.displaySpaceFonts[displayId] ?? [:],
                iconStyles: store.displaySpaceIconStyles[displayId] ?? [:],
                labels: store.displaySpaceLabels[displayId] ?? [:],
                labelStyles: store.displaySpaceLabelStyles[displayId] ?? [:],
                skinTones: store.displaySpaceSkinTones[displayId] ?? [:],
                sounds: store.displaySpaceSounds[displayId] ?? [:],
                symbolGaps: store.displaySpaceSymbolGaps[displayId] ?? [:],
                symbolPositions: store.displaySpaceSymbolPositions[displayId] ?? [:],
                symbols: store.displaySpaceSymbols[displayId] ?? [:],
                symbolWraps: store.displaySpaceSymbolWraps[displayId] ?? [:]
            )
        }

        let backup = Backup(
            bundleId: Bundle.main.bundleIdentifier ?? "io.gechr.WhichSpace",
            version: version,
            settings: settings,
            spacePreferences: spacePreferences,
            displaySpacePreferences: displaySpacePreferences,
            hotkeys: hotkeys
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(backup)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw BackupError.encodingFailed
            }
            return jsonString
        } catch let error as BackupError {
            throw error
        } catch {
            throw BackupError.encodingFailed
        }
    }

    /// Decodes a JSON string to a Backup object.
    static func decode(jsonString: String) throws -> Backup {
        guard let data = jsonString.data(using: .utf8) else {
            throw BackupError.invalidData
        }
        do {
            return try JSONDecoder().decode(Backup.self, from: data)
        } catch {
            throw BackupError.decodingFailed(error)
        }
    }

    /// Loads configuration from a file URL and applies it to the store.
    /// `applyHotkeys` receives the backup's recorded bindings (empty when it
    /// carried none) and stays nil in tests, which must not touch the live
    /// bindings in the app's standard defaults domain.
    static func load(
        from url: URL,
        store: DefaultsStore = AppEnvironment.shared.store,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider(),
        applyHotkeys: (([String: String]) -> Void)? = nil
    ) throws {
        let jsonString: String
        do {
            jsonString = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw BackupError.fileReadFailed(url, error)
        }

        let config = try decode(jsonString: jsonString)
        apply(config, to: store, launchAtLogin: launchAtLogin, applyHotkeys: applyHotkeys)
    }

    /// Applies a config to the defaults store.
    static func apply(
        _ backup: Backup,
        to store: DefaultsStore,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider(),
        applyHotkeys: (([String: String]) -> Void)? = nil
    ) {
        // Apply global settings
        store.classicSpaceSwitching = backup.settings.classicSpaceSwitching
        store.clickToSwitchSpaces = backup.settings.clickToSwitchSpaces
        store.dimInactiveSpaces = backup.settings.dimInactiveSpaces
        // Unrecognized values (from a newer app version or hand edit) keep the default
        store.emojiPickerSkinTone = SkinTone(rawValue: backup.settings.emojiPickerSkinTone) ?? .default
        store.fullscreenIconStyle = backup.settings.fullscreenIconStyle
            .flatMap { FullscreenIconStyle(rawValue: $0) } ?? .appIcon
        store.hideEmptySpaces = backup.settings.hideEmptySpaces
        store.hideFullscreenApps = backup.settings.hideFullscreenApps
        store.hideSingleSpace = backup.settings.hideSingleSpace
        store.horizontalScrollEnabled = backup.settings.horizontalScrollEnabled
        store.hotkeysSkipEmptySpaces = backup.settings.hotkeysSkipEmptySpaces
        store.hotkeysWindowSkipEmptySpaces = backup.settings.hotkeysWindowSkipEmptySpaces
        store.includeBetaUpdates = backup.settings.includeBetaUpdates
        store.invertHorizontalScroll = backup.settings.invertHorizontalScroll
        store.invertVerticalScroll = backup.settings.invertVerticalScroll
        var launchAtLogin = launchAtLogin
        launchAtLogin.isEnabled = backup.settings.launchAtLogin
        store.localSpaceNumbers = backup.settings.localSpaceNumbers
        store.moveApplicationAlertSuppress = backup.settings.moveApplicationAlertSuppress
        store.paddingScale = (backup.settings.paddingScale ?? Layout.defaultPaddingScale)
            .clamped(to: Layout.paddingScaleRange)
        store.scrollHapticFeedback = backup.settings.scrollHapticFeedback
        store.scrollHapticIntensity = backup.settings.scrollHapticIntensity
        store.scrollSensitivity = backup.settings.scrollSensitivity.clamped(to: Layout.scrollSensitivityRange)
        store.scrollWrapAround = backup.settings.scrollWrapAround
        store.separatorColor = backup.settings.separatorColor?.toNSColor()
        store.separatorStyle = backup.settings.separatorStyle
            .flatMap { SeparatorStyle(rawValue: $0) } ?? .line
        // Route through SettingsConstraints so a hand-edited backup can't enable both
        SettingsConstraints.setShowAllDisplays(backup.settings.showAllDisplays, store: store)
        SettingsConstraints.setShowAllSpaces(backup.settings.showAllSpaces, store: store)
        store.shrinkIconToFit = backup.settings.shrinkIconToFit
        store.sizeScale = backup.settings.sizeScale.clamped(to: Layout.sizeScaleRange)
        store.soundName = backup.settings.soundName
        store.spacePickerMaxAppIcons = backup.settings.spacePickerMaxAppIcons
        store.spacePickerStyle = backup.settings.spacePickerStyle
            .flatMap { SpacePickerStyle(rawValue: $0) } ?? .icons
        store.verticalScrollEnabled = backup.settings.verticalScrollEnabled

        // Apply shared space preferences
        store.spaceBadges = backup.spacePreferences.toBadges()
        store.spaceColors = backup.spacePreferences.toSpaceColors()
        store.spaceFonts = backup.spacePreferences.toSpaceFonts()
        store.spaceIconStyles = backup.spacePreferences.toIconStyles()
        store.spaceLabels = backup.spacePreferences.toLabels()
        store.spaceLabelStyles = backup.spacePreferences.toLabelStyles()
        store.spaceSkinTones = backup.spacePreferences.toSkinTones()
        store.spaceSounds = backup.spacePreferences.toSounds()
        store.spaceSymbolGaps = backup.spacePreferences.toSymbolGaps()
        store.spaceSymbolPositions = backup.spacePreferences.toSymbolPositions()
        store.spaceSymbols = backup.spacePreferences.toSymbols()
        store.spaceSymbolWraps = backup.spacePreferences.toSymbolWraps()

        // Apply per-display space preferences
        var displayBadges = [String: [Int: SpaceBadge]]()
        var displayColors = [String: [Int: SpaceColors]]()
        var displayFonts = [String: [Int: SpaceFont]]()
        var displayStyles = [String: [Int: IconStyle]]()
        var displayLabels = [String: [Int: String]]()
        var displayLabelStyles = [String: [Int: IconStyle]]()
        var displayTones = [String: [Int: SkinTone]]()
        var displaySounds = [String: [Int: String]]()
        var displaySymbolGaps = [String: [Int: Double]]()
        var displaySymbolPositions = [String: [Int: SymbolPosition]]()
        var displaySymbols = [String: [Int: String]]()
        var displaySymbolWraps = [String: [Int: SymbolWrap]]()

        for (displayId, prefs) in backup.displaySpacePreferences {
            displayBadges[displayId] = prefs.toBadges()
            displayColors[displayId] = prefs.toSpaceColors()
            displayFonts[displayId] = prefs.toSpaceFonts()
            displayStyles[displayId] = prefs.toIconStyles()
            displayLabels[displayId] = prefs.toLabels()
            displayLabelStyles[displayId] = prefs.toLabelStyles()
            displayTones[displayId] = prefs.toSkinTones()
            displaySounds[displayId] = prefs.toSounds()
            displaySymbolGaps[displayId] = prefs.toSymbolGaps()
            displaySymbolPositions[displayId] = prefs.toSymbolPositions()
            displaySymbols[displayId] = prefs.toSymbols()
            displaySymbolWraps[displayId] = prefs.toSymbolWraps()
        }

        store.displaySpaceBadges = displayBadges
        store.displaySpaceColors = displayColors
        store.displaySpaceFonts = displayFonts
        store.displaySpaceIconStyles = displayStyles
        store.displaySpaceLabels = displayLabels
        store.displaySpaceLabelStyles = displayLabelStyles
        store.displaySpaceSkinTones = displayTones
        store.displaySpaceSounds = displaySounds
        store.displaySpaceSymbolGaps = displaySymbolGaps
        store.displaySpaceSymbolPositions = displaySymbolPositions
        store.displaySpaceSymbols = displaySymbols
        store.displaySpaceSymbolWraps = displaySymbolWraps

        // Legacy backups carried the per-display toggle; whichever family
        // it hid was dead data at export time, so purging it makes the
        // restore render exactly as the backup's install did.
        if let legacyPerDisplay = backup.settings.uniqueIconsPerDisplay {
            SpacePreferences.purgeHiddenScopeData(perDisplayWasEnabled: legacyPerDisplay, store: store)
        }

        applyHotkeys?(backup.hotkeys)

        NotificationCenter.default.post(name: .backupImported, object: nil)
    }

    /// Exports the current configuration to a file URL.
    static func export(
        to url: URL,
        store: DefaultsStore = AppEnvironment.shared.store,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider(),
        hotkeys: [String: String] = [:]
    ) throws {
        let jsonString = try encode(store: store, launchAtLogin: launchAtLogin, hotkeys: hotkeys)
        do {
            try jsonString.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw BackupError.fileWriteFailed(url, error)
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let backupImported = Notification.Name("backupImported")
}
