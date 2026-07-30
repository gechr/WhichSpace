import Foundation

/// A parsed `whichspace://` URL command.
///
/// Supported forms:
/// - `whichspace://switch/3` - switch to a Space by number, with optional
///   `?label=...&badge=...` query items applied in one step
/// - `whichspace://switch/next` - switch to the next Space
/// - `whichspace://switch/previous` - switch to the previous Space
/// - `whichspace://settings` - open settings on the last pane shown
/// - `whichspace://settings/spaces` - open settings on a named pane
/// - `whichspace://settings?highlight=icon-size` - open settings on whichever
///   pane holds that setting and highlight it
/// - `whichspace://settings?navigate=icon-size` - the same, without lighting
///   the row up
enum URLCommand: Equatable {
    case switchToSpace(number: Int, label: String?, badge: String?)
    case switchToNext
    case switchToPrevious
    case openSettings(pane: SettingsPaneID?, focus: SettingsFocus?)

    /// Parses a `whichspace://` URL into a command, or nil when the URL
    /// does not match a supported form. Matching is case-insensitive.
    static func parse(_ url: URL) -> Self? {
        guard url.scheme?.lowercased() == "whichspace" else {
            return nil
        }

        switch url.host?.lowercased() {
        case "switch":
            return parseSwitch(url)
        case "settings":
            return parseSettings(url)
        default:
            return nil
        }
    }

    private static func parseSwitch(_ url: URL) -> Self? {
        guard url.pathComponents.count == 2 else {
            return nil
        }

        switch url.pathComponents[1].lowercased() {
        case "next":
            return .switchToNext
        case "previous":
            return .switchToPrevious
        case let target:
            guard let number = Int(target) else {
                return nil
            }
            return .switchToSpace(
                number: number,
                label: queryValue(url, "label"),
                badge: queryValue(url, "badge")
            )
        }
    }

    private static func parseSettings(_ url: URL) -> Self? {
        // Dropping the root component treats a trailing slash as no pane
        let components = url.pathComponents.filter { $0 != "/" }
        var pane: SettingsPaneID?
        switch components.count {
        case 0:
            break
        case 1:
            guard let named = SettingsPaneID(rawValue: components[0].lowercased()) else {
                return nil
            }
            pane = named
        default:
            return nil
        }

        let highlighted = queryValue(url, "highlight")
        let navigated = queryValue(url, "navigate")
        // The two forms ask for opposite treatment of the same row, so a link
        // carrying both states no intent at all
        guard highlighted == nil || navigated == nil else {
            return nil
        }
        guard let raw = highlighted ?? navigated else {
            return .openSettings(pane: pane, focus: nil)
        }
        guard let anchor = SettingsAnchor(rawValue: raw.lowercased()) else {
            return nil
        }
        // A pane naming a setting it does not contain has no sensible reading,
        // so reject it rather than silently picking one of the two
        guard pane == nil || pane == anchor.pane else {
            return nil
        }
        let focus: SettingsFocus = highlighted == nil ? .navigate(anchor) : .highlight(anchor)
        return .openSettings(pane: anchor.pane, focus: focus)
    }

    private static func queryValue(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name }?
            .value
    }
}
