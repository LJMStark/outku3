import SwiftUI
import PhotosUI

@MainActor
public struct PersonalizationPage: View {
    let onboardingState: OnboardingState
    @Environment(ThemeManager.self) private var themeManager

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoImage: Image?

    public init(onboardingState: OnboardingState) {
        self.onboardingState = onboardingState
    }

    public var body: some View {
        ZStack {
            themeManager.colors.primary.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    SoundToggleButton(isEnabled: Binding(
                        get: { onboardingState.soundEnabled },
                        set: { onboardingState.soundEnabled = $0 }
                    ))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                ProgressDots(activeIndex: 3)
                    .padding(.top, 8)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        Text("Your Kirole, Your Way \u{1F3A8}")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        // Theme picker
                        VStack(spacing: 16) {
                            Text("Pick your favorite mood")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                            HStack(spacing: 12) {
                                ForEach(AppTheme.allCases, id: \.self) { theme in
                                    ThemePreviewCard(
                                        theme: theme,
                                        isSelected: themeManager.currentTheme == theme
                                    ) {
                                        themeManager.setTheme(theme)
                                        onboardingState.profile.selectedTheme = theme.rawValue
                                    }
                                }
                            }
                        }

                        // Companion IP selector
                        VStack(spacing: 16) {
                            Text("Meet your companion")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))

                            HStack(spacing: 12) {
                                ForEach(CompanionCharacter.allCases, id: \.self) { character in
                                    CompanionCharacterCard(
                                        character: character,
                                        isSelected: onboardingState.profile.companionCharacter == character
                                    ) {
                                        onboardingState.profile.companionCharacter = character
                                    }
                                }
                            }
                        }

                        // Custom photo upload
                        VStack(spacing: 16) {
                            Text("Or upload your own")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))

                            if let photoImage {
                                photoImage
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 80, height: 80)
                                    .clipShape(Circle())
                                    .overlay {
                                        Circle().stroke(.white, lineWidth: 3)
                                    }
                            }

                            let hasPhotoImage = photoImage != nil
                            PhotosPicker(
                                selection: $selectedPhoto,
                                matching: .images
                            ) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 16))
                                    Text(hasPhotoImage ? "Change Photo" : "Choose Photo")
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.2))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }

                OnboardingCTAButton(title: "I'll Make It Mine", emoji: "\u{1F3A8}") {
                    onboardingState.goNext()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            if onboardingState.profile.companionCharacter == nil {
                onboardingState.profile.companionCharacter = .nook
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self) else { return }
                await MainActor.run {
                    onboardingState.profile.customPhotoData = data
                    #if canImport(UIKit)
                    if let uiImage = UIImage(data: data) {
                        photoImage = Image(uiImage: uiImage)
                    }
                    #endif
                }
            }
        }
    }
}

// MARK: - Companion Character Card

@MainActor
private struct CompanionCharacterCard: View {
    let character: CompanionCharacter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(character.heroAssetName(variant: .main), bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .padding(8)
                    .background(.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(character.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(character.tagline)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? .white.opacity(0.18) : .white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white, lineWidth: isSelected ? 3 : 0)
            )
            .scaleEffect(isSelected ? 1.04 : 1.0)
            .shadow(color: .black.opacity(isSelected ? 0.2 : 0.1), radius: isSelected ? 10 : 6, y: 4)
            .animation(.kiroleSnappy, value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

private extension CompanionCharacter {
    var tagline: String {
        switch self {
        case .nook: return "Playful"
        case .silas: return "Spiritual"
        case .nova: return "Challenge"
        }
    }
}
