import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Pet Page View

struct PetPageView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var showPetStatus = false
    @State private var appeared = false
    @State private var todayDisplayFeedback: TodayDisplayFeedback?

    private var viewportWidth: CGFloat? {
        #if canImport(UIKit)
        return UIScreen.main.bounds.width
        #else
        return nil
        #endif
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Pet Illustration Section
                PetIllustrationSection(onTap: { showPetStatus = true })
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.appleEaseOut, value: appeared)

                // Tasks Section
                VStack(spacing: 0) {
                    // Tasks Today
                    TaskSectionView(
                        title: "Tasks Today",
                        tasks: todayTasks,
                        delay: 0.4,
                        onTodayDisplayChange: setTodayDisplay
                    )

                    // Upcoming
                    TaskSectionView(
                        title: "Upcoming",
                        tasks: upcomingTasks,
                        delay: 0.6,
                        onTodayDisplayChange: setTodayDisplay
                    )
                    .padding(.top, 24)

                    // No Due Dates
                    TaskSectionView(
                        title: "No Due Dates",
                        tasks: noDueDateTasks,
                        delay: 0.8,
                        onTodayDisplayChange: setTodayDisplay
                    )
                    .padding(.top, 24)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 80)
            }
            .frame(width: viewportWidth)
        }
        .background(theme.colors.background)
        .onAppear { appeared = true }
        .sheet(isPresented: $showPetStatus) {
            PetStatusView()
                .injectAppEnvironment()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let feedback = todayDisplayFeedback {
                TodayDisplayFeedbackView(
                    feedback: feedback,
                    onUndo: {
                        Task { @MainActor in
                            await appState.setTaskDisplayedToday(
                                feedback.task,
                                displayed: !feedback.displayed
                            )
                        }
                        withAnimation(.kiroleGentle) {
                            todayDisplayFeedback = nil
                        }
                    }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: todayDisplayFeedback?.id) {
            guard let feedbackID = todayDisplayFeedback?.id else { return }
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                return
            }
            guard todayDisplayFeedback?.id == feedbackID else { return }
            withAnimation(.kiroleGentle) {
                todayDisplayFeedback = nil
            }
        }
    }

    // MARK: - Task Filters

    // Intentional: tasks here are pet-dialogue context, not a to-do manager, and the product
    // is deliberately no-nag. Overdue (past-due) incomplete tasks are NOT surfaced — there is
    // no "Overdue" section by design, so a task with a past due date drops out of all three
    // buckets. Do not "fix" this into a nagging overdue list. (Confirmed product decision.)
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var todayTasks: [TaskItem] {
        appState.tasks.filter { $0.isInTodayDisplay(on: today) }
    }

    private var upcomingTasks: [TaskItem] {
        appState.tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate > today && !task.isInTodayDisplay(on: today)
        }
    }

    private var noDueDateTasks: [TaskItem] {
        appState.tasks.filter { $0.dueDate == nil && !$0.isInTodayDisplay(on: today) }
    }

    private func setTodayDisplay(_ task: TaskItem, _ displayed: Bool) {
        Task { @MainActor in
            await appState.setTaskDisplayedToday(task, displayed: displayed)
        }
        withAnimation(.kiroleGentle) {
            todayDisplayFeedback = TodayDisplayFeedback(task: task, displayed: displayed)
        }
    }
}

// MARK: - Pet Illustration Section

private struct PetIllustrationSection: View {
    let onTap: () -> Void
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motionTrigger: CompanionMotionTrigger?
    @State private var particleOffsets: [CGFloat] = [0, 0, 0]

    var body: some View {
        Button {
            guard appState.userProfile.currentSelection == .builtIn(.joy), !reduceMotion else {
                onTap()
                return
            }
            motionTrigger = CompanionMotionTrigger(motion: .react)
        } label: {
            ZStack {
                // Background Radial Gradient for "Habitat Focus"
                RadialGradient(
                    gradient: Gradient(colors: [
                        theme.colors.primary.opacity(0.15),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 50,
                    endRadius: 200
                )
                .frame(height: 340)

                VStack {
                    Spacer()

                    ZStack {
                        // Soft blurred ground shadow
                        Ellipse()
                            .fill(Color(hex: "8B5A2B").opacity(0.15))
                            .frame(width: 140, height: 24)
                            .blur(radius: 8)
                            .offset(y: 70)

                        CompanionAnimationView(
                            artwork: .scene,
                            ambientMotion: .idle,
                            trigger: motionTrigger ?? appState.pendingCompanionMotionTrigger,
                            size: CGSize(width: 300, height: 300),
                            isActive: appState.selectedTab == .pet,
                            accessibilityLabel: "Pet companion",
                            accessibilityIdentifier: "Pet_CompanionAnimation",
                            onOneShotCompletion: {
                                guard motionTrigger?.motion == .react else { return }
                                motionTrigger = nil
                                onTap()
                            }
                        )
                            .shadow(color: theme.colors.primary.opacity(0.1), radius: 20, x: 0, y: 10)
                            
                        // Floating Particles for liveliness
                        floatingParticles
                    }

                    Spacer()
                        .frame(height: 40)
                }
                .frame(height: 340)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View pet status")
        .accessibilityIdentifier("Pet_IllustrationButton")
        .accessibilityHint("Tap to view pet details")
        .onAppear {
            // Floating particles are ambient motion. Under Reduce Motion the
            // companion and decoration both remain static.
            guard !reduceMotion else { return }

            // Staggered particle animations
            for i in 0..<particleOffsets.count {
                withAnimation(
                    .easeInOut(duration: Double.random(in: 2...4))
                    .repeatForever(autoreverses: true)
                    .delay(Double.random(in: 0...2))
                ) {
                    particleOffsets[i] = -15
                }
            }
        }
    }
    
    @ViewBuilder
    private var floatingParticles: some View {
        ZStack {
            Image(systemName: "sparkle")
                .font(.system(size: 14))
                .foregroundColor(theme.colors.primary.opacity(0.3))
                .offset(x: -100, y: -40 + particleOffsets[0])

            Image(systemName: "leaf.fill")
                .font(.system(size: 10))
                .foregroundColor(Color.green.opacity(0.2))
                .offset(x: 110, y: 20 + particleOffsets[1])
                .rotationEffect(.degrees(15))

            Image(systemName: "sparkle")
                .font(.system(size: 18))
                .foregroundColor(theme.colors.primary.opacity(0.2))
                .offset(x: -80, y: 60 + particleOffsets[2])
        }
        .accessibilityHidden(true)
    }

}

// MARK: - Task Section Helper

private func iconForSectionTitle(_ title: String) -> String {
    switch title {
    case "Tasks Today":
        return "sun.max.fill"
    case "Upcoming":
        return "calendar"
    case "No Due Dates":
        return "tray.fill"
    default:
        return "list.bullet"
    }
}

// MARK: - Task Section View

private struct TaskSectionView: View {
    let title: String
    let tasks: [TaskItem]
    let delay: Double
    let onTodayDisplayChange: (TaskItem, Bool) -> Void

    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: iconForSectionTitle(title))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.colors.primary.opacity(0.8))
                
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.colors.primaryText)
            }
            .padding(.bottom, 4)

            if tasks.isEmpty {
                EmptyTaskPlaceholder()
            } else {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    TaskItemRow(task: task, onTodayDisplayChange: onTodayDisplayChange)
                        .opacity(appeared ? 1 : 0)
                        .offset(x: appeared ? 0 : -20)
                        .animation(
                            .kiroleGentle.delay(delay + Double(index) * 0.1),
                            value: appeared
                        )
                }
            }
        }
        .onAppear { appeared = true }
    }
}

// MARK: - Task Item Row

private struct TaskItemRow: View {
    let task: TaskItem
    let onTodayDisplayChange: (TaskItem, Bool) -> Void
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var showEditSheet = false
    @State private var isPressed = false

    var body: some View {
        Button {
            showEditSheet = true
        } label: {
            HStack(spacing: 12) {
                // Checkbox
                Button {
                    withAnimation(.kiroleBouncy) {
                        appState.toggleTaskCompletion(task)
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(task.isCompleted ? theme.colors.taskComplete : Color(hex: "D1D5DB"), lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .overlay {
                            if task.isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(hex: "3B82F6"))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isCompleted ? "Mark as incomplete" : "Mark as complete")
                .accessibilityIdentifier("Pet_TaskCheckbox")

                // Task title
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 15))
                        .foregroundStyle(task.isCompleted ? theme.colors.secondaryText : theme.colors.primaryText)
                        .strikethrough(task.isCompleted, color: theme.colors.secondaryText)
                        .lineLimit(1)

                    if task.syncStatus == .pending {
                        ProgressView()
                            .controlSize(.mini)
                    } else if task.syncStatus == .conflict || task.syncStatus == .error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "F59E0B"))
                    }

                    if task.pendingDeletion {
                        Text("Deleting")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }

                Spacer()

                todayDisplayControl

                // Due date label
                if let dueDate = task.dueDate {
                    Text(formatDueDate(dueDate))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(Color(hex: "8B5A2B"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "FDE68A").opacity(0.3)) // Soft pastel yellow
                        .clipShape(Capsule())
                }

                // More menu
                Menu {
                    if task.canRemoveTodayDisplayAction() {
                        Button {
                            onTodayDisplayChange(task, false)
                        } label: {
                            Label("Remove from Today", systemImage: "sun.max")
                        }
                        .accessibilityLabel("Remove from Today")
                        .accessibilityIdentifier("Pet_TaskRemoveFromTodayMenuItem")
                    } else if task.canShowTodayDisplayAction() {
                        Button {
                            onTodayDisplayChange(task, true)
                        } label: {
                            Label("Show Today", systemImage: "sun.max.fill")
                        }
                        .accessibilityLabel("Show Today")
                        .accessibilityIdentifier("Pet_TaskShowTodayMenuItem")
                    }

                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    if task.syncStatus == .conflict || task.syncStatus == .error {
                        Button {
                            Task { await appState.retryTaskSync(task) }
                        } label: {
                            Label(task.pendingDeletion ? "Retry Delete" : "Retry Sync", systemImage: "arrow.clockwise")
                        }
                    }

                    Button(role: .destructive) {
                        appState.deleteTask(task)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.secondaryText)
                        .rotationEffect(.degrees(90))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More actions")
                .accessibilityIdentifier("Pet_TaskMoreMenu")
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            // Warm shadow instead of pure black
            .shadow(color: theme.colors.primary.opacity(0.08), radius: 8, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "F3F4F6"), lineWidth: 1)
            )
        }
        .buttonStyle(RowScaleButtonStyle(isPressed: $isPressed))
        .accessibilityLabel(task.title)
        .accessibilityIdentifier("Pet_TaskRow")
        .accessibilityHint("Tap to edit task")
        .opacity(task.isCompleted ? 0.6 : 1.0)
        .sheet(isPresented: $showEditSheet) {
            TaskEditSheet(task: task)
                .injectAppEnvironment()
        }
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        return AppDateFormatters.shortDate.string(from: date)
    }

    private var isDueToday: Bool {
        task.isNaturallyDueToday()
    }

    @ViewBuilder
    private var todayDisplayControl: some View {
        // Display-only. Pin/unpin is a single entry point in the ⋯ menu (Show Today /
        // Remove from Today); the row only shows a status badge when a task is manually
        // pinned. Due-today rows already carry the yellow "today" date capsule, so nothing
        // renders there.
        if !isDueToday, task.isManuallySelectedForToday() {
            // Icon-only state badge (Microsoft To Do's My Day sun / Things 3's Today star
            // pattern): the row's only textual date stays the real due date, so the pin
            // marker can never read as a second "today".
            Image(systemName: "sun.max.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.colors.primary.opacity(0.85))
                .padding(6)
                .background(theme.colors.primary.opacity(0.1))
                .clipShape(Circle())
                .accessibilityLabel("Shown today")
        }
    }
}

private struct TodayDisplayFeedback: Identifiable {
    let id = UUID()
    let task: TaskItem
    let displayed: Bool
}

private struct TodayDisplayFeedbackView: View {
    let feedback: TodayDisplayFeedback
    let onUndo: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feedback.displayed ? "sun.max.fill" : "sun.max")
                .foregroundStyle(theme.colors.accent)

            Text(feedback.displayed
                 ? "Shown today · Due date unchanged"
                 : "Removed from today")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.primaryText)

            Spacer(minLength: 8)

            Button("Undo", action: onUndo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.accent)
                .accessibilityIdentifier("Pet_TodayDisplayUndo")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

// Custom Row Button Style for scale effect
private struct RowScaleButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.kiroleSnappy, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

// MARK: - Empty Task Placeholder

private struct EmptyTaskPlaceholder: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 18))
                .foregroundStyle(theme.colors.primary.opacity(0.6))

            Text("All caught up! Relax time.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.colors.primary.opacity(0.7))

            Spacer()
        }
        .padding(16)
        .background(theme.colors.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                )
                .foregroundColor(theme.colors.primary.opacity(0.3))
        )
    }
}

#Preview {
    PetPageView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
