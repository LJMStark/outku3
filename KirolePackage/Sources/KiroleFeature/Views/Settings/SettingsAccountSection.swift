import SwiftUI
import PhotosUI

// MARK: - Account Section (Avatar + AI Settings)

public struct SettingsAccountSection: View {
    @Environment(ThemeManager.self) private var theme
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarImage: Image?
    @State private var showPreview = false
    @State private var processResult: AvatarProcessResult?
    @State private var isProcessing = false

    public init() {}

    @MainActor
    public var body: some View {
        VStack(spacing: 24) {
            avatarSection
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            isProcessing = true
            Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self) else {
                    await MainActor.run { isProcessing = false }
                    return
                }
                await MainActor.run {
                    #if canImport(UIKit)
                    if let uiImage = UIImage(data: data),
                       let result = AvatarImageProcessor.process(image: uiImage) {
                        processResult = result
                        showPreview = true
                    }
                    #endif
                    isProcessing = false
                }
            }
        }
        .sheet(isPresented: $showPreview) {
            if let result = processResult {
                AvatarPreviewSheet(
                    originalImageData: result.originalData,
                    previewImageData: result.previewData,
                    onConfirm: {
                        confirmAvatar(result)
                        showPreview = false
                    },
                    onCancel: {
                        processResult = nil
                        showPreview = false
                    }
                )
                .environment(theme)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
            }
        }
        .task {
            loadSavedAvatar()
        }
    }

    // MARK: - Avatar

    @MainActor
    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsSectionHeader(title: "Avatar")

            HStack(spacing: 16) {
                VStack(spacing: 8) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 24)
                            .fill(theme.currentTheme.cardGradient)
                            .frame(width: 96, height: 96)

                        if let avatarImage {
                            avatarImage
                                .resizable()
                                .interpolation(.none)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                        } else {
                            Image("tiko_avatar", bundle: .module)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 76, height: 95)
                        }
                    }

                    Text("Avatar")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.colors.secondaryText)
                }
                .frame(maxWidth: .infinity)

                ZStack {
                    UploadButtonView(isProcessing: isProcessing, theme: theme)
                        .frame(maxWidth: .infinity)

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Color.clear
                    }
                    .disabled(isProcessing)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        }
    }



    // MARK: - Private Helpers

    private func confirmAvatar(_ result: AvatarProcessResult) {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: result.previewData) {
            avatarImage = Image(uiImage: uiImage)
        }
        #endif

        // Persist
        Task {
            let pixelData = BLEDataEncoder.encodePixelData(result.pixels, width: AvatarProcessResult.dimension)
            try? await LocalStorage.shared.saveAvatarData(result.previewData)
            try? await LocalStorage.shared.saveAvatarPixels(pixelData)
        }

        processResult = nil
    }

    private func loadSavedAvatar() {
        Task {
            guard let data = await LocalStorage.shared.loadAvatarData() else { return }
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

// MARK: - Upload Button View

private struct UploadButtonView: View {
    let isProcessing: Bool
    let theme: ThemeManager

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(hex: "F3F4F6"))
                    .frame(width: 96, height: 96)

                if isProcessing {
                    ProgressView()
                        .scaleEffect(1.2)
                } else {
                    Image(systemName: "arrow.up.doc")
                        .font(.system(size: 40))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                }
            }

            Text("Upload")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}
