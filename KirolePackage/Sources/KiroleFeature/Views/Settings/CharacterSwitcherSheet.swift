import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Character Switcher Sheet

public struct CharacterSwitcherSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var showCreateCustom = false

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
        .sheet(isPresented: $showCreateCustom) {
            CreateCustomCompanionSheet()
                .injectAppEnvironment()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
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
                    } onDelete: {
                        appState.deleteCustomCompanion(id: companion.id)
                    }
                }

                if appState.isCustomAvatarPendingBLEPush {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.secondaryText)
                        Text("Hardware will show default companion until next sync")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                    .padding(.top, 4)
                    .accessibilityLabel("Custom avatar pending hardware sync")
                    .accessibilityIdentifier("companion.pendingHardwareSync")
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Create button

    @ViewBuilder
    private var createButton: some View {
        Button {
            showCreateCustom = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("Create Your Own")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(theme.colors.accent)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(theme.colors.accent, lineWidth: 1.5)
                    .background(theme.colors.accentLight.clipShape(RoundedRectangle(cornerRadius: 18)))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .accessibilityIdentifier("Settings_CreateCustomCompanion")
    }

    // MARK: - Helpers

    @ViewBuilder
    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.gray.opacity(0.4))
            .frame(width: 40, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 20)
    }

    private func selectBuiltIn(_ character: CompanionCharacter) {
        guard appState.userProfile.currentSelection != .builtIn(character) else {
            dismiss()
            return
        }
        appState.selectBuiltInCompanion(character)
        dismiss()
    }

    private func selectCustom(_ id: UUID) {
        guard appState.userProfile.currentSelection != .custom(id) else {
            dismiss()
            return
        }
        appState.selectCustomCompanion(id: id)
        dismiss()
    }
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
                        .foregroundStyle(Color(hex: "4A6B53"))
                }
            }
            .padding(16)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "当前伴侣：\(character.displayName)" : "选择 \(character.displayName) 作为伴侣")
        .accessibilityIdentifier("Settings_Character_\(character.displayName)")
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color(hex: "4A6B53") : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
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

// MARK: - Custom Companion Card

private struct CustomCompanionCard: View {
    let companion: CustomCompanion
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @Environment(ThemeManager.self) private var theme
    @State private var previewData: Data?

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                avatar

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(companion.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.colors.primaryText)
                            .lineLimit(1)

                        if companion.roastModeEnabled {
                            Text("Roast")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.orange)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    Text("\(companion.relationship.displayName) · \(companion.personaVoice.displayName)")
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
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityLabel(isSelected ? "当前伴侣：\(companion.name)" : "选择 \(companion.name)")
        .accessibilityIdentifier("Settings_CustomCompanion_\(companion.id.uuidString)")
        .task(id: companion.id) {
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
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color(hex: "4A6B53") : Color.clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
}
