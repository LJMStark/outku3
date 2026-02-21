import Foundation

public extension Date {
    func formatRelativeDay() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Today"
        } else if calendar.isDateInTomorrow(self) {
            return "Tomorrow"
        } else {
            return AppDateFormatters.shortDate.string(from: self)
        }
    }
}
