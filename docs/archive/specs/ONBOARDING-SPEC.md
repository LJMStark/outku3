# Kirole Onboarding Spec — Hardware Alignment

**Version:** 1.0
**Date:** 2026-02-15
**Status:** Draft
**Scope:** Align onboarding flow copy, questions, and structure with Kirole product positioning and hardware docs.

---

## 1. Context & Problem

The current onboarding flow (15 screens) was scaffolded from the Inku Daily Schedule Planner prototype. It needs realignment because:

- All copy references "Inku" — Kirole is an independent product
- Core differentiators (AI Task Dehydration, Attention Mirror, Smart Reminders) are absent
- Kickstarter page shows Inku's crowdfunding data — irrelevant to Kirole
- Pet system changed: unified form with 5 states (not 5 forms)
- Questionnaire doesn't collect data needed for AI personalization

**Reference docs:**
- `docs/硬件需求文档-Hardware-Requirements-Document.md` (v0.3)
- `docs/固件功能规格文档.md` (v1.3.0)
- `docs/BLE通信协议规格文档.md` (v1.3.1)

---

## 2. Product Positioning

**Tagline:** Unlock the Flow, Make it Happen.

**What Kirole is:** A focus companion for deep knowledge workers who use many productivity tools but struggle with execution. Through AI-driven task dehydration, attention mirroring, and smart reminders — paired with a pixel pet companion — Kirole transforms complex intentions into executable micro-actions.

**Target users:** Remote workers, freelancers, and knowledge workers who need focus management.

**Two user paths:**
- **App + Hardware:** Users with the E-ink companion device (pairing happens post-onboarding)
- **App-only:** Users who use the iOS app without hardware

---

## 3. Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Brand name | Kirole (not Inku) | Independent product |
| Pet name | Kirole | Same as product |
| Pet form | Unified (single form, 5 states) | Simplified from 5 forms |
| Language | English | MVP scope |
| Screen count | 13 (down from 15) | Remove Kickstarter + discovery question |
| Narrative tone | Emotional storytelling (preserved) | Rewritten for Kirole's focus companion positioning |
| Feature pages | Keep structure, update copy | "Not Just a Calendar" + "Focus, not frenzy" concepts work |
| Text animation | Keep and rewrite | High emotional tension, rewrite for Kirole narrative |
| Questionnaire | 8 questions, 4 dimensions | Drives AI personalization (CompanionTextService, SmartReminderService, TaskDehydrationService) |
| Companion styles | 4: encouraging/strict/playful/calm | Existing CompanionTextService styles |
| CTA buttons | Personalized per-screen + emoji | Maintains personality and engagement |
| Registration | Last screen with skip button | Google/Apple/Email, non-blocking |
| Hardware pairing | Post-onboarding, separate flow | Supports App-only users |
| Personalization | Theme + pet + custom photo upload | Replaces old avatar selector |

---

## 4. Screen Flow (13 Screens)

### Screen 0: Welcome

**Purpose:** First impression. Kirole pet greets user, establishes emotional connection.

**Layout:** Teal background, FloatingIconRing, pet character + dialog bubble, CTA button.

**Copy:**
- Dialog: "Hey there! I'm Kirole, your focus companion. Ready to unlock your flow?"
- CTA: "Let's Go!" (with relevant emoji)
- Secondary: "Already have an account?"

**Pet behavior:** Idle animation, friendly wave gesture.

---

### Screen 1: Feature — AI-Powered Companion

**Purpose:** Show how Kirole goes beyond a calendar — it understands context and helps you act.

**Layout:** Preserve current staggered DialogBubbles structure with bouncing arrows.

**Concept:** "Not Just a Calendar" → Kirole learns your patterns and breaks tasks into actionable steps.

**Copy:**
- Title: "Not Just a Calendar"
- Subtitle: "Kirole breaks down your tasks so you know exactly what to do next"
- Dialog bubbles (3 examples showing AI task dehydration):
  - "You have 'Write project proposal' — let's start with: Read section 3 and leave inline comments"
  - "Your standup is in 30 min — want to review yesterday's notes first?"
  - "You've been crushing it today — 3 tasks done, 2 to go!"
- CTA: "Continue"

---

### Screen 2: Feature — Focus & Attention

**Purpose:** Show how Kirole tracks focus and reduces noise.

**Layout:** Preserve BeforeAfterCard (tap-to-flip) structure.

**Concept:** "Focus, not frenzy" → Kirole mirrors your attention patterns quietly.

**Copy:**
- Title: "Focus, not frenzy"
- Subtitle: "Kirole tracks your focus time quietly — no dings, no FOMO."
- Before card: Chaotic multi-app notification overload
- After card: Clean Kirole overview showing focus session stats (45 min focused, 0 interruptions)
- Tap instruction: "Tap card to see the difference"
- CTA: "I Will Focus"

---

### Screen 3: Text Animation (Narrative)

**Purpose:** Emotional peak. Rewritten for Kirole's focus companion narrative.

**Layout:** Dark background, sequential text animation, tap to continue.

**Copy (sequential lines):**
1. "You use ten tools to stay organized."
2. "But somehow, nothing gets done."
3. "Tasks pile up."
4. "Focus slips away."
5. "And the tools meant to help..."
6. "...just add more noise."
7. "Kirole is different."

**Final reveal (with features):**
- "Turning complexity into action."
- Features: "Focus" / "Flow" / "Done"

**Skip button:** Available for users who want to skip.
**Tap instruction:** "(Tap Anywhere To Continue)"

---

### Screen 4: Personalization

**Purpose:** Theme selection, pet customization, custom photo upload.

**Layout:** Theme picker cards + pet display + photo upload option.

**Copy:**
- Title: "Your Kirole, Your Way"
- Theme section: "Pick your favorite mood"
- Pet section: "Meet your companion" (shows unified Kirole pet)
- Photo section: "Or upload your own" (custom photo upload)
- CTA: "I'll Make It Mine"

**Themes available:** Classic Warm (default), Elegant Purple, Modern Teal.

---

### Screens 5–12: Questionnaire (8 Questions)

All questionnaire screens share the same layout: question title, subtitle, option cards, pet dialog bubble, and CTA button.

**Pet dialog behavior:**
- No selection: "Take your time, I'll wait!"
- After selection: "Got it — I'll remember that."

**CTA:** "Continue" (all questionnaire screens)

---

#### Dimension 1: Companion Personality Preferences

**Screen 5 — Q1: Communication Style**

- Title: "How should Kirole talk to you?"
- Subtitle: "This shapes how your companion communicates"
- Type: Single choice
- Options:
  - "Like a supportive friend" → maps to `encouraging`
  - "Like a no-nonsense coach" → maps to `strict`
  - "Like a playful buddy" → maps to `playful`
  - "Like a calm mentor" → maps to `calm`
- Maps to: `OnboardingProfile.companionStyle` → `CompanionTextService`

**Screen 6 — Q2: Motivation Style**

- Title: "When you're falling behind, what helps most?"
- Subtitle: "Kirole will adjust its encouragement to match"
- Type: Single choice
- Options:
  - "Gentle encouragement and patience"
  - "A direct reality check"
  - "Making it feel like a game"
  - "Quiet space to figure it out"
- Maps to: `OnboardingProfile.motivationStyle` → `SmartReminderService` tone

---

#### Dimension 2: Calendar & Task Habits

**Screen 7 — Q3: Calendar Usage**

- Title: "How do you use your calendar today?"
- Subtitle: "Helps Kirole understand your scheduling style"
- Type: Single choice
- Options:
  - "Only for work meetings"
  - "I don't really use one"
  - "Everything goes in my calendar"
- Maps to: `OnboardingProfile.calendarUsage` → integration suggestions, DayPack content density

**Screen 8 — Q4: Task Tracking**

- Title: "What about tracking tasks and to-dos?"
- Subtitle: "No wrong answer here"
- Type: Single choice
- Options:
  - "Nope, I wing it"
  - "Only work stuff"
  - "Can't live without my task list"
- Maps to: `OnboardingProfile.taskTrackingStyle` → task dehydration aggressiveness

---

#### Dimension 3: Distraction Patterns & Reminder Preferences

**Screen 9 — Q5: Distraction Sources**

- Title: "What pulls you away from deep work?"
- Subtitle: "This helps Kirole know when to step in"
- Type: Multiple choice
- Options:
  - "Phone notifications"
  - "Switching between apps"
  - "Meetings and interruptions"
  - "My own wandering mind"
- Maps to: `OnboardingProfile.distractionSources` → `SmartReminderService` trigger tuning

**Screen 10 — Q6: Reminder Preferences**

- Title: "How would you like to be reminded?"
- Subtitle: "Kirole can nudge you in different ways"
- Type: Single choice
- Options:
  - "Gentle nudges throughout the day" → maps to `gentleNudge` priority
  - "Only when deadlines are close" → maps to `deadline` priority
  - "Protect my streaks at all costs" → maps to `streakProtect` priority
  - "I'll check on my own" → maps to minimal reminders
- Maps to: `OnboardingProfile.reminderPreference` → `SmartReminderService` priority order

---

#### Dimension 4: Focus Mode & Task Habits

**Screen 11 — Q7: Task Approach**

- Title: "How do you handle complex tasks?"
- Subtitle: "Kirole can help break things down for you"
- Type: Single choice
- Options:
  - "I break them down myself"
  - "I jump in and figure it out"
  - "I procrastinate until pressure hits"
  - "I need help getting started"
- Maps to: `OnboardingProfile.taskApproach` → `TaskDehydrationService` aggressiveness (more dehydration for "need help" / "procrastinate")

**Screen 12 — Q8: Time Control**

- Title: "How much control do you feel over your time?"
- Subtitle: "Be honest — no judgment here"
- Type: Single choice
- Options:
  - "Barely keeping up"
  - "Completely overwhelmed"
  - "I'm in control"
  - "Some control, some chaos"
- Maps to: `OnboardingProfile.timeControl` → overall AI aggressiveness calibration

---

### Screen 13: Sign Up

**Purpose:** Account creation. Skippable — users can explore the app first.

**Layout:** Header label, title, subtitle, auth buttons, divider, email input.

**Copy:**
- Title: "Sign Up to Save Progress"
- Subtitle: "One more step to unlock your flow."
- Google button: "Continue with Google"
- Apple button: "Continue with Apple"
- Divider: "or"
- Email placeholder: "Email address"
- Email button: "Send Magic Link"
- Skip button: "Skip for now" (visible, non-judgmental)

---

## 5. Data Model Changes

### OnboardingProfile Updates

Fields to add/modify for the new questionnaire dimensions:

```swift
// New fields (replacing old Inku-specific fields)
public var companionStyle: CompanionStyle    // Q1: encouraging/strict/playful/calm
public var motivationStyle: MotivationStyle  // Q2: encouragement/reality-check/gamify/space
public var calendarUsage: CalendarUsage      // Q3: work-only/none/everything
public var taskTrackingStyle: TaskTracking   // Q4: wing-it/work-only/essential
public var distractionSources: [DistractionSource]  // Q5: multiple choice
public var reminderPreference: ReminderPref  // Q6: gentle/deadline/streak/minimal
public var taskApproach: TaskApproach        // Q7: self-break/jump-in/procrastinate/need-help
public var timeControl: TimeControl          // Q8: barely/overwhelmed/in-control/mixed
```

### AI Service Mapping

| Profile Field | Consuming Service | Effect |
|---------------|-------------------|--------|
| companionStyle | CompanionTextService | Prompt personality (4 styles) |
| motivationStyle | SmartReminderService | Reminder tone and framing |
| calendarUsage | DayPackGenerator | Content density, integration prompts |
| taskTrackingStyle | TaskDehydrationService | Dehydration aggressiveness |
| distractionSources | SmartReminderService | Trigger condition weighting |
| reminderPreference | SmartReminderService | Priority order (deadline/streak/idle/nudge) |
| taskApproach | TaskDehydrationService | Micro-action detail level |
| timeControl | Global AI calibration | Overall intervention frequency |

---

## 6. Removed Screens

| Original Screen | Reason |
|-----------------|--------|
| Screen 4: KickstarterPage | Inku-specific crowdfunding data, irrelevant to Kirole |
| Screen 6 (Q1): Discovery channel | Marketing attribution, doesn't drive AI personalization |

---

## 7. Asset Changes

| Asset | Current | New |
|-------|---------|-----|
| Pet character | tiko_mushroom / Inku references | Kirole unified form |
| Pet name in code | "Inku" / "Tiko" | "Kirole" |
| Avatar selector | boy/dog/girl/robot/toaster | Removed (unified pet + custom photo upload) |
| Kickstarter card | Inku crowdfunding stats | Removed |
| Feature page illustrations | Inku-branded | Kirole-branded |

---

## 8. OnboardingQuestions Data Structure

Replace `OnboardingQuestions.allQuestions` with 8 new questions mapped to the 4 dimensions above. Each question should include:

- `id`: Unique identifier
- `title`: Question text
- `subtitle`: Helper text
- `category`: Dimension name (companionPersonality / calendarTaskHabits / distractionReminder / focusTask)
- `type`: `.single` or `.multiple`
- `options`: Array of `OnboardingOption` with label, icon, and mapping value

---

## 9. Implementation Notes

### What changes:
1. All "Inku" references → "Kirole" in copy and code
2. `WelcomePage` dialog text
3. `FeatureCalendarPage` title, subtitle, dialog bubbles
4. `FeatureFocusPage` title, subtitle, before/after card content
5. `TextAnimationPage` all 7+ lines of sequential text
6. `PersonalizationPage` — replace AvatarSelector with pet display + photo upload
7. `OnboardingQuestions.allQuestions` — complete rewrite (8 new questions)
8. `OnboardingProfile` — new fields for 4 dimensions
9. `SignUpPage` subtitle text
10. Remove `KickstarterPage` and its route in `OnboardingContainerView`
11. Update `OnboardingState.currentPage` range (0-13 → 0-12, adjust for removed screens)

### What stays:
- SwiftUI view structure and animations
- `OnboardingContainerView` routing pattern (switch + .id() + .transition)
- `OnboardingCTAButton` component
- `OnboardingDialogBubble` component
- `BeforeAfterCard` component (content changes, structure stays)
- `ThemePreviewCard` component
- Spring transition animations
- Sound toggle functionality
- Page indicator dots

### Hardware mention:
The onboarding does NOT include hardware pairing or BLE setup. Hardware is mentioned implicitly through feature descriptions (e.g., "focus tracking" implies the E-ink device). A separate hardware pairing flow will be triggered post-onboarding when the user navigates to Settings or connects a device.

---

## 10. Screen Count Summary

| Section | Screens | Count |
|---------|---------|-------|
| Welcome | 0 | 1 |
| Feature showcase | 1–2 | 2 |
| Narrative animation | 3 | 1 |
| Personalization | 4 | 1 |
| Questionnaire | 5–12 | 8 |
| Sign Up | 13 | 1 |
| **Total** | **0–13** | **14 indexed, 13 content screens** |

Note: Screen indices 0–13 (14 values), but this represents 13 meaningful screens since the original 15-screen flow removed 2 screens (Kickstarter + discovery question) and the numbering is 0-based.

---

*Document based on interview conducted 2026-02-15. All decisions confirmed by product owner.*
