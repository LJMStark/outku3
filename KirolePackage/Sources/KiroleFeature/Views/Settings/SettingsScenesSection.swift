import SwiftUI

// MARK: - Scenes Section

public struct SettingsScenesSection: View {
    @Environment(AppState.self) private var appState
    @Environment(ThemeManager.self) private var theme
    @State private var energyBottles: Int = 0

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scenes")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.colors.primaryText)

            HStack(spacing: 12) {
                ForEach(DisplayScene.allCases, id: \.self) { scene in
                    SceneTile(
                        scene: scene,
                        state: tileState(for: scene),
                        progress: progress(for: scene),
                        onTap: { handleTap(scene) }
                    )
                }
            }

            Text("Tap a scene to display it on your hardware.")
                .font(.system(size: 12))
                .foregroundStyle(theme.colors.secondaryText)
        }
        .task {
            energyBottles = await LocalStorage.shared.loadEnergyBottles()
        }
    }

    private var activeSceneId: String {
        appState.userProfile.selectedSceneId ?? DisplayScene.harbor.rawValue
    }

    private func tileState(for scene: DisplayScene) -> SceneTileState {
        if scene.rawValue == activeSceneId {
            return .active
        }
        if isUnlocked(scene) {
            return .available
        }
        return .locked
    }

    private func isUnlocked(_ scene: DisplayScene) -> Bool {
        SceneUnlockService.shared.fetchAvailableScenes(energyBottles: energyBottles)
            .contains { $0.sceneId == scene.rawValue }
    }

    private func progress(for scene: DisplayScene) -> SceneTileProgress {
        SceneTileProgress(current: energyBottles, threshold: scene.unlockThreshold)
    }

    @MainActor
    private func handleTap(_ scene: DisplayScene) {
        switch tileState(for: scene) {
        case .active:
            return
        case .locked:
            SoundService.shared.haptic(.warning)
        case .available:
            applyScene(scene)
        }
    }

    @MainActor
    private func applyScene(_ scene: DisplayScene) {
        var updated = appState.userProfile
        updated.selectedSceneId = scene.rawValue
        appState.updateUserProfile(updated)

        SoundService.shared.playWithHaptic(.sceneMilestone, haptic: .success)

        Task {
            if BLEService.shared.connectionState.isConnected {
                do {
                    try await BLEService.shared.sendDisplayScene(scene)
                    appState.lastError = nil
                } catch {
                    appState.lastError = "Scene apply failed: \(error.localizedDescription)"
                }
            }

            #if DEBUG
            if !SimulatorBridge.shared.isConnected {
                SimulatorBridge.shared.connect()
            }
            SimulatorBridge.shared.sendPetStatus(
                petName: appState.userProfile.companionCharacter.displayName,
                petMood: appState.pet.mood.rawValue,
                sceneId: scene.rawValue,
                characterId: appState.userProfile.companionCharacter.rawValue
            )
            #endif
        }
    }
}

// MARK: - Tile state types

private enum SceneTileState {
    case active
    case available
    case locked
}

private struct SceneTileProgress {
    let current: Int
    let threshold: Int
}

// MARK: - Scene Tile

private struct SceneTile: View {
    let scene: DisplayScene
    let state: SceneTileState
    let progress: SceneTileProgress
    let onTap: () -> Void

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Image(scene.assetName, bundle: .module)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if state == .locked {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.black.opacity(0.45))
                        VStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                            Text("\(progress.current) / \(progress.threshold)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }

                    if state == .active {
                        VStack {
                            HStack {
                                Spacer()
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 22, height: 22)
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(theme.colors.accent)
                                }
                                .padding(6)
                            }
                            Spacer()
                        }
                    }
                }
                .frame(height: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(state == .active ? theme.colors.accent : Color.clear, lineWidth: 2)
                )

                Text(scene.englishLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(state == .locked ? theme.colors.secondaryText : theme.colors.primaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityIdentifier("Scenes_Tile_\(scene.rawValue)")
    }

    private var accessibilityLabelText: String {
        switch state {
        case .active: return "\(scene.englishLabel) 场景，当前正在硬件上显示"
        case .available: return "\(scene.englishLabel) 场景，已解锁"
        case .locked: return "\(scene.englishLabel) 场景，已锁定，需要 \(progress.threshold) 个能量瓶子"
        }
    }

    private var accessibilityHintText: String {
        switch state {
        case .active: return ""
        case .available: return "点击应用到硬件"
        case .locked: return "继续累积能量瓶子来解锁"
        }
    }
}

// MARK: - DisplayScene UI helpers (file-private)

private extension DisplayScene {
    var englishLabel: String {
        switch self {
        case .harbor: return "Harbor"
        case .forest: return "Forest"
        case .nightCity: return "Night City"
        }
    }

    var assetName: String {
        switch self {
        case .harbor: return "scene-harbor"
        case .forest: return "scene-forest"
        case .nightCity: return "scene-nightcity"
        }
    }
}
