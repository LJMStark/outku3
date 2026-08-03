import Foundation
@testable import KiroleFeature

enum ScenarioDevicePage: Codable, Equatable, Sendable {
    case overview
    case focus(taskID: String)
    case dailySummary
    case screensaver
}

struct ScenarioDeviceFocus: Codable, Equatable, Sendable {
    let taskID: String
    let startedAt: Date
}

struct ScenarioDeviceStaticFeedback: Equatable, Sendable {
    let soundCount: Int
    let hapticCount: Int
    let animationCount: Int

    static let none = ScenarioDeviceStaticFeedback(
        soundCount: 0,
        hapticCount: 0,
        animationCount: 0
    )
}

struct ScenarioDeviceLocalPageState: Equatable, Sendable {
    private(set) var currentPage: ScenarioDevicePage = .overview
    private(set) var focus: ScenarioDeviceFocus?
    private(set) var staticFeedback: ScenarioDeviceStaticFeedback = .none
    private(set) var rewardCount = 0

    private var focusSourcePage: ScenarioDevicePage?
    private var dailySummarySourcePage: ScenarioDevicePage?
    private var screensaverSourcePage: ScenarioDevicePage?

    mutating func showPageForTesting(_ page: ScenarioDevicePage) {
        currentPage = page
    }

    mutating func setFocusForTesting(_ focus: ScenarioDeviceFocus?) {
        self.focus = focus
    }

    mutating func enterFocus(taskID: String, at now: Date) throws {
        guard case .focus = currentPage else {
            focusSourcePage = currentPage
            currentPage = .focus(taskID: taskID)
            focus = ScenarioDeviceFocus(taskID: taskID, startedAt: now)
            return
        }
        throw AppDeviceScenarioError.invalidDevicePageAction
    }

    mutating func exitFocus(taskID: String) throws {
        guard currentPage == .focus(taskID: taskID),
              focus?.taskID == taskID else {
            throw AppDeviceScenarioError.invalidDevicePageAction
        }
        currentPage = focusSourcePage ?? .overview
        focusSourcePage = nil
        focus = nil
    }

    mutating func showDailySummary() {
        guard currentPage != .dailySummary else { return }
        dailySummarySourcePage = currentPage
        currentPage = .dailySummary
    }

    mutating func exitDailySummary() throws {
        guard currentPage == .dailySummary else {
            throw AppDeviceScenarioError.invalidDevicePageAction
        }
        currentPage = dailySummarySourcePage ?? .overview
        dailySummarySourcePage = nil
    }

    mutating func enterScreensaver() {
        guard currentPage != .screensaver else { return }
        screensaverSourcePage = currentPage
        currentPage = .screensaver
    }

    mutating func exitScreensaver() throws {
        guard currentPage == .screensaver else {
            throw AppDeviceScenarioError.invalidDevicePageAction
        }
        currentPage = screensaverSourcePage ?? .overview
        screensaverSourcePage = nil
    }
}

enum ScenarioDeviceEventCodec {
    static func taskOperationRecord(
        action: TaskListSnapshotAction,
        taskID: String,
        operationID: UInt32,
        timestamp: Date
    ) throws -> Data {
        let taskIDBytes = Data(taskID.utf8)
        let seconds = timestamp.timeIntervalSince1970.rounded(.down)
        guard action == .completeTask || action == .skipTask,
              operationID != 0,
              (1...36).contains(taskIDBytes.count),
              seconds >= 0,
              seconds <= TimeInterval(UInt32.max) else {
            throw AppDeviceScenarioError.invalidOfflineTaskAction
        }

        var record = Data([action.rawValue, 0x01])
        record.appendBigEndian(operationID)
        record.append(UInt8(taskIDBytes.count))
        record.append(taskIDBytes)
        record.appendBigEndian(UInt32(seconds))
        return record
    }
}

extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else { return [] }
        return stride(from: 0, to: count, by: maxCount).map { start in
            Array(self[start..<Swift.min(start + maxCount, count)])
        }
    }
}
