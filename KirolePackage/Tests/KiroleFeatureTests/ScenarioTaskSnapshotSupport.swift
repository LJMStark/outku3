import Foundation
@testable import KiroleFeature

actor ScenarioTaskSnapshotVersionProvider: TaskListSnapshotVersionProviding {
    private var revision: UInt32 = 0

    func nextTaskListSnapshotVersion() -> TaskListSnapshotVersion {
        revision += 1
        return TaskListSnapshotVersion(epoch: 1, revision: revision)
    }
}
