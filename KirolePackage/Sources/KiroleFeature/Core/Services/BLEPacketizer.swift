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
    /// Seq/Total 各为 2B BE，分包总数上限 65535，可承载 v2.7 CustomAvatarFrame。
    public static let headerSize: Int = 11

    /// Estimated chunk counts with negotiated BLE 5.0 MTU (512 - 11B header = 501 bytes/chunk):
    /// - Worst-case avatar v4 (2,240,041 bytes incl. metadata): ~4,472 packets
    /// - Spectra 6 frame buffers: 4寸 120,000 bytes ≈ 240 / 7.3寸 192,000 bytes ≈ 384 packets
    /// All far below the 65,535-chunk ceiling; tiny MTUs shrink per-chunk payload and can
    /// still overflow the ceiling for MiB-scale payloads — packetize then throws payloadTooLarge.

    public static func packetize(
        type: UInt8,
        messageId: UInt16,
        payload: Data,
        maxChunkSize: Int
    ) throws -> [Data] {
        guard maxChunkSize > 0 else {
            throw BLEPacketError.invalidChunkSize
        }
        // PayloadLen 字段是 2B：把片长钳到 65535，防止调用方传超大 maxChunkSize 时
        // `UInt16(chunk.count)` trap（现实 MTU ≤512，此钳位纯防御）。
        let effectiveChunkSize = min(maxChunkSize, Int(UInt16.max))

        let totalChunks = Int(ceil(Double(payload.count) / Double(effectiveChunkSize)))
        guard totalChunks > 0, totalChunks <= 65535 else {
            throw BLEPacketError.payloadTooLarge
        }

        var packets: [Data] = []
        packets.reserveCapacity(totalChunks)

        for index in 0..<totalChunks {
            let start = index * effectiveChunkSize
            let end = min(start + effectiveChunkSize, payload.count)
            let chunk = payload.subdata(in: start..<end)
            let chunkCRC = CRC16.ccittFalse(chunk)

            var packet = Data()
            packet.append(type)
            packet.appendBigEndian(messageId)
            packet.appendBigEndian(UInt16(index))
            packet.appendBigEndian(UInt16(totalChunks))
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
        // 协议未规定 App 入站重组 idle 超时。取 5 分钟；入站受 256KiB 帽限制，
        // 不承载流式写入设备的 0x15 出站头像。只有连续 5 分钟没有
        // 有效分片才驱逐，既照顾慢链路，也避免缺片消息永久占槽。
        static let assemblyIdleTimeout: TimeInterval = 5 * 60
        static let droppedMessageRetention: TimeInterval = assemblyIdleTimeout
        static let maxDroppedMessageIds = maxInFlightMessages * 8
    }

    private struct Assembly {
        let type: UInt8
        let total: UInt16
        var chunks: [Int: Data]
        var byteCount: Int
        var lastUpdatedAt: Date

        init(type: UInt8, total: UInt16, now: Date) {
            self.type = type
            self.total = total
            self.chunks = [:]
            self.byteCount = 0
            self.lastUpdatedAt = now
        }
    }

    private var messages: [UInt16: Assembly] = [:]
    // 超时/超限/槽满后暂存 tombstone，挡住迟到的 seq>0 尾片重新占槽；seq=0
    // 仍可明确开始重传。到期清理且最多保留 64 个，避免集合随坏消息持续增长。
    private var droppedMessageIds: [UInt16: Date] = [:]
    /// 槽满丢弃日志去重：同一条被拒消息的每个 chunk 都会走到槽满分支，只在 messageId 变化时记一次。
    private var lastDroppedMessageId: UInt16?

    public init() {}

    /// 11B 分包头解析（§3.2）。字段/偏移的唯一生产真源——isPotentialChunk 与 append
    /// 共用，避免 9B→11B 这类头变更再出现两处偏移各改各的漂移。
    /// 校验：长度 ≥ 头部、`chunk.count == PayloadLen`、逐片 CRC、
    /// 以及 **PayloadLen > 0**——packetize 永不产生空片（空 payload 直接抛错），
    /// 零长度片只可能是坏包或恶意填充 65535 个空片撑爆重组字典（256KiB 帽只数
    /// payload 字节、数不到字典项），一律拒收。
    private struct ChunkHeader {
        let type: UInt8
        let messageId: UInt16
        let seq: Int
        let total: UInt16
        let chunk: Data
    }

    private func parseChunk(_ packetData: Data) -> ChunkHeader? {
        // 本解析器（与 bigEndianUInt16(at:)）按绝对下标读：只对 zero-based Data 正确。
        // 现有调用方（characteristic.value / packetize 输出）都满足；传入非零 startIndex
        // 的切片会静默读错字节，故 debug 期直接断言拦截。
        assert(packetData.startIndex == 0, "BLEPacketAssembler requires zero-based Data (got startIndex \(packetData.startIndex))")
        guard packetData.count >= BLEPacketizer.headerSize else { return nil }

        let seq = Int(packetData.bigEndianUInt16(at: 3))
        let total = packetData.bigEndianUInt16(at: 5)
        let chunkLength = packetData.bigEndianUInt16(at: 7)
        let chunkCRC = packetData.bigEndianUInt16(at: 9)

        guard chunkLength > 0, total > 0, seq < Int(total) else { return nil }

        let chunk = packetData.subdata(in: BLEPacketizer.headerSize..<packetData.count)
        guard chunk.count == Int(chunkLength), CRC16.ccittFalse(chunk) == chunkCRC else { return nil }

        return ChunkHeader(
            type: packetData[0],
            messageId: packetData.bigEndianUInt16(at: 1),
            seq: seq,
            total: total,
            chunk: chunk
        )
    }

    public func isPotentialChunk(packetData: Data) -> Bool {
        guard let header = parseChunk(packetData) else { return false }
        return header.total > 1
    }

    private func markMessageDropped(_ messageId: UInt16, now: Date) {
        let expiresAt = now.addingTimeInterval(Limits.droppedMessageRetention)
        droppedMessageIds[messageId] = expiresAt

        guard droppedMessageIds.count > Limits.maxDroppedMessageIds,
              let oldest = droppedMessageIds.min(by: { $0.value < $1.value })?.key else {
            return
        }
        droppedMessageIds.removeValue(forKey: oldest)
    }

    private func evictExpiredState(now: Date) {
        droppedMessageIds = droppedMessageIds.filter { $0.value > now }

        let expiredMessageIds = messages.compactMap { entry -> UInt16? in
            let idleTime = now.timeIntervalSince(entry.value.lastUpdatedAt)
            return idleTime >= Limits.assemblyIdleTimeout ? entry.key : nil
        }
        for messageId in expiredMessageIds {
            messages.removeValue(forKey: messageId)
            markMessageDropped(messageId, now: now)
        }
    }

    public func append(packetData: Data, now: Date = Date()) -> BLEReceivedMessage? {
        guard let header = parseChunk(packetData) else { return nil }
        evictExpiredState(now: now)

        let type = header.type
        let messageId = header.messageId
        let seq = header.seq
        let total = header.total
        let chunk = header.chunk

        if seq == 0 {
            droppedMessageIds.removeValue(forKey: messageId)
            // Sequence zero is the protocol's explicit restart marker. Reusing an in-flight id
            // without clearing it can splice a new head to old tail chunks and emit corrupt data.
            messages.removeValue(forKey: messageId)
        } else if droppedMessageIds[messageId] != nil {
            return nil
        }

        if messages[messageId] == nil {
            guard messages.count < Limits.maxInFlightMessages else {
                markMessageDropped(messageId, now: now)
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
            messages[messageId] = Assembly(type: type, total: total, now: now)
        }

        guard var assembly = messages[messageId], assembly.total == total, assembly.type == type else { return nil }

        let previousChunkSize = assembly.chunks[seq]?.count ?? 0
        let nextByteCount = assembly.byteCount - previousChunkSize + chunk.count
        guard nextByteCount <= Limits.maxAssembledPayloadBytes else {
            messages.removeValue(forKey: messageId)
            markMessageDropped(messageId, now: now)
            return nil
        }

        assembly.chunks[seq] = chunk
        assembly.byteCount = nextByteCount
        assembly.lastUpdatedAt = max(assembly.lastUpdatedAt, now)
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
//
// 旧 `0xAA` 开发显示命令构造器（`buildSceneUnlockPacket` / `buildScreensaverPacket`）已全部移除。
// 场景解锁 = `0x17`（`BLEDataEncoder.encodeSceneUnlock`）、屏保 = `0x16`（`encodeScreensaver`），
// 均改走 `writeData` 业务帧（v2.5.10 屏保 / v2.5.11 场景解锁，secure 可发）。
// App 出站不再产生任何 `0xAA` 命令。
