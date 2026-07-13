import CryptoKit
import Foundation

@MainActor
public final class BLESecurityManager {
    private enum Handshake {
        static let requestKind: UInt8 = 0x01
        static let responseKind: UInt8 = 0x02
        static let signatureLength = 32
        static let allowedClockSkewSeconds: UInt32 = 120
        static let maxTrackedIncomingNonces = 512
    }

    private var pendingClientNonce: UInt64?
    private var seenIncomingNonces: [UInt64: UInt32] = [:]

    public private(set) var isSessionEstablished = false

    public func resetSession() {
        pendingClientNonce = nil
        isSessionEstablished = false
        pruneExpiredNonces(referenceTimestamp: currentTimestamp())
    }

    public func makeHandshakeRequestPayload() throws -> Data {
        let nonce = randomNonce()
        pendingClientNonce = nonce
        let issuedAt = currentTimestamp()

        var data = Data()
        data.append(Handshake.requestKind)
        data.appendBigEndian(nonce)
        data.appendBigEndian(issuedAt)
        data.append(try signature(for: data))
        return data
    }

    public func validateHandshakeResponsePayload(_ payload: Data) throws {
        let expectedLength = 1 + 8 + 8 + 4 + Handshake.signatureLength
        guard payload.count == expectedLength else {
            throw AppError.bleSecurity("Invalid handshake response length")
        }

        guard let expectedClientNonce = pendingClientNonce else {
            throw AppError.bleSecurity("No pending BLE handshake request")
        }

        let kind = payload[0]
        guard kind == Handshake.responseKind else {
            throw AppError.bleSecurity("Unexpected handshake response kind")
        }

        let signedData = Data(payload.prefix(1 + 8 + 8 + 4))
        let responseSignature = Data(payload.suffix(Handshake.signatureLength))
        let expectedSignature = try signature(for: signedData)
        guard responseSignature == expectedSignature else {
            throw AppError.bleSecurity("Handshake signature mismatch")
        }

        let clientNonce = payload.bigEndianUInt64(at: 1)
        guard clientNonce == expectedClientNonce else {
            throw AppError.bleSecurity("Handshake nonce mismatch")
        }

        let timestamp = payload.bigEndianUInt32(at: 17)

        try validateTimestamp(timestamp)

        isSessionEstablished = true
        pendingClientNonce = nil
    }

    public func securePayload(type: UInt8, payload: Data) throws -> Data {
        guard isSessionEstablished else {
            throw AppError.bleSecurity("BLE secure session has not been established")
        }
        // SecureEnvelope 的长度字段是 2 字节（signingBytes 里 `UInt16(payload.count)` 为
        // trapping 转换）：payload > 65535B 会直接崩进程，而 v2.5.24 的 0x15 头像 PNG
        // 可达 ~1MiB。信封 wire 格式结构上装不下大帧——在与固件重新设计 secure 大帧
        // 封装（加宽长度字段 / 分片签名）之前，这里抛错而非崩溃：调用方按普通发送失败
        // 处理（0x15 走待重发队列），不会发出损坏帧。见协议 §4.12 secure 模式备注。
        guard payload.count <= Int(UInt16.max) else {
            throw AppError.bleSecurity(
                "SecureEnvelope cannot carry \(payload.count)B payload (2-byte length field, max 65535B); large-frame secure design pending with firmware"
            )
        }

        let envelope = BLESecureEnvelope(
            payloadType: type,
            nonce: randomNonce(),
            issuedAt: currentTimestamp(),
            payload: payload,
            signature: Data()
        )

        let signature = try self.signature(for: envelope.signingBytes)
        let signed = BLESecureEnvelope(
            payloadType: type,
            nonce: envelope.nonce,
            issuedAt: envelope.issuedAt,
            payload: payload,
            signature: signature
        )

        return signed.encoded()
    }

    public func openSecurePayload(_ data: Data) throws -> BLEReceivedMessage {
        guard isSessionEstablished else {
            throw AppError.bleSecurity("BLE secure session has not been established")
        }

        let envelope = try BLESecureEnvelope.decode(data)
        guard envelope.version == BLESecureEnvelope.protocolVersion else {
            throw AppError.unsupportedProtocol(version: envelope.version)
        }

        try validateTimestamp(envelope.issuedAt)

        let expectedSignature = try signature(for: envelope.signingBytes)
        guard expectedSignature == envelope.signature else {
            throw AppError.bleSecurity("Secure envelope signature mismatch")
        }

        pruneExpiredNonces(referenceTimestamp: currentTimestamp())
        guard seenIncomingNonces[envelope.nonce] == nil else {
            throw AppError.bleSecurity("Replay packet detected")
        }
        seenIncomingNonces[envelope.nonce] = envelope.issuedAt
        trimNonceCacheIfNeeded()

        return BLEReceivedMessage(type: envelope.payloadType, payload: envelope.payload)
    }

    private func secretKey() throws -> SymmetricKey {
        guard let rawSecret = AppSecrets.bleSharedSecret, !rawSecret.isEmpty else {
            throw AppError.configuration("Missing BLE shared secret")
        }

        if let decoded = Data(base64Encoded: rawSecret), !decoded.isEmpty {
            return SymmetricKey(data: decoded)
        }

        guard let utf8 = rawSecret.data(using: .utf8), !utf8.isEmpty else {
            throw AppError.configuration("Invalid BLE shared secret")
        }

        return SymmetricKey(data: utf8)
    }

    private func signature(for data: Data) throws -> Data {
        let key = try secretKey()
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(signature)
    }

    private func validateTimestamp(_ timestamp: UInt32) throws {
        let now = currentTimestamp()
        let lowerBound = now > Handshake.allowedClockSkewSeconds ? now - Handshake.allowedClockSkewSeconds : 0
        let upperBound = now + Handshake.allowedClockSkewSeconds
        guard timestamp >= lowerBound, timestamp <= upperBound else {
            throw AppError.bleSecurity("Packet timestamp out of accepted window")
        }
    }

    private func pruneExpiredNonces(referenceTimestamp: UInt32) {
        let floor = referenceTimestamp > Handshake.allowedClockSkewSeconds
            ? referenceTimestamp - Handshake.allowedClockSkewSeconds
            : 0
        seenIncomingNonces = seenIncomingNonces.filter { $0.value >= floor }
    }

    private func trimNonceCacheIfNeeded() {
        guard seenIncomingNonces.count > Handshake.maxTrackedIncomingNonces else { return }

        let sortedByTimestamp = seenIncomingNonces.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value < rhs.value
        }
        let overflow = seenIncomingNonces.count - Handshake.maxTrackedIncomingNonces
        for (nonce, _) in sortedByTimestamp.prefix(overflow) {
            seenIncomingNonces.removeValue(forKey: nonce)
        }
    }

    private func randomNonce() -> UInt64 {
        UInt64.random(in: UInt64.min...UInt64.max)
    }

    private func currentTimestamp() -> UInt32 {
        UInt32(Date().timeIntervalSince1970)
    }
}
