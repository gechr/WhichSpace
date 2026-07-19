import Foundation

/// A parsed `whichspace://` URL command.
///
/// Supported forms:
/// - `whichspace://switch/3` - switch to a Space by number, with optional
///   `?label=...&badge=...` query items applied in one step
/// - `whichspace://switch/next` - switch to the next Space
/// - `whichspace://switch/previous` - switch to the previous Space
enum URLCommand: Equatable {
    case switchToSpace(number: Int, label: String?, badge: String?)
    case switchToNext
    case switchToPrevious

    /// Parses a `whichspace://` URL into a command, or nil when the URL
    /// does not match a supported form. Matching is case-insensitive.
    static func parse(_ url: URL) -> Self? {
        guard url.scheme?.lowercased() == "whichspace",
              url.host?.lowercased() == "switch",
              url.pathComponents.count == 2
        else {
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
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            return .switchToSpace(
                number: number,
                label: queryItems?.first { $0.name.lowercased() == "label" }?.value,
                badge: queryItems?.first { $0.name.lowercased() == "badge" }?.value
            )
        }
    }
}
