import Foundation

actor BLEWriteGate {
    private var isWriting = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isWriting else {
            isWriting = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard let nextWaiter = waiters.first else {
            isWriting = false
            return
        }

        waiters.removeFirst()
        nextWaiter.resume()
    }
}
