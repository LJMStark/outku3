import SwiftUI

struct MorphingPetView: View {
    let form: PetForm
    let isShadowMode: Bool
    let isRevealed: Bool
    
    @State private var breathe = false
    @Environment(ThemeManager.self) private var theme
    
    var body: some View {
        ZStack {
            if isShadowMode {
                // Shadow / Silhouette
                Image(systemName: formIcon) // Use SF Symbols as placeholder for silhouette
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 150, height: 150)
                    .foregroundStyle(.black)
                    .shadow(color: theme.colors.accent.opacity(0.8), radius: 20) // Glowing edges
                    .scaleEffect(breathe ? 1.05 : 0.95)
                    .opacity(0.9)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                            breathe = true
                        }
                    }
                    .transition(.opacity)
            }
            
            if isRevealed {
                // Real Pet
                PixelPetView(size: .large, animated: true)
                    .frame(width: 180, height: 180)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .shadow(color: theme.colors.accent.opacity(0.4), radius: 30)
            }
        }
    }
    
    private var formIcon: String {
        switch form {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .bunny: return "hare.fill"
        case .bird: return "bird.fill"
        case .dragon: return "flame.fill"
        }
    }
}
