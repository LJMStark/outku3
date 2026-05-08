import SwiftUI

// MARK: - Character Switcher Sheet

public struct CharacterSwitcherSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            Text("Switch Companion")
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(theme.colors.primaryText)
                .padding(.bottom, 24)

            VStack(spacing: 12) {
                ForEach(CompanionCharacter.allCases, id: \.self) { character in
                    CharacterCard(
                        character: character,
                        isSelected: appState.userProfile.companionCharacter == character
                    ) {
                        selectCharacter(character)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .background(theme.colors.background)
    }

    private func selectCharacter(_ character: CompanionCharacter) {
        guard character != appState.userProfile.companionCharacter else {
            dismiss()
            return
        }

        var updatedProfile = appState.userProfile
        updatedProfile.companionCharacter = character
        updatedProfile.intimacyStage = .acquaintance
        appState.updateUserProfile(updatedProfile)

        Task {
            do {
                try await LocalStorage.shared.saveUserProfile(updatedProfile)
            } catch {
                // Persistence failure handled by AppState.lastError
            }
        }

        dismiss()
    }
}

// MARK: - Character Card

private struct CharacterCard: View {
    let character: CompanionCharacter
    let isSelected: Bool
    let onSelect: () -> Void
    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Character icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color(hex: "4A6B53").opacity(0.15) : theme.colors.accentLight)
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
                        .foregroundStyle(Color(hex: "4A6B53"))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(isSelected ? Color(hex: "4A6B53") : Color.clear, lineWidth: 2)
                    )
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "当前伴侣：\(character.displayName)" : "选择 \(character.displayName) 作为伴侣")
        .accessibilityIdentifier("Settings_Character_\(character.displayName)")
    }

    private var characterEmoji: String {
        switch character {
        case .joy: return "🌿"
        case .silas: return "🌙"
        case .nova: return "⚡"
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
