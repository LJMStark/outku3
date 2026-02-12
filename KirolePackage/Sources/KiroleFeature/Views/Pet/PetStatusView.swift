import SwiftUI

// MARK: - Pet Status View

struct PetStatusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Pet Status Card
                    PetStatusCard()
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.9)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: appeared)

                    // Achievement Card
                    AchievementCard()
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 30)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: appeared)

                    // Tasks Statistics
                    TasksStatisticsCard()
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 30)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5), value: appeared)

                    Spacer()
                        .frame(height: 80)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .background(theme.colors.background)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
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
        .onAppear { appeared = true }
    }
}

// MARK: - Pet Status Card

private struct PetStatusCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var progressAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Green status indicator
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.colors.accent)
                .frame(width: 48, height: 12)
                .padding(.top, 16)

            // Pet info row
            HStack(alignment: .top, spacing: 20) {
                // Pet Avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(theme.currentTheme.cardGradient)
                        .frame(width: 128, height: 128)

                    Image("tiko_avatar", bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                }
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

                // Pet Info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baby Waffle")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(theme.colors.primaryText)

                    Text("He/Him • 3 Adventures")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.secondaryText)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Decorative circle
            Circle()
                .stroke(theme.colors.background, lineWidth: 8)
                .frame(width: 96, height: 96)
                .opacity(0.5)
                .offset(x: 100, y: -80)

            // Divider
            Rectangle()
                .fill(Color(hex: "E5E7EB"))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.top, -40)

            // Stats Grid
            VStack(spacing: 12) {
                StatRow(label: "Age", value: "29 days")
                StatRow(label: "Status", value: "Exploring", emoji: "🧭")
                StatRow(label: "Stage", value: "Newborn")
                ProgressRow(progress: 0.3)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Divider
            Rectangle()
                .fill(Color(hex: "E5E7EB"))
                .frame(height: 1)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            // Pet Measurements
            HStack(spacing: 24) {
                MeasurementItem(emoji: "⚖️", value: "4.9g")
                MeasurementItem(emoji: "📏", value: "1.6cm")
                MeasurementItem(emoji: "🦋", value: "4.1cm")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
    }
}

// MARK: - Stat Row

private struct StatRow: View {
    let label: String
    let value: String
    var emoji: String? = nil
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)

                if let emoji = emoji {
                    Text(emoji)
                        .font(.system(size: 18))
                }
            }
        }
    }
}

// MARK: - Progress Row

private struct ProgressRow: View {
    let progress: Double
    @Environment(ThemeManager.self) private var theme
    @State private var animatedProgress = false

    var body: some View {
        HStack {
            Text("Progress Bar")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    Circle()
                        .fill(Double(index) / 10.0 < progress ? theme.colors.primaryText : Color(hex: "E5E7EB"))
                        .frame(width: 12, height: 12)
                        .scaleEffect(animatedProgress ? 1 : 0)
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.6)
                            .delay(0.6 + Double(index) * 0.05),
                            value: animatedProgress
                        )
                }

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                    .padding(.leading, 8)
            }
        }
        .onAppear { animatedProgress = true }
    }
}

// MARK: - Measurement Item

private struct MeasurementItem: View {
    let emoji: String
    let value: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 24, height: 24)

                Text(emoji)
                    .font(.system(size: 14))
            }

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.primaryText)
        }
    }
}

// MARK: - Achievement Card

private struct AchievementCard: View {
    @Environment(ThemeManager.self) private var theme
    @State private var iconRotated = false

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "e8c17f"), Color(hex: "d4a660")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                Text("✓")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(iconRotated ? 10 : -10))
            }
            .task {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeInOut(duration: 0.5)) { iconRotated = true }
                try? await Task.sleep(for: .seconds(0.5))
                withAnimation(.easeInOut(duration: 0.5)) { iconRotated = false }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("7 day streak")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(theme.colors.primaryText)

                Text("Longest self-care streak ever!")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Spacer()
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(theme.colors.primary.opacity(0.2), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
    }
}

// MARK: - Tasks Statistics Card

private struct TasksStatisticsCard: View {
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tasks Today")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)

            VStack(spacing: 24) {
                TaskStatSection(title: "Today", tasks: 5, focusTime: "7h 11m", delay: 0.1)
                TaskStatSection(title: "Past Week", tasks: 5, focusTime: "7h 11m", delay: 0.2)
                TaskStatSection(title: "Last 30 Days", tasks: 5, focusTime: "7h 11m", delay: 0.3)
            }
            .padding(24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.1), radius: 12, y: 4)
        }
    }
}

// MARK: - Task Stat Section

private struct TaskStatSection: View {
    let title: String
    let tasks: Int
    let focusTime: String
    let delay: Double

    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.colors.secondaryText)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack {
                // Tasks
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("Tasks")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.primaryText)

                    Text("\(tasks)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.colors.primaryText)
                }

                Spacer()

                // Focus Time
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("Focus Time")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.primaryText)

                    Text(focusTime)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.colors.primaryText)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -20)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: appeared)
        .onAppear { appeared = true }
    }
}

#Preview {
    PetStatusView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
