import Cocoa
import Testing
@testable import WhichSpace

@Suite("Style Picker")
@MainActor
struct StylePickerTests {
    private let sut: StylePicker

    init() {
        sut = StylePicker(style: .square)
        sut.frame = NSRect(origin: .zero, size: sut.intrinsicContentSize)
    }

    // MARK: - onSelected Tests

    @Test("mouseUp triggers onSelected")
    func mouseUp_triggersOnSelected() {
        var onSelectedCalled = false
        sut.onSelected = {
            onSelectedCalled = true
        }

        simulateMouseUp(at: CGPoint(x: sut.bounds.midX, y: sut.bounds.midY))

        #expect(onSelectedCalled, "mouseUp should trigger onSelected callback")
    }

    @Test("mouseUp triggers onSelected for each style")
    func mouseUp_triggersOnSelectedForEachStyle() {
        for style in IconStyle.allCases {
            let stylePicker = StylePicker(style: style)
            stylePicker.frame = NSRect(origin: .zero, size: stylePicker.intrinsicContentSize)

            var onSelectedCalled = false
            stylePicker.onSelected = {
                onSelectedCalled = true
            }

            simulateMouseUp(on: stylePicker, at: CGPoint(x: stylePicker.bounds.midX, y: stylePicker.bounds.midY))

            #expect(onSelectedCalled, "mouseUp should trigger onSelected for style \(style.rawValue)")
        }
    }

    @Test("mouseUp with nil callback does not crash")
    func mouseUp_withNilCallback_doesNotCrash() {
        sut.onSelected = nil

        // Should not crash
        simulateMouseUp(at: CGPoint(x: sut.bounds.midX, y: sut.bounds.midY))
    }

    // MARK: - isChecked Tests

    @Test("isChecked defaults to false")
    func isChecked_defaultsToFalse() {
        let stylePicker = StylePicker(style: .circle)
        #expect(!stylePicker.isChecked, "isChecked should default to false")
    }

    @Test("setting isChecked to true updates property")
    func settingIsChecked_toTrue_updatesProperty() {
        sut.isChecked = false

        sut.isChecked = true

        #expect(sut.isChecked, "Setting isChecked to true should update the property")
    }

    @Test("setting isChecked to false updates property")
    func settingIsChecked_toFalse_updatesProperty() {
        sut.isChecked = true

        sut.isChecked = false

        #expect(!sut.isChecked, "Setting isChecked to false should update the property")
    }

    @Test("setting isChecked toggles correctly")
    func settingIsChecked_togglesCorrectly() {
        #expect(!sut.isChecked)

        sut.isChecked = true
        #expect(sut.isChecked)

        sut.isChecked = false
        #expect(!sut.isChecked)

        sut.isChecked = true
        #expect(sut.isChecked)
    }

    @Test("isChecked can draw when checked")
    func isChecked_canDrawWhenChecked() {
        // Verify the view can draw without crashing when checked
        sut.isChecked = true
        sut.frame = NSRect(origin: .zero, size: sut.intrinsicContentSize)

        // This should not crash - drawing with isChecked = true shows checkmark
        sut.display()

        #expect(sut.isChecked)
    }

    @Test("isChecked can draw when unchecked")
    func isChecked_canDrawWhenUnchecked() {
        // Verify the view can draw without crashing when unchecked
        sut.isChecked = false
        sut.frame = NSRect(origin: .zero, size: sut.intrinsicContentSize)

        // This should not crash - drawing with isChecked = false hides checkmark
        sut.display()

        #expect(!sut.isChecked)
    }

    // MARK: - intrinsicContentSize Tests

    @Test("intrinsicContentSize is stable")
    func intrinsicContentSize_isStable() {
        let size1 = sut.intrinsicContentSize
        let size2 = sut.intrinsicContentSize
        let size3 = sut.intrinsicContentSize

        #expect(size1 == size2, "intrinsicContentSize should be stable")
        #expect(size2 == size3, "intrinsicContentSize should remain stable across calls")
    }

    @Test("intrinsicContentSize unchanged by isChecked")
    func intrinsicContentSize_unchangedByIsChecked() {
        let sizeUnchecked = sut.intrinsicContentSize

        sut.isChecked = true
        let sizeChecked = sut.intrinsicContentSize

        #expect(sizeUnchecked == sizeChecked, "isChecked should not affect intrinsicContentSize")
    }

    @Test("intrinsicContentSize unchanged by custom colors")
    func intrinsicContentSize_unchangedByCustomColors() {
        let sizeBefore = sut.intrinsicContentSize

        sut.customColors = SpaceColors(foreground: .red, background: .blue)
        let sizeAfter = sut.intrinsicContentSize

        #expect(sizeBefore == sizeAfter, "customColors should not affect intrinsicContentSize")
    }

    @Test("intrinsicContentSize unchanged by dark mode")
    func intrinsicContentSize_unchangedByDarkMode() {
        let sizeBefore = sut.intrinsicContentSize

        sut.darkMode = true
        let sizeAfter = sut.intrinsicContentSize

        #expect(sizeBefore == sizeAfter, "darkMode should not affect intrinsicContentSize")
    }

    @Test("intrinsicContentSize unchanged by preview number")
    func intrinsicContentSize_unchangedByPreviewNumber() {
        let sizeBefore = sut.intrinsicContentSize

        sut.previewNumber = "99"
        let sizeAfter = sut.intrinsicContentSize

        #expect(sizeBefore == sizeAfter, "previewNumber should not affect intrinsicContentSize")
    }

    @Test("intrinsicContentSize consistent across styles")
    func intrinsicContentSize_consistentAcrossStyles() {
        var sizes: [CGSize] = []

        for style in IconStyle.allCases {
            let stylePicker = StylePicker(style: style)
            sizes.append(stylePicker.intrinsicContentSize)
        }

        // All sizes should be the same
        let firstSize = sizes[0]
        for (index, size) in sizes.enumerated() {
            #expect(
                size == firstSize,
                "All styles should have same intrinsicContentSize, but \(IconStyle.allCases[index].rawValue) differs"
            )
        }
    }

    @Test("intrinsicContentSize has expected dimensions")
    func intrinsicContentSize_hasExpectedDimensions() {
        let size = sut.intrinsicContentSize

        // Based on the implementation: width = 180, height = Layout.statusItemHeight (22)
        #expect(size.width == 180, "Width should be 180")
        #expect(size.height == 22.0, "Height should match statusItemHeight")
    }

    // MARK: - Configuration Properties Tests

    @Test("customColors can be set and read")
    func customColors_canBeSetAndRead() {
        let colors = SpaceColors(foreground: .systemGreen, background: .systemPurple)
        sut.customColors = colors

        #expect(sut.customColors?.foreground == colors.foreground)
        #expect(sut.customColors?.background == colors.background)
    }

    @Test("darkMode can be set and read")
    func darkMode_canBeSetAndRead() {
        sut.darkMode = false
        #expect(!sut.darkMode)

        sut.darkMode = true
        #expect(sut.darkMode)
    }

    @Test("previewNumber can be set and read")
    func previewNumber_canBeSetAndRead() {
        sut.previewNumber = "5"
        #expect(sut.previewNumber == "5")

        sut.previewNumber = "F"
        #expect(sut.previewNumber == "F")
    }

    @Test("previewNumber defaults to one")
    func previewNumber_defaultsToOne() {
        let stylePicker = StylePicker(style: .square)
        #expect(stylePicker.previewNumber == "1", "previewNumber should default to '1'")
    }

    // MARK: - sizeScale Tests

    @Test("sizeScale defaults to Layout default")
    func sizeScale_defaultsToLayoutDefault() {
        let stylePicker = StylePicker(style: .square)
        #expect(
            stylePicker.sizeScale == Layout.defaultSizeScale,
            "sizeScale should default to Layout.defaultSizeScale"
        )
    }

    @Test("sizeScale can be set and read")
    func sizeScale_canBeSetAndRead() {
        sut.sizeScale = 80.0
        #expect(sut.sizeScale == 80.0)

        sut.sizeScale = 120.0
        #expect(sut.sizeScale == 120.0)
    }

    @Test("sizeScale unchanged by other properties")
    func sizeScale_unchangedByOtherProperties() {
        sut.sizeScale = 75.0

        sut.customColors = SpaceColors(foreground: .red, background: .blue)
        sut.darkMode = true
        sut.previewNumber = "5"
        sut.isChecked = true

        #expect(sut.sizeScale == 75.0, "sizeScale should not be affected by other property changes")
    }

    @Test("intrinsicContentSize unchanged by sizeScale")
    func intrinsicContentSize_unchangedBySizeScale() {
        let sizeBefore = sut.intrinsicContentSize

        sut.sizeScale = 50.0
        let sizeAfter = sut.intrinsicContentSize

        #expect(sizeBefore == sizeAfter, "sizeScale should not affect intrinsicContentSize")
    }

    @Test("sizeScale can draw with different scales")
    func sizeScale_canDrawWithDifferentScales() {
        // Verify the view can draw without crashing at different scales
        for scale in [50.0, 75.0, 100.0, 125.0, 150.0] {
            sut.sizeScale = scale
            sut.frame = NSRect(origin: .zero, size: sut.intrinsicContentSize)

            // This should not crash
            sut.display()

            #expect(sut.sizeScale == scale)
        }
    }

    // MARK: - Style Initialization Tests

    @Test("init with different styles")
    func init_withDifferentStyles() {
        for style in IconStyle.allCases {
            let stylePicker = StylePicker(style: style)

            // View should be created successfully
            #expect(stylePicker != nil, "Should create view for style \(style.rawValue)")

            // Should have valid intrinsic size
            let size = stylePicker.intrinsicContentSize
            #expect(size.width > 0, "Width should be positive for style \(style.rawValue)")
            #expect(size.height > 0, "Height should be positive for style \(style.rawValue)")
        }
    }

    // MARK: - Helpers

    private func simulateMouseUp(at point: CGPoint) {
        simulateMouseUp(on: sut, at: point)
    }

    private func simulateMouseUp(on view: StylePicker, at point: CGPoint) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: view.intrinsicContentSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view

        let event = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!

        view.mouseUp(with: event)
    }
}
