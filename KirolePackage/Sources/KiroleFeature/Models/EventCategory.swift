import Foundation

// MARK: - Event Category

/// 日历事件六大类标签（客户《图标对应关系》docx，2026-07-17）。
///
/// wire 上是 DayPack Events[] 每条的 1 字节 `Category`（协议 §4.7，v2.5.27）：App 只发
/// 类别信号字节，六个像素图标本体由固件内置（与 IP 形象 / 天气图标同一"信号选内置图"
/// 架构，见 docs/assets/event-category-icons/）。`0x00` = 未分类，固件不画图标——但
/// v2.5.28 起 App 不再发送它：归类不了的按客户拍板（2026-07-17）落 `.admin`（点赞图标），
/// 映射在 EventCategoryService 出口处做，本枚举与启发式仍如实返回 `.unknown`。
public enum EventCategory: UInt8, Codable, Sendable, CaseIterable {
    case unknown = 0x00
    /// 深度工作/核心生产力 — 沙漏图标（写代码、写文案、做设计、分析数据）
    case deepWork = 0x01
    /// 会议与协同沟通 — 对话气泡图标（同步会、对数据、客户对齐、面试）
    case meetings = 0x02
    /// 行政日常与琐碎待办 — 点赞图标（清邮件、填表、处理询盘）
    case admin = 0x03
    /// 硬性死线与交付 — 对勾图标（上线日、合同截止、还款日）
    case deadline = 0x04
    /// 生物钟习惯与健康调理 — 爱心图标（拉伸、喝水、维他命、睡前）
    case wellness = 0x05
    /// 充能与私人生活 — 笑脸图标（午休、午餐、看书、陪宠物）
    case rest = 0x06

    /// LLM 分类提示词里 1-6 的类别定义（编号 = rawValue，勿改序）。
    static let promptDefinitions = """
        1 = Deep Work (focused solo output: coding, writing, design, data analysis)
        2 = Meetings & Synced (meetings, calls, syncs, standups, interviews, 1:1s)
        3 = Administrative & Routine (email, forms, paperwork, errands, chores)
        4 = Critical Deadlines (launches, contract/payment due dates, submissions)
        5 = Bio-Habits & Wellness (stretch, hydrate, vitamins, sleep wind-down, workout)
        6 = Rest & Recharge (nap, lunch, reading, pets, games, personal downtime)
        """

    /// 关键词启发式兜底：AI 不可用/输出非法时按标题猜类别，兜不住返回 `.unknown`。
    /// 只收显而易见的词，保持「不知道就说不知道」；`.unknown` → `.admin`（点赞）的
    /// 产品级兜底由 EventCategoryService 在出口处统一做（客户拍板 2026-07-17）。
    static func heuristic(for title: String) -> EventCategory {
        let lowered = title.lowercased()
        let table: [(EventCategory, [String])] = [
            (.meetings, ["meeting", "meet ", "sync", "standup", "stand-up", "call", "interview", "1:1", "1on1", "review with", "会议", "面试", "对齐"]),
            (.deadline, ["deadline", "due", "launch", "submit", "release", "payment", "renewal", "截止", "上线", "交付"]),
            (.wellness, ["stretch", "water", "hydrate", "vitamin", "sleep", "wind down", "workout", "gym", "run", "yoga", "喝水", "拉伸", "睡觉"]),
            (.rest, ["lunch", "nap", "break", "dinner", "breakfast", "reading", "read ", "game", "walk", "午休", "午餐", "休息"]),
            (.admin, ["email", "inbox", "invoice", "expense", "form", "paperwork", "admin", "报销", "邮件", "填表"]),
            (.deepWork, ["coding", "code", "write", "writing", "design", "focus", "deep work", "analysis", "写作", "编码", "设计"])
        ]
        for (category, keywords) in table where keywords.contains(where: { lowered.contains($0) }) {
            return category
        }
        return .unknown
    }
}
