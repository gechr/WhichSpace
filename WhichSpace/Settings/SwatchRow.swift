import AppKit
import SwiftUI

/// A horizontal strip of preset color swatches with a rainbow cell for
/// custom colors and an optional clear ("no color") cell. The current color
/// is marked with a ring around its preset cell rather than a separate well.
struct SwatchRow: View {
    /// A preset cell and the name shown in its tooltip
    struct Preset {
        let color: NSColor
        let name: String
    }

    static let presets: [Preset] = [
        Preset(color: .black, name: Localization.colorBlack),
        Preset(color: .white, name: Localization.colorWhite),
        Preset(color: .systemRed, name: Localization.colorRed),
        Preset(color: .systemOrange, name: Localization.colorOrange),
        Preset(color: .systemYellow, name: Localization.colorYellow),
        Preset(color: .systemGreen, name: Localization.colorGreen),
        Preset(color: .systemBlue, name: Localization.colorBlue),
        Preset(color: .systemPurple, name: Localization.colorPurple),
    ]

    /// The stored color; the matching preset cell gets a selection ring
    let currentColor: NSColor?
    /// Gated by `ClearCellRules` so no combination of clears can leave the
    /// icon fully transparent
    var showsClearCell = false
    let onSelect: (NSColor) -> Void
    var onClear: (() -> Void)?
    /// Opens the shared color panel for colors outside the presets
    let onCustom: () -> Void
    /// Hover preview callbacks for the preset and clear cells; the custom
    /// cell has none because its color is unknown until the panel opens
    var onHoverSelect: ((NSColor, Bool) -> Void)?
    var onHoverClear: ((Bool) -> Void)?

    private static let swatchSize = 16.0

    var body: some View {
        HStack(spacing: 6) {
            if showsClearCell, onClear != nil {
                Button {
                    onClear?()
                } label: {
                    clearCell
                }
                .buttonStyle(.plain)
                .help(Localization.colorTransparent)
                .onHover { hovering in
                    onHoverClear?(hovering)
                }
            }
            ForEach(0 ..< Self.presets.count, id: \.self) { index in
                let preset = Self.presets[index]
                Button {
                    onSelect(preset.color)
                } label: {
                    Circle()
                        .fill(Color(nsColor: preset.color))
                        .overlay(Circle().strokeBorder(.gray.opacity(0.5)))
                        .overlay(ring(active: matches(preset.color)))
                        .frame(width: Self.swatchSize, height: Self.swatchSize)
                }
                .buttonStyle(.plain)
                .help(preset.name)
                .onHover { hovering in
                    onHoverSelect?(preset.color, hovering)
                }
            }
            Button {
                onCustom()
            } label: {
                customCell
            }
            .buttonStyle(.plain)
            .help(Localization.colorPicker)
        }
    }

    /// Ring marking the current color's cell.
    private func ring(active: Bool) -> some View {
        Circle()
            .strokeBorder(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2)
            .padding(-3)
    }

    /// Stored colors round-trip through archiving, so presets are matched by
    /// component closeness rather than object equality.
    private func matches(_ preset: NSColor) -> Bool {
        guard let current = currentColor?.usingColorSpace(.sRGB),
              let candidate = preset.usingColorSpace(.sRGB)
        else {
            return false
        }
        return abs(current.redComponent - candidate.redComponent) < 0.01
            && abs(current.greenComponent - candidate.greenComponent) < 0.01
            && abs(current.blueComponent - candidate.blueComponent) < 0.01
            && abs(current.alphaComponent - candidate.alphaComponent) < 0.01
    }

    /// A rainbow wheel marking "custom color", matching the menu's cell.
    private var customCell: some View {
        Circle()
            .fill(AngularGradient(
                colors: [.red, .yellow, .green, .blue, .purple, .red],
                center: .center
            ))
            .overlay(Circle().strokeBorder(.gray.opacity(0.5)))
            .frame(width: Self.swatchSize, height: Self.swatchSize)
    }

    /// A slashed circle marking "no color", matching the menu's clear cell.
    /// Ringed like a preset when the stored color is transparent.
    private var clearCell: some View {
        ZStack {
            Circle()
                .strokeBorder(.gray.opacity(0.5))
            Line()
                .stroke(Color(nsColor: .systemRed), lineWidth: 1.5)
                .padding(2.5)
        }
        .overlay(ring(active: currentIsClear))
        .frame(width: Self.swatchSize, height: Self.swatchSize)
        // The stroked circle is hollow, and hit testing only sees drawn
        // pixels - clicks in the middle would fall through
        .contentShape(Circle())
    }

    private var currentIsClear: Bool {
        guard let currentColor else {
            return false
        }
        return currentColor.alphaComponent < 0.001
    }
}

/// A bottom-left to top-right diagonal, drawn inside the clear cell.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
