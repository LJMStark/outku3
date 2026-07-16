import SwiftUI

@MainActor
public struct CharacterView: View {
    let character: CompanionCharacter
    var size: CGFloat = 80

    @State private var trigger = CompanionMotionTrigger(motion: .greet)

    public init(character: CompanionCharacter, size: CGFloat = 80) {
        self.character = character
        self.size = size
    }

    public var body: some View {
        Button {
            trigger = CompanionMotionTrigger(motion: .react)
        } label: {
            CompanionAnimationView(
                selection: .builtIn(character),
                artwork: .main,
                ambientMotion: .idle,
                trigger: trigger,
                size: CGSize(width: size, height: size),
                accessibilityLabel: "Onboarding companion",
                accessibilityIdentifier: "Onboarding_CompanionAnimation"
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Onboarding companion")
        .accessibilityIdentifier("Onboarding_CompanionButton")
        .accessibilityHint("Tap to see a reaction")
    }
}
