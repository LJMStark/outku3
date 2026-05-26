import Foundation

public struct BLESecureEnvelope: Sendable {
    public static let protocolVersion: UInt8 = 2
    public static let signatureLength: Int = 32

    public let version: UInt8
    public let payloadType: UInt8
    public let nonce: UInt64
    public let issuedAt: UInt32
    public let payload: Data
    public let signature: Data

    public init(
        version: UInt8 = BLESecureEnvelope.protocolVersion,
        payloadType: UInt8,
        nonce: UInt64,
        issuedAt: UInt32,
        payload: Data,
        signature: Data
    ) {
        self.version = version
        self.payloadType = payloadType
        self.nonce = nonce
        self.issuedAt = issuedAt
        self.payload = payload
        self.signature = signature
    }

    public var signingBytes: Data {
        var data = Data()
        data.append(version)
        data.append(payloadType)
        data.appendBigEndian(nonce)
        data.appendBigEndian(issuedAt)
        data.appendBigEndian(UInt16(payload.count))
        data.append(payload)
        return data
    }

    public func encoded() -> Data {
        var data = signingBytes
        data.append(signature)
        return data
    }

    public static func decode(_ data: Data) throws -> BLESecureEnvelope {
        let fixedHeaderLength = 1 + 1 + 8 + 4 + 2
        let minimumLength = fixedHeaderLength + signatureLength
        guard data.count >= minimumLength else {
            throw AppError.bleSecurity("Secure envelope too short")
        }

        var cursor = 0
        let version = data[cursor]
        cursor += 1

        let payloadType = data[cursor]
        cursor += 1

        let nonce = data.bigEndianUInt64(at: cursor)
        cursor += 8

        let issuedAt = data.bigEndianUInt32(at: cursor)
        cursor += 4

        let payloadLength = data.bigEndianUInt16(at: cursor)
        cursor += 2

        let payloadEnd = cursor + Int(payloadLength)
        guard payloadEnd + signatureLength == data.count else {
            throw AppError.bleSecurity("Secure envelope length mismatch")
        }

        let payload = data.subdata(in: cursor..<payloadEnd)
        let signature = data.subdata(in: payloadEnd..<(payloadEnd + signatureLength))

        return BLESecureEnvelope(
            version: version,
            payloadType: payloadType,
            nonce: nonce,
            issuedAt: issuedAt,
            payload: payload,
            signature: signature
        )
    }
}
