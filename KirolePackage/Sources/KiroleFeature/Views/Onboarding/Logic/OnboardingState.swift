import SwiftUI

// MARK: - Onboarding State

@Observable
@MainActor
public final class OnboardingState {
    public var currentPage: Int = 0
    public var direction: Int = 1
    public var profile: OnboardingProfile = OnboardingProfile()
    public var soundEnabled: Bool = true

    private let maxPage = 14

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
        case "discovery":
            profile.discoverySource = DiscoverySource(rawValue: value)
        case "struggles":
            profile.struggle = Struggle(rawValue: value)
        case "scheduleFullness":
            profile.scheduleFullness = ScheduleFullness(rawValue: value)
        case "schedulePredictability":
            profile.schedulePredictability = SchedulePredictability(rawValue: value)
        case "calendarUsage":
            profile.calendarUsage = CalendarUsage(rawValue: value)
        case "taskTracking":
            profile.taskTracking = TaskTracking(rawValue: value)
        case "timeControl":
            profile.timeControl = TimeControl(rawValue: value)
        default:
            break
        }
    }

    public func toggleMultiAnswer(questionId: String, optionId: String) {
        switch questionId {
        case "userType":
            if let type = OnboardingUserType(rawValue: optionId) {
                if let index = profile.userTypes.firstIndex(of: type) {
                    profile.userTypes.remove(at: index)
                } else {
                    profile.userTypes.append(type)
                }
            }
        default:
            break
        }
    }

    public func selectedOptions(for questionId: String) -> [String] {
        switch questionId {
        case "discovery":
            return profile.discoverySource.map { [$0.rawValue] } ?? []
        case "userType":
            return profile.userTypes.map(\.rawValue)
        case "struggles":
            return profile.struggle.map { [$0.rawValue] } ?? []
        case "scheduleFullness":
            return profile.scheduleFullness.map { [$0.rawValue] } ?? []
        case "schedulePredictability":
            return profile.schedulePredictability.map { [$0.rawValue] } ?? []
        case "calendarUsage":
            return profile.calendarUsage.map { [$0.rawValue] } ?? []
        case "taskTracking":
            return profile.taskTracking.map { [$0.rawValue] } ?? []
        case "timeControl":
            return profile.timeControl.map { [$0.rawValue] } ?? []
        default:
            return []
        }
    }
}
