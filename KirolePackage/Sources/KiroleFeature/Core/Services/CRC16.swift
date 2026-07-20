import Foundation

// MARK: - CRC16

// MARK: - CRC32

enum CRC32 {
    /// CRC-32/IEEE（反射，poly 0xEDB88320，init/xorout 0xFFFFFFFF）——协议 §5.8
    /// DeviceWake `AvatarCRC32` 同口径（v2.6.0）：固件存 0x15 PNG 时算一次并随
    /// DeviceWake 上报，App 比对本地激活头像的 CRC，不一致/无图即重推。
    static func ieee(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }
}

enum CRC16 {
    /// CRC16-CCITT-FALSE (poly 0x1021, init 0xFFFF)
    static func ccittFalse(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if (crc & 0x8000) != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }
}
