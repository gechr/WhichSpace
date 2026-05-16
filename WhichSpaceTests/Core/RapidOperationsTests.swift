import Cocoa
import Defaults
import Testing
@testable import WhichSpace

// MARK: - Rapid Operations Tests

@MainActor
struct RapidOperationsTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    // MARK: - Rapid Preference Changes

    @Test("rapid color changes settle on final value")
    func rapidColorChanges() {
        for idx in 0 ..< 100 {
            let colors = SpaceColors(
                foreground: NSColor(calibratedHue: Double(idx) / 100.0, saturation: 1, brightness: 1, alpha: 1),
                background: NSColor(calibratedHue: Double(99 - idx) / 100.0, saturation: 1, brightness: 1, alpha: 1)
            )
            SpacePreferences.setColors(colors, forSpace: 1, store: store)
        }

        let final = SpacePreferences.colors(forSpace: 1, store: store)
        #expect(final != nil)
    }

    @Test("rapid style changes settle on last style")
    func rapidStyleChanges() {
        for _ in 0 ..< 50 {
            for style in IconStyle.allCases {
                SpacePreferences.setIconStyle(style, forSpace: 1, store: store)
            }
        }

        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == IconStyle.allCases.last)
    }

    @Test("rapid symbol changes settle on valid value")
    func rapidSymbolChanges() {
        let symbols = ItemData.symbols
        for _ in 0 ..< 20 {
            for symbol in symbols.prefix(50) {
                SpacePreferences.setSymbol(symbol, forSpace: 1, store: store)
            }
        }

        #expect(SpacePreferences.symbol(forSpace: 1, store: store) != nil)
    }

    // MARK: - Rapid Toggle Operations

    @Test("rapid uniqueIconsPerDisplay toggle persists both storage paths")
    func rapidUniqueIconsPerDisplayToggle() {
        for _ in 0 ..< 100 {
            store.uniqueIconsPerDisplay = true
            SpacePreferences.setIconStyle(.circle, forSpace: 1, display: "Display1", store: store)

            store.uniqueIconsPerDisplay = false
            SpacePreferences.setIconStyle(.square, forSpace: 1, store: store)
        }

        store.uniqueIconsPerDisplay = true
        #expect(SpacePreferences.iconStyle(forSpace: 1, display: "Display1", store: store) == .circle)

        store.uniqueIconsPerDisplay = false
        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == .square)
    }

    // MARK: - Concurrent-Like Access Patterns

    @Test("setting preferences for many spaces at once")
    func manySpacesSimultaneously() {
        for space in 1 ... 100 {
            SpacePreferences.setIconStyle(.circle, forSpace: space, store: store)
            SpacePreferences.setSymbol("star.fill", forSpace: space, store: store)
            SpacePreferences.setColors(
                SpaceColors(foreground: .red, background: .blue),
                forSpace: space,
                store: store
            )
        }

        for space in 1 ... 100 {
            #expect(SpacePreferences.iconStyle(forSpace: space, store: store) == .circle)
            #expect(SpacePreferences.symbol(forSpace: space, store: store) == "star.fill")
            #expect(SpacePreferences.colors(forSpace: space, store: store) != nil)
        }
    }

    @Test("setting preferences for many displays at once")
    func manyDisplaysSimultaneously() {
        store.uniqueIconsPerDisplay = true

        for displayNum in 1 ... 20 {
            let displayID = "Display\(displayNum)"
            for space in 1 ... 10 {
                SpacePreferences.setIconStyle(.hexagon, forSpace: space, display: displayID, store: store)
            }
        }

        for displayNum in 1 ... 20 {
            let displayID = "Display\(displayNum)"
            for space in 1 ... 10 {
                #expect(SpacePreferences.iconStyle(forSpace: space, display: displayID, store: store) == .hexagon)
            }
        }
    }

    // MARK: - Clear All Under Load

    @Test("clearAll removes all preferences under load")
    func clearAllWithManyPreferences() {
        for space in 1 ... 50 {
            SpacePreferences.setIconStyle(.circle, forSpace: space, store: store)
            SpacePreferences.setSymbol("star", forSpace: space, store: store)
            SpacePreferences.setColors(
                SpaceColors(foreground: .red, background: .blue),
                forSpace: space,
                store: store
            )
        }

        store.uniqueIconsPerDisplay = true
        for displayNum in 1 ... 5 {
            let displayID = "Display\(displayNum)"
            for space in 1 ... 10 {
                SpacePreferences.setIconStyle(.square, forSpace: space, display: displayID, store: store)
            }
        }

        SpacePreferences.clearAll(store: store)

        for space in 1 ... 50 {
            #expect(SpacePreferences.iconStyle(forSpace: space, store: store) == nil)
            #expect(SpacePreferences.symbol(forSpace: space, store: store) == nil)
            #expect(SpacePreferences.colors(forSpace: space, store: store) == nil)
        }

        for displayNum in 1 ... 5 {
            let displayID = "Display\(displayNum)"
            for space in 1 ... 10 {
                #expect(SpacePreferences.iconStyle(forSpace: space, display: displayID, store: store) == nil)
            }
        }
    }

    // MARK: - Icon Generation Under Load

    @Test("rapid icon generation across all styles")
    func rapidIconGeneration() {
        for _ in 0 ..< 100 {
            for style in IconStyle.allCases {
                let image = SpaceIconGenerator.generateIcon(
                    for: "1",
                    darkMode: false,
                    customColors: nil,
                    customFont: nil,
                    style: style
                )
                #expect(image as NSImage? != nil)
            }
        }
    }

    @Test("rapid symbol icon generation")
    func rapidSymbolIconGeneration() {
        let symbols = ["star.fill", "heart.fill", "circle.fill", "square.fill", "triangle.fill"]

        for _ in 0 ..< 50 {
            for symbol in symbols {
                let image = SpaceIconGenerator.generateSymbolIcon(
                    symbolName: symbol,
                    darkMode: false,
                    customColors: nil,
                    skinTone: nil
                )
                #expect(image as NSImage? != nil)
            }
        }
    }

    @Test("rapid emoji icon generation across skin tones")
    func rapidEmojiIconGeneration() {
        let emojis = ["😀", "👋", "🎉", "❤️", "🌟"]

        for _ in 0 ..< 50 {
            for emoji in emojis {
                for tone in SkinTone.allCases {
                    let image = SpaceIconGenerator.generateSymbolIcon(
                        symbolName: emoji,
                        darkMode: false,
                        customColors: nil,
                        skinTone: tone
                    )
                    #expect(image as NSImage? != nil)
                }
            }
        }
    }
}
