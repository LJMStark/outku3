import SwiftUI

struct DaySectionView: View {
    let date: Date

    @Environment(AppState.self) private var appState

    private var eventsForDay: [CalendarEvent] {
        let calendar = Calendar.current
        return appState.events
            .filter { calendar.isDate($0.startTime, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            DateDividerView(date: date)
                .padding(.top, 24)

            DayTimelineView(date: date, events: eventsForDay)
                .padding(.horizontal, 24)
        }
    }
}
