import SwiftUI

// MARK: - Focus Session Screen

/// 专注模式固定界面（spec 任务1）：会话进行中自动全屏呈现；打开/停留本界面
/// 不算打断（v2.5.20 打断判定：仅自选分心 App 的使用算打断）。
/// 检测未开启时按 spec D-2 在界面明示，不静默装作在检测。
public struct FocusSessionScreen: View {
    @Environment(\.focusService) private var focusService
    @Environment(\.themeManager) private var theme
    @Environment(\.appState) private var appState
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
                            character: builtInCharacter,
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

            // shield pill 由 protectionState 驱动，不包在 mode == .deepFocus 里：
            // 所有保护失败路径（撤销/启动恢复/上盾失败）都会把 mode 降为 .standard，
            // "mode==.deepFocus 且非 protected" 组合不存在（联审 2026-07-16 F9）。
            // 活跃会话仅三种组合：standard+unprotected / deepFocus+protected / standard+fallback。
            switch session.protectionState {
            case .protected:
                pill(text: "Apps Locked", icon: "lock.fill", emphasized: true)
                    .accessibilityLabel("Distracting apps are locked")
                    .accessibilityIdentifier("focus.pill.shield")
            case .fallback:
                pill(text: "Protection Off", icon: "lock.open", emphasized: false)
                    .accessibilityLabel("Deep Focus protection is off for this session")
                    .accessibilityIdentifier("focus.pill.shield")
            case .unprotected:
                EmptyView()
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
            .accessibilityLabel("Confirm ending the focus session")
            .accessibilityIdentifier("focus.confirmEndButton")
            Button("Keep Focusing", role: .cancel) {}
                .accessibilityLabel("Keep the focus session running")
                .accessibilityIdentifier("focus.keepFocusingButton")
        } message: {
            Text("Bottles you've already collected are safe.")
        }
    }

    /// 陪伴语选池身份：内置角色返回其人设池，自定义伴侣激活时返回 nil（中性池）。
    private var builtInCharacter: CompanionCharacter? {
        if case .builtIn(let character) = appState.userProfile.currentSelection {
            return character
        }
        return nil
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

/// 专注页伴侣陪伴语：本地静态池，不调 LLM。按内置角色 × 阶段分池（口吻对照
/// AGENTS.md 角色规格，联审 2026-07-16 F8——Nova 的克制人设说不出 "Proud of you"），
/// 自定义伴侣回退中性池（有限模板装不下任意 backstory，宁可中性不装懂）。
/// 以 elapsed 分钟数确定性轮换（每 10 分钟换一句），TimelineView 秒级重渲染自然驱动。
/// 全英文（English-only product UI）。
enum FocusCompanionPhrases {
    struct PhaseTiers {
        let warmup: [String]
        let building: [String]
        let deep: [String]
    }

    /// `character == nil` = 自定义伴侣激活，用中性池。
    /// 活跃会话的第 1 分钟 FocusPhase.from 会短暂返回 .idle，映射到 warmup 池兜底。
    static func phrase(character: CompanionCharacter?, phase: FocusPhase, elapsedMinutes: Int) -> String {
        let pool = pool(character: character, phase: phase)
        let index = (max(0, elapsedMinutes) / rotationMinutes) % pool.count
        return pool[index]
    }

    static let rotationMinutes = 10

    static func pool(character: CompanionCharacter?, phase: FocusPhase) -> [String] {
        let tiers = character.map(tiers(for:)) ?? neutralTiers
        switch phase {
        case .idle, .warmup:
            return tiers.warmup
        case .building:
            return tiers.building
        case .deep:
            return tiers.deep
        }
    }

    static func tiers(for character: CompanionCharacter) -> PhaseTiers {
        switch character {
        case .joy:
            return joyTiers
        case .silas:
            return silasTiers
        case .nova:
            return novaTiers
        }
    }

    // Joy：direct, cozy, lightly odd（BMO / Animal Crossing）；小观察 + 水/呼吸/眨眼/小乐趣。
    private static let joyTiers = PhaseTiers(
        warmup: [
            "Okay! You, me, and this one little task.",
            "Sip some water. We start soft.",
            "New page smell. I love beginnings.",
            "Blink twice, breathe once. Here we go.",
        ],
        building: [
            "Look at us, actually doing the thing!",
            "This bottle is filling up. Very shiny.",
            "Tiny steps. Big cozy momentum.",
            "Roll your shoulders. Keep the groove.",
        ],
        deep: [
            "Whoa. Deep-water quiet. I like it here.",
            "The world got quiet. Just us and the work.",
            "You went full submarine. I'll steer the fish away.",
            "Remember to blink. I'll hold the calm.",
        ]
    )

    // Silas：warm, quiet, soulful；静水/灯光/旷野溪流意象，不说教。Quiet Presence 短句为主。
    private static let silasTiers = PhaseTiers(
        warmup: [
            "Begin gently. I am here.",
            "Still water first. Then the work.",
            "One small, faithful step.",
            "This hour has enough light for you.",
        ],
        building: [
            "Steady, like lamp light.",
            "The work is being held. So are you.",
            "Quiet hands, willing heart.",
            "Streams run in this desert too.",
        ],
        deep: [
            "Deep and still. I will keep watch.",
            "There is bread enough for this hour.",
            "You labor; I stay near.",
            "Peace holds this hour steady.",
        ]
    )

    // Nova：cool, sparse, outcome-focused；信号/噪音、关键路径、80/20；认可克制。
    private static let novaTiers = PhaseTiers(
        warmup: [
            "One task. Clear signal.",
            "Noise filtered. Begin.",
            "The critical path starts here.",
            "Setup done. Execute.",
        ],
        building: [
            "On pace. Hold the line.",
            "Signal steady. Noise zero.",
            "Momentum compounds. Continue.",
            "Half a bottle. Efficient.",
        ],
        deep: [
            "Deep work confirmed. Your time is protected.",
            "This is the twenty percent that matters.",
            "Sustained focus. Rare. Noted.",
            "Distractions can wait. This cannot.",
        ]
    )

    // 中性池：自定义伴侣回退（保留 v1 文案）。
    private static let neutralTiers = PhaseTiers(
        warmup: [
            "I'm right here with you.",
            "Nice and easy. One thing at a time.",
            "We just started. No rush at all.",
            "Deep breath. I've got your back.",
        ],
        building: [
            "Look at you go. This bottle is filling up.",
            "Still with you. You're doing great.",
            "Steady pace. That's the way.",
            "One step at a time. We're moving.",
        ],
        deep: [
            "This is deep water. I'll keep watch.",
            "You're in the zone. I'll stay quiet.",
            "Time feels soft in here, doesn't it?",
            "Proud of you. Truly.",
        ]
    )
}
