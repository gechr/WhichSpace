import Testing
@testable import WhichSpace

@MainActor
struct SpaceDefaultStyleTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    /// Builds a template by styling space 1 and saving it, mirroring the
    /// settings flow. saveDefaultStyle strips the source, so space 1 ends
    /// up inheriting the template it produced.
    private func saveTemplate(style: IconStyle = .circle, symbol: String? = nil) {
        SpacePreferences.setIconStyle(style, forSpace: 1, store: store)
        if let symbol {
            SpacePreferences.setSymbol(symbol, forSpace: 1, store: store)
        }
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)
    }

    // MARK: - Live Inheritance

    @Test("space without its own style resolves the template")
    func unconfiguredSpace_resolvesTemplate() {
        saveTemplate(style: .circle, symbol: "star.fill")

        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == .circle)
        #expect(SpacePreferences.symbol(forSpace: 3, store: store) == "star.fill")
    }

    @Test("own preference wins over the template")
    func ownPreference_winsOverTemplate() {
        saveTemplate(style: .circle)
        SpacePreferences.setIconStyle(.hexagon, forSpace: 3, store: store)

        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == .hexagon)
    }

    @Test("cascade falls back per key, not per space")
    func cascade_isPerKey() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store
        )
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)
        SpacePreferences.setSymbol("flame.fill", forSpace: 3, store: store)

        // Space 3 keeps its symbol and inherits everything else
        #expect(SpacePreferences.symbol(forSpace: 3, store: store) == "flame.fill")
        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == .circle)
        #expect(SpacePreferences.colors(forSpace: 3, store: store)?.foreground == .red)
    }

    @Test("template edits reach inheriting spaces immediately")
    func templateEdit_reachesInheritors() {
        saveTemplate(style: .circle)
        SpacePreferences.setIconStyle(
            .hexagon, forSpace: SpacePreferences.defaultStyleSpace, store: store
        )

        #expect(SpacePreferences.iconStyle(forSpace: 5, store: store) == .hexagon)
    }

    @Test("template does not fall back to itself")
    func template_doesNotFallBackToItself() {
        #expect(SpacePreferences.iconStyle(forSpace: SpacePreferences.defaultStyleSpace, store: store) == nil)
        #expect(!SpacePreferences.hasDefaultStyle(store: store))
    }

    @Test("no template means no fallback")
    func noTemplate_noFallback() {
        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == nil)
        #expect(!SpacePreferences.hasAnyPreference(forSpace: 3, store: store))
    }

    @Test("clearing a preference returns the space to the template")
    func clear_returnsToTemplate() {
        saveTemplate(style: .circle)
        SpacePreferences.setIconStyle(.hexagon, forSpace: 3, store: store)
        SpacePreferences.clearIconStyle(forSpace: 3, store: store)

        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == .circle)
    }

    @Test("empty-string sentinels stop the cascade for symbol and label")
    func sentinels_stopCascade() {
        SpacePreferences.setSymbol("star.fill", forSpace: 1, store: store)
        SpacePreferences.setLabel("Work", forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        SpacePreferences.setSymbol("", forSpace: 3, store: store)
        SpacePreferences.setLabel("", forSpace: 3, store: store)

        #expect(SpacePreferences.symbol(forSpace: 3, store: store) == nil)
        #expect(SpacePreferences.label(forSpace: 3, store: store) == nil)
        // Other spaces still inherit
        #expect(SpacePreferences.symbol(forSpace: 4, store: store) == "star.fill")
        #expect(SpacePreferences.label(forSpace: 4, store: store) == "Work")
    }

    @Test("sound does not cascade from the template slot")
    func sound_doesNotCascade() {
        SpacePreferences.setSound(
            "Glass", forSpace: SpacePreferences.defaultStyleSpace, store: store
        )

        #expect(SpacePreferences.sound(forSpace: 3, store: store) == nil)
    }

    @Test("per-display value wins, absent per-display falls back to the shared template")
    func perDisplay_fallsBackToSharedTemplate() {
        saveTemplate(style: .circle)
        SpacePreferences.setIconStyle(.hexagon, forSpace: 2, display: "Main", store: store)

        #expect(SpacePreferences.iconStyle(forSpace: 2, display: "Main", store: store) == .hexagon)
        #expect(SpacePreferences.iconStyle(forSpace: 3, display: "Main", store: store) == .circle)
        #expect(SpacePreferences.iconStyle(forSpace: 2, display: "Secondary", store: store) == .circle)
    }

    // MARK: - Save as Default

    @Test("saveDefaultStyle strips the source space into an inheritor")
    func saveDefaultStyle_stripsSource() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setColors(
            SpaceColors(foreground: .red, background: .blue), forSpace: 1, store: store
        )
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        #expect(!SpacePreferences.hasAnyPreference(forSpace: 1, store: store))
        #expect(SpacePreferences.hasDefaultStyle(store: store))
        // The source renders identically, now via the cascade
        #expect(SpacePreferences.iconStyle(forSpace: 1, store: store) == .circle)
        #expect(SpacePreferences.colors(forSpace: 1, store: store)?.foreground == .red)
    }

    @Test("saveDefaultStyle leaves the source's sound alone")
    func saveDefaultStyle_keepsSourceSound() {
        SpacePreferences.setIconStyle(.circle, forSpace: 1, store: store)
        SpacePreferences.setSound("Glass", forSpace: 1, store: store)
        SpacePreferences.saveDefaultStyle(fromSpace: 1, store: store)

        #expect(SpacePreferences.sound(forSpace: 1, store: store) == "Glass")
        #expect(SpacePreferences.sound(forSpace: SpacePreferences.defaultStyleSpace, store: store) == nil)
    }

    // MARK: - Migration

    /// Re-creates what the retired creation-time stamp wrote: a full copy
    /// of the template's preferences under a space's own keys.
    private func stamp(space: Int) {
        SpacePreferences.copyPreferences(
            from: SpacePreferences.defaultStyleSpace, to: space, fromDisplay: nil, toDisplay: nil, store: store
        )
    }

    @Test("migration strips spaces whose stored preferences match the template")
    func migration_stripsExactMatches() {
        saveTemplate(style: .circle, symbol: "star.fill")
        stamp(space: 2)
        stamp(space: 3)
        SpacePreferences.setSound("Glass", forSpace: 3, store: store)

        SpacePreferences.migrateStampedTemplateCopies(store: store)

        #expect(!SpacePreferences.hasAnyPreference(forSpace: 2, store: store))
        // The sound-only leftover survives; the stamped copies are gone
        #expect(SpacePreferences.sound(forSpace: 3, store: store) == "Glass")
        #expect(store.spaceIconStyles[3] == nil)
        // Rendering is unchanged: both spaces resolve the template
        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == .circle)
        #expect(SpacePreferences.iconStyle(forSpace: 3, store: store) == .circle)
    }

    @Test("migration keeps spaces that differ from the template")
    func migration_keepsDifferingSpaces() {
        saveTemplate(style: .circle, symbol: "star.fill")
        stamp(space: 2)
        SpacePreferences.setIconStyle(.hexagon, forSpace: 2, store: store)

        SpacePreferences.migrateStampedTemplateCopies(store: store)

        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == .hexagon)
        #expect(store.spaceSymbols[2] == "star.fill")
    }

    @Test("migration scans per-display copies regardless of the current storage mode")
    func migration_stripsPerDisplayCopies() {
        saveTemplate(style: .circle)
        // A stamp written while the per-display toggle was on
        store.displaySpaceIconStyles = ["Main": [2: .circle]]

        SpacePreferences.migrateStampedTemplateCopies(store: store)

        #expect(store.displaySpaceIconStyles["Main"]?[2] == nil)
    }

    @Test("migration runs once")
    func migration_runsOnce() {
        saveTemplate(style: .circle)
        SpacePreferences.migrateStampedTemplateCopies(store: store)
        #expect(store.spaceStyleMigrationVersion == 1)

        stamp(space: 2)
        SpacePreferences.migrateStampedTemplateCopies(store: store)

        #expect(store.spaceIconStyles[2] == .circle)
    }

    @Test("migration without a template only sets the flag")
    func migration_withoutTemplate_setsFlagOnly() {
        SpacePreferences.setIconStyle(.hexagon, forSpace: 2, store: store)
        var snapshotCalls = 0

        SpacePreferences.migrateStampedTemplateCopies(store: store) {
            snapshotCalls += 1
        }

        #expect(store.spaceStyleMigrationVersion == 1)
        #expect(snapshotCalls == 0)
        #expect(SpacePreferences.iconStyle(forSpace: 2, store: store) == .hexagon)
    }

    @Test("migration snapshots before stripping")
    func migration_snapshotsFirst() {
        saveTemplate(style: .circle)
        stamp(space: 2)
        var snapshotCalls = 0

        SpacePreferences.migrateStampedTemplateCopies(store: store) {
            snapshotCalls += 1
            #expect(store.spaceIconStyles[2] == .circle)
        }

        #expect(snapshotCalls == 1)
        #expect(store.spaceIconStyles[2] == nil)
    }

    // MARK: - Scope Migration

    @Test("scope migration purges per-display data when the toggle was off")
    func scopeMigration_toggleOff() {
        store.spaceStyleMigrationVersion = 1
        store.suite.set(false, forKey: "uniqueIconsPerDisplay")
        store.displaySpaceIconStyles = ["Main": [2: .circle]]
        var snapshotCalls = 0

        SpacePreferences.migrateDisplayScopeOverrides(store: store) {
            snapshotCalls += 1
        }

        #expect(store.displaySpaceIconStyles.isEmpty)
        #expect(store.spaceStyleMigrationVersion == 2)
        #expect(store.suite.object(forKey: "uniqueIconsPerDisplay") == nil)
        #expect(snapshotCalls == 1)
    }

    @Test("scope migration purges shared per-space data when the toggle was on")
    func scopeMigration_toggleOn() {
        store.spaceStyleMigrationVersion = 1
        store.suite.set(true, forKey: "uniqueIconsPerDisplay")
        store.spaceIconStyles = [0: .circle, 2: .hexagon]
        store.displaySpaceIconStyles = ["Main": [2: .square]]

        SpacePreferences.migrateDisplayScopeOverrides(store: store)

        // The live template survives; the invisible shared entry is gone
        #expect(store.spaceIconStyles == [0: .circle])
        #expect(store.displaySpaceIconStyles["Main"]?[2] == .square)
        #expect(store.spaceStyleMigrationVersion == 2)
    }

    @Test("scope migration runs once and skips the snapshot when clean")
    func scopeMigration_runsOnce() {
        store.spaceStyleMigrationVersion = 1
        var snapshotCalls = 0

        SpacePreferences.migrateDisplayScopeOverrides(store: store) {
            snapshotCalls += 1
        }
        #expect(store.spaceStyleMigrationVersion == 2)
        #expect(snapshotCalls == 0)

        store.displaySpaceIconStyles = ["Main": [2: .circle]]
        SpacePreferences.migrateDisplayScopeOverrides(store: store)
        #expect(store.displaySpaceIconStyles["Main"]?[2] == .circle)
    }
}
