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

    private enum CodingKeys: String, CodingKey {
        case bundleId, version, settings, spacePreferences, displaySpacePreferences
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
    }

    init(
        bundleId: String,
        version: String,
        settings: BackupSettings,
        spacePreferences: BackupSpacePreferences,
        displaySpacePreferences: [String: BackupSpacePreferences]
    ) {
        self.bundleId = bundleId
        self.version = version
        self.settings = settings
        self.spacePreferences = spacePreferences
        self.displaySpacePreferences = displaySpacePreferences
    }
}

// MARK: - BackupSettings

/// Global settings that apply to the entire app.
struct BackupSettings: Codable {
    var clickToSwitchSpaces: Bool
    var dimInactiveSpaces: Bool
    var hideEmptySpaces: Bool
    var hideFullscreenApps: Bool
    var hideSingleSpace: Bool
    var launchAtLogin: Bool
    var localSpaceNumbers: Bool
    var paddingScale: Double?
    var separatorColor: CodableColor?
    var showAllDisplays: Bool
    var showAllSpaces: Bool
    var sizeScale: Double
    var soundName: String
    var uniqueIconsPerDisplay: Bool
}

// MARK: - BackupSpacePreferences

/// Per-space preferences (badges, colors, styles, symbols, fonts, skin tones).
struct BackupSpacePreferences: Codable {
    var badges: [String: CodableBadge]
    var colors: [String: CodableSpaceColors]
    var fonts: [String: CodableSpaceFont]
    var iconStyles: [String: String]
    var labels: [String: String]
    var labelStyles: [String: String]
    var skinTones: [String: Int]
    var symbols: [String: String]

    private enum CodingKeys: String, CodingKey {
        case badges, colors, fonts, iconStyles, labels, labelStyles, skinTones, symbols
    }

    var isEmpty: Bool {
        badges.isEmpty && colors.isEmpty && fonts.isEmpty && iconStyles.isEmpty
            && labels.isEmpty && labelStyles.isEmpty && skinTones.isEmpty && symbols.isEmpty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !badges.isEmpty { try container.encode(badges, forKey: .badges) }
        if !colors.isEmpty { try container.encode(colors, forKey: .colors) }
        if !fonts.isEmpty { try container.encode(fonts, forKey: .fonts) }
        if !iconStyles.isEmpty { try container.encode(iconStyles, forKey: .iconStyles) }
        if !labels.isEmpty { try container.encode(labels, forKey: .labels) }
        if !labelStyles.isEmpty { try container.encode(labelStyles, forKey: .labelStyles) }
        if !skinTones.isEmpty { try container.encode(skinTones, forKey: .skinTones) }
        if !symbols.isEmpty { try container.encode(symbols, forKey: .symbols) }
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
        symbols = try container.decodeIfPresent([String: String].self, forKey: .symbols) ?? [:]
    }

    init(
        badges: [Int: SpaceBadge] = [:],
        colors: [Int: SpaceColors] = [:],
        fonts: [Int: SpaceFont] = [:],
        iconStyles: [Int: IconStyle] = [:],
        labels: [Int: String] = [:],
        labelStyles: [Int: IconStyle] = [:],
        skinTones: [Int: SkinTone] = [:],
        symbols: [Int: String] = [:]
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
        self.symbols = symbols.reduce(into: [:]) { result, pair in
            result[String(pair.key)] = pair.value
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

    func toSymbols() -> [Int: String] {
        convertDict(symbols) { $0 }
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
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - CodableSpaceColors

/// Space colors (foreground/background) for JSON serialization.
struct CodableSpaceColors: Codable {
    let foreground: CodableColor
    let background: CodableColor

    init(from colors: SpaceColors) {
        foreground = CodableColor(from: colors.foreground)
        background = CodableColor(from: colors.background)
    }

    func toSpaceColors() -> SpaceColors? {
        SpaceColors(
            foreground: foreground.toNSColor(),
            background: background.toNSColor()
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
        guard let font = NSFont(name: name, size: size) else {
            return nil
        }
        return SpaceFont(font: font)
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

    /// Encodes the current settings to a JSON string.
    static func encode(
        store: DefaultsStore = AppEnvironment.shared.store,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider()
    ) throws -> String {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            throw BackupError.encodingFailed
        }

        let settings = BackupSettings(
            clickToSwitchSpaces: store.clickToSwitchSpaces,
            dimInactiveSpaces: store.dimInactiveSpaces,
            hideEmptySpaces: store.hideEmptySpaces,
            hideFullscreenApps: store.hideFullscreenApps,
            hideSingleSpace: store.hideSingleSpace,
            launchAtLogin: launchAtLogin.isEnabled,
            localSpaceNumbers: store.localSpaceNumbers,
            paddingScale: store.paddingScale,
            separatorColor: store.separatorColor.map { CodableColor(from: $0) },
            showAllDisplays: store.showAllDisplays,
            showAllSpaces: store.showAllSpaces,
            sizeScale: store.sizeScale,
            soundName: store.soundName,
            uniqueIconsPerDisplay: store.uniqueIconsPerDisplay
        )

        let spacePreferences = BackupSpacePreferences(
            badges: store.spaceBadges,
            colors: store.spaceColors,
            fonts: store.spaceFonts,
            iconStyles: store.spaceIconStyles,
            labels: store.spaceLabels,
            labelStyles: store.spaceLabelStyles,
            skinTones: store.spaceSkinTones,
            symbols: store.spaceSymbols
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
        displayIds.formUnion(store.displaySpaceSymbols.keys)

        for displayId in displayIds {
            displaySpacePreferences[displayId] = BackupSpacePreferences(
                badges: store.displaySpaceBadges[displayId] ?? [:],
                colors: store.displaySpaceColors[displayId] ?? [:],
                fonts: store.displaySpaceFonts[displayId] ?? [:],
                iconStyles: store.displaySpaceIconStyles[displayId] ?? [:],
                labels: store.displaySpaceLabels[displayId] ?? [:],
                labelStyles: store.displaySpaceLabelStyles[displayId] ?? [:],
                skinTones: store.displaySpaceSkinTones[displayId] ?? [:],
                symbols: store.displaySpaceSymbols[displayId] ?? [:]
            )
        }

        let backup = Backup(
            bundleId: Bundle.main.bundleIdentifier ?? "com.georgechu.WhichSpace",
            version: version,
            settings: settings,
            spacePreferences: spacePreferences,
            displaySpacePreferences: displaySpacePreferences
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
    static func load(
        from url: URL,
        store: DefaultsStore = AppEnvironment.shared.store,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider()
    ) throws {
        let jsonString: String
        do {
            jsonString = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw BackupError.fileReadFailed(url, error)
        }

        let config = try decode(jsonString: jsonString)
        apply(config, to: store, launchAtLogin: launchAtLogin)
    }

    /// Applies a config to the defaults store.
    static func apply(
        _ backup: Backup,
        to store: DefaultsStore,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider()
    ) {
        // Apply global settings
        store.clickToSwitchSpaces = backup.settings.clickToSwitchSpaces
        store.dimInactiveSpaces = backup.settings.dimInactiveSpaces
        store.hideEmptySpaces = backup.settings.hideEmptySpaces
        store.hideFullscreenApps = backup.settings.hideFullscreenApps
        store.hideSingleSpace = backup.settings.hideSingleSpace
        var launchAtLogin = launchAtLogin
        launchAtLogin.isEnabled = backup.settings.launchAtLogin
        store.localSpaceNumbers = backup.settings.localSpaceNumbers
        store.paddingScale = backup.settings.paddingScale ?? Layout.defaultPaddingScale
        store.separatorColor = backup.settings.separatorColor?.toNSColor()
        store.showAllDisplays = backup.settings.showAllDisplays
        store.showAllSpaces = backup.settings.showAllSpaces
        store.sizeScale = backup.settings.sizeScale
        store.soundName = backup.settings.soundName
        store.uniqueIconsPerDisplay = backup.settings.uniqueIconsPerDisplay

        // Apply shared space preferences
        store.spaceBadges = backup.spacePreferences.toBadges()
        store.spaceColors = backup.spacePreferences.toSpaceColors()
        store.spaceFonts = backup.spacePreferences.toSpaceFonts()
        store.spaceIconStyles = backup.spacePreferences.toIconStyles()
        store.spaceLabels = backup.spacePreferences.toLabels()
        store.spaceLabelStyles = backup.spacePreferences.toLabelStyles()
        store.spaceSkinTones = backup.spacePreferences.toSkinTones()
        store.spaceSymbols = backup.spacePreferences.toSymbols()

        // Apply per-display space preferences
        var displayBadges = [String: [Int: SpaceBadge]]()
        var displayColors = [String: [Int: SpaceColors]]()
        var displayFonts = [String: [Int: SpaceFont]]()
        var displayStyles = [String: [Int: IconStyle]]()
        var displayLabels = [String: [Int: String]]()
        var displayLabelStyles = [String: [Int: IconStyle]]()
        var displayTones = [String: [Int: SkinTone]]()
        var displaySymbols = [String: [Int: String]]()

        for (displayId, prefs) in backup.displaySpacePreferences {
            displayBadges[displayId] = prefs.toBadges()
            displayColors[displayId] = prefs.toSpaceColors()
            displayFonts[displayId] = prefs.toSpaceFonts()
            displayStyles[displayId] = prefs.toIconStyles()
            displayLabels[displayId] = prefs.toLabels()
            displayLabelStyles[displayId] = prefs.toLabelStyles()
            displayTones[displayId] = prefs.toSkinTones()
            displaySymbols[displayId] = prefs.toSymbols()
        }

        store.displaySpaceBadges = displayBadges
        store.displaySpaceColors = displayColors
        store.displaySpaceFonts = displayFonts
        store.displaySpaceIconStyles = displayStyles
        store.displaySpaceLabels = displayLabels
        store.displaySpaceLabelStyles = displayLabelStyles
        store.displaySpaceSkinTones = displayTones
        store.displaySpaceSymbols = displaySymbols

        NotificationCenter.default.post(name: .backupImported, object: nil)
    }

    /// Exports the current configuration to a file URL.
    static func export(
        to url: URL,
        store: DefaultsStore = AppEnvironment.shared.store,
        launchAtLogin: LaunchAtLoginProvider = DefaultLaunchAtLoginProvider()
    ) throws {
        let jsonString = try encode(store: store, launchAtLogin: launchAtLogin)
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
