import SwiftUI

// MARK: - Home View

public struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(AuthManager.self) private var authManager
    @State private var showScrollToTop = false
    @State private var scrollOffset: CGFloat = 0
    @State private var isInitialLoading = true

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Scrollable content
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Anchor for scroll to top
                            Color.clear
                                .frame(height: 1)
                                .id("top")

                            // Loading indicator
                            if isInitialLoading {
                                LoadingIndicatorView()
                                    .padding(.top, 40)
                            }

                            // Timeline content
                            TimelineContentView()

                            // Bottom spacing
                            Spacer()
                                .frame(height: 100)
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geo.frame(in: .named("scroll")).minY
                                    )
                            }
                        )
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showScrollToTop = value < -300
                        }
                        scrollOffset = value
                    }
                    .refreshable {
                        await refreshData()
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if showScrollToTop {
                            ScrollToTopButton {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    proxy.scrollTo("top", anchor: .top)
                                }
                            }
                            .padding(.trailing, 24)
                            .padding(.bottom, 24)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .background(theme.colors.background)
        .task {
            guard !appState.hasCompletedInitialHomeLoad else {
                isInitialLoading = false
                return
            }
            appState.hasCompletedInitialHomeLoad = true
            await loadInitialData()
        }
    }

    private func loadInitialData() async {
        isInitialLoading = true
        defer { isInitialLoading = false }

        // Initial screen should not be blocked by network / EventKit callbacks.
        Task { @MainActor in
            await appState.loadTodayHaiku()
        }

        if authManager.isGoogleConnected {
            Task { @MainActor in
                await appState.syncGoogleData()
            }
        }

        Task { @MainActor in
            await appState.syncAppleData()
        }

        // Keep loader briefly to avoid flicker and ensure first paint is stable.
        try? await Task.sleep(for: .milliseconds(300))
    }

    private func refreshData() async {
        // Haptic feedback at start
        SoundService.shared.haptic(.medium)

        // Sync all data
        if authManager.isGoogleConnected {
            await appState.syncGoogleData()
        }

        await appState.syncAppleData()
        await appState.loadTodayHaiku()

        // Success haptic
        SoundService.shared.haptic(.success)
    }
}

// MARK: - Loading Indicator View

private struct LoadingIndicatorView: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(theme.colors.accent)

            Text("Loading your day...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.secondaryText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(theme.colors.cardBackground)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Scroll to Top Button

private struct ScrollToTopButton: View {
    @Environment(ThemeManager.self) private var theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                Circle()
                    .stroke(theme.colors.primary, lineWidth: 2)
                    .frame(width: 56, height: 56)

                Image(systemName: "arrow.up")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.colors.primary)
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

#Preview {
    HomeView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
