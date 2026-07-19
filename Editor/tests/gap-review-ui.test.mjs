import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const editorRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const projectRoot = resolve(editorRoot, '..');
const gaps = readFileSync(resolve(editorRoot, 'src/gapSuggestions.ts'), 'utf8');
const pendingEdits = readFileSync(resolve(editorRoot, 'src/pendingEdits.ts'), 'utf8');
const theme = readFileSync(resolve(editorRoot, 'src/theme.css'), 'utf8');
const contentView = readFileSync(
  resolve(projectRoot, 'Sources/WordProcessor/Views/ContentView.swift'),
  'utf8'
);

test('shows an accessible animated loader inside the writing-gap brackets', () => {
  assert.match(gaps, /className = 'writing-gap-loading'/);
  assert.match(gaps, /aria-label', 'Writing a suggestion'/);
  assert.match(gaps, /for \(let index = 0; index < 3; index \+= 1\)/);
  assert.match(gaps, /textContent = '\[\['/);
  assert.match(gaps, /textContent = '\]\]'/);
  assert.match(theme, /@keyframes writing-gap-dot/);
  assert.match(theme, /@media \(prefers-reduced-motion: reduce\)/);
});

test('keeps gap approval inline and restores decorations after decisions', () => {
  assert.match(pendingEdits, /usesCompactGapReview \? '✓' : 'Accept'/);
  assert.match(pendingEdits, /usesCompactGapReview \? '×' : 'Reject'/);
  assert.match(pendingEdits, /aria-label', 'Use this text'/);
  assert.match(pendingEdits, /aria-label', 'Leave the gap in place'/);
  assert.match(pendingEdits, /pending-edit-gap-original/);
  assert.match(gaps, /tr\.getMeta\(pendingEditPluginKey\)/);
  assert.doesNotMatch(contentView, /struct PendingEditsBar/);
});
