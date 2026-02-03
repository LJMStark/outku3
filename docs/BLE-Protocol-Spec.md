# Kiro BLE Communication Protocol Specification

**Version:** v1.1.0
**Last Updated:** 2026-01-31
**Status:** Draft

---

## Table of Contents

1. [Protocol Overview](#1-protocol-overview)
2. [BLE Configuration](#2-ble-configuration)
3. [Data Packet Format](#3-data-packet-format)
4. [App → Device Commands](#4-app--device-commands)
5. [Device → App Events](#5-device--app-events)
6. [Page Data Structures](#6-page-data-structures)
7. [Example Data](#7-example-data)
8. [Error Handling](#8-error-handling)

---

## 1. Protocol Overview

### 1.1 Purpose

This document defines the BLE communication protocol between the Kiro iOS app and the E-ink hardware device. The protocol enables:

- Sending daily data (Day Pack) from app to device
- Receiving user interaction events from device to app
- Real-time task status synchronization

### 1.2 Revision History

| Version | Date       | Changes                          |
|---------|------------|----------------------------------|
| v1.0.0  | 2026-01-30 | Initial protocol specification   |
| v1.1.0  | 2026-01-31 | Added WheelSelect, ViewEventDetail, LowBattery events |

### 1.3 Terminology

| Term          | Definition                                           |
|---------------|------------------------------------------------------|
| Day Pack      | Complete daily data package sent to device           |
| Event Log     | User interaction event sent from device to app       |
| Task In       | Task detail page on E-ink display                    |
| Settlement    | End-of-day summary page                              |
| Focus Mode    | Simplified display mode with fewer distractions      |

---

## 2. BLE Configuration

### 2.1 Service UUID

```
Service UUID: 0000FFE0-0000-1000-8000-00805F9B34FB
```

### 2.2 Characteristics

| Characteristic | UUID                                   | Direction      | Properties      |
|----------------|----------------------------------------|----------------|-----------------|
| Write          | `0000FFE1-0000-1000-8000-00805F9B34FB` | App → Device   | Write           |
| Notify         | `0000FFE2-0000-1000-8000-00805F9B34FB` | Device → App   | Notify          |

### 2.3 Connection Parameters

| Parameter          | Value      |
|--------------------|------------|
| Scan Timeout       | 10 seconds |
| Connection Timeout | 15 seconds |
| Auto Reconnect     | Enabled    |

---

## 3. Data Packet Format

### 3.1 General Packet Structure (App → Device)

All data sent from app to device follows this format:

```
+--------+--------+--------+------------------+
| Type   | Length (BE)     | Payload          |
| 1 byte | 2 bytes         | N bytes          |
+--------+--------+--------+------------------+
```

| Field   | Size    | Description                              |
|---------|---------|------------------------------------------|
| Type    | 1 byte  | Command type identifier (see Section 4)  |
| Length  | 2 bytes | Payload length (Big Endian)              |
| Payload | N bytes | Command-specific data                    |

### 3.2 String Encoding

Strings are encoded with a length prefix:

```
+--------+------------------+
| Length | UTF-8 Data       |
| 1 byte | N bytes          |
+--------+------------------+
```

- **Encoding:** UTF-8
- **Max Length:** Specified per field (truncated if exceeded)
- **Length Byte:** Actual byte count (not character count)

### 3.3 Byte Order

- **Multi-byte integers:** Big Endian
- **Signed integers:** Two's complement

---

## 4. App → Device Commands

### 4.1 Command Type Summary

| Type   | Name         | Description                        |
|--------|--------------|-----------------------------------|
| `0x01` | PetStatus    | Pet state information             |
| `0x02` | TaskList     | Today's task list                 |
| `0x03` | Schedule     | Today's calendar events           |
| `0x04` | Weather      | Current weather information       |
| `0x05` | Time         | Current time synchronization      |
| `0x10` | DayPack      | Complete daily data package       |
| `0x11` | TaskInPage   | Task detail page data             |
| `0x12` | DeviceMode   | Device operation mode             |

---

### 4.2 PetStatus (0x01)

Pet state information for display.

**Payload Structure:**

| Offset | Field    | Size        | Max Length | Description                    |
|--------|----------|-------------|------------|--------------------------------|
| 0      | Name     | 1 + N bytes | 20 chars   | Pet name (length-prefixed)     |
| N+1    | Mood     | 1 byte      | -          | First char ASCII of mood       |
| N+2    | Stage    | 1 byte      | -          | First char ASCII of stage      |
| N+3    | Progress | 1 byte      | -          | Progress 0-100 (clamped to 255)|

**Mood Values:**

| Value | Mood        |
|-------|-------------|
| `H`   | Happy       |
| `E`   | Excited     |
| `F`   | Focused     |
| `S`   | Sleepy      |
| `M`   | Missing You |

**Stage Values:**

| Value | Stage  |
|-------|--------|
| `B`   | Baby   |
| `C`   | Child  |
| `T`   | Teen   |
| `A`   | Adult  |
| `E`   | Elder  |

---

### 4.3 TaskList (0x02)

Today's task list (max 10 tasks).

**Payload Structure:**

| Offset | Field      | Size        | Description                    |
|--------|------------|-------------|--------------------------------|
| 0      | TaskCount  | 1 byte      | Number of tasks (0-10)         |
| 1+     | Tasks[]    | Variable    | Array of task entries          |

**Task Entry:**

| Offset | Field       | Size        | Max Length | Description              |
|--------|-------------|-------------|------------|--------------------------|
| 0      | Title       | 1 + N bytes | 30 chars   | Task title               |
| N+1    | IsCompleted | 1 byte      | -          | 0x00=incomplete, 0x01=complete |

---

### 4.4 Schedule (0x03)

Today's calendar events (max 8 events).

**Payload Structure:**

| Offset | Field       | Size        | Description                    |
|--------|-------------|-------------|--------------------------------|
| 0      | EventCount  | 1 byte      | Number of events (0-8)         |
| 1+     | Events[]    | Variable    | Array of event entries         |

**Event Entry:**

| Offset | Field     | Size        | Max Length | Description              |
|--------|-----------|-------------|------------|--------------------------|
| 0      | Title     | 1 + N bytes | 25 chars   | Event title              |
| N+1    | StartTime | 5 bytes     | -          | "HH:mm" format (raw UTF-8) |

---

### 4.5 Weather (0x04)

Current weather information.

**Payload Structure:**

| Offset | Field       | Size        | Max Length | Description              |
|--------|-------------|-------------|------------|--------------------------|
| 0      | Temperature | 1 byte      | -          | Signed int8 (Celsius)    |
| 1      | Condition   | 1 + N bytes | 15 chars   | Weather condition string |

**Condition Values:**

| Value     | Description |
|-----------|-------------|
| `sunny`   | Clear sky   |
| `cloudy`  | Cloudy      |
| `rainy`   | Rain        |
| `snowy`   | Snow        |
| `stormy`  | Storm       |

---

### 4.6 Time (0x05)

Time synchronization.

**Payload Structure:**

| Offset | Field  | Size   | Description                    |
|--------|--------|--------|--------------------------------|
| 0      | Year   | 1 byte | Year - 2000 (e.g., 26 = 2026)  |
| 1      | Month  | 1 byte | Month (1-12)                   |
| 2      | Day    | 1 byte | Day (1-31)                     |
| 3      | Hour   | 1 byte | Hour (0-23)                    |
| 4      | Minute | 1 byte | Minute (0-59)                  |
| 5      | Second | 1 byte | Second (0-59)                  |

---

### 4.7 DayPack (0x10)

Complete daily data package containing all 4 pages.

**Payload Structure:**

| Offset | Field                  | Size        | Max Length | Description                    |
|--------|------------------------|-------------|------------|--------------------------------|
| 0      | Year                   | 1 byte      | -          | Year - 2000                    |
| 1      | Month                  | 1 byte      | -          | Month (1-12)                   |
| 2      | Day                    | 1 byte      | -          | Day (1-31)                     |
| 3      | DeviceMode             | 1 byte      | -          | 0x00=Interactive, 0x01=Focus   |
| 4      | FocusChallengeEnabled  | 1 byte      | -          | 0x00=disabled, 0x01=enabled    |
| 5      | MorningGreeting        | 1 + N bytes | 50 chars   | Page 1: Morning greeting       |
| N+6    | DailySummary           | 1 + N bytes | 60 chars   | Page 1: Daily summary          |
| ...    | FirstItem              | 1 + N bytes | 40 chars   | Page 1: First task/event       |
| ...    | CurrentScheduleSummary | 1 + N bytes | 30 chars   | Page 2: Schedule summary       |
| ...    | CompanionPhrase        | 1 + N bytes | 40 chars   | Page 2: Companion message      |
| ...    | TaskCount              | 1 byte      | -          | Number of top tasks (0-3)      |
| ...    | TopTasks[]             | Variable    | -          | Page 2: Top 3 tasks            |
| ...    | SettlementData         | Variable    | -          | Page 4: Settlement data        |

**TopTask Entry:**

| Offset | Field       | Size        | Max Length | Description              |
|--------|-------------|-------------|------------|--------------------------|
| 0      | TaskId      | 1 + N bytes | 36 chars   | UUID string              |
| N+1    | Title       | 1 + N bytes | 30 chars   | Task title               |
| ...    | IsCompleted | 1 byte      | -          | 0x00=incomplete, 0x01=complete |
| ...    | Priority    | 1 byte      | -          | Priority level (1-3)     |

**SettlementData:**

| Offset | Field               | Size        | Max Length | Description              |
|--------|---------------------|-------------|------------|--------------------------|
| 0      | TasksCompleted      | 1 byte      | -          | Completed task count     |
| 1      | TasksTotal          | 1 byte      | -          | Total task count         |
| 2      | PointsEarned        | 2 bytes     | -          | Points (Big Endian)      |
| 4      | StreakDays          | 1 byte      | -          | Current streak days      |
| 5      | SummaryMessage      | 1 + N bytes | 50 chars   | Summary text             |
| N+6    | EncouragementMessage| 1 + N bytes | 50 chars   | Encouragement text       |

---

### 4.8 TaskInPage (0x11)

Task detail page data (Page 3).

**Payload Structure:**

| Offset | Field                | Size        | Max Length | Description              |
|--------|----------------------|-------------|------------|--------------------------|
| 0      | TaskId               | 1 + N bytes | 36 chars   | UUID string              |
| N+1    | TaskTitle            | 1 + N bytes | 40 chars   | Task title               |
| ...    | TaskDescription      | 1 + N bytes | 100 chars  | Task description         |
| ...    | EstimatedDuration    | 1 + N bytes | 10 chars   | Duration (e.g., "30min") |
| ...    | Encouragement        | 1 + N bytes | 50 chars   | Encouragement message    |
| ...    | FocusChallengeActive | 1 byte      | -          | 0x00=inactive, 0x01=active |

---

### 4.9 DeviceMode (0x12)

Set device operation mode.

**Payload Structure:**

| Offset | Field | Size   | Description                    |
|--------|-------|--------|--------------------------------|
| 0      | Mode  | 1 byte | 0x00=Interactive, 0x01=Focus   |

---

## 5. Device → App Events

Events are sent from device to app via the Notify characteristic.

### 5.1 Event Packet Structure

```
+--------+--------+------------------+
| Type   | Length | Payload          |
| 1 byte | 1 byte | N bytes          |
+--------+--------+------------------+
```

### 5.2 Event Type Summary

| Type   | Name                | Description                        |
|--------|---------------------|------------------------------------|
| `0x10` | EnterTaskIn         | User entered task detail page      |
| `0x11` | CompleteTask        | User marked task as complete       |
| `0x12` | SkipTask            | User skipped a task                |
| `0x13` | SelectedTaskChanged | User changed selected task         |
| `0x14` | WheelSelect         | Wheel button pressed (confirm selection) |
| `0x15` | ViewEventDetail     | User viewing calendar event detail |
| `0x20` | RequestRefresh      | Device requests data refresh       |
| `0x30` | DeviceWake          | Device woke from sleep             |
| `0x31` | DeviceSleep         | Device entering sleep mode         |
| `0x40` | LowBattery          | Device battery low notification    |

---

### 5.3 EnterTaskIn (0x10)

User entered the task detail page (focus mode started).

**Payload:**

| Offset | Field  | Size        | Description              |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | TaskId length            |
| 1      | TaskId | N bytes     | UUID string (UTF-8)      |
| 1+N    | Timestamp | 4 bytes  | Unix Timestamp (Big Endian) (UInt32) |

**App Response:**
- Send TaskInPage (0x11) with task details
- Record focus session start timestamp for this task

**Focus Time Tracking:**
This event marks the START of a focus session. App records the provided timestamp to calculate focus duration when CompleteTask or SkipTask is received.

---

### 5.4 CompleteTask (0x11)

User marked a task as complete on the device (short press wheel).

**Payload:**

| Offset | Field  | Size        | Description              |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | TaskId length            |
| 1      | TaskId | N bytes     | UUID string (UTF-8)      |
| 1+N    | Timestamp | 4 bytes  | Unix Timestamp (Big Endian) (UInt32) |

**App Response:**
- Update task status in AppState, recalculate points
- Record focus session end timestamp
- Calculate focus duration (end - start)
- Cross-reference with Screen Time data to determine actual focus time

---

### 5.5 SkipTask (0x12)

User skipped a task (long press wheel >1s).

**Payload:**

| Offset | Field  | Size        | Description              |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | TaskId length            |
| 1      | TaskId | N bytes     | UUID string (UTF-8)      |
| 1+N    | Timestamp | 4 bytes  | Unix Timestamp (Big Endian) (UInt32) |

**App Response:**
- Mark task as skipped, move to next task
- Record focus session end timestamp
- Calculate focus duration (end - start)
- Cross-reference with Screen Time data to determine actual focus time

---

### 5.5 SkipTask (0x12)

User skipped a task (long press wheel >1s).

**Payload:**

| Offset | Field     | Size    | Description                          |
|--------|-----------|---------|--------------------------------------|
| 0      | Length    | 1 byte  | TaskId length                        |
| 1      | TaskId    | N bytes | UUID string (UTF-8)                  |
| 1+N    | Timestamp | 4 bytes | Unix Timestamp (Big Endian) (UInt32) |

**App Response:**
- Mark task as skipped, move to next task
- Record focus session end timestamp
- Calculate focus duration (end - start)
- Cross-reference with Screen Time data to determine actual focus time

---

### 5.6 SelectedTaskChanged (0x13)

User changed the selected task in the overview.

**Payload:**

| Offset | Field  | Size        | Description              |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | TaskId length            |
| 1      | TaskId | N bytes     | UUID string (UTF-8)      |

**App Response:** Update selected task state.

---

### 5.7 RequestRefresh (0x20)

Device requests fresh data from app.

**Payload:** None (Length = 0)

**App Response:** Send updated DayPack (0x10).

---

### 5.8 DeviceWake (0x30)

Device woke from sleep mode.

**Payload:** None (Length = 0)

**App Response:** Optionally sync time and send updated data.

---

### 5.9 DeviceSleep (0x31)

Device is entering sleep mode.

**Payload:** None (Length = 0)

**App Response:** None required.

---

### 5.10 WheelSelect (0x14)

User confirmed selection via wheel button press.

**Payload:**

| Offset | Field  | Size        | Description              |
|--------|--------|-------------|--------------------------|
| 0      | Length | 1 byte      | Selected item ID length  |
| 1      | ItemId | N bytes     | Selected item ID (UTF-8) |

**App Response:**
- If task selected: Send TaskInPage (0x11) with task details
- If event selected: Send event detail data

---

### 5.11 ViewEventDetail (0x15)

User viewing calendar event detail.

**Payload:**

| Offset | Field   | Size        | Description              |
|--------|---------|-------------|--------------------------|
| 0      | Length  | 1 byte      | EventId length           |
| 1      | EventId | N bytes     | Event ID (UTF-8)         |

**App Response:** None required (auto-timeout returns to Overview).

---

### 5.12 LowBattery (0x40)

Device battery is low.

**Payload:**

| Offset | Field        | Size   | Description              |
|--------|--------------|--------|--------------------------|
| 0      | BatteryLevel | 1 byte | Battery percentage (0-100) |

**App Response:** Show low battery notification to user.

---

## 6. Page Data Structures

### 6.1 Page 1: Start of Day

Displayed when user first interacts with device in the morning.

**Content:**
- Morning greeting (personalized)
- Daily summary (weather, task count, first event)
- First item preview (next event or top task)

**Data Source:** DayPack fields:
- `morningGreeting`
- `dailySummary`
- `firstItem`

---

### 6.2 Page 2: Overview

Main dashboard showing today's overview.

**Content:**
- Current/next schedule item
- Top 3 tasks with completion status
- Companion phrase (encouragement)

**Data Source:** DayPack fields:
- `currentScheduleSummary`
- `topTasks[]`
- `companionPhrase`

---

### 6.3 Page 3: Task In

Task detail page shown when user selects a task.

**Content:**
- Task title and description
- Estimated duration
- Encouragement message
- Focus challenge indicator

**Data Source:** TaskInPage command (0x11)

**Trigger:** EnterTaskIn event (0x10) from device

---

### 6.4 Page 4: Settlement

End-of-day summary page.

**Content:**
- Tasks completed / total
- Points earned today
- Current streak
- Summary message
- Encouragement for tomorrow

**Data Source:** DayPack.settlementData

---

## 7. Example Data

### 7.1 DayPack Example (Hex)

```
Command: 0x10 (DayPack)

Full Packet:
10 00 C8                              // Type=0x10, Length=200 (example)

Payload:
1A 01 1E                              // Date: 2026-01-30
00                                    // DeviceMode: Interactive
00                                    // FocusChallengeEnabled: false

// Page 1: Start of Day
0F 47 6F 6F 64 20 6D 6F 72 6E 69 6E 67 21 20 F0  // "Good morning! " (15 bytes)
1A 59 6F 75 20 68 61 76 65 20 35 20 74 61 73 6B  // "You have 5 task" (26 bytes)
73 20 74 6F 64 61 79 2E
0E 39 3A 30 30 20 54 65 61 6D 20 63 61 6C 6C     // "9:00 Team call" (14 bytes)

// Page 2: Overview
0C 4E 65 78 74 3A 20 31 30 3A 30 30              // "Next: 10:00" (12 bytes)
0F 4B 65 65 70 20 67 6F 69 6E 67 21 20 F0 9F 92  // "Keep going! " (15 bytes)

// Top Tasks (3 tasks)
03                                    // TaskCount: 3

// Task 1
24 61 62 63 64 65 66 67 68 2D 31 32 33 34 2D 35  // TaskId (36 bytes UUID)
36 37 38 2D 39 30 61 62 2D 63 64 65 66 67 68 69
6A 6B 6C 6D
0C 52 65 76 69 65 77 20 50 52 73                 // "Review PRs" (12 bytes)
00                                    // IsCompleted: false
01                                    // Priority: 1

// ... (Task 2, Task 3 similar)

// Page 4: Settlement
03                                    // TasksCompleted: 3
05                                    // TasksTotal: 5
00 32                                 // PointsEarned: 50 (Big Endian)
07                                    // StreakDays: 7
12 47 72 65 61 74 20 70 72 6F 67 72 65 73 73 21  // "Great progress!" (18 bytes)
0E 53 65 65 20 79 6F 75 20 74 6F 6D 6F 72 72 6F  // "See you tomorrow" (14 bytes)
77 21
```

### 7.2 Event Log Example (Hex)

**CompleteTask Event:**

```
11                                    // Type: CompleteTask
24                                    // Length: 36 bytes
61 62 63 64 65 66 67 68 2D 31 32 33 34 2D 35 36  // TaskId UUID
37 38 2D 39 30 61 62 2D 63 64 65 66 67 68 69 6A
6B 6C 6D
```

**RequestRefresh Event:**

```
20                                    // Type: RequestRefresh
00                                    // Length: 0 (no payload)
```

### 7.3 Time Sync Example (Hex)

```
Command: 0x05 (Time)

Full Packet:
05 00 06                              // Type=0x05, Length=6

Payload:
1A                                    // Year: 26 (2026)
01                                    // Month: 1
1E                                    // Day: 30
09                                    // Hour: 9
1E                                    // Minute: 30
00                                    // Second: 0
```

---

## 8. Error Handling

### 8.1 Connection Errors

| Error                  | App Behavior                              |
|------------------------|-------------------------------------------|
| Bluetooth Off          | Show "Enable Bluetooth" prompt            |
| Permission Denied      | Show settings redirect                    |
| Device Not Found       | Retry scan, show "Device not found"       |
| Connection Timeout     | Retry connection (max 3 attempts)         |
| Unexpected Disconnect  | Auto-reconnect if enabled                 |

### 8.2 Data Validation

| Validation             | Rule                                      |
|------------------------|-------------------------------------------|
| String Length          | Truncate to max length                    |
| Integer Overflow       | Clamp to valid range                      |
| Invalid Event Type     | Ignore unknown event types                |
| Malformed Packet       | Discard and log error                     |

### 8.3 Retry Policy

| Operation              | Max Retries | Backoff                |
|------------------------|-------------|------------------------|
| Scan                   | 3           | 2s, 4s, 8s             |
| Connect                | 3           | 1s, 2s, 4s             |
| Write                  | 2           | 500ms, 1s              |

---

## 9. Focus Time Calculation

### 9.1 Overview

Focus time is calculated by combining device events with phone screen activity data. The goal is to measure actual focused work time during task sessions.

### 9.2 Data Sources

| Source | Data | Purpose |
|--------|------|---------|
| Device Events | EnterTaskIn, CompleteTask, SkipTask timestamps | Define task session boundaries |
| Screen Time API | Phone screen unlock/lock events | Detect phone usage during sessions |

### 9.3 Calculation Algorithm

```
Focus Session:
  Start: EnterTaskIn timestamp
  End: CompleteTask or SkipTask timestamp
  Duration: End - Start

Focus Time Calculation:
  1. Get all screen unlock events during the session
  2. For each 30-minute window without screen unlock:
     - Count as focus time
  3. Total Focus Time = Sum of all 30+ minute uninterrupted periods
```

### 9.4 Example

```
Task Session: 09:00 - 10:30 (90 minutes total)

Screen Activity:
  09:05 - Phone unlocked (5 min usage)
  09:45 - Phone unlocked (2 min usage)
  10:20 - Phone unlocked (1 min usage)

Focus Periods:
  09:10 - 09:45 = 35 min (>30 min, counts as focus)
  09:47 - 10:20 = 33 min (>30 min, counts as focus)

Total Focus Time: 68 minutes
```

### 9.5 App Implementation Notes

- Use `DeviceActivityMonitor` framework (iOS 15+) for screen time data
- Requires user authorization for Screen Time access
- Store focus sessions locally for offline calculation
- Sync focus data to cloud when connected

---

## Appendix A: Swift Type Reference

### A.1 BLEDataType Enum

```swift
public enum BLEDataType: UInt8, Sendable {
    case petStatus = 0x01
    case taskList = 0x02
    case schedule = 0x03
    case weather = 0x04
    case time = 0x05
    case dayPack = 0x10
    case taskInPage = 0x11
    case deviceMode = 0x12
}
```

### A.2 EventLogType Enum

```swift
public enum EventLogType: String, Codable, Sendable {
    case enterTaskIn = "enter_task_in"       // 0x10
    case completeTask = "complete_task"      // 0x11
    case skipTask = "skip_task"              // 0x12
    case selectedTaskChanged = "selected_task_changed"  // 0x13
    case wheelSelect = "wheel_select"        // 0x14
    case viewEventDetail = "view_event_detail"  // 0x15
    case requestRefresh = "request_refresh"  // 0x20
    case deviceWake = "device_wake"          // 0x30
    case deviceSleep = "device_sleep"        // 0x31
    case lowBattery = "low_battery"          // 0x40
}
```

### A.3 DeviceMode Enum

```swift
public enum DeviceMode: String, Codable, Sendable {
    case interactive = "Interactive"  // 0x00
    case focus = "Focus"              // 0x01
}
```

---

## Appendix B: Checksum (Future)

Reserved for future protocol versions. Current version (v1.0.0) does not include checksum validation.

Proposed format for v1.1.0:

```
+--------+--------+--------+------------------+----------+
| Type   | Length (BE)     | Payload          | CRC16    |
| 1 byte | 2 bytes         | N bytes          | 2 bytes  |
+--------+--------+--------+------------------+----------+
```

---

## Contact

For protocol questions or clarifications, contact the Kiro development team.
