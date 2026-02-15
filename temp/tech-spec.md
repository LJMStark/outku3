# Inku App Onboarding - Technical Specification

## Component Inventory

### shadcn/ui Components (Built-in)
- `Button` - Primary and secondary buttons
- `Card` - Option cards, dialog boxes
- `Input` - Email input field
- `Progress` - Progress bar for questionnaire
- `RadioGroup` - Single select options
- `Checkbox` - Multi-select options
- `Label` - Form labels

### Custom Components to Build

1. **OnboardingContainer**
   - Full-screen wrapper with safe area handling
   - Page transition management

2. **StatusBar**
   - iOS-style status bar (time, signal, battery)
   - Speaker icon toggle

3. **ProgressIndicator**
   - Dot-based progress (4 dots)
   - Line-based progress (questionnaire)

4. **PixelCharacter**
   - Animated pixel art character
   - Different poses/outfits
   - Bounce animation

5. **DialogBox**
   - Speech bubble style
   - Typewriter text effect

6. **FloatingIcons**
   - Rotating container with app icons
   - Individual floating animations

7. **OptionCard**
   - Selectable card with icon
   - Selected state styling
   - Hover effects

8. **ThemePreview**
   - Color scheme preview card
   - Selection state

9. **AvatarSelector**
   - Horizontal scrolling avatar list
   - Selection highlight

10. **TypewriterText**
    - Character-by-character reveal
    - Cursor blink

11. **BeforeAfterCard**
    - Blur to clear transition
    - Toggle animation

## Animation Implementation Table

| Animation | Library | Implementation Approach | Complexity |
|-----------|---------|------------------------|------------|
| Page transitions | Framer Motion | AnimatePresence + motion.div with slide/fade | Medium |
| Button hover/press | Framer Motion | whileHover, whileTap props | Low |
| Character idle bounce | Framer Motion | animate prop with repeat | Low |
| Floating icons rotation | CSS Animation | @keyframes rotate, infinite | Low |
| Icon floating (up/down) | Framer Motion | animate with y offset, stagger | Medium |
| Dialog box stagger | Framer Motion | staggerChildren in variants | Medium |
| Typewriter effect | Custom Hook | useState + useEffect with interval | Medium |
| Text reveal (Page 6) | Framer Motion | staggerChildren + y/opacity | Medium |
| Progress bar fill | Framer Motion | animate width on page change | Low |
| Card selection | Framer Motion | layoutId for smooth transitions | Medium |
| Before/After blur | CSS + Framer | filter transition + motion | Medium |
| Avatar scroll | CSS | overflow-x: auto, snap points | Low |
| Arrow pulse | CSS Animation | @keyframes pulse | Low |

## Animation Library Choices

### Primary: Framer Motion
**Rationale:**
- Best React integration for declarative animations
- AnimatePresence for exit animations
- Gesture support (hover, tap)
- Layout animations
- Stagger support

### Secondary: CSS Animations
**Use for:**
- Simple infinite loops (rotation, pulse)
- Performance-critical animations
- Background effects

## Project File Structure

```
src/
├── components/
│   ├── ui/                    # shadcn components
│   ├── OnboardingContainer.tsx
│   ├── StatusBar.tsx
│   ├── ProgressIndicator.tsx
│   ├── PixelCharacter.tsx
│   ├── DialogBox.tsx
│   ├── FloatingIcons.tsx
│   ├── OptionCard.tsx
│   ├── ThemePreview.tsx
│   ├── AvatarSelector.tsx
│   ├── TypewriterText.tsx
│   └── BeforeAfterCard.tsx
├── pages/
│   ├── WelcomePage.tsx
│   ├── FeatureCalendarPage.tsx
│   ├── FeatureFocusPage.tsx
│   ├── PersonalizationPage.tsx
│   ├── KickstarterPage.tsx
│   ├── TextAnimationPage.tsx
│   ├── QuestionnairePage.tsx
│   └── SignUpPage.tsx
├── hooks/
│   ├── useTypewriter.ts
│   ├── useOnboardingState.ts
│   └── usePageTransition.ts
├── types/
│   └── onboarding.ts
├── data/
│   └── questions.ts
├── assets/
│   └── characters/            # Pixel character images
├── App.tsx
├── main.tsx
└── index.css
```

## Dependencies to Install

```bash
# Animation
npm install framer-motion

# Icons
npm install lucide-react

# Fonts (optional - for pixel aesthetic)
npm install @fontsource/press-start-2p
```

## State Management

### Onboarding State (useOnboardingState hook)
```typescript
interface OnboardingState {
  currentPage: number;
  answers: {
    discoverySource?: string;
    userTypes?: string[];
    struggles?: string;
    scheduleFullness?: string;
    schedulePredictability?: string;
    calendarUsage?: string;
    taskTracking?: string;
    timeControl?: string;
  };
  selectedTheme?: string;
  selectedAvatar?: string;
}
```

## Page Flow

```
Page 1: WelcomePage
  ↓
Page 2: FeatureCalendarPage
  ↓
Page 3: FeatureFocusPage
  ↓
Page 4: PersonalizationPage
  ↓
Page 5: KickstarterPage
  ↓
Page 6: TextAnimationPage
  ↓
Page 7-14: QuestionnairePage (dynamic based on question index)
  ↓
Page 15: SignUpPage
```

## Responsive Breakpoints

- Mobile: 320px - 428px (primary target)
- Tablet: 429px - 768px (scaled up)
- Desktop: 769px+ (centered mobile frame)

## Performance Considerations

1. **Image Optimization**
   - Use WebP format for characters
   - Lazy load off-screen images
   - Proper sizing (2x for retina)

2. **Animation Performance**
   - Use transform and opacity only
   - Add will-change for heavy animations
   - Reduce motion for accessibility

3. **Bundle Size**
   - Tree-shake Framer Motion
   - Import only needed Lucide icons

## Accessibility

1. **Reduced Motion**
   - Respect prefers-reduced-motion
   - Disable floating animations
   - Instant transitions

2. **Focus Management**
   - Visible focus indicators
   - Logical tab order
   - Focus trap in modals

3. **Screen Readers**
   - Proper heading hierarchy
   - ARIA labels for icons
   - Live regions for dynamic content
