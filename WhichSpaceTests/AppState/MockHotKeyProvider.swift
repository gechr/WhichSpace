import Foundation
@testable import WhichSpace

/// Mock implementation of `HotKeyProvider` for testing space switching logic.
final class MockHotKeyProvider: HotKeyProvider, @unchecked Sendable {
    /// Pre-configured hot key values keyed by symbolic hot key.
    var hotKeyValues: [CGSSymbolicHotKey: (keyChar: UniChar, keyCode: CGKeyCode, flags: UInt64)] = [:]

    /// Set of hot keys that are currently enabled.
    var enabledHotKeys: Set<CGSSymbolicHotKey> = []

    /// Records of `setHotKeyEnabled` calls for verification.
    private(set) var setEnabledCalls: [(hotKey: CGSSymbolicHotKey, enabled: Bool)] = []

    func getHotKeyValue(for hotKey: CGSSymbolicHotKey) -> (keyChar: UniChar, keyCode: CGKeyCode, flags: UInt64)? {
        hotKeyValues[hotKey]
    }

    func isHotKeyEnabled(_ hotKey: CGSSymbolicHotKey) -> Bool {
        enabledHotKeys.contains(hotKey)
    }

    func setHotKeyEnabled(_ hotKey: CGSSymbolicHotKey, enabled: Bool) {
        setEnabledCalls.append((hotKey: hotKey, enabled: enabled))
        if enabled {
            enabledHotKeys.insert(hotKey)
        } else {
            enabledHotKeys.remove(hotKey)
        }
    }
}
