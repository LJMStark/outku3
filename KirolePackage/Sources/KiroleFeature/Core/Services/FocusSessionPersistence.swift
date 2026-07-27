import Foundation

/// Narrow persistence boundary for the active→history focus transaction. Tests inject failures at
/// the two crash-sensitive steps; production delegates to LocalStorage's atomic JSON writes.
protocol FocusSessionPersisting: Sendable {
    func loadSessions() async throws -> [FocusSession]?
    func saveSessions(_ sessions: [FocusSession], date: Date) async throws
    func loadActiveSession() async throws -> FocusSession?
    func saveActiveSession(_ session: FocusSession) async throws
    func clearActiveSession() async throws
    func applyEnergyReward(receiptID: UUID, bottles: Int) async throws -> Int
}

struct LocalFocusSessionPersistence: FocusSessionPersisting {
    let storage: LocalStorage

    init(storage: LocalStorage = .shared) {
        self.storage = storage
    }

    func loadSessions() async throws -> [FocusSession]? {
        try await storage.loadFocusSessions()
    }

    func saveSessions(_ sessions: [FocusSession], date: Date) async throws {
        try await storage.saveFocusSessions(sessions)
        try await storage.saveFocusSessionsForDate(sessions, date: date)
    }

    func loadActiveSession() async throws -> FocusSession? {
        try await storage.loadActiveFocusSession()
    }

    func saveActiveSession(_ session: FocusSession) async throws {
        try await storage.saveActiveFocusSession(session)
    }

    func clearActiveSession() async throws {
        try await storage.clearActiveFocusSession()
    }

    func applyEnergyReward(receiptID: UUID, bottles: Int) async throws -> Int {
        try await storage.applyFocusEnergyReward(receiptID: receiptID, bottles: bottles)
    }
}
