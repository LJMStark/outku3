import SwiftUI

public struct OnboardingProgressBar: View {
    @Environment(ThemeManager.self) private var theme

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
                .foregroundStyle(theme.colors.primary)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < filledSegments ? theme.colors.primary : theme.colors.timeline)
                        .frame(height: 4)
                }
            }
        }
    }
}
