import SwiftUI

public struct ProgressDots: View {
    let activeIndex: Int
    let total: Int

    public init(activeIndex: Int, total: Int = 4) {
        self.activeIndex = activeIndex
        self.total = total
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index == activeIndex ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 32, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: activeIndex)
            }
        }
    }
}
