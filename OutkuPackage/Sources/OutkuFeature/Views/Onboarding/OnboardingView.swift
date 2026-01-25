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
                Spacer()
                
                // Pet / Shadow Centerpiece
                if manager.currentStep != .awakening {
                    MorphingPetView(
                        form: manager.selectedForm,
                        isShadowMode: manager.isShadowMode,
                        isRevealed: manager.isRevealed
                    )
                    // Matched Geometry could go here for sophisticated moves
                    .padding(.bottom, 40)
                }
                
                // Dialog & Interactions
                VStack(spacing: 24) {
                    // Chat Bubble
                    if !manager.dialogText.isEmpty {
                        DialogBubble(text: manager.dialogText, isTyping: manager.isTyping)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    // Interaction Area
                    switch manager.currentStep {
                    case .awakening:
                        // Tap anywhere to wake handled by background tap
                        Text("Tap to Wake")
                            .font(AppTypography.body)
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.top, 100)
                            .opacity(0.6)
                            .animation(.easeInOut(duration: 1.5).repeatForever(), value: true)
                        
                    case .conversation:
                        if manager.showChoices {
                            VStack(spacing: 12) {
                                ChoicePill(title: "Hello?") {
                                    withAnimation {
                                        // Simple script progression for MVP
                                        manager.startDialog(text: "I was waiting for you. Do you know what I look like?")
                                    }
                                }
                                
                                // Form Selection embedded in chat
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(PetForm.allCases, id: \.self) { form in
                                            Button {
                                                manager.selectForm(form)
                                            } label: {
                                                VStack {
                                                    Image(systemName: formIcon(for: form))
                                                        .font(.title)
                                                        .foregroundStyle(manager.selectedForm == form ? theme.colors.accent : .white)
                                                    Text(form.rawValue)
                                                        .font(AppTypography.caption)
                                                        .foregroundStyle(.white.opacity(0.8))
                                                }
                                                .padding()
                                                .background(
                                                    Circle()
                                                        .fill(.white.opacity(0.1))
                                                        .stroke(manager.selectedForm == form ? theme.colors.accent : .clear, lineWidth: 2)
                                                )
                                            }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                                .padding(.top, 10)
                                
                                Button("You look like this!") {
                                    withAnimation {
                                        manager.currentStep = .naming
                                        manager.startDialog(text: "I like this form. Do you have a name for me?")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.colors.accent)
                                .padding(.top)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                    case .naming:
                        if manager.showChoices {
                            VStack(spacing: 20) {
                                TextField("Enter Name", text: $manager.petName)
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
                                
                                Button {
                                    manager.confirmName()
                                } label: {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(theme.colors.accent)
                                }
                                .disabled(manager.petName.isEmpty)
                            }
                            .onAppear { isNameFocused = true }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        
                    case .reveal:
                        // Just wait for animation sequence
                        EmptyView()
                        
                    case .sanctuary:
                        // Setup List
                        if manager.showChoices {
                            VStack(spacing: 16) {
                                Text("Let's set up our home.")
                                    .font(AppTypography.headline)
                                    .foregroundStyle(theme.colors.secondaryText)
                                
                                Button("Finish & Explore") {
                                    manager.completeOnboarding()
                                    isOnboardingComplete = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(theme.colors.accent)
                                .padding(.top, 20)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(theme.colors.cardBackground)
                                    .shadow(radius: 10)
                            )
                            .padding(.horizontal)
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                    case .complete:
                        EmptyView()
                    }
                }
                .padding(.bottom, 60)
            }
            // Tap to Wake (Global hit area for first step)
            .contentShape(Rectangle())
            .onTapGesture {
                if manager.currentStep == .awakening {
                    manager.wakeUp()
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
    }
    
    private func formIcon(for form: PetForm) -> String {
        switch form {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .bunny: return "hare.fill"
        case .bird: return "bird.fill"
        case .dragon: return "flame.fill"
        }
    }
}

// MARK: - Preview
#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
