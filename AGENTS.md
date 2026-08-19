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
- **Hardware BLE 1.3.1 source of truth (flag-day with firmware)**: read `docs/专注状态重连协议变更_Ver_1_3_1.md` then `docs/Kirole_BLE协议命令字节表_专注重连协议更新_Ver_1_3_1.md`. Arbitration table still lives in `docs/Kirole_专注状态重连_App对接说明_Ver_1_3_0.md` §9. Repo-wide spec is `docs/BLE通信协议规格文档.md`; RESULT / COMMIT sentences and EventLogBatch `0x10/0x11/0x12` record lengths there are superseded by `docs/BLE通信协议规格文档-v2.13.2补记.md`. The hardware 1.3.1 byte table §5.15 leftover v2.9 batch rows are not App contract; use the 补记 plus live §5.3–5.5. Remaining questions: `docs/专注重连-与硬件协商项_Ver_1_3_1.md`. Do not unlock `0x14` until `RESULT=COMMITTED`, and do not `COMMIT` while focus is still active.
- **Name**: Kirole (iOS Companion App for E-ink Device)
- **Platform**: iOS 17.0+ (iPhone only)
- **Architecture**: Workspace + SPM Package (`Kirole.xcworkspace` + `KirolePackage`)
  - **App Shell**: `Kirole/` (Minimal entry point)
  - **Feature Logic**: `KirolePackage/Sources/KiroleFeature/` (Development happens here)
- **Tech Stack**:
  - **Language**: Swift 6.1+ (Strict Concurrency)
  - **UI**: SwiftUI (Model-View Pattern - **NO ViewModels**)
  - **State**: `@Observable` singletons (`AppState`, `ThemeManager`, `AuthManager`) injected via `.environment()`
  - **AI Backend**: **OpenRouter only** via `OpenAIService` (2026-07-03 decision) — primary = paid `openai/gpt-oss-120b` pool (`OPENAI_MODEL` in Secrets.xcconfig; `OPENAI_BASE_URL` left empty = OpenRouter). Requests pin `reasoning: {effort: low, exclude: true}` — without it gpt-oss burns the whole 80-token budget on the hidden trace and `content` comes back null. Primary failure falls back to the same model's `:free` pool (same-model pool downgrade, logged, never silent — `ai-provider-fallback`). ⚠️ Closed-model pools (OpenAI/Anthropic/Google official) are region-blocked (403) from CN egress on OpenRouter — don't point the primary at them.
  - **Testing**: Swift Testing Framework (`@Test`, `#expect`) - **NO XCTest**

### Apple Developer Account
- **Account Type**: Paid Apple Developer Program ($99/year)
- **Email**: xiaoyouzi2010@gmail.com
- **Team ID**: 93SL23NPNG
- **Team Name**: Jiaming Liang
- **Status**: Active
- **Capabilities**: Can publish to TestFlight and App Store
- **Family Controls**: Distribution version application submitted

### Release Channel Policy (2026-08-15 Decision)

Kirole has exactly **two distributed channels**. Local `Debug` builds are development tools, not a third distribution channel.

| Channel | Purpose | Required build behavior |
|---------|---------|-------------------------|
| **Internal TestFlight** | Product acceptance and hardware/firmware debugging by the internal team | Release-optimized build with all internal/debug tools enabled; upload as **TestFlight Internal Only** |
| **App Store** | Customer distribution | Release-optimized production build with internal/debug UI, behavior, logging, factory commands, and test shortcuts compiled out |

#### Source and Branching Rules

- Maintain **one codebase and one long-lived `main` branch**. Do not create permanent `internal`, `develop`, or App Store branches that accumulate separate fixes and features.
- Use small, short-lived feature branches. Merge through a reviewed PR after tests pass, then delete the branch.
- A temporary release or hotfix branch is allowed only for short stabilization work. Merge every fix back to `main` promptly and delete the temporary branch after release.
- Prefer one app target with two distribution configurations/schemes: `InternalRelease` / `Kirole-Internal` and `AppStoreRelease` / `Kirole-AppStore`. Because feature code lives in `KirolePackage`, implementation must prove that the internal compilation condition reaches the package target and that excluded symbols are absent from the App Store archive. If Xcode/SPM cannot guarantee that boundary, isolate internal tools in a separate package product or app target instead of falling back to a runtime-only gate. A separate bundle ID or App Store Connect app still requires an explicit product decision and is only justified by needs such as side-by-side installation or complete data/environment isolation.
- After a feature is approved for production, generate the Internal verification build and App Store candidate from the same tagged source commit when practical. They are separate binaries because their compilation conditions differ; never promote an Internal TestFlight binary directly to App Store.

#### Compile-Time Debug Boundary

- `InternalRelease` defines one explicit compilation condition such as `KIROLE_INTERNAL`; `AppStoreRelease` must not define it. Do not use `DEBUG` to identify Internal TestFlight because the internal archive is still a Release-optimized build.
- Internal-only capabilities must be protected at the implementation boundary with `#if KIROLE_INTERNAL` or an equivalent build-time exclusion. Hiding a SwiftUI row is insufficient if services, logging, timers, BLE commands, or mutable test behavior remain active.
- Internal-only scope includes Wi-Fi PC Debug, the Keep Alive **toggle**, Focus Debug and virtual time, test focus sessions, raw BLE diagnostic summaries, Shipping Mode and other factory commands, engineering OTA flows, environment/source diagnostics, and future hardware bring-up tools. MVP still keeps the BLE link open on both channels; only the Settings switch is Internal-only.
- Internal diagnostics are **never promoted** to App Store. Keep their implementation available to the hardware team through Internal TestFlight, but keep them absent from the App Store binary.
- Never embed secrets in either binary or diagnostic output. Production security configuration, including BLE secure-channel inputs, must come from the production build configuration and must fail closed when required values are missing.
- Add paired gate tests: Internal builds must prove required diagnostics are present; App Store builds must prove the same UI, behavior, logs, commands, and side effects are absent. A receipt-based runtime check may be used only as a temporary defense-in-depth signal, never as the primary release boundary.

#### Feature Promotion Workflow

1. Implement a customer feature on a short-lived branch with tests.
2. Merge it into `main` in small batches. Until product acceptance, compile it only into `InternalRelease`; it must remain absent from `AppStoreRelease`.
3. Upload the internal archive using **TestFlight Internal Only** and record the build number, commit, test scope, and hardware/firmware versions used for acceptance.
4. Only the user's explicit confirmation promotes a product feature to App Store. Approval of a product feature does not approve any adjacent debug or factory capability.
5. Promote the accepted feature with a small reviewed change that enables it for `AppStoreRelease`; do not copy code between branches.
6. Build and test a fresh App Store candidate from a tagged commit. Internal TestFlight acceptance is product evidence, but it is not proof that the differently compiled App Store binary works; run the production gate tests and real-device smoke test separately.
7. Describe every new customer-visible feature specifically in App Review notes and make it accessible to review. Do not ship hidden, dormant, remotely activated, or undocumented internal functionality in the App Store binary.
8. Runtime feature flags are reserved for staged rollout or emergency disablement of functionality already included in, disclosed to, and accessible during App Review. They must not be used to smuggle unreviewed internal/debug functionality through review.
9. Prefer App Store phased release for a gradual customer rollout after approval; do not use a hidden remote switch as a substitute for App Review.

#### Current Migration Status

- **Implemented 2026-08-15**: `InternalRelease` / `AppStoreRelease` configurations exist on the project and all three targets (added via `scripts/add-release-configurations.rb`, idempotent), with shared schemes `Kirole-Internal` / `Kirole-AppStore` archiving them. `Config/InternalRelease.xcconfig` defines `KIROLE_INTERNAL`; `Config/AppStoreRelease.xcconfig` does not.
- **Boundary mechanism (verified)**: Xcode intentionally does not forward custom-configuration `SWIFT_ACTIVE_COMPILATION_CONDITIONS` into SwiftPM package targets, so `KIROLE_INTERNAL` is only visible to app-shell (`Kirole/`) sources. Per this policy's fallback rule, internal-only implementations must live at the app-target level (or a separately linked package product) — an `#if KIROLE_INTERNAL` inside `KirolePackage` compiles identically in both configurations and is NOT a boundary. `Kirole/InternalBuildBoundary.swift` carries the marker; `scripts/verify-release-boundary.sh` is the paired gate (marker present in InternalRelease, absent in AppStoreRelease).
- Fastlane lanes are split: `release` archives `Kirole-Internal` for the TestFlight hardware-acceptance channel (still distributes to the external **kirole** group for tester continuity — moving it to TestFlight Internal Only is a pending workflow decision); `appstore` requires a non-empty `BLE_SHARED_SECRET`, runs the boundary + internal-string gate, archives `Kirole-AppStore`, and uploads the binary without any TestFlight distribution.
- **Implemented 2026-08-17 (App Store wash)**: internal Settings / Focus Debug UI lives in `Kirole/Internal/` under `#if KIROLE_INTERNAL` and is injected via `InternalToolsViews`. `showsHardwareDebugTools` is off unless the Internal app shell calls `enableInternalHardwareChannel()`. MVP still forces BLE keep-alive on the customer channel (no Settings toggle). `scripts/verify-release-boundary.sh` also asserts the internal-tool UI strings are present in InternalRelease and absent from AppStoreRelease. AppStoreRelease device/archive builds and `fastlane ios appstore` fail closed if `BLE_SHARED_SECRET` is empty.
- **Still open (blocking submission)**: `0x19` / `0x1C` encoders remain in `KiroleFeature` (no user-facing strings; symbol-level removal needs a separate package product). Prompt debugger stays Debug-only. App Store screenshots, store copy, privacy questionnaire, WeatherKit attribution on weather-display pages, and hardware-claim evidence are still outstanding.

Primary references: [Apple build configurations](https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project), [Apple schemes](https://developer.apple.com/documentation/xcode/customizing-the-build-schemes-for-a-project), [Apple Internal TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers), [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [Apple phased release](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases), [DORA trunk-based development](https://dora.dev/capabilities/trunk-based-development/), and [GitHub Flow](https://docs.github.com/en/get-started/using-github/github-flow).

### Current Phase Policy
- The project is in a rapid development phase. Prefer clean iteration over preserving local caches, local JSON files, or provisional interfaces.
- `LocalStorage`, `UserDefaults`, and on-device JSON are disposable development state. When their shape/schema changes, reset local data instead of adding migration code.
- Most BLE payloads are still iterable, but Ver 1.3.1 专注重连 + Schedule v2 is the live firmware contract: `0x14` / Enter / Complete / Skip / `FOCUS_STATE` / `FOCUS_RESOLVE` + `RESULT` / `0x03` are flag-day. Do not add compatibility branches for pre-v2 frames. `FOCUS_RESOLVE` unlocks only on matching `RESULT/COMMITTED`. Active focus must not send OfflineSync `COMMIT`.
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
- **Custom companions**: `CustomCompanion` struct (`Models/CustomCompanion.swift`) — the App keeps at most **3** custom companions; creating or "Save as New" is blocked at the limit, while editing/replacing an existing companion remains allowed. User uploads a photo, names the companion, picks a `CompanionRelationship` (Pet/Child/Partner/Friend/Mentor/Self/Other) and a `CompanionPersonaVoice` (Companion/Challenger/Zen/Playful/Custom Prompt) + free-text `backstory` / `sensitiveBoundary` (the latter supersedes the old `roastModeEnabled` boolean, `658a2fb`; the onboarding-side `customCompanionRoast` flag still exists). Persona prompt is template-driven from these structured fields; user free text enters prompts only through `PromptSanitizer` fences (custom-prompt voice audited at build 580).
- **Active companion = `UserProfile.currentSelection`**: returns `.builtIn(character)` when `customCompanionId == nil`, else `.custom(id)`. Most call sites can keep reading `userProfile.companionCharacter` directly; only branch on `currentSelection` when the built-in / custom distinction actually matters (prompt assembly, hero artwork, BLE avatar push).
- User initially selects via `OnboardingProfile.companionCharacter`; later switches via `CharacterSwitcherSheet` (Joy/Silas/Nova + custom list + "Create Your Own" CTA).
- Drives pet identity (image assets `<rawValue>-main` / `<rawValue>-head` under `Resources/Media.xcassets/` for built-ins, on-disk avatar PNG for custom) and companion text style via `resolvedStyle` (built-in) or `CompanionPersonaVoice.promptDescription` (custom).
- **Custom avatar transport (protocol v2.8)**: WiFi is the preferred byte channel. BLE `0x1A WiFiAvatarSession` opens a device SoftAP and returns SSID/endpoint credentials; every response echoes Command + OperationID so the App can discard stale results. The App joins the hotspot, verifies the current SSID by exact UTF-8 bytes, then HTTP POSTs the raw KRI without following redirects. Only a direct HTTP 200 is byte receipt: the existing `0x22 staged → commit → committed` transaction remains authoritative. BLE `0x15 customAvatarFrame` is the automatic fallback and remains a staging-only payload: `subVersion(0x04) | OperationID | AvatarID | FileLength | FileCRC32 | KRI v1 file bytes`. The old PNG (`0x02`) and anonymous KRI (`0x03`) paths are removed. `AvatarImageProcessor` aspect-fits into 800×700 (no square crop, never upscales); `KRIEncoder` converts the persisted PNG to straight-alpha BGRA KRI at send time. The App keeps the old companion active until a matching `committed` result arrives. One persisted `PendingCustomAvatarOperation` supports query-based recovery after disconnect or process death; retries restart from byte zero, with no resumable upload or background-transfer promise. `SecureEnvelope` is HMAC-only and does not hide WiFi credentials; production firmware must require encrypted BLE pairing/link security or a jointly versioned AEAD envelope before enabling `0x1A`, otherwise return unsupported and use BLE fallback.

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

The only supported simulator is **iPhone 17 Pro**. Do not boot, install to, or reuse whatever device happens to be `Booted`. `open -a Simulator` without `-CurrentDeviceUDID` opens Simulator.app's last device (on this machine that is often iPhone 16e), not the one you just booted — that is how a second window appears. Shut other simulators down first:

```bash
xcrun simctl shutdown all
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator --args -CurrentDeviceUDID "$(xcrun simctl list devices booted | awk -F '[()]' '/iPhone 17 Pro/ {print $2; exit}')"
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

### Product Scope Red Lines (do NOT build — reject on sight)
Kirole 是「硬件优先的单设备宠物陪伴产品」。以下提议与定位冲突，直接拒绝：
- **不做多入口稀释**：不做多头像库网格、Apple Watch / Mac 原生端、家庭/多人共享。E-ink 硬件是唯一日常入口，多一块屏就稀释这一叙事。
- **一账号 = 一活跃设备**：跨设备同步按「换机 = 顺序恢复（`max` 合并）」建模，无多写者并发——分布式多写竞态（如「远端写非单调 / 较低值覆盖较高值」）**不适用本产品，勿当 bug 报**（见 CLAUDE.md「Product Identity」单设备模型）。
- **不待办化**：不做 AI 任务拆解、详情页步骤展开、催办式提醒。task/event 只是驱动宠物对话的 prompt 上下文（`TaskDehydrationService` / `MicroAction` 已于 2026-05-07 因此删除，见下文「Known Inconsistencies」）。
- 来源：Inku 竞品深度对比逐条人工裁定（2026-05）。定位话术见 `docs/positioning-narrative.md`。

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
- All user-controlled text (task title / event name / pet name / learn content) MUST flow through `PromptSanitizer.sanitize(_:)` — currently 7 call sites (count drifts; `grep PromptSanitizer.sanitize` for the live number). Wrap user content in XML delimiters declared in the system prompt.

- **Character source of truth**:
  1. `CompanionCharacter` is the **built-in** IP selection: `joy`, `silas`, `nova` (defined in `Models/CompanionCharacter.swift`).
  2. `CompanionStyle` mirrors the three product IPs: `.joy`, `.silas`, `.nova`.
  3. Character drives style through `CompanionCharacter.resolvedStyle`; do not add independent style choices for built-ins.
  4. **Custom companions take precedence**: when `UserProfile.customCompanionId != nil`, prompt assembly uses `OpenAIService.customCompanionPersonaPrompt(_:)` and skips the built-in `characterPrompt`. The active `CustomCompanion` flows through `AIContext.customCompanion` from both `CompanionTextService.generateAIText` and `AppState+Companion.buildCompanionDialogueTriggerState`. The dialogue cache fingerprint versions by custom id + `updatedAt` — any persona field change (voice included) invalidates it (`CustomCompanion.swift`).
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
  - Logic: echo the task name and turn boring work into a small friendly observation. Care nudges (water, breathing, rest) are RARE — client 2026-07-28 removed the habitual add-on; most lines are just a short, funny, or warm reaction.
  - 80/20 mode split: Everyday Companion (about 80%) and Quotable Moment (about 20%, Wilde / Little Prince turn). Joy's Mode B is **generative** — it writes an original line, never attributed and never in quotation marks, so it carries no approved-quote bank.
  - Limit: maximum 25 English words in both modes.
- **Silas**:
  - Core virtue: loving care. Help work feel held, meaningful, and spiritually steady.
  - Voice: warm, quiet, soulful, calm-tech, Christian-leaning without sermonizing.
  - 80/20 mode split: Quiet Presence (about 80%, maximum 15 words) and Quotable Moment (about 20%, maximum 20 words). Mode B is **deterministic**: it reproduces one line from the approved bank verbatim with attribution, never an improvised reference.
  - Mode A carries NO biblical imagery — client 2026-07-28 confined all devotional register to Mode B. Approved sources are currently KJV only; *Streams in the Desert* (1925 Cowman edition) is sanctioned by the client but not yet in the bank because the 1925 wording could not be verified, and inventing a devotional line is worse than a smaller pool.
  - Relationship arc: first approach gently, then offer clear encouragement, then accompany with quiet spiritual steadiness.
- **Nova**:
  - Core virtue: temperance and discipline. Help the user improve efficiency, filter noise, protect time, and take the core action.
  - Voice: cool, sparse, rational, secular, and outcome-focused.
  - 80/20 mode split: Pragmatic Navigation (about 80%, maximum 20 words) and Strategic Insight (about 20%, maximum 25 words including the attribution).
  - Use signal-over-noise framing, one critical path, 80/20 thinking, and rare short quotes only when they sharpen the point.
  - Relationship arc: first observe calmly and say little, then give restrained recognition, then work beside the user as a steady operator.
- **Subservices**:
  - `SmartReminderService` — context-aware reminder triggers.
  - `FocusSessionService` — see Focus Mode section below.
  - (Removed 2026-05-07: `TaskDehydrationService` and `MicroAction` model — "AI 任务拆解" was deleted as off-product-positioning. See CLAUDE.md "Product Identity": tasks are prompt context, not actionable todos to be broken down.)
- **Data flow**: `DayPackGenerator` -> `CompanionTextService` -> `OpenAIService.generateCompanionText` -> `chatCompletion` -> `DayPack { currentPetDialogue, daySummary, firstUp }`（v2.5.0 起旧的 `morningGreeting / dailySummary / companionPhrase` 已收敛为单句宠物对话 + 中性面板文本）-> `HaikuSectionView` / `TimelineView`. Tests go through `PromptDebuggerView` and `CompanionCharacterMappingTests`.

### Home Companion Presentation
- `AppState.refreshHomeCompanionPresentation()` decides between daily haiku or shared pet dialogue.
- First display of a new day shows haiku; subsequent displays fall back to pet dialogue. Do not force update on `onDisappear`.
- Only persist `LocalStorage.lastHomeHaikuShownDate` after async load completes.

### BLE Protocol & Supabase Data
- **E-ink Hardware**: 4-inch/7.3-inch, ESP32-S3. Spectra 6 pixel encoding (4bpp).
- **Frame structure** (`BLEPacketizer.swift:60-98`):
  - Packetized (v2.5.24, ≤65535 chunks): `type(1B) | messageId(2B BE) | seq(2B BE) | totalChunks(2B BE) | chunkLength(2B BE) | chunkCRC(2B BE) | payload`.
  - Simple App→Device: `type(1B) | length(2B BE) | payload`.
  - Simple Device→App: `type(1B) | length(1B) | payload`.
- **App→Device 出站帧类型** (`BLEProtocol.swift` — `BLEDataType` enum): `0x01=petStatus`, `0x02=taskList`, `0x03=schedule`（v2：`ScheduleV2Codec`，日期头 + Time/Title/Description/Category/EndTime/SupportText；跨午夜按日切开或不发；空描述填 `Details forthcoming.`，见协商项 H4）, `0x04=weather`, `0x05=time`, `0x10=dayPack`, `0x11=taskInPage`, `0x12=deviceMode`（**不得**用来进入、退出或裁决专注）, `0x13=smartReminder`, `0x14=focusStatus`（v2：`SubVersion 0x02` + Revision + SessionId + FocusState + Phase + Bottles + ElapsedSeconds + TaskTitle + SegmentSeconds；收到匹配 `RESULT/COMMITTED` 前冻结）, `0x15=customAvatarFrame`（v2.7 自定义头像暂存，SubVersion 0x04 + KRI）, `0x16=screensaver`（屏保金句/明信片业务帧）, `0x17=sceneUnlock`（场景解锁业务帧）, `0x18=otaReboot`（触发固件升级重启，零 payload）, `0x19=wifiDebugMode`（开启/关闭/查询 SoftAP，设备用同 type 实时应答）, `0x1A=wifiAvatarSession`（SoftAP 头像快传会话握手，双向回显 command+OpID）, `0x1B=taskListSnapshotAck`（设备任务操作业务确认 + Overview 任务全量快照）, `0x1C=shippingMode`（工厂运输模式开启命令，无业务 ACK，以设备主动断连确认生效）, `0x20=eventLogRequest`, `0x22=avatarControl`（头像 commit/erase/query/abort，双向实时帧）, `0x25=offlineSync`（QUERY/STATE/OP_BATCH/OP_ACK、`FOCUS_STATE 0x83`、`FOCUS_RESOLVE 0x06` 33B、等 `RESULT 0x81/COMMITTED`、可选 BEGIN→TaskList→DayPack→Schedule→COMMIT，双向）, `0x7E=secureData`, `0x7F=securityHandshake`. 注：`0x21 eventLogBatch` 虽然挂在 `BLEDataType` enum 里（命名空间归类），实际方向是 Device→App 入站，参见入站事件清单。
- **Device→App 入站事件关键字节** (`EventLog.swift` — `EventLogType.rawByte`): `0x10=enterTaskIn` / `0x11=completeTask` / `0x12=skipTask`（只收 v2：`0x02 | OpID | SessionId(8) | TaskId | Ts`，Complete/Skip 再加 ElapsedSeconds；旧 payload 拒绝）; `0x19=wifiDebugMode`（实时返回 `Enabled+StatusCode`，不进入 `0x21` 批次）; `0x21=eventLogBatch`（设备批量回传事件，`BLEEventHandler` 入站分支，高水位去重）; `0x25=offlineSync`（STATE / FOCUS_STATE / OP_BATCH / RESULT 实时事务帧，路由早于 `0x21`，不进 Event Log；App 侧由 `BLEOfflineSyncCoordinator` 处理。`RESULT 0x81` 同时确认 BEGIN/COMMIT/ABORT 与 `FOCUS_RESOLVE`：后者 `SyncId=ResolveID`，只有 `COMMITTED` 才解锁）; `0x30=deviceWake`（payload[0] = battery level 0-100，v2.3.0+；v2.5.19+ 追加固件版本 3B，更新 `BLEService.deviceBatteryLevel`；收到后立刻冻 `0x14`）; `0x31=deviceSleep`; `0x40=lowBattery`（payload 含电量字节，同样更新 `BLEService.deviceBatteryLevel`）.
- **Security Mode** (`BLEService.swift` — `configuredSecurityMode` / `securityMode` / `requiresSecureChannel`): `AppSecrets.bleSharedSecret` empty → development (unsigned). Non-empty → secure (HMAC-SHA256 envelope: 16B header + 32B signature). Ordinary payloads use one envelope; the v2.7 custom-avatar transfer is packetized with the existing 11-byte chunk header first, then every complete chunk is placed in its own envelope with an independent timestamp, nonce, and HMAC.
- **Defenses**:
  - `BLEWriteGate` (`BLEWriteGate.swift:8-29`) — actor-serialized writes.
  - `BLERateLimiter` (`BLERateLimiter.swift:12-28`) — 20 writes/sec; refresh ≥ 2s interval.
  - Timeouts: write 5s (`BLEService.swift:545`) / scan 10s default (`BLEService.swift:281` `scanForDevices(timeout:)` 默认参数) / connect 15s 硬编码 (`BLEService.swift:262` `Task.sleep(for: .seconds(15))`) / handshake 5s (`BLEService.swift:585`).
  - `BLEDeviceIdentityStore` (`BLEDeviceIdentityStore.swift:17-35`) — trust/block lists in UserDefaults; enforced in secure mode at `BLEService.swift:229-234` (scan filter) and `:715-720` (post-connect gate).
- **Sync**: `BLESyncCoordinator` (background sync via `com.kirole.app.ble.sync`); wake-triggered `0x25` goes through `BLEOfflineSyncCoordinator` + `BLEOfflineOperationProcessor`. Reconnect order: freeze `0x14` → STATE → `FOCUS_STATE` → `OP_BATCH` → `OP_ACK` → `FOCUS_RESOLVE` → `RESULT/COMMITTED` → 普通 `0x11` / `0x14` / `0x10` / `0x03`. 活动专注期间禁止 dataset `COMMIT`（`NeedsFullSync` 也延后到退出专注）. 仅 `OperationOverflow` 时 ACK 后不 BEGIN；两旗同在且已 idle 才做完整核对 COMMIT. OfflineSync 同批固定先 DayPack 再 Schedule。
- **Supabase**: Keys injected via `AppSecrets.configure(...)` using build-time constants (`Config/Secrets.xcconfig`). Keep RLS enabled and sync schema changes with `Config/supabase-schema.sql`. Current schema source is aligned with the post-IP/post-streak code path: no legacy pet-form column and no old streak table.

### Focus Mode State Machine
- **Source**: `FocusSessionService.swift` + `FocusSessionService+Reconnect.swift` / `+Statistics.swift`, `FocusReconnectArbiter.swift`, `FocusReconnectProtocol.swift`, `FocusSession.swift`, `DisplayScene.swift`.
- **`FocusSessionService` properties**: 
  - `focusEnforcementMode`: Persistent Focus Enforcement mode (moved from `AppState` in Wave 3 refactor, 2026-05-08). Loaded via `loadFocusEnforcementMode()` at init; persisted via `setFocusEnforcementMode(_:)`. `AppState.focusEnforcementMode` is now a computed forwarding property.
  - `isFocusStatusPushFrozen` / `lastAppliedFocusRevision` / `suppressVisibleFocusStart` live in `FocusReconnectFlagStore` (DeviceWake 起到 `RESULT/COMMITTED` 后解冻).
- **`FocusSession` fields**: Immutable `id`, `taskId`, `taskTitle`, `startTime`. Mutable: `endTime`, `endReason`, `calculatedFocusTime`, `screenUnlockEvents`, `mode`, `protectionState`, `interruptionSource`, `earnedEnergyBottles`, plus 1.3.0 identity `focusSessionId`, `focusRevision`, `deviceId`, `bootSessionId`, `startSource`, `lastOperationId`.
- **End reasons** (7): `completed`, `skipped`, `timeout`, `disconnected`, `interrupted`, `permissionDenied`, `recoveredOnLaunch`. BLE 断连**不再**走 `disconnected` 结束会话；`handleDeviceDisconnected()` 是空操作，挡板保持。
- **Modes** (2): `standard`, `deepFocus`. **Protection states** (3): `unprotected`, `protected`, `fallback`.
- **Reconnect arbitration** (`FocusReconnectArbiter.decide`，对接说明 §9)：只认 `FocusSessionId`（`BootSessionId + StartOperationID`），不用 `taskId` 兜底。结束优先；离线新进入则 adopt；历史结算不闪 UI；不同会话 `replaceWithDevice` + `conflictResolved`。`StartSource=appEstablished` 用 App start，`deviceOffline` 用设备 start；elapsed 差 >120s 只记日志，不新建会话。同一 `FocusSessionId` 重试复用 `ResolveID`。
- **Unknown live EnterTaskIn**: send `0x14 idle`（专注通道），never `0x12`.

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
| Focus interrupted (phone / Screen Time) | `FocusInterruptionDetector` → `FSS` | session stays active; segment resets | `0x14` push unless `isFocusStatusPushFrozen` |
| **Scene unlock celebration** | `celebrateSceneUnlock` (`+HardwareDisplay:177`) | `pendingSceneCelebration = SceneCelebration(sceneId, now)` | `SoundService.playWithHaptic(.sceneMilestone, .success)`; `SceneUnlockBanner` 3s; confetti via `ContentView:141 onChange`; auto-clear |
| BLE connect | `BLEService.didConnect` (`BLE:739`) | `connectionState=.connected` (in BLEService, not AppState) | SettingsBLESection observes BLEService directly |
| BLE disconnect | `BLEService.disconnect` / `didDisconnect` → `FSS.handleDeviceDisconnected`（空操作） | 会话与挡板保持 | 冻 `0x14`，等重连 `FOCUS_RESOLVE` 后再恢复普通心跳 |
| DeviceWake / OfflineSync | `BLESyncCoordinator.performDeviceWakeSync` → `BLEOfflineSyncCoordinator.synchronize` | 可能 adopt / end / settleHistorical | `RESULT/COMMITTED` 后解冻；补 `0x11`+`0x14`；未 COMMIT 时再发普通 DayPack/Schedule |
| EnterTaskIn 找不到任务 | `BLEEventHandler.handleEnterTaskIn` | 不改会话（已有 active 则不动） | `0x14 idle`，不用 `0x12` |
| Sync complete (Google) | `syncGoogleData` (`+Sync:64`) | `events`, `tasks` (merge), `lastGoogleSyncDebug` | `updatePetState` → `refreshSharedPetDialogueIfNeeded` → `refreshHomeCompanionPresentation` |
| Sync complete (Apple) | `syncAppleData` (`+Sync:175`) | same subset | same path as Google |
| Sync complete (Notion / Taskade / Microsoft / Todoist / TickTick) | `syncNotionData` / `syncTaskadeData` / `syncMicrosoftData` / `syncTodoistData` / `syncTickTickData` in `+Sync` | basic fields only | same path as Google (via shared `applyPostSyncHooks()`; line numbers drift — grep the function name) |

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
OPENROUTER_API_KEY = ...
```
Full commented reference (incl. optional provider `*_OAUTH_CLIENT_ID` / `*_OAUTH_ENABLED` gate pairs for Notion / Taskade / Microsoft / Todoist / TickTick): `Config/Secrets.xcconfig.template`.

## 8. Development Workflow
1. Read `.cursor/rules/` for domain-specific rules. BLE / focus reconnect changes start from the 1.3.1 docs listed in §2, not from memory or old flowcharts.
2. Develop in `KirolePackage/Sources/KiroleFeature/`.
3. Verify via tests, strict concurrency check, and regression coverage (`HomeCompanionPresentationTests`, `PromptDebuggerView`). After wire or reconnect edits run `FocusReconnect*`, `BLEOfflineSyncCoordinatorTests`, `ScheduleV2CodecTests`, and `BLEProtocolSimulationTests`.
4. Follow secret config logic (via build-generated constants, not info.plist). Local dev uses `.env` logic. 
5. **Always rebuild and open the simulator after modifying frontend/UI code to verify the changes** (每次修改完前端/UI代码后，必须使用相应命令重新构建并打开模拟器进行验证).

## 9. Interaction Rules (CRITICAL)
- **Addressing**: Always address the user as **B哥** at the start of every response.
- **Language**: All responses must be in **Chinese** (Simplified). When the user sounds non-technical, prefer plain Chinese, explain jargon immediately.
- **Workspace Boundary (STRICT)**:
  - All commands MUST execute within the current workspace root (`/Users/demon/vibecoding/outku3`). NEVER reference outside directories.
  - Ignore open files from other projects.
  - Unspecified actions ("commit", "build") ALWAYS refer to **this workspace**. Ask explicitly if outside access is needed.
