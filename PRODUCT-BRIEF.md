# Kirole Product Brief

**Date**: 2026-06-30
**Status**: GO (with gear-shift)
**Diagnostic Mode**: Product Lens / Founder Review

---

## 1. Who Is This For?

Deep knowledge workers who are daily bombarded by tasks, calendars, and notifications but refuse to be chained to their phone. They want a quiet, low-distraction companion that walks through the day with them -- not another tool that yells "just be more organized."

**Overlap with Inku**: High in hardware form-factor, but Kirole targets an emotional need ("someone watching over my day") rather than a functional need ("glanceable dashboard").

**Risk**: Will this audience pay hardware-price for "companionship feel"? Validation point = pre-sale conversion.

---

## 2. What's the Pain?

| Pain Point | Frequency | Severity |
|------------|-----------|----------|
| Phone is #1 enemy of focus (unlock for calendar -> scroll 30 min) | 10+/day | High |
| Existing task apps induce anxiety (more todos = more stress) | Daily | Medium-High |
| Loneliness during remote/solo work -- "nobody's here with me" | Persistent | Emotionally High |

**Current workarounds**: Paper calendars (no sync), Apple Watch (still phone ecosystem), Inku (Wi-Fi display, no pet/companion layer).

---

## 3. Why Now?

- Color E-ink panels (Spectra 6, 4-inch) at consumer-grade pricing
- LLMs make "event-reactive companion writing" feasible -- no more 200 canned lines
- Remote/hybrid work is the norm -- "quiet companionship" need is real
- Inku validated the "E-ink desk device" category (pre-sale stretch goals hit); Kirole adds the pet layer on top

---

## 4. The 10-Star Version

Boot the hardware. Joy/Silas/Nova already knows what you need to do today. While you focus, it silently switches to a "working alongside you" scene. When you finish a task, it says something warm, banks an energy bottle. By evening, it settles into a day-end summary -- like a small creature that witnessed your whole day. **You never touched your phone.**

---

## 5. The MVP (Current State)

**Score: 7/10 -- App-side near-complete, hardware-side blocked.**

### Done (App Side)

| Module | Status | Notes |
|--------|--------|-------|
| 3 built-in IP companions + custom companions | Done | Full prompt architecture + persona system |
| BLE protocol | Done | 176+ source files, heavy test coverage, v2.5.11 |
| DayPack generation + sync | Done | Throttle policy included |
| Focus mode + energy bottles + scene unlock | Done | Hardware reverse-trigger chain complete |
| Offline-first event replay | Done | `0x21 eventLogBatch` |
| Google/Apple Calendar sync | Done | |
| Notion/Taskade integration | Done | OAuth via Supabase Edge Functions |
| 14-screen onboarding | Done | |
| TestFlight pipeline | Done | Build 585, fastlane automated |
| Privacy (zero tracking) | Done | Verified: zero analytics SDKs |
| Custom companion avatar (on-device quantization) | Done | Photos never uploaded |

### Blocked / Not Started

| Module | Status | Blocker |
|--------|--------|---------|
| **Hardware production** | Draft v0.5 | HRD still Draft |
| **First BLE integration** | Partial | Build 572/573 audited; needs firmware team |
| **Subscription / payment** | Planned | Zero code, not even StoreKit imported |
| **Family Controls** | Submitted | Waiting Apple approval |
| **App Store launch** | Not started | Debug gates must be restored (573 keep-alive etc.) |

---

## 6. Anti-Goals (Explicitly NOT Building)

Product red lines are unusually clear (a strength):

- **No multi-device**: One account = one active device
- **No task management**: Tasks/events are prompt context only
- **No Apple Watch / Mac**: E-ink is the only daily surface
- **No family sharing / multi-user**
- **No AI task breakdown / nagging reminders**
- **No analytics / tracking**

---

## 7. How Do You Know It's Working?

**Current problem: Zero observability.** No user behavior data, retention metrics, or usage stats. Consistent with the "zero tracking" positioning, but means:

| Metric | Current State | Suggestion |
|--------|---------------|------------|
| DAU / Retention | Unmeasurable | Hardware-side anonymous aggregation (total focus minutes / tasks completed via BLE backfill) without touching privacy promise |
| Focus duration | App-local only, not reported | Core value metric if subscription launches |
| Companion dialogue triggers | Unmeasurable | |
| Pre-sale conversion | Not started | **North star metric = paid pre-sale count** |

---

## 8. Product-Market Fit Score: 5/10

| Dimension | Score | Reasoning |
|-----------|-------|-----------|
| Usage growth | 2/10 | No external users; TestFlight internal only |
| Retention signals | N/A | No data |
| Revenue signals | 1/10 | Zero code, zero pricing, zero pre-sale page |
| Competitive moat | 7/10 | BLE reverse-trigger + pet IP + privacy narrative + offline-first = structurally impossible for Inku |
| Product completeness | 6/10 | App-side high polish, but hardware IS the product and hardware is still Draft |

---

## 9. The One Thing That Would 10x This

**Not more App features. Get the first batch of working hardware into 10 real people's hands.**

The biggest risk is not code quality (176 files, 45 test suites, strict concurrency -- solid). It is:

1. **Hardware timeline is uncontrollable** -- HRD is v0.5 Draft, firmware team cadence unclear
2. **Zero external validation** -- all "is this product good" judgments are founder's own, no signal from paying users
3. **Subscription monetization not started** -- "plan to do subscription" but zero StoreKit code, zero pricing experiments

---

## 10. Things Being Built That Don't Matter Yet

| Item | Assessment |
|------|------------|
| Custom companion avatar BLE push (0x15) | Hardware isn't produced; on-device pixel push can wait |
| Notion/Taskade integration | Does the core user actually use Notion? Google Calendar covers 80% |
| Full 3-IP prompt system | Built, but Joy alone suffices for MVP launch |
| Scene unlock / energy bottles | Retention mechanics designed, but no users to retain |

**These aren't wrong -- they're early.** App-side features are ahead of hardware and market validation.

---

## 11. Verdict: GO -- But Shift Gears

Product direction is right (hardware companionship, not efficiency tool). Technical execution is solid. Differentiation narrative is compelling.

**But the current mode = "infinitely polishing the App."** 292 commits in 2 months, build 585, nearly all invested in App + BLE protocol. Hardware is still a draft.

### Recommended Priority Shift

| Priority | Action | Why |
|----------|--------|-----|
| **P0** | Hardware -> get dev board / EVT | Only blocker for the actual product |
| **P1** | Pre-sale page / landing page | Validate "someone will pay for this" -- even a Notion page + Stripe link |
| **P2** | StoreKit integration | Subscription is the business model core; can't wait until launch eve |
| **P3** | Freeze App new features | Current App exceeds MVP needs; shift energy from App to hardware + market validation |

---

## 12. Strengths to Protect

1. **Privacy narrative is a real moat**: Zero analytics SDKs + photos never uploaded + hardware doesn't ping = verifiable promise, not marketing spin. Against Inku (PostHog + Statsig + Sentry), this is genuine moral high ground. But it must become externally perceivable, not buried in code.

2. **Anti-todo positioning is sharp**: "Walks through your day with you, doesn't manage your todos" is a clear, memorable wedge against every productivity app.

3. **Technical depth**: BLE protocol at v2.5.11 with simulation tests, strict concurrency, prompt sanitization -- the engineering foundation is production-grade. This is rare for a pre-hardware startup.

---

## 13. Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Hardware delay pushes past market window (Inku ships first) | High | High | Parallel-path: launch App-only "companion mode" (phone widget) as interim validation |
| Subscription model rejected by users ("I already bought the hardware") | Medium | High | Test pricing before hardware ships; consider hardware margin as primary revenue |
| Feature-complete trap: keep building App instead of shipping | High | Medium | This brief is the intervention; freeze non-essential App work |
| Single founder burnout | Medium | Critical | 292 commits in 2 months is unsustainable; prioritize ruthlessly |

---

*Generated by Product Lens diagnostic. Next steps: `product-capability` for implementation-ready spec if proceeding with P1 (pre-sale page) or P2 (StoreKit).*
