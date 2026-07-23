import CryptoKit
import Foundation
import Testing
@testable import KiroleFeature

@MainActor
private final class AvatarResultBox {
    var value: AvatarControlResult?
}

@Suite("BLE Avatar Protocol v2.7")
struct BLEAvatarProtocolV27Tests {
    private let operationID: UInt32 = 0x1020_3040
    private let avatarID = UUID(uuidString: "00112233-4455-6677-8899-AABBCCDDEEFF")!

    @Test("0x15 v4 encodes operation, UUID, length, CRC and KRI bytes")
    func customAvatarV4RoundTrip() throws {
        let kriData = try makeKRI(width: 2, height: 2)

        let payload = try BLEDataEncoder.encodeCustomAvatarFrame(
            operationID: operationID,
            avatarID: avatarID,
            kriData: kriData
        )

        #expect(payload[0] == 0x04)
        #expect(payload.bigEndianUInt32(at: 1) == operationID)
        #expect(payload.subdata(in: 5..<21) == uuidBytes(avatarID))
        #expect(payload.bigEndianUInt32(at: 21) == UInt32(kriData.count))
        #expect(payload.bigEndianUInt32(at: 25) == CRC32.ieee(kriData))
        #expect(Data(payload.dropFirst(CustomAvatarFrameV4Codec.headerLength)) == kriData)

        let decoded = try CustomAvatarFrameV4Codec.decode(payload)
        #expect(decoded.operationID == operationID)
        #expect(decoded.avatarID == avatarID)
        #expect(decoded.fileLength == UInt32(kriData.count))
        #expect(decoded.fileCRC32 == CRC32.ieee(kriData))
        #expect(decoded.kriData == kriData)
    }

    @Test("0x15 v4 rejects old versions, bad length and bad CRC")
    func customAvatarV4StrictValidation() throws {
        let kriData = try makeKRI(width: 2, height: 2)
        let valid = try BLEDataEncoder.encodeCustomAvatarFrame(
            operationID: operationID,
            avatarID: avatarID,
            kriData: kriData
        )

        var oldVersion = valid
        oldVersion[0] = 0x03
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try CustomAvatarFrameV4Codec.decode(oldVersion)
        }

        var badLength = valid
        badLength[24] &+= 1
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try CustomAvatarFrameV4Codec.decode(badLength)
        }

        var badCRC = valid
        badCRC[badCRC.count - 1] ^= 0xFF
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try CustomAvatarFrameV4Codec.decode(badCRC)
        }
    }

    @Test("0x15 v4 encoder rejects bytes that are not a valid KRI file")
    func customAvatarV4RejectsInvalidKRI() {
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try BLEDataEncoder.encodeCustomAvatarFrame(
                operationID: operationID,
                avatarID: avatarID,
                kriData: Data([0x00, 0x01, 0x02])
            )
        }
    }

    @Test("0x15 v4 rejects KRI dimensions outside the 800 by 700 avatar bounds")
    func customAvatarV4RejectsOversizedDimensions() throws {
        for kriData in [
            try makeKRI(width: 801, height: 1),
            try makeKRI(width: 1, height: 701),
        ] {
            #expect(throws: BLEAvatarProtocolError.self) {
                _ = try BLEDataEncoder.encodeCustomAvatarFrame(
                    operationID: operationID,
                    avatarID: avatarID,
                    kriData: kriData
                )
            }
        }
    }

    @Test("0x22 has fixed command encoding for all operations")
    func avatarControlCommandEncoding() throws {
        #expect(BLEDataType.avatarControl.rawValue == 0x22)

        let cases: [(AvatarControlCommand, UInt8, UUID?)] = [
            (.commit(operationID: operationID, avatarID: avatarID), 0x01, avatarID),
            (.eraseExact(operationID: operationID, avatarID: avatarID), 0x02, avatarID),
            (.eraseAll(operationID: operationID), 0x03, nil),
            (.query(operationID: operationID), 0x04, nil),
            (.abort(operationID: operationID), 0x05, nil),
        ]

        for (command, commandByte, expectedAvatarID) in cases {
            let payload = BLEDataEncoder.encodeAvatarControlCommand(command)
            #expect(payload.count == AvatarControlCodec.commandLength)
            #expect(payload[0] == commandByte)
            #expect(payload.bigEndianUInt32(at: 1) == operationID)
            let expectedUUIDBytes = expectedAvatarID.map(uuidBytes) ?? Data(repeating: 0, count: 16)
            #expect(payload.subdata(in: 5..<21) == expectedUUIDBytes)
            #expect(try AvatarControlCodec.decodeCommand(payload) == command)
        }
    }

    @Test("0x22 command decoder rejects unknown commands and illegal UUID fields")
    func avatarControlCommandStrictValidation() {
        var unknown = BLEDataEncoder.encodeAvatarControlCommand(.query(operationID: operationID))
        unknown[0] = 0x7F
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try AvatarControlCodec.decodeCommand(unknown)
        }

        var queryWithAvatar = BLEDataEncoder.encodeAvatarControlCommand(.query(operationID: operationID))
        queryWithAvatar.replaceSubrange(5..<21, with: uuidBytes(avatarID))
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try AvatarControlCodec.decodeCommand(queryWithAvatar)
        }
    }

    @Test("0x22 result strictly decodes inventory identity and metadata")
    func avatarControlResultRoundTrip() throws {
        let result = AvatarControlResult(
            operationID: operationID,
            status: .committed,
            avatarState: .committed,
            customActive: true,
            avatarID: avatarID,
            byteLength: 2_240_012,
            crc32: 0xCBF4_3926
        )

        let payload = AvatarControlCodec.encodeResult(result)
        #expect(payload.count == AvatarControlCodec.resultLength)
        #expect(try AvatarControlCodec.decodeResult(payload) == result)
    }

    @Test("0x22 result rejects trailing bytes, unknown enums and invalid bool")
    func avatarControlResultStrictValidation() {
        let valid = AvatarControlCodec.encodeResult(
            AvatarControlResult(
                operationID: operationID,
                status: .state,
                avatarState: .empty,
                customActive: false,
                avatarID: nil,
                byteLength: 0,
                crc32: 0
            )
        )

        var trailing = valid
        trailing.append(0x00)
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try AvatarControlCodec.decodeResult(trailing)
        }

        var badStatus = valid
        badStatus[4] = 0x7F
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try AvatarControlCodec.decodeResult(badStatus)
        }

        var badState = valid
        badState[5] = 0x7F
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try AvatarControlCodec.decodeResult(badState)
        }

        var badBool = valid
        badBool[6] = 0x02
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try AvatarControlCodec.decodeResult(badBool)
        }

        var inconsistentEmpty = valid
        inconsistentEmpty[6] = 0x01
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try AvatarControlCodec.decodeResult(inconsistentEmpty)
        }

        var inconsistentStatus = valid
        inconsistentStatus[4] = AvatarControlStatus.committed.rawValue
        #expect(throws: BLEAvatarProtocolError.self) {
            _ = try AvatarControlCodec.decodeResult(inconsistentStatus)
        }
    }

    @Test("0x22 is routed to BLEService callback before EventLog parsing")
    @MainActor
    func avatarControlInboundCallback() async {
        let expected = AvatarControlResult(
            operationID: operationID,
            status: .staged,
            avatarState: .staged,
            customActive: false,
            avatarID: avatarID,
            byteLength: 128,
            crc32: 0x1020_3040
        )
        let received = AvatarResultBox()
        BLEService.shared.onAvatarControlResult = { received.value = $0 }
        defer { BLEService.shared.onAvatarControlResult = nil }

        await BLEEventHandler.handleReceivedPayload(
            BLEReceivedMessage(
                type: BLEDataType.avatarControl.rawValue,
                payload: AvatarControlCodec.encodeResult(expected)
            ),
            service: .shared
        )

        #expect(received.value == expected)
    }

    @Test("Secure avatar transport signs each already-packetized 0x15 chunk")
    @MainActor
    func secureAvatarChunksStayWithinNegotiatedWriteLength() throws {
        configureSecret()
        defer { resetSecret() }

        let manager = BLESecurityManager()
        try establishSession(manager)
        let kriData = try makeKRI(width: 20, height: 20)
        let payload = try BLEDataEncoder.encodeCustomAvatarFrame(
            operationID: operationID,
            avatarID: avatarID,
            kriData: kriData
        )

        let plainPackets = try manager.packetizeForSecureTransport(
            type: BLEDataType.customAvatarFrame.rawValue,
            messageId: 0x5150,
            payload: payload,
            maxWriteLength: 185
        )

        #expect(plainPackets.count > 1)

        var reassembler = SimulatedFirmwareChunkReassembler()
        var reconstructed: Data?
        for plainPacket in plainPackets {
            // Production mirrors this loop: signing happens immediately before each write,
            // so a multi-minute transfer never reuses a stale batch timestamp.
            let packet = try manager.secureChunkPacket(
                type: BLEDataType.customAvatarFrame.rawValue,
                plainPacket: plainPacket,
                maxWriteLength: 185
            )
            #expect(packet.count <= 185)
            #expect(packet.first == BLEDataType.secureData.rawValue)
            let envelopeData = packet.subdata(in: 3..<packet.count)
            let opened = try manager.openSecurePayload(envelopeData)
            #expect(opened.type == BLEDataType.customAvatarFrame.rawValue)
            if let complete = try reassembler.receive(opened.payload) {
                reconstructed = complete
            }
        }
        #expect(reconstructed == payload)
    }

    @Test("Worst-case 800×700 KRI fits every negotiated secure write")
    @MainActor
    func worstCaseSecureAvatarChunksStayWithinNegotiatedWriteLength() throws {
        configureSecret()
        defer { resetSecret() }

        let manager = BLESecurityManager()
        try establishSession(manager)
        let kriData = try KRIEncoder.encode(
            width: 800,
            height: 700,
            straightRGBA: [UInt8](repeating: 0x7F, count: 800 * 700 * 4)
        )
        let payload = try BLEDataEncoder.encodeCustomAvatarFrame(
            operationID: operationID,
            avatarID: avatarID,
            kriData: kriData
        )
        let maxWriteLength = 512
        let plainPackets = try manager.packetizeForSecureTransport(
            type: BLEDataType.customAvatarFrame.rawValue,
            messageId: 0x5151,
            payload: payload,
            maxWriteLength: maxWriteLength
        )

        // 512 - 3B outer frame - 48B envelope - 11B chunk header = 450B/file chunk.
        #expect(plainPackets.count == 4_978)
        for plainPacket in plainPackets {
            let wirePacket = try manager.secureChunkPacket(
                type: BLEDataType.customAvatarFrame.rawValue,
                plainPacket: plainPacket,
                maxWriteLength: maxWriteLength
            )
            #expect(wirePacket.count <= maxWriteLength)
            #expect(wirePacket.first == BLEDataType.secureData.rawValue)
            let envelope = try BLESecureEnvelope.decode(wirePacket.subdata(in: 3..<wirePacket.count))
            #expect(envelope.payloadType == BLEDataType.customAvatarFrame.rawValue)
            #expect(envelope.payload == plainPacket)
        }
    }

    private func makeKRI(width: Int, height: Int) throws -> Data {
        let bytes = (0..<(width * height * 4)).map { UInt8($0 % 251) }
        return try KRIEncoder.encode(width: width, height: height, straightRGBA: bytes)
    }

    private func uuidBytes(_ id: UUID) -> Data {
        var value = id.uuid
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    @MainActor
    private func establishSession(_ manager: BLESecurityManager) throws {
        let request = try manager.makeHandshakeRequestPayload()
        let clientNonce = request.subdata(in: 1..<9)
        let serverNonce = Data(repeating: 0x61, count: 8)
        let issuedAt = UInt32(Date().timeIntervalSince1970)

        var response = Data([0x02])
        response.append(clientNonce)
        response.append(serverNonce)
        response.appendBigEndian(issuedAt)
        let key = SymmetricKey(data: Data(Self.sharedSecret.utf8))
        response.append(Data(HMAC<SHA256>.authenticationCode(for: response, using: key)))
        try manager.validateHandshakeResponsePayload(response)
    }

    private static let sharedSecret = "kirole-ble-avatar-v27-test-secret"

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
}
