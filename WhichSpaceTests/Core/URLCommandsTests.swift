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

    @Test("settings transfers decode absolute paths")
    func settingsTransfersParse() {
        let file = URL(fileURLWithPath: "/tmp/Design & Code #1.json")
        #expect(parse("whichspace://settings/import?path=/tmp/Design%20%26%20Code%20%231.json") ==
            .importSettings(file))
        #expect(parse("whichspace://SETTINGS/EXPORT?PATH=/tmp/Design%20%26%20Code%20%231.json") ==
            .exportSettings(file))
    }

    @Test("settings transfers reject missing or nonabsolute paths", arguments: [
        "whichspace://settings/import",
        "whichspace://settings/export?path=",
        "whichspace://settings/import?path=relative.json",
        "whichspace://settings/export?path=~/backup.json",
        "whichspace://settings/import?path=https://example.com/backup.json",
        "whichspace://settings/import/extra?path=/tmp/backup.json",
        "whichspace://settings/export?path=/tmp/bad%00.json",
    ])
    func invalidSettingsTransfer(string: String) {
        #expect(parse(string) == nil)
    }

    @Test("switch with a number parses")
    func switchNumberParses() {
        #expect(parse("whichspace://switch/3") == .switchToSpace(number: 3, label: nil, badge: nil))
    }

    @Test("switch left and right parse")
    func leftAndRightParse() {
        #expect(parse("whichspace://switch/left") == .switchLeft)
        #expect(parse("whichspace://switch/right") == .switchRight)
    }

    @Test("switch previous parses")
    func previousParses() {
        #expect(parse("whichspace://switch/previous") == .switchPrevious)
    }

    @Test("matching is case-insensitive")
    func matchingIsCaseInsensitive() {
        #expect(parse("WHICHSPACE://Switch/LEFT") == .switchLeft)
        #expect(parse("WHICHSPACE://Send/3") == .moveWindowToSpace(number: 3, follow: false))
        #expect(parse("WHICHSPACE://Diagnostics/COPY") == .copyDiagnostics)
    }

    @Test("diagnostics copy parses")
    func diagnosticsCopyParses() {
        #expect(parse("whichspace://diagnostics/copy") == .copyDiagnostics)
    }

    @Test("diagnostics without a verb is rejected")
    func diagnosticsWithoutVerbIsRejected() {
        // Bare `diagnostics` does nothing on its own, so it must not silently
        // fall through to the copy
        #expect(parse("whichspace://diagnostics") == nil)
        #expect(parse("whichspace://diagnostics/paste") == nil)
    }

    @Test("move follows the window and send does not switch Space")
    func moveAndSendDifferInFollowing() {
        #expect(parse("whichspace://move/3") == .moveWindowToSpace(number: 3, follow: true))
        #expect(parse("whichspace://send/3") == .moveWindowToSpace(number: 3, follow: false))
    }

    @Test("relative window moves parse")
    func relativeWindowMovesParse() {
        #expect(parse("whichspace://move/right") == .moveWindowRelative(goRight: true, follow: true))
        #expect(parse("whichspace://move/left") == .moveWindowRelative(goRight: false, follow: true))
        #expect(parse("whichspace://send/right") == .moveWindowRelative(goRight: true, follow: false))
        #expect(parse("whichspace://send/left") == .moveWindowRelative(goRight: false, follow: false))
    }

    @Test("malformed window moves are rejected")
    func malformedWindowMovesAreRejected() {
        #expect(parse("whichspace://move") == nil)
        #expect(parse("whichspace://move/") == nil)
        #expect(parse("whichspace://move/abc") == nil)
        #expect(parse("whichspace://send/3/4") == nil)
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
        #expect(parse("whichspace://switch/next") == nil)
        #expect(parse("whichspace://switch/1/2") == nil)
        #expect(parse("whichspace://other/3") == nil)
        #expect(parse("otherscheme://switch/3") == nil)
    }

    @Test("unknown or repeated query names reject every route", arguments: [
        "whichspace://switch/3?labl=Work",
        "whichspace://switch/3?label=Work&label=Mail",
        "whichspace://switch/left?label=Work",
        "whichspace://switch/previous?badge=A",
        "whichspace://move/3?follow=1",
        "whichspace://send/left?x=1",
        "whichspace://diagnostics/copy?format=json",
        "whichspace://settings/import?path=/tmp/backup.json&overwrite=1",
        "whichspace://settings/export?path=/tmp/a.json&path=/tmp/b.json",
        "whichspace://settings?highlight=icon-size&x=1",
        "whichspace://settings/spaces?path=/tmp/backup.json",
        "whichspace://settings?highlight=icon-size&highlight=icon-size",
    ])
    func unknownQueryNamesAreRejected(string: String) {
        #expect(parse(string) == nil)
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
            parse("whichspace://settings/mouse?highlight=scroll-sensitivity")
                == .openSettings(pane: .mouse, focus: .highlight(.scrollSensitivity))
        )
        #expect(
            parse("whichspace://settings/mouse?navigate=scroll-sensitivity")
                == .openSettings(pane: .mouse, focus: .navigate(.scrollSensitivity))
        )
    }

    @Test("the retired switching pane name still reaches the Mouse pane")
    func retiredSwitchingNameParses() {
        #expect(
            parse("whichspace://settings/switching")
                == .openSettings(pane: .mouse, focus: nil)
        )
        #expect(
            parse("whichspace://settings/switching?highlight=scroll-sensitivity")
                == .openSettings(pane: .mouse, focus: .highlight(.scrollSensitivity))
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

    // MARK: - Space appearance

    @Test("space appearance URLs carry every field as raw text")
    func spaceAppearanceParses() {
        #expect(
            parse("whichspace://space/3?symbol=curlybraces&foreground=CC30E0&background=202020")
                == .setSpaceAppearance(
                    position: 3,
                    display: nil,
                    patch: AppearancePatch(symbol: "curlybraces", foreground: "CC30E0", background: "202020")
                )
        )
        #expect(
            parse(
                "whichspace://SPACE/2?Display=2&Emoji=%F0%9F%8E%A8&symbol-color=&symbol-background=00000080&label=Art&badge=%23"
            )
                == .setSpaceAppearance(
                    position: 2,
                    display: 2,
                    patch: AppearancePatch(
                        emoji: "🎨", symbolColor: "", symbolBackground: "00000080", label: "Art", badge: "#"
                    )
                )
        )
        // A bare name clears the field
        #expect(
            parse("whichspace://space/1?symbol")
                == .setSpaceAppearance(position: 1, display: nil, patch: AppearancePatch(symbol: ""))
        )
        // Values are not validated here, so a bad colour reaches the app and is reported
        #expect(
            parse("whichspace://space/1?foreground=nope")
                == .setSpaceAppearance(position: 1, display: nil, patch: AppearancePatch(foreground: "nope"))
        )
    }

    @Test("space reset URLs accept only an optional display")
    func spaceResetParses() {
        #expect(parse("whichspace://space/3/reset") == .resetSpace(position: 3, display: nil))
        #expect(parse("whichspace://space/3/reset?display=2") == .resetSpace(position: 3, display: 2))
        #expect(parse("whichspace://space/3/reset/color") == .resetSpaceColors(position: 3, display: nil))
        #expect(parse("whichspace://space/3/reset/color?display=2") == .resetSpaceColors(position: 3, display: 2))
        #expect(parse("whichspace://space/1/Reset/Icon?display=1") == .resetSpaceIcon(position: 1, display: 1))
        #expect(parse("whichspace://space/1/reset/icon?display=1&display=1") == nil)
    }

    @Test("the British spelling is accepted quietly")
    func britishSpellingParses() {
        #expect(parse("whichspace://space/3/reset/colour") == .resetSpaceColors(position: 3, display: nil))
        #expect(
            parse("whichspace://space/3?symbol-colour=FFFFFF")
                == .setSpaceAppearance(position: 3, display: nil, patch: AppearancePatch(symbolColor: "FFFFFF"))
        )
        // Both spellings of one field are still a duplicate
        #expect(parse("whichspace://space/3?symbol-color=FFFFFF&symbol-colour=000000") == nil)
    }

    @Test("malformed space URLs are rejected", arguments: [
        "whichspace://space",
        "whichspace://space/0?symbol=star",
        "whichspace://space/x?symbol=star",
        "whichspace://space/3",
        "whichspace://space/3?other=1",
        "whichspace://space/3?symbol=star&other=1",
        "whichspace://space/3?symbl=star",
        "whichspace://space/3/reset/icon?other=1",
        "whichspace://space/3?display=0&symbol=star",
        "whichspace://space/3?display=two&symbol=star",
        "whichspace://space/3?symbol=star&emoji=%F0%9F%8E%A8",
        "whichspace://space/3?symbol=star&symbol=heart",
        "whichspace://space/3?display=1&display=2&symbol=star",
        "whichspace://space/3/reset?symbol=star",
        "whichspace://space/3/reset/color?symbol=star",
        "whichspace://space/3/reset/icon?label=",
        "whichspace://space/3/reset/icon?display=1&display=1",
        "whichspace://space/3/reset/nope",
        "whichspace://space/3/reset/color/extra",
        "whichspace://space/3/color",
        "whichspace://space/3/reset-color",
    ])
    func malformedSpaceURLsAreRejected(string: String) {
        #expect(parse(string) == nil)
    }
}
