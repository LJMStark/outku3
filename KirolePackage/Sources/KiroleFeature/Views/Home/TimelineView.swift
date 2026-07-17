import SwiftUI

// MARK: - Date Divider View

struct DateDividerView: View {
    let date: Date
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 16) {
            Capsule()
                .fill(theme.colors.accentDark.opacity(0.85))
                .frame(height: 2.5)

            Text(formattedDate)
                .font(.system(size: 15, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(theme.colors.accentDark)

            Capsule()
                .fill(theme.colors.accentDark.opacity(0.85))
                .frame(height: 2.5)
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
    @Environment(AppState.self) private var appState

    private var sunTimes: SunTimes { .forDate(date) }

    /// Insert pet after this many events (0-indexed boundary).
    private let petInsertAfter = 4

    var body: some View {
        let companion = appState.userProfile.companionCharacter
        VStack(spacing: 0) {
            TimelineEventRow(
                time: AppDateFormatters.time.string(from: sunTimes.sunrise),
                iconContent: .asset(companion.heroAssetName(variant: .sunrise)),
                title: "Sunrise",
                delay: 0
            )

            TimelineEventRow(
                time: "9:00 AM",
                iconContent: .emoji("\u{1F4EC}"),
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
                iconContent: .asset(companion.heroAssetName(variant: .sunset)),
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
                    videoMeetingURL: event.videoMeetingURL,
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
        case .emoji(let character):
            Text(character)
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

                CompanionAnimationView(
                    artwork: .reading,
                    ambientMotion: .idle,
                    trigger: appState.pendingCompanionMotionTrigger,
                    size: CGSize(
                        width: HaikuSectionLayout.petArtworkHeight,
                        height: HaikuSectionLayout.petArtworkHeight
                    ),
                    isActive: appState.selectedTab == .home,
                    accessibilityLabel: "Pet companion illustration",
                    accessibilityIdentifier: "Home_PetArtwork"
                )
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .frame(height: HaikuSectionLayout.petArtworkHeight)
            }
            .padding(.vertical, 24)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.kiroleAdaptive(.appleEaseOut, reduceMotion: reduceMotion).delay(delay), value: appeared)
        .onAppear {
            appeared = true
        }
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
