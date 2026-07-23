import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension CreateCustomCompanionSheet {
    // MARK: - Flow and persistence

    var stepTitle: String {
        switch step {
        case .upload: return isEditing ? "Companion Photo" : "Pick a Photo"
        case .identity: return "Who Is This?"
        case .voice: return "How Do They Speak?"
        case .personality: return "Shape Their Personality"
        }
    }

    var primaryButtonTitle: String {
        guard step == .personality else { return "Next" }
        return isEditing ? "Save Changes" : "Create"
    }

    var primaryAccessibilityHint: String {
        guard step == .personality else { return "Continues to the next step" }
        if isEditing {
            return didReplacePhoto
                ? "Saves the changes after Kirole confirms the replacement photo"
                : "Saves text changes without sending a photo"
        }
        return "Creates and applies this companion to Kirole"
    }

    var isEditing: Bool { editingCompanion != nil }

    var isEditingActiveCompanion: Bool {
        guard let id = editingCompanion?.id else { return false }
        return appState.userProfile.currentSelection == .custom(id)
    }

    var canChoosePhoto: Bool {
        guard isEditing else { return true }
        return isEditingActiveCompanion && bleService.connectionState.isConnected
    }

    var uploadDescription: String {
        guard isEditing else {
            return "Upload anyone — your pet, your kid, yourself. They become your desk companion."
        }
        if !isEditingActiveCompanion {
            return "Apply this companion first if you want to replace its photo. You can still edit its name and personality now."
        }
        if !bleService.connectionState.isConnected {
            return "Reconnect Kirole to replace this photo. You can still edit the companion's text details offline."
        }
        return "This is the current companion. Choose a new photo only if you want to replace it on Kirole."
    }

    var photoHelpText: String {
        if canChoosePhoto {
            return "Tap photo to change. Kirole's 6-color E-ink screen shows it softer and more muted than your photo — that's expected."
        }
        return isEditingActiveCompanion
            ? "Photo replacement is available after Kirole reconnects."
            : "Select this companion from the companion list before replacing its photo."
    }

    var canSaveAsNew: Bool {
        isEditing
            && !isProcessing
            && processResult != nil
            && bleService.connectionState.isConnected
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (personaVoice != .customPrompt || !customPromptTrimmed.isEmpty)
    }

    var canAdvance: Bool {
        guard !isProcessing else { return false }
        switch step {
        case .upload: return isEditing || processResult != nil
        case .identity:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .voice:
            return personaVoice != .customPrompt || !customPromptTrimmed.isEmpty
        case .personality: return true
        }
    }

    func handleBack() {
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

    func handleNext() {
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
            if isEditing {
                saveChangesAndDismiss()
            } else {
                createAndDismiss()
            }
        }
    }

    func createAndDismiss() {
        guard let result = processResult, !isSaving else { return }
        guard bleService.connectionState.isConnected else {
            showConnectionRequired = true
            return
        }
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
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    func saveChangesAndDismiss() {
        guard let companion = editingCompanion, !isSaving, !isProcessing else { return }
        let updated = formDraft.updating(companion)
        let replacement = didReplacePhoto ? processResult : nil
        isSaving = true
        saveError = nil
        Task {
            do {
                if let replacement {
                    guard bleService.connectionState.isConnected else {
                        showConnectionRequired = true
                        isSaving = false
                        return
                    }
                    // Metadata and the replacement photo form one candidate. Neither is
                    // visible locally until firmware confirms the image commit, so a failed
                    // or cancelled transfer leaves the previous companion wholly unchanged.
                    _ = try await appState.replaceCustomCompanion(
                        updated,
                        previewData: replacement.previewData,
                        imageData: replacement.imageData
                    )
                } else {
                    // Text-only edits are intentionally local and remain available offline.
                    _ = try await appState.updateCustomCompanionMetadata(updated)
                }
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    func saveAsNewAndDismiss() {
        guard let result = processResult, canSaveAsNew, !isSaving, !isProcessing else {
            if !bleService.connectionState.isConnected {
                showConnectionRequired = true
            }
            return
        }
        isSaving = true
        saveError = nil
        guard let companion = editingCompanion else {
            isSaving = false
            return
        }
        let source = formDraft.updating(companion)
        Task {
            do {
                _ = try await appState.saveCustomCompanionAsNew(
                    from: source,
                    previewData: result.previewData,
                    imageData: result.imageData
                )
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }

    var formDraft: CustomCompanionFormDraft {
        var draft = CustomCompanionFormDraft()
        draft.name = name
        draft.relationship = relationship
        draft.personaVoice = personaVoice
        draft.customPrompt = customPrompt
        draft.curiosityLevel = curiosityLevel
        draft.humorLevel = humorLevel
        draft.strictnessLevel = strictnessLevel
        draft.backstory = backstory
        draft.sensitiveBoundary = sensitiveBoundary
        return draft
    }

    func loadExistingPhotoIfNeeded() async {
        guard let companion = editingCompanion else { return }
        async let preview = LocalStorage.shared.loadCustomCompanionPreview(id: companion.id)
        async let image = LocalStorage.shared.loadCustomCompanionImageData(id: companion.id)
        let (previewData, imageData) = await (preview, image)
        guard editingCompanion?.id == companion.id else { return }
        if let previewData, let imageData {
            processResult = AvatarProcessResult(previewData: previewData, imageData: imageData)
        } else {
            saveError = "Couldn't load the saved companion photo."
        }
        isProcessing = false
    }

    func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let requestID = photoRequestTracker.begin()
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
                    guard photoRequestTracker.isCurrent(requestID) else { return }
                    if let result {
                        processResult = result
                        didReplacePhoto = editingCompanion != nil
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
                    guard photoRequestTracker.isCurrent(requestID) else { return }
                    saveError = "Couldn't load that photo. Please try again."
                    isProcessing = false
                }
            }
        }
    }

    var customPromptTrimmed: String {
        customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var customPromptBinding: Binding<String> {
        Binding(
            get: { customPrompt },
            set: { customPrompt = String($0.prefix(Self.customPromptLimit)) }
        )
    }


    enum Step: Int, CaseIterable {
        case upload = 0
        case identity = 1
        case voice = 2
        case personality = 3
    }
}
