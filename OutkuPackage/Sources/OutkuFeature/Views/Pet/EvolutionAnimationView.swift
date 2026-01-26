import SwiftUI

// MARK: - Evolution Animation View

struct EvolutionAnimationView: View {
    let fromStage: PetStage
    let toStage: PetStage
    let onComplete: () -> Void

    @Environment(ThemeManager.self) private var theme
    @State private var phase: EvolutionPhase = .intro
    @State private var glowOpacity: Double = 0
    @State private var particleOffsets: [CGSize] = []
    @State private var particleOpacities: [Double] = []
    @State private var petScale: CGFloat = 1.0
    @State private var petOpacity: Double = 1.0
    @State private var showNewPet: Bool = false
    @State private var textOpacity: Double = 0

    private enum EvolutionPhase {
        case intro
        case glowing
        case transforming
        case reveal
        case complete
    }

    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.colors.accent.opacity(glowOpacity),
                            theme.colors.accent.opacity(glowOpacity * 0.5),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)

            // Particles
            ForEach(0..<12, id: \.self) { index in
                Image(systemName: "sparkle")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.colors.accent)
                    .offset(particleOffsets.indices.contains(index) ? particleOffsets[index] : .zero)
                    .opacity(particleOpacities.indices.contains(index) ? particleOpacities[index] : 0)
            }

            // Pet container
            VStack(spacing: 40) {
                // Stage label
                if phase == .intro || phase == .glowing {
                    Text(fromStage.rawValue)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(textOpacity)
                } else if phase == .reveal || phase == .complete {
                    Text(toStage.rawValue)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(theme.colors.accent)
                        .opacity(textOpacity)
                }

                // Pet display
                ZStack {
                    // Old pet (fading out)
                    if !showNewPet {
                        PixelPetView(size: .large, animated: false)
                            .frame(width: 200, height: 200)
                            .scaleEffect(petScale)
                            .opacity(petOpacity)
                    }

                    // New pet (fading in)
                    if showNewPet {
                        PixelPetView(size: .large, animated: true)
                            .frame(width: 200, height: 200)
                            .scaleEffect(petScale)
                            .opacity(petOpacity)
                    }
                }

                // Evolution text
                if phase == .complete {
                    VStack(spacing: 12) {
                        Text("Evolution Complete!")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)

                        Text("Your pet has grown stronger!")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .opacity(textOpacity)
                }
            }

            // Continue button
            if phase == .complete {
                VStack {
                    Spacer()

                    Button {
                        onComplete()
                    } label: {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 48)
                            .padding(.vertical, 16)
                            .background(theme.colors.accent)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .opacity(textOpacity)
                    .padding(.bottom, 60)
                }
            }
        }
        .onAppear {
            startEvolutionSequence()
        }
    }

    private func startEvolutionSequence() {
        // Initialize particles
        particleOffsets = Array(repeating: .zero, count: 12)
        particleOpacities = Array(repeating: 0, count: 12)

        // Phase 1: Intro
        withAnimation(.easeIn(duration: 0.5)) {
            textOpacity = 1.0
        }

        // Phase 2: Glowing (after 1s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            phase = .glowing
            withAnimation(.easeInOut(duration: 1.5)) {
                glowOpacity = 0.8
            }

            // Start particles
            startParticleAnimation()
        }

        // Phase 3: Transforming (after 2.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            phase = .transforming
            withAnimation(.easeIn(duration: 0.3)) {
                textOpacity = 0
            }

            withAnimation(.easeInOut(duration: 0.5)) {
                petScale = 1.3
                glowOpacity = 1.0
            }

            // Flash and swap
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.2)) {
                    petOpacity = 0
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showNewPet = true
                    petScale = 0.8

                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        petOpacity = 1.0
                        petScale = 1.0
                    }
                }
            }
        }

        // Phase 4: Reveal (after 3.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            phase = .reveal
            withAnimation(.easeOut(duration: 1.0)) {
                glowOpacity = 0.3
            }

            withAnimation(.easeIn(duration: 0.5)) {
                textOpacity = 1.0
            }
        }

        // Phase 5: Complete (after 4.5s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            phase = .complete
            SoundService.shared.playWithHaptic(.petEvolution, haptic: .success)
        }
    }

    private func startParticleAnimation() {
        for i in 0..<12 {
            let angle = Double(i) * (360.0 / 12.0) * .pi / 180.0
            let radius: Double = 80

            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.05) {
                particleOpacities[i] = 1.0

                withAnimation(.easeOut(duration: 1.5)) {
                    particleOffsets[i] = CGSize(
                        width: cos(angle) * radius * 2,
                        height: sin(angle) * radius * 2
                    )
                    particleOpacities[i] = 0
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    EvolutionAnimationView(
        fromStage: .baby,
        toStage: .child,
        onComplete: {}
    )
    .environment(AppState.shared)
    .environment(ThemeManager.shared)
}
