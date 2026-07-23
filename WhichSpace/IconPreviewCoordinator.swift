import AppKit

/// A single hover-preview render request for the status bar icon.
struct IconPreviewRequest {
    let background: NSColor?
    let badgePosition: BadgePosition?
    let clearSymbol: Bool
    let clearSymbolBackground: Bool
    let foreground: NSColor?
    let labelStyle: IconStyle?
    let separatorColor: NSColor?
    let skinTone: SkinTone?
    let style: IconStyle?
    let symbol: String?
    let symbolBackground: NSColor?
    let symbolColor: NSColor?
    let symbolPosition: SymbolPosition?
    let symbolWrap: SymbolWrap?
}

/// Owns the status bar icon hover-preview lifecycle: coalesces rapid
/// preview requests to ~60Hz with latest-wins semantics, defers hover-end
/// restores so sweeps across preview rows never flash the base icon, and
/// guarantees stale previews cannot apply after preview mode ends.
@MainActor
final class IconPreviewCoordinator {
    /// Renders and installs a preview icon; returns false when the status
    /// item isn't available so preview mode is not entered.
    private let applyPreview: (IconPreviewRequest) -> Bool
    /// Reinstalls the regular (non-preview) status bar icon.
    private let restoreBaseIcon: () -> Void

    private(set) var isPreviewing = false
    /// Latest preview request waiting for the next throttle slot
    private var pendingRequest: IconPreviewRequest?
    /// Defers hover-end restores so sweeping across preview rows doesn't
    /// commit a base-icon frame between consecutive previews (the restore
    /// would win the vsync and the intermediate previews would never show)
    private var restoreTimer: Timer?
    /// Non-nil while inside a one-frame preview coalescing window
    private var throttleTimer: Timer?

    init(
        applyPreview: @escaping (IconPreviewRequest) -> Bool,
        restoreBaseIcon: @escaping () -> Void
    ) {
        self.applyPreview = applyPreview
        self.restoreBaseIcon = restoreBaseIcon
    }

    /// Records a preview request; applies immediately when idle, otherwise
    /// coalesces to ~60Hz with latest-wins semantics.
    ///
    /// Rendering synchronously in every tracking-event handler makes the
    /// handler slower than the mouse-event arrival rate, so the main thread
    /// falls behind the sweep and previews replay late in a burst. Keeping
    /// the handler near-zero cost and applying at most one preview per
    /// display frame keeps the preview locked to the cursor.
    func show(_ request: IconPreviewRequest) {
        // A new hover arrived - cancel any pending restore from the row we
        // just left so the base icon never flashes between two previews
        restoreTimer?.invalidate()
        restoreTimer = nil
        pendingRequest = request
        // Idle: apply on the spot so the first hover feels instant, then
        // open a one-frame coalescing window for any follow-up hovers
        if throttleTimer == nil {
            flushPendingRequest()
            armThrottle()
        }
    }

    /// Schedules a deferred restore of the base icon once the pointer has
    /// left preview content. mouseExited fires before the next row's
    /// mouseEntered, and an immediate restore would commit a base-icon
    /// frame between consecutive previews. The timer is cancelled by
    /// `show` when hovering continues to another preview row.
    func scheduleRestore() {
        guard isPreviewing else {
            return
        }
        // The pointer has left preview content - a preview still waiting
        // for a throttle slot is stale and must not apply after this point
        pendingRequest = nil
        // Already scheduled: don't push the restore out again, or sweeping
        // across plain menu items (each schedules a restore) would defer
        // the restore indefinitely
        guard restoreTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: 0.08, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.end()
            }
        }
        // .common includes the menu-tracking mode; a default-mode timer
        // would not fire until the menu closes
        RunLoop.main.add(timer, forMode: .common)
        restoreTimer = timer
    }

    /// Ends preview mode and reinstalls the base icon. Cancels all
    /// in-flight preview work first, otherwise a stale preview could apply
    /// after the menu has closed and stick until the next icon update.
    func end() {
        cancelPendingWork()
        guard isPreviewing else {
            return
        }
        isPreviewing = false
        restoreBaseIcon()
    }

    /// Ends preview mode without reinstalling the base icon, for callers
    /// about to trigger their own icon update - a restore here would
    /// render the stale pre-change icon first.
    func endWithoutRestore() {
        cancelPendingWork()
        isPreviewing = false
    }

    /// Cancels a scheduled restore, a preview waiting for a throttle slot,
    /// and the throttle window itself.
    private func cancelPendingWork() {
        restoreTimer?.invalidate()
        restoreTimer = nil
        pendingRequest = nil
        throttleTimer?.invalidate()
        throttleTimer = nil
    }

    private func flushPendingRequest() {
        guard let request = pendingRequest else {
            return
        }
        pendingRequest = nil
        if applyPreview(request) {
            isPreviewing = true
        }
    }

    private func armThrottle() {
        // Fixed 60Hz regardless of display refresh rate: each apply costs
        // several ms (icon render + forced display + CATransaction.flush),
        // which fits a 16ms slot comfortably but could saturate the main
        // thread at 120Hz - and a status bar preview gains nothing visible
        // beyond 60 updates/sec
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.throttleTimer = nil
                if self.pendingRequest != nil {
                    self.flushPendingRequest()
                    self.armThrottle()
                }
            }
        }
        // .common includes the menu-tracking mode; a default-mode timer
        // would not fire until the menu closes
        RunLoop.main.add(timer, forMode: .common)
        throttleTimer = timer
    }
}
