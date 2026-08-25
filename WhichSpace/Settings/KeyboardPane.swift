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

    /// Placeholder rows stay hidden until asked for, so the numbered card
    /// only spends height on Spaces that exist
    @State private var revealsInactiveSpaces = false

    /// Which verb a card's rows record: switch goes there, send moves the
    /// front window and stays, move takes the window and follows. One column
    /// behind a picker rather than three cards of the same rows each.
    fileprivate enum Verb: Int {
        case switchTo
        case send
        case move
    }

    @State private var directionalVerb = Verb.switchTo
    @State private var numberedVerb = Verb.switchTo

    /// Read to flip a card's picker to the verb a deep link or search hit
    /// targets, since the other verbs' rows are not in the hierarchy.
    @Environment(SettingsHighlighter.self) private var highlighter: SettingsHighlighter?

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
        // Revealing the hidden numbered rows grows the pane after the window
        // was sized to it, so the window has to follow
        .fitsSettingsWindow(measuring: CGSize(width: 0, height: Double(visibleNumbers.count)))
    }

    @ViewBuilder
    private var sections: some View {
        // "Previous" names the last-visited Space - unlike every other
        // hotkey it has no direction or number, so it leads on its own card.
        SettingsSection(Localization.labelPreviousSpace) {
            recorderRow(
                title: Localization.labelPrevious,
                icon: "arrow.uturn.backward",
                subtitle: Localization.tipHotkeySwitchPrevious,
                anchor: .hotkeySwitchPrevious,
                name: .switchPrevious
            )
        }
        directionalSection
        if !SpaceWindowMover.isSupported {
            unsupportedNote
        }
        numberedSection
        behaviorNote
    }

    // MARK: - Adjacent Spaces

    /// The left/right hotkeys for all three verbs, one verb's rows at a time
    /// behind the same picker the numbered card uses. Each verb keeps its own
    /// skip toggle: landing a window on an empty Space is a normal way to
    /// start a fresh Desktop, so the window verbs decide separately from
    /// switching.
    private var directionalSection: some View {
        SettingsSection(Localization.labelAdjacentSpaces) {
            verbPicker(Localization.labelAdjacentSpaces, selection: $directionalVerb)
            SettingsRowDivider()
            switch directionalVerb {
            case .switchTo:
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
            case .send:
                recorderRow(
                    title: Localization.labelLeft,
                    icon: "arrowshape.left.fill",
                    subtitle: Localization.tipHotkeySendLeft,
                    anchor: .hotkeySendLeft,
                    name: .sendLeft
                )
                SettingsRowDivider()
                recorderRow(
                    title: Localization.labelRight,
                    icon: "arrowshape.right.fill",
                    subtitle: Localization.tipHotkeySendRight,
                    anchor: .hotkeySendRight,
                    name: .sendRight
                )
                SettingsRowDivider()
                SettingsToggleRow(
                    title: Localization.toggleSkipEmptySpaces,
                    isOn: model.binding(\.hotkeysSendSkipEmptySpaces),
                    icon: "arrow.right.to.line.compact",
                    subtitle: Localization.tipSendSkipEmptySpaces,
                    anchor: .hotkeySendSkipEmptySpaces
                )
            case .move:
                recorderRow(
                    title: Localization.labelLeft,
                    icon: "arrowshape.left.fill",
                    subtitle: Localization.tipHotkeyMoveLeft,
                    anchor: .hotkeyMoveLeft,
                    name: .moveLeft
                )
                SettingsRowDivider()
                recorderRow(
                    title: Localization.labelRight,
                    icon: "arrowshape.right.fill",
                    subtitle: Localization.tipHotkeyMoveRight,
                    anchor: .hotkeyMoveRight,
                    name: .moveRight
                )
                SettingsRowDivider()
                SettingsToggleRow(
                    title: Localization.toggleSkipEmptySpaces,
                    isOn: model.binding(\.hotkeysMoveSkipEmptySpaces),
                    icon: "arrow.right.to.line.compact",
                    subtitle: Localization.tipMoveSkipEmptySpaces,
                    anchor: .hotkeyMoveSkipEmptySpaces
                )
            }
        }
        // A deep link or search hit can target a row the picker is hiding,
        // so the verb follows the anchor before the highlight lands
        .onChange(of: highlighter?.anchor) { _, anchor in
            if let verb = Self.directionalVerb(for: anchor) {
                directionalVerb = verb
            }
        }
        .onAppear {
            if let verb = Self.directionalVerb(for: highlighter?.anchor) {
                directionalVerb = verb
            }
        }
    }

    /// The verb whose rows carry the anchor, nil for anchors outside the
    /// directional card.
    private static func directionalVerb(for anchor: SettingsAnchor?) -> Verb? {
        switch anchor {
        case .hotkeySwitchLeft, .hotkeySwitchRight, .hotkeySkipEmptySpaces:
            .switchTo
        case .hotkeySendLeft, .hotkeySendRight, .hotkeySendSkipEmptySpaces:
            .send
        case .hotkeyMoveLeft, .hotkeyMoveRight, .hotkeyMoveSkipEmptySpaces:
            .move
        default:
            nil
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

    /// The rows outside the numbered list, which differ only in what they say
    /// and which binding they record.
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
            recorder(for: name)
        }
    }

    /// One combination must map to one action: the library invokes every
    /// handler whose name resolves to a shortcut, so a duplicate would fire
    /// both actions on a single press. Recording one already taken asks
    /// before replacing it, naming the action that holds it, and the
    /// confirmed replacement clears the previous owner once the save lands.
    private func recorder(for name: KeyboardShortcuts.Name) -> some View {
        KeyboardShortcuts.Recorder(for: name) { shortcut in
            guard let shortcut,
                  let owner = HotkeyCenter.owner(of: shortcut, excluding: name)
            else {
                return
            }
            KeyboardShortcuts.reset(owner)
        }
        .shortcutValidation { shortcut in
            guard let owner = HotkeyCenter.owner(of: shortcut, excluding: name) else {
                return .allow
            }
            // The combination and its owner go in the detail rather than the
            // title, so the title stays one line at any name length.
            return .confirm(
                reason: Localization.alertDuplicateShortcut,
                message: String(
                    format: Localization.alertDuplicateShortcutDetail,
                    "\(shortcut)",
                    label(for: owner)
                ),
                cancelTitle: Localization.buttonCancel,
                confirmTitle: Localization.buttonReplace
            )
        }
    }

    /// Names an action the way the pane presents it, verb then row, using the
    /// same separator the behavior note uses for a settings path. A picker
    /// may be hiding the row that holds the combination, so the verb has to
    /// be part of the name for it to be findable.
    private func label(for name: KeyboardShortcuts.Name) -> String {
        // Previous has no direction or number and leads on its own card, so
        // the card title names it on its own.
        guard name != .switchPrevious else {
            return Localization.labelPreviousSpace
        }
        for verb in [Verb.switchTo, .send, .move] {
            if let index = verb.numberedNames.firstIndex(of: name) {
                return path(verb.title, numberedLabel(number: index + 1))
            }
            let directional = verb.directionalNames
            if name == directional.left {
                return path(verb.title, Localization.labelLeft)
            }
            if name == directional.right {
                return path(verb.title, Localization.labelRight)
            }
        }
        return name.rawValue
    }

    private func path(_ verb: String, _ row: String) -> String {
        "\(verb) › \(row)"
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
    /// active display. The card lays out every visible row; the pane's own
    /// scroll view handles a revealed sixteen rows overrunning the screen.
    private var numberedSection: some View {
        let visible = visibleNumbers
        return SettingsSection(Localization.labelNumberedSpaces, anchor: .numberedSpaces) {
            verbPicker(Localization.labelNumberedSpaces, selection: $numberedVerb)
            SettingsRowDivider()
            ForEach(Array(visible.enumerated()), id: \.element) { index, number in
                if index > 0 {
                    SettingsRowDivider()
                }
                numberedRow(number: number)
            }
            if hasInactiveSpaces {
                SettingsRowDivider()
                revealToggleButton
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
    private var visibleNumbers: [Int] {
        let all = Array(1 ... HotkeyCenter.maxJumpTargets)
        return revealsInactiveSpaces ? all : all.filter { !isPlaceholder($0) }
    }

    /// A recorded binding on a hidden row must stay visible whichever verb
    /// the picker shows, so every verb's names count.
    private var placeholderHasBinding: Bool {
        (1 ... HotkeyCenter.maxJumpTargets).contains { number in
            isPlaceholder(number) && [
                KeyboardShortcuts.Name.jumpToSpace[number - 1],
                KeyboardShortcuts.Name.sendToSpace[number - 1],
                KeyboardShortcuts.Name.moveToSpace[number - 1],
            ].contains { KeyboardShortcuts.getShortcut(for: $0) != nil }
        }
    }

    /// The verbs share one card's rows, so the picker chooses which binding
    /// a row records rather than growing the card threefold. `title` names
    /// the control for accessibility.
    private func verbPicker(_ title: String, selection: Binding<Verb>) -> some View {
        VerbSegments(title: title, selection: selection)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Layout.settingsRowHorizontalPadding)
            .padding(.vertical, Layout.settingsRowVerticalPadding)
    }

    private func recorderName(for number: Int) -> KeyboardShortcuts.Name {
        switch numberedVerb {
        case .switchTo:
            KeyboardShortcuts.Name.jumpToSpace[number - 1]
        case .send:
            KeyboardShortcuts.Name.sendToSpace[number - 1]
        case .move:
            KeyboardShortcuts.Name.moveToSpace[number - 1]
        }
    }

    /// Whether any bindable number is a placeholder, leaving the toggle
    /// below the rows something to reveal or hide.
    private var hasInactiveSpaces: Bool {
        (1 ... HotkeyCenter.maxJumpTargets).contains(where: isPlaceholder)
    }

    private var revealToggleButton: some View {
        Button {
            withAnimation {
                revealsInactiveSpaces.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: revealsInactiveSpaces ? "chevron.up.2" : "chevron.down.2")
                    .frame(width: Layout.settingsRowIconWidth)
                Text(
                    revealsInactiveSpaces
                        ? Localization.actionHideInactiveSpaces
                        : Localization.actionRevealInactiveSpaces
                )
                Spacer(minLength: 0)
            }
            .font(.system(size: Layout.settingsRowFontSize))
            .foregroundStyle(Color.accentColor.opacity(0.7))
            .padding(.horizontal, Layout.settingsRowHorizontalPadding)
            .padding(.vertical, Layout.settingsRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(revealsInactiveSpaces ? "" : Localization.tipSpacePlaceholderHotkey)
    }

    /// Placeholder rows grey only the name, the same treatment the Spaces
    /// sidebar gives them; the recorder stays full strength because binding
    /// ahead of time is exactly what those rows are for.
    private func numberedRow(number: Int) -> some View {
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
            recorder(for: recorderName(for: number))
        }
        .help(placeholder ? Localization.tipSpacePlaceholderHotkey : "")
    }

    /// What a numbered row calls its Desktop, matching the row above so a
    /// conflict alert names the row the way it reads on screen.
    private func numberedLabel(number: Int) -> String {
        guard model.value(\.localSpaceNumbers) else {
            return editorModel.globalDesktopName(for: number)
        }
        return editorModel.spaceName(for: localCandidate(number))
            ?? String(format: Localization.labelSpaceNumber, number)
    }

    /// The same candidate shape the Spaces sidebar lists: the real entry
    /// while the Space exists, nil past the current count so the name
    /// extrapolates the Desktop number the Space would get.
    private func localCandidate(_ number: Int) -> (number: Int, entry: SpaceEntry?) {
        let entries = appState.allSpaceEntries
        return (number, number <= entries.count ? entries[number - 1] : nil)
    }
}

/// The verb tabs as an `NSSegmentedControl`: SwiftUI's segmented picker
/// sizes to its labels and centers in extra width, while
/// `segmentDistribution = .fillEqually` stretches the segments across the
/// card's full row.
private struct VerbSegments: NSViewRepresentable {
    let title: String
    @Binding fileprivate var selection: KeyboardPane.Verb

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: [
                Localization.labelSwitch,
                Localization.labelSendWindow,
                Localization.labelMoveWindow,
            ],
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(title)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        control.selectedSegment = selection.rawValue
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        fileprivate var selection: Binding<KeyboardPane.Verb>

        fileprivate init(selection: Binding<KeyboardPane.Verb>) {
            self.selection = selection
        }

        @MainActor
        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            guard let verb = KeyboardPane.Verb(rawValue: sender.selectedSegment) else {
                return
            }
            selection.wrappedValue = verb
        }
    }
}

/// What each verb records, so a conflict alert can name a binding by the
/// picker tab and row it lives behind rather than by its storage key.
private extension KeyboardPane.Verb {
    var title: String {
        switch self {
        case .switchTo:
            Localization.labelSwitch
        case .send:
            Localization.labelSendWindow
        case .move:
            Localization.labelMoveWindow
        }
    }

    var numberedNames: [KeyboardShortcuts.Name] {
        switch self {
        case .switchTo:
            KeyboardShortcuts.Name.jumpToSpace
        case .send:
            KeyboardShortcuts.Name.sendToSpace
        case .move:
            KeyboardShortcuts.Name.moveToSpace
        }
    }

    var directionalNames: (left: KeyboardShortcuts.Name, right: KeyboardShortcuts.Name) {
        switch self {
        case .switchTo:
            (.switchLeft, .switchRight)
        case .send:
            (.sendLeft, .sendRight)
        case .move:
            (.moveLeft, .moveRight)
        }
    }
}
