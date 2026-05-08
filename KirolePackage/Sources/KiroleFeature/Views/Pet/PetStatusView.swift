import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

    private var viewportWidth: CGFloat? {
        #if canImport(UIKit)
        return UIScreen.main.bounds.width
        #else
        return nil
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 24) {
                    // Pet Status Card — scale-in entrance; the two sibling
                    // cards below use offset-in, so these are hand-rolled
                    // rather than sharing one modifier.
                    PetStatusCard()
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.9)
                        .animation(.kiroleGentle, value: appeared)

                    // Tasks Statistics
                    TasksStatisticsCard()
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 30)
                        .animation(.kiroleGentle.delay(0.5), value: appeared)

                    Spacer()
                        .frame(height: 80)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .frame(width: viewportWidth)
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
                    .accessibilityLabel("关闭")
                    .accessibilityIdentifier("PetStatus_Close")
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

                            Image(appState.userProfile.companionCharacter.heroAssetName(variant: .main), bundle: .module)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 150)
                        }
                        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

                        // Pet Info Text
                        VStack(alignment: .leading, spacing: 6) {
                            Text(appState.pet.name)
                                .font(.system(size: 22, weight: .bold, design: .serif))
                                .foregroundStyle(Color(hex: "1F3A2C"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("\(appState.pet.pronouns.rawValue) • \(appState.pet.adventuresCount) Adventures")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.colors.secondaryText)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
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
                        StatRowNew(label: "STATUS", value: appState.pet.status.rawValue, icon: "globe")
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

// MARK: - Tasks Statistics Card

private struct TasksStatisticsCard: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    @State private var pastWeekFocusTimeFormatted: String = "—"
    @State private var last30DaysFocusTimeFormatted: String = "—"

    private var todayFocusTimeFormatted: String {
        formatFocusTime(FocusSessionService.shared.statistics.todayFocusTime)
    }

    private func formatFocusTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "—"
    }

    private func sumFocusTime(forPastDays count: Int) async -> TimeInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var total: TimeInterval = 0
        for offset in 1...count {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return total }
            let sessions = (try? await LocalStorage.shared.loadFocusSessionsForDate(date)) ?? []
            total += sessions.compactMap(\.calculatedFocusTime).reduce(0, +)
        }
        return total
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

                TaskStatSection(title: "PAST WEEK", tasks: appState.statistics.pastWeekCompleted, focusTime: pastWeekFocusTimeFormatted, delay: 0.2)

                Divider()
                    .padding(.vertical, 16)

                TaskStatSection(title: "LAST 30 DAYS", tasks: appState.statistics.last30DaysCompleted, focusTime: last30DaysFocusTimeFormatted, delay: 0.3)
            }
            .padding(24)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(hex: "1F2937").opacity(0.8), lineWidth: 1)
            )
        }
        .task {
            async let pastWeekFocusTime = sumFocusTime(forPastDays: 7)
            async let last30DaysFocusTime = sumFocusTime(forPastDays: 30)

            pastWeekFocusTimeFormatted = await formatFocusTime(pastWeekFocusTime)
            last30DaysFocusTimeFormatted = await formatFocusTime(last30DaysFocusTime)
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

            HStack(spacing: 0) {
                // Tasks Column
                HStack(spacing: 8) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("Tasks")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.colors.secondaryText)

                    Spacer()

                    Text("\(tasks)")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "1F2937"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 24)

                // Focus Time Column
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.secondaryText)

                    Text("Focus Time")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.colors.secondaryText)

                    Spacer()

                    Text(focusTime)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color(hex: "1F2937"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -20)
        .animation(.kiroleGentle.delay(delay), value: appeared)
        .onAppear { appeared = true }
    }
}

#Preview {
    PetStatusView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
