import SwiftUI

// MARK: - Pet Status View

struct PetStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppSpacing.xxl) {
                    // Pet display
                    PetStatusHeaderView()

                    // Progress section
                    PetStatsSection()

                    // Physical stats
                    PhysicalStatsSection()

                    // Streak section
                    StreakSection()

                    // Task statistics
                    TaskStatisticsSection()

                    // Feed button
                    FeedPetButton()
                        .padding(.horizontal, AppSpacing.xl)

                    Spacer()
                        .frame(height: AppSpacing.xxl)
                }
                .padding(.top, AppSpacing.lg)
            }
            .background(theme.colors.background)
            .navigationTitle("Pet Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
            }
        }
    }
}

// MARK: - Feed Pet Button

struct FeedPetButton: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var isFeeding = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isFeeding = true
            }
            // 模拟喂食效果
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isFeeding = false
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: isFeeding ? "heart.fill" : "leaf.fill")
                    .font(.system(size: 18))

                Text("Feed \(appState.pet.name)")
                    .font(AppTypography.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .fill(theme.colors.accent)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isFeeding ? 0.95 : 1.0)
    }
}

// MARK: - Pet Status Header

struct PetStatusHeaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Pet illustration
            PixelPetView(size: .large, animated: true)
                .frame(height: 180)
                .frame(maxWidth: .infinity)
                .background {
                    RoundedRectangle(cornerRadius: AppCornerRadius.large)
                        .fill(theme.colors.cardBackground)
                }
                .padding(.horizontal, AppSpacing.xl)

            // Name and pronouns
            VStack(spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.sm) {
                    Text(appState.pet.name)
                        .font(AppTypography.title)
                        .foregroundStyle(theme.colors.primaryText)

                    Text("(\(appState.pet.pronouns.rawValue.lowercased()))")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(theme.colors.secondaryText)
                }

                // Adventures and age
                HStack(spacing: AppSpacing.lg) {
                    Label("\(appState.pet.adventuresCount) adventures", systemImage: "star.fill")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.colors.secondaryText)

                    Label("\(appState.pet.age) days old", systemImage: "calendar")
                        .font(AppTypography.caption)
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }

            // Status and Mood badges
            HStack(spacing: AppSpacing.md) {
                StatusBadge(
                    icon: "face.smiling.fill",
                    label: "Status",
                    value: appState.pet.status.rawValue
                )

                StatusBadge(
                    icon: "heart.fill",
                    label: "Mood",
                    value: appState.pet.mood.rawValue
                )
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let icon: String
    let label: String
    let value: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.colors.secondaryText)

                Text(value)
                    .font(AppTypography.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(theme.colors.primaryText)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
        .background {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(theme.colors.cardBackground)
        }
    }
}

// MARK: - Pet Stats Section

struct PetStatsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Progress to Next Stage")
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

            // Progress card
            VStack(spacing: AppSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text("Current: \(appState.pet.stage.rawValue)")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(theme.colors.secondaryText)

                        if let nextStage = appState.pet.stage.nextStage {
                            Text("Next: \(nextStage.rawValue)")
                                .font(AppTypography.subheadline)
                                .foregroundStyle(theme.colors.accent)
                        }
                    }

                    Spacer()

                    Text("\(Int(appState.pet.progress * 100))%")
                        .font(AppTypography.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(theme.colors.accent)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.colors.timeline)
                            .frame(height: 12)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.colors.accent)
                            .frame(width: geometry.size.width * appState.pet.progress, height: 12)
                    }
                }
                .frame(height: 12)
            }
            .padding(AppSpacing.xl)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .fill(theme.colors.cardBackground)
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }
}

// MARK: - Physical Stats Section

struct PhysicalStatsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Physical Stats")
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

            HStack(spacing: AppSpacing.md) {
                PhysicalStatCard(
                    icon: "scalemass.fill",
                    label: "Weight",
                    value: String(format: "%.1fg", appState.pet.weight)
                )

                PhysicalStatCard(
                    icon: "ruler.fill",
                    label: "Height",
                    value: String(format: "%.1fcm", appState.pet.height)
                )

                PhysicalStatCard(
                    icon: "wind",
                    label: "Tail",
                    value: String(format: "%.1fcm", appState.pet.tailLength)
                )
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }
}

struct PhysicalStatCard: View {
    let icon: String
    let label: String
    let value: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(theme.colors.accent)

            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(theme.colors.secondaryText)

            Text(value)
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(theme.colors.cardBackground)
        }
    }
}

// MARK: - Streak Section

struct StreakSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Streak")
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

            HStack(spacing: AppSpacing.lg) {
                // Flame icon
                ZStack {
                    Circle()
                        .fill(theme.colors.streakActive.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: "flame.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.colors.streakActive)
                }

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("\(appState.streak.currentStreak)")
                        .font(AppTypography.largeTitle)
                        .foregroundStyle(theme.colors.primaryText)

                    Text("day streak")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(theme.colors.secondaryText)
                }

                Spacer()

                // Streak days visualization
                HStack(spacing: AppSpacing.xs) {
                    ForEach(0..<7, id: \.self) { index in
                        Circle()
                            .fill(index < appState.streak.currentStreak ? theme.colors.streakActive : theme.colors.timeline)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(AppSpacing.xl)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .fill(theme.colors.cardBackground)
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }
}

// MARK: - Task Statistics Section

struct TaskStatisticsSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Task Statistics")
                .font(AppTypography.headline)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.xl)

            VStack(spacing: AppSpacing.md) {
                TaskStatRow(
                    label: "Today",
                    completed: appState.statistics.todayCompleted,
                    total: appState.statistics.todayTotal,
                    percentage: appState.statistics.todayPercentage
                )

                TaskStatRow(
                    label: "Past Week",
                    completed: appState.statistics.pastWeekCompleted,
                    total: appState.statistics.pastWeekTotal,
                    percentage: appState.statistics.pastWeekPercentage
                )

                TaskStatRow(
                    label: "Last 30 Days",
                    completed: appState.statistics.last30DaysCompleted,
                    total: appState.statistics.last30DaysTotal,
                    percentage: appState.statistics.last30DaysPercentage
                )
            }
            .padding(.horizontal, AppSpacing.xl)
        }
    }
}

struct TaskStatRow: View {
    let label: String
    let completed: Int
    let total: Int
    let percentage: Double
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text(label)
                    .font(AppTypography.body)
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                Text("\(completed)/\(total)")
                    .font(AppTypography.subheadline)
                    .foregroundStyle(theme.colors.secondaryText)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.colors.timeline)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.colors.taskComplete)
                        .frame(width: geometry.size.width * percentage, height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(AppSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(theme.colors.cardBackground)
        }
    }
}

// MARK: - Stat Row View

struct StatRowView: View {
    let icon: String
    let label: String
    let value: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 24)

            Text(label)
                .font(AppTypography.body)
                .foregroundStyle(theme.colors.primaryText)

            Spacer()

            Text(value)
                .font(AppTypography.subheadline)
                .foregroundStyle(theme.colors.secondaryText)
        }
        .padding(AppSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                .fill(theme.colors.cardBackground)
        }
    }
}

#Preview {
    PetStatusView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
