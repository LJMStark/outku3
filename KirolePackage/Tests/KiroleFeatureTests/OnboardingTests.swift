import Testing
@testable import KiroleFeature
import Foundation

// MARK: - OnboardingState Navigation Tests

@MainActor
struct OnboardingStateNavigationTests {
    @Test func goNextIncrementsPage() {
        let state = OnboardingState()
        state.goNext()
        #expect(state.currentPage == 1)
    }

    @Test func goBackDecrementsPage() {
        let state = OnboardingState()
        state.currentPage = 5
        state.goBack()
        #expect(state.currentPage == 4)
    }

    @Test func goBackAtZeroStaysAtZero() {
        let state = OnboardingState()
        state.goBack()
        #expect(state.currentPage == 0)
    }

    @Test func goNextAtMaxStaysAtMax() {
        let state = OnboardingState()
        state.currentPage = 13
        state.goNext()
        #expect(state.currentPage == 13)
    }

    @Test func directionIsPositiveOnNext() {
        let state = OnboardingState()
        state.goNext()
        #expect(state.direction == 1)
    }

    @Test func directionIsNegativeOnBack() {
        let state = OnboardingState()
        state.currentPage = 5
        state.goBack()
        #expect(state.direction == -1)
    }
}

// MARK: - OnboardingProfile Codable Tests

struct OnboardingProfileCodableTests {
    @Test func profileEncodeDecode() throws {
        let profile = OnboardingProfile(
            companionCharacter: .nook,
            motivationStyle: .encouragement,
            calendarUsage: .everything,
            taskTracking: .cantLive,
            distractionSources: [.notifications, .appSwitching],
            reminderPreference: .gentleNudge,
            taskApproach: .selfBreak,
            timeControl: .someControl,
            selectedTheme: "Classic Warm",
            onboardingCompletedAt: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OnboardingProfile.self, from: data)

        #expect(decoded == profile)
    }

    @Test func defaultProfileHasNilCompletedAt() {
        let profile = OnboardingProfile()
        #expect(profile.onboardingCompletedAt == nil)
        #expect(profile.distractionSources.isEmpty)
    }
}

// MARK: - Question Data Integrity Tests

struct OnboardingQuestionDataTests {
    @Test func allQuestionsHaveUniqueIds() {
        let ids = OnboardingQuestions.allQuestions.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count)
    }

    @Test func allQuestionsHaveOptions() {
        for question in OnboardingQuestions.allQuestions {
            #expect(question.options.count >= 2, "Question '\(question.id)' should have at least 2 options")
        }
    }

    @Test func questionOptionsHaveUniqueIds() {
        for question in OnboardingQuestions.allQuestions {
            let optionIds = question.options.map(\.id)
            let uniqueOptionIds = Set(optionIds)
            #expect(optionIds.count == uniqueOptionIds.count, "Question '\(question.id)' has duplicate option ids")
        }
    }

    @Test func questionCount() {
        #expect(OnboardingQuestions.allQuestions.count == 7)
    }
}

// MARK: - OnboardingState Validation Tests

@MainActor
struct OnboardingStateValidationTests {
    @Test func canAdvanceReturnsTrueForNonQuestionnairePage() {
        let state = OnboardingState()
        for page in [0, 1, 2, 3, 4, 12] {
            #expect(state.canAdvance(from: page), "Page \(page) should always allow advance")
        }
    }

    @Test func canAdvanceReturnsFalseWhenAnswerMissing() {
        let state = OnboardingState()
        // All questionnaire pages (5-11) start empty
        for page in 5...11 {
            #expect(!state.canAdvance(from: page), "Page \(page) should block advance without answer")
        }
    }

    @Test func canAdvanceReturnsTrueAfterAnswering() {
        let state = OnboardingState()
        state.setAnswer(questionId: "motivationStyle", value: "encouragement")
        #expect(state.canAdvance(from: 5))
    }

    @Test func isProfileCompleteIsFalseWithPartialAnswers() {
        let state = OnboardingState()
        state.setAnswer(questionId: "motivationStyle", value: "encouragement")
        #expect(!state.isProfileComplete)
    }

    @Test func isProfileCompleteIsTrueWithAllAnswers() {
        let state = OnboardingState()
        state.setAnswer(questionId: "motivationStyle", value: "encouragement")
        state.setAnswer(questionId: "calendarUsage", value: "everything")
        state.setAnswer(questionId: "taskTracking", value: "cant-live")
        state.toggleMultiAnswer(questionId: "distractionSources", optionId: "notifications")
        state.setAnswer(questionId: "reminderPreference", value: "gentleNudge")
        state.setAnswer(questionId: "taskApproach", value: "self-break")
        state.setAnswer(questionId: "timeControl", value: "in-control")
        #expect(state.isProfileComplete)
    }

    @Test func firstIncompletePagePointsToFirstMissingAnswer() {
        let state = OnboardingState()
        state.setAnswer(questionId: "motivationStyle", value: "encouragement")
        // calendarUsage (page 6) is the next missing one
        #expect(state.firstIncompletePage == 6)
    }

    @Test func firstIncompletePageIsNilWhenAllAnswered() {
        let state = OnboardingState()
        state.setAnswer(questionId: "motivationStyle", value: "encouragement")
        state.setAnswer(questionId: "calendarUsage", value: "everything")
        state.setAnswer(questionId: "taskTracking", value: "cant-live")
        state.toggleMultiAnswer(questionId: "distractionSources", optionId: "notifications")
        state.setAnswer(questionId: "reminderPreference", value: "gentleNudge")
        state.setAnswer(questionId: "taskApproach", value: "self-break")
        state.setAnswer(questionId: "timeControl", value: "in-control")
        #expect(state.firstIncompletePage == nil)
    }

    @Test func goNextBlocksOnUnansweredQuestionnairePage() {
        let state = OnboardingState()
        state.currentPage = 5 // motivationStyle — unanswered
        state.goNext()
        #expect(state.currentPage == 5, "Should not advance past an unanswered questionnaire page")
    }

    @Test func goNextAllowsAdvanceAfterAnswer() {
        let state = OnboardingState()
        state.currentPage = 5
        state.setAnswer(questionId: "motivationStyle", value: "encouragement")
        state.goNext()
        #expect(state.currentPage == 6)
    }
}

// MARK: - OnboardingState Answer Tests

@MainActor
struct OnboardingStateAnswerTests {
    @Test func setSingleAnswer() {
        let state = OnboardingState()
        state.setAnswer(questionId: "companionCharacter", value: "nook")
        #expect(state.profile.companionCharacter == .nook)
    }

    @Test func toggleMultiAnswer() {
        let state = OnboardingState()
        state.toggleMultiAnswer(questionId: "distractionSources", optionId: "notifications")
        #expect(state.profile.distractionSources.contains(.notifications))

        state.toggleMultiAnswer(questionId: "distractionSources", optionId: "app-switching")
        #expect(state.profile.distractionSources.count == 2)

        // Toggle off
        state.toggleMultiAnswer(questionId: "distractionSources", optionId: "notifications")
        #expect(!state.profile.distractionSources.contains(.notifications))
        #expect(state.profile.distractionSources.count == 1)
    }

    @Test func selectedOptionsReturnsCorrectValues() {
        let state = OnboardingState()
        state.setAnswer(questionId: "calendarUsage", value: "everything")
        let selected = state.selectedOptions(for: "calendarUsage")
        #expect(selected == ["everything"])
    }

    @Test func selectedOptionsEmptyByDefault() {
        let state = OnboardingState()
        let selected = state.selectedOptions(for: "companionCharacter")
        #expect(selected.isEmpty)
    }
}
