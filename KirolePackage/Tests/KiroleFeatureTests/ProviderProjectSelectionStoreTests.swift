import Foundation
import Testing
@testable import KiroleFeature

@Suite("Provider project selection")
struct ProviderProjectSelectionStoreTests {
    @Test("New providers import no projects until the user chooses")
    func missingSelectionIsEmpty() async {
        let suite = "ProviderProjectSelectionStoreTests-\(UUID().uuidString)"
        let store = ProviderProjectSelectionStore(suiteName: suite)
        #expect(await store.selectedProjectIDs(for: .todoist).isEmpty)
    }

    @Test("International and China selections are isolated")
    func regionIsolation() async {
        let suite = "ProviderProjectSelectionStoreTests-\(UUID().uuidString)"
        let store = ProviderProjectSelectionStore(suiteName: suite)
        await store.save(["international"], for: .tickTickInternational)
        await store.save(["china"], for: .didaChina)

        #expect(await store.selectedProjectIDs(for: .tickTickInternational) == ["international"])
        #expect(await store.selectedProjectIDs(for: .didaChina) == ["china"])
    }
}
