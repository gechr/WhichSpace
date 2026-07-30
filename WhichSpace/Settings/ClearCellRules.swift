import AppKit

/// Snapshot of one Space's icon configuration and the color-editing rules
/// derived from it. A clear ("no color") cell is offered only while the
/// opposite side stays visible, so no combination of clears can leave the
/// icon fully transparent.
struct ClearCellRules: Equatable {
    let customColors: SpaceColors?
    let symbol: String?
    let hasLabel: Bool
    let iconStyle: IconStyle
    let labelStyle: IconStyle
    let wrap: SymbolWrap

    // MARK: - Derived Configuration

    var symbolIsActive: Bool {
        symbol != nil
    }

    var symbolIsEmoji: Bool {
        symbol?.containsEmoji ?? false
    }

    /// The symbol renders alone, without label or number text beside it
    var symbolAlone: Bool {
        symbolIsActive && !hasLabel
    }

    var labelStyleCanWrap: Bool {
        labelStyle.supportsInsideSymbolLayout
    }

    /// Symbol background applies whenever the symbol renders bare:
    /// shown alone (no label), or beside a styled label via the outside
    /// wrap (any non-wrapping label style always renders side-by-side)
    var symbolBackgroundVisible: Bool {
        symbolIsActive && (!hasLabel || wrap == .outside || !labelStyleCanWrap)
    }

    /// The style whose background the number/label colors apply to
    var styleForColors: IconStyle {
        hasLabel ? labelStyle : iconStyle
    }

    // MARK: - Transparency

    var foregroundIsTransparent: Bool {
        (customColors?.foreground.alphaComponent ?? 1) < 0.001
    }

    var backgroundIsTransparent: Bool {
        styleForColors == .transparent
            || (customColors?.background.alphaComponent ?? 1) < 0.001
    }

    /// Emoji render without a tint, so a stale clear SF Symbol tint must
    /// not count as a transparent symbol
    var symbolIsTransparent: Bool {
        !symbolIsEmoji && (customColors?.symbol?.alphaComponent ?? 1) < 0.001
    }

    // MARK: - Clear Cell Gating

    /// A clear symbol can knock out of its own chip, or of the filled
    /// label shape wrapping it
    private var symbolHasChipBackdrop: Bool {
        symbolBackgroundVisible && (customColors?.hasVisibleSymbolBackground ?? false)
    }

    private var symbolHasLabelBackdrop: Bool {
        hasLabel && wrap == .inside && labelStyleCanWrap && labelStyle.isFilled
            && !backgroundIsTransparent
    }

    var showsForegroundClear: Bool {
        !backgroundIsTransparent
    }

    var showsBackgroundClear: Bool {
        !foregroundIsTransparent
    }

    var showsSymbolClear: Bool {
        symbolHasChipBackdrop || symbolHasLabelBackdrop
    }

    var showsSymbolBackgroundClear: Bool {
        !symbolIsTransparent
    }
}

// MARK: - Preference Loading

extension ClearCellRules {
    /// Builds the rules from a Space's stored preferences.
    @MainActor
    init(forSpace space: Int, display: String?, store: DefaultsStore) {
        let label = SpacePreferences.label(forSpace: space, display: display, store: store)
        self.init(
            customColors: SpacePreferences.colors(forSpace: space, display: display, store: store),
            symbol: SpacePreferences.symbol(forSpace: space, display: display, store: store),
            hasLabel: label.map { !$0.isEmpty } ?? false,
            iconStyle: SpacePreferences.iconStyle(forSpace: space, display: display, store: store) ?? .square,
            labelStyle: SpacePreferences.labelStyle(forSpace: space, display: display, store: store) ?? .square,
            wrap: SpacePreferences.symbolWrap(forSpace: space, display: display, store: store) ?? .inside
        )
    }
}
