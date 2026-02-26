import Foundation

#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif

#if os(iOS) && canImport(ManagedSettings)
import ManagedSettings
#endif

// MARK: - Focus Guard Models

public struct FocusAppSelection: Codable, Sendable, Equatable {
    public let tokenData: Data
    public let selectedApplicationCount: Int

    public init(tokenData: Data, selectedApplicationCount: Int) {
        self.tokenData = tokenData
        self.selectedApplicationCount = selectedApplicationCount
    }

    public var isEmpty: Bool {
        selectedApplicationCount == 0 || tokenData.isEmpty
    }
}

public enum FocusAuthorizationStatus: String, Codable, Sendable {
    case notDetermined
    case approved
    case denied
    case unavailable
    case unsupported
}

public enum FocusGuardError: Error, Sendable {
    case capabilityUnavailable
    case notAuthorized
    case selectionMissing
    case selectionDecodeFailed
}

// MARK: - Focus Guard Protocol

@MainActor
public protocol FocusGuardService: AnyObject {
    var authorizationStatus: FocusAuthorizationStatus { get }
    var isDeepFocusFeatureEnabled: Bool { get }
    var isDeepFocusCapable: Bool { get }
    var canShowDeepFocusEntry: Bool { get }
    var selectedApplicationCount: Int { get }
    var isPickerPresented: Bool { get set }

    func refreshAuthorizationStatus() async
    func requestAuthorization() async -> FocusAuthorizationStatus
    func presentAppPicker()
    func applyShield(selection: FocusAppSelection) throws
    func clearShield()
    func currentSelection() -> FocusAppSelection?
}

// MARK: - Screen Time Focus Guard Service

@Observable
@MainActor
public final class ScreenTimeFocusGuardService: FocusGuardService {
    public static let shared = ScreenTimeFocusGuardService()

    public private(set) var authorizationStatus: FocusAuthorizationStatus = .unsupported
    public private(set) var selectedApplicationCount: Int = 0
    public var isPickerPresented: Bool = false

    #if os(iOS) && canImport(FamilyControls)
    public private(set) var familyActivitySelection = FamilyActivitySelection()
    #endif

    private var cachedSelection: FocusAppSelection?
    private let localStorage: LocalStorage

    #if os(iOS) && canImport(ManagedSettings)
    private let managedSettingsStore = ManagedSettingsStore()
    #endif

    public var isDeepFocusFeatureEnabled: Bool {
        AppSecrets.deepFocusFeatureEnabled
    }

    public var isDeepFocusCapable: Bool {
        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        true
        #else
        false
        #endif
    }

    public var canShowDeepFocusEntry: Bool {
        isDeepFocusFeatureEnabled && isDeepFocusCapable && authorizationStatus != .unavailable
    }

    private init(localStorage: LocalStorage = .shared) {
        self.localStorage = localStorage
        Task { @MainActor in
            await refreshAuthorizationStatus()
            await loadPersistedSelection()
        }
    }

    public func refreshAuthorizationStatus() async {
        guard isDeepFocusFeatureEnabled else {
            authorizationStatus = .unsupported
            return
        }
        guard isDeepFocusCapable else {
            authorizationStatus = .unsupported
            return
        }

        #if os(iOS) && canImport(FamilyControls)
        authorizationStatus = mapAuthorizationStatus(AuthorizationCenter.shared.authorizationStatus)
        #else
        authorizationStatus = .unsupported
        #endif
    }

    public func requestAuthorization() async -> FocusAuthorizationStatus {
        guard isDeepFocusFeatureEnabled else {
            authorizationStatus = .unsupported
            return authorizationStatus
        }
        guard isDeepFocusCapable else {
            authorizationStatus = .unsupported
            return authorizationStatus
        }

        #if os(iOS) && canImport(FamilyControls)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            await refreshAuthorizationStatus()
        } catch {
            authorizationStatus = isCapabilityError(error) ? .unavailable : .denied
        }
        #else
        authorizationStatus = .unsupported
        #endif

        return authorizationStatus
    }

    public func presentAppPicker() {
        guard canShowDeepFocusEntry, authorizationStatus == .approved else { return }
        isPickerPresented = true
    }

    public func applyShield(selection: FocusAppSelection) throws {
        guard isDeepFocusCapable else {
            throw FocusGuardError.capabilityUnavailable
        }
        guard authorizationStatus == .approved else {
            throw FocusGuardError.notAuthorized
        }
        guard !selection.isEmpty else {
            throw FocusGuardError.selectionMissing
        }

        #if os(iOS) && canImport(FamilyControls) && canImport(ManagedSettings)
        let decodedSelection: FamilyActivitySelection
        do {
            decodedSelection = try PropertyListDecoder().decode(FamilyActivitySelection.self, from: selection.tokenData)
        } catch {
            throw FocusGuardError.selectionDecodeFailed
        }
        guard !decodedSelection.applicationTokens.isEmpty else {
            throw FocusGuardError.selectionMissing
        }
        managedSettingsStore.shield.applications = decodedSelection.applicationTokens
        #else
        throw FocusGuardError.capabilityUnavailable
        #endif
    }

    public func clearShield() {
        #if os(iOS) && canImport(ManagedSettings)
        managedSettingsStore.shield.applications = nil
        #endif
    }

    public func currentSelection() -> FocusAppSelection? {
        cachedSelection
    }

    public func saveSelection(_ selection: FocusAppSelection) {
        cachedSelection = selection
        selectedApplicationCount = selection.selectedApplicationCount
        Task {
            do {
                try await localStorage.saveDeepFocusSelection(selection)
            } catch {
                ErrorReporter.log(
                    .persistence(
                        operation: "save",
                        target: "deep_focus_selection.json",
                        underlying: error.localizedDescription
                    ),
                    context: "ScreenTimeFocusGuardService.saveSelection"
                )
            }
        }
    }

    #if os(iOS) && canImport(FamilyControls)
    public func updateFamilyActivitySelection(_ selection: FamilyActivitySelection) {
        familyActivitySelection = selection
        do {
            let encoded = try PropertyListEncoder().encode(selection)
            let appSelection = FocusAppSelection(
                tokenData: encoded,
                selectedApplicationCount: selection.applicationTokens.count
            )
            saveSelection(appSelection)
        } catch {
            ErrorReporter.log(
                .configuration("Failed to encode FamilyActivitySelection"),
                context: "ScreenTimeFocusGuardService.updateFamilyActivitySelection"
            )
        }
    }
    #endif

    private func loadPersistedSelection() async {
        do {
            guard let selection = try await localStorage.loadDeepFocusSelection() else { return }
            cachedSelection = selection
            selectedApplicationCount = selection.selectedApplicationCount

            #if os(iOS) && canImport(FamilyControls)
            if let decoded = try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: selection.tokenData) {
                familyActivitySelection = decoded
            }
            #endif
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "load",
                    target: "deep_focus_selection.json",
                    underlying: error.localizedDescription
                ),
                context: "ScreenTimeFocusGuardService.loadPersistedSelection"
            )
        }
    }

    #if os(iOS) && canImport(FamilyControls)
    private func mapAuthorizationStatus(_ status: AuthorizationStatus) -> FocusAuthorizationStatus {
        switch status {
        case .approved:
            return .approved
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .unavailable
        }
    }
    #endif

    private func isCapabilityError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain.contains("FamilyControls"), nsError.code == 5 {
            return true
        }
        return false
    }
}
