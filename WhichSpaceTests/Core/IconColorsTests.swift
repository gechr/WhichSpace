import XCTest
@testable import WhichSpace

final class IconColorsTests: XCTestCase {
    // MARK: - Static Color Constants

    func testFilledDarkForegroundIsBlack() {
        let color = IconColors.filledDarkForeground
        XCTAssertEqual(color, NSColor(calibratedWhite: 0, alpha: 1))
    }

    func testFilledDarkBackgroundIsLightGray() {
        let color = IconColors.filledDarkBackground
        XCTAssertEqual(color, NSColor(calibratedWhite: 0.7, alpha: 1))
    }

    func testFilledLightForegroundIsWhite() {
        let color = IconColors.filledLightForeground
        XCTAssertEqual(color, NSColor(calibratedWhite: 1, alpha: 1))
    }

    func testFilledLightBackgroundIsDarkGray() {
        let color = IconColors.filledLightBackground
        XCTAssertEqual(color, NSColor(calibratedWhite: 0.3, alpha: 1))
    }

    func testOutlineDarkIsLightGray() {
        let color = IconColors.outlineDark
        XCTAssertEqual(color, NSColor(calibratedWhite: 0.7, alpha: 1))
    }

    func testOutlineLightIsDarkGray() {
        let color = IconColors.outlineLight
        XCTAssertEqual(color, NSColor(calibratedWhite: 0.3, alpha: 1))
    }

    // MARK: - Filled Colors (Dark Mode)

    func testFilledColorsDarkModeReturnsDarkForeground() {
        let (foreground, _) = IconColors.filledColors(darkMode: true)
        XCTAssertEqual(foreground, IconColors.filledDarkForeground)
    }

    func testFilledColorsDarkModeReturnsDarkBackground() {
        let (_, background) = IconColors.filledColors(darkMode: true)
        XCTAssertEqual(background, IconColors.filledDarkBackground)
    }

    // MARK: - Filled Colors (Light Mode)

    func testFilledColorsLightModeReturnsLightForeground() {
        let (foreground, _) = IconColors.filledColors(darkMode: false)
        XCTAssertEqual(foreground, IconColors.filledLightForeground)
    }

    func testFilledColorsLightModeReturnsLightBackground() {
        let (_, background) = IconColors.filledColors(darkMode: false)
        XCTAssertEqual(background, IconColors.filledLightBackground)
    }

    // MARK: - Outline Colors (Dark Mode)

    func testOutlineColorsDarkModeReturnsSameForForegroundAndBackground() {
        let (foreground, background) = IconColors.outlineColors(darkMode: true)
        XCTAssertEqual(foreground, background)
    }

    func testOutlineColorsDarkModeReturnsOutlineDark() {
        let (foreground, background) = IconColors.outlineColors(darkMode: true)
        XCTAssertEqual(foreground, IconColors.outlineDark)
        XCTAssertEqual(background, IconColors.outlineDark)
    }

    // MARK: - Outline Colors (Light Mode)

    func testOutlineColorsLightModeReturnsSameForForegroundAndBackground() {
        let (foreground, background) = IconColors.outlineColors(darkMode: false)
        XCTAssertEqual(foreground, background)
    }

    func testOutlineColorsLightModeReturnsOutlineLight() {
        let (foreground, background) = IconColors.outlineColors(darkMode: false)
        XCTAssertEqual(foreground, IconColors.outlineLight)
        XCTAssertEqual(background, IconColors.outlineLight)
    }

    // MARK: - Mode Difference Tests

    func testFilledColorsAreDifferentBetweenModes() {
        let darkColors = IconColors.filledColors(darkMode: true)
        let lightColors = IconColors.filledColors(darkMode: false)

        XCTAssertNotEqual(darkColors.foreground, lightColors.foreground)
        XCTAssertNotEqual(darkColors.background, lightColors.background)
    }

    func testOutlineColorsAreDifferentBetweenModes() {
        let darkColors = IconColors.outlineColors(darkMode: true)
        let lightColors = IconColors.outlineColors(darkMode: false)

        XCTAssertNotEqual(darkColors.foreground, lightColors.foreground)
        XCTAssertNotEqual(darkColors.background, lightColors.background)
    }

    // MARK: - Contrast Tests

    func testFilledDarkModeHasSufficientContrast() {
        let (foreground, background) = IconColors.filledColors(darkMode: true)

        // Dark foreground on light background should have good contrast
        // Foreground is black (0.0), background is 0.7 gray
        let fgWhite = foreground.luminance
        let bgWhite = background.luminance

        XCTAssertLessThan(fgWhite, bgWhite, "Foreground should be darker than background in dark mode")
        XCTAssertGreaterThan(bgWhite - fgWhite, 0.5, "Contrast should be at least 0.5")
    }

    func testFilledLightModeHasSufficientContrast() {
        let (foreground, background) = IconColors.filledColors(darkMode: false)

        // Light foreground on dark background should have good contrast
        // Foreground is white (1.0), background is 0.3 gray
        let fgWhite = foreground.luminance
        let bgWhite = background.luminance

        XCTAssertGreaterThan(fgWhite, bgWhite, "Foreground should be lighter than background in light mode")
        XCTAssertGreaterThan(fgWhite - bgWhite, 0.5, "Contrast should be at least 0.5")
    }
}

// MARK: - NSColor Helper Extension

extension NSColor {
    /// Returns the luminance of the color (0 = black, 1 = white)
    fileprivate var luminance: Double {
        guard let calibrated = usingColorSpace(.genericGray) else {
            // Fallback: compute luminance from RGB
            guard let rgb = usingColorSpace(.genericRGB) else {
                return 0
            }
            return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        }
        return calibrated.whiteComponent
    }
}
