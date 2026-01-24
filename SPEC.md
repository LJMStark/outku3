# Outku - Product Specification

## Overview

**Outku** is an iOS companion app for an E-ink hardware device, designed to help remote workers build better habits through AI-powered pet companionship and gamified task management.

### Vision
Transform mundane task completion into a delightful journey of nurturing a virtual pet companion, creating emotional connections that motivate users to maintain productive habits.

### Target Users
Remote workers seeking to establish healthy routines through AI pet companionship and habit gamification.

---

## Core Features

### 1. Home Page - Timeline View

#### 1.1 Header Section
- Current date display
- Time with timezone indicator (e.g., "GMT")
- Weather information (atmosphere feature, not core functionality)
- Navigation icons: Home, Pet (Tiko), Settings

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
- Shows current evolutionary form

---

### 3. Pet Status Page

#### 3.1 Pet Identity
- Name (user-customizable, e.g., "Baby Waffle")
- Pronouns selection
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

#### 4.3 Avatar/Pet Customization
- Preset pet designs (pixel art style)
- User can upload custom images
- Hybrid mode: presets + custom uploads

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

### Evolution System
**Branch Evolution** (Pokémon-style):
- Multiple evolution paths based on user behavior
- Different forms unlock based on:
  - Task completion patterns
  - Streak consistency
  - Focus time distribution
  - Activity types

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
E-ink daily schedule display (similar to Inku)

### Communication
**Hybrid Mode**:
- Primary: Bluetooth Low Energy (BLE) direct connection
- Secondary: Cloud sync via Supabase
- Ensures reliability across scenarios

### Hardware Display Content
- Task list and schedule
- Pet display (static or simplified animation for E-ink)
- Time and date
- Weather information

### Development Approach
**Synchronized Development**:
- App and hardware integration developed in parallel
- Ensures seamless experience from launch

---

## Technical Architecture

### Platform
- **Device**: iPhone only (iOS)
- **Framework**: SwiftUI primary
- **Minimum iOS**: Latest stable version

### Data Layer

#### Local Storage
- Core Data or SwiftData for local persistence
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
- OpenAI API for haiku generation
- Context-aware content generation

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
- Notifications primarily sent to E-ink device
- Reference: Inku implementation approach

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
- Initial assets created during development
- Placeholder-ready for future replacement
- Multiple evolution forms needed

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
8. Pet growth and evolution system
9. AI haiku generation
10. iOS widgets (multiple styles)
11. BLE hardware communication
12. Supabase backend integration
13. Story-driven onboarding
14. Full animations and sound effects

### Excluded from MVP
- Subscription/payment features
- Multi-language support
- iPad support
- Apple Watch app
- Deep nurturing mechanics

---

## File Structure (Proposed)

```
Outku/
├── App/
│   ├── OutkuApp.swift
│   └── AppDelegate.swift
├── Features/
│   ├── Home/
│   │   ├── HomeView.swift
│   │   ├── TimelineView.swift
│   │   ├── EventCardView.swift
│   │   └── HaikuView.swift
│   ├── Pet/
│   │   ├── PetPageView.swift
│   │   ├── TaskListView.swift
│   │   └── PetDisplayView.swift
│   ├── PetStatus/
│   │   ├── PetStatusView.swift
│   │   ├── StatsView.swift
│   │   └── StreakView.swift
│   ├── Settings/
│   │   ├── SettingsView.swift
│   │   ├── ThemePickerView.swift
│   │   └── IntegrationsView.swift
│   └── Onboarding/
│       ├── OnboardingView.swift
│       └── StoryView.swift
├── Core/
│   ├── Models/
│   ├── Services/
│   │   ├── CalendarService.swift
│   │   ├── CloudKitService.swift
│   │   ├── SupabaseService.swift
│   │   ├── BluetoothService.swift
│   │   └── OpenAIService.swift
│   ├── Utilities/
│   └── Extensions/
├── Design/
│   ├── Theme/
│   ├── Components/
│   └── Animations/
├── Resources/
│   ├── Assets.xcassets
│   ├── Sounds/
│   └── Localizable.strings
└── Widget/
    └── OutkuWidget/
```

---

## Design References

### Prototype Images
1. **Image 1 & 2**: Home page - Timeline with events, haiku, pet
2. **Image 3**: Pet page - Task categories with pet illustration
3. **Image 4**: Pet status - Stats, streak, task statistics
4. **Image 5**: Settings - Widget preview, themes, integrations

### Functional Reference
- Inku: Daily Schedule Planner (hardware integration approach)

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

1. Specific BLE protocol details (pending hardware team documentation)
2. Final pet evolution tree design
3. Exact theme color palettes
4. Haiku generation prompt engineering
5. E-ink display resolution and constraints

---

*Document Version: 1.0*
*Last Updated: 2026-01-24*
