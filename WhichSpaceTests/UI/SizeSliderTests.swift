import Cocoa
import XCTest
@testable import WhichSpace

@MainActor
final class SizeSliderTests: XCTestCase {
    private var sut: SizeSlider!
    private var testWindow: NSWindow!
    private let testRange = 60.0 ... 120.0
    private let initialSize = 100.0

    override func setUp() {
        super.setUp()
        sut = SizeSlider(initialSize: initialSize, range: testRange)
        sut.frame = NSRect(origin: .zero, size: sut.intrinsicContentSize)
        sut.layout()

        // Create window to enable proper event handling
        testWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: sut.intrinsicContentSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        testWindow.contentView = sut
        testWindow.makeFirstResponder(sut)
    }

    override func tearDown() {
        testWindow = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_currentSizeMatchesInitialValue() {
        XCTAssertEqual(sut.currentSize, initialSize, "Initial currentSize should match initialSize")
    }

    func testInitialState_withDifferentInitialSize() {
        let customSize = 80.0
        let customSut = SizeSlider(initialSize: customSize, range: testRange)

        XCTAssertEqual(customSut.currentSize, customSize, "currentSize should match custom initial size")
    }

    // MARK: - Slider/Stepper Sync Tests

    func testSettingCurrentSize_updatesInternalState() {
        sut.currentSize = 85.0

        XCTAssertEqual(sut.currentSize, 85.0, "currentSize should update when set")
    }

    func testSettingCurrentSize_staysWithinBounds() {
        // Set value at lower bound
        sut.currentSize = testRange.lowerBound
        XCTAssertEqual(sut.currentSize, testRange.lowerBound, "Should accept lower bound")

        // Set value at upper bound
        sut.currentSize = testRange.upperBound
        XCTAssertEqual(sut.currentSize, testRange.upperBound, "Should accept upper bound")
    }

    func testSettingCurrentSize_multipleTimesInSequence() {
        sut.currentSize = 70.0
        XCTAssertEqual(sut.currentSize, 70.0)

        sut.currentSize = 90.0
        XCTAssertEqual(sut.currentSize, 90.0)

        sut.currentSize = 110.0
        XCTAssertEqual(sut.currentSize, 110.0)
    }

    // MARK: - onSizeChanged Callback Tests

    func testOnSizeChanged_emitsRoundedPercentages() {
        var receivedValues: [Double] = []
        sut.onSizeChanged = { value in
            receivedValues.append(value)
        }

        // Simulate keyboard adjustment (which goes through stepperChanged)
        simulateKeyDown(keyCode: 124) // Right arrow

        XCTAssertFalse(receivedValues.isEmpty, "Should have received at least one value")
        if let lastValue = receivedValues.last {
            XCTAssertEqual(lastValue, round(lastValue), "Emitted value should be rounded")
        }
    }

    func testOnSizeChanged_calledOnKeyboardAdjustment() {
        var callCount = 0
        sut.onSizeChanged = { _ in
            callCount += 1
        }

        simulateKeyDown(keyCode: 124) // Right arrow

        XCTAssertEqual(callCount, 1, "onSizeChanged should be called once per keyboard adjustment")
    }

    // MARK: - Keyboard Arrow Tests

    func testRightArrow_increasesValue() {
        let originalValue = sut.currentSize
        simulateKeyDown(keyCode: 124) // Right arrow

        XCTAssertEqual(sut.currentSize, originalValue + 1, "Right arrow should increase value by 1")
    }

    func testLeftArrow_decreasesValue() {
        let originalValue = sut.currentSize
        simulateKeyDown(keyCode: 123) // Left arrow

        XCTAssertEqual(sut.currentSize, originalValue - 1, "Left arrow should decrease value by 1")
    }

    func testUpArrow_increasesValue() {
        let originalValue = sut.currentSize
        simulateKeyDown(keyCode: 126) // Up arrow

        XCTAssertEqual(sut.currentSize, originalValue + 1, "Up arrow should increase value by 1")
    }

    func testDownArrow_decreasesValue() {
        let originalValue = sut.currentSize
        simulateKeyDown(keyCode: 125) // Down arrow

        XCTAssertEqual(sut.currentSize, originalValue - 1, "Down arrow should decrease value by 1")
    }

    func testKeyboardAdjustment_respectsUpperBound() {
        sut.currentSize = testRange.upperBound
        let originalValue = sut.currentSize

        simulateKeyDown(keyCode: 124) // Right arrow (increase)

        XCTAssertEqual(sut.currentSize, originalValue, "Should not exceed upper bound")
    }

    func testKeyboardAdjustment_respectsLowerBound() {
        sut.currentSize = testRange.lowerBound
        let originalValue = sut.currentSize

        simulateKeyDown(keyCode: 123) // Left arrow (decrease)

        XCTAssertEqual(sut.currentSize, originalValue, "Should not go below lower bound")
    }

    func testMultipleKeyPresses_accumulateCorrectly() {
        let startValue = sut.currentSize

        // Press right arrow 5 times
        for _ in 0 ..< 5 {
            simulateKeyDown(keyCode: 124)
        }

        XCTAssertEqual(sut.currentSize, startValue + 5, "Multiple right arrows should accumulate")

        // Press left arrow 3 times
        for _ in 0 ..< 3 {
            simulateKeyDown(keyCode: 123)
        }

        XCTAssertEqual(sut.currentSize, startValue + 2, "Should correctly handle mixed directions")
    }

    func testKeyboardAtBounds_emitsCallbackEvenWhenClamped() {
        sut.currentSize = testRange.upperBound
        var callbackCalled = false
        sut.onSizeChanged = { _ in
            callbackCalled = true
        }

        simulateKeyDown(keyCode: 124) // Right arrow at upper bound

        // Note: Behavior depends on implementation - if clamped before callback,
        // callback may or may not fire. This test documents expected behavior.
        // Based on the implementation, it will fire with the clamped value.
        XCTAssertTrue(callbackCalled, "Callback should still fire at bounds")
    }

    // MARK: - Stepper Click Tests

    func testStepperClickUp_increasesValue() {
        let originalValue = sut.currentSize
        simulateStepperClick(increment: true)

        XCTAssertEqual(sut.currentSize, originalValue + 1, "Stepper up click should increase value by 1")
    }

    func testStepperClickDown_decreasesValue() {
        let originalValue = sut.currentSize
        simulateStepperClick(increment: false)

        XCTAssertEqual(sut.currentSize, originalValue - 1, "Stepper down click should decrease value by 1")
    }

    func testStepperClick_firesOnSizeChangedCallback() {
        var receivedValue: Double?
        sut.onSizeChanged = { value in
            receivedValue = value
        }

        simulateStepperClick(increment: true)

        XCTAssertNotNil(receivedValue, "onSizeChanged should be called on stepper click")
        XCTAssertEqual(receivedValue, initialSize + 1, "Callback should receive the new value")
    }

    func testStepperClickAtUpperBound_clampsValue() {
        sut.currentSize = testRange.upperBound
        var receivedValue: Double?
        sut.onSizeChanged = { value in
            receivedValue = value
        }

        simulateStepperClick(increment: true)

        XCTAssertEqual(sut.currentSize, testRange.upperBound, "Value should stay at upper bound")
        XCTAssertEqual(receivedValue, testRange.upperBound, "Callback should receive clamped value")
    }

    func testStepperClickAtLowerBound_clampsValue() {
        sut.currentSize = testRange.lowerBound
        var receivedValue: Double?
        sut.onSizeChanged = { value in
            receivedValue = value
        }

        simulateStepperClick(increment: false)

        XCTAssertEqual(sut.currentSize, testRange.lowerBound, "Value should stay at lower bound")
        XCTAssertEqual(receivedValue, testRange.lowerBound, "Callback should receive clamped value")
    }

    // MARK: - Value Clamping Tests

    func testOnSizeChanged_receivesClampedValueAtUpperBound() {
        sut.currentSize = testRange.upperBound - 0.5
        var receivedValues: [Double] = []
        sut.onSizeChanged = { value in
            receivedValues.append(value)
        }

        // Try to increase past upper bound twice
        simulateKeyDown(keyCode: 124) // Right arrow
        simulateKeyDown(keyCode: 124) // Right arrow again

        // All received values should be at or below upper bound
        for value in receivedValues {
            XCTAssertLessThanOrEqual(value, testRange.upperBound, "Callback value should be clamped to upper bound")
        }
    }

    func testOnSizeChanged_receivesClampedValueAtLowerBound() {
        sut.currentSize = testRange.lowerBound + 0.5
        var receivedValues: [Double] = []
        sut.onSizeChanged = { value in
            receivedValues.append(value)
        }

        // Try to decrease past lower bound twice
        simulateKeyDown(keyCode: 123) // Left arrow
        simulateKeyDown(keyCode: 123) // Left arrow again

        // All received values should be at or above lower bound
        for value in receivedValues {
            XCTAssertGreaterThanOrEqual(value, testRange.lowerBound, "Callback value should be clamped to lower bound")
        }
    }

    func testOnSizeChanged_alwaysReceivesRoundedValues() {
        var receivedValues: [Double] = []
        sut.onSizeChanged = { value in
            receivedValues.append(value)
        }

        // Multiple interactions
        simulateKeyDown(keyCode: 124) // Right arrow
        simulateStepperClick(increment: true)
        simulateKeyDown(keyCode: 123) // Left arrow
        simulateStepperClick(increment: false)

        for value in receivedValues {
            XCTAssertEqual(value, round(value), "All callback values should be rounded integers")
        }
    }

    // MARK: - Intrinsic Content Size Tests

    func testIntrinsicContentSize_hasReasonableDimensions() {
        let size = sut.intrinsicContentSize

        XCTAssertGreaterThan(size.width, 0, "Width should be positive")
        XCTAssertGreaterThan(size.height, 0, "Height should be positive")
        XCTAssertLessThan(size.width, 500, "Width should be reasonable")
        XCTAssertLessThan(size.height, 100, "Height should be reasonable")
    }

    func testIntrinsicContentSize_isStable() {
        let size1 = sut.intrinsicContentSize
        sut.currentSize = 80.0
        let size2 = sut.intrinsicContentSize
        sut.currentSize = 110.0
        let size3 = sut.intrinsicContentSize

        XCTAssertEqual(size1, size2, "Size should not change when value changes")
        XCTAssertEqual(size2, size3, "Size should remain stable")
    }

    // MARK: - First Responder Tests

    func testAcceptsFirstResponder_returnsTrue() {
        XCTAssertTrue(sut.acceptsFirstResponder, "Should accept first responder for keyboard input")
    }

    // MARK: - Value Label Update Tests

    func testValueLabel_updatesAfterKeyboardInteraction() {
        let labelBefore = findValueLabel()?.stringValue
        simulateKeyDown(keyCode: 124) // Right arrow
        let labelAfter = findValueLabel()?.stringValue

        XCTAssertNotEqual(labelBefore, labelAfter, "Value label should update after keyboard interaction")
        XCTAssertEqual(labelAfter, "101%", "Value label should show new value with percent suffix")
    }

    func testValueLabel_updatesAfterStepperClick() {
        let labelBefore = findValueLabel()?.stringValue
        simulateStepperClick(increment: false)
        let labelAfter = findValueLabel()?.stringValue

        XCTAssertNotEqual(labelBefore, labelAfter, "Value label should update after stepper click")
        XCTAssertEqual(labelAfter, "99%", "Value label should show new value with percent suffix")
    }

    func testValueLabel_showsCorrectFormatAfterMultipleInteractions() {
        // Increase to 105
        for _ in 0 ..< 5 {
            simulateKeyDown(keyCode: 124)
        }

        let label = findValueLabel()?.stringValue
        XCTAssertEqual(label, "105%", "Value label should show current value with percent suffix")
    }

    func testValueLabel_initialValueShowsCorrectFormat() {
        let label = findValueLabel()?.stringValue
        XCTAssertEqual(label, "100%", "Initial value label should show initialSize with percent suffix")
    }

    func testValueLabel_atBoundsShowsCorrectFormat() {
        sut.currentSize = testRange.lowerBound
        let lowerLabel = findValueLabel()?.stringValue
        XCTAssertEqual(lowerLabel, "60%", "Lower bound should show correct label")

        sut.currentSize = testRange.upperBound
        let upperLabel = findValueLabel()?.stringValue
        XCTAssertEqual(upperLabel, "120%", "Upper bound should show correct label")
    }

    // MARK: - Slider Action Tests

    func testSliderDrag_updatesValueAndLabel() {
        var receivedValue: Double?
        sut.onSizeChanged = { value in
            receivedValue = value
        }

        simulateSliderDrag(to: 85.0)

        XCTAssertEqual(sut.currentSize, 85.0, "currentSize should update after slider drag")
        XCTAssertEqual(receivedValue, 85.0, "onSizeChanged should be called with new value")
        XCTAssertEqual(findValueLabel()?.stringValue, "85%", "Value label should update")
    }

    func testSliderDrag_roundsValue() {
        simulateSliderDrag(to: 85.7)

        // The slider rounds values to integers
        XCTAssertEqual(sut.currentSize, 86.0, "Slider should round to nearest integer")
        XCTAssertEqual(findValueLabel()?.stringValue, "86%", "Label should show rounded value")
    }

    func testSliderDrag_syncsStepper() {
        simulateSliderDrag(to: 90.0)

        guard let stepper = findStepper() else {
            XCTFail("Could not find stepper")
            return
        }

        XCTAssertEqual(stepper.doubleValue, 90.0, "Stepper should sync with slider value")
    }

    // MARK: - Helpers

    /// Finds the stepper control in the view hierarchy
    private func findStepper() -> NSStepper? {
        sut.subviews.compactMap { $0 as? NSStepper }.first
    }

    /// Finds the slider control in the view hierarchy
    private func findSlider() -> NSSlider? {
        sut.subviews.compactMap { $0 as? NSSlider }.first
    }

    /// Finds the value label (the one showing the percentage) in the view hierarchy
    private func findValueLabel() -> NSTextField? {
        // The value label has a larger font than min/max labels
        sut.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.font?.pointSize == 13 }
    }

    /// Simulates keyboard adjustment by directly calling keyDown
    /// This exercises the same code path as user keyboard input
    private func simulateKeyDown(keyCode: UInt16) {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: testWindow.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )!

        sut.keyDown(with: event)
    }

    /// Simulates clicking on the stepper by directly manipulating the stepper value
    /// and triggering the action. This is more robust than coordinate-based clicks.
    private func simulateStepperClick(increment: Bool) {
        guard let stepper = findStepper() else {
            XCTFail("Could not find stepper")
            return
        }

        // Directly adjust stepper value and trigger action via mouseDown
        // This mimics what the SizeSlider.mouseDown does
        let stepperMidY = stepper.frame.midY
        let clickY = increment ? stepperMidY + 5 : stepperMidY - 5
        let clickPoint = CGPoint(x: stepper.frame.midX, y: clickY)

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: clickPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: testWindow.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!

        sut.mouseDown(with: event)
    }

    /// Simulates slider drag by setting value and triggering action
    private func simulateSliderDrag(to value: Double) {
        guard let slider = findSlider() else {
            XCTFail("Could not find slider")
            return
        }

        slider.doubleValue = value
        // Trigger the action by sending action to target
        if let target = slider.target, let action = slider.action {
            _ = target.perform(action, with: slider)
        }
    }
}
