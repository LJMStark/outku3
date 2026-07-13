# Kirole BLE 初次联调指南

**版本:** v0.1.2
**更新日期:** 2026-07-14
**状态:** 第一次硬件联调用
**v0.1.2 变更:** 分包头随 BLE 协议 v2.5.24 由 9 字节更新为 **11 字节**（`Seq`/`Total` 各 2B BE、上限 65535），§2/§4/§5.3 同步；简单包格式不变。

---

## 1. 本次目标

本次只验证 App 和设备能发现、连接、互发基础数据。不验证完整业务，不验证安全握手，不验证离线补传，不验证图片帧。

成功标准很简单：

- App 能搜到设备。
- App 能连接设备。
- App 能发现 `FFE1` Write 和 `FFE2` Notify。
- 设备能收到 App 发来的 `Time(0x05)`。
- 设备能请求刷新并收到 App 发来的 `DayPack(0x10)`。

完整协议参考 `BLE通信协议规格文档.md`。第一次联调以本文为准。

---

## 2. 固件本次必须实现

| 项目 | 固件要做什么 | App 期望 |
|------|--------------|----------|
| 广播 | 广播 Service UUID `0000FFE0-0000-1000-8000-00805F9B34FB` | App 能扫描到设备 |
| GATT | 提供 Write `0000FFE1-0000-1000-8000-00805F9B34FB` 和 Notify `0000FFE2-0000-1000-8000-00805F9B34FB` | App 能完成连接和特征发现 |
| 设备上线通知 / Wake Notify | BLE Notify 开启后，固件**主动**发送 `DeviceWake(0x30)`，payload 为 `BatteryLevel(1B)` | App 更新电量，并写入 `Time(0x05)` 完成时间同步 |
| 时间同步 | 接收 App 写入的 `Time(0x05)` 简单包 | 固件串口打印收到的年月日时分秒 |
| 请求刷新 | Notify 发送 `RequestRefresh(0x20)`，payload 为空 | App 触发数据同步（**联调期 60s 合并窗去抖**：固件勿把 0x20 当 ~2s 心跳狂发，否则整轮 sync 会被合并为 ≤1 次/分，见协议 §8.5）|
| DayPack 接收 | 接收 App 写入的 `DayPack(0x10)`，支持 11 字节分包（v2.5.24） | 固件串口打印 payload 总长度和前几个字段 |

> **语义说明（设备上线通知）**：`DeviceWake(0x30)` **不是 App 唤醒 MCU 的命令**，App 无法也不会触发 MCU 从休眠中醒来。MCU 何时唤醒由固件自行决定（RTC 定时、按键、电源事件等）。完整流程如下：
> 1. MCU 自主唤醒 → 开始广播
> 2. App 扫描到设备 → 建立 BLE 连接 → 完成 GATT 发现 → 开启 Notify
> 3. 固件通过 Notify 发送此帧，通知 App「设备已上线」
>
> 因此，文档中"唤醒事件"旧名已更正为"设备上线通知 / Wake Notify"，避免误解为 App 触发方向。

---

## 3. 本次暂不实现

以下内容不要放进第一次联调验收里，避免同时排查太多问题：

- `SecurityHandshake(0x7F)` 和 `SecureData(0x7E)`。
- `EventLogBatch(0x21)` 离线批量补传。
- `TaskInPage(0x11)` 任务详情页回发。
- `FocusStatus(0x14)` 专注状态实时推送。
- `SmartReminder(0x13)` 智能提醒。
- `WheelSelect(0x14)` 打开任务详情。
- Spectra 6 图片帧传输。
- 分包 ACK 或单包重传。

---

## 4. 本次使用明文协议

第一次联调默认使用明文 BLE 包。

如果 App 包没有配置 `BLE_SHARED_SECRET`：

- 固件不需要实现 HMAC。
- 固件不需要回复安全握手。
- App 会直接发送普通 `Type + Length + Payload` 包或 11 字节分包（v2.5.24）。

安全模式等基础收发稳定后再单独联调。

---

## 5. 包格式速查

### 5.1 App → Device 简单包

```
+--------+-------------+------------------+
| Type   | Length      | Payload          |
| 1 byte | 2 bytes BE  | N bytes          |
+--------+-------------+------------------+
```

例：`Time(0x05)` 的完整包长度固定为 9 字节。

```
05 00 06 YY MM DD HH mm SS
```

### 5.2 Device → App 简单事件

```
+--------+--------+------------------+
| Type   | Length | Payload          |
| 1 byte | 1 byte | N bytes          |
+--------+--------+------------------+
```

例：设备上线通知（Wake Notify），电量 87%：

```
30 01 57
```

例：请求刷新：

```
20 00
```

### 5.3 App → Device 分包

DayPack 通常走 11 字节分包（v2.5.24 起，`Seq`/`Total` 各 2B BE）：

```
+--------+------------+------------+------------+------------+----------+---------+
| Type   | MessageId  | Seq        | Total      | PayloadLen | CRC16    | Payload |
| 1 byte | 2 bytes BE | 2 bytes BE | 2 bytes BE | 2 bytes BE | 2 bytes  | N bytes |
+--------+------------+------------+------------+------------+----------+---------+
```

CRC 使用 CRC16-CCITT-FALSE：

- 多项式：`0x1021`
- 初始值：`0xFFFF`
- XOR out：`0x0000`
- 不反射

当前没有分包 ACK。固件如果发现 CRC 错、缺包或超时，直接丢弃整条消息，等待 App 重新发送。

---

## 6. 推荐测试步骤

1. 固件启动后广播 `FFE0` Service UUID。
2. 打开 App 的设置页，点击设备卡片进入扫描。
3. App 列出设备后，点击设备连接。
4. 固件确认 App 已订阅 Notify。
5. 固件发送 `DeviceWake(0x30)`：

```hex
30 01 64
```

6. App 应写入 `Time(0x05)`，固件打印收到的时间。
7. 固件发送 `RequestRefresh(0x20)`：

```hex
20 00
```

8. App 应写入 `DayPack(0x10)`，固件完成分包重组后打印：

- `payload length`
- 年月日
- `DeviceMode`
- `FocusChallengeEnabled`
- 第一段字符串长度和内容

---

## 7. 成功标准

| 检查项 | 成功表现 |
|--------|----------|
| 扫描 | App 能看到设备名 |
| 连接 | App 设备卡片显示已连接 |
| Notify | 固件发送 `30 01 xx` 后 App 电量显示更新 |
| Time | 固件串口看到 `05 00 06 ...` |
| RequestRefresh | 固件发送 `20 00` 后 App 有写入动作（**首次或距上次 ≥60s 时**；60s 合并窗内重复的 0x20 会被去抖、无写入，属正常，见协议 §8.5）|
| DayPack | 固件能完成分包重组，并能解析日期和第一段字符串 |

---

## 8. 常见问题

### App 搜不到设备

优先检查广播包里是否包含 Service UUID `FFE0`。App 不是按设备名扫描。

### App 连接后没有数据

检查固件是否提供了正确的 Write / Notify characteristic，并确认 Notify 已开启。

### 想确认 App 到底收发了哪些帧

DEBUG 包与 TestFlight 包可用 Console.app（或 `log stream`）过滤 `subsystem:com.kirole.app category:BLE` 查看 App 的 BLE 收发帧摘要：TX 记录 `type/len`，RX 记录 `len/firstByte`。可据此判断「固件发出的帧 App 有没有收到」「App 写出的帧类型 / 长度对不对」。正式 App Store 包关闭此日志，且不记录完整 payload。

### 收到 `0x14` 不知道怎么解释

先看方向：

- App 写给设备的 `0x14` 是 `FocusStatus`。
- 设备 Notify 给 App 的 `0x14` 是 `WheelSelect`。

第一次联调不需要处理 `0x14`。

### DayPack 分包收不完整

先只打印每包的 `MessageId / Seq / Total / PayloadLen / CRC`。确认所有 `Seq` 都收到后再解析 payload。
