import SwiftUI

// MARK: - Device Section

/// 设备模式设置区域
public struct DeviceModeSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader

            VStack(spacing: 12) {
                deviceCard
                
                homeScreenHint
            }
        }
    }

    private var sectionHeader: some View {
        Text("Device")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.colors.primaryText)
    }

    private var deviceCard: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "5A7D6A"), Color(hex: "4A6352")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Texture overlay (optional)
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.black.opacity(0.1))
                .blendMode(.multiply)

            HStack(spacing: 8) {
                // Pet Image
                Image("tiko_avatar", bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 120)
                    .offset(y: 10) // Push pet slightly down
                
                VStack(alignment: .trailing, spacing: 12) {
                    // Battery indicator
                    HStack(spacing: 4) {
                        HStack(spacing: 2) {
                            ForEach(0..<10) { i in
                                Circle()
                                    .fill(i < 5 ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        Text("50%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    // Speech Bubble
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "C6D8C8"))
                        
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: "95B19A"), lineWidth: 4)
                        
                        Text("Back to back meetings to start the day, an intense morning, I must say.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "374151"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .frame(height: 140)
        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }
    
    private var homeScreenHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.secondaryText)
            
            Text("How do I add to my home screen?")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

#Preview {
    DeviceModeSection()
        .padding()
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
