import WidgetKit
import SwiftUI

// MARK: - Widget Entry

struct KiroEntry: TimelineEntry {
    let date: Date
    let petName: String
    let petMood: String
    let currentStreak: Int
    let todayCompleted: Int
    let todayTotal: Int
    let configuration: ConfigurationAppIntent
}

// MARK: - Timeline Provider

struct KiroProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> KiroEntry {
        KiroEntry(
            date: Date(),
            petName: "Baby Waffle",
            petMood: "happy",
            currentStreak: 7,
            todayCompleted: 3,
            todayTotal: 5,
            configuration: ConfigurationAppIntent()
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> KiroEntry {
        await loadEntry(configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<KiroEntry> {
        let entry = await loadEntry(configuration: configuration)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func loadEntry(configuration: ConfigurationAppIntent) async -> KiroEntry {
        let sharedDefaults = UserDefaults(suiteName: "group.com.kiro.app")

        let petName = sharedDefaults?.string(forKey: "petName") ?? "Baby Waffle"
        let petMood = sharedDefaults?.string(forKey: "petMood") ?? "happy"
        let currentStreak = sharedDefaults?.integer(forKey: "currentStreak") ?? 0
        let todayCompleted = sharedDefaults?.integer(forKey: "todayCompleted") ?? 0
        let todayTotal = sharedDefaults?.integer(forKey: "todayTotal") ?? 0

        return KiroEntry(
            date: Date(),
            petName: petName,
            petMood: petMood,
            currentStreak: currentStreak,
            todayCompleted: todayCompleted,
            todayTotal: todayTotal,
            configuration: configuration
        )
    }
}

// MARK: - Configuration Intent

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Kiro Widget" }
    static var description: IntentDescription { "Display your pet and task progress" }

    @Parameter(title: "Show Streak", default: true)
    var showStreak: Bool
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: KiroEntry

    var body: some View {
        VStack(spacing: 8) {
            // Pet icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: moodIcon)
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            }

            // Pet name
            Text(entry.petName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            // Streak
            if entry.configuration.showStreak {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)

                    Text("\(entry.currentStreak)")
                        .font(.system(size: 10, weight: .medium))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var moodIcon: String {
        switch entry.petMood {
        case "excited": return "face.smiling.inverse"
        case "sleepy": return "moon.zzz.fill"
        case "focused": return "brain.head.profile"
        case "missing": return "heart.slash"
        default: return "face.smiling"
        }
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: KiroEntry

    var body: some View {
        HStack(spacing: 16) {
            // Pet section
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 60, height: 60)

                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                }

                Text(entry.petName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }

            // Stats section
            VStack(alignment: .leading, spacing: 8) {
                // Today's progress
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack {
                        Text("\(entry.todayCompleted)/\(entry.todayTotal)")
                            .font(.system(size: 16, weight: .bold))

                        Spacer()

                        Text(progressPercentage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.green)
                                .frame(width: geometry.size.width * progressValue, height: 4)
                        }
                    }
                    .frame(height: 4)
                }

                // Streak
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)

                    Text("\(entry.currentStreak) day streak")
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var progressValue: CGFloat {
        guard entry.todayTotal > 0 else { return 0 }
        return CGFloat(entry.todayCompleted) / CGFloat(entry.todayTotal)
    }

    private var progressPercentage: String {
        guard entry.todayTotal > 0 else { return "0%" }
        let percentage = Int((Double(entry.todayCompleted) / Double(entry.todayTotal)) * 100)
        return "\(percentage)%"
    }
}

// MARK: - Large Widget View

struct LargeWidgetView: View {
    let entry: KiroEntry

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Kiro")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Text(entry.date, style: .time)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Pet display
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 100, height: 100)

                    VStack(spacing: 4) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)

                        Text(entry.petName)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    // Mood
                    HStack(spacing: 6) {
                        Image(systemName: moodIcon)
                            .font(.system(size: 14))
                            .foregroundStyle(.green)

                        Text(entry.petMood.capitalized)
                            .font(.system(size: 13, weight: .medium))
                    }

                    // Streak
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.orange)

                        Text("\(entry.currentStreak) day streak")
                            .font(.system(size: 13, weight: .medium))
                    }
                }

                Spacer()
            }

            Divider()

            // Today's tasks
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's Progress")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack {
                    Text("\(entry.todayCompleted)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.green)

                    Text("/ \(entry.todayTotal) tasks")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(progressPercentage)
                        .font(.system(size: 20, weight: .bold))
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.green)
                            .frame(width: geometry.size.width * progressValue, height: 8)
                    }
                }
                .frame(height: 8)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var moodIcon: String {
        switch entry.petMood {
        case "excited": return "face.smiling.inverse"
        case "sleepy": return "moon.zzz.fill"
        case "focused": return "brain.head.profile"
        case "missing": return "heart.slash"
        default: return "face.smiling"
        }
    }

    private var progressValue: CGFloat {
        guard entry.todayTotal > 0 else { return 0 }
        return CGFloat(entry.todayCompleted) / CGFloat(entry.todayTotal)
    }

    private var progressPercentage: String {
        guard entry.todayTotal > 0 else { return "0%" }
        let percentage = Int((Double(entry.todayCompleted) / Double(entry.todayTotal)) * 100)
        return "\(percentage)%"
    }
}

// MARK: - Widget Entry View

struct KiroWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: KiroEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Widget Definition

struct KiroWidget: Widget {
    let kind: String = "KiroWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: KiroProvider()) { entry in
            KiroWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Kiro")
        .description("Track your pet and task progress")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Widget Bundle

@main
struct KiroWidgetBundle: WidgetBundle {
    var body: some Widget {
        KiroWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    KiroWidget()
} timeline: {
    KiroEntry(date: Date(), petName: "Baby Waffle", petMood: "happy", currentStreak: 7, todayCompleted: 3, todayTotal: 5, configuration: ConfigurationAppIntent())
}

#Preview("Medium", as: .systemMedium) {
    KiroWidget()
} timeline: {
    KiroEntry(date: Date(), petName: "Baby Waffle", petMood: "excited", currentStreak: 14, todayCompleted: 4, todayTotal: 5, configuration: ConfigurationAppIntent())
}

#Preview("Large", as: .systemLarge) {
    KiroWidget()
} timeline: {
    KiroEntry(date: Date(), petName: "Baby Waffle", petMood: "focused", currentStreak: 30, todayCompleted: 2, todayTotal: 6, configuration: ConfigurationAppIntent())
}
