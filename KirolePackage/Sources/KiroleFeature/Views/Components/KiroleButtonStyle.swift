import SwiftUI

/// 统一的 Kirole 按钮缩放及震动动效
public struct KiroleButtonStyle: ButtonStyle {
    public enum StyleType {
        /// 主次大按钮：形变明显，弹簧更强，中等震动
        case cta
        /// 独立图标/小按钮：激进形变，轻微震动
        case icon
        /// 列表项/整行平铺：几乎无形变，靠背景灰度反馈，轻微震动
        case row
    }

    let type: StyleType
    
    // 给 .row 准备的按压背景反馈 (如果不用这套，可以在外面单独套)
    let pressedBackgroundColor: Color

    public init(_ type: StyleType, pressedBackgroundColor: Color = Color.gray.opacity(0.1)) {
        self.type = type
        self.pressedBackgroundColor = pressedBackgroundColor
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed

        // 统一在按下的瞬间触发触觉反馈
        if isPressed {
            switch type {
            case .cta:
                SoundService.shared.haptic(.medium)
            case .icon, .row:
                SoundService.shared.haptic(.light)
            }
        }

        return configuration.label
            // .row 使用按压背景色
            .background(
                Group {
                    if type == .row && isPressed {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(pressedBackgroundColor)
                            // 稍微往外扩充一点点击热区填充
                            .padding(.horizontal, -8)
                            .padding(.vertical, -4)
                    }
                }
            )
            // 按压形变
            .scaleEffect(scale(for: isPressed))
            // 降低透明度 (可选)
            .opacity(opacity(for: isPressed))
            // 动画曲线
            .animation(animation(for: isPressed), value: isPressed)
    }

    private func scale(for isPressed: Bool) -> CGFloat {
        guard isPressed else { return 1.0 }
        switch type {
        case .cta: return 0.95
        case .icon: return 0.90
        case .row: return 0.99  // 极轻微缩放
        }
    }

    private func opacity(for isPressed: Bool) -> Double {
        guard isPressed else { return 1.0 }
        switch type {
        case .cta: return 1.0
        case .icon: return 0.8
        case .row: return 0.95
        }
    }

    private func animation(for isPressed: Bool) -> Animation {
        switch type {
        case .cta:
            return .spring(response: 0.25, dampingFraction: 0.6)
        case .icon:
            return .spring(response: 0.2, dampingFraction: 0.7)
        case .row:
            return .easeOut(duration: 0.1) // row不需要弹簧，干脆点
        }
    }
}

// 供快捷调用的 Extension
public extension ButtonStyle where Self == KiroleButtonStyle {
    static var kiroleCTA: KiroleButtonStyle { KiroleButtonStyle(.cta) }
    static var kiroleIcon: KiroleButtonStyle { KiroleButtonStyle(.icon) }
    static var kiroleRow: KiroleButtonStyle { KiroleButtonStyle(.row) }
}
