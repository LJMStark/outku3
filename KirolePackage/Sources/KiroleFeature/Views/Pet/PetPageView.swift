import SwiftUI

// MARK: - Private Helpers

private let dueDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
}()

// MARK: - Pet Page View

struct PetPageView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var showPetStatus = false
    @State private var appeared = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Pet Illustration Section
                PetIllustrationSection(onTap: { showPetStatus = true })
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.6), value: appeared)

                // Tasks Section
                VStack(spacing: 0) {
                    // Tasks Today
                    TaskSectionView(
                        title: "Tasks Today",
                        tasks: todayTasks,
                        delay: 0.4
                    )

                    // Upcoming
                    TaskSectionView(
                        title: "Upcoming",
                        tasks: upcomingTasks,
                        delay: 0.6
                    )
                    .padding(.top, 24)

                    // No Due Dates
                    TaskSectionView(
                        title: "No Due Dates",
                        tasks: noDueDateTasks,
                        delay: 0.8
                    )
                    .padding(.top, 24)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 80)
            }
        }
        .background(theme.colors.background)
        .onAppear { appeared = true }
        .sheet(isPresented: $showPetStatus) {
            PetStatusView()
                .environment(appState)
                .environment(theme)
        }
        #if os(iOS)
        .fullScreenCover(isPresented: evolutionBinding) {
            evolutionContent
        }
        #else
        .sheet(isPresented: evolutionBinding) {
            evolutionContent
        }
        #endif
    }

    // MARK: - Evolution Helpers

    private var evolutionBinding: Binding<Bool> {
        .constant(appState.showEvolutionAnimation)
    }

    @ViewBuilder
    private var evolutionContent: some View {
        if let fromStage = appState.evolutionFromStage,
           let toStage = appState.evolutionToStage {
            EvolutionAnimationView(
                fromStage: fromStage,
                toStage: toStage,
                onComplete: {
                    appState.completeEvolution()
                }
            )
            .environment(appState)
            .environment(theme)
        }
    }

    // MARK: - Task Filters

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var todayTasks: [TaskItem] {
        appState.tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return Calendar.current.isDate(dueDate, inSameDayAs: today)
        }
    }

    private var upcomingTasks: [TaskItem] {
        appState.tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate > today && !Calendar.current.isDate(dueDate, inSameDayAs: today)
        }
    }

    private var noDueDateTasks: [TaskItem] {
        appState.tasks.filter { $0.dueDate == nil }
    }
}

// MARK: - Pet Illustration Section

private struct PetIllustrationSection: View {
    let onTap: () -> Void
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var breathingOffset: CGFloat = 0
    @State private var particleOffsets: [CGFloat] = [0, 0, 0]

    var body: some View {
        Button(action: onTap) {
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

                        // Pet image
                        Image(petImageName, bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 320, height: 320)
                            .offset(y: breathingOffset)
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
        .onAppear {
            withAnimation(
                .easeInOut(duration: 3)
                .repeatForever(autoreverses: true)
            ) {
                breathingOffset = -8
            }
            
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
    }

    private var petImageName: String {
        appState.pet.currentForm.imageName
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
                    TaskItemRow(task: task)
                        .opacity(appeared ? 1 : 0)
                        .offset(x: appeared ? 0 : -20)
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(delay + Double(index) * 0.1),
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
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

                // Task title
                Text(task.title)
                    .font(.system(size: 15))
                    .foregroundStyle(task.isCompleted ? theme.colors.secondaryText : theme.colors.primaryText)
                    .strikethrough(task.isCompleted, color: theme.colors.secondaryText)
                    .lineLimit(1)

                Spacer()

                // Tag
                Text("#My Tasks")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.primary.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.colors.primary.opacity(0.1))
                    .clipShape(Capsule())

                // Due date label
                if let dueDate = task.dueDate {
                    Text(formatDueDate(dueDate))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: "8B5A2B"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(hex: "FDE68A").opacity(0.3)) // Soft pastel yellow
                        .clipShape(Capsule())
                }

                // More menu
                Menu {
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
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
        .opacity(task.isCompleted ? 0.6 : 1.0)
        .sheet(isPresented: $showEditSheet) {
            TaskEditSheet(task: task)
                .environment(appState)
                .environment(theme)
        }
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInTomorrow(date) { return "tomorrow" }
        return dueDateFormatter.string(from: date)
    }
}

// Custom Row Button Style for scale effect
private struct RowScaleButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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
