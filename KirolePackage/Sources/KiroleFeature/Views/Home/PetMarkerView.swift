import SwiftUI

struct PetMarkerView: View {
    let dayOffset: Int

    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var appeared = false

    private static let phrases: [String] = [
        "Keep going, you're doing great!",
        "One step at a time, champion!",
        "Your pet is proud of you!",
        "Consistency is your superpower!",
        "Small wins add up to big victories!",
        "You're building something amazing!",
        "Stay curious, stay awesome!",
    ]

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
                .frame(width: 80)

            VStack(spacing: 16) {
                Image(appState.pet.currentForm.imageName, bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

                Text(Self.phrases[dayOffset % Self.phrases.count])
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.easeOut(duration: 0.6), value: appeared)
        .onAppear { appeared = true }
    }
}
