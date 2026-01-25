import SwiftUI

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
    }

    private var todayTasks: [TaskItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return appState.tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: today)
        }
    }

    private var upcomingTasks: [TaskItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return appState.tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate > today && !calendar.isDate(dueDate, inSameDayAs: today)
        }
    }

    private var noDueDateTasks: [TaskItem] {
        appState.tasks.filter { $0.dueDate == nil }
    }
}

// MARK: - Pet Illustration Section

private struct PetIllustrationSection: View {
    let onTap: () -> Void
    @Environment(ThemeManager.self) private var theme
    @State private var breathingOffset: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [
                        theme.colors.background,
                        theme.colors.accentLight.opacity(0.5),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Pet image placeholder
                VStack {
                    Spacer()

                    ZStack {
                        // Ground shadow
                        Ellipse()
                            .fill(Color.black.opacity(0.1))
                            .frame(width: 120, height: 30)
                            .offset(y: 60)

                        // Pet image
                        Image("tiko_mushroom", bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 320, height: 320)
                            .offset(y: breathingOffset)
                    }

                    Spacer()
                        .frame(height: 40)
                }
            }
            .frame(height: 340)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 3)
                .repeatForever(autoreverses: true)
            ) {
                breathingOffset = -8
            }
        }
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
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)

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
    @State private var isPressed = false

    var body: some View {
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

            Spacer()

            // Tag
            Text("#My Tasks")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)

            // Due date label
            if let dueDate = task.dueDate {
                Text(formatDueDate(dueDate))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.primaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(hex: "E5E7EB"))
                    .clipShape(Capsule())
            }

            // More button
            Button {
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "3B82F6"))
                    .rotationEffect(.degrees(90))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "F3F4F6"), lineWidth: 1)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "today"
        } else if calendar.isDateInTomorrow(date) {
            return "tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Empty Task Placeholder

private struct EmptyTaskPlaceholder: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(hex: "D1D5DB"), lineWidth: 2)
                .frame(width: 24, height: 24)

            Text("No tasks")
                .font(.system(size: 15))
                .foregroundStyle(theme.colors.secondaryText)

            Spacer()
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

#Preview {
    PetPageView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
