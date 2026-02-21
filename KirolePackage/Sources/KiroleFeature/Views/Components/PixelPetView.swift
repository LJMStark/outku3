import SwiftUI

// MARK: - Pixel Pet Size

enum PixelPetSize {
    case small
    case medium
    case large

    var scale: CGFloat {
        switch self {
        case .small: return 0.5
        case .medium: return 0.75
        case .large: return 1.0
        }
    }

    var pixelSize: CGFloat {
        switch self {
        case .small: return 3
        case .medium: return 4
        case .large: return 5
        }
    }
}

// MARK: - Pet Animation State

enum PetAnimationState {
    case idle
    case celebrating
    case happy
    case sleepy
}

// MARK: - Pixel Pet View

struct PixelPetView: View {
    let size: PixelPetSize
    let animated: Bool
    var scene: PetScene? = nil
    var onTap: (() -> Void)? = nil

    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) var theme

    @State var animationPhase: Int = 0
    @State var bounceOffset: CGFloat = 0
    @State var celebrationScale: CGFloat = 1.0
    @State var celebrationRotation: Double = 0
    @State var showStars: Bool = false
    @State var starOffsets: [CGSize] = []
    @State var starOpacities: [Double] = []
    @State var isPressed: Bool = false

    // Idle micro-animation states
    @State var idleBreathScale: CGFloat = 1.0
    @State var idleSwayX: CGFloat = 0
    @State var isBlinking: Bool = false

    // Mood-specific animation states
    @State var sleepyBreathScale: CGFloat = 1.0
    @State var sleepyZOffset: CGFloat = 0
    @State var showZzz: Bool = false
    @State var excitedSparkles: Bool = false
    @State var excitedTremor: CGFloat = 0
    @State var sparkleOffsets: [CGSize] = []
    @State var sparkleOpacities: [Double] = []
    @State var missingLookDirection: CGFloat = 0
    @State var focusedPulse: CGFloat = 1.0
    @State var focusedLean: Double = 0
    @State var happyTailWag: Double = 0
    @State var sleepySink: CGFloat = 0

    // Interaction feedback states
    @State var showHearts: Bool = false
    @State var heartOffsets: [CGSize] = []
    @State var heartOpacities: [Double] = []
    @State var showNotes: Bool = false
    @State var noteOffsets: [CGSize] = []
    @State var noteOpacities: [Double] = []
    @State var longPressSquash: CGFloat = 1.0
    @State var showLoveBubble: Bool = false
    @State var loveBubbleOpacity: Double = 0

    // Scene animation states
    @State var cloudDriftX: CGFloat = 0
    @State var starTwinkle: [Double] = Array(repeating: 1.0, count: 8)
    @State var windowLightX: CGFloat = -50

    // Track whether continuous mood animation is already running
    @State var continuousMoodActive: Bool = false

    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    let moodTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    let blinkTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    // Stable star layout (computed once, not re-randomized per render)
    let starPositions: [CGSize] = (0..<8).map { _ in
        CGSize(width: CGFloat.random(in: -80...80), height: CGFloat.random(in: -80...(-20)))
    }
    let starSizes: [CGFloat] = (0..<8).map { _ in CGFloat.random(in: 2...4) }

    // 当前场景（优先使用传入的，否则使用 appState 中的）
    var currentScene: PetScene {
        scene ?? appState.pet.scene
    }

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2

            ZStack {
                sceneBackground
                    .frame(width: geometry.size.width, height: geometry.size.height)

                moodEffects
                interactionParticles

                if showStars {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: "star.fill")
                            .font(.system(size: 12 * size.scale))
                            .foregroundStyle(theme.colors.accent)
                            .offset(starOffsets.indices.contains(index) ? starOffsets[index] : .zero)
                            .opacity(starOpacities.indices.contains(index) ? starOpacities[index] : 0)
                    }
                }

                Ellipse()
                    .fill(shadowColor.opacity(0.15))
                    .frame(width: 60 * size.scale, height: 20 * size.scale)
                    .offset(y: 40 * size.scale + bounceOffset * 0.3)
                    .scaleEffect(
                        x: (celebrationScale * idleBreathScale) * (1.0 - abs(bounceOffset) * 0.003),
                        y: 1.0 - (celebrationScale - 1.0) * 0.5
                    )
                    .opacity(1.0 - abs(bounceOffset) * 0.008)

                PixelArtBody(
                    pixelSize: size.pixelSize,
                    primaryColor: petPrimaryColor,
                    secondaryColor: petSecondaryColor,
                    accentColor: theme.colors.accent,
                    animationPhase: animationPhase,
                    petForm: appState.pet.currentForm,
                    mood: appState.pet.mood,
                    isBlinking: isBlinking
                )
                .offset(x: missingLookDirection + idleSwayX + excitedTremor, y: bounceOffset + sleepySink)
                .scaleEffect(celebrationScale * sleepyBreathScale * focusedPulse * idleBreathScale * longPressSquash)
                .rotationEffect(.degrees(celebrationRotation + focusedLean + happyTailWag))
                .scaleEffect(isPressed ? 0.95 : 1.0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(x: centerX, y: centerY)
            .contentShape(Rectangle())
            .onTapGesture {
                triggerHappyAnimation()
                triggerTapParticles()
                onTap?()
            }
            .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isPressed = pressing
                    longPressSquash = pressing ? 0.92 : 1.0
                }
            }, perform: {
                triggerLoveBubble()
            })
        }
        .onReceive(timer) { _ in
            guard animated else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                animationPhase = (animationPhase + 1) % 4
                bounceOffset = animationPhase % 2 == 0 ? 0 : -5
            }
        }
        .onReceive(moodTimer) { _ in
            guard animated else { return }
            triggerMoodAnimation()
        }
        .onReceive(blinkTimer) { _ in
            guard animated else { return }
            if Int.random(in: 0...3) == 0 && !isBlinking {
                isBlinking = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isBlinking = false
                }
            }
        }
        .onChange(of: appState.pet.adventuresCount) { oldValue, newValue in
            if newValue > oldValue {
                triggerCelebrationAnimation()
            }
        }
        .onChange(of: appState.pet.mood) { _, _ in
            resetMoodAnimations()
            if animated {
                triggerMoodAnimation()
            }
        }
        .onAppear {
            if animated {
                triggerMoodAnimation()
                startIdleAnimations()
                startSceneAnimations()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        PixelPetView(size: .large, animated: true)
            .frame(height: 200)

        PixelPetView(size: .medium, animated: true)
            .frame(height: 150)

        PixelPetView(size: .small, animated: false)
            .frame(height: 100)
    }
    .padding()
    .background(Color(hex: "#FDF6E3"))
    .environment(AppState.shared)
    .environment(ThemeManager.shared)
}
