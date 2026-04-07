import SwiftUI

public struct CompanionDialogueView: View {
    let text: String
    let color: Color

    public init(_ text: String, color: Color = .primary) {
        self.text = CompanionDialogueDisplayPolicy.normalized(text)
        self.color = color
    }

    public var body: some View {
        Group {
            #if canImport(UIKit)
            BalancedTextView(
                text,
                fontSize: CompanionDialogueDisplayPolicy.fontSize,
                italic: true,
                color: color,
                alignment: .center,
                maxLines: CompanionDialogueDisplayPolicy.maxLines
            )
            #else
            Text(text)
                .font(.system(size: CompanionDialogueDisplayPolicy.fontSize, weight: .regular, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .lineLimit(CompanionDialogueDisplayPolicy.maxLines)
                .foregroundStyle(color)
            #endif
        }
        .frame(maxWidth: CompanionDialogueDisplayPolicy.maxWidth)
        .frame(minHeight: CompanionDialogueDisplayPolicy.reservedHeight, alignment: .center)
        .frame(maxWidth: .infinity)
    }
}
