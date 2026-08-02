import AppKit
import SwiftUI

private extension NSToolbarItem.Identifier {
    /// AppKit publishes no identifier for a search item, so the field brings
    /// its own
    static let settingsSearch = Self("settingsSearch")
}

// MARK: - SettingsSearchController

/// Puts a search field in the settings window's toolbar and turns a chosen
/// result into a jump to that setting.
///
/// The window comes from the Settings package, whose tab controller owns the
/// toolbar and its delegate. Rather than fork the package, this stands in
/// front of that delegate: pane items are forwarded untouched and the search
/// item is answered here, so the package keeps driving tab selection.
@MainActor
final class SettingsSearchController: NSObject {
    /// How wide the field sits in the titlebar, and where it puts its
    /// results
    private static let searchFieldWidth = 160.0
    private static let popoverWidth = 320.0
    private static let popoverMaxHeight = 320.0

    private let onSelect: (SettingsSearchEntry) -> Void

    /// The package's own delegate, kept so its items still resolve. Weak
    /// because the tab controller belongs to the window.
    private weak var base: NSToolbarDelegate?
    private weak var searchItem: NSSearchToolbarItem?
    private weak var searchField: NSSearchField?
    private var shortcutMonitor: Any?
    private var popover: NSPopover?
    /// Kept across keystrokes so the list refreshes in place; a replacement
    /// controller rebuilds the view hierarchy and takes focus off the field.
    private var resultsHost: NSHostingController<SettingsSearchResultsView>?
    private var results: [SettingsSearchEntry] = []
    /// Which result Return takes. The list is driven from the field, which
    /// keeps focus, so the highlight is tracked here rather than by SwiftUI.
    private var selected = 0

    init(onSelect: @escaping (SettingsSearchEntry) -> Void) {
        self.onSelect = onSelect
    }

    /// Adds the field to a window's toolbar. Called once, after the package
    /// has built the toolbar, so the items it inserted are already there and
    /// the search item only has to be appended.
    func attach(to window: NSWindow) {
        guard let toolbar = window.toolbar, base == nil else {
            return
        }
        base = toolbar.delegate
        toolbar.delegate = self
        // The preference style centres its items as one group, leaving a
        // flexible space no room to work
        window.toolbarStyle = .expanded
        toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: toolbar.items.count)
        toolbar.insertItem(withItemIdentifier: .settingsSearch, at: toolbar.items.count)
        observeShortcut(in: window)
    }

    /// Takes Command-F to the field.
    ///
    /// An accessory app has no main menu to hang a key equivalent on, so the
    /// shortcut is watched for directly. The monitor is app-wide, hence the
    /// check that the event belongs to this window; it lives as long as the
    /// controller, which the coordinator keeps for the app's lifetime.
    private func observeShortcut(in window: NSWindow) {
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, event.window === window, Self.isSearchShortcut(event) else {
                return event
            }
            focusField()
            return nil
        }
    }

    /// Command-F, with no other modifier along for the ride.
    private static func isSearchShortcut(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "f"
    }

    /// Focuses the field and selects whatever is in it, so a second
    /// Command-F starts a new query rather than appending to the old one.
    private func focusField() {
        searchItem?.beginSearchInteraction()
        guard let field = searchField else {
            return
        }
        field.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// Empties the field and puts the results away. Called when the window
    /// closes so it does not reopen mid-query.
    func reset() {
        searchField?.stringValue = ""
        dismissResults()
    }

    // MARK: - Results

    private func updateResults(for query: String) {
        results = SettingsSearchIndex.results(for: query)
        guard !results.isEmpty else {
            dismissResults()
            return
        }
        // A narrowed query leaves the old highlight pointing at a different
        // setting, so each round starts back at the top
        selected = 0
        showResults()
    }

    private func showResults() {
        guard let field = searchField else {
            return
        }
        let list = SettingsSearchResultsView(results: results, selected: selected) { [weak self] entry in
            self?.choose(entry)
        }
        if let resultsHost, popover?.isShown == true {
            resultsHost.rootView = list
            resize(resultsHost)
            return
        }
        let content = NSHostingController(rootView: list)
        resize(content)
        resultsHost = content
        let popover = NSPopover()
        popover.contentViewController = content
        popover.behavior = .transient
        // A transient popover also closes on a click elsewhere, which the
        // delegate reports so the results go with it
        popover.delegate = self
        // Animating a list that reopens on every keystroke reads as flicker
        popover.animates = false
        self.popover = popover
        let selection = field.currentEditor()?.selectedRange
        popover.show(relativeTo: field.bounds, of: field, preferredEdge: .maxY)
        restoreTyping(in: field, selection: selection)
    }

    /// Keeps the query intact when the list appears. A popover can take key
    /// focus, and reclaiming it selects the field's whole text, so the caret
    /// goes back where it was; a field that kept focus is left alone.
    private func restoreTyping(in field: NSSearchField, selection: NSRange?) {
        guard field.currentEditor() == nil else {
            return
        }
        field.window?.makeFirstResponder(field)
        guard let selection, let editor = field.currentEditor() else {
            return
        }
        editor.selectedRange = selection
    }

    /// Fits the popover to however many results the query left, capped so a
    /// broad query scrolls rather than running down the screen.
    ///
    /// The rows are measured on their own: the scroll view carrying them
    /// takes whatever height it is offered, so measuring it would pad every
    /// list out to the cap.
    private func resize(_ host: NSHostingController<SettingsSearchResultsView>) {
        let rows = NSHostingController(
            rootView: SettingsSearchResultRows(results: results) { _ in }
        )
        let fitted = rows.sizeThatFits(
            in: NSSize(width: Self.popoverWidth, height: .greatestFiniteMagnitude)
        )
        host.preferredContentSize = NSSize(
            width: Self.popoverWidth,
            height: min(fitted.height, Self.popoverMaxHeight)
        )
    }

    /// Puts the list away and forgets what was in it. Dropping the results is
    /// the point: Return acts on them, so results outliving their visible
    /// list would let a later Return navigate to something never shown.
    private func dismissResults() {
        popover?.performClose(nil)
        popover = nil
        resultsHost = nil
        results = []
        selected = 0
    }

    /// Moves the highlight, keeping it inside the list rather than wrapping,
    /// so holding an arrow key settles at an end.
    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else {
            return
        }
        selected = (selected + offset).clamped(to: 0 ... results.count - 1)
        showResults()
    }

    /// Navigates to a result and stands down: the field has done its job, and
    /// leaving the query in place would keep the list covering the row the
    /// user was sent to.
    private func choose(_ entry: SettingsSearchEntry) {
        dismissResults()
        searchField?.stringValue = ""
        searchField?.window?.makeFirstResponder(nil)
        onSelect(entry)
    }
}

// MARK: - NSToolbarDelegate

extension SettingsSearchController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        (base?.toolbarDefaultItemIdentifiers?(toolbar) ?? []) + [.flexibleSpace, .settingsSearch]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        (base?.toolbarAllowedItemIdentifiers?(toolbar) ?? []) + [.flexibleSpace, .settingsSearch]
    }

    /// The field is not a pane, so it stays out of the selectable set - a
    /// selectable search item would take the highlight off the current pane.
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        base?.toolbarSelectableItemIdentifiers?(toolbar) ?? []
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == .settingsSearch else {
            return base?.toolbar?(
                toolbar, itemForItemIdentifier: itemIdentifier, willBeInsertedIntoToolbar: flag
            )
        }
        let item = NSSearchToolbarItem(itemIdentifier: .settingsSearch)
        // Every item is captioned beneath its icon, which under a search
        // field only repeats its own placeholder. The overflow menu takes
        // its title from the same label, so it is named separately.
        item.label = ""
        item.paletteLabel = Localization.search
        // No main menu means no key equivalent to carry the shortcut, so the
        // tooltip is where it gets named. Key symbols are not localized.
        item.toolTip = "\(String(format: Localization.tipSearch, AppInfo.appName)) (⌘F)"
        item.menuFormRepresentation = NSMenuItem(
            title: Localization.search, action: nil, keyEquivalent: ""
        )
        let field = item.searchField
        field.delegate = self
        field.placeholderString = Localization.search
        field.setAccessibilityLabel(Localization.search)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        // The item takes whatever width the flexible space frees up, and
        // preferredWidthForSearchField only sizes the field when a collapsed
        // item expands on focus. Capping the field's own width is what the
        // item honors; a maximum rather than an equality leaves it free to
        // compress in a narrow toolbar.
        field.widthAnchor.constraint(lessThanOrEqualToConstant: Self.searchFieldWidth).isActive = true
        item.preferredWidthForSearchField = Self.searchFieldWidth
        searchItem = item
        searchField = field
        return item
    }
}

// MARK: - NSPopoverDelegate

extension SettingsSearchController: NSPopoverDelegate {
    /// Covers the dismissals the controller does not make itself, chiefly a
    /// click outside the list, so Return cannot act on results that are no
    /// longer on screen.
    func popoverDidClose(_: Notification) {
        popover = nil
        resultsHost = nil
        results = []
        selected = 0
    }
}

// MARK: - NSSearchFieldDelegate

extension SettingsSearchController: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else {
            return
        }
        updateResults(for: field.stringValue)
    }

    /// The arrows walk the list and Return takes the highlighted result,
    /// with the field keeping focus throughout so the query stays editable.
    /// Escape puts the list away without closing the window, which is what
    /// Escape would otherwise do.
    ///
    /// Each case defers to the field unless the list is actually on screen,
    /// so these keys behave normally in an empty or dismissed field.
    func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard popover?.isShown == true else {
            return false
        }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            guard results.indices.contains(selected) else {
                return false
            }
            choose(results[selected])
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismissResults()
            return true
        default:
            return false
        }
    }
}

// MARK: - SettingsSearchResultsView

/// The list under the search field: each row names a setting and where it
/// lives, and picking one navigates there.
private struct SettingsSearchResultsView: View {
    let results: [SettingsSearchEntry]
    let selected: Int
    let onSelect: (SettingsSearchEntry) -> Void

    var body: some View {
        // The highlight can be arrowed past the bottom of a capped list, so
        // the scroller follows it
        ScrollViewReader { proxy in
            ScrollView {
                SettingsSearchResultRows(
                    results: results, selected: selected, onSelect: onSelect
                )
            }
            .onChange(of: selected) { _, index in
                guard results.indices.contains(index) else {
                    return
                }
                proxy.scrollTo(results[index].id, anchor: .bottom)
            }
        }
    }
}

// MARK: - SettingsSearchResultRows

/// The rows without the scroll view around them, so the popover has
/// something to measure that reports the height the results actually need.
private struct SettingsSearchResultRows: View {
    let results: [SettingsSearchEntry]
    var selected = -1
    let onSelect: (SettingsSearchEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                row(entry, isSelected: index == selected)
            }
        }
        .padding(6)
    }

    private func row(_ entry: SettingsSearchEntry, isSelected: Bool) -> some View {
        Button {
            onSelect(entry)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .lineLimit(1)
                Text(entry.breadcrumb)
                    .font(.system(size: Layout.settingsRowSubtitleFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        // Focusable rows pull the keyboard away from the search field the
        // moment the list appears, leaving the query half typed
        .focusable(false)
        .id(entry.id)
    }
}
