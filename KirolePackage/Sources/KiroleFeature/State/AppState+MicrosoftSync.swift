import Foundation

/// Sync orchestration for the Microsoft provider. One MSAL account and one state store back both
/// Microsoft surfaces, but only Outlook Calendar is shipped — see `IntegrationType.microsoftToDo`.
extension AppState {
    /// Microsoft To Do is not a shipped integration. Pinning this to `false` here — rather than
    /// relying on `isIntegrationConnected(.microsoftToDo)` happening to be false because the row is
    /// missing from `displayOrder` — means a stray persisted `integration_connections.json` entry
    /// cannot quietly start pulling To Do lists.
    private static let includesMicrosoftTodo = false

    public func syncMicrosoftData() async {
        guard let syncGeneration = beginExternalSync(.microsoft) else { return }
        defer { finishExternalSync(.microsoft, generation: syncGeneration) }

        let includeOutlook = isIntegrationConnected(.outlookCalendar)
            && AuthManager.shared.hasMicrosoftCalendarAccess
        let includeTodo = Self.includesMicrosoftTodo
        guard includeOutlook || includeTodo else { return }

        do {
            let result = try await microsoftSyncEngine.performSync(
                currentEvents: events.filter { $0.source == .outlook },
                currentTasks: tasks.filter { $0.source == .microsoftToDo },
                includeOutlook: includeOutlook,
                includeTodo: includeTodo
            )
            guard canCommitExternalSync(.microsoft, generation: syncGeneration),
                  result.isCurrentForAppStateCommit else { return }
            applyMicrosoftSyncResult(
                result,
                includeOutlook: includeOutlook,
                includeTodo: includeTodo
            )
            try await persistMicrosoftSyncResult(
                result,
                includeOutlook: includeOutlook,
                includeTodo: includeTodo
            )
            guard canCommitExternalSync(.microsoft, generation: syncGeneration),
                  result.isCurrentForAppStateCommit else { return }
            lastError = nil
            remoteSyncErrors.removeValue(forKey: "Microsoft")
            if result.warnings.isEmpty {
                remoteSyncWarnings.removeValue(forKey: "Microsoft")
            } else {
                remoteSyncWarnings["Microsoft"] = result.warnings.joined(separator: " | ")
            }
            markIntegrationSynced("Microsoft")
        } catch MicrosoftSyncError.fullSyncFailed(let result) {
            guard canCommitExternalSync(.microsoft, generation: syncGeneration),
                  isMicrosoftResultCurrent(result) else { return }
            guard await handleMicrosoftFailedSyncResult(
                result,
                error: MicrosoftSyncError.fullSyncFailed(result),
                includeOutlook: includeOutlook,
                includeTodo: includeTodo,
                syncGeneration: syncGeneration
            ) else { return }
        } catch MicrosoftSyncError.stateIOFailed(let failure) {
            guard canCommitExternalSync(.microsoft, generation: syncGeneration),
                  isMicrosoftResultCurrent(failure.result) else { return }
            guard await handleMicrosoftFailedSyncResult(
                failure.result,
                error: MicrosoftSyncError.stateIOFailed(failure),
                includeOutlook: includeOutlook,
                includeTodo: includeTodo,
                syncGeneration: syncGeneration
            ) else { return }
        } catch MicrosoftSyncError.staleOperation {
            return
        } catch {
            guard canCommitExternalSync(.microsoft, generation: syncGeneration) else { return }
            recordProviderSyncFailure(error, provider: "Microsoft", context: "AppState.syncMicrosoftData")
        }

        guard canCommitExternalSync(.microsoft, generation: syncGeneration) else { return }
        await applyPostSyncHooks()
    }

    /// Applies and durably mirrors an account boundary before exposing the sync error. The state
    /// cursor may have failed to save, but account B's new/empty snapshots must still replace A.
    private func handleMicrosoftFailedSyncResult(
        _ result: MicrosoftSyncResult,
        error: MicrosoftSyncError,
        includeOutlook: Bool,
        includeTodo: Bool,
        syncGeneration: UInt64
    ) async -> Bool {
        guard canCommitExternalSync(.microsoft, generation: syncGeneration),
              isMicrosoftResultCurrent(result) else { return false }
        let appliedAccountBoundary = applyMicrosoftFailedSyncResult(
            result,
            includeOutlook: includeOutlook,
            includeTodo: includeTodo
        )
        if appliedAccountBoundary {
            do {
                try await persistMicrosoftSyncResult(
                    result,
                    includeOutlook: includeOutlook,
                    includeTodo: includeTodo
                )
            } catch {
                ErrorReporter.log(
                    .persistence(
                        operation: "save",
                        target: "Microsoft provider snapshots",
                        underlying: error.localizedDescription
                    ),
                    context: "AppState.syncMicrosoftData.accountBoundary"
                )
            }
        }
        guard canCommitExternalSync(.microsoft, generation: syncGeneration),
              isMicrosoftResultCurrent(result) else { return false }
        recordProviderSyncFailure(
            error,
            provider: "Microsoft",
            context: "AppState.syncMicrosoftData"
        )
        return true
    }

    private func isMicrosoftResultCurrent(_ result: MicrosoftSyncResult) -> Bool {
        result.isCurrentForAppStateCommit
    }

    /// Applies one provider-scoped Microsoft result without touching unrelated sources.
    /// An account change replaces both Microsoft snapshots so data from the previous identity
    /// cannot survive behind a disabled scope or a failed first pull.
    func applyMicrosoftSyncResult(
        _ result: MicrosoftSyncResult,
        includeOutlook: Bool,
        includeTodo: Bool
    ) {
        if includeOutlook || result.didChangeAccount {
            events = events.filter { $0.source != .outlook } + result.events
        }
        if includeTodo || result.didChangeAccount {
            mergeRemoteTasks(from: .microsoftToDo, with: result.tasks)
        }
    }

    /// A failed sync only carries a replacement instruction when the account changed. Same-account
    /// failures leave the current in-memory snapshot alone so concurrent local edits cannot be
    /// overwritten by the pre-request snapshot held by the sync engine.
    @discardableResult
    func applyMicrosoftFailedSyncResult(
        _ result: MicrosoftSyncResult,
        includeOutlook: Bool,
        includeTodo: Bool
    ) -> Bool {
        guard result.didChangeAccount else { return false }
        applyMicrosoftSyncResult(
            result,
            includeOutlook: includeOutlook,
            includeTodo: includeTodo
        )
        return true
    }

    /// Attempts both provider files even if the first write fails. Their files are individually
    /// atomic; this prevents one failed save from leaving the other account snapshot untouched.
    private func persistMicrosoftSyncResult(
        _ result: MicrosoftSyncResult,
        includeOutlook: Bool,
        includeTodo: Bool
    ) async throws {
        var firstError: (any Error)?
        if includeOutlook || result.didChangeAccount {
            do {
                try await localStorage.saveEvents(events)
            } catch {
                firstError = error
            }
        }
        if includeTodo || result.didChangeAccount {
            do {
                try await localStorage.saveTasks(tasks)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

}
