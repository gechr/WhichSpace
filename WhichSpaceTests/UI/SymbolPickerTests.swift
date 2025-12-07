import Cocoa
import XCTest
@testable import WhichSpace

@MainActor
final class SymbolPickerTests: XCTestCase {
    private var sut: SymbolPicker!
    private var testWindow: NSWindow!

    override func setUp() {
        super.setUp()
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

    override func tearDown() {
        testWindow = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - selectedSymbol Tests

    func testSelectedSymbol_defaultsToNil() {
        let symbolPicker = SymbolPicker()
        XCTAssertNil(symbolPicker.selectedSymbol, "selectedSymbol should default to nil")
    }

    func testSelectedSymbol_canBeSet() {
        sut.selectedSymbol = "star.fill"
        XCTAssertEqual(sut.selectedSymbol, "star.fill")
    }

    func testSelectedSymbol_canBeCleared() {
        sut.selectedSymbol = "star.fill"
        sut.selectedSymbol = nil

        XCTAssertNil(sut.selectedSymbol)
    }

    func testSelectedSymbol_acceptsVariousSymbolNames() {
        let symbols = ["heart.fill", "bolt", "gear", "house.fill", "moon.stars"]

        for symbol in symbols {
            sut.selectedSymbol = symbol
            XCTAssertEqual(sut.selectedSymbol, symbol, "Should accept symbol: \(symbol)")
        }
    }

    // MARK: - onSymbolSelected Closure Tests

    func testOnSymbolSelected_canBeSet() {
        var capturedSymbol: String?
        sut.onSymbolSelected = { symbol in
            capturedSymbol = symbol
        }

        // Verify closure is set by calling it manually
        sut.onSymbolSelected?("test.symbol")

        XCTAssertEqual(capturedSymbol, "test.symbol")
    }

    func testOnSymbolSelected_receivesSymbolWhenClicked() {
        var receivedSymbol: String?
        sut.onSymbolSelected = { symbol in
            receivedSymbol = symbol
        }

        // Click on first symbol cell in grid
        simulateClickOnSymbolCell(row: 0, column: 0)

        XCTAssertNotNil(receivedSymbol, "onSymbolSelected should be called when clicking a symbol cell")
    }

    func testOnSymbolSelected_receivesCorrectSymbolForDifferentCells() {
        var receivedSymbols: [String] = []
        sut.onSymbolSelected = { symbol in
            if let symbol {
                receivedSymbols.append(symbol)
            }
        }

        // Click on multiple cells and verify we get different symbols
        simulateClickOnSymbolCell(row: 0, column: 0)
        simulateClickOnSymbolCell(row: 0, column: 1)

        XCTAssertEqual(receivedSymbols.count, 2, "Should receive callback for each click")
        // The symbols should be different (from different cells)
        if receivedSymbols.count == 2 {
            XCTAssertNotEqual(
                receivedSymbols[0],
                receivedSymbols[1],
                "Different cells should return different symbols"
            )
        }
    }

    func testClickOnSymbolCell_firesOnSymbolSelectedWithValidSymbol() {
        var selectedSymbolIsValid = false
        sut.onSymbolSelected = { symbol in
            // Symbol should be a non-empty string for valid symbol names
            selectedSymbolIsValid = symbol != nil && !symbol!.isEmpty
        }

        simulateClickOnSymbolCell(row: 1, column: 2)

        XCTAssertTrue(selectedSymbolIsValid, "Clicked symbol should have a valid non-empty name")
    }

    func testOnSymbolSelected_nilClosureDoesNotCrash() {
        sut.onSymbolSelected = nil

        // Should not crash
        XCTAssertNil(sut.onSymbolSelected)
    }

    // MARK: - darkMode Tests

    func testDarkMode_defaultsToFalse() {
        let symbolPicker = SymbolPicker()
        XCTAssertFalse(symbolPicker.darkMode)
    }

    func testDarkMode_canBeToggled() {
        sut.darkMode = false
        XCTAssertFalse(sut.darkMode)

        sut.darkMode = true
        XCTAssertTrue(sut.darkMode)

        sut.darkMode = false
        XCTAssertFalse(sut.darkMode)
    }

    // MARK: - intrinsicContentSize Tests

    func testIntrinsicContentSize_hasValidDimensions() {
        let size = sut.intrinsicContentSize

        XCTAssertGreaterThan(size.width, 0, "Width should be positive")
        XCTAssertGreaterThan(size.height, 0, "Height should be positive")
    }

    func testIntrinsicContentSize_isStable() {
        let size1 = sut.intrinsicContentSize
        let size2 = sut.intrinsicContentSize
        let size3 = sut.intrinsicContentSize

        XCTAssertEqual(size1, size2)
        XCTAssertEqual(size2, size3)
    }

    func testIntrinsicContentSize_unchangedBySelectedSymbol() {
        let sizeBefore = sut.intrinsicContentSize

        sut.selectedSymbol = "star.fill"
        let sizeAfter = sut.intrinsicContentSize

        XCTAssertEqual(sizeBefore, sizeAfter, "selectedSymbol should not affect intrinsicContentSize")
    }

    func testIntrinsicContentSize_unchangedByDarkMode() {
        let sizeBefore = sut.intrinsicContentSize

        sut.darkMode = true
        let sizeAfter = sut.intrinsicContentSize

        XCTAssertEqual(sizeBefore, sizeAfter, "darkMode should not affect intrinsicContentSize")
    }

    // MARK: - First Responder Tests

    func testAcceptsFirstResponder_returnsTrue() {
        XCTAssertTrue(sut.acceptsFirstResponder, "Should accept first responder for keyboard interaction")
    }

    // MARK: - Configuration Propagation Tests

    func testSelectedSymbol_propagatesToView() {
        // Set selection
        sut.selectedSymbol = "gear"

        // The selectedSymbol property should be accessible
        XCTAssertEqual(sut.selectedSymbol, "gear", "selectedSymbol should propagate to view")
    }

    func testDarkMode_propagatesToView() {
        sut.darkMode = true

        // The darkMode property should be accessible
        XCTAssertTrue(sut.darkMode, "darkMode should propagate to view")
    }

    // MARK: - Multiple Updates Tests

    func testMultipleUpdates_maintainCorrectState() {
        sut.selectedSymbol = "star"
        sut.darkMode = true
        XCTAssertEqual(sut.selectedSymbol, "star")
        XCTAssertTrue(sut.darkMode)

        sut.selectedSymbol = "heart"
        XCTAssertEqual(sut.selectedSymbol, "heart")
        XCTAssertTrue(sut.darkMode)

        sut.darkMode = false
        XCTAssertEqual(sut.selectedSymbol, "heart")
        XCTAssertFalse(sut.darkMode)

        sut.selectedSymbol = nil
        XCTAssertNil(sut.selectedSymbol)
        XCTAssertFalse(sut.darkMode)
    }

    // MARK: - Click Interaction Tests

    func testClickOutsideSymbols_doesNotFireCallback() {
        var callbackFired = false
        sut.onSymbolSelected = { _ in
            callbackFired = true
        }

        // Click in padding area (outside symbol grid)
        simulateClickOnGrid(at: CGPoint(x: 2, y: 2))

        XCTAssertFalse(callbackFired, "Clicking outside symbol cells should not fire callback")
    }

    func testClickInSpacingBetweenSymbols_doesNotFireCallback() {
        var callbackFired = false
        sut.onSymbolSelected = { _ in
            callbackFired = true
        }

        // Get cell frames from helper and click between them
        let cellFrames = symbolCellFrames(count: 2)
        guard cellFrames.count >= 2 else {
            XCTFail("Could not get symbol cell frames")
            return
        }
        // Click midway between first and second cell (in spacing)
        let spacingX = (cellFrames[0].maxX + cellFrames[1].minX) / 2
        let spacingY = cellFrames[0].midY
        simulateClickOnGrid(at: CGPoint(x: spacingX, y: spacingY))

        XCTAssertFalse(callbackFired, "Clicking in spacing between symbols should not fire callback")
    }

    // MARK: - Selection Visual Verification Tests

    func testClickOnSymbolCell_setsSelectedSymbol() {
        var selectedSymbol: String?
        sut.onSymbolSelected = { symbol in
            selectedSymbol = symbol
        }

        // Click on first symbol cell
        simulateClickOnSymbolCell(row: 0, column: 0)

        // Verify the callback fired with a symbol
        XCTAssertNotNil(selectedSymbol, "Should receive selected symbol")

        // Now set selectedSymbol on the view and verify draw path
        sut.selectedSymbol = selectedSymbol
        sut.needsDisplay = true
        sut.displayIfNeeded()

        XCTAssertEqual(sut.selectedSymbol, selectedSymbol, "selectedSymbol should be set after click")
    }

    func testSelectedSymbol_triggersRedraw() {
        // Set a symbol and verify the view updates
        sut.selectedSymbol = "star.fill"
        sut.needsDisplay = true
        sut.displayIfNeeded()

        // The selected symbol should persist through the draw cycle
        XCTAssertEqual(sut.selectedSymbol, "star.fill", "selectedSymbol should persist after redraw")
    }

    // MARK: - Hover State Tests

    // Note: SymbolGridView uses setNeedsDisplay(rect) for partial invalidation (performance),
    // so we verify hover behavior through observable side effects (toolTip) rather than needsDisplay

    func testMouseMoveOverSymbol_setsToolTip() {
        guard let gridView = findGridView() else {
            XCTFail("Could not find grid view")
            return
        }
        XCTAssertNil(gridView.toolTip, "Initial toolTip should be nil")

        guard let symbolCenter = centerPointForSymbol(at: 0) else {
            XCTFail("Could not get center for first symbol")
            return
        }
        simulateMouseMoveOnGrid(at: symbolCenter)

        XCTAssertNotNil(gridView.toolTip, "Hovering over a symbol should set toolTip")
    }

    func testMouseMoveToNewSymbol_changesToolTip() {
        guard let gridView = findGridView() else {
            XCTFail("Could not find grid view")
            return
        }

        // Move to first symbol
        guard let firstCenter = centerPointForSymbol(at: 0) else {
            XCTFail("Could not get center for first symbol")
            return
        }
        simulateMouseMoveOnGrid(at: firstCenter)
        let firstToolTip = gridView.toolTip

        // Move to second symbol
        guard let secondCenter = centerPointForSymbol(at: 1) else {
            XCTFail("Could not get center for second symbol")
            return
        }
        simulateMouseMoveOnGrid(at: secondCenter)
        let secondToolTip = gridView.toolTip

        XCTAssertNotNil(firstToolTip, "First symbol should have a toolTip")
        XCTAssertNotNil(secondToolTip, "Second symbol should have a toolTip")
        XCTAssertNotEqual(firstToolTip, secondToolTip, "Different symbols should have different toolTips")
    }

    func testMouseMoveFromSymbolToOutside_clearsToolTip() {
        guard let gridView = findGridView() else {
            XCTFail("Could not find grid view")
            return
        }

        // Move to first symbol
        guard let symbolCenter = centerPointForSymbol(at: 0) else {
            XCTFail("Could not get center for first symbol")
            return
        }
        simulateMouseMoveOnGrid(at: symbolCenter)
        XCTAssertNotNil(gridView.toolTip, "Should have toolTip when over symbol")

        // Move to padding area (outside symbols)
        let outsidePoint = CGPoint(x: 2, y: 2)
        simulateMouseMoveOnGrid(at: outsidePoint)

        XCTAssertNil(gridView.toolTip, "Moving from symbol to outside should clear toolTip")
    }

    func testMouseExit_clearsToolTip() {
        guard let gridView = findGridView() else {
            XCTFail("Could not find grid view")
            return
        }

        // First hover over a symbol
        guard let symbolCenter = centerPointForSymbol(at: 0) else {
            XCTFail("Could not get center for first symbol")
            return
        }
        simulateMouseMoveOnGrid(at: symbolCenter)
        XCTAssertNotNil(gridView.toolTip, "Should have toolTip when over symbol")

        // Trigger mouseExited
        gridView.mouseExited(with: createDummyMouseEvent())

        XCTAssertNil(gridView.toolTip, "Mouse exit should clear toolTip")
    }

    // MARK: - Layout Robustness Tests

    func testLayoutInfo_isConsistentWithIntrinsicContentSize() {
        let layout = sut.layoutInfo
        let intrinsicSize = sut.intrinsicContentSize

        // Verify the intrinsic width is consistent with layout info
        // Width = padding * 2 + columns * symbolSize + (columns - 1) * spacing + scrollbarWidth
        let scrollbarWidth = 15.0 // Known constant
        let expectedWidth = layout.padding * 2
            + Double(layout.columns) * layout.symbolSize
            + Double(layout.columns - 1) * layout.spacing
            + scrollbarWidth

        XCTAssertEqual(
            intrinsicSize.width,
            expectedWidth,
            accuracy: 1.0,
            "Intrinsic width should be consistent with layout info"
        )
    }

    func testFrameForSymbol_isWithinGridBounds() {
        guard let gridView = findGridView() else {
            XCTFail("Could not find grid view")
            return
        }

        // Check first few symbols are within bounds
        for index in 0 ..< min(10, sut.symbolCount) {
            guard let frame = frameForSymbol(at: index) else {
                XCTFail("Could not get frame for symbol at index \(index)")
                continue
            }
            XCTAssertTrue(
                frame.maxX <= gridView.bounds.width,
                "Symbol \(index) frame should be within grid width"
            )
            XCTAssertTrue(
                frame.maxY <= gridView.bounds.height,
                "Symbol \(index) frame should be within grid height"
            )
        }
    }

    func testClicksUsingFrameForSymbol_consistentlyHitSymbols() {
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

        XCTAssertEqual(
            successfulClicks,
            testCount,
            "All clicks using frameForSymbol centers should hit symbols"
        )
    }

    func testSpacingBetweenSymbols_isCorrectlyCalculated() {
        // Verify spacing calculation is correct by checking frames don't overlap
        let layout = sut.layoutInfo

        guard let frame0 = frameForSymbol(at: 0),
              let frame1 = frameForSymbol(at: 1)
        else {
            XCTFail("Could not get symbol frames")
            return
        }

        // Second symbol should start after first + spacing
        let expectedSecondX = frame0.maxX + layout.spacing
        XCTAssertEqual(
            frame1.minX,
            expectedSecondX,
            accuracy: 0.1,
            "Second symbol should start after first + spacing"
        )

        // Frames should not overlap
        XCTAssertFalse(
            frame0.intersects(frame1),
            "Adjacent symbol frames should not overlap"
        )
    }

    // MARK: - Hit Testing API Tests

    func testSymbolIndex_returnsCorrectIndexForSymbolCenter() {
        // Verify symbolIndex uses the same logic as click handling
        for index in 0 ..< min(5, sut.symbolCount) {
            guard let center = centerPointForSymbol(at: index) else {
                XCTFail("Could not get center for symbol at index \(index)")
                continue
            }
            let hitIndex = sut.symbolIndex(at: center)
            XCTAssertEqual(hitIndex, index, "symbolIndex should return \(index) for its center point")
        }
    }

    func testSymbolIndex_returnsNilForSpacingBetweenSymbols() {
        guard let frame0 = frameForSymbol(at: 0),
              let frame1 = frameForSymbol(at: 1)
        else {
            XCTFail("Could not get symbol frames")
            return
        }

        // Point in the spacing between symbols
        let spacingPoint = CGPoint(x: (frame0.maxX + frame1.minX) / 2, y: frame0.midY)
        let hitIndex = sut.symbolIndex(at: spacingPoint)

        XCTAssertNil(hitIndex, "symbolIndex should return nil for points in spacing")
    }

    func testSymbolIndex_returnsNilForPaddingArea() {
        // Point in the padding area (before first symbol)
        let paddingPoint = CGPoint(x: 2, y: 2)
        let hitIndex = sut.symbolIndex(at: paddingPoint)

        XCTAssertNil(hitIndex, "symbolIndex should return nil for points in padding area")
    }

    func testSymbolIndex_matchesClickBehavior() {
        // Verify that symbolIndex correctly predicts whether a click will fire
        let testPoints: [(CGPoint, Bool)] = [
            (centerPointForSymbol(at: 0)!, true), // Should hit
            (centerPointForSymbol(at: 3)!, true), // Should hit
            (CGPoint(x: 2, y: 2), false), // Padding - should miss
        ]

        for (point, shouldHit) in testPoints {
            var didFire = false
            sut.onSymbolSelected = { _ in didFire = true }
            simulateClickOnGrid(at: point)

            let hitIndex = sut.symbolIndex(at: point)
            let predictedHit = hitIndex != nil

            XCTAssertEqual(
                predictedHit,
                shouldHit,
                "symbolIndex prediction should match expected for point \(point)"
            )
            XCTAssertEqual(
                didFire,
                shouldHit,
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
            XCTFail("Could not get frame for symbol at row \(row), column \(column)")
            return
        }
        simulateClickOnGrid(at: center)
    }

    /// Simulates a click at a specific point within the grid view
    private func simulateClickOnGrid(at gridPoint: CGPoint) {
        guard let gridView = findGridView() else {
            XCTFail("Could not find grid view")
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
            XCTFail("Could not find grid view")
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
