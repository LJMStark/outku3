import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Focus Protection Section

public struct SettingsFocusSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var guardService = ScreenTimeFocusGuardService.shared
    @State private var showFocusTest = false

    public init() {}

    public var body: some View {
        if shouldShowSection {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader(title: "Focus Protection")

                VStack(alignment: .leading, spacing: 14) {
                    modeSelector
                    statusCard
                    actionArea
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    Button {
                        showFocusTest = true
                    } label: {
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                            Text("Test Focus UI")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(theme.colors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
            }
            .task {
                await guardService.refreshAuthorizationStatus()
            }
            .sheet(
                isPresented: Binding(
                    get: { guardService.isPickerPresented },
                    set: { guardService.isPickerPresented = $0 }
                )
            ) {
                pickerSheet
            }
            .fullScreenCover(isPresented: $showFocusTest) {
                FocusTestOverlayView(isPresented: $showFocusTest)
            }
        }
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
            withAnimation(Animation.appStandard) {
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
        if appState.focusEnforcementMode == .deepFocus {
            if !guardService.canShowDeepFocusEntry {
                Text("Deep Focus 在当前构建中不可用。")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if guardService.authorizationStatus != .approved {
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
                    }
                }
            }
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
            return "Standard 模式"
        }
        if guardService.authorizationStatus == .approved, guardService.selectedApplicationCount > 0 {
            return "Deep Focus 已启用"
        }
        return "Deep Focus 未启用保护"
    }

    private var statusDescription: String {
        if appState.focusEnforcementMode == .standard {
            return "基于 BLE 和前后台事件统计专注时长，不会拦截 App。"
        }

        if !guardService.canShowDeepFocusEntry {
            return "系统能力不可用，已自动回退标准专注。"
        }

        switch guardService.authorizationStatus {
        case .approved:
            if guardService.selectedApplicationCount > 0 {
                return "会话期间将屏蔽 \(guardService.selectedApplicationCount) 个分心 App，结束后自动恢复。"
            }
            return "请先选择需要屏蔽的分心 App，未选择时会自动回退标准专注。"
        case .denied:
            return "未授予 Screen Time 权限，已自动回退标准专注。"
        case .notDetermined:
            return "请先授予 Screen Time 权限，未授权时会自动回退标准专注。"
        case .unavailable:
            return "当前签名未开通 Family Controls 能力，已自动回退标准专注。"
        case .unsupported:
            return "当前系统不支持 Deep Focus，已自动回退标准专注。"
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

// MARK: - Focus Test View

private struct FocusTestOverlayView: View {
    @Binding var isPresented: Bool
    @Environment(ThemeManager.self) private var theme
    
    @State private var elapsedSeconds: Int = 0
    @State private var isAccelerated = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            theme.colors.background.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                Text(elapsedSeconds > 0 ? "Focusing" : "Ready to Focus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(theme.colors.primaryText)
                
                FocusPetView(focusMinutes: elapsedSeconds / 60)
                
                Text(timeString(from: elapsedSeconds))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.colors.primaryText)
                
                HStack(spacing: 20) {
                    Toggle(isOn: $isAccelerated) {
                        Text("加速测试 (1秒=1分)")
                    }
                    .toggleStyle(.button)
                    .tint(theme.colors.accent)
                    
                    Button("Reset") {
                        withAnimation { elapsedSeconds = 0 }
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.colors.secondaryText)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding()
            }
        }
        .onReceive(timer) { _ in
            if isPresented {
                withAnimation {
                    // 如果是加速测试，每1秒跳1分钟（60秒）
                    elapsedSeconds += isAccelerated ? 60 : 1
                }
            }
        }
    }
    
    private func timeString(from totalSeconds: Int) -> String {
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}
