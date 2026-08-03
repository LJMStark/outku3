import assert from 'node:assert/strict';
import test from 'node:test';

import { DisplayMode, SimulatorState } from '../src/state.js';
import { WebSocketBridge } from '../src/websocket-bridge.js';

const committedTasks = [
  {
    taskID: 'alpha',
    title: 'Alpha',
    detail: 'First task details',
    phaseTexts: {
      starting: 'Alpha 0-5',
      building: 'Alpha 6-15',
      deep: 'Alpha 16+',
    },
  },
  {
    taskID: 'beta',
    title: 'Beta',
    detail: 'Second task details',
    phaseTexts: {
      starting: 'Beta 0-5',
      building: 'Beta 6-15',
      deep: 'Beta 16+',
    },
  },
  {
    taskID: 'gamma',
    title: 'Gamma',
    detail: 'Third task details',
    phaseTexts: {
      starting: 'Gamma 0-5',
      building: 'Gamma 6-15',
      deep: 'Gamma 16+',
    },
  },
];

function disconnectedState(now = 1_778_200_000_000) {
  const state = new SimulatorState({ nowProvider: () => now });
  state.setAppConnected(false);
  state.setCommittedTaskLibrary(committedTasks);
  return state;
}

function bridgeFor(state) {
  const bridge = Object.create(WebSocketBridge.prototype);
  bridge.state = state;
  bridge.ws = null;
  bridge._sent = [];
  bridge._log = () => {};
  bridge.send = message => {
    bridge._sent.push(message);
  };
  return bridge;
}

test('offline complete mutates the committed library, returns to source, and persists a pending action', () => {
  const state = disconnectedState();
  state.enterDailySummary();
  state.startFocusTask(committedTasks[0]);

  const message = state.completeCurrentTask();

  assert.equal(message.type, 'hw_complete_task');
  assert.equal(message.taskId, 'alpha');
  assert.ok(message.operationId > 0);
  assert.ok(message.insertionSeq > 0);
  assert.equal(state.displayMode, DisplayMode.DAILY_SUMMARY);
  assert.deepEqual(state.taskLibrary.map(task => task.id), ['beta', 'gamma']);

  const pending = state.pendingTaskActions();
  assert.equal(pending.length, 1);
  assert.equal(pending[0].action, 'complete');
  assert.equal(pending[0].taskId, 'alpha');
  assert.equal(pending[0].operationId, message.operationId);
  assert.equal(pending[0].insertionSeq, message.insertionSeq);
  assert.equal(pending[0].status, 'pending');
});

test('offline skip moves task to the tail, awards zero, and persists a pending action', () => {
  const state = disconnectedState();
  state.update({ energyBottles: 7 });
  state.handleShortPress();

  const message = state.skipCurrentTask();

  assert.equal(message.type, 'hw_skip_task');
  assert.equal(message.taskId, 'alpha');
  assert.ok(message.operationId > 0);
  assert.equal(state.displayMode, DisplayMode.IDLE);
  assert.equal(state.energyBottles, 7);
  assert.deepEqual(state.taskLibrary.map(task => task.id), ['beta', 'gamma', 'alpha']);
  assert.equal(state.taskLibrary.at(-1).completed, undefined);

  const pending = state.pendingTaskActions();
  assert.equal(pending.length, 1);
  assert.equal(pending[0].action, 'skip');
  assert.equal(pending[0].taskId, 'alpha');
  assert.equal(pending[0].status, 'pending');
});

test('replay order follows insertion sequence, never RTC timestamps', () => {
  let now = 1_778_200_000_000;
  const state = new SimulatorState({ nowProvider: () => now });
  state.setAppConnected(false);
  state.setCommittedTaskLibrary(committedTasks);

  state.handleShortPress();
  now = 1_778_200_500_000; // later RTC for first action
  const complete = state.completeCurrentTask();

  state.handleShortPress();
  now = 1_778_200_100_000; // earlier RTC for second action
  const skip = state.skipCurrentTask();

  assert.ok(complete.timestamp > skip.timestamp);
  assert.ok(complete.insertionSeq < skip.insertionSeq);

  const flushed = state.flushPendingTaskActions();
  assert.deepEqual(
    flushed.map(entry => [entry.action, entry.operationId]),
    [
      ['complete', complete.operationId],
      ['skip', skip.operationId],
    ]
  );
  assert.deepEqual(
    flushed.map(entry => entry.insertionSeq),
    [complete.insertionSeq, skip.insertionSeq]
  );
  assert.ok(flushed.every(entry => entry.status === 'unacknowledged'));
});

test('exact same action+id+taskId+timestamp is a duplicate without second mutation', () => {
  const state = disconnectedState();
  state.handleShortPress();
  const first = state.completeCurrentTask();
  const libraryAfterFirst = state.taskLibrary.map(task => task.id);
  const energy = state.energyBottles;

  const duplicate = state.ingestTaskAction({
    operationId: first.operationId,
    action: 'complete',
    taskId: first.taskId,
    timestamp: first.timestamp,
  });

  assert.equal(duplicate.status, 'duplicate');
  assert.equal(duplicate.result.code, first.result.code);
  assert.deepEqual(state.taskLibrary.map(task => task.id), libraryAfterFirst);
  assert.equal(state.energyBottles, energy);
  assert.equal(state.pendingTaskActions().length, 1);
});

test('same action+id with a different task or timestamp is a diagnosable conflict', () => {
  const state = disconnectedState();
  state.handleShortPress();
  const first = state.completeCurrentTask();
  const libraryAfterFirst = state.taskLibrary.map(task => task.id);

  const conflict = state.ingestTaskAction({
    operationId: first.operationId,
    action: 'complete',
    taskId: 'beta',
    timestamp: first.timestamp + 10,
  });

  assert.equal(conflict.status, 'conflict');
  assert.equal(conflict.result.code, 'invalidRequest');
  assert.match(String(conflict.result.reason || ''), /payload|conflict|operation/i);
  assert.deepEqual(state.taskLibrary.map(task => task.id), libraryAfterFirst);
});

test('complete and skip may share the same numeric operation id because identity is action-scoped', () => {
  const state = disconnectedState();

  const complete = state.ingestTaskAction({
    operationId: 7,
    action: 'complete',
    taskId: 'alpha',
    timestamp: 100,
  });
  const skip = state.ingestTaskAction({
    operationId: 7,
    action: 'skip',
    taskId: 'beta',
    timestamp: 200,
  });

  assert.equal(complete.status, 'applied');
  assert.equal(skip.status, 'applied');
  assert.deepEqual(
    state.outboxTaskActions().map(entry => [entry.action, entry.operationId]),
    [
      ['complete', 7],
      ['skip', 7],
    ]
  );
  assert.deepEqual(state.taskLibrary.map(task => task.id), ['gamma', 'beta']);
});

test('export/import restores pending and unacknowledged actions; acknowledged entries stay for cache', () => {
  const state = disconnectedState();
  state.handleShortPress();
  const complete = state.completeCurrentTask();
  state.handleShortPress();
  const skip = state.skipCurrentTask();
  state.flushPendingTaskActions();
  state.applyTaskActionAck({
    action: 'complete',
    operationId: complete.operationId,
    result: 'applied',
  });

  const snapshot = state.exportDurableDeviceState();
  const restored = new SimulatorState();
  restored.importDurableDeviceState(snapshot);

  assert.deepEqual(
    restored.taskLibrary.map(task => task.id),
    state.taskLibrary.map(task => task.id)
  );

  const completeEntry = restored.taskActionLedger.find(
    entry => entry.action === 'complete' && entry.operationId === complete.operationId
  );
  const skipEntry = restored.taskActionLedger.find(
    entry => entry.action === 'skip' && entry.operationId === skip.operationId
  );
  assert.equal(completeEntry.status, 'acknowledged');
  assert.equal(skipEntry.status, 'unacknowledged');
  assert.deepEqual(restored.pendingTaskActions(), []);
  assert.deepEqual(
    restored.unacknowledgedTaskActions().map(entry => entry.operationId),
    [skip.operationId]
  );
  assert.equal(restored._nextInsertionSeq, state._nextInsertionSeq);

  // Acknowledged entries still serve duplicate caching after restart.
  const cached = restored.ingestTaskAction({
    operationId: complete.operationId,
    action: 'complete',
    taskId: complete.taskId,
    timestamp: complete.timestamp,
  });
  assert.equal(cached.status, 'duplicate');
  assert.equal(cached.result.code, 'applied');
});

test('reconnect resends pending and unacknowledged actions; library waits for explicit ACK', () => {
  const state = disconnectedState();
  state.handleShortPress();
  const complete = state.completeCurrentTask();

  assert.equal(
    state.setCommittedTaskLibrary([{ taskID: 'zeta', title: 'Zeta' }]),
    false
  );

  const bridge = bridgeFor(state);
  bridge._onConnected();

  assert.equal(bridge._sent.length, 2);
  assert.equal(bridge._sent[0].type, 'hw_complete_task');
  assert.equal(bridge._sent[1].type, 'hw_task_action_replay_end');
  assert.equal(state.pendingTaskActions().length, 0);
  assert.equal(state.unacknowledgedTaskActions().length, 1);

  // Flush / replay_end alone must NOT open the library gate.
  assert.equal(
    state.setCommittedTaskLibrary([{ taskID: 'zeta', title: 'Zeta' }]),
    false
  );

  // Second reconnect must resend the still-unacknowledged outbox item, then end.
  bridge._sent = [];
  bridge._onConnected();
  assert.equal(bridge._sent.length, 2);
  assert.equal(bridge._sent[0].operationId, complete.operationId);
  assert.equal(bridge._sent[0].type, 'hw_complete_task');
  assert.equal(bridge._sent[1].type, 'hw_task_action_replay_end');

  bridge._handleMessage({
    type: 'app_task_action_ack',
    action: 'complete',
    operationId: complete.operationId,
    result: 'applied',
  });
  assert.equal(state.outboxTaskActions().length, 0);
  assert.equal(
    state.setCommittedTaskLibrary([{ taskID: 'zeta', title: 'Zeta' }]),
    true
  );
  assert.deepEqual(state.taskLibrary.map(task => task.id), ['zeta']);
});

test('websocket reconnect emits action A, action B, then hw_task_action_replay_end in order', () => {
  const state = disconnectedState();
  state.handleShortPress();
  const actionA = state.completeCurrentTask();
  state.handleShortPress();
  const actionB = state.skipCurrentTask();

  const bridge = bridgeFor(state);
  bridge._onConnected();

  assert.deepEqual(
    bridge._sent.map(message => message.type),
    ['hw_complete_task', 'hw_skip_task', 'hw_task_action_replay_end']
  );
  assert.equal(bridge._sent[0].operationId, actionA.operationId);
  assert.equal(bridge._sent[0].taskId, 'alpha');
  assert.equal(bridge._sent[1].operationId, actionB.operationId);
  assert.equal(bridge._sent[1].taskId, 'beta');
  assert.deepEqual(bridge._sent[2], { type: 'hw_task_action_replay_end' });

  // replay_end is only a wire marker — outbox still blocks the library.
  assert.equal(state.outboxTaskActions().length, 2);
  assert.equal(
    state.setCommittedTaskLibrary([{ taskID: 'zeta', title: 'Zeta' }]),
    false
  );
});

test('restart keeps unacknowledged outbox replayable on the next reconnect', () => {
  const state = disconnectedState();
  state.handleShortPress();
  const complete = state.completeCurrentTask();
  state.flushPendingTaskActions();

  const restored = new SimulatorState();
  restored.importDurableDeviceState(state.exportDurableDeviceState());
  assert.equal(restored.unacknowledgedTaskActions().length, 1);

  const bridge = bridgeFor(restored);
  bridge._onConnected();
  assert.equal(bridge._sent.length, 2);
  assert.equal(bridge._sent[0].operationId, complete.operationId);
  assert.equal(bridge._sent[1].type, 'hw_task_action_replay_end');
  assert.equal(restored.canAcceptTaskLibrarySnapshot(), false);

  bridge._handleMessage({
    type: 'app_task_action_ack',
    payload: {
      action: 'complete',
      operationId: complete.operationId,
      result: { code: 'applied' },
    },
  });
  assert.equal(restored.canAcceptTaskLibrarySnapshot(), true);
});

test('internalError ACK keeps the outbox item and continues blocking the library', () => {
  const state = disconnectedState();
  state.handleShortPress();
  const complete = state.completeCurrentTask();
  state.flushPendingTaskActions();

  const outcome = state.applyTaskActionAck({
    action: 'complete',
    operationId: complete.operationId,
    result: 'internalError',
  });
  assert.equal(outcome.status, 'internalError');
  assert.equal(state.replayFailed, true);
  assert.equal(state.unacknowledgedTaskActions().length, 1);
  assert.equal(
    state.setCommittedTaskLibrary([{ taskID: 'stale', title: 'Stale' }]),
    false
  );

  // clearReplayFailed alone is insufficient while outbox remains.
  state.clearReplayFailed();
  assert.equal(
    state.setCommittedTaskLibrary([{ taskID: 'stale', title: 'Stale' }]),
    false
  );

  state.applyTaskActionAck({
    action: 'complete',
    operationId: complete.operationId,
    result: 'applied',
  });
  assert.equal(state.outboxTaskActions().length, 0);
  assert.equal(
    state.setCommittedTaskLibrary([{ taskID: 'fresh', title: 'Fresh' }]),
    true
  );
});

test('websocket bridge refuses app_task_library until every outbox item is ACKed', () => {
  const state = disconnectedState();
  state.handleShortPress();
  const complete = state.completeCurrentTask();
  const bridge = bridgeFor(state);

  bridge._handleMessage({
    type: 'app_task_library',
    payload: { records: [{ taskID: 'stale', title: 'Stale' }] },
  });
  assert.deepEqual(state.taskLibrary.map(task => task.id), ['beta', 'gamma']);

  bridge._onConnected();
  bridge._handleMessage({
    type: 'app_task_library',
    payload: { records: [{ taskID: 'still-blocked', title: 'Still' }] },
  });
  assert.deepEqual(state.taskLibrary.map(task => task.id), ['beta', 'gamma']);

  bridge._handleMessage({
    type: 'app_task_action_ack',
    action: 'complete',
    operationId: complete.operationId,
    result: 'alreadyApplied',
  });
  bridge._handleMessage({
    type: 'app_task_library',
    payload: { records: [{ taskID: 'merged', title: 'Merged' }] },
  });
  assert.deepEqual(state.taskLibrary.map(task => task.id), ['merged']);
});

test('failed-replay flag blocks library even after outbox is empty until cleared', () => {
  const state = disconnectedState();
  state.markReplayFailed('batch corrupt');
  assert.equal(
    state.setCommittedTaskLibrary([{ taskID: 'x', title: 'X' }]),
    false
  );
  state.clearReplayFailed();
  assert.equal(
    state.setCommittedTaskLibrary([{ taskID: 'x', title: 'X' }]),
    true
  );
});
