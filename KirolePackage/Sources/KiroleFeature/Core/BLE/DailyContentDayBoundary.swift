import Foundation

/// A committed daily package is usable only on its exact device-local calendar date. Firmware
/// applies the same rule before reading any schedule or daily copy; a mismatched package remains
/// stored for recovery diagnostics but is never presented.
public enum DailyContentLocalDayPolicy {
    public static func packageForDisplay(
        _ package: DailyContentPackage?,
        at date: Date,
        calendar: Calendar = .current
    ) -> DailyContentPackage? {
        guard let package,
              package.localDate == DailyContentDate(date: date, calendar: calendar) else {
            return nil
        }
        return package
    }
}

enum DailyContentDayBoundary {
    static func next(after date: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        )
    }
}
