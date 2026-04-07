import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#endif

enum CompanionDialogueDisplayPolicy {
    static let fontSize: CGFloat = 15
    static let maxWidth: CGFloat = 240
    static let maxLines: Int = 3
    static let reservedHeight: CGFloat = 68

    static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"\s*\n+\s*"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s{2,}"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidForDisplay(_ text: String) -> Bool {
        let normalizedText = normalized(text)
        guard !normalizedText.isEmpty else { return false }
        guard !normalizedText.hasPrefix("[Error]") else { return false }
        guard hasTerminalPunctuation(normalizedText) else { return false }
        return renderedLineCount(for: normalizedText) <= maxLines
    }

    static func hasTerminalPunctuation(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.last else { return false }
        return CharacterSet(charactersIn: ".!?…。！？").contains(scalar)
    }

    static func renderedLineCount(for text: String) -> Int {
        #if canImport(UIKit) || canImport(AppKit)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineBreakStrategy = .pushOut

        let attributes: [NSAttributedString.Key: Any] = [
            .font: measurementFont(),
            .paragraphStyle: paragraphStyle
        ]

        let bounds = NSAttributedString(string: text, attributes: attributes).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let lineHeight = measurementLineHeight()
        return max(1, Int(ceil(bounds.height / lineHeight)))
        #else
        return 1
        #endif
    }

    #if canImport(UIKit) || canImport(AppKit)
    private static func measurementFont() -> PlatformFont {
        #if canImport(UIKit)
        let baseDescriptor = UIFont.systemFont(ofSize: fontSize, weight: .regular).fontDescriptor
        let serifDescriptor = baseDescriptor.withDesign(.serif) ?? baseDescriptor
        let italicDescriptor = serifDescriptor.withSymbolicTraits([.traitItalic]) ?? serifDescriptor
        return UIFont(descriptor: italicDescriptor, size: fontSize)
        #else
        return NSFont.systemFont(ofSize: fontSize)
        #endif
    }

    private static func measurementLineHeight() -> CGFloat {
        #if canImport(UIKit)
        measurementFont().lineHeight
        #else
        NSLayoutManager().defaultLineHeight(for: measurementFont())
        #endif
    }
    #endif
}
