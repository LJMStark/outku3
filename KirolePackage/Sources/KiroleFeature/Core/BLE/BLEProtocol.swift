import Foundation

// MARK: - BLE Protocol Overview
//
// 本文件是 Kirole BLE 协议的单一真相源，集中定义 App↔Device 的数据类型字节。
//
// App → Device（本文件 BLEDataType）：
//   0x01 petStatus       宠物状态
//   0x02 taskList        任务列表
//   0x03 schedule        日程
//   0x04 weather         天气
//   0x05 time            时间同步
//   0x10 dayPack         完整每日数据包
//   0x11 taskInPage      任务详情页
//   0x12 deviceMode      设备运行模式
//   0x13 smartReminder   AI 智能提醒
//   0x14 focusStatus     专注状态与能量瓶子数（App→Device 实时推送）
//   0x15 customAvatarFrame 用户自定义伴侣的 96×96 Spectra 6 像素帧（待硬件团队对齐）
//   0x20 eventLogRequest 请求增量 Event Log
//   0x21 eventLogBatch   批量回传 Event Log（Device→App，此 type 仅出现在入站方向）
//   0x7E secureData      安全封装（v2 SecureEnvelope）
//   0x7F securityHandshake 安全握手（v2）
//
// Device → App（入站事件，字节定义见 Models/EventLog.swift 的 EventLogType.rawByte）：
//   0x01 encoderRotateUp        旋钮顺时针
//   0x02 encoderRotateDown      旋钮逆时针
//   0x03 encoderShortPress      旋钮短按
//   0x04 encoderLongPress       旋钮长按
//   0x05 powerShortPress        电源键短按
//   0x06 powerLongPress         电源键长按
//   0x10 enterTaskIn            进入任务详情（触发 App 专注模式）
//   0x11 completeTask           标记任务完成
//   0x12 skipTask               跳过任务
//   0x13 selectedTaskChanged    切换选中任务
//   0x14 wheelSelect            旋钮选择确认
//   0x15 viewEventDetail        查看日历事件详情
//   0x16 reminderAcknowledged   用户确认智能提醒
//   0x17 reminderDismissed      智能提醒超时关闭
//   0x20 requestRefresh         请求数据刷新
//   0x21 eventLogBatch          批量回传事件（含 EventLogType.rawByte 流）
//   0x30 deviceWake             设备唤醒
//   0x31 deviceSleep            设备休眠
//   0x40 lowBattery             低电量

// MARK: - BLE Data Types (App → Device)

/// App 向 E-ink 设备发送的数据类型字节。
/// 与 Device→App 入站事件字节（`EventLogType.rawByte`）分离在不同命名空间，
/// 联调时以本文件为出站协议的唯一参考，入站协议参见 `Models/EventLog.swift`。
public enum BLEDataType: UInt8, Sendable {
    case petStatus = 0x01
    case taskList = 0x02
    case schedule = 0x03
    case weather = 0x04
    case time = 0x05
    case dayPack = 0x10
    case taskInPage = 0x11
    case deviceMode = 0x12
    case smartReminder = 0x13
    /// App→Device: 推送当前专注状态和能量瓶子数
    case focusStatus = 0x14
    /// App→Device: 推送用户自定义伴侣的 96×96 Spectra 6 像素帧
    /// 协议待硬件团队对齐：当前 payload = 1B subVersion(0x01) | 1B width(0x60) | 1B height(0x60) | 4608B 4bpp pixels
    case customAvatarFrame = 0x15
    case eventLogRequest = 0x20
    case eventLogBatch = 0x21
    case secureData = 0x7E
    case securityHandshake = 0x7F
}
