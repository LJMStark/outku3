// ============================================================
// Durable offline task-action ledger (device outbox + idempotency)
// Identity is scoped by (action, operationId) per BLE protocol.
// Replay order is always insertionSeq — never RTC timestamp.
// ============================================================

export function normalizeTaskAction(action) {
  if (action === 'complete' || action === 'hw_complete_task' || action === 0x11) {
    return 'complete';
  }
  if (action === 'skip' || action === 'hw_skip_task' || action === 0x12) {
    return 'skip';
  }
  return null;
}

export function normalizeAckResult(result) {
  if (result == null) return null;
  if (typeof result === 'string') return result;
  if (typeof result === 'object') {
    const code = result.code ?? result.result ?? result.status;
    return code == null ? null : String(code);
  }
  return String(result);
}

const TERMINAL_ACK_RESULTS = new Set([
  'applied',
  'alreadyApplied',
  'taskNotFound',
  'invalidRequest',
  'supersededByApp',
]);

export function isInternalErrorResult(result) {
  const code = normalizeAckResult(result);
  return code === 'internalError'
    || code === 'internal_error'
    || code === 'FF'
    || code === '0xFF'
    || code === '255';
}

export function taskActionToHardwareMessage(entry) {
  if (!entry) return null;
  return {
    type: entry.action === 'complete' ? 'hw_complete_task' : 'hw_skip_task',
    taskId: entry.taskId,
    operationId: entry.operationId,
    insertionSeq: entry.insertionSeq,
    timestamp: entry.timestamp,
    result: entry.result,
  };
}

/**
 * Device-side durable ledger for offline complete/skip actions.
 * Does not own task-library mutation — callers supply applyMutation.
 */
export class TaskActionLedger {
  constructor() {
    this.entries = [];
    // Operation IDs are scoped per action (complete 7 ≠ skip 7).
    this.nextOperationIdByAction = { complete: 1, skip: 1 };
    this.nextInsertionSeq = 1;
    this.replayFailed = false;
    this.replayFailureReason = null;
  }

  pendingActions() {
    return this._byStatus('pending');
  }

  unacknowledgedActions() {
    return this._byStatus('unacknowledged');
  }

  acknowledgedActions() {
    return this._byStatus('acknowledged');
  }

  /** Outbox = pending ∪ unacknowledged, ordered by insertionSeq. */
  outboxActions() {
    return this.entries
      .filter(entry => entry.status === 'pending' || entry.status === 'unacknowledged')
      .slice()
      .sort((a, b) => a.insertionSeq - b.insertionSeq);
  }

  hasOutbox() {
    return this.outboxActions().length > 0;
  }

  canAcceptTaskLibrarySnapshot() {
    if (this.replayFailed) return false;
    return !this.hasOutbox();
  }

  allocateOperationId(action) {
    const normalized = normalizeTaskAction(action);
    if (!normalized) throw new Error(`unknown task action: ${action}`);
    const operationId = this.nextOperationIdByAction[normalized];
    this.nextOperationIdByAction[normalized] = operationId + 1;
    return operationId;
  }

  allocateInsertionSeq() {
    const insertionSeq = this.nextInsertionSeq;
    this.nextInsertionSeq += 1;
    return insertionSeq;
  }

  findByIdentity(action, operationId) {
    const normalized = normalizeTaskAction(action);
    const opId = Number(operationId);
    if (!normalized || !Number.isFinite(opId) || opId <= 0) return null;
    return this.entries.find(
      entry => entry.action === normalized && entry.operationId === opId
    ) || null;
  }

  /**
   * Mark pending → unacknowledged, then return the full outbox (pending was just
   * promoted; prior unacknowledged stay) in insertionSeq order for resend.
   */
  flushOutboxForReplay() {
    this.entries = this.entries.map(entry => (
      entry.status === 'pending'
        ? { ...entry, status: 'unacknowledged' }
        : entry
    ));
    return this.outboxActions();
  }

  markReplayFailed(reason = 'replay_failed') {
    this.replayFailed = true;
    this.replayFailureReason = String(reason);
  }

  clearReplayFailed() {
    this.replayFailed = false;
    this.replayFailureReason = null;
  }

  /**
   * App business ACK for a device outbox item.
   * Non-internal-error results matching (action, operationId) clear the outbox item
   * (status → acknowledged) while retaining the entry for duplicate caching.
   * internalError keeps the item in outbox and blocks library snapshots.
   */
  applyAppAck({ action, operationId, result } = {}) {
    const normalized = normalizeTaskAction(action);
    const opId = Number(operationId);
    if (!normalized || !Number.isFinite(opId) || opId <= 0) {
      return {
        status: 'rejected',
        result: { code: 'invalidRequest', reason: 'malformed_ack' },
      };
    }

    const existing = this.findByIdentity(normalized, opId);
    if (!existing) {
      return {
        status: 'unmatched',
        result: { code: 'invalidRequest', reason: 'unknown_operation' },
      };
    }

    if (isInternalErrorResult(result)) {
      this.markReplayFailed('app_internal_error');
      // Keep pending/unacknowledged so reconnect can resend.
      if (existing.status === 'pending') {
        this.entries = this.entries.map(entry => (
          entry.action === normalized && entry.operationId === opId
            ? { ...entry, status: 'unacknowledged' }
            : entry
        ));
      }
      return {
        status: 'internalError',
        result: { code: 'internalError', reason: 'app_internal_error' },
        entry: this.findByIdentity(normalized, opId),
      };
    }

    const code = normalizeAckResult(result);
    if (!TERMINAL_ACK_RESULTS.has(code)) {
      return {
        status: 'rejected',
        result: { code: 'invalidRequest', reason: 'invalid_ack_result' },
        entry: existing,
      };
    }
    this.entries = this.entries.map(entry => (
      entry.action === normalized && entry.operationId === opId
        ? {
            ...entry,
            status: 'acknowledged',
            appResult: code,
          }
        : entry
    ));
    // A successful business ACK means this attempt did not fail replay.
    if (!this.hasOutbox()) {
      this.clearReplayFailed();
    }
    return {
      status: 'acknowledged',
      result: { code },
      entry: this.findByIdentity(normalized, opId),
    };
  }

  /**
   * Ingest a task action with (action, operationId)-scoped idempotency.
   * applyMutation(action, taskId) performs local library mutation for first apply only.
   */
  ingest(
    {
      operationId,
      action,
      taskId,
      timestamp,
      insertionSeq = null,
    } = {},
    applyMutation = () => ({ applied: false })
  ) {
    const normalizedAction = normalizeTaskAction(action);
    const normalizedTaskId = String(taskId || '');
    const opId = Number(operationId);
    const ts = Number(timestamp);

    if (!normalizedAction || !normalizedTaskId || !Number.isFinite(opId) || opId <= 0) {
      return {
        status: 'rejected',
        result: { code: 'invalidRequest', reason: 'malformed_task_action' },
      };
    }

    const existing = this.findByIdentity(normalizedAction, opId);
    if (existing) {
      if (this._payloadEquals(existing, {
        taskId: normalizedTaskId,
        timestamp: ts,
      })) {
        return {
          status: 'duplicate',
          result: { ...existing.result },
          entry: existing,
        };
      }
      return {
        status: 'conflict',
        result: {
          code: 'invalidRequest',
          reason: 'operation_id_payload_conflict',
          action: normalizedAction,
          operationId: opId,
          existingPayload: {
            action: existing.action,
            taskId: existing.taskId,
            timestamp: existing.timestamp,
          },
          receivedPayload: {
            action: normalizedAction,
            taskId: normalizedTaskId,
            timestamp: ts,
          },
        },
        entry: existing,
      };
    }

    const seq = Number.isFinite(Number(insertionSeq)) && Number(insertionSeq) > 0
      ? Number(insertionSeq)
      : this.allocateInsertionSeq();

    if (opId >= this.nextOperationIdByAction[normalizedAction]) {
      this.nextOperationIdByAction[normalizedAction] = opId + 1;
    }
    if (seq >= this.nextInsertionSeq) {
      this.nextInsertionSeq = seq + 1;
    }

    const mutation = applyMutation(normalizedAction, normalizedTaskId) || { applied: false };
    const result = {
      code: mutation.applied ? 'applied' : 'taskNotFound',
      type: normalizedAction === 'complete' ? 'hw_complete_task' : 'hw_skip_task',
      taskId: normalizedTaskId,
      reward: 0,
    };
    const entry = {
      operationId: opId,
      insertionSeq: seq,
      action: normalizedAction,
      taskId: normalizedTaskId,
      timestamp: ts,
      status: 'pending',
      result,
    };
    this.entries = [...this.entries, entry];
    return { status: 'applied', result, entry };
  }

  exportState() {
    return {
      entries: this.entries.map(entry => ({
        ...entry,
        result: entry.result ? { ...entry.result } : entry.result,
      })),
      nextOperationIdByAction: { ...this.nextOperationIdByAction },
      nextInsertionSeq: this.nextInsertionSeq,
      replayFailed: this.replayFailed,
      replayFailureReason: this.replayFailureReason,
    };
  }

  importState(snapshot = {}) {
    this.entries = Array.isArray(snapshot.entries)
      ? snapshot.entries.map(entry => ({
          ...entry,
          action: normalizeTaskAction(entry.action) || entry.action,
          operationId: Number(entry.operationId),
          insertionSeq: Number(entry.insertionSeq),
          timestamp: Number(entry.timestamp),
          result: entry.result ? { ...entry.result } : entry.result,
        }))
      : [];

    if (snapshot.nextOperationIdByAction) {
      this.nextOperationIdByAction = {
        complete: Math.max(1, Number(snapshot.nextOperationIdByAction.complete) || 1),
        skip: Math.max(1, Number(snapshot.nextOperationIdByAction.skip) || 1),
      };
    } else if (snapshot.nextOperationId != null) {
      // Backward-compatible single counter → both action scopes.
      const n = Math.max(1, Number(snapshot.nextOperationId) || 1);
      this.nextOperationIdByAction = { complete: n, skip: n };
    } else {
      this.nextOperationIdByAction = { complete: 1, skip: 1 };
    }

    this.nextInsertionSeq = Math.max(1, Number(snapshot.nextInsertionSeq) || 1);
    this.replayFailed = Boolean(snapshot.replayFailed);
    this.replayFailureReason = snapshot.replayFailureReason ?? null;
  }

  _byStatus(status) {
    return this.entries
      .filter(entry => entry.status === status)
      .slice()
      .sort((a, b) => a.insertionSeq - b.insertionSeq);
  }

  _payloadEquals(entry, payload) {
    // Action is already part of identity; payload is taskId + timestamp.
    return entry.taskId === payload.taskId
      && Number(entry.timestamp) === Number(payload.timestamp);
  }
}
