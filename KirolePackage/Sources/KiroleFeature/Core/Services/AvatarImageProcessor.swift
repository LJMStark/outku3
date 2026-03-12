import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Avatar Process Result

public struct AvatarProcessResult: Sendable {
    /// Original image data (JPEG compressed)
    public let originalData: Data
    /// Pixelated preview image data (PNG) for UI display
    public let previewData: Data
    /// EInkColor pixel array (96x96 = 9216 elements), row-major
    public let pixels: [EInkColor]
    /// Avatar dimension (always square)
    public static let dimension: Int = 96
}

// MARK: - Avatar Image Processor

/// Processes user-uploaded avatar images into E-ink compatible pixelated format.
/// Crops to square, scales to 96x96, quantizes to Spectra 6 color palette.
public enum AvatarImageProcessor {

    /// Target dimension for the avatar (square)
    private static let targetSize = 96

    // Spectra 6 reference colors in RGB (0-255)
    private static let palette: [(color: EInkColor, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (.black,  0,   0,   0),
        (.white,  255, 255, 255),
        (.yellow, 255, 230, 0),
        (.red,    200, 30,  30),
        (.blue,   0,   60,  180),
        (.green,  0,   140, 60),
    ]

    #if canImport(UIKit)

    /// Process a UIImage into an E-ink compatible avatar.
    /// - Parameter image: Source image from user's photo library
    /// - Returns: Processed result with original data, preview, and pixel array
    public static func process(image: UIImage) -> AvatarProcessResult? {
        // 1. Crop to center square
        let cropped = cropToSquare(image)

        // 2. Scale to target size
        guard let scaled = resize(cropped, to: CGSize(width: targetSize, height: targetSize)) else {
            return nil
        }

        // 3. Extract pixel data and quantize to Spectra 6
        guard let cgImage = scaled.cgImage else { return nil }
        let (pixels, previewImage) = quantizeToSpectra6(cgImage)

        // 4. Compress original for storage
        guard let originalData = cropped.jpegData(compressionQuality: 0.8) else { return nil }
        guard let previewData = previewImage.pngData() else { return nil }

        return AvatarProcessResult(
            originalData: originalData,
            previewData: previewData,
            pixels: pixels
        )
    }

    // MARK: - Private Helpers

    private static func cropToSquare(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let side = min(width, height)
        let originX = (width - side) / 2
        let originY = (height - side) / 2
        let cropRect = CGRect(x: originX, y: originY, width: side, height: side)

        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func resize(_ image: UIImage, to size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Ensure exact pixel dimensions
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func quantizeToSpectra6(_ cgImage: CGImage) -> ([EInkColor], UIImage) {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (Array(repeating: .white, count: width * height), UIImage())
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixels = [EInkColor]()
        pixels.reserveCapacity(width * height)

        // Build preview pixel data (RGBA)
        var previewData = [UInt8](repeating: 255, count: width * height * bytesPerPixel)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                let r = CGFloat(rawData[offset])
                let g = CGFloat(rawData[offset + 1])
                let b = CGFloat(rawData[offset + 2])

                // Find nearest Spectra 6 color (Euclidean distance in RGB)
                let nearest = findNearestColor(r: r, g: g, b: b)
                pixels.append(nearest.color)

                // Write preview pixel
                let previewOffset = (y * width + x) * bytesPerPixel
                previewData[previewOffset] = UInt8(nearest.r)
                previewData[previewOffset + 1] = UInt8(nearest.g)
                previewData[previewOffset + 2] = UInt8(nearest.b)
                previewData[previewOffset + 3] = 255
            }
        }

        // Create preview UIImage from quantized data
        let previewImage = createImage(from: previewData, width: width, height: height) ?? UIImage()

        return (pixels, previewImage)
    }

    private static func findNearestColor(
        r: CGFloat, g: CGFloat, b: CGFloat
    ) -> (color: EInkColor, r: CGFloat, g: CGFloat, b: CGFloat) {
        var bestMatch = palette[0]
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for entry in palette {
            let dr = r - entry.r
            let dg = g - entry.g
            let db = b - entry.b
            let distance = dr * dr + dg * dg + db * db

            if distance < bestDistance {
                bestDistance = distance
                bestMatch = entry
            }
        }

        return bestMatch
    }

    private static func createImage(from pixelData: [UInt8], width: Int, height: Int) -> UIImage? {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let dataSize = pixelData.count

        guard let provider = CGDataProvider(data: Data(pixelData) as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: bytesPerPixel * 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ), dataSize == height * bytesPerRow else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    #endif
}
