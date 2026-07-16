import Foundation
import Testing
@testable import KiroleFeature

// MARK: - BLEConnectionPolicy

/// 覆盖连接状态机的纯决策逻辑——扫描 / 连接互斥、断开后是否重连。
/// 这些是 BLE 重连卡死复盘后抽离出来的"唯一真相源"，必须被穷尽测试。
@Suite("BLEConnectionPolicy")
struct BLEConnectionPolicyTests {

    // MARK: - canBeginScan

    @Test("given idle state, when canBeginScan, then allowed")
    func givenIdle_whenCanBeginScan_thenAllowed() {
        #expect(BLEConnectionPolicy.canBeginScan(state: .disconnected))
        #expect(BLEConnectionPolicy.canBeginScan(state: .error("bluetooth off")))
    }

    @Test("given busy state, when canBeginScan, then rejected")
    func givenBusy_whenCanBeginScan_thenRejected() {
        // 这正是历史卡死的根因：扫描 / 连接进行中再发起扫描会覆盖单槽 continuation。
        #expect(!BLEConnectionPolicy.canBeginScan(state: .scanning))
        #expect(!BLEConnectionPolicy.canBeginScan(state: .connecting))
        #expect(!BLEConnectionPolicy.canBeginScan(state: .connected))
    }

    // MARK: - canBeginConnect

    @Test("given idle state, when canBeginConnect, then allowed")
    func givenIdle_whenCanBeginConnect_thenAllowed() {
        #expect(BLEConnectionPolicy.canBeginConnect(state: .disconnected))
        #expect(BLEConnectionPolicy.canBeginConnect(state: .error("bluetooth off")))
    }

    @Test("given busy state, when canBeginConnect, then rejected")
    func givenBusy_whenCanBeginConnect_thenRejected() {
        #expect(!BLEConnectionPolicy.canBeginConnect(state: .scanning))
        #expect(!BLEConnectionPolicy.canBeginConnect(state: .connecting))
        #expect(!BLEConnectionPolicy.canBeginConnect(state: .connected))
    }

    // MARK: - shouldAutoReconnect

    @Test("given intentional disconnect, when shouldAutoReconnect, then never reconnects")
    func givenIntentional_whenShouldAutoReconnect_thenNever() {
        // sync 收尾 / 用户点断开 / 后台到期都属主动断开，绝不能触发自动重连（否则连接风暴）。
        #expect(!BLEConnectionPolicy.shouldAutoReconnect(isIntentional: true, autoReconnectEnabled: true))
        #expect(!BLEConnectionPolicy.shouldAutoReconnect(isIntentional: true, autoReconnectEnabled: false))
    }

    @Test("given unexpected disconnect, when shouldAutoReconnect, then reconnects only if enabled")
    func givenUnexpected_whenShouldAutoReconnect_thenOnlyIfEnabled() {
        #expect(BLEConnectionPolicy.shouldAutoReconnect(isIntentional: false, autoReconnectEnabled: true))
        #expect(!BLEConnectionPolicy.shouldAutoReconnect(isIntentional: false, autoReconnectEnabled: false))
    }

    @Test("WiFi debug keeps BLE open even when generic keep-alive is off")
    func wifiDebugKeepsConnectionOpen() {
        #expect(BLEConnectionPolicy.shouldKeepConnectionOpenForDebug(
            keepAliveEnabled: false,
            wifiDebugRequiresConnection: true
        ))
        #expect(BLEConnectionPolicy.shouldKeepConnectionOpenForDebug(
            keepAliveEnabled: true,
            wifiDebugRequiresConnection: false
        ))
        #expect(!BLEConnectionPolicy.shouldKeepConnectionOpenForDebug(
            keepAliveEnabled: false,
            wifiDebugRequiresConnection: false
        ))
    }
}

// MARK: - BLERateLimiter sync throttle

@Suite("BLERateLimiter sync throttle")
struct BLERateLimiterSyncThrottleTests {

    @Test("first sync trigger is allowed, immediate second within window is throttled")
    func firstAllowedSecondThrottled() async {
        let limiter = BLERateLimiter()

        let first = await limiter.allowSyncTrigger()
        let second = await limiter.allowSyncTrigger()

        #expect(first == true)
        #expect(second == false)
    }

    @Test("independent limiter instances do not share throttle state")
    func independentInstancesIsolated() async {
        let limiterA = BLERateLimiter()
        let limiterB = BLERateLimiter()

        _ = await limiterA.allowSyncTrigger()
        let bFirst = await limiterB.allowSyncTrigger()

        #expect(bFirst == true)
    }
}

// MARK: - BLERateLimiter refresh throttle (H4)

/// H4 回归护栏：硬件物理刷新键 0x20(requestRefresh) 必须有独立于 deviceWake 0x30 的节流闸。
/// 否则频繁的设备唤醒会吃掉共享配额、饿死用户的显式刷新——联调时表现为"按了刷新没反应"。
@Suite("BLERateLimiter refresh throttle")
struct BLERateLimiterRefreshThrottleTests {

    @Test("given fresh limiter, when first refresh trigger, then allowed")
    func givenFresh_whenFirstRefresh_thenAllowed() async {
        let limiter = BLERateLimiter()

        #expect(await limiter.allowRefreshTrigger() == true)
    }

    @Test("given a refresh just allowed, when immediate second refresh, then throttled")
    func givenRefreshAllowed_whenImmediateSecond_thenThrottled() async {
        let limiter = BLERateLimiter()

        let first = await limiter.allowRefreshTrigger()
        let second = await limiter.allowRefreshTrigger()

        #expect(first == true)
        #expect(second == false)
    }

    @Test("given deviceWake throttle consumed, when requestRefresh checks its gate, then not starved")
    func givenWakeConsumed_whenRefresh_thenNotStarved() async {
        // H4 核心契约：0x20 与 0x30 用各自独立的闸。设备唤醒吃掉 sync 配额后，
        // 用户的物理刷新键仍必须能触发——绝不能被唤醒饿死。
        let limiter = BLERateLimiter()

        _ = await limiter.allowSyncTrigger()                // deviceWake(0x30) 消费 sync 闸
        let refresh = await limiter.allowRefreshTrigger()   // requestRefresh(0x20) 独立闸

        #expect(refresh == true)
    }

    @Test("given a refresh consumed, when deviceWake checks its gate, then not starved")
    func givenRefreshConsumed_whenWake_thenNotStarved() async {
        // 反向同理：刷新闸与唤醒闸互不挤占。
        let limiter = BLERateLimiter()

        _ = await limiter.allowRefreshTrigger()
        let wake = await limiter.allowSyncTrigger()

        #expect(wake == true)
    }
}

// MARK: - BLERateLimiter focus-refresh throttle (codex review 2026-07-13, 发现1)

/// 护栏：0x20 触发的专注状态(0x14)回推自带独立短闸——它放在整轮 sync 的 60s 合并窗**之前**
/// （要按时更新瓶子），故须自带限流，防固件把 0x20 当 ~2s 心跳狂发时并发 Task 在首个 BLE 写
/// 完成、去重键更新前无界排入写队列。独立于 sync 闸与整轮 refresh 闸，三者互不挤占。
@Suite("BLERateLimiter focus-refresh throttle")
struct BLERateLimiterFocusRefreshThrottleTests {

    @Test("given fresh limiter, when first focus-refresh trigger, then allowed")
    func givenFresh_whenFirstFocusRefresh_thenAllowed() async {
        let limiter = BLERateLimiter()

        #expect(await limiter.allowFocusRefreshTrigger() == true)
    }

    @Test("given a focus-refresh just allowed, when immediate second, then throttled")
    func givenFocusRefreshAllowed_whenImmediateSecond_thenThrottled() async {
        let limiter = BLERateLimiter()

        let first = await limiter.allowFocusRefreshTrigger()
        let second = await limiter.allowFocusRefreshTrigger()

        #expect(first == true)
        #expect(second == false)
    }

    @Test("focus-refresh gate is independent of the sync and full-refresh gates")
    func focusRefreshGateIndependent() async {
        // 三条闸互不挤占：deviceWake(0x30) sync 闸与 0x20 整轮 refresh 闸消费后，
        // 专注回推闸仍必须放行——否则息屏期间瓶子/段位更新被饿死。
        let limiter = BLERateLimiter()

        _ = await limiter.allowSyncTrigger()
        _ = await limiter.allowRefreshTrigger()
        let focus = await limiter.allowFocusRefreshTrigger()

        #expect(focus == true)
    }

    // MARK: - shouldProcessCallback（迟到 delegate 回调准入：代次门 + 外设身份）

    @Test("given same generation and matching peripheral, when callback arrives, then processed")
    func givenCurrentCallback_whenShouldProcess_thenAllowed() {
        let device = UUID()

        #expect(BLEConnectionPolicy.shouldProcessCallback(
            generationAtDelivery: 7,
            currentGeneration: 7,
            callbackPeripheralID: device,
            trackedPeripheralID: device
        ))
    }

    @Test("given generation changed between delivery and execution, when callback arrives, then dropped")
    func givenStaleGeneration_whenShouldProcess_thenDropped() {
        // 投递→Task 执行之间新尝试已起步：旧回调若放行会推进已死尝试的发现/完成链，
        // didDisconnect 场景还会误清新尝试状态、错误完成单槽 connectCompletion。
        let device = UUID()

        #expect(!BLEConnectionPolicy.shouldProcessCallback(
            generationAtDelivery: 7,
            currentGeneration: 8,
            callbackPeripheralID: device,
            trackedPeripheralID: device
        ))
    }

    @Test("given callback from a peripheral no longer tracked, when callback arrives, then dropped")
    func givenForeignPeripheral_whenShouldProcess_thenDropped() {
        // 身份门在"投递本身已晚于换代、代次检查失明"的场景仍然有效：
        // 残留外设的回调与当前跟踪外设不同，一律拒绝。
        #expect(!BLEConnectionPolicy.shouldProcessCallback(
            generationAtDelivery: 8,
            currentGeneration: 8,
            callbackPeripheralID: UUID(),
            trackedPeripheralID: UUID()
        ))
    }

    @Test("given cleanup already cleared the tracked peripheral, when callback arrives, then dropped")
    func givenNoTrackedPeripheral_whenShouldProcess_thenDropped() {
        // cleanup 跑完（connectedPeripheral=nil）后到达的迟到回调无归属，跳过。
        #expect(!BLEConnectionPolicy.shouldProcessCallback(
            generationAtDelivery: 8,
            currentGeneration: 8,
            callbackPeripheralID: UUID(),
            trackedPeripheralID: nil
        ))
    }
}
