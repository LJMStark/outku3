import CryptoKit
import Foundation
import Testing
@testable import KiroleFeature

@Suite("BLESecurity Tests")
struct BLESecurityTests {
    private static let sharedSecret = "kirole-ble-security-test-secret"

    @Test("BLE mode falls back to compatibility when shared secret is missing")
    @MainActor
    func compatibilityModeWithoutSecret() {
        AppSecrets.configure(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            openRouterAPIKey: nil,
            bleSharedSecret: nil
        )

        #expect(BLEService.configuredSecurityMode == .compatibility)
        #expect(BLEService.shared.securityMode == .compatibility)
    }

    @Test("BLE mode becomes secure when shared secret is configured")
    @MainActor
    func secureModeWithSecret() {
        configureSecret()

        #expect(BLEService.configuredSecurityMode == .secure)
        #expect(BLEService.shared.securityMode == .secure)
    }

    @Test("Handshake establishes secure session and allows secure payload round-trip")
    @MainActor
    func handshakeAndSecureRoundTrip() throws {
        configureSecret()
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

    private func configureSecret() {
        AppSecrets.configure(
            supabaseURL: nil,
            supabaseAnonKey: nil,
            openRouterAPIKey: nil,
            bleSharedSecret: Self.sharedSecret
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
        signedData.append(contentsOf: withUnsafeBytes(of: issuedAt.bigEndian) { Array($0) })

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
