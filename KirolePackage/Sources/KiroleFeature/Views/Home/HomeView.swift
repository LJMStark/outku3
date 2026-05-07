import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Focus Settlement Data

struct FocusSettlementData: Identifiable {
    let id = UUID()
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
    @State private var isInitialLoading = true
    @State private var dataSource = TimelineDataSource()
    @State private var settlementData: FocusSettlementData?

    public init() {}

    private var viewportWidth: CGFloat? {
        #if canImport(UIKit)
        return UIScreen.main.bounds.width
        #else
        return nil
        #endif
    }

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
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            // Top anchor: drives both scrollTo target and
                            // scroll-to-top button visibility via lifecycle.
                            Color.clear
                                .frame(height: 1)
                                .id("top")
                                .onAppear {
                                    withAnimation(.kiroleSnappy) {
                                        showScrollToTop = false
                                    }
                                }
                                .onDisappear {
                                    withAnimation(.kiroleSnappy) {
                                        showScrollToTop = true
                                    }
                                }

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
                        .frame(width: viewportWidth)
                    }
                    .accessibilityIdentifier("home.timelineScrollView")
                    .coordinateSpace(name: "scroll")
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
                } // VStack

                if showScrollToTop {
                    ScrollToTopButton {
                        withAnimation(.kiroleGentle) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                    .accessibilityIdentifier("home.scrollToTopButton")
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(2)
                }

                #if DEBUG
                VStack {
                    PromptDebuggerFAB()
                        .padding(.trailing, 16)
                        .padding(.top, 60) // Avoid safe area / notch
                    Spacer()
                }
                .zIndex(3)
                #endif
            } // ZStack
            .background(theme.colors.background)
        } // ScrollViewReader
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
                totalBottles: FocusSessionService.shared.todaySessions.reduce(0) { $0 + $1.earnedEnergyBottles }
            )
        }
        .sheet(item: $settlementData) { data in
            FocusSettlementSheet(
                focusMinutes: data.focusMinutes,
                earnedBottles: data.earnedBottles,
                totalBottles: data.totalBottles
            )
            .injectAppEnvironment()
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(24)
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

// MARK: - Scroll to Top Button

private struct ScrollToTopButton: View {
    @Environment(ThemeManager.self) private var theme
    let action: () -> Void

    private let faceSize: CGFloat = 52
    private let outerHeight: CGFloat = 60
    private let cornerRadius: CGFloat = 16
    private let strokeWidth: CGFloat = 3.5

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                // Back shelf — solid dark base to create the 3D depth
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.colors.primaryDark)
                    .frame(width: faceSize, height: outerHeight)

                // Front white face
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
                    .frame(width: faceSize, height: faceSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(theme.colors.primaryDark, lineWidth: strokeWidth)
                    )
                    .overlay(
                        Image(systemName: "arrow.up.to.line")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(theme.colors.primaryDark)
                            .offset(y: 1) // optical alignment
                    )
            }
            .frame(width: faceSize, height: outerHeight)
        }
        .buttonStyle(.kiroleIcon)
    }
}
#Preview {
    HomeView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
