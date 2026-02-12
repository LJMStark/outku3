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
        let length = UInt16(payload.count)
        packet.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })
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
        guard data.count >= expectedTotal else { return nil }
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
            let chunkLength = UInt16(chunk.count)
            let chunkCRC = CRC16.ccittFalse(chunk)

            var packet = Data()
            packet.append(type)
            packet.append(contentsOf: withUnsafeBytes(of: messageId.bigEndian) { Array($0) })
            packet.append(UInt8(index))
            packet.append(UInt8(totalChunks))
            packet.append(contentsOf: withUnsafeBytes(of: chunkLength.bigEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: chunkCRC.bigEndian) { Array($0) })
            packet.append(chunk)

            packets.append(packet)
        }

        return packets
    }
}

// MARK: - BLE Packet Assembler

public final class BLEPacketAssembler {
    private struct Assembly {
        let type: UInt8
        let total: UInt8
        var chunks: [Int: Data]

        init(type: UInt8, total: UInt8) {
            self.type = type
            self.total = total
            self.chunks = [:]
        }
    }

    private var messages: [UInt16: Assembly] = [:]

    public init() {}

    public func append(packetData: Data) -> BLEReceivedMessage? {
        guard packetData.count >= BLEPacketizer.headerSize else { return nil }

        let type = packetData[0]
        let messageId = UInt16(packetData[1]) << 8 | UInt16(packetData[2])
        let seq = Int(packetData[3])
        let total = packetData[4]
        let chunkLength = UInt16(packetData[5]) << 8 | UInt16(packetData[6])
        let chunkCRC = UInt16(packetData[7]) << 8 | UInt16(packetData[8])

        guard total > 0, seq < Int(total) else { return nil }

        let chunk = packetData.subdata(in: BLEPacketizer.headerSize..<packetData.count)
        guard chunk.count == Int(chunkLength) else { return nil }

        let computedChunkCRC = CRC16.ccittFalse(chunk)
        guard computedChunkCRC == chunkCRC else { return nil }

        if messages[messageId] == nil {
            messages[messageId] = Assembly(type: type, total: total)
        }

        guard var assembly = messages[messageId], assembly.total == total, assembly.type == type else { return nil }

        assembly.chunks[seq] = chunk
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
