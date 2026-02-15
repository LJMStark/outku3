import SwiftUI

public enum DialogBubbleStyle {
    case light
    case dark
    case accent
}

public struct OnboardingDialogBubble: View {
    let text: String
    let style: DialogBubbleStyle
    var showPointer: Bool = true

    public init(text: String, style: DialogBubbleStyle = .light, showPointer: Bool = true) {
        self.text = text
        self.style = style
        self.showPointer = showPointer
    }

    private var backgroundColor: Color {
        switch style {
        case .light: return Color(hex: "F5F5F0")
        case .dark: return Color(hex: "2D2D3A")
        case .accent: return Color(hex: "E8D5C4")
        }
    }

    private var textColor: Color {
        switch style {
        case .light: return Color(hex: "1A1A2E")
        case .dark: return .white
        case .accent: return Color(hex: "1A1A2E")
        }
    }

    private var borderColor: Color? {
        switch style {
        case .accent: return Color(hex: "D4A574")
        default: return nil
        }
    }

    public var body: some View {
        HStack {
            if showPointer {
                Triangle()
                    .fill(backgroundColor)
                    .frame(width: 10, height: 16)
                    .rotationEffect(.degrees(-90))
                    .offset(x: 5)
            }

            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(textColor)
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(backgroundColor)
                        .overlay {
                            if let border = borderColor {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(border, lineWidth: 2)
                            }
                        }
                }
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
