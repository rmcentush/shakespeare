import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const editorRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const repositoryRoot = resolve(editorRoot, '..');

function methodNames(source, pattern) {
  return new Set(Array.from(source.matchAll(pattern), (match) => match[1]));
}

test('Swift and TypeScript expose one exact editor bridge contract', () => {
  const bridge = readFileSync(resolve(editorRoot, 'src/bridge.ts'), 'utf8');
  const editor = readFileSync(resolve(editorRoot, 'src/editor.ts'), 'utf8');
  const viewModel = readFileSync(
    resolve(repositoryRoot, 'Sources/WordProcessor/ViewModels/EditorViewModel.swift'),
    'utf8'
  );
  const textChecking = readFileSync(
    resolve(repositoryRoot, 'Sources/WordProcessor/Services/TextCheckingSettings.swift'),
    'utf8'
  );

  const interfaceBody = bridge.match(/registerSwiftCallbacks\(callbacks: \{([\s\S]*?)\n\}\): void/);
  const registrationBody = editor.match(/registerSwiftCallbacks\(\{([\s\S]*?)\n\}\);/);
  assert.ok(interfaceBody, 'bridge callback interface was not found');
  assert.ok(registrationBody, 'editor callback registration was not found');

  const declared = methodNames(interfaceBody[1], /^\s{2}([A-Za-z]\w+):/gm);
  const registered = methodNames(registrationBody[1], /^\s{2}([A-Za-z]\w+)\s*(?:\(|:)/gm);
  assert.deepEqual(registered, declared, 'registered methods diverged from the TypeScript contract');

  const swiftCalls = methodNames(viewModel, /callEditorAPI\(\s*"([A-Za-z]\w+)"/g);
  for (const name of methodNames(textChecking, /window\.editorAPI\?\.([A-Za-z]\w+)/g)) {
    swiftCalls.add(name);
  }
  for (const name of methodNames(
    textChecking,
    /"(setSpellcheckEnabled|setAutocorrectEnabled)"/g
  )) {
    swiftCalls.add(name);
  }

  assert.deepEqual(
    registered,
    swiftCalls,
    'the bridge contains an unused callback or Swift calls an unregistered method'
  );
});
