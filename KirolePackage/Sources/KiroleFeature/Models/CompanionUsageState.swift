import Foundation

public struct ConsecutiveUsageProgress: Sendable, Codable, Equatable {
    public var currentStreak: Int
    public var lastUsedDate: Date?

    public init(currentStreak: Int = 0, lastUsedDate: Date? = nil) {
        self.currentStreak = currentStreak
        self.lastUsedDate = lastUsedDate
    }

    @discardableResult
    public mutating func registerUse(on date: Date, calendar: Calendar = .current) -> Bool {
        if let lastUsedDate, calendar.isDate(lastUsedDate, inSameDayAs: date) {
            return false
        }

        let previousDay = calendar.date(byAdding: .day, value: -1, to: date)
        if let lastUsedDate,
           let previousDay,
           calendar.isDate(lastUsedDate, inSameDayAs: previousDay) {
            currentStreak = max(1, currentStreak + 1)
        } else {
            currentStreak = 1
        }

        lastUsedDate = date
        return true
    }
}

public struct CompanionBindingProgress: Sendable, Codable, Equatable {
    public var totalUsedDays: Int
    public var lastUsedDate: Date?

    public init(totalUsedDays: Int = 0, lastUsedDate: Date? = nil) {
        self.totalUsedDays = totalUsedDays
        self.lastUsedDate = lastUsedDate
    }

    @discardableResult
    public mutating func registerUse(on date: Date, calendar: Calendar = .current) -> Bool {
        if let lastUsedDate, calendar.isDate(lastUsedDate, inSameDayAs: date) {
            return false
        }

        totalUsedDays += 1
        lastUsedDate = date
        return true
    }
}

public struct CompanionUsageState: Sendable, Codable, Equatable {
    public var joy: CompanionBindingProgress
    public var silas: CompanionBindingProgress
    public var nova: CompanionBindingProgress
    /// Custom companions are separate identities. Their binding days must not inherit the
    /// last built-in character's progress or another custom companion's relationship history.
    public var customCompanions: [UUID: CompanionBindingProgress]

    public init(
        joy: CompanionBindingProgress = CompanionBindingProgress(),
        silas: CompanionBindingProgress = CompanionBindingProgress(),
        nova: CompanionBindingProgress = CompanionBindingProgress(),
        customCompanions: [UUID: CompanionBindingProgress] = [:]
    ) {
        self.joy = joy
        self.silas = silas
        self.nova = nova
        self.customCompanions = customCompanions
    }

    public func progress(for character: CompanionCharacter) -> CompanionBindingProgress {
        switch character {
        case .joy:
            return joy
        case .silas:
            return silas
        case .nova:
            return nova
        }
    }

    public mutating func setProgress(_ progress: CompanionBindingProgress, for character: CompanionCharacter) {
        switch character {
        case .joy:
            joy = progress
        case .silas:
            silas = progress
        case .nova:
            nova = progress
        }
    }

    public func progress(forCustomCompanion id: UUID) -> CompanionBindingProgress {
        customCompanions[id] ?? CompanionBindingProgress()
    }

    public mutating func setProgress(
        _ progress: CompanionBindingProgress,
        forCustomCompanion id: UUID
    ) {
        customCompanions[id] = progress
    }

    public mutating func removeProgress(forCustomCompanion id: UUID) {
        customCompanions[id] = nil
    }
}
