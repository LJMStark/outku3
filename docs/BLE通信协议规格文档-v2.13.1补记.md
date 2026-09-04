# BLE 通信协议规格文档 v2.13.1 补记

**日期:** 2026-08-19  
**原因:** `docs/BLE通信协议规格文档.md` 已超过仓库单文件行数上限，本补记回写与硬件 Ver 1.3.0 冲突的条目。合并进主规格前，以本文件 + 固件原文为准。

> **已过时。** 硬件 Ver 1.3.1 覆盖了本补记里「FOCUS_RESOLVE 无 RESULT / 发出即解锁」和「NeedsFullSync 仍可在 active 时 COMMIT」两句。现行口径已回写主规格：请读 `docs/BLE通信协议规格文档.md` v2.13.3 §4.23.2 / §4.23.4 / §5.15。

权威阅读顺序（历史，仅 1.3.0）：

1. `docs/Kirole_专注状态重连_App对接说明_Ver_1_3_0.md`
2. `docs/Kirole_BLE协议命令字节表_专注重连协议更新_Ver_1_3_1.md`（1.3.0 字节表 Markdown 已删）
3. 本补记（覆盖主规格 v2.13.0 里仍写成 App 加戏的句子；RESULT / COMMIT 以 v2.13.2 补记为准）
4. `docs/BLE通信协议规格文档.md` 其余未改章节
5. `docs/专注重连-与硬件协商项_Ver_1_3_0.md`

## 覆盖主规格 v2.13.0 的句子

| 主规格位置 | v2.13.0 写法 | 1.3.0 固件原文 / App 现实现 |
|---|---|---|
| 修订史 v2.13.0 ②、§4.23.2 FOCUS_RESOLVE、§4.23.4 步骤 6 | 设备用 `RESULT(TargetType=0x25, SyncID=ResolveID)` 确认后再解锁 | 字节表无此应答。发出 `FOCUS_RESOLVE` 后即解锁，恢复普通 `0x14` / `0x11` / `0x10` / `0x03` |
| §4.23.1 RESULT 行 | 「返回暂存、提交或 FOCUS_RESOLVE 结果」 | RESULT 只服务 BEGIN / COMMIT / ABORT |
| §4.23.3 STATE overflow | 溢出一律不 BEGIN | 仅溢出：ACK 后结束。溢出 + `NeedsFullSync`：完整核对 COMMIT |
| §4.23.4 步骤 8 隐含 | 裁决后仍 active 也强制 COMMIT | 不因专注仍在而打洞 COMMIT；设备要求全量同步时除外 |
| §5.3 未知任务 | 回发 `DeviceMode(0x12)=Interactive` | 改发 `0x14 idle`。`0x12` 不得进出或裁决专注 |

## 未改的主规格内容

`0x14` / Enter / Complete / Skip / Schedule v2 线格式、OfflineSync 底盘、`0x1B`、安全封装仍以主规格对应章节为准，并与字节表核对偏移。
