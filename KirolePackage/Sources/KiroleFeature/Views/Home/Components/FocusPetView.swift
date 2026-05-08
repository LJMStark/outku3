import SwiftUI

public struct FocusPetView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let focusMinutes: Int
    @State private var isBreathing = false
    
    // Derived values based on minutes
    private var energyBottles: Int {
        FocusEnergyCalculator.bottlesEarned(minutes: focusMinutes)
    }
    
    public init(focusMinutes: Int) {
        self.focusMinutes = focusMinutes
    }
    
    public var body: some View {
        VStack(spacing: 32) {
            // Energy slots (3 stages: 5 mins, 15 mins, 30 mins)
            HStack(spacing: 16) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index < energyBottles ? theme.colors.accent : theme.colors.secondaryText.opacity(0.2))
                        .frame(width: 16, height: 16)
                        .shadow(color: index < energyBottles ? theme.colors.accent.opacity(0.6) : .clear, radius: 8, x: 0, y: 0)
                }
            }
            .animation(.kiroleAdaptive(.kiroleGentle, reduceMotion: reduceMotion), value: energyBottles)

            // Pet with breathing animation — skipped entirely under Reduce
            // Motion so the pet stays at a fixed scale instead of perpetually
            // pulsing.
            ZStack {
                // Background aura based on energy
                if energyBottles > 0 {
                    Circle()
                        .fill(theme.colors.accent.opacity(0.15))
                        .frame(width: 220, height: 220)
                        .blur(radius: 20)
                        .scaleEffect(reduceMotion ? 1.0 : (isBreathing ? 1.1 : 0.9))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: isBreathing)
                }

                Image(appState.userProfile.companionCharacter.heroAssetName(variant: .main), bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .scaleEffect(reduceMotion ? 1.0 : (isBreathing ? 1.05 : 0.98))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isBreathing)
            }
            .onAppear {
                guard !reduceMotion else { return }
                isBreathing = true
            }
        }
        .padding()
    }
}
