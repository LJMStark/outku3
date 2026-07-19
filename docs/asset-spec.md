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
- `petScene`, `reading`, `sunrise`, `sunset`, and `profile`: contextual artwork resolved
  through `CompanionCharacter.heroAssetName(variant:)`; character-specific fallbacks
  remain allowed where a dedicated image is not available.

### Asset naming contract

- Use lowercase kebab-case only.
- Keep the `.imageset` name and its contained image filename identical.
- Static companion art uses `<character>-<variant>`.
- Motion frames use `<character>-<artwork>-<motion>-<NN>`.
- Pet page art uses `<character>-pet-scene`; hardware scene previews use
  `display-scene-preview-<scene-id>`. Do not shorten either family to `scene-*`.
- Do not add source-tool version suffixes such as `-2` to shipping asset filenames.

## Multi-base identity model (character consistency)

Companions are **not** a single global sprite sheet. Each built-in IP has:

1. **L0 Identity card** — permanent visual markers shared across every asset.
2. **L1 Composition bases** — separate page/state illustrations (different pose,
   props, and background contracts). Never blend families.
3. **L2 Derivatives** — motion frames, crops, and profile variants that
   **edit-chain only from their own L1 base**.

### Joy L0 identity card (must hold on every Joy asset)

| Marker | Required look |
|--------|----------------|
| Species / silhouette | Small fennec-fox companion, tall ears, soft chibi proportions |
| Fur | Warm golden-brown; cream muzzle / belly |
| Ears | Dark brown outer backs, lighter pinkish inner ears |
| Forehead | Small diamond / lozenge mark |
| Scarf | Green triangular bandana, knot at the back |
| Tail (when visible) | Fluffy with pale / cream tip |
| Temperament | Glad, gentle, lightly odd — not manic, not hostile |
| Hard bans | No scarf recolor, no species swap, no photoreal drift, no text/logos |

Allowed to change across L1 bases: pose, expression, props (book), and
background contract (transparent vs grass vignette vs full mushroom scene).

### Joy L1 composition bases (do not cross-chain)

| Family | L1 base file | Freeze contract | L2 grows from this base only |
|--------|--------------|-----------------|------------------------------|
| `main` | `joy-main.png` | Sitting full body, transparent bg | `joy-main-idle-*`, `joy-main-greet-*`, `joy-profile`, preferred source for `joy-head` |
| `reading` | `joy-reading.png` | Grass + book + reading pose | `joy-reading-idle-*` (lock non-face to batch frame 01) |
| `pet-scene` | `joy-pet-scene.png` | Full mushroom-forest illustration | `joy-pet-scene-idle-*` (lock non-face to batch frame 01) |

**Cross-family rule:** never use `joy-main` as the reference when regenerating
reading/pet-scene art (or the reverse). Identity (L0) is shared; composition (L1)
is not.

### Edit-chain protocol

```
Keep this exact character identity: [Joy L0 markers].
Freeze completely: [this family's pose, props, background, framing, style words].
Change only: [single delta].
```

Always keep style words that match the **target L1** (main = cel sticker;
reading/pet-scene = storybook watercolor edges). Style may differ by family;
identity markers may not.

### Joy idle batch audit (2026-07-19)

Method: contact sheets in `docs/asset-review/joy-*-idle-audit-sheet.png`;
intra-batch pixel compare of each frame vs that batch's frame 01
(`docs/asset-review/joy-idle-intra-batch-audit-v1.json`).

| Family | L0 identity vs L1 | Lock-scene (vs batch 01) | Notes |
|--------|-------------------|--------------------------|--------|
| `main` | PASS | WARN | Idle frames intentionally change expression/pose (eyes/mouth); not face-only micro-motion. OK for onboarding energy; not a lock-scene batch. |
| `reading` | PASS | PASS | Outer region essentially identical across idle 01–08; motion concentrated in face. Meets subtle-cycle contract. |
| `pet-scene` | PASS | PASS | Forest/mushroom locked; only micro face deltas. Meets subtle-cycle contract. |

Raw pixel-diff vs original L1 hero files is high for reading/pet-scene because
export rescales and re-keys the sheet; **batch-internal** lock is the
acceptance criterion for ambient motion.

`joy-profile` (2026-07-19): dedicated imageset name for PetStatusView. Art is
currently the same pixels as approved `joy-main.png` (no AI redraw). All three
built-in IPs resolve profile via `heroAssetName(.profile)` →
`<rawValue>-profile` (`joy-profile` / `silas-profile` / `nova-profile`).

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
| `main` | Onboarding | `joy-main-idle-*`, `joy-main-greet-*` | intermittent idle + shared interaction one shot |
| `reading` | Home / Focus | `joy-reading-idle-*` | one shared fixed-ground batch, state-specific timing |
| `pet-scene` | Pet | `joy-pet-scene-idle-*` | one shared fixed-scene batch, state-specific timing |

Frames are 512 x 512 RGBA PNGs. `main` currently has four source drawings per
retained batch, `reading` has eight, and `pet-scene` has six. A page family stores
one batch and reuses it with different frame order and durations; it does not
duplicate identical PNGs for every semantic state. `main` and `reading` remove the
neutral sheet background; `pet-scene` preserves the complete mushroom illustration.
Silas, Nova, and custom companions remain static. Reduce Motion resolves directly
to the matching `main`, `reading`, or `pet-scene` artwork.

Playback uses per-frame durations instead of one fixed FPS. Ambient states hold
frame 01 for several seconds, use 0.10-0.16 second transition drawings, then settle
again. One-shot feedback lasts about 0.8-1.2 seconds and returns to ambient. The
player sleeps for the current frame duration rather than continuously refreshing
an unchanged hold frame.

AI-generated scenery is never allowed to animate. During export, every `reading`
frame is registered to frame 01 and only a small facial region is accepted; the
grass, body, book, and tail remain frame-01 pixels. The same rule applies to
`pet-scene`: the mushroom forest remains frame-01 pixels and only the fox face changes.
This follows Apple's requirement for consistent texture size and anchor placement
and avoids the disorienting background motion warned against in the Motion HIG.

Each family was generated with Image2 from exactly one current App reference:

- `joy-main-action-sheet-v2.png` references only `joy-main.png`.
- `joy-reading-action-sheet-v2.png` references only `joy-reading.png`.
- `joy-pet-scene-idle-sheet-v2.png` and `joy-pet-scene-react-sheet-v2.png` reference only
  `joy-pet-scene.png` and keep its complete composition.
- `joy-reading-subtle-sheet-v3.png` references only `joy-reading.png` and supplies
  the shared restrained eight-frame facial cycle for idle, focus, and celebrate.
- `joy-pet-scene-subtle-sheet-v3.png` references only `joy-pet-scene.png` and supplies the
  shared restrained six-frame facial cycle for idle and react while retaining the
  complete upper scene.

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
  docs/asset-sources/joy-pet-scene-react-sheet-v2.png \
  --character joy \
  --catalog KirolePackage/Sources/KiroleFeature/Resources/Media.xcassets \
  --review-output docs/asset-review/joy-pet-scene-react-contact-sheet-v2.png \
  --manifest-output docs/asset-review/joy-pet-scene-react-manifest-v2.json \
  --rows 2 --columns 2 --motions pet-scene-react \
  --layout single-motion --background preserve

python3 scripts/companion_action_sheet.py \
  docs/asset-sources/joy-reading-subtle-sheet-v3.png \
  --character joy \
  --catalog KirolePackage/Sources/KiroleFeature/Resources/Media.xcassets \
  --review-output docs/asset-review/joy-reading-idle-contact-sheet-v3.png \
  --manifest-output docs/asset-review/joy-reading-idle-manifest-v3.json \
  --rows 2 --columns 4 --motions reading-idle --layout single-motion \
  --extraction grid --placement cell --resampling lanczos --align-to-first \
  --motion-region 200,145,110,85 --motion-region-feather 3
```

The splitter validates deterministic naming, RGBA PNG format, 512 x 512 dimensions,
frame count and shared anchor metadata, then emits a review contact sheet and JSON
manifest. AI output still requires visual approval for identity and scene drift.

## Visual Style by L1 family

- Every derivative inherits the style and background contract of its own L1 base.
  Do not impose one global pixel-art or transparent-background rule across families.
- For Joy, `main` and its `head` / `profile` derivatives keep the approved cel-sticker
  treatment and transparent background.
- `reading` keeps its storybook watercolor edges, grass, book, pose, and framing.
  The grass vignette is intentional artwork, not a background-removal target.
- `pet-scene` keeps the complete storybook mushroom-forest composition. Its baked-in
  environment is required and must not be stripped or replaced.
- New Silas and Nova derivatives must match their own approved L1 reference rather
  than borrowing Joy's family-specific rendering style.
- No text, logos, signatures, halos, crosses, labels, or UI chrome.
- Keep comparable identity/card assets visually balanced so switching companions
  does not unexpectedly resize the layout.
- Character expressions should remain legible at their intended display size.

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

1. Generate or edit each variant with a raster image tool that matches the target
   L1 family's approved style and background contract above.
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
- [ ] Joy has the reviewed frame count declared above for every supported artwork/motion pair.
- [ ] Main, reading, and pet-scene frames retain their own original page composition.
- [ ] Pixels outside each declared motion region remain identical to frame 01.
- [ ] Ambient key poses hold longer than transition drawings; one shots return to ambient.
- [ ] Reduce Motion, Silas, Nova, and custom companion fallbacks remain static.
- [ ] Joy L0 identity markers hold on every Joy imageset (scarf, ears, forehead mark).
- [ ] New Joy derivatives edit-chain only from the matching L1 base (no cross-family).
- [ ] `heroAssetName(.profile)` returns `<rawValue>-profile` for Joy, Silas, and Nova.
- [ ] `joy-profile` / `silas-profile` / `nova-profile` imagesets each ship a PNG.
