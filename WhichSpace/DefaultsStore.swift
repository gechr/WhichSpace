import AppKit
import Defaults
import Foundation

// MARK: - KeySpec

/// Describes a Defaults key without binding it to a specific UserDefaults suite.
///
/// This enables creating keys bound to different suites (`.standard` for production,
/// per-test suites for testing) while keeping key definitions centralized.
protocol KeySpec {
    associatedtype Value: Defaults.Serializable
    var name: String { get }
    var defaultValue: Value { get }
}

struct TypedKeySpec<Value: Defaults.Serializable>: KeySpec {
    let name: String
    let defaultValue: Value

    func key(suite: UserDefaults) -> Defaults.Key<Value> {
        Defaults.Key<Value>(name, default: defaultValue, suite: suite)
    }
}

// MARK: - KeySpecs

/// Central definitions of all app Defaults keys.
///
/// Keys are defined as specifications (name + default) rather than bound instances.
/// This enables `DefaultsStore` to create suite-specific keys for testing.
///
/// ## Adding New Keys
/// 1. Add the spec here following the existing pattern
/// 2. Add the corresponding property in `DefaultsStore`
/// 3. Tests will automatically pick up the new key
enum KeySpecs {
    static let clickToSwitchSpaces = TypedKeySpec(name: "clickToSwitchSpaces", defaultValue: false)
    static let dimInactiveSpaces = TypedKeySpec(name: "dimInactiveSpaces", defaultValue: true)
    static let hideEmptySpaces = TypedKeySpec(name: "hideEmptySpaces", defaultValue: false)
    static let hideFullscreenApps = TypedKeySpec(name: "hideFullscreenApps", defaultValue: false)
    static let showAllSpaces = TypedKeySpec(name: "showAllSpaces", defaultValue: false)
    static let showAllDisplays = TypedKeySpec(name: "showAllDisplays", defaultValue: false)
    static let spaceColors = TypedKeySpec(name: "spaceColors", defaultValue: [Int: SpaceColors]())
    static let spaceIconStyles = TypedKeySpec(name: "spaceIconStyles", defaultValue: [Int: IconStyle]())
    static let spaceSFSymbols = TypedKeySpec(name: "spaceSFSymbols", defaultValue: [Int: String]())
    static let sizeScale = TypedKeySpec(name: "sizeScale", defaultValue: Layout.defaultSizeScale)

    // Per-display settings (separate from shared settings for backwards compatibility)
    static let uniqueIconsPerDisplay = TypedKeySpec(name: "uniqueIconsPerDisplay", defaultValue: false)
    static let displaySpaceColors = TypedKeySpec(
        name: "displaySpaceColors",
        defaultValue: [String: [Int: SpaceColors]]()
    )
    static let displaySpaceIconStyles = TypedKeySpec(
        name: "displaySpaceIconStyles",
        defaultValue: [String: [Int: IconStyle]]()
    )
    static let displaySpaceSFSymbols = TypedKeySpec(
        name: "displaySpaceSFSymbols",
        defaultValue: [String: [Int: String]]()
    )
    static let separatorColor = TypedKeySpec(name: "separatorColor", defaultValue: Data?.none)
    static let spaceFonts = TypedKeySpec(name: "spaceFonts", defaultValue: [Int: SpaceFont]())
    static let displaySpaceFonts = TypedKeySpec(
        name: "displaySpaceFonts",
        defaultValue: [String: [Int: SpaceFont]]()
    )

    /// All key names for enumeration (e.g., in tests).
    static let allKeyNames: Set<String> = [
        clickToSwitchSpaces.name,
        dimInactiveSpaces.name,
        displaySpaceColors.name,
        displaySpaceFonts.name,
        displaySpaceIconStyles.name,
        displaySpaceSFSymbols.name,
        hideEmptySpaces.name,
        hideFullscreenApps.name,
        separatorColor.name,
        showAllDisplays.name,
        showAllSpaces.name,
        sizeScale.name,
        spaceColors.name,
        spaceFonts.name,
        spaceIconStyles.name,
        spaceSFSymbols.name,
        uniqueIconsPerDisplay.name,
    ]
}

// MARK: - DefaultsStore

/// Provides access to app preferences backed by a specific UserDefaults suite.
///
/// ## Production Usage
/// Use `DefaultsStore.shared` which uses `UserDefaults.standard`:
/// ```swift
/// let store = DefaultsStore.shared
/// store.showAllSpaces = true
/// ```
///
/// ## Test Usage
/// Create an isolated store with a per-test suite:
/// ```swift
/// let suite = UserDefaults(suiteName: UUID().uuidString)!
/// let store = DefaultsStore(suite: suite)
/// // Each test gets its own isolated store
/// ```
///
/// ## Parallel Test Safety
/// With per-test suites, tests can safely run in parallel without interference.
final class DefaultsStore: @unchecked Sendable {
    /// Shared instance using `UserDefaults.standard` for production use.
    static let shared = DefaultsStore(suite: .standard)

    let suite: UserDefaults

    // Lazily-created keys bound to this store's suite
    private(set) lazy var keyClickToSwitchSpaces = KeySpecs.clickToSwitchSpaces.key(suite: suite)
    private(set) lazy var keyDimInactiveSpaces = KeySpecs.dimInactiveSpaces.key(suite: suite)
    private(set) lazy var keyHideEmptySpaces = KeySpecs.hideEmptySpaces.key(suite: suite)
    private(set) lazy var keyHideFullscreenApps = KeySpecs.hideFullscreenApps.key(suite: suite)
    private(set) lazy var keyShowAllDisplays = KeySpecs.showAllDisplays.key(suite: suite)
    private(set) lazy var keyShowAllSpaces = KeySpecs.showAllSpaces.key(suite: suite)
    private(set) lazy var keySpaceColors = KeySpecs.spaceColors.key(suite: suite)
    private(set) lazy var keySpaceIconStyles = KeySpecs.spaceIconStyles.key(suite: suite)
    private(set) lazy var keySpaceSFSymbols = KeySpecs.spaceSFSymbols.key(suite: suite)
    private(set) lazy var keySizeScale = KeySpecs.sizeScale.key(suite: suite)

    // Per-display keys
    private(set) lazy var keyUniqueIconsPerDisplay = KeySpecs.uniqueIconsPerDisplay.key(suite: suite)
    private(set) lazy var keyDisplaySpaceColors = KeySpecs.displaySpaceColors.key(suite: suite)
    private(set) lazy var keyDisplaySpaceIconStyles = KeySpecs.displaySpaceIconStyles.key(suite: suite)
    private(set) lazy var keyDisplaySpaceSFSymbols = KeySpecs.displaySpaceSFSymbols.key(suite: suite)

    /// Separator color
    private(set) lazy var keySeparatorColor = KeySpecs.separatorColor.key(suite: suite)

    /// Font keys
    private(set) lazy var keySpaceFonts = KeySpecs.spaceFonts.key(suite: suite)
    private(set) lazy var keyDisplaySpaceFonts = KeySpecs.displaySpaceFonts.key(suite: suite)

    init(suite: UserDefaults) {
        self.suite = suite
    }

    // MARK: - Property Accessors

    var clickToSwitchSpaces: Bool {
        get { Defaults[keyClickToSwitchSpaces] }
        set { Defaults[keyClickToSwitchSpaces] = newValue }
    }

    var dimInactiveSpaces: Bool {
        get { Defaults[keyDimInactiveSpaces] }
        set { Defaults[keyDimInactiveSpaces] = newValue }
    }

    var hideEmptySpaces: Bool {
        get { Defaults[keyHideEmptySpaces] }
        set { Defaults[keyHideEmptySpaces] = newValue }
    }

    var hideFullscreenApps: Bool {
        get { Defaults[keyHideFullscreenApps] }
        set { Defaults[keyHideFullscreenApps] = newValue }
    }

    var showAllDisplays: Bool {
        get { Defaults[keyShowAllDisplays] }
        set { Defaults[keyShowAllDisplays] = newValue }
    }

    var showAllSpaces: Bool {
        get { Defaults[keyShowAllSpaces] }
        set { Defaults[keyShowAllSpaces] = newValue }
    }

    var spaceColors: [Int: SpaceColors] {
        get { Defaults[keySpaceColors] }
        set { Defaults[keySpaceColors] = newValue }
    }

    var spaceIconStyles: [Int: IconStyle] {
        get { Defaults[keySpaceIconStyles] }
        set { Defaults[keySpaceIconStyles] = newValue }
    }

    var spaceSFSymbols: [Int: String] {
        get { Defaults[keySpaceSFSymbols] }
        set { Defaults[keySpaceSFSymbols] = newValue }
    }

    var sizeScale: Double {
        get { Defaults[keySizeScale] }
        set { Defaults[keySizeScale] = newValue }
    }

    /// Per-display properties
    var uniqueIconsPerDisplay: Bool {
        get { Defaults[keyUniqueIconsPerDisplay] }
        set { Defaults[keyUniqueIconsPerDisplay] = newValue }
    }

    var displaySpaceColors: [String: [Int: SpaceColors]] {
        get { Defaults[keyDisplaySpaceColors] }
        set { Defaults[keyDisplaySpaceColors] = newValue }
    }

    var displaySpaceIconStyles: [String: [Int: IconStyle]] {
        get { Defaults[keyDisplaySpaceIconStyles] }
        set { Defaults[keyDisplaySpaceIconStyles] = newValue }
    }

    var displaySpaceSFSymbols: [String: [Int: String]] {
        get { Defaults[keyDisplaySpaceSFSymbols] }
        set { Defaults[keyDisplaySpaceSFSymbols] = newValue }
    }

    var spaceFonts: [Int: SpaceFont] {
        get { Defaults[keySpaceFonts] }
        set { Defaults[keySpaceFonts] = newValue }
    }

    var displaySpaceFonts: [String: [Int: SpaceFont]] {
        get { Defaults[keyDisplaySpaceFonts] }
        set { Defaults[keyDisplaySpaceFonts] = newValue }
    }

    var separatorColor: NSColor? {
        get {
            guard let data = Defaults[keySeparatorColor] else {
                return nil
            }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
        }
        set {
            if let color = newValue {
                Defaults[keySeparatorColor] = try? NSKeyedArchiver.archivedData(
                    withRootObject: color,
                    requiringSecureCoding: true
                )
            } else {
                Defaults[keySeparatorColor] = nil
            }
        }
    }

    // MARK: - Utilities

    /// Resets all keys to their default values.
    func resetAll() {
        Defaults.reset(
            keyClickToSwitchSpaces,
            keyDimInactiveSpaces,
            keyDisplaySpaceColors,
            keyDisplaySpaceFonts,
            keyDisplaySpaceIconStyles,
            keyDisplaySpaceSFSymbols,
            keyHideEmptySpaces,
            keyHideFullscreenApps,
            keySeparatorColor,
            keyShowAllDisplays,
            keyShowAllSpaces,
            keySizeScale,
            keySpaceColors,
            keySpaceFonts,
            keySpaceIconStyles,
            keySpaceSFSymbols,
            keyUniqueIconsPerDisplay
        )
    }

    /// Removes the suite's persistent domain (for test cleanup).
    ///
    /// Only call this for non-standard suites created for testing.
    func removeSuite() {
        guard let suiteName = suite.volatileDomainNames.first,
              suite != .standard
        else {
            return
        }
        suite.removePersistentDomain(forName: suiteName)
    }
}
