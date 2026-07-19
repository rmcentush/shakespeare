import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const source = fs.readFileSync(new URL('../src/comments.ts', import.meta.url), 'utf8');

test('agent comments map their source revision before insertion', () => {
  assert.match(source, /mapRangeFromRevision\(sourceRevision, from, to\)/);
  assert.match(source, /Number\.isSafeInteger\(sourceRevision\)/);
});

test('agent comments reject stale or out-of-bounds anchor text', () => {
  assert.match(source, /to > editor\.state\.doc\.content\.size/);
  assert.match(source, /currentText !== input\.expectedText/);
});
