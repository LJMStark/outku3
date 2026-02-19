import SwiftUI

public struct SignUpPage: View {
    let onboardingState: OnboardingState
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager
    @Environment(ThemeManager.self) private var theme

    @State private var email: String = ""
    @State private var isSigningIn = false
    @State private var showComingSoonAlert = false

    private var isValidEmail: Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    public init(onboardingState: OnboardingState) {
        self.onboardingState = onboardingState
    }

    public var body: some View {
        ZStack {
            theme.colors.cardBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: back button + full progress bar
                HStack(spacing: 16) {
                    Button {
                        onboardingState.goBack()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(theme.colors.background)
                                .frame(width: 40, height: 40)
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.colors.secondaryText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personalization")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.colors.primary)

                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule()
                                    .fill(theme.colors.primary)
                                    .frame(height: 4)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Logo
                        // TODO: Replace with Kirole pet asset
                        Image("inku-head", bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)
                            .padding(.top, 32)

                        // Title
                        Text("Sign up to Save Progress")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.colors.primaryText)
                            .padding(.top, 24)

                        Text("One more step to unlock your flow.")
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(theme.colors.secondaryText)
                            .padding(.top, 8)

                        // Social sign in buttons
                        VStack(spacing: 12) {
                            // Google Sign In
                            Button {
                                isSigningIn = true
                                Task { @MainActor in
                                    try? await authManager.signInWithGoogle()
                                    if authManager.isGoogleConnected {
                                        appState.completeOnboarding(with: onboardingState.profile)
                                    }
                                    isSigningIn = false
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "g.circle.fill")
                                        .font(.system(size: 20))
                                    Text("Continue with Google")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(theme.colors.primaryText)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            }
                            .disabled(isSigningIn)

                            // Apple Sign In (coming soon)
                            Button {
                                showComingSoonAlert = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "apple.logo")
                                        .font(.system(size: 20))
                                    Text("Continue with Apple")
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(theme.colors.primaryText)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            }
                        }
                        .padding(.top, 32)

                        // Divider
                        HStack(spacing: 16) {
                            Rectangle()
                                .fill(theme.colors.timeline)
                                .frame(height: 1)
                            Text("or")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(theme.colors.secondaryText)
                            Rectangle()
                                .fill(theme.colors.timeline)
                                .frame(height: 1)
                        }
                        .padding(.vertical, 24)

                        // Email input
                        VStack(spacing: 12) {
                            TextField("Email address", text: $email)
                                .font(.system(size: 16, design: .rounded))
                                .padding(.horizontal, 24)
                                .padding(.vertical, 18)
                                .background {
                                    Capsule()
                                        .stroke(
                                            isValidEmail ? theme.colors.primary : theme.colors.timeline,
                                            lineWidth: 2
                                        )
                                }
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                #endif
                                .autocorrectionDisabled()

                            Button {
                                if isValidEmail {
                                    showComingSoonAlert = true
                                }
                            } label: {
                                Text("Send Magic Link")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isValidEmail ? theme.colors.primaryText : theme.colors.secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background {
                                        Capsule()
                                            .fill(isValidEmail ? theme.colors.cardBackground : theme.colors.background)
                                            .overlay {
                                                if isValidEmail {
                                                    Capsule().stroke(theme.colors.timeline, lineWidth: 2)
                                                }
                                            }
                                    }
                                    .shadow(color: .black.opacity(isValidEmail ? 0.08 : 0), radius: 4, y: 2)
                            }
                            .disabled(!isValidEmail)
                        }

                        // Skip for now
                        Button {
                            appState.completeOnboarding(with: onboardingState.profile)
                        } label: {
                            Text("Skip for now")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.colors.secondaryText)
                                .padding(.top, 16)
                                .padding(.bottom, 8)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
        .alert("Coming Soon", isPresented: $showComingSoonAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This sign-in method will be available in a future update.")
        }
    }
}
