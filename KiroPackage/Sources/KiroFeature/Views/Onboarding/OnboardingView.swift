import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Binding var isOnboardingComplete: Bool

    @State private var manager = OnboardingFlowManager()
    @FocusState private var isNameFocused: Bool

    var body: some View {
        ZStack {
            // 1. Dynamic Background
            CinematicBackground(step: manager.currentStep)

            // 2. Main Content
            VStack {
                // Back button for applicable steps
                if canGoBack {
                    HStack {
                        Button {
                            manager.goToPreviousStep()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.6))
                                .padding()
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                }

                // Step Content
                switch manager.currentStep {
                case .welcome:
                    OnboardingWelcomeStep {
                        manager.goToNextStep()
                    }

                case .identity:
                    OnboardingIdentityStep(
                        selectedWorkType: manager.selectedWorkType,
                        onSelect: { manager.selectWorkType($0) }
                    )

                case .goals:
                    OnboardingGoalsStep(
                        selectedGoals: manager.selectedGoals,
                        onToggle: { manager.toggleGoal($0) },
                        onContinue: { manager.goToNextStep() }
                    )

                case .companionStyle:
                    OnboardingStyleStep(
                        selectedStyle: manager.selectedCompanionStyle,
                        onSelect: { manager.selectCompanionStyle($0) }
                    )

                case .awakening:
                    awakeningContent

                case .naming:
                    namingContent

                case .connect:
                    connectContent

                case .complete:
                    EmptyView()
                }
            }

            // 3. Flash Overlay
            if manager.showFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .onAppear {
            manager.setAppState(appState)
        }
        .onDisappear {
            manager.cancelAllTasks()
        }
    }

    // MARK: - Awakening Content

    private var awakeningContent: some View {
        VStack {
            Spacer()

            // Shadow Pet
            MorphingPetView(
                form: appState.pet.currentForm,
                isShadowMode: manager.isShadowMode,
                isRevealed: manager.isRevealed
            )
            .padding(.bottom, 40)

            // Dialog
            if !manager.dialogText.isEmpty {
                DialogBubble(text: manager.dialogText, isTyping: manager.isTyping)
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()

            // Tap to continue or Skip
            HStack {
                Button {
                    manager.skipAwakening()
                } label: {
                    Text("Skip")
                        .font(AppTypography.body)
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                if manager.showChoices {
                    Button {
                        manager.advanceAwakeningDialog()
                    } label: {
                        Text("Tap to continue")
                            .font(AppTypography.body)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if manager.showChoices {
                manager.advanceAwakeningDialog()
            }
        }
    }

    // MARK: - Naming Content

    private var namingContent: some View {
        VStack {
            Spacer()

            // Pet (revealed or shadow)
            MorphingPetView(
                form: appState.pet.currentForm,
                isShadowMode: manager.isShadowMode,
                isRevealed: manager.isRevealed
            )
            .padding(.bottom, 40)

            // Dialog
            if !manager.dialogText.isEmpty {
                DialogBubble(text: manager.dialogText, isTyping: manager.isTyping)
                    .padding(.horizontal, 24)
            }

            // Name Input
            VStack(spacing: 20) {
                TextField("Enter a name", text: $manager.petName)
                    .font(AppTypography.title)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        manager.confirmName()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(.white.opacity(0.1))
                    )
                    .padding(.horizontal, 40)

                // Suggested names
                HStack(spacing: 12) {
                    ForEach(manager.suggestedNames, id: \.self) { name in
                        Button {
                            manager.selectSuggestedName(name)
                        } label: {
                            Text(name)
                                .font(AppTypography.caption)
                                .foregroundStyle(.white.opacity(0.8))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(manager.petName == name ? 0.2 : 0.1))
                                        .stroke(.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }

                // Confirm button
                Button {
                    manager.confirmName()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(theme.colors.accent)
                }
                .disabled(!manager.canProceedFromNaming)
                .opacity(manager.canProceedFromNaming ? 1 : 0.4)
            }
            .padding(.top, 24)

            Spacer()
        }
        .onAppear {
            isNameFocused = true
        }
    }

    // MARK: - Connect Content

    private var connectContent: some View {
        VStack {
            Spacer()

            // Revealed Pet
            MorphingPetView(
                form: appState.pet.currentForm,
                isShadowMode: false,
                isRevealed: true
            )
            .padding(.bottom, 40)

            // Dialog
            if !manager.dialogText.isEmpty {
                DialogBubble(text: manager.dialogText, isTyping: manager.isTyping)
                    .padding(.horizontal, 24)
            }

            // Connect Card
            VStack(spacing: 20) {
                Text("Connect Your Calendar")
                    .font(AppTypography.headline)
                    .foregroundStyle(.white)

                Text("Sync your calendar and tasks to help \(appState.pet.name) understand your day")
                    .font(AppTypography.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                OnboardingSignInSection(onComplete: {
                    manager.completeOnboarding()
                    isOnboardingComplete = true
                })

                Button("Skip for now") {
                    manager.skipConnect()
                    isOnboardingComplete = true
                }
                .font(AppTypography.body)
                .foregroundStyle(.white.opacity(0.6))
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    // MARK: - Helpers

    private var canGoBack: Bool {
        [.identity, .goals, .companionStyle].contains(manager.currentStep)
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
        .environment(AuthManager.shared)
}
