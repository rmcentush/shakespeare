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
const personalizedContext = readProjectFile(
  'Sources/WordProcessor/Services/PersonalizedWritingContext.swift'
);
const styleAssembler = readProjectFile(
  'Sources/WordProcessor/Services/StyleContextAssembler.swift'
);
const ambientContract = readProjectFile(
  'Sources/WordProcessor/Services/AmbientReviewContract.swift'
);
const gapContract = readProjectFile(
  'Sources/WordProcessor/Services/GapFillContract.swift'
);
const selectionContract = readProjectFile(
  'Sources/WordProcessor/Services/SelectionFeedbackContract.swift'
);
const grammarContract = readProjectFile(
  'Sources/WordProcessor/Services/GrammarCheckContract.swift'
);
const researchContract = readProjectFile(
  'Sources/WordProcessor/Services/ResearchAssistantContract.swift'
);
const inferenceSettings = readProjectFile(
  'Sources/WordProcessor/Services/InferenceSettings.swift'
);
const stringEscaping = readProjectFile(
  'Sources/WordProcessor/Services/StringEscaping.swift'
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
  assert.match(styleAssembler, /<writing_option_guidance>/);
  assert.match(styleAssembler, /queryTerms: taskTerms/);
  assert.match(personalizedContext, /generalGuidance \?\? defaultGeneralGuidance/);
});

test('every personalized writing option has a dedicated prompt, style task, and cache session', () => {
  assert.match(ambientContract, /static let styleTask/);
  assert.match(ambientContract, /static let systemPrompt/);
  assert.match(gapContract, /static let styleTask/);
  assert.match(gapContract, /static let systemPrompt/);
  assert.match(selectionContract, /static let styleTask/);
  assert.match(selectionContract, /static let systemPrompt/);
  assert.match(researchContract, /static let systemPrompt/);
  assert.match(researchContract, /Distinguish clearly among what the draft claims/);

  assert.match(
    editorViewModel,
    /ambientReviewService = LanguageModelService\([\s\S]*?purpose: \.ambientReview[\s\S]*?\)/
  );
  assert.match(editorViewModel, /gapFillService = LanguageModelService\(purpose: \.gapFill\)/);
  assert.match(editorViewModel, /gapFillService\.streamMessage\(/);
  assert.match(
    chatViewModel,
    /selectionFeedbackService = LanguageModelService\([\s\S]*?purpose: \.selectionFeedback[\s\S]*?\)/
  );
  assert.match(chatViewModel, /ResearchAssistantContract\.systemPrompt/);
  assert.match(styleUpdater, /LanguageModelService\(purpose: \.styleProfile\)/);
  assert.match(inferenceSettings, /case selectionFeedback = "selection-feedback"/);
  assert.match(inferenceSettings, /case gapFill = "gap-fill"/);
  assert.match(inferenceSettings, /case ambientReview = "ambient-review"/);
  assert.match(inferenceSettings, /case styleProfile = "style-profile"/);
  assert.match(
    editorViewModel,
    /ambientReviewService\.streamMessage\([\s\S]*?webSearchEnabled: false/
  );

  assert.match(grammarContract, /case continuous/);
  assert.match(grammarContract, /case thorough/);
  assert.match(grammarContract, /automatic grammar checking after a writing pause/);
  assert.match(grammarContract, /writer-invoked thorough proofread/);
  assert.match(editorViewModel, /grammarService = LanguageModelService\(purpose: \.grammar\)/);
  assert.match(editorViewModel, /thoroughGrammarService = LanguageModelService\(purpose: \.proofread\)/);
});

test('untrusted prompt data cannot forge framework-owned tags', () => {
  assert.match(stringEscaping, /var promptTagEscaped: String/);
  assert.match(chatViewModel, /preparedDocument\.promptTagEscaped/);
  assert.match(chatViewModel, /selection\.htmlEscaped/);
  assert.match(styleUpdater, /currentPreferences\.prefix\(4_000\)\)\.promptTagEscaped/);
  assert.match(styleUpdater, /evidence\.samplesJSON\.promptTagEscaped/);
  assert.match(styleUpdater, /evidence\.editsJSON\.promptTagEscaped/);
});

test('machine-consumed outputs use strict, described, bounded schemas', () => {
  for (const contract of [ambientContract, gapContract, grammarContract]) {
    assert.match(contract, /"description":/);
    assert.match(contract, /"additionalProperties": false/);
  }
  assert.match(grammarContract, /detectorOutputSchema\(mode:/);
  assert.match(grammarContract, /verifierOutputSchema\(candidateCount:/);
  assert.match(editorViewModel, /Set\(decisionIDs\) == candidateIDs/);
  assert.match(modelService, /"strict": true/);
  assert.match(modelService, /provider\["require_parameters"\] = true/);
});
