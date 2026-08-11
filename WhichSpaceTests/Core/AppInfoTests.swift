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

    @Test("an unknown stamp names no tag")
    func unknownStampNamesNoTag() {
        #expect(AppInfo.releaseTag(for: "?") == nil)
    }
}
