import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Read-only version information, styled like the other Settings cards.
struct SettingsVersionRow: View {
    let title: String
    let value: String
    let icon: String
    let identifier: String
    var copyValue: String? = nil

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        #if canImport(UIKit)
        if let copyValue {
            row
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = copyValue
                    } label: {
                        Label("Copy Version", systemImage: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy \(title)")
                    .accessibilityIdentifier("\(identifier)_Copy")
                }
                .accessibilityHint("Touch and hold to copy the version.")
                .accessibilityAction(named: Text("Copy Version")) {
                    UIPasteboard.general.string = copyValue
                }
        } else {
            row
        }
        #else
        row
        #endif
    }

    private var row: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(theme.colors.accent)
                .frame(width: 24)
                .accessibilityHidden(true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    titleText.fixedSize()
                    Spacer(minLength: 0)
                    valueText.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    titleText
                    valueText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(theme.colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    private var titleText: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(theme.colors.primaryText)
    }

    private var valueText: some View {
        Text(value)
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(theme.colors.secondaryText)
    }
}
