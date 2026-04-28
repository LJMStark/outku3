import SwiftUI

// MARK: - Onboarding State

@Observable
@MainActor
public final class OnboardingState {
    public var currentPage: Int = 0
    public var direction: Int = 1
    public var profile: OnboardingProfile = OnboardingProfile()
    public var soundEnabled: Bool = true

    private let maxPage = 12

    public init() {}

    public func goNext() {
        guard currentPage < maxPage, canAdvance(from: currentPage) else { return }
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
        case "companionCharacter":
            profile.companionCharacter = CompanionCharacter(rawValue: value)
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

    public func canAdvance(from page: Int) -> Bool {
        switch page {
        case 5: return profile.motivationStyle != nil
        case 6: return profile.calendarUsage != nil
        case 7: return profile.taskTracking != nil
        case 8: return !profile.distractionSources.isEmpty
        case 9: return profile.reminderPreference != nil
        case 10: return profile.taskApproach != nil
        case 11: return profile.timeControl != nil
        default: return true
        }
    }

    public var isProfileComplete: Bool {
        (5...11).allSatisfy { canAdvance(from: $0) }
    }

    public var firstIncompletePage: Int? {
        (5...11).first { !canAdvance(from: $0) }
    }

    public func selectedOptions(for questionId: String) -> [String] {
        switch questionId {
        case "companionCharacter":
            return profile.companionCharacter.map { [$0.rawValue] } ?? []
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
