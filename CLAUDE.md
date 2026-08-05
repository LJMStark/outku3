# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

The authoritative rules, BLE protocol, and full subsystem detail live in `./AGENTS.md`.
Read it before any non-trivial change. `.cursor/rules/*.mdc` adds Swift/SwiftUI/Testing/Concurrency guidance.

## Interaction Rules
1. Every response must begin with **B哥**.
2. Respond in **Simplified Chinese**. For non-technical questions, keep language plain and explain jargon inline.
3. Treat `/Users/demon/vibecoding/outku3` as the strict workspace boundary. Unqualified requests ("build", "commit", "run tests") always refer to this repo.
4. **English-only product UI (CRITICAL).** This is an English-language product. ALL user-facing copy — companion dialogue, notification titles/bodies, banners, button labels, on-device E-ink text — must be English. Chinese is allowed ONLY in code comments and assistant↔user chat. Never introduce Chinese into a displayed string (this is why AI output is never localized to the user's language). Pre-existing Chinese UI strings are tech debt to clean up, not a pattern to follow.

## Product Identity (READ FIRST)
Kirole 是 **硬件优先的宠物陪伴产品**：硬件 E-ink 设备是用户主要的日常交互入口，App 是给硬件配置数据的工具。任务和日历事件主要作为 **prompt 上下文** 驱动宠物对话，**不是给用户管理待办用的**。任何把 task/event 当"待办"来增强（AI 任务拆解、详情页步骤展开、催促式提醒等）的提议都偏离产品定位，应直接拒绝或反向清理。

**Pet 页面布局是设计内容（客户需求，勿动）**：上半部分显示宠物形象，下半部分是任务列表 UI（Tasks Today / Upcoming / No Due Dates，含 checkbox / Edit / Delete）。这是刻意的产品设计，不是"待办增强"。

**硬件优先意味着**：硬件离线时用户操作不能丢——硬件本地缓存事件，BLE 重连后通过 `0x21 eventLogBatch` 帧批量回推给 App，App 必须把每条事件应用到 AppState（任务完成状态、专注会话等）。"补传"是核心功能而非可选项。v2.16.0 起它还是**每个连接的强制前置握手**：`BLEEventReplayBarrier` fail-closed——App 处理完 `0x20→0x21` 回放前不发任何 presentation 数据，15 秒未完成判连接失败并主动断开（固件无离线事件也必须回空 `0x21`）。

**设备内容 = 两个独立版本域（v2.16.0 预备模型）**：`0x23 TaskLibraryTransaction` 承载**当天任务库**（每条任务带详情 + 三条阶段文案，设备按本地专注分钟 0–5/6–15/16+ 自选，进任务不再向 App 现场索取——`0x11 TaskInPage` 生成路径已删除）；`0x24 DailyContentTransaction` 承载**当天内容包**（当天日程 + 每日文案 + 屏保/总结文字，跨自然日立即失效）。两者各自原子提交、独立持久化，普通内容变化走 **180 秒稳定窗**（`TaskLibraryStabilityState`），完成/删除即时。**任务库只含当天任务**（dueDate 当天 ∪ 手动设为今天，`TaskItem.isEligibleForHardwareTaskLibrary`，ADR 0029 拍板，2026-08-04）——未来/过期/未选入的无日期任务不上 wire，跨日由 App 立即重算重发、设备沿用旧库到新版到达。**上 wire 各封顶 20 条**（ADR 0030，`TaskLibraryMembership.members` 单一截断口）：任务取 App 列表序前 20、日程取最早 20，App 侧截断、固件收多少存多少；完成/删除的即时小事务不提拔第 21 条，设备暂剩 19 条、最多 180 秒后补齐——这不是 bug。**断连不结束专注**（ADR 0019，`handleDeviceDisconnected` 为 no-op）：设备本地续计时，重连不切页不清零。

**一账号 = 一活跃设备（单设备模型，READ）**：Supabase 数据按登录账号（`userId`）存，但产品是"一台手机配一台硬件"。同一账号**不预期同时在多台设备上活跃**——换机 / 重装是**顺序**事件（旧机退役 → 新机登录拉云端、`max` 合并恢复），不是并发。因此跨设备同步（能量瓶子、宠物状态）**不存在多写者并发**：分布式多写竞态（如"远端写非单调 / 较低值覆盖较高值"）**不适用本产品，勿当 bug 报**。与"不做 Watch / Mac / 家庭共享"定位一致。将来若真做多设备陪伴端，再引入 DB 端 `max` / 条件更新。

三条核心数据流：

1. **任务/事件 → Prompt → 宠物对话**
   `appState.tasks/events` → `DayPackGenerator` / `CompanionTextService` → `OpenAIService`。家页伴侣槽显示**单一、随时段变脸**的 `currentPetDialogue`（晨安 / 任务鼓励 / 结算语，由 `AppState+Companion.resolveCompanionPhase` 选型；亦可切日俳句模式），DayPack 另带**中性面板文本** `daySummary`（框②，`OpenAIService.generateDaySummaryText` 非人格生成）+ `firstUp`（框③）；三者经 BLE 推给硬件。**宠物口吻只在 `currentPetDialogue` 一句**——v2.5.0 起旧的多输出 `morningGreeting / dailySummary / companionPhrase` 已收敛，面板文本一律中性。

2. **App → 硬件同步有节流，不立刻 push**
   `BLESyncCoordinator.performSync()` + `BLESyncPolicy`：白天 08-23 每 1 小时；夜间 23-08 每 4 小时。触发时机：iOS `BGAppRefreshTask`、硬件主动发 `0x20`/`0x30`、DayPack 指纹变化或 `force: true`。任务/当日日程的**内容编辑**另有 180 秒稳定窗（最后一次变化后 3 分钟才成为待发版本，断连/重连不重计）。**用户加任务后硬件不会立刻显示**，要等窗口到点 + 下一个 sync。跨自然日是例外：任务库与当天内容包**立即**重算推送（0x23 → 0x24 → DayPack 一轮）。

3. **硬件 → App 反向触发专注模式**
   硬件点击任务 → `0x10 enterTaskIn` → `BLEEventHandler` → `FocusSessionService.startSession(...)` → 整套专注链路自动启动。v2.16.0 起 `0x10` **只**用于建立会话（Device→App 唯一的"专注已开始"信号，固件不可停发）；App **不再回发 `0x11 TaskInPage`**，设备从已提交任务库本地读详情与三阶段文案。

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
│   ├── BLE/                         # BLEProtocol.swift（字节定义）、TaskLibraryProtocol/Update/Delivery.swift（0x23 当天任务库：codec + 稳定窗状态机 + 冻结事务）、DailyContentProtocol/Update/Delivery/DayBoundary.swift（0x24 当天内容包 + 跨日）、TaskListSnapshotProtocol.swift（0x1B 业务确认 + 离线动作账本）
│   ├── Config/                      # AppSecrets (xcconfig-injected secrets), AppBuildEnvironment (debug-tool gating)
│   ├── Error/                       # ErrorReporter
│   ├── Network/                     # OpenAIService, CompanionTextService, PromptSanitizer, SimulatorBridge, PromptSpec.generated.swift
│   ├── Services/                    # BLE runtime (BLEService, BLESyncCoordinator, BLEEventHandler, BLEDataEncoder, BLEPacketizer, BLESecurityManager, BLEOTACoordinator…) + FocusSessionService, FocusInterruptionDetector, DayPackGenerator, WiFiAvatarTransfer/…
│   ├── Storage/                     # LocalStorage, SupabaseClient, SyncManager
│   └── Util/                        # Log.swift — the `Log.*` category logger (Log.weather, Log.ble…); use it, not print()
├── Design/                          # Theme.swift + FontScale.swift — design tokens; ThemeManager (State/) consumes these
├── Models/                          # Value types only: CompanionCharacter, Pet, TaskItem, CalendarEvent, FocusSession, EventLog, DayPack, DisplayScene…
├── State/                           # @Observable singletons: AppState + all AppState+*.swift extensions, ThemeManager, TaskManager, PetManager, TimelineDataSource, IntegrationCoordinator…
├── Views/                           # Home/, Pet/, Settings/, Onboarding/, Auth/, Focus/, Components/ (AppHeaderView, CompanionDialogueView, PetAnimationEngine…), Modifiers/
└── Resources/                       # Media.xcassets (image assets)
```

> **DeviceActivityMonitor extension mirrors constants — change both sides together.** `KiroleDeviceActivityMonitor/` is a **zero-dependency** appex (must NOT import KiroleFeature; appex memory limits): it detects "distracting app used ≥1 min during focus", writes the timestamp into the App Group, and posts a Darwin notification. Its `Bridge` enum duplicates three constants from `ScreenTimeInterruptionDetector` (`appGroupID` / `pendingKey` / `darwinName`) **verbatim by design** — any change must be made in both files or interruption detection silently dies. `agvtool` rewrites the extension's Info.plist build number on every release; that diff is expected.

> **BLE byte namespaces are direction-split.** `Core/BLE/BLEProtocol.swift` (`BLEDataType`) defines App→Device bytes; Device→App bytes live in `Models/EventLog.swift` (`EventLogType.rawByte`). The **same byte value can mean different things by direction** — e.g. `0x15` is CustomAvatarFrame (outbound) vs ViewEventDetail (inbound), and `0x10` is DayPack (outbound) vs EnterTaskIn (inbound). This is intentional and not an on-wire conflict; don't flag it as one. The `0x10` pair is the one that bites: "停发 0x10" without naming the direction once nearly killed the focus-start signal (v2.16.0 correction) — always specify inbound/outbound when discussing these bytes.

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
- `KeychainService` (`Core/Auth/`) — stores ALL credentials: OAuth tokens (Google / Notion / Taskade), the Apple user identifier, and the OpenAI/OpenRouter API key. Never persist a credential anywhere else.

**AppState extension map** — where to put code:
- User-triggered mutations → `AppState+Actions.swift`
- Remote sync (Google/Apple/Notion/Taskade) → `AppState+Sync.swift`
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
- **Schema source of truth**: `Config/supabase-schema.sql` — apply manually to Zeabur PostgreSQL when schema changes.
- **OAuth proxy**: Notion / Taskade token exchange via Supabase Edge Functions (`supabase/functions/`). `client_secret` is server-side only.

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
- **~129 test files (150 suites, ~1245 tests)** in `KirolePackage/Tests/KiroleFeatureTests/`. BLE is the most heavily covered surface (`BLEProtocolTests`, `BLESecurityTests`, `BLESyncPolicyTests`, `BLEWriteGateTests`, `BLEConnectionPolicyTests`, `BLEEventHandlerTests`, `BLEProtocolSimulationTests`, `BLEOTACoordinatorTests`, plus the task-library group: `TaskLibraryFullSyncTests` / `TaskLibraryIncrementalUpdateTests` / `TaskLibraryDeliveryTests` / `DailyContentDayRolloverTests` / `OfflineTaskStateMergeTests`), followed by focus/sync/companion logic. The stateful App↔virtual-device acceptance entry is `AppDeviceScenarioTests` (`AppDeviceScenarioSupport` wires controllable clock, AI, BLE fault points, and persistence).
- **Time-dependent task-library tests**: the `0x23` filter is day-dependent (`isEligibleForHardwareTaskLibrary(on:calendar:)`, no default args). Fixtures pin fixed timestamps (`1_800_000_000` etc.) and MUST inject `appState.taskLibraryNowProvider` / `dailyContentCalendarProvider` (Asia/Shanghai helper: `TaskLibraryFullSyncTests.makeShanghaiCalendar()`); a fixture task needs `dueDate:`/`todayDisplayDate:` matching that clock or it silently drops out of the library and assertions go red. New offsets ≤ 3600s with an explicit calendar.
- **`BLEDataEncoder` has a strict mirror decoder in the test layer.** `BLEProtocolSimulationSupport.swift`'s `parseDayPack` / `parseWeather` re-parse the exact wire bytes and call `requireEnd()` (any trailing byte throws `trailingBytes`). So **any field added to `encodeDayPack` / `encodeWeather` MUST be read back in the matching `parse*` before `requireEnd()`** — even an empty length-prefixed string appends a byte and trips it — and the fixture + `Simulated*` struct + round-trip assertion updated. `BLEProtocolTests` walks the cursor by hand and will *not* catch a desync; run the **full** `swift test` (which includes `BLEProtocolSimulationTests`) after any wire-format change, not just `BLEProtocolTests`.
- **Parallel-test isolation (CRITICAL):** Swift Testing runs suites concurrently. Any test that mutates global `UserDefaults.standard` — i.e. anything going through `LocalStorage` resettable keys, focus energy bottles, or gamify storage — MUST wrap its body in `await SharedPersistenceTestLock.shared.withLock { ... }` (`Tests/.../SharedPersistenceTestLock.swift`) or it flakes intermittently. Suites that assert state on shared singletons (e.g. `BLEService.shared.isPendingOTAReboot` in `BLEOTACoordinatorTests`) must be `@Suite(..., .serialized)` — in-suite parallel tests interleave at `await` points and clobber the flag. **Adding a new key to `LocalStorage.resettableUserDefaultKeys` can make previously-green tests flaky.** If a suite flakes, run it alone first (`swift test --filter SuiteName`) to confirm an isolation problem before changing production code.
- **Which runner:** `swift test` (package-only, fast) for logic/services; the simulator host (`xcodebuild ... test`, or XcodeBuildMCP `test_sim`) only when the test exercises app-shell / UI lifecycle. `Kirole/Kirole.xctestplan` coordinates the full run.
- **No SwiftLint / SwiftFormat is configured** in this repo — there is no lint or format step; don't invent one.

### TestFlight Release (Full Pipeline)
```bash
# Full release: auto-increment build → archive → upload → set notes → distribute external group
# /release slash command (auto-generates English notes from git log, uses Haiku model)
/release

# Or via fastlane directly (English notes required; zh_text optional)
fastlane ios release text:"Bug fixes and UI improvements"
fastlane ios release text:"English notes" zh_text:"中文说明"

# Notes-only update (no build, no distribution)
fastlane ios notes text:"说明内容"

# Verify the latest build actually landed (processing + beta-review state) — run after EVERY release
fastlane ios status

# Recover a release that uploaded+processed OK but died at external distribution (e.g. SSL EOF).
# Idempotent, operates on the latest build: no archive, no upload, no build bump.
fastlane ios finish_external
```

Pipeline steps (automated): `increment_build_number` → `gym` (archive ~3 min) → `upload_to_testflight` (processing ~5 min) → set en-US + zh-Hans notes → distribute to external group **kirole**.

Credentials: `fastlane/.env` (git-ignored) — copy from `fastlane/.env.template` and fill `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`.

**Version numbers live in the pbxproj, not the xcconfig.** `Config/Shared.xcconfig` declares `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1`, but the Xcode project's own build settings override both (currently `2.0` / `632`). Editing the xcconfig values does nothing; `fastlane` bumps the build via `increment_build_number(xcodeproj:)`. Never hand-edit build numbers — let the lane do it.

**Verify the build actually landed.** `upload_to_testflight` can be killed mid-upload (process timeout / transient `SSL_read` EOF), leaving the build number bumped locally + an archive on disk but **nothing on App Store Connect** — a "Done" line or local archive is not proof. Confirm with `fastlane ios status` (or the ASC API directly: latest build number + `processing_state` + beta-review state). Run the release detached/in background so one timeout can't kill the upload; transient SSL errors are retryable.

**Before App Store submission (TestFlight is fine as-is):** `AppBuildEnvironment.showsHardwareDebugTools` currently `return true` unconditionally — deliberately loosened in build 573 (all-builds-visible + keep-alive default-on) for firmware integration, and still loose as of build 632. The `DEBUG || isTestFlight` gate must be restored before a store release. Other pre-release gates (on-device interruption-detection acceptance, firmware OTA safety sign-off) are tracked in the `release-acceptance` skill — check there rather than assuming this is the only one.

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
Create `Config/Secrets.xcconfig` (git-ignored) with:
```
DEVELOPMENT_TEAM = 93SL23NPNG
GOOGLE_CLIENT_ID = ...
GOOGLE_REVERSED_CLIENT_ID = ...
SUPABASE_URL = ...
SUPABASE_ANON_KEY = ...
BLE_SHARED_SECRET =         # leave empty for dev (unsigned frames)
OPENAI_API_KEY = ...        # OpenRouter key used by OpenAIService
```

For TestFlight automation, copy `fastlane/.env.template` → `fastlane/.env` and fill in `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`.

**Build settings & entitlements (separate from `Secrets.xcconfig`):**
- Build config is layered across `Config/Shared.xcconfig` (bundle id, versions, `IPHONEOS_DEPLOYMENT_TARGET = 17.0`), `Config/Debug.xcconfig`, `Config/Release.xcconfig`, `Config/Tests.xcconfig`.
- App capabilities live in `Config/Kirole.entitlements` — declarative XML you can edit directly without touching the Xcode project. Family Controls + App Group + WeatherKit are already enabled. **Hotspot Configuration** (`com.apple.developer.networking.HotspotConfiguration`, added for WiFi custom-avatar transfer via `0x1A`) is declared in the entitlements too, but a **device** build additionally requires enabling the Hotspot Configuration capability on the App ID in the Apple Developer portal (signing team `93SL23NPNG`) and re-signing the provisioning profile — the entitlement XML alone does not grant it on device (sim builds ignore it). The DeviceActivity extension carries its own `KiroleDeviceActivityMonitor/KiroleDeviceActivityMonitor.entitlements` (must keep the same App Group).
- **Platform floor:** Swift 6.1 toolchain, **iOS 17+** (`KirolePackage` declares `platforms: [.iOS(.v17), .macOS(.v14)]`).

## Where to Look Next
- `AGENTS.md` — full rules, BLE protocol *rules/summary*, companion IP prompt architecture, onboarding detail, Focus Mode state machine, Event→Output dispatch map.
- `CONTEXT.md`（仓库根）— **领域术语表（ubiquitous language）**：设备任务库、当天内容包、三分钟稳定窗、来源页面、断联专注、完成优先/跳过合并/删除优先等 29 条术语的权威定义（每条附「避免」反义词）。给功能命名、判断行为对错、写协议条款前先对照它；产品决定变更时它随 ADR 一起改。
- `docs/adr/` — 0001–0029 逐条产品决定（ADR），一篇一决定。已被推翻的顶部有 superseded 标注（0001/0002 → 0029「任务库仅当天」）。改任务范围、稳定窗、冲突优先级前先查这里——#13 明文：变更这些必须重新做产品决定，不能编码时自行改写。
- `docs/` — **hardware-facing source of truth** (AGENTS.md defers here). `BLE通信协议规格文档.md` is the **authoritative BLE wire-protocol spec** — the firmware contract; edit this file directly (versioned — see its header for the current version), never a root-level copy. `BLE初次联调指南.md` / `BLE联调前全协议模拟报告.md` are the integration + dry-run guides; `硬件需求文档-Hardware-Requirements-Document.md` and `固件功能规格文档.md` are the hardware/firmware requirement specs; `Kirole显示屏页面（游戏机制2）.pdf` and `positioning-narrative.md` are the product mechanism / positioning source of truth (e.g. why the streak system was deleted); `2026-07-09-spec.md` is the executed spec for the focus-interruption redesign (D-1/D-2/D-3 decisions + "don't fix as bug" list). `电子墨水屏需求/客户答复-2026-07-20.md` + `待客户确认问题清单.md` are the **settled customer rulings** behind the current e-ink display behavior — check these before re-litigating a display question or reporting one as a bug. When you change a BLE/firmware doc here, the protocol byte tables and §-numbers are what the hardware team builds against — keep them exact.
- `.cursor/rules/*.mdc` — Swift / SwiftUI / Testing / Concurrency / Foundation Models / XcodeBuildMCP guidance.
- `TESTFLIGHT_GUIDE.md`, `TESTFLIGHT_PROGRESS.md` — release workflow state.

### Repo-specific skills (`.claude/skills/`) — check before non-trivial work
CLAUDE.md / AGENTS.md describe **what this repo is**; these skills describe **how not to get hurt in it** (distilled from commit history, incidents, and past rollbacks). **`kirole-atlas` is the routing index — open it first when unsure which applies.**

| About to… | Skill |
|-----------|-------|
| Change BLE wire bytes / encoder fields | `ble-wire-change-control` |
| Debug "hardware isn't showing new data" / sync / offline replay | `ble-sync-runbook` |
| Delete or replace an image / audio / font asset | `client-asset-change-control` |
| Edit a `docs/` hardware contract (protocol, firmware spec) | `docs-contract-change-control` |
| Judge whether a feature/audit suggestion should be built at all | `product-scope-contract` |
| Triage a test that flakes red/green | `flaky-test-triage` |
| Check if a "bug" is actually intentional | `intentional-behaviors-contract` |
| Touch LLM prompts / sanitization / output budget | `llm-prompt-safety-contract` |
| Release to TestFlight, or debug testers not seeing a build | `release-acceptance`, `testflight-distribution-runbook` |
| Take over after a subagent run, or act on a review/audit report | `subagent-output-audit` |
| Call UI work "done" | `ui-change-acceptance` |
| Understand why a guardrail exists | `failure-archaeology` |
| Find a diagnostic tool (simulator, frame trace, prompt debugger) | `diagnostic-toolbox` |

The `ios-*` (DebugBridge), `reactcomponents`, and `swift-*` skills are generic, not Kirole-specific.
