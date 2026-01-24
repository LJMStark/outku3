import SwiftUI

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Binding var isOnboardingComplete: Bool

    @State private var currentPage: Int = 0
    @State private var petName: String = ""
    @State private var selectedPronouns: PetPronouns = .theyThem
    @State private var selectedForm: PetForm = .cat

    private let totalPages = 5

    var body: some View {
        ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressView(currentPage: currentPage, totalPages: totalPages)
                    .padding(.top, AppSpacing.xl)
                    .padding(.horizontal, AppSpacing.xl)

                // Content
                TabView(selection: $currentPage) {
                    WelcomePage()
                        .tag(0)

                    StoryPage()
                        .tag(1)

                    PetFormSelectionPage(selectedForm: $selectedForm)
                        .tag(2)

                    PetNamingPage(petName: $petName, selectedPronouns: $selectedPronouns)
                        .tag(3)

                    CompletionPage(
                        petName: petName.isEmpty ? "Your Pet" : petName,
                        selectedForm: selectedForm
                    )
                    .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Navigation buttons
                OnboardingNavigationView(
                    currentPage: $currentPage,
                    totalPages: totalPages,
                    canProceed: canProceedToNextPage,
                    onComplete: completeOnboarding
                )
                .padding(.horizontal, AppSpacing.xl)
                .padding(.bottom, AppSpacing.xxl)
            }
        }
    }

    private var canProceedToNextPage: Bool {
        switch currentPage {
        case 3:
            return !petName.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return true
        }
    }

    private func completeOnboarding() {
        // Save pet settings
        appState.pet.name = petName.trimmingCharacters(in: .whitespaces)
        appState.pet.pronouns = selectedPronouns
        appState.pet.currentForm = selectedForm

        withAnimation(.easeInOut(duration: 0.5)) {
            isOnboardingComplete = true
        }
    }
}

// MARK: - Progress View

struct OnboardingProgressView: View {
    let currentPage: Int
    let totalPages: Int
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index <= currentPage ? theme.colors.accent : theme.colors.timeline)
                    .frame(height: 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
    }
}

// MARK: - Navigation View

struct OnboardingNavigationView: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let canProceed: Bool
    let onComplete: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            // Back button
            if currentPage > 0 {
                Button {
                    withAnimation {
                        currentPage -= 1
                    }
                } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(AppTypography.body)
                    .foregroundStyle(theme.colors.secondaryText)
                }
            }

            Spacer()

            // Next/Complete button
            Button {
                if currentPage < totalPages - 1 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    onComplete()
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Text(currentPage < totalPages - 1 ? "Next" : "Let's Go!")
                    if currentPage < totalPages - 1 {
                        Image(systemName: "chevron.right")
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .font(AppTypography.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
                .background {
                    Capsule()
                        .fill(canProceed ? theme.colors.accent : theme.colors.secondaryText.opacity(0.5))
                }
            }
            .disabled(!canProceed)
        }
    }
}

// MARK: - Welcome Page

struct WelcomePage: View {
    @Environment(ThemeManager.self) private var theme
    @State private var showContent = false

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            // App icon/logo
            ZStack {
                Circle()
                    .fill(theme.colors.accent.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "pawprint.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(theme.colors.accent)
            }
            .scaleEffect(showContent ? 1 : 0.5)
            .opacity(showContent ? 1 : 0)

            VStack(spacing: AppSpacing.md) {
                Text("Welcome to Outku")
                    .font(AppTypography.largeTitle)
                    .foregroundStyle(theme.colors.primaryText)

                Text("Your companion for building better habits")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2)) {
                showContent = true
            }
        }
    }
}

// MARK: - Story Page

struct StoryPage: View {
    @Environment(ThemeManager.self) private var theme
    @State private var showContent = false
    @State private var currentTextIndex = 0

    private let storyTexts = [
        "In a world where tasks pile up and habits fade away...",
        "A little companion awaits to join your journey.",
        "Together, you'll turn everyday tasks into adventures.",
        "Every completed task helps your pet grow stronger."
    ]

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            // Animated pet silhouette
            ZStack {
                Circle()
                    .fill(theme.colors.cardBackground)
                    .frame(width: 180, height: 180)
                    .shadow(color: theme.colors.accent.opacity(0.3), radius: 20)

                Image(systemName: "questionmark")
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(theme.colors.accent.opacity(0.5))
            }
            .scaleEffect(showContent ? 1 : 0.8)
            .opacity(showContent ? 1 : 0)

            // Story text
            VStack(spacing: AppSpacing.lg) {
                ForEach(0..<storyTexts.count, id: \.self) { index in
                    if index <= currentTextIndex {
                        Text(storyTexts[index])
                            .font(AppTypography.body)
                            .foregroundStyle(theme.colors.primaryText)
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.5), value: currentTextIndex)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showContent = true
            }

            // Animate story text appearance
            for i in 0..<storyTexts.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.8 + 0.5) {
                    withAnimation {
                        currentTextIndex = i
                    }
                }
            }
        }
    }
}

// MARK: - Pet Form Selection Page

struct PetFormSelectionPage: View {
    @Binding var selectedForm: PetForm
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var showContent = false

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            VStack(spacing: AppSpacing.md) {
                Text("Choose Your Companion")
                    .font(AppTypography.title)
                    .foregroundStyle(theme.colors.primaryText)

                Text("What form will your pet take?")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .opacity(showContent ? 1 : 0)

            // Pet preview
            ZStack {
                Circle()
                    .fill(theme.colors.cardBackground)
                    .frame(width: 160, height: 160)
                    .shadow(color: theme.colors.accent.opacity(0.2), radius: 15)

                // Temporarily set form for preview
                PixelPetView(size: .large, animated: true)
                    .frame(width: 120, height: 120)
                    .onAppear {
                        appState.pet.currentForm = selectedForm
                    }
                    .onChange(of: selectedForm) { _, newValue in
                        appState.pet.currentForm = newValue
                    }
            }
            .scaleEffect(showContent ? 1 : 0.8)
            .opacity(showContent ? 1 : 0)

            // Form selection grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: AppSpacing.lg) {
                ForEach(PetForm.allCases, id: \.self) { form in
                    PetFormButton(
                        form: form,
                        isSelected: selectedForm == form,
                        action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedForm = form
                            }
                        }
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                showContent = true
            }
        }
    }
}

struct PetFormButton: View {
    let form: PetForm
    let isSelected: Bool
    let action: () -> Void
    @Environment(ThemeManager.self) private var theme

    private var formIcon: String {
        switch form {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .bunny: return "hare.fill"
        case .bird: return "bird.fill"
        case .dragon: return "flame.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.sm) {
                ZStack {
                    Circle()
                        .fill(isSelected ? theme.colors.accent : theme.colors.cardBackground)
                        .frame(width: 60, height: 60)

                    Image(systemName: formIcon)
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? .white : theme.colors.secondaryText)
                }

                Text(form.rawValue)
                    .font(AppTypography.caption)
                    .foregroundStyle(isSelected ? theme.colors.accent : theme.colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Pet Naming Page

struct PetNamingPage: View {
    @Binding var petName: String
    @Binding var selectedPronouns: PetPronouns
    @Environment(ThemeManager.self) private var theme
    @FocusState private var isNameFieldFocused: Bool
    @State private var showContent = false

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            VStack(spacing: AppSpacing.md) {
                Text("Name Your Pet")
                    .font(AppTypography.title)
                    .foregroundStyle(theme.colors.primaryText)

                Text("Give your companion a special name")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.colors.secondaryText)
            }
            .opacity(showContent ? 1 : 0)

            // Name input
            VStack(spacing: AppSpacing.lg) {
                TextField("Enter a name...", text: $petName)
                    .font(AppTypography.title2)
                    .foregroundStyle(theme.colors.primaryText)
                    .multilineTextAlignment(.center)
                    .padding(AppSpacing.lg)
                    .background {
                        RoundedRectangle(cornerRadius: AppCornerRadius.medium)
                            .fill(theme.colors.cardBackground)
                    }
                    .focused($isNameFieldFocused)

                // Pronouns selection
                VStack(spacing: AppSpacing.md) {
                    Text("Pronouns")
                        .font(AppTypography.subheadline)
                        .foregroundStyle(theme.colors.secondaryText)

                    HStack(spacing: AppSpacing.md) {
                        ForEach(PetPronouns.allCases, id: \.self) { pronouns in
                            PronounsButton(
                                pronouns: pronouns,
                                isSelected: selectedPronouns == pronouns,
                                action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        selectedPronouns = pronouns
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                showContent = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNameFieldFocused = true
            }
        }
    }
}

struct PronounsButton: View {
    let pronouns: PetPronouns
    let isSelected: Bool
    let action: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: action) {
            Text(pronouns.rawValue)
                .font(AppTypography.subheadline)
                .foregroundStyle(isSelected ? .white : theme.colors.primaryText)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background {
                    Capsule()
                        .fill(isSelected ? theme.colors.accent : theme.colors.cardBackground)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Completion Page

struct CompletionPage: View {
    let petName: String
    let selectedForm: PetForm
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var showContent = false
    @State private var showPet = false

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            Spacer()

            // Pet reveal
            ZStack {
                // Glow effect
                Circle()
                    .fill(theme.colors.accent.opacity(0.2))
                    .frame(width: 200, height: 200)
                    .blur(radius: 20)
                    .scaleEffect(showPet ? 1.2 : 0.5)
                    .opacity(showPet ? 1 : 0)

                Circle()
                    .fill(theme.colors.cardBackground)
                    .frame(width: 180, height: 180)
                    .shadow(color: theme.colors.accent.opacity(0.3), radius: 20)

                PixelPetView(size: .large, animated: true)
                    .frame(width: 140, height: 140)
            }
            .scaleEffect(showPet ? 1 : 0.3)
            .opacity(showPet ? 1 : 0)

            VStack(spacing: AppSpacing.md) {
                Text("Meet \(petName)!")
                    .font(AppTypography.title)
                    .foregroundStyle(theme.colors.primaryText)

                Text("Your adventure begins now.\nComplete tasks to help \(petName) grow!")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)

            // Stats preview
            HStack(spacing: AppSpacing.xl) {
                StatPreview(icon: "star.fill", label: "Adventures", value: "0")
                StatPreview(icon: "flame.fill", label: "Streak", value: "0 days")
                StatPreview(icon: "heart.fill", label: "Status", value: "Happy")
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 30)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, AppSpacing.xl)
        .onAppear {
            appState.pet.currentForm = selectedForm

            withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
                showPet = true
            }

            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.6)) {
                showContent = true
            }
        }
    }
}

struct StatPreview: View {
    let icon: String
    let label: String
    let value: String
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(theme.colors.accent)

            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(theme.colors.secondaryText)

            Text(value)
                .font(AppTypography.subheadline)
                .foregroundStyle(theme.colors.primaryText)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(isOnboardingComplete: .constant(false))
        .environment(AppState.shared)
        .environment(ThemeManager.shared)
}
