import Foundation

@Observable
@MainActor
public final class TimelineDataSource {
    private(set) var dayOffsets: [Int]

    init() {
        dayOffsets = Array(0..<7)
    }

    func loadMoreDays() {
        let nextStart = (dayOffsets.last ?? 0) + 1
        dayOffsets = dayOffsets + Array(nextStart..<(nextStart + 7))
    }

    func shouldShowPetMarker(at offset: Int) -> Bool {
        offset > 0 && offset % 3 == 0
    }

    func dateForOffset(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Self.today) ?? Self.today
    }

    private static var today: Date { Calendar.current.startOfDay(for: Date()) }
}
