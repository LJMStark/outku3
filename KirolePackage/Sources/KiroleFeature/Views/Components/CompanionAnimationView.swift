import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Native SwiftUI player for semantic companion motions.
/// Joy uses generated PNG sequences; other built-ins and custom companions stay static.
@MainActor
public struct CompanionAnimationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let selectionOverride: CompanionSelection?
    private let artwork: CompanionAnimationArtwork
    private let ambientMotion: CompanionMotion
    private let trigger: CompanionMotionTrigger?
    private let size: CGSize
    private let isActive: Bool
    private let accessibilityLabel: String
    private let accessibilityIdentifier: String
    private let onOneShotCompletion: @MainActor () -> Void

    @State private var acceptedTrigger: CompanionMotionTrigger?
    @State private var isVisible = false
    @State private var customPreviewData: Data?
    @State private var displayedFrameName: String?

    public init(
        selection: CompanionSelection? = nil,
        artwork: CompanionAnimationArtwork,
        ambientMotion: CompanionMotion = .idle,
        trigger: CompanionMotionTrigger? = nil,
        size: CGSize,
        isActive: Bool = true,
        accessibilityLabel: String = "Companion",
        accessibilityIdentifier: String = "Companion_Animation",
        onOneShotCompletion: @escaping @MainActor () -> Void = {}
    ) {
        self.selectionOverride = selection
        self.artwork = artwork
        self.ambientMotion = ambientMotion
        self.trigger = trigger
        self.size = size
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onOneShotCompletion = onOneShotCompletion
    }

    public var body: some View {
        animationContent
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier)
            .onAppear {
                isVisible = true
                accept(trigger)
            }
            .onDisappear {
                isVisible = false
                acceptedTrigger = nil
            }
            .onChange(of: trigger?.id) { _, _ in
                accept(trigger)
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase != .active else { return }
                acceptedTrigger = nil
            }
            .onChange(of: isActive) { _, newValue in
                guard !newValue else { return }
                acceptedTrigger = nil
            }
            .task(id: acceptedTrigger?.id) {
                guard let acceptedTrigger else { return }
                guard let definition = CompanionAnimationCatalog.oneShotDefinition(
                    selection: selection,
                    artwork: artwork,
                    motion: acceptedTrigger.motion,
                    reduceMotion: reduceMotion
                ) else {
                    self.acceptedTrigger = nil
                    return
                }
                do {
                    try await Task.sleep(for: .seconds(definition.totalDuration))
                } catch {
                    return
                }
                guard self.acceptedTrigger?.id == acceptedTrigger.id else { return }
                guard isActive, isVisible, scenePhase == .active else { return }
                self.acceptedTrigger = nil
                onOneShotCompletion()
            }
            .task(id: playbackTaskID) {
                await playFrames()
            }
            .task(id: customCompanionID) {
                guard let customCompanionID else {
                    customPreviewData = nil
                    return
                }
                customPreviewData = await LocalStorage.shared.loadCustomCompanionPreview(id: customCompanionID)
            }
    }

    @ViewBuilder
    private var animationContent: some View {
        switch presentation {
        case .animated(let definition):
            companionFrame(
                named: displayedFrameName ?? definition.frames[0].name,
                fallback: definition.staticFallbackAssetName
            )
        case .staticAsset(let assetName):
            Image(assetName, bundle: .module)
                .resizable()
                .aspectRatio(contentMode: imageContentMode)
                .clipped()
                .accessibilityHidden(true)
        case .custom:
            customCompanionImage
        }
    }

    @ViewBuilder
    private func companionFrame(named frameName: String, fallback: String) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(named: frameName, in: .module, compatibleWith: nil) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: imageContentMode)
                .clipped()
                .accessibilityHidden(true)
        } else {
            Image(fallback, bundle: .module)
                .resizable()
                .aspectRatio(contentMode: imageContentMode)
                .clipped()
                .accessibilityHidden(true)
        }
        #else
        Image(frameName, bundle: .module)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: imageContentMode)
            .clipped()
            .accessibilityHidden(true)
        #endif
    }

    @ViewBuilder
    private var customCompanionImage: some View {
        #if canImport(UIKit)
        if let customPreviewData, let image = UIImage(data: customPreviewData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            missingCustomCompanionFallback
        }
        #elseif canImport(AppKit)
        if let customPreviewData, let image = NSImage(data: customPreviewData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            missingCustomCompanionFallback
        }
        #else
        missingCustomCompanionFallback
        #endif
    }

    private var missingCustomCompanionFallback: some View {
        Color.clear
        .accessibilityHidden(true)
    }

    private var selection: CompanionSelection {
        selectionOverride ?? appState.userProfile.currentSelection
    }

    private var customCompanionID: UUID? {
        if case .custom(let id) = selection { return id }
        return nil
    }

    private var activeMotion: CompanionMotion {
        acceptedTrigger?.motion ?? ambientMotion
    }

    private var presentation: CompanionMotionPresentation {
        CompanionAnimationCatalog.resolve(
            selection: selection,
            artwork: artwork,
            motion: activeMotion,
            reduceMotion: reduceMotion
        )
    }

    private var shouldPlay: Bool {
        isActive && isVisible && scenePhase == .active && !reduceMotion
    }

    private var imageContentMode: ContentMode {
        artwork == .scene ? .fill : .fit
    }

    private var playbackTaskID: String {
        "\(selection)-\(artwork.rawValue)-\(activeMotion.rawValue)-\(acceptedTrigger?.id.uuidString ?? "ambient")-\(shouldPlay)"
    }

    private func playFrames() async {
        guard case .animated(let definition) = presentation else {
            displayedFrameName = nil
            return
        }

        displayedFrameName = definition.frames[0].name
        guard shouldPlay else { return }

        var index = 0
        while !Task.isCancelled {
            let frame = definition.frames[index]
            displayedFrameName = frame.name
            do {
                try await Task.sleep(for: .seconds(frame.duration))
            } catch {
                return
            }

            if definition.loopMode == .oneShot, index == definition.frames.count - 1 {
                return
            }
            index = (index + 1) % definition.frames.count
        }
    }

    private func accept(_ candidate: CompanionMotionTrigger?) {
        guard acceptedTrigger == nil,
              let candidate,
              candidate.motion != ambientMotion,
              CompanionAnimationCatalog.oneShotDefinition(
                selection: selection,
                artwork: artwork,
                motion: candidate.motion,
                reduceMotion: reduceMotion
              ) != nil else { return }
        acceptedTrigger = candidate
    }
}
