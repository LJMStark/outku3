# Kirole - Product Specification

## Overview

**Kirole** is an iOS companion app for an E-ink hardware device — a focus companion for deep knowledge workers. Through AI-driven task dehydration, attention mirroring, and smart reminders, paired with a pixel pet companion, Kirole helps users transform complex intentions into executable micro-actions.

### Vision
**Unlock the Flow, Make it Happen.** Help users who rely on many productivity tools but struggle with execution — by breaking tasks into clear next steps, reflecting focus patterns, and providing context-aware nudges through both the app and an E-ink companion device.

### Target Users
- Deep knowledge workers who use multiple productivity tools but struggle with execution
- Remote workers and freelancers needing focus management
- Users who want a low-distraction companion device on their desk
- Two user paths: **App + Hardware** (E-ink device) and **App-only**

---

## Core Features

### 1. Home Page - Timeline View

#### 1.1 Header Section
- Current date display
- Time with timezone indicator (e.g., "GMT")
- Weather information (atmosphere feature, not core functionality)
- Navigation icons: Home, Pet (Kirole), Settings

#### 1.2 Timeline
- **Default View**: Today's tasks and events
- **Navigation**: Horizontal swipe to view upcoming days
- **Visual Markers**: Sunrise/sunset indicators on timeline
- **Time Scale**: Vertical timeline with hour markers

#### 1.3 Event Cards
- Event title and duration
- Source indicator (Google Calendar, Apple Reminders, etc.)
- Participant avatars (if applicable)
- Brief description preview
- Tap to expand for full details

#### 1.4 Haiku Feature
- AI-generated haiku poetry (via OpenAI API)
- Dynamically generated based on:
  - Current tasks and mood
  - Time of day
  - User's activity patterns
- Displayed with pet illustration

#### 1.5 Pet Display
- Pet appears on home screen with idle animations
- Reacts to task completion with celebratory animations
- Shows current mood/status visually

---

### 2. Pet Page - Task Management

#### 2.1 Task Categories
- **Today**: Tasks due today
- **Upcoming**: Future tasks
- **No Due Dates**: Tasks without deadlines

#### 2.2 Task Display
- Task title
- Source indicator (synced from external services)
- Completion checkbox
- Visual feedback on completion (pet reaction)

#### 2.3 Pet Illustration
- Large pet display with animations
- Responds to user interactions (light nurturing)
- Shows current mood/state visually

---

### 3. Pet Status Page

#### 3.1 Pet Identity
- Name: Kirole (same as product)
- Adventures count (completed tasks)

#### 3.2 Growth Metrics
- **Age**: Days since creation
- **Status**: Current mood/health state
- **Stage**: Evolution stage name
- **Progress Bar**: Progress to next evolution

#### 3.3 Physical Stats (Fun Metrics)
- Weight
- Height
- Tail Length
- (These grow with pet evolution)

#### 3.4 Streak System
- Current streak counter (consecutive days)
- Visual streak indicator
- Streak affects pet growth rate

#### 3.5 Task Statistics
- Today's completed tasks
- Past week summary
- Last 30 days overview

---

### 4. Settings Page

#### 4.1 Widget Preview
- Live preview of iOS home screen widget
- Multiple widget styles available

#### 4.2 Theme Selection
- Fixed theme collection (3-5 carefully designed themes)
- Each theme includes:
  - Color palette
  - UI element styling
  - Consistent visual language

#### 4.3 Pet Customization
- Unified pet form (Kirole) — single design, not multiple presets
- User can upload a custom photo
- Pet displays 5 mood states visually

#### 4.4 Third-Party Integrations
- **Apple Ecosystem**:
  - Apple Calendar (EventKit)
  - Apple Reminders (EventKit)
- **Google Services**:
  - Google Calendar API
  - Google Tasks API
- **Other Services**:
  - Todoist
  - Additional integrations as needed

---

## Pet System Design

### Unified Form
**Single pet form** named Kirole with 5 mood states:
- Happy (default)
- Excited (consecutive task completions)
- Focused (during Task In / focus sessions)
- Sleepy (nighttime)
- Missing You (prolonged absence)

### Growth Logic
**Comprehensive Scoring System**:
- Multi-dimensional weighted calculation
- Factors include:
  - Task completion rate
  - Streak maintenance
  - Focus time
  - Consistency across days

### Interaction Model
**Light Nurturing**:
- Simple feed/pet animations
- Builds emotional connection
- Does NOT affect growth (reduces user burden)
- Growth tied only to task completion

### Absence Handling
**Gentle Reminder**:
- Pet expression changes when user is absent
- Push notifications with encouraging messages
- NO progress penalty
- NO stat degradation
- Encouragement over pressure

---

## Hardware Integration

### Device Type
Kirole E-ink companion device — a desk-mounted focus display.
- **Sizes:** 4-inch (400x600) and 7.3-inch (800x480)
- **Display:** E Ink Spectra 6, 4bpp, 6 colors (Black, White, Yellow, Red, Blue, Green)
- **SoC:** ESP32-S3, BLE 5.0
- **Interaction:** Power button + Encoder knob (rotary + press)
- **Battery:** 30+ days standby

### Communication
**Hybrid Mode**:
- Primary: Bluetooth Low Energy (BLE) direct connection
- Secondary: Cloud sync via Supabase
- BLE sync policy: hourly 08:00–23:00, every 4h overnight
- Protocol details: see `docs/BLE通信协议规格文档.md`

### Hardware Display Pages
4 pages on E-ink device (via DayPack):
1. **Start of Day** — Morning greeting, daily summary, first item, weather
2. **Overview** — Mixed timeline (tasks + events), companion phrase, micro-actions
3. **Task In** — Task detail with What/Why micro-actions, encouragement, focus challenge
4. **Settlement** — Daily stats, focus metrics, streak, points

### Smart Reminders on Device
- AI-driven context-aware reminders pushed via BLE (0x13 command)
- 3 types: Gentle, Urgent, Streak Protect
- Banner overlay on current page, auto-dismiss after 10s

---

## Technical Architecture

### Platform
- **Device**: iPhone only (iOS)
- **Framework**: SwiftUI primary
- **Minimum iOS**: Latest stable version

### Data Layer

#### Local Storage
- SwiftData or raw JSON persistence (NO CoreData)
- Offline-first architecture

#### Cloud Sync
- **CloudKit**: User data sync across devices
- **Supabase**:
  - User authentication
  - Analytics and insights
  - Hardware cloud sync relay

### External APIs

#### Calendar/Task Integration
- EventKit (Apple Calendar & Reminders)
- Google Calendar API
- Google Tasks API
- OAuth 2.0 authentication flow

#### AI Services
- **CompanionTextService**: Personalized greetings, summaries, encouragement (4 styles: encouraging/strict/playful/calm)
- **TaskDehydrationService**: AI task decomposition into What/When/Why micro-actions
- **SmartReminderService**: Context-aware reminders (deadline/streakProtect/idle/gentleNudge)
- **BehaviorAnalyzer**: User behavior summary for prompt injection
- **OpenAI API** (GPT-4o-mini): Backend for companion text and task dehydration
- Haiku generation (part of CompanionTextService)

#### Location Services
- Sunrise/sunset calculation
- Weather data (atmosphere feature)
- Minimal permissions, atmosphere only

### Bluetooth
- CoreBluetooth framework
- BLE standard protocol
- Background data sync support

---

## User Experience

### Onboarding
**Story Introduction**:
- Narrative-driven introduction
- Pet backstory and personality
- Emotional connection before functionality
- Minimal steps to start using

### Notifications
- Hardware-focused push strategy
- Notifications primarily sent to E-ink device via BLE SmartReminder
- App-side notifications for App-only users

### Audio
**Subtle Sound Effects**:
- Key interactions have gentle audio feedback
- Task completion sounds
- Pet evolution celebration
- All sounds can be disabled

### Animations
**Fully Polished**:
- Every interaction has carefully designed animation
- Pet has rich idle and reaction animations
- Smooth transitions throughout app
- Brings the pet to life

---

## Widgets

### Strategy
**Diversified Widgets**:
- Multiple sizes (small, medium, large)
- Multiple styles:
  - Task-focused widget
  - Pet status widget
  - Combined overview widget
- User chooses based on preference

### Content
- Upcoming tasks
- Pet status/mood
- Streak counter
- Quick glance information

---

## Localization

### Language Support
- English only (MVP)
- UI text in English
- Error messages in English

---

## Privacy & Data

### Approach
**Smart Optimization**:
- Data used for personalization
- AI feature optimization
- Clear privacy policy
- User consent for data usage

### Permissions Required
- Calendar access (read)
- Reminders access (read)
- Bluetooth
- Location (optional, for atmosphere)
- Notifications

---

## Visual Design

### Style
**Fully Custom**:
- Complete replication of prototype design
- No reliance on system components
- Unique visual identity

### Pet Assets
**Pixel Art Style**:
- Unified pet form (Kirole)
- 5 mood state variations
- Placeholder-ready for future replacement

### Themes
- 3-5 fixed, carefully designed themes
- Each theme is complete and polished
- No user customization beyond selection

---

## MVP Scope

### Included
1. Home page with timeline view
2. Pet page with task management
3. Pet status page with stats
4. Settings page with integrations
5. Apple Calendar/Reminders sync
6. Google Calendar/Tasks sync
7. CloudKit data sync
8. Pet mood states and growth system
9. AI companion text (CompanionTextService)
10. AI task dehydration (TaskDehydrationService)
11. Smart reminders (SmartReminderService)
12. Focus session tracking (FocusSessionService)
13. iOS widgets (multiple styles)
14. BLE hardware communication (DayPack, TaskInPage, SmartReminder)
15. Supabase backend integration
16. Story-driven onboarding (see ONBOARDING-SPEC.md)
17. Full animations and sound effects

### Excluded from MVP
- Subscription/payment features
- Multi-language support
- iPad support
- Apple Watch app
- Deep nurturing mechanics

---

## File Structure

See `CLAUDE.md` for the actual workspace + SPM package structure. Key layout:

```
outku3/
├── Kirole.xcworkspace/          # Open this in Xcode
├── Kirole/                      # App shell (entry point only)
│   └── KiroleApp.swift
├── KirolePackage/               # ALL development happens here
│   ├── Package.swift
│   └── Sources/KiroleFeature/
│       ├── ContentView.swift
│       ├── State/AppState.swift
│       ├── Models/
│       ├── Design/Theme.swift
│       ├── Core/               # Services
│       └── Views/
│           ├── Home/, Pet/, Settings/, Components/
│           └── Onboarding/
├── Config/                      # xcconfig + entitlements
└── docs/                        # Hardware specs, BLE protocol
```

---

## Design References

### Prototype Images
1. **Image 1 & 2**: Home page - Timeline with events, haiku, pet
2. **Image 3**: Pet page - Task categories with pet illustration
3. **Image 4**: Pet status - Stats, streak, task statistics
4. **Image 5**: Settings - Widget preview, themes, integrations

### Hardware Documentation
- `docs/硬件需求文档-Hardware-Requirements-Document.md` (v0.3) — Hardware electrical requirements
- `docs/固件功能规格文档.md` (v1.3.0) — Firmware feature spec (pages, interaction, pet system)
- `docs/BLE通信协议规格文档.md` (v1.3.1) — BLE protocol (commands, data structures, events)

---

## Success Metrics

### User Engagement
- Daily active usage
- Task completion rate
- Streak maintenance
- Pet evolution progress

### Technical
- Sync reliability
- BLE connection stability
- App performance and responsiveness

---

## Open Questions

1. Final pet pixel art assets (unified form, 5 mood states)
2. Custom photo upload implementation details (crop, format, size limits)
3. App-only user experience without hardware (which features are gated?)

---

*Document Version: 2.0*
*Last Updated: 2026-02-15*
