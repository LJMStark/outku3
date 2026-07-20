import Foundation
import Testing
@testable import KiroleFeature

/// v2.6.0 设备头像库存对账：DeviceWake(0x30) 追加 AvatarState(1B)+AvatarCRC32(4B BE)，
/// App 比对本地激活头像的 CRC-32/IEEE，无图或不一致即重推 0x15——关闭"同设备存储
/// 被清空 App 无感知"盲区（行业惯例：设备上报所持资产校验和，主机差异重传）。
@Suite("Avatar Inventory (DeviceWake v2.6.0)")
struct AvatarInventoryTests {

    @Test("CRC-32/IEEE 标准校验向量：\"123456789\" → 0xCBF43926")
    func crc32KnownVector() {
        #expect(CRC32.ieee(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.ieee(Data()) == 0x0000_0000)
    }

    @Test("DeviceWake 9B payload：解析电量+固件版本+头像库存（BE CRC）")
    func deviceWakeParsesAvatarInventory() {
        let payload = Data([0x64, 0x01, 0x02, 0x03, 0x01, 0xCB, 0xF4, 0x39, 0x26])
        let event = EventLog.fromBLEPayload(type: 0x30, payload: payload)
        #expect(event?.value == 100)
        #expect(event?.firmwareVersion == FirmwareVersion(major: 1, minor: 2, patch: 3))
        #expect(event?.avatarInventory == EventLog.AvatarInventory(hasImage: true, crc32: 0xCBF4_3926))
    }

    @Test("旧固件 payload（0B/1B/4B）：库存为 nil，不触发对账")
    func shorterPayloadsHaveNoInventory() {
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: Data())?.avatarInventory == nil)
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: Data([0x50]))?.avatarInventory == nil)
        #expect(EventLog.fromBLEPayload(type: 0x30, payload: Data([0x50, 0x01, 0x00, 0x00]))?.avatarInventory == nil)
    }

    @Test("重推判定：无图必重推；有图但 CRC 不一致重推；一致不重推")
    func repushDecisionTable() {
        #expect(AppState.avatarNeedsRepush(hasImage: false, reportedCRC32: 0, localCRC32: 0xAB))
        #expect(AppState.avatarNeedsRepush(hasImage: true, reportedCRC32: 0x11, localCRC32: 0x22))
        #expect(!AppState.avatarNeedsRepush(hasImage: true, reportedCRC32: 0xAB, localCRC32: 0xAB))
    }
}
