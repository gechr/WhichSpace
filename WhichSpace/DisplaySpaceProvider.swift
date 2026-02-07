import Cocoa

// MARK: - Display Space Provider Protocol

/// Protocol for abstracting CGS display space functions for testability
protocol DisplaySpaceProvider {
    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]?
    func copyActiveMenuBarDisplayIdentifier() -> String?
    func spacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int>
}

// MARK: - CGSDisplaySpaceProvider

/// Default implementation using the actual CGS/SLS functions
struct CGSDisplaySpaceProvider: DisplaySpaceProvider {
    private let conn: Int32

    init() {
        conn = _CGSDefaultConnection()
    }

    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]? {
        CGSCopyManagedDisplaySpaces(conn) as? [NSDictionary]
    }

    func copyActiveMenuBarDisplayIdentifier() -> String? {
        CGSCopyActiveMenuBarDisplayIdentifier(conn) as? String
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

        guard !windowIDs.isEmpty else {
            return []
        }

        // Single batch call to get all spaces for all windows
        // Selector 0x7 = all spaces the windows are on
        guard let result = SLSCopySpacesForWindows(conn, 0x7, windowIDs as CFArray) else {
            return []
        }
        let spaces = result.takeRetainedValue() as? [Int] ?? []

        let spaceIDSet = Set(spaceIDs)
        return Set(spaces).intersection(spaceIDSet)
    }
}

// MARK: - FallbackDisplaySpaceProvider

/// Wraps a CGSDisplaySpaceProvider and returns graceful empty results if CGS calls return nil.
struct FallbackDisplaySpaceProvider: DisplaySpaceProvider {
    private let wrapped: DisplaySpaceProvider

    init(wrapping provider: DisplaySpaceProvider = CGSDisplaySpaceProvider()) {
        wrapped = provider
    }

    // swiftlint:disable:next discouraged_optional_collection
    func copyManagedDisplaySpaces() -> [NSDictionary]? {
        wrapped.copyManagedDisplaySpaces() ?? []
    }

    func copyActiveMenuBarDisplayIdentifier() -> String? {
        wrapped.copyActiveMenuBarDisplayIdentifier() ?? ""
    }

    func spacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int> {
        wrapped.spacesWithWindows(forSpaceIDs: spaceIDs)
    }
}
