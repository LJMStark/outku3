# Brand Asset Specification

This document defines the companion character art consumed by SwiftUI via
`Image(name, bundle: .module)` from
`KirolePackage/Sources/KiroleFeature/Resources/Media.xcassets/`.

## Context

Kirole has three product IP companions defined in
`KirolePackage/Sources/KiroleFeature/Models/CompanionCharacter.swift`.
`CompanionCharacter` is the user-facing source of truth, and
`resolvedStyle` maps each character to the matching `CompanionStyle`.

| Character | `resolvedStyle` | Product Role | Voice Anchor |
|-----------|-----------------|--------------|--------------|
| Joy | `.joy` | Gladness | Less anxiety, more work delight and daily beauty |
| Silas | `.silas` | Loving care | Calm-tech presence with Christian-shaped imagery |
| Nova | `.nova` | Temperance / discipline | Signal over noise, time protection, core action |

`Nook` and the old `companion` / `slacker` / `challenger` mappings are retired.
Do not add new assets, fallbacks, tests, or documentation that depend on those
old names.

Each built-in character may provide these static variants:

- `main`: full body, used in onboarding hero shots and character cards.
- `head`: cropped head or head-and-shoulders, used as avatar-style artwork.
- `scene`, `reading`, `sunrise`, `sunset`, and `profile`: contextual artwork resolved
  through `CompanionCharacter.heroAssetName(variant:)`; character-specific fallbacks
  remain allowed where a dedicated image is not available.

## Deliverables

The required identity baseline is six PNG assets, each in its own `.imageset`:

| File | Dimensions | Notes |
|------|------------|-------|
| `joy-main.imageset/joy-main.png` | 512 x 512 px | full body, transparent background |
| `joy-head.imageset/joy-head.png` | 256 x 256 px | head or head-and-shoulders, transparent background |
| `silas-main.imageset/silas-main.png` | 512 x 512 px | full body, transparent background |
| `silas-head.imageset/silas-head.png` | 256 x 256 px | head or head-and-shoulders, transparent background |
| `nova-main.imageset/nova-main.png` | 512 x 512 px | full body, transparent background |
| `nova-head.imageset/nova-head.png` | 256 x 256 px | head or head-and-shoulders, transparent background |

Each `Contents.json` should use a universal 1x image slot. Higher-scale variants
are optional only if the art direction needs crisper Retina scaling.

## App Motion Pilot (Joy)

Joy's current static illustrations are three separate page/state references. They
must never be blended into one generic character-only animation family:

| Artwork family | App surface | Motion files | Playback |
|----------------|-------------|--------------|----------|
| `main` | Onboarding | `joy-main-idle-*`, `joy-main-greet-*`, `joy-main-react-*` | idle loop + one shots |
| `reading` | Home / Focus | `joy-reading-idle-*`, `joy-reading-focus-*`, `joy-reading-celebrate-*` | ambient + completion one shot |
| `scene` | Pet | `joy-scene-idle-*`, `joy-scene-react-*` | full-scene loop + tap one shot |

Each motion has four 512 x 512 RGBA PNG frames at 6.67 FPS. `main` and `reading`
remove the neutral sheet background; `scene` intentionally preserves the complete
mushroom illustration. Silas, Nova, and custom companions remain static. Reduce
Motion resolves directly to the matching `main`, `reading`, or `scene` artwork.
Ambient `idle` and `focus` playback returns to frame 01 and holds it for eight
ticks (1.2 seconds) after every four-frame movement, so the companion stays calm
instead of moving continuously. One-shot motions play their four frames once.

Each family was generated with Image2 from exactly one current App reference:

- `joy-main-action-sheet-v2.png` references only `joy-main.png`.
- `joy-reading-action-sheet-v2.png` references only `joy-reading-2.png`.
- `joy-scene-idle-sheet-v2.png` and `joy-scene-react-sheet-v2.png` reference only
  `joy-scene.png` and keep its complete composition.

Example regeneration commands:

```bash
python3 scripts/companion_action_sheet.py \
  docs/asset-sources/joy-main-action-sheet-v2.png \
  --character joy \
  --catalog KirolePackage/Sources/KiroleFeature/Resources/Media.xcassets \
  --review-output docs/asset-review/joy-main-contact-sheet-v2.png \
  --manifest-output docs/asset-review/joy-main-manifest-v2.json \
  --rows 3 --columns 4 \
  --motions main-idle,main-greet,main-react \
  --extraction components --placement trim --padding 24

python3 scripts/companion_action_sheet.py \
  docs/asset-sources/joy-scene-react-sheet-v2.png \
  --character joy \
  --catalog KirolePackage/Sources/KiroleFeature/Resources/Media.xcassets \
  --review-output docs/asset-review/joy-scene-react-contact-sheet-v2.png \
  --manifest-output docs/asset-review/joy-scene-react-manifest-v2.json \
  --rows 2 --columns 2 --motions scene-react \
  --layout single-motion --background preserve
```

The splitter validates deterministic naming, RGBA PNG format, 512 x 512 dimensions,
frame count and shared anchor metadata, then emits a review contact sheet and JSON
manifest. AI output still requires visual approval for identity and scene drift.

## Visual Style

- Pixel art that matches the existing companion sprite density.
- Transparent background; characters composite over app theme colors at runtime.
- No text, logos, signatures, halos, crosses, labels, UI chrome, or baked-in
  backdrop.
- Consistent silhouette weight across the three characters so switching IPs does
  not visually resize the layout.
- Character expression should read clearly at small avatar sizes.

## Per-Character Direction

### Joy

- Golden-brown fox with curious big eyes, a fluffy tail, and a green scarf.
- Friendly, playful, comfortable, lightly odd.
- Reads as gladness: less anxious, more able to notice pleasure inside ordinary
  work and daily life.
- Avoid manic energy, mascot grin overload, or childish toy styling.

### Silas

- Calm grey-brown companion with wise eyes and a quiet presence.
- Warm, grounded, caring, still-screen friendly.
- Reads as loving care: work feels held, meaningful, and spiritually steady.
- Christian influence should stay in mood and imagery, not literal religious
  iconography unless specifically approved.
- Avoid the retired slacker direction: no sarcastic posture, no lazy trope, no
  half-lidded boredom.

### Nova

- Blue-grey wolf with sharp confident eyes and a cool, composed stance.
- Minimal, disciplined, focused, professional.
- Reads as temperance: filters noise, protects time, and points toward the core
  action.
- Avoid hostility or aggression; Nova should feel precise, not angry.

## Generation Workflow

1. Generate or edit each variant with a raster image tool that can match the
   project pixel-art style.
2. Keep filenames and imageset names exactly aligned with
   `CompanionCharacter.heroAssetName(variant:)`.
3. Submit each generated PNG to the user for review before committing.
4. Place approved files under `Resources/Media.xcassets/` and update the matching
   `Contents.json`.
5. After asset changes, run the package tests and visually check onboarding /
   character switching in the simulator.

For action sheets, also run `python3 -m unittest
scripts/tests/test_companion_action_sheet.py` and inspect the generated contact
sheet before shipping.

## Wiring Notes

- Onboarding and settings should load character images through
  `CompanionCharacter.heroAssetName(variant:)`.
- Animated App surfaces resolve semantic motions through
  `CompanionAnimationCatalog` and render them with `CompanionAnimationView`.
- Do not put animation asset names directly in feature views.
- Pre-selection onboarding pages default to `CompanionCharacter.joy`.
- Character switching must propagate to later onboarding pages and settings
  without hardcoded image names.

## Acceptance Checklist

- [ ] All six `.imageset` directories exist with PNG + `Contents.json`.
- [ ] Joy, Silas, and Nova match the product IP descriptions above.
- [ ] User has signed off on each character's visual direction.
- [ ] No active source file references retired `nook-main` or `nook-head` assets.
- [ ] `CompanionCharacter.allCases` remains exactly `[.joy, .silas, .nova]`.
- [ ] Walk through onboarding character selection; subsequent pages reflect the
      selected character.
- [ ] Joy has exactly four reviewed frames for every supported artwork/motion pair.
- [ ] Main, reading, and scene frames retain their own original page composition.
- [ ] Reduce Motion, Silas, Nova, and custom companion fallbacks remain static.
