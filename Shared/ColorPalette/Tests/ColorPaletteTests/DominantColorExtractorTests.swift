import Testing
@testable import ColorPalette
@testable import Core

#if canImport(UIKit)
import UIKit

@Suite("DominantColorExtractor Tests")
struct DominantColorExtractorTests {

    let extractor = DominantColorExtractor()

    // MARK: - Solid Color Tests

    @Test("Extracts red from solid red image")
    func extractsRedFromSolidRedImage() {
        let image = createSolidColorImage(.red)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Red is around 0/360 degrees
        #expect(result!.hue < 15 || result!.hue > 345)
        #expect(result!.saturation > 0.8)
        #expect(result!.brightness > 0.8)
    }

    @Test("Extracts green from solid green image")
    func extractsGreenFromSolidGreenImage() {
        let image = createSolidColorImage(.green)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Green is around 120 degrees
        #expect(result!.hue > 100 && result!.hue < 140)
        #expect(result!.saturation > 0.8)
        #expect(result!.brightness > 0.8)
    }

    @Test("Extracts blue from solid blue image")
    func extractsBlueFromSolidBlueImage() {
        let image = createSolidColorImage(.blue)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Blue is around 240 degrees
        #expect(result!.hue > 220 && result!.hue < 260)
        #expect(result!.saturation > 0.8)
        #expect(result!.brightness > 0.8)
    }

    @Test("Extracts yellow from solid yellow image")
    func extractsYellowFromSolidYellowImage() {
        let image = createSolidColorImage(.yellow)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Yellow is around 60 degrees
        #expect(result!.hue > 45 && result!.hue < 75)
        #expect(result!.saturation > 0.8)
        #expect(result!.brightness > 0.8)
    }

    @Test("Extracts cyan from solid cyan image")
    func extractsCyanFromSolidCyanImage() {
        let image = createSolidColorImage(.cyan)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Cyan is around 180 degrees
        #expect(result!.hue > 165 && result!.hue < 195)
    }

    @Test("Extracts magenta from solid magenta image")
    func extractsMagentaFromSolidMagentaImage() {
        let image = createSolidColorImage(.magenta)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Magenta is around 300 degrees
        #expect(result!.hue > 285 && result!.hue < 315)
    }

    // MARK: - Grayscale Tests

    @Test("Handles grayscale image gracefully")
    func handlesGrayscaleImage() {
        let image = createSolidColorImage(.gray)
        let result = extractor.extractDominantColor(from: image)

        // Should return something, but saturation should be low
        #expect(result != nil)
        #expect(result!.saturation < 0.2)
    }

    @Test("Returns result for white image")
    func returnsResultForWhiteImage() {
        let image = createSolidColorImage(.white)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        #expect(result!.saturation < 0.2)
        #expect(result!.brightness > 0.8)
    }

    @Test("Returns result for black image")
    func returnsResultForBlackImage() {
        let image = createSolidColorImage(.black)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        #expect(result!.brightness < 0.2)
    }

    // MARK: - Two-Color Image Tests

    @Test("Returns dominant color from two-color image with 75/25 split")
    func returnsDominantFromTwoColorImageMajority() {
        // Create image that is 75% blue, 25% red
        let image = createTwoColorImage(primary: .blue, secondary: .red, ratio: 0.75)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Should be blue (around 240 degrees)
        #expect(result!.hue > 200 && result!.hue < 280)
    }

    @Test("Returns dominant color from two-color image with 60/40 split")
    func returnsDominantFromTwoColorImageCloser() {
        // Create image that is 60% green, 40% orange
        let image = createTwoColorImage(primary: .green, secondary: .orange, ratio: 0.60)
        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Should be green (around 120 degrees)
        #expect(result!.hue > 90 && result!.hue < 150)
    }

    // MARK: - Transparency Tests

    @Test("Handles transparent pixels")
    func handlesTransparentPixels() {
        let image = createImageWithTransparency()
        let result = extractor.extractDominantColor(from: image)

        // Should not crash and should ignore transparent areas
        // The visible portion is green
        #expect(result != nil)
        #expect(result!.hue > 90 && result!.hue < 150)
    }

    @Test("Handles fully transparent image")
    func handlesFullyTransparentImage() {
        let image = createSolidColorImage(.clear)
        let result = extractor.extractDominantColor(from: image)

        // Should return something (fallback behavior)
        #expect(result != nil)
    }

    // MARK: - Edge Cases

    @Test("Handles small 1x1 image")
    func handlesSmall1x1Image() {
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.purple.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Purple is around 300 degrees
        #expect(result!.hue > 260 && result!.hue < 320)
    }

    @Test("Handles large image efficiently")
    func handlesLargeImageEfficiently() {
        // Create a large image (1000x1000) - should be downsampled internally
        let size = CGSize(width: 1000, height: 1000)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }

        let result = extractor.extractDominantColor(from: image)

        #expect(result != nil)
        // Orange is around 30-40 degrees
        #expect(result!.hue > 15 && result!.hue < 55)
    }

    // MARK: - Test Helpers

    private func createSolidColorImage(_ color: UIColor) -> Image {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func createTwoColorImage(
        primary: UIColor,
        secondary: UIColor,
        ratio: CGFloat
    ) -> Image {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Primary color fills the ratio portion
            primary.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 100 * ratio))

            // Secondary fills the rest
            secondary.setFill()
            context.fill(CGRect(x: 0, y: 100 * ratio, width: 100, height: 100 * (1 - ratio)))
        }
    }

    private func createImageWithTransparency() -> Image {
        let size = CGSize(width: 100, height: 100)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 50, height: 100))

            UIColor.green.setFill()
            context.fill(CGRect(x: 50, y: 0, width: 50, height: 100))
        }
    }
}
#endif
