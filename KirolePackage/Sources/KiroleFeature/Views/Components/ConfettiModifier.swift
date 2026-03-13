import SwiftUI

/// 纸屑粒子模型
struct ConfettiParticle: Identifiable {
    let id = UUID()
    // 采用多个不同的颜色库
    var color: Color
    // 初始和最终的相对位移
    var initialOffset: CGSize = .zero
    var maxOffset: CGSize
    // 随机缩放和旋转
    var scale: CGFloat = 1.0
    var rotation: Double = 0.0
    var delay: Double = 0.0
}

/// 发射烟花/粒子的 ViewModifier
public struct ConfettiModifier: ViewModifier {
    @Binding var trigger: Int
    @State private var particles: [ConfettiParticle] = []
    @State private var fireCount = 0
    
    // 可配置参数
    var colors: [Color]
    var particleCount: Int
    var explosionRadius: CGFloat
    
    public init(
        trigger: Binding<Int>,
        colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .pink],
        particleCount: Int = 20,
        explosionRadius: CGFloat = 200
    ) {
        self._trigger = trigger
        self.colors = colors
        self.particleCount = particleCount
        self.explosionRadius = explosionRadius
    }
    
    public func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    if fireCount > 0 { // 避免初始渲染
                        ForEach(particles) { particle in
                            Circle()
                                .fill(particle.color)
                                .frame(width: 8, height: 8)
                                .scaleEffect(particle.scale)
                                .rotationEffect(.degrees(particle.rotation))
                                .offset(particle.maxOffset)
                                .opacity(particle.scale == 0 ? 0 : 1.0)
                                // 每个粒子有一点延迟和不同的弹簧速度
                                .animation(
                                    .spring(response: 0.8, dampingFraction: 0.6, blendDuration: 0)
                                    .delay(particle.delay),
                                    value: particle.maxOffset
                                )
                                .animation(
                                    .easeOut(duration: 1.2).delay(0.2 + particle.delay),
                                    value: particle.scale
                                )
                        }
                    }
                }
            )
            .onChange(of: trigger) { _, newValue in
                if newValue > 0 {
                    fireConfetti()
                }
            }
    }
    
    private func fireConfetti() {
        // 重置/生成新的粒子
        fireCount += 1
        var newParticles = [ConfettiParticle]()
        
        for _ in 0..<particleCount {
            let particle = ConfettiParticle(
                color: colors.randomElement() ?? .accentColor,
                initialOffset: .zero,
                maxOffset: .zero, // 刚创建时在中心
                scale: 1.0,
                rotation: Double.random(in: 0...360),
                delay: Double.random(in: 0...0.1)
            )
            newParticles.append(particle)
        }
        
        particles = newParticles
        
        // 触发动画，先炸开并缩小到 0 消失
        DispatchQueue.main.async {
            for i in particles.indices {
                particles[i].maxOffset = CGSize(
                    width: cos(Double.random(in: 0...(2 * .pi))) * CGFloat.random(in: (explosionRadius / 2)...explosionRadius),
                    height: sin(Double.random(in: 0...(2 * .pi))) * CGFloat.random(in: (explosionRadius / 2)...explosionRadius)
                )
            }
            
            // 稍后将它们缩小并隐藏（重置态）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                for i in particles.indices {
                    particles[i].scale = 0.0
                }
            }
        }
    }
}

public extension View {
    /// 轻松挂载烟花特效
    func confetti(
        trigger: Binding<Int>,
        particleCount: Int = 30,
        explosionRadius: CGFloat = 200
    ) -> some View {
        self.modifier(ConfettiModifier(trigger: trigger, particleCount: particleCount, explosionRadius: explosionRadius))
    }
}
