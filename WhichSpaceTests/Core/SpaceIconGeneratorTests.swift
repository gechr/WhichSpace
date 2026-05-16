import AppKit
import Defaults
import Testing
@testable import WhichSpace

@MainActor
struct SpaceIconGeneratorTests {
    private let store: DefaultsStore
    private let testSuite: TestSuite

    init() {
        testSuite = TestSuiteFactory.createSuite()
        store = DefaultsStore(suite: testSuite.suite)
    }

    // MARK: - Image Size Tests

    @Test("generated icon has expected size")
    func generatedIconHasExpectedSize() {
        let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        #expect(icon.size == Layout.statusItemSize)
    }

    @Test("all styles generate correct size (except dynamic-width pill styles)")
    func allStylesGenerateCorrectSize() {
        let dynamicWidthStyles: Set<IconStyle> = [.pill, .pillOutline]
        for style in IconStyle.allCases where !dynamicWidthStyles.contains(style) {
            let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, style: style)
            #expect(icon.size == Layout.statusItemSize, "Style \(style.rawValue) should produce correct size")
        }
    }

    @Test("multi-digit numbers generate correct size")
    func multiDigitNumbersGenerateCorrectSize() {
        let singleDigit = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        let doubleDigit = SpaceIconGenerator.generateIcon(for: "12", darkMode: true)
        let tripleDigit = SpaceIconGenerator.generateIcon(for: "123", darkMode: true)

        #expect(singleDigit.size == Layout.statusItemSize)
        #expect(doubleDigit.size == Layout.statusItemSize)
        #expect(tripleDigit.size == Layout.statusItemSize)
    }

    // MARK: - Scale Tests

    // Note: These tests verify the container size is constant. The scale affects
    // drawn content only, not the image dimensions.

    @Test("icon size unchanged at default scale")
    func iconSizeUnchangedAtDefaultScale() {
        let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        #expect(icon.size == Layout.statusItemSize)
    }

    @Test("size scale range is valid")
    func sizeScaleRangeIsValid() {
        #expect(Layout.sizeScaleRange.lowerBound < Layout.defaultSizeScale)
        #expect(Layout.sizeScaleRange.upperBound > Layout.defaultSizeScale)
        #expect(Layout.defaultSizeScale == 100.0)
    }

    // MARK: - Dark/Light Mode Tests

    @Test("dark mode produces valid image")
    func darkModeProducesValidImage() {
        let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        #expect(!(icon.size.width <= 0))
        #expect(!(icon.size.height <= 0))
        #expect(icon.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }

    @Test("light mode produces valid image")
    func lightModeProducesValidImage() {
        let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: false)
        #expect(!(icon.size.width <= 0))
        #expect(!(icon.size.height <= 0))
        #expect(icon.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }

    @Test("dark and light mode produce different images")
    func darkAndLightModeProduceDifferentImages() {
        let darkIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        let lightIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: false)

        let darkData = darkIcon.tiffRepresentation
        let lightData = lightIcon.tiffRepresentation

        #expect(darkData != nil)
        #expect(lightData != nil)
        #expect(darkData != lightData)
    }

    // MARK: - Custom Colors Tests

    @Test("custom colors are applied")
    func customColorsApplied() {
        let customColors = SpaceColors(foreground: .systemRed, background: .systemBlue)
        let icon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors
        )

        #expect(icon.size == Layout.statusItemSize)
        #expect(icon.tiffRepresentation != nil)
    }

    @Test("custom colors produce different image from default")
    func customColorsDifferFromDefault() {
        let customColors = SpaceColors(foreground: .systemRed, background: .systemBlue)

        let defaultIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        let customIcon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors
        )

        let defaultData = defaultIcon.tiffRepresentation
        let customData = customIcon.tiffRepresentation

        #expect(defaultData != nil)
        #expect(customData != nil)
        #expect(defaultData != customData)
    }

    @Test("custom colors contain expected pixels at the center")
    func customColorsContainExpectedPixels() {
        let foreground = NSColor.red
        let background = NSColor.blue
        let customColors = SpaceColors(foreground: foreground, background: background)

        let icon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors,
            style: .square
        )

        let centerX = Int(icon.size.width / 2)
        let centerY = Int(icon.size.height / 2)
        let centerColor = samplePixelColor(from: icon, at: CGPoint(x: centerX, y: centerY))

        #expect(centerColor != nil)

        if let color = centerColor {
            #expect(color.alphaComponent > 0.5)
        }
    }

    @Test("background color appears in image")
    func backgroundColorAppearsInImage() {
        let customColors = SpaceColors(
            foreground: .black,
            background: NSColor(red: 1.0, green: 0, blue: 0, alpha: 1.0)
        )

        let icon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors,
            style: .square
        )

        let hasRedPixels = imageContainsColor(icon, targetRed: 1.0, targetGreen: 0, targetBlue: 0, tolerance: 0.1)
        #expect(hasRedPixels)
    }

    @Test("foreground color appears in image")
    func foregroundColorAppearsInImage() {
        let customColors = SpaceColors(
            foreground: NSColor(red: 0, green: 1.0, blue: 0, alpha: 1.0),
            background: .black
        )

        let icon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: customColors,
            style: .square
        )

        let hasGreenPixels = imageContainsColor(icon, targetRed: 0, targetGreen: 1.0, targetBlue: 0, tolerance: 0.1)
        #expect(hasGreenPixels)
    }

    // MARK: - Symbol Tests

    @Test("symbol icon has expected size")
    func symbolIconHasExpectedSize() {
        let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: "star.fill", darkMode: true)
        #expect(icon.size == Layout.statusItemSize)
    }

    @Test("symbol with custom colors produces valid image")
    func symbolWithCustomColors() {
        let customColors = SpaceColors(foreground: .systemGreen, background: .clear)
        let icon = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "star.fill",
            darkMode: true,
            customColors: customColors
        )

        #expect(icon.size == Layout.statusItemSize)
        #expect(icon.tiffRepresentation != nil)
    }

    @Test("invalid symbol falls back to question mark")
    func invalidSymbolFallsBackToQuestionMark() {
        let icon = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "this.symbol.definitely.does.not.exist",
            darkMode: true
        )

        #expect(icon.size == Layout.statusItemSize)
        #expect(icon.tiffRepresentation != nil)
    }

    // MARK: - Emoji Tests

    @Test("emoji icon has expected size")
    func emojiIconHasExpectedSize() {
        let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: "😀", darkMode: true)
        #expect(icon.size == Layout.statusItemSize)
    }

    @Test("emoji icon produces valid image")
    func emojiIconProducesValidImage() {
        let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: "👋", darkMode: true)
        #expect(icon.tiffRepresentation != nil)
        #expect(icon.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }

    @Test("emoji with skin tone produces valid image")
    func emojiWithSkinToneProducesValidImage() {
        Defaults[.emojiPickerSkinTone] = .medium
        let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: "👋", darkMode: true)
        #expect(icon.size == Layout.statusItemSize)
        #expect(icon.tiffRepresentation != nil)
    }

    @Test("various emojis produce valid images")
    func variousEmojisProduceValidImages() {
        let emojis = ["😀", "🎉", "⭐", "🔥", "💡", "🖐️", "👍"]
        for emoji in emojis {
            let icon = SpaceIconGenerator.generateSymbolIcon(symbolName: emoji, darkMode: true)
            #expect(icon.size == Layout.statusItemSize, "\(emoji) should have correct size")
            #expect(icon.tiffRepresentation != nil, "\(emoji) should produce valid image")
        }
    }

    @Test("emoji differs from SF Symbol")
    func emojiDifferentFromSFSymbol() {
        let emojiIcon = SpaceIconGenerator.generateSymbolIcon(symbolName: "⭐", darkMode: true)
        let symbolIcon = SpaceIconGenerator.generateSymbolIcon(symbolName: "star.fill", darkMode: true)

        let emojiData = emojiIcon.tiffRepresentation
        let symbolData = symbolIcon.tiffRepresentation

        #expect(emojiData != nil)
        #expect(symbolData != nil)
        #expect(emojiData != symbolData)
    }

    // MARK: - Style-Specific Tests

    @Test("outline styles produce valid images")
    func outlineStyleProducesValidImage() {
        let outlineStyles: [IconStyle] = [
            .squareOutline,
            .pillOutline,
            .slimOutline,
            .circleOutline,
            .triangleOutline,
            .pentagonOutline,
            .hexagonOutline,
        ]

        for style in outlineStyles {
            let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, style: style)
            if style != .pillOutline {
                #expect(icon.size == Layout.statusItemSize, "\(style) should have correct size")
            }
            #expect(icon.tiffRepresentation != nil, "\(style) should produce valid image")
        }
    }

    @Test("filled styles produce valid images")
    func filledStyleProducesValidImage() {
        let filledStyles: [IconStyle] = [.square, .pill, .slim, .circle, .triangle, .pentagon, .hexagon]

        for style in filledStyles {
            let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, style: style)
            if style != .pill {
                #expect(icon.size == Layout.statusItemSize, "\(style) should have correct size")
            }
            #expect(icon.tiffRepresentation != nil, "\(style) should produce valid image")
        }
    }

    @Test("slim style differs by digit count (dynamic width)")
    func slimStyleProducesDifferentImagesForDifferentDigitCounts() {
        let singleDigit = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, style: .slim)
        let doubleDigit = SpaceIconGenerator.generateIcon(for: "12", darkMode: true, style: .slim)

        let singleData = singleDigit.tiffRepresentation
        let doubleData = doubleDigit.tiffRepresentation

        #expect(singleData != nil)
        #expect(doubleData != nil)
        #expect(singleData != doubleData)
    }

    // MARK: - Badge Tests

    @Test("badge does not change icon size")
    func badgeDoesNotChangeIconSize() {
        let badge = SpaceBadge(character: "A", position: .topRight)
        let badgedIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, badge: badge)
        #expect(badgedIcon.size == Layout.statusItemSize)
    }

    @Test("badge produces different image")
    func badgeProducesDifferentImage() {
        let baseIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        let badge = SpaceBadge(character: "X", position: .topRight)
        let badgedIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, badge: badge)
        #expect(baseIcon.tiffRepresentation != badgedIcon.tiffRepresentation)
    }

    @Test("emoji badge produces valid image")
    func emojiBadgeProducesValidImage() {
        let badge = SpaceBadge(character: "🔴", position: .bottomLeft)
        let badgedIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, badge: badge)
        #expect(badgedIcon.size == Layout.statusItemSize)
        #expect(badgedIcon.tiffRepresentation != nil)
    }

    @Test("badge in all positions produces valid images")
    func badgeAllPositionsProduceValidImages() {
        for position in BadgePosition.allCases {
            let badge = SpaceBadge(character: "B", position: position)
            let badgedIcon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, badge: badge)
            #expect(badgedIcon.size == Layout.statusItemSize, "\(position) should produce correct size")
            #expect(badgedIcon.tiffRepresentation != nil, "\(position) should produce valid image")
        }
    }

    @Test("badge with all styles produces valid images")
    func badgeWithAllStylesProducesValidImages() {
        let badge = SpaceBadge(character: "A", position: .topRight)
        let dynamicWidthStyles: Set<IconStyle> = [.pill, .pillOutline]
        for style in IconStyle.allCases {
            let icon = SpaceIconGenerator.generateIcon(
                for: "1",
                darkMode: true,
                style: style,
                badge: badge
            )
            if !dynamicWidthStyles.contains(style) {
                #expect(icon.size == Layout.statusItemSize, "Badge with style \(style.rawValue) should produce correct size")
            }
            #expect(icon.tiffRepresentation != nil, "Badge with style \(style.rawValue) should produce valid image")
        }
    }

    @Test("badge with multi-digit number")
    func badgeWithMultiDigitNumber() {
        let badge = SpaceBadge(character: "X", position: .topLeft)
        let icon = SpaceIconGenerator.generateIcon(for: "12", darkMode: true, badge: badge)
        #expect(icon.size == Layout.statusItemSize)
        #expect(icon.tiffRepresentation != nil)
    }

    @Test("empty badge character matches no-badge")
    func emptyBadgeCharacterMatchesNoBadge() {
        let emptyBadge = SpaceBadge(character: "", position: .topRight)
        let withEmpty = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, badge: emptyBadge)
        let withNil = SpaceIconGenerator.generateIcon(for: "1", darkMode: true)
        #expect(withEmpty.tiffRepresentation == withNil.tiffRepresentation)
    }

    @Test("different badge positions produce different images")
    func differentPositionsProduceDifferentImages() {
        let badgeLeft = SpaceBadge(character: "A", position: .topLeft)
        let badgeRight = SpaceBadge(character: "A", position: .topRight)
        let iconLeft = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, badge: badgeLeft)
        let iconRight = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, badge: badgeRight)
        #expect(iconLeft.tiffRepresentation != iconRight.tiffRepresentation)
    }

    // MARK: - Padding Scale Tests

    @Test("default padding scale produces standard width")
    func paddingScaleDefaultProducesStandardWidth() {
        let icon = SpaceIconGenerator.generateIcon(
            for: "1", darkMode: true, paddingScale: Layout.defaultPaddingScale
        )
        #expect(abs(icon.size.width - Layout.statusItemWidth) < 0.1)
        #expect(abs(icon.size.height - Layout.statusItemHeight) < 0.001)
    }

    @Test("zero padding scale produces tighter icon")
    func paddingScaleZeroProducesTighterIcon() {
        let icon = SpaceIconGenerator.generateIcon(for: "1", darkMode: true, paddingScale: 0)
        #expect(icon.size.width < Layout.statusItemWidth)
        #expect(abs(icon.size.height - Layout.statusItemHeight) < 0.001)
    }

    @Test("transparent style with zero padding uses text-tight width")
    func transparentStyleZeroPaddingUsesTextTightWidth() {
        let icon = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            style: .transparent,
            paddingScale: 0
        )
        #expect(icon.size.width < Layout.baseSquareSize)
    }

    @Test("slim with clear background collapses to visible text width")
    func slimWithClearBackgroundCollapsesToVisibleTextWidth() {
        let opaqueSlim = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            style: .slim,
            paddingScale: 0
        )
        let clearSlim = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: SpaceColors(foreground: .white, background: .clear),
            style: .slim,
            paddingScale: 0
        )

        #expect(clearSlim.size.width < opaqueSlim.size.width)
    }

    @Test("slim padding does not change visible shape")
    func slimPaddingDoesNotChangeVisibleShape() throws {
        let colors = SpaceColors(foreground: .black, background: .white)
        let tight = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: colors,
            style: .slim,
            paddingScale: 0
        )
        let standard = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            customColors: colors,
            style: .slim,
            paddingScale: Layout.defaultPaddingScale
        )

        let tightBounds = try #require(nonTransparentBounds(of: tight))
        let standardBounds = try #require(nonTransparentBounds(of: standard))

        #expect(abs(tightBounds.width - standardBounds.width) <= 2.0)
        #expect(abs(tightBounds.height - standardBounds.height) <= 2.0)
    }

    @Test("max padding scale produces wider icon")
    func paddingScaleMaxProducesWiderIcon() {
        let icon = SpaceIconGenerator.generateIcon(
            for: "1", darkMode: true, paddingScale: Layout.paddingScaleRange.upperBound
        )
        #expect(icon.size.width > Layout.statusItemWidth)
        #expect(abs(icon.size.height - Layout.statusItemHeight) < 0.001)
    }

    @Test("pill style padding affects overflowing width")
    func pillStylePaddingAffectsOverflowingWidth() {
        let tight = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            style: .pill,
            paddingScale: 0
        )
        let standard = SpaceIconGenerator.generateIcon(
            for: "1",
            darkMode: true,
            style: .pill,
            paddingScale: Layout.defaultPaddingScale
        )

        #expect(tight.size.width < standard.size.width)
    }

    @Test("padding scale affects symbol icon width")
    func paddingScaleAffectsSymbolIconWidth() {
        let tight = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "star.fill", darkMode: true, paddingScale: 0
        )
        let wide = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "star.fill", darkMode: true, paddingScale: 120
        )
        #expect(tight.size.width < wide.size.width)
    }

    @Test("padding scale affects emoji icon width")
    func paddingScaleAffectsEmojiIconWidth() {
        let tight = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "😀", darkMode: true, paddingScale: 0
        )
        let wide = SpaceIconGenerator.generateSymbolIcon(
            symbolName: "😀", darkMode: true, paddingScale: 120
        )
        #expect(tight.size.width < wide.size.width)
    }

    @Test("all styles produce valid images with custom padding")
    func allStylesProduceValidImagesWithCustomPadding() {
        for style in IconStyle.allCases {
            let icon = SpaceIconGenerator.generateIcon(
                for: "1", darkMode: true, style: style, paddingScale: 50
            )
            #expect(icon.size.width > 0, "\(style) should have non-zero width at padding 50%")
            #expect(abs(icon.size.height - Layout.statusItemHeight) < 0.001, "\(style) height should be unchanged")
            #expect(icon.tiffRepresentation != nil, "\(style) should produce valid image at padding 50%")
        }
    }

    @Test("padding scale range is valid")
    func paddingScaleRangeIsValid() {
        #expect(Layout.paddingScaleRange.lowerBound == 0.0)
        #expect(Layout.defaultPaddingScale < Layout.paddingScaleRange.upperBound)
        #expect(Layout.defaultPaddingScale == 100.0)
    }

    @Test("default horizontal padding equals status width minus base square")
    func defaultHorizontalPadding() {
        #expect(Layout.defaultHorizontalPadding == Layout.statusItemWidth - Layout.baseSquareSize)
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

                if alpha < 0.5 { continue }

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

    private func nonTransparentBounds(of image: NSImage, alphaThreshold: Double = 0.05) -> CGRect? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
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
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            return nil
        }

        let pointer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let alphaCutoff = UInt8(alphaThreshold * 255)
        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1

        for py in 0 ..< height {
            for px in 0 ..< width {
                let offset = (py * width + px) * 4
                let alpha = pointer[offset + 3]
                if alpha <= alphaCutoff {
                    continue
                }
                minX = min(minX, px)
                maxX = max(maxX, px)
                minY = min(minY, py)
                maxY = max(maxY, py)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}
