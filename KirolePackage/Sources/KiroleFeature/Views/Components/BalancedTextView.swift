import SwiftUI

#if canImport(UIKit)
import UIKit

/// A text view that uses Apple's `.pushOut` line break strategy
/// to prevent widow/orphan words and produce visually balanced line lengths.
public struct BalancedTextView: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let isItalic: Bool
    let color: Color
    let textAlignment: NSTextAlignment

    public init(
        _ text: String,
        fontSize: CGFloat = 15,
        italic: Bool = false,
        color: Color = .primary,
        alignment: NSTextAlignment = .center
    ) {
        self.text = text
        self.fontSize = fontSize
        self.isItalic = italic
        self.color = color
        self.textAlignment = alignment
    }

    public func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        configureLabel(label)
        return label
    }

    public func updateUIView(_ label: UILabel, context: Context) {
        configureLabel(label)
    }

    private func configureLabel(_ label: UILabel) {
        let font: UIFont = isItalic
            ? UIFont.italicSystemFont(ofSize: fontSize)
            : UIFont.systemFont(ofSize: fontSize)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineBreakStrategy = .pushOut

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(color),
            .paragraphStyle: paragraphStyle
        ]

        label.attributedText = NSAttributedString(
            string: text,
            attributes: attributes
        )
    }
}

#endif
