import Foundation

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

    /// 按偏好路由头像帧传输：WiFi 优先，技术性失败自动回退 BLE。
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
            } catch let error as WiFiTransferError {
                // 用户取消与技术性失败可能同时到达；取消优先，不能再启动昂贵的 BLE 分包。
                try Task.checkCancellation()
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

}
