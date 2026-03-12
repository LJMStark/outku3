import SwiftUI

// MARK: - Avatar Preview Sheet

/// Shows original vs pixelated preview for user confirmation before saving.
struct AvatarPreviewSheet: View {
    let originalImageData: Data
    let previewImageData: Data
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(spacing: 24) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 12)

            Text("Preview Avatar")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)

            Text("Left: Original  |  Right: E-ink Preview")
                .font(.system(size: 13))
                .foregroundStyle(theme.colors.secondaryText)

            // Comparison
            HStack(spacing: 24) {
                imagePreview(data: originalImageData, label: "Original")
                imagePreview(data: previewImageData, label: "E-ink")
            }
            .padding(.horizontal, 24)

            // Info
            Text("The pixelated version is how it will appear on your E-ink device (Spectra 6 color)")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: "F3F4F6"))
                        .foregroundStyle(theme.colors.secondaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("Confirm")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(theme.colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(theme.colors.background)
    }

    @ViewBuilder
    private func imagePreview(data: Data, label: String) -> some View {
        VStack(spacing: 8) {
            #if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.none) // Keep pixelated look crisp
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(theme.colors.accent.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            #endif

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.colors.secondaryText)
        }
    }
}
