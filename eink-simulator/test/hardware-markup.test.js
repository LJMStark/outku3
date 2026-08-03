import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('device markup exposes no up/down wheel controls', async () => {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');

  assert.equal(html.includes('btn-scroll-up'), false);
  assert.equal(html.includes('btn-scroll-down'), false);
  assert.equal(html.includes('btn-scroll'), false);
  assert.equal(html.includes('Scroll Up'), false);
  assert.equal(html.includes('Scroll Down'), false);
});
