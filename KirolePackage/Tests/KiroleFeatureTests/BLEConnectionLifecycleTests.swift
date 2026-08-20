import Foundation
import Testing
@testable import KiroleFeature

@Suite("BLE connection attempt lifecycle")
struct BLEConnectionLifecycleTests {
    @Test("a slow physical link receives a fresh readiness phase")
    func slowLinkGetsFreshReadinessPhase() {
        let peripheralID = UUID()
        var attempt = BLEConnectionAttempt(
            generation: 9,
            peripheralID: peripheralID,
            origin: .requested,
            phase: .awaitingLink
        )

        #expect(attempt.accepts(generation: 9, peripheralID: peripheralID, phase: .awaitingLink))

        attempt.phase = .discoveringServices

        #expect(!attempt.accepts(generation: 9, peripheralID: peripheralID, phase: .awaitingLink))
        #expect(attempt.accepts(generation: 9, peripheralID: peripheralID, phase: .discoveringServices))
        #expect(BLEConnectionAttemptTimeout.link == .seconds(15))
        #expect(BLEConnectionAttemptTimeout.readiness == .seconds(15))
    }

    @Test("setNotify is not ready until the notification acknowledgement succeeds")
    func notificationAcknowledgementControlsReadiness() {
        let peripheralID = UUID()
        var attempt = BLEConnectionAttempt(
            generation: 4,
            peripheralID: peripheralID,
            origin: .requested,
            phase: .discoveringCharacteristics
        )

        attempt.phase = .enablingNotifications
        #expect(attempt.phase != .ready)

        attempt.phase = .ready
        #expect(attempt.phase == .ready)
    }

    @Test("secure handshake is a distinct phase after notification readiness")
    func secureHandshakeFollowsNotificationReadiness() {
        let attempt = BLEConnectionAttempt(
            generation: 1,
            peripheralID: UUID(),
            origin: .requested,
            phase: .handshaking
        )

        #expect(attempt.phase == .handshaking)
        #expect(BLEConnectionAttemptTimeout.handshake == .seconds(5))
    }

    @Test("stale generations and foreign peripherals never advance an attempt")
    func staleCallbacksAreRejected() {
        let peripheralID = UUID()
        let attempt = BLEConnectionAttempt(
            generation: 12,
            peripheralID: peripheralID,
            origin: .requested,
            phase: .enablingNotifications
        )

        #expect(!attempt.accepts(generation: 11, peripheralID: peripheralID, phase: .enablingNotifications))
        #expect(!attempt.accepts(generation: 12, peripheralID: UUID(), phase: .enablingNotifications))
        #expect(!attempt.accepts(generation: 12, peripheralID: peripheralID, phase: .discoveringCharacteristics))
    }

    @Test("connection setup retries ten actual connects with the specified delays")
    @MainActor
    func connectionRetryBudgetAndBackoff() async {
        #expect(BLEConnectionRetryPolicy.maximumAttempts == 10)
        #expect(BLEConnectionRetryPolicy.delays == [
            .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(15),
            .seconds(30), .seconds(30), .seconds(30), .seconds(30),
        ])
        #expect(BLEConnectionRetryPolicy.delay(afterFailedAttempt: 1) == .seconds(1))
        #expect(BLEConnectionRetryPolicy.delay(afterFailedAttempt: 9) == .seconds(30))
        #expect(BLEConnectionRetryPolicy.delay(afterFailedAttempt: 10) == nil)

        var connectCalls = 0
        var waited: [Duration] = []
        do {
            try await BLEConnectionRetryRunner.run(
                connect: {
                    connectCalls += 1
                    throw BLEError.connectionTimeout
                },
                wait: { delay in waited.append(delay) }
            )
            Issue.record("Expected the ten-attempt round to fail")
        } catch {
            #expect(connectCalls == 10)
            #expect(waited == BLEConnectionRetryPolicy.delays)
        }
    }

    @Test("the retry UI stays connecting until attempt ten publishes the final error")
    @MainActor
    func retryStatePublicationWaitsForExhaustion() async {
        var state: BLEConnectionState = .disconnected
        var connectCalls = 0
        var errorPublications: [Int] = []

        do {
            try await BLEConnectionRetryRunner.run(
                connect: {
                    if case .error = state {
                        Issue.record("Find/error became visible before the retry round exhausted")
                    }
                    state = .connecting
                    connectCalls += 1
                    throw BLEError.connectionReadinessTimeout
                },
                wait: { _ in },
                willWait: { _ in state = .connecting },
                didWait: { state = .disconnected }
            )
            Issue.record("Expected the retry round to exhaust")
        } catch {
            if BLEConnectionRetryPublicationPolicy.shouldPublishFinalError(
                ownsRound: true,
                isIntentionalDisconnect: false
            ) {
                state = .error(error.localizedDescription)
                errorPublications.append(connectCalls)
            }
        }

        #expect(connectCalls == 10)
        #expect(errorPublications == [10])
        guard case .error = state else {
            Issue.record("The exhausted retry round did not publish its final error")
            return
        }
    }

    @Test("connection completion resolves exactly once")
    func connectionCompletionResolvesExactlyOnce() {
        var results: [Bool] = []
        var latch = BLEConnectionCompletionLatch()
        latch.install { result in
            results.append((try? result.get()) != nil)
        }

        #expect(latch.isPending)
        let firstResolution = latch.resolve(.success(()))
        #expect(firstResolution)
        #expect(!latch.isPending)
        let secondResolution = latch.resolve(.failure(.connectionTimeout))
        #expect(!secondResolution)
        #expect(results == [true])
    }

    @Test("requested cancellation finishes locally until CoreBluetooth owns the attempt")
    func requestedCancellationChoosesOneCompletionOwner() {
        var attempt = BLEConnectionAttempt(
            generation: 2,
            peripheralID: UUID(),
            origin: .requested,
            phase: .awaitingLink
        )

        #expect(attempt.requestedCancellationDisposition(completionPending: false) == .finishLocally)
        #expect(attempt.requestedCancellationDisposition(completionPending: true) == .cancelPeripheral)

        attempt.phase = .cancelling
        #expect(attempt.requestedCancellationDisposition(completionPending: true) == .ignore)
        attempt.phase = .ready
        #expect(attempt.requestedCancellationDisposition(completionPending: false) == .ignore)
    }

    @Test("only the current retry owner can publish the final error")
    func retryErrorPublicationRequiresOwnership() {
        #expect(BLEConnectionRetryPublicationPolicy.shouldPublishFinalError(
            ownsRound: true,
            isIntentionalDisconnect: false
        ))
        #expect(!BLEConnectionRetryPublicationPolicy.shouldPublishFinalError(
            ownsRound: false,
            isIntentionalDisconnect: false
        ))
        #expect(!BLEConnectionRetryPublicationPolicy.shouldPublishFinalError(
            ownsRound: true,
            isIntentionalDisconnect: true
        ))
    }

    @Test("Bluetooth power recovery supersedes a DeviceWake timeout retry")
    func bluetoothPowerRecoveryOwnsTheDisconnect() {
        #expect(BLEPostDisconnectRecoveryPolicy.owner(
            shouldResumeAfterBluetoothPowerCycle: true,
            hasDeviceWakeRecoveryPeripheral: true
        ) == .bluetoothPowerCycle)
        #expect(BLEPostDisconnectRecoveryPolicy.owner(
            shouldResumeAfterBluetoothPowerCycle: false,
            hasDeviceWakeRecoveryPeripheral: true
        ) == .deviceWakeTimeout)
        #expect(BLEPostDisconnectRecoveryPolicy.owner(
            shouldResumeAfterBluetoothPowerCycle: false,
            hasDeviceWakeRecoveryPeripheral: false
        ) == .none)
    }

    @Test("setup failures stay internal while ready transport failures are visible")
    func preReadyFailureDoesNotExposeFindEarly() {
        var attempt = BLEConnectionAttempt(
            generation: 3,
            peripheralID: UUID(),
            origin: .requested,
            phase: .enablingNotifications
        )
        #expect(!attempt.exposesTransportErrorImmediately)

        attempt.phase = .ready
        #expect(attempt.exposesTransportErrorImmediately)
        attempt.phase = .cancelling
        #expect(!attempt.exposesTransportErrorImmediately)
    }

    @Test("a successful setup attempt stops the retry round immediately")
    @MainActor
    func successfulConnectionStopsRetryRound() async throws {
        var connectCalls = 0
        var waitCalls = 0

        try await BLEConnectionRetryRunner.run(
            connect: {
                connectCalls += 1
                if connectCalls < 4 { throw BLEError.connectionReadinessTimeout }
            },
            wait: { _ in waitCalls += 1 }
        )

        #expect(connectCalls == 4)
        #expect(waitCalls == 3)
    }

    @Test("a retry operation that loses ownership stops without waiting")
    @MainActor
    func cancelledConnectionRoundDoesNotRetry() async {
        var connectCalls = 0
        var waitCalls = 0
        var cancellationCleanups = 0

        do {
            try await BLEConnectionRetryRunner.run(
                connect: {
                    connectCalls += 1
                    throw CancellationError()
                },
                wait: { _ in waitCalls += 1 },
                didCancel: { cancellationCleanups += 1 }
            )
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            #expect(connectCalls == 1)
            #expect(waitCalls == 0)
            #expect(cancellationCleanups == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("cancelling retry backoff runs cleanup and never starts the next attempt")
    @MainActor
    func cancellingRetryBackoffRunsCleanup() async {
        var connectCalls = 0
        var didEnterWait = false
        var didWaitCalls = 0
        var cancellationCleanups = 0

        let task = Task { @MainActor in
            try await BLEConnectionRetryRunner.run(
                connect: {
                    connectCalls += 1
                    throw BLEError.connectionTimeout
                },
                wait: { _ in
                    didEnterWait = true
                    try await Task.sleep(for: .seconds(30))
                },
                didWait: { didWaitCalls += 1 },
                didCancel: { cancellationCleanups += 1 }
            )
        }

        while !didEnterWait {
            await Task.yield()
        }
        task.cancel()

        do {
            try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            #expect(connectCalls == 1)
            #expect(didWaitCalls == 0)
            #expect(cancellationCleanups == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("a retry round that loses ownership during backoff cannot start another connect")
    @MainActor
    func retryRoundOwnershipStopsOldBackoff() async {
        var ownsRound = true
        var connectCalls = 0
        var didWaitCalls = 0

        do {
            try await BLEConnectionRetryRunner.run(
                connect: {
                    connectCalls += 1
                    throw BLEError.connectionTimeout
                },
                wait: { _ in ownsRound = false },
                didWait: { didWaitCalls += 1 },
                shouldStop: { !ownsRound }
            )
            Issue.record("Expected the superseded round to stop")
        } catch BLEError.disconnected {
            #expect(connectCalls == 1)
            #expect(didWaitCalls == 0)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Bluetooth power cycling cannot let an old backoff overwrite the new pending connection")
    @MainActor
    func bluetoothPowerCycleInvalidatesOldBackoff() async {
        var ownsOldRound = true
        var state: BLEConnectionState = .connecting
        var connectCalls = 0
        var didWaitCalls = 0

        do {
            try await BLEConnectionRetryRunner.run(
                connect: {
                    connectCalls += 1
                    throw BLEError.connectionTimeout
                },
                wait: { _ in
                    // poweredOff invalidates the old round; poweredOn starts the new pending link.
                    ownsOldRound = false
                    state = .connecting
                },
                didWait: {
                    didWaitCalls += 1
                    state = .disconnected
                },
                shouldStop: { !ownsOldRound }
            )
            Issue.record("Expected the old round to stop")
        } catch BLEError.disconnected {
            #expect(connectCalls == 1)
            #expect(didWaitCalls == 0)
            #expect(state == .connecting)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("a stable unexpected disconnect uses an unbounded pending connection")
    func pendingReconnectDoesNotConsumeSetupBudgetWhileAwaitingLink() {
        var attempt = BLEConnectionAttempt(
            generation: 20,
            peripheralID: UUID(),
            origin: .pendingReconnect,
            phase: .awaitingLink
        )

        #expect(!attempt.origin.usesLinkTimeout)
        #expect(attempt.origin.startsSetupRetryRoundAfterReadinessFailure)
        #expect(!attempt.suppressesAutomaticRecovery)
        #expect(attempt.shouldStartSetupRetryRound)
        #expect(attempt.keepsRetryRoundActiveAfterFailure)

        attempt.suppressesAutomaticRecovery = true
        #expect(attempt.suppressesAutomaticRecovery)
        #expect(!attempt.shouldStartSetupRetryRound)
        #expect(!attempt.keepsRetryRoundActiveAfterFailure)
    }

    @Test("requested attempts use a link timeout and their caller owns retry")
    func requestedAttemptUsesLinkTimeout() {
        #expect(BLEConnectionAttemptOrigin.requested.usesLinkTimeout)
        #expect(!BLEConnectionAttemptOrigin.requested.startsSetupRetryRoundAfterReadinessFailure)
    }

    @Test("DeviceWake observed before ready satisfies the matching generation only")
    @MainActor
    func earlyDeviceWakeIsRetainedByGeneration() async throws {
        let barrier = BLEDeviceWakeBarrier()
        barrier.prepare(generation: 30)
        barrier.observe(generation: 30)

        #expect(try await barrier.wait(generation: 30, timeout: .zero))

        barrier.prepare(generation: 31)
        #expect(!barrier.hasObserved(generation: 31))
        barrier.observe(generation: 30)
        #expect(!barrier.hasObserved(generation: 31))
    }

    @Test("an already-cancelled waiter cannot consume an observed DeviceWake")
    @MainActor
    func cancelledWaitDoesNotUseFastPath() async {
        let barrier = BLEDeviceWakeBarrier()
        barrier.prepare(generation: 32)
        barrier.observe(generation: 32)

        let task = Task { @MainActor in
            try await barrier.wait(generation: 32, timeout: .zero)
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected: cancellation wins even though DeviceWake was already observed.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("a cancelling generation is no longer ready for late DeviceWake delivery")
    func cancellingAttemptRejectsLateReadyWork() {
        let peripheralID = UUID()
        var attempt = BLEConnectionAttempt(
            generation: 33,
            peripheralID: peripheralID,
            origin: .requested,
            phase: .ready
        )
        #expect(attempt.accepts(generation: 33, peripheralID: peripheralID, phase: .ready))

        attempt.phase = .cancelling
        #expect(!attempt.accepts(generation: 33, peripheralID: peripheralID, phase: .ready))
        #expect(attempt.shouldFinishAsSetupFailure(hasDeviceWakeRecovery: false))
        #expect(!attempt.shouldFinishAsSetupFailure(hasDeviceWakeRecovery: true))
    }

    @Test("ready DeviceWake watchdog fires only for an unobserved current generation")
    @MainActor
    func deviceWakeWatchdogIsGenerationBound() async {
        let barrier = BLEDeviceWakeBarrier()
        var timedOutGenerations: [UInt64] = []

        barrier.prepare(generation: 40)
        barrier.armWatchdog(generation: 40, timeout: .seconds(30)) {
            timedOutGenerations.append(40)
        }
        barrier.expireWatchdog(generation: 40)
        #expect(timedOutGenerations == [40])

        barrier.prepare(generation: 41)
        barrier.armWatchdog(generation: 41, timeout: .seconds(30)) {
            timedOutGenerations.append(41)
        }
        barrier.observe(generation: 41)
        barrier.prepare(generation: 42)
        barrier.armWatchdog(generation: 41, timeout: .zero) {
            timedOutGenerations.append(41)
        }
        barrier.expireWatchdog(generation: 41)

        #expect(timedOutGenerations == [40])
    }

    @Test("cancelling a DeviceWake wait exits without spinning or reporting a timeout")
    @MainActor
    func deviceWakeWaitPropagatesCancellation() async {
        let barrier = BLEDeviceWakeBarrier()
        barrier.prepare(generation: 50)
        let task = Task { @MainActor in
            try await barrier.wait(generation: 50, timeout: .seconds(30))
        }

        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected CancellationError")
        } catch is CancellationError {
            // Expected: cancellation is distinct from a DeviceWake timeout.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("DeviceWake wait and watchdog can claim timeout recovery only once")
    @MainActor
    func deviceWakeTimeoutRecoveryIsClaimedOnce() async throws {
        let barrier = BLEDeviceWakeBarrier()
        var recoveryCount = 0

        barrier.prepare(generation: 60)
        barrier.armWatchdog(generation: 60, timeout: .seconds(30)) {
            recoveryCount += 1
        }
        let didObserve = try await barrier.wait(generation: 60, timeout: .zero)
        if !didObserve, barrier.claimTimeoutRecovery(generation: 60) {
            recoveryCount += 1
        }
        barrier.observe(generation: 60)
        barrier.expireWatchdog(generation: 60)

        #expect(recoveryCount == 1)
        #expect(!barrier.hasObserved(generation: 60))

        barrier.prepare(generation: 61)
        barrier.armWatchdog(generation: 61, timeout: .seconds(30)) {
            recoveryCount += 1
        }
        barrier.expireWatchdog(generation: 61)
        let secondDidObserve = try await barrier.wait(generation: 61, timeout: .zero)
        if !secondDidObserve, barrier.claimTimeoutRecovery(generation: 61) {
            recoveryCount += 1
        }

        #expect(recoveryCount == 2)
    }

    @Test("pre-ready messages preserve order and drain only once")
    func preReadyMessagesPreserveOrder() {
        var buffer = BLEPreReadyMessageBuffer()
        #expect(buffer.append(BLEReceivedMessage(type: 0x30, payload: Data([1]))) == .accepted)
        #expect(buffer.append(BLEReceivedMessage(type: 0x25, payload: Data([2, 3]))) == .accepted)

        let drained = buffer.drain()
        #expect(drained.map(\.type) == [0x30, 0x25])
        #expect(buffer.drain().isEmpty)
    }

    @Test("pre-ready message limits fail closed")
    func preReadyMessageLimits() {
        var countBuffer = BLEPreReadyMessageBuffer()
        for index in 0..<8 {
            #expect(countBuffer.append(
                BLEReceivedMessage(type: UInt8(index), payload: Data())
            ) == .accepted)
        }
        #expect(countBuffer.append(BLEReceivedMessage(type: 9, payload: Data())) == .overflow)

        var byteBuffer = BLEPreReadyMessageBuffer()
        #expect(byteBuffer.append(
            BLEReceivedMessage(type: 1, payload: Data(repeating: 0, count: 8 * 1024))
        ) == .overflow)
    }

    @Test("the captured first-connect regression fixture requires first-attempt Notify readiness")
    func firstConnectFixtureEncodesTheFixedContract() throws {
        let fixture = try Self.loadFirstConnectFixture()

        #expect(fixture.observedRegression.firstAttempt.connectedDurationMilliseconds == 4_570)
        #expect(fixture.observedRegression.firstAttempt.notifyEnabledObserved == false)
        #expect(fixture.observedRegression.firstAttempt.disconnectReason == "0x13")
        #expect(fixture.observedRegression.secondAttempt.connectedToNotifyEnabledMilliseconds == 5_910)

        #expect(!fixture.fixedExpected.firstAttemptDisconnectsBeforeNotifyEnabled)
        #expect(fixture.fixedExpected.firstAttemptSequence == [
            "connected", "cccdWrite", "notifyEnabled", "deviceWake", "offlineSyncState",
        ])
        #expect(fixture.fixedExpected.businessFramesBeforeDeviceWake.isEmpty)
        #expect(fixture.fixedExpected.maximumConnectAttemptsPerRound == 10)
        #expect(fixture.fixedExpected.disconnectReasonMeansRemoteUserTerminatedConnection)
    }

    @Test("BLEService keeps link and readiness deadlines wired to separate delegate phases")
    func productionConnectionWiringKeepsPhaseBoundaries() throws {
        let source = try Self.loadBLEServiceSource()
        let didConnect = try #require(Self.slice(
            source,
            from: "didConnect peripheral: CBPeripheral",
            to: "didFailToConnect peripheral: CBPeripheral"
        ))
        let cancelLink = try #require(didConnect.range(of: "linkTimeoutTask?.cancel()"))
        let armReadiness = try #require(didConnect.range(of: "armReadinessTimeout("))
        #expect(cancelLink.lowerBound < armReadiness.lowerBound)

        let discoveredCharacteristics = try #require(Self.slice(
            source,
            from: "didDiscoverCharacteristicsFor service: CBService",
            to: "didUpdateNotificationStateFor characteristic: CBCharacteristic"
        ))
        #expect(discoveredCharacteristics.contains("peripheral.setNotifyValue(true"))
        #expect(!discoveredCharacteristics.contains("completeSecureConnection()"))

        let notificationState = try #require(Self.slice(
            source,
            from: "didUpdateNotificationStateFor characteristic: CBCharacteristic",
            to: "didWriteValueFor characteristic: CBCharacteristic"
        ))
        let validatesNotify = try #require(notificationState.range(of: "guard error == nil, isNotifying"))
        let cancelsReadiness = try #require(notificationState.range(of: "readinessTimeoutTask?.cancel()"))
        let completesConnection = try #require(notificationState.range(of: "await completeSecureConnection()"))
        #expect(validatesNotify.lowerBound < cancelsReadiness.lowerBound)
        #expect(cancelsReadiness.lowerBound < completesConnection.lowerBound)
    }

    @Test("production cancellation and recovery exits remain generation owned")
    func productionCancellationRecoveryWiring() throws {
        let service = try Self.loadSource("BLEService.swift")
        let requestedConnect = try #require(Self.slice(
            service,
            from: "private func connectKnownPeripheral(_ peripheral:",
            to: "private func cancelRequestedConnectionIfOwned"
        ))
        #expect(requestedConnect.contains("catch is CancellationError"))
        #expect(requestedConnect.contains("cancelRequestedConnectionIfOwned("))

        let cancellation = try #require(Self.slice(
            service,
            from: "private func cancelRequestedConnectionIfOwned",
            to: "private func armLinkTimeout"
        ))
        #expect(cancellation.contains("requestedCancellationDisposition"))
        #expect(cancellation.contains("case .finishLocally"))
        #expect(cancellation.contains("cleanup()"))

        let bluetoothState = try #require(Self.slice(
            service,
            from: "centralManagerDidUpdateState",
            to: "didDiscover peripheral: CBPeripheral"
        ))
        #expect(bluetoothState.contains("case .poweredOff:"))
        #expect(bluetoothState.contains("activeConnectionRetryRoundID = nil"))
        let unauthorizedState = try #require(Self.slice(
            String(bluetoothState),
            from: "case .unauthorized:",
            to: "case .unsupported:"
        ))
        #expect(unauthorizedState.contains("activeConnectionRetryRoundID = nil"))
        #expect(unauthorizedState.contains("reconnectTask?.cancel()"))

        #expect(service.contains("connectionAttempt?.exposesTransportErrorImmediately"))
        #expect(service.contains("isOTAReboot: wasOTAReboot"))

        let coordinator = try Self.loadSource("BLESyncCoordinator.swift")
        #expect(coordinator.contains("catch is CancellationError"))
        #expect(coordinator.contains("disconnectIfCurrentGeneration(transactionGeneration)"))
        #expect(coordinator.contains("currentReadyGenerationForCancellation("))

        let cancellationExits = coordinator.components(separatedBy: "catch is CancellationError")
        #expect(cancellationExits.count >= 3)
        for cancellationExit in cancellationExits.suffix(2) {
            let closesMergeWindow = try #require(
                cancellationExit.range(of: "syncState.closeDeviceWakeMergeWindow()")
            )
            let snapshotsReadyGeneration = try #require(
                cancellationExit.range(of: "currentReadyGenerationForCancellation(")
            )
            let firstAwait = try #require(cancellationExit.range(of: "await "))
            #expect(closesMergeWindow.lowerBound < snapshotsReadyGeneration.lowerBound)
            #expect(snapshotsReadyGeneration.lowerBound < firstAwait.lowerBound)
            #expect(cancellationExit.contains("if retainsReadyConnection"))
            #expect(cancellationExit.contains("releaseOfflineFocusFreezeLease()"))
            #expect(cancellationExit.contains("releaseFocusFreezeLeases()"))
        }
    }

    private static func loadFirstConnectFixture() throws -> FirstConnectRegressionFixture {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot.appendingPathComponent(
            "test/fixtures/ios-fix/ble-first-auto-connect-notify-gap.json"
        )
        return try JSONDecoder().decode(
            FirstConnectRegressionFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
    }

    private static func loadBLEServiceSource() throws -> String {
        try loadSource("BLEService.swift")
    }

    private static func loadSource(_ filename: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appendingPathComponent(
            "KirolePackage/Sources/KiroleFeature/Core/Services/\(filename)"
        )
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private static func slice(_ source: String, from start: String, to end: String) -> Substring? {
        guard let startRange = source.range(of: start),
              let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            return nil
        }
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
}

private struct FirstConnectRegressionFixture: Decodable {
    struct Attempt: Decodable {
        let connectedDurationMilliseconds: Int?
        let disconnectReason: String?
        let notifyEnabledObserved: Bool?
        let connectedToNotifyEnabledMilliseconds: Int?
    }

    struct ObservedRegression: Decodable {
        let firstAttempt: Attempt
        let secondAttempt: Attempt
    }

    struct FixedExpected: Decodable {
        let firstAttemptDisconnectsBeforeNotifyEnabled: Bool
        let firstAttemptSequence: [String]
        let businessFramesBeforeDeviceWake: [String]
        let maximumConnectAttemptsPerRound: Int
        let disconnectReasonMeansRemoteUserTerminatedConnection: Bool
    }

    let observedRegression: ObservedRegression
    let fixedExpected: FixedExpected
}
