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
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Timeline View

struct TimelineView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Sunrise
            TimelineEventRow(
                time: "6:17 AM",
                icon: "🦝",
                title: "Sunrise",
                delay: 0.3
            )

            // Day Start
            TimelineEventRow(
                time: "9:00 AM",
                icon: "🎁",
                title: "Day Start",
                delay: 0.4
            )

            // Event Card
            TimelineCardRow(delay: 0.5)

            // Sunset
            TimelineEventRow(
                time: "7:17 PM",
                icon: "🌅",
                title: "Sunset",
                delay: 0.6
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

// MARK: - Timeline Event Row

struct TimelineEventRow: View {
    let time: String
    let icon: String
    let title: String
    let delay: Double

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

                Text(icon)
                    .font(.system(size: 18))
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

// MARK: - Timeline Card Row

struct TimelineCardRow: View {
    let delay: Double

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false
    @State private var showEventDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Time header
            HStack {
                Text("5:17 PM")
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
                    title: "New Product Factory Tour!",
                    duration: "1h",
                    participants: 2,
                    description: "Join your coworkers for a factory tour in Shenzhen to see how the new product is made. Exciting!",
                    onTap: {
                        showEventDetail = true
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
        .sheet(isPresented: $showEventDetail) {
            EventDetailModal()
                .environment(theme)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Timeline With Haiku View

struct TimelineWithHaikuView: View {
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Sunrise
            TimelineEventRow(
                time: "6:17 AM",
                icon: "🦝",
                title: "Sunrise",
                delay: 0.9
            )

            // Haiku and Image
            HaikuSectionView(delay: 1.0)

            // Sunset
            TimelineEventRow(
                time: "7:17 PM",
                icon: "🌅",
                title: "Sunset",
                delay: 1.1
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

    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 80)

            VStack(spacing: 24) {
                // Haiku text
                VStack(spacing: 4) {
                    Text("library hush hums")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(theme.colors.primaryText)

                    Text("pages turn like gentle wings")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(theme.colors.primaryText)

                    Text("thoughts land, unafraid")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(theme.colors.primaryText)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                // Pet image placeholder
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.colors.accentLight)
                    .frame(height: 200)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                            Text("Pet Image")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                        }
                    }
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
}

#Preview {
    ScrollView {
        TimelineContentView()
    }
    .background(Color(hex: "f5f1e8"))
    .environment(AppState.shared)
    .environment(ThemeManager.shared)
}
