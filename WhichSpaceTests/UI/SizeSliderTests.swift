import Cocoa
import Testing
@testable import WhichSpace

@Suite("Size Slider")
@MainActor
struct SizeSliderTests {
    private let sut: SizeSlider
    private let testWindow: NSWindow
    private let testRange = 60.0 ... 120.0
    private let initialSize = 100.0

    init() {
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

    // MARK: - Initial State Tests

    @Test("Initial state current size matches initial value")
    func initialState_currentSizeMatchesInitialValue() {
        #expect(sut.currentSize == initialSize, "Initial currentSize should match initialSize")
    }

    @Test("Initial state with different initial size")
    func initialState_withDifferentInitialSize() {
        let customSize = 80.0
        let customSut = SizeSlider(initialSize: customSize, range: testRange)

        #expect(customSut.currentSize == customSize, "currentSize should match custom initial size")
    }

    // MARK: - Slider/Stepper Sync Tests

    @Test("Setting current size updates internal state")
    func settingCurrentSize_updatesInternalState() {
        sut.currentSize = 85.0

        #expect(sut.currentSize == 85.0, "currentSize should update when set")
    }

    @Test("Setting current size stays within bounds")
    func settingCurrentSize_staysWithinBounds() {
        // Set value at lower bound
        sut.currentSize = testRange.lowerBound
        #expect(sut.currentSize == testRange.lowerBound, "Should accept lower bound")

        // Set value at upper bound
        sut.currentSize = testRange.upperBound
        #expect(sut.currentSize == testRange.upperBound, "Should accept upper bound")
    }

    @Test("Setting current size multiple times in sequence")
    func settingCurrentSize_multipleTimesInSequence() {
        sut.currentSize = 70.0
        #expect(sut.currentSize == 70.0)

        sut.currentSize = 90.0
        #expect(sut.currentSize == 90.0)

        sut.currentSize = 110.0
        #expect(sut.currentSize == 110.0)
    }

    // MARK: - onSizeChanged Callback Tests

    @Test("onSizeChanged emits rounded percentages")
    func onSizeChanged_emitsRoundedPercentages() {
        var receivedValues: [Double] = []
        sut.onSizeChanged = { value in
            receivedValues.append(value)
        }

        // Simulate keyboard adjustment (which goes through stepperChanged)
        simulateKeyDown(keyCode: 124) // Right arrow

        #expect(!receivedValues.isEmpty, "Should have received at least one value")
        if let lastValue = receivedValues.last {
            #expect(lastValue == round(lastValue), "Emitted value should be rounded")
        }
    }

    @Test("onSizeChanged called on keyboard adjustment")
    func onSizeChanged_calledOnKeyboardAdjustment() {
        var callCount = 0
        sut.onSizeChanged = { _ in
            callCount += 1
        }

        simulateKeyDown(keyCode: 124) // Right arrow

        #expect(callCount == 1, "onSizeChanged should be called once per keyboard adjustment")
    }

    // MARK: - Keyboard Arrow Tests

    @Test("Right arrow increases value")
    func rightArrow_increasesValue() {
        let originalValue = sut.currentSize
        simulateKeyDown(keyCode: 124) // Right arrow

        #expect(sut.currentSize == originalValue + 1, "Right arrow should increase value by 1")
    }

    @Test("Left arrow decreases value")
    func leftArrow_decreasesValue() {
        let originalValue = sut.currentSize
        simulateKeyDown(keyCode: 123) // Left arrow

        #expect(sut.currentSize == originalValue - 1, "Left arrow should decrease value by 1")
    }

    @Test("Up arrow increases value")
    func upArrow_increasesValue() {
        let originalValue = sut.currentSize
        simulateKeyDown(keyCode: 126) // Up arrow

        #expect(sut.currentSize == originalValue + 1, "Up arrow should increase value by 1")
    }

    @Test("Down arrow decreases value")
    func downArrow_decreasesValue() {
        let originalValue = sut.currentSize
        simulateKeyDown(keyCode: 125) // Down arrow

        #expect(sut.currentSize == originalValue - 1, "Down arrow should decrease value by 1")
    }

    @Test("Keyboard adjustment respects upper bound")
    func keyboardAdjustment_respectsUpperBound() {
        sut.currentSize = testRange.upperBound
        let originalValue = sut.currentSize

        simulateKeyDown(keyCode: 124) // Right arrow (increase)

        #expect(sut.currentSize == originalValue, "Should not exceed upper bound")
    }

    @Test("Keyboard adjustment respects lower bound")
    func keyboardAdjustment_respectsLowerBound() {
        sut.currentSize = testRange.lowerBound
        let originalValue = sut.currentSize

        simulateKeyDown(keyCode: 123) // Left arrow (decrease)

        #expect(sut.currentSize == originalValue, "Should not go below lower bound")
    }

    @Test("Multiple key presses accumulate correctly")
    func multipleKeyPresses_accumulateCorrectly() {
        let startValue = sut.currentSize

        // Press right arrow 5 times
        for _ in 0 ..< 5 {
            simulateKeyDown(keyCode: 124)
        }

        #expect(sut.currentSize == startValue + 5, "Multiple right arrows should accumulate")

        // Press left arrow 3 times
        for _ in 0 ..< 3 {
            simulateKeyDown(keyCode: 123)
        }

        #expect(sut.currentSize == startValue + 2, "Should correctly handle mixed directions")
    }

    @Test("Keyboard at bounds emits callback even when clamped")
    func keyboardAtBounds_emitsCallbackEvenWhenClamped() {
        sut.currentSize = testRange.upperBound
        var callbackCalled = false
        sut.onSizeChanged = { _ in
            callbackCalled = true
        }

        simulateKeyDown(keyCode: 124) // Right arrow at upper bound

        // Note: Behavior depends on implementation - if clamped before callback,
        // callback may or may not fire. This test documents expected behavior.
        // Based on the implementation, it will fire with the clamped value.
        #expect(callbackCalled, "Callback should still fire at bounds")
    }

    // MARK: - Stepper Click Tests

    @Test("Stepper click up increases value")
    func stepperClickUp_increasesValue() {
        let originalValue = sut.currentSize
        simulateStepperClick(increment: true)

        #expect(sut.currentSize == originalValue + 1, "Stepper up click should increase value by 1")
    }

    @Test("Stepper click down decreases value")
    func stepperClickDown_decreasesValue() {
        let originalValue = sut.currentSize
        simulateStepperClick(increment: false)

        #expect(sut.currentSize == originalValue - 1, "Stepper down click should decrease value by 1")
    }

    @Test("Stepper click fires onSizeChanged callback")
    func stepperClick_firesOnSizeChangedCallback() {
        var receivedValue: Double?
        sut.onSizeChanged = { value in
            receivedValue = value
        }

        simulateStepperClick(increment: true)

        #expect(receivedValue != nil, "onSizeChanged should be called on stepper click")
        #expect(receivedValue == initialSize + 1, "Callback should receive the new value")
    }

    @Test("Stepper click at upper bound clamps value")
    func stepperClickAtUpperBound_clampsValue() {
        sut.currentSize = testRange.upperBound
        var receivedValue: Double?
        sut.onSizeChanged = { value in
            receivedValue = value
        }

        simulateStepperClick(increment: true)

        #expect(sut.currentSize == testRange.upperBound, "Value should stay at upper bound")
        #expect(receivedValue == testRange.upperBound, "Callback should receive clamped value")
    }

    @Test("Stepper click at lower bound clamps value")
    func stepperClickAtLowerBound_clampsValue() {
        sut.currentSize = testRange.lowerBound
        var receivedValue: Double?
        sut.onSizeChanged = { value in
            receivedValue = value
        }

        simulateStepperClick(increment: false)

        #expect(sut.currentSize == testRange.lowerBound, "Value should stay at lower bound")
        #expect(receivedValue == testRange.lowerBound, "Callback should receive clamped value")
    }

    // MARK: - Value Clamping Tests

    @Test("onSizeChanged receives clamped value at upper bound")
    func onSizeChanged_receivesClampedValueAtUpperBound() {
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
            #expect(value <= testRange.upperBound, "Callback value should be clamped to upper bound")
        }
    }

    @Test("onSizeChanged receives clamped value at lower bound")
    func onSizeChanged_receivesClampedValueAtLowerBound() {
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
            #expect(value >= testRange.lowerBound, "Callback value should be clamped to lower bound")
        }
    }

    @Test("onSizeChanged always receives rounded values")
    func onSizeChanged_alwaysReceivesRoundedValues() {
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
            #expect(value == round(value), "All callback values should be rounded integers")
        }
    }

    // MARK: - Intrinsic Content Size Tests

    @Test("Intrinsic content size has reasonable dimensions")
    func intrinsicContentSize_hasReasonableDimensions() {
        let size = sut.intrinsicContentSize

        #expect(size.width > 0, "Width should be positive")
        #expect(size.height > 0, "Height should be positive")
        #expect(size.width < 500, "Width should be reasonable")
        #expect(size.height < 100, "Height should be reasonable")
    }

    @Test("Intrinsic content size is stable")
    func intrinsicContentSize_isStable() {
        let size1 = sut.intrinsicContentSize
        sut.currentSize = 80.0
        let size2 = sut.intrinsicContentSize
        sut.currentSize = 110.0
        let size3 = sut.intrinsicContentSize

        #expect(size1 == size2, "Size should not change when value changes")
        #expect(size2 == size3, "Size should remain stable")
    }

    // MARK: - First Responder Tests

    @Test("Accepts first responder returns true")
    func acceptsFirstResponder_returnsTrue() {
        #expect(sut.acceptsFirstResponder, "Should accept first responder for keyboard input")
    }

    // MARK: - Value Label Update Tests

    @Test("Value label updates after keyboard interaction")
    func valueLabel_updatesAfterKeyboardInteraction() {
        let labelBefore = findValueLabel()?.stringValue
        simulateKeyDown(keyCode: 124) // Right arrow
        let labelAfter = findValueLabel()?.stringValue

        #expect(labelBefore != labelAfter, "Value label should update after keyboard interaction")
        #expect(labelAfter == "101%", "Value label should show new value with percent suffix")
    }

    @Test("Value label updates after stepper click")
    func valueLabel_updatesAfterStepperClick() {
        let labelBefore = findValueLabel()?.stringValue
        simulateStepperClick(increment: false)
        let labelAfter = findValueLabel()?.stringValue

        #expect(labelBefore != labelAfter, "Value label should update after stepper click")
        #expect(labelAfter == "99%", "Value label should show new value with percent suffix")
    }

    @Test("Value label shows correct format after multiple interactions")
    func valueLabel_showsCorrectFormatAfterMultipleInteractions() {
        // Increase to 105
        for _ in 0 ..< 5 {
            simulateKeyDown(keyCode: 124)
        }

        let label = findValueLabel()?.stringValue
        #expect(label == "105%", "Value label should show current value with percent suffix")
    }

    @Test("Value label initial value shows correct format")
    func valueLabel_initialValueShowsCorrectFormat() {
        let label = findValueLabel()?.stringValue
        #expect(label == "100%", "Initial value label should show initialSize with percent suffix")
    }

    @Test("Value label at bounds shows correct format")
    func valueLabel_atBoundsShowsCorrectFormat() {
        sut.currentSize = testRange.lowerBound
        let lowerLabel = findValueLabel()?.stringValue
        #expect(lowerLabel == "60%", "Lower bound should show correct label")

        sut.currentSize = testRange.upperBound
        let upperLabel = findValueLabel()?.stringValue
        #expect(upperLabel == "120%", "Upper bound should show correct label")
    }

    // MARK: - Slider Action Tests

    @Test("Slider drag updates value and label")
    func sliderDrag_updatesValueAndLabel() {
        var receivedValue: Double?
        sut.onSizeChanged = { value in
            receivedValue = value
        }

        simulateSliderDrag(to: 85.0)

        #expect(sut.currentSize == 85.0, "currentSize should update after slider drag")
        #expect(receivedValue == 85.0, "onSizeChanged should be called with new value")
        #expect(findValueLabel()?.stringValue == "85%", "Value label should update")
    }

    @Test("Slider drag rounds value")
    func sliderDrag_roundsValue() {
        simulateSliderDrag(to: 85.7)

        // The slider rounds values to integers
        #expect(sut.currentSize == 86.0, "Slider should round to nearest integer")
        #expect(findValueLabel()?.stringValue == "86%", "Label should show rounded value")
    }

    @Test("Slider drag syncs stepper")
    func sliderDrag_syncsStepper() {
        simulateSliderDrag(to: 90.0)

        guard let stepper = findStepper() else {
            Issue.record("Could not find stepper")
            return
        }

        #expect(stepper.doubleValue == 90.0, "Stepper should sync with slider value")
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
            Issue.record("Could not find stepper")
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
            Issue.record("Could not find slider")
            return
        }

        slider.doubleValue = value
        // Trigger the action by sending action to target
        if let target = slider.target, let action = slider.action {
            _ = target.perform(action, with: slider)
        }
    }
}
