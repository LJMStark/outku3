import Foundation

// MARK: - BLE Data Encoder

/// BLE 数据编码器，负责将应用数据编码为 E-ink 设备可识别的二进制格式
public enum BLEDataEncoder {

    // MARK: - Pet Status

    /// 编码宠物状态数据
    public static func encodePetStatus(_ pet: Pet, companionCharacter: CompanionCharacter) -> Data {
        var data = Data()
        data.appendString(pet.name, maxLength: 20)
        data.append(pet.mood.rawValue.first?.asciiValue ?? 0)
        data.appendString(companionCharacter.rawValue, maxLength: 10)
        return data
    }

    // MARK: - Task List

    /// 编码任务列表数据
    public static func encodeTaskList(_ tasks: [TaskItem]) -> Data {
        var data = Data()
        let todayTasks = tasks.filter { $0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false }
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
        data.appendString(dayPack.petDialogue, maxLength: 120)

        // Events[] (time / title / description)
        let maxEvents = 8
        data.appendClampedUInt8(min(dayPack.events.count, maxEvents))
        for event in dayPack.events.prefix(maxEvents) {
            data.appendString(event.time, maxLength: 8)
            data.appendString(event.title, maxLength: 40)
            data.appendString(event.description, maxLength: 120)
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
        data.appendString(dayPack.daySummary, maxLength: 180)

        // v2.5.8: FirstUp (box③ "First up:" label) — currently the final DayPack field, appended
        // after DaySummary. Same strict-reader contract: a reader must read it to reach end.
        data.appendString(dayPack.firstUp, maxLength: 60)

        return data
    }

    // MARK: - Task In Page

    /// 编码 TaskInPage 数据
    public static func encodeTaskInPage(_ taskInPage: TaskInPageData) -> Data {
        var data = Data()
        data.appendString(taskInPage.taskId, maxLength: 36)
        data.appendString(taskInPage.taskTitle, maxLength: 40)
        data.appendString(taskInPage.taskDescription ?? "", maxLength: 100)
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

    // MARK: - Screen Config

    /// 编码屏幕配置信息
    public static func encodeScreenConfig(_ screenSize: ScreenSize) -> Data {
        var data = Data()
        data.appendBigEndian(UInt16(screenSize.width))
        data.appendBigEndian(UInt16(screenSize.height))
        data.appendClampedUInt8(screenSize.maxTasks)
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

    // MARK: - Pixel Data (Spectra 6, 4bpp)

    /// 将 EInkColor 像素数组打包为 4bpp 数据（每字节 2 像素）
    /// 如果像素数为奇数，最后一个字节的低 nibble 填充白色
    public static func encodePixelData(_ pixels: [EInkColor], width: Int) -> Data {
        let count = pixels.count
        let byteCount = (count + 1) / 2
        var data = Data(count: byteCount)
        for i in stride(from: 0, to: count, by: 2) {
            let even = pixels[i]
            let odd = (i + 1 < count) ? pixels[i + 1] : .white
            data[i / 2] = EInkColor.packPixelPair(even: even, odd: odd)
        }
        return data
    }

    // MARK: - Custom Avatar Frame (0x15)

    /// 编码自定义伴侣的像素帧。
    /// Payload 布局（与硬件团队待对齐，目前以 sub-version 0x01 标记）：
    ///   subVersion(1B) | width(1B) | height(1B) | 4bpp pixels(N)
    /// pixelData 已是 4bpp packed 数据（通常 96×96 → 4608B）。
    public static func encodeCustomAvatarFrame(
        pixelData: Data,
        width: Int = AvatarProcessResult.dimension,
        height: Int = AvatarProcessResult.dimension
    ) -> Data {
        var data = Data()
        data.append(0x01)
        data.appendClampedUInt8(width)
        data.appendClampedUInt8(height)
        data.append(pixelData)
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
}
