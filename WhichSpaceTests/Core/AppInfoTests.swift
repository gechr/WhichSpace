import Foundation
import Testing
@testable import WhichSpace

@Suite("Release tag derivation")
struct AppInfoTests {
    @Test("a release stamp is already the tag")
    func releaseStampIsTheTag() {
        #expect(AppInfo.releaseTag(for: "1.2.18") == "v1.2.18")
    }

    @Test("a dirty tree drops its suffix")
    func dirtyTreeDropsSuffix() {
        #expect(AppInfo.releaseTag(for: "1.2.18-dirty") == "v1.2.18")
    }

    @Test("commits past the tag drop their describe suffix")
    func commitsPastTheTagDropSuffix() {
        #expect(AppInfo.releaseTag(for: "1.2.18-1-gfe06204") == "v1.2.18")
        #expect(AppInfo.releaseTag(for: "1.2.18-12-gfe06204-dirty") == "v1.2.18")
    }

    @Test("a pre-release tag keeps its own hyphenated parts")
    func preReleaseTagSurvives() {
        #expect(AppInfo.releaseTag(for: "1.3.0-rc.1") == "v1.3.0-rc.1")
        #expect(AppInfo.releaseTag(for: "1.3.0-rc.1-2-gabc1234-dirty") == "v1.3.0-rc.1")
    }

    @Test("a tip build names the rolling tag")
    func tipBuildNamesRollingTag() {
        #expect(AppInfo.releaseTag(for: "1.3.5-tip.616") == "tip")
        #expect(AppInfo.releaseTag(for: "1.3.5-tip.616-2-gabc1234-dirty") == "tip")
    }

    @Test("an unknown stamp names no tag")
    func unknownStampNamesNoTag() {
        #expect(AppInfo.releaseTag(for: "?") == nil)
    }
}

@Suite("Nightly-aware version comparison")
struct NightlyAwareVersionComparatorTests {
    /// Nightly channel on
    private let nightly = NightlyAwareVersionComparator(stableOutranksAnyNightly: false)
    /// Nightly channel off
    private let stable = NightlyAwareVersionComparator(stableOutranksAnyNightly: true)

    @Test("with nightlies off, the base stable release ranks above its nightlies")
    func stableRanksAboveOwnNightliesWhenLeaving() {
        #expect(stable.compareVersion("1.3.5-tip.620", toVersion: "1.3.5") == .orderedAscending)
        #expect(stable.compareVersion("1.3.5", toVersion: "1.3.5-tip.620") == .orderedDescending)
    }

    @Test("with nightlies on, a nightly ranks above the stable release it builds on")
    func nightlyRanksAboveItsBaseStable() {
        #expect(nightly.compareVersion("1.3.5", toVersion: "1.3.5-tip.620") == .orderedAscending)
        #expect(nightly.compareVersion("1.3.5-tip.620", toVersion: "1.3.5") == .orderedDescending)
    }

    @Test("a newer stable release ranks above nightlies of the previous one")
    func newerStableRanksAboveOlderNightlies() {
        #expect(nightly.compareVersion("1.3.5-tip.620", toVersion: "1.3.6") == .orderedAscending)
        #expect(stable.compareVersion("1.3.5-tip.620", toVersion: "1.3.6") == .orderedAscending)
    }

    @Test("two stable releases compare by version")
    func stableReleasesCompareByVersion() {
        #expect(stable.compareVersion("1.3.4", toVersion: "1.3.5") == .orderedAscending)
        #expect(stable.compareVersion("1.3.5", toVersion: "1.3.5") == .orderedSame)
    }

    @Test("two nightlies compare by tip counter")
    func nightliesCompareByTipCounter() {
        #expect(nightly.compareVersion("1.3.5-tip.618", toVersion: "1.3.5-tip.619") == .orderedAscending)
        #expect(nightly.compareVersion("1.3.5-tip.619", toVersion: "1.3.5-tip.619") == .orderedSame)
        #expect(stable.compareVersion("1.3.5-tip.618", toVersion: "1.3.5-tip.619") == .orderedAscending)
    }

    @Test("nightlies of different base versions compare by base version")
    func nightliesCompareByBaseVersionFirst() {
        #expect(nightly.compareVersion("1.3.5-tip.619", toVersion: "1.3.6-tip.1") == .orderedAscending)
    }
}
