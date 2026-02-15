import SwiftUI

// MARK: - Onboarding State

@Observable
@MainActor
public final class OnboardingState {
    public var currentPage: Int = 0
    public var direction: Int = 1
    public var profile: OnboardingProfile = OnboardingProfile()
    public var soundEnabled: Bool = true

    private let maxPage = 13

    public init() {}

    public func goNext() {
        guard currentPage < maxPage else { return }
        direction = 1
        currentPage += 1
    }

    public func goBack() {
        guard currentPage > 0 else { return }
        direction = -1
        currentPage -= 1
    }

    public func setAnswer(questionId: String, value: String) {
        switch questionId {
        case "companionStyle":
            profile.companionStyle = CompanionStyle(rawValue: value)
        case "motivationStyle":
            profile.motivationStyle = MotivationStyle(rawValue: value)
        case "calendarUsage":
            profile.calendarUsage = CalendarUsage(rawValue: value)
        case "taskTracking":
            profile.taskTracking = TaskTracking(rawValue: value)
        case "reminderPreference":
            profile.reminderPreference = ReminderPreference(rawValue: value)
        case "taskApproach":
            profile.taskApproach = TaskApproach(rawValue: value)
        case "timeControl":
            profile.timeControl = TimeControl(rawValue: value)
        default:
            break
        }
    }

    public func toggleMultiAnswer(questionId: String, optionId: String) {
        switch questionId {
        case "distractionSources":
            if let source = DistractionSource(rawValue: optionId) {
                if let index = profile.distractionSources.firstIndex(of: source) {
                    profile.distractionSources.remove(at: index)
                } else {
                    profile.distractionSources.append(source)
                }
            }
        default:
            break
        }
    }

    public func selectedOptions(for questionId: String) -> [String] {
        switch questionId {
        case "companionStyle":
            return profile.companionStyle.map { [$0.rawValue] } ?? []
        case "motivationStyle":
            return profile.motivationStyle.map { [$0.rawValue] } ?? []
        case "calendarUsage":
            return profile.calendarUsage.map { [$0.rawValue] } ?? []
        case "taskTracking":
            return profile.taskTracking.map { [$0.rawValue] } ?? []
        case "distractionSources":
            return profile.distractionSources.map(\.rawValue)
        case "reminderPreference":
            return profile.reminderPreference.map { [$0.rawValue] } ?? []
        case "taskApproach":
            return profile.taskApproach.map { [$0.rawValue] } ?? []
        case "timeControl":
            return profile.timeControl.map { [$0.rawValue] } ?? []
        default:
            return []
        }
    }
}
