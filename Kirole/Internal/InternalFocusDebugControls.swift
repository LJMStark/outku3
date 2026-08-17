#if KIROLE_INTERNAL
import SwiftUI
import KiroleFeature

struct InternalFocusDebugControls: View {
    @Environment(\.focusService) private var focusService
    @Environment(\.themeManager) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus Debug")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.primaryText)

            Toggle(
                "1 second = 1 minute",
                isOn: Binding(
                    get: { focusService.isFocusTimeAccelerated },
                    set: { focusService.setFocusTimeAcceleration($0) }
                )
            )
            .font(.system(size: 13, weight: .medium))
            .tint(theme.colors.accent)
            .accessibilityLabel("Accelerate focus time")
            .accessibilityHint("Makes one real second count as one focus minute")
            .accessibilityIdentifier("focus.debug.accelerationToggle")

            Button {
                focusService.advanceFocusTime(by: 30 * 60)
            } label: {
                Label("Add 30 minutes", systemImage: "goforward.30")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(theme.colors.accentLight)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add 30 focus minutes")
            .accessibilityHint("Advances this focus session by 30 virtual minutes")
            .accessibilityIdentifier("focus.debug.addThirtyMinutes")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(theme.colors.border, lineWidth: 1)
        )
    }
}
#endif
