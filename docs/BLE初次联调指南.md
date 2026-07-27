# Kirole BLE 初次联调指南

**版本:** v0.2.0
**更新日期:** 2026-07-27
**状态:** BLE v2.9.0 第一次联调与任务状态正式验收
**v0.2.0 变更:** 对齐 BLE v2.9.0 flag-day：RequestRefresh 改为严格 v1 + 非零 RequestID，新增 `0x1B TaskListSnapshotAck` 业务确认；加入 Complete/Skip 非零 OperationID、幂等重试、版本化原子替换、Skip 保留任务和旧离线日志清理验收。空 payload `0x20` 与旧 Complete/Skip 格式不再接受。
**v0.1.2 变更:** 分包头随 BLE 协议 v2.5.24 由 9 字节更新为 **11 字节**（`Seq`/`Total` 各 2B BE、上限 65535），§2/§4/§5.3 同步；简单包格式不变。

---

## 1. 本次目标

本次分两道门：先验证 App 和设备能发现、连接、互发基础数据；再验收 v2.9.0 的任务完成/跳过/刷新状态同步。不验证安全握手、图片帧或完整页面美术。

成功标准很简单：

- App 能搜到设备。
- App 能连接设备。
- App 能发现 `FFE1` Write 和 `FFE2` Notify。
- 设备能收到 App 发来的 `Time(0x05)`。
- 设备发送 v1 `RequestRefresh(0x20)` 后，立即收到匹配的 `TaskListSnapshotAck(0x1B)`。
- 完成任务后 App 的权威快照移除该任务；跳过任务后快照仍保留该任务。
- DayPack 可按内容变化另行到达，但不再作为任务动作的业务确认。

完整协议参考 `BLE通信协议规格文档.md`。第一次联调以本文为准。

---

## 2. 固件本次必须实现

| 项目 | 固件要做什么 | App 期望 |
|------|--------------|----------|
| 广播 | 广播 Service UUID `0000FFE0-0000-1000-8000-00805F9B34FB` | App 能扫描到设备 |
| GATT | 提供 Write `0000FFE1-0000-1000-8000-00805F9B34FB` 和 Notify `0000FFE2-0000-1000-8000-00805F9B34FB` | App 能完成连接和特征发现 |
| 设备上线通知 / Wake Notify | BLE Notify 开启后，固件**主动**发送 `DeviceWake(0x30)`，payload 为 `BatteryLevel(1B)` | App 更新电量，并写入 `Time(0x05)` 完成时间同步 |
| 时间同步 | 接收 App 写入的 `Time(0x05)` 简单包 | 固件串口打印收到的年月日时分秒 |
| 请求刷新 | Notify 发送严格 v1 `RequestRefresh(0x20)`：`01 + RequestID(4B BE, nonzero)` | App 立即回匹配 `0x1B`；完整 DayPack sync 仍可能受 60s 合并窗和指纹去重 |
| 任务动作 | Complete/Skip 发送严格 v1：`01 + OperationID(4B BE, nonzero) + TaskIdLength + TaskId + Timestamp(4B BE)` | App 幂等处理并立即回匹配 `0x1B` |
| 任务快照 | 解析 App 写入的 `TaskListSnapshotAck(0x1B)`，校验 Action+OperationID 与 StateEpoch+Revision | 整包合法后原子替换整个 Overview 任务清单 |
| DayPack 接收 | 接收 App 写入的 `DayPack(0x10)`，支持 11 字节分包（v2.5.24） | 固件串口打印 payload 总长度和前几个字段 |

> **确认边界：** GATT withResponse 只表示特征写入获得传输响应。设备可以先显示 pending，但只有匹配且版本更新的 `0x1B` 才能提交任务清单。App 是最终任务状态来源；`0x02 TaskList` 是 legacy，不能用于本流程。

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
- `EventLogBatch(0x21)` 的完整离线压力测试（但 v2.9 上线前必须完成本文的迁移/格式验收）。
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
20 05 01 00 00 00 2B
         ^^^^^^^^^^^ RequestID=43, nonzero
```

空 payload 旧帧 `20 00` 自 v2.9.0 起必须拒绝。

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

### 5.4 TaskListSnapshotAck (0x1B)

App→Device payload：

```text
SubVersion(1) | Action(1) | OperationID(4B BE) | Result(1) |
StateEpoch(4B BE) | Revision(4B BE) | TaskCount(1) | Tasks[]
```

Result：`00 applied`、`01 alreadyApplied`、`02 taskNotFound`、`03 invalidRequest`、`04 supersededByApp`、`FF internalError`。Task：`TaskId LP≤36 + Title LP≤30 + IsCompleted(1) + Priority(1)`，LP=`Length(1B)+UTF-8 bytes`。TaskId 必须直接取当前 DayPack/`0x1B` 下发的硬件任务 ID并逐字节回传；它不保证等于外部平台原始 ID，固件不得截断或重建。

空任务清单的 Complete 确认示例：

```hex
1B 00 10                              # Type + App->Device Length=16
01 11 00 00 00 2A 00                 # v1, Action=Complete, OperationID=42, applied
12 34 56 78 00 00 00 07 00           # StateEpoch, Revision=7, TaskCount=0
```

固件接收规则：

- Action+OperationID 必须与 pending 完全匹配。
- epoch 改变时只接受新 epoch 的 `revision=1`；同 epoch 只接受更大 revision。
- 全部长度校验通过后一次性替换整个任务清单。只含当天未完成任务：4 寸最多 3 项、7.3 寸最多 5 项。
- Complete 后任务消失；Skip 后任务保留。`taskNotFound/invalidRequest/supersededByApp` 也要撤销设备自行删除并采用 App 快照；`supersededByApp` 表示 App 新状态优先，结束 pending 后不得再重试旧动作。
- DayPack 与 `0x1B` 必须完整重组、校验后再应用；两类完整任务状态消息不会分片交错。
- App 对同一 revision 的短重试逐字节复用同一 `0x1B` payload；固件收到相同 revision 时保持现状即可。

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
7. 固件生成非零 RequestID=43，发送 v1 `RequestRefresh(0x20)`：

```hex
20 05 01 00 00 00 2B
```

8. App 应立即写入 `TaskListSnapshotAck(0x1B)`。固件确认 Action=`0x20`、OperationID=`43`，并记录 StateEpoch/Revision 后原子替换任务清单。
9. App 可按内容变化另行写入 `DayPack(0x10)`；若收到，固件完成分包重组后打印：

- `payload length`
- 年月日
- `DeviceMode`
- `FocusChallengeEnabled`
- 第一段字符串长度和内容

10. 从当前 `0x1B.Tasks[]` 取一个真实 TaskId，进入 Task In。完成时生成 OperationID=42，发送：

```text
11 | PayloadLength |
01 | 00 00 00 2A | TaskIdLength | TaskId | Timestamp(4B BE)
```

收到 Action=`0x11`、OperationID=42 的更新版本 `0x1B` 后，确认该 TaskId 已从完整清单移除。

11. 模拟确认丢失：**原样重发**第 10 步完整帧。App 应回首次处理时缓存的 Result + 新快照，任务状态不得再次翻转。
12. 对另一真实任务发送 Skip v1。收到 Action=`0x12` 的 `0x1B` 后，确认专注结束但该任务仍在清单（排序/当前选择允许变化）。
13. 用已处理的同一 OperationID 修改 TaskId 或 Timestamp 再发。App 应回 `invalidRequest(0x03)`，设备撤销 pending 并采用快照。
14. 顺序测试版本：同 epoch 的相同/更小 revision 不应用；更大 revision 应用。模拟 epoch 改变后，只接受新 epoch 的 `revision=1`。
15. 固件升级迁移测试：清空旧 `0x11/0x12/0x20` 离线环形记录；确认 `0x20` 不会写入新 EventLogBatch。
16. 构造一个 Records 线序为 Complete→Skip、但 RTC Timestamp 倒序的 EventLogBatch。App 应仍按 Records 线序处理并按线序回两帧 `0x1B`；固件不得自行按 Timestamp 排序。
17. 模拟 App 在写入 pending 后退出，再原样重发。动作应幂等恢复，不能因账本中有记录就跳过未落盘状态。模拟 GATT 回调丢失时，两次相同 revision 的 `0x1B` 业务 payload 必须逐字节一致。
18. 在设备 Complete 写前账本落盘后，由 App 立即执行完成撤销或编辑任务，再让设备请求继续。App 应回 `supersededByApp(0x04)`，固件采用快照且不得再次重试旧完成动作。另用旧 Skip 对已重新开始的同任务专注重放，确认新专注不被结束。
19. 断电测试：固件在接收 `0x1B` 的原子提交点前后各断电一次。重启后 `StateEpoch + Revision + Overview` 必须全旧或全新，不能版本已推进而列表仍旧。

---

## 7. 成功标准

| 检查项 | 成功表现 |
|--------|----------|
| 扫描 | App 能看到设备名 |
| 连接 | App 设备卡片显示已连接 |
| Notify | 固件发送 `30 01 xx` 后 App 电量显示更新 |
| Time | 固件串口看到 `05 00 06 ...` |
| RequestRefresh | 固件发送合法 v1 请求后，立即收到 Action/RequestID 匹配的 `0x1B`；不再用 DayPack 是否重发判断响应 |
| TaskListSnapshotAck | Action+OperationID 匹配；epoch/revision 只向前；整包原子替换，4 寸≤3、7.3寸≤5 |
| Complete | 匹配 `0x1B` 移除任务；原样重试返回首次缓存的 Result 且不重复执行 |
| Skip | 匹配 `0x1B` 结束 pending，但任务仍保留 |
| 冲突 ID | 同一 OperationID 改 payload 返回 invalidRequest，设备不提交本地删除 |
| App 新状态优先 | 收到 supersededByApp 后采用快照、结束 pending，不覆盖 App 撤销/编辑，也不结束更新专注会话 |
| DayPack | 若内容变化而收到，固件能完成分包重组并解析；未重发不算任务确认失败 |
| 离线迁移 | 升级后无旧格式记录；EventLogBatch 仅含 v1 Complete/Skip，不含 RequestRefresh |
| 离线顺序 | RTC Timestamp 倒序时仍按 EventLogBatch Records 线序处理并逐条匹配 `0x1B` |
| 崩溃/回调丢失 | pending 后退出可由原请求恢复；同一 revision 的 `0x1B` 短重试字节完全一致 |
| 固件断电原子性 | StateEpoch、Revision、Overview 清单全旧或全新，不出现分裂状态 |

---

## 8. 常见问题

### App 搜不到设备

优先检查广播包里是否包含 Service UUID `FFE0`。App 不是按设备名扫描。

### App 连接后没有数据

检查固件是否提供了正确的 Write / Notify characteristic，并确认 Notify 已开启。

### 发送 RequestRefresh 后没有 DayPack

先检查 RequestRefresh 是否为严格 v1：`20 05 01 <RequestID 4B BE>`，RequestID 必须非零；旧 `20 00` 会被拒绝。再检查是否收到 Action=`0x20`、OperationID=本次 RequestID 的 `0x1B`。`0x1B` 是任务刷新业务确认并立即返回；DayPack 仍受 60 秒完整同步合并窗和内容指纹影响，内容未变时不重发是正常行为。

### 完成后设备清单与 App 不一致

不要在短按后永久提交设备本地删除。先显示 pending，等待匹配且 StateEpoch/Revision 更新的 `0x1B`，然后整表原子替换。超时只能原样重发同一 OperationID/TaskId/Timestamp；生成新 ID 会绕过幂等保护。

### 想确认 App 到底收发了哪些帧

DEBUG 包与 TestFlight 包可用 Console.app（或 `log stream`）过滤 `subsystem:com.kirole.app category:BLE` 查看 App 的 BLE 收发帧摘要：TX 记录 `type/len`，RX 记录 `len/firstByte`。可据此判断「固件发出的帧 App 有没有收到」「App 写出的帧类型 / 长度对不对」。正式 App Store 包关闭此日志，且不记录完整 payload。

### 收到 `0x14` 不知道怎么解释

先看方向：

- App 写给设备的 `0x14` 是 `FocusStatus`。
- 设备 Notify 给 App 的 `0x14` 是 `WheelSelect`。

第一次联调不需要处理 `0x14`。

### DayPack 分包收不完整

先只打印每包的 `MessageId / Seq / Total / PayloadLen / CRC`。确认所有 `Seq` 都收到后再解析 payload。
