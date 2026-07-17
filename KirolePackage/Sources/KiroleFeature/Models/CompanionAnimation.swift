import Foundation

public enum CompanionMotion: String, CaseIterable, Sendable {
    case idle
    case greet
    case focus
    case celebrate
    case react
}

/// Which existing static illustration a motion grows from.
/// Keeping this separate from motion prevents one generic frame set from replacing
/// page-specific compositions such as the reading vignette or full Pet scene.
public enum CompanionAnimationArtwork: String, CaseIterable, Sendable {
    case main
    case reading
    case scene

    var heroVariant: CompanionCharacter.HeroAssetVariant {
        switch self {
        case .main: .main
        case .reading: .reading
        case .scene: .scene
        }
    }
}

public enum CompanionAnimationLoopMode: Sendable, Equatable {
    case ambient
    case oneShot
}

public struct CompanionAnimationFrame: Sendable, Equatable {
    public let name: String
    public let duration: TimeInterval

    public init(name: String, duration: TimeInterval) {
        precondition(duration > 0, "Companion animation frame duration must be positive")
        self.name = name
        self.duration = duration
    }
}

public struct CompanionAnimationDefinition: Sendable, Equatable {
    public let frames: [CompanionAnimationFrame]
    public let loopMode: CompanionAnimationLoopMode
    public let staticFallbackAssetName: String

    public init(
        frames: [CompanionAnimationFrame],
        loopMode: CompanionAnimationLoopMode,
        staticFallbackAssetName: String
    ) {
        precondition(!frames.isEmpty, "Companion animation requires at least one frame")
        self.frames = frames
        self.loopMode = loopMode
        self.staticFallbackAssetName = staticFallbackAssetName
    }

    public var frameNames: [String] {
        frames.map(\.name)
    }

    public var minimumFrameDuration: TimeInterval {
        frames.map(\.duration).min() ?? 0.1
    }

    public var totalDuration: TimeInterval {
        frames.reduce(0) { $0 + $1.duration }
    }

    public func frameName(at elapsed: TimeInterval) -> String {
        let safeElapsed = max(0, elapsed)
        let playbackTime: TimeInterval

        switch loopMode {
        case .ambient:
            playbackTime = safeElapsed.truncatingRemainder(dividingBy: totalDuration)
        case .oneShot:
            guard safeElapsed < totalDuration else { return frames[frames.count - 1].name }
            playbackTime = safeElapsed
        }

        var boundary: TimeInterval = 0
        for frame in frames {
            boundary += frame.duration
            if playbackTime < boundary {
                return frame.name
            }
        }
        return frames[frames.count - 1].name
    }
}

public enum CompanionMotionPresentation: Sendable, Equatable {
    case animated(CompanionAnimationDefinition)
    case staticAsset(String)
    case custom(UUID)
}

public struct CompanionMotionTrigger: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let motion: CompanionMotion

    public init(id: UUID = UUID(), motion: CompanionMotion) {
        self.id = id
        self.motion = motion
    }
}

public enum CompanionAnimationCatalog {
    public static func resolve(
        selection: CompanionSelection,
        artwork: CompanionAnimationArtwork,
        motion: CompanionMotion,
        reduceMotion: Bool
    ) -> CompanionMotionPresentation {
        switch selection {
        case .custom(let id):
            return .custom(id)
        case .builtIn(let character):
            let fallback = staticFallbackAssetName(for: character, artwork: artwork)
            guard character == .joy,
                  !reduceMotion,
                  let definition = animationDefinition(
                    for: character,
                    artwork: artwork,
                    motion: motion
                  ) else {
                return .staticAsset(fallback)
            }
            return .animated(definition)
        }
    }

    public static func animationDefinition(
        for character: CompanionCharacter,
        artwork: CompanionAnimationArtwork,
        motion: CompanionMotion
    ) -> CompanionAnimationDefinition? {
        guard character == .joy else { return nil }

        switch (artwork, motion) {
        case (.main, .idle), (.main, .greet), (.main, .react),
             (.reading, .idle), (.reading, .focus), (.reading, .celebrate),
             (.scene, .idle), (.scene, .react):
            break
        default:
            return nil
        }

        let loopMode: CompanionAnimationLoopMode =
            motion == .idle || motion == .focus ? .ambient : .oneShot

        return CompanionAnimationDefinition(
            frames: timeline(
                character: character,
                artwork: artwork,
                motion: motion
            ),
            loopMode: loopMode,
            staticFallbackAssetName: staticFallbackAssetName(for: character, artwork: artwork)
        )
    }

    static func oneShotDefinition(
        selection: CompanionSelection,
        artwork: CompanionAnimationArtwork,
        motion: CompanionMotion,
        reduceMotion: Bool
    ) -> CompanionAnimationDefinition? {
        guard !reduceMotion,
              case .builtIn(let character) = selection,
              let definition = animationDefinition(
                for: character,
                artwork: artwork,
                motion: motion
              ),
              definition.loopMode == .oneShot else { return nil }
        return definition
    }

    public static func staticFallbackAssetName(
        for character: CompanionCharacter,
        artwork: CompanionAnimationArtwork
    ) -> String {
        character.heroAssetName(variant: artwork.heroVariant)
    }

    private static func timeline(
        character: CompanionCharacter,
        artwork: CompanionAnimationArtwork,
        motion: CompanionMotion
    ) -> [CompanionAnimationFrame] {
        let sourceMotion: CompanionMotion
        switch artwork {
        case .main:
            sourceMotion = motion == .react ? .greet : motion
        case .reading, .scene:
            sourceMotion = .idle
        }
        let prefix = "\(character.rawValue)-\(artwork.rawValue)-\(sourceMotion.rawValue)"
        let cues: [(Int, TimeInterval)]

        switch (artwork, motion) {
        case (.main, .idle):
            cues = [(1, 2.8), (2, 0.10), (3, 0.12), (2, 0.10), (1, 1.8)]
        case (.main, .greet), (.main, .react):
            cues = [(4, 0.12), (3, 0.10), (2, 0.12), (1, 0.32), (2, 0.12), (3, 0.10), (4, 0.20)]
        case (.reading, .idle):
            cues = [(1, 2.8), (2, 0.12), (1, 1.4), (5, 0.12), (1, 1.8)]
        case (.reading, .focus):
            cues = [(1, 2.2), (3, 0.12), (2, 0.16), (4, 0.12), (1, 1.4)]
        case (.reading, .celebrate):
            cues = [(1, 0.12), (3, 0.10), (6, 0.12), (2, 0.36), (6, 0.12), (3, 0.10), (1, 0.20)]
        case (.scene, .idle):
            cues = [(1, 3.4), (2, 0.10), (1, 1.6), (5, 0.14), (1, 2.4)]
        case (.scene, .react):
            cues = [(1, 0.12), (2, 0.12), (5, 0.36), (2, 0.12), (1, 0.20)]
        default:
            preconditionFailure("Unsupported companion animation timeline")
        }

        return cues.map { index, duration in
            CompanionAnimationFrame(
                name: "\(prefix)-\(String(format: "%02d", index))",
                duration: duration
            )
        }
    }
}
