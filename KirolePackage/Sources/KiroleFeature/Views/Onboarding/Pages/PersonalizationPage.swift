import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public struct PersonalizationPage: View {
    private static let customPromptLimit = 1200

    let onboardingState: OnboardingState
    @Environment(ThemeManager.self) private var themeManager

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var processError: String?

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

                        themePicker

                        builtInCompanionPicker

                        customCompanionSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }

                OnboardingCTAButton(
                    title: "I'll Make It Mine",
                    emoji: "\u{1F3A8}",
                    isEnabled: canAdvance
                ) {
                    onboardingState.goNext()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            if onboardingState.profile.companionCharacter == nil {
                onboardingState.profile.companionCharacter = .joy
            }
            if onboardingState.profile.customCompanionRelationship == nil {
                onboardingState.profile.customCompanionRelationship = .pet
            }
            if onboardingState.profile.customCompanionVoice == nil {
                onboardingState.profile.customCompanionVoice = .companion
            }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            handlePhotoSelection(newValue)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var themePicker: some View {
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
    }

    @ViewBuilder
    private var builtInCompanionPicker: some View {
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
    }

    @ViewBuilder
    private var customCompanionSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Or upload your own")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                if onboardingState.profile.customAvatarPreviewData != nil {
                    Button {
                        clearCustomCompanion()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear custom companion")
                    .accessibilityIdentifier("Onboarding_ClearCustom")
                }
            }

            photoPreviewBlock

            photoPickerButton

            if onboardingState.profile.customAvatarPreviewData != nil {
                customCompanionForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let processError {
                Text(processError)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .accessibilityIdentifier("Onboarding_CustomCompanion_Error")
            }

            if shouldShowNameHint {
                // Without this hint, users who uploaded a photo + picked
                // relationship/voice but forgot to type a name would silently
                // lose their custom companion: completeOnboarding's
                // hasCustomCompanionDraft check requires a non-empty name, so
                // the whole upload would just be discarded with no UI feedback.
                Text("Give your companion a name to save them.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("Onboarding_CustomCompanion_NameHint")
            }
        }
        .animation(.kiroleSnappy, value: onboardingState.profile.customAvatarPreviewData != nil)
        .padding(.top, 8)
    }

    // MARK: - Advance gating

    private var hasCustomPhoto: Bool {
        onboardingState.profile.customAvatarPreviewData != nil
    }

    private var hasCustomName: Bool {
        let trimmed = (onboardingState.profile.customCompanionName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    private var usesCustomPromptVoice: Bool {
        (onboardingState.profile.customCompanionVoice ?? .companion) == .customPrompt
    }

    private var hasCustomPrompt: Bool {
        let trimmed = (onboardingState.profile.customCompanionPrompt ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    /// Users on the built-in 3-IP track (no photo) are free to advance.
    /// Users on the custom-IP track (photo uploaded) must also fill in a name,
    /// otherwise the upload silently drops on completeOnboarding.
    private var canAdvance: Bool {
        !hasCustomPhoto || (hasCustomName && (!usesCustomPromptVoice || hasCustomPrompt))
    }

    private var shouldShowNameHint: Bool {
        hasCustomPhoto && !hasCustomName
    }

    @ViewBuilder
    private var photoPreviewBlock: some View {
        #if canImport(UIKit)
        if let previewData = onboardingState.profile.customAvatarPreviewData,
           let uiImage = UIImage(data: previewData) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fill)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay {
                    RoundedRectangle(cornerRadius: 16).stroke(.white, lineWidth: 3)
                }
                .accessibilityLabel("Custom companion preview")
        } else if isProcessing {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.08))
                    .frame(width: 96, height: 96)
                ProgressView().tint(.white)
            }
            .accessibilityLabel("Processing image")
        }
        #endif
    }

    @ViewBuilder
    private var photoPickerButton: some View {
        let hasPhoto = onboardingState.profile.customAvatarPreviewData != nil
        PhotosPicker(
            selection: $selectedPhoto,
            matching: .images
        ) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16))
                    .accessibilityHidden(true)
                Text(hasPhoto ? "Change Photo" : "Choose Photo")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.white.opacity(0.2))
            .clipShape(Capsule())
        }
        .disabled(isProcessing)
        .accessibilityLabel(hasPhoto ? "Change custom image" : "Choose custom image")
        .accessibilityIdentifier("Onboarding_ChoosePhoto")
    }

    @ViewBuilder
    private var customCompanionForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Name them")
            TextField(
                "",
                text: Binding(
                    get: { onboardingState.profile.customCompanionName ?? "" },
                    set: { onboardingState.profile.customCompanionName = $0 }
                ),
                prompt: Text("e.g. Mochi").foregroundColor(.white.opacity(0.4))
            )
            .textFieldStyle(.plain)
            .foregroundStyle(.white)
            .autocorrectionDisabled()
            .padding(14)
            .background(.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("Custom companion name")
            .accessibilityIdentifier("Onboarding_CustomCompanion_Name")

            sectionHeader("Who are they to you?")
                .padding(.top, 4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(CompanionRelationship.allCases, id: \.self) { option in
                    relationshipPill(option)
                }
            }

            sectionHeader("Voice")
                .padding(.top, 4)
            VStack(spacing: 8) {
                ForEach(CompanionPersonaVoice.allCases, id: \.self) { voice in
                    voiceCard(voice)
                }
            }

            if usesCustomPromptVoice {
                customPromptEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Toggle(isOn: Binding(
                get: { onboardingState.profile.customCompanionRoast },
                set: { onboardingState.profile.customCompanionRoast = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Roast Mode")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Lovingly call out your bad habits.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .tint(.white)
            .padding(14)
            .background(.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 4)
            .accessibilityIdentifier("Onboarding_CustomCompanion_Roast")
        }
    }

    @ViewBuilder
    private var customPromptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Custom Prompt")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            Text("Describe how this companion should speak. Kirole still keeps safety, schedule context, and short replies.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            TextEditor(text: onboardingCustomPromptBinding)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white)
                .frame(minHeight: 96, maxHeight: 130)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("Onboarding_CustomCompanion_CustomPrompt")
                .accessibilityLabel("Custom companion voice prompt")
            HStack {
                if !hasCustomPrompt {
                    Text("Required for Custom Prompt")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Text("\((onboardingState.profile.customCompanionPrompt ?? "").count)/\(Self.customPromptLimit)")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.top, 2)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
    }

    private func relationshipPill(_ option: CompanionRelationship) -> some View {
        let selected = (onboardingState.profile.customCompanionRelationship ?? .pet) == option
        return Button {
            onboardingState.profile.customCompanionRelationship = option
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.iconName)
                    .font(.system(size: 13))
                Text(option.displayName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.white.opacity(0.25) : Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Color.white : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "Current relationship: \(option.displayName)" : "Select relationship \(option.displayName)")
        .accessibilityIdentifier("Onboarding_CustomCompanion_Relationship_\(option.rawValue)")
    }

    private func voiceCard(_ voice: CompanionPersonaVoice) -> some View {
        let selected = (onboardingState.profile.customCompanionVoice ?? .companion) == voice
        return Button {
            onboardingState.profile.customCompanionVoice = voice
        } label: {
            HStack(spacing: 10) {
                Image(systemName: voice.iconName)
                    .font(.system(size: 16))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.displayName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(voice.shortDescription)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.white.opacity(0.20) : Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.white : Color.clear, lineWidth: 1.5)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selected ? "Current voice: \(voice.displayName)" : "Select voice \(voice.displayName)")
        .accessibilityIdentifier("Onboarding_CustomCompanion_Voice_\(voice.rawValue)")
    }

    private var onboardingCustomPromptBinding: Binding<String> {
        Binding(
            get: { onboardingState.profile.customCompanionPrompt ?? "" },
            set: {
                onboardingState.profile.customCompanionPrompt = String($0.prefix(Self.customPromptLimit))
            }
        )
    }

    // MARK: - Actions

    private func clearCustomCompanion() {
        onboardingState.profile.customAvatarPreviewData = nil
        onboardingState.profile.customAvatarPixelData = nil
        onboardingState.profile.customCompanionName = nil
        onboardingState.profile.customCompanionPrompt = nil
        onboardingState.profile.customCompanionRoast = false
        selectedPhoto = nil
        processError = nil
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isProcessing = true
        processError = nil
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                applyProcessedPhoto(data: data)
                isProcessing = false
            }
        }
    }

    private func applyProcessedPhoto(data: Data?) {
        #if canImport(UIKit)
        guard let data,
              let uiImage = UIImage(data: data),
              let result = AvatarImageProcessor.process(image: uiImage) else {
            processError = "Couldn't process this image. Try another."
            return
        }
        let pixelData = BLEDataEncoder.encodePixelData(
            result.pixels,
            width: AvatarProcessResult.dimension
        )
        onboardingState.profile.customAvatarPreviewData = result.previewData
        onboardingState.profile.customAvatarPixelData = pixelData
        #else
        _ = data
        processError = "Image processing unavailable on this platform."
        #endif
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
                    .accessibilityHidden(true)

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
        .accessibilityLabel(isSelected ? "Current companion: \(character.displayName)" : "Select \(character.displayName) as companion")
        .accessibilityIdentifier("Onboarding_Character_\(character.displayName)")
    }
}

private extension CompanionCharacter {
    var tagline: String {
        switch self {
        case .joy: return "Joy"
        case .silas: return "Care"
        case .nova: return "Discipline"
        }
    }
}
