# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The authoritative rules, BLE protocol, and full subsystem detail live in `./AGENTS.md`.
Read it before any non-trivial change. Repo-specific playbooks (change gates, runbooks, acceptance checklists, failure archaeology) live in `.claude/skills/` — start at `.claude/skills/kirole-atlas/SKILL.md`, which routes by the task you are about to do. (There is no `.cursor/rules/` — the XcodeBuildMCP scaffold's Cursor rules were never committed.)

## Interaction Rules
1. Every response must begin with **B哥**.
2. Respond in **Simplified Chinese**. For non-technical questions, keep language plain and explain jargon inline.
3. Treat `/Users/demon/vibecoding/outku3` as the strict workspace boundary. Unqualified requests ("build", "commit", "run tests") always refer to this repo.
4. **English-only product UI (CRITICAL).** This is an English-language product. ALL user-facing copy — companion dialogue, notification titles/bodies, banners, button labels, on-device E-ink text — must be English. Chinese is allowed ONLY in code comments and assistant↔user chat. Never introduce Chinese into a displayed string (this is why AI output is never localized to the user's language). Pre-existing Chinese UI strings are tech debt to clean up, not a pattern to follow.

## Product Identity (READ FIRST)
Kirole 是 **硬件优先的宠物陪伴产品**：硬件 E-ink 设备是用户主要的日常交互入口，App 是给硬件配置数据的工具。任务和日历事件主要作为 **prompt 上下文** 驱动宠物对话，**不是给用户管理待办用的**。任何把 task/event 当"待办"来增强（AI 任务拆解、详情页步骤展开、催促式提醒等）的提议都偏离产品定位，应直接拒绝或反向清理。

**Pet 页面布局是设计内容（客户需求，勿动）**：上半部分显示宠物形象，下半部分是任务列表 UI（Tasks Today / Upcoming / No Due Dates，含 checkbox / Edit / Delete）。这是刻意的产品设计，不是"待办增强"。

**硬件优先意味着**：硬件离线时用户操作不能丢。两条补传通道都是核心功能，不是可选项：

1. `0x21 eventLogBatch`：设备批量回推事件（高水位去重），`BLEEventHandler` 必须把每条应用到 AppState（任务完成状态、专注会话等）。
2. `0x25 offlineSync`（`BLEOfflineSyncCoordinator`）：离线操作补报 ACK，以及 TaskList / Schedule / DayPack 的原子提交。Ver 1.3.1 起专注重连顺序是 `FOCUS_STATE` → `OP_BATCH` → `OP_ACK` → `FOCUS_RESOLVE` → `RESULT/COMMITTED`，只有匹配的 `COMMITTED` 才解除普通 `0x14`。活动专注期间禁止 dataset `COMMIT`。BLE 断连**不再结束**专注；挡板保持，重连后再裁决。

专注重连 / Schedule v2 以硬件 Ver 1.3.1 原文为准，不要用旧流程图或「断连就撤挡板」覆盖协议。阅读顺序见文末 `docs/`。

**一账号 = 一活跃设备（单设备模型，READ）**：Supabase 数据按登录账号（`userId`）存，但产品是"一台手机配一台硬件"。同一账号**不预期同时在多台设备上活跃**——换机 / 重装是**顺序**事件（旧机退役 → 新机登录拉云端、`max` 合并恢复），不是并发。因此跨设备同步（能量瓶子、宠物状态）**不存在多写者并发**：分布式多写竞态（如"远端写非单调 / 较低值覆盖较高值"）**不适用本产品，勿当 bug 报**。与"不做 Watch / Mac / 家庭共享"定位一致。将来若真做多设备陪伴端，再引入 DB 端 `max` / 条件更新。

三条核心数据流：

1. **任务/事件 → Prompt → 宠物对话**
   `appState.tasks/events` → `DayPackGenerator` / `CompanionTextService` → `OpenAIService`。家页伴侣槽显示**单一、随时段变脸**的 `currentPetDialogue`（晨安 / 任务鼓励 / 结算语，由 `AppState+Companion.resolveCompanionPhase` 选型；亦可切日俳句模式），DayPack 另带**中性面板文本** `daySummary`（框②，`OpenAIService.generateDaySummaryText` 非人格生成）+ `firstUp`（框③）；三者经 BLE 推给硬件。**宠物口吻只在 `currentPetDialogue` 一句**——v2.5.0 起旧的多输出 `morningGreeting / dailySummary / companionPhrase` 已收敛，面板文本一律中性。

2. **App → 硬件同步有节流，不立刻 push**
   `BLESyncCoordinator.performSync()` + `BLESyncPolicy`：白天 08-23 每 1 小时；夜间 23-08 每 4 小时。触发时机：iOS `BGAppRefreshTask`、硬件主动发 `0x20`/`0x30`、DayPack 指纹变化或 `force: true`。**用户加任务后硬件不会立刻显示**，要等下一个 sync。

3. **硬件 → App 反向触发专注模式**
   在线：硬件点击任务 → `0x10 enterTaskIn`（v2）→ `BLEEventHandler` → `FocusSessionService.startSession(...)` → 专注链路启动。找不到任务时发 `0x14 idle`，**不要**用 `0x12 DeviceMode` 进出专注。
   离线：设备本地立即进入/退出并入队；重连走 `0x25` 裁决（`FocusReconnectArbiter`），不要用 App 缓存的 `idle` 盖掉设备 `active`。裁决与"要不要发 `FOCUS_RESOLVE`"只能用 `FocusReconnectProtocol.swift` 上的命名谓词（`hasNoArbitrableFocusContent` / `takesIdleShortCircuit` / `isContentEmptyIdleSnapshot` / `isMeaninglessIdleSnapshot`），不要在调用点内联重写 idle 判断——2026-09-03 的「连上 ~10s 就断、永远连不回」就是两套 idle 谓词打架：仲裁器短路成全零 idle 裁决，跳过逻辑却认为快照有内容，设备回 `INVALID_STATE`。这些谓词**刻意容忍**固件在空闲快照里带非零 `LastOperationID`（字节表要求为零）；这是对固件偏离的容忍，不是合规修复，别"修回"字节表原文。

## Development Rules
1. After any frontend / UI change, rebuild and launch the simulator to visually verify. Do not mark UI work complete without this check.
2. The project is in rapid iteration: `LocalStorage`, `UserDefaults`, on-device JSON, and BLE payload shapes are disposable. Prefer resetting local data over writing migration shims until hardware/TestFlight consumers exist (see AGENTS.md §2 "Current Phase Policy").

## Architecture at a Glance

### Package Structure
- **Workspace**: Open `Kirole.xcworkspace`. App shell in `Kirole/`; all feature code in `KirolePackage/Sources/KiroleFeature/`; the DeviceActivity monitor extension lives in `KiroleDeviceActivityMonitor/` at repo root (separate appex target, see below).
- New code almost always belongs in the package. No manual file adding to Xcode targets — `KirolePackage` uses buildable folders.
- Views exposed from `KirolePackage` to the app shell must be `public`.

```
KiroleFeature/
├── Core/
│   ├── AppEnvironmentValues.swift   # EnvironmentKey definitions for all 4 singletons
│   ├── Auth/                        # Google/Apple sign-in + KeychainService
│   ├── BLE/                         # BLEProtocol.swift + TaskListSnapshotProtocol.swift (0x1B) + OfflineSyncProtocol.swift / OfflineDatasetSnapshot.swift (0x25) + FocusReconnectProtocol.swift / FocusReconnectArbiter.swift (FOCUS_STATE 0x83 / FOCUS_RESOLVE 0x06) + ScheduleV2Codec.swift (0x03 v2)
│   ├── Config/                      # AppSecrets (xcconfig-injected secrets), AppBuildEnvironment (debug-tool gating)
│   ├── Error/                       # ErrorReporter
│   ├── InternalToolsViews.swift     # Slot struct the Internal app shell fills with debug UI; `.empty` in customer builds
│   ├── Network/                     # OpenAIService, CompanionTextService, PromptSanitizer, SimulatorBridge, PromptSpec.generated.swift + Google API clients
│   ├── Services/                    # BLE runtime (BLEService, BLESyncCoordinator, BLEOfflineSyncCoordinator[+FocusReconnect/+Operations], BLEEventHandler, BLEDataEncoder, BLEPacketizer, BLESecurityManager, BLEOTACoordinator, BLEInternalToolsRuntime…) + FocusSessionService[+Reconnect/+Statistics], FocusReconnectFlagStore, FocusInterruptionDetector, DayPackGenerator, WiFiAvatarTransfer/… + Apple/Google sync engines
│   ├── Storage/                     # LocalStorage, SupabaseClient, SyncManager
│   └── Util/
├── Design/                          # Theme.swift (3 themes), FontScale.swift
├── Models/                          # Value types only: CompanionCharacter, Pet, TaskItem, CalendarEvent, FocusSession, EventLog, DayPack, DisplayScene…
├── State/                           # @Observable singletons: AppState + all AppState+*.swift extensions, ThemeManager, TaskManager, PetManager, TimelineDataSource, IntegrationCoordinator…
├── Views/                           # Home/, Pet/, Focus/, Settings/, Onboarding/, Auth/, Components/, Modifiers/
└── Resources/                       # Media.xcassets (image assets)

KiroleInternalBLE/                   # Internal-only BLE tools — see the callout below before touching
```

> **Internal-only BLE tools sit in `KirolePackage/Sources/KiroleInternalBLE/` but are compiled as *app-shell* sources.** Its three files (`InternalBLEToolsController`, `BLEWiFiDebugCoordinator`, `BLEShippingModeCoordinator`) are referenced straight from `project.pbxproj` (`sourceTree = SOURCE_ROOT`) so that `KIROLE_INTERNAL` — which Xcode never forwards into SwiftPM targets — can reach them, and every file body is wrapped in `#if KIROLE_INTERNAL || KIROLE_INTERNAL_BLE_MODULE`, so in `AppStoreRelease` they compile to nothing. The SwiftPM target `KiroleInternalBLE` (defines `KIROLE_INTERNAL_BLE_MODULE`) exists only so `KiroleFeatureTests` can exercise them. They reach package internals via `@_spi(KiroleInternal) import KiroleFeature` and plug in through `BLEInternalToolsRuntime.install(...)`, called from `Kirole/InternalBuildBoundary.activate()`; customer builds leave the runtime empty, so factory/debug BLE behaviour is a no-op with no branches in normal BLE flows. Any new internal-only capability goes through this seam (plus the `InternalToolsViews` slot for UI) — never behind an `#if` inside `KiroleFeature`, which compiles identically in both configurations.

> **DeviceActivityMonitor extension mirrors constants — change both sides together.** `KiroleDeviceActivityMonitor/` is a **zero-dependency** appex (must NOT import KiroleFeature; appex memory limits): it detects "distracting app used ≥1 min during focus", writes the timestamp into the App Group, and posts a Darwin notification. Its `Bridge` enum duplicates three constants from `ScreenTimeInterruptionDetector` (`appGroupID` / `pendingKey` / `darwinName`) **verbatim by design** — any change must be made in both files or interruption detection silently dies. `agvtool` rewrites the extension's Info.plist build number on every release; that diff is expected.

> **BLE byte namespaces are direction-split.** `Core/BLE/BLEProtocol.swift` (`BLEDataType`) defines App→Device bytes; Device→App bytes live in `Models/EventLog.swift` (`EventLogType.rawByte`). The **same byte value can mean different things by direction** — e.g. `0x15` is CustomAvatarFrame (outbound) vs ViewEventDetail (inbound). This is intentional and not an on-wire conflict; don't flag it as one. Same trap with `0x20`: App→Device `eventLogRequest` is retired (`BLEService.requestEventLogsIfNeeded` has no callers — `0x25 OP_BATCH` replays offline events, device-verified 2026-09-03), while Device→App `0x20 requestRefresh` is still a live sync trigger.

### State Management
Four `@Observable` singletons injected at `ContentView` via `.environment()`:

| Singleton | Purpose |
|-----------|---------|
| `AppState` | Tasks, events, pet, navigation — split across `AppState+Actions/Sync/Loading/HardwareDisplay/Profile/Companion.swift` |
| `ThemeManager` | 3 themes |
| `AuthManager` | Apple / Google Sign In |
| `FocusSessionService` | Focus session state, enforcement mode, energy bottles, interruption detection (DeviceActivity; spec `docs/2026-07-09-spec.md` D-1/D-2) |

**Persistence & secrets (the two most-connected non-UI nodes — touch them carefully):**
- `LocalStorage` (`Core/Storage/`) — the JSON + `UserDefaults` persistence hub for tasks, pet, focus & gamify state. Mutations through its *resettable* keys are exactly what the parallel-test lock below guards.
- `KeychainService` (`Core/Auth/`) — stores Google OAuth tokens, the Apple user identifier, and the OpenAI/OpenRouter API key. Never persist a credential anywhere else.

**AppState extension map** — where to put code:
- User-triggered mutations → `AppState+Actions.swift`
- Remote sync (Google/Apple) → `AppState+Sync.swift`
- Provider sync generation guard (stale-sync-commit prevention) → `AppState+ExternalSyncGeneration.swift`
- Sign-out provider data cleanup → `AppState+SignOut.swift`
- Initial data loading → `AppState+Loading.swift`
- BLE / DisplayScene / hardware push → `AppState+HardwareDisplay.swift`
- Profile and companion text → `AppState+Profile.swift` / `AppState+Companion.swift`
- Custom companion avatar BLE push → `AppState+CustomCompanions.swift`
- Custom avatar transaction state → `AppState+CustomAvatarTransactions.swift`
- Third-party integration state → `AppState+Integrations.swift`
- WiFi avatar transport routing → `AppState+WiFiAvatarTransport.swift`
- Persistence helpers (`persistTasks`, `persistPet`) → `AppState.swift` main file

### UI Stack
SwiftUI with **Model-View only** — no ViewModels. Tab-based nav via `AppState.selectedTab`. Custom `AppHeaderView` fixed at top (outside `ScrollView`); no native `TabView`.

### CompanionCharacter Image Asset Naming
Assets live in `Resources/Media.xcassets/<name>.imageset/`. Naming convention: `<rawValue>-<variant>` where `rawValue` is `joy` / `silas` / `nova`.

Variants: `main`, `head`, `reading`, `profile`, `sunrise`, `sunset`, `petScene`.

Asset catalogs and their contained files use lowercase kebab-case and the same
base name. Pet page artwork uses `<character>-pet-scene`; hardware scene previews
use `display-scene-preview-<scene-id>`. These are separate systems.

**Always assign art to the correct character's imageset. Never place Silas art in `joy-*` or vice versa — this has caused multiple rollback commits.**

Current per-variant state (source of truth: `CompanionCharacter.heroAssetName(variant:)`):

| Variant | Joy | Silas | Nova |
|---------|-----|-------|------|
| `.reading` | `joy-reading.png` (575KB) — timeline & focus pose | `silas-reading.png` (754KB) | `nova-reading.png` |
| `.profile` | `joy-profile.png` (same art as `joy-main`) | `silas-profile.png` | `nova-profile.png` |
| `.main` | `joy-main.png` — standing pose; **not** used on the home timeline | `silas-main.png` | `nova-main.png` |
| `.petScene` | `joy-pet-scene.png` | `silas-pet-scene.png` | `nova-pet-scene.png` |
| `.sunrise`/`.sunset` | `joy-sunrise/sunset.png` | `silas-sunrise/sunset.png` | `nova-sunrise/sunset.png` |

The home timeline pet embed and Focus mode both use `.reading`. PetStatusView uses `.profile`.

## Hard Constraints (do not violate)
- NO ViewModels, NO XCTest (use Swift Testing: `import Testing`, `@Test`, `#expect`), NO CoreData/CloudKit, NO Combine unless strictly required.
- **NO `Task { }` inside `onAppear`** — use `.task` modifier. Replace `DispatchQueue.main.asyncAfter` with `Task { try? await Task.sleep(for: ...) }` inside `.task`.
- **NO deprecated `.onChange(of:perform:)`** — use `.onChange(of:) { oldValue, newValue in ... }`.
- NO secrets in `Info.plist`. Secrets come from `Config/Secrets.xcconfig` (git-ignored) via `AppSecrets.configure(...)`.
- Concurrency: `@MainActor` for UI, `actor` for shared state, avoid `@unchecked Sendable`.
- Accessibility: every interactive element needs `accessibilityLabel` and `accessibilityIdentifier`.

## Sheet / FullScreenCover Environment Injection
`.sheet`, `.fullScreenCover`, `.popover` create a new SwiftUI environment scope — singletons are **not inherited automatically**. Use the `injectAppEnvironment()` modifier (`Views/Modifiers/InjectAppEnvironment.swift`) on every sheet/cover root view. For testing, inject mocks via typed keys:

```swift
.environment(\.appState, mockAppState)
.environment(\.themeManager, mockThemeManager)
.environment(\.authManager, mockAuthManager)
.environment(\.focusService, mockFocusService)
```

## LLM Prompt Safety
All user-controlled text (task titles, event names, pet names, learn content) **must pass through `PromptSanitizer.sanitize(_:)` before interpolation into any LLM prompt**. Wrap user content in XML delimiters (`<user_event>…</user_event>`) and declare the fence in the system prompt. `PromptSanitizer` lives in `Core/Network/PromptSanitizer.swift`.

## Supabase (Self-Hosted on Zeabur)
- **API gateway (Kong)**: `https://outku3.zeabur.app`
- **REST**: `/rest/v1` — tables: `pets`, `sync_state`
- **Schema source of truth**: `Config/supabase-schema.sql` — apply manually to Zeabur PostgreSQL when schema changes. `supabase/migrations/` is empty by design; don't start a second schema lineage there.
- **Edge Functions**: `supabase/functions/` (`notion-oauth`, `taskade-oauth`, `ticktick-oauth[-callback]`, shared code in `_shared/`) hold the third-party OAuth exchanges so client secrets never ship in the app. They deploy separately from the iOS build — a change here is not live until redeployed.
- Apple / Google Sign In go through GoTrue (Supabase Auth), so an OAuth provider that is not enabled on the self-hosted instance fails on device with no client-side fix; check the server config before touching `Core/Auth/`.

## Common Commands

Prefer XcodeBuildMCP tools when available. Before the first build in a session, always call `session_show_defaults` to confirm project/scheme/simulator are set.

### Build & Run (simulator)
```bash
# Fast package-only compile
cd KirolePackage && swift build

# Full app build
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Tests
```bash
# Full package test suite (Swift Testing)
cd KirolePackage && swift test

# Single test
cd KirolePackage && swift test --filter "MyTestSuite/testMethod"

# Simulator run (with filter)
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test \
  -only-testing:KiroleFeatureTests/MyTestSuite/testMethod
```

### Test Suite Notes
- **~125 test files** in `KirolePackage/Tests/KiroleFeatureTests/` (`KiroleUITests/` is an untouched XCUITest scaffold — the "no XCTest" rule is about package tests, not that target). BLE is the most heavily covered surface (`BLEProtocolTests`, `BLESecurityTests`, `BLESyncPolicyTests`, `BLEWriteGateTests`, `BLEConnectionPolicyTests`, `BLEEventHandlerTests`, `BLEProtocolSimulationTests`, `BLEOTACoordinatorTests`, `BLEOfflineSyncCoordinatorTests`, `FocusReconnectArbiterTests` / `FocusReconnectProtocolTests` / `FocusReconnectFixTests`, `ScheduleV2CodecTests`), followed by focus/sync/companion logic. Wire-format or reconnect changes must run the reconnect + OfflineSync + Schedule v2 suites, not only `BLEProtocolTests`.
- **`BLEDataEncoder` has a strict mirror decoder in the test layer.** `BLEProtocolSimulationSupport.swift`'s `parseDayPack` / `parseWeather` re-parse the exact wire bytes and call `requireEnd()` (any trailing byte throws `trailingBytes`). So **any field added to `encodeDayPack` / `encodeWeather` MUST be read back in the matching `parse*` before `requireEnd()`** — even an empty length-prefixed string appends a byte and trips it — and the fixture + `Simulated*` struct + round-trip assertion updated. `BLEProtocolTests` walks the cursor by hand and will *not* catch a desync; run the **full** `swift test` (which includes `BLEProtocolSimulationTests`) after any wire-format change, not just `BLEProtocolTests`.
- **Parallel-test isolation (CRITICAL):** Swift Testing runs suites concurrently. Any test that mutates global `UserDefaults.standard` — i.e. anything going through `LocalStorage` resettable keys, focus energy bottles, or gamify storage — MUST wrap its body in `await SharedPersistenceTestLock.shared.withLock { ... }` (`Tests/.../SharedPersistenceTestLock.swift`) or it flakes intermittently. Suites that assert state on shared singletons (e.g. `BLEService.shared.isPendingOTAReboot` in `BLEOTACoordinatorTests`) must be `@Suite(..., .serialized)` — in-suite parallel tests interleave at `await` points and clobber the flag. **Adding a new key to `LocalStorage.resettableUserDefaultKeys` can make previously-green tests flaky.** If a suite flakes, run it alone first (`swift test --filter SuiteName`) to confirm an isolation problem before changing production code.
- **Which runner:** `swift test` (package-only, fast) for logic/services; the simulator host (`xcodebuild ... test`, or XcodeBuildMCP `test_sim`) only when the test exercises app-shell / UI lifecycle. `Kirole.xctestplan` coordinates the full run.
- **No SwiftLint / SwiftFormat is configured** in this repo — there is no lint or format step; don't invent one.

### TestFlight Release (Full Pipeline)
```bash
# /release slash command (auto-generates English notes from git log, uses Haiku model)
/release            # internal channel → Kirole-Internal → "Kirole Hardware Internal" group only
/release external   # external channel → Kirole-AppStore → all external groups + Beta App Review

# Or via fastlane directly (English notes required; zh_text optional)
fastlane ios internal text:"Bug fixes and UI improvements"
fastlane ios external text:"English notes" zh_text:"中文说明"

# Notes-only update (no build, no distribution; build:N to target a specific build)
fastlane ios notes text:"说明内容"

# App Store candidate binary only — prefer promoting the build external testers verified
fastlane ios appstore

# Recover an external release that uploaded+processed but died before distribution (SSL EOF etc.)
# build:N is REQUIRED — no archive, no bump; refuses a build that sits in the internal hardware group
fastlane ios finish_external build:658 text:"English notes"

# Per-channel landing check (run after every release)
fastlane ios status
```

Pipeline steps (automated): `increment_build_number` → `gym` (archive ~3 min) → `upload_to_testflight` (processing ~5 min) → set en-US + zh-Hans notes → assign to the hardware group (`internal`) or distribute to external groups + Beta App Review (`external`).

**Two binaries, three audiences (AGENTS.md "Release Channel Policy", 2026-09-03 lane split)**: `internal` archives `Kirole-Internal` (`InternalRelease`, defines `KIROLE_INTERNAL`) — the hardware/firmware acceptance channel, never handed to external testers. `external` and `appstore` both archive `Kirole-AppStore` (`AppStoreRelease`, no `KIROLE_INTERNAL`) after `scripts/verify-release-boundary.sh` proves the boundary marker and internal-tool strings are compiled out; the App Store submission promotes the build number external testers verified instead of archiving a third binary. `KIROLE_INTERNAL` is only visible to app-shell (`Kirole/`) sources — Xcode does not forward custom-configuration compilation conditions into SwiftPM packages, so never gate package code with it (see the `KiroleInternalBLE` callout above for the sanctioned seam).

**Customer builds carry no BLE logging except registered fault records.** `scripts/verify-release-boundary.sh` also scans the `AppStoreRelease` Mach-O for `os.Logger` categories: `AUTHORISED_CUSTOMER_LOG_CATEGORIES` (currently only `FocusReconnect`, fired when a device rejects a `FOCUS_RESOLVE`) must be present, `INTERNAL_ONLY_LOG_CATEGORIES` (e.g. `BLEDisconnect`) must be absent. A new `Logger(category:)` that reaches the customer binary fails the gate unless it meets all four conditions in AGENTS.md "Narrow exception — authorised fault records" (anomaly-only / no user content / no capability / registered) **and** is added to both the AGENTS.md table and the script's allow-list.

**BLE secret is a firmware-readiness switch, not a channel property.** `BLE_SECURE_CHANNEL_ENABLED` in `Config/Secrets.xcconfig` (single source of truth, currently `0`) decides whether any archive enters `.secure` mode. At `0` every configuration ships the plaintext BLE channel the firmware actually implements (BLE protocol §3.3: secure handshake is a second-phase item never confirmed with the hardware team) and `BLE_SHARED_SECRET` is ignored; flip to `1` only after the secret has been generated with the hardware team, provisioned on devices, and confirmed per protocol §4.17 — then customer-candidate archives fail closed on an empty secret. App Store candidates 651 / 655 were archived in `.secure` mode with a secret the firmware never received; they cannot pair with any device and must not be released.

Credentials: `fastlane/.env` (git-ignored) — copy from `fastlane/.env.template` and fill `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`.

**Verify the build actually landed.** `upload_to_testflight` can be killed mid-upload (process timeout / transient `SSL_read` EOF), leaving the build number bumped locally + an archive on disk but **nothing on App Store Connect** — a "Done" line or local archive is not proof. Confirm via the ASC API (latest build number + `processing_state` + beta-review state). Run the release detached/in background so one timeout can't kill the upload; transient SSL errors are retryable.

**Before App Store submission:** internal Settings / Focus Debug UI is compiled only into `InternalRelease` (`Kirole/Internal/`, `#if KIROLE_INTERNAL`). `showsHardwareDebugTools` stays off unless the Internal app shell enables the hardware channel. `fastlane ios external` / `appstore` fail closed on an empty `BLE_SHARED_SECRET` only when `BLE_SECURE_CHANNEL_ENABLED = 1`. Remaining blockers are screenshots, store copy, privacy questionnaire, WeatherKit attribution on weather-display pages, and hardware-claim evidence — not the debug-tool wash.

### E-ink Simulator (hardware-free UI preview)
```bash
# Start the WebSocket relay (port 3456) — keep running in background
cd eink-simulator && node server.js

# Serve the browser canvas
npm run dev        # Vite dev server → open http://localhost:5173

# iOS sim connects via SimulatorBridge.shared.connect() (ws://localhost:3456)
# Any BLE frame the app sends is fan-out-relayed to the browser canvas in real time
```

### PromptSpec code generation
Edit `prompt-studio/lib/prompt-spec.json` (canonical source), then regenerate:
```bash
python3 Config/generate-prompt-spec.py          # writes PromptSpec.generated.swift
python3 Config/generate-prompt-spec.py --check  # exits non-zero if Swift is stale
```
`PromptSpecConsistencyTests` verifies the generated file byte-for-byte — the test will fail if the JSON was edited without re-running the generator.

### Real Device Install
```bash
xcrun devicectl device install app --device <DEVICE_ID> \
  ~/Library/Developer/Xcode/DerivedData/Kirole-*/Build/Products/Debug-iphoneos/Kirole.app
```

## Config / Secrets Setup
Create `Config/Secrets.xcconfig` (git-ignored) — full commented reference: `Config/Secrets.xcconfig.template`. Core keys:
```
DEVELOPMENT_TEAM = 93SL23NPNG
GOOGLE_CLIENT_ID = ...
GOOGLE_REVERSED_CLIENT_ID = ...
SUPABASE_URL = ...
SUPABASE_ANON_KEY = ...
BLE_SECURE_CHANNEL_ENABLED = 0 # firmware-readiness switch, strictly 0 or 1 (anything else fails the build)
BLE_SHARED_SECRET =            # ignored while the switch is 0; required by external/appstore lanes once it is 1
OPENROUTER_API_KEY = ...       # OpenRouter key used by OpenAIService (was OPENAI_API_KEY)
```
For TestFlight automation, copy `fastlane/.env.template` → `fastlane/.env` and fill in `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`.

**How secrets reach Swift:** a build phase runs `Config/scripts-generate-build-secrets.sh`, which writes the git-ignored `Kirole/BuildSecrets.generated.swift`; `KiroleApp` then calls `AppSecrets.configure(...)` with those constants. The script blanks `BLE_SHARED_SECRET` whenever `BLE_SECURE_CHANNEL_ENABLED != 1`, so the package never sees a secret the firmware cannot use. `BuildSecretsLeakTests` pins this contract (0 / 1 / absent / illegal values) — run it, not just the boundary script, after touching the generator.

**Build settings & entitlements (separate from `Secrets.xcconfig`):**
- Build config is layered across `Config/Shared.xcconfig` (bundle id, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`), `Config/Debug.xcconfig`, `Config/Release.xcconfig` → `Config/InternalRelease.xcconfig` (adds `KIROLE_INTERNAL`) / `Config/AppStoreRelease.xcconfig` (adds `EXCLUDED_SOURCE_FILE_NAMES` for repo-only files), `Config/Tests.xcconfig`.
- **Version numbers live in `Kirole.xcodeproj/project.pbxproj`, not the xcconfig.** `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` are set explicitly per target × configuration (App + DeviceActivity extension × 4 configs = **8 sites**, and Apple requires the extension's short version to match the app), and pbxproj settings outrank xcconfig. `Shared.xcconfig` mirrors the value only so readers aren't misled. fastlane `increment_build_number` edits the pbxproj too.
- App capabilities live in `Config/Kirole.entitlements` — declarative XML you can edit directly without touching the Xcode project. Family Controls + App Group + WeatherKit are already enabled. **Hotspot Configuration** (`com.apple.developer.networking.HotspotConfiguration`, added for WiFi custom-avatar transfer via `0x1A`) is declared in the entitlements too, but a **device** build additionally requires enabling the Hotspot Configuration capability on the App ID in the Apple Developer portal (signing team `93SL23NPNG`) and re-signing the provisioning profile — the entitlement XML alone does not grant it on device (sim builds ignore it). The DeviceActivity extension carries its own `KiroleDeviceActivityMonitor/KiroleDeviceActivityMonitor.entitlements` (must keep the same App Group).
- **Platform floor:** Swift 6.1 toolchain, **iOS 17+** (`KirolePackage` declares `platforms: [.iOS(.v17), .macOS(.v14)]`).

## Where to Look Next
- `AGENTS.md` — full rules, BLE protocol *rules/summary*, companion IP prompt architecture, onboarding detail, Focus Mode state machine, Event→Output dispatch map.
- `docs/` — **hardware-facing source of truth** (AGENTS.md defers here). Ver 1.3.1 专注重连 / Schedule v2 阅读顺序：`专注状态重连协议变更_Ver_1_3_1.md`（语义）→ `Kirole_BLE协议命令字节表_专注重连协议更新_Ver_1_3_1.md`（字节；由同名 `.xlsx` 转写）→ `Kirole_专注状态重连_App对接说明_Ver_1_3_0.md` §9 裁决表 → `BLE通信协议规格文档.md`（v2.13.3 起 §4.23 / §5.15 已直接对齐 1.3.1：只有 `RESULT=COMMITTED` 解锁 `0x14`、活动专注不进 `BEGIN/COMMIT`、批内 `0x10/0x11/0x12` 记录为 v2 `19+N` / `23+N`；`-v2.13.1补记` / `-v2.13.2补记` 两个文件是已合并的历史记录，不再覆盖任何句子）。冲突时 **固件 1.3.1 原文优先**，但硬件 1.3.1 字节表 §5.15 那两行旧 v2.9 不是合同，批内进入/完成/跳过以主规格 §5.15 + 同表 §5.3–5.5 为准（硬件原文未改）。未决项：`专注重连-与硬件协商项_Ver_1_3_1.md`。`BLE初次联调指南.md` / `BLE联调前全协议模拟报告.md` 是联调指南；`硬件需求文档-Hardware-Requirements-Document.md` 与 `固件功能规格文档.md` 是硬件需求；`Kirole显示屏页面（游戏机制2）.pdf` 与 `positioning-narrative.md` 是产品机制；`2026-07-09-spec.md` 是专注打断 D-1/D-2/D-3。改 BLE/固件文档时字节表和 § 号必须与硬件合同一致。
- `.claude/skills/` — 15 repo-specific playbooks distilled from commit history and incidents; `kirole-atlas` is the router. Open the matching one *before* acting: `ble-wire-change-control` (any byte change), `docs-contract-change-control` (editing `docs/` — includes the mandatory Feishu sync), `client-asset-change-control` (deleting/moving image assets — grep-no-refs ≠ safe), `flaky-test-triage`, `ble-sync-runbook`, `testflight-distribution-runbook`, `release-acceptance`, `ui-change-acceptance`, `intentional-behaviors-contract` (the "looks like a bug, isn't" list — check before filing or fixing), `subagent-output-audit` (always `git diff` a subagent's full change set before trusting its report). The remaining skills (`ios-*`, `swift-*`, `reactcomponents`) are generic imports, not Kirole-specific.
- `.claude/commands/` — `/release [external]` (spawns a Haiku agent that writes English notes from `git log`; must never name an AI model/provider) and `/baseline-ui` (UI anti-slop checklist). `.gitignore` commits only `.claude/skills/` and `.claude/commands/`; the rest of `.claude/` (settings, worktrees, PRPs) is machine-private.
- `website/` — the public site that also hosts App Review evidence (privacy policy, WeatherKit-attribution and hardware demo videos linked from the review notes). Deployed via Zeabur, independent of the iOS build.
- `TESTFLIGHT_GUIDE.md`, `TESTFLIGHT_PROGRESS.md` — release workflow state.
