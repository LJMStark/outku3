import SwiftUI

// MARK: - Postmark Stamp Decoration
private struct StampDecoration: View {
    var body: some View {
        ZStack {
            // Wavy lines representation
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(Color(hex: "E8D9C8").opacity(0.6))
                        .frame(width: 140, height: 2)
                }
            }
            .rotationEffect(.degrees(-15))
            .offset(x: 20, y: 0)
            
            // Dashed Circles
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .fill(Color(hex: "E8D9C8").opacity(0.6))
                    .frame(width: 100 + CGFloat(i)*40, height: 100 + CGFloat(i)*40)
            }
        }
    }
}

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

    var body: some View {
        VStack(spacing: 0) {
            // Green status indicator hook at top
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(hex: "4A6B53"))
                .frame(width: 48, height: 16)
                .padding(.top, -8)
                .zIndex(1)
            
            ZStack(alignment: .topTrailing) {
                // Postmark Stamp Background
                StampDecoration()
                    .offset(x: 40, y: -20)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                VStack(spacing: 0) {
                    // Pet info row
                    HStack(alignment: .top, spacing: 20) {
                        // Pet Avatar Container
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(hex: "E6F4EA")) // Pale green
                                .frame(width: 128, height: 160)

                            Image("tiko_avatar", bundle: .module)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 150)
                        }
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

                        // Pet Info Text
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appState.pet.name)
                                .font(.system(size: 26, weight: .bold, design: .serif))
                                .foregroundStyle(Color(hex: "1F3A2C"))

                            Text("\(appState.pet.pronouns.rawValue) • \(appState.pet.adventuresCount) Adventures")
                                .font(.system(size: 15))
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                        .padding(.top, 20)

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    // Line Divider
                    Rectangle()
                        .fill(Color(hex: "E5E7EB"))
                        .frame(height: 1)
                        .padding(.leading, 172)
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                    // Stats Grid Layout
                    VStack(alignment: .leading, spacing: 16) {
                        StatRowNew(label: "AGE", value: "\(appState.pet.age) days")
                        StatRowNew(label: "STATUS", value: appState.pet.status.rawValue, icon: "safari.fill")
                        StatRowNew(label: "STAGE", value: appState.pet.stage.rawValue)
                        ProgressRowNew(progress: appState.pet.progress)
                    }
                    .padding(.horizontal, 24)

                    // Divider
                    Rectangle()
                        .fill(Color(hex: "E5E7EB"))
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    // Pet Measurements
                    HStack(spacing: 32) {
                        MeasurementItem(icon: "scalemass", value: String(format: "%.1fg", appState.pet.weight))
                        MeasurementItem(icon: "arrow.up.and.down", value: String(format: "%.1fcm", appState.pet.height))
                        MeasurementItem(emoji: "🦋", value: String(format: "%.1fcm", appState.pet.tailLength))
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .padding(.top, 8)
    }
}

// MARK: - Stat Row New

private struct StatRowNew: View {
    let label: String
    let value: String
    var icon: String? = nil
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: 140, alignment: .leading)

            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "1F2937"))

                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "BFA573"))
                }
            }
            Spacer()
        }
    }
}

// MARK: - Progress Row New

private struct ProgressRowNew: View {
    let progress: Double
    @Environment(ThemeManager.self) private var theme
    @State private var animatedProgress = false

    var body: some View {
        HStack(spacing: 0) {
            Text("PROGRESS BAR")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: 140, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(0..<10, id: \.self) { index in
                    let isFilled = Double(index) / 10.0 < progress
                    Circle()
                        .fill(isFilled ? Color(hex: "4A6B53") : Color(hex: "C8E6C9"))
                        .frame(width: 10, height: 10)
                        .scaleEffect(animatedProgress ? 1 : 0)
                        .animation(
                            .spring(response: 0.3, dampingFraction: 0.6)
                            .delay(0.2 + Double(index) * 0.05),
                            value: animatedProgress
                        )
                }

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(hex: "1F2937"))
                    .padding(.leading, 8)
            }
            Spacer()
        }
        .onAppear { animatedProgress = true }
    }
}

// MARK: - Measurement Item

private struct MeasurementItem: View {
    var icon: String? = nil
    var emoji: String? = nil
    let value: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.colors.secondaryText)
            } else if let emoji = emoji {
                Text(emoji)
                    .font(.system(size: 16))
                    .grayscale(1.0)
            }

            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}

// MARK: - Achievement Card

private struct AchievementCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var iconRotated = false

    private var streakSubtitle: String {
        let streak = appState.streak
        if streak.currentStreak > 0 && streak.currentStreak >= streak.longestStreak {
            return "Longest self-care streak ever!"
        }
        return "Best: \(streak.longestStreak) days"
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)
                .foregroundStyle(Color(hex: "C48B44"))
                .background(Circle().fill(Color.white).frame(width: 24, height: 24))
                .rotationEffect(.degrees(iconRotated ? 10 : -10))
                .task {
                    try? await Task.sleep(for: .seconds(1.2))
                    withAnimation(.easeInOut(duration: 0.5)) { iconRotated = true }
                    try? await Task.sleep(for: .seconds(0.5))
                    withAnimation(.easeInOut(duration: 0.5)) { iconRotated = false }
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(appState.streak.currentStreak)")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Color(hex: "1F2937"))
                    Text("day streak")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(hex: "1F2937"))
                }

                Text(streakSubtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.colors.secondaryText)
            }

            Spacer()
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color(hex: "1F2937").opacity(0.8), lineWidth: 1)
        )
    }
}

// MARK: - Tasks Statistics Card

private struct TasksStatisticsCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    private var todayFocusTimeFormatted: String {
        let totalSeconds = FocusSessionService.shared.statistics.todayFocusTime
        let hours = Int(totalSeconds) / 3600
        let minutes = (Int(totalSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tasks Today")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(Color(hex: "1F3A2C"))

            VStack(spacing: 0) {
                TaskStatSection(title: "TODAY", tasks: appState.statistics.todayCompleted, focusTime: todayFocusTimeFormatted, delay: 0.1)
                
                Divider()
                    .padding(.vertical, 16)
                
                TaskStatSection(title: "PAST WEEK", tasks: appState.statistics.pastWeekCompleted, focusTime: "7h 11m", delay: 0.2) // Simulated for demo layout matching
                
                Divider()
                    .padding(.vertical, 16)
                
                TaskStatSection(title: "LAST 30 DAYS", tasks: appState.statistics.last30DaysCompleted, focusTime: "7h 11m", delay: 0.3)
            }
            .padding(24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "1F2937").opacity(0.8), lineWidth: 1)
            )
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
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.colors.secondaryText)
                .tracking(0.5)

            HStack {
                // Tasks Count
                HStack(spacing: 8) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("Tasks")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("\(tasks)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "1F2937"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Focus Time
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("Focus Time")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text(focusTime)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "1F2937"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
