import SwiftUI
import PhotosUI

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
            Color(hex: "0D8A6A").ignoresSafeArea()

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

                        // Pet display
                        VStack(spacing: 16) {
                            Text("Meet your companion")
                                .font(.system(size: 16, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))

                            // TODO: Replace with Kirole pet asset
                            Image("inku-main", bundle: .module)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 24))
                                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
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

                            PhotosPicker(
                                selection: $selectedPhoto,
                                matching: .images
                            ) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo.on.rectangle.angled")
                                        .font(.system(size: 16))
                                    Text(photoImage == nil ? "Choose Photo" : "Change Photo")
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
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
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
