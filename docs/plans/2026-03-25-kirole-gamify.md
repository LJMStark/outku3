# Kirole Gamify 模式实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 实现应用和墨水屏的联动游戏化机制，包含带IP宠物陪伴与呼吸动画的精致专注页面，以及连续使用场景解锁和定制化屏保。

**Architecture:** 
1. 前端新增 `GamificationManager` (@Observable) 负责管理连续使用天数、能量点数和场景解锁状态，并与 `LocalStorage` 双向同步。
2. 重构 `FocusView` 专注页面：引入高度贴合项目UI风格的陪伴型组件，展示项目专属IP宠物（如 `tiko_dog`, `tiko_reading` 等），且带有柔和的动态呼吸效果（`.scaleEffect` + `.animation(.easeInOut.repeatForever())`）。三段式（5分、15分、30分）能量吸收也将通过宠物周围的光源或漂浮的能量体来实现。
3. 后端 (Supabase) 扩展用户 Profile，存储连续打卡天数和能量/场景状态。通过 `BLESyncCoordinator` 下发解锁的新场景和明信片屏保到墨水屏硬件。

**Tech Stack:** Swift 6.1, SwiftUI, @Observable, Supabase, CoreBluetooth (BLE Protocol)

---

### Task 1: 数据模型与本地存储扩展

**Files:**
- Create: `KirolePackage/Sources/KiroleFeature/Models/GamifyModels.swift`
- Modify: `KirolePackage/Sources/KiroleFeature/Core/Storage/LocalStorage.swift`
- Test: `KirolePackage/Tests/KiroleFeatureTests/GamifyStorageTests.swift`

**Step 1: Write the failing test**

```swift
import Testing
@testable import KiroleFeature

@Test func testGamifyStorage() {
    let storage = LocalStorage.shared
    storage.consecutiveDays = 0
    storage.energyBlocks = 0
    
    storage.energyBlocks += 1
    #expect(storage.energyBlocks == 1)
}
```

**Step 2: Run test to verify it fails**

Run: `cd KirolePackage && swift test --filter "GamifyStorageTests"`
Expected: FAIL 原因是 `consecutiveDays` 和 `energyBlocks` 属性不存在。

**Step 3: Write minimal implementation**

```swift
// In LocalStorage.swift
public var consecutiveDays: Int {
    get { defaults.integer(forKey: "consecutiveDays") }
    set { defaults.set(newValue, forKey: "consecutiveDays") }
}
public var energyBlocks: Int {
    get { defaults.integer(forKey: "energyBlocks") }
    set { defaults.set(newValue, forKey: "energyBlocks") }
}
```

**Step 4: Run test to verify it passes**

Run: `cd KirolePackage && swift test --filter "GamifyStorageTests"`
Expected: PASS

**Step 5: Commit**

```bash
git add KirolePackage/Sources/KiroleFeature/Core/Storage/LocalStorage.swift KirolePackage/Tests/KiroleFeatureTests/GamifyStorageTests.swift
git commit -m "feat: add gamification storage properties and tests"
```

### Task 2: 带呼吸动画的 IP 专属专注陪伴页面

**Files:**
- Create: `KirolePackage/Sources/KiroleFeature/Views/Home/Components/FocusPetView.swift`
- Modify: `KirolePackage/Sources/KiroleFeature/Views/Home/FocusView.swift`

**Step 1: Write the failing test (Logical portion)**

测试能量计算器：
新建 `KirolePackage/Tests/KiroleFeatureTests/FocusEnergyTests.swift`

```swift
import Testing
@testable import KiroleFeature

@Test func testEnergyStageCalculation() {
    #expect(FocusEnergyCalculator.blocksEarned(minutes: 4) == 0)
    #expect(FocusEnergyCalculator.blocksEarned(minutes: 5) == 1)
    #expect(FocusEnergyCalculator.blocksEarned(minutes: 30) == 3)
}
```

**Step 2: Run test to verify it fails**

Run: `cd KirolePackage && swift test --filter "FocusEnergyTests"`
Expected: FAIL 原因是 `FocusEnergyCalculator` 不存在。

**Step 3: Write minimal implementation**

```swift
// 在 FocusPetView.swift 或相关逻辑文件里
import SwiftUI

public struct FocusEnergyCalculator {
    public static func blocksEarned(minutes: Int) -> Int {
        if minutes >= 30 { return 3 }
        if minutes >= 15 { return 2 }
        if minutes >= 5 { return 1 }
        return 0
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd KirolePackage && swift test --filter "FocusEnergyTests"`
Expected: PASS

**Step 5: UI 设计实现 (No Test)**

实现 `FocusPetView`：
- 使用 `Image("tiko_reading")` 或根据当期解锁状态展示IP。
- 添加 `@State private var isBreathing = false`。
- 在 `onAppear` 中触发 `.scaleEffect(isBreathing ? 1.05 : 0.98)` 以及带有 `.animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isBreathing)` 的效果。
- 将原本纯平面的 3 阶段触发（5分/15分/30分），替换为宠物四周的 **点亮动画/星光环绕** 或 **晶石收集槽**。

**Step 6: Commit**

```bash
git add KirolePackage/Sources/KiroleFeature/Views/Home/Components/FocusPetView.swift KirolePackage/Tests/KiroleFeatureTests/FocusEnergyTests.swift
git commit -m "feat: implement animated IP pet focus view and energy logic"
```

### Task 3: 场景解锁与蓝牙协议扩展

**Files:**
- Modify: `KirolePackage/Sources/KiroleFeature/Core/Services/BLEPacketizer.swift`

**Step 1: Write the failing test**

```swift
import Testing
@testable import KiroleFeature

@Test func testBLESceneUnlockCommand() {
    let packet = BLEPacketizer.buildSceneUnlockPacket(sceneId: 1)
    #expect(packet.count > 9) // Header + Data
}
```

**Step 2: Run test to verify it fails**

Run: `cd KirolePackage && swift test --filter "testBLESceneUnlockCommand"`
Expected: FAIL

**Step 3: Write minimal implementation**

```swift
// In BLEPacketizer.swift
extension BLEPacketizer {
    public static func buildSceneUnlockPacket(sceneId: UInt8) -> Data {
        var data = Data()
        data.append(contentsOf: [0xAA, 0x01, 0x01, sceneId]) 
        return data
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd KirolePackage && swift test --filter "testBLESceneUnlockCommand"`
Expected: PASS

**Step 5: Commit**

```bash
git add KirolePackage/Sources/KiroleFeature/Core/Services/BLEPacketizer.swift
git commit -m "feat: add ble packet encoding for scene unlock"
```
