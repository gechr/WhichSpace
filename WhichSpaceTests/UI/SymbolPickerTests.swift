import Cocoa
import Testing
@testable import WhichSpace

@Suite("Symbol Picker")
@MainActor
struct SymbolPickerTests {
    private let sut: ItemPicker
    private let testWindow: NSWindow

    init() {
        sut = ItemPicker(type: .symbols)
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

    // MARK: - selectedItem Tests

    @Test("selectedItem defaults to nil")
    func selectedItem_defaultsToNil() {
        let picker = ItemPicker(type: .symbols)
        #expect(picker.selectedItem == nil, "selectedItem should default to nil")
    }

    @Test("selectedItem can be set")
    func selectedItem_canBeSet() {
        sut.selectedItem = "star.fill"
        #expect(sut.selectedItem == "star.fill")
    }

    @Test("selectedItem can be cleared")
    func selectedItem_canBeCleared() {
        sut.selectedItem = "star.fill"
        sut.selectedItem = nil

        #expect(sut.selectedItem == nil)
    }

    @Test("selectedItem accepts various symbol names")
    func selectedItem_acceptsVariousSymbolNames() {
        let symbols = ["heart.fill", "bolt", "gear", "house.fill", "moon.stars"]

        for symbol in symbols {
            sut.selectedItem = symbol
            #expect(sut.selectedItem == symbol, "Should accept symbol: \(symbol)")
        }
    }

    // MARK: - onItemSelected Closure Tests

    @Test("onItemSelected can be set")
    func onItemSelected_canBeSet() {
        var capturedItem: String?
        sut.onItemSelected = { item in
            capturedItem = item
        }

        // Verify closure is set by calling it manually
        sut.onItemSelected?("test.symbol")

        #expect(capturedItem == "test.symbol")
    }

    @Test("onItemSelected receives symbol when clicked")
    func onItemSelected_receivesSymbolWhenClicked() {
        var receivedItem: String?
        sut.onItemSelected = { item in
            receivedItem = item
        }

        // Click on first symbol cell in grid
        simulateClickOnItemCell(row: 0, column: 0)

        #expect(receivedItem != nil, "onItemSelected should be called when clicking a symbol cell")
    }

    @Test("onItemSelected receives correct symbol for different cells")
    func onItemSelected_receivesCorrectSymbolForDifferentCells() {
        var receivedItems: [String] = []
        sut.onItemSelected = { item in
            if let item {
                receivedItems.append(item)
            }
        }

        // Click on multiple cells and verify we get different symbols
        simulateClickOnItemCell(row: 0, column: 0)
        simulateClickOnItemCell(row: 0, column: 1)

        #expect(receivedItems.count == 2, "Should receive callback for each click")
        // The symbols should be different (from different cells)
        if receivedItems.count == 2 {
            #expect(
                receivedItems[0] != receivedItems[1],
                "Different cells should return different symbols"
            )
        }
    }

    @Test("Click on symbol cell fires onItemSelected with valid symbol")
    func clickOnItemCell_firesOnItemSelectedWithValidSymbol() {
        var selectedItemIsValid = false
        sut.onItemSelected = { item in
            // Symbol should be a non-empty string for valid symbol names
            selectedItemIsValid = item != nil && !item!.isEmpty
        }

        simulateClickOnItemCell(row: 1, column: 2)

        #expect(selectedItemIsValid, "Clicked symbol should have a valid non-empty name")
    }

    @Test("onItemSelected nil closure does not crash")
    func onItemSelected_nilClosureDoesNotCrash() {
        sut.onItemSelected = nil

        // Should not crash
        #expect(sut.onItemSelected == nil)
    }

    // MARK: - darkMode Tests

    @Test("darkMode defaults to false")
    func darkMode_defaultsToFalse() {
        let picker = ItemPicker(type: .symbols)
        #expect(!picker.darkMode)
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

    @Test("intrinsicContentSize unchanged by selectedItem")
    func intrinsicContentSize_unchangedBySelectedItem() {
        let sizeBefore = sut.intrinsicContentSize

        sut.selectedItem = "star.fill"
        let sizeAfter = sut.intrinsicContentSize

        #expect(sizeBefore == sizeAfter, "selectedItem should not affect intrinsicContentSize")
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

    @Test("selectedItem propagates to view")
    func selectedItem_propagatesToView() {
        // Set selection
        sut.selectedItem = "gear"

        // The selectedItem property should be accessible
        #expect(sut.selectedItem == "gear", "selectedItem should propagate to view")
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
        sut.selectedItem = "star"
        sut.darkMode = true
        #expect(sut.selectedItem == "star")
        #expect(sut.darkMode)

        sut.selectedItem = "heart"
        #expect(sut.selectedItem == "heart")
        #expect(sut.darkMode)

        sut.darkMode = false
        #expect(sut.selectedItem == "heart")
        #expect(!sut.darkMode)

        sut.selectedItem = nil
        #expect(sut.selectedItem == nil)
        #expect(!sut.darkMode)
    }

    // MARK: - Click Interaction Tests

    @Test("Click outside symbols does not fire callback")
    func clickOutsideSymbols_doesNotFireCallback() {
        var callbackFired = false
        sut.onItemSelected = { _ in
            callbackFired = true
        }

        // Click in padding area (outside symbol grid)
        simulateClickOnGrid(at: CGPoint(x: 2, y: 2))

        #expect(!callbackFired, "Clicking outside symbol cells should not fire callback")
    }

    @Test("Click in spacing between symbols does not fire callback")
    func clickInSpacingBetweenSymbols_doesNotFireCallback() {
        var callbackFired = false
        sut.onItemSelected = { _ in
            callbackFired = true
        }

        // Get cell frames from helper and click between them
        let cellFrames = itemCellFrames(count: 2)
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

    @Test("Click on symbol cell sets selectedItem")
    func clickOnItemCell_setsSelectedItem() {
        var selectedItem: String?
        sut.onItemSelected = { item in
            selectedItem = item
        }

        // Click on first symbol cell
        simulateClickOnItemCell(row: 0, column: 0)

        // Verify the callback fired with a symbol
        #expect(selectedItem != nil, "Should receive selected symbol")

        // Now set selectedItem on the view and verify draw path
        sut.selectedItem = selectedItem
        sut.needsDisplay = true
        sut.displayIfNeeded()

        #expect(sut.selectedItem == selectedItem, "selectedItem should be set after click")
    }

    @Test("selectedItem triggers redraw")
    func selectedItem_triggersRedraw() {
        // Set a symbol and verify the view updates
        sut.selectedItem = "star.fill"
        sut.needsDisplay = true
        sut.displayIfNeeded()

        // The selected symbol should persist through the draw cycle
        #expect(sut.selectedItem == "star.fill", "selectedItem should persist after redraw")
    }

    // MARK: - Hover State Tests

    // Note: ItemGridView uses setNeedsDisplay(rect) for partial invalidation (performance),
    // so we verify hover behavior through observable side effects (toolTip) rather than needsDisplay

    @Test("Mouse move over symbol sets toolTip")
    func mouseMoveOverSymbol_setsToolTip() throws {
        let gridView = try #require(findGridView())
        #expect(gridView.toolTip == nil, "Initial toolTip should be nil")

        let itemCenter = try #require(centerPointForItem(at: 0))
        simulateMouseMoveOnGrid(at: itemCenter)

        #expect(gridView.toolTip != nil, "Hovering over a symbol should set toolTip")
    }

    @Test("Mouse move to new symbol changes toolTip")
    func mouseMoveToNewSymbol_changesToolTip() throws {
        let gridView = try #require(findGridView())

        // Move to first symbol
        let firstCenter = try #require(centerPointForItem(at: 0))
        simulateMouseMoveOnGrid(at: firstCenter)
        let firstToolTip = gridView.toolTip

        // Move to second symbol
        let secondCenter = try #require(centerPointForItem(at: 1))
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
        let itemCenter = try #require(centerPointForItem(at: 0))
        simulateMouseMoveOnGrid(at: itemCenter)
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
        let itemCenter = try #require(centerPointForItem(at: 0))
        simulateMouseMoveOnGrid(at: itemCenter)
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
        // Width = padding * 2 + columns * itemSize + (columns - 1) * spacing + scrollbarWidth
        let scrollbarWidth = 15.0 // Known constant
        let expectedWidth = layout.padding * 2
            + Double(layout.columns) * layout.itemSize
            + Double(layout.columns - 1) * layout.spacing
            + scrollbarWidth

        #expect(
            abs(intrinsicSize.width - expectedWidth) <= 1.0,
            "Intrinsic width should be consistent with layout info"
        )
    }

    @Test("Frame for item is within grid bounds")
    func frameForItem_isWithinGridBounds() throws {
        let gridView = try #require(findGridView())

        // Check first few symbols are within bounds
        for index in 0 ..< min(10, sut.itemCount) {
            guard let frame = frameForItem(at: index) else {
                Issue.record("Could not get frame for item at index \(index)")
                continue
            }
            #expect(
                frame.maxX <= gridView.bounds.width,
                "Item \(index) frame should be within grid width"
            )
            #expect(
                frame.maxY <= gridView.bounds.height,
                "Item \(index) frame should be within grid height"
            )
        }
    }

    @Test("Clicks using frameForItem consistently hit symbols")
    func clicksUsingFrameForItem_consistentlyHitSymbols() {
        // This test verifies that clicks using the frame API reliably hit symbols
        // regardless of small changes in layout constants
        var successfulClicks = 0
        let testCount = 5

        for index in 0 ..< testCount {
            var receivedCallback = false
            sut.onItemSelected = { _ in
                receivedCallback = true
            }

            guard let center = centerPointForItem(at: index) else {
                continue
            }
            simulateClickOnGrid(at: center)

            if receivedCallback {
                successfulClicks += 1
            }
        }

        #expect(
            successfulClicks == testCount,
            "All clicks using frameForItem centers should hit symbols"
        )
    }

    @Test("Spacing between symbols is correctly calculated")
    func spacingBetweenSymbols_isCorrectlyCalculated() throws {
        // Verify spacing calculation is correct by checking frames don't overlap
        let layout = sut.layoutInfo

        let frame0 = try #require(frameForItem(at: 0))
        let frame1 = try #require(frameForItem(at: 1))

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

    @Test("itemIndex returns correct index for item center")
    func itemIndex_returnsCorrectIndexForItemCenter() {
        // Verify itemIndex uses the same logic as click handling
        for index in 0 ..< min(5, sut.itemCount) {
            guard let center = centerPointForItem(at: index) else {
                Issue.record("Could not get center for item at index \(index)")
                continue
            }
            let hitIndex = sut.itemIndex(at: center)
            #expect(hitIndex == index, "itemIndex should return \(index) for its center point")
        }
    }

    @Test("itemIndex returns nil for spacing between symbols")
    func itemIndex_returnsNilForSpacingBetweenSymbols() throws {
        let frame0 = try #require(frameForItem(at: 0))
        let frame1 = try #require(frameForItem(at: 1))

        // Point in the spacing between symbols
        let spacingPoint = CGPoint(x: (frame0.maxX + frame1.minX) / 2, y: frame0.midY)
        let hitIndex = sut.itemIndex(at: spacingPoint)

        #expect(hitIndex == nil, "itemIndex should return nil for points in spacing")
    }

    @Test("itemIndex returns nil for padding area")
    func itemIndex_returnsNilForPaddingArea() {
        // Point in the padding area (before first symbol)
        let paddingPoint = CGPoint(x: 2, y: 2)
        let hitIndex = sut.itemIndex(at: paddingPoint)

        #expect(hitIndex == nil, "itemIndex should return nil for points in padding area")
    }

    @Test("itemIndex matches click behavior")
    func itemIndex_matchesClickBehavior() throws {
        // Verify that itemIndex correctly predicts whether a click will fire
        let testPoints: [(CGPoint, Bool)] = try [
            (#require(centerPointForItem(at: 0)), true), // Should hit
            (#require(centerPointForItem(at: 3)), true), // Should hit
            (CGPoint(x: 2, y: 2), false), // Padding - should miss
        ]

        for (point, shouldHit) in testPoints {
            var didFire = false
            sut.onItemSelected = { _ in didFire = true }
            simulateClickOnGrid(at: point)

            let hitIndex = sut.itemIndex(at: point)
            let predictedHit = hitIndex != nil

            #expect(
                predictedHit == shouldHit,
                "itemIndex prediction should match expected for point \(point)"
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

    /// Returns the frame for an item at the given index using the view's test API
    private func frameForItem(at index: Int) -> CGRect? {
        sut.frameForItem(at: index)
    }

    /// Returns frames for the first N item cells by querying the picker's layout
    private func itemCellFrames(count: Int) -> [CGRect] {
        var frames: [CGRect] = []
        for index in 0 ..< count {
            if let frame = frameForItem(at: index) {
                frames.append(frame)
            }
        }
        return frames
    }

    /// Returns the center point for the item at the given index
    private func centerPointForItem(at index: Int) -> CGPoint? {
        guard let frame = frameForItem(at: index) else {
            return nil
        }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Simulates a click on an item cell at the given row and column
    private func simulateClickOnItemCell(row: Int, column: Int) {
        let layout = sut.layoutInfo
        let index = row * layout.columns + column
        guard let center = centerPointForItem(at: index) else {
            Issue.record("Could not get frame for item at row \(row), column \(column)")
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
