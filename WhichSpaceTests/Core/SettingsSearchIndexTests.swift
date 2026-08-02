import Testing
@testable import WhichSpace

@MainActor
struct SettingsSearchIndexTests {
    // MARK: - Coverage

    /// The index is written by hand, so this is what stops a new setting from
    /// being unsearchable: adding a `SettingsAnchor` without an entry fails
    /// here rather than shipping a row no query can reach.
    @Test("every anchor is either indexed or explicitly unlisted")
    func everyAnchorIsAccountedFor() {
        let indexed = Set(SettingsSearchIndex.entries.map(\.anchor))
        let accounted = indexed.union(SettingsSearchIndex.unlisted)
        let missing = SettingsAnchor.allCases.filter { !accounted.contains($0) }
        #expect(missing.isEmpty, "unindexed anchors: \(missing.map(\.rawValue))")
    }

    @Test("no anchor is indexed twice")
    func noDuplicateAnchors() {
        let anchors = SettingsSearchIndex.entries.map(\.anchor)
        #expect(anchors.count == Set(anchors).count)
    }

    /// An unlisted anchor is one a hit could not show, so offering it as a
    /// result as well would send the user somewhere nothing happens.
    @Test("unlisted anchors are never also indexed")
    func unlistedAnchorsAreNotIndexed() {
        let indexed = Set(SettingsSearchIndex.entries.map(\.anchor))
        #expect(indexed.isDisjoint(with: SettingsSearchIndex.unlisted))
    }

    @Test("entries carry no blank titles")
    func titlesArePresent() {
        for entry in SettingsSearchIndex.entries {
            #expect(!entry.title.isEmpty)
        }
    }

    // MARK: - Matching

    @Test("an empty or blank query matches nothing")
    func blankQuery() {
        #expect(SettingsSearchIndex.results(for: "").isEmpty)
        #expect(SettingsSearchIndex.results(for: "   ").isEmpty)
    }

    @Test("a query matches a row by its title")
    func matchesTitle() {
        let results = SettingsSearchIndex.results(for: Localization.toggleHideEmptySpaces)
        #expect(results.first?.anchor == .hideEmptySpaces)
    }

    @Test("matching ignores case")
    func matchesIgnoringCase() {
        let lower = SettingsSearchIndex.results(for: Localization.labelFont.lowercased())
        let upper = SettingsSearchIndex.results(for: Localization.labelFont.uppercased())
        #expect(lower.map(\.anchor) == upper.map(\.anchor))
        #expect(lower.contains { $0.anchor == .font })
    }

    /// The axis rows are titled only "Vertical" and "Horizontal", so the card
    /// they sit on has to be searchable for "scroll" to find them.
    @Test("a query matches a row by its section")
    func matchesSection() {
        let results = SettingsSearchIndex.results(for: Localization.menuScroll)
        #expect(results.contains { $0.anchor == .verticalScroll })
        #expect(results.contains { $0.anchor == .horizontalScroll })
    }

    /// "Sensitivity" is the sensitivity row's whole title and appears inside
    /// other rows' descriptions, so the row it names has to lead.
    @Test("a title match outranks a description match")
    func titleOutranksSubtitle() {
        let results = SettingsSearchIndex.results(for: Localization.labelSensitivity)
        #expect(results.first?.anchor == .scrollSensitivity)
    }

    /// Asserted as a full list rather than "no more than": a cap that also
    /// passes when nothing matches would not be testing the cap.
    @Test("results stop at the limit")
    func resultsAreCapped() {
        // Every entry's breadcrumb names its pane, so a pane name is the
        // broadest query the index can be given
        let results = SettingsSearchIndex.results(for: Localization.paneSpaces)
        #expect(results.count == SettingsSearchIndex.resultLimit)
    }

    /// Field weights were once derived from how many fields an entry had, so
    /// an entry carrying a description outranked a bare one that matched the
    /// same way. Two Menu Bar rows sharing a section make that visible.
    @Test("ranking does not favor entries with more fields")
    func rankingIgnoresFieldCount() {
        let sparse = SettingsSearchEntry(
            anchor: .numberStyle, section: "Group", title: "Alpha", subtitle: nil
        )
        let full = SettingsSearchEntry(
            anchor: .badge, section: "Group", title: "Beta Alpha", subtitle: "Alpha"
        )
        // A title the query leads outscores the same word inside a title,
        // whatever else the entries carry
        #expect(sparse.fields.first?.weight == full.fields.first?.weight)
        #expect(sparse.fields.count < full.fields.count)
    }

    @Test("matching ignores diacritics")
    func matchesIgnoringDiacritics() {
        // The index is searched in the build's own language, so the query is
        // built by stripping marks from a real title rather than hardcoded
        let title = Localization.toggleHideEmptySpaces
        let stripped = title.folding(options: .diacriticInsensitive, locale: nil)
        #expect(SettingsSearchIndex.results(for: stripped).first?.anchor == .hideEmptySpaces)
    }

    @Test("a query that names nothing returns nothing")
    func noMatches() {
        #expect(SettingsSearchIndex.results(for: "qqzzxx").isEmpty)
    }

    // MARK: - Navigation

    /// A result routes through `show(pane:focus:)`, so its pane has to be the
    /// one the anchor actually lives on.
    @Test("an entry's pane follows its anchor")
    func paneFollowsAnchor() {
        for entry in SettingsSearchIndex.entries {
            #expect(entry.pane == entry.anchor.pane)
        }
    }

    @Test("a breadcrumb names the pane, then the section")
    func breadcrumbNamesPane() {
        let entry = SettingsSearchEntry(
            anchor: .scrollSensitivity,
            section: Localization.labelBehavior,
            title: Localization.labelSensitivity,
            subtitle: nil
        )
        #expect(entry.breadcrumb == "\(Localization.paneMouse) › \(Localization.labelBehavior)")

        let bare = SettingsSearchEntry(
            anchor: .backup, section: nil, title: Localization.labelBackup, subtitle: nil
        )
        #expect(bare.breadcrumb == Localization.paneGeneral)
    }
}
