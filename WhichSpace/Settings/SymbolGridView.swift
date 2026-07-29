import AppKit
import EmojiKit
import SwiftUI

/// A searchable grid over one of the symbol catalogs, mirroring the menu's
/// `ItemPicker` in SwiftUI. `LazyVGrid` only materializes visible cells, so
/// the ~600-item catalogs stay cheap.
struct SymbolGridView: View {
    enum Catalog {
        case symbols
        case emojis

        var items: [String] {
            switch self {
            case .symbols:
                ItemData.symbols
            case .emojis:
                ItemData.emojis
            }
        }
    }

    let catalog: Catalog
    let selected: String?
    /// Tone applied to emoji cells for display; selections store the base
    /// emoji and the per-Space tone is applied at render time
    let pickerSkinTone: SkinTone
    let onSelect: (String?) -> Void

    @State private var searchText = ""

    private static let cellSize = 26.0
    private static let gridHeight = 176.0

    var body: some View {
        VStack(spacing: 8) {
            searchRow
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.cellSize), spacing: 4)],
                    spacing: 4
                ) {
                    ForEach(filteredItems, id: \.self) { item in
                        cell(for: item)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: Self.gridHeight)
        }
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(Localization.search, text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .quaternarySystemFill))
        )
    }

    private var filteredItems: [String] {
        guard !searchText.isEmpty else {
            return catalog.items
        }
        switch catalog {
        case .symbols:
            return catalog.items.filter { $0.localizedCaseInsensitiveContains(searchText) }
        case .emojis:
            // EmojiKit matches on names and keywords, not the character itself
            let matching = Set(Emoji.all.matching(searchText).map(\.char))
            return catalog.items.filter { matching.contains($0) }
        }
    }

    private func cell(for item: String) -> some View {
        let isSelected = item == selected
        // Tapping the selected item deselects it, reverting the entry to
        // its label or number
        return Button {
            onSelect(isSelected ? nil : item)
        } label: {
            Group {
                switch catalog {
                case .symbols:
                    Image(systemName: item)
                        .font(.system(size: 14, weight: .medium))
                case .emojis:
                    // The default tone must show the raw emoji: applying it
                    // strips the emoji-presentation selector along with the
                    // modifiers, downgrading some glyphs to monochrome text
                    Text(pickerSkinTone == .default ? item : SkinTone.apply(to: item, tone: pickerSkinTone))
                        .font(.system(size: 17))
                }
            }
            .frame(width: Self.cellSize, height: Self.cellSize)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        .help(catalog == .symbols ? item : "")
    }
}

// MARK: - SkinToneRow

/// Six skin-tone choices with a selection ring, mirroring the menu's
/// `SkinToneSwatch`.
struct SkinToneRow: View {
    let selected: SkinTone
    let onSelect: (SkinTone) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(SkinTone.allCases, id: \.rawValue) { tone in
                Button {
                    onSelect(tone)
                } label: {
                    Text(SkinToneSwatch.skinToneEmojis[tone.rawValue])
                        .font(.system(size: 15))
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    tone == selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
