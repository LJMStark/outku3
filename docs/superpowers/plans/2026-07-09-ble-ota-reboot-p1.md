# BLE OTA Reboot — Part 1 (Protocol + Coordinator + BLEService)

> **续 Part 2:** `2026-07-09-ble-ota-reboot-p2.md` 包含 BLEEventHandler + UI + 验证。

**Goal:** 实现 `0x18 OTAReboot`/`OTAResult` 协议层、`BLEOTACoordinator` 状态机、`BLEService` 集成。

**Architecture:** 新 `BLEOTACoordinator` 单例（照 `BLESyncCoordinator` 形状）管理状态机。`BLEService` 添加 `sendOTAReboot()` 和 `isPendingOTAReboot` 标记，在 `didDisconnectPeripheral` 里通知协调器。

**Tech Stack:** Swift 6.1, Swift Testing, `KiroleFeature` package.

## Global Constraints

- Swift Testing only: `import Testing`, `@Test`, `#expect`. No XCTest.
- English-only UI strings.
- 每个 task 完成后 `cd KirolePackage && swift build` 确认无编译错误再 commit。
- 每次 commit 前先标对应 task 为 completed。

---

### Task 1: Protocol layer — byte definitions + EventLog parsing

**Files:**
- Modify: `KirolePackage/Sources/KiroleFeature/Core/BLE/BLEProtocol.swift`
- Modify: `KirolePackage/Sources/KiroleFeature/Models/EventLog.swift`
- Modify: `KirolePackage/Sources/KiroleFeature/Core/Services/BLEEventHandler.swift`
- Test: `KirolePackage/Tests/KiroleFeatureTests/BLEProtocolTests.swift`

**Interfaces produced:**
- `BLEDataType.otaReboot` = `0x18`
- `EventLogType.otaResult` raw string `"ota_result"`, `rawByte` `0x18`
- `EventLog.fromBLEPayload(type: 0x18, payload: Data([code]))` → `.otaResult`, `value = Int(code)`

- [ ] **Step 1.1: 在 BLEProtocolTests.swift 末尾追加 5 个测试**

```swift
@Test("OTAReboot byte value is 0x18")
func otaRebootByteValue() {
    #expect(BLEDataType.otaReboot.rawValue == 0x18)
}

@Test("OTAResult rawByte is 0x18")
func otaResultRawByte() {
    #expect(EventLogType.otaResult.rawByte == 0x18)
}

@Test("OTAResult round-trips through rawByte init")
func otaResultRawByteInit() {
    #expect(EventLogType(rawByte: 0x18) == .otaResult)
}

@Test("OTAResult parses 1-byte status code from payload")
func otaResultParsesStatusCode() {
    let log = EventLog.fromBLEPayload(type: 0x18, payload: Data([0x01]))
    #expect(log?.eventType == .otaResult)
    #expect(log?.value == 1)
}

@Test("OTAResult falls back to 0xFF on empty payload")
func otaResultEmptyPayloadFallback() {
    let log = EventLog.fromBLEPayload(type: 0x18, payload: Data())
    #expect(log?.value == 0xFF)
}
```

- [ ] **Step 1.2: 运行确认失败**

```bash
cd KirolePackage && swift test --filter "BLEProtocolTests/otaRebootByteValue" 2>&1 | tail -5
```

Expected: 编译错误 `type 'BLEDataType' has no member 'otaReboot'`

- [ ] **Step 1.3: 在 BLEProtocol.swift 添加 otaReboot**

在 `case sceneUnlock = 0x17` 之后加：

```swift
    /// App→Device: 触发固件升级重启（零 payload），见协议文档 §4.17
    case otaReboot = 0x18
```

同时在文件顶部注释块的 `0x17 sceneUnlock` 行之后加：
```
//   0x18 otaReboot     触发固件升级重启（零 payload；固件校验包后应答并重启）
```

- [ ] **Step 1.4: 在 EventLog.swift 添加 otaResult**

**①** 在 `EventLogType` enum 的 `case reminderDismissed` 之后加：
```swift
    /// 固件升级重启应答（0x00=成功 / 0x01=无文件 / 0x02=大小异常 / 0x03=SD卡 / 0x04=写入失败 / 0xFF=未知）
    case otaResult = "ota_result"
```

**②** 在 `rawByte` computed property 加（紧接 `reminderDismissed` 的 case）：
```swift
        case .otaResult: return 0x18
```

**③** 在 `init?(rawByte:)` 加：
```swift
        case 0x18: self = .otaResult
```

**④** 在 `fromBLEPayload(type:payload:)` 的 switch 里加：
```swift
        case .otaResult:
            let code = payload.isEmpty ? 0xFF : payload[0]
            return EventLog(eventType: eventType, value: Int(code))
```

- [ ] **Step 1.5: 在 BLEEventHandler.swift 的 recordLength 中覆盖 0x18**

找到 `case 0x40:` 这一行（LowBattery，2 字节：type + 1B 电量），改成：
```swift
        case 0x18, 0x40:
            return 2
```

- [ ] **Step 1.6: 运行 5 个测试确认全部 PASS**

```bash
cd KirolePackage && swift test --filter "BLEProtocolTests/otaR" 2>&1 | tail -15
```

- [ ] **Step 1.7: 全量构建确认无报错**

```bash
cd KirolePackage && swift build 2>&1 | tail -5
```

- [ ] **Step 1.8: Commit**

```bash
git add KirolePackage/Sources/KiroleFeature/Core/BLE/BLEProtocol.swift \
        KirolePackage/Sources/KiroleFeature/Models/EventLog.swift \
        KirolePackage/Sources/KiroleFeature/Core/Services/BLEEventHandler.swift \
        KirolePackage/Tests/KiroleFeatureTests/BLEProtocolTests.swift
git commit -m "feat(ble): add OTAReboot(0x18)/OTAResult(0x18) protocol definitions"
```

---

### Task 2: BLEOTACoordinator — 状态机

**Files:**
- Create: `KirolePackage/Sources/KiroleFeature/Core/Services/BLEOTACoordinator.swift`
- Create: `KirolePackage/Tests/KiroleFeatureTests/BLEOTACoordinatorTests.swift`

**Interfaces produced:**
- `BLEOTACoordinator.shared`, `BLEOTACoordinator.makeForTesting()`
- `BLEOTACoordinator.state: State` (@Observable)
- `State`: `.idle / .sending / .awaitingReboot / .failed(Failure)`
- `Failure`: `.deviceRejected(UInt8) / .noResponse / .timedOutWaitingForReboot`
- `requestReboot() async`, `handleOTAResult(statusCode:)`, `handleExpectedDisconnect()`, `handleDeviceWake()`, `reset()`

- [ ] **Step 2.1: 创建测试文件**

创建 `KirolePackage/Tests/KiroleFeatureTests/BLEOTACoordinatorTests.swift`：

```swift
import Testing
import Foundation
@testable import KiroleFeature

@MainActor
@Suite("BLEOTACoordinator state machine")
struct BLEOTACoordinatorTests {

    @Test("Initial state is idle")
    func initialStateIsIdle() async {
        let c = BLEOTACoordinator.makeForTesting()
        #expect(c.state == .idle)
    }

    @Test("0x00 response → awaitingReboot")
    func successResponseEntersAwaitingReboot() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        #expect(c.state == .awaitingReboot)
    }

    @Test("Non-zero response → failed(deviceRejected)")
    func errorResponseFails() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x01)
        #expect(c.state == .failed(.deviceRejected(0x01)))
    }

    @Test("Disconnect during sending → awaitingReboot")
    func disconnectDuringSendingEntersAwaitingReboot() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleExpectedDisconnect()
        #expect(c.state == .awaitingReboot)
    }

    @Test("DeviceWake during awaitingReboot → idle")
    func deviceWakeCompletesUpgrade() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        c.handleDeviceWake()
        #expect(c.state == .idle)
    }

    @Test("reset() returns to idle from awaitingReboot")
    func resetFromAwaitingReboot() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        c.reset()
        #expect(c.state == .idle)
    }

    @Test("handleDeviceWake is no-op when idle")
    func deviceWakeIgnoredWhenIdle() async {
        let c = BLEOTACoordinator.makeForTesting()
        c.handleDeviceWake()
        #expect(c.state == .idle)
    }

    @Test("handleOTAResult is no-op when idle")
    func otaResultIgnoredWhenIdle() async {
        let c = BLEOTACoordinator.makeForTesting()
        c.handleOTAResult(statusCode: 0x00)
        #expect(c.state == .idle)
    }
}
```

- [ ] **Step 2.2: 确认测试失败（编译错误）**

```bash
cd KirolePackage && swift test --filter "BLEOTACoordinatorTests" 2>&1 | tail -5
```

Expected: 编译错误 `cannot find type 'BLEOTACoordinator'`

- [ ] **Step 2.3: 创建 BLEOTACoordinator.swift**

创建 `KirolePackage/Sources/KiroleFeature/Core/Services/BLEOTACoordinator.swift`：

```swift
import Foundation
import Observation

// MARK: - BLE OTA Coordinator

/// App-side state machine for the 0x18 OTA upgrade trigger flow (§4.17 / §5.17).
/// States: idle → sending → awaitingReboot → idle (success) / failed (error/timeout).
@MainActor
@Observable
public final class BLEOTACoordinator {

    // MARK: - Types

    public enum State: Equatable {
        case idle
        case sending
        case awaitingReboot
        case failed(Failure)
    }

    public enum Failure: Equatable {
        case deviceRejected(UInt8)
        case noResponse
        case timedOutWaitingForReboot
    }

    // MARK: - Constants

    private static let maxAttempts = 3
    private static let responseTimeoutSeconds: TimeInterval = 5
    private static let rebootTimeoutSeconds: TimeInterval = 90

    // MARK: - Shared

    public static let shared = BLEOTACoordinator()

    // MARK: - Observed

    public private(set) var state: State = .idle

    // MARK: - Private

    private let bleService: BLEService
    private var attemptCount = 0
    private var responseTimeoutTask: Task<Void, Never>?
    private var rebootTimeoutTask: Task<Void, Never>?

    private init(bleService: BLEService = .shared) {
        self.bleService = bleService
    }

    // Factory for unit tests only — not public product API.
    static func makeForTesting(bleService: BLEService = .shared) -> BLEOTACoordinator {
        BLEOTACoordinator(bleService: bleService)
    }

    // MARK: - Public API

    public func requestReboot() async {
        guard state == .idle else { return }
        attemptCount = 0
        await sendAttempt()
    }

    /// Called by BLEEventHandler when 0x18 OTAResult notify arrives.
    public func handleOTAResult(statusCode: UInt8) {
        guard state == .sending else { return }
        cancelResponseTimeout()
        if statusCode == 0x00 {
            enterAwaitingReboot()
        } else {
            bleService.isPendingOTAReboot = false
            state = .failed(.deviceRejected(statusCode))
        }
    }

    /// Called by BLEService.didDisconnectPeripheral when isPendingOTAReboot is true.
    /// A pre-response disconnect means the device likely started upgrading (§4.17).
    public func handleExpectedDisconnect() {
        guard state == .sending || state == .awaitingReboot else { return }
        cancelResponseTimeout()
        if state == .sending { enterAwaitingReboot() }
    }

    /// Called by BLEEventHandler on DeviceWake(0x30) to confirm upgrade complete.
    public func handleDeviceWake() {
        guard state == .awaitingReboot else { return }
        cancelRebootTimeout()
        bleService.isPendingOTAReboot = false
        state = .idle
    }

    /// Cancels all timers and resets to idle. Safe to call from any state.
    public func reset() {
        cancelResponseTimeout()
        cancelRebootTimeout()
        bleService.isPendingOTAReboot = false
        state = .idle
        attemptCount = 0
    }

    // MARK: - Private

    private func sendAttempt() async {
        guard attemptCount < Self.maxAttempts else {
            state = .failed(.noResponse)
            return
        }
        attemptCount += 1
        state = .sending
        // Write error is non-fatal here: the 5s timer will retry or give up.
        try? await bleService.sendOTAReboot()
        scheduleResponseTimeout()
    }

    private func scheduleResponseTimeout() {
        cancelResponseTimeout()
        responseTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BLEOTACoordinator.responseTimeoutSeconds))
            guard !Task.isCancelled, let self, self.state == .sending else { return }
            if self.bleService.connectionState.isConnected {
                await self.sendAttempt()
            }
            // If disconnected, handleExpectedDisconnect() was already called by BLEService.
        }
    }

    private func enterAwaitingReboot() {
        bleService.isPendingOTAReboot = true
        state = .awaitingReboot
        scheduleRebootTimeout()
    }

    private func scheduleRebootTimeout() {
        cancelRebootTimeout()
        rebootTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BLEOTACoordinator.rebootTimeoutSeconds))
            guard !Task.isCancelled, let self, self.state == .awaitingReboot else { return }
            self.bleService.isPendingOTAReboot = false
            self.state = .failed(.timedOutWaitingForReboot)
        }
    }

    private func cancelResponseTimeout() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
    }

    private func cancelRebootTimeout() {
        rebootTimeoutTask?.cancel()
        rebootTimeoutTask = nil
    }
}
```

- [ ] **Step 2.4: 运行 8 个测试确认全部 PASS**

```bash
cd KirolePackage && swift test --filter "BLEOTACoordinatorTests" 2>&1 | tail -15
```

- [ ] **Step 2.5: 全量构建**

```bash
cd KirolePackage && swift build 2>&1 | tail -5
```

- [ ] **Step 2.6: Commit**

```bash
git add KirolePackage/Sources/KiroleFeature/Core/Services/BLEOTACoordinator.swift \
        KirolePackage/Tests/KiroleFeatureTests/BLEOTACoordinatorTests.swift
git commit -m "feat(ble): add BLEOTACoordinator state machine for 0x18 OTA trigger"
```

---

### Task 3: BLEService — sendOTAReboot + disconnect notification

**Files:**
- Modify: `KirolePackage/Sources/KiroleFeature/Core/Services/BLEService.swift`

**Interfaces produced:**
- `BLEService.isPendingOTAReboot: Bool` (internal)
- `BLEService.sendOTAReboot() async throws`

- [ ] **Step 3.1: 添加 isPendingOTAReboot 属性**

在 `BLEService.swift` 中 `private var isIntentionalDisconnect = false`（约第 130 行）之后加：

```swift
    /// Set by BLEOTACoordinator during the OTA upgrade window.
    /// Suppresses connection-error UI during the expected device reboot disconnect.
    var isPendingOTAReboot = false
```

- [ ] **Step 3.2: 添加 sendOTAReboot() 方法**

在 `sendSceneUnlock` 之后（约第 630 行后）加：

```swift
    /// Sends OTAReboot (0x18) with zero payload. In secure mode, writeData
    /// automatically wraps this in SecureEnvelope (0x7E) — no special handling needed.
    public func sendOTAReboot() async throws {
        try await writeData(type: .otaReboot, data: Data())
    }
```

- [ ] **Step 3.3: 在 didDisconnectPeripheral 通知协调器**

在 `centralManager(_:didDisconnectPeripheral:error:)` 中，紧跟 `let wasIntentional = isIntentionalDisconnect` 这一行之后，`cleanup()` 之前，插入：

```swift
            // Notify OTA coordinator so it can transition to awaitingReboot
            // without waiting for the (now impossible) 0x18 response.
            if isPendingOTAReboot {
                BLEOTACoordinator.shared.handleExpectedDisconnect()
            }
```

- [ ] **Step 3.4: 全量构建 + 全套测试**

```bash
cd KirolePackage && swift build 2>&1 | tail -5
cd KirolePackage && swift test 2>&1 | tail -10
```

Expected: `Build complete!`，所有测试绿。

- [ ] **Step 3.5: Commit**

```bash
git add KirolePackage/Sources/KiroleFeature/Core/Services/BLEService.swift
git commit -m "feat(ble): add sendOTAReboot() and isPendingOTAReboot disconnect hook"
```

---

**继续到 Part 2：** `docs/superpowers/plans/2026-07-09-ble-ota-reboot-p2.md`
