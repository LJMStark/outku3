import Foundation
import Testing
@testable import KiroleFeature

@Suite("BLE Task-list Snapshot Firmware Tests")
struct BLETaskListSnapshotFirmwareTests {
    @Test("Malformed or oversized 0x1B cannot partially replace firmware state")
    func taskSnapshotValidationIsAtomic() throws {
        var hardware = SimulatedHardware()
        var firmware = SimulatedTaskListSnapshotFirmware()
        try firmware.beginPending(action: .requestRefresh, operationID: 90)

        let initialPacket = BLESimpleEncoder.encode(
            type: BLEDataType.taskListSnapshotAck.rawValue,
            payload: BLEDataEncoder.encodeTaskListSnapshotAck(
                TaskListSnapshotAck(
                    action: .requestRefresh,
                    operationID: 90,
                    result: .applied,
                    version: TaskListSnapshotVersion(epoch: 3, revision: 1),
                    tasks: [TaskSummary(id: "task-a", title: "A", isCompleted: false, priority: 1)]
                )
            )
        )
        try firmware.apply(
            hardware.receiveSingleAppPacket(initialPacket).parseTaskListSnapshotAck(),
            screenSize: .fourInch
        )

        for payload in [
            malformedSnapshotPayload(operationID: 0, epoch: 3, revision: 2, completed: 0),
            malformedSnapshotPayload(operationID: 91, epoch: 3, revision: 0, completed: 0),
            malformedSnapshotPayload(operationID: 91, epoch: 3, revision: 2, completed: 2),
        ] {
            let packet = BLESimpleEncoder.encode(
                type: BLEDataType.taskListSnapshotAck.rawValue,
                payload: payload
            )
            #expect(throws: SimulationError.self) {
                try hardware.receiveSingleAppPacket(packet).parseTaskListSnapshotAck()
            }
        }

        try firmware.beginPending(action: .requestRefresh, operationID: 91)
        let oversizedPacket = BLESimpleEncoder.encode(
            type: BLEDataType.taskListSnapshotAck.rawValue,
            payload: BLEDataEncoder.encodeTaskListSnapshotAck(
                TaskListSnapshotAck(
                    action: .requestRefresh,
                    operationID: 91,
                    result: .applied,
                    version: TaskListSnapshotVersion(epoch: 3, revision: 2),
                    tasks: (0..<4).map {
                        TaskSummary(id: "task-\($0)", title: "Task \($0)", isCompleted: false)
                    }
                )
            )
        )
        let oversized = try hardware.receiveSingleAppPacket(oversizedPacket).parseTaskListSnapshotAck()
        #expect(throws: SimulationError.snapshotTaskCountExceeded) {
            try firmware.apply(oversized, screenSize: .fourInch)
        }
        #expect(firmware.version == TaskListSnapshotVersion(epoch: 3, revision: 1))
        #expect(firmware.tasks.map(\.id) == ["task-a"])
        #expect(firmware.pendingOperationID == 91)
    }

    @Test("A first snapshot must start at revision 1")
    func firstSnapshotMustStartAtRevisionOne() throws {
        var firmware = SimulatedTaskListSnapshotFirmware()
        try firmware.beginPending(action: .completeTask, operationID: 77)

        #expect(throws: SimulationError.snapshotVersionRejected) {
            try firmware.apply(
                acknowledgement(
                    action: .completeTask,
                    operationID: 77,
                    epoch: 8,
                    revision: 9,
                    taskID: "task-a"
                ),
                screenSize: .fourInch
            )
        }
        #expect(firmware.version == nil)
        #expect(firmware.tasks.isEmpty)
        #expect(firmware.pendingOperationID == 77)
    }

    @Test("A changed epoch must restart at revision 1")
    func changedEpochMustRestartAtRevisionOne() throws {
        var firmware = try firmwareWithInitialSnapshot()
        try firmware.beginPending(action: .requestRefresh, operationID: 91)

        #expect(throws: SimulationError.snapshotVersionRejected) {
            try firmware.apply(
                acknowledgement(
                    operationID: 91,
                    epoch: 4,
                    revision: 2,
                    taskID: "task-b"
                ),
                screenSize: .fourInch
            )
        }
        #expect(firmware.version == TaskListSnapshotVersion(epoch: 3, revision: 1))
        #expect(firmware.tasks.map(\.id) == ["task-a"])
        #expect(firmware.pendingOperationID == 91)

        try firmware.apply(
            acknowledgement(
                operationID: 91,
                epoch: 4,
                revision: 1,
                taskID: "task-b"
            ),
            screenSize: .fourInch
        )
        #expect(firmware.version == TaskListSnapshotVersion(epoch: 4, revision: 1))
        #expect(firmware.tasks.map(\.id) == ["task-b"])
        #expect(firmware.pendingOperationID == nil)
    }

    @Test("Internal error preserves the last snapshot and pending request")
    func internalErrorPreservesStateAndPendingRequest() throws {
        var firmware = try firmwareWithInitialSnapshot()
        try firmware.beginPending(action: .requestRefresh, operationID: 92)

        try firmware.apply(
            acknowledgement(
                operationID: 92,
                result: .internalError,
                epoch: 3,
                revision: 2,
                taskID: "task-b"
            ),
            screenSize: .fourInch
        )

        #expect(firmware.version == TaskListSnapshotVersion(epoch: 3, revision: 1))
        #expect(firmware.tasks.map(\.id) == ["task-a"])
        #expect(firmware.pendingAction == .requestRefresh)
        #expect(firmware.pendingOperationID == 92)
    }

    @Test("An identical retry of an applied frame is ignored idempotently")
    func identicalAppliedFrameIsIdempotent() throws {
        let frame = acknowledgement(
            operationID: 90,
            epoch: 3,
            revision: 1,
            taskID: "task-a"
        )
        var firmware = SimulatedTaskListSnapshotFirmware()
        try firmware.beginPending(action: .requestRefresh, operationID: 90)
        try firmware.apply(frame, screenSize: .fourInch)

        try firmware.apply(frame, screenSize: .fourInch)

        #expect(firmware.version == TaskListSnapshotVersion(epoch: 3, revision: 1))
        #expect(firmware.tasks.map(\.id) == ["task-a"])
        #expect(firmware.pendingOperationID == nil)
    }

    @Test("A changed frame cannot reuse an applied revision")
    func changedFrameCannotReuseAppliedRevision() throws {
        var firmware = try firmwareWithInitialSnapshot()
        try firmware.beginPending(action: .requestRefresh, operationID: 90)

        #expect(throws: SimulationError.snapshotVersionRejected) {
            try firmware.apply(
                acknowledgement(
                    operationID: 90,
                    epoch: 3,
                    revision: 1,
                    taskID: "task-b"
                ),
                screenSize: .fourInch
            )
        }
        #expect(firmware.version == TaskListSnapshotVersion(epoch: 3, revision: 1))
        #expect(firmware.tasks.map(\.id) == ["task-a"])
        #expect(firmware.pendingOperationID == 90)
    }

    @Test("Zero epoch or revision is rejected without partial replacement")
    func zeroVersionIsRejectedAtomically() throws {
        var firmware = SimulatedTaskListSnapshotFirmware()
        try firmware.beginPending(action: .requestRefresh, operationID: 93)

        for version in [
            TaskListSnapshotVersion(epoch: 0, revision: 1),
            TaskListSnapshotVersion(epoch: 3, revision: 0),
        ] {
            #expect(throws: SimulationError.snapshotVersionRejected) {
                try firmware.apply(
                    acknowledgement(
                        operationID: 93,
                        epoch: version.epoch,
                        revision: version.revision,
                        taskID: "task-a"
                    ),
                    screenSize: .fourInch
                )
            }
        }

        #expect(firmware.version == nil)
        #expect(firmware.tasks.isEmpty)
        #expect(firmware.pendingOperationID == 93)
    }

    private func firmwareWithInitialSnapshot() throws -> SimulatedTaskListSnapshotFirmware {
        var firmware = SimulatedTaskListSnapshotFirmware()
        try firmware.beginPending(action: .requestRefresh, operationID: 90)
        try firmware.apply(
            acknowledgement(
                operationID: 90,
                epoch: 3,
                revision: 1,
                taskID: "task-a"
            ),
            screenSize: .fourInch
        )
        return firmware
    }

    private func acknowledgement(
        action: TaskListSnapshotAction = .requestRefresh,
        operationID: UInt32,
        result: TaskListSnapshotResultCode = .applied,
        epoch: UInt32,
        revision: UInt32,
        taskID: String
    ) -> SimulatedTaskListSnapshotAck {
        SimulatedTaskListSnapshotAck(
            action: action,
            operationID: operationID,
            result: result,
            epoch: epoch,
            revision: revision,
            tasks: [
                SimulatedTaskListSnapshotAck.Task(
                    id: taskID,
                    title: taskID,
                    isCompleted: false,
                    priority: 1
                ),
            ]
        )
    }

    private func malformedSnapshotPayload(
        operationID: UInt32,
        epoch: UInt32,
        revision: UInt32,
        completed: UInt8
    ) -> Data {
        var payload = Data([TaskListSnapshotAck.subVersion, TaskListSnapshotAction.requestRefresh.rawValue])
        payload.appendBigEndian(operationID)
        payload.append(TaskListSnapshotResultCode.applied.rawValue)
        payload.appendBigEndian(epoch)
        payload.appendBigEndian(revision)
        payload.append(1)
        payload.append(1)
        payload.append(contentsOf: Data("a".utf8))
        payload.append(1)
        payload.append(contentsOf: Data("A".utf8))
        payload.append(completed)
        payload.append(UInt8(TaskPriority.medium.rawValue))
        return payload
    }
}
