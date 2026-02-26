# Refactor Onboarding Spec

## Overview
Refactor the existing `OnboardingView` to use a cinematic, conversational, and highly animated approach, replacing the standard `TabView` pagination.

## Core Pillars
1.  **Cinematic (Visual)**: Fluid transitions using `matchedGeometryEffect`. No hard cuts or standard push navigations. Deep, atmospheric backgrounds.
2.  **Conversational (Narrative)**: The user interacts with the "spirit" of the pet. Text appears character-by-character (typewriter effect). User inputs are "responses" to the pet.
3.  **Shadow Reveal (The "Wow" Moment)**: The pet remains a mystery (animated silhouette/shadow) until the naming ceremony, where it bursts into light/color.
4.  **Hardware Last**: Peripheral setup is a post-climax utility step.

## Flow States

1.  **Awakening (Intro)**
    -   **Visual**: Dark, misty background. A pulsing light or subtle shadow in the center.
    -   **Action**: User taps to "wake" or "begin".
    -   **Transition**: The light expands to become the background aura.

2.  **Connection (Conversation)**
    -   **Visual**: The pet is a silhouette (Shadow Mode) in the center.
    -   **Interaction**:
        -   Pet: "Where am I? ... Oh, hello." (Typewriter text)
        -   User: [Selects options like "Hi there", "Who are you?"]
        -   Pet: "I'm... I'm looking for a friend. Some call me a Cat, some a Dragon..."
    -   **Form Selection**: Integrated here. "What do I look like to you?"
        -   Options: Icons of Cat, Dog, Dragon, etc.
        -   Selection updates the Silhouette immediately (morphing shape).

3.  **Naming (The Bond)**
    -   **Interaction**:
        -   Pet: "I like this form. Do you have a name for me?"
    -   **Input**: Floating text field.
    -   **Action**: User types name and confirms.

4.  **The Reveal (Climax)**
    -   **Visual**:
        -   The Silhouette glimmers (shader effect or overlay opacity).
        -   A blast of light (scale effect + bloom).
        -   The **Real Pet** illustration replaces the silhouette.
        -   Background changes to the Pet's color theme.
    -   **Pet**: "I am [Name]! I'm so happy to meet you!"

5.  **Sanctuary (Setup)**
    -   **Context**: "Now, let's set up our home."
    -   **Steps**:
        -   Permissions (Notifications - "To hear me")
        -   Calendar (Google/Apple - "To help you")
        -   Hardware Pairing ("To be with you always") - *Replaces the 'ConnectAccountPage' logic but placed end-of-flow.*

6.  **Timeline (End)**
    -   Transition to Home View.

## Technical Components

### `OnboardingFlowManager` (Observable)
-   Manages `currentStep` enum.
-   Manages `animationNamespace`.
-   Handles persistence of onboarding data.

### Views
-   `CinematicBackground`: ZStack with gradients/blurs that animate based on state.
-   `DialogBubble`: Styled text view with typewriter effect.
-   `ChoicePill`: Interactive button for user responses.
-   `MorphingPetView`:
    -   State: `isHidden` -> `isShadow` -> `isRevealed`.
    -   Uses `matchedGeometryEffect` to stay centered but change size/presence.

## Animation Specs
-   **Text**: Character delay 0.03s. Haptic feedback on every 3rd character (light).
-   **Transitions**: Spring animations (damping: 0.7, response: 0.6).
-   **Reveal**: 
    -   Flash White Overlay: 0.1s -> 0.0s
    -   Scale Up: 0.8 -> 1.1 -> 1.0
    -   Particles: Usage of `CAEmitterLayer` or SwiftUI `KeyframeAnimator` for sparks.
