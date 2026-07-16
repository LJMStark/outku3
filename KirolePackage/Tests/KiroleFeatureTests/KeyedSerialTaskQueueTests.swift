import Testing
@testable import KiroleFeature

private actor SerialQueueRecorder {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

private actor SerialQueueGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

@MainActor
@Suite("Keyed Serial Task Queue")
struct KeyedSerialTaskQueueTests {
    @Test("Operations for the same key complete in submission order")
    func sameKeyRunsInOrder() async {
        let queue = KeyedSerialTaskQueue<String>()
        let recorder = SerialQueueRecorder()
        let gate = SerialQueueGate()

        let first = queue.enqueue(for: "task") {
            await recorder.append("first-start")
            await gate.wait()
            await recorder.append("first-end")
        }
        let second = queue.enqueue(for: "task") {
            await recorder.append("second")
        }

        for _ in 0..<100 {
            if !(await recorder.snapshot()).isEmpty { break }
            await Task.yield()
        }
        #expect(await recorder.snapshot() == ["first-start"])

        await gate.open()
        await first.value
        await second.value

        #expect(await recorder.snapshot() == ["first-start", "first-end", "second"])
    }

    @Test("run serializes the same key and returns each operation's value")
    func runSerializesSameKeyAndReturnsValue() async throws {
        let queue = KeyedSerialTaskQueue<String>()
        let recorder = SerialQueueRecorder()
        let gate = SerialQueueGate()

        let first = Task { @MainActor in
            try await queue.run(for: "cred") { () async throws -> String in
                await recorder.append("first-start")
                await gate.wait()
                await recorder.append("first-end")
                return "first"
            }
        }

        // 等首个操作确定已注册并卡在 gate 上，再提交第二个，保证提交顺序确定。
        for _ in 0..<100 {
            if !(await recorder.snapshot()).isEmpty { break }
            await Task.yield()
        }
        #expect(await recorder.snapshot() == ["first-start"])

        let second = Task { @MainActor in
            try await queue.run(for: "cred") { () async throws -> String in
                await recorder.append("second")
                return "second"
            }
        }

        // 首个仍被 gate 卡住时，第二个不得进入执行——这是互斥语义本身。
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(await recorder.snapshot() == ["first-start"])

        await gate.open()
        #expect(try await first.value == "first")
        #expect(try await second.value == "second")
        #expect(await recorder.snapshot() == ["first-start", "first-end", "second"])
    }

    @Test("A throwing run does not block the next operation on the same key")
    func throwingRunDoesNotBlockNextOperation() async throws {
        let queue = KeyedSerialTaskQueue<String>()
        struct TestFailure: Error {}

        await #expect(throws: TestFailure.self) {
            try await queue.run(for: "cred") { () async throws -> String in
                throw TestFailure()
            }
        }

        let value = try await queue.run(for: "cred") { "second" }
        #expect(value == "second")
    }

    @Test("Cancelling a queued run's caller skips the operation and frees the queue")
    func cancellingCallerSkipsQueuedOperationAndFreesQueue() async throws {
        let queue = KeyedSerialTaskQueue<String>()
        let recorder = SerialQueueRecorder()
        let gate = SerialQueueGate()

        let first = Task { @MainActor in
            try await queue.run(for: "cred") { () async throws -> String in
                await recorder.append("first-start")
                await gate.wait()
                return "first"
            }
        }
        for _ in 0..<100 {
            if !(await recorder.snapshot()).isEmpty { break }
            await Task.yield()
        }

        // 第二个操作排在被 gate 卡住的首个后面、尚未起跑时取消其调用方。
        let second = Task { @MainActor in
            try await queue.run(for: "cred") { () async throws -> String in
                await recorder.append("second")
                return "second"
            }
        }
        for _ in 0..<20 { await Task.yield() }
        second.cancel()

        await gate.open()
        #expect(try await first.value == "first")
        await #expect(throws: CancellationError.self) {
            try await second.value
        }

        // 被取消的操作从未执行，且不阻塞同 key 后续操作。
        let third = try await queue.run(for: "cred") { "third" }
        #expect(third == "third")
        #expect(await recorder.snapshot() == ["first-start"])
    }
}
