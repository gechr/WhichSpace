import Cocoa
import Testing
@testable import WhichSpace

@Suite("Color Swatch")
@MainActor
struct ColorSwatchTests {
    private let sut: ColorSwatch
    private let testWindow: NSWindow

    init() {
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

    // MARK: - Color Selection Tests

    @Test("Click on first swatch calls onColorSelected with black")
    func clickOnFirstSwatch_callsOnColorSelectedWithBlack() {
        var selectedColor: NSColor?
        sut.onColorSelected = { color in
            selectedColor = color
        }

        simulateClickOnSwatch(at: 0)

        #expect(selectedColor == .black, "First swatch should be black")
    }

    @Test("Click on second swatch calls onColorSelected with white")
    func clickOnSecondSwatch_callsOnColorSelectedWithWhite() {
        var selectedColor: NSColor?
        sut.onColorSelected = { color in
            selectedColor = color
        }

        simulateClickOnSwatch(at: 1)

        #expect(selectedColor == .white, "Second swatch should be white")
    }

    @Test("Click on third swatch calls onColorSelected with systemRed")
    func clickOnThirdSwatch_callsOnColorSelectedWithSystemRed() {
        var selectedColor: NSColor?
        sut.onColorSelected = { color in
            selectedColor = color
        }

        simulateClickOnSwatch(at: 2)

        #expect(selectedColor == .systemRed, "Third swatch should be systemRed")
    }

    @Test("Click on each preset color calls onColorSelected with correct color")
    func clickOnEachPresetColor_callsOnColorSelectedWithCorrectColor() {
        let expectedColors = ColorSwatch.presetColors

        for (index, expectedColor) in expectedColors.enumerated() {
            var selectedColor: NSColor?
            sut.onColorSelected = { color in
                selectedColor = color
            }

            simulateClickOnSwatch(at: index)

            #expect(
                selectedColor == expectedColor,
                "Swatch at index \(index) should select \(expectedColor)"
            )
        }
    }

    // MARK: - Custom Color Circle Tests

    @Test("Click on custom color circle calls onCustomColorRequested")
    func clickOnCustomColorCircle_callsOnCustomColorRequested() {
        var customColorRequested = false
        sut.onCustomColorRequested = {
            customColorRequested = true
        }

        simulateClickOnCustomColorButton()

        #expect(customColorRequested, "Custom color circle should trigger onCustomColorRequested")
    }

    @Test("Click on custom color circle does not call onColorSelected")
    func clickOnCustomColorCircle_doesNotCallOnColorSelected() {
        var colorSelectedCalled = false
        sut.onColorSelected = { _ in
            colorSelectedCalled = true
        }
        sut.onCustomColorRequested = {}

        simulateClickOnCustomColorButton()

        #expect(!colorSelectedCalled, "Custom color circle should not trigger onColorSelected")
    }

    // MARK: - Edge Case Tests

    @Test("Click outside swatches does not call callbacks")
    func clickOutsideSwatches_doesNotCallCallbacks() {
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

        #expect(!colorSelectedCalled, "Should not call onColorSelected when clicking outside")
        #expect(!customColorRequestedCalled, "Should not call onCustomColorRequested when clicking outside")
    }

    @Test("Click in spacing between swatches does not call callbacks")
    func clickInSpacingBetweenSwatches_doesNotCallCallbacks() {
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

        #expect(!colorSelectedCalled, "Should not call onColorSelected when clicking in spacing")
        #expect(!customColorRequestedCalled, "Should not call onCustomColorRequested when clicking in spacing")
    }

    // MARK: - Hover State Tests

    @Test("Mouse move over swatch updates hoveredIndex")
    func mouseMoveOverSwatch_updatesHoveredIndex() {
        #expect(sut.hoveredIndex == nil)

        let swatchCenter = centerPointForSwatch(at: 0)
        simulateMouseMove(at: swatchCenter)

        #expect(sut.hoveredIndex == 0, "Hovering over first swatch should set hoveredIndex to 0")
    }

    @Test("Mouse move to new swatch updates hoveredIndex")
    func mouseMoveToNewSwatch_updatesHoveredIndex() {
        // Move to first swatch
        simulateMouseMove(at: centerPointForSwatch(at: 0))
        #expect(sut.hoveredIndex == 0)

        // Move to second swatch
        simulateMouseMove(at: centerPointForSwatch(at: 1))

        #expect(sut.hoveredIndex == 1, "Moving to a different swatch should update hoveredIndex")
    }

    @Test("Mouse move from swatch to outside clears hoveredIndex")
    func mouseMoveFromSwatchToOutside_clearsHoveredIndex() {
        // Move to first swatch
        simulateMouseMove(at: centerPointForSwatch(at: 0))
        #expect(sut.hoveredIndex == 0)

        // Move outside all swatches
        let outsidePoint = CGPoint(x: sut.bounds.width + 10, y: sut.bounds.height / 2)
        simulateMouseMove(at: outsidePoint)

        #expect(sut.hoveredIndex == nil, "Moving from swatch to outside should clear hoveredIndex")
    }

    @Test("Mouse exit clears hoveredIndex")
    func mouseExit_clearsHoveredIndex() {
        // First hover over a swatch
        simulateMouseMove(at: centerPointForSwatch(at: 0))
        #expect(sut.hoveredIndex == 0)

        // Directly call mouseExited (simulating event creation for exit is problematic)
        sut.mouseExited(with: createDummyMouseEvent())

        #expect(sut.hoveredIndex == nil, "Mouse exit should clear hoveredIndex")
    }

    @Test("Mouse move to custom color button updates hoveredIndex")
    func mouseMoveToCustomColorButton_updatesHoveredIndex() {
        #expect(sut.hoveredIndex == nil)

        simulateMouseMove(at: centerPointForCustomColorButton())

        let customIndex = ColorSwatch.presetColors.count
        #expect(sut.hoveredIndex == customIndex, "Hovering over custom color button should set hoveredIndex")
    }

    // MARK: - Intrinsic Content Size Tests

    @Test("Intrinsic content size has expected dimensions")
    func intrinsicContentSize_hasExpectedDimensions() {
        let size = sut.intrinsicContentSize
        let colorCount = Double(ColorSwatch.presetColors.count + 1) // +1 for custom button

        // Layout constants matching Swatch base class
        let swatchSize = 16.0
        let spacing = 6.0
        let leftPadding = 16.0
        let rightPadding = 12.0

        let expectedWidth = leftPadding + rightPadding + colorCount * swatchSize + (colorCount - 1) * spacing
        let expectedHeight: Double = swatchSize + rightPadding

        #expect(abs(size.width - expectedWidth) <= 0.1, "Width should match expected calculation")
        #expect(abs(size.height - expectedHeight) <= 0.1, "Height should match expected calculation")
    }

    // MARK: - Helpers

    /// Layout constants derived from view's intrinsic size for tolerance-based calculations
    private var layoutInfo: (swatchSize: Double, spacing: Double, leftPadding: Double) {
        // We use standard values that match Swatch base class
        let swatchSize = 16.0
        let spacing = 6.0
        let leftPadding = 16.0

        return (swatchSize, spacing, leftPadding)
    }

    /// Returns the frame for the swatch at the given index
    private func frameForSwatch(at index: Int) -> CGRect {
        let layout = layoutInfo
        let xOffset = layout.leftPadding + Double(index) * (layout.swatchSize + layout.spacing)
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
