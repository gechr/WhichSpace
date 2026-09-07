import Foundation

/// A parsed `whichspace://` URL command.
///
/// Supported forms:
/// - `whichspace://switch/3` - switch to a Space by number, with optional
///   `?label=...&badge=...` query items applied in one step
/// - `whichspace://switch/left` - switch to the Space on the left
/// - `whichspace://switch/right` - switch to the Space on the right
/// - `whichspace://switch/previous` - switch back to the last visited Space
/// - `whichspace://move/3` - move the front window to a Space by number and
///   switch to it; `left` and `right` are also accepted
/// - `whichspace://send/3` - the same, without switching Space
/// - `whichspace://diagnostics/copy` - copy a summary of the current setup
///   to the clipboard
/// - `whichspace://settings/import?path=/absolute/backup.json` - restore settings
/// - `whichspace://settings/export?path=/absolute/backup.json` - export settings
/// - `whichspace://settings` - open settings on the last pane shown
/// - `whichspace://settings/spaces` - open settings on a named pane
/// - `whichspace://settings?highlight=icon-size` - open settings on whichever
///   pane holds that setting and highlight it
/// - `whichspace://settings?navigate=icon-size` - the same, without lighting
///   the row up
/// - `whichspace://space/3?symbol=curlybraces&foreground=CC30E0` - style a
///   Space by its position on the current display, with optional
///   `display=M` to address another display; `emoji`, `background`,
///   `symbol-color`, `symbol-background`, `label` and `badge` are the other
///   fields. An empty symbol, emoji, label, badge or symbol color clears
///   it, and the reset paths clear foreground and background
/// - `whichspace://space/3/reset` - clear every customization of a Space, as
///   the Reset button in Settings does
/// - `whichspace://space/3/reset/color` - clear only the colors of a Space
/// - `whichspace://space/3/reset/icon` - clear only the symbol or emoji of a
///   Space
enum URLCommand: Equatable {
    case switchToSpace(number: Int, label: String?, badge: String?)
    case switchLeft
    case switchRight
    case switchPrevious
    case moveWindowToSpace(number: Int, follow: Bool)
    case moveWindowRelative(goRight: Bool, follow: Bool)
    case openSettings(pane: SettingsPaneID?, focus: SettingsFocus?)
    case importSettings(URL)
    case exportSettings(URL)
    case copyDiagnostics
    case setSpaceAppearance(position: Int, display: Int?, patch: AppearancePatch)
    case resetSpace(position: Int, display: Int?)
    case resetSpaceColors(position: Int, display: Int?)
    case resetSpaceIcon(position: Int, display: Int?)

    /// Parses a `whichspace://` URL into a command, or nil when the URL
    /// does not match a supported form. Matching is case-insensitive. A
    /// query name the route does not understand, or one given twice,
    /// rejects the URL so a typo is reported rather than silently doing
    /// nothing.
    static func parse(_ url: URL) -> Self? {
        guard url.scheme?.lowercased() == "whichspace" else {
            return nil
        }

        switch url.host?.lowercased() {
        case "switch":
            return parseSwitch(url)
        case "move":
            return parseWindowMove(url, follow: true)
        case "send":
            return parseWindowMove(url, follow: false)
        case "diagnostics":
            return (try? queryValues(url, allowed: [])) != nil
                && url.pathComponents.count > 1 && url.pathComponents[1].lowercased() == "copy"
                ? .copyDiagnostics
                : nil
        case "settings":
            return parseSettings(url)
        case "space":
            return parseSpace(url)
        default:
            return nil
        }
    }

    /// A query name the route does not understand, or one given twice.
    private struct UnsupportedQuery: Error {}

    /// The query items keyed by lowercased name. A bare name carries "".
    private static func queryValues(_ url: URL, allowed: Set<String>) throws(UnsupportedQuery) -> [String: String] {
        var values: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            let name = item.name.lowercased().replacingOccurrences(of: "colour", with: "color")
            guard allowed.contains(name), values.updateValue(item.value ?? "", forKey: name) == nil else {
                throw UnsupportedQuery()
            }
        }
        return values
    }

    /// The query names a `space` URL understands.
    private static let appearanceFields: Set<String> = [
        "display", "symbol", "emoji", "foreground", "background",
        "symbol-color", "symbol-background", "label", "badge",
    ]

    /// Parses only the syntax: positions and display are integers, a reset
    /// path carries nothing but `display`, and symbol and emoji never
    /// travel together. Values are validated against the running app when
    /// the command is applied, so a bad colour or symbol name is reported
    /// rather than silently dropped.
    private static func parseSpace(_ url: URL) -> Self? {
        let components = url.pathComponents.filter { $0 != "/" }
        guard (1 ... 3).contains(components.count),
              let position = Int(components[0]), position > 0,
              var values = try? queryValues(url, allowed: appearanceFields)
        else {
            return nil
        }
        var display: Int?
        if let raw = values.removeValue(forKey: "display") {
            guard let index = Int(raw), index > 0 else {
                return nil
            }
            display = index
        }
        if components.count > 1 {
            guard values.isEmpty, components[1].lowercased() == "reset" else {
                return nil
            }
            switch components.count == 3 ? components[2].lowercased() : nil {
            case nil:
                return .resetSpace(position: position, display: display)
            case "color", "colour":
                return .resetSpaceColors(position: position, display: display)
            case "icon":
                return .resetSpaceIcon(position: position, display: display)
            default:
                return nil
            }
        }
        let patch = AppearancePatch(
            symbol: values["symbol"],
            emoji: values["emoji"],
            foreground: values["foreground"],
            background: values["background"],
            symbolColor: values["symbol-color"],
            symbolBackground: values["symbol-background"],
            label: values["label"],
            badge: values["badge"]
        )
        guard !patch.isEmpty, patch.symbol == nil || patch.emoji == nil else {
            return nil
        }
        return .setSpaceAppearance(position: position, display: display, patch: patch)
    }

    /// `move` follows the window to its new Space, `send` does not switch Space,
    /// mirroring the AppleScript commands of the same names.
    private static func parseWindowMove(_ url: URL, follow: Bool) -> Self? {
        guard url.pathComponents.count == 2, (try? queryValues(url, allowed: [])) != nil else {
            return nil
        }

        switch url.pathComponents[1].lowercased() {
        case "left":
            return .moveWindowRelative(goRight: false, follow: follow)
        case "right":
            return .moveWindowRelative(goRight: true, follow: follow)
        case let target:
            guard let number = Int(target) else {
                return nil
            }
            return .moveWindowToSpace(number: number, follow: follow)
        }
    }

    private static func parseSwitch(_ url: URL) -> Self? {
        guard url.pathComponents.count == 2, let values = try? queryValues(url, allowed: ["label", "badge"]) else {
            return nil
        }

        switch url.pathComponents[1].lowercased() {
        case "left":
            return values.isEmpty ? .switchLeft : nil
        case "right":
            return values.isEmpty ? .switchRight : nil
        case "previous":
            return values.isEmpty ? .switchPrevious : nil
        case let target:
            guard let number = Int(target) else {
                return nil
            }
            return .switchToSpace(number: number, label: values["label"], badge: values["badge"])
        }
    }

    private static func parseSettings(_ url: URL) -> Self? {
        // Dropping the root component treats a trailing slash as no pane
        let components = url.pathComponents.filter { $0 != "/" }
        if components.count == 1, ["import", "export"].contains(components[0].lowercased()) {
            guard let path = (try? queryValues(url, allowed: ["path"]))?["path"],
                  path.hasPrefix("/"), !path.contains("\0")
            else {
                return nil
            }
            let file = URL(fileURLWithPath: path)
            return components[0].lowercased() == "import" ? .importSettings(file) : .exportSettings(file)
        }
        guard let values = try? queryValues(url, allowed: ["highlight", "navigate"]) else {
            return nil
        }
        var pane: SettingsPaneID?
        switch components.count {
        case 0:
            break
        case 1:
            guard let named = SettingsPaneID.named(components[0].lowercased()) else {
                return nil
            }
            pane = named
        default:
            return nil
        }

        let highlighted = values["highlight"]
        let navigated = values["navigate"]
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
}
