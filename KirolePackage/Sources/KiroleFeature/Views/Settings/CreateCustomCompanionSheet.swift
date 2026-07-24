import SwiftUI
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Create Custom Companion Sheet

/// 4-step flow to create a user-uploaded companion (Kindroid-inspired):
/// Step 1 — pick a photo (processed into the hardware avatar source by AvatarImageProcessor).
/// Step 2 — name + pick relationship.
/// Step 3 — pick persona voice.
/// Step 4 — persona dimensions (sliders + backstory + sensitive boundary).
/// Confirm persists to AppState and switches the active companion.
public struct CreateCustomCompanionSheet: View {
    static let customPromptLimit = 1200
    let editingCompanion: CustomCompanion?

    @Environment(AppState.self) var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) var dismiss

    @State var bleService = BLEService.shared
    @State var step: Step = .upload
    @State var selectedPhoto: PhotosPickerItem?
    @State var isProcessing = false
    @State var photoRequestTracker = LatestPhotoRequestTracker()
    @State var processResult: AvatarProcessResult?
    @State var name: String = ""
    @State var relationship: CompanionRelationship = .pet
    @State var personaVoice: CompanionPersonaVoice = .companion
    @State var customPrompt: String = ""
    @State var curiosityLevel: Double = 0.5
    @State var humorLevel: Double = 0.5
    @State var strictnessLevel: Double = 0.3
    @State var backstory: String = ""
    @State var sensitiveBoundary: String = ""
    @State var isSaving = false
    @State var saveError: String?
    @State var didReplacePhoto = false
    @State var showConnectionRequired = false

    public init(editing companion: CustomCompanion? = nil) {
        editingCompanion = companion
        let draft = CustomCompanionFormDraft(companion: companion)
        _isProcessing = State(initialValue: companion != nil)
        _name = State(initialValue: draft.name)
        _relationship = State(initialValue: draft.relationship)
        _personaVoice = State(initialValue: draft.personaVoice)
        _customPrompt = State(initialValue: draft.customPrompt)
        _curiosityLevel = State(initialValue: draft.curiosityLevel)
        _humorLevel = State(initialValue: draft.humorLevel)
        _strictnessLevel = State(initialValue: draft.strictnessLevel)
        _backstory = State(initialValue: draft.backstory)
        _sensitiveBoundary = State(initialValue: draft.sensitiveBoundary)
    }

    static func shouldDismissEditor(for state: CustomAvatarOperationState) -> Bool {
        state.isInProgress
    }

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
        .onChange(of: appState.customAvatarOperationState) { _, state in
            guard Self.shouldDismissEditor(for: state) else { return }
            dismiss()
        }
        .task(id: editingCompanion?.id) {
            await loadExistingPhotoIfNeeded()
        }
        .alert("Kirole Not Connected", isPresented: $showConnectionRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Reconnect Kirole before sending or replacing a companion photo. Text changes can still be saved offline.")
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.colors.borderStrong)
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
                          : theme.colors.primaryText.opacity(0.15))
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
            Text(uploadDescription)
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    // 墨洗底取代 F3F4F6 死灰（全文件统一）。
                    .fill(theme.colors.primaryText.opacity(0.05))
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
                if canChoosePhoto {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Color.clear
                    }
                    .disabled(isProcessing)
                    .frame(width: 200, height: 200)
                    .accessibilityLabel(processResult == nil ? "Choose companion photo" : "Change companion photo")
                    .accessibilityHint("The photo will be prepared for Kirole's E-ink display")
                    .accessibilityIdentifier("CreateCompanion_PickPhoto")
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 24))

            if processResult != nil {
                Text(photoHelpText)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .accessibilityIdentifier("CreateCompanion_PhotoHelp")
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
                .background(theme.colors.primaryText.opacity(0.05))
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
                                      : theme.colors.primaryText.opacity(0.05))
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
                                .fill(theme.colors.primaryText.opacity(0.05))
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
                .background(theme.colors.primaryText.opacity(0.05))
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
                    .background(theme.colors.primaryText.opacity(0.05))
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
                    .background(theme.colors.primaryText.opacity(0.05))
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
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                backButton
                primaryButton
            }

            if isEditing, step == .personality {
                Button(action: saveAsNewAndDismiss) {
                    Text("Save as New Companion")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(theme.colors.accentLight)
                        .foregroundStyle(canSaveAsNew ? theme.colors.accent : theme.colors.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(!canSaveAsNew || isSaving)
                .accessibilityHint(saveAsNewAccessibilityHint)
                .accessibilityIdentifier("CreateCompanion_SaveAsNew")

                if let limitMessage = appState.customCompanionLimitMessage {
                    Text(limitMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("CreateCompanion_LimitMessage")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .padding(.top, 12)
    }

    private var saveAsNewAccessibilityHint: String {
        if let limitMessage = appState.customCompanionLimitMessage {
            return limitMessage
        }
        return canSaveAsNew
            ? "Creates a separate companion and applies it to Kirole"
            : "Connect Kirole before saving a new companion"
    }

    @ViewBuilder
    private var backButton: some View {
        Button(action: handleBack) {
            Text(step == .upload ? "Cancel" : "Back")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(theme.colors.primaryText.opacity(0.05))
                .foregroundStyle(theme.colors.secondaryText)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityIdentifier("CreateCompanion_Back")
    }

    @ViewBuilder
    private var primaryButton: some View {
        Button(action: handleNext) {
            Group {
                if isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text(primaryButtonTitle)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(canAdvance && !isSaving
                        ? theme.colors.accent
                        : theme.colors.secondaryText.opacity(0.3))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!canAdvance || isSaving)
        .accessibilityHint(primaryAccessibilityHint)
        .accessibilityIdentifier(isEditing && step == .personality
                                 ? "CreateCompanion_SaveChanges"
                                 : "CreateCompanion_Next")
    }

    @ViewBuilder
    private var placeholderArtwork: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(theme.colors.secondaryText)
            Text("Tap to choose photo")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}
