import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            // Header - fixed at top
            AppHeaderView()

            // Scrollable content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Timeline content
                    TimelineContentView()

                    // Bottom spacing
                    Spacer()
                        .frame(height: 40)
                }
            }
        }
        .background(theme.colors.background)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - App Header (Shared across all main pages)

struct AppHeaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppDateFormatters.headerDate.string(from: appState.selectedDate))
                        .font(.system(size: 34, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)

                    HStack(spacing: 12) {
                        Text(AppDateFormatters.time.string(from: Date()))
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.9))

                        Circle()
                            .fill(.white.opacity(0.4))
                            .frame(width: 4, height: 4)

                        HStack(spacing: 6) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.9))
                            Text("\(appState.weather.highTemp)° / \(appState.weather.lowTemp)°")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.bottom, 2)

                Spacer()

                HStack(spacing: 14) {
                    HeaderIconButton(
                        icon: "house.fill",
                        label: "HOME",
                        iconColor: AppHeaderColors.background,
                        isSelected: appState.selectedTab == .home
                    ) {
                        appState.selectedTab = .home
                    }

                    HeaderIconButton(
                        icon: "pawprint.fill",
                        label: "TIKO",
                        iconColor: AppHeaderColors.background,
                        isSelected: appState.selectedTab == .pet,
                        usePetImage: true
                    ) {
                        appState.selectedTab = .pet
                    }

                    HeaderIconButton(
                        icon: "gearshape.fill",
                        label: "MENU",
                        iconColor: AppHeaderColors.iconAccent,
                        isSelected: appState.selectedTab == .settings
                    ) {
                        appState.selectedTab = .settings
                    }
                }
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 20)

            Rectangle()
                .fill(AppHeaderColors.border)
                .frame(height: 8)
        }
        .background(AppHeaderColors.background)
        .background(
            AppHeaderColors.background
                .ignoresSafeArea(edges: .top)
        )
    }
}

// MARK: - Header Icon Button

struct HeaderIconButton: View {
    let icon: String
    let label: String
    let iconColor: Color
    let isSelected: Bool
    var usePetImage: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                // Button container with gradient overlay
                ZStack {
                    // White background
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white)
                        .frame(width: 52, height: 52)

                    // Gradient overlay
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    .white,
                                    .white.opacity(0),
                                    Color(hex: "#FDF4EB")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 52, height: 52)
                        .opacity(0.6)

                    // Icon or Pet image
                    if usePetImage {
                        PetAvatarView()
                            .frame(width: 36, height: 36)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(iconColor)
                            .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                    }
                }

                // Label
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pet Avatar View

struct PetAvatarView: View {
    var body: some View {
        // Cute pet character
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "#E8F4E8"))

            // Simple cute pet face
            VStack(spacing: 2) {
                // Ears
                HStack(spacing: 16) {
                    Ellipse()
                        .fill(Color(hex: "#FFE0BD"))
                        .frame(width: 10, height: 14)
                        .rotationEffect(.degrees(-15))
                    Ellipse()
                        .fill(Color(hex: "#FFE0BD"))
                        .frame(width: 10, height: 14)
                        .rotationEffect(.degrees(15))
                }
                .offset(y: 6)

                // Face
                ZStack {
                    // Head
                    Circle()
                        .fill(Color(hex: "#FFE0BD"))
                        .frame(width: 28, height: 28)

                    // Eyes
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: "#2D2D2D"))
                            .frame(width: 4, height: 4)
                        Circle()
                            .fill(Color(hex: "#2D2D2D"))
                            .frame(width: 4, height: 4)
                    }
                    .offset(y: -2)

                    // Nose
                    Ellipse()
                        .fill(Color(hex: "#FFB6C1"))
                        .frame(width: 5, height: 3)
                        .offset(y: 4)

                    // Blush
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color(hex: "#FFB6C1").opacity(0.4))
                            .frame(width: 6, height: 6)
                        Circle()
                            .fill(Color(hex: "#FFB6C1").opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                    .offset(y: 3)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}


// MARK: - Timeline Content View

struct TimelineContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Date separator
            DateSeparatorView(date: appState.selectedDate)
                .padding(.top, 20)

            // Timeline items
            VStack(spacing: 0) {
                TimelineMarkerRow(
                    time: appState.sunTimes.sunrise,
                    icon: "sunrise",
                    label: "Sunrise",
                    iconColor: AppTimelineColors.sun
                )

                // Current time indicator (if today)
                if Calendar.current.isDateInToday(appState.selectedDate) {
                    CurrentTimeIndicator(currentTime: currentTime)
                }

                TimelineMarkerRow(
                    time: createTime(hour: 9, minute: 0),
                    icon: "calendar.badge.clock",
                    label: "Day Start",
                    iconColor: AppTimelineColors.google,
                    showGoogleIcon: true
                )

                ForEach(appState.events) { event in
                    TimelineEventRow(event: event)
                }

                TimelineMarkerRow(
                    time: appState.sunTimes.sunset,
                    icon: "sunset",
                    label: "Sunset",
                    iconColor: AppTimelineColors.sun
                )
            }
            .padding(.horizontal, 20)

            DateSeparatorView(date: Calendar.current.date(byAdding: .day, value: 1, to: appState.selectedDate) ?? appState.selectedDate)
                .padding(.top, 24)

            TimelineMarkerRow(
                time: appState.sunTimes.sunrise,
                icon: "sunrise",
                label: "Sunrise",
                iconColor: AppTimelineColors.sun
            )
            .padding(.horizontal, 20)

            HaikuSectionView()
                .padding(.top, 20)
                .padding(.horizontal, 20)

            TimelineMarkerRow(
                time: appState.sunTimes.sunset,
                icon: "sunset",
                label: "Sunset",
                iconColor: AppTimelineColors.sun
            )
            .padding(.horizontal, 20)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    private func createTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: appState.selectedDate)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Current Time Indicator

struct CurrentTimeIndicator: View {
    let currentTime: Date
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(AppDateFormatters.time.string(from: currentTime).uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 70, alignment: .leading)

            // Current time dot and line
            ZStack {
                Rectangle()
                    .fill(theme.colors.accent)
                    .frame(width: 2, height: 40)

                Circle()
                    .fill(theme.colors.accent)
                    .frame(width: 10, height: 10)
            }

            // "Now" label
            HStack(spacing: 6) {
                Text("NOW")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(theme.colors.accent)
                    }
            }
            .padding(.leading, 16)

            Spacer()
        }
        .frame(height: 44)
    }
}

// MARK: - Date Separator

struct DateSeparatorView: View {
    let date: Date
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(AppTimelineColors.line)
                .frame(height: 2)

            Text(AppDateFormatters.separatorDate.string(from: date))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Rectangle()
                .fill(AppTimelineColors.line)
                .frame(height: 2)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Timeline Marker Row (Sunrise/Sunset/Day Start)

struct TimelineMarkerRow: View {
    let time: Date
    let icon: String
    let label: String
    let iconColor: Color
    var showGoogleIcon: Bool = false

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text(AppDateFormatters.time.string(from: time).uppercased())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 70, alignment: .leading)

            Rectangle()
                .fill(AppTimelineColors.line)
                .frame(width: 2, height: 40)

            HStack(spacing: 8) {
                if showGoogleIcon {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(AppTimelineColors.google)
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                        }
                } else {
                    Image(systemName: icon + ".fill")
                        .font(.system(size: 24))
                        .foregroundStyle(iconColor)
                }

                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .padding(.leading, 16)

            Spacer()
        }
        .frame(height: 44)
    }
}

// MARK: - Timeline Event Row

struct TimelineEventRow: View {
    let event: CalendarEvent
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(AppDateFormatters.time.string(from: event.startTime).uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 70, alignment: .leading)
                .padding(.top, 12)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(AppTimelineColors.line)
                    .frame(width: 2)
            }

            Button {
                appState.selectEvent(event)
            } label: {
                EventCard(event: event)
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Event Card

struct EventCard: View {
    let event: CalendarEvent
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(event.durationText)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.secondaryText)

                Image(systemName: "g.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTimelineColors.google)

                if !event.participants.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12))
                        Text("\(event.participants.count)")
                            .font(.system(size: 14))
                    }
                    .foregroundStyle(theme.colors.secondaryText)
                }
            }

            if let description = event.description, !description.isEmpty {
                Text(description)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.colors.primaryText)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.colors.cardBackground)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.colors.accent.opacity(0.3), lineWidth: 1)
        }
    }
}

// MARK: - Haiku Section

struct HaikuSectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 20) {
            // Sun times header
            HStack(spacing: AppSpacing.xl) {
                SunTimeView(
                    icon: "sunrise.fill",
                    time: appState.sunTimes.sunrise,
                    label: "Sunrise",
                    color: theme.colors.sunrise
                )

                Spacer()

                // Weather info
                VStack(spacing: 4) {
                    Image(systemName: appState.weather.condition.rawValue)
                        .font(.system(size: 28))
                        .foregroundStyle(theme.colors.accent)

                    Text("\(appState.weather.temperature)°")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                }

                Spacer()

                SunTimeView(
                    icon: "sunset.fill",
                    time: appState.sunTimes.sunset,
                    label: "Sunset",
                    color: theme.colors.sunset
                )
            }
            .padding(.horizontal, AppSpacing.md)

            // Haiku card
            VStack(spacing: 16) {
                // Haiku text
                VStack(spacing: 6) {
                    ForEach(appState.currentHaiku.lines, id: \.self) { line in
                        Text(line)
                            .font(.system(size: 17, weight: .medium, design: .serif))
                            .foregroundStyle(theme.colors.primaryText)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)

                // Divider
                Rectangle()
                    .fill(theme.colors.timeline.opacity(0.5))
                    .frame(width: 60, height: 2)

                // Pet illustration
                PixelPetView(size: .large, animated: true, scene: .outdoor)
                    .frame(height: 180)
            }
            .padding(.vertical, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: AppCornerRadius.large)
                    .fill(theme.colors.cardBackground)
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            }

            // Refresh haiku button
            Button {
                Task {
                    await appState.loadTodayHaiku()
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                    Text("New Haiku")
                        .font(AppTypography.caption)
                }
                .foregroundStyle(theme.colors.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Sun Time View

struct SunTimeView: View {
    let icon: String
    let time: Date
    let label: String
    let color: Color
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)

            Text(AppDateFormatters.time.string(from: time))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}

// MARK: - Scroll to Top Button

struct ScrollToTopButton: View {
    let action: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.colors.cardBackground)
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.colors.primaryText)
            }
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
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.colors.accent)
        }
        .overlay {
            Circle()
                .stroke(theme.colors.cardBackground, lineWidth: 2)
        }
    }
}

#Preview {
    HomeView()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
