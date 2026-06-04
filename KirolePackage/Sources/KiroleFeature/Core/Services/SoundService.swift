import AVFoundation
import SwiftUI

// MARK: - Sound Types

public enum SoundType: Hashable, Sendable {
    case taskComplete
    case taskUncomplete
    case petEvolution
    case petInteraction
    case sceneMilestone
    case buttonTap
    case notification
    case custom(String)

    /// 系统音效 ID 映射
    var systemSoundID: SystemSoundID? {
        switch self {
        case .taskComplete: 1057      // Tink
        case .taskUncomplete: 1104    // Tock
        case .petEvolution: 1025      // Fanfare
        case .petInteraction: 1054    // Pop
        case .sceneMilestone: 1026   // Celebration
        case .buttonTap: 1104         // Tock
        case .notification: 1007      // Notification
        case .custom: nil
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

/// 音效服务，管理应用内的音效播放与触觉反馈
@Observable
@MainActor
public final class SoundService {
    public static let shared = SoundService()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let soundEnabled = "soundEnabled"
        static let soundVolume = "soundVolume"
    }

    // MARK: - Settings

    public var isSoundEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.soundEnabled) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.soundEnabled)
            if !newValue { stopAll() }
        }
    }

    public var volume: Float {
        get {
            let stored = UserDefaults.standard.object(forKey: Keys.soundVolume) as? Float
            return min(max(stored ?? 0.7, 0), 1)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 1), forKey: Keys.soundVolume) }
    }

    // MARK: - Private

    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        registerDefaults()
        setupAudioSession()
    }

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.soundEnabled: true,
            Keys.soundVolume: Float(0.7)
        ])
    }

    private func setupAudioSession() {
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    // MARK: - Play Sounds

    /// 播放指定类型的音效
    public func play(_ sound: SoundType) {
        guard isSoundEnabled else { return }

        if let soundID = sound.systemSoundID {
            AudioServicesPlaySystemSound(soundID)
        } else if case .custom(let name) = sound {
            playCustomSound(named: name)
        }
    }

    /// 播放自定义音效文件
    public func playCustomSound(named name: String, fileExtension: String = "mp3") {
        guard isSoundEnabled,
              let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return }

        // Same-named sounds intentionally do NOT overlap: the newest play replaces the
        // previous one. Stop the old player first — overwriting the dictionary entry drops
        // its only strong reference, so ARC would otherwise deallocate it mid-playback and
        // cut the sound off abruptly instead of stopping it cleanly. (These are short UI
        // cues like task-complete dings; a multi-player pool would be overkill.)
        players[name]?.stop()

        player.volume = volume
        player.prepareToPlay()
        player.play()
        players[name] = player
    }

    /// 停止所有音效
    public func stopAll() {
        players.values.forEach { $0.stop() }
        players.removeAll()
    }

    // MARK: - Haptic Feedback

    /// 触发触觉反馈
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

    /// 播放音效并触发触觉反馈
    public func playWithHaptic(_ sound: SoundType, haptic: HapticType) {
        play(sound)
        self.haptic(haptic)
    }
}
