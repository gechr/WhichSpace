import AppKit
import Testing
@testable import WhichSpace

@Suite("IconColors")
struct IconColorsTests {
    // MARK: - Static Color Constants

    @Test("filledDarkForeground is black")
    func filledDarkForegroundIsBlack() {
        #expect(IconColors.filledDarkForeground == NSColor(calibratedWhite: 0, alpha: 1))
    }

    @Test("filledDarkBackground is light gray")
    func filledDarkBackgroundIsLightGray() {
        #expect(IconColors.filledDarkBackground == NSColor(calibratedWhite: 0.7, alpha: 1))
    }

    @Test("filledLightForeground is white")
    func filledLightForegroundIsWhite() {
        #expect(IconColors.filledLightForeground == NSColor(calibratedWhite: 1, alpha: 1))
    }

    @Test("filledLightBackground is dark gray")
    func filledLightBackgroundIsDarkGray() {
        #expect(IconColors.filledLightBackground == NSColor(calibratedWhite: 0.3, alpha: 1))
    }

    @Test("outlineDark is light gray")
    func outlineDarkIsLightGray() {
        #expect(IconColors.outlineDark == NSColor(calibratedWhite: 0.7, alpha: 1))
    }

    @Test("outlineLight is dark gray")
    func outlineLightIsDarkGray() {
        #expect(IconColors.outlineLight == NSColor(calibratedWhite: 0.3, alpha: 1))
    }

    // MARK: - Filled Colors

    @Test("filled colors dark mode returns dark foreground and background")
    func filledColorsDarkMode() {
        let (foreground, background) = IconColors.filledColors(darkMode: true)
        #expect(foreground == IconColors.filledDarkForeground)
        #expect(background == IconColors.filledDarkBackground)
    }

    @Test("filled colors light mode returns light foreground and background")
    func filledColorsLightMode() {
        let (foreground, background) = IconColors.filledColors(darkMode: false)
        #expect(foreground == IconColors.filledLightForeground)
        #expect(background == IconColors.filledLightBackground)
    }

    // MARK: - Outline Colors

    @Test("outline colors dark mode returns same color for both")
    func outlineColorsDarkMode() {
        let (foreground, background) = IconColors.outlineColors(darkMode: true)
        #expect(foreground == background)
        #expect(foreground == IconColors.outlineDark)
    }

    @Test("outline colors light mode returns same color for both")
    func outlineColorsLightMode() {
        let (foreground, background) = IconColors.outlineColors(darkMode: false)
        #expect(foreground == background)
        #expect(foreground == IconColors.outlineLight)
    }

    // MARK: - Mode Difference Tests

    @Test("filled colors differ between dark and light mode")
    func filledColorsAreDifferentBetweenModes() {
        let darkColors = IconColors.filledColors(darkMode: true)
        let lightColors = IconColors.filledColors(darkMode: false)

        #expect(darkColors.foreground != lightColors.foreground)
        #expect(darkColors.background != lightColors.background)
    }

    @Test("outline colors differ between dark and light mode")
    func outlineColorsAreDifferentBetweenModes() {
        let darkColors = IconColors.outlineColors(darkMode: true)
        let lightColors = IconColors.outlineColors(darkMode: false)

        #expect(darkColors.foreground != lightColors.foreground)
        #expect(darkColors.background != lightColors.background)
    }

    // MARK: - Contrast Tests

    @Test("filled dark mode has sufficient contrast")
    func filledDarkModeHasSufficientContrast() {
        let (foreground, background) = IconColors.filledColors(darkMode: true)

        let fgWhite = foreground.luminance
        let bgWhite = background.luminance

        #expect(fgWhite < bgWhite, "Foreground should be darker than background in dark mode")
        #expect(bgWhite - fgWhite > 0.5, "Contrast should be at least 0.5")
    }

    @Test("filled light mode has sufficient contrast")
    func filledLightModeHasSufficientContrast() {
        let (foreground, background) = IconColors.filledColors(darkMode: false)

        let fgWhite = foreground.luminance
        let bgWhite = background.luminance

        #expect(fgWhite > bgWhite, "Foreground should be lighter than background in light mode")
        #expect(fgWhite - bgWhite > 0.5, "Contrast should be at least 0.5")
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
