import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Focus Protection Section

public struct SettingsFocusSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.focusService) private var focusService
    @State private var guardService = ScreenTimeFocusGuardService.shared

    public init() {}

    public var body: some View {
        if shouldShowSection || AppBuildEnvironment.showsHardwareDebugTools {
            sectionContent
                .task {
                    await guardService.refreshAuthorizationStatus()
                }
                .sheet(
                    isPresented: Binding(
                        get: { guardService.isPickerPresented },
                        set: { guardService.isPickerPresented = $0 }
                    )
                ) {
                    pickerSheet.injectAppEnvironment()
                }
        }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Focus Protection")

            VStack(alignment: .leading, spacing: 12) {
                if shouldShowSection {
                    modeSelector
                    statusCard
                    actionArea
                }

                if AppBuildEnvironment.showsHardwareDebugTools {
                    if shouldShowSection {
                        Divider()
                            .padding(.vertical, 4)
                    }
                    debugSessionButton
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }

    private var debugSessionButton: some View {
        Button {
            Task { @MainActor in
                if focusService.activeSession == nil {
                    await focusService.startSession(
                        taskId: "debug-focus-session",
                        taskTitle: "Debug Focus Session",
                        mode: .standard
                    )
                } else {
                    focusService.endSession(reason: .skipped)
                }
            }
        } label: {
            HStack {
                Image(systemName: "timer")
                Text(
                    focusService.activeSession == nil
                    ? "Start Test Focus Session"
                    : "End Test Focus Session"
                )
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(theme.colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start or end a real test focus session")
        .accessibilityHint("Opens the real focus screen with debugging controls")
        .accessibilityIdentifier("Debug_TestFocusSession")
    }

    private var shouldShowSection: Bool {
        guardService.isDeepFocusFeatureEnabled
    }

    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus Mode")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            HStack(spacing: 10) {
                modeButton(.standard)

                if guardService.canShowDeepFocusEntry {
                    modeButton(.deepFocus)
                }
            }
        }
    }

    private func modeButton(_ mode: FocusEnforcementMode) -> some View {
        Button {
            withAnimation(.kiroleGentle) {
                appState.setFocusEnforcementMode(mode)
            }
        } label: {
            Text(mode.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    appState.focusEnforcementMode == mode
                    ? theme.colors.accent
                    : theme.colors.secondaryText
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    appState.focusEnforcementMode == mode
                    ? theme.colors.accentLight
                    : Color(hex: "F9FAFB")
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Focus mode: \(mode.displayName)")
        .accessibilityIdentifier("Settings_FocusMode_\(mode.displayName)")
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Text(statusDescription)
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "F9FAFB"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var actionArea: some View {
        // 授权与选 App 入口对两种模式都开放：Standard 的打断检测（记打断、不拦截）
        // 复用 Deep Focus 的授权与自选分心 App 清单（spec 2026-07-09 D-1）。此前两个
        // 按钮只在 Deep Focus 分支渲染，Standard-only 用户被专注页文案指到 Settings
        // 却无门可进（授权和选 App 两道门都锁）。
        if !guardService.canShowDeepFocusEntry {
            // FamilyControls 能力不可用时两种模式都无可操作项（状态卡已明示检测
            // 不可用），只有 Deep Focus 需要解释为什么整个模式没了。
            if appState.focusEnforcementMode == .deepFocus {
                Text("Deep Focus is not available in this build.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
            }
        } else if guardService.authorizationStatus != .approved {
            Button {
                Task {
                    _ = await guardService.requestAuthorization()
                }
            } label: {
                actionCapsule(
                    icon: "hand.raised.fill",
                    title: "Request Screen Time Access"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Request Screen Time permission")
            .accessibilityIdentifier("Settings_RequestScreenTime")
        } else {
            Button {
                guardService.presentAppPicker()
            } label: {
                actionCapsule(
                    icon: "app.badge",
                    title: "Select Distracting Apps"
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose your distracting apps")
            .accessibilityIdentifier("Settings_SelectDistractingApps")
        }
    }

    private func actionCapsule(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(theme.colors.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.colors.accentLight)
        .clipShape(Capsule())
    }

    private var statusTitle: String {
        if appState.focusEnforcementMode == .standard {
            return "Standard Mode"
        }
        if guardService.authorizationStatus == .approved, guardService.selectedApplicationCount > 0 {
            return "Deep Focus Enabled"
        }
        return "Deep Focus Not Active"
    }

    private var statusDescription: String {
        if appState.focusEnforcementMode == .standard {
            // v2.5.20 打断判定重做后文案对齐：旧 "app state events" 信号已删除，
            // 现为屏幕使用时间监测自选分心 App（记打断、不拦截）。
            // 未就绪时明示缺哪一步，与 detectionState 的 unauthorized/selectionEmpty
            // 明示态（spec D-2）和下方 actionArea 的入口一一对应。
            guard guardService.canShowDeepFocusEntry else {
                return "Tracks focus time. Interruption detection isn't available on this build. No app blocking."
            }
            if guardService.authorizationStatus != .approved {
                return "Tracks focus time. Allow Screen Time access and select your distracting apps to enable interruption detection. No app blocking."
            }
            if guardService.selectedApplicationCount == 0 {
                return "Tracks focus time. Select your distracting apps to enable interruption detection. No app blocking."
            }
            return "Tracks focus time; using a distracting app you selected resets the current bottle. No app blocking."
        }

        if !guardService.canShowDeepFocusEntry {
            return "Deep Focus is unavailable on this system. Falling back to Standard."
        }

        switch guardService.authorizationStatus {
        case .approved:
            if guardService.selectedApplicationCount > 0 {
                return "Blocks \(guardService.selectedApplicationCount) distracting app(s) during sessions. Restored automatically when done."
            }
            return "Select distracting apps to block. Without a selection, Standard mode is used."
        case .denied:
            return "Screen Time access was denied. Falling back to Standard mode."
        case .notDetermined:
            return "Grant Screen Time access to enable Deep Focus. Standard mode is used until then."
        case .unavailable:
            return "Family Controls entitlement is not active on this build. Falling back to Standard."
        case .unsupported:
            return "Deep Focus is not supported on this system. Falling back to Standard."
        }
    }

    @ViewBuilder
    private var pickerSheet: some View {
        #if os(iOS) && canImport(FamilyControls)
        NavigationStack {
            FamilyActivityPicker(
                selection: Binding(
                    get: { guardService.familyActivitySelection },
                    set: { guardService.updateFamilyActivitySelection($0) }
                )
            )
            .navigationTitle("Select Distracting Apps")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        guardService.isPickerPresented = false
                    }
                }
            }
        }
        #else
        Text("Deep Focus picker is unavailable on this platform.")
            .padding(24)
        #endif
    }
}
