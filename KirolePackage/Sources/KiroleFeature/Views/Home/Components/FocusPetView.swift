import SwiftUI

public struct FocusPetView: View {
    @Environment(ThemeManager.self) private var theme
    
    let focusMinutes: Int
    @State private var isBreathing = false
    
    // Derived values based on minutes
    private var energyBlocks: Int {
        FocusEnergyCalculator.blocksEarned(minutes: focusMinutes)
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
                        .fill(index < energyBlocks ? theme.colors.accent : theme.colors.secondaryText.opacity(0.2))
                        .frame(width: 16, height: 16)
                        .shadow(color: index < energyBlocks ? theme.colors.accent.opacity(0.6) : .clear, radius: 8, x: 0, y: 0)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: energyBlocks)
            
            // Pet with breathing animation
            ZStack {
                // Background aura based on energy
                if energyBlocks > 0 {
                    Circle()
                        .fill(theme.colors.accent.opacity(0.15))
                        .frame(width: 220, height: 220)
                        .blur(radius: 20)
                        .scaleEffect(isBreathing ? 1.1 : 0.9)
                        .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: isBreathing)
                }
                
                Image("tiko_reading")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .scaleEffect(isBreathing ? 1.05 : 0.98)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isBreathing)
            }
            .onAppear {
                isBreathing = true
            }
        }
        .padding()
    }
}
