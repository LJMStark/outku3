// ============================================================
// SimulatorState offline task-action surface (outbox + durable state)
// Kept separate so state.js stays under the 800-line package limit.
// ============================================================

import { taskActionToHardwareMessage } from './task-action-ledger.js';

/**
 * Install offline task-action methods on SimulatorState.prototype.
 * @param {object} proto
 * @param {{ isFocusMode: (mode: string) => boolean }} deps
 */
export function installTaskActionDeviceApi(proto, { isFocusMode }) {
  Object.assign(proto, {
    canAcceptTaskLibrarySnapshot() {
      return this._taskActionLedger.canAcceptTaskLibrarySnapshot();
    },

    pendingTaskActions() {
      return this._taskActionLedger.pendingActions();
    },

    unacknowledgedTaskActions() {
      return this._taskActionLedger.unacknowledgedActions();
    },

    outboxTaskActions() {
      return this._taskActionLedger.outboxActions();
    },

    /**
     * Reconnect resend: promote pending → unacknowledged, return full outbox
     * (pending + prior unacknowledged) ordered by insertionSeq.
     */
    flushPendingTaskActions() {
      const outbox = this._taskActionLedger.flushOutboxForReplay();
      this._notify();
      return outbox;
    },

    /**
     * Explicit App business ACK. Non-internal-error matching action+ID clears outbox.
     */
    applyTaskActionAck({ action, operationId, result } = {}) {
      const outcome = this._taskActionLedger.applyAppAck({ action, operationId, result });
      this._notify();
      return outcome;
    },

    /** @deprecated Prefer applyTaskActionAck({ action, operationId, result }) */
    acknowledgeTaskAction(actionOrOperationId, operationId) {
      if (typeof actionOrOperationId === 'object' && actionOrOperationId) {
        return this.applyTaskActionAck(actionOrOperationId);
      }
      if (operationId === undefined) {
        return {
          status: 'rejected',
          result: { code: 'invalidRequest', reason: 'action_required' },
        };
      }
      return this.applyTaskActionAck({
        action: actionOrOperationId,
        operationId,
        result: 'applied',
      });
    },

    markReplayFailed(reason = 'replay_failed') {
      this._taskActionLedger.markReplayFailed(reason);
      this._notify();
    },

    clearReplayFailed() {
      this._taskActionLedger.clearReplayFailed();
      this._notify();
    },

    /**
     * Identity is (action, operationId). Same action+ID+taskId+timestamp is a
     * duplicate; same action+ID with different task/timestamp is a conflict.
     * Complete ID N and Skip ID N are distinct.
     */
    ingestTaskAction({
      operationId,
      action,
      taskId,
      timestamp = Math.floor(this._nowProvider() / 1000),
      insertionSeq = null,
    } = {}) {
      const outcome = this._taskActionLedger.ingest(
        { operationId, action, taskId, timestamp, insertionSeq },
        (normalizedAction, normalizedTaskId) => (
          this._applyTaskActionMutation(normalizedAction, normalizedTaskId)
        )
      );
      if (outcome.status === 'applied') this._notify();
      return outcome;
    },

    exportDurableDeviceState() {
      const ledger = this._taskActionLedger.exportState();
      return {
        version: 1,
        taskLibrary: this.taskLibrary.map(task => ({
          ...task,
          phaseTexts: { ...task.phaseTexts },
        })),
        tasks: this.tasks.map(task => ({ ...task })),
        energyBottles: this.energyBottles,
        taskActionLedger: ledger.entries,
        nextOperationIdByAction: ledger.nextOperationIdByAction,
        nextInsertionSeq: ledger.nextInsertionSeq,
        replayFailed: ledger.replayFailed,
        replayFailureReason: ledger.replayFailureReason,
        activeFocusTaskId: this.activeFocusTaskId,
        focusTask: this.focusTask
          ? { ...this.focusTask, phaseTexts: { ...(this.focusTask.phaseTexts || {}) } }
          : null,
        focusPhase: this.focusPhase,
        focusElapsedMinutes: this.focusElapsedMinutes,
        focusStartedAt: this.focusStartedAt,
        focusTimerActive: this.focusTimerActive,
        focusSourceMode: this.focusSourceMode,
        displayMode: this.displayMode,
      };
    },

    importDurableDeviceState(snapshot = {}) {
      if (!snapshot || typeof snapshot !== 'object') return false;

      this._taskActionLedger.importState({
        entries: snapshot.taskActionLedger,
        nextOperationIdByAction: snapshot.nextOperationIdByAction,
        nextOperationId: snapshot.nextOperationId,
        nextInsertionSeq: snapshot.nextInsertionSeq,
        replayFailed: snapshot.replayFailed,
        replayFailureReason: snapshot.replayFailureReason,
      });

      // Bypass the reconnect gate: restore is a local durable reload, not an App snapshot.
      const taskLibrary = Array.isArray(snapshot.taskLibrary)
        ? snapshot.taskLibrary
            .map(record => this._normalizeTaskRecord(record))
            .filter(record => record.id && !record.completed)
        : this.taskLibrary;

      this.update({
        taskLibrary,
        tasks: Array.isArray(snapshot.tasks)
          ? snapshot.tasks.map(task => ({ ...task }))
          : this.tasks,
        energyBottles: snapshot.energyBottles ?? this.energyBottles,
        activeFocusTaskId: snapshot.activeFocusTaskId ?? null,
        focusTask: snapshot.focusTask
          ? this._normalizeTaskRecord(snapshot.focusTask)
          : this.focusTask,
        focusPhase: snapshot.focusPhase ?? this.focusPhase,
        focusElapsedMinutes: snapshot.focusElapsedMinutes ?? this.focusElapsedMinutes,
        focusStartedAt: snapshot.focusStartedAt ?? this.focusStartedAt,
        focusTimerActive: Boolean(snapshot.focusTimerActive),
        focusSourceMode: snapshot.focusSourceMode ?? this.focusSourceMode,
        displayMode: snapshot.displayMode ?? this.displayMode,
        currentPhaseBottleProgress: snapshot.focusElapsedMinutes
          ? Number(snapshot.focusElapsedMinutes) / 30
          : this.currentPhaseBottleProgress,
      });
      return true;
    },

    _performOfflineTaskAction(action, taskId) {
      const operationId = this._taskActionLedger.allocateOperationId(action);
      const timestamp = Math.floor(this._nowProvider() / 1000);
      const outcome = this.ingestTaskAction({
        operationId,
        action,
        taskId,
        timestamp,
      });
      const entry = outcome.entry;

      if (isFocusMode(this.displayMode) && this.activeFocusTaskId === taskId) {
        this._returnFromFocus();
      }

      return {
        type: action === 'complete' ? 'hw_complete_task' : 'hw_skip_task',
        taskId,
        operationId: entry?.operationId ?? operationId,
        insertionSeq: entry?.insertionSeq,
        timestamp: entry?.timestamp ?? timestamp,
        result: outcome.result,
      };
    },

    taskActionToHardwareMessage(entry) {
      return taskActionToHardwareMessage(entry);
    },

    _applyTaskActionMutation(action, taskId) {
      if (action === 'complete') {
        const inLibrary = this.taskLibrary.some(task => task.id === taskId);
        const taskLibrary = this.taskLibrary.filter(task => task.id !== taskId);
        const tasks = this.tasks.map(task => (
          this._taskId(task) === taskId ? { ...task, completed: true } : task
        ));
        if (isFocusMode(this.displayMode) && this.activeFocusTaskId === taskId) {
          this._returnFromFocus({ taskLibrary, tasks }, { notify: false });
        } else {
          this.update({ taskLibrary, tasks }, { notify: false });
        }
        return { applied: true, inLibrary };
      }

      if (action === 'skip') {
        const taskIndex = this.taskLibrary.findIndex(task => task.id === taskId);
        const taskLibrary = taskIndex < 0
          ? this.taskLibrary
          : [
              ...this.taskLibrary.slice(0, taskIndex),
              ...this.taskLibrary.slice(taskIndex + 1),
              this.taskLibrary[taskIndex],
            ];
        if (isFocusMode(this.displayMode) && this.activeFocusTaskId === taskId) {
          this._returnFromFocus({ taskLibrary }, { notify: false });
        } else {
          this.update({ taskLibrary }, { notify: false });
        }
        return { applied: true, inLibrary: taskIndex >= 0, reward: 0 };
      }

      return { applied: false };
    },
  });
}
