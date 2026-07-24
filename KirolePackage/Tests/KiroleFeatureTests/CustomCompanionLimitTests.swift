import Foundation
import Testing
@testable import KiroleFeature

@Suite("Custom companion limit")
@MainActor
struct CustomCompanionLimitTests {
    @Test("creation availability explains the three companion limit")
    func creationAvailabilityExplainsLimit() {
        let state = AppState.makeForTesting()
        state.customCompanions = (1...2).map { index in
            makeCompanion(name: "Companion \(index)")
        }

        #expect(state.customCompanionLimitMessage == nil)

        state.customCompanions.append(makeCompanion(name: "Companion 3"))

        #expect(
            state.customCompanionLimitMessage
                == "You can keep up to 3 custom companions. Delete until fewer than 3 remain before creating another."
        )
    }

    @Test("a fourth custom companion is rejected")
    func fourthCompanionIsRejected() async {
        let state = AppState.makeForTesting()
        state.customCompanions = (1...3).map { index in
            makeCompanion(name: "Companion \(index)")
        }

        await #expect(throws: CustomAvatarOperationError.companionLimitReached) {
            _ = try await state.addCustomCompanion(
                name: "Companion 4",
                relationship: .friend,
                personaVoice: .companion,
                previewData: Data(),
                imageData: Data()
            )
        }

        #expect(state.customCompanions.count == 3)
        #expect(state.pendingCustomAvatarOperation == nil)
    }

    @Test("save as new shares the three companion limit")
    func saveAsNewIsRejectedAtLimit() async {
        let state = AppState.makeForTesting()
        state.customCompanions = (1...3).map { index in
            makeCompanion(name: "Companion \(index)")
        }

        await #expect(throws: CustomAvatarOperationError.companionLimitReached) {
            _ = try await state.saveCustomCompanionAsNew(
                from: state.customCompanions[0],
                previewData: Data(),
                imageData: Data()
            )
        }

        #expect(state.customCompanions.count == 3)
        #expect(state.pendingCustomAvatarOperation == nil)
    }

    @Test("legacy companions over the limit are preserved but cannot grow")
    func legacyCompanionsArePreserved() async {
        let state = AppState.makeForTesting()
        state.customCompanions = (1...4).map { index in
            makeCompanion(name: "Companion \(index)")
        }

        await #expect(throws: CustomAvatarOperationError.companionLimitReached) {
            _ = try await state.addCustomCompanion(
                name: "Companion 5",
                relationship: .friend,
                personaVoice: .companion,
                previewData: Data(),
                imageData: Data()
            )
        }

        #expect(state.customCompanions.count == 4)
        #expect(!state.canCreateCustomCompanion)
    }

    private func makeCompanion(name: String) -> CustomCompanion {
        let id = UUID()
        return CustomCompanion(
            id: id,
            name: name,
            relationship: .pet,
            personaVoice: .companion,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id)
        )
    }
}
