import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const editorRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const projectRoot = resolve(editorRoot, '..');
const readProjectFile = (path) => readFileSync(resolve(projectRoot, path), 'utf8');

const modelService = readProjectFile(
  'Sources/WordProcessor/Services/LanguageModelService.swift'
);
const editorViewModel = readProjectFile(
  'Sources/WordProcessor/ViewModels/EditorViewModel.swift'
);
const chatViewModel = readProjectFile(
  'Sources/WordProcessor/ViewModels/AssistantChatViewModel.swift'
);
const styleUpdater = readProjectFile(
  'Sources/WordProcessor/Services/StyleGuideUpdater.swift'
);

test('every model service uses sticky prompt-cache routing and cacheable instructions', () => {
  assert.match(modelService, /promptCacheSessionID/);
  assert.match(modelService, /body\["session_id"\]/);
  assert.match(modelService, /cacheablePromptContent\(from: systemPrompt\)/);
  assert.match(modelService, /markRecentUserPrefixesCacheable/);
  assert.match(modelService, /remainingBreakpoints = 2/);
  assert.match(modelService, /cache_control/);
  assert.match(modelService, /openRouterPromptCacheUsage/);

  const callSites = [editorViewModel, chatViewModel, styleUpdater].join('\n');
  const requests = Array.from(callSites.matchAll(/\.streamMessage\(/g));
  assert.equal(requests.length, 6);
  for (const request of requests) {
    const requestBody = callSites.slice(request.index, request.index + 800);
    assert.match(
      requestBody,
      /systemPrompt:/,
      'every model request must supply a system prompt for a reusable cache prefix'
    );
  }
});

test('style-aware requests separate profile prefixes from live prose', () => {
  assert.equal(
    Array.from(editorViewModel.matchAll(/stylePacket\.cacheablePrefixText/g)).length,
    2,
    'gap fills and ambient review should cache their style packet prefix'
  );
  assert.match(chatViewModel, /stylePacket\.cacheablePrefixText/);
  assert.match(chatViewModel, /stylePacket\.taskRelevantText/);
  assert.match(styleUpdater, /cacheableTextBlock\("""[\s\S]*?<current_learned_preferences>/);

  assert.match(editorViewModel, /"text": gapFillPrompt\(/);
  assert.match(editorViewModel, /"text": ambientReviewPrompt\(/);
  assert.match(chatViewModel, /<selected_passage>/);
});
