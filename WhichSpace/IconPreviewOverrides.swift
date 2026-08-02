import AppKit

/// Temporary overrides applied when rendering the settings preview card
/// while a candidate value is hovered. Each hover sets exactly one field
/// (plus a skin tone alongside an emoji symbol); the renderer resolves
/// every other input from stored preferences, so the preview shows what
/// committing the hovered value would render. The status bar render path
/// never passes overrides.
struct IconPreviewOverrides: Equatable {
    var background: NSColor?
    /// Applied only while a badge character is stored, as committing does
    var badgePosition: BadgePosition?
    /// Previews removing the stored symbol, which clicking the selected
    /// symbol cell commits
    var clearSymbol = false
    var clearSymbolBackground = false
    /// Full replacement of the stored colors, used by the invert preview
    var colors: SpaceColors?
    var font: NSFont?
    var foreground: NSColor?
    var labelStyle: IconStyle?
    var skinTone: SkinTone?
    var style: IconStyle?
    var symbol: String?
    var symbolBackground: NSColor?
    var symbolColor: NSColor?
    var symbolPosition: SymbolPosition?
    var symbolWrap: SymbolWrap?
}
