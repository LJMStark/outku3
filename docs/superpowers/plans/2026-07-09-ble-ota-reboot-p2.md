# BLE OTA Reboot — Part 2 (BLEEventHandler + UI + Verification)

> **前置 Part 1:** `2026-07-09-ble-ota-reboot-p1.md` 必须先全部完成。

## Global Constraints

- Swift Testing only: `import Testing`, `@Test`, `#expect`. No XCTest.
- English-only UI strings.
- No ViewModels; SwiftUI 视图直接读 @Observable 单例。
- Every interactive element needs `accessibilityLabel` + `accessibilityIdentifier`.
- 每个 task 完成后 `cd KirolePackage && swift build` 确认无编译错误再 commit。

---

### Task 4: BLEEventHandler — 路由 otaResult + deviceWake

**Files:**
- Modify: `KirolePackage/Sources/KiroleFeature/Core/Services/BLEEventHandler.swift`

**Interfaces consumed:**
- `EventLogType.otaResult` (Part 1 Task 1)
- `BLEOTACoordinator.shared` (Part 1 Task 2)

- [ ] **Step 4.1: 在 handleSingleEvent 中路由 otaResult**

在 `BLEEventHandler.swift` 的 `handleSingleEvent(_:service:)` 函数 switch 块里，
在 `case .reminderAcknowledged, .reminderDismissed:` 之后追加：

```swift
        case .otaResult:
            // Status code is stored in EventLog.value (Int), clamped to UInt8.
            let statusCode = UInt8(clamping: eventLog.value)
            BLEOTACoordinator.shared.handleOTAResult(statusCode: statusCode)
```

- [ ] **Step 4.2: 在 deviceWake case 里通知协调器**

找到 `case .deviceWake:` 对应的 `Task { @MainActor in` 块，
在 `do { try await service.syncTime() }` 这行**之前**插入：

```swift
                // Confirm upgrade complete if OTA was pending.
                BLEOTACoordinator.shared.handleDeviceWake()
```

完整 `case .deviceWake:` 的 Task 块头部应该是：
```swift
        case .deviceWake:
            Task { @MainActor in
                BLEOTACoordinator.shared.handleDeviceWake()  // ← 新增
                do {
                    try await service.syncTime()
                } catch { ...
```

- [ ] **Step 4.3: 全量构建 + 全套测试**

```bash
cd KirolePackage && swift build 2>&1 | tail -5
cd KirolePackage && swift test 2>&1 | tail -10
```

Expected: `Build complete!`，所有测试绿。

- [ ] **Step 4.4: Commit**

```bash
git add KirolePackage/Sources/KiroleFeature/Core/Services/BLEEventHandler.swift
git commit -m "feat(ble): route OTAResult and DeviceWake events to BLEOTACoordinator"
```

---

### Task 5: Settings UI — OTA upgrade card

**Files:**
- Modify: `KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsBLESection.swift`

**Interfaces consumed:**
- `BLEOTACoordinator.shared.state: BLEOTACoordinator.State` (Part 1 Task 2)
- `FocusSessionService.shared` — check existing API for "is session active" before writing

- [ ] **Step 5.1: 先查 FocusSessionService 的会话状态属性**

```bash
grep -n "isSession\|activeSession\|var.*session" \
  KirolePackage/Sources/KiroleFeature/Core/Services/FocusSessionService.swift | head -10
```

记下正确的属性名（可能是 `activeSession != nil` 或 `isSessionActive`），Step 5.2 里用这个。

- [ ] **Step 5.2: 在 SettingsBLESection 添加 otaCoordinator state 属性**

在现有的 `@State private var bleService = BLEService.shared` 之后加：

```swift
    @State private var otaCoordinator = BLEOTACoordinator.shared
```

- [ ] **Step 5.3: 添加 otaUpgradeCard computed property**

在 `screenSizeCard` 之后，`keepAliveCard` 之前，添加以下 computed property（用 Step 5.1 查到的正确属性名替换 `/* isActive */`）：

```swift
    @MainActor
    private var otaUpgradeCard: some View {
        let otaState = otaCoordinator.state
        // Use the result of Step 5.1 to get focus session active status:
        let hasFocusSession = FocusSessionService.shared.activeSession != nil
        let isBusy = otaState == .sending || otaState == .awaitingReboot
        let isDisabled: Bool = {
            if hasFocusSession { return true }
            switch otaState {
            case .idle, .failed: return false
            case .sending, .awaitingReboot: return true
            }
        }()

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                Text("Firmware Update")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer()
                otaStateBadge(otaState)
            }

            Text(otaDescriptionText(otaState, hasFocusSession: hasFocusSession))
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { @MainActor in
                    if case .failed = otaState { otaCoordinator.reset() }
                    await otaCoordinator.requestReboot()
                }
            } label: {
                HStack(spacing: 8) {
                    if isBusy { ProgressView().scaleEffect(0.8).tint(theme.colors.primaryText) }
                    Text(otaButtonLabel(otaState))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(isDisabled ? theme.colors.secondaryText : theme.colors.primaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isDisabled ? Color.gray.opacity(0.08) : theme.colors.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isDisabled || isBusy)
            .accessibilityLabel(isBusy ? "Firmware upgrade in progress" : "Update firmware")
            .accessibilityIdentifier("Settings_OTAUpgradeButton")
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private func otaStateBadge(_ state: BLEOTACoordinator.State) -> some View {
        let (label, color): (String, Color) = switch state {
        case .idle:           ("Ready", theme.colors.accent)
        case .sending:        ("Sending...", Color.orange)
        case .awaitingReboot: ("Upgrading...", Color.orange)
        case .failed:         ("Failed", Color.red)
        }
        return Text(label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func otaDescriptionText(
        _ state: BLEOTACoordinator.State,
        hasFocusSession: Bool
    ) -> String {
        if hasFocusSession {
            return "Focus session in progress. End your focus session before updating firmware."
        }
        switch state {
        case .idle:
            return "Upload update.bin via the device WiFi AP first, then tap Update. The device will reboot (~20 seconds)."
        case .sending:
            return "Sending upgrade command to device..."
        case .awaitingReboot:
            return "Device is upgrading firmware (~20 seconds). Do not close this screen."
        case .failed(.deviceRejected(let code)):
            return "Device rejected upgrade (code 0x\(String(format: "%02X", code))). Check that update.bin was uploaded via WiFi AP."
        case .failed(.noResponse):
            return "Device did not respond. Check the BLE connection and try again."
        case .failed(.timedOutWaitingForReboot):
            return "Device did not reconnect after the expected upgrade window. Check the device."
        case .failed:
            return "Upgrade failed. Please try again."
        }
    }

    private func otaButtonLabel(_ state: BLEOTACoordinator.State) -> String {
        switch state {
        case .idle:           "Update Firmware"
        case .sending:        "Sending..."
        case .awaitingReboot: "Upgrading... (~20s)"
        case .failed:         "Retry"
        }
    }
```

- [ ] **Step 5.4: 在 body 中插入 otaUpgradeCard**

在 `SettingsBLESection.body` 的 VStack 里，`screenSizeCard` 之后加一行：

```swift
            screenSizeCard
            otaUpgradeCard     // ← 新增
            
            if AppBuildEnvironment.showsHardwareDebugTools {
                keepAliveCard
            }
```

- [ ] **Step 5.5: 全量构建**

```bash
cd KirolePackage && swift build 2>&1 | tail -5
```

如果编译报 `activeSession` 属性不存在，根据 Step 5.1 的查询结果修正属性名。

- [ ] **Step 5.6: 全套测试**

```bash
cd KirolePackage && swift test 2>&1 | tail -10
```

- [ ] **Step 5.7: Commit**

```bash
git add KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsBLESection.swift
git commit -m "feat(ble): add OTA firmware upgrade card to Hardware Details settings"
```

---

### Task 6: 最终验证

- [ ] **Step 6.1: 运行全套测试并检查 simulation suite**

```bash
cd KirolePackage && swift test 2>&1 | tail -20
```

特别关注 `BLEProtocolSimulationTests`——OTA 帧全是定长（出站零 payload、入站 1 字节），
不触碰 `parseDayPack`/`parseWeather`，但要确认无意外回归。

- [ ] **Step 6.2: 确认 BLEOTACoordinatorTests 全覆盖**

```bash
cd KirolePackage && swift test --filter "BLEOTACoordinatorTests" 2>&1 | grep -E "passed|failed"
```

Expected: 8 tests passed, 0 failed.

- [ ] **Step 6.3: 提交协议文档（之前只改了不在 staged 的文件）**

```bash
git status | grep "BLE通信"
git add "docs/BLE通信协议规格文档.md"
git commit -m "docs(ble): v2.5.18 add OTAReboot/OTAResult protocol spec (§4.17/§5.17)"
```

- [ ] **Step 6.4: 检查最终 git log**

```bash
git log --oneline -7
git status
```

Expected: working tree clean，6-7 commits 覆盖 Part 1 Task 1-3 + Part 2 Task 4-6 + 文档。

---

## 遗留事项（不在本计划里）

- **固件版本号识别**：升级成功与升级失败回滚在 App 侧观察到的现象相同（DeviceWake 回来）。§4.17"已知边界"已记录，待后续与固件团队确认 DeviceWake 是否需要携带版本号字段。
- **安全模式联调**：当前 `BLE_SHARED_SECRET` 为空（明文模式）。启用安全模式前须确认固件 OTAResult 回复走 SecureEnvelope，见 §5.17"安全模式说明"。
- **Simulator 测试**：UI 改动在模拟器里目测验收——本次计划里没有 UI 快照测试，视情况补。
