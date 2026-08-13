import Foundation

extension MicrosoftSyncEngine {
    nonisolated static func applyOutlookDelta(
        _ changes: [MicrosoftOutlookEvent],
        to current: [CalendarEvent],
        accountID: String
    ) -> [CalendarEvent] {
        var byID: [String: CalendarEvent] = [:]
        for event in current where event.externalReference?.provider == .outlook {
            byID[event.id] = event
        }

        for change in changes {
            let reference = ProviderItemReference(
                provider: .outlook,
                accountID: accountID,
                containerID: "default",
                itemID: change.id,
                region: .global,
                etag: change.etag,
                allowsContentModifications: false
            )
            if change.isDeleted {
                byID.removeValue(forKey: reference.stableLocalID)
                continue
            }
            guard let start = change.start?.date,
                  let end = change.end?.date else {
                continue
            }
            let existing = byID[reference.stableLocalID]
            byID[reference.stableLocalID] = CalendarEvent(
                id: reference.stableLocalID,
                localId: existing?.localId ?? UUID(),
                externalReference: reference,
                title: change.subject ?? "Untitled Event",
                startTime: start,
                endTime: end,
                source: .outlook,
                participants: (change.attendees ?? []).compactMap { attendee in
                    guard let name = attendee.emailAddress.name
                        ?? attendee.emailAddress.address else { return nil }
                    return Participant(name: name)
                },
                description: change.bodyPreview,
                location: change.location?.displayName,
                isAllDay: change.isAllDay ?? false,
                syncStatus: .synced,
                lastModified: change.lastModified ?? existing?.lastModified ?? Date(),
                videoMeetingURL: VideoMeetingURLDetector.detect(
                    description: change.bodyPreview,
                    location: change.location?.displayName
                )
            )
        }

        return byID.values.sorted { $0.startTime < $1.startTime }
    }

    nonisolated static func applyTodoDelta(
        _ changes: [MicrosoftTodoTask],
        listID: String,
        to current: [TaskItem],
        accountID: String
    ) -> [TaskItem] {
        var passthrough: [TaskItem] = []
        var byID: [String: TaskItem] = [:]
        for task in current {
            guard task.externalReference?.provider == .microsoftToDo,
                  task.externalReference?.accountID == accountID,
                  task.externalReference?.containerID == listID else {
                passthrough.append(task)
                continue
            }
            byID[task.id] = task
        }

        for change in changes {
            let temporaryReference = ProviderItemReference(
                provider: .microsoftToDo,
                accountID: accountID,
                containerID: listID,
                itemID: change.id,
                region: .global,
                etag: change.etag,
                remoteStatus: change.status?.rawValue,
                allowsContentModifications: true
            )
            let stableID = temporaryReference.stableLocalID
            if change.removed != nil {
                byID.removeValue(forKey: stableID)
                continue
            }

            let existing = byID[stableID]
            let status = change.status ?? .notStarted
            let previousStatus: String?
            if status == .completed {
                previousStatus = existing?.externalReference?.previousRemoteStatus
                    ?? existing?.externalReference?.remoteStatus.flatMap {
                        $0 == MicrosoftTodoStatus.completed.rawValue ? nil : $0
                    }
            } else {
                previousStatus = status.rawValue
            }
            var reference = temporaryReference
            reference.remoteStatus = status.rawValue
            reference.previousRemoteStatus = previousStatus

            let remoteModified = change.lastModified ?? Date()
            var mapped = TaskItem(
                id: stableID,
                localId: existing?.localId ?? UUID(),
                externalReference: reference,
                title: change.title ?? "Untitled Task",
                isCompleted: status == .completed,
                dueDate: change.dueDateTime?.date,
                source: .microsoftToDo,
                priority: Self.mapImportance(change.importance),
                syncStatus: .synced,
                lastModified: remoteModified,
                remoteUpdatedAt: remoteModified,
                remoteEtag: change.etag,
                notes: change.body?.content,
                todayDisplayDate: existing?.todayDisplayDate
            )

            // A local dirty write newer than this delta page must survive until its outbox drains.
            if let existing,
               existing.syncStatus != .synced,
               existing.lastModified > remoteModified {
                mapped = existing
            }
            byID[stableID] = mapped
        }

        return passthrough + byID.values
    }

    private nonisolated static func mapImportance(
        _ importance: MicrosoftTodoImportance?
    ) -> TaskPriority {
        switch importance {
        case .high: return .high
        case .low: return .low
        default: return .medium
        }
    }
}
