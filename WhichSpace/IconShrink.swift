import AppKit

// MARK: - Shrink Level

/// How far the status item has been degraded to keep it on the menu bar.
///
/// The ladder only ever descends. It returns to `full` when the user switches
/// Space, clicks the status item, changes a setting, or the display
/// configuration changes.
enum IconShrinkLevel: Int, CaseIterable, Comparable, Sendable {
    /// Every Space rendered with the user's own labels, symbols and badges
    case full = 0
    /// Every Space reduced to a bare numeral with no padding
    case compact = 1
    /// One numeral per display, showing that display's active Space
    case activePerDisplay = 2
    /// The current Space alone
    case currentOnly = 3

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The next level down, or nil at the bottom of the ladder.
    var next: Self? {
        Self(rawValue: rawValue + 1)
    }

    /// Whether per-Space labels, symbols and badges still apply. Shrunk icons
    /// render the Space number alone, which is both narrower and cheaper: the
    /// preference lookups behind those values are skipped entirely.
    var usesCustomStyling: Bool {
        self == .full
    }

    /// Whether fullscreen Spaces keep a slot of their own.
    var showsFullscreenSpaces: Bool {
        self == .full
    }

    /// Whether Spaces other than each display's active one keep a slot.
    var showsInactiveSpaces: Bool {
        self <= .compact
    }

    /// Whether displays other than the current one keep a slot. Giving up the
    /// other displays comes last, because it is the only step that stops
    /// reporting a Space the user can see.
    var showsOtherDisplays: Bool {
        self != .currentOnly
    }

    /// The padding scale to render at, or nil to use the user's preference.
    /// Shrunk icons give up nearly all their padding before they give up a
    /// Space, keeping the point that stops neighbouring icons merging into one
    /// continuous block.
    var paddingScaleOverride: Double? {
        self == .full ? nil : Layout.shrunkPaddingScale
    }
}

// MARK: - Status Window Probe

/// What the menu bar looked like at the moment of a reading.
///
/// The two halves come from different places on purpose. Whether this app's
/// own icon is drawn is an AppKit fact, read from the status window's
/// occlusion state. Whether anyone else's is drawn is a WindowServer fact,
/// read from the window list. Neither source can answer both halves: the
/// WindowServer does not attribute a status item to the app that created it,
/// so this app's own status window never appears in the list, and occlusion
/// is only observable for windows this process owns.
struct StatusWindowSnapshot: Equatable, Sendable {
    /// Whether this app's own status item is drawn
    let ownWindowIsOnScreen: Bool
    /// How many other processes' status items are drawn on the same display
    let otherStatusWindowCount: Int
    /// Whether the screen is showing the desktop, rather than the lock screen,
    /// the screensaver, or a sleeping display.
    ///
    /// Those states are the one case the neighbour count cannot speak for.
    /// Measured on a locked screen, the display keeps between 4 and 20 status
    /// windows drawn while this app's own occlusion drops, which reads exactly
    /// like running out of room. They have to be excluded by name.
    let sessionIsActive: Bool

    /// Whether the menu bar is drawing anything at all besides this app.
    var otherMenuBarWindowIsOnScreen: Bool {
        otherStatusWindowCount > 0
    }

    /// The reading that keeps the icon at full size, used when a source is
    /// unavailable so a failed query never shrinks anything.
    static let unavailable = Self(
        ownWindowIsOnScreen: true,
        otherStatusWindowCount: 0,
        sessionIsActive: true
    )
}

/// Reports what else the menu bar is drawing; stubbed in tests.
protocol MenuBarVisibilityProbe: Sendable {
    /// How many other processes' status items are drawn on the given display.
    ///
    /// A count rather than a flag: zero answers whether the bar is drawn at
    /// all, and a drop in the count is the only cheap evidence that room may
    /// have opened up.
    func otherStatusWindowCount(onDisplay bounds: CGRect) -> Int
}

/// Default implementation backed by the window list.
///
/// Only window levels, owners, bounds and the on-screen flag are read. Those
/// carry no privacy restriction, unlike `kCGWindowName`, so this needs no
/// Screen Recording permission.
struct CGMenuBarVisibilityProbe: MenuBarVisibilityProbe {
    /// Status items sit one level above the menu bar the WindowServer draws.
    ///
    /// The menu bar's own level is deliberately not accepted as evidence: on a
    /// display showing a fullscreen Space its window stays on screen while
    /// that display's bar and its status items are hidden, so counting it
    /// would report a drawn bar where there is none.
    private static let statusLevel = Int(CGWindowLevelForKey(.statusWindow))

    func otherStatusWindowCount(onDisplay bounds: CGRect) -> Int {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]]
        else {
            return 0
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        return windowList.count { window in
            guard window[kCGWindowLayer as String] as? Int == Self.statusLevel,
                  window[kCGWindowOwnerPID as String] as? pid_t != ownPID,
                  let frame = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: frame as CFDictionary)
            else {
                return false
            }
            // Scoped to one display: a fullscreen Space hides that display's
            // bar while another display keeps drawing its own, so a global
            // count reads as a drawn bar when ours is gone
            return rect.intersects(bounds)
        }
    }
}

// MARK: - Eviction Detector

/// Tracks whether the status item has been dropped from the menu bar for lack
/// of room, and how far to degrade the icon in response.
///
/// macOS posts no notification when it drops a status item, and
/// `NSStatusItem.isVisible` keeps reporting the app's intent rather than what
/// reached the screen, so eviction has to be observed rather than asked for.
///
/// The reading that distinguishes eviction from an ordinary hidden menu bar is
/// a relative one: running out of room takes this app's item off screen and
/// leaves its neighbours behind, while a fullscreen Space, menu bar auto-hide,
/// Mission Control, the lock screen, the screensaver and display sleep take
/// every menu bar window off screen together.
struct MenuBarEvictionDetector {
    /// How long a freshly assigned icon is given to be laid out again. Setting
    /// the image relayouts the bar, during which the item reads as off screen.
    static let settleInterval: TimeInterval = 0.4

    /// How long after a render the deciding reading is taken. A little past
    /// the settle interval, so a reading is never discarded for landing on
    /// the boundary.
    static let checkDelay: TimeInterval = settleInterval + 0.05

    private(set) var level: IconShrinkLevel = .full

    private var settleDeadline: Date = .distantPast
    /// How many other status items shared the display when the icon last gave
    /// up a level. Growing back means widening the item, which reflows every
    /// icon to its left, so it is only worth attempting on evidence that the
    /// crowding eased.
    private var neighbourCountWhenShrunk: Int?
    /// Whether the recorded neighbour count still comes from the eviction
    /// reading. That reading is taken while the arriving status item is
    /// mid-layout and not yet drawn, so it misses the very item that caused
    /// the shrink; the first settled reading afterwards replaces it.
    private var neighbourCountIsProvisional = false

    /// Holds readings off until the status item has been laid out again.
    mutating func beginSettling(now: Date) {
        settleDeadline = now.addingTimeInterval(Self.settleInterval)
    }

    /// The moment a held-off reading becomes usable again.
    var settleDeadlineDate: Date {
        settleDeadline
    }

    /// Whether the next settled reading is still needed to replace the
    /// provisional neighbour count, even at the bottom of the ladder.
    var awaitingSettledNeighbourCount: Bool {
        neighbourCountIsProvisional
    }

    /// Applies a probe reading, returning the level to render at, or nil to
    /// leave the icon as it is.
    mutating func apply(_ snapshot: StatusWindowSnapshot, now: Date) -> IconShrinkLevel? {
        guard now >= settleDeadline,
              snapshot.sessionIsActive,
              snapshot.otherMenuBarWindowIsOnScreen
        else {
            return nil
        }

        if snapshot.ownWindowIsOnScreen {
            // The settled reading is the first to count the item whose
            // arrival caused the shrink. Taking the larger of the two
            // readings keeps a transient departure between them from
            // lowering the bar for growing back.
            if neighbourCountIsProvisional {
                neighbourCountWhenShrunk = max(
                    neighbourCountWhenShrunk ?? 0,
                    snapshot.otherStatusWindowCount
                )
                neighbourCountIsProvisional = false
            }
            return nil
        }

        guard let next = level.next else {
            return nil
        }

        level = next
        neighbourCountWhenShrunk = snapshot.otherStatusWindowCount
        neighbourCountIsProvisional = true
        return next
    }

    /// Whether the icon has earned another attempt at full size.
    ///
    /// A Space switch on its own is not evidence: the menu bar holds the same
    /// items either way, so expanding would only widen the item, reflow every
    /// icon to its left, and collapse again a moment later. A status item
    /// going away is evidence, and it is the case the user is waiting on.
    func shouldRetryFullSize(otherStatusWindowCount: Int) -> Bool {
        guard level != .full, let neighbourCountWhenShrunk else {
            return false
        }
        return otherStatusWindowCount < neighbourCountWhenShrunk
    }

    /// Returns the icon to full size.
    ///
    /// Called when the user switches Space, changes a setting, or the display
    /// configuration changes. Every layout starts at the top of the ladder and
    /// steps down only as far as the readings require: remembering where a
    /// layout settled last time would save a step, but a remembered level is
    /// applied without testing the one above it, so a stale entry can never
    /// discover that the shallower level now fits.
    mutating func reset() {
        level = .full
        settleDeadline = .distantPast
        neighbourCountWhenShrunk = nil
        neighbourCountIsProvisional = false
    }
}
