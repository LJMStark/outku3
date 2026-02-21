import SwiftUI

extension PixelPetView {
    func triggerCelebrationAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.4)) {
            bounceOffset = -25
            celebrationScale = 1.15
        }

        showStars = true
        starOffsets = PetAnimationEngine.randomOffsets(count: 5, xRange: -40...40, yRange: -50 ... -20)
        starOpacities = PetAnimationEngine.fadeValues(count: 5, to: 1.0)

        withAnimation(.easeOut(duration: 0.6)) {
            starOffsets = PetAnimationEngine.scaleOffsets(starOffsets, xScale: 2, yScale: 1.5)
        }

        withAnimation(.easeOut(duration: 0.8)) {
            starOpacities = PetAnimationEngine.fadeValues(count: 5, to: 0.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                bounceOffset = 0
                celebrationScale = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showStars = false
        }
    }

    func triggerHappyAnimation() {
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

        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) {
            bounceOffset = -10
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                bounceOffset = 0
            }
        }
    }

    @ViewBuilder
    var interactionParticles: some View {
        if showHearts {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "heart.fill")
                    .font(.system(size: 10 * size.scale))
                    .foregroundStyle(Color.pink)
                    .offset(heartOffsets.indices.contains(index) ? heartOffsets[index] : .zero)
                    .opacity(heartOpacities.indices.contains(index) ? heartOpacities[index] : 0)
            }
        }

        if showNotes {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index % 2 == 0 ? "music.note" : "music.quarternote.3")
                    .font(.system(size: 10 * size.scale))
                    .foregroundStyle(theme.colors.accent)
                    .offset(noteOffsets.indices.contains(index) ? noteOffsets[index] : .zero)
                    .opacity(noteOpacities.indices.contains(index) ? noteOpacities[index] : 0)
            }
        }

        if showLoveBubble {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 24 * size.scale))
                .foregroundStyle(Color.pink.opacity(0.8))
                .offset(y: -50 * size.scale)
                .opacity(loveBubbleOpacity)
        }
    }

    func startIdleAnimations() {
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            idleBreathScale = 1.02
        }

        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            idleSwayX = 2
        }
    }

    func startSceneAnimations() {
        switch currentScene {
        case .indoor:
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                windowLightX = 50
            }
        case .outdoor:
            withAnimation(.linear(duration: 12.0).repeatForever(autoreverses: true)) {
                cloudDriftX = 40
            }
        case .night:
            for i in 0..<8 {
                let delay = Double.random(in: 0...2)
                let duration = Double.random(in: 1.5...3.0)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                        starTwinkle[i] = Double.random(in: 0.3...1.0)
                    }
                }
            }
        case .work:
            break
        }
    }

    func triggerTapParticles() {
        switch appState.pet.mood {
        case .happy:
            triggerHeartParticles()
        case .excited:
            triggerNoteParticles()
        case .missing:
            break
        default:
            break
        }
    }

    func triggerHeartParticles() {
        showHearts = true
        heartOffsets = [
            CGSize(width: -20, height: -35),
            CGSize(width: 5, height: -45),
            CGSize(width: 25, height: -30)
        ]
        heartOpacities = PetAnimationEngine.fadeValues(count: 3, to: 1.0)

        withAnimation(.easeOut(duration: 0.8)) {
            heartOffsets = PetAnimationEngine.scaleOffsets(heartOffsets, xScale: 1.5, yScale: 1.8)
            heartOpacities = PetAnimationEngine.fadeValues(count: 3, to: 0.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showHearts = false
        }
    }

    func triggerNoteParticles() {
        showNotes = true
        noteOffsets = [
            CGSize(width: -25, height: -30),
            CGSize(width: 10, height: -45),
            CGSize(width: 30, height: -35)
        ]
        noteOpacities = PetAnimationEngine.fadeValues(count: 3, to: 1.0)

        withAnimation(.easeOut(duration: 0.8)) {
            noteOffsets = PetAnimationEngine.scaleOffsets(noteOffsets, xScale: 1.5, yScale: 1.5)
            noteOpacities = PetAnimationEngine.fadeValues(count: 3, to: 0.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            showNotes = false
        }
    }

    func triggerLoveBubble() {
        showLoveBubble = true
        withAnimation(.easeOut(duration: 0.3)) {
            loveBubbleOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.5)) {
                loveBubbleOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showLoveBubble = false
        }
    }
}
