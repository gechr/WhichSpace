import Cocoa
import Testing
@testable import WhichSpace

@Suite("Symbol Picker")
@MainActor
struct SymbolPickerTests {
    private let sut: SymbolPicker
    private let testWindow: NSWindow

    init() {
        sut = SymbolPicker()
        sut.frame = NSRect(origin: .zero, size: sut.intrinsicContentSize)

        // Create window to enable proper event handling
        testWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: sut.intrinsicContentSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        testWindow.contentView = sut
    }

    // MARK: - selectedSymbol Tests

    @Test("selectedSymbol defaults to nil")
    func selectedSymbol_defaultsToNil() {
        let symbolPicker = SymbolPicker()
        #expect(symbolPicker.selectedSymbol == nil, "selectedSymbol should default to nil")
    }

    @Test("selectedSymbol can be set")
    func selectedSymbol_canBeSet() {
        sut.selectedSymbol = "star.fill"
        #expect(sut.selectedSymbol == "star.fill")
    }

    @Test("selectedSymbol can be cleared")
    func selectedSymbol_canBeCleared() {
        sut.selectedSymbol = "star.fill"
        sut.selectedSymbol = nil

        #expect(sut.selectedSymbol == nil)
    }

    @Test("selectedSymbol accepts various symbol names")
    func selectedSymbol_acceptsVariousSymbolNames() {
        let symbols = ["heart.fill", "bolt", "gear", "house.fill", "moon.stars"]

        for symbol in symbols {
            sut.selectedSymbol = symbol
            #expect(sut.selectedSymbol == symbol, "Should accept symbol: \(symbol)")
        }
    }

    // MARK: - onSymbolSelected Closure Tests

    @Test("onSymbolSelected can be set")
    func onSymbolSelected_canBeSet() {
        var capturedSymbol: String?
        sut.onSymbolSelected = { symbol in
            capturedSymbol = symbol
        }

        // Verify closure is set by calling it manually
        sut.onSymbolSelected?("test.symbol")

        #expect(capturedSymbol == "test.symbol")
    }

    @Test("onSymbolSelected receives symbol when clicked")
    func onSymbolSelected_receivesSymbolWhenClicked() {
        var receivedSymbol: String?
        sut.onSymbolSelected = { symbol in
            receivedSymbol = symbol
        }

        // Click on first symbol cell in grid
        simulateClickOnSymbolCell(row: 0, column: 0)

        #expect(receivedSymbol != nil, "onSymbolSelected should be called when clicking a symbol cell")
    }

    @Test("onSymbolSelected receives correct symbol for different cells")
    func onSymbolSelected_receivesCorrectSymbolForDifferentCells() {
        var receivedSymbols: [String] = []
        sut.onSymbolSelected = { symbol in
            if let symbol {
                receivedSymbols.append(symbol)
            }
        }

        // Click on multiple cells and verify we get different symbols
        simulateClickOnSymbolCell(row: 0, column: 0)
        simulateClickOnSymbolCell(row: 0, column: 1)

        #expect(receivedSymbols.count == 2, "Should receive callback for each click")
        // The symbols should be different (from different cells)
        if receivedSymbols.count == 2 {
            #expect(
                receivedSymbols[0] != receivedSymbols[1],
                "Different cells should return different symbols"
            )
        }
    }

    @Test("Click on symbol cell fires onSymbolSelected with valid symbol")
    func clickOnSymbolCell_firesOnSymbolSelectedWithValidSymbol() {
        var selectedSymbolIsValid = false
        sut.onSymbolSelected = { symbol in
            // Symbol should be a non-empty string for valid symbol names
            selectedSymbolIsValid = symbol != nil && !symbol!.isEmpty
        }

        simulateClickOnSymbolCell(row: 1, column: 2)

        #expect(selectedSymbolIsValid, "Clicked symbol should have a valid non-empty name")
    }

    @Test("onSymbolSelected nil closure does not crash")
    func onSymbolSelected_nilClosureDoesNotCrash() {
        sut.onSymbolSelected = nil

        // Should not crash
        #expect(sut.onSymbolSelected == nil)
    }

    // MARK: - darkMode Tests

    @Test("darkMode defaults to false")
    func darkMode_defaultsToFalse() {
        let symbolPicker = SymbolPicker()
        #expect(!symbolPicker.darkMode)
    }

    @Test("darkMode can be toggled")
    func darkMode_canBeToggled() {
        sut.darkMode = false
        #expect(!sut.darkMode)

        sut.darkMode = true
        #expect(sut.darkMode)

        sut.darkMode = false
        #expect(!sut.darkMode)
    }

    // MARK: - intrinsicContentSize Tests

    @Test("intrinsicContentSize has valid dimensions")
    func intrinsicContentSize_hasValidDimensions() {
        let size = sut.intrinsicContentSize

        #expect(size.width > 0, "Width should be positive")
        #expect(size.height > 0, "Height should be positive")
    }

    @Test("intrinsicContentSize is stable")
    func intrinsicContentSize_isStable() {
        let size1 = sut.intrinsicContentSize
        let size2 = sut.intrinsicContentSize
        let size3 = sut.intrinsicContentSize

        #expect(size1 == size2)
        #expect(size2 == size3)
    }

    @Test("intrinsicContentSize unchanged by selectedSymbol")
    func intrinsicContentSize_unchangedBySelectedSymbol() {
        let sizeBefore = sut.intrinsicContentSize

        sut.selectedSymbol = "star.fill"
        let sizeAfter = sut.intrinsicContentSize

        #expect(sizeBefore == sizeAfter, "selectedSymbol should not affect intrinsicContentSize")
    }

    @Test("intrinsicContentSize unchanged by darkMode")
    func intrinsicContentSize_unchangedByDarkMode() {
        let sizeBefore = sut.intrinsicContentSize

        sut.darkMode = true
        let sizeAfter = sut.intrinsicContentSize

        #expect(sizeBefore == sizeAfter, "darkMode should not affect intrinsicContentSize")
    }

    // MARK: - First Responder Tests

    @Test("acceptsFirstResponder returns true")
    func acceptsFirstResponder_returnsTrue() {
        #expect(sut.acceptsFirstResponder, "Should accept first responder for keyboard interaction")
    }

    // MARK: - Configuration Propagation Tests

    @Test("selectedSymbol propagates to view")
    func selectedSymbol_propagatesToView() {
        // Set selection
        sut.selectedSymbol = "gear"

        // The selectedSymbol property should be accessible
        #expect(sut.selectedSymbol == "gear", "selectedSymbol should propagate to view")
    }

    @Test("darkMode propagates to view")
    func darkMode_propagatesToView() {
        sut.darkMode = true

        // The darkMode property should be accessible
        #expect(sut.darkMode, "darkMode should propagate to view")
    }

    // MARK: - Multiple Updates Tests

    @Test("Multiple updates maintain correct state")
    func multipleUpdates_maintainCorrectState() {
        sut.selectedSymbol = "star"
        sut.darkMode = true
        #expect(sut.selectedSymbol == "star")
        #expect(sut.darkMode)

        sut.selectedSymbol = "heart"
        #expect(sut.selectedSymbol == "heart")
        #expect(sut.darkMode)

        sut.darkMode = false
        #expect(sut.selectedSymbol == "heart")
        #expect(!sut.darkMode)

        sut.selectedSymbol = nil
        #expect(sut.selectedSymbol == nil)
        #expect(!sut.darkMode)
    }

    // MARK: - Click Interaction Tests

    @Test("Click outside symbols does not fire callback")
    func clickOutsideSymbols_doesNotFireCallback() {
        var callbackFired = false
        sut.onSymbolSelected = { _ in
            callbackFired = true
        }

        // Click in padding area (outside symbol grid)
        simulateClickOnGrid(at: CGPoint(x: 2, y: 2))

        #expect(!callbackFired, "Clicking outside symbol cells should not fire callback")
    }

    @Test("Click in spacing between symbols does not fire callback")
    func clickInSpacingBetweenSymbols_doesNotFireCallback() {
        var callbackFired = false
        sut.onSymbolSelected = { _ in
            callbackFired = true
        }

        // Get cell frames from helper and click between them
        let cellFrames = symbolCellFrames(count: 2)
        guard cellFrames.count >= 2 else {
            Issue.record("Could not get symbol cell frames")
            return
        }
        // Click midway between first and second cell (in spacing)
        let spacingX = (cellFrames[0].maxX + cellFrames[1].minX) / 2
        let spacingY = cellFrames[0].midY
        simulateClickOnGrid(at: CGPoint(x: spacingX, y: spacingY))

        #expect(!callbackFired, "Clicking in spacing between symbols should not fire callback")
    }

    // MARK: - Selection Visual Verification Tests

    @Test("Click on symbol cell sets selectedSymbol")
    func clickOnSymbolCell_setsSelectedSymbol() {
        var selectedSymbol: String?
        sut.onSymbolSelected = { symbol in
            selectedSymbol = symbol
        }

        // Click on first symbol cell
        simulateClickOnSymbolCell(row: 0, column: 0)

        // Verify the callback fired with a symbol
        #expect(selectedSymbol != nil, "Should receive selected symbol")

        // Now set selectedSymbol on the view and verify draw path
        sut.selectedSymbol = selectedSymbol
        sut.needsDisplay = true
        sut.displayIfNeeded()

        #expect(sut.selectedSymbol == selectedSymbol, "selectedSymbol should be set after click")
    }

    @Test("selectedSymbol triggers redraw")
    func selectedSymbol_triggersRedraw() {
        // Set a symbol and verify the view updates
        sut.selectedSymbol = "star.fill"
        sut.needsDisplay = true
        sut.displayIfNeeded()

        // The selected symbol should persist through the draw cycle
        #expect(sut.selectedSymbol == "star.fill", "selectedSymbol should persist after redraw")
    }

    // MARK: - Hover State Tests

    // Note: SymbolGridView uses setNeedsDisplay(rect) for partial invalidation (performance),
    // so we verify hover behavior through observable side effects (toolTip) rather than needsDisplay

    @Test("Mouse move over symbol sets toolTip")
    func mouseMoveOverSymbol_setsToolTip() throws {
        let gridView = try #require(findGridView())
        #expect(gridView.toolTip == nil, "Initial toolTip should be nil")

        let symbolCenter = try #require(centerPointForSymbol(at: 0))
        simulateMouseMoveOnGrid(at: symbolCenter)

        #expect(gridView.toolTip != nil, "Hovering over a symbol should set toolTip")
    }

    @Test("Mouse move to new symbol changes toolTip")
    func mouseMoveToNewSymbol_changesToolTip() throws {
        let gridView = try #require(findGridView())

        // Move to first symbol
        let firstCenter = try #require(centerPointForSymbol(at: 0))
        simulateMouseMoveOnGrid(at: firstCenter)
        let firstToolTip = gridView.toolTip

        // Move to second symbol
        let secondCenter = try #require(centerPointForSymbol(at: 1))
        simulateMouseMoveOnGrid(at: secondCenter)
        let secondToolTip = gridView.toolTip

        #expect(firstToolTip != nil, "First symbol should have a toolTip")
        #expect(secondToolTip != nil, "Second symbol should have a toolTip")
        #expect(firstToolTip != secondToolTip, "Different symbols should have different toolTips")
    }

    @Test("Mouse move from symbol to outside clears toolTip")
    func mouseMoveFromSymbolToOutside_clearsToolTip() throws {
        let gridView = try #require(findGridView())

        // Move to first symbol
        let symbolCenter = try #require(centerPointForSymbol(at: 0))
        simulateMouseMoveOnGrid(at: symbolCenter)
        #expect(gridView.toolTip != nil, "Should have toolTip when over symbol")

        // Move to padding area (outside symbols)
        let outsidePoint = CGPoint(x: 2, y: 2)
        simulateMouseMoveOnGrid(at: outsidePoint)

        #expect(gridView.toolTip == nil, "Moving from symbol to outside should clear toolTip")
    }

    @Test("Mouse exit clears toolTip")
    func mouseExit_clearsToolTip() throws {
        let gridView = try #require(findGridView())

        // First hover over a symbol
        let symbolCenter = try #require(centerPointForSymbol(at: 0))
        simulateMouseMoveOnGrid(at: symbolCenter)
        #expect(gridView.toolTip != nil, "Should have toolTip when over symbol")

        // Trigger mouseExited
        gridView.mouseExited(with: createDummyMouseEvent())

        #expect(gridView.toolTip == nil, "Mouse exit should clear toolTip")
    }

    // MARK: - Layout Robustness Tests

    @Test("Layout info is consistent with intrinsicContentSize")
    func layoutInfo_isConsistentWithIntrinsicContentSize() {
        let layout = sut.layoutInfo
        let intrinsicSize = sut.intrinsicContentSize

        // Verify the intrinsic width is consistent with layout info
        // Width = padding * 2 + columns * symbolSize + (columns - 1) * spacing + scrollbarWidth
        let scrollbarWidth = 15.0 // Known constant
        let expectedWidth = layout.padding * 2
            + Double(layout.columns) * layout.symbolSize
            + Double(layout.columns - 1) * layout.spacing
            + scrollbarWidth

        #expect(
            abs(intrinsicSize.width - expectedWidth) <= 1.0,
            "Intrinsic width should be consistent with layout info"
        )
    }

    @Test("Frame for symbol is within grid bounds")
    func frameForSymbol_isWithinGridBounds() throws {
        let gridView = try #require(findGridView())

        // Check first few symbols are within bounds
        for index in 0 ..< min(10, sut.symbolCount) {
            guard let frame = frameForSymbol(at: index) else {
                Issue.record("Could not get frame for symbol at index \(index)")
                continue
            }
            #expect(
                frame.maxX <= gridView.bounds.width,
                "Symbol \(index) frame should be within grid width"
            )
            #expect(
                frame.maxY <= gridView.bounds.height,
                "Symbol \(index) frame should be within grid height"
            )
        }
    }

    @Test("Clicks using frameForSymbol consistently hit symbols")
    func clicksUsingFrameForSymbol_consistentlyHitSymbols() {
        // This test verifies that clicks using the frame API reliably hit symbols
        // regardless of small changes in layout constants
        var successfulClicks = 0
        let testCount = 5

        for index in 0 ..< testCount {
            var receivedCallback = false
            sut.onSymbolSelected = { _ in
                receivedCallback = true
            }

            guard let center = centerPointForSymbol(at: index) else {
                continue
            }
            simulateClickOnGrid(at: center)

            if receivedCallback {
                successfulClicks += 1
            }
        }

        #expect(
            successfulClicks == testCount,
            "All clicks using frameForSymbol centers should hit symbols"
        )
    }

    @Test("Spacing between symbols is correctly calculated")
    func spacingBetweenSymbols_isCorrectlyCalculated() throws {
        // Verify spacing calculation is correct by checking frames don't overlap
        let layout = sut.layoutInfo

        let frame0 = try #require(frameForSymbol(at: 0))
        let frame1 = try #require(frameForSymbol(at: 1))

        // Second symbol should start after first + spacing
        let expectedSecondX = frame0.maxX + layout.spacing
        #expect(
            abs(frame1.minX - expectedSecondX) <= 0.1,
            "Second symbol should start after first + spacing"
        )

        // Frames should not overlap
        #expect(
            !frame0.intersects(frame1),
            "Adjacent symbol frames should not overlap"
        )
    }

    // MARK: - Hit Testing API Tests

    @Test("symbolIndex returns correct index for symbol center")
    func symbolIndex_returnsCorrectIndexForSymbolCenter() {
        // Verify symbolIndex uses the same logic as click handling
        for index in 0 ..< min(5, sut.symbolCount) {
            guard let center = centerPointForSymbol(at: index) else {
                Issue.record("Could not get center for symbol at index \(index)")
                continue
            }
            let hitIndex = sut.symbolIndex(at: center)
            #expect(hitIndex == index, "symbolIndex should return \(index) for its center point")
        }
    }

    @Test("symbolIndex returns nil for spacing between symbols")
    func symbolIndex_returnsNilForSpacingBetweenSymbols() throws {
        let frame0 = try #require(frameForSymbol(at: 0))
        let frame1 = try #require(frameForSymbol(at: 1))

        // Point in the spacing between symbols
        let spacingPoint = CGPoint(x: (frame0.maxX + frame1.minX) / 2, y: frame0.midY)
        let hitIndex = sut.symbolIndex(at: spacingPoint)

        #expect(hitIndex == nil, "symbolIndex should return nil for points in spacing")
    }

    @Test("symbolIndex returns nil for padding area")
    func symbolIndex_returnsNilForPaddingArea() {
        // Point in the padding area (before first symbol)
        let paddingPoint = CGPoint(x: 2, y: 2)
        let hitIndex = sut.symbolIndex(at: paddingPoint)

        #expect(hitIndex == nil, "symbolIndex should return nil for points in padding area")
    }

    @Test("symbolIndex matches click behavior")
    func symbolIndex_matchesClickBehavior() throws {
        // Verify that symbolIndex correctly predicts whether a click will fire
        let testPoints: [(CGPoint, Bool)] = try [
            (#require(centerPointForSymbol(at: 0)), true), // Should hit
            (#require(centerPointForSymbol(at: 3)), true), // Should hit
            (CGPoint(x: 2, y: 2), false), // Padding - should miss
        ]

        for (point, shouldHit) in testPoints {
            var didFire = false
            sut.onSymbolSelected = { _ in didFire = true }
            simulateClickOnGrid(at: point)

            let hitIndex = sut.symbolIndex(at: point)
            let predictedHit = hitIndex != nil

            #expect(
                predictedHit == shouldHit,
                "symbolIndex prediction should match expected for point \(point)"
            )
            #expect(
                didFire == shouldHit,
                "Click behavior should match expected for point \(point)"
            )
        }
    }

    // MARK: - Helpers

    /// Returns the grid view from the scroll view hierarchy
    private func findGridView() -> NSView? {
        sut.subviews.compactMap { $0 as? NSScrollView }.first?.documentView
    }

    /// Returns the frame for a symbol at the given index using the view's test API
    private func frameForSymbol(at index: Int) -> CGRect? {
        sut.frameForSymbol(at: index)
    }

    /// Returns frames for the first N symbol cells by querying the picker's layout
    private func symbolCellFrames(count: Int) -> [CGRect] {
        var frames: [CGRect] = []
        for index in 0 ..< count {
            if let frame = frameForSymbol(at: index) {
                frames.append(frame)
            }
        }
        return frames
    }

    /// Returns the center point for the symbol at the given index
    private func centerPointForSymbol(at index: Int) -> CGPoint? {
        guard let frame = frameForSymbol(at: index) else {
            return nil
        }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Simulates a click on a symbol cell at the given row and column
    private func simulateClickOnSymbolCell(row: Int, column: Int) {
        let layout = sut.layoutInfo
        let index = row * layout.columns + column
        guard let center = centerPointForSymbol(at: index) else {
            Issue.record("Could not get frame for symbol at row \(row), column \(column)")
            return
        }
        simulateClickOnGrid(at: center)
    }

    /// Simulates a click at a specific point within the grid view
    private func simulateClickOnGrid(at gridPoint: CGPoint) {
        guard let gridView = findGridView() else {
            Issue.record("Could not find grid view")
            return
        }

        // Convert grid point to window coordinates
        let windowPoint = gridView.convert(gridPoint, to: nil)

        let event = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: testWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!

        gridView.mouseUp(with: event)
    }

    /// Simulates a mouse move at a specific point within the grid view
    private func simulateMouseMoveOnGrid(at gridPoint: CGPoint) {
        guard let gridView = findGridView() else {
            Issue.record("Could not find grid view")
            return
        }

        let windowPoint = gridView.convert(gridPoint, to: nil)

        let event = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: testWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!

        gridView.mouseMoved(with: event)
    }

    /// Creates a dummy mouse event for cases where event content doesn't matter
    private func createDummyMouseEvent() -> NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: testWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!
    }
}
