import SwiftUI

// MARK: - Home View

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Header - Brown background with date, time, weather, nav icons
                AppHeaderView()

                // Timeline content
                TimelineContentView()

                // Bottom spacing
                Spacer()
                    .frame(height: 40)
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

    // Header background - warm brown
    private let headerColor = Color(hex: "#C4944A")

    // Bottom border color - darker brown
    private let borderColor = Color(hex: "#8B6914")

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM dd"
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            HStack(alignment: .bottom) {
                // Left side: Date, Time, Weather
                VStack(alignment: .leading, spacing: 8) {
                    // Large date - extrabold style
                    Text(dateFormatter.string(from: appState.selectedDate))
                        .font(.system(size: 34, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)

                    // Time and weather row with dot separator
                    HStack(spacing: 12) {
                        Text(timeFormatter.string(from: Date()))
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(.white.opacity(0.9))

                        // Dot separator
                        Circle()
                            .fill(.white.opacity(0.4))
                            .frame(width: 4, height: 4)

                        // Weather
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

                // Right side: Navigation buttons
                HStack(spacing: 14) {
                    HeaderIconButton(
                        icon: "house.fill",
                        label: "HOME",
                        iconColor: Color(hex: "#C4944A"),
                        isSelected: appState.selectedTab == .home
                    ) {
                        appState.selectedTab = .home
                    }

                    HeaderIconButton(
                        icon: "pawprint.fill",
                        label: "TIKO",
                        iconColor: Color(hex: "#C4944A"),
                        isSelected: appState.selectedTab == .pet,
                        usePetImage: true
                    ) {
                        appState.selectedTab = .pet
                    }

                    HeaderIconButton(
                        icon: "gearshape.fill",
                        label: "MENU",
                        iconColor: Color(hex: "#D69E2E"),
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

            // Bottom border - 8px dark brown
            Rectangle()
                .fill(borderColor)
                .frame(height: 8)
        }
        .background(headerColor)
        .background(
            headerColor
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

    var body: some View {
        VStack(spacing: 0) {
            // Date separator
            DateSeparatorView(date: appState.selectedDate)
                .padding(.top, 20)

            // Timeline items
            VStack(spacing: 0) {
                // Sunrise
                TimelineMarkerRow(
                    time: appState.sunTimes.sunrise,
                    icon: "sunrise",
                    label: "Sunrise",
                    iconColor: Color(hex: "#FFB347")
                )

                // Day Start
                TimelineMarkerRow(
                    time: createTime(hour: 9, minute: 0),
                    icon: "calendar.badge.clock",
                    label: "Day Start",
                    iconColor: Color(hex: "#4285F4"),
                    showGoogleIcon: true
                )

                // Events
                ForEach(appState.events) { event in
                    TimelineEventRow(event: event)
                }

                // Sunset
                TimelineMarkerRow(
                    time: appState.sunTimes.sunset,
                    icon: "sunset",
                    label: "Sunset",
                    iconColor: Color(hex: "#FFB347")
                )
            }
            .padding(.horizontal, 20)

            // Next day separator (if scrolling)
            DateSeparatorView(date: Calendar.current.date(byAdding: .day, value: 1, to: appState.selectedDate) ?? appState.selectedDate)
                .padding(.top, 24)

            // Sunrise for next day
            TimelineMarkerRow(
                time: appState.sunTimes.sunrise,
                icon: "sunrise",
                label: "Sunrise",
                iconColor: Color(hex: "#FFB347")
            )
            .padding(.horizontal, 20)

            // Haiku section
            HaikuSectionView()
                .padding(.top, 20)
                .padding(.horizontal, 20)

            // Sunset for next day
            TimelineMarkerRow(
                time: appState.sunTimes.sunset,
                icon: "sunset",
                label: "Sunset",
                iconColor: Color(hex: "#FFB347")
            )
            .padding(.horizontal, 20)
        }
    }

    private func createTime(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: appState.selectedDate)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
}

// MARK: - Date Separator

struct DateSeparatorView: View {
    let date: Date
    @Environment(ThemeManager.self) private var theme

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }

    // Dark green color for the separator
    private let separatorColor = Color(hex: "#2D5016")

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(separatorColor)
                .frame(height: 2)

            Text(dateFormatter.string(from: date))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Rectangle()
                .fill(separatorColor)
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

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    // Timeline line color - dark green
    private let lineColor = Color(hex: "#2D5016")

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Time label
            Text(timeFormatter.string(from: time).uppercased())
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 70, alignment: .leading)

            // Vertical line segment
            Rectangle()
                .fill(lineColor)
                .frame(width: 2, height: 40)

            // Icon and label
            HStack(spacing: 8) {
                if showGoogleIcon {
                    // Google Calendar icon placeholder
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(hex: "#4285F4"))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                        }
                } else {
                    // Sun icon with emoji style
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

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }

    // Timeline line color - dark green
    private let lineColor = Color(hex: "#2D5016")

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Time label
            Text(timeFormatter.string(from: event.startTime).uppercased())
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)
                .frame(width: 70, alignment: .leading)
                .padding(.top, 12)

            // Vertical line
            VStack(spacing: 0) {
                Rectangle()
                    .fill(lineColor)
                    .frame(width: 2)
            }

            // Event card
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
            // Title
            Text(event.title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Duration, source, participants
            HStack(spacing: 8) {
                Text(event.durationText)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.secondaryText)

                // Source icon (Google Calendar)
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "#4285F4"))

                // Participants
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

            // Description
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
        VStack(spacing: 24) {
            // Haiku text - centered, poetic style
            VStack(spacing: 8) {
                ForEach(appState.currentHaiku.lines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 18, weight: .medium, design: .serif))
                        .foregroundStyle(theme.colors.primaryText)
                }
            }
            .multilineTextAlignment(.center)

            // Pet illustration - large, centered
            ZStack {
                // Background grass/field illustration would go here
                // For now, using the pixel pet
                PixelPetView(size: .large, animated: true)
                    .frame(height: 200)
            }
        }
        .padding(.vertical, 24)
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
