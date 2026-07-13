import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Create Custom Companion Sheet

/// 4-step flow to create a user-uploaded companion (Kindroid-inspired):
/// Step 1 — pick a photo (processed into the hardware PNG by AvatarImageProcessor).
/// Step 2 — name + pick relationship.
/// Step 3 — pick persona voice.
/// Step 4 — persona dimensions (sliders + backstory + sensitive boundary).
/// Confirm persists to AppState and switches the active companion.
public struct CreateCustomCompanionSheet: View {
    private static let customPromptLimit = 1200

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .upload
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessing = false
    // Monotonic token: only the latest photo selection's async result is applied,
    // so a slow earlier load can't overwrite a newer pick (stale-result race).
    @State private var photoRequestID = 0
    @State private var processResult: AvatarProcessResult?
    @State private var name: String = ""
    @State private var relationship: CompanionRelationship = .pet
    @State private var personaVoice: CompanionPersonaVoice = .companion
    @State private var customPrompt: String = ""
    @State private var curiosityLevel: Double = 0.5
    @State private var humorLevel: Double = 0.5
    @State private var strictnessLevel: Double = 0.3
    @State private var backstory: String = ""
    @State private var sensitiveBoundary: String = ""
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
                case .personality:
                    personalityStep
                }

                // Shown regardless of the active step: photo-load failures surface on the
                // upload step, save failures on the personality step. Pinning this to a
                // single step (as it was) meant the error was set while a different step
                // was on screen, so the user never saw it.
                if let saveError {
                    Text(saveError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("CreateCompanion_SaveError")
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
                .accessibilityLabel(processResult == nil ? "Choose companion photo" : "Change companion photo")
                .accessibilityIdentifier("CreateCompanion_PickPhoto")
            }
            .contentShape(RoundedRectangle(cornerRadius: 24))

            if processResult != nil {
                Text("Tap photo to change. Kirole's 6-color E-ink screen shows it softer and more muted than your photo — that's expected.")
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            personaVoice = voice
                        }
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

            if personaVoice == .customPrompt {
                customPromptEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var customPromptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom Prompt")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)
            Text("Describe exactly how this companion should speak. Global safety, schedule context, and short output rules still apply.")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
            TextEditor(text: customPromptBinding)
                .font(.system(size: 14))
                .frame(minHeight: 120, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Color(hex: "F3F4F6"))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("CreateCompanion_CustomPrompt")
                .accessibilityLabel("Custom companion voice prompt")
            HStack {
                if customPromptTrimmed.isEmpty {
                    Text("Required when Custom Prompt is selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.red.opacity(0.8))
                }
                Spacer()
                Text("\(customPrompt.count)/\(Self.customPromptLimit)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.secondaryText)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Step 4: Personality

    @ViewBuilder
    private var personalityStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shape how they think and talk. All optional — defaults work great.")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.secondaryText)

            personalitySlider(
                label: "Curiosity",
                value: $curiosityLevel,
                lowLabel: "Quiet observer",
                highLabel: "Always wondering",
                identifier: "CreateCompanion_Curiosity"
            )
            personalitySlider(
                label: "Humor",
                value: $humorLevel,
                lowLabel: "Earnest",
                highLabel: "Playfully witty",
                identifier: "CreateCompanion_Humor"
            )
            personalitySlider(
                label: "Accountability",
                value: $strictnessLevel,
                lowLabel: "Gentle",
                highLabel: "Firm standards",
                identifier: "CreateCompanion_Strictness"
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Backstory")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Text("Who are they? What makes them unique? (optional)")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
                TextEditor(text: $backstory)
                    .font(.system(size: 14))
                    .frame(minHeight: 80, maxHeight: 120)
                    .padding(10)
                    .background(Color(hex: "F3F4F6"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("CreateCompanion_Backstory")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Topic Boundary")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Text("e.g. \"Tease my procrastination, but skip work stress\" (optional)")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
                TextField("Your preference here…", text: $sensitiveBoundary, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(3)
                    .padding(12)
                    .background(Color(hex: "F3F4F6"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("CreateCompanion_SensitiveBoundary")
            }
        }
    }

    @ViewBuilder
    private func personalitySlider(
        label: String,
        value: Binding<Double>,
        lowLabel: String,
        highLabel: String,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.primaryText)
                Spacer()
            }
            Slider(value: value, in: 0...1)
                .tint(theme.colors.accent)
                .accessibilityIdentifier(identifier)
            HStack {
                Text(lowLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.secondaryText)
                Spacer()
                Text(highLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.colors.secondaryText)
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
                        Text(step == .personality ? "Create" : "Next")
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
        case .personality: return "Shape Their Personality"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .upload: return processResult != nil
        case .identity:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .voice:
            return personaVoice != .customPrompt || !customPromptTrimmed.isEmpty
        case .personality: return true
        }
    }

    private func handleBack() {
        // Clear any error before changing steps. The error view renders step-agnostically,
        // so a stale message (e.g. "Save failed") would otherwise bleed onto an unrelated step.
        saveError = nil
        switch step {
        case .upload:
            dismiss()
        case .identity:
            step = .upload
        case .voice:
            step = .identity
        case .personality:
            step = .voice
        }
    }

    private func handleNext() {
        guard canAdvance else { return }
        // Clear stale errors when advancing so a prior step's message doesn't follow the user.
        saveError = nil
        switch step {
        case .upload:
            step = .identity
        case .identity:
            step = .voice
        case .voice:
            step = .personality
        case .personality:
            createAndDismiss()
        }
    }

    private func createAndDismiss() {
        guard let result = processResult, !isSaving else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isSaving = true
        saveError = nil
        Task {
            do {
                _ = try await appState.addCustomCompanion(
                    name: trimmedName,
                    relationship: relationship,
                    personaVoice: personaVoice,
                    customPrompt: personaVoice == .customPrompt ? customPromptTrimmed : "",
                    curiosityLevel: curiosityLevel,
                    humorLevel: humorLevel,
                    strictnessLevel: strictnessLevel,
                    backstory: backstory,
                    sensitiveBoundary: sensitiveBoundary,
                    previewData: result.previewData,
                    imageData: result.imageData
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
        // Invalidate any in-flight selection: a newer pick supersedes an older,
        // possibly-slower one (e.g. a large iCloud photo that finishes downloading last).
        photoRequestID += 1
        let requestID = photoRequestID
        isProcessing = true
        saveError = nil
        Task {
            do {
                let data = try await item.loadTransferable(type: Data.self)
                // Heavy decode + multi-round PNG encode runs OFF the main actor
                // (ImageIO downsample inside the processor bounds memory even for
                // huge panoramas) — a 48MP photo would otherwise freeze the UI.
                var result: AvatarProcessResult?
                #if canImport(UIKit)
                if let data {
                    result = await Task.detached(priority: .userInitiated) {
                        AvatarImageProcessor.process(imageData: data)
                    }.value
                }
                #endif
                await MainActor.run {
                    // Drop stale results: only the most recent selection may apply. A late
                    // earlier load must not overwrite the newer pick's preview/result, nor
                    // clear isProcessing while the newer request is still running.
                    guard requestID == photoRequestID else { return }
                    if let result {
                        processResult = result
                    } else {
                        // Load succeeded but the bytes weren't a usable image (unsupported
                        // format, decode failure, or the processor rejected it).
                        saveError = "Couldn't use that photo. Try a different image."
                    }
                    isProcessing = false
                }
            } catch {
                // loadTransferable threw (permission, transfer failure) — previously
                // swallowed by try?, leaving the user with a disabled Next and no reason.
                await MainActor.run {
                    guard requestID == photoRequestID else { return }
                    saveError = "Couldn't load that photo. Please try again."
                    isProcessing = false
                }
            }
        }
    }

    private var customPromptTrimmed: String {
        customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customPromptBinding: Binding<String> {
        Binding(
            get: { customPrompt },
            set: { customPrompt = String($0.prefix(Self.customPromptLimit)) }
        )
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
        case personality = 3
    }
}
