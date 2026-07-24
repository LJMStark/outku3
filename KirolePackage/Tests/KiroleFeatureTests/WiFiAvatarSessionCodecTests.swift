import Foundation
import Testing
@testable import KiroleFeature

@Suite("WiFi Avatar Session Codec (0x1A)")
struct WiFiAvatarSessionCodecTests {

    // MARK: Request (App → Device)

    @Test("Request round-trips for every command", arguments: WiFiAvatarSessionCommand.allCases)
    func requestRoundTrips(command: WiFiAvatarSessionCommand) throws {
        let request = WiFiAvatarSessionRequest(command: command, operationID: 0xDEAD_BEEF)
        let encoded = WiFiAvatarSessionCodec.encodeRequest(request)

        #expect(encoded.count == WiFiAvatarSessionCodec.requestLength)
        // Command(1) + OperationID(4 BE)
        #expect([UInt8](encoded) == [command.rawValue, 0xDE, 0xAD, 0xBE, 0xEF])

        let decoded = try WiFiAvatarSessionCodec.decodeRequest(encoded)
        #expect(decoded == request)
    }

    @Test("Request rejects wrong length")
    func requestRejectsWrongLength() {
        #expect(throws: WiFiAvatarSessionCodecError.invalidRequestLength(4)) {
            try WiFiAvatarSessionCodec.decodeRequest(Data([0x01, 0x00, 0x00, 0x00]))
        }
        #expect(throws: WiFiAvatarSessionCodecError.invalidRequestLength(6)) {
            try WiFiAvatarSessionCodec.decodeRequest(Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00]))
        }
    }

    @Test("Request rejects unknown command byte")
    func requestRejectsUnknownCommand() {
        #expect(throws: WiFiAvatarSessionCodecError.invalidCommand(0x09)) {
            try WiFiAvatarSessionCodec.decodeRequest(Data([0x09, 0x00, 0x00, 0x00, 0x01]))
        }
    }

    // MARK: Response (Device → App)

    @Test("OK response round-trips with credentials")
    func okResponseRoundTrips() throws {
        let credentials = WiFiAvatarSessionCredentials(
            ssid: "Kirole-A1B2",
            passphrase: "s0me-p@ss",
            gateway: IPv4Address(192, 168, 4, 1),
            port: 8080,
            path: "/avatar",
            token: "tok_0123456789",
            ttlSeconds: 120
        )
        let response = WiFiAvatarSessionResponse(
            command: .open,
            operationID: 0xA1B2_C3D4,
            status: .ok,
            credentials: credentials
        )

        let encoded = WiFiAvatarSessionCodec.encodeResponse(response)
        let decoded = try WiFiAvatarSessionCodec.decodeResponse(encoded)

        #expect(Array(encoded.prefix(6)) == [0x01, 0xA1, 0xB2, 0xC3, 0xD4, 0x00])
        #expect(decoded == response)
        #expect(decoded.credentials?.endpointURL?.absoluteString == "http://192.168.4.1:8080/avatar")
    }

    @Test("Non-OK response carries no credentials and round-trips")
    func errorResponseRoundTrips() throws {
        for status in [WiFiAvatarSessionStatus.unsupported, .busy, .wifiInitFailed, .invalidCommand, .unknownError] {
            let response = WiFiAvatarSessionResponse(
                command: .query,
                operationID: 7,
                status: status,
                credentials: nil
            )
            let encoded = WiFiAvatarSessionCodec.encodeResponse(response)
            let decoded = try WiFiAvatarSessionCodec.decodeResponse(encoded)
            #expect(decoded.status == status)
            #expect(decoded.credentials == nil)
        }
    }

    @Test("Passphrase and token are NOT ASCII-sanitized (credentials, not display text)")
    func credentialsPreserveNonASCII() throws {
        // café + smart quote — appendString would strip/rewrite these; the codec must not.
        let credentials = WiFiAvatarSessionCredentials(
            ssid: "Café-Net",
            passphrase: "pä$$w\u{2019}rd",
            gateway: IPv4Address(10, 0, 0, 1),
            port: 80,
            path: "/avatar",
            token: "tok",
            ttlSeconds: 60
        )
        let encoded = WiFiAvatarSessionCodec.encodeResponse(
            WiFiAvatarSessionResponse(
                command: .open,
                operationID: 1,
                status: .ok,
                credentials: credentials
            )
        )
        let decoded = try WiFiAvatarSessionCodec.decodeResponse(encoded)
        #expect(decoded.credentials?.ssid == "Café-Net")
        #expect(decoded.credentials?.passphrase == "pä$$w\u{2019}rd")
    }

    @Test("Empty response is rejected")
    func emptyResponseRejected() {
        #expect(throws: WiFiAvatarSessionCodecError.emptyResponse) {
            try WiFiAvatarSessionCodec.decodeResponse(Data())
        }
    }

    @Test("Unknown status byte is rejected")
    func unknownStatusRejected() {
        #expect(throws: WiFiAvatarSessionCodecError.invalidStatus(0x7A)) {
            try WiFiAvatarSessionCodec.decodeResponse(Data([0x01, 0x00, 0x00, 0x00, 0x01, 0x7A]))
        }
    }

    @Test("Truncated response is rejected")
    func truncatedResponseRejected() {
        // Command 后缺 OperationID / Status 及其余字段。
        #expect(throws: (any Error).self) {
            try WiFiAvatarSessionCodec.decodeResponse(Data([0x01]))
        }
    }

    @Test("Trailing bytes after a well-formed response are rejected")
    func trailingBytesRejected() throws {
        let valid = WiFiAvatarSessionCodec.encodeResponse(
            WiFiAvatarSessionResponse(
                command: .query,
                operationID: 1,
                status: .unsupported,
                credentials: nil
            )
        )
        let withTail = valid + Data([0xFF])
        #expect(throws: WiFiAvatarSessionCodecError.trailingBytes(1)) {
            try WiFiAvatarSessionCodec.decodeResponse(withTail)
        }
    }

    @Test("Field length prefix exceeding the max is rejected")
    func fieldTooLongRejected() {
        // Command + OperationID + Status OK 后，SSID 长度 200（> 32）。
        #expect(throws: WiFiAvatarSessionCodecError.fieldTooLong(field: "ssid", length: 200, max: 32)) {
            try WiFiAvatarSessionCodec.decodeResponse(Data([0x01, 0, 0, 0, 1, 0x00, 200]))
        }
    }

    @Test("HTTP contract helpers format hex and bearer correctly")
    func httpContractHelpers() {
        #expect(WiFiAvatarHTTPContract.hex(0x0000_00FF) == "000000ff")
        #expect(WiFiAvatarHTTPContract.hex(0xDEAD_BEEF) == "deadbeef")
        #expect(WiFiAvatarHTTPContract.bearer("tok_1") == "Bearer tok_1")
    }
}
