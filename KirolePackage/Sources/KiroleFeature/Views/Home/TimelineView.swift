import SwiftUI

// MARK: - Timeline Content View

struct TimelineContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Date separator
            DateDividerView(date: appState.selectedDate)
                .padding(.top, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(.easeOut(duration: 0.5).delay(0.2), value: appeared)

            // Timeline
            TimelineView()
                .padding(.horizontal, 24)

            // Next day section
            DateDividerView(date: Calendar.current.date(byAdding: .day, value: 1, to: appState.selectedDate) ?? appState.selectedDate)
                .padding(.top, 32)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(0.8), value: appeared)

            // Second timeline with haiku
            TimelineWithHaikuView()
                .padding(.horizontal, 24)

            Spacer()
                .frame(height: 80)
        }
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Date Divider View

struct DateDividerView: View {
    let date: Date
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(theme.colors.accent)
                .frame(height: 4)
                .clipShape(Capsule())

            Text(formattedDate)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.colors.accent)

            Rectangle()
                .fill(theme.colors.accent)
                .frame(height: 4)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 24)
    }

    private var formattedDate: String {
        AppDateFormatters.separatorDate.string(from: date)
    }
}

// MARK: - Timeline View

struct TimelineView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    private var filteredEvents: [CalendarEvent] {
        let calendar = Calendar.current
        return appState.events
            .filter { calendar.isDate($0.startTime, inSameDayAs: appState.selectedDate) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sunrise
            TimelineEventRow(
                time: AppDateFormatters.time.string(from: appState.sunTimes.sunrise),
                icon: "sunrise.fill",
                title: "Sunrise",
                delay: 0.3,
                isSystemIcon: true
            )

            // Day Start
            TimelineEventRow(
                time: "9:00 AM",
                icon: "sun.max.fill",
                title: "Day Start",
                delay: 0.4,
                isSystemIcon: true
            )

            // Dynamic Events
            if filteredEvents.isEmpty {
                TimelineEmptyStateRow(delay: 0.5)
            } else {
                ForEach(Array(filteredEvents.enumerated()), id: \.element.id) { index, event in
                    TimelineEventCardRow(event: event, delay: 0.5 + Double(index) * 0.1)
                }
            }

            // Sunset
            TimelineEventRow(
                time: AppDateFormatters.time.string(from: appState.sunTimes.sunset),
                icon: "sunset.fill",
                title: "Sunset",
                delay: 0.6 + Double(max(filteredEvents.count, 1)) * 0.1,
                isSystemIcon: true
            )
        }
        .background(
            // Vertical timeline line
            HStack {
                Spacer()
                    .frame(width: 64)
                Rectangle()
                    .fill(Color(hex: "D1D5DB"))
                    .frame(width: 2)
                Spacer()
            }
        )
    }
}

// MARK: - Timeline Empty State Row

struct TimelineEmptyStateRow: View {
    let delay: Double

    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 80)

            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 32))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.5))

                Text("No events today")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)

                Text("Connect your calendar to see events")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Timeline Event Card Row

struct TimelineEventCardRow: View {
    let event: CalendarEvent
    let delay: Double

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Time header
            HStack {
                Text(AppDateFormatters.time.string(from: event.startTime))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 64, alignment: .leading)

                Spacer()
            }
            .padding(.top, 8)

            // Event card
            HStack(spacing: 0) {
                Spacer()
                    .frame(width: 80)

                EventCardView(
                    title: event.title,
                    duration: event.durationText,
                    participants: event.participants.count,
                    description: event.description ?? "",
                    source: event.source,
                    onTap: {
                        appState.selectEvent(event)
                    }
                )
            }
            .padding(.vertical, 8)
        }
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -30)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Timeline Event Row

struct TimelineEventRow: View {
    let time: String
    let icon: String
    let title: String
    let delay: Double
    var isSystemIcon: Bool = false

    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 16) {
            // Time
            Text(time)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: 64, alignment: .leading)

            // Icon circle
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                if isSystemIcon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.accent)
                } else {
                    Text(icon)
                        .font(.system(size: 18))
                }
            }

            // Title
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Spacer()
        }
        .padding(.vertical, 16)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -30)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Timeline With Haiku View

struct TimelineWithHaikuView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    private var tomorrowSunTimes: SunTimes {
        .default
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sunrise
            TimelineEventRow(
                time: AppDateFormatters.time.string(from: tomorrowSunTimes.sunrise),
                icon: "sunrise.fill",
                title: "Sunrise",
                delay: 0.9,
                isSystemIcon: true
            )

            // Haiku and Image
            HaikuSectionView(delay: 1.0)

            // Sunset
            TimelineEventRow(
                time: AppDateFormatters.time.string(from: tomorrowSunTimes.sunset),
                icon: "sunset.fill",
                title: "Sunset",
                delay: 1.1,
                isSystemIcon: true
            )
        }
        .background(
            // Vertical timeline line
            HStack {
                Spacer()
                    .frame(width: 64)
                Rectangle()
                    .fill(Color(hex: "D1D5DB"))
                    .frame(width: 2)
                Spacer()
            }
        )
    }
}

// MARK: - Haiku Section View

struct HaikuSectionView: View {
    let delay: Double

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false
    @State private var isRefreshing = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 80)

            VStack(spacing: 24) {
                // Haiku text from AppState
                VStack(spacing: 4) {
                    ForEach(Array(appState.currentHaiku.lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(theme.colors.primaryText)
                            .opacity(isRefreshing ? 0.5 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: isRefreshing)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                // Refresh button
                Button {
                    refreshHaiku()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)

                        Text("New Haiku")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.colors.cardBackground)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)

                // Pet image
                Image("tiko_reading", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            }
            .padding(.vertical, 24)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
    }

    private func refreshHaiku() {
        isRefreshing = true
        Task { @MainActor in
            await appState.loadTodayHaiku()
            isRefreshing = false
        }
    }
}

#Preview {
    ScrollView {
        TimelineContentView()
    }
    .background(Color(hex: "f5f1e8"))
    .environment(AppState.shared)
    .environment(ThemeManager.shared)
}
