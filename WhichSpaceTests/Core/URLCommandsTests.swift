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

    // MARK: - Settings

    @Test("settings without a pane opens the last pane shown")
    func settingsWithoutPane() {
        #expect(parse("whichspace://settings") == .openSettings(pane: nil, focus: nil))
        #expect(parse("whichspace://settings/") == .openSettings(pane: nil, focus: nil))
    }

    @Test("every pane name parses")
    func everyPaneNameParses() {
        for pane in SettingsPaneID.allCases {
            #expect(
                parse("whichspace://settings/\(pane.rawValue)")
                    == .openSettings(pane: pane, focus: nil)
            )
        }
    }

    @Test("pane names are case-insensitive")
    func paneNamesAreCaseInsensitive() {
        #expect(parse("whichspace://settings/MenuBar") == .openSettings(pane: .menuBar, focus: nil))
    }

    @Test("every setting is reachable by highlight alone")
    func everyAnchorRoundTrips() {
        for anchor in SettingsAnchor.allCases {
            #expect(
                parse("whichspace://settings?highlight=\(anchor.rawValue)")
                    == .openSettings(pane: anchor.pane, focus: .highlight(anchor))
            )
        }
    }

    @Test("every setting is reachable by navigate alone")
    func everyAnchorRoundTripsWithoutEmphasis() {
        for anchor in SettingsAnchor.allCases {
            #expect(
                parse("whichspace://settings?navigate=\(anchor.rawValue)")
                    == .openSettings(pane: anchor.pane, focus: .navigate(anchor))
            )
        }
    }

    @Test("navigate lands on the same row without emphasis")
    func navigateSkipsEmphasis() {
        let focus = SettingsFocus.navigate(.iconSize)
        #expect(focus.anchor == SettingsFocus.highlight(.iconSize).anchor)
        #expect(focus.isEmphasized == false)
        #expect(SettingsFocus.highlight(.iconSize).isEmphasized)
    }

    @Test("a pane naming one of its own settings is accepted")
    func matchingPaneAndAnchorParse() {
        #expect(
            parse("whichspace://settings/switching?highlight=scroll-sensitivity")
                == .openSettings(pane: .switching, focus: .highlight(.scrollSensitivity))
        )
        #expect(
            parse("whichspace://settings/switching?navigate=scroll-sensitivity")
                == .openSettings(pane: .switching, focus: .navigate(.scrollSensitivity))
        )
    }

    @Test("unsupported settings URLs are rejected")
    func unsupportedSettingsURLsAreRejected() {
        #expect(parse("whichspace://settings/nowhere") == nil)
        #expect(parse("whichspace://settings/general/extra") == nil)
        #expect(parse("whichspace://settings?highlight=nothing") == nil)
        #expect(parse("whichspace://settings?navigate=nothing") == nil)
        // The pane does not hold that setting, so neither reading is right
        #expect(parse("whichspace://settings/general?highlight=icon-size") == nil)
        #expect(parse("whichspace://settings/general?navigate=icon-size") == nil)
        // The two forms ask for opposite treatment of the same row
        #expect(parse("whichspace://settings?highlight=icon-size&navigate=icon-size") == nil)
    }
}
