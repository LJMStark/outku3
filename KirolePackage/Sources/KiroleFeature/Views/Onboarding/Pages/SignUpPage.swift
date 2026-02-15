import SwiftUI

public struct SignUpPage: View {
    let onboardingState: OnboardingState
    @Environment(AppState.self) private var appState
    @Environment(AuthManager.self) private var authManager

    @State private var email: String = ""
    @State private var isSigningIn = false

    private var isValidEmail: Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    public init(onboardingState: OnboardingState) {
        self.onboardingState = onboardingState
    }

    public var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header: back button + full progress bar
                HStack(spacing: 16) {
                    Button {
                        onboardingState.goBack()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "F3F4F6"))
                                .frame(width: 40, height: 40)
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(hex: "6B7280"))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personalization")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(hex: "0D8A6A"))

                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { _ in
                                Capsule()
                                    .fill(Color(hex: "0D8A6A"))
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
                        Image("inku-head", bundle: .module)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 96, height: 96)
                            .padding(.top, 32)

                        // Title
                        Text("Sign up to Save Progress")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(hex: "1A1A2E"))
                            .padding(.top, 24)

                        Text("One more step to clarity, control and joy.")
                            .font(.system(size: 16, design: .rounded))
                            .foregroundStyle(Color(hex: "6B7280"))
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
                                .background(Color(hex: "1A1A2E"))
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            }
                            .disabled(isSigningIn)

                            // Apple Sign In (placeholder)
                            Button {
                                appState.completeOnboarding(with: onboardingState.profile)
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
                                .background(Color(hex: "1A1A2E"))
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                            }
                        }
                        .padding(.top, 32)

                        // Divider
                        HStack(spacing: 16) {
                            Rectangle()
                                .fill(Color(hex: "E5E7EB"))
                                .frame(height: 1)
                            Text("or")
                                .font(.system(size: 14, design: .rounded))
                                .foregroundStyle(Color(hex: "9CA3AF"))
                            Rectangle()
                                .fill(Color(hex: "E5E7EB"))
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
                                            isValidEmail ? Color(hex: "0D8A6A") : Color(hex: "E5E7EB"),
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
                                    appState.completeOnboarding(with: onboardingState.profile)
                                }
                            } label: {
                                Text("Send Magic Link")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isValidEmail ? Color(hex: "1A1A2E") : Color(hex: "9CA3AF"))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background {
                                        Capsule()
                                            .fill(isValidEmail ? Color.white : Color(hex: "F3F4F6"))
                                            .overlay {
                                                if isValidEmail {
                                                    Capsule().stroke(Color(hex: "E5E7EB"), lineWidth: 2)
                                                }
                                            }
                                    }
                                    .shadow(color: .black.opacity(isValidEmail ? 0.08 : 0), radius: 4, y: 2)
                            }
                            .disabled(!isValidEmail)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }
}
