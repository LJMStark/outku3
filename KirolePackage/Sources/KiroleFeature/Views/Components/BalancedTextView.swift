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
    let maxLines: Int

    public init(
        _ text: String,
        fontSize: CGFloat = 15,
        italic: Bool = false,
        color: Color = .primary,
        alignment: NSTextAlignment = .center,
        maxLines: Int = 0
    ) {
        self.text = text
        self.fontSize = fontSize
        self.isItalic = italic
        self.color = color
        self.textAlignment = alignment
        self.maxLines = maxLines
    }

    public func makeUIView(context: Context) -> BalancedLabelContainerView {
        let container = BalancedLabelContainerView()
        configureLabel(container.label)
        return container
    }

    public func updateUIView(_ container: BalancedLabelContainerView, context: Context) {
        configureLabel(container.label)
    }

    private func configureLabel(_ label: UILabel) {
        let font = makeFont()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = textAlignment
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineBreakStrategy = .pushOut

        label.numberOfLines = maxLines

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

    private func makeFont() -> UIFont {
        let baseDescriptor = UIFont.systemFont(ofSize: fontSize, weight: .regular).fontDescriptor
        let serifDescriptor = baseDescriptor.withDesign(.serif) ?? baseDescriptor

        guard isItalic else {
            return UIFont(descriptor: serifDescriptor, size: fontSize)
        }

        let italicDescriptor = serifDescriptor.withSymbolicTraits([.traitItalic]) ?? serifDescriptor
        return UIFont(descriptor: italicDescriptor, size: fontSize)
    }
}

public final class BalancedLabelContainerView: UIView {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLabel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLabel()
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        label.preferredMaxLayoutWidth = bounds.width
    }

    private func setupLabel() {
        backgroundColor = .clear
        label.backgroundColor = .clear
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .vertical)
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
}

#endif
