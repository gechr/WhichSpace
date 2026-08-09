import KeyboardShortcuts
import SwiftUI

/// The Keyboard settings pane: global hotkeys for relative switching, for
/// moving the front window, and for jumping straight to a Space, plus the
/// accessibility permission they need.
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

    /// Placeholder rows stay hidden until asked for, so the Jump card only
    /// spends height on Spaces that exist
    @State private var revealsInactiveSpaces = false

    var body: some View {
        // The banner pins above the scroll view, so the warning stays visible
        // while the sections scroll beneath it
        Group {
            if model.accessibilityGranted {
                SettingsForm {
                    sections
                }
            } else {
                SettingsForm {
                    AccessibilityBannerSection(model: model)
                } content: {
                    sections
                }
            }
        }
        // Revealing the hidden Jump rows grows the pane after the window was
        // sized to it, so the window has to follow
        .fitsSettingsWindow(measuring: CGSize(width: 0, height: Double(visibleJumpNumbers.count)))
    }

    @ViewBuilder
    private var sections: some View {
        // Left/right rather than previous/next: "previous" names the
        // last-visited Space, so it gets its own card below the directional
        // hotkeys and the skip toggle that only governs them.
        SettingsSection(Localization.labelSwitch) {
            recorderRow(
                title: Localization.labelLeft,
                icon: "arrowshape.left.fill",
                subtitle: Localization.tipHotkeySwitchLeft,
                anchor: .hotkeySwitchLeft,
                name: .switchLeft
            )
            SettingsRowDivider()
            recorderRow(
                title: Localization.labelRight,
                icon: "arrowshape.right.fill",
                subtitle: Localization.tipHotkeySwitchRight,
                anchor: .hotkeySwitchRight,
                name: .switchRight
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleSkipEmptySpaces,
                isOn: model.binding(\.hotkeysSkipEmptySpaces),
                icon: "arrow.right.to.line.compact",
                subtitle: Localization.tipSkipEmptySpaces,
                anchor: .hotkeySkipEmptySpaces
            )
            .padding(.trailing, Layout.settingsSpaceListScrollerWidth)
        }
        SettingsSection {
            recorderRow(
                title: Localization.labelPrevious,
                icon: "arrow.uturn.backward",
                subtitle: Localization.tipHotkeySwitchPrevious,
                anchor: .hotkeySwitchPrevious,
                name: .switchPrevious
            )
        }
        windowSection
        if !SpaceWindowMover.isSupported {
            unsupportedNote
        }
        jumpSection
        behaviorNote
    }

    // MARK: - Window

    /// Sending leaves you where you are and moving follows the window, so the
    /// filled arrows mark the rows that switch Space too.
    private var windowSection: some View {
        SettingsSection(Localization.labelWindow) {
            recorderRow(
                title: Localization.labelSendLeft,
                icon: "arrow.left.square",
                subtitle: Localization.tipHotkeySendLeft,
                anchor: .hotkeySendLeft,
                name: .sendLeft
            )
            SettingsRowDivider()
            recorderRow(
                title: Localization.labelSendRight,
                icon: "arrow.right.square",
                subtitle: Localization.tipHotkeySendRight,
                anchor: .hotkeySendRight,
                name: .sendRight
            )
            SettingsRowDivider()
            recorderRow(
                title: Localization.labelMoveLeft,
                icon: "arrow.left.square.fill",
                subtitle: Localization.tipHotkeyMoveLeft,
                anchor: .hotkeyMoveLeft,
                name: .moveLeft
            )
            SettingsRowDivider()
            recorderRow(
                title: Localization.labelMoveRight,
                icon: "arrow.right.square.fill",
                subtitle: Localization.tipHotkeyMoveRight,
                anchor: .hotkeyMoveRight,
                name: .moveRight
            )
            SettingsRowDivider()
            SettingsToggleRow(
                title: Localization.toggleSkipEmptySpaces,
                isOn: model.binding(\.hotkeysWindowSkipEmptySpaces),
                icon: "arrow.right.to.line.compact",
                subtitle: Localization.tipWindowSkipEmptySpaces,
                anchor: .hotkeyWindowSkipEmptySpaces
            )
            .padding(.trailing, Layout.settingsSpaceListScrollerWidth)
        }
    }

    /// No backend on this host can move a window, so a binding recorded above
    /// would do nothing without saying why.
    private var unsupportedNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.triangle")
            Text(Localization.errorScriptingMoveUnsupported)
        }
        .font(.system(size: Layout.settingsRowSubtitleFontSize))
        .foregroundStyle(.secondary)
        .padding(.leading, 4)
    }

    // MARK: - Rows

    /// The rows outside the Jump list, which differ only in what they say and
    /// which binding they record.
    private func recorderRow(
        title: String,
        icon: String,
        subtitle: String,
        anchor: SettingsAnchor,
        name: KeyboardShortcuts.Name
    ) -> some View {
        SettingsRow(icon: icon, subtitle: subtitle, anchor: anchor) {
            Text(title)
        } control: {
            KeyboardShortcuts.Recorder(for: name)
        }
        // The Jump list gives up this strip to its scroller, so the other
        // cards give up the same width and all the recorders stay aligned
        .padding(.trailing, Layout.settingsSpaceListScrollerWidth)
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

    /// One recorder per Desktop the current layout has, with the remaining
    /// bindable numbers hidden behind a reveal button so the card does not
    /// spend sixteen rows of height on Spaces that do not exist. Global
    /// numbering resolves across every display; local numbering follows the
    /// active display. The list scrolls within a capped height so a revealed
    /// sixteen rows do not run the window off the screen.
    private var jumpSection: some View {
        let visible = visibleJumpNumbers
        return SettingsSection(Localization.labelJump, anchor: .jump) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element) { index, number in
                        if index > 0 {
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
            if visible.count < HotkeyCenter.maxJumpTargets {
                SettingsRowDivider()
                revealButton
            }
        }
        // A binding on a hidden row must stay visible, so the list starts
        // revealed when any placeholder already has one recorded
        .onAppear {
            if !revealsInactiveSpaces, placeholderHasBinding {
                revealsInactiveSpaces = true
            }
        }
    }

    /// Placeholder rows stand for Desktop numbers past the current count.
    /// Local numbering resolves them against the active display, global
    /// numbering against every display.
    private func isPlaceholder(_ number: Int) -> Bool {
        model.value(\.localSpaceNumbers)
            ? localCandidate(number).entry == nil
            : number > appState.regularSpaceCount
    }

    /// The rows on screen: every Space that exists, plus the placeholders
    /// once revealed.
    private var visibleJumpNumbers: [Int] {
        let all = Array(1 ... HotkeyCenter.maxJumpTargets)
        return revealsInactiveSpaces ? all : all.filter { !isPlaceholder($0) }
    }

    private var placeholderHasBinding: Bool {
        (1 ... HotkeyCenter.maxJumpTargets).contains { number in
            isPlaceholder(number)
                && KeyboardShortcuts.getShortcut(for: KeyboardShortcuts.Name.jumpToSpace[number - 1]) != nil
        }
    }

    private var revealButton: some View {
        Button {
            withAnimation {
                revealsInactiveSpaces = true
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.down.2")
                    .frame(width: Layout.settingsRowIconWidth)
                Text(Localization.actionRevealInactiveSpaces)
                Spacer(minLength: 0)
            }
            .font(.system(size: Layout.settingsRowFontSize))
            .foregroundStyle(Color.accentColor.opacity(0.7))
            .padding(.horizontal, Layout.settingsRowHorizontalPadding)
            .padding(.vertical, Layout.settingsRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Localization.tipSpacePlaceholderHotkey)
    }

    /// Placeholder rows grey only the name, the same treatment the Spaces
    /// sidebar gives them; the recorder stays full strength because binding
    /// ahead of time is exactly what those rows are for.
    private func jumpRow(number: Int) -> some View {
        let localNumbers = model.value(\.localSpaceNumbers)
        let candidate = localCandidate(number)
        let placeholder = isPlaceholder(number)
        return SettingsRow(icon: "\(number).square") {
            Text(
                localNumbers
                    ? editorModel.spaceName(for: candidate)
                    ?? String(format: Localization.labelSpaceNumber, number)
                    : editorModel.globalDesktopName(for: number)
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
    private func localCandidate(_ number: Int) -> (number: Int, entry: SpaceEntry?) {
        let entries = appState.allSpaceEntries
        return (number, number <= entries.count ? entries[number - 1] : nil)
    }
}
