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
];

function stateWithTasks() {
  const state = new SimulatorState();
  state.setCommittedTaskLibrary(committedTasks);
  return state;
}

test('overview short press always enters the committed queue head with local phase copy', () => {
  const state = stateWithTasks();

  const message = state.handleShortPress();

  assert.equal(message.type, 'hw_start_task');
  assert.equal(message.taskId, 'alpha');
  assert.equal(state.activeFocusTaskId, 'alpha');
  assert.equal(state.focusTask.overview, 'First task details');
  assert.equal(state.displayMode, DisplayMode.FOCUS_WARMUP);
  assert.equal(state.focusSupportText(), 'Alpha 0-5');

  state.setFocusMinutes(6);
  assert.equal(state.focusSupportText(), 'Alpha 6-15');
  state.setFocusMinutes(16);
  assert.equal(state.focusSupportText(), 'Alpha 16+');
});

test('completing removes the active task, returns to its source, and exposes the next head', () => {
  const state = stateWithTasks();
  state.handleShortPress();

  const message = state.handleShortPress();

  assert.equal(message.type, 'hw_complete_task');
  assert.equal(message.taskId, 'alpha');
  assert.equal(state.displayMode, DisplayMode.IDLE);
  assert.deepEqual(state.taskLibrary.map(task => task.id), ['beta']);

  state.handleShortPress();
  assert.equal(state.activeFocusTaskId, 'beta');
});

test('skipping keeps the task unfinished, gives no reward, and moves it to the queue tail', () => {
  const state = stateWithTasks();
  state.update({ energyBottles: 4 });
  state.handleShortPress();

  const message = state.handleLongPress();

  assert.equal(message.type, 'hw_skip_task');
  assert.equal(message.taskId, 'alpha');
  assert.equal(state.displayMode, DisplayMode.IDLE);
  assert.equal(state.energyBottles, 4);
  assert.deepEqual(state.taskLibrary.map(task => task.id), ['beta', 'alpha']);
  assert.equal(state.taskLibrary[1].completed, undefined);
});

test('focus completion restores the page that preceded an externally started focus', () => {
  const state = stateWithTasks();
  state.enterDailySummary();
  state.applyFocusState({
    activeFocusTaskId: 'alpha',
    focusPhase: 'warmup',
    elapsedMinutes: 0,
  });

  state.completeCurrentTask();

  assert.equal(state.displayMode, DisplayMode.DAILY_SUMMARY);
});

test('long pressing daily summary returns to the page that opened it', () => {
  const state = stateWithTasks();

  assert.deepEqual(state.handleLongPress(), { type: 'hw_enter_daily_summary' });
  assert.equal(state.displayMode, DisplayMode.DAILY_SUMMARY);
  assert.deepEqual(state.handleLongPress(), { type: 'hw_exit_daily_summary' });
  assert.equal(state.displayMode, DisplayMode.IDLE);
});

test('screensaver exit restores either summary or an active focus page', () => {
  const summaryState = stateWithTasks();
  summaryState.enterDailySummary();
  summaryState.toggleScreensaver();
  summaryState.toggleScreensaver();
  assert.equal(summaryState.displayMode, DisplayMode.DAILY_SUMMARY);

  const focusState = stateWithTasks();
  focusState.handleShortPress();
  focusState.toggleScreensaver();
  focusState.toggleScreensaver();
  assert.equal(focusState.displayMode, DisplayMode.FOCUS_WARMUP);
  assert.equal(focusState.activeFocusTaskId, 'alpha');
});

test('focus updates stay behind the screensaver and update the page restored on exit', () => {
  const activeState = stateWithTasks();
  activeState.handleShortPress();
  activeState.toggleScreensaver();
  const screensaverMode = activeState.displayMode;
  activeState.applyFocusState({
    activeFocusTaskId: 'alpha',
    focusPhase: 'building',
    elapsedMinutes: 8,
  });
  assert.equal(activeState.displayMode, screensaverMode);
  activeState.toggleScreensaver();
  assert.equal(activeState.displayMode, DisplayMode.FOCUS_BUILDING);

  const endedState = stateWithTasks();
  endedState.handleShortPress();
  endedState.toggleScreensaver();
  endedState.applyFocusState({ activeFocusTaskId: null, focusPhase: 'idle', elapsedMinutes: 0 });
  assert.equal(endedState.displayMode.startsWith('screensaver'), true);
  endedState.toggleScreensaver();
  assert.equal(endedState.displayMode, DisplayMode.IDLE);
});

test('an idle App focus update does not force a non-focus page back to overview', () => {
  const state = stateWithTasks();
  state.enterDailySummary();

  state.applyFocusState({ activeFocusTaskId: null, focusPhase: 'idle', elapsedMinutes: 0 });

  assert.equal(state.displayMode, DisplayMode.DAILY_SUMMARY);
});

test('focus end applies earned bottles immediately without an animation step', () => {
  const state = stateWithTasks();
  state.handleShortPress();
  const bridge = Object.create(WebSocketBridge.prototype);
  bridge.state = state;

  const result = bridge._handleFocusEnd({ bottlesEarned: 2 });

  assert.equal(result, undefined);
  assert.equal(state.displayMode, DisplayMode.IDLE);
  assert.equal(state.energyBottles, 2);
});
