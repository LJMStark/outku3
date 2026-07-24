import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Character Switcher Sheet

public struct CharacterSwitcherSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var bleService = BLEService.shared
    @State private var editorTarget: CompanionEditorTarget?
    @State private var companionPendingDeletion: CustomCompanion?
    @State private var showConnectionRequired = false
    @State private var actionError: String?
    @State private var showActionError = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                dragIndicator
                Text("Switch Companion")
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(theme.colors.primaryText)
                    .padding(.bottom, 24)

                builtInSection
                customSection
                createButton
                Spacer(minLength: 24)
            }
        }
        .background(theme.colors.background)
        .sheet(item: $editorTarget) { target in
            CreateCustomCompanionSheet(editing: target.companion)
                .injectAppEnvironment()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
        }
        .alert(item: $companionPendingDeletion) { companion in
            Alert(
                title: Text("Delete \(companion.name)?"),
                message: Text(deleteConfirmationMessage(for: companion)),
                primaryButton: .destructive(Text("Delete")) {
                    Task {
                        do {
                            try await appState.deleteCustomCompanion(id: companion.id)
                        } catch {
                            ErrorReporter.log(error, context: "CharacterSwitcherSheet.deleteCustomCompanion")
                            actionError = error.localizedDescription
                            showActionError = true
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Kirole Not Connected", isPresented: $showConnectionRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Connect your Kirole before creating or applying a custom companion.")
        }
        .alert("Couldn't Update Companion", isPresented: $showActionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Please try again.")
        }
        .onChange(of: appState.customAvatarOperationState) { _, state in
            guard state != .idle else { return }
            dismiss()
        }
    }

    // MARK: - Section: Built-in characters

    @ViewBuilder
    private var builtInSection: some View {
        VStack(spacing: 12) {
            ForEach(CompanionCharacter.allCases, id: \.self) { character in
                CharacterCard(
                    character: character,
                    isSelected: appState.userProfile.currentSelection == .builtIn(character)
                ) {
                    selectBuiltIn(character)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Section: Custom companions

    @ViewBuilder
    private var customSection: some View {
        if !appState.customCompanions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Companions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.secondaryText)
                    .padding(.top, 24)
                    .padding(.bottom, 4)

                ForEach(appState.customCompanions) { companion in
                    CustomCompanionCard(
                        companion: companion,
                        isSelected: appState.userProfile.currentSelection == .custom(companion.id)
                    ) {
                        selectCustom(companion.id)
                    } onEdit: {
                        editorTarget = CompanionEditorTarget(companion: companion)
                    } onDelete: {
                        companionPendingDeletion = companion
                    }
                }

            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Create button

    @ViewBuilder
    private var createButton: some View {
        VStack(spacing: 8) {
            Button {
                guard bleService.connectionState.isConnected else {
                    showConnectionRequired = true
                    return
                }
                editorTarget = CompanionEditorTarget(companion: nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                    Text(appState.canCreateCustomCompanion
                         ? "Create Your Own"
                         : "\(CustomCompanion.maximumCount) Companion Limit Reached")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(appState.canCreateCustomCompanion
                                 ? theme.colors.accent
                                 : theme.colors.secondaryText)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(appState.canCreateCustomCompanion
                                ? theme.colors.accent
                                : theme.colors.borderStrong, lineWidth: 1.5)
                        .background(theme.colors.accentLight.clipShape(RoundedRectangle(cornerRadius: 18)))
                )
            }
            .buttonStyle(.plain)
            .disabled(!appState.canCreateCustomCompanion)
            .accessibilityHint(createButtonAccessibilityHint)
            .accessibilityIdentifier("Settings_CreateCustomCompanion")

            if let limitMessage = appState.customCompanionLimitMessage {
                Text(limitMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("Settings_CustomCompanionLimitMessage")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var createButtonAccessibilityHint: String {
        if let limitMessage = appState.customCompanionLimitMessage {
            return limitMessage
        }
        return bleService.connectionState.isConnected
            ? "Opens the custom companion creator"
            : "Connect Kirole before creating a companion"
    }

    // MARK: - Helpers

    @ViewBuilder
    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(theme.colors.borderStrong)
            .frame(width: 40, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 20)
    }

    private func selectBuiltIn(_ character: CompanionCharacter) {
        guard appState.userProfile.currentSelection != .builtIn(character) else {
            dismiss()
            return
        }
        Task {
            do {
                try await appState.selectBuiltInCompanion(character)
                dismiss()
            } catch {
                ErrorReporter.log(error, context: "CharacterSwitcherSheet.selectBuiltInCompanion")
                actionError = error.localizedDescription
                showActionError = true
            }
        }
    }

    private func selectCustom(_ id: UUID) {
        guard appState.userProfile.currentSelection != .custom(id) else {
            dismiss()
            return
        }
        guard bleService.connectionState.isConnected else {
            showConnectionRequired = true
            return
        }
        Task {
            do {
                try await appState.selectCustomCompanion(id: id)
            } catch {
                ErrorReporter.log(error, context: "CharacterSwitcherSheet.selectCustomCompanion")
                actionError = error.localizedDescription
                showActionError = true
            }
        }
    }

    private func deleteConfirmationMessage(for _: CustomCompanion) -> String {
        return Self.deleteConfirmationMessage(
            isConnected: bleService.connectionState.isConnected,
            hasKnownDevice: bleService.lastKnownDeviceID != nil
        )
    }

    nonisolated static func deleteConfirmationMessage(
        isConnected: Bool,
        hasKnownDevice: Bool
    ) -> String {
        if isConnected {
            return "This removes the companion from the app and erases its saved photo from Kirole."
        }
        if hasKnownDevice {
            return "This removes the companion from the app now. Kirole will erase its saved photo the next time it connects."
        }
        return "This removes the companion from this iPhone. No known Kirole device is scheduled for photo removal."
    }
}

private struct CompanionEditorTarget: Identifiable {
    let id = UUID()
    let companion: CustomCompanion?
}

// MARK: - Character Card (built-in)

private struct CharacterCard: View {
    let character: CompanionCharacter
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(theme.colors.accentLight)
                        .frame(width: 56, height: 56)

                    Text(characterEmoji)
                        .font(.system(size: 28))
                        .grayscale(isSelected ? 0 : 0.8)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(character.displayName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.colors.primaryText)

                        Text(character.resolvedStyle.description)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.colors.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(theme.colors.secondaryText.opacity(0.08))
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }

                    Text(characterTagline)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.colors.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        // 选中勾选跟随主题 accent（原 4A6B53 硬绿）。
                        .foregroundStyle(theme.colors.accent)
                }
            }
            .padding(16)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Current companion: \(character.displayName)" : "Select \(character.displayName) as companion")
        .accessibilityIdentifier("Settings_Character_\(character.displayName)")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? theme.colors.accent : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }

    private var characterEmoji: String {
        switch character {
        case .joy: return "\u{1F33F}"
        case .silas: return "\u{1F319}"
        case .nova: return "\u{26A1}"
        }
    }

    private var characterTagline: String {
        switch character {
        case .joy: return "Helps you notice delight in work and daily life"
        case .silas: return "Helps work feel held with quiet spiritual care"
        case .nova: return "Filters noise and protects time with discipline"
        }
    }
}

// MARK: - Custom Companion Card

private struct CustomCompanionCard: View {
    let companion: CustomCompanion
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(ThemeManager.self) private var theme
    @State private var previewData: Data?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 16) {
                    avatar

                    VStack(alignment: .leading, spacing: 4) {
                        Text(companion.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)

                        Text("\(companion.relationship.displayName) · \(companion.personaVoice.displayName)")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(theme.colors.accent)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Current companion: \(companion.name)" : "Select \(companion.name)")
            .accessibilityHint(isSelected ? "Already selected" : "Applies this companion to the app and Kirole")
            .accessibilityIdentifier("Settings_CustomCompanion_\(companion.id.uuidString)")

            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.colors.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More options for \(companion.name)")
            .accessibilityHint("Edit or delete this companion")
            .accessibilityIdentifier("Settings_CustomCompanionMenu_\(companion.id.uuidString)")
        }
        .padding(16)
        .background(cardBackground)
        .task(id: companion.avatarRevisionKey) {
            previewData = await LocalStorage.shared.loadCustomCompanionPreview(id: companion.id)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Circle()
                .fill(theme.colors.accentLight)
                .frame(width: 56, height: 56)

            #if canImport(UIKit)
            if let previewData, let uiImage = UIImage(data: previewData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.colors.secondaryText)
            }
            #else
            Image(systemName: "person.fill")
                .font(.system(size: 24))
                .foregroundStyle(theme.colors.secondaryText)
            #endif
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(theme.colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? theme.colors.accent : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}
