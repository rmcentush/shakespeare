import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const editorRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const projectRoot = resolve(editorRoot, '..');
const readProjectFile = (path) => readFileSync(resolve(projectRoot, path), 'utf8');

const feedbackExtension = readFileSync(
  resolve(editorRoot, 'src/selectionFeedback.ts'),
  'utf8'
);
const gapSuggestions = readFileSync(
  resolve(editorRoot, 'src/gapSuggestions.ts'),
  'utf8'
);
const theme = readFileSync(resolve(editorRoot, 'src/theme.css'), 'utf8');
const contentView = readProjectFile('Sources/WordProcessor/Views/ContentView.swift');
const chatViewModel = readProjectFile(
  'Sources/WordProcessor/ViewModels/AssistantChatViewModel.swift'
);
const editorViewModel = readProjectFile(
  'Sources/WordProcessor/ViewModels/EditorViewModel.swift'
);
const personalizedContext = readProjectFile(
  'Sources/WordProcessor/Services/PersonalizedWritingContext.swift'
);

test('places an accessible feedback control beside selected editor text', () => {
  assert.match(feedbackExtension, /Decoration\.widget\(to, selectionFeedbackWidget/);
  assert.match(feedbackExtension, /aria-label', 'Ask for feedback on selected text'/);
  assert.match(feedbackExtension, /sendToSwift\('selectionFeedbackRequested'\)/);
  assert.match(theme, /\.selection-feedback-anchor\s*\{[\s\S]*?width: 0;[\s\S]*?height: 0;/);
  assert.match(theme, /\.selection-feedback-action\s*\{[\s\S]*?position: absolute;/);
  assert.match(contentView, /for: \.selectionFeedbackRequested,[\s\S]*?requestSelectionFeedback\(\)/);
  assert.doesNotMatch(contentView, /Label\("Feedback"/);
});

test('shows only one sparkle when selection and writing-gap actions overlap', () => {
  assert.match(feedbackExtension, /if \(selectionIsWithinWritingGap\(state\)\) return DecorationSet\.empty/);
  assert.match(
    gapSuggestions,
    /const active = selectionFrom >= gap\.from && selectionTo <= gap\.to/
  );
  assert.doesNotMatch(
    gapSuggestions,
    /selectionFrom <= gap\.to && selectionTo >= gap\.from/
  );
});

test('routes selection feedback through the writing model without web search', () => {
  assert.match(chatViewModel, /writingService = LanguageModelService\(purpose: \.assistant\)/);
  assert.match(chatViewModel, /researchService = LanguageModelService\(purpose: \.chat\)/);
  assert.match(chatViewModel, /sendSelectionFeedback[\s\S]*?allowsWebSearch: false,[\s\S]*?route: \.writingFeedback/);
  assert.match(chatViewModel, /route == \.writingFeedback \? writingService : researchService/);
  assert.match(chatViewModel, /if route == \.research \{[\s\S]*?apiMessages = requestMessages/);
});

test('all subjective writing assistance shares the live reviewed style context', () => {
  assert.match(personalizedContext, /AuthorStyleReference\.content/);
  assert.match(personalizedContext, /AuthorStyleReference\.learnedPreferences/);
  assert.match(personalizedContext, /TrainingEventStore\.shared\.writingSamples\(\)/);
  assert.match(personalizedContext, /TrainingEventStore\.shared\.confirmedStyleExamples\(\)/);
  assert.match(chatViewModel, /PersonalizedWritingContext\.assemble\(/);
  assert.equal(
    Array.from(editorViewModel.matchAll(/PersonalizedWritingContext\.assemble\(/g)).length,
    2,
    'gap fills and ambient suggestions should both use the shared style context'
  );
  assert.doesNotMatch(editorViewModel, /StyleContextAssembler\.assemble\(/);
});
