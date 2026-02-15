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
        state.currentPage = 14
        state.goNext()
        #expect(state.currentPage == 14)
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
            discoverySource: .chatgpt,
            userTypes: [.multipleCalendars, .brainCluttered],
            struggle: .loseFocus,
            scheduleFullness: .absolutelyPacked,
            schedulePredictability: .depends,
            calendarUsage: .everything,
            taskTracking: .cantLive,
            timeControl: .someControl,
            selectedTheme: "Classic Warm",
            selectedAvatar: .inku,
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
        #expect(profile.userTypes.isEmpty)
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
        state.setAnswer(questionId: "discovery", value: "chatgpt")
        #expect(state.profile.discoverySource == .chatgpt)
    }

    @Test func toggleMultiAnswer() {
        let state = OnboardingState()
        state.toggleMultiAnswer(questionId: "userType", optionId: "multiple-calendars")
        #expect(state.profile.userTypes.contains(.multipleCalendars))

        state.toggleMultiAnswer(questionId: "userType", optionId: "brain-cluttered")
        #expect(state.profile.userTypes.count == 2)

        // Toggle off
        state.toggleMultiAnswer(questionId: "userType", optionId: "multiple-calendars")
        #expect(!state.profile.userTypes.contains(.multipleCalendars))
        #expect(state.profile.userTypes.count == 1)
    }

    @Test func selectedOptionsReturnsCorrectValues() {
        let state = OnboardingState()
        state.setAnswer(questionId: "struggles", value: "lose-focus")
        let selected = state.selectedOptions(for: "struggles")
        #expect(selected == ["lose-focus"])
    }

    @Test func selectedOptionsEmptyByDefault() {
        let state = OnboardingState()
        let selected = state.selectedOptions(for: "discovery")
        #expect(selected.isEmpty)
    }
}
