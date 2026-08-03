import assert from 'node:assert/strict';
import test from 'node:test';

import { HardwareControls } from '../src/hardware-controls.js';
import { DisplayMode, SimulatorState } from '../src/state.js';
import { WebSocketBridge } from '../src/websocket-bridge.js';

const originalTask = {
  taskID: 'alpha',
  title: 'Original title',
  detail: 'Original detail',
  phaseTexts: {
    starting: 'original 0-5',
    building: 'original 6-15',
    deep: 'original 16+',
  },
};

const updatedTask = {
  ...originalTask,
  title: 'Updated title',
  detail: 'Updated detail',
  phaseTexts: {
    starting: 'updated 0-5',
    building: 'updated 6-15',
    deep: 'updated 16+',
  },
};

function bridgeFor(state) {
  const bridge = Object.create(WebSocketBridge.prototype);
  bridge.state = state;
  bridge._log = () => {};
  return bridge;
}

test('a disconnected device keeps task identity, startedAt, page, and local phase boundaries', () => {
  let now = 1_778_100_000_000;
  const state = new SimulatorState({ nowProvider: () => now });
  state.setCommittedTaskLibrary([originalTask]);
  state.enterQueueHead();
  const startedAt = state.focusStartedAt;

  state.setAppConnected(false);
  const expectations = [
    [5, DisplayMode.FOCUS_WARMUP, 'original 0-5'],
    [6, DisplayMode.FOCUS_BUILDING, 'original 6-15'],
    [15, DisplayMode.FOCUS_BUILDING, 'original 6-15'],
    [16, DisplayMode.FOCUS_DEEP, 'original 16+'],
  ];

  for (const [minutes, displayMode, text] of expectations) {
    now = startedAt + (minutes * 60_000);
    state.refreshFocusFromClock();
    assert.equal(state.activeFocusTaskId, 'alpha');
    assert.equal(state.focusStartedAt, startedAt);
    assert.equal(state.displayMode, displayMode);
    assert.equal(state.focusSupportText(), text);
  }
});

test('reconnect messages only reconcile identity and elapsed time without entering or resetting', () => {
  let now = 1_778_100_000_000;
  const state = new SimulatorState({ nowProvider: () => now });
  const bridge = bridgeFor(state);
  state.setCommittedTaskLibrary([originalTask]);
  state.enterQueueHead();
  const startedAt = state.focusStartedAt;

  state.setAppConnected(false);
  now += 16 * 60_000;
  state.refreshFocusFromClock();
  state.setAppConnected(true);

  bridge._handleMessage({
    type: 'focus_start',
    payload: {
      taskId: 'alpha',
      taskTitle: 'Updated title must not be applied',
    },
  });
  bridge._handleMessage({
    type: 'app_focus_state',
    activeFocusTaskId: 'alpha',
    focusPhase: 'warmup',
    elapsedMinutes: 0,
    taskTitle: 'Updated title must not be applied',
  });

  assert.equal(state.displayMode, DisplayMode.FOCUS_DEEP);
  assert.equal(state.activeFocusTaskId, 'alpha');
  assert.equal(state.focusStartedAt, startedAt);
  assert.equal(state.focusElapsedMinutes, 16);
  assert.equal(state.focusTask.title, 'Original title');
  assert.equal(state.focusSupportText(), 'original 16+');
});

test('a reconnect state for another task cannot replace the active hardware focus', () => {
  let now = 1_778_100_000_000;
  const state = new SimulatorState({ nowProvider: () => now });
  const bridge = bridgeFor(state);
  state.setCommittedTaskLibrary([
    originalTask,
    { ...originalTask, taskID: 'beta', title: 'Beta task' },
  ]);
  state.enterQueueHead();
  const startedAt = state.focusStartedAt;

  state.setAppConnected(false);
  now += 8 * 60_000;
  state.refreshFocusFromClock();
  state.setAppConnected(true);

  bridge._handleMessage({
    type: 'focus_start',
    payload: { taskId: 'beta', taskTitle: 'Beta task' },
  });
  bridge._handleMessage({
    type: 'app_focus_state',
    activeFocusTaskId: 'beta',
    focusPhase: 'warmup',
    elapsedMinutes: 1,
    taskTitle: 'Beta task',
  });

  assert.equal(state.activeFocusTaskId, 'alpha');
  assert.equal(state.displayMode, DisplayMode.FOCUS_BUILDING);
  assert.equal(state.focusStartedAt, startedAt);
  assert.equal(state.focusElapsedMinutes, 8);
  assert.equal(state.focusTask.title, 'Original title');
});

test('same-task reconciliation adopts the greatest elapsed value without moving startedAt', () => {
  let now = 1_778_100_000_000;
  const state = new SimulatorState({ nowProvider: () => now });
  const bridge = bridgeFor(state);
  state.setCommittedTaskLibrary([originalTask]);
  state.enterQueueHead();
  const startedAt = state.focusStartedAt;

  now += 5 * 60_000;
  state.refreshFocusFromClock();
  state.setAppConnected(true);
  bridge._handleMessage({
    type: 'app_focus_state',
    activeFocusTaskId: 'alpha',
    focusPhase: 'deep',
    elapsedMinutes: 18,
  });

  assert.equal(state.focusElapsedMinutes, 18);
  assert.equal(state.displayMode, DisplayMode.FOCUS_DEEP);
  assert.equal(state.focusStartedAt, startedAt);

  now += 60_000;
  state.refreshFocusFromClock();

  assert.equal(state.focusElapsedMinutes, 18);
  assert.equal(state.displayMode, DisplayMode.FOCUS_DEEP);
  assert.equal(state.focusStartedAt, startedAt);

  now = startedAt + (19 * 60_000);
  state.refreshFocusFromClock();

  assert.equal(state.focusElapsedMinutes, 19);
  assert.equal(state.focusStartedAt, startedAt);
});

test('task-library updates stay frozen on the current focus page and appear after re-entry', () => {
  let now = 1_778_100_000_000;
  const state = new SimulatorState({ nowProvider: () => now });
  const bridge = bridgeFor(state);
  state.setCommittedTaskLibrary([originalTask]);
  state.enterQueueHead();

  bridge._handleMessage({
    type: 'app_task_library',
    payload: { records: [updatedTask] },
  });

  assert.equal(state.taskLibrary[0].title, 'Updated title');
  assert.equal(state.focusTask.title, 'Original title');
  assert.equal(state.focusSupportText(), 'original 0-5');

  state.skipCurrentTask();
  state.enterQueueHead();

  assert.equal(state.focusTask.title, 'Updated title');
  assert.equal(state.focusSupportText(), 'updated 0-5');
});

test('skip exits a deleted active task without restoring it to the queue', () => {
  const state = new SimulatorState();
  state.setCommittedTaskLibrary([originalTask]);
  state.setDisplayMode(DisplayMode.DAILY_SUMMARY);
  state.startFocusTask(originalTask);
  state.setCommittedTaskLibrary([]);

  const event = state.skipCurrentTask();

  assert.deepEqual(event, { type: 'hw_skip_task', taskId: 'alpha' });
  assert.equal(state.displayMode, DisplayMode.DAILY_SUMMARY);
  assert.equal(state.activeFocusTaskId, null);
  assert.deepEqual(state.taskLibrary, []);
});

test('complete exits a deleted active task without restoring it to the queue', () => {
  const state = new SimulatorState();
  state.setCommittedTaskLibrary([originalTask]);
  state.setDisplayMode(DisplayMode.DAILY_SUMMARY);
  state.startFocusTask(originalTask);
  state.setCommittedTaskLibrary([]);

  const event = state.completeCurrentTask();

  assert.deepEqual(event, { type: 'hw_complete_task', taskId: 'alpha' });
  assert.equal(state.displayMode, DisplayMode.DAILY_SUMMARY);
  assert.equal(state.activeFocusTaskId, null);
  assert.deepEqual(state.taskLibrary, []);
});

test('hardware clock keeps advancing focus while the App connection is down', () => {
  let now = 1_778_100_000_000;
  let tick = () => {};
  const elements = new Map();
  const previousDocument = globalThis.document;
  globalThis.document = {
    getElementById(id) {
      if (!elements.has(id)) {
        elements.set(id, { addEventListener() {} });
      }
      return elements.get(id);
    },
  };

  try {
    const state = new SimulatorState({ nowProvider: () => now });
    state.setCommittedTaskLibrary([originalTask]);
    state.enterQueueHead();
    state.setAppConnected(false);
    const controls = new HardwareControls(state, {
      scheduleRepeating(callback) {
        tick = callback;
        return 1;
      },
      cancelRepeating() {},
    });

    now += 6 * 60_000;
    tick();

    assert.equal(state.focusElapsedMinutes, 6);
    assert.equal(state.displayMode, DisplayMode.FOCUS_BUILDING);
    controls.dispose();
  } finally {
    globalThis.document = previousDocument;
  }
});
