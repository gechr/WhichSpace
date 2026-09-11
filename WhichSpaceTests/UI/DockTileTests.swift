import AppKit
import Testing
@testable import WhichSpace

@MainActor
struct DockTileTests {
    private func spec(
        symbol: String? = nil,
        label: String? = nil,
        appIcon: NSImage? = nil,
        number: Int = 3
    ) -> DockTileSpec {
        DockTileSpec(
            number: number,
            centerText: String(number),
            label: label,
            symbol: symbol,
            skinTone: .default,
            appIcon: appIcon,
            foreground: IconColors.filledLightForeground,
            background: IconColors.filledLightBackground,
            symbolTint: IconColors.filledLightForeground,
            font: nil,
            badgeBackground: IconColors.dockBadgeBackground,
            badgeForeground: IconColors.dockBadgeForeground
        )
    }

    /// Rasterizes the tile and reads back one pixel in device RGB.
    private func pixel(of image: NSImage, at point: CGPoint) -> NSColor? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        let scaleX = Double(rep.pixelsWide) / image.size.width
        let scaleY = Double(rep.pixelsHigh) / image.size.height
        // Bitmap rows run top-down, image coordinates bottom-up
        let x = Int(point.x * scaleX)
        let y = rep.pixelsHigh - 1 - Int(point.y * scaleY)
        return rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    }

    @Test("the tile is square at the Dock's size")
    func tileIsSquare() {
        let image = DockTileRenderer.image(for: spec())
        #expect(image.size == CGSize(width: DockTileRenderer.tileSize, height: DockTileRenderer.tileSize))
    }

    @Test("a symbol with a label draws the number badge in the badge fill")
    func badgeUsesBadgeFill() throws {
        let image = DockTileRenderer.image(for: spec(symbol: "envelope.fill", label: "Mail"))
        let canvas = CGRect(origin: .zero, size: image.size)
        let badge = DockTileRenderer.badgeRect(in: canvas)
        // Off the digit, still well inside the circle
        let sample = CGPoint(x: badge.minX + badge.width * 0.2, y: badge.midY)
        let color = try #require(pixel(of: image, at: sample))
        #expect(color.redComponent > 0.9)
        #expect(color.greenComponent > 0.9)
        #expect(color.blueComponent > 0.9)
    }

    @Test("a plain number draws no badge, since the centre already shows it")
    func plainNumberHasNoBadge() throws {
        let image = DockTileRenderer.image(for: spec())
        let canvas = CGRect(origin: .zero, size: image.size)
        let badge = DockTileRenderer.badgeRect(in: canvas)
        let sample = CGPoint(x: badge.minX + badge.width * 0.2, y: badge.midY)
        let color = try #require(pixel(of: image, at: sample))
        // That point lies on the tile's dark grey, not on a white badge
        #expect(color.alphaComponent > 0.9)
        #expect(color.redComponent < 0.5)
    }

    @Test("the layout flags follow the spec")
    func layoutFlags() {
        #expect(spec().centerIsNumber)
        #expect(!spec().showsLabelPill)
        #expect(!spec(label: "Mail").centerIsNumber)
        #expect(!spec(label: "Mail").showsLabelPill)
        #expect(spec(symbol: "envelope.fill", label: "Mail").showsLabelPill)
        #expect(spec(label: "Mail", appIcon: NSImage(size: CGSize(width: 8, height: 8))).showsLabelPill)
    }

    @Test("emoji and unknown symbols still render")
    func emojiAndUnknownSymbolRender() {
        for symbol in ["🧑‍💻", "no.such.symbol.name", "star.fill"] {
            let image = DockTileRenderer.image(for: spec(symbol: symbol, label: "Code"))
            #expect(image.tiffRepresentation != nil)
        }
    }

    @Test("badge colours round-trip through the store and reset to nil")
    func badgeColorsPersist() {
        let testSuite = TestSuiteFactory.createSuite()
        defer { TestSuiteFactory.destroySuite(testSuite) }
        let store = DefaultsStore(suite: testSuite.suite)
        #expect(store.dockBadgeBackgroundColor == nil)
        #expect(store.dockBadgeForegroundColor == nil)

        store.dockBadgeBackgroundColor = .red
        store.dockBadgeForegroundColor = .green
        let reread = DefaultsStore(suite: testSuite.suite)
        #expect(reread.dockBadgeBackgroundColor?.usingColorSpace(.deviceRGB)?.redComponent == 1)
        #expect(reread.dockBadgeForegroundColor?.usingColorSpace(.deviceRGB)?.greenComponent == 1)

        store.dockBadgeBackgroundColor = nil
        #expect(store.dockBadgeBackgroundColor == nil)
        #expect(DefaultsStore(suite: testSuite.suite).dockBadgeBackgroundColor == nil)
    }

    /// Writes sample tiles to a directory named by an environment variable,
    /// for eyeballing the design; a no-op in a normal test run.
    @Test("preview tiles can be written for inspection")
    func writePreviews() throws {
        guard let directory = ProcessInfo.processInfo.environment["WHICHSPACE_DOCK_PREVIEW_DIR"] else {
            return
        }
        let samples: [(String, DockTileSpec)] = [
            ("symbol-label", spec(symbol: "envelope.fill", label: "Mail")),
            ("emoji-label", spec(symbol: "🧑‍💻", label: "Code")),
            ("label-only", spec(label: "Meetings and calls")),
            ("number-only", spec(number: 12)),
            ("symbol-only", spec(symbol: "safari.fill")),
        ]
        for (name, sample) in samples {
            let image = DockTileRenderer.image(for: sample)
            let tiff = try #require(image.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("dock-\(name).png"))
        }
    }
}
