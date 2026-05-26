import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Companion Section (Switch + Create entries)

/// Two-card grid that owns the companion identity controls:
/// - Left card: shows the active companion image + name, taps into CharacterSwitcherSheet
///   to switch among built-in IPs or already-created custom companions.
/// - Right card: taps into CreateCustomCompanionSheet to upload + persona-configure a new one.
///
/// Replaces the prior "user avatar" upload that quantized photos to disk but never wired them
/// to the hardware — see git history for the dead path.
public struct SettingsAccountSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme

    @State private var showCharacterSwitcher = false
    @State private var showCreateCustom = false
    @State private var customPreviewData: Data?

    public init() {}

    @MainActor
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Companion")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)

            HStack(spacing: 16) {
                avatarCard
                createCard
            }
        }
        .sheet(isPresented: $showCharacterSwitcher) {
            CharacterSwitcherSheet()
                .injectAppEnvironment()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showCreateCustom) {
            CreateCustomCompanionSheet()
                .injectAppEnvironment()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
        }
        .task(id: appState.userProfile.customCompanionId) {
            await refreshCustomPreview()
        }
    }

    // MARK: - Left: active companion card

    @MainActor
    private var avatarCard: some View {
        Button {
            showCharacterSwitcher = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(hex: "374151"), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(hex: "F3F4F6"))
                    )

                VStack(spacing: 8) {
                    activeAvatarImage

                    Text(activeName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.colors.primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
                .padding(.top, 16)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("切换伴侣，当前是 \(activeName)")
        .accessibilityIdentifier("Settings_SwitchCompanion")
    }

    /// Shows the custom companion preview when one is active; otherwise the built-in hero art.
    /// `customPreviewData` is loaded by `.task(id:)` whenever `customCompanionId` changes,
    /// so switching companions refreshes the image without a manual reload call.
    @ViewBuilder
    @MainActor
    private var activeAvatarImage: some View {
        #if canImport(UIKit)
        if let customPreviewData,
           let uiImage = UIImage(data: customPreviewData) {
            Image(uiImage: uiImage)
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            builtInArtwork
        }
        #else
        builtInArtwork
        #endif
    }

    @ViewBuilder
    @MainActor
    private var builtInArtwork: some View {
        Image(
            appState.userProfile.companionCharacter.heroAssetName(variant: .main),
            bundle: .module
        )
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: 76, height: 95)
        .offset(y: 5)
    }

    // MARK: - Right: create custom card

    @MainActor
    private var createCard: some View {
        Button {
            showCreateCustom = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "F3F4F6"))

                VStack(spacing: 8) {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Color(hex: "6B7280"))
                        .frame(width: 80, height: 80)

                    Text("Create")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.colors.primaryText)
                        .padding(.bottom, 8)
                }
                .padding(.top, 16)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("创建自定义伴侣")
        .accessibilityIdentifier("Settings_CompanionCreateCard")
    }

    // MARK: - Helpers

    private var activeName: String {
        appState.activeCustomCompanion?.name
            ?? appState.userProfile.companionCharacter.displayName
    }

    private func refreshCustomPreview() async {
        guard let id = appState.userProfile.customCompanionId else {
            customPreviewData = nil
            return
        }
        customPreviewData = await LocalStorage.shared.loadCustomCompanionPreview(id: id)
    }
}
