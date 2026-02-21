import SwiftUI

struct PetAnimationEngine {
    static func randomOffsets(count: Int, xRange: ClosedRange<CGFloat>, yRange: ClosedRange<CGFloat>) -> [CGSize] {
        (0..<count).map { _ in
            CGSize(width: CGFloat.random(in: xRange), height: CGFloat.random(in: yRange))
        }
    }

    static func scaleOffsets(_ offsets: [CGSize], xScale: CGFloat, yScale: CGFloat) -> [CGSize] {
        offsets.map { CGSize(width: $0.width * xScale, height: $0.height * yScale) }
    }

    static func fadeValues(count: Int, to value: Double) -> [Double] {
        Array(repeating: value, count: count)
    }
}
