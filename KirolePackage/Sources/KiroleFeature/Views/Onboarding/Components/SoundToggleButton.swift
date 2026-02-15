import SwiftUI

public struct SoundToggleButton: View {
    @Binding var isEnabled: Bool

    public init(isEnabled: Binding<Bool>) {
        self._isEnabled = isEnabled
    }

    public var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
    }
}
