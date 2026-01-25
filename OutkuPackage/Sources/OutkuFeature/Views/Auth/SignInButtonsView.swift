import SwiftUI
import AuthenticationServices

// MARK: - Sign In Buttons View

/// 登录按钮组件，包含 Apple Sign In 和 Google Sign In
public struct SignInButtonsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AuthManager.self) private var authManager

    public var onSignInComplete: (() -> Void)?

    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(onSignInComplete: (() -> Void)? = nil) {
        self.onSignInComplete = onSignInComplete
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Apple Sign In Button
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .cornerRadius(12)

            // Google Sign In Button
            Button {
                Task {
                    await handleGoogleSignIn()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "g.circle.fill")
                        .font(.title2)
                    Text("Sign in with Google")
                        .font(.system(size: 17, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
            .disabled(isLoading)

            // Error Message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            // Loading Indicator
            if isLoading {
                ProgressView()
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Apple Sign In Handler

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success:
            Task {
                isLoading = true
                errorMessage = nil

                do {
                    try await authManager.signInWithApple()
                    onSignInComplete?()
                } catch {
                    errorMessage = error.localizedDescription
                }

                isLoading = false
            }

        case .failure(let error):
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                // User canceled, don't show error
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Google Sign In Handler

    private func handleGoogleSignIn() async {
        isLoading = true
        errorMessage = nil

        do {
            try await authManager.signInWithGoogle()
            onSignInComplete?()
        } catch {
            // Platform specific error handling within the block
            #if canImport(UIKit)
            if let error = error as? GoogleSignInError {
                if case .canceled = error {
                    // User canceled, don't show error
                    isLoading = false
                    return
                } else {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
            #else
            errorMessage = error.localizedDescription
            #endif
        }

        isLoading = false
    }
}

// MARK: - Preview

#Preview {
    SignInButtonsView()
        .padding()
        .environment(ThemeManager.shared)
        .environment(AuthManager.shared)
}
