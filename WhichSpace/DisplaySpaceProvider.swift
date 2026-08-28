import Cocoa

// MARK: - Display Space Provider Protocol

/// Protocol for abstracting CGS display space functions for testability
protocol DisplaySpaceProvider: Sendable {
    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]?
    func copyActiveMenuBarDisplayIdentifier() -> String?
    func displayBounds(forIdentifier identifier: String) -> CGRect?
    func fullscreenOwnerPIDs(forSpaceIDs spaceIDs: [Int]) -> [Int: pid_t]
    func spacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int>
    func windowOwnerPIDs(forSpaceIDs spaceIDs: [Int]) -> [Int: [pid_t]]
}

// MARK: - Display Geometry

/// Resolves a CGS "Display Identifier" UUID string to its global CG frame.
/// Returns nil for identifiers with no matching display, including the
/// literal "Main" used when "Displays have separate Spaces" is off.
enum DisplayGeometry {
    static func bounds(forDisplayIdentifier identifier: String) -> CGRect? {
        guard let uuid = CFUUIDCreateFromString(nil, identifier as CFString) else {
            return nil
        }
        let displayID = CGDisplayGetDisplayIDFromUUID(uuid)
        guard displayID != kCGNullDirectDisplay else {
            return nil
        }
        return CGDisplayBounds(displayID)
    }
}

// MARK: - Display Arrangement

/// Orders display-keyed items by physical monitor position, left to right
/// then top to bottom. Generic so the snapshot builder and the space
/// switcher share one definition of arrangement order.
enum DisplayArrangement {
    /// Stable sort by (origin.x, origin.y) of each item's display frame in
    /// global CG coordinates. Returns `items` unchanged when any frame is
    /// unresolvable, keeping CGS order rather than sorting a partial set.
    static func sorted<Element>(
        _ items: [Element],
        identifier: (Element) -> String,
        bounds: (String) -> CGRect?
    ) -> [Element] {
        guard items.count > 1 else {
            return items
        }
        var frames: [CGRect] = []
        for item in items {
            guard let frame = bounds(identifier(item)) else {
                return items
            }
            frames.append(frame)
        }
        let order = items.indices.sorted { lhs, rhs in
            let left = frames[lhs]
            let right = frames[rhs]
            if left.origin.x != right.origin.x {
                return left.origin.x < right.origin.x
            }
            if left.origin.y != right.origin.y {
                return left.origin.y < right.origin.y
            }
            // Swift's sort is not guaranteed stable; equal frames (e.g.
            // mirrored displays) keep their CGS relative order.
            return lhs < rhs
        }
        return order.map { items[$0] }
    }
}

// MARK: - CGSDisplaySpaceProvider

/// Default implementation using the actual CGS/SLS functions
struct CGSDisplaySpaceProvider: DisplaySpaceProvider {
    /// Window server attribute bit set while a window is ordered in,
    /// including windows on other Spaces and displays.
    private static let orderedInAttribute: UInt64 = 0x2

    /// Tag bits carried by windows that are ordered out yet still occupy
    /// their Space: minimized to the Dock (bit 60, bit 58 on older
    /// releases) or part of a hidden app (bit 39).
    private static let orderedOutOccupantTags: UInt64 = 0x1400_0080_0000_0000

    private let conn: Int32

    init() {
        conn = _CGSDefaultConnection()
    }

    /// Whether iterator state describes a window that occupies its Space.
    /// A closed window an app keeps alive in the window server clears the
    /// ordered-in attribute and carries none of the minimized or hidden
    /// tags, yet still reports the Space it was last on. Counting it kept
    /// the app's icon on that Space until the app quit (issue #86).
    static func isSpaceOccupant(attributes: UInt64, tags: UInt64) -> Bool {
        attributes & orderedInAttribute != 0 || tags & orderedOutOccupantTags != 0
    }

    /// Filters `windowIDs` to windows that occupy their Space, dropping
    /// closed windows the owning app never released. Returns the input
    /// unchanged when the query fails so occupancy degrades to the
    /// unfiltered behavior rather than reporting every Space empty.
    private func spaceOccupantWindowIDs(_ windowIDs: [Int]) -> [Int] {
        guard !windowIDs.isEmpty,
              let query = SLSWindowQueryWindows(conn, windowIDs as CFArray, Int32(windowIDs.count))
        else {
            return windowIDs
        }
        let queryObject = query.takeRetainedValue()
        guard let result = SLSWindowQueryResultCopyWindows(queryObject) else {
            return windowIDs
        }
        let iterator = result.takeRetainedValue()
        var occupants: Set<Int> = []
        while SLSWindowIteratorAdvance(iterator) {
            let attributes = SLSWindowIteratorGetAttributes(iterator)
            let tags = SLSWindowIteratorGetTags(iterator)
            if Self.isSpaceOccupant(attributes: attributes, tags: tags) {
                occupants.insert(Int(SLSWindowIteratorGetWindowID(iterator)))
            }
        }
        return windowIDs.filter(occupants.contains)
    }

    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]? {
        guard let result = CGSCopyManagedDisplaySpaces(conn) else {
            return nil
        }
        return result.takeRetainedValue() as? [NSDictionary]
    }

    func copyActiveMenuBarDisplayIdentifier() -> String? {
        guard let result = CGSCopyActiveMenuBarDisplayIdentifier(conn) else {
            return nil
        }
        return result.takeRetainedValue() as String
    }

    func displayBounds(forIdentifier identifier: String) -> CGRect? {
        DisplayGeometry.bounds(forDisplayIdentifier: identifier)
    }

    func spacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int> {
        // Get all windows (not just on-screen) to detect windows on other spaces
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // Collect all qualifying window IDs
        var windowIDs: [Int] = []

        for window in windowList {
            // Filter to regular windows (layer 0) - skip menu bar, dock, etc.
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }

            // Skip windows that are too small (likely utility/overlay windows)
            guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 5, height > 5
            else {
                continue
            }

            if let windowNumber = window[kCGWindowNumber as String] as? Int {
                windowIDs.append(windowNumber)
            }
        }

        let occupantIDs = spaceOccupantWindowIDs(windowIDs)
        guard !occupantIDs.isEmpty else {
            return []
        }

        // Single batch call to get all spaces for all windows
        // Selector 0x7 = all spaces the windows are on
        guard let result = SLSCopySpacesForWindows(conn, 0x7, occupantIDs as CFArray) else {
            return []
        }
        let spaces = result.takeRetainedValue() as? [Int] ?? []

        let spaceIDSet = Set(spaceIDs)
        return Set(spaces).intersection(spaceIDSet)
    }

    /// Maps each fullscreen space ID to the PID of the app whose window lives on it.
    /// Windows are grouped by owning app (front-to-back) so each app needs one
    /// batched space query, and the walk stops once every space is resolved.
    func fullscreenOwnerPIDs(forSpaceIDs spaceIDs: [Int]) -> [Int: pid_t] {
        guard !spaceIDs.isEmpty else {
            return [:]
        }
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var windowsByPID: [pid_t: [Int]] = [:]
        var orderedPIDs: [pid_t] = []
        for window in windowList {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowNumber = window[kCGWindowNumber as String] as? Int,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
            else {
                continue
            }
            if windowsByPID[ownerPID] == nil {
                orderedPIDs.append(ownerPID)
            }
            windowsByPID[ownerPID, default: []].append(windowNumber)
        }

        let occupantIDs = Set(spaceOccupantWindowIDs(Array(windowsByPID.values.joined())))
        var unresolved = Set(spaceIDs)
        var owners: [Int: pid_t] = [:]
        for pid in orderedPIDs {
            guard !unresolved.isEmpty else {
                break
            }
            let windowNumbers = windowsByPID[pid, default: []].filter(occupantIDs.contains)
            guard !windowNumbers.isEmpty,
                  let result = SLSCopySpacesForWindows(conn, 0x7, windowNumbers as CFArray)
            else {
                continue
            }
            let spaces = result.takeRetainedValue() as? [Int] ?? []
            for spaceID in spaces where unresolved.contains(spaceID) {
                owners[spaceID] = pid
                unresolved.remove(spaceID)
            }
        }
        return owners
    }

    /// Maps each requested Space ID to the apps with qualifying windows on
    /// it, frontmost app first. Windows are grouped by owning app so each app
    /// needs one batched space query in the common case.
    func windowOwnerPIDs(forSpaceIDs spaceIDs: [Int]) -> [Int: [pid_t]] {
        guard !spaceIDs.isEmpty else {
            return [:]
        }
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var windowsByPID: [pid_t: [Int]] = [:]
        var orderedPIDs: [pid_t] = []
        for window in windowList {
            // Same qualification as spacesWithWindows: regular layer-0
            // windows larger than 5x5
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 5, height > 5,
                  let windowNumber = window[kCGWindowNumber as String] as? Int,
                  let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t
            else {
                continue
            }
            if windowsByPID[ownerPID] == nil {
                orderedPIDs.append(ownerPID)
            }
            windowsByPID[ownerPID, default: []].append(windowNumber)
        }

        let occupantIDs = Set(spaceOccupantWindowIDs(Array(windowsByPID.values.joined())))
        let appWindows = orderedPIDs.map { pid in
            (pid: pid, windowIDs: windowsByPID[pid, default: []].filter(occupantIDs.contains))
        }
        return Self.resolveWindowOwners(appWindows: appWindows, spaceIDs: spaceIDs) { windowNumbers in
            guard let result = SLSCopySpacesForWindows(conn, 0x7, windowNumbers as CFArray) else {
                return []
            }
            return result.takeRetainedValue() as? [Int] ?? []
        }
    }

    /// Resolves each app's Space occupancy from its windows. The batched
    /// query returns the union over an app's windows, so an app that covers
    /// every requested Space is re-queried per window: a window assigned to
    /// all Spaces is dropped rather than attributing the app everywhere,
    /// while an app with one real window per Space keeps them all. The
    /// filter is skipped for a single requested Space, where every window
    /// trivially covers the whole set.
    static func resolveWindowOwners(
        appWindows: [(pid: pid_t, windowIDs: [Int])],
        spaceIDs: [Int],
        spacesForWindows: ([Int]) -> [Int]
    ) -> [Int: [pid_t]] {
        let requested = Set(spaceIDs)
        guard !requested.isEmpty else {
            return [:]
        }
        var owners: [Int: [pid_t]] = [:]
        for app in appWindows where !app.windowIDs.isEmpty {
            var covered = Set(spacesForWindows(app.windowIDs)).intersection(requested)
            if covered == requested, requested.count > 1 {
                var surviving: Set<Int> = []
                for windowID in app.windowIDs {
                    let windowSpaces = Set(spacesForWindows([windowID])).intersection(requested)
                    if windowSpaces != requested {
                        surviving.formUnion(windowSpaces)
                    }
                }
                covered = surviving
            }
            for spaceID in spaceIDs where covered.contains(spaceID) {
                owners[spaceID, default: []].append(app.pid)
            }
        }
        return owners
    }
}
