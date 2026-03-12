import SwiftUI
import PhotosUI

// MARK: - Account Section (Avatar)

public struct SettingsAccountSection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: Image?

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            avatarSection
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self) else { return }
                await MainActor.run {
                    #if canImport(UIKit)
                    if let uiImage = UIImage(data: data) {
                        avatarImage = Image(uiImage: uiImage)
                    }
                    #endif
                }
            }
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Avatar")

            HStack(spacing: 16) {
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(theme.currentTheme.cardGradient)
                            .frame(width: 96, height: 96)

                        if let avatarImage {
                            avatarImage
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else {
                            Image("tiko_avatar", bundle: .module)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        }
                    }

                    Text("Avatar")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .frame(maxWidth: .infinity)

                PhotosPicker(
                    selection: $selectedPhoto,
                    matching: .images
                ) {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(Color(hex: "F3F4F6"))
                                .frame(width: 96, height: 96)

                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 40))
                                .foregroundStyle(Color(hex: "9CA3AF"))
                        }

                        Text("Upload")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.colors.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }
}

