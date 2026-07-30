import AppKit
import SwiftUI

/// A grid of icon-style choices, each cell showing the style rendered with
/// the edited entry's number and colors.
struct StyleGridView: View {
    /// The label-shape subset offered for custom labels.
    static let labelStyles: [IconStyle] = [
        .pill, .pillOutline, .square, .squareOutline, .stroke, .transparent,
    ]

    /// Label shapes reuse the number-style artwork but describe the shape
    /// around the text, so four get label-specific names.
    static func labelStyleTitle(for style: IconStyle) -> String? {
        switch style {
        case .pill:
            Localization.labelStylePill
        case .pillOutline:
            Localization.labelStylePillOutline
        case .square:
            Localization.labelStyleBox
        case .squareOutline:
            Localization.labelStyleBoxOutline
        default:
            nil
        }
    }

    let styles: [IconStyle]
    let selected: IconStyle?
    let previewNumber: String
    /// Label grids render the entry's actual label text instead of its number
    var previewText: String?
    var previewFont: NSFont?
    let customColors: SpaceColors?
    let darkMode: Bool
    var usesLabelTitles = false
    let onSelect: (IconStyle) -> Void

    private static let columnCount = 4

    /// Laid out eagerly rather than with `LazyVGrid`: a deep link scrolling
    /// straight to a section would otherwise leave the grid blank until a
    /// manual scroll realized its rows. Cells already expand to fill, so an
    /// `HStack` per row gives the same equal-width columns.
    private var rows: [[IconStyle]] {
        stride(from: 0, to: styles.count, by: Self.columnCount).map {
            Array(styles[$0 ..< min($0 + Self.columnCount, styles.count)])
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.rawValue) { style in
                        cell(for: style)
                    }
                    // Keep a short final row's cells the same width as the
                    // rows above rather than letting them stretch
                    ForEach(row.count ..< Self.columnCount, id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func cell(for style: IconStyle) -> some View {
        let isSelected = style == selected
        return Button {
            onSelect(style)
        } label: {
            VStack(spacing: 3) {
                Image(nsImage: icon(for: style))
                Text(title(for: style))
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.selection.opacity(0.25)) : AnyShapeStyle(.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func title(for style: IconStyle) -> String {
        if usesLabelTitles, let override = Self.labelStyleTitle(for: style) {
            return override
        }
        return style.localizedTitle
    }

    private func icon(for style: IconStyle) -> NSImage {
        // Label text goes through the same style and font mapping as the
        // status bar, so cells match what selecting them produces; numbers
        // always render their style as stored
        guard let previewText else {
            return SpaceIconGenerator.generateIcon(
                for: previewNumber,
                darkMode: darkMode,
                customColors: customColors,
                style: style
            )
        }
        let font = previewFont
            ?? (previewText.count > 1 ? NSFont.boldSystemFont(ofSize: Layout.baseFontSizeSmall) : nil)
        return SpaceIconGenerator.generateIcon(
            for: previewText,
            darkMode: darkMode,
            customColors: customColors,
            customFont: font,
            style: StatusBarRenderer.renderStyle(for: style, labelLength: previewText.count)
        )
    }
}
