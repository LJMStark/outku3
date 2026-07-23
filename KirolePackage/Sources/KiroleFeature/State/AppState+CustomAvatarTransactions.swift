import Foundation

enum PendingApplyRecoveryDisposition {
    case committed
    case staged
    case retransmit
}

extension AppState {
    // MARK: - Apply transaction

    func applyCustomCompanion(
        _ companion: CustomCompanion,
        previewData: Data,
        imageData: Data
    ) async throws {
        try ensureNoCustomAvatarOperation()
        let connection = customAvatarConnectionProvider()
        guard connection.isConnected, let deviceID = connection.deviceID else {
            throw CustomAvatarOperationError.deviceNotConnected
        }
        guard AvatarImageProcessor.isPNGData(imageData),
              imageData.count <= AvatarImageProcessor.maxEncodedByteCount else {
            throw CustomAvatarOperationError.missingAvatarData
        }
        let generation = beginCustomAvatarOperationGeneration()
        var operation = PendingCustomAvatarOperation(
            kind: .apply,
            phase: .preparing,
            operationID: nextCustomAvatarOperationID(),
            avatarID: companion.id,
            deviceID: deviceID,
            fileCRC32: 0,
            fileLength: 0,
            candidateCompanion: companion,
            candidatePreviewFileName: LocalStorage.pendingCustomAvatarPreviewFileName,
            candidateImageFileName: LocalStorage.pendingCustomAvatarImageFileName,
            oldSelection: CustomAvatarSelectionSnapshot(profile: userProfile)
        )
        pendingCustomAvatarOperation = operation
        customAvatarOperationState = .preparing
        do {
            // Persist intent before writing private candidate bytes. A crash or partial image
            // write can then be recovered and cleaned instead of leaving untracked photos.
            try await persistPendingCustomAvatarOperation(operation)
            try await localStorage.savePendingCustomAvatarAssets(
                previewData: previewData,
                imageData: imageData
            )
            let kriData = try await Task.detached(priority: .userInitiated) {
                try KRIEncoder.encode(pngData: imageData)
            }.value
            try ensureCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            )
            guard AvatarImageProcessor.isValidAvatarKRI(kriData) else {
                throw CustomAvatarOperationError.missingAvatarData
            }
            operation.phase = .prepared
            operation.fileLength = kriData.count
            operation.fileCRC32 = CRC32.ieee(kriData)
            try await persistPendingCustomAvatarOperation(operation)
            try await runApplyTransaction(
                operation,
                companion: companion,
                imageData: imageData,
                generation: generation,
                preparedKRIData: kriData
            )
        } catch {
            if isCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            ) {
                markCustomAvatarOperationFailure(error)
            } else if pendingCustomAvatarOperation == nil {
                do {
                    try await localStorage.clearPendingCustomAvatarOperation()
                } catch {
                    reportPersistenceError(
                        error,
                        operation: "delete",
                        target: "pending_custom_avatar_operation"
                    )
                }
            }
            throw error
        }
    }

    func runApplyTransaction(
        _ initialOperation: PendingCustomAvatarOperation,
        companion: CustomCompanion,
        imageData: Data,
        generation: UInt64,
        preparedKRIData: Data? = nil
    ) async throws {
        var operation = initialOperation
        do {
            try ensureCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            )
            let kriData: Data
            if let preparedKRIData {
                kriData = preparedKRIData
            } else {
                customAvatarOperationState = .preparing
                kriData = try await Task.detached(priority: .userInitiated) {
                    try KRIEncoder.encode(pngData: imageData)
                }.value
            }
            try ensureCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            )
            guard operation.avatarID == companion.id,
                  AvatarImageProcessor.isValidAvatarKRI(kriData) else {
                throw CustomAvatarOperationError.missingAvatarData
            }
            let crc = CRC32.ieee(kriData)
            if operation.phase == .preparing || operation.fileLength == 0 {
                operation.phase = .prepared
                operation.fileLength = kriData.count
                operation.fileCRC32 = crc
                try await persistPendingCustomAvatarOperation(operation)
            } else if operation.fileLength != kriData.count || operation.fileCRC32 != crc {
                throw CustomAvatarOperationError.missingAvatarData
            }
            try ensureExpectedDeviceConnected(operation)
            operation.phase = .transferring
            try await persistPendingCustomAvatarOperation(operation)
            customAvatarOperationState = .transferring(sentBytes: 0, totalBytes: kriData.count)
            avatarControlExpectedBufferedStatus = .staged

            let frameSender = customAvatarFrameSender
            let transferTask = Task { @MainActor in
                try await frameSender(
                    operation.operationID,
                    companion.id,
                    kriData
                ) { [weak self] sentBytes, totalBytes in
                    guard let self,
                          self.isCurrentCustomAvatarOperation(
                            operationID: operation.operationID,
                            generation: generation
                          ) else {
                        return
                    }
                    self.customAvatarOperationState = .transferring(
                        sentBytes: sentBytes,
                        totalBytes: totalBytes
                    )
                }
            }
            customAvatarPushTask = transferTask
            try await transferTask.value
            customAvatarPushTask = nil
            try ensureCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            )

            operation.phase = .awaitingValidation
            try await persistPendingCustomAvatarOperation(operation)
            customAvatarOperationState = .validating
            let staged = try await awaitAvatarControlResult(
                operationID: operation.operationID,
                expectedStatus: .staged
            )
            try ensureCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            )
            try validateStagedResult(staged, operation: operation)

            try ensureExpectedDeviceConnected(operation)
            operation.phase = .awaitingCommitResult
            try await persistPendingCustomAvatarOperation(operation)
            customAvatarOperationState = .committing
            avatarControlExpectedBufferedStatus = .committed
            try await avatarControlSender(
                .commit(operationID: operation.operationID, avatarID: companion.id)
            )
            let committed = try await awaitAvatarControlResult(
                operationID: operation.operationID,
                expectedStatus: .committed
            )
            try ensureCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            )
            try validateCommittedResult(committed, operation: operation)
            try await finalizeCommittedApply(operation)
        } catch {
            customAvatarPushTask = nil
            if isCurrentCustomAvatarOperation(
                operationID: operation.operationID,
                generation: generation
            ) {
                markCustomAvatarOperationFailure(error)
            }
            throw error
        }
    }

    func validateStagedResult(
        _ result: AvatarControlResult,
        operation: PendingCustomAvatarOperation
    ) throws {
        guard result.status == .staged,
              result.avatarState == .staged,
              result.avatarID == operation.avatarID,
              result.byteLength == UInt32(operation.fileLength),
              result.crc32 == operation.fileCRC32 else {
            throw CustomAvatarOperationError.deviceRejected("Kirole rejected the staged companion image.")
        }
    }

    func validateCommittedResult(
        _ result: AvatarControlResult,
        operation: PendingCustomAvatarOperation
    ) throws {
        guard result.status == .committed,
              result.avatarState == .committed,
              result.customActive,
              result.avatarID == operation.avatarID,
              result.byteLength == UInt32(operation.fileLength),
              result.crc32 == operation.fileCRC32 else {
            throw CustomAvatarOperationError.deviceRejected("Kirole did not commit the companion image.")
        }
    }

    func finalizeCommittedApply(
        _ operation: PendingCustomAvatarOperation
    ) async throws {
        guard let companion = operation.candidateCompanion,
              operation.avatarID == companion.id else {
            throw CustomAvatarOperationError.missingAvatarData
        }
        try await localStorage.commitPendingCustomAvatarAssets(to: companion.id)

        var updatedList = customCompanions
        if let index = updatedList.firstIndex(where: { $0.id == companion.id }) {
            updatedList[index] = companion
        } else {
            updatedList.append(companion)
        }
        try await localStorage.saveCustomCompanions(updatedList)

        let usageState = try await localStorage.loadCompanionUsageState() ?? CompanionUsageState()
        let progress = usageState.progress(forCustomCompanion: companion.id)
        var profile = userProfile
        profile.customCompanionId = companion.id
        profile.intimacyStage = operation.oldSelection.customCompanionID == companion.id
            ? operation.oldSelection.intimacyStage
            : IntimacyStage.from(bindingDays: progress.totalUsedDays)
        try await localStorage.saveUserProfile(profile)

        customCompanions = updatedList
        userProfile = profile
        try await clearPendingCustomAvatarOperation()
        customAvatarOperationState = .success
        await completePendingOnboardingAfterCustomAvatarCommitIfNeeded()
        await refreshSharedPetDialogueIfNeeded()
        await refreshHomeCompanionPresentation()
        requestBLESync(reason: "customAvatarCommitted")
    }

    /// Query before replay: a lost `committed` notify must not force a second 4-minute transfer.
    /// A known old/empty inventory restarts from chunk zero; an unrelated third identity fails.
    func pendingApplyRecoveryDisposition(
        _ operation: PendingCustomAvatarOperation,
        generation: UInt64
    ) async throws -> PendingApplyRecoveryDisposition {
        bufferedAvatarControlResults[operation.operationID] = nil
        avatarControlExpectedBufferedStatus = .state
        try await avatarControlSender(.query(operationID: operation.operationID))
        let result = try await awaitAvatarControlResult(
            operationID: operation.operationID,
            expectedStatus: .state
        )
        try ensureCurrentCustomAvatarOperation(
            operationID: operation.operationID,
            generation: generation
        )
        let candidateMatches = result.avatarID == operation.avatarID
            && result.byteLength == UInt32(operation.fileLength)
            && result.crc32 == operation.fileCRC32
        if result.avatarState == .committed,
           result.customActive,
           candidateMatches {
            return .committed
        }
        if candidateMatches, result.avatarState == .staged {
            return .staged
        }
        if candidateMatches, result.avatarState == .committed {
            let error = CustomAvatarOperationError.deviceRejected(
                "Kirole stored the candidate image but did not activate it. The previous companion was kept."
            )
            try await clearPendingCustomAvatarOperation()
            customAvatarOperationState = .failed(error.localizedDescription)
            throw error
        }
        if result.avatarState == .empty {
            return .retransmit
        }
        if let oldCustomID = operation.oldSelection.customCompanionID,
           result.avatarID == oldCustomID {
            return .retransmit
        }
        // Selecting a built-in companion disables the stored custom photo but deliberately does
        // not erase the device's single slot. If staging the new candidate was lost on reboot,
        // that inactive committed inventory is the safe old state and may be overwritten.
        if operation.oldSelection.customCompanionID == nil,
           result.avatarState == .committed,
           !result.customActive {
            return .retransmit
        }
        let error = CustomAvatarOperationError.deviceRejected(
            "Kirole contains a different companion image. The previous companion was kept."
        )
        try await clearPendingCustomAvatarOperation()
        customAvatarOperationState = .failed(error.localizedDescription)
        throw error
    }

    func commitStagedApply(
        _ initialOperation: PendingCustomAvatarOperation,
        generation: UInt64
    ) async throws {
        var operation = initialOperation
        operation.phase = .awaitingCommitResult
        try await persistPendingCustomAvatarOperation(operation)
        try ensureCurrentCustomAvatarOperation(
            operationID: operation.operationID,
            generation: generation
        )
        guard let avatarID = operation.avatarID else {
            throw CustomAvatarOperationError.missingAvatarData
        }
        try ensureExpectedDeviceConnected(operation)
        customAvatarOperationState = .committing
        avatarControlExpectedBufferedStatus = .committed
        try await avatarControlSender(
            .commit(operationID: operation.operationID, avatarID: avatarID)
        )
        let committed = try await awaitAvatarControlResult(
            operationID: operation.operationID,
            expectedStatus: .committed
        )
        try ensureCurrentCustomAvatarOperation(
            operationID: operation.operationID,
            generation: generation
        )
        try validateCommittedResult(committed, operation: operation)
        try await finalizeCommittedApply(operation)
    }

    func runPendingAbort(
        _ operation: PendingCustomAvatarOperation,
        generation: UInt64
    ) async throws {
        guard operation.kind == .apply,
              operation.phase == .awaitingAbortResult else {
            throw CustomAvatarOperationError.commitAlreadyStarted
        }
        try ensureExpectedDeviceConnected(operation)
        customAvatarOperationState = .validating
        bufferedAvatarControlResults[operation.operationID] = nil
        avatarControlExpectedBufferedStatus = .aborted
        try await avatarControlSender(.abort(operationID: operation.operationID))
        let result = try await awaitAvatarControlResult(
            operationID: operation.operationID,
            expectedStatus: .aborted
        )
        try ensureCurrentCustomAvatarOperation(
            operationID: operation.operationID,
            generation: generation
        )
        try validateAbortedResult(result, operation: operation)
        try await clearPendingCustomAvatarOperation()
        customAvatarOperationState = .idle
    }

    // MARK: - Erase transaction

    func runPendingErase(
        _ operation: PendingCustomAvatarOperation,
        generation: UInt64
    ) async throws {
        try ensureExpectedDeviceConnected(operation)
        customAvatarOperationState = .erasing
        avatarControlExpectedBufferedStatus = .erased
        switch operation.kind {
        case .eraseExact:
            guard let avatarID = operation.avatarID else {
                throw CustomAvatarOperationError.companionNotFound
            }
            try await avatarControlSender(
                .eraseExact(operationID: operation.operationID, avatarID: avatarID)
            )
        case .eraseAll:
            try await avatarControlSender(.eraseAll(operationID: operation.operationID))
        case .apply:
            return
        }
        let result = try await awaitAvatarControlResult(
            operationID: operation.operationID,
            expectedStatus: .erased
        )
        try ensureCurrentCustomAvatarOperation(
            operationID: operation.operationID,
            generation: generation
        )
        try validateErasedResult(
            result,
            exactTargetID: operation.kind == .eraseExact ? operation.avatarID : nil
        )
        switch operation.kind {
        case .eraseExact:
            if let id = operation.avatarID {
                try await removeLocalCustomCompanion(id: id)
            }
        case .eraseAll:
            // The marker may have survived a process exit between persisting eraseAll and
            // removing local data. Finish that cleanup before deleting the durable marker.
            try await removeAllLocalCustomCompanionData()
        case .apply:
            break
        }
        try await clearPendingCustomAvatarOperation()
        customAvatarOperationState = .success
    }

    func validateErasedResult(
        _ result: AvatarControlResult,
        exactTargetID: UUID?
    ) throws {
        guard result.status == .erased else {
            throw CustomAvatarOperationError.deviceRejected("Kirole did not confirm photo deletion.")
        }
        switch result.avatarState {
        case .empty:
            guard !result.customActive,
                  result.avatarID == nil,
                  result.byteLength == 0,
                  result.crc32 == 0 else {
                throw CustomAvatarOperationError.deviceRejected(
                    "Kirole returned inconsistent empty avatar inventory."
                )
            }
        case .committed:
            guard let exactTargetID,
                  let remainingID = result.avatarID,
                  remainingID != exactTargetID,
                  result.byteLength > 0 else {
                throw CustomAvatarOperationError.deviceRejected(
                    "Kirole returned inconsistent avatar inventory after deletion."
                )
            }
        case .staged:
            throw CustomAvatarOperationError.deviceRejected(
                "Kirole still has a staged avatar after deletion."
            )
        }
    }

    func validateAbortedResult(
        _ result: AvatarControlResult,
        operation: PendingCustomAvatarOperation
    ) throws {
        guard result.status == .aborted else {
            throw CustomAvatarOperationError.deviceRejected(
                "Kirole did not cancel the companion image operation."
            )
        }
        if let oldCustomID = operation.oldSelection.customCompanionID {
            guard result.avatarState == .committed,
                  result.customActive,
                  result.avatarID == oldCustomID,
                  result.byteLength > 0 else {
                throw CustomAvatarOperationError.deviceRejected(
                    "Kirole did not restore the previous companion after cancellation."
                )
            }
            return
        }
        guard !result.customActive else {
            throw CustomAvatarOperationError.deviceRejected(
                "Kirole activated a custom image after cancellation."
            )
        }
        switch result.avatarState {
        case .empty:
            guard result.avatarID == nil,
                  result.byteLength == 0,
                  result.crc32 == 0 else {
                throw CustomAvatarOperationError.deviceRejected(
                    "Kirole returned inconsistent empty avatar inventory."
                )
            }
        case .committed:
            guard result.avatarID != nil, result.byteLength > 0 else {
                throw CustomAvatarOperationError.deviceRejected(
                    "Kirole returned inconsistent avatar inventory after cancellation."
                )
            }
        case .staged:
            throw CustomAvatarOperationError.deviceRejected(
                "Kirole did not discard the staged companion image."
            )
        }
    }

    // MARK: - Result waiting

    func canBufferAvatarControlResult(
        _ result: AvatarControlResult,
        operation: PendingCustomAvatarOperation
    ) -> Bool {
        guard avatarControlExpectedBufferedStatus == result.status else { return false }
        switch result.status {
        case .staged:
            return operation.kind == .apply
                && (operation.phase == .transferring || operation.phase == .awaitingValidation)
        case .committed:
            return operation.kind == .apply && operation.phase == .awaitingCommitResult
        case .erased:
            return operation.phase == .awaitingEraseResult
        case .aborted:
            return operation.kind == .apply && operation.phase == .awaitingAbortResult
        case .state:
            return operation.kind == .apply
        }
    }

    func awaitAvatarControlResult(
        operationID: UInt32,
        expectedStatus: AvatarControlStatus
    ) async throws -> AvatarControlResult {
        avatarControlExpectedBufferedStatus = expectedStatus
        if var buffered = bufferedAvatarControlResults[operationID],
           let index = buffered.firstIndex(where: { $0.status == expectedStatus }) {
            let result = buffered.remove(at: index)
            bufferedAvatarControlResults[operationID] = buffered.isEmpty ? nil : buffered
            avatarControlExpectedBufferedStatus = nil
            return result
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                avatarControlResultWaiter = AvatarControlResultWaiter(
                    operationID: operationID,
                    expectedStatus: expectedStatus,
                    continuation: continuation
                )
                avatarControlTimeoutTask?.cancel()
                avatarControlTimeoutTask = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(for: .seconds(15))
                    } catch {
                        return
                    }
                    guard let self,
                          self.avatarControlResultWaiter?.operationID == operationID,
                          self.avatarControlResultWaiter?.expectedStatus == expectedStatus else {
                        return
                    }
                    self.resumeAvatarControlWaiter(
                        throwing: CustomAvatarOperationError.confirmationTimedOut
                    )
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeAvatarControlWaiter(throwing: CancellationError())
            }
        }
    }

    func resumeAvatarControlWaiter(throwing error: any Error) {
        avatarControlExpectedBufferedStatus = nil
        guard let waiter = avatarControlResultWaiter else { return }
        avatarControlResultWaiter = nil
        avatarControlTimeoutTask?.cancel()
        avatarControlTimeoutTask = nil
        waiter.continuation.resume(throwing: error)
    }

    // MARK: - Persistence and cleanup

    func restorePendingCustomAvatarOperation() async {
        do {
            let operation = try await localStorage.loadPendingCustomAvatarOperation()
            pendingCustomAvatarOperation = operation
            if let operation {
                customAvatarOperationState = operation.kind == .apply
                    && operation.phase != .awaitingAbortResult
                    ? .interrupted("Reconnect Kirole, then send the photo again from the beginning.")
                    : .idle
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "pending_custom_avatar_operation.json")
        }
    }

    func persistPendingCustomAvatarOperation(
        _ operation: PendingCustomAvatarOperation
    ) async throws {
        try await localStorage.savePendingCustomAvatarOperation(operation)
        pendingCustomAvatarOperation = operation
    }

    func clearPendingCustomAvatarOperation() async throws {
        try await localStorage.clearPendingCustomAvatarOperation()
        pendingCustomAvatarOperation = nil
        bufferedAvatarControlResults.removeAll()
        avatarControlExpectedBufferedStatus = nil
    }

    func removeLocalCustomCompanion(id: UUID) async throws {
        let wasActive = userProfile.customCompanionId == id
        let updatedList = customCompanions.filter { $0.id != id }
        try await localStorage.deleteCustomCompanionAssets(id: id)
        try await localStorage.saveCustomCompanions(updatedList)

        var usage = try await localStorage.loadCompanionUsageState() ?? CompanionUsageState()
        let restoredBuiltInStage = IntimacyStage.from(
            bindingDays: usage.progress(for: userProfile.companionCharacter).totalUsedDays
        )
        usage.removeProgress(forCustomCompanion: id)
        try await localStorage.saveCompanionUsageState(usage)

        customCompanions = updatedList
        if wasActive {
            var profile = userProfile
            profile.customCompanionId = nil
            profile.intimacyStage = restoredBuiltInStage
            try await localStorage.saveUserProfile(profile)
            userProfile = profile
            requestBLESync(reason: "deleteCustomCompanion")
        }
    }

    func removeAllLocalCustomCompanionData() async throws {
        try await localStorage.deleteAllCustomCompanionAssets()
        try await localStorage.deleteCustomCompanionIndex()
        var usage = try await localStorage.loadCompanionUsageState() ?? CompanionUsageState()
        let restoredBuiltInStage = IntimacyStage.from(
            bindingDays: usage.progress(for: userProfile.companionCharacter).totalUsedDays
        )
        usage.customCompanions.removeAll()
        try await localStorage.saveCompanionUsageState(usage)
        var profile = userProfile
        profile.customCompanionId = nil
        profile.intimacyStage = restoredBuiltInStage
        try await localStorage.saveUserProfile(profile)
        customCompanions = []
        userProfile = profile
    }

    func ensureNoCustomAvatarOperation() throws {
        guard pendingCustomAvatarOperation == nil,
              !customAvatarOperationState.isInProgress,
              !isCustomAvatarRetryRunning else {
            throw CustomAvatarOperationError.operationInProgress
        }
    }

    func ensureExpectedDeviceConnected(
        _ operation: PendingCustomAvatarOperation
    ) throws {
        let connection = customAvatarConnectionProvider()
        guard connection.isConnected else {
            throw CustomAvatarOperationError.deviceNotConnected
        }
        guard let expectedDeviceID = operation.deviceID,
              expectedDeviceID == connection.deviceID else {
            throw CustomAvatarOperationError.wrongDevice
        }
    }

    func beginCustomAvatarOperationGeneration() -> UInt64 {
        customAvatarOperationGeneration &+= 1
        return customAvatarOperationGeneration
    }

    func invalidateCustomAvatarOperationGeneration() {
        customAvatarOperationGeneration &+= 1
    }

    func isCurrentCustomAvatarOperation(
        operationID: UInt32,
        generation: UInt64
    ) -> Bool {
        customAvatarOperationGeneration == generation
            && pendingCustomAvatarOperation?.operationID == operationID
    }

    func ensureCurrentCustomAvatarOperation(
        operationID: UInt32,
        generation: UInt64
    ) throws {
        guard isCurrentCustomAvatarOperation(
            operationID: operationID,
            generation: generation
        ) else {
            throw CancellationError()
        }
    }

    func interruptCustomAvatarOperation(message: String) {
        invalidateCustomAvatarOperationGeneration()
        customAvatarPushTask?.cancel()
        customAvatarPushTask = nil
        resumeAvatarControlWaiter(throwing: CancellationError())
        customAvatarOperationState = .interrupted(message)
    }

    func nextCustomAvatarOperationID() -> UInt32 {
        let candidate = customAvatarOperationIDProvider()
        return candidate == 0 ? 1 : candidate
    }

    func markCustomAvatarOperationFailure(_ error: any Error) {
        avatarControlExpectedBufferedStatus = nil
        let isDisconnected: Bool
        if let bleError = error as? BLEError, case .disconnected = bleError {
            isDisconnected = true
        } else if let avatarError = error as? CustomAvatarOperationError,
                  avatarError == .deviceNotConnected {
            isDisconnected = true
        } else {
            isDisconnected = false
        }
        if error is CancellationError || isDisconnected {
            customAvatarOperationState = .interrupted(error.localizedDescription)
        } else {
            customAvatarOperationState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Immediate identity status

    func sendPetStatusNow(customActive: Bool, context: String) {
        let petSnapshot = pet
        let characterSnapshot = userProfile.companionCharacter
        let previousTask = companionIdentityStatusSendTask
        let sender = companionIdentityStatusSender
        companionIdentityStatusSendTask = Task { @MainActor in
            await previousTask?.value
            do {
                try await sender(petSnapshot, characterSnapshot, customActive)
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE PetStatus", underlying: error.localizedDescription),
                    context: context
                )
            }
        }
    }
}
