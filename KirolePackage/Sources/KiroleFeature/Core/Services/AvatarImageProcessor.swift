import Foundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Avatar Process Result

public struct AvatarProcessResult: Sendable {
    /// PNG for in-app UI display (same bytes as `imageData`; single Data instance, CoW).
    public let previewData: Data
    /// Wire PNG pushed to hardware via CustomAvatarFrame (0x15, SubVersion 0x02).
    public let imageData: Data
}

// MARK: - Avatar Image Processor

/// Processes user-uploaded avatar images into the hardware-accepted PNG shape
/// (v2.5.24 hardware requirement): aspect-fit into 800×700 preserving the original
/// ratio (never upscaled, never cropped), PNG-encoded, best-effort ≤1 MiB via a
/// ×0.9 shrink-and-re-encode loop. Color quantization for the 6-color E-ink panel
/// now happens firmware-side — the app no longer quantizes.
public enum AvatarImageProcessor {

    /// Hardware bounding box (protocol §4.12): width ≤ 800, height ≤ 700.
    public static let maxPixelWidth = 800
    public static let maxPixelHeight = 700
    /// Hard cap for the encoded PNG (hardware asks "尽量 1MB 内"; we never exceed it).
    public static let maxEncodedByteCount = 1_048_576
    /// Per-iteration scale factor when the encoded PNG is still over the byte cap.
    static let shrinkFactor: CGFloat = 0.9
    /// Loop-termination floor. A ≤50px PNG can't plausibly exceed 1 MiB, so this is
    /// theoretical protection against a runaway loop, not an expected path.
    static let minShrinkDimension: CGFloat = 50

    // MARK: Pure logic (outside the UIKit block so `swift test` covers it on macOS)

    /// PNG 8-byte file signature check. Doubles as the stale-asset guard: pre-v2.5.24
    /// persisted avatars are packed 4bpp Spectra data (every byte's nibbles ≤ 0x6),
    /// which can never start with 0x89.
    public static func isPNGData(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= signature.count else { return false }
        return data.prefix(signature.count).elementsEqual(signature)
    }

    /// Aspect-fit `original` into the bounding box, preserving ratio. Never upscales
    /// (scale clamped to 1.0). Floor-rounded to integer pixels, minimum 1×1.
    static func fitSize(
        original: CGSize,
        maxWidth: Int = maxPixelWidth,
        maxHeight: Int = maxPixelHeight
    ) -> CGSize {
        guard original.width > 0, original.height > 0 else {
            return CGSize(width: 1, height: 1)
        }
        let scale = min(
            CGFloat(maxWidth) / original.width,
            CGFloat(maxHeight) / original.height,
            1.0
        )
        return CGSize(
            width: max(1, (original.width * scale).rounded(.down)),
            height: max(1, (original.height * scale).rounded(.down))
        )
    }

    /// One step of the over-budget shrink loop (pure, so termination is unit-testable).
    static func nextShrunkSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(1, (size.width * shrinkFactor).rounded(.down)),
            height: max(1, (size.height * shrinkFactor).rounded(.down))
        )
    }

    #if canImport(UIKit)

    /// Process a user-picked image into the hardware PNG.
    /// - Parameter image: Source image from the photo library (any format UIImage decodes,
    ///   e.g. HEIC/JPEG/PNG; EXIF orientation is baked in by the render pass).
    /// - Returns: nil when the image can't be rendered/encoded, or — theoretically —
    ///   when even the minimum-size PNG exceeds the byte cap.
    public static func process(image: UIImage) -> AvatarProcessResult? {
        // image.size is in points with orientation already applied; × scale = source pixels.
        let sourcePixels = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        var target = fitSize(original: sourcePixels)
        var png = renderPNG(image: image, size: target)

        // Photographic PNGs at 800×700 routinely exceed 1 MiB — shrink until they fit.
        // Always re-render from the ORIGINAL image so quality degrades once, not cumulatively.
        while let data = png,
              data.count > maxEncodedByteCount,
              target.width > minShrinkDimension,
              target.height > minShrinkDimension {
            target = nextShrunkSize(target)
            png = renderPNG(image: image, size: target)
        }

        guard let data = png, data.count <= maxEncodedByteCount else { return nil }
        return AvatarProcessResult(previewData: data, imageData: data)
    }

    private static func renderPNG(image: UIImage, size: CGSize) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0 // Exact pixel dimensions
        // format.opaque stays false → alpha survives into the PNG (firmware composites on white).
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size)) // bakes EXIF orientation
        }
        return rendered.pngData()
    }

    #endif
}
