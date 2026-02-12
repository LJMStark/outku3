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

    // Mood-specific animation states
    @State private var sleepyBreathScale: CGFloat = 1.0
    @State private var sleepyZOffset: CGFloat = 0
    @State private var showZzz: Bool = false
    @State private var excitedSparkles: Bool = false
    @State private var sparkleOffsets: [CGSize] = []
    @State private var sparkleOpacities: [Double] = []
    @State private var missingLookDirection: CGFloat = 0
    @State private var focusedPulse: CGFloat = 1.0

    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    private let moodTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    // 当前场景（优先使用传入的，否则使用 appState 中的）
    private var currentScene: PetScene {
        scene ?? appState.pet.scene
    }

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2

            ZStack {
                // Scene background
                sceneBackground
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // Mood-specific effects
                moodEffects

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
                    .fill(shadowColor.opacity(0.15))
                    .frame(width: 60 * size.scale, height: 20 * size.scale)
                    .offset(y: 40 * size.scale + bounceOffset * 0.3)
                    .scaleEffect(x: celebrationScale, y: 1.0 - (celebrationScale - 1.0) * 0.5)

                // Pet body with mood-specific transforms
                PixelArtBody(
                    pixelSize: size.pixelSize,
                    primaryColor: petPrimaryColor,
                    secondaryColor: petSecondaryColor,
                    accentColor: theme.colors.accent,
                    animationPhase: animationPhase,
                    petForm: appState.pet.currentForm,
                    mood: appState.pet.mood
                )
                .offset(x: missingLookDirection, y: bounceOffset)
                .scaleEffect(celebrationScale * sleepyBreathScale * focusedPulse)
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
        .onReceive(moodTimer) { _ in
            guard animated else { return }
            triggerMoodAnimation()
        }
        .onChange(of: appState.pet.adventuresCount) { oldValue, newValue in
            if newValue > oldValue {
                triggerCelebrationAnimation()
            }
        }
        .onChange(of: appState.pet.mood) { _, newMood in
            resetMoodAnimations()
            if animated {
                triggerMoodAnimation()
            }
        }
        .onAppear {
            if animated {
                triggerMoodAnimation()
            }
        }
    }

    // MARK: - Scene Background

    @ViewBuilder
    private var sceneBackground: some View {
        switch currentScene {
        case .indoor:
            // 室内：温暖的渐变背景
            LinearGradient(
                colors: [
                    theme.colors.cardBackground,
                    theme.colors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                // 窗户光线效果
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.yellow.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 150)
                    .offset(x: -50, y: -80)
            )

        case .outdoor:
            // 户外：蓝天白云
            LinearGradient(
                colors: [
                    Color(hex: "#87CEEB"),
                    Color(hex: "#E0F7FA")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                // 云朵
                HStack(spacing: 30) {
                    cloudShape
                        .offset(y: -60)
                    cloudShape
                        .scaleEffect(0.7)
                        .offset(y: -40)
                }
                .offset(y: -20)
            )
            .overlay(
                // 草地
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#90EE90"),
                                Color(hex: "#228B22")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 40)
                    .offset(y: 80)
                , alignment: .bottom
            )

        case .night:
            // 夜晚：深蓝色星空
            LinearGradient(
                colors: [
                    Color(hex: "#0D1B2A"),
                    Color(hex: "#1B263B")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay(
                // 星星
                ZStack {
                    ForEach(0..<8, id: \.self) { index in
                        Circle()
                            .fill(Color.white)
                            .frame(width: CGFloat.random(in: 2...4), height: CGFloat.random(in: 2...4))
                            .offset(
                                x: CGFloat.random(in: -80...80),
                                y: CGFloat.random(in: -80...(-20))
                            )
                            .opacity(Double.random(in: 0.5...1.0))
                    }
                    // 月亮
                    Circle()
                        .fill(Color(hex: "#F5F5DC"))
                        .frame(width: 30, height: 30)
                        .offset(x: 60, y: -70)
                        .shadow(color: Color(hex: "#F5F5DC").opacity(0.5), radius: 10)
                }
            )

        case .work:
            // 工作模式：专注的简洁背景
            LinearGradient(
                colors: [
                    theme.colors.background,
                    theme.colors.cardBackground.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                // 专注光环
                Circle()
                    .stroke(theme.colors.accent.opacity(0.2), lineWidth: 2)
                    .frame(width: 120, height: 120)
            )
            .overlay(
                // 小装饰点
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(theme.colors.accent.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .offset(y: 70)
            )
        }
    }

    private var cloudShape: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 30, height: 30)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 25, height: 25)
                .offset(x: 15, y: 5)
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 20, height: 20)
                .offset(x: -12, y: 3)
        }
    }

    // MARK: - Mood Effects

    @ViewBuilder
    private var moodEffects: some View {
        switch appState.pet.mood {
        case .sleepy:
            // Zzz 效果
            if showZzz {
                ZStack {
                    Text("Z")
                        .font(.system(size: 14 * size.scale, weight: .bold))
                        .foregroundStyle(theme.colors.secondaryText.opacity(0.6))
                        .offset(x: 30 * size.scale, y: -40 * size.scale + sleepyZOffset)
                    Text("z")
                        .font(.system(size: 10 * size.scale, weight: .bold))
                        .foregroundStyle(theme.colors.secondaryText.opacity(0.4))
                        .offset(x: 40 * size.scale, y: -50 * size.scale + sleepyZOffset * 0.8)
                    Text("z")
                        .font(.system(size: 8 * size.scale, weight: .bold))
                        .foregroundStyle(theme.colors.secondaryText.opacity(0.3))
                        .offset(x: 48 * size.scale, y: -58 * size.scale + sleepyZOffset * 0.6)
                }
            }

        case .excited:
            // 闪烁星星效果
            if excitedSparkles {
                ForEach(0..<4, id: \.self) { index in
                    Image(systemName: "sparkle")
                        .font(.system(size: 10 * size.scale))
                        .foregroundStyle(theme.colors.accent)
                        .offset(sparkleOffsets.indices.contains(index) ? sparkleOffsets[index] : .zero)
                        .opacity(sparkleOpacities.indices.contains(index) ? sparkleOpacities[index] : 0)
                }
            }

        case .missing:
            // 问号效果
            Text("?")
                .font(.system(size: 16 * size.scale, weight: .bold))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                .offset(x: 35 * size.scale, y: -45 * size.scale)

        case .focused:
            // 专注光环
            Circle()
                .stroke(theme.colors.accent.opacity(0.3), lineWidth: 2)
                .frame(width: 80 * size.scale * focusedPulse, height: 80 * size.scale * focusedPulse)

        case .happy:
            // 小心形效果（偶尔出现）
            EmptyView()
        }
    }

    // MARK: - Mood Animations

    private func triggerMoodAnimation() {
        switch appState.pet.mood {
        case .sleepy:
            triggerSleepyAnimation()
        case .excited:
            triggerExcitedAnimation()
        case .missing:
            triggerMissingAnimation()
        case .focused:
            triggerFocusedAnimation()
        case .happy:
            triggerHappyIdleAnimation()
        }
    }

    private func resetMoodAnimations() {
        sleepyBreathScale = 1.0
        showZzz = false
        excitedSparkles = false
        missingLookDirection = 0
        focusedPulse = 1.0
    }

    private func triggerSleepyAnimation() {
        // 呼吸效果
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            sleepyBreathScale = 1.03
        }

        // Zzz 浮动效果
        showZzz = true
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            sleepyZOffset = -10
        }
    }

    private func triggerExcitedAnimation() {
        // 跳跃动画
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            bounceOffset = -15
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                bounceOffset = 0
            }
        }

        // 闪烁星星
        excitedSparkles = true
        sparkleOffsets = [
            CGSize(width: -35, height: -30),
            CGSize(width: 35, height: -35),
            CGSize(width: -40, height: -50),
            CGSize(width: 40, height: -45)
        ]
        sparkleOpacities = Array(repeating: 1.0, count: 4)

        withAnimation(.easeOut(duration: 1.0)) {
            sparkleOpacities = Array(repeating: 0.0, count: 4)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            excitedSparkles = false
        }
    }

    private func triggerMissingAnimation() {
        // 左右张望效果
        withAnimation(.easeInOut(duration: 1.0)) {
            missingLookDirection = -8
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 1.0)) {
                missingLookDirection = 8
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.5)) {
                missingLookDirection = 0
            }
        }
    }

    private func triggerFocusedAnimation() {
        // 专注脉冲效果
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            focusedPulse = 1.02
        }
    }

    private func triggerHappyIdleAnimation() {
        // 偶尔的小跳跃
        if Int.random(in: 0...2) == 0 {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                bounceOffset = -8
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    bounceOffset = 0
                }
            }
        }
    }

    private var shadowColor: Color {
        switch currentScene {
        case .night:
            return Color.white
        default:
            return theme.colors.primaryText
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
    var mood: PetMood = .happy

    // 0 = transparent, 1 = primary, 2 = secondary, 3 = accent, 4 = white, 5 = black, 6 = highlight, 7 = sleepy eyes
    private var pixelPattern: [[Int]] {
        var pattern = basePatternForForm(petForm)

        // Apply mood-based eye modifications
        pattern = applyMoodToPattern(pattern, mood: mood, form: petForm)

        // Apply blink animation every 4th phase (only if not sleepy)
        if animationPhase == 3 && mood != .sleepy {
            pattern = applyBlinkAnimation(to: pattern, form: petForm)
        }

        return pattern
    }

    // MARK: - Mood Pattern Modifications

    private func applyMoodToPattern(_ pattern: [[Int]], mood: PetMood, form: PetForm) -> [[Int]] {
        var result = pattern

        switch mood {
        case .sleepy:
            // 半闭眼效果
            result = applySleepyEyes(to: result, form: form)
        case .excited:
            // 眼睛更大/更亮（使用 accent 色）
            result = applyExcitedEyes(to: result, form: form)
        case .missing:
            // 悲伤的眼睛（向下看）
            result = applyMissingEyes(to: result, form: form)
        case .focused, .happy:
            // 保持默认
            break
        }

        return result
    }

    private func applySleepyEyes(to pattern: [[Int]], form: PetForm) -> [[Int]] {
        var result = pattern

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

    private func applyExcitedEyes(to pattern: [[Int]], form: PetForm) -> [[Int]] {
        var result = pattern

        // 使用 accent 色（3）替代白色（4）让眼睛更亮
        switch form {
        case .cat:
            result[4] = [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0]
        case .dog:
            result[4] = [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 3, 1, 1, 1, 1, 5, 3, 1, 2, 0, 0]
        case .bunny:
            result[5] = [0, 0, 2, 1, 1, 5, 3, 1, 1, 5, 3, 1, 1, 2, 0, 0]
            result[6] = [0, 2, 6, 1, 1, 5, 3, 1, 1, 5, 3, 1, 1, 6, 2, 0]
        case .bird:
            result[4] = [0, 0, 0, 2, 1, 5, 3, 1, 5, 3, 1, 2, 0, 0, 0, 0]
            result[5] = [0, 0, 0, 2, 1, 5, 3, 1, 5, 3, 1, 2, 2, 2, 0, 0]
        case .dragon:
            // Dragon already has glowing eyes
            break
        }

        return result
    }

    private func applyMissingEyes(to pattern: [[Int]], form: PetForm) -> [[Int]] {
        var result = pattern

        // 眼睛向下看的效果
        switch form {
        case .cat:
            result[4] = [0, 0, 2, 1, 4, 4, 1, 1, 1, 1, 4, 4, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .dog:
            result[4] = [0, 0, 2, 1, 4, 4, 1, 1, 1, 1, 4, 4, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        case .bunny:
            result[5] = [0, 0, 2, 1, 1, 4, 4, 1, 1, 4, 4, 1, 1, 2, 0, 0]
            result[6] = [0, 2, 6, 1, 1, 5, 5, 1, 1, 5, 5, 1, 1, 6, 2, 0]
        case .bird:
            result[4] = [0, 0, 0, 2, 1, 4, 4, 1, 4, 4, 1, 2, 0, 0, 0, 0]
            result[5] = [0, 0, 0, 2, 1, 5, 5, 1, 5, 5, 1, 2, 2, 2, 0, 0]
        case .dragon:
            result[4] = [0, 0, 2, 1, 4, 4, 1, 1, 1, 1, 4, 4, 1, 2, 0, 0]
            result[5] = [0, 0, 2, 1, 5, 5, 1, 1, 1, 1, 5, 5, 1, 2, 0, 0]
        }

        return result
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
