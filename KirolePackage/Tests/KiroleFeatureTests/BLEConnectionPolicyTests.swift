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
