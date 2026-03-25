import Foundation

public struct FocusEnergyCalculator {
    public static func blocksEarned(minutes: Int) -> Int {
        if minutes >= 30 { return 3 }
        if minutes >= 15 { return 2 }
        if minutes >= 5 { return 1 }
        return 0
    }
}
