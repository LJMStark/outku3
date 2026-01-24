import SwiftUI

// MARK: - Pet Page View

struct PetPageView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var selectedCategory: TaskCategory = .today
    @State private var showPetStatus = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: AppSpacing.xl) {
                // Pet display area
                PetDisplaySection(showPetStatus: $showPetStatus)

                // Task categories
                TaskCategoryPicker(selectedCategory: $selectedCategory)

                // Task list
                TaskListSection(category: selectedCategory)

                // Bottom spacing for tab bar
                Spacer()
                    .frame(height: 100)
            }
            .padding(.top, AppSpacing.lg)
        }
        .background(theme.colors.background)
        .sheet(isPresented: $showPetStatus) {
            PetStatusView()
                .environment(appState)
                .environment(theme)
        }
    }
}

// MARK: - Pet Display Section

struct PetDisplaySection: View {
    @Binding var showPetStatus: Bool
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Pet name and info button
            HStack {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(appState.pet.name)
                        .font(AppTypography.title2)
                        .foregroundStyle(theme.colors.primaryText)

                    Text("\(appState.pet.adventuresCount) adventures")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(theme.colors.secondaryText)
                }

                Spacer()

                Button {
                    showPetStatus = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.colors.accent)
                }
            }
            .padding(.horizontal, AppSpacing.xl)

            // Pet illustration
            Button {
                showPetStatus = true
            } label: {
                PixelPetView(size: .large, animated: true)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: AppCornerRadius.large)
                            .fill(theme.colors.cardBackground)
                            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                    }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.xl)

            // Streak indicator
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.streakActive)

                Text("\(appState.streak.currentStreak) day streak")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(theme.colors.primaryText)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background {
                Capsule()
                    .fill(theme.colors.streakActive.opacity(0.15))
            }
        }
    }
}

// MARK: - Task Category Picker

struct TaskCategoryPicker: View {
    @Binding var selectedCategory: TaskCategory
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(TaskCategory.allCases) { category in
                CategoryButton(
                    category: category,
                    isSelected: selectedCategory == category,
                    action: { selectedCategory = category }
                )
            }
        }
        .padding(.horizontal, AppSpacing.xl)
    }
}

struct CategoryButton: View {
    let category: TaskCategory
    let isSelected: Bool
    let action: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            Text(category.rawValue)
                .font(AppTypography.subheadline)
                .foregroundStyle(isSelected ? .white : theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background {
                    Capsule()
                        .fill(isSelected ? theme.colors.accent : theme.colors.cardBackground)
                }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Task List Section

struct TaskListSection: View {
    let category: TaskCategory
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    private var filteredTasks: [TaskItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        switch category {
        case .today:
            return appState.tasks.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: today)
            }
        case .upcoming:
            return appState.tasks.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return dueDate > today && !calendar.isDate(dueDate, inSameDayAs: today)
            }
        case .noDueDate:
            return appState.tasks.filter { $0.dueDate == nil }
        }
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            if filteredTasks.isEmpty {
                EmptyTasksView(category: category)
            } else {
                ForEach(filteredTasks) { task in
                    TaskRowView(task: task)
                }
            }
        }
        .padding(.horizontal, AppSpacing.xl)
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    let task: TaskItem
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            // Checkbox
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    appState.toggleTaskCompletion(task)
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(task.isCompleted ? theme.colors.taskComplete : theme.colors.secondaryText.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if task.isCompleted {
                        Circle()
                            .fill(theme.colors.taskComplete)
                            .frame(width: 24, height: 24)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            // Task info
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(task.title)
                    .font(AppTypography.body)
                    .foregroundStyle(task.isCompleted ? theme.colors.secondaryText : theme.colors.primaryText)
                    .strikethrough(task.isCompleted)

                HStack(spacing: AppSpacing.sm) {
                    // Source
                    Image(systemName: task.source.iconName)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.colors.secondaryText)

                    // Priority indicator
                    Circle()
                        .fill(Color(hex: task.priority.color))
                        .frame(width: 6, height: 6)

                    // Due date if exists
                    if let dueDate = task.dueDate {
                        Text(formatDueDate(dueDate))
                            .font(AppTypography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
            }

            Spacer()
        }
        .padding(AppSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(theme.colors.cardBackground)
                .shadow(color: .black.opacity(0.03), radius: 4, x: 0, y: 2)
        }
        .opacity(task.isCompleted ? 0.7 : 1)
    }

    private func formatDueDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Empty Tasks View

struct EmptyTasksView: View {
    let category: TaskCategory
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.5))

            Text(emptyMessage)
                .font(AppTypography.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.xxxl)
    }

    private var emptyMessage: String {
        switch category {
        case .today:
            return "No tasks for today.\nEnjoy your free time!"
        case .upcoming:
            return "No upcoming tasks.\nYou're all caught up!"
        case .noDueDate:
            return "No tasks without due dates."
        }
    }
}

#Preview {
    PetPageView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
