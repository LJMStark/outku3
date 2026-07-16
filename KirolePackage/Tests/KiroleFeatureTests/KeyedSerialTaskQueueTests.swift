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
}
