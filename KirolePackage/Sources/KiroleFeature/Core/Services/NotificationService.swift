import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Notification Service

/// iOS 本地/远程通知服务，与 SmartReminderService 配合推送提醒到 iOS 端
@Observable
@MainActor
public final class NotificationService {
    public static let shared = NotificationService()

    public private(set) var isAuthorized = false

    private init() {}

    // MARK: - Authorization

    /// 请求通知权限
    public func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    /// 检查当前授权状态
    public func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Local Notifications

    /// 从 SmartReminderResult 发送本地通知
    public func scheduleLocalNotification(from reminder: SmartReminderResult) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: reminder.reason)
        content.body = reminder.text
        content.sound = .default

        if let taskTitle = reminder.taskTitle {
            content.userInfo = ["taskTitle": taskTitle]
        }

        let request = UNNotificationRequest(
            identifier: "smart-reminder-\(reminder.reason.rawValue)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // 立即发送
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("[NotificationService] Failed to schedule notification: \(error.localizedDescription)")
        }
    }

    /// 清除所有已投递的通知
    public func clearDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    // MARK: - Remote Notifications

    /// 注册远程推送（需在 AppDelegate 或 App 入口调用）
    public func registerForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    // MARK: - Private

    private func notificationTitle(for reason: ReminderReason) -> String {
        switch reason {
        case .deadline:
            return "Task Due Soon"
        case .streakProtect:
            return "Protect Your Streak"
        case .idle:
            return "Time to Focus"
        case .gentleNudge:
            return "Gentle Reminder"
        }
    }
}
