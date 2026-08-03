import assert from 'node:assert/strict';
import test from 'node:test';

import { ScreenRenderer } from '../src/screen-renderer.js';
import { SimulatorState } from '../src/state.js';

const committedTasks = [
  { taskID: 'alpha', title: 'Alpha' },
  { taskID: 'beta', title: 'Beta' },
];

function rendererWithCommittedTasks() {
  const state = new SimulatorState();
  const screen = { innerHTML: '' };
  state.setCommittedTaskLibrary(committedTasks);
  return { renderer: new ScreenRenderer(screen, state), screen, state };
}

function taskTitles(screen) {
  return [...screen.innerHTML.matchAll(/<li[^>]*>([^<]*)<\/li>/g)]
    .map(match => match[1]);
}

test('overview renders the committed local task queue through complete and skip actions', () => {
  const { renderer, screen, state } = rendererWithCommittedTasks();

  renderer.renderIdleScreen();
  assert.deepEqual(taskTitles(screen), ['Alpha', 'Beta']);

  state.handleShortPress();
  state.handleShortPress();
  renderer.renderIdleScreen();
  assert.deepEqual(taskTitles(screen), ['Beta']);

  state.handleShortPress();
  state.handleLongPress();
  renderer.renderIdleScreen();
  assert.deepEqual(taskTitles(screen), ['Beta']);

  // Offline actions leave an outbox; library waits for explicit App ACKs, not flush alone.
  state.flushPendingTaskActions();
  assert.equal(state.setCommittedTaskLibrary(committedTasks), false);
  for (const entry of state.outboxTaskActions()) {
    state.applyTaskActionAck({
      action: entry.action,
      operationId: entry.operationId,
      result: 'applied',
    });
  }
  assert.equal(state.setCommittedTaskLibrary(committedTasks), true);
  state.handleShortPress();
  state.handleLongPress();
  renderer.renderIdleScreen();
  assert.deepEqual(taskTitles(screen), ['Beta', 'Alpha']);
});

test('overview escapes committed task titles before inserting them into HTML', () => {
  const state = new SimulatorState();
  const screen = { innerHTML: '' };
  const renderer = new ScreenRenderer(screen, state);
  state.setCommittedTaskLibrary([
    { taskID: 'unsafe', title: '<img src=x onerror="globalThis.taskInjected=true">' },
  ]);

  renderer.renderIdleScreen();

  assert.equal(screen.innerHTML.includes('<img'), false);
  assert.match(
    screen.innerHTML,
    /&lt;img src=x onerror=&quot;globalThis\.taskInjected=true&quot;&gt;/
  );
});

test('daily summary escapes review and quote before inserting them into HTML', () => {
  const state = new SimulatorState();
  const screen = { innerHTML: '' };
  const renderer = new ScreenRenderer(screen, state);
  state.update({
    settlementReview: '<img src=x onerror="globalThis.reviewInjected=true"> & steady',
    settlementQuote: '<script>globalThis.quoteInjected=true</script>',
  });

  renderer.renderDailySummary();

  assert.equal(screen.innerHTML.includes('<img'), false);
  assert.equal(screen.innerHTML.includes('<script>'), false);
  assert.match(
    screen.innerHTML,
    /&lt;img src=x onerror=&quot;globalThis\.reviewInjected=true&quot;&gt; &amp; steady/
  );
  assert.match(
    screen.innerHTML,
    /&lt;script&gt;globalThis\.quoteInjected=true&lt;\/script&gt;/
  );
});
