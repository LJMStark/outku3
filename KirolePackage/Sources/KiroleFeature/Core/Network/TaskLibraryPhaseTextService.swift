import Foundation

protocol TaskLibraryPhaseTextGenerating: Sendable {
    func generate(
        task: TaskItem,
        userProfile: UserProfile,
        customCompanion: CustomCompanion?
    ) async throws -> TaskLibraryPhaseTexts
}

struct OpenAITaskLibraryPhaseTextGenerator: TaskLibraryPhaseTextGenerating {
    private let openAI: OpenAIService

    init(openAI: OpenAIService = .shared) {
        self.openAI = openAI
    }

    func generate(
        task: TaskItem,
        userProfile: UserProfile,
        customCompanion: CustomCompanion?
    ) async throws -> TaskLibraryPhaseTexts {
        try await openAI.generateTaskLibraryPhaseTexts(
            task: task,
            userProfile: userProfile,
            customCompanion: customCompanion
        )
    }
}

/// Prepares one immutable phase-text map for a task-library transaction. Each task gets at most
/// two model attempts. The deadline child freezes whatever has completed and cancels the rest;
/// callers receive one map and therefore cannot send a second version when a late request returns.
struct TaskLibraryPhaseTextService: Sendable {
    static let shared = TaskLibraryPhaseTextService()
    static let defaultTimeout: Duration = .seconds(180)

    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let generator: any TaskLibraryPhaseTextGenerating
    private let sleeper: Sleeper

    init(
        generator: any TaskLibraryPhaseTextGenerating = OpenAITaskLibraryPhaseTextGenerator(),
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.generator = generator
        self.sleeper = sleeper
    }

    func prepare(
        tasks: [TaskItem],
        userProfile: UserProfile,
        customCompanions: [CustomCompanion],
        timeout: Duration = defaultTimeout
    ) async -> [String: TaskLibraryPhaseTexts] {
        let eligible = tasks.filter { !$0.isCompleted && !$0.pendingDeletion }
        guard !eligible.isEmpty else { return [:] }

        let customCompanion = userProfile.customCompanionId.flatMap { id in
            customCompanions.first { $0.id == id }
        }
        let fallback = customCompanion == nil
            ? TaskLibraryPhaseTexts.localFallback(for: userProfile.companionCharacter)
            : TaskLibraryPhaseTexts.localFallback
        var prepared = Dictionary(
            uniqueKeysWithValues: eligible.map { ($0.hardwareIdentifier, fallback) }
        )

        return await withTaskGroup(of: PreparationOutcome.self) { group in
            for task in eligible {
                group.addTask {
                    let texts = await prepareOne(
                        task: task,
                        userProfile: userProfile,
                        customCompanion: customCompanion,
                        fallback: fallback
                    )
                    return .task(task.hardwareIdentifier, texts)
                }
            }
            group.addTask {
                do {
                    try await sleeper(timeout)
                } catch {
                    return .cancelledDeadline
                }
                return .deadline
            }

            var completedCount = 0
            while let outcome = await group.next() {
                switch outcome {
                case let .task(taskID, texts):
                    prepared[taskID] = texts
                    completedCount += 1
                    if completedCount == eligible.count {
                        group.cancelAll()
                        return prepared
                    }
                case .deadline:
                    group.cancelAll()
                    return prepared
                case .cancelledDeadline:
                    continue
                }
            }
            return prepared
        }
    }

    private func prepareOne(
        task: TaskItem,
        userProfile: UserProfile,
        customCompanion: CustomCompanion?,
        fallback: TaskLibraryPhaseTexts
    ) async -> TaskLibraryPhaseTexts {
        for _ in 0..<2 {
            guard !Task.isCancelled else { return fallback }
            do {
                let generated = try await generator.generate(
                    task: task,
                    userProfile: userProfile,
                    customCompanion: customCompanion
                )
                if let accepted = Self.accepted(generated) {
                    return accepted
                }
            } catch is CancellationError {
                return fallback
            } catch {
                guard !Task.isCancelled else { return fallback }
                continue
            }
        }
        return fallback
    }

    private static func accepted(
        _ texts: TaskLibraryPhaseTexts
    ) -> TaskLibraryPhaseTexts? {
        guard let starting = accepted(texts.starting),
              let building = accepted(texts.building),
              let deep = accepted(texts.deep) else {
            return nil
        }
        return TaskLibraryPhaseTexts(starting: starting, building: building, deep: deep)
    }

    private static func accepted(_ raw: String) -> String? {
        let containsEmoji = raw.unicodeScalars.contains {
            $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x7E)
        }
        guard !containsEmoji,
              !CompanionDialogueDisplayPolicy.containsCJKScript(raw) else {
            return nil
        }
        let sanitized = raw.asciiSanitizedForEInk()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let budgeted = CompanionTextService.enforceByteBudget(
            sanitized,
            maxBytes: DayPackTextBudget.taskSupportText
        )
        guard !budgeted.isEmpty,
              budgeted.utf8.contains(where: {
                  (0x30...0x39).contains($0)
                      || (0x41...0x5A).contains($0)
                      || (0x61...0x7A).contains($0)
              }),
              budgeted.range(of: #"^[^.!?]*[.!?]+$"#, options: .regularExpression) != nil,
              !budgeted.localizedCaseInsensitiveContains("[Error]") else {
            return nil
        }
        return budgeted
    }
}

private enum PreparationOutcome: Sendable {
    case task(String, TaskLibraryPhaseTexts)
    case deadline
    case cancelledDeadline
}
