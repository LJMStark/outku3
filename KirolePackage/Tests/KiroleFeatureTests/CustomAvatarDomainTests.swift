import Foundation
import Testing
@testable import KiroleFeature

@Suite("Custom avatar domain", .serialized)
struct CustomAvatarDomainTests {
    @Test("avatar revision key changes when the same companion is updated")
    func avatarRevisionKeyTracksSameIdentityUpdates() {
        let id = UUID()
        let original = makeCompanion(
            id: id,
            name: "Mochi",
            updatedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )
        let updated = original.updatingMetadata(
            from: original,
            updatedAt: Date(timeIntervalSince1970: 1_720_000_001)
        )

        #expect(updated.id == original.id)
        #expect(updated.avatarRevisionKey != original.avatarRevisionKey)
    }

    @Test("custom companions keep independent binding-day progress")
    func customCompanionUsageIsIndependent() {
        let firstID = UUID()
        let secondID = UUID()
        let firstProgress = CompanionBindingProgress(totalUsedDays: 6)
        let secondProgress = CompanionBindingProgress(totalUsedDays: 2)
        var usage = CompanionUsageState()

        usage.setProgress(firstProgress, forCustomCompanion: firstID)
        usage.setProgress(secondProgress, forCustomCompanion: secondID)

        #expect(usage.progress(forCustomCompanion: firstID) == firstProgress)
        #expect(usage.progress(forCustomCompanion: secondID) == secondProgress)
        #expect(usage.progress(forCustomCompanion: UUID()) == CompanionBindingProgress())
    }

    @Test("custom companion usage survives Codable round trip")
    func customCompanionUsageCodableRoundTrip() throws {
        let id = UUID()
        var usage = CompanionUsageState()
        usage.setProgress(
            CompanionBindingProgress(
                totalUsedDays: 15,
                lastUsedDate: Date(timeIntervalSince1970: 1_720_000_000)
            ),
            forCustomCompanion: id
        )

        let decoded = try JSONDecoder().decode(
            CompanionUsageState.self,
            from: JSONEncoder().encode(usage)
        )

        #expect(decoded == usage)
        #expect(IntimacyStage.from(bindingDays: decoded.progress(forCustomCompanion: id).totalUsedDays) == .closeFriend)
    }

    @Test("pending avatar operation persists identity and rollback snapshot without image bytes")
    func pendingOperationCodableRoundTrip() throws {
        let operationID: UInt32 = 0x0102_0304
        let avatarID = UUID()
        let deviceID = UUID()
        let candidate = makeCompanion(id: avatarID, name: "Mochi")
        let oldProfile = UserProfile(
            companionCharacter: .nova,
            intimacyStage: .familiar,
            customCompanionId: UUID()
        )
        let pending = PendingCustomAvatarOperation(
            kind: .apply,
            phase: .awaitingValidation,
            operationID: operationID,
            avatarID: avatarID,
            deviceID: deviceID,
            fileCRC32: 0xCBF4_3926,
            fileLength: 2_240_012,
            candidateCompanion: candidate,
            candidatePreviewFileName: "candidate_preview.png",
            candidateImageFileName: "candidate_image.kri",
            oldSelection: CustomAvatarSelectionSnapshot(profile: oldProfile),
            startedAt: Date(timeIntervalSince1970: 1_720_000_000)
        )

        let decoded = try JSONDecoder().decode(
            PendingCustomAvatarOperation.self,
            from: JSONEncoder().encode(pending)
        )

        #expect(decoded == pending)
        #expect(decoded.oldSelection.customCompanionID == oldProfile.customCompanionId)
        #expect(decoded.oldSelection.intimacyStage == .familiar)
    }

    @Test("pending avatar operation and candidate files round trip in local storage")
    func pendingOperationStorageRoundTrip() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let savedPending = try await LocalStorage.shared.loadPendingCustomAvatarOperation()
            let savedPreview = await LocalStorage.shared.loadPendingCustomAvatarPreviewData()
            let savedImage = await LocalStorage.shared.loadPendingCustomAvatarImageData()
            let id = UUID()
            let pending = PendingCustomAvatarOperation(
                kind: .eraseExact,
                phase: .awaitingEraseResult,
                operationID: 7,
                avatarID: id,
                deviceID: nil,
                fileCRC32: 0,
                fileLength: 0,
                candidateCompanion: nil,
                candidatePreviewFileName: nil,
                candidateImageFileName: nil,
                oldSelection: CustomAvatarSelectionSnapshot(profile: .default),
                startedAt: Date(timeIntervalSince1970: 1_720_000_000)
            )
            let preview = Data([0x89, 0x50, 0x4E, 0x47])
            let image = Data([0x4B, 0x52, 0x49, 0x31])

            try await LocalStorage.shared.savePendingCustomAvatarOperation(pending)
            try await LocalStorage.shared.savePendingCustomAvatarAssets(
                previewData: preview,
                imageData: image
            )

            #expect(try await LocalStorage.shared.loadPendingCustomAvatarOperation() == pending)
            #expect(await LocalStorage.shared.loadPendingCustomAvatarPreviewData() == preview)
            #expect(await LocalStorage.shared.loadPendingCustomAvatarImageData() == image)

            try await LocalStorage.shared.clearPendingCustomAvatarOperation()
            #expect(try await LocalStorage.shared.loadPendingCustomAvatarOperation() == nil)
            #expect(await LocalStorage.shared.loadPendingCustomAvatarPreviewData() == nil)
            #expect(await LocalStorage.shared.loadPendingCustomAvatarImageData() == nil)

            if let savedPending {
                try await LocalStorage.shared.savePendingCustomAvatarOperation(savedPending)
            }
            if let savedPreview, let savedImage {
                try await LocalStorage.shared.savePendingCustomAvatarAssets(
                    previewData: savedPreview,
                    imageData: savedImage
                )
            }
        }
    }

    private func makeCompanion(
        id: UUID,
        name: String,
        updatedAt: Date = Date()
    ) -> CustomCompanion {
        CustomCompanion(
            id: id,
            name: name,
            relationship: .pet,
            personaVoice: .companion,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id),
            updatedAt: updatedAt
        )
    }
}
