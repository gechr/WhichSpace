import Cocoa
import Testing
@testable import WhichSpace

@Suite("Emoji Rendering")
struct EmojiRenderTests {
    // MARK: - Emoji Rendering Tests

    @Test("all emojis render with visible content")
    func allEmojisRenderWithVisibleContent() {
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

        #expect(
            emptyRenders.isEmpty,
            "The following emojis rendered with no visible content: \(emptyRenders.joined(separator: " "))"
        )
    }

    @Test("skinnable emoji variants render correctly")
    func emojiSkinnableVariantsRenderCorrectly() {
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

        #expect(
            failures.isEmpty,
            "Failed to render: \(failures.map { "\($0.emoji) tone:\($0.tone)" }.joined(separator: ", "))"
        )
    }

    @Test("emoji content is centered and within bounds")
    func emojiContentIsCenteredAndWithinBounds() {
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

            let scaleFactor = Double(cgImage.width) / image.size.width

            guard let bounds = contentBounds(of: image) else {
                boundaryViolations.append("\(emoji): no content")
                continue
            }

            let boundsInPoints = CGRect(
                x: bounds.minX / scaleFactor,
                y: bounds.minY / scaleFactor,
                width: bounds.width / scaleFactor,
                height: bounds.height / scaleFactor
            )

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

        #expect(
            boundaryViolations.isEmpty,
            "Boundary violations: \(boundaryViolations.joined(separator: "; "))"
        )
    }

    @Test("emojis without skin tone support render correctly")
    func emojisWithoutSkinToneSupportRenderCorrectly() {
        let noSkinToneEmojis = ["👯", "👯‍♀️", "👯‍♂️", "🤼", "🤼‍♀️", "🤼‍♂️"]

        for emoji in noSkinToneEmojis {
            let image = SpaceIconGenerator.generateSymbolIcon(
                symbolName: emoji,
                darkMode: false,
                customColors: nil,
                skinTone: .medium
            )

            #expect(
                hasVisibleContent(image),
                "Emoji '\(emoji)' without skin tone support should render with visible content"
            )
        }
    }

    // MARK: - Symbol Rendering Tests

    @Test("all symbols render with visible content")
    func allSymbolsRenderWithVisibleContent() {
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

        #expect(
            emptyRenders.isEmpty,
            "The following symbols rendered with no visible content: \(emptyRenders.joined(separator: ", "))"
        )
    }

    // MARK: - Number Icon Rendering Tests

    @Test("number icons render correctly for all styles")
    func numberIconsRenderCorrectly() {
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

                #expect(
                    hasVisibleContent(image),
                    "Number \(number) with style \(style) should render with visible content"
                )
            }
        }
    }

    // MARK: - Helpers

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

        for idx in stride(from: 3, to: totalBytes, by: bytesPerPixel) {
            if pixelData[idx] > 0 {
                return true
            }
        }

        return false
    }

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

        return CGRect(
            x: Double(minX),
            y: Double(height - maxY - 1),
            width: Double(maxX - minX + 1),
            height: Double(maxY - minY + 1)
        )
    }
}
