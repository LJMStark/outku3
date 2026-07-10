import SwiftUI

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Focus Protection Section

public struct SettingsFocusSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var guardService = ScreenTimeFocusGuardService.shared
    #if DEBUG
    @State private var showFocusTest = false
    #endif

    public init() {}

    public var body: some View {
        if shouldShowSection {
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
                #if DEBUG
                .modifier(FocusTestPresentationModifier(isPresented: $showFocusTest))
                #endif
        }
    }

    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Focus Protection")

            VStack(alignment: .leading, spacing: 12) {
                modeSelector
                statusCard
                actionArea

                #if DEBUG
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
                .accessibilityLabel("Test focus UI")
                .accessibilityIdentifier("Debug_TestFocusUI")

                Button {
                    Task { @MainActor in
                        if FocusSessionService.shared.activeSession == nil {
                            await FocusSessionService.shared.startSession(
                                taskId: "debug-focus-session",
                                taskTitle: "Debug Focus Session"
                            )
                        } else {
                            FocusSessionService.shared.endSession(reason: .skipped)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "timer")
                        Text(FocusSessionService.shared.activeSession == nil
                             ? "Start Test Focus Session"
                             : "End Test Focus Session")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(theme.colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start or end a test focus session")
                .accessibilityIdentifier("Debug_TestFocusSession")
                #endif
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
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
        if appState.focusEnforcementMode == .deepFocus {
            if !guardService.canShowDeepFocusEntry {
                Text("Deep Focus is not available in this build.")
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
                        .accessibilityLabel("Choose apps to block")
                        .accessibilityIdentifier("Settings_SelectDistractingApps")
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
            return "Standard Mode"
        }
        if guardService.authorizationStatus == .approved, guardService.selectedApplicationCount > 0 {
            return "Deep Focus Enabled"
        }
        return "Deep Focus Not Active"
    }

    private var statusDescription: String {
        if appState.focusEnforcementMode == .standard {
            return "Tracks focus duration via BLE and app state events. No app blocking."
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

// MARK: - Focus Test View

private struct FocusTestPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: $isPresented) {
            FocusTestOverlayView(isPresented: $isPresented)
                .injectAppEnvironment()
        }
        #else
        content.sheet(isPresented: $isPresented) {
            FocusTestOverlayView(isPresented: $isPresented)
                .injectAppEnvironment()
        }
        #endif
    }
}

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
                        Text("Fast-forward test (1s = 1min)")
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
            .accessibilityLabel("Close focus test")
            .accessibilityIdentifier("FocusTest_Close")
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
