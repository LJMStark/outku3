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
            companionStyle: .encouraging,
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
        #expect(OnboardingQuestions.allQuestions.count == 8)
    }
}

// MARK: - OnboardingState Answer Tests

@MainActor
struct OnboardingStateAnswerTests {
    @Test func setSingleAnswer() {
        let state = OnboardingState()
        state.setAnswer(questionId: "companionStyle", value: "Encouraging")
        #expect(state.profile.companionStyle == .encouraging)
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
        let selected = state.selectedOptions(for: "companionStyle")
        #expect(selected.isEmpty)
    }
}
