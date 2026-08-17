import AudioToolbox
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Sound Types

public enum SoundType: Hashable, Sendable {
    case taskComplete
    case taskUncomplete
    case petEvolution
    case petInteraction
    case sceneMilestone
    case buttonTap
    case notification

    /// iOS 系统提示音 ID。响度跟铃声音量走，静音键关上就不播。
    var systemSoundID: SystemSoundID {
        switch self {
        case .taskComplete: 1057
        case .taskUncomplete: 1104
        case .petEvolution: 1025
        case .petInteraction: 1054
        case .sceneMilestone: 1026
        case .buttonTap: 1104
        case .notification: 1007
        }
    }
}

// MARK: - Haptic Types

public enum HapticType: Sendable {
    case light, medium, heavy
    case success, warning, error
    case selection
}

// MARK: - Sound Service

/// 短提示音 + 触觉反馈。音效走系统提示音，不在 App 内再做开关或音量。
@MainActor
public final class SoundService {
    public static let shared = SoundService()

    private init() {}

    public func play(_ sound: SoundType) {
        AudioServicesPlaySystemSound(sound.systemSoundID)
    }

    public func haptic(_ type: HapticType) {
        #if canImport(UIKit)
        switch type {
        case .light:   UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:   UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:   UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        }
        #endif
    }

    public func playWithHaptic(_ sound: SoundType, haptic: HapticType) {
        play(sound)
        self.haptic(haptic)
    }
}
