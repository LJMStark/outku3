import Foundation
import Testing
@testable import KiroleFeature

@Suite("Provider Item Reference")
struct ProviderItemReferenceTests {
    @Test("Stable identity includes provider region account container and item")
    func stableIdentityIsFullyNamespaced() {
        let international = ProviderItemReference(
            provider: .tickTick,
            accountID: "account",
            containerID: "project",
            itemID: "task",
            region: .international,
            allowsContentModifications: false
        )
        let china = ProviderItemReference(
            provider: .tickTick,
            accountID: "account",
            containerID: "project",
            itemID: "task",
            region: .china,
            allowsContentModifications: false
        )

        #expect(international.stableLocalID != china.stableLocalID)
        #expect(international.stableLocalID.hasPrefix("tickTick:"))
    }

    @Test("Opaque identifiers cannot collide through separators")
    func opaqueIdentifiersUseLengthPrefixes() {
        let first = ProviderItemReference(
            provider: .todoist,
            accountID: "a:b",
            containerID: "c",
            itemID: "d"
        )
        let second = ProviderItemReference(
            provider: .todoist,
            accountID: "a",
            containerID: "b:c",
            itemID: "d"
        )

        #expect(first.stableLocalID != second.stableLocalID)
    }

    @Test("Reference metadata round trips without losing write-back state")
    func codableRoundTrip() throws {
        let reference = ProviderItemReference(
            provider: .microsoftToDo,
            accountID: "home-account",
            containerID: "list-id",
            itemID: "task-id",
            region: .global,
            etag: "etag",
            remoteStatus: "completed",
            previousRemoteStatus: "inProgress",
            allowsContentModifications: true
        )

        let data = try JSONEncoder().encode(reference)
        let decoded = try JSONDecoder().decode(ProviderItemReference.self, from: data)

        #expect(decoded == reference)
    }

    @Test("Legacy task and event JSON decode without provider metadata")
    func legacyModelsRemainDecodable() throws {
        let task = TaskItem(title: "Legacy")
        let event = CalendarEvent(
            title: "Legacy event",
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200)
        )
        let encoder = JSONEncoder()
        var taskObject = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(task)) as? [String: Any]
        )
        var eventObject = try #require(
            JSONSerialization.jsonObject(with: encoder.encode(event)) as? [String: Any]
        )
        taskObject.removeValue(forKey: "externalReference")
        eventObject.removeValue(forKey: "externalReference")

        let decodedTask = try JSONDecoder().decode(
            TaskItem.self,
            from: JSONSerialization.data(withJSONObject: taskObject)
        )
        let decodedEvent = try JSONDecoder().decode(
            CalendarEvent.self,
            from: JSONSerialization.data(withJSONObject: eventObject)
        )

        #expect(decodedTask.externalReference == nil)
        #expect(decodedEvent.externalReference == nil)
    }
}
