import SwiftUI

// MARK: - Focus Settlement Data

struct FocusSettlementData {
    let focusMinutes: Int
    let earnedBottles: Int
    let totalBottles: Int
}

// MARK: - Home View

public struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var showScrollToTop = false
    @State private var scrollOffset: CGFloat = 0
    @State private var isInitialLoading = true
    @State private var dataSource = TimelineDataSource()
    @State private var showSettlement = false
    @State private var settlementData: FocusSettlementData?

    public init() {}

    private var companionTaskRefreshKey: String {
        let activeSession = FocusSessionService.shared.activeSession
        let taskSignature = appState.tasks
            .sorted { $0.id < $1.id }
            .map { task in
                let recency = AppState.taskRecency(task).timeIntervalSince1970
                return "\(task.id)|\(task.title)|\(task.isCompleted ? 1 : 0)|\(task.pendingDeletion ? 1 : 0)|\(recency)"
            }
            .joined(separator: "||")
        return "\(activeSession?.taskId ?? "")||\(activeSession?.taskTitle ?? "")||\(taskSignature)"
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            Color.clear
                                .frame(height: 1)
                                .id("top")

                            if isInitialLoading {
                                LoadingIndicatorView()
                                    .padding(.top, 40)
                            }

                            // Today section with pet embedded in timeline
                            DaySectionView(date: dataSource.dateForOffset(0), showPet: true)
                                .background(daySectionPositionTracker(for: dataSource.dateForOffset(0)))

                            // Remaining days (offset 1+)
                            ForEach(dataSource.dayOffsets.dropFirst(), id: \.self) { offset in
                                DaySectionView(
                                    date: dataSource.dateForOffset(offset),
                                    showPet: dataSource.shouldShowPetMarker(at: offset)
                                )
                                .background(daySectionPositionTracker(for: dataSource.dateForOffset(offset)))
                            }

                            // Sentinel to trigger loading more days
                            Color.clear
                                .frame(height: 1)
                                .onAppear { dataSource.loadMoreDays() }

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
                    .onPreferenceChange(VisibleDatePreferenceKey.self) { items in
                        // Pick the topmost section that has scrolled to or past the top
                        if let top = items
                            .filter({ $0.minY <= 40 })
                            .max(by: { $0.minY < $1.minY })
                        {
                            appState.selectedDate = top.date
                        }
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
                    #if DEBUG
                    .overlay(alignment: .topTrailing) {
                        PromptDebuggerFAB()
                            .padding(.trailing, 16)
                            .padding(.top, 60) // Avoid safe area / notch
                    }
                    #endif
                }
            }
        }
        .background(theme.colors.background)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshVisibleHomeCompanion()
        }
        .onChange(of: companionTaskRefreshKey) { _, _ in
            Task {
                await appState.refreshSharedPetDialogueIfNeeded()
                await appState.refreshHomeCompanionPresentation()
            }
        }
        .task {
            guard !appState.hasCompletedInitialHomeLoad else {
                isInitialLoading = false
                return
            }
            appState.hasCompletedInitialHomeLoad = true
            await loadInitialData()
        }
        .onChange(of: FocusSessionService.shared.todaySessions.count) { oldCount, newCount in
            guard newCount > oldCount, newCount > 0 else { return }
            guard let lastSession = FocusSessionService.shared.todaySessions.last else { return }
            let focusMinutes = Int((lastSession.calculatedFocusTime ?? 0) / 60)
            guard focusMinutes > 0 else { return }
            settlementData = FocusSettlementData(
                focusMinutes: focusMinutes,
                earnedBottles: lastSession.earnedEnergyBottles,
                totalBottles: FocusSessionService.shared.todaySessions.map(\.earnedEnergyBottles).reduce(0, +)
            )
            showSettlement = true
        }
        .sheet(isPresented: $showSettlement) {
            if let data = settlementData {
                FocusSettlementSheet(
                    focusMinutes: data.focusMinutes,
                    earnedBottles: data.earnedBottles,
                    totalBottles: data.totalBottles
                )
                .environment(theme)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
            }
        }
    }

    /// Invisible background that reports this section's Y position for date tracking.
    private func daySectionPositionTracker(for date: Date) -> some View {
        GeometryReader { geo in
            Color.clear
                .preference(
                    key: VisibleDatePreferenceKey.self,
                    value: [VisibleDateItem(
                        date: date,
                        minY: geo.frame(in: .named("scroll")).minY
                    )]
                )
        }
    }

    private func loadInitialData() async {
        isInitialLoading = true
        defer { isInitialLoading = false }

        Task { @MainActor in
            await appState.syncConnectedExternalData()
        }

        // Keep loader briefly to avoid flicker and ensure first paint is stable.
        try? await Task.sleep(for: .milliseconds(300))
    }

    private func refreshVisibleHomeCompanion() async {
        appState.selectedDate = Date()
        await appState.refreshSharedPetDialogueIfNeeded()
        await appState.refreshHomeCompanionPresentation()
    }

    private func refreshData() async {
        // Haptic feedback at start
        SoundService.shared.haptic(.medium)
        appState.selectedDate = Date()

        await appState.syncConnectedExternalData()
        await appState.refreshSharedPetDialogueIfNeeded(force: true)
        appState.switchHomeToPetDialogue()

        // Success haptic
        SoundService.shared.haptic(.success)
    }
}

// MARK: - Visible Date Tracking

private struct VisibleDateItem: Equatable {
    let date: Date
    let minY: CGFloat
}

private struct VisibleDatePreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [VisibleDateItem] = []
    static func reduce(value: inout [VisibleDateItem], nextValue: () -> [VisibleDateItem]) {
        value.append(contentsOf: nextValue())
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
        .buttonStyle(.kiroleIcon)
    }
}



#Preview {
    HomeView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
