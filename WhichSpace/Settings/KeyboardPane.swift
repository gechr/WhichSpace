import KeyboardShortcuts
import SwiftUI

/// The Keyboard settings pane: global hotkeys for relative switching and for
/// jumping straight to a Space, plus the accessibility permission they need.
/// Container-agnostic - it knows nothing about the window chrome hosting it.
struct KeyboardPane: View {
    let model: SettingsModel
    /// Names the jump rows the way the Spaces sidebar does: the custom
    /// Desktop name when one is set, otherwise "Desktop N"
    let editorModel: SpaceEditorModel
    /// Read for the Space entries the names resolve against
    let appState: AppState
    /// Navigates to the Mouse pane's Behavior card when the note's link is
    /// tapped. A direct callback rather than the whichspace:// URL: the
    /// system would route the scheme to the installed copy, not this one
    let onOpenBehavior: () -> Void

    var body: some View {
        SettingsForm {
            if !model.accessibilityGranted {
                AccessibilityBannerSection(model: model)
            }
            // Left/right rather than previous/next: "previous" is reserved
            // for the last-visited Space
            SettingsSection(Localization.labelSwitch) {
                SettingsRow(
                    icon: "arrow.left.square",
                    subtitle: Localization.tipHotkeySwitchLeft,
                    anchor: .hotkeySwitchLeft
                ) {
                    Text(Localization.labelLeft)
                } control: {
                    KeyboardShortcuts.Recorder(for: .switchLeft)
                }
                .padding(.trailing, Layout.settingsSpaceListScrollerWidth)
                SettingsRowDivider()
                SettingsRow(
                    icon: "arrow.right.square",
                    subtitle: Localization.tipHotkeySwitchRight,
                    anchor: .hotkeySwitchRight
                ) {
                    Text(Localization.labelRight)
                } control: {
                    KeyboardShortcuts.Recorder(for: .switchRight)
                }
                .padding(.trailing, Layout.settingsSpaceListScrollerWidth)
            }
            jumpSection
            behaviorNote
        }
    }

    /// Wrap around and classic switching govern these hotkeys too - for
    /// example the right bind on the last Space wraps to the first only when
    /// Wrap Around is on - so the note links to where they live.
    private var behaviorNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "info.circle")
            Text(noteText)
        }
        .font(.system(size: Layout.settingsRowSubtitleFontSize))
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
        .environment(\.openURL, OpenURLAction { _ in
            // Deferred a turn: swapping panes while SwiftUI is still
            // processing the tap can leave the incoming pane blank
            Task { @MainActor in
                onOpenBehavior()
            }
            return .handled
        })
    }

    private var noteText: AttributedString {
        let markdown = String(
            format: Localization.tipHotkeysBehavior,
            "\(Localization.paneMouse) › \(Localization.labelBehavior)",
            "whichspace://settings/mouse?highlight=behavior"
        )
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    /// One recorder per bindable position, all shown regardless of the
    /// current Space count so bindings can be recorded ahead of time.
    /// Rows mirror the Spaces sidebar: titled with the Desktop name, dimmed
    /// while the Space does not exist yet, live either way. The list scrolls
    /// within a capped height so sixteen rows do not run the window off the
    /// screen.
    private var jumpSection: some View {
        SettingsSection(Localization.labelJump, anchor: .jump) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(1 ... HotkeyCenter.maxJumpTargets, id: \.self) { number in
                        if number > 1 {
                            SettingsRowDivider()
                        }
                        jumpRow(number: number)
                    }
                }
                // A space-reserving scroller insets the rows by itself; the
                // overlay kind floats over them, so the rows step aside for
                // it here. Either way the Switch card above pads by the same
                // width, keeping the two columns of recorders aligned.
                .padding(
                    .trailing,
                    NSScroller.preferredScrollerStyle == .overlay
                        ? Layout.settingsSpaceListScrollerWidth
                        : 0
                )
            }
            .frame(maxHeight: Layout.settingsJumpListMaxHeight)
        }
    }

    /// Placeholder rows grey only the name, the same treatment the Spaces
    /// sidebar gives them; the recorder stays full strength because binding
    /// ahead of time is exactly what those rows are for.
    private func jumpRow(number: Int) -> some View {
        let candidate = candidate(number)
        let placeholder = candidate.entry == nil
        return SettingsRow(icon: "\(number).square") {
            Text(
                editorModel.spaceName(for: candidate)
                    ?? String(format: Localization.labelSpaceNumber, number)
            )
            .foregroundStyle(placeholder ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
        } control: {
            KeyboardShortcuts.Recorder(for: KeyboardShortcuts.Name.jumpToSpace[number - 1])
        }
        .help(placeholder ? Localization.tipSpacePlaceholderHotkey : "")
    }

    /// The same candidate shape the Spaces sidebar lists: the real entry
    /// while the Space exists, nil past the current count so the name
    /// extrapolates the Desktop number the Space would get.
    private func candidate(_ number: Int) -> (number: Int, entry: SpaceEntry?) {
        let entries = appState.allSpaceEntries
        return (number, number <= entries.count ? entries[number - 1] : nil)
    }
}
