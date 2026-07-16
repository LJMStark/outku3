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

public struct CompanionAnimationDefinition: Sendable, Equatable {
    public let frameNames: [String]
    public let frameDuration: TimeInterval
    public let loopMode: CompanionAnimationLoopMode
    public let staticFallbackAssetName: String

    public init(
        frameNames: [String],
        frameDuration: TimeInterval,
        loopMode: CompanionAnimationLoopMode,
        staticFallbackAssetName: String
    ) {
        precondition(!frameNames.isEmpty, "Companion animation requires at least one frame")
        precondition(frameDuration > 0, "Companion animation frame duration must be positive")
        self.frameNames = frameNames
        self.frameDuration = frameDuration
        self.loopMode = loopMode
        self.staticFallbackAssetName = staticFallbackAssetName
    }

    public var totalDuration: TimeInterval {
        frameDuration * Double(frameNames.count)
    }

    public func frameName(at elapsed: TimeInterval) -> String {
        let safeElapsed = max(0, elapsed)
        let rawIndex = Int(safeElapsed / frameDuration)
        let index: Int

        switch loopMode {
        case .ambient:
            index = rawIndex % frameNames.count
        case .oneShot:
            index = min(rawIndex, frameNames.count - 1)
        }

        return frameNames[index]
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

        let sourceFrameNames = (1...4).map {
            "\(character.rawValue)-\(artwork.rawValue)-\(motion.rawValue)-\(String(format: "%02d", $0))"
        }
        let loopMode: CompanionAnimationLoopMode =
            motion == .idle || motion == .focus ? .ambient : .oneShot
        let playbackFrameNames = loopMode == .ambient
            ? sourceFrameNames + Array(repeating: sourceFrameNames[0], count: 8)
            : sourceFrameNames

        return CompanionAnimationDefinition(
            frameNames: playbackFrameNames,
            frameDuration: 0.15,
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
}
