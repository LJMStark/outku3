import CryptoKit
import Foundation

@MainActor
public final class BLESecurityManager {
    private enum Handshake {
        static let requestKind: UInt8 = 0x01
        static let responseKind: UInt8 = 0x02
        static let signatureLength = 32
        static let allowedClockSkewSeconds: UInt32 = 120
    }

    private var pendingClientNonce: UInt64?
    private var seenIncomingNonces: [UInt64: UInt32] = [:]

    public private(set) var isSessionEstablished = false

    public func resetSession() {
        pendingClientNonce = nil
        seenIncomingNonces.removeAll()
        isSessionEstablished = false
    }

    public func makeHandshakeRequestPayload() throws -> Data {
        let nonce = randomNonce()
        pendingClientNonce = nonce
        let issuedAt = currentTimestamp()

        var data = Data()
        data.append(Handshake.requestKind)
        data.append(contentsOf: withUnsafeBytes(of: nonce.bigEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: issuedAt.bigEndian) { Array($0) })
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

        let clientNonceData = payload.subdata(in: 1..<9)
        let clientNonce = clientNonceData.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard clientNonce == expectedClientNonce else {
            throw AppError.bleSecurity("Handshake nonce mismatch")
        }

        let timestampData = payload.subdata(in: 17..<21)
        let timestamp = timestampData.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }

        try validateTimestamp(timestamp)

        isSessionEstablished = true
        pendingClientNonce = nil
    }

    public func securePayload(type: UInt8, payload: Data) throws -> Data {
        guard isSessionEstablished else {
            throw AppError.bleSecurity("BLE secure session has not been established")
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

    private func randomNonce() -> UInt64 {
        UInt64.random(in: UInt64.min...UInt64.max)
    }

    private func currentTimestamp() -> UInt32 {
        UInt32(Date().timeIntervalSince1970)
    }
}
