# Kiro Hardware Product Specification

**Version:** v1.1.0
**Last Updated:** 2026-01-31
**Status:** Draft
**Reference Product:** Inku Daily Schedule Planner

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Hardware Specifications](#2-hardware-specifications)
3. [Display Page Design](#3-display-page-design)
4. [Interaction Flow](#4-interaction-flow)
5. [Pet System](#5-pet-system)
6. [Data Synchronization](#6-data-synchronization)
7. [4-inch vs 7-inch Differences](#7-4-inch-vs-7-inch-differences)
8. [Firmware Development Guide](#8-firmware-development-guide)

---

## 1. Product Overview

### 1.1 Product Positioning

Kiro is a habit-building companion device designed for remote workers. Through AI-powered pixel pet companionship and gamified task management, it helps users establish healthy work habits.

### 1.2 Core Features

| Feature | Description |
|---------|-------------|
| Task Display | Shows today's task list with completion marking |
| Pet Companion | Pixel-style virtual pet that grows with task completion |
| Schedule Reminder | Displays calendar events and time schedules |
| Daily Settlement | Summarizes daily completion stats and point rewards |

### 1.3 Product Form Factor

- **Device Type:** Display-focused E-ink device
- **Size Options:** 4-inch / 7-inch variants
- **Interaction:** Power button + Scroll wheel + BLE connection to iOS App
- **Power:** Built-in battery + USB-C charging

### 1.4 Target Users

- Remote workers
- Freelancers
- Users seeking habit formation
- Pixel art / virtual pet enthusiasts

---

## 2. Hardware Specifications

### 2.1 Display Specifications

#### 4-inch Display

| Parameter | Specification |
|-----------|---------------|
| Resolution | 400 × 300 pixels |
| Pixel Density | ~125 PPI |
| Display Technology | E-ink Electronic Paper |
| Grayscale Levels | 16 levels |
| Refresh Time | Full refresh ~1.5s, Partial refresh ~0.3s |
| Viewing Angle | 180° |

#### 7-inch Display

| Parameter | Specification |
|-----------|---------------|
| Resolution | 800 × 480 pixels |
| Pixel Density | ~133 PPI |
| Display Technology | E-ink Electronic Paper |
| Grayscale Levels | 16 levels |
| Refresh Time | Full refresh ~2s, Partial refresh ~0.5s |
| Viewing Angle | 180° |

### 2.2 Button Specifications

#### Power Button

| Parameter | Specification |
|-----------|---------------|
| Button Count | 1 physical button |
| Button Type | Tactile switch |
| Button Position | Device side (hardware team decides) |
| Function | Power on/off, enter screensaver |
| Actuation Force | 150-200gf |
| Lifespan | ≥100,000 presses |

#### Scroll Wheel Button

| Parameter | Specification |
|-----------|---------------|
| Button Count | 1 scroll wheel button |
| Button Type | Stepless scroll wheel + press confirm |
| Button Position | Bottom of screen |
| Scroll Function | Scroll to select list items |
| Press Function | Confirm selection / Complete task |
| Sensitivity | Dynamic adjustment (based on scroll speed) |
| Selection Feedback | Inverted display (white text on black) |
| Refresh Mode | Partial refresh (fast response) |
| Lifespan | ≥100,000 presses |

### 2.3 BLE Module

| Parameter | Specification |
|-----------|---------------|
| Bluetooth Version | BLE 5.0 |
| Transmission Range | ≥10m (open environment) |
| Service UUID | `0000FFE0-0000-1000-8000-00805F9B34FB` |
| Write Characteristic UUID | `0000FFE1-0000-1000-8000-00805F9B34FB` |
| Notify Characteristic UUID | `0000FFE2-0000-1000-8000-00805F9B34FB` |

### 2.4 Power Management

| Parameter | 4-inch Spec | 7-inch Spec |
|-----------|-------------|-------------|
| Battery Capacity | 500mAh | 1000mAh |
| Standby Time | ~30 days | ~20 days |
| Active Use | ~7 days | ~5 days |
| Charging Port | USB-C | USB-C |
| Charging Time | ~1.5 hours | ~2.5 hours |

### 2.5 Other Specifications

| Parameter | 4-inch Spec | 7-inch Spec |
|-----------|-------------|-------------|
| Shell Material | ABS + PC | ABS + PC |
| Dimensions (mm) | 95 × 75 × 8 | 175 × 115 × 10 |
| Weight | ~60g | ~150g |
| Operating Temp | 0°C ~ 40°C | 0°C ~ 40°C |
| Storage Temp | -20°C ~ 60°C | -20°C ~ 60°C |

---

## 3. Display Page Design

The device has 4 main pages, switching automatically based on time of day or through user interaction.

### 3.1 Page 1: Start of Day

**Display Timing:** Default page on power on

**Page Content:**

```
┌─────────────────────────────────┐
│                                 │
│     [Pet Pixel Art - Morning]   │
│                                 │
│   "Good morning! Ready for      │
│    a great day?"                │
│                                 │
│   ─────────────────────────     │
│                                 │
│   3 tasks, 2 events today.      │
│                                 │
│   Next: 09:00 Team standup      │
│                                 │
│   [Weather Icon] 22°C Partly    │
│                  Cloudy         │
└─────────────────────────────────┘
```

**Trigger:** Default display on power on
**Exit:** Any button press → Overview

**Data Fields:**

| Field | Max Length | Description |
|-------|------------|-------------|
| morningGreeting | 50 chars | Morning greeting message |
| dailySummary | 60 chars | Today's overview (task/event count) |
| firstItem | 40 chars | First item preview (next event or task) |
| weather | - | Weather information (from App) |

### 3.2 Page 2: Overview (Mixed Timeline)

**Display Timing:** Enter from Start of Day by pressing any button

**Page Content:**

```
┌─────────────────────────────────┐
│  [Pet Pixel Art]  Next: 14:00   │
│                   Product Review│
│                                 │
│  ─────────────────────────────  │
│                                 │
│  Mixed Timeline                 │
│                                 │
│  09:00 Team standup (event)     │
│  ▶ Review project proposal      │
│  10:30 Client call (event)      │
│  ○ Send weekly report           │
│                                 │
│  ─────────────────────────────  │
│                                 │
│  "Keep going, you're doing      │
│   great!"                       │
│                                 │
│  [Scroll to select / Press to   │
│   confirm]                      │
└─────────────────────────────────┘
```

**Sorting Rules:**
- Events: Sorted by time, display only (not interactive)
- Tasks: Sorted by priority, can select to enter Task In

**Display Count:** Adjusted based on screen size (4-inch/7-inch differ)
**Empty State:** Show "No tasks today" message

**Interaction:**
- Scroll wheel: Select item (inverted highlight)
- Press wheel (task): Enter Task In
- Press wheel (event): Show event detail (auto-timeout return)

**Data Fields:**

| Field | Max Length | Description |
|-------|------------|-------------|
| currentScheduleSummary | 30 chars | Current/next schedule |
| mixedTimeline | Dynamic | Events + Tasks mixed list |
| companionPhrase | 40 chars | Companion message |

### 3.3 Page 3: Task In

**Display Timing:** Enter from Overview by selecting a task

**Page Content:**

```
┌─────────────────────────────────┐
│                                 │
│     [Pet Pixel Art - Focused]   │
│                                 │
│  ─────────────────────────────  │
│                                 │
│  Current Task                   │
│                                 │
│  "Review project proposal"      │
│                                 │
│  Description: Check all items   │
│  and provide feedback           │
│                                 │
│  Estimated: 30 min              │
│                                 │
│  ─────────────────────────────  │
│                                 │
│  "You can do this! Focus and    │
│   conquer!"                     │
│                                 │
│  [Press wheel: Mark complete]   │
└─────────────────────────────────┘
```

**Trigger:** Select task from Overview
**Interaction:**
- Short press wheel: Mark complete → Auto return to Overview
- Long press wheel (>1s): Skip task → Return to Overview

**Event Sync:**
- On enter task: Send `EnterTaskIn` event (with timestamp)
- On complete task: Send `CompleteTask` event (with timestamp)
- On skip task: Send `SkipTask` event (with timestamp)

**Data Fields:**

| Field | Max Length | Description |
|-------|------------|-------------|
| taskTitle | 40 chars | Task title |
| taskDescription | 100 chars | Task description (optional) |
| estimatedDuration | 10 chars | Estimated duration (optional) |
| encouragement | 50 chars | Encouragement message |

### 3.4 Page 4: Settlement

**Display Timing:** Auto-display when all tasks completed

**Page Content:**

```
┌─────────────────────────────────┐
│                                 │
│     [Pet Pixel Art - Happy]     │
│                                 │
│  ─────────────────────────────  │
│                                 │
│  Today's Summary                │
│                                 │
│  Tasks: 3/5 completed           │
│  Points: +50                    │
│  Streak: 7 days                 │
│                                 │
│  ─────────────────────────────  │
│                                 │
│  "Great progress today!"        │
│                                 │
│  "See you tomorrow!"            │
│                                 │
└─────────────────────────────────┘
```

**Trigger:** Auto-display when all tasks completed
**Exit:** Any button press → Stay on Overview

**Data Fields:**

| Field | Description |
|-------|-------------|
| tasksCompleted | Completed task count |
| tasksTotal | Total task count |
| pointsEarned | Points earned |
| streakDays | Consecutive days |
| summaryMessage | Summary text (50 chars) |
| encouragementMessage | Encouragement text (50 chars) |

---

### 3.5 Screensaver Mode

**Trigger:** Press power button
**Content:** Static pet image (desktop decoration)
**BLE:** Disconnected (power saving)
**Exit:** Press power button again → Start of Day

---

## 4. Interaction Flow

### 4.1 Page Switching Methods (3 Types)

| Trigger | Description | Target Page |
|---------|-------------|-------------|
| Schedule Trigger | Firmware wake + App pushes new data | Overview |
| Button Trigger | Scroll wheel select task → Press to enter | Task In |
| Screensaver Trigger | Press power button for static screensaver | Screensaver (pet image) |

### 4.2 Scroll Wheel Interaction

#### Overview Page

| Action | Response |
|--------|----------|
| Scroll wheel | Select item (inverted highlight), local processing only |
| Press wheel (task) | Enter Task In page |
| Press wheel (event) | Show event detail (auto-timeout return) |

#### Task In Page

| Action | Response |
|--------|----------|
| Short press wheel | Mark task complete, send CompleteTask event, return to Overview |
| Long press wheel (>1s) | Skip task, send SkipTask event, return to Overview |

#### Settlement Page

| Action | Response |
|--------|----------|
| Any button press | Return to Overview |

### 4.3 Power Button Interaction

| Current State | Action | Response |
|---------------|--------|----------|
| Any page | Press power | Enter screensaver mode |
| Screensaver | Press power | Return to Start of Day |
| Power off | Press power | Power on, show Start of Day |

### 4.4 State Machine

```
┌─────────────┐
│ First Pair  │ ← New device
└──────┬──────┘
       │ App pairing success
       ▼
┌─────────────┐  Power btn ┌─────────────┐
│ Start of Day│◄──────────►│ Screensaver │
└──────┬──────┘            └─────────────┘
       │ Any button              │
       ▼                         │ Power btn
┌─────────────┐                  │
│  Overview   │◄─────────────────┘
└──────┬──────┘
       │ Scroll select + Press
       ▼
┌─────────────┐  Complete   ┌─────────────┐
│  Task In    │────────────►│ Settlement  │
└──────┬──────┘  (all done) └──────┬──────┘
       │ Complete single task      │ Any button
       └───────────────────────────┘
              Return to Overview
```

**State Descriptions:**

| State | Description |
|-------|-------------|
| First Pair | New device waiting for App pairing |
| Start of Day | Default page on power on, shows morning info |
| Overview | Main page, mixed timeline display |
| Task In | Task detail page, focus mode |
| Settlement | Summary page, shown when all tasks complete |
| Screensaver | Static pet image, BLE disconnected for power saving |

---

## 5. Pet System

### 5.1 Pet Forms

| Form | Name | Pixel Asset |
|------|------|-------------|
| Cat | Cat | cat_*.png |
| Dog | Dog | dog_*.png |
| Rabbit | Bunny | bunny_*.png |
| Bird | Bird | bird_*.png |
| Dragon | Dragon | dragon_*.png |

### 5.2 Growth Stages

| Stage | Name | Unlock Condition |
|-------|------|------------------|
| Baby | Baby | Initial stage |
| Child | Child | Complete 50 tasks |
| Teen | Teen | Complete 150 tasks |
| Adult | Adult | Complete 300 tasks |
| Elder | Elder | Complete 500 tasks |

### 5.3 Mood States

| Mood | Name | Trigger Condition |
|------|------|-------------------|
| Happy | Happy | Default state |
| Excited | Excited | Completing multiple tasks consecutively |
| Focused | Focused | Entering Task In page |
| Sleepy | Sleepy | Nighttime period |
| Missing | Missing You | Long time without interaction |

### 5.4 Pixel Art Asset Requirements

Each form requires the following assets:

```
{form}/
├── {stage}/
│   ├── idle.png          # Idle animation (4 frames)
│   ├── happy.png         # Happy expression
│   ├── excited.png       # Excited expression
│   ├── focused.png       # Focused expression
│   ├── sleepy.png        # Sleepy expression
│   └── missing.png       # Missing expression
```

**Image Specifications:**

| Spec | 4-inch Display | 7-inch Display |
|------|----------------|----------------|
| Size | 64 × 64 px | 128 × 128 px |
| Format | 1-bit BMP | 1-bit BMP |
| Colors | Black & White | Black & White |

---

## 6. Data Synchronization

### 6.1 BLE Protocol Overview

For detailed protocol, refer to `BLE-Protocol-Spec.md`.

#### Main Commands

| Command | Type Code | Direction | Description |
|---------|-----------|-----------|-------------|
| DayPack | 0x10 | App → Device | Send daily data package |
| TaskInPage | 0x11 | App → Device | Send task details |
| DeviceMode | 0x12 | App → Device | Set device mode |
| CompleteTask | 0x11 | Device → App | Task completion event |
| WheelSelect | 0x14 | Device → App | Wheel selection confirm (sends selected item ID) |
| ViewEventDetail | 0x15 | Device → App | View event detail |
| RequestRefresh | 0x20 | Device → App | Request data refresh |
| LowBattery | 0x40 | Device → App | Low battery notification |

### 6.2 Event Sending Timing

| Trigger | Event Sent |
|---------|------------|
| Scroll wheel | Local processing only, no event sent |
| Press confirm (task) | WheelSelect (sends selected item ID) |
| Press confirm (event) | ViewEventDetail |
| Complete task | CompleteTask |
| Battery below 20% | LowBattery |

### 6.3 Data Refresh Timing

| Trigger Condition | Refresh Content |
|-------------------|-----------------|
| App launch | Full DayPack |
| Device connection | Full DayPack |
| Task status change | Incremental update |
| User manual refresh | Full DayPack |
| Scheduled refresh (hourly) | Full DayPack |

### 6.4 Offline Behavior

| Scenario | Device Behavior |
|----------|-----------------|
| Not connected to App | Display cached data |
| Button task completion | Mark locally + delayed sync |
| Day change without sync | App pushes new Day Pack |

---

## 7. 4-inch vs 7-inch Differences

### 7.1 Layout Adaptation

#### 4-inch Display (400 × 300)

- Compact layout
- Smaller pet image (64 × 64)
- Maximum 3 tasks displayed
- Single column layout

#### 7-inch Display (800 × 480)

- Spacious layout
- Larger pet image (128 × 128)
- Maximum 5 tasks displayed
- Optional dual column layout

### 7.2 Font Sizes

| Element | 4-inch | 7-inch |
|---------|--------|--------|
| Title | 16px | 24px |
| Body | 12px | 16px |
| Caption | 10px | 12px |

### 7.3 Information Density

| Content | 4-inch | 7-inch |
|---------|--------|--------|
| Task List | 3 items | 5 items |
| Schedule Preview | 1 item | 3 items |
| Weather Details | Icon + temp only | Full info |

---

## 8. Firmware Development Guide

### 8.1 Development Environment

| Item | Recommendation |
|------|----------------|
| MCU | ESP32-C3 / nRF52832 |
| IDE | ESP-IDF / Zephyr |
| E-ink Driver | GxEPD2 / Vendor SDK |

### 8.2 Memory Layout

```
Flash (4MB):
├── Bootloader (64KB)
├── Firmware (1MB)
├── Pet Assets (2MB)
│   ├── cat/ (400KB)
│   ├── dog/ (400KB)
│   ├── bunny/ (400KB)
│   ├── bird/ (400KB)
│   └── dragon/ (400KB)
├── Fonts (512KB)
└── Cache (448KB)
    ├── DayPack (64KB)
    └── Display Buffer (384KB)
```

### 8.3 Key Implementation Points

#### Power Management

```c
// Sleep/Wake
void enter_deep_sleep() {
    // Save current state
    save_state_to_rtc();
    // Configure wake sources: button + timer
    esp_sleep_enable_ext0_wakeup(BUTTON_PIN, 0);
    esp_sleep_enable_timer_wakeup(SLEEP_DURATION_US);
    esp_deep_sleep_start();
}
```

#### E-ink Refresh Strategy

```c
typedef enum {
    REFRESH_FULL,      // Full refresh - page switch
    REFRESH_PARTIAL,   // Partial refresh - task status update
    REFRESH_FAST       // Fast refresh - animation frames
} RefreshMode;
```

#### BLE Data Reception

```c
void on_ble_data_received(uint8_t* data, size_t len) {
    uint8_t type = data[0];
    uint16_t payload_len = (data[1] << 8) | data[2];
    uint8_t* payload = &data[3];

    switch (type) {
        case 0x10: // DayPack
            parse_day_pack(payload, payload_len);
            refresh_display(REFRESH_FULL);
            break;
        case 0x11: // TaskInPage
            parse_task_in_page(payload, payload_len);
            show_task_in_page();
            break;
        // ...
    }
}
```

### 8.4 Test Checklist

- [ ] BLE connection stability (continuous 24 hours)
- [ ] Battery life test (standby + active use)
- [ ] E-ink refresh quality (ghosting, grayscale)
- [ ] Button response (debounce, long press detection)
- [ ] Data parsing (boundary conditions, abnormal data)
- [ ] Offline mode (caching, state recovery)

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| Day Pack | Daily data package containing all 4 pages of data |
| Event Log | User interaction event sent from device to App |
| Task In | Task detail page |
| Settlement | End-of-day summary page |
| Focus Mode | Simplified display mode with fewer distractions |

## Appendix B: Revision History

| Version | Date | Changes |
|---------|------|---------|
| v1.0.0 | 2026-01-30 | Initial version |
| v1.1.0 | 2026-01-31 | Updated button config (power + scroll wheel), interaction flow, state machine, BLE events |
| v1.1.1 | 2026-02-03 | Specified scroll wheel button position at bottom of screen |

---

## Contact

For protocol questions or clarifications, contact the Kiro development team.
