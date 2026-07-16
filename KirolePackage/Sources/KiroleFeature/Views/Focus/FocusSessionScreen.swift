import SwiftUI

// MARK: - Focus Session Screen

/// 专注模式固定界面（spec 任务1）：会话进行中自动全屏呈现；打开/停留本界面
/// 不算打断（v2.5.20 打断判定：仅自选分心 App 的使用算打断）。
/// 检测未开启时按 spec D-2 在界面明示，不静默装作在检测。
public struct FocusSessionScreen: View {
    @Environment(\.focusService) private var focusService
    @Environment(\.themeManager) private var theme
    @State private var showEndEarlyConfirmation = false

    /// 每 30 分钟一个能量瓶（协议 §9 / FocusEnergyCalculator 同一常量）。
    private let bottleBlockSeconds: TimeInterval = 30 * 60

    let onHide: () -> Void

    public init(onHide: @escaping () -> Void) {
        self.onHide = onHide
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.colors.background.ignoresSafeArea()

            if let session = focusService.activeSession {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    sessionContent(session: session, now: context.date)
                }
            } else {
                // Session ended while the cover was up; ContentView's binding
                // dismisses on the next update pass.
                Color.clear
            }

            Button(action: onHide) {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .padding(20)
            .accessibilityLabel("Hide focus screen")
            .accessibilityIdentifier("focus.hideButton")
        }
        // 不给根容器挂 accessibilityIdentifier：实测会级联覆盖所有子元素的 id
        // （隐藏按钮的 focus.hideButton 因此查不到），交互元素各自持有 id 即可。
    }

    @ViewBuilder
    private func sessionContent(session: FocusSession, now: Date) -> some View {
        let progress = focusService.progressSnapshot(now: now)

        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                // spacing 18 + 顶部 16：四块新增内容后总高度必须收在一屏内，
                // 否则页面可滚动、宠物图会滚到灵动岛下面被遮挡（2026-07-16 用户反馈）。
                VStack(spacing: 18) {
                    Spacer(minLength: 16)

                    VStack(spacing: 6) {
                        Text("Focusing")
                            .font(.system(size: 15, weight: .semibold))
                            .textCase(.uppercase)
                            .kerning(1.2)
                            .foregroundStyle(theme.colors.secondaryText)
                        Text(session.taskTitle)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(theme.colors.primaryText)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 32)
                        statusPills(session: session)
                            .padding(.top, 6)
                    }

                    FocusPetView(focusMinutes: progress.segmentMinutes)

                    CompanionDialogueView(
                        FocusCompanionPhrases.phrase(
                            phase: progress.phase,
                            elapsedMinutes: progress.elapsedMinutes
                        ),
                        color: theme.colors.secondaryText
                    )
                    .padding(.horizontal, 32)
                    .accessibilityIdentifier("focus.companionPhrase")

                    Text(timeString(from: progress.elapsedSeconds))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.primaryText)
                        .accessibilityLabel("Focused for \(timeString(from: progress.elapsedSeconds))")

                    VStack(spacing: 10) {
                        ProgressView(value: min(1, progress.segmentSeconds / bottleBlockSeconds))
                            .tint(theme.colors.accent)
                            .padding(.horizontal, 48)
                        HStack(spacing: 14) {
                            Text(progress.phase.displayString)
                            Text("·")
                            Text(
                                progress.earnedEnergyBottles == 1
                                ? "1 bottle collected"
                                : "\(progress.earnedEnergyBottles) bottles collected"
                            )
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.colors.secondaryText)
                        HStack(spacing: 6) {
                            Text("Today \(formatFocusTime(focusService.todayFocusTimeIncludingActive(now: now)))")
                            Text("·")
                            Text("Started \(session.startTime.formatted(date: .omitted, time: .shortened))")
                        }
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(theme.colors.secondaryText)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("focus.todayInfoRow")
                    }

                    Spacer()

                    endEarlyButton

                    detectionNotice
                        .padding(.horizontal, 24)
                        .padding(.bottom, AppBuildEnvironment.showsHardwareDebugTools ? 0 : 28)

                    // Debug 卡放最底：即便折叠到首屏外也只影响调试者，
                    // 用户内容（宠物→End Early→检测卡）保持一屏内不滚动。
                    if AppBuildEnvironment.showsHardwareDebugTools {
                        debugControls
                            .padding(.horizontal, 24)
                            .padding(.bottom, 28)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .accessibilityIdentifier("focus.scrollView")
        }
    }

    // MARK: - Status Pills

    /// Deep Focus / shield 生效状态徽章。数据一直都在（session.mode / protectionState），
    /// 此前 UI 完全不显示——用户开了 Deep Focus 屏上看不到任何确认。
    @ViewBuilder
    private func statusPills(session: FocusSession) -> some View {
        HStack(spacing: 8) {
            pill(
                text: session.mode == .deepFocus ? "Deep Focus" : "Standard",
                icon: nil,
                emphasized: session.mode == .deepFocus
            )
            .accessibilityLabel(
                session.mode == .deepFocus ? "Deep Focus mode" : "Standard mode"
            )
            .accessibilityIdentifier("focus.pill.mode")

            if session.mode == .deepFocus {
                let isShielded = session.protectionState == .protected
                pill(
                    text: isShielded ? "Apps Locked" : "Apps Unlocked",
                    icon: isShielded ? "lock.fill" : "lock.open",
                    emphasized: isShielded
                )
                .accessibilityLabel(
                    isShielded
                    ? "Distracting apps are locked"
                    : "Distracting apps are not locked"
                )
                .accessibilityIdentifier("focus.pill.shield")
            }
        }
    }

    private func pill(text: String, icon: String?, emphasized: Bool) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.8)
        }
        .foregroundStyle(emphasized ? theme.colors.accent : theme.colors.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(emphasized ? theme.colors.accentLight : theme.colors.cardBackground)
        )
    }

    // MARK: - End Early

    /// 低调文字按钮：给 Settings 手动开局的会话一个 App 内出口。结束走与硬件
    /// 完成/跳过/断连同一条 endSession 出口（shield 清除、结算、0x14 idle 推硬件）。
    private var endEarlyButton: some View {
        Button {
            showEndEarlyConfirmation = true
        } label: {
            Text("End Early")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.secondaryText)
                .padding(.vertical, 8)
                .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("End focus session early")
        .accessibilityIdentifier("focus.endEarlyButton")
        .confirmationDialog(
            "End this focus session early?",
            isPresented: $showEndEarlyConfirmation,
            titleVisibility: .visible
        ) {
            Button("End Session", role: .destructive) {
                focusService.endSession(reason: .manual)
            }
            Button("Keep Focusing", role: .cancel) {}
        } message: {
            Text("Bottles you've already collected are safe.")
        }
    }

    private func formatFocusTime(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private var debugControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus Debug")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Toggle(
                "1 second = 1 minute",
                isOn: Binding(
                    get: { focusService.isFocusTimeAccelerated },
                    set: { focusService.setFocusTimeAcceleration($0) }
                )
            )
            .font(.system(size: 13, weight: .medium))
            .tint(theme.colors.accent)
            .accessibilityLabel("Accelerate focus time")
            .accessibilityHint("Makes one real second count as one focus minute")
            .accessibilityIdentifier("focus.debug.accelerationToggle")

            Button {
                focusService.advanceFocusTime(by: 30 * 60)
            } label: {
                Label("Add 30 minutes", systemImage: "goforward.30")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(theme.colors.accentLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add 30 focus minutes")
            .accessibilityHint("Advances this focus session by 30 virtual minutes")
            .accessibilityIdentifier("focus.debug.addThirtyMinutes")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.colors.cardBackground)
        )
    }

    private var detectionNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: detectionIconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(detectionIsActive ? theme.colors.accent : theme.colors.secondaryText)
                .padding(.top, 1)
            Text(detectionNoticeText)
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.colors.cardBackground)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("focus.detectionNotice")
    }

    private var detectionIsActive: Bool {
        focusService.interruptionDetectionState == .active
    }

    private var detectionIconName: String {
        detectionIsActive ? "eye" : "eye.slash"
    }

    private var detectionNoticeText: String {
        switch focusService.interruptionDetectionState {
        case .active:
            return "Interruption detection is on. Using a distracting app you selected will reset the current bottle."
        case .unauthorized:
            return "Interruption detection is off — allow Screen Time access to enable it. Your focus time still counts."
        case .selectionEmpty:
            return "Interruption detection is off — choose your distracting apps in Settings to enable it. Your focus time still counts."
        case .extensionUnavailable:
            return "Interruption detection isn't available in this version yet. Your focus time still counts."
        case .monitoringFailed:
            return "Interruption detection couldn't start due to a system error. Your focus time still counts."
        }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let total = Int(interval)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Focus Companion Phrases

/// 专注页伴侣陪伴语：本地静态池，不调 LLM。按阶段分池、以 elapsed 分钟数确定性
/// 轮换（每 10 分钟换一句），TimelineView 的秒级重渲染自然驱动切换。
/// 全英文（English-only product UI）；口吻与 CompanionTextService 的温暖人设一致。
enum FocusCompanionPhrases {
    /// 活跃会话的第 1 分钟 FocusPhase.from 会短暂返回 .idle，映射到 warmup 池兜底。
    static func phrase(phase: FocusPhase, elapsedMinutes: Int) -> String {
        let pool = pool(for: phase)
        let index = (max(0, elapsedMinutes) / rotationMinutes) % pool.count
        return pool[index]
    }

    static let rotationMinutes = 10

    static func pool(for phase: FocusPhase) -> [String] {
        switch phase {
        case .idle, .warmup:
            return warmupPool
        case .building:
            return buildingPool
        case .deep:
            return deepPool
        }
    }

    private static let warmupPool = [
        "I'm right here with you.",
        "Nice and easy. One thing at a time.",
        "We just started. No rush at all.",
        "Deep breath. I've got your back.",
    ]

    private static let buildingPool = [
        "Look at you go. This bottle is filling up.",
        "Still with you. You're doing great.",
        "Steady pace. That's the way.",
        "One step at a time. We're moving.",
    ]

    private static let deepPool = [
        "This is deep water. I'll keep watch.",
        "You're in the zone. I'll stay quiet.",
        "Time feels soft in here, doesn't it?",
        "Proud of you. Truly.",
    ]
}
