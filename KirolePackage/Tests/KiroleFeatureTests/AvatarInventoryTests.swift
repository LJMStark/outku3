import Foundation
import Testing
@testable import KiroleFeature

/// v2.7 设备头像库存对账：DeviceWake(0x30) 追加 AvatarState、AvatarID、长度和 CRC。
@Suite("Avatar Inventory (DeviceWake v2.7)", .serialized)
struct AvatarInventoryTests {

    @Test("CRC-32/IEEE 标准校验向量：\"123456789\" → 0xCBF43926")
    func crc32KnownVector() {
        #expect(CRC32.ieee(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.ieee(Data()) == 0x0000_0000)
    }

    @Test("DeviceWake 29B payload：解析电量、固件版本、头像身份、长度与 CRC")
    func deviceWakeParsesAvatarInventory() {
        let avatarID = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!
        var rawUUID = avatarID.uuid
        var payload = Data([0x64, 0x01, 0x02, 0x03, 0x01])
        payload.append(withUnsafeBytes(of: &rawUUID) { Data($0) })
        payload.appendBigEndian(UInt32(2_240_012))
        payload.appendBigEndian(UInt32(0xCBF4_3926))
        let event = EventLog.fromBLEPayload(type: 0x30, payload: payload)
        #expect(event?.value == 100)
        #expect(event?.firmwareVersion == FirmwareVersion(major: 1, minor: 2, patch: 3))
        #expect(event?.avatarInventory == EventLog.AvatarInventory(
            hasImage: true,
            avatarID: avatarID,
            byteLength: 2_240_012,
            crc32: 0xCBF4_3926
        ))
    }

    @Test("短 payload 与旧 9B 库存格式均不按 v2.7 解析")
    func shorterPayloadsHaveNoInventory() {
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: Data())?.avatarInventory == nil)
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: Data([0x50]))?.avatarInventory == nil)
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: Data([0x50, 0x01, 0x00, 0x00]))?.avatarInventory == nil)
        #expect(EventLog.fromBLEPayload(
            type: 0x30,
            payload: Data([0x50, 0x01, 0x00, 0x00, 0x01, 0xCB, 0xF4, 0x39, 0x26])
        )?.avatarInventory == nil)
    }

    @Test("DeviceWake 拒绝非法布尔值、矛盾库存和尾部字节")
    func inconsistentInventoryIsIgnored() {
        let avatarID = UUID()
        var rawUUID = avatarID.uuid
        let uuidData = withUnsafeBytes(of: &rawUUID) { Data($0) }

        var invalidBoolean = Data([80, 2, 7, 0, 2])
        invalidBoolean.append(Data(repeating: 0, count: 24))
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: invalidBoolean)?.avatarInventory == nil)

        var emptyWithIdentity = Data([80, 2, 7, 0, 0])
        emptyWithIdentity.append(uuidData)
        emptyWithIdentity.appendBigEndian(UInt32(16))
        emptyWithIdentity.appendBigEndian(UInt32(1))
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: emptyWithIdentity)?.avatarInventory == nil)

        var imageWithoutIdentity = Data([80, 2, 7, 0, 1])
        imageWithoutIdentity.append(Data(repeating: 0, count: 16))
        imageWithoutIdentity.appendBigEndian(UInt32(16))
        imageWithoutIdentity.appendBigEndian(UInt32(1))
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: imageWithoutIdentity)?.avatarInventory == nil)

        var trailing = Data([80, 2, 7, 0, 1])
        trailing.append(uuidData)
        trailing.appendBigEndian(UInt32(16))
        trailing.appendBigEndian(UInt32(1))
        trailing.append(0)
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: trailing)?.avatarInventory == nil)
    }

    @Test("DeviceWake 库存匹配只触发 query 恢复，不直接切换本地身份")
    @MainActor func matchingInventoryRequestsQueryRecovery() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let previousProfile = try await storage.loadUserProfile()
            let previousCompanions = try await storage.loadCustomCompanions()
            let id = UUID()
            let png = try #require(Data(base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9WQAAAABJRU5ErkJggg=="
            ))
            let kri = try KRIEncoder.encode(pngData: png)
            let companion = makeCompanion(id: id)
            let operation = makeApplyOperation(
                companion: companion,
                fileLength: kri.count,
                crc32: CRC32.ieee(kri)
            )
            try await storage.savePendingCustomAvatarAssets(previewData: png, imageData: png)
            try await storage.savePendingCustomAvatarOperation(operation)
            let state = AppState.makeForTesting()
            state.pendingCustomAvatarOperation = operation
            state.customAvatarConnectionProvider = { (true, operation.deviceID) }

            let shouldRecover = await state.reconcileCustomAvatarInventory(
                hasImage: true,
                avatarID: id,
                byteLength: UInt32(kri.count),
                reportedCRC32: CRC32.ieee(kri)
            )

            #expect(shouldRecover)
            #expect(state.userProfile.customCompanionId != id)
            #expect(state.pendingCustomAvatarOperation == operation)
            #expect(state.customAvatarOperationState == .idle)
            #expect(await storage.loadCustomCompanionImageData(id: id) == nil)

            try await storage.deleteCustomCompanionAssets(id: id)
            try await storage.saveUserProfile(previousProfile ?? .default)
            try await storage.saveCustomCompanions(previousCompanions)
            try await storage.clearPendingCustomAvatarOperation()
        }
    }

    @Test("DeviceWake 不判断第三方库存，统一交给 query 恢复")
    @MainActor func inventoryMismatchStillRequestsQueryRecovery() async throws {
        let state = AppState.makeForTesting()
        let candidate = makeCompanion(id: UUID())
        let oldID = UUID()
        var profile = UserProfile.default
        profile.customCompanionId = oldID
        state.userProfile = profile
        let operation = makeApplyOperation(
            companion: candidate,
            fileLength: 128,
            crc32: 0xCBF4_3926,
            oldProfile: profile
        )
        state.pendingCustomAvatarOperation = operation
        state.customAvatarConnectionProvider = { (true, operation.deviceID) }

        let shouldRecover = await state.reconcileCustomAvatarInventory(
            hasImage: true,
            avatarID: oldID,
            byteLength: 128,
            reportedCRC32: 0xCBF4_3926
        )

        #expect(shouldRecover)
        #expect(state.userProfile.customCompanionId == oldID)
        #expect(state.pendingCustomAvatarOperation == operation)
        #expect(state.customAvatarOperationState == .idle)
    }

    @Test("活跃传输期间的 DeviceWake 不抢占事务所有权")
    @MainActor func activeTransferIgnoresDeviceWakeInventory() async {
        let state = AppState.makeForTesting()
        let candidate = makeCompanion(id: UUID())
        let operation = makeApplyOperation(
            companion: candidate,
            fileLength: 128,
            crc32: 0xCBF4_3926
        )
        state.pendingCustomAvatarOperation = operation
        state.customAvatarOperationState = .transferring(sentBytes: 64, totalBytes: 128)
        state.customAvatarConnectionProvider = { (true, operation.deviceID) }

        let shouldRecover = await state.reconcileCustomAvatarInventory(
            hasImage: true,
            avatarID: candidate.id,
            byteLength: 128,
            reportedCRC32: 0xCBF4_3926
        )

        #expect(!shouldRecover)
        #expect(state.pendingCustomAvatarOperation == operation)
        #expect(state.userProfile.customCompanionId != candidate.id)
        #expect(state.customAvatarOperationState == .transferring(sentBytes: 64, totalBytes: 128))
    }

    private func makeCompanion(id: UUID) -> CustomCompanion {
        CustomCompanion(
            id: id,
            name: "Mochi",
            relationship: .pet,
            personaVoice: .companion,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id)
        )
    }

    private func makeApplyOperation(
        companion: CustomCompanion,
        fileLength: Int,
        crc32: UInt32,
        oldProfile: UserProfile = .default
    ) -> PendingCustomAvatarOperation {
        PendingCustomAvatarOperation(
            kind: .apply,
            phase: .awaitingCommitResult,
            operationID: 0x1020_3040,
            avatarID: companion.id,
            deviceID: UUID(),
            fileCRC32: crc32,
            fileLength: fileLength,
            candidateCompanion: companion,
            candidatePreviewFileName: LocalStorage.pendingCustomAvatarPreviewFileName,
            candidateImageFileName: LocalStorage.pendingCustomAvatarImageFileName,
            oldSelection: CustomAvatarSelectionSnapshot(profile: oldProfile)
        )
    }
}
