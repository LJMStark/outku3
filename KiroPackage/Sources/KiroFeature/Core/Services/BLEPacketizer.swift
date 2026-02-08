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

// MARK: - BLE Packetizer

public enum BLEPacketizer {
    public static let headerSize: Int = 9

    public static func packetize(
        type: UInt8,
        messageId: UInt16,
        payload: Data,
        maxChunkSize: Int
    ) throws -> [Data] {
        guard maxChunkSize > 0 else {
            throw BLEPacketError.invalidChunkSize
        }

        guard payload.count <= Int(UInt16.max) else {
            throw BLEPacketError.payloadTooLarge
        }
        let payloadLength = UInt16(payload.count)
        let crc = CRC16.ccittFalse(payload)

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

            var packet = Data()
            packet.append(type)
            packet.append(contentsOf: withUnsafeBytes(of: messageId.bigEndian) { Array($0) })
            packet.append(UInt8(index))
            packet.append(UInt8(totalChunks))
            packet.append(contentsOf: withUnsafeBytes(of: payloadLength.bigEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: crc.bigEndian) { Array($0) })
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
        let payloadLength: UInt16
        let crc: UInt16
        var chunks: [Int: Data]

        init(type: UInt8, total: UInt8, payloadLength: UInt16, crc: UInt16) {
            self.type = type
            self.total = total
            self.payloadLength = payloadLength
            self.crc = crc
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
        let payloadLength = UInt16(packetData[5]) << 8 | UInt16(packetData[6])
        let crc = UInt16(packetData[7]) << 8 | UInt16(packetData[8])

        guard total > 0, seq >= 0, seq < Int(total) else { return nil }

        let chunk = packetData.subdata(in: BLEPacketizer.headerSize..<packetData.count)

        if messages[messageId] == nil {
            messages[messageId] = Assembly(type: type, total: total, payloadLength: payloadLength, crc: crc)
        }

        guard var assembly = messages[messageId], assembly.total == total else { return nil }

        assembly.chunks[seq] = chunk
        messages[messageId] = assembly

        guard assembly.chunks.count == Int(total) else { return nil }

        var payload = Data()
        payload.reserveCapacity(Int(payloadLength))
        for index in 0..<Int(total) {
            guard let part = assembly.chunks[index] else { return nil }
            payload.append(part)
        }

        guard payload.count == Int(payloadLength) else {
            messages.removeValue(forKey: messageId)
            return nil
        }

        let computedCrc = CRC16.ccittFalse(payload)
        guard computedCrc == crc else {
            messages.removeValue(forKey: messageId)
            return nil
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
