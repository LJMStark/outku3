import CryptoKit
import Foundation
import Testing
@testable import KiroleFeature

@Suite("BLESecurity Tests", .serialized)
struct BLESecurityTests {
    private static let sharedSecret = "kirole-ble-security-test-secret"

    @Test("BLE mode uses development transport when shared secret is missing")
    @MainActor
    func developmentModeWithoutSecret() {
        defer { resetSecret() }
        AppSecrets.configure(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            openRouterAPIKey: nil,
            bleSharedSecret: nil
        )

        #expect(BLEService.configuredSecurityMode == .development)
        #expect(BLEService.shared.securityMode == .development)
    }

    @Test("BLE mode becomes secure when shared secret is configured")
    @MainActor
    func secureModeWithSecret() {
        configureSecret()
        defer { resetSecret() }

        #expect(BLEService.configuredSecurityMode == .secure)
        #expect(BLEService.shared.securityMode == .secure)
    }

    @Test("Handshake establishes secure session and allows secure payload round-trip")
    @MainActor
    func handshakeAndSecureRoundTrip() throws {
        configureSecret()
        defer { resetSecret() }
        let manager = BLESecurityManager()

        let request = try manager.makeHandshakeRequestPayload()
        let response = try makeHandshakeResponse(for: request)
        try manager.validateHandshakeResponsePayload(response)

        #expect(manager.isSessionEstablished)

        let plainPayload = Data("secure-message".utf8)
        let secured = try manager.securePayload(type: BLEDataType.taskList.rawValue, payload: plainPayload)
        let opened = try manager.openSecurePayload(secured)

        #expect(opened.type == BLEDataType.taskList.rawValue)
        #expect(opened.payload == plainPayload)
    }

    @Test("Forged signature is rejected")
    @MainActor
    func forgedSignatureRejected() throws {
        configureSecret()
        defer { resetSecret() }
        let manager = BLESecurityManager()

        let request = try manager.makeHandshakeRequestPayload()
        let response = try makeHandshakeResponse(for: request)
        try manager.validateHandshakeResponsePayload(response)

        var forged = try manager.securePayload(type: BLEDataType.weather.rawValue, payload: Data([0x01, 0x02, 0x03]))
        forged[forged.count - 1] ^= 0xFF

        #expect(throws: AppError.self) {
            _ = try manager.openSecurePayload(forged)
        }
    }

    @Test("Replay nonce is rejected")
    @MainActor
    func replayNonceRejected() throws {
        configureSecret()
        defer { resetSecret() }
        let manager = BLESecurityManager()

        let request = try manager.makeHandshakeRequestPayload()
        let response = try makeHandshakeResponse(for: request)
        try manager.validateHandshakeResponsePayload(response)

        let packet = try manager.securePayload(type: BLEDataType.time.rawValue, payload: Data([0xAA]))

        _ = try manager.openSecurePayload(packet)
        #expect(throws: AppError.self) {
            _ = try manager.openSecurePayload(packet)
        }
    }

    @Test("Replay nonce is rejected after session reset")
    @MainActor
    func replayNonceRejectedAfterSessionReset() throws {
        configureSecret()
        defer { resetSecret() }
        let manager = BLESecurityManager()

        let request = try manager.makeHandshakeRequestPayload()
        let response = try makeHandshakeResponse(for: request)
        try manager.validateHandshakeResponsePayload(response)

        let packet = try manager.securePayload(type: BLEDataType.time.rawValue, payload: Data([0xAA]))
        _ = try manager.openSecurePayload(packet)

        manager.resetSession()
        let secondRequest = try manager.makeHandshakeRequestPayload()
        let secondResponse = try makeHandshakeResponse(for: secondRequest)
        try manager.validateHandshakeResponsePayload(secondResponse)

        #expect(throws: AppError.self) {
            _ = try manager.openSecurePayload(packet)
        }
    }

    @Test("Secure envelope rejects trailing bytes")
    @MainActor
    func secureEnvelopeRejectsTrailingBytes() throws {
        configureSecret()
        defer { resetSecret() }
        let manager = BLESecurityManager()

        let request = try manager.makeHandshakeRequestPayload()
        let response = try makeHandshakeResponse(for: request)
        try manager.validateHandshakeResponsePayload(response)

        var packet = try manager.securePayload(type: BLEDataType.weather.rawValue, payload: Data([0x01]))
        packet.append(0x00)

        #expect(throws: AppError.self) {
            _ = try BLESecureEnvelope.decode(packet)
        }
    }

    private func configureSecret() {
        AppSecrets.configure(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            openRouterAPIKey: nil,
            bleSharedSecret: Self.sharedSecret
        )
    }

    private func resetSecret() {
        AppSecrets.configure(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            openRouterAPIKey: nil,
            bleSharedSecret: nil
        )
    }

    private func makeHandshakeResponse(for request: Data) throws -> Data {
        guard request.count >= 9 else {
            throw AppError.bleSecurity("Invalid handshake request payload in test")
        }

        let clientNonce = request.subdata(in: 1..<9)
        let serverNonce = Data(repeating: 0x42, count: 8)
        let issuedAt = UInt32(Date().timeIntervalSince1970)

        var signedData = Data()
        signedData.append(0x02)
        signedData.append(clientNonce)
        signedData.append(serverNonce)
        signedData.appendBigEndian(issuedAt)

        var response = signedData
        response.append(signature(for: signedData))
        return response
    }

    private func signature(for data: Data) -> Data {
        let key = SymmetricKey(data: Data(Self.sharedSecret.utf8))
        let code = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(code)
    }
}
