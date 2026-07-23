import Foundation
import Testing
@testable import KiroleFeature

@Suite("Custom avatar transaction", .serialized)
@MainActor
struct CustomCompanionBLEQueueTests {
    @Test("custom selection keeps the old identity until matching committed result")
    func selectionCommitsIdentityOnlyAfterFirmwareConfirmation() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let oldID = UUID()
            let newID = UUID()
            let deviceID = UUID()
            let old = makeCompanion(id: oldID, name: "Old")
            let next = makeCompanion(id: newID, name: "Next")
            let png = try validPNG()
            var usage = CompanionUsageState()
            usage.setProgress(
                CompanionBindingProgress(totalUsedDays: 6),
                forCustomCompanion: newID
            )
            try await LocalStorage.shared.saveCompanionUsageState(usage)
            try await LocalStorage.shared.saveCustomCompanionAssets(
                id: newID,
                previewData: png,
                imageData: png
            )
            state.customCompanions = [old, next]
            state.userProfile.customCompanionId = oldID
            state.userProfile.intimacyStage = .closeFriend
            state.customAvatarOperationIDProvider = { 77 }
            state.customAvatarConnectionProvider = { (true, deviceID) }
            state.customAvatarFrameSender = { operationID, avatarID, kriData, progress in
                #expect(state.userProfile.customCompanionId == oldID)
                progress(kriData.count, kriData.count)
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .staged,
                        avatarState: .staged,
                        customActive: true,
                        avatarID: avatarID,
                        byteLength: UInt32(kriData.count),
                        crc32: CRC32.ieee(kriData)
                    )
                )
            }
            state.avatarControlSender = { command in
                guard case .commit(let operationID, let avatarID) = command else { return }
                #expect(state.userProfile.customCompanionId == oldID)
                let kriData = try #require(await LocalStorage.shared.loadPendingCustomAvatarImageData())
                let encoded = try KRIEncoder.encode(pngData: kriData)
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .committed,
                        avatarState: .committed,
                        customActive: true,
                        avatarID: avatarID,
                        byteLength: UInt32(encoded.count),
                        crc32: CRC32.ieee(encoded)
                    )
                )
            }

            try await state.selectCustomCompanion(id: newID)

            #expect(state.userProfile.customCompanionId == newID)
            #expect(state.userProfile.intimacyStage == .familiar)
            #expect(state.customAvatarOperationState == .success)
            #expect(state.pendingCustomAvatarOperation == nil)

            try await snapshot.restore(removingAssetIDs: [oldID, newID])
        }
    }

    @Test("offline delete removes local photo and keeps exact erase marker when UI closes")
    func offlineDeleteKeepsMinimalEraseMarker() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let id = UUID()
            let companion = makeCompanion(id: id, name: "Mochi")
            let png = try validPNG()
            try await LocalStorage.shared.saveCustomCompanionAssets(
                id: id,
                previewData: png,
                imageData: png
            )
            state.customCompanions = [companion]
            state.userProfile.companionCharacter = .silas
            state.userProfile.customCompanionId = id
            state.userProfile.intimacyStage = .closeFriend
            var usage = CompanionUsageState()
            usage.silas = CompanionBindingProgress(totalUsedDays: 18)
            usage.setProgress(
                CompanionBindingProgress(totalUsedDays: 3),
                forCustomCompanion: id
            )
            try await LocalStorage.shared.saveCompanionUsageState(usage)
            let deviceID = UUID()
            state.customAvatarConnectionProvider = { (false, deviceID) }
            state.customAvatarOperationIDProvider = { 91 }

            try await state.deleteCustomCompanion(id: id)

            let pending = try await LocalStorage.shared.loadPendingCustomAvatarOperation()
            #expect(state.customCompanions.isEmpty)
            #expect(state.userProfile.customCompanionId == nil)
            #expect(state.userProfile.intimacyStage == .closeFriend)
            #expect(await LocalStorage.shared.loadCustomCompanionImageData(id: id) == nil)
            #expect(pending?.kind == .eraseExact)
            #expect(pending?.avatarID == id)
            #expect(pending?.deviceID == deviceID)
            #expect(pending?.candidateCompanion == nil)
            #expect(pending?.candidateImageFileName == nil)

            state.resetCustomAvatarOperationState()
            #expect(state.customAvatarOperationState == .idle)
            #expect(try await LocalStorage.shared.loadPendingCustomAvatarOperation()?.avatarID == id)

            try await snapshot.restore(removingAssetIDs: [id])
        }
    }

    @Test("metadata edits preserve UUID, creation time and asset paths while offline")
    func metadataEditPreservesIdentity() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let id = UUID()
            let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            let original = CustomCompanion(
                id: id,
                name: "Before",
                relationship: .pet,
                personaVoice: .companion,
                avatarPreviewFileName: "fixed-preview.png",
                avatarPixelsFileName: "fixed-image.dat",
                createdAt: createdAt,
                updatedAt: createdAt
            )
            var draft = original
            draft.name = "After"
            draft.relationship = .friend
            draft.personaVoice = .playful
            draft.avatarPreviewFileName = "tampered-preview.png"
            draft.avatarPixelsFileName = "tampered-image.dat"
            draft.createdAt = Date()
            state.customCompanions = [original]
            state.customAvatarConnectionProvider = { (false, nil) }

            let saved = try await state.updateCustomCompanionMetadata(draft)

            #expect(saved.id == id)
            #expect(saved.name == "After")
            #expect(saved.relationship == .friend)
            #expect(saved.createdAt == createdAt)
            #expect(saved.avatarPreviewFileName == "fixed-preview.png")
            #expect(saved.avatarPixelsFileName == "fixed-image.dat")
            #expect(saved.updatedAt > createdAt)

            try await snapshot.restore(removingAssetIDs: [id])
        }
    }

    @Test("photo replacement commits metadata and image as one transaction")
    func photoReplacementKeepsOldMetadataUntilCommit() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let id = UUID()
            let deviceID = UUID()
            let original = makeCompanion(id: id, name: "Before")
            var draft = original
            draft.name = "After"
            draft.relationship = .mentor
            let png = try validPNG()
            let kriData = try KRIEncoder.encode(pngData: png)
            state.customCompanions = [original]
            state.userProfile.customCompanionId = id
            state.userProfile.intimacyStage = .closeFriend
            state.customAvatarOperationIDProvider = { 95 }
            state.customAvatarConnectionProvider = { (true, deviceID) }
            state.customAvatarFrameSender = { operationID, avatarID, sentKRI, progress in
                #expect(state.customCompanions.first?.name == "Before")
                #expect(sentKRI == kriData)
                progress(sentKRI.count, sentKRI.count)
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .staged,
                        avatarState: .staged,
                        customActive: true,
                        avatarID: avatarID,
                        byteLength: UInt32(sentKRI.count),
                        crc32: CRC32.ieee(sentKRI)
                    )
                )
            }
            state.avatarControlSender = { command in
                guard case .commit(let operationID, let avatarID) = command else { return }
                #expect(state.customCompanions.first?.name == "Before")
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .committed,
                        avatarState: .committed,
                        customActive: true,
                        avatarID: avatarID,
                        byteLength: UInt32(kriData.count),
                        crc32: CRC32.ieee(kriData)
                    )
                )
            }

            let committed = try await state.replaceCustomCompanion(
                draft,
                previewData: png,
                imageData: png
            )

            #expect(committed.id == id)
            #expect(committed.name == "After")
            #expect(state.customCompanions.first?.name == "After")
            #expect(state.customCompanions.first?.relationship == .mentor)
            #expect(state.userProfile.intimacyStage == .closeFriend)

            try await snapshot.restore(removingAssetIDs: [id])
        }
    }

    @Test("offline sign out cleanup removes every local photo and persists eraseAll")
    func offlineSignOutCleanupPersistsEraseAll() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let firstID = UUID()
            let secondID = UUID()
            let deviceID = UUID()
            let png = try validPNG()
            state.customCompanions = [
                makeCompanion(id: firstID, name: "One"),
                makeCompanion(id: secondID, name: "Two"),
            ]
            state.userProfile.customCompanionId = firstID
            try await LocalStorage.shared.saveCustomCompanionAssets(
                id: firstID, previewData: png, imageData: png
            )
            try await LocalStorage.shared.saveCustomCompanionAssets(
                id: secondID, previewData: png, imageData: png
            )
            state.customAvatarConnectionProvider = { (false, deviceID) }
            state.customAvatarOperationIDProvider = { 101 }

            try await state.prepareCustomCompanionDataForSignOut()

            #expect(state.customCompanions.isEmpty)
            #expect(state.userProfile.customCompanionId == nil)
            #expect(await LocalStorage.shared.loadCustomCompanionImageData(id: firstID) == nil)
            #expect(await LocalStorage.shared.loadCustomCompanionImageData(id: secondID) == nil)
            #expect(try await LocalStorage.shared.loadPendingCustomAvatarOperation()?.kind == .eraseAll)

            try await snapshot.restore(removingAssetIDs: [firstID, secondID])
        }
    }

    @Test("sign out without a target device identity still deletes local photos")
    func signOutWithoutDeviceIdentityDeletesLocalData() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let id = UUID()
            let companion = makeCompanion(id: id, name: "Keep Me")
            let png = try validPNG()
            state.customCompanions = [companion]
            state.userProfile.customCompanionId = id
            try await LocalStorage.shared.saveCustomCompanionAssets(
                id: id,
                previewData: png,
                imageData: png
            )
            state.customAvatarConnectionProvider = { (false, nil) }

            try await state.prepareCustomCompanionDataForSignOut()

            #expect(state.customCompanions.isEmpty)
            #expect(state.userProfile.customCompanionId == nil)
            #expect(state.pendingCustomAvatarOperation == nil)
            #expect(await LocalStorage.shared.loadCustomCompanionImageData(id: id) == nil)

            try await snapshot.restore(removingAssetIDs: [id])
        }
    }

    @Test("online erase failure blocks sign out and preserves local photos")
    func onlineEraseFailureKeepsLocalData() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let id = UUID()
            let deviceID = UUID()
            let companion = makeCompanion(id: id, name: "Keep Me")
            let png = try validPNG()
            try await LocalStorage.shared.saveCustomCompanionAssets(
                id: id,
                previewData: png,
                imageData: png
            )
            state.customCompanions = [companion]
            state.userProfile.customCompanionId = id
            state.customAvatarConnectionProvider = { (true, deviceID) }
            state.avatarControlSender = { _ in
                throw CustomAvatarOperationError.deviceRejected("erase rejected")
            }

            await #expect(throws: CustomAvatarOperationError.self) {
                try await state.prepareCustomCompanionDataForSignOut()
            }

            #expect(state.customCompanions.map(\.id) == [id])
            #expect(state.userProfile.customCompanionId == id)
            #expect(await LocalStorage.shared.loadCustomCompanionImageData(id: id) != nil)
            #expect(state.pendingCustomAvatarOperation?.kind == .eraseAll)

            try await snapshot.restore(removingAssetIDs: [id])
        }
    }

    @Test("sign out sends idempotent eraseAll when the known device may still hold a photo")
    func emptyLocalSignOutStillErasesKnownDevice() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let deviceID = UUID()
            state.customCompanions = []
            state.userProfile = .default
            state.customAvatarConnectionProvider = { (true, deviceID) }
            state.customAvatarOperationIDProvider = { 404 }
            var sentEraseAll = false
            state.avatarControlSender = { command in
                guard case .eraseAll(let operationID) = command else {
                    Issue.record("Expected eraseAll")
                    return
                }
                sentEraseAll = true
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .erased,
                        avatarState: .empty,
                        customActive: false,
                        avatarID: nil,
                        byteLength: 0,
                        crc32: 0
                    )
                )
            }

            try await state.prepareCustomCompanionDataForSignOut()

            #expect(sentEraseAll)
            #expect(state.pendingCustomAvatarOperation == nil)
            #expect(state.customAvatarOperationState == .success)

            try await snapshot.restore(removingAssetIDs: [])
        }
    }

    @Test("sign out with no custom data and no known device is a no-op")
    func emptyLocalSignOutWithoutKnownDeviceReturns() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            state.customCompanions = []
            state.userProfile = .default
            state.customAvatarConnectionProvider = { (false, nil) }
            var sentCommand = false
            state.avatarControlSender = { _ in sentCommand = true }

            try await state.prepareCustomCompanionDataForSignOut()

            #expect(!sentCommand)
            #expect(state.pendingCustomAvatarOperation == nil)

            try await snapshot.restore(removingAssetIDs: [])
        }
    }

    @Test("sign out without an index still removes orphaned private avatar files")
    func emptyLocalSignOutSweepsOrphanedAvatarFiles() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let fileManager = FileManager.default
            let documentsDirectory = try #require(
                fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            )
            let orphanURL = documentsDirectory.appendingPathComponent(
                "custom_companion_orphan_\(UUID().uuidString)_pixels.dat"
            )
            let pendingPreviewURL = documentsDirectory.appendingPathComponent(
                LocalStorage.pendingCustomAvatarPreviewFileName
            )
            let pendingImageURL = documentsDirectory.appendingPathComponent(
                LocalStorage.pendingCustomAvatarImageFileName
            )
            defer {
                try? fileManager.removeItem(at: orphanURL)
                try? fileManager.removeItem(at: pendingPreviewURL)
                try? fileManager.removeItem(at: pendingImageURL)
            }
            try Data("private-avatar".utf8).write(to: orphanURL)
            try Data("private-preview".utf8).write(to: pendingPreviewURL)
            try Data("private-image".utf8).write(to: pendingImageURL)

            let state = AppState.makeForTesting()
            state.customCompanions = []
            state.userProfile = .default
            state.customAvatarConnectionProvider = { (false, nil) }

            try await state.prepareCustomCompanionDataForSignOut()

            #expect(!fileManager.fileExists(atPath: orphanURL.path))
            #expect(!fileManager.fileExists(atPath: pendingPreviewURL.path))
            #expect(!fileManager.fileExists(atPath: pendingImageURL.path))
            #expect(state.pendingCustomAvatarOperation == nil)

            try await snapshot.restore(removingAssetIDs: [])
        }
    }

    @Test("sign out removes malformed and quarantined custom companion indexes")
    func emptyLocalSignOutRemovesPrivateCompanionIndexes() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let fileManager = FileManager.default
            let documentsDirectory = try #require(
                fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            )
            let indexURL = documentsDirectory.appendingPathComponent("custom_companions.json")
            let corruptIndexURL = documentsDirectory.appendingPathComponent("custom_companions.json.corrupt")
            defer {
                try? fileManager.removeItem(at: indexURL)
                try? fileManager.removeItem(at: corruptIndexURL)
            }
            try Data("private-backstory".utf8).write(to: indexURL)
            try Data("private-boundary".utf8).write(to: corruptIndexURL)

            let state = AppState.makeForTesting()
            state.customCompanions = []
            state.userProfile = .default
            state.customAvatarConnectionProvider = { (false, nil) }

            try await state.prepareCustomCompanionDataForSignOut()

            #expect(!fileManager.fileExists(atPath: indexURL.path))
            #expect(!fileManager.fileExists(atPath: corruptIndexURL.path))

            try await snapshot.restore(removingAssetIDs: [])
        }
    }

    @Test("a pending apply marker survives candidate image write failure")
    func applyMarkerPrecedesCandidateImageWrites() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let fileManager = FileManager.default
            let documentsDirectory = try #require(
                fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            )
            let pendingImageURL = documentsDirectory.appendingPathComponent(
                LocalStorage.pendingCustomAvatarImageFileName
            )
            try await LocalStorage.shared.clearPendingCustomAvatarOperation()
            try fileManager.createDirectory(
                at: pendingImageURL,
                withIntermediateDirectories: false
            )
            defer { try? fileManager.removeItem(at: pendingImageURL) }

            let state = AppState.makeForTesting()
            let companion = makeCompanion(id: UUID(), name: "Tracked")
            state.customAvatarConnectionProvider = { (true, UUID()) }

            await #expect(throws: (any Error).self) {
                try await state.applyCustomCompanion(
                    companion,
                    previewData: validPNG(),
                    imageData: validPNG()
                )
            }

            #expect(try await LocalStorage.shared.loadPendingCustomAvatarOperation()?.avatarID == companion.id)

            try? fileManager.removeItem(at: pendingImageURL)
            try await snapshot.restore(removingAssetIDs: [companion.id])
        }
    }

    @Test("offline exact deletion without a known device still removes local data")
    func offlineExactDeletionWithoutDeviceIdentityDeletesLocalData() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let id = UUID()
            state.customCompanions = [makeCompanion(id: id, name: "Keep Me")]
            state.userProfile.customCompanionId = id
            state.customAvatarConnectionProvider = { (false, nil) }

            try await state.deleteCustomCompanion(id: id)

            #expect(state.customCompanions.isEmpty)
            #expect(state.userProfile.customCompanionId == nil)
            #expect(state.pendingCustomAvatarOperation == nil)

            try await snapshot.restore(removingAssetIDs: [id])
        }
    }

    @Test("erase retry and inventory reconciliation reject a wildcard device marker")
    func eraseRecoveryRejectsMissingDeviceIdentity() async {
        let state = AppState.makeForTesting()
        let operation = PendingCustomAvatarOperation(
            kind: .eraseAll,
            phase: .awaitingEraseResult,
            operationID: 405,
            avatarID: nil,
            deviceID: nil,
            fileCRC32: 0,
            fileLength: 0,
            candidateCompanion: nil,
            candidatePreviewFileName: nil,
            candidateImageFileName: nil,
            oldSelection: CustomAvatarSelectionSnapshot(profile: .default)
        )
        state.pendingCustomAvatarOperation = operation
        state.customAvatarConnectionProvider = { (true, UUID()) }
        var sentCommand = false
        state.avatarControlSender = { _ in sentCommand = true }

        await state.retryCustomAvatarOperation()

        #expect(!sentCommand)
        #expect(state.pendingCustomAvatarOperation == operation)
        #expect(state.customAvatarOperationState == .failed(
            CustomAvatarOperationError.wrongDevice.localizedDescription
        ))

        let shouldRetry = await state.reconcileCustomAvatarInventory(
            hasImage: false,
            avatarID: nil,
            byteLength: 0,
            reportedCRC32: 0
        )
        #expect(!shouldRetry)
        #expect(state.pendingCustomAvatarOperation == operation)
        #expect(state.customAvatarOperationState == .failed(
            CustomAvatarOperationError.wrongDevice.localizedDescription
        ))
    }

    @Test("empty DeviceWake inventory cannot complete eraseAll while staged bytes may remain")
    func emptyInventoryStillFlushesEraseAllControl() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let deviceID = UUID()
            let operation = PendingCustomAvatarOperation(
                kind: .eraseAll,
                phase: .awaitingEraseResult,
                operationID: 406,
                avatarID: nil,
                deviceID: deviceID,
                fileCRC32: 0,
                fileLength: 0,
                candidateCompanion: nil,
                candidatePreviewFileName: nil,
                candidateImageFileName: nil,
                oldSelection: CustomAvatarSelectionSnapshot(profile: .default)
            )
            try await LocalStorage.shared.savePendingCustomAvatarOperation(operation)
            state.pendingCustomAvatarOperation = operation
            state.customAvatarConnectionProvider = { (true, deviceID) }
            var sentEraseAll = false
            state.avatarControlSender = { command in
                guard case .eraseAll(let operationID) = command else {
                    Issue.record("Expected eraseAll")
                    return
                }
                sentEraseAll = true
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .erased,
                        avatarState: .empty,
                        customActive: false,
                        avatarID: nil,
                        byteLength: 0,
                        crc32: 0
                    )
                )
            }

            let needsControlErase = await state.reconcileCustomAvatarInventory(
                hasImage: false,
                avatarID: nil,
                byteLength: 0,
                reportedCRC32: 0
            )

            #expect(needsControlErase)
            #expect(state.pendingCustomAvatarOperation == operation)
            let persisted = try await LocalStorage.shared.loadPendingCustomAvatarOperation()
            #expect(persisted?.kind == .eraseAll)
            #expect(persisted?.operationID == operation.operationID)
            #expect(persisted?.deviceID == deviceID)

            await state.flushPriorityCustomAvatarOperationIfNeeded()

            #expect(sentEraseAll)
            #expect(state.pendingCustomAvatarOperation == nil)

            try await snapshot.restore(removingAssetIDs: [])
        }
    }

    @Test("recovered eraseAll also finishes local sign-out cleanup before clearing its marker")
    func recoveredEraseAllRemovesLocalCustomData() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let companionID = UUID()
            let deviceID = UUID()
            let companion = makeCompanion(id: companionID, name: "Remove Me")
            let png = try validPNG()
            try await LocalStorage.shared.saveCustomCompanionAssets(
                id: companionID,
                previewData: png,
                imageData: png
            )
            try await LocalStorage.shared.saveCustomCompanions([companion])
            var profile = UserProfile.default
            profile.customCompanionId = companionID
            try await LocalStorage.shared.saveUserProfile(profile)
            state.customCompanions = [companion]
            state.userProfile = profile

            let operation = PendingCustomAvatarOperation(
                kind: .eraseAll,
                phase: .awaitingEraseResult,
                operationID: 407,
                avatarID: nil,
                deviceID: deviceID,
                fileCRC32: 0,
                fileLength: 0,
                candidateCompanion: nil,
                candidatePreviewFileName: nil,
                candidateImageFileName: nil,
                oldSelection: CustomAvatarSelectionSnapshot(profile: profile)
            )
            try await LocalStorage.shared.savePendingCustomAvatarOperation(operation)
            state.pendingCustomAvatarOperation = operation
            state.customAvatarConnectionProvider = { (true, deviceID) }
            state.avatarControlSender = { command in
                guard case .eraseAll(let operationID) = command else {
                    Issue.record("Expected eraseAll")
                    return
                }
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .erased,
                        avatarState: .empty,
                        customActive: false,
                        avatarID: nil,
                        byteLength: 0,
                        crc32: 0
                    )
                )
            }

            await state.retryCustomAvatarOperation()

            #expect(state.customCompanions.isEmpty)
            #expect(state.userProfile.customCompanionId == nil)
            #expect(await LocalStorage.shared.loadCustomCompanionImageData(id: companionID) == nil)
            #expect(state.pendingCustomAvatarOperation == nil)
            #expect(try await LocalStorage.shared.loadPendingCustomAvatarOperation() == nil)

            try await snapshot.restore(removingAssetIDs: [companionID])
        }
    }

    @Test("two concurrent avatar starts admit only one transaction")
    func concurrentAvatarStartsAdmitOnlyOne() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let deviceID = UUID()
            let png = try validPNG()
            let kriData = try KRIEncoder.encode(pngData: png)
            state.customAvatarConnectionProvider = { (true, deviceID) }
            state.customAvatarFrameSender = { operationID, avatarID, _, progress in
                try await Task.sleep(for: .milliseconds(100))
                progress(kriData.count, kriData.count)
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .staged,
                        avatarState: .staged,
                        customActive: false,
                        avatarID: avatarID,
                        byteLength: UInt32(kriData.count),
                        crc32: CRC32.ieee(kriData)
                    )
                )
            }
            state.avatarControlSender = { command in
                guard case .commit(let operationID, let avatarID) = command else { return }
                state.handleAvatarControlResult(
                    AvatarControlResult(
                        operationID: operationID,
                        status: .committed,
                        avatarState: .committed,
                        customActive: true,
                        avatarID: avatarID,
                        byteLength: UInt32(kriData.count),
                        crc32: CRC32.ieee(kriData)
                    )
                )
            }

            let first = Task { @MainActor in
                try await state.addCustomCompanion(
                    name: "First",
                    relationship: .pet,
                    personaVoice: .companion,
                    previewData: png,
                    imageData: png
                )
            }
            let transferDeadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < transferDeadline {
                if case .transferring = state.customAvatarOperationState { break }
                await Task.yield()
            }
            guard case .transferring = state.customAvatarOperationState else {
                first.cancel()
                _ = try? await first.value
                try await snapshot.restore(removingAssetIDs: [])
                Issue.record("First operation did not reach transferring before the deadline")
                return
            }

            var secondError: CustomAvatarOperationError?
            do {
                _ = try await state.addCustomCompanion(
                    name: "Second",
                    relationship: .friend,
                    personaVoice: .playful,
                    previewData: png,
                    imageData: png
                )
            } catch let error as CustomAvatarOperationError {
                secondError = error
            }
            let committed = try await first.value

            #expect(secondError == .operationInProgress)
            #expect(state.customCompanions.map(\.id) == [committed.id])
            #expect(state.pendingCustomAvatarOperation == nil)

            try await snapshot.restore(removingAssetIDs: [committed.id])
        }
    }

    @Test("sign out waits while an acknowledged commit is finishing locally")
    func signOutDoesNotReplaceCommittingApply() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let snapshot = try await PersistenceSnapshot.capture()
            let state = AppState.makeForTesting()
            let deviceID = UUID()
            let candidate = makeCompanion(id: UUID(), name: "Candidate")
            let operation = makePendingApply(
                companion: candidate,
                oldID: nil,
                deviceID: deviceID,
                kriData: Data([1]),
                phase: .awaitingCommitResult
            )
            try await LocalStorage.shared.savePendingCustomAvatarOperation(operation)
            state.pendingCustomAvatarOperation = operation
            state.customAvatarOperationState = .committing
            state.customAvatarConnectionProvider = { (false, deviceID) }

            await #expect(throws: CustomAvatarOperationError.self) {
                try await state.prepareCustomCompanionDataForSignOut()
            }
            #expect(state.pendingCustomAvatarOperation == operation)
            let persisted = try await LocalStorage.shared.loadPendingCustomAvatarOperation()
            #expect(persisted?.operationID == operation.operationID)
            #expect(persisted?.kind == .apply)
            #expect(persisted?.phase == .awaitingCommitResult)

            try await snapshot.restore(removingAssetIDs: [candidate.id])
        }
    }

    private func makeCompanion(id: UUID, name: String) -> CustomCompanion {
        CustomCompanion(
            id: id,
            name: name,
            relationship: .pet,
            personaVoice: .companion,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id)
        )
    }

    private func validPNG() throws -> Data {
        try #require(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9WQAAAABJRU5ErkJggg=="
        ))
    }

    private func makePendingApply(
        companion: CustomCompanion,
        oldID: UUID?,
        deviceID: UUID,
        kriData: Data,
        phase: PendingCustomAvatarPhase
    ) -> PendingCustomAvatarOperation {
        PendingCustomAvatarOperation(
            kind: .apply,
            phase: phase,
            operationID: 700,
            avatarID: companion.id,
            deviceID: deviceID,
            fileCRC32: CRC32.ieee(kriData),
            fileLength: kriData.count,
            candidateCompanion: companion,
            candidatePreviewFileName: LocalStorage.pendingCustomAvatarPreviewFileName,
            candidateImageFileName: LocalStorage.pendingCustomAvatarImageFileName,
            oldSelection: CustomAvatarSelectionSnapshot(
                builtInCharacter: .joy,
                customCompanionID: oldID,
                intimacyStage: .closeFriend
            )
        )
    }
}

private struct PersistenceSnapshot: Sendable {
    let companions: [CustomCompanion]
    let profile: UserProfile?
    let onboardingProfile: OnboardingProfile?
    let usage: CompanionUsageState?
    let pendingOperation: PendingCustomAvatarOperation?
    let pendingPreview: Data?
    let pendingImage: Data?
    let onboardingGate: Bool

    static func capture() async throws -> Self {
        Self(
            companions: try await LocalStorage.shared.loadCustomCompanions(),
            profile: try await LocalStorage.shared.loadUserProfile(),
            onboardingProfile: try await LocalStorage.shared.loadOnboardingProfile(),
            usage: try await LocalStorage.shared.loadCompanionUsageState(),
            pendingOperation: try await LocalStorage.shared.loadPendingCustomAvatarOperation(),
            pendingPreview: await LocalStorage.shared.loadPendingCustomAvatarPreviewData(),
            pendingImage: await LocalStorage.shared.loadPendingCustomAvatarImageData(),
            onboardingGate: UserDefaults.standard.bool(forKey: "isOnboardingCompleted")
        )
    }

    func restore(removingAssetIDs ids: [UUID]) async throws {
        for id in ids {
            try await LocalStorage.shared.deleteCustomCompanionAssets(id: id)
        }
        try await LocalStorage.shared.saveCustomCompanions(companions)
        if let profile {
            try await LocalStorage.shared.saveUserProfile(profile)
        } else {
            try await LocalStorage.shared.deleteFile(named: "user_profile.json")
        }
        if let onboardingProfile {
            try await LocalStorage.shared.saveOnboardingProfile(onboardingProfile)
        } else {
            try await LocalStorage.shared.deleteFile(named: "onboarding_profile.json")
        }
        if let usage {
            try await LocalStorage.shared.saveCompanionUsageState(usage)
        } else {
            try await LocalStorage.shared.deleteFile(named: "companion_usage_state.json")
        }
        try await LocalStorage.shared.clearPendingCustomAvatarOperation()
        if let pendingOperation {
            try await LocalStorage.shared.savePendingCustomAvatarOperation(pendingOperation)
        }
        if let pendingPreview, let pendingImage {
            try await LocalStorage.shared.savePendingCustomAvatarAssets(
                previewData: pendingPreview,
                imageData: pendingImage
            )
        }
        UserDefaults.standard.set(onboardingGate, forKey: "isOnboardingCompleted")
    }
}
