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
    var onTap: (() -> Void)? = nil

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var animationPhase: Int = 0
    @State private var bounceOffset: CGFloat = 0
    @State private var celebrationScale: CGFloat = 1.0
    @State private var celebrationRotation: Double = 0
    @State private var showStars: Bool = false
    @State private var starOffsets: [CGSize] = []
    @State private var starOpacities: [Double] = []
    @State private var isPressed: Bool = false

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2

            ZStack {
                // Celebration stars
                if showStars {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: "star.fill")
                            .font(.system(size: 12 * size.scale))
                            .foregroundStyle(theme.colors.accent)
                            .offset(starOffsets.indices.contains(index) ? starOffsets[index] : .zero)
                            .opacity(starOpacities.indices.contains(index) ? starOpacities[index] : 0)
                    }
                }

                // Shadow
                Ellipse()
                    .fill(theme.colors.primaryText.opacity(0.1))
                    .frame(width: 60 * size.scale, height: 20 * size.scale)
                    .offset(y: 40 * size.scale + bounceOffset * 0.3)
                    .scaleEffect(x: celebrationScale, y: 1.0 - (celebrationScale - 1.0) * 0.5)

                // Pet body
                PixelArtBody(
                    pixelSize: size.pixelSize,
                    primaryColor: petPrimaryColor,
                    secondaryColor: petSecondaryColor,
                    accentColor: theme.colors.accent,
                    animationPhase: animationPhase,
                    petForm: appState.pet.currentForm
                )
                .offset(y: bounceOffset)
                .scaleEffect(celebrationScale)
                .rotationEffect(.degrees(celebrationRotation))
                .scaleEffect(isPressed ? 0.95 : 1.0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .position(x: centerX, y: centerY)
            .contentShape(Rectangle())
            .onTapGesture {
                triggerHappyAnimation()
                onTap?()
            }
            .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }, perform: {})
        }
        .onReceive(timer) { _ in
            guard animated else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                animationPhase = (animationPhase + 1) % 4
                bounceOffset = animationPhase % 2 == 0 ? 0 : -5
            }
        }
        .onChange(of: appState.pet.adventuresCount) { oldValue, newValue in
            if newValue > oldValue {
                triggerCelebrationAnimation()
            }
        }
    }

    // MARK: - Animations

    private func triggerCelebrationAnimation() {
        // Jump animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
            bounceOffset = -25
            celebrationScale = 1.15
        }

        // Show stars
        showStars = true
        starOffsets = (0..<5).map { _ in
            CGSize(width: CGFloat.random(in: -40...40), height: CGFloat.random(in: -50...(-20)))
        }
        starOpacities = Array(repeating: 1.0, count: 5)

        // Animate stars outward and fade
        withAnimation(.easeOut(duration: 0.6)) {
            starOffsets = starOffsets.map { offset in
                CGSize(width: offset.width * 2, height: offset.height * 1.5)
            }
        }

        withAnimation(.easeOut(duration: 0.8)) {
            starOpacities = Array(repeating: 0.0, count: 5)
        }

        // Return to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                bounceOffset = 0
                celebrationScale = 1.0
            }
        }

        // Hide stars
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showStars = false
        }
    }

    private func triggerHappyAnimation() {
        // Quick wiggle animation
        withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
            celebrationRotation = 8
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                celebrationRotation = -8
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.3)) {
                celebrationRotation = 5
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                celebrationRotation = 0
            }
        }

        // Small bounce
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            bounceOffset = -10
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                bounceOffset = 0
            }
        }
    }

    private var petPrimaryColor: Color {
        switch appState.pet.currentForm {
        case .cat:
            return Color(hex: "#FFB366") // Orange for cat
        case .dog:
            return Color(hex: "#C4A484") // Brown for dog
        case .bunny:
            return Color(hex: "#F5F5DC") // Cream for bunny
        case .bird:
            return Color(hex: "#87CEEB") // Sky blue for bird
        case .dragon:
            return Color(hex: "#9370DB") // Purple for dragon
        }
    }

    private var petSecondaryColor: Color {
        switch appState.pet.currentForm {
        case .cat:
            return Color(hex: "#FF8C00") // Darker orange
        case .dog:
            return Color(hex: "#8B7355") // Darker brown
        case .bunny:
            return Color(hex: "#FFB6C1") // Pink for bunny ears
        case .bird:
            return Color(hex: "#4682B4") // Steel blue
        case .dragon:
            return Color(hex: "#6A5ACD") // Slate blue
        }
    }
}

// MARK: - Pixel Art Body

struct PixelArtBody: View {
    let pixelSize: CGFloat
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    let animationPhase: Int
    let petForm: PetForm

    // 0 = transparent, 1 = primary, 2 = secondary, 3 = accent, 4 = white, 5 = black, 6 = highlight
    private var pixelPattern: [[Int]] {
        var pattern = basePatternForForm(petForm)

        // Apply blink animation every 4th phase
        if animationPhase == 3 {
            pattern = applyBlinkAnimation(to: pattern, form: petForm)
        }

        return pattern
    }

    // MARK: - Pet Form Patterns

    private func basePatternForForm(_ form: PetForm) -> [[Int]] {
        switch form {
        case .cat:
            return catPattern
        case .dog:
            return dogPattern
        case .bunny:
            return bunnyPattern
        case .bird:
            return birdPattern
        case .dragon:
            return dragonPattern
        }
    }

    // Cat: Pointed ears, whiskers, sleek body
    private var catPattern: [[Int]] {
        [
            [0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0],  // Row 0 - ear tips
            [0, 0, 2, 1, 2, 0, 0, 0, 0, 0, 0, 2, 1, 2, 0, 0],  // Row 1 - ears
            [0, 0, 2, 1, 1, 2, 2, 2, 2, 2, 2, 1, 1, 2, 0, 0],  // Row 2 - head top
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 3 - head
            [0, 0, 2, 1, 5, 4, 1, 1, 1, 1, 5, 4, 1, 2, 0, 0],  // Row 4 - eyes top
            [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0],  // Row 5 - eyes bottom
            [0, 2, 2, 1, 1, 1, 1, 3, 3, 1, 1, 1, 1, 2, 2, 0],  // Row 6 - whiskers + nose
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 7 - mouth
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 8 - neck
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 9 - body top
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 10 - body
            [0, 0, 2, 1, 1, 1, 6, 1, 1, 6, 1, 1, 1, 2, 0, 0],  // Row 11 - belly
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2],  // Row 12 - body + tail
            [0, 0, 0, 2, 1, 2, 0, 0, 0, 0, 2, 1, 2, 0, 1, 2],  // Row 13 - feet + tail
            [0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 2, 0, 0, 2, 0],  // Row 14 - paws
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // Row 15 - empty
        ]
    }

    // Dog: Floppy ears, happy tongue, wagging tail
    private var dogPattern: [[Int]] {
        [
            [0, 0, 2, 2, 0, 0, 0, 0, 0, 0, 0, 0, 2, 2, 0, 0],  // Row 0 - ear tops
            [0, 2, 1, 1, 2, 0, 0, 0, 0, 0, 0, 2, 1, 1, 2, 0],  // Row 1 - floppy ears
            [0, 2, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 2, 0],  // Row 2 - ears + head
            [0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0],  // Row 3 - head
            [0, 0, 2, 1, 5, 4, 1, 1, 1, 1, 5, 4, 1, 2, 0, 0],  // Row 4 - eyes
            [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0],  // Row 5 - eyes
            [0, 0, 2, 1, 1, 1, 1, 5, 5, 1, 1, 1, 1, 2, 0, 0],  // Row 6 - snout
            [0, 0, 2, 1, 1, 1, 1, 3, 3, 1, 1, 1, 1, 2, 0, 0],  // Row 7 - tongue
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 8 - chin
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 9 - neck
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 10 - body
            [0, 0, 2, 1, 1, 6, 6, 6, 6, 6, 6, 1, 1, 2, 0, 0],  // Row 11 - belly
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 0],  // Row 12 - body + tail
            [0, 0, 0, 2, 1, 1, 2, 0, 0, 2, 1, 1, 2, 0, 2, 2],  // Row 13 - feet + tail
            [0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0],  // Row 14 - paws
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // Row 15 - empty
        ]
    }

    // Bunny: Long upright ears, fluffy cheeks, cotton tail
    private var bunnyPattern: [[Int]] {
        [
            [0, 0, 0, 0, 2, 1, 2, 0, 0, 2, 1, 2, 0, 0, 0, 0],  // Row 0 - ear tips
            [0, 0, 0, 0, 2, 1, 2, 0, 0, 2, 1, 2, 0, 0, 0, 0],  // Row 1 - ears
            [0, 0, 0, 0, 2, 1, 2, 0, 0, 2, 1, 2, 0, 0, 0, 0],  // Row 2 - ears
            [0, 0, 0, 0, 2, 3, 2, 2, 2, 2, 3, 2, 0, 0, 0, 0],  // Row 3 - inner ears + head
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 4 - head
            [0, 0, 2, 1, 1, 5, 4, 1, 1, 5, 4, 1, 1, 2, 0, 0],  // Row 5 - eyes
            [0, 2, 6, 1, 1, 5, 5, 1, 1, 5, 5, 1, 1, 6, 2, 0],  // Row 6 - cheeks + eyes
            [0, 2, 6, 1, 1, 1, 1, 3, 3, 1, 1, 1, 1, 6, 2, 0],  // Row 7 - cheeks + nose
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 8 - mouth
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 9 - neck
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0],  // Row 10 - body
            [0, 0, 2, 1, 1, 1, 6, 6, 6, 6, 1, 1, 1, 2, 0, 0],  // Row 11 - belly
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 6, 0],  // Row 12 - body + tail
            [0, 0, 0, 2, 1, 1, 2, 0, 0, 2, 1, 1, 2, 6, 6, 0],  // Row 13 - feet + fluffy tail
            [0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 2, 2, 0, 0, 0, 0],  // Row 14 - paws
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // Row 15 - empty
        ]
    }

    // Bird: Wings, beak, feathered crest
    private var birdPattern: [[Int]] {
        [
            [0, 0, 0, 0, 0, 0, 2, 2, 2, 0, 0, 0, 0, 0, 0, 0],  // Row 0 - crest
            [0, 0, 0, 0, 0, 2, 3, 3, 3, 2, 0, 0, 0, 0, 0, 0],  // Row 1 - crest
            [0, 0, 0, 0, 2, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0],  // Row 2 - head top
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0],  // Row 3 - head
            [0, 0, 0, 2, 1, 5, 4, 1, 5, 4, 1, 2, 0, 0, 0, 0],  // Row 4 - eyes
            [0, 0, 0, 2, 1, 5, 5, 1, 5, 5, 1, 2, 2, 2, 0, 0],  // Row 5 - eyes + beak
            [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 3, 3, 3, 2, 0],  // Row 6 - face + beak
            [0, 0, 0, 0, 2, 1, 1, 1, 1, 1, 2, 2, 2, 0, 0, 0],  // Row 7 - chin
            [0, 0, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2, 2, 0, 0, 0],  // Row 8 - wings start
            [0, 2, 2, 1, 2, 1, 1, 1, 1, 1, 2, 1, 2, 2, 0, 0],  // Row 9 - wings
            [2, 2, 1, 1, 2, 1, 6, 6, 6, 1, 2, 1, 1, 2, 2, 0],  // Row 10 - wings + belly
            [0, 2, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0],  // Row 11 - wings end
            [0, 0, 0, 0, 2, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0, 0],  // Row 12 - body
            [0, 0, 0, 0, 0, 2, 1, 2, 1, 2, 0, 0, 0, 0, 0, 0],  // Row 13 - feet
            [0, 0, 0, 0, 0, 2, 2, 0, 2, 2, 0, 0, 0, 0, 0, 0],  // Row 14 - claws
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],  // Row 15 - empty
        ]
    }

    // Dragon: Horns, wings, spiky tail
    private var dragonPattern: [[Int]] {
        [
            [0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0],  // Row 0 - horn tips
            [0, 0, 2, 3, 2, 0, 0, 0, 0, 0, 0, 2, 3, 2, 0, 0],  // Row 1 - horns
            [0, 0, 0, 2, 1, 2, 2, 2, 2, 2, 2, 1, 2, 0, 0, 0],  // Row 2 - head top
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 3 - head
            [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0],  // Row 4 - glowing eyes
            [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0],  // Row 5 - eyes
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0],  // Row 6 - snout
            [0, 0, 2, 1, 1, 1, 3, 1, 1, 3, 1, 1, 1, 2, 0, 0],  // Row 7 - nostrils
            [0, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 0],  // Row 8 - neck + wing start
            [2, 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 2, 2],  // Row 9 - wings
            [0, 2, 1, 2, 1, 6, 6, 6, 6, 6, 6, 1, 2, 1, 2, 0],  // Row 10 - wings + belly
            [0, 0, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 0, 0],  // Row 11 - body
            [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2],  // Row 12 - body + tail
            [0, 0, 0, 2, 1, 1, 2, 0, 0, 2, 1, 1, 2, 0, 3, 2],  // Row 13 - feet + spiky tail
            [0, 0, 0, 0, 2, 2, 0, 0, 0, 0, 2, 2, 0, 2, 3, 2],  // Row 14 - claws + tail tip
            [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0],  // Row 15 - tail end
        ]
    }

    // MARK: - Blink Animation

    private func applyBlinkAnimation(to pattern: [[Int]], form: PetForm) -> [[Int]] {
        var result = pattern

        // Find eye rows and close them (replace white/pupil with primary color)
        switch form {
        case .cat:
            result[4] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .dog:
            result[4] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .bunny:
            result[5] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[6] = [0, 2, 6, 1, 1, 5, 5, 1, 1, 5, 5, 1, 1, 6, 2, 0]
        case .bird:
            result[4] = [0, 0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0, 0, 0]
            result[5] = [0, 0, 0, 2, 1, 5, 5, 1, 5, 5, 1, 2, 2, 2, 0, 0]
        case .dragon:
            result[4] = [0, 0, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<pixelPattern.count, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<pixelPattern[row].count, id: \.self) { col in
                        Rectangle()
                            .fill(colorForPixel(pixelPattern[row][col]))
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
            }
        }
    }

    private func colorForPixel(_ value: Int) -> Color {
        switch value {
        case 0: return .clear
        case 1: return primaryColor
        case 2: return secondaryColor
        case 3: return accentColor
        case 4: return .white
        case 5: return .black
        case 6: return primaryColor.opacity(0.7) // Highlight/belly color
        default: return .clear
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
