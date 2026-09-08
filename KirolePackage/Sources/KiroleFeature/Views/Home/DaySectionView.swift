import SwiftUI

struct DaySectionView: View {
    let date: Date
    var showPet: Bool = false

    @Environment(AppState.self) private var appState

    /// Multi-day events list under every day they cover, not just the day they start on — see
    /// `CalendarEvent.covers(day:calendar:)` for why the span test is half-open, and why the
    /// hardware encoders keep filtering by start day instead.
    private var eventsForDay: [CalendarEvent] {
        appState.presentationEvents
            .filter { $0.covers(day: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            DateDividerView(date: date)
                .padding(.top, 12)

            DayTimelineView(date: date, events: eventsForDay, showPet: showPet)
                .padding(.horizontal, 24)
        }
    }
}
