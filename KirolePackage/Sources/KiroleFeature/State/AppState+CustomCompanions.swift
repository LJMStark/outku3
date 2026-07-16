// NOTE: try? is discouraged in this codebase. Use do-try-catch + ErrorReporter.log instead.
import Foundation

extension AppState {

    // MARK: - Lifecycle

    /// Create a new custom companion, persist its metadata + assets, and make it active.
    /// Throws on persistence failure so the UI can surface the error and the user can retry —
    /// silently swallowing the error here used to leave a customCompanionId pointing at a
    /// companion that had never been written to disk.
    @discardableResult
    public func addCustomCompanion(
        name: String,
        relationship: CompanionRelationship,
        personaVoice: CompanionPersonaVoice,
        customPrompt: String = "",
        curiosityLevel: Double = 0.5,
        humorLevel: Double = 0.5,
        strictnessLevel: Double = 0.3,
        backstory: String = "",
        sensitiveBoundary: String = "",
        previewData: Data,
        imageData: Data
    ) async throws -> CustomCompanion {
        let id = UUID()
        let companion = CustomCompanion(
            id: id,
            name: name,
            relationship: relationship,
            personaVoice: personaVoice,
            customPrompt: customPrompt,
            curiosityLevel: curiosityLevel,
            humorLevel: humorLevel,
            strictnessLevel: strictnessLevel,
            backstory: backstory,
            sensitiveBoundary: sensitiveBoundary,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id)
        )

        // Persist assets first; if this fails we never touch in-memory or selection state.
        try await localStorage.saveCustomCompanionAssets(
            id: id,
            previewData: previewData,
            imageData: imageData
        )

        // Build the would-be list and try to persist before mutating shared state. If list
        // persistence fails, roll back the asset write so we don't leak orphan files.
        let updatedList = customCompanions + [companion]
        do {
            try await localStorage.saveCustomCompanions(updatedList)
        } catch {
            let listSaveError = error
            do {
                try await localStorage.deleteCustomCompanionAssets(id: id)
            } catch {
                reportPersistenceError(error, operation: "delete", target: "custom_companion_assets")
                ErrorReporter.log(error, context: "AppState.addCustomCompanion.rollback")
            }
            throw listSaveError
        }

        customCompanions = updatedList
        selectCustomCompanion(id: id)
        return companion
    }

    /// Replace an existing custom companion's metadata (name / relationship / voice / roast).
    /// Avatar assets are immutable here — re-upload requires deleting and recreating.
    /// Bumps `updatedAt` so downstream caches (e.g. home dialogue fingerprint) invalidate
    /// even if the caller forgot to set it.
    public func updateCustomCompanion(_ updated: CustomCompanion) {
        guard let index = customCompanions.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        var bumped = updated
        bumped.updatedAt = Date()
        customCompanions[index] = bumped
        persistCustomCompanionsList()
    }

    /// Delete a custom companion (its metadata + assets) and snap back to the built-in
    /// character if it was active.
    public func deleteCustomCompanion(id: UUID) {
        let wasActive = userProfile.customCompanionId == id
        if wasActive {
            // 0x15 PNG 最坏要发 1-2 分钟；删除时不取消，半路中的旧流会在删除后继续写完，
            // 反过来覆盖设备身份。先停流并清掉待重发状态，旧头像不能再赢回来。
            customAvatarPushTask?.cancel()
            isCustomAvatarPendingBLEPush = false
            customAvatarFlushAttempts = 0
            Task { @MainActor in
                await localStorage.clearPendingCustomCompanionPush()
            }
        }
        customCompanions.removeAll { $0.id == id }

        if wasActive {
            var profile = userProfile
            profile.customCompanionId = nil
            updateUserProfile(profile)
        }

        Task { @MainActor in
            do {
                try await localStorage.deleteCustomCompanionAssets(id: id)
            } catch {
                reportPersistenceError(error, operation: "delete", target: "custom_companion_assets")
            }
        }
        persistCustomCompanionsList()
    }

    // MARK: - Selection

    /// Switching to a new companion identity resets intimacy back to acquaintance —
    /// staying at "close friend" while meeting a brand-new persona would make the AI
    /// open with an unearned tone. Selecting the same companion again is a no-op for intimacy.
    public func selectBuiltInCompanion(_ character: CompanionCharacter) {
        // 0x15 PNG 最坏要发 1-2 分钟；切回内置伙伴时必须停掉半路中的自定义头像流，
        // 否则旧流稍后写完会覆盖刚切换的内置身份，形成 stale-stream-wins。
        customAvatarPushTask?.cancel()
        isCustomAvatarPendingBLEPush = false
        customAvatarFlushAttempts = 0
        Task { @MainActor in
            await localStorage.clearPendingCustomCompanionPush()
        }
        let isDifferentIdentity = userProfile.currentSelection != .builtIn(character)
        var profile = userProfile
        profile.companionCharacter = character
        profile.customCompanionId = nil
        if isDifferentIdentity {
            profile.intimacyStage = .acquaintance
        }
        updateUserProfile(profile)
        // v2.5.20: 伙伴切换不再等节流窗——立即单发一帧 PetStatus(0x01) 携带新 characterId
        // （与自定义头像的立即推送 0x15 同待遇）。character 仍被有意排除在 DayPack 指纹外
        // （2026-07-04 审计 F2 决定保留），常规每轮 sync 照发兜底；断连时跳过即可，
        // 下一轮 sync 自带最新值。
        Task { @MainActor in
            guard BLEService.shared.connectionState.isConnected else { return }
            do {
                try await BLEService.shared.sendPetStatus(pet, companionCharacter: character)
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE PetStatus", underlying: error.localizedDescription),
                    context: "AppState.selectBuiltInCompanion"
                )
            }
        }
        requestBLESync(reason: "selectBuiltInCompanion")
    }

    public func selectCustomCompanion(id: UUID) {
        guard customCompanions.contains(where: { $0.id == id }) else { return }
        let isDifferentIdentity = userProfile.currentSelection != .custom(id)
        var profile = userProfile
        profile.customCompanionId = id
        if isDifferentIdentity {
            profile.intimacyStage = .acquaintance
        }
        updateUserProfile(profile)
        requestBLESync(reason: "selectCustomCompanion")

        // Re-push the avatar PNG so the device shows the newly active avatar.
        // Cancel any in-flight push first: BLE 写锁只串行单个 packet，两条 ~2000 片的
        // 0x15 流会逐片交错，旧选择可能最后完成反杀新选择（写循环见 Task.checkCancellation）。
        customAvatarPushTask?.cancel()
        customAvatarPushTask = Task { @MainActor in
            guard let imageData = await localStorage.loadCustomCompanionImageData(id: id) else { return }
            customAvatarFlushAttempts = 0  // fresh retry budget for the newly selected avatar
            await pushCustomAvatarFrame(imageData: imageData, companionId: id)
        }
    }

    // MARK: - Helpers

    public var activeCustomCompanion: CustomCompanion? {
        guard let id = userProfile.customCompanionId else { return nil }
        return customCompanions.first { $0.id == id }
    }

    private func persistCustomCompanionsList() {
        let snapshot = customCompanions
        Task { @MainActor in
            do {
                try await localStorage.saveCustomCompanions(snapshot)
            } catch {
                reportPersistenceError(error, operation: "save", target: "custom_companions.json")
            }
        }
    }

    /// Sends the avatar PNG frame via BLE. On failure, queues the companion ID in LocalStorage
    /// so `flushPendingCustomCompanionPushIfNeeded` can retry on the next BLE reconnect.
    private func pushCustomAvatarFrame(imageData: Data, companionId: UUID) async {
        // Wire-contract guard (v2.5.24): the persisted asset must be a PNG within the
        // documented ≤1MiB budget before it touches BLE.
        // - Non-PNG bytes = pre-PNG installs' 4bpp pixel data (can never start with the
        //   PNG signature) — sending them as SubVersion 0x02 would hand firmware garbage.
        // - Oversize with a valid signature = corrupted/replaced file; §4.12 promises the
        //   device never receives >1,048,576 PNG bytes, so enforce it at the BLE exit too.
        // Either way: drop the push (and any pending marker) instead of retrying forever;
        // re-creating the companion regenerates a proper PNG.
        guard AvatarImageProcessor.isPNGData(imageData),
              imageData.count <= AvatarImageProcessor.maxEncodedByteCount else {
            ErrorReporter.log(
                .sync(
                    component: "BLE CustomAvatarFrame",
                    underlying: "Persisted avatar asset rejected (not PNG or >1MiB; \(imageData.count)B) — dropping push; re-create the companion to fix"
                ),
                context: "AppState.pushCustomAvatarFrame id=\(companionId)"
            )
            await localStorage.clearPendingCustomCompanionPush()
            isCustomAvatarPendingBLEPush = false
            customAvatarFlushAttempts = 0
            return
        }
        do {
            try await BLEService.shared.sendCustomAvatarFrame(imageData: imageData)
            await localStorage.clearPendingCustomCompanionPush()
            isCustomAvatarPendingBLEPush = false
            customAvatarFlushAttempts = 0
        } catch is CancellationError {
            // 被更新的选择/flush 取消：新任务已接管重试状态，这里不标 pending、不记错——
            // 否则旧任务会把新选择刚清掉的待重发标记又写回去。
            return
        } catch {
            await localStorage.savePendingCustomCompanionPush(id: companionId)
            isCustomAvatarPendingBLEPush = true
            ErrorReporter.log(
                .sync(component: "BLE CustomAvatarFrame", underlying: error.localizedDescription),
                context: "AppState.pushCustomAvatarFrame id=\(companionId)"
            )
        }
    }

    /// Flush back-off policy. Re-push the 0x15 frame on every sync for the first
    /// `maxImmediateFlushAttempts`, then drop to once every `periodicFlushRetryInterval` syncs.
    /// This stops the frame from being re-sent on every single sync while firmware can't accept
    /// 0x15 yet, WITHOUT ever permanently giving up: a hard cap would strand a pending push
    /// forever once hit — a transient failure streak (hardware briefly unready) would then never
    /// self-heal even after the hardware recovers, leaving the device on the old avatar until the
    /// user manually re-selects a companion. Counter resets on a successful push or new selection.
    private static let maxImmediateFlushAttempts = 5
    private static let periodicFlushRetryInterval = 20

    /// Whether the `attempt`-th consecutive flush should actually re-push. Pure + static so the
    /// back-off schedule is unit-testable without driving real BLE. `attempt` is 1-based.
    static func shouldAttemptCustomAvatarFlush(attempt: Int) -> Bool {
        attempt <= maxImmediateFlushAttempts || attempt % periodicFlushRetryInterval == 0
    }

    /// Called by BLESyncCoordinator after establishing a connection.
    /// Re-sends the avatar frame for the active custom companion when a previous push failed.
    public func flushPendingCustomCompanionPushIfNeeded() async {
        guard isCustomAvatarPendingBLEPush,
              let id = userProfile.customCompanionId,
              let imageData = await localStorage.loadCustomCompanionImageData(id: id) else {
            return
        }
        // Count every flush opportunity (even skipped ones) so the periodic retry keeps advancing.
        customAvatarFlushAttempts += 1
        guard Self.shouldAttemptCustomAvatarFlush(attempt: customAvatarFlushAttempts) else { return }
        // 与 selectCustomCompanion 共用同一任务槽：flush 也可能与手动切换赛跑，
        // 同一时刻只允许一条 0x15 大帧流在发。仍然 await 完成，调用方语义不变。
        customAvatarPushTask?.cancel()
        let task = Task { @MainActor in
            await pushCustomAvatarFrame(imageData: imageData, companionId: id)
        }
        customAvatarPushTask = task
        await task.value
    }
}
