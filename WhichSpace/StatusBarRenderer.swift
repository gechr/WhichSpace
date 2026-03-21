import Cocoa

/// Renders status bar icons for the current space state.
///
/// Extracted from AppState to separate icon rendering concerns from space detection.
/// Takes an unowned reference to AppState for reading space data and a DefaultsStore for preferences.
@MainActor
final class StatusBarRenderer {
    /// A fully resolved space slot used by both layout hit-testing and icon rendering.
    private struct ResolvedSlot {
        let displayID: String
        let localIndex: Int
        let globalIndex: Int
        let displayLabel: String
        let spaceID: Int
        let isActive: Bool
        let isFullscreen: Bool
    }

    /// Couples a resolved slot with the rendered icon so layout and drawing stay in sync.
    private struct RenderedSlotIcon {
        let slot: ResolvedSlot
        let icon: NSImage
    }

    /// Captures all state that affects icon rendering so we can detect changes and serve a cached image.
    private struct IconCacheKey: Equatable {
        let allDisplaysSpaceInfo: [DisplaySpaceInfo]
        let allSpaceEntries: [SpaceEntry]
        let currentDisplayID: String?
        let currentSpace: Int
        let currentSpaceID: Int
        let dimInactiveSpaces: Bool
        let displaySpaceBadges: [String: [Int: SpaceBadge]]
        let displaySpaceColors: [String: [Int: SpaceColors]]
        let displaySpaceFonts: [String: [Int: SpaceFont]]
        let displaySpaceIconStyles: [String: [Int: IconStyle]]
        let displaySpaceLabels: [String: [Int: String]]
        let displaySpaceLabelStyles: [String: [Int: IconStyle]]
        let displaySpaceSkinTones: [String: [Int: SkinTone]]
        let displaySpaceSymbols: [String: [Int: String]]
        let hideEmptySpaces: Bool
        let hideFullscreenApps: Bool
        let isDarkMode: Bool
        let localSpaceNumbers: Bool
        let paddingScale: Double
        let separatorColorData: Data?
        let showAllDisplays: Bool
        let showAllSpaces: Bool
        let sizeScale: Double
        let spaceBadges: [Int: SpaceBadge]
        let spaceColors: [Int: SpaceColors]
        let spaceFonts: [Int: SpaceFont]
        let spaceIconStyles: [Int: IconStyle]
        let spaceLabels: [Int: String]
        let spaceLabelStyles: [Int: IconStyle]
        let spaceSkinTones: [Int: SkinTone]
        let spaceSymbols: [Int: String]
        let spacesWithWindows: Set<Int>
        let uniqueIconsPerDisplay: Bool
    }

    private unowned let appState: AppState
    private let displaySpaceProvider: DisplaySpaceProvider
    private let store: DefaultsStore

    /// Callback invoked when a background window scan completes and the icon should be refreshed.
    var onIconNeedsUpdate: (() -> Void)?

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
    private struct PreviewState {
        var badge: SpaceBadge?
        var background: NSColor?
        var clearSymbol = false
        var foreground: NSColor?
        var labelStyle: IconStyle?
        var separatorColor: NSColor?
        var skinTone: SkinTone?
        var style: IconStyle?
        var symbol: String?
    }

    private var preview: PreviewState?

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
        overrideLabelStyle: IconStyle? = nil,
        overrideSymbol: String? = nil,
        overrideForeground: NSColor? = nil,
        overrideBackground: NSColor? = nil,
        overrideSeparatorColor: NSColor? = nil,
        clearSymbol: Bool = false,
        skinTone: SkinTone? = nil,
        overrideBadgePosition: BadgePosition? = nil
    ) -> NSImage {
        var badgeOverride: SpaceBadge?
        if let position = overrideBadgePosition {
            let current = SpacePreferences.badge(
                forSpace: appState.currentSpace,
                display: appState.currentDisplayID,
                store: store
            )
            let character = current?.character ?? ""
            if !character.isEmpty {
                badgeOverride = SpaceBadge(character: character, position: position)
            }
        }

        preview = PreviewState(
            badge: badgeOverride,
            background: overrideBackground,
            clearSymbol: clearSymbol,
            foreground: overrideForeground,
            labelStyle: overrideLabelStyle,
            separatorColor: overrideSeparatorColor,
            skinTone: skinTone,
            style: overrideStyle,
            symbol: overrideSymbol
        )
        defer { preview = nil }

        return generateStatusBarIcon(isDark: appState.darkModeEnabled)
    }

    /// Returns the layout of visible icons in the status bar for the current mode
    func statusBarLayout() -> StatusBarLayout {
        if showAllDisplays {
            let renderedDisplays = renderedCrossDisplayIcons(darkMode: appState.darkModeEnabled)
            guard !renderedDisplays.isEmpty else {
                return .empty
            }

            var iconSlots: [StatusBarIconSlot] = []
            var xOffset: Double = 0

            for (displayIndex, displayIcons) in renderedDisplays.enumerated() {
                if displayIndex > 0 {
                    xOffset += Layout.displaySeparatorWidth
                }
                for rendered in displayIcons {
                    iconSlots.append(StatusBarIconSlot(
                        startX: xOffset,
                        width: rendered.icon.size.width,
                        label: rendered.slot.displayLabel,
                        targetSpace: rendered.slot.isFullscreen ? nil : rendered.slot.globalIndex,
                        spaceID: rendered.slot.spaceID
                    ))
                    xOffset += rendered.icon.size.width
                }
            }

            return StatusBarLayout(slots: iconSlots)
        }

        if showAllSpaces {
            let renderedIcons = renderedCurrentDisplayIcons(darkMode: appState.darkModeEnabled)
            guard !renderedIcons.isEmpty else {
                return .empty
            }

            var xOffset: Double = 0
            let iconSlots = renderedIcons.map { rendered in
                let iconSlot = StatusBarIconSlot(
                    startX: xOffset,
                    width: rendered.icon.size.width,
                    label: rendered.slot.displayLabel,
                    targetSpace: rendered.slot.isFullscreen ? nil : rendered.slot.globalIndex,
                    spaceID: rendered.slot.spaceID
                )
                xOffset += rendered.icon.size.width
                return iconSlot
            }
            return StatusBarLayout(slots: iconSlots)
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
            displaySpaceBadges: store.displaySpaceBadges,
            displaySpaceColors: store.displaySpaceColors,
            displaySpaceFonts: store.displaySpaceFonts,
            displaySpaceIconStyles: store.displaySpaceIconStyles,
            displaySpaceLabels: store.displaySpaceLabels,
            displaySpaceLabelStyles: store.displaySpaceLabelStyles,
            displaySpaceSkinTones: store.displaySpaceSkinTones,
            displaySpaceSymbols: store.displaySpaceSymbols,
            hideEmptySpaces: store.hideEmptySpaces,
            hideFullscreenApps: store.hideFullscreenApps,
            isDarkMode: isDark,
            localSpaceNumbers: store.localSpaceNumbers,
            paddingScale: store.paddingScale,
            separatorColorData: store.separatorColorData,
            showAllDisplays: store.showAllDisplays,
            showAllSpaces: store.showAllSpaces,
            sizeScale: store.sizeScale,
            spaceBadges: store.spaceBadges,
            spaceColors: store.spaceColors,
            spaceFonts: store.spaceFonts,
            spaceIconStyles: store.spaceIconStyles,
            spaceLabels: store.spaceLabels,
            spaceLabelStyles: store.spaceLabelStyles,
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

        let labels = fetchLabels(displayID: appState.currentDisplayID ?? "")
        let defaultLabel = appState.currentSpaceLabel
        let rawLabel = labels[appState.currentSpace].flatMap { $0.isEmpty ? nil : $0 }
        let label = rawLabel.map { LabelTemplate.resolve($0, space: appState.currentSpace) } ?? defaultLabel
        return generateSingleIcon(for: appState.currentSpace, label: label, labels: labels, darkMode: isDark)
    }

    // MARK: - Icon Generation

    private func generateSingleIcon(
        for space: Int, label: String, labels: [Int: String], darkMode: Bool
    ) -> NSImage {
        let isCurrentSpace = space == appState.currentSpace
        return generateIcon(
            forSpace: space,
            label: label,
            labels: labels,
            displayID: appState.currentDisplayID,
            applyPreview: isCurrentSpace,
            darkMode: darkMode
        )
    }

    private func renderedCurrentDisplayIcons(darkMode: Bool) -> [RenderedSlotIcon] {
        let labels = fetchLabels(displayID: appState.currentDisplayID ?? "")
        return resolveCurrentDisplaySlots().map { slot in
            RenderedSlotIcon(
                slot: slot,
                icon: generateSingleIcon(
                    for: slot.localIndex, label: slot.displayLabel, labels: labels, darkMode: darkMode
                )
            )
        }
    }

    private func renderedCrossDisplayIcons(darkMode: Bool) -> [[RenderedSlotIcon]] {
        resolveCrossDisplaySlots().map { displaySlots in
            let labels = displaySlots.first.map { fetchLabels(displayID: $0.displayID) } ?? [:]
            return displaySlots.map { slot in
                RenderedSlotIcon(
                    slot: slot,
                    icon: generateSingleIconForCrossDisplay(
                        label: slot.displayLabel,
                        labels: labels,
                        displayID: slot.displayID,
                        localIndex: slot.localIndex,
                        darkMode: darkMode
                    )
                )
            }
        }
    }

    private func generateCombinedIcon(darkMode: Bool) -> NSImage {
        let renderedIcons = renderedCurrentDisplayIcons(darkMode: darkMode)

        // If no spaces to show, show just the current space
        guard !renderedIcons.isEmpty else {
            let labels = fetchLabels(displayID: appState.currentDisplayID ?? "")
            let rawLabel = labels[appState.currentSpace].flatMap { $0.isEmpty ? nil : $0 }
            let label = rawLabel.map { LabelTemplate.resolve($0, space: appState.currentSpace) }
                ?? appState.currentSpaceLabel
            return generateSingleIcon(
                for: appState.currentSpace, label: label, labels: labels, darkMode: darkMode
            )
        }

        let totalWidth = renderedIcons.reduce(0) { $0 + $1.icon.size.width }
        let imageSize = NSSize(width: totalWidth, height: Layout.statusItemHeight)
        return Self.drawImmediate(size: imageSize) {
            var xOffset: Double = 0
            for rendered in renderedIcons {
                let drawRect = NSRect(
                    x: xOffset,
                    y: 0,
                    width: rendered.icon.size.width,
                    height: Layout.statusItemHeight
                )

                let alpha = rendered.slot.isActive || !store.dimInactiveSpaces ? 1.0 : 0.35
                rendered.icon.draw(
                    in: drawRect,
                    from: NSRect(origin: .zero, size: rendered.icon.size),
                    operation: .sourceOver,
                    fraction: alpha
                )
                xOffset += rendered.icon.size.width
            }
        }
    }

    private func generateCrossDisplayIcon(darkMode: Bool) -> NSImage {
        let renderedDisplays = renderedCrossDisplayIcons(darkMode: darkMode)

        // If no spaces to show at all, return single icon
        guard !renderedDisplays.isEmpty else {
            let labels = fetchLabels(displayID: appState.currentDisplayID ?? "")
            let rawLabel = labels[appState.currentSpace].flatMap { $0.isEmpty ? nil : $0 }
            let label = rawLabel.map { LabelTemplate.resolve($0, space: appState.currentSpace) }
                ?? appState.currentSpaceLabel
            return generateSingleIcon(
                for: appState.currentSpace, label: label, labels: labels, darkMode: darkMode
            )
        }

        // Calculate total width: spaces + separators between displays
        let totalSpacesWidth = renderedDisplays
            .flatMap(\.self)
            .reduce(0) { $0 + $1.icon.size.width }
        let separatorCount = max(0, renderedDisplays.count - 1)
        let totalWidth = totalSpacesWidth + Double(separatorCount) * Layout.displaySeparatorWidth

        let imageSize = NSSize(width: totalWidth, height: Layout.statusItemHeight)
        return Self.drawImmediate(size: imageSize) {
            var xOffset: Double = 0

            for (displayIndex, displayIcons) in renderedDisplays.enumerated() {
                if displayIndex > 0 {
                    drawDisplaySeparator(at: xOffset, darkMode: darkMode)
                    xOffset += Layout.displaySeparatorWidth
                }

                for rendered in displayIcons {
                    let drawRect = NSRect(
                        x: xOffset,
                        y: 0,
                        width: rendered.icon.size.width,
                        height: Layout.statusItemHeight
                    )

                    let alpha = rendered.slot.isActive || !store.dimInactiveSpaces ? 1.0 : 0.35
                    rendered.icon.draw(
                        in: drawRect,
                        from: NSRect(origin: .zero, size: rendered.icon.size),
                        operation: .sourceOver,
                        fraction: alpha
                    )

                    xOffset += rendered.icon.size.width
                }
            }
        }
    }

    /// Generates a single icon for cross-display mode, looking up preferences by display and local index
    private func generateSingleIconForCrossDisplay(
        label: String,
        labels: [Int: String],
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
            labels: labels,
            displayID: displayID,
            applyPreview: shouldApplyPreview,
            darkMode: darkMode
        )
    }

    /// Shared icon generation: resolves preferences, applies preview overrides, dispatches to SpaceIconGenerator
    private func generateIcon(
        forSpace space: Int,
        label: String,
        labels: [Int: String],
        displayID: String?,
        applyPreview: Bool,
        darkMode: Bool
    ) -> NSImage {
        // During style preview, skip all preference reads for speed
        let isStylePreview = applyPreview && preview?.style != nil
        let isLabelStylePreview = applyPreview && preview?.labelStyle != nil
        var colors: SpaceColors?
        var style: IconStyle
        let font: NSFont?
        if isStylePreview {
            colors = SpacePreferences.colors(forSpace: space, display: displayID, store: store)
            style = preview!.style!
            font = SpacePreferences.font(forSpace: space, display: displayID, store: store)?.font
        } else if isLabelStylePreview {
            colors = SpacePreferences.colors(forSpace: space, display: displayID, store: store)
            let resolvedLabel = labels[space].flatMap { $0.isEmpty ? nil : $0 }
                .map { LabelTemplate.resolve($0, space: space) }
            style = Self.renderStyle(for: preview!.labelStyle!, labelLength: resolvedLabel?.count ?? 1)
            let userFont = SpacePreferences.font(forSpace: space, display: displayID, store: store)?.font
            font = (resolvedLabel?.count ?? 0) > 1 && userFont == nil
                ? NSFont.boldSystemFont(ofSize: Layout.baseFontSizeSmall)
                : userFont
        } else {
            colors = SpacePreferences.colors(forSpace: space, display: displayID, store: store)
            let resolvedLabel = labels[space].flatMap { $0.isEmpty ? nil : $0 }
                .map { LabelTemplate.resolve($0, space: space) }
            if let resolvedLabel {
                let labelStyle = SpacePreferences.labelStyle(
                    forSpace: space, display: displayID, store: store
                ) ?? .square
                style = Self.renderStyle(for: labelStyle, labelLength: resolvedLabel.count)
                let userFont = SpacePreferences.font(forSpace: space, display: displayID, store: store)?.font
                font = resolvedLabel.count > 1 && userFont == nil
                    ? NSFont.boldSystemFont(ofSize: Layout.baseFontSizeSmall)
                    : userFont
            } else {
                style = SpacePreferences.iconStyle(forSpace: space, display: displayID, store: store) ?? .square
                font = SpacePreferences.font(forSpace: space, display: displayID, store: store)?.font
            }

            // Apply non-style preview overrides (color)
            if applyPreview, let preview {
                let defaults = IconColors.filledColors(darkMode: darkMode)
                if let fg = preview.foreground {
                    let bg = colors?.background ?? defaults.background
                    colors = SpaceColors(foreground: fg, background: bg)
                }
                if let bg = preview.background {
                    let fg = colors?.foreground ?? defaults.foreground
                    colors = SpaceColors(foreground: fg, background: bg)
                }
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
                sizeScale: store.sizeScale,
                paddingScale: store.paddingScale
            )
        }

        // Check for preview symbol override first
        if applyPreview, let previewSymbol = preview?.symbol {
            let skinTone = preview?.skinTone
                ?? SpacePreferences.skinTone(forSpace: space, display: displayID, store: store)
                ?? .default
            return SpaceIconGenerator.generateSymbolIcon(
                symbolName: previewSymbol,
                darkMode: darkMode,
                customColors: colors,
                skinTone: skinTone,
                sizeScale: store.sizeScale,
                paddingScale: store.paddingScale
            )
        }

        // Skip all pref reads during style preview
        let skipSymbolAndBadge = isStylePreview || isLabelStylePreview
        let symbol: String? = skipSymbolAndBadge
            ? nil
            : ((applyPreview && (preview?.clearSymbol ?? false))
                ? nil
                : SpacePreferences.symbol(forSpace: space, display: displayID, store: store))

        let rawBadge: SpaceBadge? = skipSymbolAndBadge
            ? nil
            : ((applyPreview ? preview?.badge : nil)
                ?? SpacePreferences.badge(forSpace: space, display: displayID, store: store))
        let badge = rawBadge.map { Self.resolveBadge($0, space: space) }

        if let symbol {
            let skinTone = SpacePreferences
                .skinTone(forSpace: space, display: displayID, store: store) ?? .default
            return SpaceIconGenerator.generateSymbolIcon(
                symbolName: symbol,
                darkMode: darkMode,
                customColors: colors,
                skinTone: skinTone,
                sizeScale: store.sizeScale,
                paddingScale: store.paddingScale
            )
        }

        // During number style preview, show space number instead of custom label
        let displayText = isStylePreview ? String(space) : label
        return SpaceIconGenerator.generateIcon(
            for: displayText,
            darkMode: darkMode,
            customColors: colors,
            customFont: font,
            style: style,
            sizeScale: store.sizeScale,
            paddingScale: store.paddingScale,
            badge: badge
        )
    }

    /// Creates an NSImage by drawing immediately into a bitmap context.
    ///
    /// Unlike `NSImage(size:flipped:drawingHandler:)` which defers drawing, this executes
    /// the drawing block synchronously so it captures the current state (including preview overrides).
    private static func drawImmediate(size: CGSize, draw: () -> Void) -> NSImage {
        let image = NSImage(size: size)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        return image
    }

    /// Draws a vertical separator line between displays
    private func drawDisplaySeparator(at xOffset: Double, darkMode: Bool) {
        let separatorColor = preview?.separatorColor ?? store.separatorColor ?? (darkMode
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
            onIconNeedsUpdate?()
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

    /// Resolves visible spaces for the current display into fully computed slots.
    private func resolveCurrentDisplaySlots() -> [ResolvedSlot] {
        let globalStartIndex = appState.allDisplaysSpaceInfo
            .first { $0.displayID == appState.currentDisplayID }?.globalStartIndex ?? 1
        let displayID = appState.currentDisplayID ?? ""

        let nonEmptySpaceIDs: Set<Int> = if store.hideEmptySpaces {
            getCachedSpacesWithWindows(forSpaceIDs: appState.allSpaceIDs)
        } else {
            []
        }

        let labels = fetchLabels(displayID: displayID)
        var slots: [ResolvedSlot] = []

        for (arrayIndex, entry) in appState.allSpaceEntries.enumerated() {
            let localIndex = arrayIndex + 1
            let isActive = localIndex == appState.currentSpace
            let isFullscreen = entry.label == Labels.fullscreen

            if !isActive,
               !shouldShowSpace(label: entry.label, spaceID: entry.id, nonEmptySpaceIDs: nonEmptySpaceIDs)
            {
                continue
            }

            let globalIndex = Self.globalIndex(entry: entry, globalStartIndex: globalStartIndex)
            let displayLabel = displayLabel(
                entry: entry,
                globalIndex: globalIndex,
                localIndex: localIndex,
                labels: labels,
                isFullscreen: isFullscreen
            )

            slots.append(ResolvedSlot(
                displayID: displayID,
                localIndex: localIndex,
                globalIndex: globalIndex,
                displayLabel: displayLabel,
                spaceID: entry.id,
                isActive: isActive,
                isFullscreen: isFullscreen
            ))
        }

        return slots
    }

    /// Resolves visible spaces across all displays into fully computed slots grouped by display.
    private func resolveCrossDisplaySlots() -> [[ResolvedSlot]] {
        let allSpaceIDsAcrossDisplays = appState.allDisplaysSpaceInfo.flatMap { $0.entries.map(\.id) }
        let nonEmptySpaceIDs: Set<Int> = if store.hideEmptySpaces {
            getCachedSpacesWithWindows(forSpaceIDs: allSpaceIDsAcrossDisplays)
        } else {
            []
        }

        var slotsPerDisplay: [[ResolvedSlot]] = []

        for displayInfo in appState.allDisplaysSpaceInfo {
            let labels = fetchLabels(displayID: displayInfo.displayID)
            var displaySlots: [ResolvedSlot] = []

            for (arrayIndex, entry) in displayInfo.entries.enumerated() {
                let localIndex = arrayIndex + 1
                let globalIndex = Self.globalIndex(entry: entry, globalStartIndex: displayInfo.globalStartIndex)
                let isActive = entry.id == appState.currentSpaceID
                let isFullscreen = entry.label == Labels.fullscreen

                guard isActive || shouldShowSpace(
                    label: entry.label, spaceID: entry.id, nonEmptySpaceIDs: nonEmptySpaceIDs
                )
                else {
                    continue
                }

                let displayLabel = displayLabel(
                    entry: entry,
                    globalIndex: globalIndex,
                    localIndex: localIndex,
                    labels: labels,
                    isFullscreen: isFullscreen
                )

                displaySlots.append(ResolvedSlot(
                    displayID: displayInfo.displayID,
                    localIndex: localIndex,
                    globalIndex: globalIndex,
                    displayLabel: displayLabel,
                    spaceID: entry.id,
                    isActive: isActive,
                    isFullscreen: isFullscreen
                ))
            }

            if !displaySlots.isEmpty {
                slotsPerDisplay.append(displaySlots)
            }
        }

        return slotsPerDisplay
    }

    // MARK: - Slot Helpers

    private static func globalIndex(entry: SpaceEntry, globalStartIndex: Int) -> Int {
        let localRegularIndex = entry.regularIndex ?? 0
        return globalStartIndex + max(localRegularIndex - 1, 0)
    }

    /// Fetches all custom labels for a display in a single read.
    private func fetchLabels(displayID: String) -> [Int: String] {
        if store.uniqueIconsPerDisplay {
            return store.displaySpaceLabels[displayID] ?? [:]
        }
        return store.spaceLabels
    }

    /// Resolves the `#` badge token to the current space number.
    private static func resolveBadge(_ badge: SpaceBadge, space: Int) -> SpaceBadge {
        guard badge.character == "#" else {
            return badge
        }
        return SpaceBadge(character: String(space), position: badge.position)
    }

    /// Maps a stored label style to the rendering style used by SpaceIconGenerator.
    /// Multi-character labels use Slim/SlimOutline for auto-expanding width.
    private static func renderStyle(for labelStyle: IconStyle, labelLength: Int) -> IconStyle {
        guard labelLength > 1 else {
            return labelStyle
        }
        return switch labelStyle {
        case .square:
            .slim
        case .squareOutline:
            .slimOutline
        default:
            labelStyle
        }
    }

    private func displayLabel(
        entry: SpaceEntry,
        globalIndex: Int,
        localIndex: Int,
        labels: [Int: String],
        isFullscreen: Bool
    ) -> String {
        if isFullscreen {
            return entry.label
        }
        if let label = labels[localIndex], !label.isEmpty {
            return LabelTemplate.resolve(label, space: globalIndex)
        }
        return store.localSpaceNumbers ? entry.label : String(globalIndex)
    }
}
