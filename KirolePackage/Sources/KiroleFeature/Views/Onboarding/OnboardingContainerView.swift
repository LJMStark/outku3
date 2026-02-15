import SwiftUI

// MARK: - Onboarding Container

public struct OnboardingContainerView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AuthManager.self) private var authManager

    @State private var onboardingState = OnboardingState()

    public init() {}

    public var body: some View {
        ZStack {
            pageView(for: onboardingState.currentPage)
                .id(onboardingState.currentPage)
                .transition(.asymmetric(
                    insertion: .move(edge: onboardingState.direction > 0 ? .trailing : .leading),
                    removal: .move(edge: onboardingState.direction > 0 ? .leading : .trailing)
                ))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: onboardingState.currentPage)
        }
        .environment(themeManager)
        .environment(authManager)
        .environment(appState)
    }

    @ViewBuilder
    private func pageView(for page: Int) -> some View {
        switch page {
        case 0:
            WelcomePage(onboardingState: onboardingState)
        case 1:
            FeatureCalendarPage(onboardingState: onboardingState)
        case 2:
            FeatureFocusPage(onboardingState: onboardingState)
        case 3:
            TextAnimationPage(onboardingState: onboardingState)
        case 4:
            PersonalizationPage(onboardingState: onboardingState)
        case 5, 6, 7, 8, 9, 10, 11, 12:
            QuestionnairePage(onboardingState: onboardingState, questionIndex: page - 5)
        case 13:
            SignUpPage(onboardingState: onboardingState)
        default:
            WelcomePage(onboardingState: onboardingState)
        }
    }
}
