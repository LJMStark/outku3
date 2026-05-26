import Foundation

extension Data {
    /// 追加带长度前缀的字符串数据（截断到指定最大长度）。
    mutating func appendString(_ string: String, maxLength: Int) {
        let stringData = string.data(using: .utf8) ?? Data()
        let truncatedData = stringData.validUTF8Prefix(maxLength: maxLength)
        append(UInt8(truncatedData.count))
        append(truncatedData)
    }

    mutating func appendBigEndian(_ value: UInt16) {
        append(contentsOf: Swift.withUnsafeBytes(of: value.bigEndian) { Array($0) })
    }

    mutating func appendBigEndian(_ value: UInt32) {
        append(contentsOf: Swift.withUnsafeBytes(of: value.bigEndian) { Array($0) })
    }

    mutating func appendBigEndian(_ value: UInt64) {
        append(contentsOf: Swift.withUnsafeBytes(of: value.bigEndian) { Array($0) })
    }

    mutating func appendClampedUInt8(_ value: Int) {
        append(UInt8(clamping: value))
    }

    func bigEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    func bigEndianUInt32(at offset: Int) -> UInt32 {
        (UInt32(self[offset]) << 24)
            | (UInt32(self[offset + 1]) << 16)
            | (UInt32(self[offset + 2]) << 8)
            | UInt32(self[offset + 3])
    }

    func bigEndianUInt64(at offset: Int) -> UInt64 {
        (UInt64(bigEndianUInt32(at: offset)) << 32)
            | UInt64(bigEndianUInt32(at: offset + 4))
    }
}

private extension Data {
    func validUTF8Prefix(maxLength: Int) -> Data {
        guard maxLength > 0 else { return Data() }
        guard count > maxLength else { return self }

        var end = maxLength
        while end > 0 {
            let candidate = prefix(end)
            if String(data: candidate, encoding: .utf8) != nil {
                return Data(candidate)
            }
            end -= 1
        }

        return Data()
    }
}
