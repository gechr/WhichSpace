import Cocoa

/// Renders status bar icons for the current space state.
///
/// Extracted from AppState to separate icon rendering concerns from space detection.
/// Takes an unowned reference to AppState for reading space data and a DefaultsStore for preferences.
@MainActor
final class StatusBarRenderer {
    private struct CrossDisplaySpace {
        let displayID: String
        let localIndex: Int
        let globalIndex: Int
        let label: String
        let spaceID: Int
        let isActive: Bool
    }

    /// Captures all state that affects icon rendering so we can detect changes and serve a cached image.
    private struct IconCacheKey: Equatable {
        let allDisplaysSpaceInfo: [DisplaySpaceInfo]
        let allSpaceEntries: [SpaceEntry]
        let currentDisplayID: String?
        let currentSpace: Int
        let currentSpaceID: Int
        let dimInactiveSpaces: Bool
        let displaySpaceColors: [String: [Int: SpaceColors]]
        let displaySpaceFonts: [String: [Int: SpaceFont]]
        let displaySpaceIconStyles: [String: [Int: IconStyle]]
        let displaySpaceSkinTones: [String: [Int: SkinTone]]
        let displaySpaceSymbols: [String: [Int: String]]
        let hideEmptySpaces: Bool
        let hideFullscreenApps: Bool
        let isDarkMode: Bool
        let localSpaceNumbers: Bool
        let separatorColorData: Data?
        let showAllDisplays: Bool
        let showAllSpaces: Bool
        let sizeScale: Double
        let spaceColors: [Int: SpaceColors]
        let spaceFonts: [Int: SpaceFont]
        let spaceIconStyles: [Int: IconStyle]
        let spaceSkinTones: [Int: SkinTone]
        let spaceSymbols: [Int: String]
        let spacesWithWindows: Set<Int>
        let uniqueIconsPerDisplay: Bool
    }

    private unowned let appState: AppState
    private let displaySpaceProvider: DisplaySpaceProvider
    private let store: DefaultsStore

    private static let spacesWithWindowsCacheTTL: TimeInterval = 0.2

    private var backgroundScanTask: Task<Void, Never>?
    private var cachedSpacesWithWindows: Set<Int> = []
    private var cachedSpacesWithWindowsPopulated = false
    private var cachedSpacesWithWindowsSpaceIDs: [Int] = []
    private var cachedSpacesWithWindowsTime: Date = .distantPast

    // MARK: - Icon Cache

    private var cachedIcon: NSImage?
    private var cachedIconKey: IconCacheKey?

    // MARK: - Preview Overrides

    /// Temporary overrides for previewing style changes (only applied to current space)
    private var previewBackground: NSColor?
    private var previewClearSymbol = false
    private var previewForeground: NSColor?
    private var previewSeparatorColor: NSColor?
    private var previewSkinTone: SkinTone?
    private var previewStyle: IconStyle?
    private var previewSymbol: String?

    init(appState: AppState, displaySpaceProvider: DisplaySpaceProvider, store: DefaultsStore) {
        self.appState = appState
        self.displaySpaceProvider = displaySpaceProvider
        self.store = store
    }

    // MARK: - Public API

    var showAllSpaces: Bool {
        store.showAllSpaces
    }

    var showAllDisplays: Bool {
        store.showAllDisplays
    }

    var statusBarIcon: NSImage {
        let key = buildIconCacheKey()

        if let cachedIcon, cachedIconKey == key {
            return cachedIcon
        }

        let icon = generateStatusBarIcon(isDark: key.isDarkMode)
        cachedIcon = icon
        cachedIconKey = key
        return icon
    }

    /// Sets preview overrides and returns the full status bar icon with previewed changes
    func generatePreviewIcon(
        overrideStyle: IconStyle? = nil,
        overrideSymbol: String? = nil,
        overrideForeground: NSColor? = nil,
        overrideBackground: NSColor? = nil,
        overrideSeparatorColor: NSColor? = nil,
        clearSymbol: Bool = false,
        skinTone: SkinTone? = nil
    ) -> NSImage {
        // Store overrides temporarily
        previewStyle = overrideStyle
        previewSymbol = overrideSymbol
        previewForeground = overrideForeground
        previewBackground = overrideBackground
        previewSeparatorColor = overrideSeparatorColor
        previewClearSymbol = clearSymbol
        previewSkinTone = skinTone

        defer {
            previewStyle = nil
            previewSymbol = nil
            previewForeground = nil
            previewBackground = nil
            previewSeparatorColor = nil
            previewClearSymbol = false
            previewSkinTone = nil
        }

        return generateStatusBarIcon(isDark: appState.darkModeEnabled)
    }

    /// Returns the layout of visible icons in the status bar for the current mode
    func statusBarLayout() -> StatusBarLayout {
        if showAllDisplays {
            let spacesPerDisplay = spacesToShowAcrossDisplays()
            guard !spacesPerDisplay.isEmpty else {
                return .empty
            }

            var slots: [StatusBarIconSlot] = []
            var xOffset: Double = 0
            var shortcutNum = 0

            for (displayIndex, displaySpaces) in spacesPerDisplay.enumerated() {
                if displayIndex > 0 {
                    xOffset += Layout.displaySeparatorWidth
                }

                for space in displaySpaces {
                    let isFullscreen = space.label == Labels.fullscreen
                    if !isFullscreen {
                        shortcutNum += 1
                    }
                    let target = isFullscreen ? nil : shortcutNum
                    let displayLabel = isFullscreen ? space.label :
                        (store.localSpaceNumbers ? space.label : String(space.globalIndex))
                    slots.append(StatusBarIconSlot(
                        startX: xOffset,
                        width: Layout.statusItemWidth,
                        label: displayLabel,
                        targetSpace: target,
                        spaceID: space.spaceID
                    ))
                    xOffset += Layout.statusItemWidth
                }
            }

            return StatusBarLayout(slots: slots)
        }

        if showAllSpaces {
            let spacesToShow = spacesToShowForCurrentDisplay()
            guard !spacesToShow.isEmpty else {
                return .empty
            }

            // Get global start index for current display
            let globalStartIndex = appState.allDisplaysSpaceInfo
                .first { $0.displayID == appState.currentDisplayID }?.globalStartIndex ?? 1

            // Count only non-fullscreen spaces to get keyboard shortcut numbers
            var shortcutNum = 0
            var slots: [StatusBarIconSlot] = []

            for (drawIndex, spaceInfo) in spacesToShow.enumerated() {
                let isFullscreen = spaceInfo.label == Labels.fullscreen
                if !isFullscreen {
                    shortcutNum += 1
                }
                let target = isFullscreen ? nil : shortcutNum
                let entry = appState.allSpaceEntries[spaceInfo.index]
                let localRegularIndex = entry.regularIndex ?? 0
                let globalIndex = globalStartIndex + max(localRegularIndex - 1, 0)
                let displayLabel = isFullscreen ? spaceInfo.label :
                    (store.localSpaceNumbers ? spaceInfo.label : String(globalIndex))
                let spaceID = entry.id
                slots.append(StatusBarIconSlot(
                    startX: Double(drawIndex) * Layout.statusItemWidth,
                    width: Layout.statusItemWidth,
                    label: displayLabel,
                    targetSpace: target,
                    spaceID: spaceID
                ))
            }
            return StatusBarLayout(slots: slots)
        }

        return .empty
    }

    /// Invalidates both the spacesWithWindows cache and the icon cache (call on space change)
    func invalidateSpacesWithWindowsCache() {
        backgroundScanTask?.cancel()
        backgroundScanTask = nil
        cachedSpacesWithWindowsTime = .distantPast
        cachedSpacesWithWindowsSpaceIDs = []
        cachedSpacesWithWindowsPopulated = false
        cachedSpacesWithWindows = []
        invalidateIconCache()
    }

    /// Invalidates only the icon cache (call when preferences change)
    func invalidateIconCache() {
        cachedIcon = nil
        cachedIconKey = nil
    }

    // MARK: - Icon Cache Helpers

    private func buildIconCacheKey() -> IconCacheKey {
        let isDark = appState.darkModeEnabled

        return IconCacheKey(
            allDisplaysSpaceInfo: appState.allDisplaysSpaceInfo,
            allSpaceEntries: appState.allSpaceEntries,
            currentDisplayID: appState.currentDisplayID,
            currentSpace: appState.currentSpace,
            currentSpaceID: appState.currentSpaceID,
            dimInactiveSpaces: store.dimInactiveSpaces,
            displaySpaceColors: store.displaySpaceColors,
            displaySpaceFonts: store.displaySpaceFonts,
            displaySpaceIconStyles: store.displaySpaceIconStyles,
            displaySpaceSkinTones: store.displaySpaceSkinTones,
            displaySpaceSymbols: store.displaySpaceSymbols,
            hideEmptySpaces: store.hideEmptySpaces,
            hideFullscreenApps: store.hideFullscreenApps,
            isDarkMode: isDark,
            localSpaceNumbers: store.localSpaceNumbers,
            separatorColorData: store.separatorColorData,
            showAllDisplays: store.showAllDisplays,
            showAllSpaces: store.showAllSpaces,
            sizeScale: store.sizeScale,
            spaceColors: store.spaceColors,
            spaceFonts: store.spaceFonts,
            spaceIconStyles: store.spaceIconStyles,
            spaceSkinTones: store.spaceSkinTones,
            spaceSymbols: store.spaceSymbols,
            spacesWithWindows: cachedSpacesWithWindows,
            uniqueIconsPerDisplay: store.uniqueIconsPerDisplay
        )
    }

    private func generateStatusBarIcon(isDark: Bool) -> NSImage {
        // Show all displays mode takes precedence (shows spaces from all displays with separators)
        if showAllDisplays, !appState.allDisplaysSpaceInfo.isEmpty {
            return generateCrossDisplayIcon(darkMode: isDark)
        }

        // Show all spaces mode (shows all spaces from current display only)
        if showAllSpaces, !appState.allSpaceEntries.isEmpty {
            return generateCombinedIcon(darkMode: isDark)
        }

        return generateSingleIcon(for: appState.currentSpace, label: appState.currentSpaceLabel, darkMode: isDark)
    }

    // MARK: - Icon Generation

    private func generateSingleIcon(for space: Int, label: String, darkMode: Bool) -> NSImage {
        let isCurrentSpace = space == appState.currentSpace
        return generateIcon(
            forSpace: space,
            label: label,
            displayID: appState.currentDisplayID,
            applyPreview: isCurrentSpace,
            darkMode: darkMode
        )
    }

    private func generateCombinedIcon(darkMode: Bool) -> NSImage {
        let spacesToShow = spacesToShowForCurrentDisplay()

        // If no spaces to show, show just the current space
        guard !spacesToShow.isEmpty else {
            return generateSingleIcon(
                for: appState.currentSpace, label: appState.currentSpaceLabel, darkMode: darkMode
            )
        }

        // Get global start index for current display
        let globalStartIndex = appState.allDisplaysSpaceInfo
            .first { $0.displayID == appState.currentDisplayID }?.globalStartIndex ?? 1

        let totalWidth = Double(spacesToShow.count) * Layout.statusItemWidth
        let combinedImage = NSImage(size: NSSize(width: totalWidth, height: Layout.statusItemHeight))

        combinedImage.lockFocus()

        for (drawIndex, spaceInfo) in spacesToShow.enumerated() {
            let spaceIndex = spaceInfo.index + 1
            let isActive = spaceIndex == appState.currentSpace
            let isFullscreen = spaceInfo.label == Labels.fullscreen
            let entry = appState.allSpaceEntries[spaceInfo.index]
            let localRegularIndex = entry.regularIndex ?? 0
            let globalIndex = globalStartIndex + max(localRegularIndex - 1, 0)
            let displayLabel = isFullscreen ? spaceInfo.label :
                (store.localSpaceNumbers ? spaceInfo.label : String(globalIndex))
            let icon = generateSingleIcon(for: spaceIndex, label: displayLabel, darkMode: darkMode)

            let xOffset = Double(drawIndex) * Layout.statusItemWidth
            let drawRect = NSRect(
                x: xOffset,
                y: 0,
                width: Layout.statusItemWidth,
                height: Layout.statusItemHeight
            )

            // Draw with reduced opacity for inactive spaces (if dimming is enabled)
            let alpha = isActive || !store.dimInactiveSpaces ? 1.0 : 0.35
            icon.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: alpha)
        }

        combinedImage.unlockFocus()
        return combinedImage
    }

    // Generates an icon showing all spaces across all displays with separators between displays
    // swiftlint:disable:next function_body_length
    private func generateCrossDisplayIcon(darkMode: Bool) -> NSImage {
        let spacesPerDisplay = spacesToShowAcrossDisplays()

        // If no spaces to show at all, return single icon
        guard !spacesPerDisplay.isEmpty else {
            return generateSingleIcon(
                for: appState.currentSpace, label: appState.currentSpaceLabel, darkMode: darkMode
            )
        }

        // Calculate total width: spaces + separators between displays
        let totalSpaces = spacesPerDisplay.reduce(0) { $0 + $1.count }
        let separatorCount = max(0, spacesPerDisplay.count - 1)
        let totalWidth = Double(totalSpaces) * Layout.statusItemWidth +
            Double(separatorCount) * Layout.displaySeparatorWidth

        let combinedImage = NSImage(size: NSSize(width: totalWidth, height: Layout.statusItemHeight))

        combinedImage.lockFocus()

        var xOffset: Double = 0

        for (displayIndex, displaySpaces) in spacesPerDisplay.enumerated() {
            // Draw separator before this display (except for the first)
            if displayIndex > 0 {
                drawDisplaySeparator(at: xOffset, darkMode: darkMode)
                xOffset += Layout.displaySeparatorWidth
            }

            // Draw each space for this display
            for space in displaySpaces {
                let displayLabel: String
                if space.label == Labels.fullscreen {
                    displayLabel = Labels.fullscreen
                } else if !store.localSpaceNumbers {
                    displayLabel = String(space.globalIndex)
                } else {
                    displayLabel = space.label
                }
                let icon = generateSingleIconForCrossDisplay(
                    label: displayLabel,
                    displayID: space.displayID,
                    localIndex: space.localIndex,
                    darkMode: darkMode
                )

                let drawRect = NSRect(
                    x: xOffset,
                    y: 0,
                    width: Layout.statusItemWidth,
                    height: Layout.statusItemHeight
                )

                // Draw with reduced opacity for inactive spaces (if dimming is enabled)
                let alpha = space.isActive || !store.dimInactiveSpaces ? 1.0 : 0.35
                icon.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: alpha)

                xOffset += Layout.statusItemWidth
            }
        }

        combinedImage.unlockFocus()
        return combinedImage
    }

    /// Generates a single icon for cross-display mode, looking up preferences by display and local index
    private func generateSingleIconForCrossDisplay(
        label: String,
        displayID: String,
        localIndex: Int,
        darkMode: Bool
    ) -> NSImage {
        // When uniqueIconsPerDisplay is OFF, preview should apply to all spaces with same local index
        // (since they share settings). When ON, only apply to the exact current space.
        let shouldApplyPreview = localIndex == appState.currentSpace
            && (displayID == appState.currentDisplayID || !store.uniqueIconsPerDisplay)

        return generateIcon(
            forSpace: localIndex,
            label: label,
            displayID: displayID,
            applyPreview: shouldApplyPreview,
            darkMode: darkMode
        )
    }

    /// Shared icon generation: resolves preferences, applies preview overrides, dispatches to SpaceIconGenerator
    private func generateIcon(
        forSpace space: Int,
        label: String,
        displayID: String?,
        applyPreview: Bool,
        darkMode: Bool
    ) -> NSImage {
        var colors = SpacePreferences.colors(forSpace: space, display: displayID, store: store)
        var style = SpacePreferences.iconStyle(forSpace: space, display: displayID, store: store) ?? .square
        let font = SpacePreferences.font(forSpace: space, display: displayID, store: store)?.font

        // Apply preview overrides
        if applyPreview {
            if let previewStyle {
                style = previewStyle
            }
            let defaults = IconColors.filledColors(darkMode: darkMode)
            if let fg = previewForeground {
                let bg = colors?.background ?? defaults.background
                colors = SpaceColors(foreground: fg, background: bg)
            }
            if let bg = previewBackground {
                let fg = colors?.foreground ?? defaults.foreground
                colors = SpaceColors(foreground: fg, background: bg)
            }
        }

        // Fullscreen spaces just show "F" with the same colors
        if label == Labels.fullscreen {
            return SpaceIconGenerator.generateIcon(
                for: Labels.fullscreen,
                darkMode: darkMode,
                customColors: colors,
                customFont: font,
                style: style,
                sizeScale: store.sizeScale
            )
        }

        // Check for preview symbol override first
        if applyPreview, let previewSymbol {
            let skinTone = previewSkinTone
                ?? SpacePreferences.skinTone(forSpace: space, display: displayID, store: store)
                ?? .default
            return SpaceIconGenerator.generateSymbolIcon(
                symbolName: previewSymbol,
                darkMode: darkMode,
                customColors: colors,
                skinTone: skinTone,
                sizeScale: store.sizeScale
            )
        }

        // Skip saved symbol if previewing a number style (previewClearSymbol)
        let symbol = (applyPreview && previewClearSymbol)
            ? nil
            : SpacePreferences.symbol(forSpace: space, display: displayID, store: store)

        if let symbol {
            let skinTone = SpacePreferences
                .skinTone(forSpace: space, display: displayID, store: store) ?? .default
            return SpaceIconGenerator.generateSymbolIcon(
                symbolName: symbol,
                darkMode: darkMode,
                customColors: colors,
                skinTone: skinTone,
                sizeScale: store.sizeScale
            )
        }
        return SpaceIconGenerator.generateIcon(
            for: label,
            darkMode: darkMode,
            customColors: colors,
            customFont: font,
            style: style,
            sizeScale: store.sizeScale
        )
    }

    /// Draws a vertical separator line between displays
    private func drawDisplaySeparator(at xOffset: Double, darkMode: Bool) {
        let separatorColor = previewSeparatorColor ?? store.separatorColor ?? (darkMode
            ? NSColor(calibratedWhite: 0.5, alpha: 0.6)
            : NSColor(calibratedWhite: 0.4, alpha: 0.6))
        separatorColor.setStroke()

        let centerX = xOffset + Layout.displaySeparatorWidth / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centerX, y: 3))
        path.line(to: NSPoint(x: centerX, y: Layout.statusItemHeight - 3))
        path.lineWidth = 1.0
        path.stroke()
    }

    // MARK: - Filtering Helpers

    /// Returns cached spaces with windows, scheduling a background refresh when the cache is stale.
    ///
    /// On the very first call (cache never populated) a synchronous scan is performed to avoid
    /// showing incorrect state. Subsequent stale reads return old data immediately so the main
    /// thread never blocks on `CGWindowListCopyWindowInfo`. When the background scan completes
    /// the icon cache is invalidated, causing the next `statusBarIcon` access to re-render.
    private func getCachedSpacesWithWindows(forSpaceIDs spaceIDs: [Int]) -> Set<Int> {
        let now = Date()
        let cacheValid = cachedSpacesWithWindowsSpaceIDs == spaceIDs &&
            now.timeIntervalSince(cachedSpacesWithWindowsTime) < Self.spacesWithWindowsCacheTTL

        if !cacheValid {
            if cachedSpacesWithWindowsPopulated {
                // Stale data exists - return it immediately and refresh in background
                scheduleBackgroundWindowScan(forSpaceIDs: spaceIDs)
            } else {
                // First call: populate synchronously so we have valid data to return
                cachedSpacesWithWindows = displaySpaceProvider.spacesWithWindows(forSpaceIDs: spaceIDs)
                cachedSpacesWithWindowsTime = now
                cachedSpacesWithWindowsSpaceIDs = spaceIDs
                cachedSpacesWithWindowsPopulated = true
            }
        }
        return cachedSpacesWithWindows
    }

    /// Runs `spacesWithWindows` on a background thread and updates the cache on completion.
    private func scheduleBackgroundWindowScan(forSpaceIDs spaceIDs: [Int]) {
        backgroundScanTask?.cancel()
        let provider = displaySpaceProvider
        backgroundScanTask = Task {
            let result = await Task.detached {
                provider.spacesWithWindows(forSpaceIDs: spaceIDs)
            }.value

            guard !Task.isCancelled
            else { return }

            cachedSpacesWithWindows = result
            cachedSpacesWithWindowsTime = Date()
            cachedSpacesWithWindowsSpaceIDs = spaceIDs
            cachedSpacesWithWindowsPopulated = true
            invalidateIconCache()
        }
    }

    /// Determines if a space should be shown based on filtering settings
    private func shouldShowSpace(label: String, spaceID: Int, nonEmptySpaceIDs: Set<Int>) -> Bool {
        // Hide full-screen applications if enabled
        if store.hideFullscreenApps, label == Labels.fullscreen {
            return false
        }
        // Hide empty spaces if enabled
        if store.hideEmptySpaces, !nonEmptySpaceIDs.contains(spaceID) {
            return false
        }
        return true
    }

    private func spacesToShowForCurrentDisplay() -> [(index: Int, label: String)] {
        let needsFiltering = store.hideEmptySpaces || store.hideFullscreenApps
        if needsFiltering {
            let nonEmptySpaceIDs: Set<Int>
            if store.hideEmptySpaces {
                nonEmptySpaceIDs = getCachedSpacesWithWindows(forSpaceIDs: appState.allSpaceIDs)
            } else {
                nonEmptySpaceIDs = []
            }

            let filtered = appState.allSpaceEntries.enumerated().filter { index, entry in
                let spaceIndex = index + 1
                let isActive = spaceIndex == appState.currentSpace

                // Always show active space
                if isActive {
                    return true
                }

                return shouldShowSpace(label: entry.label, spaceID: entry.id, nonEmptySpaceIDs: nonEmptySpaceIDs)
            }
            return filtered.map { (index: $0.offset, label: $0.element.label) }
        }

        return appState.allSpaceEntries.enumerated().map { (index: $0.offset, label: $0.element.label) }
    }

    private func spacesToShowAcrossDisplays() -> [[CrossDisplaySpace]] {
        // Collect all space IDs for window detection
        let allSpaceIDsAcrossDisplays = appState.allDisplaysSpaceInfo.flatMap { $0.entries.map(\.id) }
        let nonEmptySpaceIDs: Set<Int>
        if store.hideEmptySpaces {
            nonEmptySpaceIDs = getCachedSpacesWithWindows(forSpaceIDs: allSpaceIDsAcrossDisplays)
        } else {
            nonEmptySpaceIDs = []
        }

        var spacesPerDisplay: [[CrossDisplaySpace]] = []

        for displayInfo in appState.allDisplaysSpaceInfo {
            var displaySpaces: [CrossDisplaySpace] = []

            for (arrayIndex, entry) in displayInfo.entries.enumerated() {
                let localIndex = arrayIndex + 1
                let localRegularIndex = entry.regularIndex ?? 0
                let globalIndex = displayInfo.globalStartIndex + max(localRegularIndex - 1, 0)
                let isActive = entry.id == appState.currentSpaceID

                // Always show active space
                guard isActive || shouldShowSpace(
                    label: entry.label, spaceID: entry.id, nonEmptySpaceIDs: nonEmptySpaceIDs
                )
                else {
                    continue
                }

                displaySpaces.append(CrossDisplaySpace(
                    displayID: displayInfo.displayID,
                    localIndex: localIndex,
                    globalIndex: globalIndex,
                    label: entry.label,
                    spaceID: entry.id,
                    isActive: isActive
                ))
            }

            if !displaySpaces.isEmpty {
                spacesPerDisplay.append(displaySpaces)
            }
        }

        return spacesPerDisplay
    }
}
