import Foundation

extension FocusSessionService {
    /// 完成任务（短按滚轮）
    @discardableResult
    public func completeTask(
        taskId: String,
        endTime: Date = Date(),
        authoritativeElapsedSeconds: UInt32? = nil,
        focusSessionId: FocusSessionId? = nil
    ) -> Bool {
        guard bindAndMatchActiveSession(taskId: taskId, focusSessionId: focusSessionId) else {
            return false
        }
        _ = endActiveSession(
            reason: .completed,
            endTime: endTime,
            operationKey: nil,
            authoritativeElapsedSeconds: authoritativeElapsedSeconds
        )
        return true
    }

    /// 跳过任务（长按滚轮）
    @discardableResult
    public func skipTask(
        taskId: String,
        endTime: Date = Date(),
        authoritativeElapsedSeconds: UInt32? = nil,
        focusSessionId: FocusSessionId? = nil
    ) -> Bool {
        guard bindAndMatchActiveSession(taskId: taskId, focusSessionId: focusSessionId) else {
            return false
        }
        _ = endActiveSession(
            reason: .skipped,
            endTime: endTime,
            operationKey: nil,
            authoritativeElapsedSeconds: authoritativeElapsedSeconds
        )
        return true
    }

    @discardableResult
    func bindAndMatchActiveSession(
        taskId: String,
        focusSessionId: FocusSessionId?
    ) -> Bool {
        guard var session = activeSession else { return false }
        guard session.matchesHardwareCompletion(taskId: taskId, focusSessionId: focusSessionId) else {
            return false
        }
        if let incoming = focusSessionId, !incoming.isIdle, session.focusSessionId == nil {
            session.focusSessionId = incoming
            activeSession = session
        }
        return true
    }
}
