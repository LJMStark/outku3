import SwiftUI

extension PixelPetView {
    @ViewBuilder
    var moodEffects: some View {
        switch appState.pet.mood {
        case .sleepy:
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
            Text("?")
                .font(.system(size: 16 * size.scale, weight: .bold))
                .foregroundStyle(theme.colors.secondaryText.opacity(0.5))
                .offset(x: 35 * size.scale, y: -45 * size.scale)

        case .focused:
            Circle()
                .stroke(theme.colors.accent.opacity(0.3), lineWidth: 2)
                .frame(width: 80 * size.scale * focusedPulse, height: 80 * size.scale * focusedPulse)

        case .happy:
            EmptyView()
        }
    }

    func triggerMoodAnimation() {
        switch appState.pet.mood {
        case .sleepy:
            guard !continuousMoodActive else { return }
            continuousMoodActive = true
            triggerSleepyAnimation()
        case .excited:
            triggerExcitedAnimation()
        case .missing:
            triggerMissingAnimation()
        case .focused:
            guard !continuousMoodActive else { return }
            continuousMoodActive = true
            triggerFocusedAnimation()
        case .happy:
            if !continuousMoodActive {
                continuousMoodActive = true
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    happyTailWag = 3
                }
            }
            triggerHappyIdleAnimation()
        }
    }

    func resetMoodAnimations() {
        continuousMoodActive = false
        sleepyBreathScale = 1.0
        showZzz = false
        excitedSparkles = false
        excitedTremor = 0
        missingLookDirection = 0
        focusedPulse = 1.0
        focusedLean = 0
        happyTailWag = 0
        sleepySink = 0
    }

    func triggerSleepyAnimation() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            sleepyBreathScale = 1.03
        }

        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            sleepySink = 2
        }

        showZzz = true
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            sleepyZOffset = -10
        }
    }

    func triggerExcitedAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            bounceOffset = -15
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                bounceOffset = 0
            }
        }

        withAnimation(.easeInOut(duration: 0.08).repeatCount(6, autoreverses: true)) {
            excitedTremor = 1.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            excitedTremor = 0
        }

        excitedSparkles = true
        sparkleOffsets = [
            CGSize(width: -35, height: -30),
            CGSize(width: 35, height: -35),
            CGSize(width: -40, height: -50),
            CGSize(width: 40, height: -45)
        ]
        sparkleOpacities = PetAnimationEngine.fadeValues(count: 4, to: 1.0)

        withAnimation(.easeOut(duration: 1.0)) {
            sparkleOpacities = PetAnimationEngine.fadeValues(count: 4, to: 0.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            excitedSparkles = false
        }
    }

    func triggerMissingAnimation() {
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

    func triggerFocusedAnimation() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            focusedPulse = 1.02
        }
        withAnimation(.easeInOut(duration: 2.0)) {
            focusedLean = -2
        }
    }

    func triggerHappyIdleAnimation() {
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
}
