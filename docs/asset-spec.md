# Brand Asset Specification (P0.6)

This document defines the AI-generated character art that replaces the
`inku-main` / `inku-head` / `blue-monster` placeholders currently used in
onboarding and the pet UI. Output is consumed by SwiftUI via
`Image(name, bundle: .module)` from `Resources/Media.xcassets/Pets/`.

## Context

Kirole has 3 companion characters defined in
`KirolePackage/Sources/KiroleFeature/Models/CompanionCharacter.swift`:

| Character | Persona (`resolvedStyle`) | Vibe |
|-----------|---------------------------|------|
| Nook      | `companion`               | warm, supportive, gentle |
| Silas     | `slacker`                 | laid-back, sarcastic, dry humor |
| Nova      | `challenger`              | energetic, motivating, sharp |

Each character needs **two variants**: a full-body `main` (used in onboarding
hero shots and the home pet view) and a cropped `head` (used as an avatar in
the sign-up screen and inline dialog bubbles).

## Deliverables

Six PNG assets, each in its own `.imageset` under
`KirolePackage/Sources/KiroleFeature/Resources/Media.xcassets/Pets/`:

| File | Dimensions | Notes |
|------|------------|-------|
| `nook-main.imageset/nook-main.png`   | 512 × 512 px | full body, transparent background |
| `nook-head.imageset/nook-head.png`   | 256 × 256 px | head + shoulders, transparent background |
| `silas-main.imageset/silas-main.png` | 512 × 512 px | full body, transparent background |
| `silas-head.imageset/silas-head.png` | 256 × 256 px | head + shoulders, transparent background |
| `nova-main.imageset/nova-main.png`   | 512 × 512 px | full body, transparent background |
| `nova-head.imageset/nova-head.png`   | 256 × 256 px | head + shoulders, transparent background |

Each `Contents.json` should follow the existing `inku-main.imageset` template
(1x slot only is fine for pixel art; @2x / @3x optional but encouraged for
crisp scaling on Retina displays).

## Visual Style

- **Pixel art** matching the existing `inku-main` asset's pixel density
  (~64-pixel-tall sprite scaled to 512 × 512).
- **Limited palette**: align with `ThemeManager.colors.accent` family —
  warm coral / desaturated teal / soft violet are the three theme accents.
- **Transparent background** — characters composite over theme colors at
  runtime; do not bake in any backdrop.
- **No text, logos, or signatures** baked into the art.
- **Consistent silhouette weight** across the three characters so the pet
  size never visually jumps between selections.

## Per-Character Direction

### Nook (warm companion)
- Round, plush, mochi-like body. Pale cream + soft coral palette.
- Cheerful neutral face with subtle blush; closed-eyes "happy" expression
  acceptable.
- Reads as the "default safe choice" — the grandparent's-cat energy.

### Silas (slacker)
- Slouched posture, half-lidded eyes. Cool greys + dusty teal palette.
- Possibly holding a tiny prop (mug, blanket corner) but optional.
- Reads as "perpetually unbothered" — never aggressive, just chill.

### Nova (challenger)
- Upright, alert posture. Saturated violet + electric yellow accents.
- Bright eyes, slight smirk — the "your sparring partner" energy.
- Avoid looking angry; the vibe is competitive, not hostile.

## Generation Workflow

1. Use `baoyu-image-gen` (or any text-to-image tool capable of pixel art) to
   generate each variant. Reference the existing `inku-main.png` to match
   pixel density.
2. Submit each generated PNG to the user for review **before** committing.
3. On approval, place the file under the matching imageset directory and
   update `Contents.json` to reference the filename.
4. Flip the fallbacks in
   `CompanionCharacter.heroAssetName(variant:)` from the placeholder
   `"inku"` base to `"nook"` / `"silas"` / `"nova"`.

## Wiring Plan (deferred until assets exist)

Six onboarding files currently hardcode placeholder names. After assets
land, swap to the helper so character switching propagates everywhere:

- `Views/Onboarding/Pages/WelcomePage.swift:43`
- `Views/Onboarding/Pages/FeatureCalendarPage.swift:70`
- `Views/Onboarding/Pages/FeatureFocusPage.swift:18` (currently `blue-monster`)
- `Views/Onboarding/Pages/QuestionnairePage.swift:87`
- `Views/Onboarding/Pages/PersonalizationPage.swift:65`
- `Views/Onboarding/Pages/SignUpPage.swift:57` (uses `inku-head`)

Pre-character-selection pages (Welcome, FeatureCalendar, FeatureFocus,
TextAnimation) should default to `CompanionCharacter.nook` since Nook is
positioned as the safe default in `OnboardingProfile`.

## Acceptance Checklist

- [ ] All six `.imageset` directories exist with PNG + Contents.json.
- [ ] User has signed off on each character's visual direction.
- [ ] `CompanionCharacter.heroAssetName(variant:)` no longer falls back to
      `"inku"` for any character.
- [ ] `grep -rn "inku-main\|inku-head\|blue-monster" KirolePackage/Sources/`
      returns zero hits inside `Views/Onboarding/`.
- [ ] Walk through onboarding switching characters at the personalization
      step — the hero asset on every subsequent page reflects the choice.
