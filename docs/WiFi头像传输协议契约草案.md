# Kirole WiFi 头像传输协议契约草案

**版本:** v0.1.0（草案，待固件评审）
**创建日期:** 2026-07-24
**关联:** BLE 通信协议规格文档 §4.20 / §5.20（`0x1A WiFiAvatarSession`）、`KRI_图片转换规范.md`
**状态:** App 先行定案，固件按本草案实现设备侧 SoftAP HTTP 收图端点。评审通过后并入正式协议编号。

---

## 1. 概述

### 1.1 目的

自定义头像走 BLE `0x15` 分包传输太慢——单张 800×700 KRI ≈ 2.14 MiB，切成 ~5000 分包 + 逐包 ACK + 20 写/秒限流 + secure 逐包 HMAC，硬地板 **4–5 分钟**。本契约定义一条 **WiFi(SoftAP) 快速传输通道**：App 加入设备自建热点后，一次整块 HTTP 上传 KRI，把传输压到**秒级**。

### 1.2 通道分工（关键）

| 层 | 通道 | 职责 |
|----|------|------|
| **握手/会话** | BLE `0x1A WiFiAvatarSession`（§4.20/§5.20） | 开/关 SoftAP、下发热点凭据 + HTTP 端点、绑定 OperationID |
| **头像字节** | **WiFi HTTP POST（本契约）** | 一次整块上传裸 KRI 到设备端点 |
| **事务确认** | BLE `0x22 AvatarControl`（§4.19/§5.19） | **完全不变**：staged → commit → committed |

**头像字节的到达方式（WiFi vs BLE）对 App 的事务状态机透明**。这条契约只替换"字节怎么送到设备"，不碰暂存/提交/擦除/恢复语义。

### 1.3 架构

复用 ESP32-S3 已有的"设备自建 SoftAP + 本地 HTTP 服务器"骨架（与 OTA `update.bin` 上传、`0x19` PC 调试同源），**新增一个程序化收图端点**——区别于 OTA 的人工网页上传，本端点由 App 以编程方式 `POST`。

```
App ──BLE 0x1A open(OperationID)──▶ 设备启 SoftAP + HTTP 端点
App ◀──BLE 0x1A 应答{SSID,pass,gateway,port,path,token,ttl}── 设备
App ──加入设备热点(NEHotspotConfiguration)──▶ 连上 gateway(192.168.4.1)
App ──HTTP POST <path> 裸 KRI + headers──▶ 设备端点
设备 ──落盘 + CRC 校验通过──▶ 【强约束】BLE 主动发 0x22 staged
App ◀──BLE 0x22 staged── 设备；App 发 0x22 commit ──▶ 设备原子提交
App ──BLE 0x1A close──▶ 设备停 SoftAP；App removeConfiguration 恢复家庭网
```

---

## 2. SoftAP 会话生命周期

会话由 BLE `0x1A` 驱动（详见 BLE 规格 §4.20/§5.20），要点：

1. **open（`0x01`）**：设备启动 SoftAP + HTTP 端点，生成会话专用**一次性 token**（绑 OperationID），BLE 应答回报 `{SSID, Passphrase, Gateway, Port, Path, Token, TTL}`。
2. **close（`0x00`）**：设备停止 SoftAP + HTTP 端点，token 立即失效。App 在传输**成功或失败后都发** close。
3. **query（`0x02`）**：只读当前会话状态。
4. **TTL**：设备在 TTL 秒内未收到有效上传则自动关闭会话（防止 App 崩溃后 SoftAP 长开）。建议 TTL ≥ 120s。
5. **互斥**：SoftAP 硬件与 `0x19` PC 调试共用，逻辑互斥，占用时 open 回 `Status=busy`。
6. **BLE 共存**：SoftAP 期间必须保持 BLE 可用，不得主动断 BLE。

---

## 3. HTTP 收图端点契约

### 3.1 请求

```
POST http://<Gateway>:<Port><Path>          例：POST http://192.168.4.1/avatar
```

**请求头：**

| Header | 必填 | 说明 |
|--------|------|------|
| `Content-Type` | 是 | `application/octet-stream` |
| `Authorization` | 是 | `Bearer <token>`，token 取自本次 `0x1A open` 应答，绑定 OperationID |
| `X-Kirole-Operation-Id` | 是 | 8 位十六进制（4B BE 的 OperationID），必须与 `0x1A open` 的 OperationID 一致 |
| `X-Kirole-Avatar-Id` | 是 | 头像 UUID（36 字符标准格式或 32 位 hex），= 伴侣 AvatarID |
| `X-Kirole-File-Length` | 是 | KRI 字节数（十进制），= body 长度 |
| `X-Kirole-File-CRC32` | 是 | 8 位十六进制，KRI 文件字节的 CRC-32/IEEE |
| `Content-Length` | 是 | 同 `X-Kirole-File-Length` |

**请求体：** 裸 KRI 文件字节（12B 小端头 + 逐行直通 alpha 的 BGRA 裸像素，格式见 `KRI_图片转换规范.md`）。**不含** BLE 的 `0x15` v4 帧头（OperationID/AvatarID/CRC 已在 HTTP header 里）。上限 2,240,012 B（800×700）。

> **备选（评审可选）**：body 也可直接放 `0x15` v4 的 29B 头 + KRI，让固件复用现有 `0x15` 解析器。**本草案默认"headers + 裸 KRI"**，因为设备可边收边写 flash、无需缓冲帧头；二选一由固件评审拍板，定案后本节收敛为唯一格式。

### 3.2 设备校验（收完后）

1. token 有效且未过期 → 否则 `401`。
2. `X-Kirole-Operation-Id` == 当前会话 OperationID → 否则 `409`。
3. body 长度 == `X-Kirole-File-Length` == `Content-Length` → 否则 `400`。
4. KRI 头合法（magic `4B 52 49 01`、colorFormat/version、`fileSize == 12 + w*h*4`，见 KRI 规范 §7）→ 否则 `400`。
5. body 的 CRC-32/IEEE == `X-Kirole-File-CRC32` → 否则 `400`。
6. 全部通过 → 落盘到临时头像文件（同 `0x15` 暂存语义），返回 `200`，**并立即经 BLE 发 `0x22 staged`**（见 §4）。

### 3.3 响应

**成功 `200`：**

```json
{ "status": "staging", "operationId": "1a2b3c4d", "avatarId": "…", "crc32": "…", "byteLength": 2240012 }
```

**错误：**

| 状态码 | 含义 |
|--------|------|
| `400` | CRC/长度不符 或 KRI 头非法 |
| `401` | token 缺失/错误/过期 |
| `409` | OperationID 与当前会话不匹配 / 设备忙 |
| `413` | body 超过 2,240,012 B 上限 |
| `500` | 落盘或内部错误 |

App 对任何非 `200`（含超时/连接失败）→ 发 `0x1A close` 收尾并回退 BLE `0x15`。

---

## 4. 强约束：收完即发 0x22 staged

**这是本契约与事务确认层的唯一衔接点，必须严格实现：**

> 设备通过 HTTP 收完整块 KRI、CRC 校验通过、落盘到临时文件后，**必须照 BLE `0x15` 路径主动发一帧 `0x22 AvatarControlResult` with `Status=staged`（§5.19），字节与 `0x15` 后那帧完全相同**（OperationID/AvatarState=staged/AvatarID/FileLength/FileCRC32 均指向刚收下的候选）。

- HTTP `200` 仅表示"字节已收、正在暂存"，**不**是持久化成功；App 不把 HTTP 200 当作 staged。
- App 收到 BLE `0x22 staged` 后走 `validateStagedResult` → 发 `0x22 commit` → 等 `0x22 committed` → 才切换身份。整条链与 BLE 传输路径**逐字节相同**。
- 若设备只回了 HTTP 200 但未发 BLE `0x22 staged`，App 会在 staged 等待超时后按失败处理（可能回退 BLE 重传）。

---

## 5. 幂等与恢复

- **上传幂等**：同 OperationID 的重复 `POST`（App 重试/网络抖动）应返回 `200` 并复用同一暂存结果，不重复占用 flash；对齐 `0x22` "同 OperationID 不重复执行"哲学。
- **恢复**：WiFi 传输中断（热点掉线/App 后台化）后，App 走既有 `0x22 query` 恢复流程判断 committed/staged/retransmit——**与 BLE 路径共用**，无需 WiFi 专属恢复。重传可选 WiFi 或 BLE（App 决策）。
- **不做字节级断点续传**：WiFi 传输失败即整块重来（HTTP 一次整块，天然无分片续传需求）。

---

## 6. 与 OTA 网页服务的区别

| 维度 | OTA `update.bin`（§4.17） | WiFi 头像（本契约） |
|------|--------------------------|---------------------|
| 上传方 | 人（PC 浏览器手动上传） | App（程序化 POST） |
| 端点 | 固件自带网页表单 | 程序化 `POST <path>` + Bearer token |
| 触发 | 用户操作 + `0x18` 重启 | BLE `0x1A` 握手 + HTTP |
| 确认 | `0x18` OTAResult | `0x22 staged`（复用头像事务层） |

两者可复用同一 SoftAP + HTTP server 基础设施，但**头像端点需要程序化鉴权（token）与 CRC 校验**，OTA 的人工网页表单不满足，故新增。

---

## 7. 安全考量

- **token**：会话一次性、绑 OperationID、TTL 短；`close` 或 TTL 到期立即失效。防止 SoftAP 开着期间被同网其他设备 POST 脏图。
- **密码经 BLE 下发**：`0x1A open` 应答含 SoftAP 密码，属本地临时 AP 一次性凭据；secure 模式（`0x7E`）下加密传输，dev 模式明文。风险面 = 攻击者需同时嗅探 BLE + 在 TTL 窗内接入本地 AP + 猜中 token，且只能污染一次暂存（commit 前 App 会 `validateStagedResult` 比对 CRC）。
- **App 侧**：App 用 `NEHotspotConfiguration`（`joinOnce`）加入，传输完 `removeConfiguration` 立即退出；HTTP 请求强制走 WiFi 接口、禁蜂窝，避免请求泄漏到公网。

---

## 8. 固件实现清单

- [ ] BLE `0x1A WiFiAvatarSession` open/close/query + `0x1A` 应答回报凭据（§4.20/§5.20）。
- [ ] SoftAP 启停 + 会话一次性 token 生成/失效 + TTL 自动关闭。
- [ ] HTTP `POST <path>` 端点：Bearer 鉴权、header 校验、body 长度/CRC-32 校验、KRI 头校验。
- [ ] 落盘到临时头像文件（复用 `0x15` 暂存路径）。
- [ ] **收完 CRC OK 后经 BLE 主动发 `0x22 staged`**（字节同 `0x15` 路径）。
- [ ] 上传幂等（同 OperationID 重复 POST 复用结果）。
- [ ] `0x1A` 与 `0x19` SoftAP 互斥、SoftAP 期间保持 BLE。
- [ ] 错误码 400/401/409/413/500 按 §3.3。
