import assert from 'node:assert/strict';
import test from 'node:test';
import { classifyPersonalizationOutcome } from '../src/personalizationOutcome.ts';

test('unchanged model prose is never eligible to teach the writer profile', () => {
  assert.deepEqual(
    classifyPersonalizationOutcome('accept', 'Original', 'Model suggestion', 'Model suggestion'),
    {
      outcome: 'accepted_unchanged',
      finalText: 'Model suggestion',
      confidence: 1,
      trainingEligible: false,
    }
  );
});

test('format-only whitespace changes do not become writer evidence', () => {
  assert.equal(
    classifyPersonalizationOutcome(
      'accept',
      'Original',
      'A model\u00a0suggestion with spacing.',
      '  A model suggestion\nwith spacing.  '
    ).trainingEligible,
    false
  );
});

test('active writer modifications remain eligible evidence', () => {
  const accepted = classifyPersonalizationOutcome(
    'accept',
    'Original',
    'Model suggestion',
    'Writer-modified result'
  );
  const rejected = classifyPersonalizationOutcome(
    'reject',
    'Original',
    'Model suggestion',
    'Writer replacement'
  );
  assert.equal(accepted.outcome, 'accepted_modified');
  assert.equal(accepted.trainingEligible, true);
  assert.equal(rejected.outcome, 'rejected_rewritten');
  assert.equal(rejected.trainingEligible, true);
});

test('reverts and unchanged rejections do not become positive evidence', () => {
  assert.equal(
    classifyPersonalizationOutcome('accept', 'Original', 'Model suggestion', 'Original')
      .trainingEligible,
    false
  );
  assert.equal(
    classifyPersonalizationOutcome('reject', 'Original', 'Model suggestion', 'Original')
      .trainingEligible,
    false
  );
});
