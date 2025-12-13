import Defaults
import XCTest
@testable import WhichSpace

final class SpaceIconGeneratorTests: IsolatedDefaultsTestCase {
    // MARK: - Image Size Tests

    func testGeneratedIconHasExpectedSize() {
        let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        XCTAssertEqual(icon.size, Layout.statusItemSize)
    }

    func testAllStylesGenerateCorrectSize() {
        for style in IconStyle.allCases {
            let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, style: style)
            XCTAssertEqual(
                icon.size,
                Layout.statusItemSize,
                "Style \(style.rawValue) should produce correct size"
            )
        }
    }

    func testMultiDigitNumbersGenerateCorrectSize() {
        let singleDigit = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        let doubleDigit = SpaceIconGenerator.generateIcon(for: "12", darkMode: true)
        let tripleDigit = SpaceIconGenerator.generateIcon(for: "123", darkMode: true)

        XCTAssertEqual(singleDigit.size, Layout.statusItemSize)
        XCTAssertEqual(doubleDigit.size, Layout.statusItemSize)
        XCTAssertEqual(tripleDigit.size, Layout.statusItemSize)
    }

    // MARK: - Scale Tests

    // Note: These tests verify the container size is constant. The scale affects
    // drawn content only, not the image dimensions.

    func testIconSizeUnchangedAtDefaultScale() {
        // Default scale - image size should be statusItemSize
        let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        XCTAssertEqual(icon.size, Layout.statusItemSize)
    }

    func testSizeScaleRangeIsValid() {
        // Verify the range is sensible
        XCTAssertLessThan(Layout.sizeScaleRange.lowerBound, Layout.defaultSizeScale)
        XCTAssertGreaterThan(Layout.sizeScaleRange.upperBound, Layout.defaultSizeScale)
        XCTAssertEqual(Layout.defaultSizeScale, 100.0)
    }

    // MARK: - Dark/Light Mode Tests

    func testDarkModeProducesValidImage() {
        let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        XCTAssertFalse(icon.size.width <= 0)
        XCTAssertFalse(icon.size.height <= 0)
        XCTAssertNotNil(icon.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func testLightModeProducesValidImage() {
        let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: false)
        XCTAssertFalse(icon.size.width <= 0)
        XCTAssertFalse(icon.size.height <= 0)
        XCTAssertNotNil(icon.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func testDarkAndLightModeProduceDifferentImages() {
        let darkIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        let lightIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: false)

        let darkData = darkIcon.tiffRepresentation
        let lightData = lightIcon.tiffRepresentation

        XCTAssertNotNil(darkData)
        XCTAssertNotNil(lightData)
        XCTAssertNotEqual(darkData, lightData, "Dark and light mode icons should differ")
    }

    // MARK: - Custom Colors Tests

    func testCustomColorsApplied() {
        let customColors = SpaceColors(foreground: .systemRed, background: .systemBlue)
        let icon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors
        )

        XCTAssertEqual(icon.size, Layout.statusItemSize)
        XCTAssertNotNil(icon.tiffRepresentation)
    }

    func testCustomColorsDifferFromDefault() {
        let customColors = SpaceColors(foreground: .systemRed, background: .systemBlue)

        let defaultIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        let customIcon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors
        )

        let defaultData = defaultIcon.tiffRepresentation
        let customData = customIcon.tiffRepresentation

        XCTAssertNotNil(defaultData)
        XCTAssertNotNil(customData)
        XCTAssertNotEqual(defaultData, customData, "Custom colors should produce different image")
    }

    func testCustomColorsContainExpectedPixels() {
        let foreground = NSColor.red
        let background = NSColor.blue
        let customColors = SpaceColors(foreground: foreground, background: background)

        let icon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors,
            style: .square
        )

        // Sample the center pixel (should be within the background shape)
        let centerX = Int(icon.size.width / 2)
        let centerY = Int(icon.size.height / 2)
        let centerColor = samplePixelColor(from: icon, at: CGPoint(x: centerX, y: centerY))

        XCTAssertNotNil(centerColor, "Should be able to sample center pixel")

        // The center should have some non-transparent content
        if let color = centerColor {
            XCTAssertGreaterThan(color.alphaComponent, 0.5, "Center should have visible content")
        }
    }

    func testBackgroundColorAppearsInImage() {
        // Use a distinctive background color
        let customColors = SpaceColors(
            foreground: .black,
            background: NSColor(red: 1.0, green: 0, blue: 0, alpha: 1.0) // Pure red
        )

        let icon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors,
            style: .square
        )

        // Check that the image contains red pixels
        let hasRedPixels = imageContainsColor(icon, targetRed: 1.0, targetGreen: 0, targetBlue: 0, tolerance: 0.1)
        XCTAssertTrue(hasRedPixels, "Background color should appear in the generated icon")
    }

    func testForegroundColorAppearsInImage() {
        // Use a distinctive foreground color on contrasting background
        let customColors = SpaceColors(
            foreground: NSColor(red: 0, green: 1.0, blue: 0, alpha: 1.0), // Pure green
            background: .black
        )

        let icon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors,
            style: .square
        )

        // Check that the image contains green pixels (the text)
        let hasGreenPixels = imageContainsColor(icon, targetRed: 0, targetGreen: 1.0, targetBlue: 0, tolerance: 0.1)
        XCTAssertTrue(hasGreenPixels, "Foreground color should appear in the generated icon")
    }

    // MARK: - Symbol Tests

    func testSymbolIconHasExpectedSize() {
        let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: "star.fill", darkMode: true)
        XCTAssertEqual(icon.size, Layout.statusItemSize)
    }

    func testSymbolWithCustomColors() {
        let customColors = SpaceColors(foreground: .systemGreen, background: .clear)
        let icon = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "star.fill",
            darkMode: true,
            customColors: customColors
        )

        XCTAssertEqual(icon.size, Layout.statusItemSize)
        XCTAssertNotNil(icon.tiffRepresentation)
    }

    func testInvalidSymbolFallsBackToQuestionMark() {
        let icon = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "this.symbol.definitely.does.not.exist",
            darkMode: true
        )

        XCTAssertEqual(icon.size, Layout.statusItemSize)
        XCTAssertNotNil(icon.tiffRepresentation)
    }

    // MARK: - Emoji Tests

    func testEmojiIconHasExpectedSize() {
        let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: "😀", darkMode: true)
        XCTAssertEqual(icon.size, Layout.statusItemSize)
    }

    func testEmojiIconProducesValidImage() {
        let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: "👋", darkMode: true)
        XCTAssertNotNil(icon.tiffRepresentation)
        XCTAssertNotNil(icon.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    func testEmojiWithSkinToneProducesValidImage() {
        Defaults[.emojiPickerSkinTone] = 3 // Medium
        let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: "👋", darkMode: true)
        XCTAssertEqual(icon.size, Layout.statusItemSize)
        XCTAssertNotNil(icon.tiffRepresentation)
    }

    func testVariousEmojisProduceValidImages() {
        let emojis = ["😀", "🎉", "⭐", "🔥", "💡", "🖐️", "👍"]
        for emoji in emojis {
            let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: emoji, darkMode: true)
            XCTAssertEqual(icon.size, Layout.statusItemSize, "\(emoji) should have correct size")
            XCTAssertNotNil(icon.tiffRepresentation, "\(emoji) should produce valid image")
        }
    }

    func testEmojiDifferentFromSFSymbol() {
        let emojiIcon = SpaceIconGenerator.generateSymbolIcon(symbolName: "⭐", darkMode: true)
        let symbolIcon = SpaceIconGenerator.generateSymbolIcon(symbolName: "star.fill", darkMode: true)

        let emojiData = emojiIcon.tiffRepresentation
        let symbolData = symbolIcon.tiffRepresentation

        XCTAssertNotNil(emojiData)
        XCTAssertNotNil(symbolData)
        XCTAssertNotEqual(emojiData, symbolData, "Emoji and SF Symbol should produce different images")
    }

    // MARK: - Style-Specific Tests

    func testOutlineStyleProducesValidImage() {
        let outlineStyles: [IconStyle] = [
            .squareOutline,
            .slimOutline,
            .circleOutline,
            .triangleOutline,
            .pentagonOutline,
            .hexagonOutline,
        ]

        for style in outlineStyles {
            let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, style: style)
            XCTAssertEqual(icon.size, Layout.statusItemSize, "\(style) should have correct size")
            XCTAssertNotNil(icon.tiffRepresentation, "\(style) should produce valid image")
        }
    }

    func testFilledStyleProducesValidImage() {
        let filledStyles: [IconStyle] = [.square, .slim, .circle, .triangle, .pentagon, .hexagon]

        for style in filledStyles {
            let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, style: style)
            XCTAssertEqual(icon.size, Layout.statusItemSize, "\(style) should have correct size")
            XCTAssertNotNil(icon.tiffRepresentation, "\(style) should produce valid image")
        }
    }

    func testSlimStyleProducesDifferentImagesForDifferentDigitCounts() {
        // Slim style has dynamic width based on text, so different digit counts
        // should produce visually different icons
        let singleDigit = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, style: .slim)
        let doubleDigit = SpaceIconGenerator.generateIcon(for: "12", darkMode: true, style: .slim)

        let singleData = singleDigit.tiffRepresentation
        let doubleData = doubleDigit.tiffRepresentation

        XCTAssertNotNil(singleData)
        XCTAssertNotNil(doubleData)
        XCTAssertNotEqual(singleData, doubleData, "Slim icons should differ for different digit counts")
    }

    // MARK: - Helpers

    private func samplePixelColor(from image: NSImage, at point: CGPoint) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let x = Int(point.x)
        let y = Int(point.y)

        guard x >= 0, x < width, y >= 0, y < height else {
            return nil
        }

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return nil
        }

        let offset = ((height - 1 - y) * width + x) * 4
        let pointer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        let red = Double(pointer[offset]) / 255.0
        let green = Double(pointer[offset + 1]) / 255.0
        let blue = Double(pointer[offset + 2]) / 255.0
        let alpha = Double(pointer[offset + 3]) / 255.0

        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func imageContainsColor(
        _ image: NSImage,
        targetRed: Double,
        targetGreen: Double,
        targetBlue: Double,
        tolerance: Double
    ) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let width = cgImage.width
        let height = cgImage.height

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return false
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return false
        }

        let pointer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        for py in 0 ..< height {
            for px in 0 ..< width {
                let offset = (py * width + px) * 4
                let red = Double(pointer[offset]) / 255.0
                let green = Double(pointer[offset + 1]) / 255.0
                let blue = Double(pointer[offset + 2]) / 255.0
                let alpha = Double(pointer[offset + 3]) / 255.0

                // Skip transparent pixels
                if alpha < 0.5 { continue }

                // Check if this pixel matches the target color
                if abs(red - targetRed) <= tolerance,
                   abs(green - targetGreen) <= tolerance,
                   abs(blue - targetBlue) <= tolerance
                {
                    return true
                }
            }
        }

        return false
    }
}
