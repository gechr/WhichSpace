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
    static let dimInactiveSpaces = TypedKeySpec(name: "dimInactiveSpaces", defaultValue: true)
    static let hideEmptySpaces = TypedKeySpec(name: "hideEmptySpaces", defaultValue: false)
    static let showAllSpaces = TypedKeySpec(name: "showAllSpaces", defaultValue: false)
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

    /// All key names for enumeration (e.g., in tests).
    static let allKeyNames: Set<String> = [
        dimInactiveSpaces.name,
        displaySpaceColors.name,
        displaySpaceIconStyles.name,
        displaySpaceSFSymbols.name,
        hideEmptySpaces.name,
        showAllSpaces.name,
        sizeScale.name,
        spaceColors.name,
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
    private(set) lazy var dimInactiveSpacesKey = KeySpecs.dimInactiveSpaces.key(suite: suite)
    private(set) lazy var hideEmptySpacesKey = KeySpecs.hideEmptySpaces.key(suite: suite)
    private(set) lazy var showAllSpacesKey = KeySpecs.showAllSpaces.key(suite: suite)
    private(set) lazy var spaceColorsKey = KeySpecs.spaceColors.key(suite: suite)
    private(set) lazy var spaceIconStylesKey = KeySpecs.spaceIconStyles.key(suite: suite)
    private(set) lazy var spaceSFSymbolsKey = KeySpecs.spaceSFSymbols.key(suite: suite)
    private(set) lazy var sizeScaleKey = KeySpecs.sizeScale.key(suite: suite)

    // Per-display keys
    private(set) lazy var uniqueIconsPerDisplayKey = KeySpecs.uniqueIconsPerDisplay.key(suite: suite)
    private(set) lazy var displaySpaceColorsKey = KeySpecs.displaySpaceColors.key(suite: suite)
    private(set) lazy var displaySpaceIconStylesKey = KeySpecs.displaySpaceIconStyles.key(suite: suite)
    private(set) lazy var displaySpaceSFSymbolsKey = KeySpecs.displaySpaceSFSymbols.key(suite: suite)

    init(suite: UserDefaults) {
        self.suite = suite
    }

    // MARK: - Property Accessors

    var dimInactiveSpaces: Bool {
        get { Defaults[dimInactiveSpacesKey] }
        set { Defaults[dimInactiveSpacesKey] = newValue }
    }

    var hideEmptySpaces: Bool {
        get { Defaults[hideEmptySpacesKey] }
        set { Defaults[hideEmptySpacesKey] = newValue }
    }

    var showAllSpaces: Bool {
        get { Defaults[showAllSpacesKey] }
        set { Defaults[showAllSpacesKey] = newValue }
    }

    var spaceColors: [Int: SpaceColors] {
        get { Defaults[spaceColorsKey] }
        set { Defaults[spaceColorsKey] = newValue }
    }

    var spaceIconStyles: [Int: IconStyle] {
        get { Defaults[spaceIconStylesKey] }
        set { Defaults[spaceIconStylesKey] = newValue }
    }

    var spaceSFSymbols: [Int: String] {
        get { Defaults[spaceSFSymbolsKey] }
        set { Defaults[spaceSFSymbolsKey] = newValue }
    }

    var sizeScale: Double {
        get { Defaults[sizeScaleKey] }
        set { Defaults[sizeScaleKey] = newValue }
    }

    /// Per-display properties
    var uniqueIconsPerDisplay: Bool {
        get { Defaults[uniqueIconsPerDisplayKey] }
        set { Defaults[uniqueIconsPerDisplayKey] = newValue }
    }

    var displaySpaceColors: [String: [Int: SpaceColors]] {
        get { Defaults[displaySpaceColorsKey] }
        set { Defaults[displaySpaceColorsKey] = newValue }
    }

    var displaySpaceIconStyles: [String: [Int: IconStyle]] {
        get { Defaults[displaySpaceIconStylesKey] }
        set { Defaults[displaySpaceIconStylesKey] = newValue }
    }

    var displaySpaceSFSymbols: [String: [Int: String]] {
        get { Defaults[displaySpaceSFSymbolsKey] }
        set { Defaults[displaySpaceSFSymbolsKey] = newValue }
    }

    // MARK: - Utilities

    /// Resets all keys to their default values.
    func resetAll() {
        Defaults.reset(
            dimInactiveSpacesKey,
            displaySpaceColorsKey,
            displaySpaceIconStylesKey,
            displaySpaceSFSymbolsKey,
            hideEmptySpacesKey,
            showAllSpacesKey,
            sizeScaleKey,
            spaceColorsKey,
            spaceIconStylesKey,
            spaceSFSymbolsKey,
            uniqueIconsPerDisplayKey
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
