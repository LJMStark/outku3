import Foundation

extension BLESyncCoordinator {
    static func completeTaskActionPresentation(
        maximumAttempts: Int = 3,
        sendFinalDayPack: @MainActor () async -> UInt64?,
        acknowledge: @MainActor (UInt64) async -> TaskListSnapshotResponder.Outcome
    ) async -> Bool {
        for _ in 0..<maximumAttempts {
            guard let taskStateVersion = await sendFinalDayPack() else { return false }
            switch await acknowledge(taskStateVersion) {
            case .sent:
                return true
            case .staleTaskState:
                continue
            case .failed:
                return false
            }
        }
        return false
    }

    func sendFinalTaskActionDayPack() async -> UInt64? {
        let appState = AppState.shared
        await appState.ensureInitialLoadComplete()

        for _ in 0..<3 {
            await appState.refreshSharedPetDialogueIfNeeded()
            let sourceTaskStateVersion = appState.taskStateVersion
            guard appState.currentPetDialogueTaskStateVersion == sourceTaskStateVersion else {
                continue
            }

            let dayPack = await dayPackGenerator.generateDayPack(
                pet: appState.pet,
                tasks: appState.tasks,
                events: appState.events,
                weather: appState.weather,
                deviceMode: appState.deviceMode,
                userProfile: appState.userProfile,
                customCompanions: appState.customCompanions,
                screenSize: bleService.hardwareScreenSize,
                petDialogue: appState.currentPetDialogue
            )
            guard appState.taskStateVersion == sourceTaskStateVersion else { continue }

            let fingerprint = dayPack.stableFingerprint()
            if await localStorage.loadLastDayPackHash() == fingerprint {
                // A routine sync that was already in flight successfully sent this exact final
                // state. Reuse it instead of emitting a duplicate 0x10 before the same 0x1B.
                return sourceTaskStateVersion
            }

            if !bleService.connectionState.isConnected {
                do {
                    try await bleService.connectToPreferredDevice(timeout: 10)
                } catch {
                    syncState.enqueue(force: false, hardwareWakeDate: nil)
                    ErrorReporter.log(
                        .sync(
                            component: "BLE Task Action DayPack",
                            underlying: error.localizedDescription
                        ),
                        context: "BLESyncCoordinator.sendFinalTaskActionDayPack"
                    )
                    return nil
                }
            }

            var taskStateChanged = false
            var lastWriteError: Error?
            for attempt in 0..<2 {
                do {
                    try await bleService.sendDayPack(
                        dayPack,
                        expectedTaskStateVersion: sourceTaskStateVersion
                    )
                    await localStorage.saveLastDayPackHash(fingerprint)
                    return sourceTaskStateVersion
                } catch let error as BLEError {
                    if case .staleTaskSnapshot = error {
                        taskStateChanged = true
                        break
                    }
                    lastWriteError = error
                } catch {
                    lastWriteError = error
                }

                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            if taskStateChanged { continue }

            ErrorReporter.log(
                .sync(
                    component: "BLE Task Action DayPack",
                    underlying: lastWriteError?.localizedDescription ?? "write failed after 2 attempts"
                ),
                context: "BLESyncCoordinator.sendFinalTaskActionDayPack"
            )
            syncState.enqueue(force: false, hardwareWakeDate: nil)
            return nil
        }

        syncState.enqueue(force: false, hardwareWakeDate: nil)
        ErrorReporter.log(
            .sync(
                component: "BLE Task Action DayPack",
                underlying: "task state changed during 3 consecutive generation attempts"
            ),
            context: "BLESyncCoordinator.sendFinalTaskActionDayPack"
        )
        return nil
    }

    /// 路由一条到期的智能提醒：硬件可达就推设备，否则落本地通知，让离线用户也收得到。
    /// 每轮同步只评估一次（限流逻辑在 SmartReminderService 内）。
    func deliverSmartReminder(appState: AppState) async {
        guard let reminder = await SmartReminderService.shared.evaluateAndPushReminder(
            tasks: appState.tasks,
            pet: appState.pet
        ) else { return }

        if bleService.connectionState.isConnected {
            do {
                try await bleService.sendSmartReminder(
                    text: reminder.text,
                    urgency: reminder.urgency,
                    petMood: appState.pet.mood
                )
                SmartReminderService.shared.markReminderSent()
                return
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE SmartReminder", underlying: error.localizedDescription),
                    context: "BLESyncCoordinator.deliverSmartReminder"
                )
            }
        }

        await NotificationService.shared.refreshAuthorizationStatus()
        let delivered = await NotificationService.shared.scheduleLocalNotification(from: reminder)
        if delivered {
            SmartReminderService.shared.markReminderSent()
        }
    }
}

extension BLESyncCoordinator: TaskActionPresentationCoordinating {
    func sendFinalDayPackBeforeAcknowledgement(
        _ acknowledgement: @MainActor @Sendable (
            _ expectedTaskStateVersion: UInt64
        ) async -> TaskListSnapshotResponder.Outcome
    ) async {
        taskActionPresentationCount += 1
        AppState.shared.cancelPendingBLESyncForTaskActionPresentation()

        do {
            try await taskActionPresentationGate.acquire()
        } catch {
            // Firmware keeps the operation pending and retries the same OperationID. Sending
            // 0x1B here would exit TaskIn without the final DayPack and recreate the double refresh.
            taskActionPresentationCount -= 1
            schedulePendingSyncIfPossible()
            return
        }

        await waitForActiveSyncToFinish()
        AppState.shared.cancelPendingBLESyncForTaskActionPresentation()
        let completed = await Self.completeTaskActionPresentation(
            sendFinalDayPack: { await self.sendFinalTaskActionDayPack() },
            acknowledge: acknowledgement
        )
        if !completed {
            syncState.enqueue(force: false, hardwareWakeDate: nil)
            ErrorReporter.log(
                .sync(
                    component: "BLE Task Action Presentation",
                    underlying: "final DayPack and acknowledgement did not complete as one task version"
                ),
                context: "BLESyncCoordinator.sendFinalDayPackBeforeAcknowledgement"
            )
        }

        await taskActionPresentationGate.release()
        taskActionPresentationCount -= 1
        schedulePendingSyncIfPossible()
    }
}
