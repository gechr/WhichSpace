import Foundation
import Testing
@testable import WhichSpace

@Suite("URLCommand parsing")
struct URLCommandsTests {
    private func parse(_ string: String) -> URLCommand? {
        guard let url = URL(string: string) else {
            return nil
        }
        return URLCommand.parse(url)
    }

    @Test("switch with a number parses")
    func switchNumberParses() {
        #expect(parse("whichspace://switch/3") == .switchToSpace(number: 3, label: nil, badge: nil))
    }

    @Test("switch next and previous parse")
    func nextAndPreviousParse() {
        #expect(parse("whichspace://switch/next") == .switchToNext)
        #expect(parse("whichspace://switch/previous") == .switchToPrevious)
    }

    @Test("matching is case-insensitive")
    func matchingIsCaseInsensitive() {
        #expect(parse("WHICHSPACE://Switch/NEXT") == .switchToNext)
    }

    @Test("label and badge query items are captured")
    func labelAndBadgeAreCaptured() {
        #expect(
            parse("whichspace://switch/3?label=Work&badge=A")
                == .switchToSpace(number: 3, label: "Work", badge: "A")
        )
    }

    @Test("percent-encoded query values are decoded")
    func percentEncodedValuesAreDecoded() {
        #expect(
            parse("whichspace://switch/2?label=Deep%20Work")
                == .switchToSpace(number: 2, label: "Deep Work", badge: nil)
        )
    }

    @Test("unsupported URLs are rejected")
    func unsupportedURLsAreRejected() {
        #expect(parse("whichspace://switch") == nil)
        #expect(parse("whichspace://switch/abc") == nil)
        #expect(parse("whichspace://switch/1/2") == nil)
        #expect(parse("whichspace://other/3") == nil)
        #expect(parse("otherscheme://switch/3") == nil)
    }
}
