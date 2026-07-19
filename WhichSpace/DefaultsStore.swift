import AppKit
import Defaults

struct TypedKeySpec<Value: Defaults.Serializable>: @unchecked Sendable {
    let name: String
    let defaultValue: Value

    func key(suite: UserDefaults) -> Defaults.Key<Value> {
        Defaults.Key<Value>(name, default: defaultValue, suite: suite)
    }
}

/// Type-erased view of a `TypedKeySpec`, for heterogeneous registries.
protocol AnyKeySpec: Sendable {
    var name: String { get }
    func anyKey(suite: UserDefaults) -> Defaults._AnyKey
}

extension TypedKeySpec: AnyKeySpec {
    func anyKey(suite: UserDefaults) -> Defaults._AnyKey {
        key(suite: suite)
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
    static let displaySpaceBadges = TypedKeySpec(
        name: "displaySpaceBadges",
        defaultValue: [String: [Int: SpaceBadge]]()
    )
    static let displaySpaceColors = TypedKeySpec(
        name: "displaySpaceColors",
        defaultValue: [String: [Int: SpaceColors]]()
    )
    static let displaySpaceFonts = TypedKeySpec(
        name: "displaySpaceFonts",
        defaultValue: [String: [Int: SpaceFont]]()
    )
    static let displaySpaceIconStyles = TypedKeySpec(
        name: "displaySpaceIconStyles",
        defaultValue: [String: [Int: IconStyle]]()
    )
    static let displaySpaceLabels = TypedKeySpec(
        name: "displaySpaceLabels",
        defaultValue: [String: [Int: String]]()
    )
    static let displaySpaceLabelStyles = TypedKeySpec(
        name: "displaySpaceLabelStyles",
        defaultValue: [String: [Int: IconStyle]]()
    )
    static let displaySpaceSkinTones = TypedKeySpec(
        name: "displaySpaceSkinTones",
        defaultValue: [String: [Int: SkinTone]]()
    )
    static let displaySpaceSymbols = TypedKeySpec(
        name: "displaySpaceSymbols",
        defaultValue: [String: [Int: String]]()
    )
    static let fullscreenIconStyle = TypedKeySpec(
        name: "fullscreenIconStyle",
        defaultValue: FullscreenIconStyle.appIcon
    )
    static let horizontalScrollEnabled = TypedKeySpec(name: "horizontalScrollEnabled", defaultValue: false)
    static let invertHorizontalScroll = TypedKeySpec(name: "invertHorizontalScroll", defaultValue: false)
    static let invertVerticalScroll = TypedKeySpec(name: "invertVerticalScroll", defaultValue: false)
    static let paddingScale = TypedKeySpec(name: "paddingScale", defaultValue: Layout.defaultPaddingScale)
    static let hideEmptySpaces = TypedKeySpec(name: "hideEmptySpaces", defaultValue: false)
    static let hideFullscreenApps = TypedKeySpec(name: "hideFullscreenApps", defaultValue: false)
    static let hideSingleSpace = TypedKeySpec(name: "hideSingleSpace", defaultValue: false)
    static let localSpaceNumbers = TypedKeySpec(name: "localSpaceNumbers", defaultValue: false)
    static let scrollSensitivity = TypedKeySpec(
        name: "scrollSensitivity",
        defaultValue: Layout.defaultScrollSensitivity
    )
    static let verticalScrollEnabled = TypedKeySpec(name: "verticalScrollEnabled", defaultValue: false)
    static let separatorColor = TypedKeySpec(name: "separatorColor", defaultValue: Data?.none)
    static let showAllDisplays = TypedKeySpec(name: "showAllDisplays", defaultValue: false)
    static let showAllSpaces = TypedKeySpec(name: "showAllSpaces", defaultValue: false)
    static let sizeScale = TypedKeySpec(name: "sizeScale", defaultValue: Layout.defaultSizeScale)
    static let soundName = TypedKeySpec(name: "soundName", defaultValue: "")
    static let spaceBadges = TypedKeySpec(name: "spaceBadges", defaultValue: [Int: SpaceBadge]())
    static let spaceColors = TypedKeySpec(name: "spaceColors", defaultValue: [Int: SpaceColors]())
    static let spaceFonts = TypedKeySpec(name: "spaceFonts", defaultValue: [Int: SpaceFont]())
    static let spaceIconStyles = TypedKeySpec(name: "spaceIconStyles", defaultValue: [Int: IconStyle]())
    static let spaceLabels = TypedKeySpec(name: "spaceLabels", defaultValue: [Int: String]())
    static let spaceLabelStyles = TypedKeySpec(name: "spaceLabelStyles", defaultValue: [Int: IconStyle]())
    static let spaceSkinTones = TypedKeySpec(name: "spaceSkinTones", defaultValue: [Int: SkinTone]())
    static let spaceSymbols = TypedKeySpec(name: "spaceSymbols", defaultValue: [Int: String]())
    static let uniqueIconsPerDisplay = TypedKeySpec(name: "uniqueIconsPerDisplay", defaultValue: false)

    /// The single key registry: reset, test enumeration, and icon-change
    /// observation all derive from it, so a new key only needs an entry
    /// here and a `DefaultsStore` accessor.
    static let allSpecs: [any AnyKeySpec] = [
        clickToSwitchSpaces,
        dimInactiveSpaces,
        displaySpaceBadges,
        displaySpaceColors,
        displaySpaceFonts,
        displaySpaceIconStyles,
        displaySpaceLabels,
        displaySpaceLabelStyles,
        displaySpaceSkinTones,
        displaySpaceSymbols,
        fullscreenIconStyle,
        hideEmptySpaces,
        hideFullscreenApps,
        hideSingleSpace,
        horizontalScrollEnabled,
        invertHorizontalScroll,
        invertVerticalScroll,
        localSpaceNumbers,
        paddingScale,
        scrollSensitivity,
        separatorColor,
        showAllDisplays,
        showAllSpaces,
        sizeScale,
        soundName,
        spaceBadges,
        spaceColors,
        spaceFonts,
        spaceIconStyles,
        spaceLabels,
        spaceLabelStyles,
        spaceSkinTones,
        spaceSymbols,
        uniqueIconsPerDisplay,
        verticalScrollEnabled,
    ]

    /// Keys that never affect status bar icon rendering. Everything else is
    /// observed for external defaults writes, so a newly added key is
    /// icon-affecting by default - the safe direction for cache invalidation.
    static let nonIconKeyNames: Set<String> = [
        clickToSwitchSpaces.name,
        horizontalScrollEnabled.name,
        invertHorizontalScroll.name,
        invertVerticalScroll.name,
        scrollSensitivity.name,
        soundName.name,
        verticalScrollEnabled.name,
    ]

    /// All key names for enumeration (e.g. in tests).
    static var allKeyNames: Set<String> {
        Set(allSpecs.map(\.name))
    }
}

// MARK: - DefaultsStore

/// Provides access to app preferences backed by a specific UserDefaults suite.
///
/// ## Production Usage
/// Use `AppEnvironment.shared.store` which uses `UserDefaults.standard`:
/// ```swift
/// let store = AppEnvironment.shared.store
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
@MainActor
final class DefaultsStore {
    let suite: UserDefaults

    /// Incremented on every write; a cheap change token for caches keyed on preferences
    private(set) var mutationCount = 0

    /// Memoized decoded values, keyed by spec name. The `Defaults` library
    /// does NOT cache reads - every get re-deserializes the entire stored
    /// value (an `NSKeyedUnarchiver` round-trip per entry for colors and
    /// fonts), which makes per-space reads O(n) and a full render pass
    /// O(n^2) in customized spaces. Populated on first read, refreshed on
    /// write, dropped via `invalidateCachedValues()` for external changes.
    private var cachedValues: [String: Any] = [:]
    private var cachedSeparatorColor: NSColor??

    init(suite: UserDefaults) {
        self.suite = suite
    }

    /// Read/write a defaults value via its `TypedKeySpec`, memoizing decoded
    /// values so repeated reads don't re-deserialize the whole value.
    private subscript<V>(spec: TypedKeySpec<V>) -> V {
        get {
            if let cached = cachedValues[spec.name] as? V {
                return cached
            }
            let value = Defaults[spec.key(suite: suite)]
            cachedValues[spec.name] = value
            return value
        }
        set {
            Defaults[spec.key(suite: suite)] = newValue
            cachedValues[spec.name] = newValue
            mutationCount += 1
        }
    }

    /// Drops memoized decoded values. Call when the underlying suite changes
    /// outside this store (e.g. an external `defaults write`).
    func invalidateCachedValues() {
        cachedValues.removeAll()
        cachedSeparatorColor = nil
    }

    /// Returns a suite-bound `Defaults.Key` for the given spec. Used by callers
    /// that need a typed key for observation (e.g. `Defaults.updates(_:)`)
    /// rather than a value.
    func keyFor<V>(_ spec: TypedKeySpec<V>) -> Defaults.Key<V> {
        spec.key(suite: suite)
    }

    /// All suite-bound keys, derived from the `KeySpecs` registry.
    var allKeys: [Defaults._AnyKey] {
        KeySpecs.allSpecs.map { $0.anyKey(suite: suite) }
    }

    /// Suite-bound keys for every preference that can affect status bar
    /// icon rendering, for observing external defaults writes.
    var iconAffectingKeys: [Defaults._AnyKey] {
        KeySpecs.allSpecs
            .filter { !KeySpecs.nonIconKeyNames.contains($0.name) }
            .map { $0.anyKey(suite: suite) }
    }

    // MARK: - Property Accessors

    var clickToSwitchSpaces: Bool {
        get { self[KeySpecs.clickToSwitchSpaces] }
        set { self[KeySpecs.clickToSwitchSpaces] = newValue }
    }

    var dimInactiveSpaces: Bool {
        get { self[KeySpecs.dimInactiveSpaces] }
        set { self[KeySpecs.dimInactiveSpaces] = newValue }
    }

    var displaySpaceBadges: [String: [Int: SpaceBadge]] {
        get { self[KeySpecs.displaySpaceBadges] }
        set { self[KeySpecs.displaySpaceBadges] = newValue }
    }

    var displaySpaceColors: [String: [Int: SpaceColors]] {
        get { self[KeySpecs.displaySpaceColors] }
        set { self[KeySpecs.displaySpaceColors] = newValue }
    }

    var displaySpaceFonts: [String: [Int: SpaceFont]] {
        get { self[KeySpecs.displaySpaceFonts] }
        set { self[KeySpecs.displaySpaceFonts] = newValue }
    }

    var displaySpaceIconStyles: [String: [Int: IconStyle]] {
        get { self[KeySpecs.displaySpaceIconStyles] }
        set { self[KeySpecs.displaySpaceIconStyles] = newValue }
    }

    var displaySpaceLabels: [String: [Int: String]] {
        get { self[KeySpecs.displaySpaceLabels] }
        set { self[KeySpecs.displaySpaceLabels] = newValue }
    }

    var displaySpaceLabelStyles: [String: [Int: IconStyle]] {
        get { self[KeySpecs.displaySpaceLabelStyles] }
        set { self[KeySpecs.displaySpaceLabelStyles] = newValue }
    }

    var displaySpaceSkinTones: [String: [Int: SkinTone]] {
        get { self[KeySpecs.displaySpaceSkinTones] }
        set { self[KeySpecs.displaySpaceSkinTones] = newValue }
    }

    var displaySpaceSymbols: [String: [Int: String]] {
        get { self[KeySpecs.displaySpaceSymbols] }
        set { self[KeySpecs.displaySpaceSymbols] = newValue }
    }

    var fullscreenIconStyle: FullscreenIconStyle {
        get { self[KeySpecs.fullscreenIconStyle] }
        set { self[KeySpecs.fullscreenIconStyle] = newValue }
    }

    var hideEmptySpaces: Bool {
        get { self[KeySpecs.hideEmptySpaces] }
        set { self[KeySpecs.hideEmptySpaces] = newValue }
    }

    var hideFullscreenApps: Bool {
        get { self[KeySpecs.hideFullscreenApps] }
        set { self[KeySpecs.hideFullscreenApps] = newValue }
    }

    var hideSingleSpace: Bool {
        get { self[KeySpecs.hideSingleSpace] }
        set { self[KeySpecs.hideSingleSpace] = newValue }
    }

    var horizontalScrollEnabled: Bool {
        get { self[KeySpecs.horizontalScrollEnabled] }
        set { self[KeySpecs.horizontalScrollEnabled] = newValue }
    }

    var invertHorizontalScroll: Bool {
        get { self[KeySpecs.invertHorizontalScroll] }
        set { self[KeySpecs.invertHorizontalScroll] = newValue }
    }

    var invertVerticalScroll: Bool {
        get { self[KeySpecs.invertVerticalScroll] }
        set { self[KeySpecs.invertVerticalScroll] = newValue }
    }

    var localSpaceNumbers: Bool {
        get { self[KeySpecs.localSpaceNumbers] }
        set { self[KeySpecs.localSpaceNumbers] = newValue }
    }

    var paddingScale: Double {
        get { self[KeySpecs.paddingScale] }
        set { self[KeySpecs.paddingScale] = newValue }
    }

    var scrollSensitivity: Double {
        get { self[KeySpecs.scrollSensitivity] }
        set { self[KeySpecs.scrollSensitivity] = newValue }
    }

    var separatorColor: NSColor? {
        get {
            if let cached = cachedSeparatorColor {
                return cached
            }
            guard let data = self[KeySpecs.separatorColor]
            else {
                cachedSeparatorColor = .some(nil)
                return nil
            }
            do {
                let color = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data)
                cachedSeparatorColor = .some(color)
                return color
            } catch {
                NSLog("DefaultsStore: failed to unarchive separatorColor: %@", error.localizedDescription)
                return nil
            }
        }
        set {
            cachedSeparatorColor = .some(newValue)
            if let color = newValue {
                do {
                    self[KeySpecs.separatorColor] = try NSKeyedArchiver.archivedData(
                        withRootObject: color,
                        requiringSecureCoding: true
                    )
                } catch {
                    NSLog("DefaultsStore: failed to archive separatorColor: %@", error.localizedDescription)
                }
            } else {
                self[KeySpecs.separatorColor] = nil
            }
        }
    }

    var showAllDisplays: Bool {
        get { self[KeySpecs.showAllDisplays] }
        set { self[KeySpecs.showAllDisplays] = newValue }
    }

    var showAllSpaces: Bool {
        get { self[KeySpecs.showAllSpaces] }
        set { self[KeySpecs.showAllSpaces] = newValue }
    }

    var sizeScale: Double {
        get { self[KeySpecs.sizeScale] }
        set { self[KeySpecs.sizeScale] = newValue }
    }

    var soundName: String {
        get { self[KeySpecs.soundName] }
        set { self[KeySpecs.soundName] = newValue }
    }

    var spaceBadges: [Int: SpaceBadge] {
        get { self[KeySpecs.spaceBadges] }
        set { self[KeySpecs.spaceBadges] = newValue }
    }

    var spaceColors: [Int: SpaceColors] {
        get { self[KeySpecs.spaceColors] }
        set { self[KeySpecs.spaceColors] = newValue }
    }

    var spaceFonts: [Int: SpaceFont] {
        get { self[KeySpecs.spaceFonts] }
        set { self[KeySpecs.spaceFonts] = newValue }
    }

    var spaceIconStyles: [Int: IconStyle] {
        get { self[KeySpecs.spaceIconStyles] }
        set { self[KeySpecs.spaceIconStyles] = newValue }
    }

    var spaceLabels: [Int: String] {
        get { self[KeySpecs.spaceLabels] }
        set { self[KeySpecs.spaceLabels] = newValue }
    }

    var spaceLabelStyles: [Int: IconStyle] {
        get { self[KeySpecs.spaceLabelStyles] }
        set { self[KeySpecs.spaceLabelStyles] = newValue }
    }

    var spaceSkinTones: [Int: SkinTone] {
        get { self[KeySpecs.spaceSkinTones] }
        set { self[KeySpecs.spaceSkinTones] = newValue }
    }

    var spaceSymbols: [Int: String] {
        get { self[KeySpecs.spaceSymbols] }
        set { self[KeySpecs.spaceSymbols] = newValue }
    }

    var uniqueIconsPerDisplay: Bool {
        get { self[KeySpecs.uniqueIconsPerDisplay] }
        set { self[KeySpecs.uniqueIconsPerDisplay] = newValue }
    }

    var verticalScrollEnabled: Bool {
        get { self[KeySpecs.verticalScrollEnabled] }
        set { self[KeySpecs.verticalScrollEnabled] = newValue }
    }

    // MARK: - Utilities

    /// Resets all keys to their default values.
    func resetAll() {
        invalidateCachedValues()
        mutationCount += 1
        Defaults.reset(allKeys)
    }
}
