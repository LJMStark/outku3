import Foundation
import Testing
@testable import KiroleFeature

/// Google Tasks PATCH reads an omitted key as "leave unchanged". Swift's synthesized encoder
/// omits every nil, which is why turning off "Has due date" used to round-trip as a no-op and
/// the response restored the date the user had just removed (real-device finding D04, build 663).
@Suite("GoogleTaskUpdateRequest encoding")
struct GoogleTaskUpdateRequestEncodingTests {

    private func encodedObject(_ request: GoogleTaskUpdateRequest) throws -> [String: Any] {
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    // MARK: - Whole-task writes clear fields

    @Test("A whole-task write sends a cleared due date as explicit null")
    func wholeTaskWriteClearsDueDate() throws {
        let request = GoogleTaskUpdateRequest(
            title: "Renew passport",
            notes: "Bring the old one",
            due: nil,
            status: "needsAction",
            writesClearedFields: true
        )

        let json = try encodedObject(request)

        #expect(json.keys.contains("due"))
        #expect(json["due"] is NSNull)
    }

    @Test("A whole-task write sends cleared notes as explicit null")
    func wholeTaskWriteClearsNotes() throws {
        let request = GoogleTaskUpdateRequest(
            title: "Renew passport",
            notes: nil,
            due: "2026-09-08T00:00:00Z",
            status: "needsAction",
            writesClearedFields: true
        )

        let json = try encodedObject(request)

        #expect(json.keys.contains("notes"))
        #expect(json["notes"] is NSNull)
    }

    @Test("A whole-task write still sends present values, not nulls")
    func wholeTaskWritePreservesValues() throws {
        let request = GoogleTaskUpdateRequest(
            title: "Renew passport",
            notes: "Bring the old one",
            due: "2026-09-08T00:00:00Z",
            status: "needsAction",
            writesClearedFields: true
        )

        let json = try encodedObject(request)

        #expect(json["title"] as? String == "Renew passport")
        #expect(json["notes"] as? String == "Bring the old one")
        #expect(json["due"] as? String == "2026-09-08T00:00:00Z")
        #expect(json["status"] as? String == "needsAction")
        // Never sent for an incomplete task; Google clears it from the status change.
        #expect(!json.keys.contains("completed"))
    }

    // MARK: - Partial writes must not wipe untouched fields

    @Test("markCompleted only writes the completion fields")
    func markCompletedIsPartial() throws {
        let json = try encodedObject(.markCompleted())

        #expect(json["status"] as? String == "completed")
        #expect(json["completed"] is String)
        // The critical half: a completion toggle must never blank the task it is toggling.
        #expect(!json.keys.contains("title"))
        #expect(!json.keys.contains("notes"))
        #expect(!json.keys.contains("due"))
    }

    @Test("markIncomplete only writes the status")
    func markIncompleteIsPartial() throws {
        let json = try encodedObject(.markIncomplete())

        #expect(json["status"] as? String == "needsAction")
        #expect(!json.keys.contains("title"))
        #expect(!json.keys.contains("notes"))
        #expect(!json.keys.contains("due"))
        #expect(!json.keys.contains("completed"))
    }

    @Test("A partial write omits nil fields instead of nulling them")
    func partialWriteOmitsNils() throws {
        let request = GoogleTaskUpdateRequest(title: "Renamed only")

        let json = try encodedObject(request)

        #expect(json["title"] as? String == "Renamed only")
        #expect(!json.keys.contains("notes"))
        #expect(!json.keys.contains("due"))
    }

    @Test("writesClearedFields defaults to the safe partial behaviour")
    func defaultsToPartial() throws {
        let json = try encodedObject(GoogleTaskUpdateRequest(title: "Renamed only", due: nil))

        #expect(!json.keys.contains("due"))
    }
}
