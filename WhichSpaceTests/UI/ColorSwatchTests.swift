import Cocoa
import XCTest
@testable import WhichSpace

@MainActor
final class ColorSwatchTests: XCTestCase {
    private var sut: ColorSwatch!
    private var testWindow: NSWindow!

    override func setUp() {
        super.setUp()
        sut = ColorSwatch()
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

    // MARK: - Color Selection Tests

    func testClickOnFirstSwatch_callsOnColorSelectedWithBlack() {
        var selectedColor: NSColor?
        sut.onColorSelected = { color in
            selectedColor = color
        }

        simulateClickOnSwatch(at: 0)

        XCTAssertEqual(selectedColor, .black, "First swatch should be black")
    }

    func testClickOnSecondSwatch_callsOnColorSelectedWithWhite() {
        var selectedColor: NSColor?
        sut.onColorSelected = { color in
            selectedColor = color
        }

        simulateClickOnSwatch(at: 1)

        XCTAssertEqual(selectedColor, .white, "Second swatch should be white")
    }

    func testClickOnThirdSwatch_callsOnColorSelectedWithSystemRed() {
        var selectedColor: NSColor?
        sut.onColorSelected = { color in
            selectedColor = color
        }

        simulateClickOnSwatch(at: 2)

        XCTAssertEqual(selectedColor, .systemRed, "Third swatch should be systemRed")
    }

    func testClickOnEachPresetColor_callsOnColorSelectedWithCorrectColor() {
        let expectedColors = ColorSwatch.presetColors

        for (index, expectedColor) in expectedColors.enumerated() {
            var selectedColor: NSColor?
            sut.onColorSelected = { color in
                selectedColor = color
            }

            simulateClickOnSwatch(at: index)

            XCTAssertEqual(
                selectedColor,
                expectedColor,
                "Swatch at index \(index) should select \(expectedColor)"
            )
        }
    }

    // MARK: - Custom Color Circle Tests

    func testClickOnCustomColorCircle_callsOnCustomColorRequested() {
        var customColorRequested = false
        sut.onCustomColorRequested = {
            customColorRequested = true
        }

        simulateClickOnCustomColorButton()

        XCTAssertTrue(customColorRequested, "Custom color circle should trigger onCustomColorRequested")
    }

    func testClickOnCustomColorCircle_doesNotCallOnColorSelected() {
        var colorSelectedCalled = false
        sut.onColorSelected = { _ in
            colorSelectedCalled = true
        }
        sut.onCustomColorRequested = {}

        simulateClickOnCustomColorButton()

        XCTAssertFalse(colorSelectedCalled, "Custom color circle should not trigger onColorSelected")
    }

    // MARK: - Edge Case Tests

    func testClickOutsideSwatches_doesNotCallCallbacks() {
        var colorSelectedCalled = false
        var customColorRequestedCalled = false

        sut.onColorSelected = { _ in
            colorSelectedCalled = true
        }
        sut.onCustomColorRequested = {
            customColorRequestedCalled = true
        }

        // Click outside all swatches (far right)
        let outsidePoint = CGPoint(x: sut.bounds.width + 10.0, y: sut.bounds.height / 2.0)
        simulateMouseUp(at: outsidePoint)

        XCTAssertFalse(colorSelectedCalled, "Should not call onColorSelected when clicking outside")
        XCTAssertFalse(customColorRequestedCalled, "Should not call onCustomColorRequested when clicking outside")
    }

    func testClickInSpacingBetweenSwatches_doesNotCallCallbacks() {
        var colorSelectedCalled = false
        var customColorRequestedCalled = false

        sut.onColorSelected = { _ in
            colorSelectedCalled = true
        }
        sut.onCustomColorRequested = {
            customColorRequestedCalled = true
        }

        // Click in the spacing between first and second swatch
        let spacingPoint = spacingPointBetweenSwatches(0, 1)
        simulateMouseUp(at: spacingPoint)

        XCTAssertFalse(colorSelectedCalled, "Should not call onColorSelected when clicking in spacing")
        XCTAssertFalse(customColorRequestedCalled, "Should not call onCustomColorRequested when clicking in spacing")
    }

    // MARK: - Hover State Tests

    func testMouseMoveOverSwatch_setsNeedsDisplay() {
        sut.needsDisplay = false

        let swatchCenter = centerPointForSwatch(at: 0)
        simulateMouseMove(at: swatchCenter)

        XCTAssertTrue(sut.needsDisplay, "Hovering over a swatch should set needsDisplay")
    }

    func testMouseMoveToNewSwatch_setsNeedsDisplay() {
        // Move to first swatch
        simulateMouseMove(at: centerPointForSwatch(at: 0))
        sut.needsDisplay = false

        // Move to second swatch
        simulateMouseMove(at: centerPointForSwatch(at: 1))

        XCTAssertTrue(sut.needsDisplay, "Moving to a different swatch should set needsDisplay")
    }

    func testMouseMoveFromSwatchToOutside_setsNeedsDisplay() {
        // Move to first swatch
        simulateMouseMove(at: centerPointForSwatch(at: 0))
        sut.needsDisplay = false

        // Move outside all swatches
        let outsidePoint = CGPoint(x: sut.bounds.width + 10, y: sut.bounds.height / 2)
        simulateMouseMove(at: outsidePoint)

        XCTAssertTrue(sut.needsDisplay, "Moving from swatch to outside should set needsDisplay")
    }

    func testMouseExit_setsNeedsDisplay() {
        // First hover over a swatch
        simulateMouseMove(at: centerPointForSwatch(at: 0))
        sut.needsDisplay = false

        // Directly call mouseExited (simulating event creation for exit is problematic)
        sut.mouseExited(with: createDummyMouseEvent())

        XCTAssertTrue(sut.needsDisplay, "Mouse exit should set needsDisplay")
    }

    func testMouseMoveToCustomColorButton_setsNeedsDisplay() {
        sut.needsDisplay = false

        simulateMouseMove(at: centerPointForCustomColorButton())

        XCTAssertTrue(sut.needsDisplay, "Hovering over custom color button should set needsDisplay")
    }

    // MARK: - Intrinsic Content Size Tests

    func testIntrinsicContentSize_hasExpectedDimensions() {
        let size = sut.intrinsicContentSize
        let colorCount = Double(ColorSwatch.presetColors.count + 1) // +1 for custom button

        // Layout constants matching ColorSwatch
        let swatchSize = 16.0
        let spacing = 6.0
        let padding = 12.0

        let expectedWidth = padding * 2 + colorCount * swatchSize + (colorCount - 1) * spacing
        let expectedHeight: Double = swatchSize + padding

        XCTAssertEqual(size.width, expectedWidth, accuracy: 0.1, "Width should match expected calculation")
        XCTAssertEqual(size.height, expectedHeight, accuracy: 0.1, "Height should match expected calculation")
    }

    // MARK: - Helpers

    /// Layout constants derived from view's intrinsic size for tolerance-based calculations
    private var layoutInfo: (swatchSize: Double, spacing: Double, padding: Double) {
        // Derive layout from intrinsic content size and known color count
        let totalItems = Double(ColorSwatch.presetColors.count + 1)
        let width = sut.intrinsicContentSize.width

        // Known: width = padding * 2 + count * swatchSize + (count - 1) * spacing
        // Known: height = swatchSize + padding, so swatchSize = height - padding
        // We use standard values that match ColorSwatch implementation
        let swatchSize = 16.0
        let spacing = 6.0
        let padding = (width - totalItems * swatchSize - (totalItems - 1) * spacing) / 2

        return (swatchSize, spacing, padding)
    }

    /// Returns the frame for the swatch at the given index
    private func frameForSwatch(at index: Int) -> CGRect {
        let layout = layoutInfo
        let xOffset = layout.padding + Double(index) * (layout.swatchSize + layout.spacing)
        let yOffset = (sut.bounds.height - layout.swatchSize) / 2
        return CGRect(x: xOffset, y: yOffset, width: layout.swatchSize, height: layout.swatchSize)
    }

    /// Returns the center point for the swatch at the given index
    private func centerPointForSwatch(at index: Int) -> CGPoint {
        let frame = frameForSwatch(at: index)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Returns the frame for the custom color button
    private func frameForCustomColorButton() -> CGRect {
        frameForSwatch(at: ColorSwatch.presetColors.count)
    }

    /// Returns the center point for the custom color button
    private func centerPointForCustomColorButton() -> CGPoint {
        let frame = frameForCustomColorButton()
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// Returns a point in the spacing between two adjacent swatches
    private func spacingPointBetweenSwatches(_ first: Int, _ second: Int) -> CGPoint {
        let firstFrame = frameForSwatch(at: first)
        let secondFrame = frameForSwatch(at: second)
        let xMiddle = (firstFrame.maxX + secondFrame.minX) / 2
        return CGPoint(x: xMiddle, y: firstFrame.midY)
    }

    /// Simulates clicking on the swatch at the given index
    private func simulateClickOnSwatch(at index: Int) {
        simulateMouseUp(at: centerPointForSwatch(at: index))
    }

    /// Simulates clicking on the custom color button
    private func simulateClickOnCustomColorButton() {
        simulateMouseUp(at: centerPointForCustomColorButton())
    }

    private func simulateMouseUp(at point: CGPoint) {
        let event = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: testWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!

        sut.mouseUp(with: event)
    }

    private func simulateMouseMove(at point: CGPoint) {
        let event = NSEvent.mouseEvent(
            with: .mouseMoved,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: testWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        )!

        sut.mouseMoved(with: event)
    }

    /// Creates a dummy mouse event for cases where the event content doesn't matter
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
