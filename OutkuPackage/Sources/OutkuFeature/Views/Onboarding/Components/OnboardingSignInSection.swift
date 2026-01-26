import SwiftUI

struct OnboardingSignInSection: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(AuthManager.self) private var authManager

    var onComplete: () -> Void

    @State private var isLoading = false
    @State private var isGoogleConnected = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            if isGoogleConnected {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Google Connected")
                        .foregroundStyle(.white)
                }
                .padding(.vertical, 12)

                Button("Continue") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.colors.accent)
            } else {
                Button {
                    Task { await handleGoogleSignIn() }
                } label: {
                    HStack(spacing: 12) {
                        GoogleIcon(lineWidth: 2, inset: 2)
                            .frame(width: 20, height: 20)
                        Text("Connect Google Calendar & Tasks")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .cornerRadius(12)
                }
                .disabled(isLoading)

                HStack {
                    Image(systemName: "apple.logo")
                    Text("Apple Sign In")
                    Spacer()
                    Text("Coming Soon")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .padding(.horizontal, 16)
                .background(Color.white.opacity(0.1))
                .foregroundColor(.white.opacity(0.5))
                .cornerRadius(12)
            }

            if isLoading {
                ProgressView().tint(.white)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func handleGoogleSignIn() async {
        isLoading = true
        errorMessage = nil

        do {
            try await authManager.signInWithGoogle()
            isGoogleConnected = true
        } catch {
            if let googleError = error as? GoogleSignInError,
               case .canceled = googleError {
                // User canceled, don't show error
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }
}
