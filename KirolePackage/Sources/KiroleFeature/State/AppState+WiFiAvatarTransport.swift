import Foundation

/// WiFi 未开启弹窗的用户选择。
public enum WiFiEnableChoice: Sendable {
    case openSettings
    case useBluetooth
    case cancel
}

extension AppState {
    /// 把 `customAvatarFrameSender` seam 换成 WiFi-优先路由闭包（失败自动回退 BLE），
    /// 并从 UserDefaults 载入传输偏好。生产实例在 init 调用；测试实例可按需手动调用。
    func installCustomAvatarTransportRouter() {
        avatarTransferPreference = AvatarTransferPreference.load()
        let bleSender = bleCustomAvatarFrameSender
        customAvatarFrameSender = { [weak self] operationID, avatarID, kriData, progress in
            guard let self else {
                try await bleSender(operationID, avatarID, kriData, progress)
                return
            }
            try await self.routeCustomAvatarFrame(
                operationID: operationID,
                avatarID: avatarID,
                kriData: kriData,
                progress: progress,
                bleSender: bleSender
            )
        }
    }

    /// 按偏好路由头像帧传输：WiFi 优先，失败按类型回退 BLE 或弹窗引导。
    func routeCustomAvatarFrame(
        operationID: UInt32,
        avatarID: UUID,
        kriData: Data,
        progress: @escaping @MainActor @Sendable (Int, Int) -> Void,
        bleSender: CustomAvatarFrameSender
    ) async throws {
        switch avatarTransferPreference {
        case .bleOnly:
            try await bleSender(operationID, avatarID, kriData, progress)
        case .auto, .wifiPreferred:
            do {
                try await wifiAvatarTransport.send(
                    operationID: operationID,
                    avatarID: avatarID,
                    kriData: kriData,
                    onPhase: { [weak self] phase in self?.applyWiFiTransferPhase(phase) },
                    onProgress: progress
                )
            } catch WiFiTransferError.wifiDisabled {
                switch await promptWiFiEnable() {
                case .useBluetooth:
                    try await bleSender(operationID, avatarID, kriData, progress)
                case .openSettings, .cancel:
                    // 用户选择不走 WiFi：中断本次（→ .interrupted，可 Send Again / 开 WiFi 后重试）。
                    throw CancellationError()
                }
            } catch let error as WiFiTransferError where error.isRecoverableToBLE {
                ErrorReporter.log(
                    .sync(component: "WiFi Avatar", underlying: String(describing: error)),
                    context: "AppState.routeCustomAvatarFrame.fallbackBLE"
                )
                try await bleSender(operationID, avatarID, kriData, progress)
            }
            // CancellationError（传输中用户取消）不在此捕获——冒泡给事务机按中断处理。
        }
    }

    /// 把 WiFi 传输子阶段桥接到 `customAvatarOperationState`。带在途守卫，忽略迟到回调。
    func applyWiFiTransferPhase(_ phase: WiFiTransferPhase) {
        guard customAvatarOperationState.isInProgress else { return }
        switch phase {
        case .joiningHotspot:
            customAvatarOperationState = .joiningHotspot
        case .uploading:
            let total = pendingCustomAvatarOperation?.fileLength ?? 0
            customAvatarOperationState = .transferring(sentBytes: 0, totalBytes: total)
        }
    }

    /// 挂起路由决策，展示 WiFi-off 引导弹窗，直到用户在 ContentView `.alert` 做出选择。
    func promptWiFiEnable() async -> WiFiEnableChoice {
        await withCheckedContinuation { continuation in
            wifiEnableContinuation = continuation
            isWiFiEnablePromptPresented = true
        }
    }

    /// ContentView `.alert` 按钮回调：resume 挂起的路由决策。
    public func resolveWiFiEnablePrompt(_ choice: WiFiEnableChoice) {
        guard let continuation = wifiEnableContinuation else { return }
        wifiEnableContinuation = nil
        isWiFiEnablePromptPresented = false
        continuation.resume(returning: choice)
    }
}
