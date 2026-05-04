import SwiftUI

// MARK: - Date Divider View

struct DateDividerView: View {
    let date: Date
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 16) {
            Capsule()
                .fill(theme.colors.accentDark)
                .frame(height: 5)

            Text(formattedDate)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.colors.accentDark)

            Capsule()
                .fill(theme.colors.accentDark)
                .frame(height: 5)
        }
        .padding(.horizontal, 24)
    }

    private var formattedDate: String {
        AppDateFormatters.separatorDate.string(from: date)
    }
}

// MARK: - Day Timeline View

struct DayTimelineView: View {
    let date: Date
    let events: [CalendarEvent]
    var showPet: Bool = false

    @Environment(ThemeManager.self) private var theme

    private var sunTimes: SunTimes { .forDate(date) }

    /// Insert pet after this many events (0-indexed boundary).
    private let petInsertAfter = 4

    var body: some View {
        VStack(spacing: 0) {
            TimelineEventRow(
                time: AppDateFormatters.time.string(from: sunTimes.sunrise),
                iconContent: .asset("tiko_sunrise"),
                title: "Sunrise",
                delay: 0
            )

            TimelineEventRow(
                time: "9:00 AM",
                iconContent: .emoji("📬"),
                title: "Day Start",
                delay: 0
            )

            if events.isEmpty {
                TimelineEmptyStateRow(delay: 0)

                if showPet {
                    HaikuSectionView(delay: 0)
                }
            } else {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    TimelineEventCardRow(event: event, delay: 0)

                    if showPet && index == min(petInsertAfter - 1, events.count - 1) {
                        HaikuSectionView(delay: 0)
                    }
                }
            }

            TimelineEventRow(
                time: AppDateFormatters.time.string(from: sunTimes.sunset),
                iconContent: .system("sunset.fill"),
                title: "Sunset",
                delay: 0
            )
        }
        .background(
            // Vertical timeline line sits between the time and icon columns.
            HStack {
                Spacer()
                    .frame(width: 70)
                Rectangle()
                    .fill(theme.colors.timeline)
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
        .animation(.kiroleGentle.delay(delay), value: appeared)
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
        .animation(.kiroleGentle.delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
    }
}

// MARK: - Timeline Event Row

enum TimelineRowIcon {
    case system(String)
    case emoji(String)
    case asset(String)
}

struct TimelineEventRow: View {
    let time: String
    let iconContent: TimelineRowIcon
    let title: String
    let delay: Double
    var hasIconCircle: Bool = false

    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    /// Icon slot width; must match timeline line alignment math in DayTimelineView.
    static let iconSlotSize: CGFloat = 36

    var body: some View {
        HStack(spacing: 16) {
            // Time
            Text(time)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.secondaryText)
                .frame(width: 64, alignment: .leading)

            // Icon slot — line doesn't pass through, no mask needed.
            ZStack {
                if hasIconCircle {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 32, height: 32)
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                }

                iconView
            }
            .frame(width: Self.iconSlotSize, height: Self.iconSlotSize)

            // Title
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Spacer()
        }
        .padding(.vertical, 12)
        .opacity(appeared ? 1 : 0)
        .animation(.kiroleGentle.delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch iconContent {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: hasIconCircle ? 16 : 22))
                .foregroundStyle(theme.colors.accent)
                .symbolRenderingMode(.hierarchical)
        case .emoji(let char):
            Text(char)
                .font(.system(size: hasIconCircle ? 18 : 24))
        case .asset(let name):
            Image(name, bundle: .module)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.iconSlotSize, height: Self.iconSlotSize)
        }
    }
}

// MARK: - Haiku Section View

struct HaikuSectionView: View {
    let delay: Double

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var ballProgress: CGFloat = -1
    @State private var ballRotation: Double = -180

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 80)

            VStack(spacing: 24) {
                // Dialogue / Haiku text from AppState
                VStack(spacing: 4) {
                    if appState.homeCompanionDisplayMode == .petDialogue && !appState.currentPetDialogue.isEmpty {
                        CompanionDialogueView(
                            appState.currentPetDialogue,
                            color: theme.colors.primaryText
                        )
                    } else {
                        ForEach(Array(appState.currentHaiku.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .italic()
                                .foregroundStyle(theme.colors.primaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: CompanionDialogueDisplayPolicy.reservedHeight)

                // Pet image with rolling toy ball. Under Reduce Motion the
                // ball is omitted entirely — its whole purpose is the
                // perpetual horizontal roll + rotation. Without that motion
                // it would otherwise render at its initial edge pose and
                // float outside the pet container like a visual
                // glitch. Keeping only the pet image is the right neutral.
                GeometryReader { geometry in
                    let ballTravel = HaikuSectionLayout.toyBallHorizontalTravel(
                        availableWidth: geometry.size.width
                    )

                    ZStack {
                        if !reduceMotion {
                            PetToyBall(size: HaikuSectionLayout.toyBallSize)
                                .rotationEffect(.degrees(ballRotation))
                                // Keep the rolling ball inside the visible
                                // home content width instead of hard-coding a
                                // travel distance that can spill off-screen.
                                .offset(
                                    x: ballProgress * ballTravel,
                                    y: HaikuSectionLayout.toyBallVerticalOffset
                                )
                        }

                        Image("tiko_reading", bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: HaikuSectionLayout.petArtworkHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: HaikuSectionLayout.petArtworkHeight)
            }
            .padding(.vertical, 24)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.kiroleAdaptive(.appleEaseOut, reduceMotion: reduceMotion).delay(delay), value: appeared)
        .onAppear {
            appeared = true

            // Rolling ball idle loop — skipped entirely under Reduce Motion to
            // avoid vestibular strain from a perpetual rotation.
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 4.0)
                .repeatForever(autoreverses: true)
            ) {
                ballProgress = 1
                ballRotation = 360 * 2.5
            }
        }
    }
}

// MARK: - Pet Toy Ball

private struct PetToyBall: View {
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // Base sphere with 3D shading
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [Color(hex: "E0C9B1"), Color(hex: "AE917A")]),
                        center: UnitPoint(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.8
                    )
                )
            
            // Subtle top-left highlight
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: size * 0.35, height: size * 0.18)
                .rotationEffect(.degrees(-30))
                .offset(x: -size * 0.18, y: -size * 0.22)
            
            // Elegant horizontal stripe (curved for 3D sphere look)
            Ellipse()
                .stroke(Color(hex: "F2E2CF"), lineWidth: size * 0.1)
                .frame(width: size * 1.5, height: size * 0.6)
                .offset(y: size * 0.12)
                
            // Inner bottom shadow for extra depth
            Circle()
                .stroke(Color(hex: "816752").opacity(0.2), lineWidth: size * 0.12)
                .offset(x: size * 0.05, y: size * 0.05)
                .blur(radius: size * 0.03)
        }
        .clipShape(Circle()) // Ensures contents stay within the sphere
        .frame(width: size, height: size)
        .shadow(color: Color(hex: "A38771").opacity(0.4), radius: size * 0.12, x: 0, y: size * 0.08)
    }
}

#Preview {
    ScrollView {
        DayTimelineView(date: Date(), events: [])
            .padding(.horizontal, 24)
    }
    .background(Color(hex: "f5f1e8"))
    .environment(AppState.shared)
    .environment(ThemeManager.shared)
}
