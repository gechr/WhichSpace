import Cocoa
import XCTest
@testable import WhichSpace

@MainActor
final class StylePickerTests: XCTestCase {
    private var sut: StylePicker!

    override func setUp() {
        super.setUp()
        sut = StylePicker(style: .square)
        sut.frame = NSRect(origin: .zero, size: sut.intrinsicContentSize)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - onSelected Tests

    func testMouseUp_triggersOnSelected() {
        var onSelectedCalled = false
        sut.onSelected = {
            onSelectedCalled = true
        }

        simulateMouseUp(at: CGPoint(x: sut.bounds.midX, y: sut.bounds.midY))

        XCTAssertTrue(onSelectedCalled, "mouseUp should trigger onSelected callback")
    }

    func testMouseUp_triggersOnSelectedForEachStyle() {
        for style in IconStyle.allCases {
            let stylePicker = StylePicker(style: style)
            stylePicker.frame = NSRect(origin: .zero, size: stylePicker.intrinsicContentSize)

            var onSelectedCalled = false
            stylePicker.onSelected = {
                onSelectedCalled = true
            }

            simulateMouseUp(on: stylePicker, at: CGPoint(x: stylePicker.bounds.midX, y: stylePicker.bounds.midY))

            XCTAssertTrue(onSelectedCalled, "mouseUp should trigger onSelected for style \(style.rawValue)")
        }
    }

    func testMouseUp_withNilCallback_doesNotCrash() {
        sut.onSelected = nil

        // Should not crash
        simulateMouseUp(at: CGPoint(x: sut.bounds.midX, y: sut.bounds.midY))
    }

    // MARK: - isChecked Tests

    func testIsChecked_defaultsToFalse() {
        let stylePicker = StylePicker(style: .circle)
        XCTAssertFalse(stylePicker.isChecked, "isChecked should default to false")
    }

    func testSettingIsChecked_toTrue_updatesProperty() {
        sut.isChecked = false

        sut.isChecked = true

        XCTAssertTrue(sut.isChecked, "Setting isChecked to true should update the property")
    }

    func testSettingIsChecked_toFalse_updatesProperty() {
        sut.isChecked = true

        sut.isChecked = false

        XCTAssertFalse(sut.isChecked, "Setting isChecked to false should update the property")
    }

    func testSettingIsChecked_togglesCorrectly() {
        XCTAssertFalse(sut.isChecked)

        sut.isChecked = true
        XCTAssertTrue(sut.isChecked)

        sut.isChecked = false
        XCTAssertFalse(sut.isChecked)

        sut.isChecked = true
        XCTAssertTrue(sut.isChecked)
    }

    func testIsChecked_canDrawWhenChecked() {
        // Verify the view can draw without crashing when checked
        sut.isChecked = true
        sut.frame = NSRect(origin: .zero, size: sut.intrinsicContentSize)

        // This should not crash - drawing with isChecked = true shows checkmark
        sut.display()

        XCTAssertTrue(sut.isChecked)
    }

    func testIsChecked_canDrawWhenUnchecked() {
        // Verify the view can draw without crashing when unchecked
        sut.isChecked = false
        sut.frame = NSRect(origin: .zero, size: sut.intrinsicContentSize)

        // This should not crash - drawing with isChecked = false hides checkmark
        sut.display()

        XCTAssertFalse(sut.isChecked)
    }

    // MARK: - intrinsicContentSize Tests

    func testIntrinsicContentSize_isStable() {
        let size1 = sut.intrinsicContentSize
        let size2 = sut.intrinsicContentSize
        let size3 = sut.intrinsicContentSize

        XCTAssertEqual(size1, size2, "intrinsicContentSize should be stable")
        XCTAssertEqual(size2, size3, "intrinsicContentSize should remain stable across calls")
    }

    func testIntrinsicContentSize_unchangedByIsChecked() {
        let sizeUnchecked = sut.intrinsicContentSize

        sut.isChecked = true
        let sizeChecked = sut.intrinsicContentSize

        XCTAssertEqual(sizeUnchecked, sizeChecked, "isChecked should not affect intrinsicContentSize")
    }

    func testIntrinsicContentSize_unchangedByCustomColors() {
        let sizeBefore = sut.intrinsicContentSize

        sut.customColors = SpaceColors(foreground: .red, background: .blue)
        let sizeAfter = sut.intrinsicContentSize

        XCTAssertEqual(sizeBefore, sizeAfter, "customColors should not affect intrinsicContentSize")
    }

    func testIntrinsicContentSize_unchangedByDarkMode() {
        let sizeBefore = sut.intrinsicContentSize

        sut.darkMode = true
        let sizeAfter = sut.intrinsicContentSize

        XCTAssertEqual(sizeBefore, sizeAfter, "darkMode should not affect intrinsicContentSize")
    }

    func testIntrinsicContentSize_unchangedByPreviewNumber() {
        let sizeBefore = sut.intrinsicContentSize

        sut.previewNumber = "99"
        let sizeAfter = sut.intrinsicContentSize

        XCTAssertEqual(sizeBefore, sizeAfter, "previewNumber should not affect intrinsicContentSize")
    }

    func testIntrinsicContentSize_consistentAcrossStyles() {
        var sizes: [CGSize] = []

        for style in IconStyle.allCases {
            let stylePicker = StylePicker(style: style)
            sizes.append(stylePicker.intrinsicContentSize)
        }

        // All sizes should be the same
        let firstSize = sizes[0]
        for (index, size) in sizes.enumerated() {
            XCTAssertEqual(
                size,
                firstSize,
                "All styles should have same intrinsicContentSize, but \(IconStyle.allCases[index].rawValue) differs"
            )
        }
    }

    func testIntrinsicContentSize_hasExpectedDimensions() {
        let size = sut.intrinsicContentSize

        // Based on the implementation: width = 180, height = Layout.statusItemHeight (22)
        XCTAssertEqual(size.width, 180, "Width should be 180")
        XCTAssertEqual(size.height, Layout.statusItemHeight, "Height should match statusItemHeight")
    }

    // MARK: - Configuration Properties Tests

    func testCustomColors_canBeSetAndRead() {
        let colors = SpaceColors(foreground: .systemGreen, background: .systemPurple)
        sut.customColors = colors

        XCTAssertEqual(sut.customColors?.foreground, colors.foreground)
        XCTAssertEqual(sut.customColors?.background, colors.background)
    }

    func testDarkMode_canBeSetAndRead() {
        sut.darkMode = false
        XCTAssertFalse(sut.darkMode)

        sut.darkMode = true
        XCTAssertTrue(sut.darkMode)
    }

    func testPreviewNumber_canBeSetAndRead() {
        sut.previewNumber = "5"
        XCTAssertEqual(sut.previewNumber, "5")

        sut.previewNumber = "F"
        XCTAssertEqual(sut.previewNumber, "F")
    }

    func testPreviewNumber_defaultsToOne() {
        let stylePicker = StylePicker(style: .square)
        XCTAssertEqual(stylePicker.previewNumber, "1", "previewNumber should default to '1'")
    }

    // MARK: - Style Initialization Tests

    func testInit_withDifferentStyles() {
        for style in IconStyle.allCases {
            let stylePicker = StylePicker(style: style)

            // View should be created successfully
            XCTAssertNotNil(stylePicker, "Should create view for style \(style.rawValue)")

            // Should have valid intrinsic size
            let size = stylePicker.intrinsicContentSize
            XCTAssertGreaterThan(size.width, 0, "Width should be positive for style \(style.rawValue)")
            XCTAssertGreaterThan(size.height, 0, "Height should be positive for style \(style.rawValue)")
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
