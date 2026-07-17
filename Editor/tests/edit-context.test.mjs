import assert from 'node:assert/strict';
import test from 'node:test';
import { selectEditContextBlocks } from '../src/editContextSelection.ts';

function block(index, type = 'paragraph') {
  const from = index * 20 + 1;
  return {
    id: `block-${index}`,
    path: String(index),
    type,
    from,
    to: from + 15,
    text: `Paragraph ${index}`,
    textHash: `hash-${index}`,
  };
}

test('short document block indexes remain unchanged', () => {
  const blocks = Array.from({ length: 12 }, (_, index) => block(index));
  assert.deepEqual(selectEditContextBlocks(blocks, blocks[7].from, 160), blocks);
});

test('long document context keeps the cursor passage and whole-draft orientation', () => {
  const blocks = Array.from(
    { length: 240 },
    (_, index) => block(index, index % 30 === 0 ? 'heading' : 'paragraph')
  );
  const selected = selectEditContextBlocks(blocks, blocks[205].from + 2, 160);
  const ids = new Set(selected.map(({ id }) => id));

  assert.equal(selected.length, 160);
  assert.ok(ids.has('block-205'), 'cursor block was omitted');
  assert.ok(ids.has('block-0'), 'document opening was omitted');
  assert.ok(ids.has('block-239'), 'document ending was omitted');
  assert.ok(ids.has('block-180'), 'nearby structural heading was omitted');
  assert.ok(ids.has('block-121'), 'whole-document checkpoint was omitted');
  assert.deepEqual(
    selected.map(({ from }) => from),
    selected.map(({ from }) => from).toSorted((left, right) => left - right),
    'selected blocks must stay in document order'
  );
});

test('the target remains present even with a tiny context budget', () => {
  const blocks = Array.from({ length: 40 }, (_, index) => block(index));
  const selected = selectEditContextBlocks(blocks, blocks[32].from, 8);
  assert.equal(selected.length, 8);
  assert.ok(selected.some(({ id }) => id === 'block-32'));
});
