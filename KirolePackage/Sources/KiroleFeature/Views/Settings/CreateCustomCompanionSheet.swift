import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Create Custom Companion Sheet

/// 3-step flow to create a user-uploaded companion (Inku-style):
/// Step 1 — pick + quantize a photo.
/// Step 2 — name + pick relationship.
/// Step 3 — pick persona voice + Roast Mode toggle.
/// Confirm persists to AppState and switches the active companion.
public struct CreateCustomCompanionSheet: View {

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .upload
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var processResult: AvatarProcessResult?
    @State private var name: String = ""
    @State private var relationship: CompanionRelationship = .pet
    @State private var personaVoice: CompanionPersonaVoice = .companion
    @State private var roastMode: Bool = false
    @State private var showRoastEducation = false
    @State private var isSaving = false
    @State private var saveError: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .background(theme.colors.background)
        .onChange(of: selectedPhoto) { _, newValue in
            handlePhotoSelection(newValue)
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 12)

            Text(stepTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)
                .padding(.top, 4)

            stepIndicator
                .padding(.top, 8)
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue
                          ? theme.colors.accent
                          : Color.gray.opacity(0.25))
                    .frame(width: s == step ? 24 : 12, height: 4)
                    .animation(.easeInOut(duration: 0.2), value: step)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch step {
                case .upload:
                    uploadStep
                case .identity:
                    identityStep
                case .voice:
                    voiceStep
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Step 1: Upload

    @ViewBuilder
    private var uploadStep: some View {
        VStack(spacing: 16) {
            Text("Upload anyone — your pet, your kid, yourself. They become your desk companion.")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 200, height: 200)

                #if canImport(UIKit)
                if let preview = processResult?.previewData,
                   let uiImage = UIImage(data: preview) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if isProcessing {
                    ProgressView().scaleEffect(1.3)
                } else {
                    placeholderArtwork
                }
                #else
                if isProcessing {
                    ProgressView().scaleEffect(1.3)
                } else {
                    placeholderArtwork
                }
                #endif

                // Transparent overlay makes the entire 200×200 tile the tap target —
                // matches SettingsAccountSection avatar upload pattern. Without this,
                // the placeholder "Tap to choose photo" lies: tap is bound to the
                // text link below instead of the obvious visual target.
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Color.clear
                }
                .disabled(isProcessing)
                .frame(width: 200, height: 200)
                .accessibilityLabel(processResult == nil ? "选择伴侣照片" : "更换伴侣照片")
                .accessibilityIdentifier("CreateCompanion_PickPhoto")
            }
            .contentShape(RoundedRectangle(cornerRadius: 24))

            if processResult != nil {
                Text("Tap photo to change · this is how it'll appear on the E-ink display.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Step 2: Identity

    @ViewBuilder
    private var identityStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Name")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
            TextField("e.g. Mochi", text: $name)
                .textFieldStyle(.plain)
                .padding(14)
                .background(Color(hex: "F3F4F6"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("CreateCompanion_NameField")

            Text("Who are they to you?")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
                .padding(.top, 8)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CompanionRelationship.allCases, id: \.self) { option in
                    Button {
                        relationship = option
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: option.iconName)
                                .font(.system(size: 14))
                            Text(option.displayName)
                                .font(.system(size: 14, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(relationship == option
                                      ? theme.colors.accent.opacity(0.15)
                                      : Color(hex: "F3F4F6"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(relationship == option
                                        ? theme.colors.accent
                                        : Color.clear, lineWidth: 1.5)
                        )
                        .foregroundStyle(theme.colors.primaryText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("CreateCompanion_Relationship_\(option.rawValue)")
                }
            }
        }
    }

    // MARK: - Step 3: Voice

    @ViewBuilder
    private var voiceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Voice")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            VStack(spacing: 10) {
                ForEach(CompanionPersonaVoice.allCases, id: \.self) { voice in
                    Button {
                        personaVoice = voice
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: voice.iconName)
                                .font(.system(size: 18))
                                .frame(width: 28)
                                .foregroundStyle(theme.colors.accent)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(voice.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(theme.colors.primaryText)
                                Text(voice.shortDescription)
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.colors.secondaryText)
                            }

                            Spacer()

                            if personaVoice == voice {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(theme.colors.accent)
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(hex: "F3F4F6"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(personaVoice == voice
                                        ? theme.colors.accent
                                        : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("CreateCompanion_Voice_\(voice.rawValue)")
                }
            }

            Toggle(isOn: Binding(
                get: { roastMode },
                set: { newValue in
                    if newValue {
                        showRoastEducation = true
                    } else {
                        roastMode = false
                    }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Roast Mode")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.colors.primaryText)
                    Text("Your companion will tease your habits. You can turn it off anytime.")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.secondaryText)
                }
            }
            .tint(theme.colors.accent)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(hex: "F3F4F6"))
            )
            .padding(.top, 4)
            .accessibilityIdentifier("CreateCompanion_RoastToggle")
            .alert("Enable Roast Mode?", isPresented: $showRoastEducation) {
                Button("Enable") { roastMode = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your companion will playfully tease your habits. This is meant to be affectionate, not harsh. You can turn it off anytime from Settings.")
            }

            if let saveError {
                Text(saveError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.red)
                    .padding(.top, 4)
                    .accessibilityIdentifier("CreateCompanion_SaveError")
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 12) {
            Button(action: handleBack) {
                Text(step == .upload ? "Cancel" : "Back")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: "F3F4F6"))
                    .foregroundStyle(theme.colors.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("CreateCompanion_Back")

            Button(action: handleNext) {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(step == .voice ? "Create" : "Next")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canAdvance && !isSaving
                            ? theme.colors.accent
                            : Color.gray.opacity(0.35))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(!canAdvance || isSaving)
            .accessibilityIdentifier("CreateCompanion_Next")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 12)
    }

    // MARK: - Logic

    private var stepTitle: String {
        switch step {
        case .upload: return "Pick a Photo"
        case .identity: return "Who Is This?"
        case .voice: return "How Do They Speak?"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .upload: return processResult != nil
        case .identity:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .voice: return true
        }
    }

    private func handleBack() {
        switch step {
        case .upload:
            dismiss()
        case .identity:
            step = .upload
        case .voice:
            step = .identity
        }
    }

    private func handleNext() {
        guard canAdvance else { return }
        switch step {
        case .upload:
            step = .identity
        case .identity:
            step = .voice
        case .voice:
            createAndDismiss()
        }
    }

    private func createAndDismiss() {
        guard let result = processResult, !isSaving else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pixelData = BLEDataEncoder.encodePixelData(
            result.pixels,
            width: AvatarProcessResult.dimension
        )
        isSaving = true
        saveError = nil
        Task {
            do {
                _ = try await appState.addCustomCompanion(
                    name: trimmedName,
                    relationship: relationship,
                    personaVoice: personaVoice,
                    roastModeEnabled: roastMode,
                    previewData: result.previewData,
                    pixelData: pixelData
                )
                dismiss()
            } catch {
                saveError = "Save failed. Please try again."
                isSaving = false
            }
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isProcessing = true
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            await MainActor.run {
                #if canImport(UIKit)
                if let data, let uiImage = UIImage(data: data),
                   let result = AvatarImageProcessor.process(image: uiImage) {
                    processResult = result
                }
                #endif
                isProcessing = false
            }
        }
    }

    @ViewBuilder
    private var placeholderArtwork: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(hex: "6B7280"))
            Text("Tap to choose photo")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}

// MARK: - Step Enum

private extension CreateCustomCompanionSheet {
    enum Step: Int, CaseIterable {
        case upload = 0
        case identity = 1
        case voice = 2
    }
}
