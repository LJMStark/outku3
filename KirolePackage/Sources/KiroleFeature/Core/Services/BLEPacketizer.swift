import Foundation

// MARK: - BLE Packet

public struct BLEReceivedMessage: Sendable {
    public let type: UInt8
    public let payload: Data

    public init(type: UInt8, payload: Data) {
        self.type = type
        self.payload = payload
    }
}

// MARK: - BLE Simple Packet Encoder (Hardware Spec v1.1.0)

/// Encodes packets using the hardware spec format: type(1) | length(2 BE) | payload(N)
public enum BLESimpleEncoder {
    /// Encode a payload with 3-byte header for App->Device communication
    public static func encode(type: UInt8, payload: Data) -> Data {
        var packet = Data()
        packet.append(type)
        packet.appendBigEndian(UInt16(payload.count))
        packet.append(payload)
        return packet
    }
}

// MARK: - BLE Simple Packet Decoder (Hardware Spec v1.1.0)

/// Decodes packets from device using format: type(1) | length(1) | payload(N)
public enum BLESimpleDecoder {
    /// Decode a Device->App packet with 2-byte header
    public static func decode(_ data: Data) -> BLEReceivedMessage? {
        guard data.count >= 2 else { return nil }
        let type = data[0]
        let length = Int(data[1])
        let expectedTotal = 2 + length
        guard data.count == expectedTotal else { return nil }
        let payload = length > 0 ? data.subdata(in: 2..<expectedTotal) : Data()
        return BLEReceivedMessage(type: type, payload: payload)
    }
}

// MARK: - BLE Packetizer

public enum BLEPacketizer {
    public static let headerSize: Int = 9

    /// Default MTU payload size for BLE 4.2 (20 bytes ATT payload - 3 bytes ATT header = 17 usable)
    /// BLE 5.0 supports negotiated MTU up to 512 bytes; use negotiated value when available.
    public static let defaultMTUPayload: Int = 17

    /// Estimated chunk counts for Spectra 6 frame buffers at default MTU:
    /// - 4寸 (120,000 bytes): ~7,059 packets
    /// - 7.3寸 (192,000 bytes): ~11,294 packets
    /// With negotiated BLE 5.0 MTU (e.g., 512 - 3 = 509 bytes): ~236 / ~377 packets

    public static func packetize(
        type: UInt8,
        messageId: UInt16,
        payload: Data,
        maxChunkSize: Int
    ) throws -> [Data] {
        guard maxChunkSize > 0 else {
            throw BLEPacketError.invalidChunkSize
        }

        let totalChunks = Int(ceil(Double(payload.count) / Double(maxChunkSize)))
        guard totalChunks > 0, totalChunks <= 255 else {
            throw BLEPacketError.payloadTooLarge
        }

        var packets: [Data] = []
        packets.reserveCapacity(totalChunks)

        for index in 0..<totalChunks {
            let start = index * maxChunkSize
            let end = min(start + maxChunkSize, payload.count)
            let chunk = payload.subdata(in: start..<end)
            let chunkCRC = CRC16.ccittFalse(chunk)

            var packet = Data()
            packet.append(type)
            packet.appendBigEndian(messageId)
            packet.append(UInt8(index))
            packet.append(UInt8(totalChunks))
            packet.appendBigEndian(UInt16(chunk.count))
            packet.appendBigEndian(chunkCRC)
            packet.append(chunk)

            packets.append(packet)
        }

        return packets
    }
}

// MARK: - BLE Packet Assembler

public final class BLEPacketAssembler {
    private enum Limits {
        static let maxInFlightMessages = 8
        static let maxAssembledPayloadBytes = 256 * 1024
    }

    private struct Assembly {
        let type: UInt8
        let total: UInt8
        var chunks: [Int: Data]
        var byteCount: Int

        init(type: UInt8, total: UInt8) {
            self.type = type
            self.total = total
            self.chunks = [:]
            self.byteCount = 0
        }
    }

    private var messages: [UInt16: Assembly] = [:]
    /// 槽满丢弃日志去重：同一条被拒消息的每个 chunk 都会走到槽满分支，只在 messageId 变化时记一次。
    private var lastDroppedMessageId: UInt16?

    public init() {}

    public func isPotentialChunk(packetData: Data) -> Bool {
        guard packetData.count >= BLEPacketizer.headerSize else { return false }

        let seq = Int(packetData[3])
        let total = Int(packetData[4])
        let chunkLength = packetData.bigEndianUInt16(at: 5)
        let chunkCRC = packetData.bigEndianUInt16(at: 7)
        let chunk = packetData.subdata(in: BLEPacketizer.headerSize..<packetData.count)

        guard total > 1, seq < total, chunk.count == Int(chunkLength) else { return false }
        return CRC16.ccittFalse(chunk) == chunkCRC
    }

    public func append(packetData: Data) -> BLEReceivedMessage? {
        guard packetData.count >= BLEPacketizer.headerSize else { return nil }

        let type = packetData[0]
        let messageId = packetData.bigEndianUInt16(at: 1)
        let seq = Int(packetData[3])
        let total = packetData[4]
        let chunkLength = packetData.bigEndianUInt16(at: 5)
        let chunkCRC = packetData.bigEndianUInt16(at: 7)

        guard total > 0, seq < Int(total) else { return nil }

        let chunk = packetData.subdata(in: BLEPacketizer.headerSize..<packetData.count)
        guard chunk.count == Int(chunkLength) else { return nil }

        let computedChunkCRC = CRC16.ccittFalse(chunk)
        guard computedChunkCRC == chunkCRC else { return nil }

        if messages[messageId] == nil {
            guard messages.count < Limits.maxInFlightMessages else {
                if lastDroppedMessageId != messageId {
                    lastDroppedMessageId = messageId
                    ErrorReporter.log(
                        .sync(
                            component: "BLEPacketAssembler",
                            underlying: "In-flight slots full (\(Limits.maxInFlightMessages)); dropping chunked message type=0x\(String(type, radix: 16)) id=\(messageId)"
                        ),
                        context: "BLEPacketAssembler.append"
                    )
                }
                return nil
            }
            messages[messageId] = Assembly(type: type, total: total)
        }

        guard var assembly = messages[messageId], assembly.total == total, assembly.type == type else { return nil }

        let previousChunkSize = assembly.chunks[seq]?.count ?? 0
        let nextByteCount = assembly.byteCount - previousChunkSize + chunk.count
        guard nextByteCount <= Limits.maxAssembledPayloadBytes else {
            messages.removeValue(forKey: messageId)
            return nil
        }

        assembly.chunks[seq] = chunk
        assembly.byteCount = nextByteCount
        messages[messageId] = assembly

        guard assembly.chunks.count == Int(total) else { return nil }

        var payload = Data()
        for index in 0..<Int(total) {
            guard let part = assembly.chunks[index] else { return nil }
            payload.append(part)
        }

        messages.removeValue(forKey: messageId)
        return BLEReceivedMessage(type: type, payload: payload)
    }
}

// MARK: - BLE Packet Error

public enum BLEPacketError: Error {
    case invalidChunkSize
    case payloadTooLarge
}

// MARK: - Gamify Scene Unlock

extension BLEPacketizer {
    public static func buildSceneUnlockPacket(sceneId: UInt8) -> Data {
        var data = Data()
        data.append(contentsOf: [0xAA, 0x01, 0x01, sceneId])
        return data
    }

    public static func buildScreensaverPacket(config: ScreensaverConfig) -> Data {
        let sceneByte = DisplayScene(rawValue: config.sceneId)?.commandByte ?? DisplayScene.harbor.commandByte
        let postcardDay = UInt8(clamping: config.postcardDay ?? 0)
        let quoteData = Data(config.quote.utf8.prefix(Int(UInt8.max)))
        let authorData = Data(config.author.utf8.prefix(Int(UInt8.max)))
        var data = Data()
        data.append(0xAA)
        data.append(0x01)
        data.append(0x02)
        data.append(config.type == .postcard ? 0x01 : 0x00)
        data.append(sceneByte)
        data.append(postcardDay)
        data.append(UInt8(quoteData.count))
        data.append(quoteData)
        data.append(UInt8(authorData.count))
        data.append(authorData)
        return data
    }
}
