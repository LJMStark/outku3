import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Header
                HomeHeaderView()

                // Timeline
                TimelineView()

                // Bottom spacing for tab bar
                Spacer()
                    .frame(height: 100)
            }
        }
        .background(theme.colors.background)
    }
}

// MARK: - Home Header

struct HomeHeaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            // Top row: Date and Weather
            HStack {
                // Date
                Text(dateFormatter.string(from: appState.selectedDate))
                    .font(AppTypography.title2)
                    .foregroundStyle(theme.colors.primaryText)

                Spacer()

                // Weather
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: appState.weather.condition.rawValue)
                        .font(.system(size: 16))
                        .foregroundStyle(theme.colors.accent)

                    Text("\(appState.weather.temperature)°")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(theme.colors.primaryText)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background {
                    Capsule()
                        .fill(theme.colors.cardBackground)
                }
            }

            // Time and timezone
            HStack {
                Text(timeFormatter.string(from: Date()))
                    .font(AppTypography.timeDisplay)
                    .foregroundStyle(theme.colors.secondaryText)

                Text("GMT")
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.7))

                Spacer()
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.top, AppSpacing.lg)
        .padding(.bottom, AppSpacing.md)
    }
}

// MARK: - Timeline View

struct TimelineView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    private let hourHeight: CGFloat = 60
    private let startHour: Int = 6
    private let endHour: Int = 22

    var body: some View {
        VStack(spacing: 0) {
            // Timeline content
            HStack(alignment: .top, spacing: AppSpacing.md) {
                // Time labels column
                VStack(spacing: 0) {
                    ForEach(startHour...endHour, id: \.self) { hour in
                        Text(formatHour(hour))
                            .font(AppTypography.caption)
                            .foregroundStyle(theme.colors.secondaryText)
                            .frame(height: hourHeight, alignment: .top)
                            .frame(width: 50, alignment: .trailing)
                    }
                }

                // Timeline and events
                ZStack(alignment: .topLeading) {
                    // Timeline line
                    TimelineLineView(
                        hourHeight: hourHeight,
                        totalHours: endHour - startHour,
                        sunTimes: appState.sunTimes,
                        startHour: startHour
                    )

                    // Events
                    ForEach(appState.events) { event in
                        EventCardView(event: event)
                            .offset(y: offsetForTime(event.startTime))
                            .frame(height: heightForDuration(event.duration))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, AppSpacing.lg)

            // Haiku section at bottom
            HaikuSectionView()
                .padding(.top, AppSpacing.xxl)
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return "\(displayHour) \(period)"
    }

    private func offsetForTime(_ time: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        let totalMinutes = (hour - startHour) * 60 + minute
        return CGFloat(totalMinutes) / 60.0 * hourHeight
    }

    private func heightForDuration(_ duration: TimeInterval) -> CGFloat {
        let minutes = duration / 60
        return CGFloat(minutes) / 60.0 * hourHeight
    }
}

// MARK: - Timeline Line

struct TimelineLineView: View {
    let hourHeight: CGFloat
    let totalHours: Int
    let sunTimes: SunTimes
    let startHour: Int
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main timeline line
            Rectangle()
                .fill(theme.colors.timeline)
                .frame(width: 2)
                .frame(height: CGFloat(totalHours) * hourHeight)
                .padding(.leading, 10)

            // Sunrise marker
            SunMarkerView(type: .sunrise, time: sunTimes.sunrise)
                .offset(y: offsetForTime(sunTimes.sunrise))

            // Sunset marker
            SunMarkerView(type: .sunset, time: sunTimes.sunset)
                .offset(y: offsetForTime(sunTimes.sunset))

            // Current time indicator
            CurrentTimeIndicator()
                .offset(y: offsetForTime(Date()))
        }
    }

    private func offsetForTime(_ time: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: time)
        let minute = calendar.component(.minute, from: time)
        let totalMinutes = (hour - startHour) * 60 + minute
        return CGFloat(totalMinutes) / 60.0 * hourHeight
    }
}

// MARK: - Sun Marker

enum SunMarkerType {
    case sunrise
    case sunset

    var iconName: String {
        switch self {
        case .sunrise: return "sunrise.fill"
        case .sunset: return "sunset.fill"
        }
    }

    var label: String {
        switch self {
        case .sunrise: return "Sunrise"
        case .sunset: return "Sunset"
        }
    }
}

struct SunMarkerView: View {
    let type: SunMarkerType
    let time: Date
    @Environment(ThemeManager.self) private var theme

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            // Icon
            ZStack {
                Circle()
                    .fill(type == .sunrise ? theme.colors.sunrise : theme.colors.sunset)
                    .frame(width: 24, height: 24)

                Image(systemName: type.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
            }

            // Label and time
            VStack(alignment: .leading, spacing: 0) {
                Text(type.label)
                    .font(AppTypography.caption)
                    .foregroundStyle(theme.colors.secondaryText)

                Text(timeFormatter.string(from: time))
                    .font(AppTypography.caption2)
                    .foregroundStyle(theme.colors.secondaryText.opacity(0.7))
            }
        }
    }
}

// MARK: - Current Time Indicator

struct CurrentTimeIndicator: View {
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(theme.colors.streakActive)
                .frame(width: 10, height: 10)
                .offset(x: 6)

            Rectangle()
                .fill(theme.colors.streakActive)
                .frame(height: 2)
        }
    }
}

// MARK: - Event Card

struct EventCardView: View {
    let event: CalendarEvent
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button {
            appState.selectEvent(event)
        } label: {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                // Color indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.colors.accent)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    // Title
                    Text(event.title)
                        .font(AppTypography.headline)
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)

                    // Duration and source
                    HStack(spacing: AppSpacing.sm) {
                        Text(event.durationText)
                            .font(AppTypography.caption)
                            .foregroundStyle(theme.colors.secondaryText)

                        // Source icon
                        Image(systemName: event.source.iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.colors.secondaryText)
                    }

                    // Participants
                    if !event.participants.isEmpty {
                        HStack(spacing: -8) {
                            ForEach(event.participants.prefix(3)) { participant in
                                ParticipantAvatarView(participant: participant)
                            }

                            if event.participants.count > 3 {
                                Text("+\(event.participants.count - 3)")
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(theme.colors.secondaryText)
                                    .padding(.leading, AppSpacing.sm)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding(AppSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                    .fill(theme.colors.cardBackground)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
            }
            .padding(.leading, 30)
            .padding(.trailing, AppSpacing.md)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Participant Avatar

struct ParticipantAvatarView: View {
    let participant: Participant
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.colors.accent.opacity(0.2))
                .frame(width: 28, height: 28)

            Text(participant.initials)
                .font(AppTypography.caption2)
                .foregroundStyle(theme.colors.accent)
        }
        .overlay {
            Circle()
                .stroke(theme.colors.cardBackground, lineWidth: 2)
        }
    }
}

// MARK: - Haiku Section

struct HaikuSectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Haiku text
            VStack(spacing: AppSpacing.sm) {
                ForEach(appState.currentHaiku.lines, id: \.self) { line in
                    Text(line)
                        .font(AppTypography.haiku)
                        .foregroundStyle(theme.colors.primaryText)
                        .italic()
                }
            }
            .padding(.horizontal, AppSpacing.xxl)

            // Pet illustration
            PixelPetView(size: .medium, animated: true)
                .frame(height: 120)
        }
        .padding(.vertical, AppSpacing.xl)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: AppCornerRadius.large)
                .fill(theme.colors.cardBackground.opacity(0.5))
        }
        .padding(.horizontal, AppSpacing.lg)
    }
}

#Preview {
    HomeView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
