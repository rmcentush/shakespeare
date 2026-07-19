import assert from 'node:assert/strict';
import test from 'node:test';
import { findWritingGaps } from '../src/writingGaps.ts';

test('finds concise writing-gap instructions and empty gaps', () => {
  assert.deepEqual(findWritingGaps('Before [[ add a concrete example ]] after [[]].'), [
    { index: 7, raw: '[[ add a concrete example ]]', instruction: 'add a concrete example' },
    { index: 42, raw: '[[]]', instruction: '' },
  ]);
});

test('keeps escaped and single brackets as ordinary prose', () => {
  assert.deepEqual(findWritingGaps(String.raw`Keep \[[literal]] and [a note]. Fill [[this]].`), [
    { index: 37, raw: '[[this]]', instruction: 'this' },
  ]);
});

test('does not allow a gap to cross a paragraph or grow without a bound', () => {
  assert.deepEqual(findWritingGaps('[[first\nsecond]]'), []);
  assert.deepEqual(findWritingGaps(`[[${'x'.repeat(301)}]]`), []);
});
