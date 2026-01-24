import SwiftUI

// MARK: - Event Detail Formatters

private enum EventDetailFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter
    }()
}

// MARK: - Event Detail View

struct EventDetailView: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    // Header with source
                    HStack {
                        // Source badge
                        HStack(spacing: AppSpacing.sm) {
                            Image(systemName: event.source.iconName)
                                .font(.system(size: 14))

                            Text(event.source.rawValue)
                                .font(AppTypography.caption)
                        }
                        .foregroundStyle(theme.colors.secondaryText)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.sm)
                        .background {
                            Capsule()
                                .fill(theme.colors.background)
                        }

                        Spacer()
                    }

                    // Title
                    Text(event.title)
                        .font(AppTypography.title)
                        .foregroundStyle(theme.colors.primaryText)

                    // Time info
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "calendar")
                                .font(.system(size: 16))
                                .foregroundStyle(theme.colors.accent)
                                .frame(width: 24)

                            Text(EventDetailFormatters.date.string(from: event.startTime))
                                .font(AppTypography.body)
                                .foregroundStyle(theme.colors.primaryText)
                        }

                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: "clock")
                                .font(.system(size: 16))
                                .foregroundStyle(theme.colors.accent)
                                .frame(width: 24)

                            Text("\(EventDetailFormatters.time.string(from: event.startTime)) - \(EventDetailFormatters.time.string(from: event.endTime))")
                                .font(AppTypography.body)
                                .foregroundStyle(theme.colors.primaryText)

                            Text("(\(event.durationText))")
                                .font(AppTypography.subheadline)
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                    }
                    .padding(AppSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                            .fill(theme.colors.background)
                    }

                    // Participants
                    if !event.participants.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text("Participants")
                                .font(AppTypography.headline)
                                .foregroundStyle(theme.colors.primaryText)

                            VStack(spacing: AppSpacing.sm) {
                                ForEach(event.participants) { participant in
                                    HStack(spacing: AppSpacing.md) {
                                        ParticipantAvatarView(participant: participant)

                                        Text(participant.name)
                                            .font(AppTypography.body)
                                            .foregroundStyle(theme.colors.primaryText)

                                        Spacer()
                                    }
                                    .padding(AppSpacing.md)
                                    .background {
                                        RoundedRectangle(cornerRadius: AppCornerRadius.small)
                                            .fill(theme.colors.background)
                                    }
                                }
                            }
                        }
                    }

                    // Description
                    if let description = event.description, !description.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text("Description")
                                .font(AppTypography.headline)
                                .foregroundStyle(theme.colors.primaryText)

                            Text(description)
                                .font(AppTypography.body)
                                .foregroundStyle(theme.colors.secondaryText)
                                .padding(AppSpacing.lg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                                        .fill(theme.colors.background)
                                }
                        }
                    }

                    // Location
                    if let location = event.location, !location.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.md) {
                            Text("Location")
                                .font(AppTypography.headline)
                                .foregroundStyle(theme.colors.primaryText)

                            HStack(spacing: AppSpacing.md) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(theme.colors.accent)

                                Text(location)
                                    .font(AppTypography.body)
                                    .foregroundStyle(theme.colors.primaryText)
                            }
                            .padding(AppSpacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background {
                                RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                                    .fill(theme.colors.background)
                            }
                        }
                    }

                    Spacer()
                        .frame(height: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .background(theme.colors.cardBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
    }
}

#Preview {
    EventDetailView(
        event: CalendarEvent(
            title: "Team Standup",
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            source: .google,
            participants: [
                Participant(name: "Alex Chen"),
                Participant(name: "Sarah Kim")
            ],
            description: "Daily sync to discuss progress and blockers"
        )
    )
    .environment(ThemeManager.shared)
}
