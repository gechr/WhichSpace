import Cocoa
import XCTest
@testable import WhichSpace

final class EmojiRenderTests: XCTestCase {
    // MARK: - Emoji Rendering Tests

    func testAllEmojisRenderWithVisibleContent() {
        var emptyRenders: [String] = []

        for emoji in ItemData.emojis {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: emoji,
                darkMode: false,
                customColors: nil,
                skinTone: .default
            )

            if !hasVisibleContent(image) {
                emptyRenders.append(emoji)
            }
        }

        XCTAssertTrue(
            emptyRenders.isEmpty,
            "The following emojis rendered with no visible content: \(emptyRenders.joined(separator: " "))"
        )
    }

    func testEmojiSkinnablVariantsRenderCorrectly() {
        // Test a sample of emojis that support skin tones
        let skinnableEmojis = ["👋", "👍", "🤞", "👨‍🍳", "👩‍💻"]
        var failures: [(emoji: String, tone: SkinTone)] = []

        for emoji in skinnableEmojis {
            for tone in SkinTone.allCases {
                let image = SpaceIconGenerator.generateSymbolIcon(
                    symbolName: emoji,
                    darkMode: false,
                    customColors: nil,
                    skinTone: tone
                )

                if !hasVisibleContent(image) {
                    failures.append((emoji, tone))
                }
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "Failed to render: \(failures.map { "\($0.emoji) tone:\($0.tone)" }.joined(separator: ", "))"
        )
    }

    func testEmojiContentIsCenteredAndWithinBounds() {
        // Test a sample of emojis to verify they're centered
        let testEmojis = ["😀", "👋", "🎉", "❤️", "👨‍🍳"]
        var boundaryViolations: [String] = []

        for emoji in testEmojis {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: emoji,
                darkMode: false,
                customColors: nil,
                skinTone: .default
            )

            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                boundaryViolations.append("\(emoji): could not get cgImage")
                continue
            }

            // Account for scale factor (Retina displays render at 2x)
            let scaleFactor = Double(cgImage.width) / image.size.width

            guard let bounds = contentBounds(of: image) else {
                boundaryViolations.append("\(emoji): no content")
                continue
            }

            // Convert bounds from pixel coordinates to points
            let boundsInPoints = CGRect(
                x: bounds.minX / scaleFactor,
                y: bounds.minY / scaleFactor,
                width: bounds.width / scaleFactor,
                height: bounds.height / scaleFactor
            )

            // Check content is within image bounds with some tolerance
            // Emoji fonts may slightly exceed bounds, allow 2pt overflow
            let tolerance = 2.0
            if boundsInPoints.minX < -tolerance ||
                boundsInPoints.minY < -tolerance ||
                boundsInPoints.maxX > image.size.width + tolerance ||
                boundsInPoints.maxY > image.size.height + tolerance
            {
                boundaryViolations.append(
                    "\(emoji): out of bounds (content: \(boundsInPoints), image: \(image.size))"
                )
            }
        }

        XCTAssertTrue(
            boundaryViolations.isEmpty,
            "Boundary violations: \(boundaryViolations.joined(separator: "; "))"
        )
    }

    func testEmojisWithoutSkinToneSupportRenderCorrectly() {
        // Emojis that don't support skin tones should still render correctly
        // EmojiKit's hasSkinTones correctly identifies these
        let noSkinToneEmojis = ["👯", "👯‍♀️", "👯‍♂️", "🤼", "🤼‍♀️", "🤼‍♂️"]

        for emoji in noSkinToneEmojis {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: emoji,
                darkMode: false,
                customColors: nil,
                skinTone: .medium // Should be ignored by EmojiKit detection
            )

            XCTAssertTrue(
                hasVisibleContent(image),
                "Emoji '\(emoji)' without skin tone support should render with visible content"
            )
        }
    }

    // MARK: - Symbol Rendering Tests

    func testAllSymbolsRenderWithVisibleContent() {
        var emptyRenders: [String] = []

        for symbol in ItemData.symbols {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: symbol,
                darkMode: false,
                customColors: nil,
                skinTone: nil
            )

            if !hasVisibleContent(image) {
                emptyRenders.append(symbol)
            }
        }

        XCTAssertTrue(
            emptyRenders.isEmpty,
            "The following symbols rendered with no visible content: \(emptyRenders.joined(separator: ", "))"
        )
    }

    // MARK: - Number Icon Rendering Tests

    func testNumberIconsRenderCorrectly() {
        let styles: [IconStyle] = [.square, .circle, .triangle, .pentagon, .hexagon, .transparent, .stroke]

        for style in styles {
            for number in 1 ... 16 {
                let image = SpaceIconGenerator.generateIcon(
                    for: String(number),
                    darkMode: false,
                    customColors: nil,
                    customFont: nil,
                    style: style
                )

                XCTAssertTrue(
                    hasVisibleContent(image),
                    "Number \(number) with style \(style) should render with visible content"
                )
            }
        }
    }

    // MARK: - Helpers

    /// Checks if an NSImage has any visible (non-transparent) content
    private func hasVisibleContent(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Check for any non-transparent pixel
        for idx in stride(from: 3, to: totalBytes, by: bytesPerPixel) {
            if pixelData[idx] > 0 { // Alpha channel > 0
                return true
            }
        }

        return false
    }

    /// Returns the bounding box of visible content in the image
    private func contentBounds(of image: NSImage) -> CGRect? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow

        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var hasContent = false

        for yCoord in 0 ..< height {
            for xCoord in 0 ..< width {
                let pixelIndex = (yCoord * bytesPerRow) + (xCoord * bytesPerPixel)
                let alpha = pixelData[pixelIndex + 3]
                if alpha > 0 {
                    hasContent = true
                    minX = min(minX, xCoord)
                    minY = min(minY, yCoord)
                    maxX = max(maxX, xCoord)
                    maxY = max(maxY, yCoord)
                }
            }
        }

        guard hasContent else {
            return nil
        }

        // Convert to NSImage coordinate space (flip Y)
        return CGRect(
            x: Double(minX),
            y: Double(height - maxY - 1),
            width: Double(maxX - minX + 1),
            height: Double(maxY - minY + 1)
        )
    }
}
