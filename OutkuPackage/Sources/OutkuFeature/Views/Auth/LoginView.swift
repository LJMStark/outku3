import SwiftUI

// MARK: - Login View

/// 登录页面，展示品牌 Logo 和登录选项
public struct LoginView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AuthManager.self) private var authManager

    public var onLoginComplete: (() -> Void)?

    public init(onLoginComplete: (() -> Void)? = nil) {
        self.onLoginComplete = onLoginComplete
    }

    public var body: some View {
        ZStack {
            // Background
            themeManager.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo and Welcome
                VStack(spacing: 24) {
                    // Pet Icon
                    ZStack {
                        Circle()
                            .fill(themeManager.colors.accent.opacity(0.2))
                            .frame(width: 120, height: 120)

                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 48))
                            .foregroundColor(themeManager.colors.accent)
                    }

                    // App Name
                    Text("Outku")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundColor(themeManager.colors.primaryText)

                    // Tagline
                    Text("Your pixel pet companion\nfor productive days")
                        .font(.system(size: 17))
                        .foregroundColor(themeManager.colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer()

                // Sign In Buttons
                VStack(spacing: 24) {
                    SignInButtonsView {
                        onLoginComplete?()
                    }

                    // Terms and Privacy
                    Text("By signing in, you agree to our Terms of Service and Privacy Policy")
                        .font(.caption)
                        .foregroundColor(themeManager.colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView()
        .environment(ThemeManager.shared)
        .environment(AuthManager.shared)
}
