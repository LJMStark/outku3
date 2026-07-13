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
