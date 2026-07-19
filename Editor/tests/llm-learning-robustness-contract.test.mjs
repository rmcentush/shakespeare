import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const editorRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const projectRoot = resolve(editorRoot, '..');
const readProjectFile = (path) => readFileSync(resolve(projectRoot, path), 'utf8');

const editorViewModel = readProjectFile(
  'Sources/WordProcessor/ViewModels/EditorViewModel.swift'
);
const eventStore = readProjectFile(
  'Sources/WordProcessor/Services/TrainingEventStore.swift'
);
const pendingEdits = readProjectFile('Editor/src/pendingEdits.ts');

test('superseded model tasks cannot clear newer request handles', () => {
  assert.match(editorViewModel, /grammarCheckGeneration == generation/);
  assert.match(editorViewModel, /gapFillTaskIDs\[request\.requestID\] == taskID/);
  assert.match(editorViewModel, /ambientReviewGeneration == generation/);
  assert.match(editorViewModel, /try Task\.checkCancellation\(\)/);
});

test('dismissed editorial feedback is stored as an idempotent resolved rejection', () => {
  assert.match(eventStore, /let actionID = "\\\(comment\.id\)_rejected"/);
  assert.match(eventStore, /eventType: "edit_outcome"/);
  assert.match(eventStore, /outcome: "rejected_unchanged"/);
  assert.match(eventStore, /trainingEligible: false/);
  assert.match(eventStore, /cachedEventIDs\?\.contains\(outcome\.id\)/);
});

test('reject-all emits learning decisions only after the editor accepts the action', () => {
  const start = pendingEdits.indexOf('export function rejectAllPendingEdits');
  const end = pendingEdits.indexOf('export const PendingEditHighlight', start);
  const implementation = pendingEdits.slice(start, end);
  const dispatchIndex = implementation.indexOf("dispatchPendingEditAction(ed, { type: 'rejectAll' })");
  const emitIndex = implementation.indexOf("sendToSwift('editDecision', payload)");

  assert.ok(dispatchIndex >= 0, 'reject-all dispatch is missing');
  assert.ok(emitIndex > dispatchIndex, 'learning decisions were emitted before dispatch succeeded');
  assert.match(implementation, /if \(result\) \{[\s\S]*sendToSwift\('editDecision', payload\)/);
});
