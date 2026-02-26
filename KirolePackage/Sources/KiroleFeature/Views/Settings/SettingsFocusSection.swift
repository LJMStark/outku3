import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Focus Protection Section

public struct SettingsFocusSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var guardService = ScreenTimeFocusGuardService.shared

    public init() {}

    public var body: some View {
        if shouldShowSection {
            VStack(alignment: .leading, spacing: 12) {
                SettingsSectionHeader(title: "Focus Protection")

                VStack(alignment: .leading, spacing: 14) {
                    modeSelector
                    statusCard
                    actionArea
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
