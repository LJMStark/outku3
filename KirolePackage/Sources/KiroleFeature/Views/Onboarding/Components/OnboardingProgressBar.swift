import SwiftUI

public struct OnboardingProgressBar: View {
    let questionIndex: Int

    public init(questionIndex: Int) {
        self.questionIndex = questionIndex
    }

    private var category: String {
        if questionIndex < 2 { return "Profile" }
        if questionIndex < 5 { return "Habits & Goals" }
        return "Personalization"
    }

    private var filledSegments: Int {
        if questionIndex < 2 { return 1 }
        if questionIndex < 5 { return 2 }
        return 3
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: "0D8A6A"))

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < filledSegments ? Color(hex: "0D8A6A") : Color(hex: "E5E7EB"))
                        .frame(height: 4)
                }
            }
        }
    }
}
