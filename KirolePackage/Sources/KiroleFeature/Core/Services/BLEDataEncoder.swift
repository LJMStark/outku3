import Foundation

// MARK: - Data Extension for BLE Encoding

extension Data {
    /// 追加带长度前缀的字符串数据（截断到指定最大长度）
    mutating func appendString(_ string: String, maxLength: Int) {
        let stringData = string.data(using: .utf8) ?? Data()
        append(UInt8(Swift.min(stringData.count, maxLength)))
        append(stringData.prefix(maxLength))
    }
}

// MARK: - BLE Data Encoder

/// BLE 数据编码器，负责将应用数据编码为 E-ink 设备可识别的二进制格式
public enum BLEDataEncoder {

    // MARK: - Pet Status

    /// 编码宠物状态数据
    public static func encodePetStatus(_ pet: Pet) -> Data {
        var data = Data()
        data.appendString(pet.name, maxLength: 20)
        data.append(pet.mood.rawValue.first?.asciiValue ?? 0)
        data.append(pet.stage.rawValue.first?.asciiValue ?? 0)
        data.append(UInt8(min(Int(pet.progress * 100), 255)))
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

        // Page 1: Start of Day
        data.appendString(dayPack.morningGreeting, maxLength: 50)
        data.appendString(dayPack.dailySummary, maxLength: 60)
        data.appendString(dayPack.firstItem, maxLength: 40)

        // Page 2: Overview
        data.appendString(dayPack.currentScheduleSummary ?? "", maxLength: 30)
        data.appendString(dayPack.companionPhrase, maxLength: 40)

        // Top tasks (dynamic limit based on screen size)
        let maxTasks = screenSize.maxTasks
        data.append(UInt8(min(dayPack.topTasks.count, maxTasks)))
        for task in dayPack.topTasks.prefix(maxTasks) {
            data.appendString(task.id, maxLength: 36)
            data.appendString(task.title, maxLength: 30)
            data.appendString(task.microActionWhat ?? "", maxLength: 40)
            data.append(task.isCompleted ? 0x01 : 0x00)
            data.append(UInt8(clamping: task.priority))
        }

        // Page 4: Settlement
        data.append(UInt8(clamping: dayPack.settlementData.tasksCompleted))
        data.append(UInt8(clamping: dayPack.settlementData.tasksTotal))
        let points = UInt16(min(dayPack.settlementData.pointsEarned, 65535))
        data.append(contentsOf: withUnsafeBytes(of: points.bigEndian) { Array($0) })
        data.append(UInt8(clamping: dayPack.settlementData.streakDays))
        let focusMinutes = UInt16(min(dayPack.settlementData.totalFocusMinutes, 65535))
        data.append(contentsOf: withUnsafeBytes(of: focusMinutes.bigEndian) { Array($0) })
        data.append(UInt8(clamping: dayPack.settlementData.focusSessionCount))
        let longestFocus = UInt16(min(dayPack.settlementData.longestFocusMinutes, 65535))
        data.append(contentsOf: withUnsafeBytes(of: longestFocus.bigEndian) { Array($0) })
        data.append(UInt8(clamping: dayPack.settlementData.interruptionCount))
        data.appendString(dayPack.settlementData.summaryMessage, maxLength: 50)
        data.appendString(dayPack.settlementData.encouragementMessage, maxLength: 50)

        return data
    }

    // MARK: - Task In Page

    /// 编码 TaskInPage 数据
    public static func encodeTaskInPage(_ taskInPage: TaskInPageData) -> Data {
        var data = Data()
        data.appendString(taskInPage.taskId, maxLength: 36)
        data.appendString(taskInPage.taskTitle, maxLength: 40)
        data.appendString(taskInPage.microActionWhat ?? "", maxLength: 40)
        data.appendString(taskInPage.microActionWhy ?? "", maxLength: 60)
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
        data.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian) { Array($0) })
        return data
    }

    // MARK: - Screen Config

    /// 编码屏幕配置信息
    public static func encodeScreenConfig(_ screenSize: ScreenSize) -> Data {
        var data = Data()
        let widthBE = UInt16(screenSize.width).bigEndian
        let heightBE = UInt16(screenSize.height).bigEndian
        data.append(contentsOf: withUnsafeBytes(of: widthBE) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: heightBE) { Array($0) })
        data.append(UInt8(screenSize.maxTasks))
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
}
