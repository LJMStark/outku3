import SwiftUI

// MARK: - Focus Session Screen

/// 专注模式固定界面（spec 任务1）：会话进行中自动全屏呈现；打开/停留本界面
/// 不算打断（v2.5.20 打断判定：仅自选分心 App 的使用算打断）。
/// 检测未开启时按 spec D-2 在界面明示，不静默装作在检测。
public struct FocusSessionScreen: View {
    @Environment(\.focusService) private var focusService
    @Environment(\.themeManager) private var theme

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
        let interruptions = focusService.currentUnlockEvents(until: now)
        let segmentStart = FocusTimeCalculator.currentSegmentStart(
            sessionStart: session.startTime,
            now: now,
            screenUnlockEvents: interruptions
        )
        let segmentSeconds = max(0, now.timeIntervalSince(segmentStart))
        let segmentMinutes = Int(segmentSeconds / 60)
        let bottles = FocusTimeCalculator.countableBottles(
            sessionStart: session.startTime,
            sessionEnd: now,
            screenUnlockEvents: interruptions
        )
        let phase = FocusPhase.from(elapsedMinutes: segmentMinutes)
        let elapsed = max(0, now.timeIntervalSince(session.startTime))

        VStack(spacing: 28) {
            Spacer(minLength: 60)

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
            }

            FocusPetView(focusMinutes: segmentMinutes)

            Text(timeString(from: elapsed))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.colors.primaryText)
                .accessibilityLabel("Focused for \(timeString(from: elapsed))")

            VStack(spacing: 10) {
                ProgressView(value: min(1, segmentSeconds / bottleBlockSeconds))
                    .tint(theme.colors.accent)
                    .padding(.horizontal, 48)
                HStack(spacing: 14) {
                    Text(phase.displayString)
                    Text("·")
                    Text(bottles == 1 ? "1 bottle collected" : "\(bottles) bottles collected")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.secondaryText)
            }

            Spacer()

            detectionNotice
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
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
