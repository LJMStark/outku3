import SwiftUI

public struct OnboardingProgressBar: View {
    @Environment(ThemeManager.self) private var theme

    let questionIndex: Int

    public init(questionIndex: Int) {
        self.questionIndex = questionIndex
    }

    private static let categories: [String] = {
        var seen: [String] = []
        for question in OnboardingQuestions.allQuestions {
            if !seen.contains(question.category) {
                seen.append(question.category)
            }
        }
        return seen
    }()

    private var totalSegments: Int {
        Self.categories.count
    }

    private var currentCategory: String {
        let questions = OnboardingQuestions.allQuestions
        guard questionIndex >= 0, questionIndex < questions.count else {
            return Self.categories.last ?? ""
        }
        return questions[questionIndex].category
    }

    private var filledSegments: Int {
        guard let idx = Self.categories.firstIndex(of: currentCategory) else {
            return totalSegments
        }
        return idx + 1
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(currentCategory)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(theme.colors.primary)

            HStack(spacing: 4) {
                ForEach(0..<totalSegments, id: \.self) { index in
                    Capsule()
                        .fill(index < filledSegments ? theme.colors.primary : theme.colors.timeline)
                        .frame(height: 4)
                }
            }
        }
    }
}
