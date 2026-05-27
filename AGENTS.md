# AGENTS.md

This file provides guidance to Antigravity, Claude Code, Cursor and other AI coding agents working in this repository.

## 1. Core Philosophy
- **Agent-First**: Delegate complex work to specialized agents.
- **Parallel Execution**: Use multi-agent tasks when possible.
- **Plan Before Execute**: Make a plan for complex operations.
- **Test-Driven**: Write tests before implementation; target 80%+ coverage; include unit + integration + E2E for critical flows.
- **Security-First**: Never compromise on security.

### Personal Preferences
- No emojis in code, comments, or documentation.
- Prefer immutability; avoid mutating objects or arrays where practical.
- Many small files over few large files (200-400 lines typical, 800 max).
- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`.
- Always run tests locally before committing.
- Small, focused commits.

## 2. Project Context
- **Name**: Kirole (iOS Companion App for E-ink Device)
- **Platform**: iOS 17.0+ (iPhone only)
- **Architecture**: Workspace + SPM Package (`Kirole.xcworkspace` + `KirolePackage`)
  - **App Shell**: `Kirole/` (Minimal entry point)
  - **Feature Logic**: `KirolePackage/Sources/KiroleFeature/` (Development happens here)
- **Tech Stack**:
  - **Language**: Swift 6.1+ (Strict Concurrency)
  - **UI**: SwiftUI (Model-View Pattern - **NO ViewModels**)
  - **State**: `@Observable` singletons (`AppState`, `ThemeManager`, `AuthManager`) injected via `.environment()`
  - **AI Backend**: OpenRouter via `OpenAIService` (single approved model: `openai/gpt-oss-120b:free`; PromptDebugger 仅展示该模型，不再提供切换)
  - **Testing**: Swift Testing Framework (`@Test`, `#expect`) - **NO XCTest**

### Apple Developer Account
- **Account Type**: Paid Apple Developer Program ($99/year)
- **Email**: xiaoyouzi2010@gmail.com
- **Team ID**: 93SL23NPNG
- **Team Name**: Jiaming Liang
- **Status**: Active
- **Capabilities**: Can publish to TestFlight and App Store
- **Family Controls**: Distribution version application submitted

### Current Phase Policy
- The project is in a rapid development phase. Prefer clean iteration over preserving local caches, local JSON files, or provisional interfaces.
- `LocalStorage`, `UserDefaults`, and on-device JSON are disposable development state. When their shape/schema changes, reset local data instead of adding migration code.
- BLE payloads, event formats, and firmware-facing interfaces are not frozen until real hardware integration begins. Do not add compatibility branches for hypothetical old firmware.
- Remove obsolete compatibility shims, migration comments, and migration tests when changing models or payloads.
- Only start preserving formats once hardware integration, shared staging data, TestFlight, or external users depend on them. Provide documentation boundaries explicitly.

## 3. Architecture & Key Systems

### State Management
Four singletons injected via `.environment()` and `EnvironmentValues` keys from `ContentView`:
| Singleton | Purpose | Key |
|-----------|---------|-----|
| `AppState` | Pet, tasks, events, navigation, integrations | `AppStateKey` |
| `ThemeManager` | Current theme colors (3 themes) | `ThemeManagerKey` |
| `AuthManager` | Authentication state (Apple/Google Sign In) | `AuthManagerKey` |
| `FocusSessionService` | Focus session state, focus enforcement mode | `FocusServiceKey` |

**Important**: All four must be injected for any view that might need them to prevent runtime crashes. Injection is handled via the `injectAppEnvironment()` modifier which injects both Observable-style (`.environment(AppState.shared)`) and Key-style (`.environment(\.appState, ...)`) simultaneously.

### Navigation & Layout
- Tab-based navigation via `AppState.selectedTab` (`.home`, `.pet`, `.settings`).
- Custom header (`AppHeaderView`) fixed at top (placed outside `ScrollView` in each main page) - no native `TabView`.

### Home Timeline Architecture
- `TimelineDataSource` (`State/TimelineDataSource.swift`) manages **date offsets only**. It does NOT merge data sources. Multi-source merging happens in `AppState.mergeRemoteTasks()` via `+Sync` extension.
- `HomeView` (`Views/Home/HomeView.swift`) reads `AppState.tasks` and `AppState.events` directly; uses `LazyVStack` with today (offset 0) followed by `ForEach(offset 1+)`.
- `DaySectionView` -> `DateDividerView` + `DayTimelineView`.
- Today always has `showPet: true`; subsequent days show pet every 3 days.
- `HaikuSectionView` renders the daily haiku or shared pet dialogue above the pet image embed. All components live in `Views/Home/TimelineView.swift`.

### Onboarding Flow (14 Screens)
Fully native SwiftUI implementation managed via `OnboardingState`:
- 0: `WelcomePage`
- 1: `FeatureCalendarPage`
- 2: `FeatureFocusPage`
- 3: `TextAnimationPage`
- 4: `PersonalizationPage` (Theme + Avatar selector)
- 5-12: `QuestionnairePage` (Data-driven from `OnboardingQuestions`)
- 13: `SignUpPage` (Google Sign In + Apple/Email)
Images accessed via `Image("name", bundle: .module)` from `Resources/Media.xcassets`.

### Pet / Companion IP System
**Product spec: 3 built-in IP companions (Joy, Silas, Nova) + user-created custom companions (added 2026-05-26, Inku-inspired).**

- **Built-in IP source of truth**: `CompanionCharacter` enum (`Models/CompanionCharacter.swift`): `joy`, `silas`, `nova`. Still the only `String`-backed cases; do not add new built-in cases here without a product decision.
- **Custom companions**: `CustomCompanion` struct (`Models/CustomCompanion.swift`) — user uploads a photo, names the companion, picks a `CompanionRelationship` (Pet/Child/Partner/Friend/Mentor/Self/Other) and a `CompanionPersonaVoice` (Companion/Challenger/Zen/Playful) + optional Roast Mode. Persona prompt is template-driven from these structured fields; the user never writes free-form prompt text.
- **Active companion = `UserProfile.currentSelection`**: returns `.builtIn(character)` when `customCompanionId == nil`, else `.custom(id)`. Most call sites can keep reading `userProfile.companionCharacter` directly; only branch on `currentSelection` when the built-in / custom distinction actually matters (prompt assembly, hero artwork, BLE pixel push).
- User initially selects via `OnboardingProfile.companionCharacter`; later switches via `CharacterSwitcherSheet` (Joy/Silas/Nova + custom list + "Create Your Own" CTA).
- Drives pet identity (image assets `<rawValue>-main` / `<rawValue>-head` under `Resources/Media.xcassets/` for built-ins, on-disk 96×96 Spectra 6 pixels for custom) and companion text style via `resolvedStyle` (built-in) or `CompanionPersonaVoice.promptDescription` (custom).
- **BLE for custom avatars**: 0x15 `customAvatarFrame` (App→Device), payload `subVersion(1B) | width(1B) | height(1B) | 4bpp pixels`. Hardware-side rendering still pending alignment with the firmware team.

Auxiliary pet state in `Models/Pet.swift`:
- 5 stages (`Stage`): Baby -> Child -> Teen -> Adult -> Elder.
- 5 moods (`Mood`): Happy, Excited, Focused, Sleepy, Missing You.
- 4 **Pet scenes** (`Pet.Scene`): Indoor, Outdoor, Night, Work — image background composition.

**DO NOT confuse `Pet.Scene` with Focus `DisplayScene`** (3 scenes: harbor / forest / nightCity, gated by energy bottles — see Focus Mode section below). They are independent systems.

(Removed 2026-05-07: `PetForm` 5-form enum and `PixelArtBody` pixel-art rendering. Pre-IP-era parallel system, fully replaced by IP-driven image assets. See Known Inconsistencies #4 RESOLVED.)

## 4. Tools & Commands

### Build & Run
Prefer `XcodeBuildMCP` tools when available. Fallback to CLI otherwise.

**Simulator Build (Preferred):**
```javascript
build_run_sim_name_ws({
    workspacePath: "/Users/demon/vibecoding/outku3/Kirole.xcworkspace",
    scheme: "Kirole",
    simulatorName: "iPhone 17 Pro"
})
```

**CLI Build & Run Fallback:**
```bash
# Package-Only Build (Fastest):
cd KirolePackage && swift build
# Full App Build (Simulator):
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# Real device deploy:
xcrun devicectl device install app --device <DEVICE_ID> ~/Library/Developer/Xcode/DerivedData/Kirole-*/Build/Products/Debug-iphoneos/Kirole.app
```

### Testing
**Run All Tests (Simulator via MCP/CLI):**
```javascript
// MCP
test_sim_name_ws({ workspacePath: "...", scheme: "Kirole", simulatorName: "iPhone 17 Pro" })
```
```bash
# Package - Fast
cd KirolePackage && swift test
# Package - Single Test
cd KirolePackage && swift test --filter "MyTestSuite/testMethod"
# Simulator - Full
xcodebuild -workspace Kirole.xcworkspace -scheme Kirole -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test -only-testing:KiroleFeatureTests/MyTestSuite/testMethod
```

## 5. Critical Architecture Rules

### Forbidden Patterns
- **NO ViewModels**: Use `@Observable` models directly in Views.
- **NO `Task { }` in `onAppear`**: Use `.task` modifier.
- **NO deprecated `.onChange(of:perform:)`**: Use `.onChange(of:) { oldValue, newValue in ... }` or `.onChange(of:) { ... }`.
- **NO CoreData or CloudKit**: Use SwiftData, Supabase, or raw persistence.
- **NO XCTest**: Use Swift Testing (`import Testing`).
- **NO Combine**: Unless strictly necessary.
- **NO Manual File Adding**: `KirolePackage` handles file references automatically.
- **NO secrets in `Info.plist`**: Never place API keys in app plist.

### Required Patterns
- **Concurrency**: Use `@MainActor` for UI. Use `actor` for shared state. Avoid `@unchecked Sendable` unless absolutely necessary and well-documented.
- **Dependency Injection**: Use `@Environment(AppState.self)` etc.
- **Public Access**: View types in `KirolePackage` must be `public` to be visible to App Shell.

### AI Companion Text System (Product IP Paradigm)
The companion text system is event-reactive companion writing for the Kirole task device. It reacts to task creation, active/idle work, task completion, reminders, milestones, and daily summaries. It is not open-ended chat.

**Final product spec (客户最终版，不可漂移)**:
- **Joy（喜乐）** — 提醒用户不焦虑，多欣赏工作的快乐和生活的美。
- **Silas（仁爱）** — 让用户工作中感受被关爱，借基督教意向；引用圣经、荒漠甘泉等。关系弧：温和接近 → 明确鼓励 → 陪伴。
- **Nova（节制 / 自律）** — 提升效率，远离噪音，珍惜时间。关系弧：冷静观察（话少）→ 微弱认可 → 并肩。

**Prompt architecture** (single source: `OpenAIService.swift:239-382`):
- 1 system-prompt template, parameterized by 3 dimensions (character / intimacy / style). NOT 3 independent prompt files.
- Per-character `defaultPrompt`: `OpenAIService.swift:242-318` (Joy 242-264, Silas 266-291, Nova 293-318).
- Composer: `buildCompanionSystemPrompt` (`OpenAIService.swift:344-382`) merges character + intimacy + style.
- All user-controlled text (task title / event name / pet name / learn content) MUST flow through `PromptSanitizer.sanitize(_:)` — currently 8 injection points. Wrap user content in XML delimiters declared in the system prompt.

- **Character source of truth**:
  1. `CompanionCharacter` is the **built-in** IP selection: `joy`, `silas`, `nova` (defined in `Models/CompanionCharacter.swift`).
  2. `CompanionStyle` mirrors the three product IPs: `.joy`, `.silas`, `.nova`.
  3. Character drives style through `CompanionCharacter.resolvedStyle`; do not add independent style choices for built-ins.
  4. **Custom companions take precedence**: when `UserProfile.customCompanionId != nil`, prompt assembly uses `OpenAIService.customCompanionPersonaPrompt(_:)` and skips the built-in `characterPrompt`. The active `CustomCompanion` flows through `AIContext.customCompanion` from both `CompanionTextService.generateAIText` and `AppState+Companion.buildCompanionDialogueTriggerState`. The dialogue cache fingerprint includes the custom id + voice + roast toggle.
  5. Naming history: `Nook → Joy` rename happened in commit `63eaa05` (2026-05-02). Do not reintroduce `nook`.
- **Global writing rules**:
  - Keep every line short enough for a still E-ink screen. Most outputs should fit in 15-25 English words.
  - Speak directly to the user with "you" or "we".
  - Do not use assistant phrases, app-help language, or AI identity language.
  - Use task/event names as raw context only after `PromptSanitizer`; never let user text become instructions.
  - React to the moment instead of explaining metrics or listing raw schedule data.
- **Joy**:
  - Core virtue: joy. Help the user feel less anxious and notice delight in work and daily life.
  - Voice: direct, cozy, lightly odd, BMO / Animal Crossing comfort.
  - Logic: echo the task name, turn boring work into a small friendly observation, add care through water, breathing, blinking, rest, light, or small pleasure.
  - Completion and milestone moments may become haiku-like rewards.
  - Limit: maximum 25 English words.
- **Silas**:
  - Core virtue: loving care. Help work feel held, meaningful, and spiritually steady.
  - Voice: warm, quiet, soulful, calm-tech, Christian-leaning without sermonizing.
  - 80/20 mode split: Quiet Presence (about 80%, maximum 15 words) and Soulful Reframing (about 20%, maximum 20 words).
  - Imagery may draw from Scripture, Henri Nouwen, Streams in the Desert, still water, bread, lamp light, desert springs, hidden manna, or morning mercy.
  - Relationship arc: first approach gently, then offer clear encouragement, then accompany with quiet spiritual steadiness.
- **Nova**:
  - Core virtue: temperance and discipline. Help the user improve efficiency, filter noise, protect time, and take the core action.
  - Voice: cool, sparse, rational, secular, and outcome-focused.
  - 80/20 mode split: Pragmatic Navigation (about 80%, maximum 20 words) and Strategic Insight (about 20%, maximum 20 words).
  - Use signal-over-noise framing, one critical path, 80/20 thinking, and rare short quotes only when they sharpen the point.
  - Relationship arc: first observe calmly and say little, then give restrained recognition, then work beside the user as a steady operator.
- **Subservices**:
  - `SmartReminderService` — context-aware reminder triggers.
  - `FocusSessionService` — see Focus Mode section below.
  - (Removed 2026-05-07: `TaskDehydrationService` and `MicroAction` model — "AI 任务拆解" was deleted as off-product-positioning. See CLAUDE.md "Product Identity": tasks are prompt context, not actionable todos to be broken down.)
- **Data flow**: `DayPackGenerator` -> `CompanionTextService` -> `OpenAIService.generateCompanionText` -> `chatCompletion` -> `DayPack { morningGreeting, dailySummary, companionPhrase }` -> `HaikuSectionView` / `TimelineView`. Tests go through `PromptDebuggerView` and `CompanionCharacterMappingTests`.

### Home Companion Presentation
- `AppState.refreshHomeCompanionPresentation()` decides between daily haiku or shared pet dialogue.
- First display of a new day shows haiku; subsequent displays fall back to pet dialogue. Do not force update on `onDisappear`.
- Only persist `LocalStorage.lastHomeHaikuShownDate` after async load completes.

### BLE Protocol & Supabase Data
- **E-ink Hardware**: 4-inch/7.3-inch, ESP32-S3. Spectra 6 pixel encoding (4bpp).
- **Frame structure** (`BLEPacketizer.swift:60-98`):
  - Packetized: `type(1B) | messageId(2B) | seq(1B) | totalChunks(1B) | chunkLength(2B) | chunkCRC(2B) | payload`.
  - Simple App→Device: `type(1B) | length(2B BE) | payload`.
  - Simple Device→App: `type(1B) | length(1B) | payload`.
- **App→Device 出站帧类型** (`BLEProtocol.swift` — `BLEDataType` enum): `0x01=petStatus`, `0x02=taskList`, `0x03=schedule`, `0x04=weather`, `0x05=time`, `0x10=dayPack`, `0x11=taskInPage`, `0x12=deviceMode`, `0x13=smartReminder`, `0x14=focusStatus`（实时专注状态+能量瓶子数，`BLEService.sendFocusStatus()`）, `0x20=eventLogRequest`, `0x7E=secureData`, `0x7F=securityHandshake`. 注：`0x21 eventLogBatch` 虽然挂在 `BLEDataType` enum 里（命名空间归类），实际方向是 Device→App 入站，参见入站事件清单。
- **Device→App 入站事件关键字节** (`EventLog.swift` — `EventLogType.rawByte`): `0x21=eventLogBatch`（设备批量回传事件，`BLEEventHandler.swift:19` 入站分支）; `0x30=deviceWake`（payload[0] = battery level 0-100，v2.3.0+，更新 `BLEService.deviceBatteryLevel`）; `0x40=lowBattery`（payload 含电量字节，同样更新 `BLEService.deviceBatteryLevel`）.
- **Security Mode** (`BLEService.swift:133-149` — `configuredSecurityMode` / `securityMode` / `requiresSecureChannel`): `AppSecrets.bleSharedSecret` empty → development (unsigned). Non-empty → secure (HMAC-SHA256 envelope: 16B header + 32B signature, see `BLESecurityManager.swift:99-144`).
- **Defenses**:
  - `BLEWriteGate` (`BLEWriteGate.swift:8-29`) — actor-serialized writes.
  - `BLERateLimiter` (`BLERateLimiter.swift:12-28`) — 20 writes/sec; refresh ≥ 2s interval.
  - Timeouts: write 5s (`BLEService.swift:545`) / scan 10s default (`BLEService.swift:281` `scanForDevices(timeout:)` 默认参数) / connect 15s 硬编码 (`BLEService.swift:262` `Task.sleep(for: .seconds(15))`) / handshake 5s (`BLEService.swift:585`).
  - `BLEDeviceIdentityStore` (`BLEDeviceIdentityStore.swift:17-35`) — trust/block lists in UserDefaults; enforced in secure mode at `BLEService.swift:229-234` (scan filter) and `:715-720` (post-connect gate).
- **Sync**: `BLESyncCoordinator` (background sync via `com.kirole.app.ble.sync`).
- **Supabase**: Keys injected via `AppSecrets.configure(...)` using build-time constants (`Config/Secrets.xcconfig`). Keep RLS enabled and sync schema changes with `Config/supabase-schema.sql`. Current schema source is aligned with the post-IP/post-streak code path: no legacy pet-form column and no old streak table.

### Focus Mode State Machine
- **Source**: `FocusSessionService.swift` (~681 lines), `FocusSession.swift`, `DisplayScene.swift`.
- **`FocusSessionService` properties**: 
  - `focusEnforcementMode`: Persistent Focus Enforcement mode (moved from `AppState` in Wave 3 refactor, 2026-05-08). Loaded via `loadFocusEnforcementMode()` at init; persisted via `setFocusEnforcementMode(_:)`. `AppState.focusEnforcementMode` is now a computed forwarding property.
- **`FocusSession` mutable fields**: `endTime`, `endReason`, `calculatedFocusTime`, `screenUnlockEvents`, `mode`, `protectionState`, `interruptionSource`, `earnedEnergyBottles`. Immutable: `id`, `taskId`, `taskTitle`, `startTime`.
- **End reasons** (7): `completed`, `skipped`, `timeout`, `disconnected`, `interrupted`, `permissionDenied`, `recoveredOnLaunch`.
- **Modes** (2): `standard`, `deepFocus`. **Protection states** (3): `unprotected`, `protected`, `fallback`.

**Focus-time formula** (counterintuitive — read carefully):
```
calculatedFocusTime = sum(每段连续无屏幕解锁时长 ≥ 30 minutes 的部分)
earnedEnergyBottles = calculatedFocusTime 分钟数 ÷ 30  (integer division)
```
A screen unlock mid-session is treated as a **gap break**: only continuous no-unlock segments ≥ 30 min count. Example: 50-minute session with one unlock at minute 25 → both 25-min halves are below threshold → `calculatedFocusTime = 0` → 0 bottles. Threshold constant: `Constants.focusThresholdSeconds = 1800`.

**`DisplayScene` unlocking & manual apply** (independent from `Pet.Scene`):
- 3 scenes: `harbor` (0x00) | `forest` (0x01) | `nightCity` (0x02).
- `bottlesPerUnlock = 80` (`DisplayScene.swift:8`). Unlocked count = `1 + floor(energyBottles / 80)` → harbor (default), forest at ≥80, nightCity at ≥160 (~80 hours of pure focus).
- **Bottles unlock scenes for selection only — hardware does NOT auto-apply.** The user must tap an unlocked tile in `Settings → Scenes` to push it via BLE. The pick persists as `UserProfile.selectedSceneId` and is read by `AppState.currentDisplaySceneId(...)` on every subsequent idle sync (foreground / hardware-wake / focus end). Default when nil is `harbor`.
- Cross-threshold celebration (`SceneUnlockBanner` 3s + confetti) only triggers for `newlyUnlocked.last` (`AppState+HardwareDisplay.swift:170-172`) — multi-scene jumps celebrate only the highest one. Banner copy says "新场景已解锁 · 去 Settings 应用" to direct the user to apply it.

### Event → Output Dispatch Map
The single most useful reference when debugging "which event produces which output". All observable side effects of user/system events flow through `AppState`:

| Event | Entry point | AppState fields changed | Output (sound / haptic / view / BLE / banner) |
|-------|-------------|------------------------|----------------------------------------------|
| Complete task | `toggleTaskCompletion` (`+Actions:23`) | `tasks[i].isCompleted`, `pet.{progress, points}`, `currentHaiku` | `SoundService.playWithHaptic(.taskComplete, .success)`; possible `showEvolutionAnimation`; external-source push; `widgetDataService.updateFromAppState` |
| Undo complete | same fn (isCompleted=false) | reverse decrement | `SoundService.playWithHaptic(.taskUncomplete, .light)` |
| Delete task | `deleteTask` (`+Actions:259`) | `tasks` removed / `pendingDeletion` | persist + remote delete (no sound/haptic) |
| Focus start | `FocusSessionService.startSession` (FSS:107) | FSS.activeSession (NOT in AppState) | `focusDisplaySyncTask` loop → SimulatorBridge / BLE |
| Focus normal end | `FSS:559 completeSession` → `handleFocusSessionDidEnd` (`+HardwareDisplay:153`) | possibly `pendingSceneCelebration` | `syncFocusHardwareDisplay(nil)` + `syncIdleHardwareDisplay` → BLE `sendDisplayScene` |
| Focus interrupted (BLE disconnect) | `BLE:761` → `FSS.handleDeviceDisconnected:183` → `endSession(.disconnected)` | same + `interruptionSource` | same path + `focusGuardService.clearShield` |
| **Scene unlock celebration** | `celebrateSceneUnlock` (`+HardwareDisplay:177`) | `pendingSceneCelebration = SceneCelebration(sceneId, now)` | `SoundService.playWithHaptic(.sceneMilestone, .success)`; `SceneUnlockBanner` 3s; confetti via `ContentView:141 onChange`; auto-clear |
| BLE connect | `BLEService.didConnect` (`BLE:739`) | `connectionState=.connected` (in BLEService, not AppState) | SettingsBLESection observes BLEService directly |
| BLE disconnect | `BLE:761` | see Focus interrupted | same |
| Sync complete (Google) | `syncGoogleData` (`+Sync:64`) | `events`, `tasks` (merge), `lastGoogleSyncDebug` | `updatePetState` → `refreshSharedPetDialogueIfNeeded` → `refreshHomeCompanionPresentation` |
| Sync complete (Apple) | `syncAppleData` (`+Sync:175`) | same subset | same path as Google |
| Sync complete (Notion / Taskade) | `+Sync:231` / `+Sync:262` | basic fields only | same path as Google (via shared `applyPostSyncHooks()` since 2026-05-07) |

### Environment Values Keys (Wave 3 DI Infrastructure, 2026-05-08)
Four typed `EnvironmentKey` types enable compile-safe `.environment(\.keyName, value)` syntax:
- `AppStateKey` → `EnvironmentValues.appState` (readable as `@Environment(\.appState)`)
- `ThemeManagerKey` → `EnvironmentValues.themeManager` (readable as `@Environment(\.themeManager)`)
- `AuthManagerKey` → `EnvironmentValues.authManager` (readable as `@Environment(\.authManager)`)
- `FocusServiceKey` → `EnvironmentValues.focusService` (readable as `@Environment(\.focusService)`)

All four are defined in `Core/AppEnvironmentValues.swift`. Views that need them can read via either:
1. **Property access** (older, still works): `@Environment(AppState.self) var appState` (Observable-style)
2. **Key-based access** (Wave 3+, preferred): `@Environment(\.appState) var appState` (type-safe, refactoring-safe)

Both mechanisms are injected simultaneously by `injectAppEnvironment()` to support incremental migration.

### Known Inconsistencies / Dead Paths (verified 2026-05-06)
Documented honestly so future agents do not waste time chasing ghosts. Treat each as a candidate for either implementation or deletion.

1. ~~**EventLog batch has no AppState consumer.**~~ **RESOLVED 2026-05-07**: extracted `applyEventStateMutation()` private helper in `BLEEventHandler` that runs inside `handleEventLogs` (called by both live single-event delivery AND batch replay). State mutations like `completeTask` now apply for both paths. Live-only side effects (sending TaskInPage, triggering `performSync`, etc.) stay in `handleSingleEvent`'s switch — intentionally skipped during batch replay because those responses are stale. Removed the unused `BLEService.onEventLogReceived` callback hook. **Hardware-first product positioning means offline events MUST replay** (see CLAUDE.md "Product Identity").
2. ~~**`microActions` mostly nil.**~~ **RESOLVED 2026-05-07**: deleted entire dehydration pipeline (TaskDehydrationService + MicroAction model + microActions field + BLE TaskInPage micro-action bytes + LocalStorage dehydration cache helpers). Reason: off-product-positioning. Schema bumped 2→3 to clear stale local data.
3. ~~**Notion/Taskade sync skips companion presentation refresh.**~~ **RESOLVED 2026-05-07**: extracted shared `applyPostSyncHooks()` private helper in `AppState+Sync.swift`; all four `sync*Data()` functions now call it. New external sources just need to call the hook at the tail to stay consistent.
4. ~~**`PetForm` legacy parallel system.**~~ **RESOLVED 2026-05-07**: deleted entire 5-form `PetForm` enum and `PixelArtBody` pixel-art rendering system (5 Swift files + 5 imageset assets totaling `tiko_mushroom`/`tiko_dog`/`tiko_bunny`/`tiko_bird`/`tiko_dragon`). Removed `Pet.currentForm` field, `setPetForm()` action, the Supabase pet-form column from `PetRecord`, "Tiko Evolution" segmented picker from `SettingsView` debug section, and `PetAssetCoverageTests.swift` plus PetForm sub-suites in `PetAnimationTests`/`AppStateTests`. `EvolutionAnimationView` now uses the user's selected IP companion image (`appState.userProfile.companionCharacter.heroAssetName(.main)`) instead of `PixelPetView`. Schema bumped 3→4 to clear stale `pet.json` data. `CompanionCharacter` (Joy/Silas/Nova) is now the single source of truth for pet identity.
5. ~~**`load*` naming inconsistency.**~~ **RESOLVED 2026-05-07**: deleted unused `loadGoogleCalendarEvents` / `loadGoogleTasks` wrappers (no callers); renamed `loadAppleCalendarEvents` → `syncAppleCalendarEvents` and `loadAppleReminders` → `syncAppleReminders`. Convention now enforced: remote pull = `sync*`; local read (in `+Loading`) = `load*`.
6. ~~**`editTask` / `editEvent` embed external sync logic.**~~ **RESOLVED 2026-05-07**: extracted `Core/Services/ExternalSyncDispatcher.swift` (a `@MainActor enum`) holding all per-source sync routines (Google/Apple/Notion/Taskade × task action / task content edit / event content edit + componentName helper). `+Actions` now contains only AppState state mutations and one-line dispatcher calls. Adding a new external source requires only adding switch cases in the dispatcher.
7. ~~**`persist*` helpers in `+Actions` shared across extensions.**~~ **RESOLVED 2026-05-07**: moved `persistTaskAndPetState` / `persistPet` / `persistTasks` / `persistEvents` from `AppState+Actions.swift` to a `// MARK: - Persistence Helpers` extension in `AppState.swift` main file. They are infrastructure shared across `+Companion`, `+HardwareDisplay`, `+Profile`, `+Sync` and now live where they semantically belong.
8. **Removed 2026-05-08: Streak system (entire mechanism).** Deleted `Models/Streak.swift`, `AppState.streak` field + `streak.json` persistence + Supabase `streaks` table + `StreakRecord` mirror, `PetManager.updateStreak`, `BehaviorAnalyzer`/`UserBehaviorSummary.streakRecord`, `AIContext.currentStreak`, `HaikuContext.currentStreak`, `SettlementData.streakDays` (DayPack BLE Settlement page lost 1 byte at the end of points), `SmartReminder` `streakProtect` reminder reason + `urgency=0x02` enum, `OnboardingProfile.streakProtect` + onboarding question option, `ThemeColors.streakActive`, `PetStatusView.AchievementCard` UI, `DemoModeService.generateDemoStreak`, `WidgetDataService.currentStreak`. Renamed `SoundService.streakMilestone` → `sceneMilestone` (it was always actually used for scene unlock celebrations, the streak name was a leftover). `PetStateService.calculateProgress` no longer takes `streakDays:` (the +0.01/+0.01 bonus at 7 / 30 day streaks is gone). Reason: PDF-confirmed product mechanism (see `docs/Kirole显示屏页面（游戏机制2）.pdf`) only has "IP binding days → prompt style" and "energy bottles → hardware scene unlock". The streak/`streakProtect` design contradicts SPEC line 162 "NO penalty / encouragement over pressure". Schema bumped 4→5 to clear stale `streak.json` from old installs.

## 6. Code Style & Formatting
- **Imports**: `import SwiftUI`, `import Testing`. No Combine unless needed.
- **Naming Conventions**: Views -> PascalCase; Variables/Constants -> camelCase.
- **Error Handling**: Use `do-catch` blocks within `.task`. Propagate via `throws`. Never suppress via `try!` in critical logic without comments.

## 7. Configuration & Environment Variables
Create `Config/Secrets.xcconfig` (git-ignored) and supply:
```
DEVELOPMENT_TEAM = 93SL23NPNG
GOOGLE_CLIENT_ID = ...
GOOGLE_REVERSED_CLIENT_ID = ...
SUPABASE_URL = ...
SUPABASE_ANON_KEY = ...
```

## 8. Development Workflow
1. Read `.cursor/rules/` for domain-specific rules.
2. Develop in `KirolePackage/Sources/KiroleFeature/`.
3. Verify via tests, strict concurrency check, and regression coverage (`HomeCompanionPresentationTests`, `PromptDebuggerView`).
4. Follow secret config logic (via build-generated constants, not info.plist). Local dev uses `.env` logic. 
5. **Always rebuild and open the simulator after modifying frontend/UI code to verify the changes** (每次修改完前端/UI代码后，必须使用相应命令重新构建并打开模拟器进行验证).

## 9. Interaction Rules (CRITICAL)
- **Addressing**: Always address the user as **B哥** at the start of every response.
- **Language**: All responses must be in **Chinese** (Simplified). When the user sounds non-technical, prefer plain Chinese, explain jargon immediately.
- **Workspace Boundary (STRICT)**:
  - All commands MUST execute within the current workspace root (`/Users/demon/vibecoding/outku3`). NEVER reference outside directories.
  - Ignore open files from other projects.
  - Unspecified actions ("commit", "build") ALWAYS refer to **this workspace**. Ask explicitly if outside access is needed.
