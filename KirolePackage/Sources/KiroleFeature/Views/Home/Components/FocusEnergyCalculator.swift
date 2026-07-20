import Foundation

public struct FocusEnergyCalculator {
    public static func bottlesEarned(minutes: Int) -> Int {
        return minutes / 30
    }

    /// 硬件专注页（`0x14 FocusStatus`）能量瓶的**显示上限**：满 5 个后不再往上加显示
    /// （客户 2026-07 决策）。只约束下发给硬件的显示值——累计积分（场景解锁，走
    /// `FocusSessionService` 会话结束的 `session.earnedEnergyBottles` 真实累加）**不受此限**。
    public static let hardwareBottleDisplayCap = 5

    /// 折算成硬件应显示的能量瓶数：真实已收集数 clamp 到 `[0, hardwareBottleDisplayCap]`。
    /// 负数（防御）归零、超上限归 5。仅用于 `0x14` 显示出口，不用于积分累加。
    public static func displayBottles(forEarned earned: Int) -> Int {
        return min(hardwareBottleDisplayCap, max(0, earned))
    }
}
