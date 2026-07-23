import Foundation

// MARK: - Text Byte Budgets

/// DayPack/TaskInPage 文本字段的字节预算唯一真源。App 侧生成（CompanionTextService
/// enforceByteBudget / DayPackGenerator）与线上编码（下方 appendString maxLength）必须
/// 同值——两边手写数字曾各写一份，漂移即被 validUTF8Prefix 静默截断。改值需同步
/// docs/BLE通信协议规格文档.md 对应字段（petDialogue §4.7 bubble / daySummary §4.7 / TaskInPage 描述）。
public enum DayPackTextBudget {
    public static let petDialogue = 120
    public static let daySummary = 180
    public static let taskDescription = 100
    /// v2.5.30 页面四概况点评（§4.7 SettlementReview）。
    public static let settlementReview = 180
    /// v2.5.30 页面四金句/明日鼓励（§4.7 SettlementQuote）。
    public static let settlementQuote = 120
}

// MARK: - BLE Data Encoder

/// BLE 数据编码器，负责将应用数据编码为 E-ink 设备可识别的二进制格式
public enum BLEDataEncoder {

    // MARK: - Pet Status

    /// 编码宠物状态数据。
    /// v2.5.32: `customActive` 尾字节——1=自定义形象激活（固件除专注页显示已持久化的
    /// 0x15 图），0=按 CharacterId 内置渲染。CharacterId 恒为最近一次**内置**选择（供
    /// 专注页美术），自定义激活与否由本字节判定，消除"例行 sync 的 0x01"与"用户切回
    /// 内置"的字节歧义。
    public static func encodePetStatus(_ pet: Pet, companionCharacter: CompanionCharacter, customActive: Bool) -> Data {
        var data = Data()
        data.appendString(pet.name, maxLength: 20)
        data.append(pet.mood.rawValue.first?.asciiValue ?? 0)
        data.appendString(companionCharacter.rawValue, maxLength: 10)
        data.append(customActive ? 0x01 : 0x00)
        return data
    }

    // MARK: - Task List

    /// 编码任务列表数据
    public static func encodeTaskList(_ tasks: [TaskItem]) -> Data {
        var data = Data()
        let todayTasks = tasks.filter { $0.isInTodayDisplay() }
        data.append(UInt8(min(todayTasks.count, 10)))

        for task in todayTasks.prefix(10) {
            data.appendString(task.title, maxLength: 30)
            data.append(task.isCompleted ? 1 : 0)
        }
        return data
    }

    // MARK: - Schedule

    /// 编码日程数据
    public static func encodeSchedule(_ events: [CalendarEvent]) -> Data {
        var data = Data()
        let todayEvents = events.filter { Calendar.current.isDateInToday($0.startTime) }
        data.append(UInt8(min(todayEvents.count, 8)))

        let formatter = DateFormatter()
        // en_US_POSIX pins ASCII digits: without it a Persian/Arabic number region would emit
        // e.g. "۰۹:۳۰" (multi-byte, non-ASCII), which both renders as tofu on the E-ink panel
        // AND desyncs the fixed 5-byte StartTime field (§4.4). This raw write bypasses the
        // appendString ASCII choke point (StartTime is a fixed 5-byte field, not length-prefixed),
        // so the locale is the guarantee here. All other time formatters already pin en_US_POSIX.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"

        for event in todayEvents.prefix(8) {
            data.appendString(event.title, maxLength: 25)
            data.append(formatter.string(from: event.startTime).data(using: .utf8) ?? Data())
        }
        return data
    }

    // MARK: - Weather

    /// 编码天气数据
    public static func encodeWeather(_ weather: Weather) -> Data {
        var data = Data()
        let temp = Int8(clamping: weather.temperature)
        data.append(contentsOf: withUnsafeBytes(of: temp) { Array($0) })
        data.appendString(weather.condition.rawValue, maxLength: 15)
        // v2.5.9: HighTemp / LowTemp (top-bar "high/low", e.g. 42/23) appended after Condition.
        let high = Int8(clamping: weather.highTemp)
        let low = Int8(clamping: weather.lowTemp)
        data.append(contentsOf: withUnsafeBytes(of: high) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: low) { Array($0) })
        return data
    }

    // MARK: - Time

    /// 编码当前时间
    public static func encodeCurrentTime() -> Data {
        var data = Data()
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date()
        )
        let yearOffset = max(0, min((components.year ?? 2024) - 2000, 255))
        data.append(UInt8(yearOffset))
        data.append(UInt8(components.month ?? 1))
        data.append(UInt8(components.day ?? 1))
        data.append(UInt8(components.hour ?? 0))
        data.append(UInt8(components.minute ?? 0))
        data.append(UInt8(components.second ?? 0))
        return data
    }

    // MARK: - Day Pack

    /// 编码 DayPack 数据
    public static func encodeDayPack(_ dayPack: DayPack, screenSize: ScreenSize = .fourInch) -> Data {
        var data = Data()

        // Header
        let dateComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: dayPack.date)
        let dayPackYearOffset = max(0, min((dateComponents.year ?? 2024) - 2000, 255))
        data.append(UInt8(dayPackYearOffset))
        data.append(UInt8(dateComponents.month ?? 1))
        data.append(UInt8(dateComponents.day ?? 1))

        // Device mode
        data.append(dayPack.deviceMode == .interactive ? 0x00 : 0x01)

        // Focus challenge flag
        data.append(dayPack.focusChallengeEnabled ? 0x01 : 0x00)

        // Pet dialogue bubble (v2.5.0: single line, = App currentPetDialogue)
        data.appendString(dayPack.petDialogue, maxLength: DayPackTextBudget.petDialogue)

        // Events[] (time / title / description / category / endTime)
        let maxEvents = 8
        data.appendClampedUInt8(min(dayPack.events.count, maxEvents))
        for event in dayPack.events.prefix(maxEvents) {
            data.appendString(event.time, maxLength: 8)
            data.appendString(event.title, maxLength: 40)
            data.appendString(event.description, maxLength: 120)
            // v2.5.27: Category byte (0x00=untagged/no icon, 0x01-0x06 = customer's six classes).
            // Signal only — the six icons are firmware-built-in art. Breaking change: the strict
            // reader (§7.1) must consume this byte; parseDayPack in the test layer mirrors it.
            data.append(event.category.rawValue)
            // v2.5.30: EndTime "HH:mm"（全天空串、跨午夜封顶 23:59）。固件用于页面二
            // <10min/>10min 间隔分支 + 页面一时间轴末端标注。Breaking change：§7.1 严格
            // 读取方必须消费此长度前缀字符串。
            data.appendString(event.endTime, maxLength: 8)
        }

        // Top tasks (dynamic limit based on screen size)
        let maxTasks = screenSize.maxTasks
        data.appendClampedUInt8(min(dayPack.topTasks.count, maxTasks))
        for task in dayPack.topTasks.prefix(maxTasks) {
            data.appendString(task.id, maxLength: 36)
            data.appendString(task.title, maxLength: 30)
            data.append(task.isCompleted ? 0x01 : 0x00)
            data.appendClampedUInt8(task.priority)
        }

        // Page 4: Settlement
        data.appendClampedUInt8(dayPack.settlementData.tasksCompleted)
        data.appendClampedUInt8(dayPack.settlementData.tasksTotal)
        data.appendBigEndian(UInt16(clamping: dayPack.settlementData.pointsEarned))
        data.appendBigEndian(UInt16(clamping: dayPack.settlementData.totalFocusMinutes))
        data.appendClampedUInt8(dayPack.settlementData.focusSessionCount)
        data.appendBigEndian(UInt16(clamping: dayPack.settlementData.longestFocusMinutes))
        data.appendClampedUInt8(dayPack.settlementData.interruptionCount)
        // v2.5.0: SummaryMessage / EncouragementMessage removed from the wire — the pet voice
        // is unified in PetDialogue; energy bottles ship via 0x14 FocusStatus.

        // v2.5.7: DaySummary (box② "day at a glance") is a tail-appended DayPack field. Per §7.1 the
        // wire reader is strict (trailing bytes = format error), so any reader MUST read the tail
        // fields to reach end-of-payload — the in-repo simulation decoder (parseDayPack) does. There
        // is no prior live DayPack parser to stay compatible with (firmware DayPack parsing isn't
        // shipped yet); tail placement just keeps the fixed SettlementData offsets stable.
        data.appendString(dayPack.daySummary, maxLength: DayPackTextBudget.daySummary)

        // v2.5.8: FirstUp (box③ "First up:" label), appended after DaySummary.
        // Same strict-reader contract: a reader must read it to reach end.
        data.appendString(dayPack.firstUp, maxLength: 60)

        // v2.5.30/v2.5.31: 每日总结页两段文案（尾部追加，SettlementData 定长偏移保持稳定）。
        // SettlementQuote 是当前 DayPack 最后一个字段——严格读取方必须依次读完这两个
        // 长度前缀字符串才到 payload 末尾。（v2.5.30 曾有第三个尾字段 TomorrowFirstUp，
        // 客户 2026-07-20 拍板总结页只有两部分，v2.5.31 在固件实现前撤除。）
        data.appendString(dayPack.settlementReview, maxLength: DayPackTextBudget.settlementReview)
        data.appendString(dayPack.settlementQuote, maxLength: DayPackTextBudget.settlementQuote)

        return data
    }

    // MARK: - Task In Page

    /// 编码 TaskInPage 数据
    public static func encodeTaskInPage(_ taskInPage: TaskInPageData) -> Data {
        var data = Data()
        data.appendString(taskInPage.taskId, maxLength: 36)
        data.appendString(taskInPage.taskTitle, maxLength: 40)
        data.appendString(taskInPage.taskDescription ?? "", maxLength: DayPackTextBudget.taskDescription)
        data.appendString(taskInPage.encouragement, maxLength: 50)
        data.append(taskInPage.focusChallengeActive ? 0x01 : 0x00)
        return data
    }

    // MARK: - Device Mode

    /// 编码设备模式
    public static func encodeDeviceMode(_ mode: DeviceMode) -> Data {
        var data = Data()
        data.append(mode == .interactive ? 0x00 : 0x01)
        return data
    }

    // MARK: - Smart Reminder (0x13)

    /// 编码智能提醒数据
    public static func encodeSmartReminder(text: String, urgency: ReminderUrgency, petMood: PetMood) -> Data {
        var data = Data()
        data.appendString(text, maxLength: 60)
        data.append(urgency.rawValue)
        data.append(petMood.rawValue.first?.asciiValue ?? 0x48) // default 'H' for Happy
        return data
    }

    // MARK: - Event Log Request

    /// 编码 Event Log 请求
    public static func encodeEventLogRequest(since timestamp: UInt32) -> Data {
        var data = Data()
        data.appendBigEndian(timestamp)
        return data
    }

    // MARK: - Focus Status (0x14)

    /// 编码专注状态，用于实时推送当前专注状态和能量瓶子数给硬件。
    ///
    /// Payload 格式：
    /// - phase      1B  专注阶段（0=idle, 1=warmup, 2=building, 3=deep）
    /// - bottles    1B  本会话已收集的能量瓶子数（按未打断段计、打断重置在装填进度；clamp 0-255）
    /// - elapsed    2B  本会话累计已专注分钟数（自进入任务，墙钟，不随打断归零；Big Endian，clamp 0-65535）
    /// - taskTitle  变长 长度前缀 UTF-8，最多 40 字节
    /// - segment    2B  当前未打断连续段分钟数（打断即归零重计，驱动装填进度；追加在 taskTitle 后，Big Endian，clamp 0-65535）
    public static func encodeFocusStatus(
        phase: FocusPhase,
        energyBottles: Int,
        elapsedMinutes: Int,
        taskTitle: String?,
        segmentMinutes: Int
    ) -> Data {
        var data = Data()
        let phaseByte: UInt8 = switch phase {
        case .idle:     0
        case .warmup:   1
        case .building: 2
        case .deep:     3
        }
        data.append(phaseByte)
        data.appendClampedUInt8(energyBottles)
        data.appendBigEndian(UInt16(clamping: elapsedMinutes))
        data.appendString(taskTitle ?? "", maxLength: 40)
        // SegmentMinutes appended after the variable-length TaskTitle so older firmware that
        // stops at TaskTitle simply ignores the trailing bytes (forward-compatible).
        data.appendBigEndian(UInt16(clamping: segmentMinutes))
        return data
    }

    // MARK: - Custom Avatar Frame (0x15)

    /// 编码自定义伴侣头像帧（v2.5.24 起 SubVersion 0x02，协议 §4.12）。
    /// Payload 布局：`SubVersion(1B)=0x02 | PNG 文件字节`。
    /// 宽高由 PNG IHDR 自描述（App 保证 ≤800×700、保持原图比例、尽力 ≤1MiB，
    /// 见 `AvatarImageProcessor`）；旧 4bpp 96×96 v1（SubVersion 0x01）已废弃。
    public static func encodeCustomAvatarFrame(pngData: Data) -> Data {
        var data = Data()
        data.append(0x02)
        data.append(pngData)
        return data
    }

    /// 编码自定义伴侣头像帧 KRI 载荷（SubVersion 0x03，协议 §4.12 v3 提案）。
    /// Payload 布局：`SubVersion(1B)=0x03 | KRI v1 文件字节`（12B 小端文件头 +
    /// 左上起始逐行 BGRA 直通 alpha 裸像素，见 docs/KRI_图片转换规范.md）。
    /// 宽高由 KRI 文件头自描述；总长恒为 `1 + 12 + width × height × 4`
    /// （≤800×700 → payload ≤2,240,013B）。当前默认仍发 0x02 PNG，本路径由
    /// `BLEService.avatarKRIPushEnabled` 调试开关启用，待固件实现后 flag-day 切换。
    public static func encodeCustomAvatarFrame(kriData: Data) -> Data {
        var data = Data()
        data.append(0x03)
        data.append(kriData)
        return data
    }

    // MARK: - Screensaver (0x16)

    /// 编码屏保金句/明信片业务帧 payload（替代旧 `0xAA 01 02` 开发命令）。
    /// 经 `BLEService.writeData(type: .screensaver, …)` 发送：dev 模式走简单包、
    /// secure 模式自动 SecureEnvelope 封装，**两种模式均可发**（旧开发命令在 secure 下被禁用）。
    ///
    /// Payload 布局（见协议 §4.15）：
    /// `ContentType(1) | SceneByte(1) | PostcardDay(1) | QuoteLen(1)+Quote(≤180) | AuthorLen(1)+Author(≤40)`
    public static func encodeScreensaver(_ config: ScreensaverConfig) -> Data {
        var data = Data()
        let sceneByte = DisplayScene(rawValue: config.sceneId)?.commandByte ?? DisplayScene.harbor.commandByte
        data.append(config.type == .postcard ? 0x01 : 0x00)
        data.append(sceneByte)
        data.appendClampedUInt8(config.postcardDay ?? 0)
        data.appendString(config.quote, maxLength: 180)
        data.appendString(config.author, maxLength: 40)
        return data
    }

    // MARK: - Scene Unlock (0x17)

    /// 编码场景解锁业务帧 payload（替代旧 `0xAA 01 01` 开发命令）。
    /// 经 `BLEService.writeData(type: .sceneUnlock, …)` 发送：dev 模式走简单包、
    /// secure 模式自动 SecureEnvelope 封装，**两种模式均可发**。
    /// Payload = 单字节 SceneId（`DisplayScene.commandByte`，见协议 §4.16）。
    public static func encodeSceneUnlock(_ scene: DisplayScene) -> Data {
        Data([scene.commandByte])
    }
}
