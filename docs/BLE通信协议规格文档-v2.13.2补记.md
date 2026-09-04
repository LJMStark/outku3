# BLE 通信协议规格文档 v2.13.2 补记

> **已回写主规格（2026-09-04）。** 本补记的全部内容已合并进 `docs/BLE通信协议规格文档.md` v2.13.3 的 §4.23.2、§4.23.4、§5.15，主规格本身即为 Ver 1.3.1 口径。本文件仅保留为变更记录；以主规格为准。

**日期:** 2026-08-19  
**原因:** 硬件 Ver 1.3.1 覆盖了 1.3.0 里互相打架的 RESULT / COMMIT 边界。本补记覆盖 `v2.13.1补记` 与主规格 v2.13.0 的过时句子。

权威阅读顺序：

1. `docs/专注状态重连协议变更_Ver_1_3_1.md`
2. `docs/Kirole_BLE协议命令字节表_专注重连协议更新_Ver_1_3_1.md`
3. 本补记
4. `docs/Kirole_专注状态重连_App对接说明_Ver_1_3_0.md`（裁决表 §9 仍有效）
5. `docs/BLE通信协议规格文档.md` 其余未改章节
6. `docs/专注重连-与硬件协商项_Ver_1_3_1.md`

## 覆盖 v2.13.1 补记 / 主规格的句子

| 位置 | 旧写法（1.3.0 App 实现 / v2.13.1 补记） | 1.3.1 固件原文 / App 现实现 |
|---|---|---|
| 补记 v2.13.1 RESULT 行 | 字节表无 `FOCUS_RESOLVE` 应答；发出即解锁 | 设备必须回 `RESULT(SyncId=ResolveID, TargetType=0x25)`。只有 `ResultCode=COMMITTED(0x02)` 才解除 `focusSyncLocked`。`ACCEPTED(0x00)` 已接收但未落地，继续等。超时重试复用同一 `ResolveID` 和同一 payload |
| 主规格 §4.23.2 / 步骤 6 | 等 `RESULT=accepted` 或发出即继续 | `ResolveResult` 是 App 裁决结论；`RESULT.ResultCode` 是设备执行应答。两者不能混用。解锁三条件：`SyncId==ResolveID` 且 `TargetType==0x25` 且 `ResultCode==COMMITTED` |
| 补记 v2.13.1 COMMIT 行 | 裁决后不因专注仍在而强制 COMMIT；`NeedsFullSync` 仍可 COMMIT | 专注重连不要求发 DayPack。普通 `0x10` 只更新业务数据，**不会**退出 TaskIn。活动专注期间**禁止** OfflineSync `COMMIT`，需要提交的数据延后到退出专注后。`COMMIT` 不能代替专注裁决 |
| 主规格 §4.23.4 步骤 8 | 设备要求全量同步时除外，active 也可 COMMIT | 与上同：active 期间一律不 COMMIT |
| 主规格 §5.15 批内 `0x10/0x11/0x12` | 正文仍写旧 `6+N` / v2.9 `11+N`（主规格超行数上限，不在原文上改） | 以本补记为准。与实时事件同一 v2：`0x10` 记录 `19+N`，`0x11/0x12` 记录 `23+N`（`SubVersion 0x02` + `FocusSessionId` 8B）。旧格式整批丢弃 |
| 硬件字节表 1.3.1 §5.15 批内表 | 仍抄 v2.9：`0x10`=`6+N`，`0x11/0x12`=`11+N` | **不要改硬件原文。** 同表 §5.3–5.5 已是 v2。入批与 OP_BATCH 跟 §5.3–5.5 与本补记，不跟 §5.15 那两行旧字 |

## 未改的主规格内容

`0x14` / Enter / Complete / Skip / Schedule v2 线格式、OfflineSync 底盘、`0x1B`、安全封装仍以主规格对应章节为准，并与 1.3.1 字节表核对偏移。`0x12 DeviceMode` 仍不得进入、退出或裁决专注。硬件 1.3.1 字节表 §5.15 批内 `0x10/0x11/0x12` 两行除外，见上表。
