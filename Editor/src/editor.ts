import { Editor, Extension, Mark, Node as TiptapNode, mergeAttributes } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import Underline from '@tiptap/extension-underline';
import Placeholder from '@tiptap/extension-placeholder';
import TextAlign from '@tiptap/extension-text-align';
import Typography from '@tiptap/extension-typography';
import FontFamily from '@tiptap/extension-font-family';
import TextStyle from '@tiptap/extension-text-style';
import Image from '@tiptap/extension-image';
import Link from '@tiptap/extension-link';
import Color from '@tiptap/extension-color';
import { Plugin, PluginKey, NodeSelection, TextSelection } from '@tiptap/pm/state';
import { Decoration, DecorationSet, EditorView } from '@tiptap/pm/view';
import { sendToSwift, registerSwiftCallbacks } from './bridge';

// --- Search / Find & Replace ---
interface SearchMatch {
  from: number;
  to: number;
}

interface SearchIndexRange {
  from: number;
  to: number;
}

interface SearchIndex {
  text: string;
  ranges: SearchIndexRange[];
}

interface SearchIndexBuilder {
  text: string;
  ranges: SearchIndexRange[];
  lastWasWhitespace: boolean;
}

interface FootnoteDetails {
  id: string;
  index: number;
  note: string;
  pos: number;
}

interface EditorSelectionState {
  hasSelection: boolean;
  selectedWords: number;
  selectedCharacters: number;
  isBold: boolean;
  isItalic: boolean;
  isUnderline: boolean;
  heading: number;
  textAlign: string;
  isLink: boolean;
  linkHref: string;
  textColor: string;
  isFootnote: boolean;
  footnoteText: string;
  isImage: boolean;
  imageLayout: ImageLayout;
  imageAlign: ImageAlign;
  imageWidth: string;
  imageHeight: string;
}

type ImageLayout = 'inline' | 'block' | 'float-left' | 'float-right';
type ImageAlign = 'left' | 'center' | 'right';
type ImageHandleDirection = 'n' | 'ne' | 'e' | 'se' | 's' | 'sw' | 'w' | 'nw';

interface ImageCropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

interface DocumentTextSnapshot {
  revision: number;
  footnotes: FootnoteDetails[];
  footnotesSignature: string;
  footnotesStructureSignature: string;
  plainText: string;
  words: number;
  characters: number;
}

interface SelectionClipboardData {
  html: string;
  text: string;
  imageSources: string[];
  singleImageSource: string | null;
}

interface FocusedFootnoteEditorState {
  id: string;
  selectionStart: number;
  selectionEnd: number;
  scrollTop: number;
}

interface PreservedTextSelection {
  from: number;
  to: number;
  text: string;
  words: number;
  characters: number;
  revision: number;
}

interface EditContextBlock {
  id: string;
  path: string;
  type: string;
  from: number;
  to: number;
  text: string;
  textHash: string;
}

interface EditContextSelection {
  from: number;
  to: number;
  text: string;
  html: string;
  words: number;
  characters: number;
}

interface EditContextSnapshot {
  revision: number;
  documentHash: string;
  plainText: string;
  cursorPosition: number;
  nearbyText: string;
  selection: EditContextSelection | null;
  blocks: EditContextBlock[];
}

interface ProposedEditTarget {
  block_id?: string;
  exact_original?: string;
  prefix?: string;
  suffix?: string;
  occurrence_index?: number;
  document_revision?: number;
  document_hash?: string;
}

interface SelectionEditTarget {
  from?: number;
  to?: number;
  text?: string;
  position?: number;
  document_revision?: number;
  document_hash?: string;
}

let searchResults: SearchMatch[] = [];
let currentMatchIdx = -1;
let activeSearchQuery = '';
const MAX_SEARCH_RESULTS = 500;
const MAX_PENDING_EDITS = 120;
const MAX_PENDING_FIND_REPLACE_MATCHES = 60;
const MAX_EDIT_CONTEXT_BLOCKS = 160;
const MAX_EDIT_CONTEXT_BLOCK_TEXT = 900;
const NEARBY_EDIT_CONTEXT_CHARS = 900;
const TOO_MANY_MATCHES = -1;
const TOO_MANY_PENDING_EDITS = -2;
const AMBIGUOUS_EDIT_TARGET = -3;
const STALE_EDIT_TARGET = -4;
const INVALID_EDIT_TARGET = -5;
const ACCEPTED_LLM_EDIT_COLOR = '#188038';
const FOOTNOTE_NODE_NAME = 'footnote';
const GENERATED_FOOTNOTES_SELECTOR = 'section[data-generated-footnotes="true"]';
const WORD_COUNT_DEBOUNCE_MS = 250;
const CONTENT_SYNC_DEBOUNCE_MS = 1000;
const FOOTNOTE_PANEL_DEBOUNCE_MS = 180;
const SELECTION_SYNC_DEBOUNCE_MS = 80;

const searchPluginKey = new PluginKey('searchHighlight');
const smartQuotesPluginKey = new PluginKey('smartQuotes');
const SMART_QUOTES_TRANSACTION_META = 'smartQuotesNormalized';

// --- Pending Edits (Cursor-like diff review) ---
type PendingEditKind = 'selection' | 'insert' | 'findReplace' | 'delete';
type PendingEditStatus = 'pending' | 'conflicted';

interface PendingEdit {
  id: string;
  groupId: string;
  kind: PendingEditKind;
  source: string;
  label: string;
  from: number;
  to: number;
  newHtml: string;
  originalText: string;
  replacementText: string;
  createdAt: number;
  status: PendingEditStatus;
  conflictReason: string | null;
}

interface PendingEditsPluginState {
  edits: PendingEdit[];
  activeEditId: string | null;
  decorations: DecorationSet;
  version: number;
  scrollToEditId: string | null;
}

type PendingEditAction =
  | {
    type: 'queue';
    edits: PendingEdit[];
    activeEditId: string | null;
    scrollToEditId: string | null;
  }
  | { type: 'focus'; id: string }
  | { type: 'accept'; id: string }
  | { type: 'acceptMany'; ids: string[] }
  | { type: 'reject'; id: string }
  | { type: 'conflict'; id: string; reason: string }
  | { type: 'acceptAll' }
  | { type: 'rejectAll' };

const pendingEditPluginKey = new PluginKey<PendingEditsPluginState>('pendingEdits');

function scrollToPendingEdit(view: EditorView, edit: PendingEdit) {
  try {
    const domAtPos = view.domAtPos(edit.from);
    const node = domAtPos.node as HTMLElement;
    const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
    el?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  } catch (_) {}
}

function notifyPendingEditState(state: PendingEditsPluginState) {
  sendToSwift('pendingEditUpdate', {
    count: state.edits.length,
    currentIndex: currentPendingEditIndex(state),
    activeEditId: state.activeEditId,
    edits: state.edits.map((edit, index) => serializePendingEdit(edit, index, state.activeEditId)),
  });
}

function plainTextFromHTML(html: string): string {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  return (parsed.body.textContent || '').replace(/\u00a0/g, ' ').trim();
}

function inferPendingEditSource(id: string): string {
  if (id.startsWith('edit_')) return 'Claude';
  return 'Suggestion';
}

function buildPendingEditLabel(source: string, kind: PendingEditKind): string {
  switch (kind) {
    case 'selection':
      return `${source} selected edit`;
    case 'insert':
      return `${source} insertion`;
    case 'findReplace':
      return `${source} suggestion`;
    case 'delete':
      return `${source} cut`;
  }
}

function createPendingEdit(
  ed: Editor,
  options: {
    id: string;
    groupId: string;
    kind: PendingEditKind;
    from: number;
    to: number;
    newHtml: string;
  }
): PendingEdit {
  const source = inferPendingEditSource(options.groupId);
  const newHtml = options.kind === 'insert'
    ? smartifyHTMLFragment(options.newHtml, contextCharacterBefore(ed.state.doc, options.from))
    : prepareReplacementHTMLForRange(
      ed,
      options.from,
      options.to,
      options.newHtml
    );
  const kind: PendingEditKind = options.kind !== 'insert' && newHtml.trim().length === 0
    ? 'delete'
    : options.kind;
  return {
    id: options.id,
    groupId: options.groupId,
    kind,
    source,
    label: buildPendingEditLabel(source, kind),
    from: options.from,
    to: options.to,
    newHtml,
    originalText: ed.state.doc.textBetween(options.from, options.to, '\n', '\n'),
    replacementText: plainTextFromHTML(newHtml),
    createdAt: Date.now(),
    status: 'pending',
    conflictReason: null,
  };
}

function serializePendingEdit(
  edit: PendingEdit,
  index: number,
  activeEditId: string | null
) {
  return {
    id: edit.id,
    groupId: edit.groupId,
    kind: edit.kind,
    source: edit.source,
    label: edit.label,
    from: edit.from,
    to: edit.to,
    originalText: edit.originalText,
    replacementText: edit.replacementText,
    createdAt: edit.createdAt,
    status: edit.status,
    conflictReason: edit.conflictReason,
    index,
    isActive: edit.id === activeEditId,
    canAccept: edit.status === 'pending',
    canReject: true,
    canFocus: true,
  };
}

function createPendingEditWidget(edit: PendingEdit, isActive: boolean): HTMLElement {
  const container = document.createElement('span');
  container.className = [
    'pending-edit-widget',
    isActive ? 'pending-edit-active' : '',
    edit.status === 'conflicted' ? 'pending-edit-conflicted' : '',
  ].filter(Boolean).join(' ');
  container.contentEditable = 'false';

  const previewButton = document.createElement('button');
  previewButton.type = 'button';
  previewButton.className = 'pending-edit-preview';
  previewButton.title = edit.status === 'conflicted'
    ? 'Jump to conflicted suggestion'
    : 'Jump to suggestion';
  previewButton.addEventListener('mousedown', (event) => {
    event.preventDefault();
    event.stopPropagation();
  });
  previewButton.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopPropagation();
    focusPendingEdit(editor, edit.id);
  });

  const previewContent = document.createElement('span');
  previewContent.className = 'pending-edit-preview-content';
  if (edit.status === 'conflicted') {
    previewContent.textContent = 'Conflict';
  } else if (edit.newHtml.trim().length > 0) {
    previewContent.innerHTML = edit.newHtml;
  } else {
    previewContent.textContent = 'Delete';
    previewContent.classList.add('pending-edit-placeholder');
  }
  previewButton.appendChild(previewContent);
  container.appendChild(previewButton);

  const actions = document.createElement('span');
  actions.className = 'pending-edit-actions';

  if (edit.status === 'pending') {
    const acceptButton = document.createElement('button');
    acceptButton.type = 'button';
    acceptButton.className = 'pending-edit-action pending-edit-action-accept';
    acceptButton.textContent = 'Accept';
    acceptButton.title = 'Accept suggestion';
    acceptButton.addEventListener('mousedown', (event) => {
      event.preventDefault();
      event.stopPropagation();
    });
    acceptButton.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      acceptPendingEdit(editor, edit.id);
    });
    actions.appendChild(acceptButton);
  }

  const rejectButton = document.createElement('button');
  rejectButton.type = 'button';
  rejectButton.className = 'pending-edit-action pending-edit-action-reject';
  rejectButton.textContent = edit.status === 'conflicted' ? 'Dismiss' : 'Reject';
  rejectButton.title = edit.status === 'conflicted'
    ? 'Dismiss conflicted suggestion'
    : 'Reject suggestion';
  rejectButton.addEventListener('mousedown', (event) => {
    event.preventDefault();
    event.stopPropagation();
  });
  rejectButton.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopPropagation();
    rejectPendingEdit(editor, edit.id);
  });
  actions.appendChild(rejectButton);

  container.appendChild(actions);
  return container;
}

function buildPendingEditDecorations(
  doc: any,
  edits: PendingEdit[],
  activeEditId: string | null
): DecorationSet {
  if (edits.length === 0) return DecorationSet.empty;

  const decorations: Decoration[] = [];
  edits.forEach((edit) => {
    const isActive = edit.id === activeEditId;
    if (edit.from < edit.to) {
      const deleteClass = edit.status === 'conflicted'
        ? (isActive ? 'pending-edit-conflict pending-edit-active' : 'pending-edit-conflict')
        : (isActive ? 'pending-edit-delete pending-edit-active' : 'pending-edit-delete');
      decorations.push(
        Decoration.inline(edit.from, edit.to, {
          class: deleteClass,
        })
      );
    }

    decorations.push(
      Decoration.widget(edit.to, () => createPendingEditWidget(edit, isActive), {
        side: 1,
        ignoreSelection: true,
        stopEvent: (event) => (
          event.target instanceof Element &&
          event.target.closest('.pending-edit-widget') !== null
        ),
      })
    );
  });

  return DecorationSet.create(doc, decorations);
}

function resolveActivePendingEditId(
  edits: PendingEdit[],
  preferredId: string | null,
  fallbackIndex = 0
): string | null {
  if (edits.length === 0) return null;
  if (preferredId && edits.some((edit) => edit.id === preferredId)) return preferredId;
  const safeIndex = Math.min(Math.max(fallbackIndex, 0), edits.length - 1);
  return edits[safeIndex].id;
}

function createPendingEditsState(
  doc: any,
  edits: PendingEdit[] = [],
  activeEditId: string | null = null,
  version = 0,
  scrollToEditId: string | null = null
): PendingEditsPluginState {
  const normalizedActiveEditId = resolveActivePendingEditId(edits, activeEditId);

  return {
    edits,
    activeEditId: normalizedActiveEditId,
    decorations: buildPendingEditDecorations(doc, edits, normalizedActiveEditId),
    version,
    scrollToEditId,
  };
}

function getPendingEditsState(state: any): PendingEditsPluginState {
  return pendingEditPluginKey.getState(state) ?? createPendingEditsState(state.doc);
}

function getPendingEditById(
  state: PendingEditsPluginState,
  id: string | null
): PendingEdit | null {
  if (!id) return null;
  return state.edits.find((edit) => edit.id === id) ?? null;
}

function getActivePendingEdit(state: PendingEditsPluginState): PendingEdit | null {
  return getPendingEditById(state, state.activeEditId);
}

function currentPendingEditIndex(state: PendingEditsPluginState): number {
  if (!state.activeEditId) return state.edits.length > 0 ? 0 : -1;
  return state.edits.findIndex((edit) => edit.id === state.activeEditId);
}

function canQueuePendingEdits(state: PendingEditsPluginState, count: number): boolean {
  return state.edits.length + count <= MAX_PENDING_EDITS;
}

function rebasePendingEdits(edits: PendingEdit[], tr: any): PendingEdit[] {
  if (!tr.docChanged || edits.length === 0) return edits;

  let didChange = false;
  const nextEdits: PendingEdit[] = [];

  edits.forEach((edit) => {
    if (edit.from === edit.to) {
      const mapped = tr.mapping.mapResult(edit.from, 1);
      if (mapped.pos !== edit.from) {
        didChange = true;
      }

      nextEdits.push({
        ...edit,
        from: mapped.pos,
        to: mapped.pos,
        status: mapped.deleted ? 'conflicted' : edit.status,
        conflictReason: mapped.deleted
          ? 'The document changed around this insertion.'
          : edit.conflictReason,
      });
      return;
    }

    const mappedFrom = tr.mapping.map(edit.from, 1);
    const mappedTo = tr.mapping.map(edit.to, -1);

    if (edit.status === 'conflicted') {
      didChange = true;
      nextEdits.push({
        ...edit,
        from: mappedFrom,
        to: Math.max(mappedFrom, mappedTo),
      });
      return;
    }

    const mappedText = tr.doc.textBetween(mappedFrom, Math.max(mappedFrom, mappedTo), '\n', '\n');
    if (mappedFrom >= mappedTo || mappedText !== edit.originalText) {
      didChange = true;
      nextEdits.push({
        ...edit,
        from: mappedFrom,
        to: Math.max(mappedFrom, mappedTo),
        status: 'conflicted',
        conflictReason: 'The document changed around this suggestion.',
      });
      return;
    }

    if (mappedFrom !== edit.from || mappedTo !== edit.to) {
      didChange = true;
    }

    nextEdits.push({
      ...edit,
      from: mappedFrom,
      to: mappedTo,
      conflictReason: null,
    });
  });

  return didChange ? nextEdits : edits;
}

function dispatchPendingEditAction(ed: Editor, action: PendingEditAction): boolean {
  const tr = ed.state.tr.setMeta(pendingEditPluginKey, action);
  ed.view.dispatch(tr);
  return true;
}

function markPendingEditConflicted(ed: Editor, id: string, reason: string): boolean {
  return dispatchPendingEditAction(ed, { type: 'conflict', id, reason });
}

function isPendingEditStillApplicable(ed: Editor, edit: PendingEdit): boolean {
  if (edit.status !== 'pending') return false;
  if (edit.from < 0 || edit.to < edit.from || edit.to > ed.state.doc.content.size) return false;
  if (edit.from === edit.to) return true;

  const currentText = ed.state.doc.textBetween(edit.from, edit.to, '\n', '\n');
  return currentText === edit.originalText;
}

function nonOverlappingPendingEdits(edits: PendingEdit[]) {
  const sorted = [...edits].sort((a, b) => a.from - b.from || a.to - b.to || a.id.localeCompare(b.id));
  const accepted: PendingEdit[] = [];
  const conflicted: PendingEdit[] = [];
  const insertionPositions = new Set<number>();
  let protectedUntil = -1;

  for (const edit of sorted) {
    const isInsertion = edit.from === edit.to;
    const overlapsReplacement = edit.from < protectedUntil;
    const duplicateInsertion = isInsertion && insertionPositions.has(edit.from);

    if (overlapsReplacement || duplicateInsertion) {
      conflicted.push(edit);
      continue;
    }

    accepted.push(edit);

    if (isInsertion) {
      insertionPositions.add(edit.from);
    } else {
      protectedUntil = Math.max(protectedUntil, edit.to);
    }
  }

  return { accepted, conflicted };
}

function queuePendingEdits(
  ed: Editor,
  edits: PendingEdit[],
  activeEditId: string | null = edits[0]?.id ?? null
): number {
  if (edits.length === 0) return 0;

  const state = getPendingEditsState(ed.state);
  if (!canQueuePendingEdits(state, edits.length)) return TOO_MANY_PENDING_EDITS;

  dispatchPendingEditAction(ed, {
    type: 'queue',
    edits,
    activeEditId,
    scrollToEditId: activeEditId,
  });
  return edits.length;
}

function currentDocumentHash(ed: Editor): string {
  return hashString(serializeDocumentPlainText(ed));
}

function targetDocumentIsCurrent(ed: Editor, target: SelectionEditTarget | ProposedEditTarget): boolean {
  if (
    typeof target.document_revision === 'number' &&
    target.document_revision !== documentRevision
  ) {
    return false;
  }

  if (
    typeof target.document_hash === 'string' &&
    target.document_hash.length > 0 &&
    target.document_hash !== currentDocumentHash(ed)
  ) {
    return false;
  }

  return true;
}

function rangeFromSelectionTarget(ed: Editor, target: SelectionEditTarget | null): SearchMatch | number | null {
  if (!target) return null;
  if (!targetDocumentIsCurrent(ed, target)) return STALE_EDIT_TARGET;

  const from = typeof target.from === 'number' ? target.from : -1;
  const to = typeof target.to === 'number' ? target.to : -1;
  if (from < 0 || to <= from || to > ed.state.doc.content.size) return INVALID_EDIT_TARGET;

  if (typeof target.text === 'string') {
    const currentText = ed.state.doc.textBetween(from, to, '\n', '\n');
    if (currentText !== target.text) return STALE_EDIT_TARGET;
  }

  return { from, to };
}

function positionFromInsertionTarget(ed: Editor, target: SelectionEditTarget | null): number | null {
  if (!target) return null;
  if (!targetDocumentIsCurrent(ed, target)) return STALE_EDIT_TARGET;

  const position = typeof target.position === 'number'
    ? target.position
    : (typeof target.from === 'number' ? target.from : -1);

  if (position < 0 || position > ed.state.doc.content.size) return INVALID_EDIT_TARGET;
  return position;
}

function findEditContextBlock(ed: Editor, blockId: string): EditContextBlock | null {
  if (!blockId) return null;
  return buildEditBlockIndex(ed.state.doc).find((block) => block.id === blockId) ?? null;
}

function normalizedContextIncludesSuffix(text: string, suffix: string): boolean {
  const normalizedText = normalizeSearchQuery(text);
  const normalizedSuffix = normalizeSearchQuery(suffix);
  return !normalizedSuffix || normalizedText.endsWith(normalizedSuffix);
}

function normalizedContextIncludesPrefix(text: string, prefix: string): boolean {
  const normalizedText = normalizeSearchQuery(text);
  const normalizedPrefix = normalizeSearchQuery(prefix);
  return !normalizedPrefix || normalizedText.startsWith(normalizedPrefix);
}

function matchSatisfiesContext(ed: Editor, match: SearchMatch, target: ProposedEditTarget): boolean {
  const prefix = target.prefix ?? '';
  if (prefix) {
    const before = ed.state.doc.textBetween(Math.max(0, match.from - 1200), match.from, '\n', '\n');
    if (!normalizedContextIncludesSuffix(before, prefix)) return false;
  }

  const suffix = target.suffix ?? '';
  if (suffix) {
    const after = ed.state.doc.textBetween(match.to, Math.min(ed.state.doc.content.size, match.to + 1200), '\n', '\n');
    if (!normalizedContextIncludesPrefix(after, suffix)) return false;
  }

  return true;
}

function resolveProposedEditMatches(
  ed: Editor,
  target: ProposedEditTarget,
  replaceAll: boolean
): SearchMatch[] | number {
  if (!targetDocumentIsCurrent(ed, target)) return STALE_EDIT_TARGET;

  const exactOriginal = target.exact_original ?? '';
  if (!normalizeSearchQuery(exactOriginal)) return INVALID_EDIT_TARGET;

  let scope: SearchMatch | null = null;
  if (target.block_id) {
    const block = findEditContextBlock(ed, target.block_id);
    if (!block) return STALE_EDIT_TARGET;
    scope = { from: block.from, to: block.to };
  }

  const maxMatches = replaceAll ? MAX_PENDING_FIND_REPLACE_MATCHES + 1 : Number.POSITIVE_INFINITY;
  const matches = findTextInDoc(ed.state.doc, exactOriginal, maxMatches, scope)
    .filter((match) => matchSatisfiesContext(ed, match, target));

  if (matches.length === 0) return STALE_EDIT_TARGET;

  if (replaceAll) {
    return matches.length > MAX_PENDING_FIND_REPLACE_MATCHES ? TOO_MANY_MATCHES : matches;
  }

  const occurrenceIndex = target.occurrence_index;
  if (typeof occurrenceIndex === 'number') {
    if (!Number.isInteger(occurrenceIndex) || occurrenceIndex < 0 || occurrenceIndex >= matches.length) {
      return AMBIGUOUS_EDIT_TARGET;
    }
    return [matches[occurrenceIndex]];
  }

  if (matches.length > 1) return AMBIGUOUS_EDIT_TARGET;
  return matches;
}

interface SentenceRange {
  from: number;
  to: number;
  text: string;
}

function trimSentenceRange(text: string, from: number, to: number): SentenceRange | null {
  let start = from;
  let end = to;

  while (start < end && /\s/.test(text[start])) start += 1;
  while (end > start && /\s/.test(text[end - 1])) end -= 1;

  if (start >= end) return null;
  return {
    from: start,
    to: end,
    text: text.slice(start, end),
  };
}

function sentenceRanges(text: string): SentenceRange[] {
  const segmenterConstructor = (Intl as any).Segmenter;
  if (segmenterConstructor) {
    const segmenter = new segmenterConstructor(undefined, { granularity: 'sentence' });
    const ranges: SentenceRange[] = [];
    for (const segment of segmenter.segment(text)) {
      const range = trimSentenceRange(text, segment.index, segment.index + segment.segment.length);
      if (range) ranges.push(range);
    }
    if (ranges.length > 0) return ranges;
  }

  const ranges: SentenceRange[] = [];
  const regex = /[^.!?]+[.!?]+["')\]]*|[^.!?]+$/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(text)) !== null) {
    const range = trimSentenceRange(text, match.index, match.index + match[0].length);
    if (range) ranges.push(range);
  }
  return ranges.length > 0 ? ranges : (text.trim() ? [{ from: 0, to: text.length, text: text.trim() }] : []);
}

function containsMeaningfulFormattingMarkup(html: string): boolean {
  const wrapperMarkupRemoved = html
    .replace(/<\/?p\b[^>]*>/gi, '')
    .replace(/<\/?div\b[^>]*>/gi, '')
    .replace(/<br\s*\/?>/gi, '');

  return /<[^>]+>/.test(wrapperMarkupRemoved);
}

function sentenceSplitPendingEdits(
  ed: Editor,
  groupId: string,
  match: SearchMatch,
  replaceHtml: string
): PendingEdit[] {
  if (containsMeaningfulFormattingMarkup(replaceHtml)) return [];

  const originalText = ed.state.doc.textBetween(match.from, match.to, '\n', '\n');
  const replacementText = plainTextFromHTML(replaceHtml);
  const originalSentences = sentenceRanges(originalText);
  const replacementSentences = sentenceRanges(replacementText);

  if (originalSentences.length <= 1 || originalSentences.length !== replacementSentences.length) {
    return [];
  }

  const changed: PendingEdit[] = [];
  for (let index = 0; index < originalSentences.length; index += 1) {
    const originalSentence = originalSentences[index];
    const replacementSentence = replacementSentences[index];
    if (normalizeSearchQuery(originalSentence.text) === normalizeSearchQuery(replacementSentence.text)) {
      continue;
    }

    const scopedMatches = findTextInDoc(ed.state.doc, originalSentence.text, 2, match);
    if (scopedMatches.length !== 1) {
      return [];
    }

    changed.push(createPendingEdit(ed, {
      id: `${groupId}_sentence_${index}`,
      groupId,
      kind: 'findReplace',
      from: scopedMatches[0].from,
      to: scopedMatches[0].to,
      newHtml: escapeHTML(replacementSentence.text),
    }));
  }

  return changed;
}

function queueProposedEdit(
  ed: Editor,
  id: string,
  target: ProposedEditTarget,
  replaceHtml: string,
  replaceAll: boolean
): number {
  const resolved = resolveProposedEditMatches(ed, target, replaceAll);
  if (typeof resolved === 'number') return resolved;
  if (resolved.length === 0) return 0;

  const edits: PendingEdit[] = [];
  resolved.forEach((match, matchIndex) => {
    const groupId = replaceAll ? `${id}_${matchIndex}` : id;
    const splitEdits = replaceAll
      ? []
      : sentenceSplitPendingEdits(ed, groupId, match, replaceHtml);

    if (splitEdits.length > 0) {
      edits.push(...splitEdits);
      return;
    }

    edits.push(createPendingEdit(ed, {
      id: replaceAll ? `${id}_${matchIndex}` : id,
      groupId,
      kind: 'findReplace',
      from: match.from,
      to: match.to,
      newHtml: replaceHtml,
    }));
  });

  return queuePendingEdits(ed, edits, edits[0]?.id ?? null);
}

function focusPendingEdit(ed: Editor, id: string): boolean {
  const state = getPendingEditsState(ed.state);
  const edit = getPendingEditById(state, id);
  if (!edit) return false;
  ed.commands.focus();
  ed.view.dispatch(
    ed.state.tr
      .setMeta(pendingEditPluginKey, { type: 'focus', id } satisfies PendingEditAction)
      .setSelection(TextSelection.create(ed.state.doc, edit.from, Math.max(edit.from, edit.to)))
      .scrollIntoView()
  );
  return true;
}

function focusRelativePendingEdit(ed: Editor, delta: 1 | -1): boolean {
  const state = getPendingEditsState(ed.state);
  if (state.edits.length === 0) return false;

  const currentIndex = currentPendingEditIndex(state);
  const baseIndex = currentIndex >= 0 ? currentIndex : (delta > 0 ? -1 : 0);
  const nextIndex = (baseIndex + delta + state.edits.length) % state.edits.length;
  return focusPendingEdit(ed, state.edits[nextIndex].id);
}

function isLLMEdit(edit: PendingEdit): boolean {
  return edit.source === 'Claude' || edit.groupId.startsWith('edit_') || edit.id.startsWith('edit_');
}

function colorizeHTMLTextNodes(html: string, color: string): string {
  if (!html.trim()) return html;

  const parsed = new DOMParser().parseFromString(html, 'text/html');
  const walker = parsed.createTreeWalker(parsed.body, NodeFilter.SHOW_TEXT);
  const textNodes: Text[] = [];

  while (walker.nextNode()) {
    const node = walker.currentNode as Text;
    if (node.data.length > 0 && !/^\s*$/.test(node.data)) {
      textNodes.push(node);
    }
  }

  for (const node of textNodes) {
    const span = parsed.createElement('span');
    span.style.color = color;
    node.parentNode?.replaceChild(span, node);
    span.appendChild(node);
  }

  return parsed.body.innerHTML;
}

function htmlForAcceptedEdit(edit: PendingEdit): string {
  return isLLMEdit(edit)
    ? colorizeHTMLTextNodes(edit.newHtml, ACCEPTED_LLM_EDIT_COLOR)
    : edit.newHtml;
}

function isPendingEditDeletion(edit: PendingEdit): boolean {
  return edit.from < edit.to && edit.newHtml.trim().length === 0;
}

function acceptPendingEdit(ed: Editor, id: string): boolean {
  const state = getPendingEditsState(ed.state);
  const edit = getPendingEditById(state, id);
  if (!edit || edit.status === 'conflicted') return false;
  if (!isPendingEditStillApplicable(ed, edit)) {
    markPendingEditConflicted(ed, id, 'The document changed around this suggestion.');
    return false;
  }

  let chain = ed.chain()
    .command(({ tr }) => {
      tr.setMeta(pendingEditPluginKey, { type: 'accept', id } satisfies PendingEditAction);
      if (isPendingEditDeletion(edit)) {
        tr.delete(edit.from, edit.to);
      }
      return true;
    });

  if (!isPendingEditDeletion(edit)) {
    chain = chain.insertContentAt({ from: edit.from, to: edit.to }, htmlForAcceptedEdit(edit));
  }

  const result = chain.run();

  if (result) {
    scheduleSmartQuotesNormalization(ed);
  }

  return result;
}

function rejectPendingEdit(ed: Editor, id: string): boolean {
  const state = getPendingEditsState(ed.state);
  if (!state.edits.some((edit) => edit.id === id)) return false;
  return dispatchPendingEditAction(ed, { type: 'reject', id });
}

function acceptAllPendingEdits(ed: Editor): boolean {
  const state = getPendingEditsState(ed.state);
  if (state.edits.length === 0) return false;

  const pendingEdits = state.edits.filter((edit) => edit.status === 'pending');
  if (pendingEdits.length === 0) return false;

  const applicable: PendingEdit[] = [];
  const stale: PendingEdit[] = [];
  for (const edit of pendingEdits) {
    if (isPendingEditStillApplicable(ed, edit)) {
      applicable.push(edit);
    } else {
      stale.push(edit);
    }
  }

  stale.forEach((edit) => {
    markPendingEditConflicted(ed, edit.id, 'The document changed around this suggestion.');
  });

  const { accepted, conflicted } = nonOverlappingPendingEdits(applicable);
  conflicted.forEach((edit) => {
    markPendingEditConflicted(ed, edit.id, 'This suggestion overlaps another pending edit.');
  });

  if (accepted.length === 0) return false;

  const sorted = [...accepted].sort((a, b) => b.from - a.from || b.to - a.to);
  const acceptedIds = sorted.map((edit) => edit.id);
  let chain = ed.chain().command(({ tr }) => {
    tr.setMeta(pendingEditPluginKey, { type: 'acceptMany', ids: acceptedIds } satisfies PendingEditAction);
    return true;
  });

  for (const edit of sorted) {
    if (isPendingEditDeletion(edit)) {
      chain = chain.command(({ tr }) => {
        tr.delete(edit.from, edit.to);
        return true;
      });
    } else {
      chain = chain.insertContentAt({ from: edit.from, to: edit.to }, htmlForAcceptedEdit(edit));
    }
  }

  const result = chain.run();

  if (result) {
    scheduleSmartQuotesNormalization(ed);
  }

  return result;
}

function rejectAllPendingEdits(ed: Editor): boolean {
  const state = getPendingEditsState(ed.state);
  if (state.edits.length === 0) return false;
  return dispatchPendingEditAction(ed, { type: 'rejectAll' });
}

function pendingEditsSummaryJSON(state: PendingEditsPluginState): string {
  return JSON.stringify({
    activeEditId: state.activeEditId,
    edits: state.edits.map((edit, index) => serializePendingEdit(edit, index, state.activeEditId)),
  });
}

// ─── Comment Mark ───────────────────────────────────────────────────

interface CommentData {
  commentId: string;
  text: string;
  selectedText: string;
  createdAt: number;
  updatedAt: number;
  rangeStart: number;
  rangeEnd: number;
  authorName: string;
  source: string;
  kind: string;
  severity: string;
  status: string;
  suggestedReplacement: string;
  agentRunId: string;
}

interface CommentInput {
  commentId: string;
  from: number;
  to: number;
  text?: string;
  authorName?: string;
  source?: string;
  kind?: string;
  severity?: string;
  status?: string;
  suggestedReplacement?: string;
  agentRunId?: string;
  allowOverlap?: boolean;
}

const CommentMark = Mark.create({
  name: 'comment',
  inclusive: false,
  excludes: '',
  addAttributes() {
    return {
      commentId: {
        default: null,
        parseHTML: (element) => element.getAttribute('data-comment-id'),
        renderHTML: (attributes) => (
          attributes.commentId ? { 'data-comment-id': attributes.commentId } : {}
        ),
      },
      commentText: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-comment-text') ?? '',
        renderHTML: (attributes) => ({ 'data-comment-text': attributes.commentText ?? '' }),
      },
      commentAuthorName: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-comment-author') ?? '',
        renderHTML: (attributes) => (
          attributes.commentAuthorName ? { 'data-comment-author': attributes.commentAuthorName } : {}
        ),
      },
      commentSource: {
        default: 'user',
        parseHTML: (element) => element.getAttribute('data-comment-source') ?? 'user',
        renderHTML: (attributes) => (
          attributes.commentSource && attributes.commentSource !== 'user'
            ? { 'data-comment-source': attributes.commentSource }
            : {}
        ),
      },
      commentKind: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-comment-kind') ?? '',
        renderHTML: (attributes) => (
          attributes.commentKind ? { 'data-comment-kind': attributes.commentKind } : {}
        ),
      },
      commentSeverity: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-comment-severity') ?? '',
        renderHTML: (attributes) => (
          attributes.commentSeverity ? { 'data-comment-severity': attributes.commentSeverity } : {}
        ),
      },
      commentStatus: {
        default: 'open',
        parseHTML: (element) => element.getAttribute('data-comment-status') ?? 'open',
        renderHTML: (attributes) => (
          attributes.commentStatus && attributes.commentStatus !== 'open'
            ? { 'data-comment-status': attributes.commentStatus }
            : {}
        ),
      },
      commentCreatedAt: {
        default: 0,
        parseHTML: (element) => parseCommentTimestamp(
          element.getAttribute('data-comment-created-at')
        ),
        renderHTML: (attributes) => (
          attributes.commentCreatedAt
            ? { 'data-comment-created-at': attributes.commentCreatedAt }
            : {}
        ),
      },
      commentUpdatedAt: {
        default: 0,
        parseHTML: (element) => parseCommentTimestamp(
          element.getAttribute('data-comment-updated-at')
        ),
        renderHTML: (attributes) => (
          attributes.commentUpdatedAt
            ? { 'data-comment-updated-at': attributes.commentUpdatedAt }
            : {}
        ),
      },
      commentSuggestedReplacement: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-comment-suggested-replacement') ?? '',
        renderHTML: (attributes) => (
          attributes.commentSuggestedReplacement
            ? { 'data-comment-suggested-replacement': attributes.commentSuggestedReplacement }
            : {}
        ),
      },
      commentAgentRunId: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-comment-agent-run-id') ?? '',
        renderHTML: (attributes) => (
          attributes.commentAgentRunId
            ? { 'data-comment-agent-run-id': attributes.commentAgentRunId }
            : {}
        ),
      },
    };
  },
  parseHTML() {
    return [{ tag: 'span[data-comment-id]' }];
  },
  renderHTML({ HTMLAttributes }) {
    return [
      'span',
      mergeAttributes(HTMLAttributes, { class: 'comment-highlight' }),
      0,
    ];
  },
});

interface CommentFragment {
  from: number;
  to: number;
  text: string;
}

interface CommentEntry {
  commentId: string;
  text: string;
  createdAt: number;
  updatedAt: number;
  rangeStart: number;
  rangeEnd: number;
  authorName: string;
  source: string;
  kind: string;
  severity: string;
  status: string;
  suggestedReplacement: string;
  agentRunId: string;
  fragments: CommentFragment[];
}

interface CommentMarkAttributes {
  commentId: string;
  commentText: string;
  commentCreatedAt: number;
  commentUpdatedAt: number;
  commentAuthorName: string;
  commentSource: string;
  commentKind: string;
  commentSeverity: string;
  commentStatus: string;
  commentSuggestedReplacement: string;
  commentAgentRunId: string;
}

function parseCommentTimestamp(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function commentString(value: unknown, fallback = ''): string {
  return typeof value === 'string' ? value : fallback;
}

function normalizeCommentStatus(value: unknown): string {
  const status = commentString(value, 'open').trim().toLowerCase();
  return status || 'open';
}

function normalizeCommentSource(value: unknown): string {
  const source = commentString(value, 'user').trim().toLowerCase();
  return source || 'user';
}

function buildCommentMarkAttributes(input: {
  commentId: string;
  text?: string;
  authorName?: string;
  source?: string;
  kind?: string;
  severity?: string;
  status?: string;
  suggestedReplacement?: string;
  agentRunId?: string;
  createdAt?: number;
  updatedAt?: number;
}): CommentMarkAttributes {
  const now = Date.now();
  const createdAt = parseCommentTimestamp(input.createdAt) || now;
  const updatedAt = parseCommentTimestamp(input.updatedAt) || createdAt;

  return {
    commentId: input.commentId,
    commentText: input.text ?? '',
    commentCreatedAt: createdAt,
    commentUpdatedAt: updatedAt,
    commentAuthorName: input.authorName ?? '',
    commentSource: normalizeCommentSource(input.source),
    commentKind: input.kind ?? '',
    commentSeverity: input.severity ?? '',
    commentStatus: normalizeCommentStatus(input.status),
    commentSuggestedReplacement: input.suggestedReplacement ?? '',
    commentAgentRunId: input.agentRunId ?? '',
  };
}

function getCommentMarkAttributes(mark: any): CommentMarkAttributes | null {
  if (mark.type.name !== 'comment') return null;

  const commentId = typeof mark.attrs.commentId === 'string' ? mark.attrs.commentId : '';
  if (!commentId) return null;
  const commentCreatedAt = parseCommentTimestamp(mark.attrs.commentCreatedAt);
  const commentUpdatedAt = parseCommentTimestamp(mark.attrs.commentUpdatedAt) || commentCreatedAt;

  return {
    commentId,
    commentText: typeof mark.attrs.commentText === 'string' ? mark.attrs.commentText : '',
    commentCreatedAt,
    commentUpdatedAt,
    commentAuthorName: commentString(mark.attrs.commentAuthorName),
    commentSource: normalizeCommentSource(mark.attrs.commentSource),
    commentKind: commentString(mark.attrs.commentKind),
    commentSeverity: commentString(mark.attrs.commentSeverity),
    commentStatus: normalizeCommentStatus(mark.attrs.commentStatus),
    commentSuggestedReplacement: commentString(mark.attrs.commentSuggestedReplacement),
    commentAgentRunId: commentString(mark.attrs.commentAgentRunId),
  };
}

function appendCommentFragment(entry: CommentEntry, from: number, to: number, text: string) {
  if (from >= to || text.length === 0) return;

  const lastFragment = entry.fragments[entry.fragments.length - 1];
  if (lastFragment && lastFragment.to === from) {
    lastFragment.to = to;
    lastFragment.text += text;
    return;
  }

  entry.fragments.push({ from, to, text });
}

function buildCommentExcerpt(fragments: CommentFragment[]): string {
  return fragments.map((fragment) => fragment.text).join('\n');
}

function collectCommentEntries(doc: any): CommentEntry[] {
  const comments: Map<string, CommentEntry> = new Map();

  doc.descendants((node: any, pos: number) => {
    if (!node.isText || !node.text) return;

    for (const mark of node.marks) {
      const attrs = getCommentMarkAttributes(mark);
      if (!attrs) continue;

      const to = pos + node.text.length;
      const existing = comments.get(attrs.commentId) ?? {
        commentId: attrs.commentId,
        text: attrs.commentText,
        createdAt: attrs.commentCreatedAt,
        updatedAt: attrs.commentUpdatedAt,
        rangeStart: pos,
        rangeEnd: to,
        authorName: attrs.commentAuthorName,
        source: attrs.commentSource,
        kind: attrs.commentKind,
        severity: attrs.commentSeverity,
        status: attrs.commentStatus,
        suggestedReplacement: attrs.commentSuggestedReplacement,
        agentRunId: attrs.commentAgentRunId,
        fragments: [],
      };

      existing.text = attrs.commentText;
      existing.createdAt = attrs.commentCreatedAt;
      existing.updatedAt = attrs.commentUpdatedAt;
      existing.authorName = attrs.commentAuthorName;
      existing.source = attrs.commentSource;
      existing.kind = attrs.commentKind;
      existing.severity = attrs.commentSeverity;
      existing.status = attrs.commentStatus;
      existing.suggestedReplacement = attrs.commentSuggestedReplacement;
      existing.agentRunId = attrs.commentAgentRunId;
      existing.rangeStart = Math.min(existing.rangeStart, pos);
      existing.rangeEnd = Math.max(existing.rangeEnd, to);
      appendCommentFragment(existing, pos, to, node.text);
      comments.set(attrs.commentId, existing);
    }
  });

  return Array.from(comments.values()).sort((a, b) => (
    a.rangeStart - b.rangeStart ||
    a.createdAt - b.createdAt ||
    a.commentId.localeCompare(b.commentId)
  ));
}

function collectComments(editor: Editor): CommentData[] {
  return collectCommentEntries(editor.state.doc).map((comment) => ({
    commentId: comment.commentId,
    text: comment.text,
    selectedText: buildCommentExcerpt(comment.fragments),
    createdAt: comment.createdAt,
    updatedAt: comment.updatedAt,
    rangeStart: comment.rangeStart,
    rangeEnd: comment.rangeEnd,
    authorName: comment.authorName,
    source: comment.source,
    kind: comment.kind,
    severity: comment.severity,
    status: comment.status,
    suggestedReplacement: comment.suggestedReplacement,
    agentRunId: comment.agentRunId,
  }));
}

function findCommentEntry(editor: Editor, commentId: string): CommentEntry | null {
  return collectCommentEntries(editor.state.doc)
    .find((comment) => comment.commentId === commentId) ?? null;
}

function findOverlappingCommentId(editor: Editor, from: number, to: number): string | null {
  let overlappingCommentId: string | null = null;

  editor.state.doc.nodesBetween(from, to, (node) => {
    if (overlappingCommentId || !node.isText) {
      return false;
    }

    for (const mark of node.marks) {
      const attrs = getCommentMarkAttributes(mark);
      if (!attrs) continue;

      overlappingCommentId = attrs.commentId;
      return false;
    }

    return undefined;
  });

  return overlappingCommentId;
}

function commentSelector(commentId: string): string {
  const escaped = typeof CSS !== 'undefined' && typeof CSS.escape === 'function'
    ? CSS.escape(commentId)
    : commentId.replace(/["\\]/g, '\\$&');
  return `[data-comment-id="${escaped}"]`;
}

function flashCommentHighlights(commentId: string) {
  const elements = Array.from(document.querySelectorAll<HTMLElement>(commentSelector(commentId)));
  if (elements.length === 0) return;

  elements.forEach((element) => {
    element.classList.remove('comment-highlight-flash');
    void element.offsetWidth;
    element.classList.add('comment-highlight-flash');
  });

  window.setTimeout(() => {
    elements.forEach((element) => element.classList.remove('comment-highlight-flash'));
  }, 800);
}

function attachCommentActivation(editor: Editor) {
  const root = editor.view.dom as HTMLElement;
  root.addEventListener('click', (event) => {
    const target = event.target;
    if (!(target instanceof Element)) return;

    const commentElement = target.closest('[data-comment-id]');
    if (!(commentElement instanceof HTMLElement) || !root.contains(commentElement)) return;

    const commentId = commentElement.dataset.commentId;
    if (!commentId) return;

    flashCommentHighlights(commentId);
    sendToSwift('commentActivated', { commentId });
  });
}

function commentsSignature(comments: CommentData[]): string {
  return comments
    .map((comment) => (
      [
        comment.commentId,
        comment.text,
        comment.selectedText,
        comment.createdAt,
        comment.updatedAt,
        comment.rangeStart,
        comment.rangeEnd,
        comment.authorName,
        comment.source,
        comment.kind,
        comment.severity,
        comment.status,
        comment.suggestedReplacement,
        comment.agentRunId,
      ].join('\u001f')
    ))
    .join('\u001e');
}

function emitCommentsChanged(editor: Editor, force = false, documentChanged = false) {
  const comments = collectComments(editor);
  const signature = commentsSignature(comments);

  if (!force && lastSentCommentsSignature === signature) {
    return;
  }

  lastSentCommentsSignature = signature;
  sendToSwift('commentsChanged', { comments, documentChanged });
}

function addComment(editor: Editor, commentId: string): boolean {
  const selection = effectiveTextSelection(editor);
  if (!selection) return false;

  const overlappingCommentId = findOverlappingCommentId(editor, selection.from, selection.to);
  if (overlappingCommentId) {
    focusComment(editor, overlappingCommentId);
    return false;
  }

  const commentMark = editor.state.schema.marks.comment;
  if (!commentMark) return false;

  const tr = editor.state.tr
    .setSelection(TextSelection.create(editor.state.doc, selection.from, selection.to))
    .addMark(
      selection.from,
      selection.to,
      commentMark.create({
        ...buildCommentMarkAttributes({
          commentId,
          source: 'user',
          status: 'open',
        }),
      })
    );

  editor.view.dispatch(tr);
  preservedTextSelection = {
    ...selection,
    revision: documentRevision,
  };
  editor.commands.focus();

  emitCommentsChanged(editor, false, true);
  return true;
}

function parsedCommentInput(json: string): CommentInput | null {
  try {
    const input = JSON.parse(json);
    if (!input || typeof input !== 'object') return null;
    return input as CommentInput;
  } catch (_) {
    return null;
  }
}

function addCommentAtRange(editor: Editor, input: CommentInput): boolean {
  const from = Number(input.from);
  const to = Number(input.to);
  if (!Number.isFinite(from) || !Number.isFinite(to) || from >= to) return false;

  const commentId = commentString(input.commentId).trim();
  if (!commentId) return false;

  if (!input.allowOverlap) {
    const overlappingCommentId = findOverlappingCommentId(editor, from, to);
    if (overlappingCommentId) {
      focusComment(editor, overlappingCommentId);
      return false;
    }
  }

  const commentMark = editor.state.schema.marks.comment;
  if (!commentMark) return false;

  try {
    const selection = TextSelection.create(editor.state.doc, from, to);
    const attrs = buildCommentMarkAttributes({
      commentId,
      text: input.text,
      authorName: input.authorName,
      source: input.source,
      kind: input.kind,
      severity: input.severity,
      status: input.status,
      suggestedReplacement: input.suggestedReplacement,
      agentRunId: input.agentRunId,
    });
    const tr = editor.state.tr
      .setSelection(selection)
      .addMark(from, to, commentMark.create(attrs));

    editor.view.dispatch(tr);
    emitCommentsChanged(editor, false, true);
    return true;
  } catch (_) {
    return false;
  }
}

function addCommentAtRangeFromJSON(editor: Editor, json: string): boolean {
  const input = parsedCommentInput(json);
  return input ? addCommentAtRange(editor, input) : false;
}

function updateCommentText(editor: Editor, commentId: string, text: string) {
  const { tr } = editor.state;
  let changed = false;
  const updatedAt = Date.now();
  editor.state.doc.descendants((node, pos) => {
    if (!node.isText) return;
    for (const mark of node.marks) {
      if (mark.type.name === 'comment' && mark.attrs.commentId === commentId) {
        const newMark = mark.type.create({
          ...mark.attrs,
          commentText: text,
          commentUpdatedAt: updatedAt,
        });
        tr.removeMark(pos, pos + node.nodeSize, mark);
        tr.addMark(pos, pos + node.nodeSize, newMark);
        changed = true;
      }
    }
  });
  if (changed) {
    editor.view.dispatch(tr);
    emitCommentsChanged(editor, false, true);
  }
}

function setCommentStatus(editor: Editor, commentId: string, status: string) {
  const { tr } = editor.state;
  let changed = false;
  const normalizedStatus = normalizeCommentStatus(status);
  const updatedAt = Date.now();

  editor.state.doc.descendants((node, pos) => {
    if (!node.isText) return;
    for (const mark of node.marks) {
      if (mark.type.name === 'comment' && mark.attrs.commentId === commentId) {
        const newMark = mark.type.create({
          ...mark.attrs,
          commentStatus: normalizedStatus,
          commentUpdatedAt: updatedAt,
        });
        tr.removeMark(pos, pos + node.nodeSize, mark);
        tr.addMark(pos, pos + node.nodeSize, newMark);
        changed = true;
      }
    }
  });

  if (changed) {
    editor.view.dispatch(tr);
    emitCommentsChanged(editor, false, true);
  }
}

function removeComment(editor: Editor, commentId: string) {
  const { tr } = editor.state;
  let changed = false;
  editor.state.doc.descendants((node, pos) => {
    if (!node.isText) return;
    for (const mark of node.marks) {
      if (mark.type.name === 'comment' && mark.attrs.commentId === commentId) {
        tr.removeMark(pos, pos + node.nodeSize, mark);
        changed = true;
      }
    }
  });
  if (changed) {
    editor.view.dispatch(tr);
    emitCommentsChanged(editor, false, true);
  }
}

function pendingReplaceComment(editor: Editor, commentId: string, editId: string, html: string): number {
  if (!html.trim()) return 0;

  const comment = findCommentEntry(editor, commentId);
  if (!comment) return 0;

  const edit = createPendingEdit(editor, {
    id: editId,
    groupId: editId,
    kind: 'selection',
    from: comment.rangeStart,
    to: comment.rangeEnd,
    newHtml: html,
  });

  return queuePendingEdits(editor, [edit], edit.id);
}

function focusComment(editor: Editor, commentId: string) {
  const comment = findCommentEntry(editor, commentId);
  if (!comment) return;

  editor.chain()
    .focus()
    .setTextSelection({ from: comment.rangeStart, to: comment.rangeEnd })
    .run();

  const firstElement = document.querySelector<HTMLElement>(commentSelector(commentId));
  firstElement?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  flashCommentHighlights(commentId);
}

const PendingEditHighlight = Extension.create({
  name: 'pendingEditHighlight',

  addKeyboardShortcuts() {
    return {
      'Tab': () => {
        const edit = getActivePendingEdit(getPendingEditsState(this.editor.state));
        return edit ? acceptPendingEdit(this.editor, edit.id) : false;
      },
      'Shift-Tab': () => {
        const edit = getActivePendingEdit(getPendingEditsState(this.editor.state));
        return edit ? rejectPendingEdit(this.editor, edit.id) : false;
      },
      'Escape': () => {
        const edit = getActivePendingEdit(getPendingEditsState(this.editor.state));
        return edit ? rejectPendingEdit(this.editor, edit.id) : false;
      },
    };
  },

  addProseMirrorPlugins() {
    return [
      new Plugin<PendingEditsPluginState>({
        key: pendingEditPluginKey,
        state: {
          init(_, state) {
            return createPendingEditsState(state.doc);
          },
          apply(tr, pluginState, _oldState, newState) {
            const action = tr.getMeta(pendingEditPluginKey) as PendingEditAction | undefined;
            const previousActiveIndex = currentPendingEditIndex(pluginState);

            let edits = pluginState.edits;
            let activeEditId = pluginState.activeEditId;
            let fallbackActiveIndex = previousActiveIndex >= 0 ? previousActiveIndex : 0;
            let scrollToEditId: string | null = null;
            let changed = false;

            if (action) {
              switch (action.type) {
                case 'queue':
                  if (action.edits.length > 0) {
                    edits = [...edits, ...action.edits];
                    activeEditId = action.activeEditId;
                    fallbackActiveIndex = edits.findIndex((edit) => edit.id === action.activeEditId);
                    scrollToEditId = action.scrollToEditId;
                    changed = true;
                  }
                  break;
                case 'focus':
                  if (pluginState.edits.some((edit) => edit.id === action.id) && action.id !== activeEditId) {
                    activeEditId = action.id;
                    fallbackActiveIndex = pluginState.edits.findIndex((edit) => edit.id === action.id);
                    scrollToEditId = action.id;
                    changed = true;
                  }
                  break;
                case 'accept':
                case 'reject': {
                  const nextEdits = edits.filter((edit) => edit.id !== action.id);
                  if (nextEdits.length !== edits.length) {
                    edits = nextEdits;
                    if (activeEditId === action.id) {
                      activeEditId = null;
                    }
                    scrollToEditId = null;
                    changed = true;
                  }
                  break;
                }
                case 'acceptMany': {
                  const acceptedIds = new Set(action.ids);
                  const nextEdits = edits.filter((edit) => !acceptedIds.has(edit.id));
                  if (nextEdits.length !== edits.length) {
                    edits = nextEdits;
                    if (activeEditId && acceptedIds.has(activeEditId)) {
                      activeEditId = null;
                    }
                    scrollToEditId = null;
                    changed = true;
                  }
                  break;
                }
                case 'conflict': {
                  let didConflict = false;
                  edits = edits.map((edit) => {
                    if (edit.id !== action.id || edit.status === 'conflicted') return edit;
                    didConflict = true;
                    return {
                      ...edit,
                      status: 'conflicted',
                      conflictReason: action.reason,
                    };
                  });
                  if (didConflict) {
                    scrollToEditId = action.id;
                    changed = true;
                  }
                  break;
                }
                case 'acceptAll':
                case 'rejectAll':
                  if (edits.length > 0) {
                    edits = [];
                    activeEditId = null;
                    scrollToEditId = null;
                    changed = true;
                  }
                  break;
              }
            }

            const rebasedEdits = rebasePendingEdits(edits, tr);
            if (rebasedEdits !== edits) {
              edits = rebasedEdits;
              changed = true;
            }

            const normalizedActiveEditId = resolveActivePendingEditId(
              edits,
              activeEditId,
              fallbackActiveIndex
            );

            if (normalizedActiveEditId !== activeEditId) {
              activeEditId = normalizedActiveEditId;
              changed = true;
            }

            if (!changed) return pluginState;

            if (!scrollToEditId && action && edits.length > 0 && activeEditId) {
              if (action.type === 'accept' || action.type === 'reject' || action.type === 'focus') {
                scrollToEditId = activeEditId;
              }
            }

            return createPendingEditsState(
              newState.doc,
              edits,
              activeEditId,
              pluginState.version + 1,
              scrollToEditId
            );
          },
        },
        props: {
          decorations(state) {
            return pendingEditPluginKey.getState(state)?.decorations ?? DecorationSet.empty;
          },
        },
        view(view) {
          return {
            update(updatedView, previousState) {
              const previousPendingState = getPendingEditsState(previousState);
              const nextPendingState = getPendingEditsState(updatedView.state);

              if (previousPendingState.version === nextPendingState.version) return;

              notifyPendingEditState(nextPendingState);

              if (!nextPendingState.scrollToEditId) return;

              const targetEdit = getPendingEditById(nextPendingState, nextPendingState.scrollToEditId);
              if (targetEdit) {
                scrollToPendingEdit(updatedView, targetEdit);
              }
            },
          };
        },
      }),
    ];
  },
});

function isSearchWhitespace(character: string): boolean {
  return character === '\u00a0' || /\s/.test(character);
}

function foldSearchCharacter(character: string): string {
  switch (character) {
    case '\u2018':
    case '\u2019':
    case '\u201A':
    case '\u201B':
      return "'";
    case '\u201C':
    case '\u201D':
    case '\u201E':
    case '\u201F':
      return '"';
    default:
      return character.toLowerCase();
  }
}

function appendSearchCharacter(
  builder: SearchIndexBuilder,
  character: string,
  from: number,
  to: number
) {
  if (isSearchWhitespace(character)) {
    if (builder.text.length === 0) return;

    if (builder.lastWasWhitespace) {
      const lastRange = builder.ranges[builder.ranges.length - 1];
      if (lastRange) {
        lastRange.from = Math.min(lastRange.from, from);
        lastRange.to = Math.max(lastRange.to, to);
      }
      return;
    }

    builder.text += ' ';
    builder.ranges.push({ from, to });
    builder.lastWasWhitespace = true;
    return;
  }

  const folded = foldSearchCharacter(character);
  for (let i = 0; i < folded.length; i += 1) {
    builder.text += folded[i];
    builder.ranges.push({ from, to });
  }
  builder.lastWasWhitespace = false;
}

function trimTrailingSearchWhitespace(builder: SearchIndexBuilder) {
  while (builder.text.endsWith(' ')) {
    builder.text = builder.text.slice(0, -1);
    builder.ranges.pop();
  }
  builder.lastWasWhitespace = builder.text.endsWith(' ');
}

function normalizeSearchQuery(query: string): string {
  const builder: SearchIndexBuilder = {
    text: '',
    ranges: [],
    lastWasWhitespace: false,
  };

  for (let i = 0; i < query.length; i += 1) {
    appendSearchCharacter(builder, query[i], i, i + 1);
  }

  trimTrailingSearchWhitespace(builder);
  return builder.text;
}

function buildDocumentSearchIndex(doc: any): SearchIndex {
  const builder: SearchIndexBuilder = {
    text: '',
    ranges: [],
    lastWasWhitespace: false,
  };
  let hasVisitedTextBlock = false;

  doc.descendants((node: any, pos: number) => {
    if (!node.isTextblock) return;

    if (hasVisitedTextBlock) {
      appendSearchCharacter(builder, '\n', pos, pos);
    }
    hasVisitedTextBlock = true;

    node.forEach((child: any, offset: number) => {
      const childPos = pos + 1 + offset;

      if (child.isText && typeof child.text === 'string') {
        for (let i = 0; i < child.text.length; i += 1) {
          appendSearchCharacter(builder, child.text[i], childPos + i, childPos + i + 1);
        }
        return;
      }

      if (child.type?.name === 'hardBreak') {
        appendSearchCharacter(builder, '\n', childPos, childPos + child.nodeSize);
      }
    });

    return false;
  });

  trimTrailingSearchWhitespace(builder);
  return {
    text: builder.text,
    ranges: builder.ranges,
  };
}

function findTextInDoc(
  doc: any,
  query: string,
  maxMatches = Number.POSITIVE_INFINITY,
  scope: SearchMatch | null = null
): SearchMatch[] {
  const normalizedQuery = normalizeSearchQuery(query);
  if (!normalizedQuery) return [];
  const matches: SearchMatch[] = [];
  const searchIndex = buildDocumentSearchIndex(doc);
  const advanceBy = Math.max(normalizedQuery.length, 1);

  let idx = searchIndex.text.indexOf(normalizedQuery);
  while (idx !== -1) {
    const start = searchIndex.ranges[idx];
    const end = searchIndex.ranges[idx + normalizedQuery.length - 1];
    if (start && end) {
      const match = { from: start.from, to: end.to };
      if (!scope || (match.from >= scope.from && match.to <= scope.to)) {
        matches.push(match);
        if (matches.length >= maxMatches) break;
      }
    }
    idx = searchIndex.text.indexOf(normalizedQuery, idx + advanceBy);
  }

  return matches;
}

function scrollToMatch(editor: Editor, match: SearchMatch) {
  try {
    const domAtPos = editor.view.domAtPos(match.from);
    const node = domAtPos.node as HTMLElement;
    const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
    el?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  } catch (_) {
    // position might not be mappable
  }
}

function updateSearchDecorations(editor: Editor) {
  // Trigger plugin to recalculate decorations
  const tr = editor.state.tr.setMeta(searchPluginKey, { query: activeSearchQuery, currentIdx: currentMatchIdx });
  editor.view.dispatch(tr);
}

const SearchHighlight = Extension.create({
  name: 'searchHighlight',
  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: searchPluginKey,
        state: {
          init() {
            return DecorationSet.empty;
          },
          apply(tr, oldSet, _oldState, newState) {
            const meta = tr.getMeta(searchPluginKey);
            if (meta !== undefined) {
              // Recalculate decorations from current search state
              if (!activeSearchQuery) return DecorationSet.empty;
              const decorations: Decoration[] = [];
              searchResults.forEach((match, i) => {
                const className = i === currentMatchIdx ? 'search-current' : 'search-match';
                decorations.push(Decoration.inline(match.from, match.to, { class: className }));
              });
              return DecorationSet.create(newState.doc, decorations);
            }
            // Map existing decorations through document changes
            return oldSet.map(tr.mapping, tr.doc);
          },
        },
        props: {
          decorations(state) {
            return this.getState(state);
          },
        },
      }),
    ];
  },
});

const HoverableLink = Link.extend({
  renderHTML({ HTMLAttributes }) {
    const href = typeof HTMLAttributes.href === 'string' ? HTMLAttributes.href : '';
    return [
      'a',
      mergeAttributes(this.options.HTMLAttributes, HTMLAttributes, href ? { title: href } : {}),
      0,
    ];
  },
});

function normalizeFootnoteNote(note: string): string {
  return smartifyQuotes(note.replace(/\r\n?/g, '\n'));
}

function createFootnoteID(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `footnote-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

function collectFootnotes(doc: any): FootnoteDetails[] {
  const footnotes: FootnoteDetails[] = [];
  let index = 1;

  doc.descendants((node: any, pos: number) => {
    if (node.type.name !== FOOTNOTE_NODE_NAME) return;
    footnotes.push({
      id: (node.attrs.id as string) || `footnote-${index}`,
      index,
      note: normalizeFootnoteNote((node.attrs.note as string) || ''),
      pos,
    });
    index += 1;
  });

  return footnotes;
}

function escapeHTML(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function buildGeneratedFootnotesHTML(footnotes: FootnoteDetails[]): string {
  if (footnotes.length === 0) return '';

  const items = footnotes.map((footnote) => {
    const noteHTML = escapeHTML(footnote.note).replace(/\n/g, '<br>');
    return `<li id="footnote-${escapeHTML(footnote.id)}">${noteHTML}</li>`;
  });

  return `<section class="generated-footnotes" data-generated-footnotes="true"><hr><ol>${items.join('')}</ol></section>`;
}

function footnotesSignature(footnotes: FootnoteDetails[]): string {
  return footnotes
    .map((footnote) => `${footnote.id}\u001f${footnote.index}\u001f${footnote.note}`)
    .join('\u001e');
}

function footnotesStructureSignature(footnotes: FootnoteDetails[]): string {
  return footnotes
    .map((footnote) => `${footnote.id}\u001f${footnote.index}`)
    .join('\u001e');
}

function buildPlainTextSnapshot(editor: Editor, footnotes: FootnoteDetails[]): DocumentTextSnapshot {
  const text = editor.getText();

  if (footnotes.length === 0) {
    return {
      revision: documentRevision,
      footnotes,
      footnotesSignature: '',
      footnotesStructureSignature: '',
      plainText: text,
      words: countWords(text),
      characters: text.length,
    };
  }

  const footnotesText = footnotes
    .map((footnote) => `[${footnote.index}] ${footnote.note}`)
    .join('\n');

  const plainText = text.trim().length > 0
    ? `${text}\n\nFootnotes\n${footnotesText}`
    : `Footnotes\n${footnotesText}`;

  return {
    revision: documentRevision,
    footnotes,
    footnotesSignature: footnotesSignature(footnotes),
    footnotesStructureSignature: footnotesStructureSignature(footnotes),
    plainText,
    words: countWords(plainText),
    characters: plainText.length,
  };
}

let documentRevision = 0;
let cachedDocumentTextSnapshot: DocumentTextSnapshot | null = null;
let cachedSerializedHTMLRevision = -1;
let cachedSerializedHTML = '';
let lastRenderedFootnotesStructureSignature: string | null = null;
let lastSentContentUpdate: { html: string; text: string } | null = null;
let lastSentSelectionState: EditorSelectionState | null = null;
let lastSentCommentsSignature: string | null = null;
let preservedTextSelection: PreservedTextSelection | null = null;

function invalidateDerivedDocumentState() {
  documentRevision += 1;
  cachedDocumentTextSnapshot = null;
  cachedSerializedHTMLRevision = -1;
  cachedSerializedHTML = '';
}

function resetEditorSyncState() {
  if (wordCountDebounceTimer) clearTimeout(wordCountDebounceTimer);
  if (contentSyncDebounceTimer) clearTimeout(contentSyncDebounceTimer);
  if (footnotePanelDebounceTimer) clearTimeout(footnotePanelDebounceTimer);
  if (selectionDebounceTimer) clearTimeout(selectionDebounceTimer);

  invalidateDerivedDocumentState();
  lastRenderedFootnotesStructureSignature = null;
  lastSentContentUpdate = null;
  lastSentSelectionState = null;
  lastSentCommentsSignature = null;
  preservedTextSelection = null;
}

function getDocumentTextSnapshot(editor: Editor): DocumentTextSnapshot {
  if (cachedDocumentTextSnapshot?.revision === documentRevision) {
    return cachedDocumentTextSnapshot;
  }

  const snapshot = buildPlainTextSnapshot(editor, collectFootnotes(editor.state.doc));
  cachedDocumentTextSnapshot = snapshot;
  return snapshot;
}

function serializeDocumentPlainText(editor: Editor): string {
  return getDocumentTextSnapshot(editor).plainText;
}

function hashString(value: string): string {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i += 1) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

function truncateForEditContext(text: string): string {
  if (text.length <= MAX_EDIT_CONTEXT_BLOCK_TEXT) return text;
  const headCount = Math.floor(MAX_EDIT_CONTEXT_BLOCK_TEXT / 2);
  const tailCount = MAX_EDIT_CONTEXT_BLOCK_TEXT - headCount;
  return `${text.slice(0, headCount)}\n[...]\n${text.slice(text.length - tailCount)}`;
}

function buildEditBlockIndex(doc: any): EditContextBlock[] {
  const blocks: EditContextBlock[] = [];

  const visit = (node: any, pos: number, path: number[], isRoot: boolean) => {
    if (blocks.length >= MAX_EDIT_CONTEXT_BLOCKS) return;

    if (node.isTextblock) {
      const text = node.textBetween(0, node.content.size, '\n', '\n');
      const pathString = path.join('.');
      const textHash = hashString(text);
      blocks.push({
        id: `block_${pathString || 'root'}_${textHash}`,
        path: pathString,
        type: node.type.name,
        from: pos + 1,
        to: pos + node.nodeSize - 1,
        text: truncateForEditContext(text),
        textHash,
      });
    }

    node.forEach((child: any, offset: number, index: number) => {
      if (blocks.length >= MAX_EDIT_CONTEXT_BLOCKS) return;
      const childPos = (isRoot ? 0 : pos + 1) + offset;
      visit(child, childPos, [...path, index], false);
    });
  };

  visit(doc, 0, [], true);
  return blocks;
}

function textNearPosition(doc: any, pos: number): string {
  const from = Math.max(0, pos - NEARBY_EDIT_CONTEXT_CHARS);
  const to = Math.min(doc.content.size, pos + NEARBY_EDIT_CONTEXT_CHARS);
  return doc.textBetween(from, to, '\n', '\n');
}

function buildEditContextSnapshot(editor: Editor): EditContextSnapshot {
  const plainText = serializeDocumentPlainText(editor);
  const activeSelection = effectiveTextSelection(editor);
  const selection = activeSelection
    ? {
      from: activeSelection.from,
      to: activeSelection.to,
      text: activeSelection.text,
      html: serializeClipboardDataForRange(editor, activeSelection.from, activeSelection.to).html,
      words: activeSelection.words,
      characters: activeSelection.characters,
    }
    : null;

  const cursorPosition = selection?.to ?? editor.state.selection.from;

  return {
    revision: documentRevision,
    documentHash: hashString(plainText),
    plainText,
    cursorPosition,
    nearbyText: textNearPosition(editor.state.doc, cursorPosition),
    selection,
    blocks: buildEditBlockIndex(editor.state.doc),
  };
}

function serializeDocumentHTML(editor: Editor): string {
  if (cachedSerializedHTMLRevision === documentRevision) {
    return cachedSerializedHTML;
  }

  const content = editor.getHTML();
  const footnotesHTML = buildGeneratedFootnotesHTML(getDocumentTextSnapshot(editor).footnotes);
  cachedSerializedHTML = footnotesHTML ? `${content}${footnotesHTML}` : content;
  cachedSerializedHTMLRevision = documentRevision;
  return cachedSerializedHTML;
}

function serializeClipboardDataForRange(
  editor: Editor,
  from: number,
  to: number
): SelectionClipboardData {
  const emptySelection: SelectionClipboardData = {
    html: '',
    text: '',
    imageSources: [],
    singleImageSource: null,
  };

  if (from >= to) {
    return emptySelection;
  }

  let selection: TextSelection;
  try {
    selection = TextSelection.create(editor.state.doc, from, to);
  } catch (_) {
    return emptySelection;
  }

  const { dom, text } = editor.view.serializeForClipboard(selection.content());
  Array.from(dom.querySelectorAll('*')).forEach((element) => {
    Array.from(element.attributes).forEach((attribute) => {
      if (attribute.name.startsWith('data-pm-')) {
        element.removeAttribute(attribute.name);
      }
    });
  });

  const html = dom.innerHTML;
  const imageSources = Array.from(dom.querySelectorAll('img'))
    .map((img) => img.getAttribute('src')?.trim() || '')
    .filter(Boolean);
  const normalizedText = text.replace(/\u00a0/g, ' ').replace(/\uFFFC/g, '');
  const singleImageSource =
    imageSources.length === 1 && !normalizedText.trim() ? imageSources[0] : null;

  return {
    html,
    text: normalizedText,
    imageSources,
    singleImageSource,
  };
}

function serializeSelectionClipboardData(editor: Editor): SelectionClipboardData {
  const { from, to } = editor.state.selection;
  return serializeClipboardDataForRange(editor, from, to);
}

function footnoteEditorSelector(id: string): string {
  const escapedID = typeof CSS !== 'undefined' && typeof CSS.escape === 'function'
    ? CSS.escape(id)
    : id.replace(/["\\]/g, '\\$&');
  return `.editor-footnote-editor[data-footnote-id="${escapedID}"]`;
}

function getFootnoteEditorElement(container: HTMLElement, id: string): HTMLElement | null {
  const editorElement = container.querySelector(footnoteEditorSelector(id));
  return editorElement instanceof HTMLElement ? editorElement : null;
}

function appendEditablePlainText(node: Node, parts: string[]) {
  if (node.nodeType === Node.TEXT_NODE) {
    parts.push(node.textContent || '');
    return;
  }

  if (node instanceof HTMLBRElement) {
    parts.push('\n');
    return;
  }

  if (!(node instanceof HTMLElement)) return;

  const tagName = node.tagName.toLowerCase();
  const isBlock = tagName === 'div' || tagName === 'p';
  if (isBlock && parts.length > 0 && parts[parts.length - 1] !== '\n') {
    parts.push('\n');
  }

  node.childNodes.forEach((child) => appendEditablePlainText(child, parts));

  if (isBlock && parts[parts.length - 1] !== '\n') {
    parts.push('\n');
  }
}

function footnoteEditorPlainText(element: HTMLElement): string {
  const parts: string[] = [];
  element.childNodes.forEach((child) => appendEditablePlainText(child, parts));
  return parts.join('').replace(/\u00a0/g, ' ').replace(/\n$/, '');
}

function setFootnoteEditorPlainText(element: HTMLElement, text: string) {
  element.textContent = text;
}

function contentEditableSelectionOffsets(element: HTMLElement): { start: number; end: number } | null {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return null;

  const range = selection.getRangeAt(0);
  if (!element.contains(range.startContainer) || !element.contains(range.endContainer)) {
    return null;
  }

  const startRange = range.cloneRange();
  startRange.selectNodeContents(element);
  startRange.setEnd(range.startContainer, range.startOffset);

  const endRange = range.cloneRange();
  endRange.selectNodeContents(element);
  endRange.setEnd(range.endContainer, range.endOffset);

  return {
    start: startRange.toString().length,
    end: endRange.toString().length,
  };
}

function clampTextOffset(offset: number, length: number): number {
  return Math.max(0, Math.min(offset, length));
}

function contentEditablePointAtOffset(
  element: HTMLElement,
  offset: number
): { node: Node; offset: number } {
  const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT);
  let remaining = Math.max(0, offset);
  let lastTextNode: Text | null = null;

  while (walker.nextNode()) {
    const textNode = walker.currentNode as Text;
    lastTextNode = textNode;
    const length = textNode.data.length;
    if (remaining <= length) {
      return { node: textNode, offset: remaining };
    }
    remaining -= length;
  }

  if (lastTextNode) {
    return { node: lastTextNode, offset: lastTextNode.data.length };
  }

  return { node: element, offset: element.childNodes.length };
}

function restoreContentEditableSelection(
  element: HTMLElement,
  selectionState: { start: number; end: number }
) {
  const selection = window.getSelection();
  if (!selection) return;

  const textLength = footnoteEditorPlainText(element).length;
  const start = clampTextOffset(selectionState.start, textLength);
  const end = clampTextOffset(selectionState.end, textLength);
  const startPoint = contentEditablePointAtOffset(element, start);
  const endPoint = contentEditablePointAtOffset(element, end);

  const range = document.createRange();
  range.setStart(startPoint.node, startPoint.offset);
  range.setEnd(endPoint.node, endPoint.offset);
  selection.removeAllRanges();
  selection.addRange(range);
}

function getFootnoteByID(editor: Editor, id: string): FootnoteDetails | null {
  return getDocumentTextSnapshot(editor).footnotes.find((footnote) => footnote.id === id) ?? null;
}

function selectFootnoteReference(
  editor: Editor,
  id: string,
  options: { focusEditor?: boolean; scrollIntoView?: boolean } = {}
): boolean {
  const footnote = getFootnoteByID(editor, id);
  if (!footnote) return false;

  const { focusEditor = false, scrollIntoView = false } = options;
  if (focusEditor) {
    editor.commands.focus();
  }

  editor.view.dispatch(
    editor.state.tr.setSelection(NodeSelection.create(editor.state.doc, footnote.pos))
  );

  if (scrollIntoView) {
    try {
      const domAtPos = editor.view.domAtPos(footnote.pos);
      const node = domAtPos.node as HTMLElement;
      const element = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
      element?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    } catch (_) {
      // Ignore if the DOM position can't be resolved.
    }
  }

  return true;
}

function focusFootnoteEditor(id: string, placeCaretAtEnd = true): boolean {
  const container = document.getElementById('footnotes');
  if (!container) return false;

  const editorElement = getFootnoteEditorElement(container, id);
  if (!editorElement) return false;

  editorElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
  editorElement.focus();

  if (placeCaretAtEnd) {
    const end = footnoteEditorPlainText(editorElement).length;
    restoreContentEditableSelection(editorElement, { start: end, end });
  }

  return true;
}

function updateFootnoteNote(editor: Editor, id: string, note: string) {
  const footnote = getFootnoteByID(editor, id);
  if (!footnote) return;

  const currentNode = editor.state.doc.nodeAt(footnote.pos);
  if (!currentNode) return;

  const normalizedNote = normalizeFootnoteNote(note);
  if ((currentNode.attrs.note as string || '') === normalizedNote) return;

  editor.view.dispatch(
    editor.state.tr.setNodeMarkup(footnote.pos, undefined, {
      ...currentNode.attrs,
      note: normalizedNote,
    })
  );
}

function captureFocusedFootnoteEditorState(container: HTMLElement): FocusedFootnoteEditorState | null {
  const activeElement = document.activeElement;
  if (!(activeElement instanceof HTMLElement)) return null;

  const id = activeElement.dataset.footnoteId;
  if (!id || !activeElement.classList.contains('editor-footnote-editor') || !container.contains(activeElement)) {
    return null;
  }

  const selectionState = contentEditableSelectionOffsets(activeElement);
  if (!selectionState) return null;

  return {
    id,
    selectionStart: selectionState.start,
    selectionEnd: selectionState.end,
    scrollTop: activeElement.scrollTop,
  };
}

function restoreFocusedFootnoteEditorState(
  container: HTMLElement,
  state: FocusedFootnoteEditorState | null
) {
  if (!state) return;

  const editorElement = getFootnoteEditorElement(container, state.id);
  if (!editorElement) return;

  editorElement.focus();
  restoreContentEditableSelection(editorElement, {
    start: state.selectionStart,
    end: state.selectionEnd,
  });
  editorElement.scrollTop = state.scrollTop;
}

function syncFootnotePanelValues(container: HTMLElement, footnotes: FootnoteDetails[]) {
  const editors = new Map<string, HTMLElement>();
  container.querySelectorAll('.editor-footnote-editor').forEach((element) => {
    if (element instanceof HTMLElement && element.dataset.footnoteId) {
      editors.set(element.dataset.footnoteId, element);
    }
  });

  footnotes.forEach((footnote) => {
    const editorElement = editors.get(footnote.id);
    if (!editorElement) return;
    if (document.activeElement === editorElement) return;

    if (footnoteEditorPlainText(editorElement) !== footnote.note) {
      setFootnoteEditorPlainText(editorElement, footnote.note);
    }
  });
}

function renderFootnotesPanel(editor: Editor, force = false) {
  const container = document.getElementById('footnotes');
  if (!container) return;

  const snapshot = getDocumentTextSnapshot(editor);
  if (!force && snapshot.footnotesStructureSignature === lastRenderedFootnotesStructureSignature) {
    syncFootnotePanelValues(container, snapshot.footnotes);
    return;
  }

  if (snapshot.footnotes.length === 0) {
    lastRenderedFootnotesStructureSignature = snapshot.footnotesStructureSignature;
    container.replaceChildren();
    container.setAttribute('hidden', 'true');
    return;
  }

  const focusedEditorState = captureFocusedFootnoteEditorState(container);
  lastRenderedFootnotesStructureSignature = snapshot.footnotesStructureSignature;
  container.replaceChildren();
  container.removeAttribute('hidden');

  const title = document.createElement('div');
  title.className = 'editor-footnotes-title';
  title.textContent = 'Footnotes';
  container.appendChild(title);

  const list = document.createElement('ol');
  list.className = 'editor-footnotes-list';

  snapshot.footnotes.forEach((footnote) => {
    const item = document.createElement('li');
    item.id = `editor-footnote-${footnote.id}`;

    const note = document.createElement('div');
    note.className = 'editor-footnote-editor';
    note.dataset.footnoteId = footnote.id;
    note.contentEditable = 'true';
    note.setAttribute('role', 'textbox');
    note.setAttribute('aria-multiline', 'true');
    note.setAttribute('data-placeholder', 'Footnote text');
    note.spellcheck = true;
    setFootnoteEditorPlainText(note, footnote.note);
    note.addEventListener('focus', () => {
      selectFootnoteReference(editor, footnote.id);
    });
    note.addEventListener('paste', (event) => {
      event.preventDefault();
      const pastedText = event.clipboardData?.getData('text/plain') || '';
      document.execCommand('insertText', false, normalizeFootnoteNote(pastedText));
    });
    note.addEventListener('input', () => {
      const selectionState = contentEditableSelectionOffsets(note);
      const draftText = footnoteEditorPlainText(note);
      const normalizedText = normalizeFootnoteNote(draftText);
      if (
        normalizedText !== draftText ||
        note.querySelector('*') !== null ||
        (normalizedText.length === 0 && note.childNodes.length > 0)
      ) {
        setFootnoteEditorPlainText(note, normalizedText);
        if (selectionState) restoreContentEditableSelection(note, selectionState);
      }
      updateFootnoteNote(editor, footnote.id, normalizedText);
    });
    note.addEventListener('keydown', (event) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        selectFootnoteReference(editor, footnote.id, {
          focusEditor: true,
          scrollIntoView: true,
        });
      }
    });
    item.appendChild(note);

    list.appendChild(item);
  });

  container.appendChild(list);
  restoreFocusedFootnoteEditorState(container, focusedEditorState);
}

function editorHasFocus(editor: Editor): boolean {
  const root = editor.view.dom as HTMLElement;
  const activeElement = document.activeElement;
  return activeElement === root || !!(activeElement && root.contains(activeElement));
}

function currentTextSelection(editor: Editor): PreservedTextSelection | null {
  const { from, to } = editor.state.selection;
  if (from === to) return null;

  const text = editor.state.doc.textBetween(from, to, '\n', '\n');
  return {
    from,
    to,
    text,
    words: countWords(text),
    characters: text.length,
    revision: documentRevision,
  };
}

function updatePreservedTextSelection(editor: Editor) {
  const selection = currentTextSelection(editor);
  if (selection) {
    preservedTextSelection = selection;
    return;
  }

  if (editorHasFocus(editor)) {
    preservedTextSelection = null;
  }
}

function effectiveTextSelection(editor: Editor): PreservedTextSelection | null {
  const selection = currentTextSelection(editor);
  if (selection) {
    preservedTextSelection = selection;
    return selection;
  }

  if (
    preservedTextSelection &&
    preservedTextSelection.revision === documentRevision &&
    !editorHasFocus(editor)
  ) {
    return preservedTextSelection;
  }

  return null;
}

function buildSelectionState(editor: Editor): EditorSelectionState {
  const activeSelection = effectiveTextSelection(editor);
  const selectedFootnote = getSelectedFootnote(editor);
  const selectedImage = selectedImageNode(editor);
  const selectedImageAttrs = (selectedImage?.node.attrs || {}) as Record<string, unknown>;

  return {
    hasSelection: activeSelection !== null,
    selectedWords: activeSelection?.words || 0,
    selectedCharacters: activeSelection?.characters || 0,
    isBold: editor.isActive('bold'),
    isItalic: editor.isActive('italic'),
    isUnderline: editor.isActive('underline'),
    heading: editor.isActive('heading', { level: 1 })
      ? 1
      : editor.isActive('heading', { level: 2 })
        ? 2
        : editor.isActive('heading', { level: 3 })
          ? 3
          : 0,
    textAlign: editor.isActive({ textAlign: 'center' })
      ? 'center'
      : editor.isActive({ textAlign: 'right' })
        ? 'right'
        : editor.isActive({ textAlign: 'justify' })
          ? 'justify'
          : 'left',
    isLink: editor.isActive('link'),
    linkHref: editor.getAttributes('link').href || '',
    textColor: editor.getAttributes('textStyle').color || '',
    isFootnote: selectedFootnote !== null,
    footnoteText: (selectedFootnote?.node.attrs.note as string) || '',
    isImage: selectedImage !== null,
    imageLayout: normalizeImageLayout(selectedImageAttrs.layout),
    imageAlign: normalizeImageAlign(selectedImageAttrs.align),
    imageWidth: (selectedImageAttrs.width as string) || '',
    imageHeight: (selectedImageAttrs.height as string) || '',
  };
}

function selectionStatesEqual(
  a: EditorSelectionState | null,
  b: EditorSelectionState
): boolean {
  if (!a) return false;

  return a.hasSelection === b.hasSelection &&
    a.selectedWords === b.selectedWords &&
    a.selectedCharacters === b.selectedCharacters &&
    a.isBold === b.isBold &&
    a.isItalic === b.isItalic &&
    a.isUnderline === b.isUnderline &&
    a.heading === b.heading &&
    a.textAlign === b.textAlign &&
    a.isLink === b.isLink &&
    a.linkHref === b.linkHref &&
    a.textColor === b.textColor &&
    a.isFootnote === b.isFootnote &&
    a.footnoteText === b.footnoteText &&
    a.isImage === b.isImage &&
    a.imageLayout === b.imageLayout &&
    a.imageAlign === b.imageAlign &&
    a.imageWidth === b.imageWidth &&
    a.imageHeight === b.imageHeight;
}

function emitWordCountUpdate(editor: Editor) {
  const snapshot = getDocumentTextSnapshot(editor);
  sendToSwift('wordCount', {
    words: snapshot.words,
    characters: snapshot.characters,
  });
}

function emitContentUpdate(editor: Editor) {
  const snapshot = getDocumentTextSnapshot(editor);
  const html = serializeDocumentHTML(editor);

  if (
    lastSentContentUpdate &&
    lastSentContentUpdate.html === html &&
    lastSentContentUpdate.text === snapshot.plainText
  ) {
    return;
  }

  lastSentContentUpdate = {
    html,
    text: snapshot.plainText,
  };

  sendToSwift('contentUpdate', {
    html,
    text: snapshot.plainText,
    words: snapshot.words,
    characters: snapshot.characters,
  });
}

function emitSelectionUpdate(editor: Editor) {
  const selectionState = buildSelectionState(editor);
  if (selectionStatesEqual(lastSentSelectionState, selectionState)) {
    return;
  }

  lastSentSelectionState = selectionState;
  sendToSwift('selectionChanged', selectionState);
}

function scheduleSelectionUpdate(editor: Editor) {
  if (selectionDebounceTimer) clearTimeout(selectionDebounceTimer);
  selectionDebounceTimer = setTimeout(() => {
    emitSelectionUpdate(editor);
  }, SELECTION_SYNC_DEBOUNCE_MS);
}

function scheduleWordCountUpdate(editor: Editor) {
  if (wordCountDebounceTimer) clearTimeout(wordCountDebounceTimer);
  wordCountDebounceTimer = setTimeout(() => {
    emitWordCountUpdate(editor);
  }, WORD_COUNT_DEBOUNCE_MS);
}

function scheduleContentUpdate(editor: Editor) {
  if (contentSyncDebounceTimer) clearTimeout(contentSyncDebounceTimer);
  contentSyncDebounceTimer = setTimeout(() => {
    emitContentUpdate(editor);
  }, CONTENT_SYNC_DEBOUNCE_MS);
}

function scheduleFootnotesPanelRender(editor: Editor) {
  if (footnotePanelDebounceTimer) clearTimeout(footnotePanelDebounceTimer);
  footnotePanelDebounceTimer = setTimeout(() => {
    renderFootnotesPanel(editor);
  }, FOOTNOTE_PANEL_DEBOUNCE_MS);
}

function attachSelectionChangeFallback(editor: Editor) {
  const root = editor.view.dom as HTMLElement;
  const scheduleFromNativeSelection = () => {
    window.requestAnimationFrame(() => {
      updatePreservedTextSelection(editor);
      scheduleSelectionUpdate(editor);
    });
  };

  const syncIfSelectionTouchesEditor = () => {
    const selection = document.getSelection();
    if (!selection) return;

    const anchorNode = selection.anchorNode;
    const focusNode = selection.focusNode;
    if (
      (anchorNode && root.contains(anchorNode)) ||
      (focusNode && root.contains(focusNode)) ||
      root.contains(document.activeElement)
    ) {
      scheduleFromNativeSelection();
    }
  };

  root.addEventListener('mouseup', syncIfSelectionTouchesEditor);
  root.addEventListener('keyup', syncIfSelectionTouchesEditor);
  root.addEventListener('dragend', syncIfSelectionTouchesEditor);
  root.addEventListener('focusin', syncIfSelectionTouchesEditor);
  document.addEventListener('selectionchange', syncIfSelectionTouchesEditor);
}

function attachSmartQuotesNormalizationFallback(editor: Editor) {
  const root = editor.view.dom as HTMLElement;
  const normalizeSoon = () => {
    scheduleSmartQuotesNormalization(editor);
  };

  root.addEventListener('paste', normalizeSoon);
  root.addEventListener('drop', normalizeSoon);
}

function stripGeneratedFootnotesSection(html: string): string {
  if (!html.includes('data-generated-footnotes')) {
    return html;
  }

  const parsed = new DOMParser().parseFromString(html, 'text/html');
  parsed.querySelectorAll(GENERATED_FOOTNOTES_SELECTOR).forEach((element) => element.remove());
  return parsed.body.innerHTML;
}

function getSelectedFootnote(editor: Editor): { node: any; pos: number } | null {
  const { selection } = editor.state;
  if (selection instanceof NodeSelection && selection.node.type.name === FOOTNOTE_NODE_NAME) {
    return { node: selection.node, pos: selection.from };
  }
  return null;
}

function upsertFootnote(editor: Editor, note: string) {
  const normalizedNote = normalizeFootnoteNote(note).trim();
  if (!normalizedNote) return;

  const selectedFootnote = getSelectedFootnote(editor);
  if (selectedFootnote) {
    editor.view.dispatch(
      editor.state.tr.setNodeMarkup(selectedFootnote.pos, undefined, {
        ...selectedFootnote.node.attrs,
        note: normalizedNote,
      })
    );
    return;
  }

  editor.chain().focus().insertContent({
    type: FOOTNOTE_NODE_NAME,
    attrs: {
      id: createFootnoteID(),
      note: normalizedNote,
      index: 0,
    },
  }).run();
}

function removeSelectedFootnote(editor: Editor) {
  const selectedFootnote = getSelectedFootnote(editor);
  if (!selectedFootnote) return;

  editor.commands.focus();
  editor.view.dispatch(
    editor.state.tr.delete(
      selectedFootnote.pos,
      selectedFootnote.pos + selectedFootnote.node.nodeSize
    )
  );
}

const Footnote = TiptapNode.create({
  name: FOOTNOTE_NODE_NAME,
  inline: true,
  group: 'inline',
  atom: true,
  selectable: true,
  draggable: true,

  addAttributes() {
    return {
      id: {
        default: null,
        parseHTML: (element: HTMLElement) => element.getAttribute('data-footnote-id') || createFootnoteID(),
        renderHTML: (attributes: Record<string, unknown>) => (
          attributes.id ? { 'data-footnote-id': attributes.id } : {}
        ),
      },
      note: {
        default: '',
        parseHTML: (element: HTMLElement) => normalizeFootnoteNote(
          element.getAttribute('data-footnote-note') || ''
        ),
        renderHTML: (attributes: Record<string, unknown>) => (
          attributes.note ? { 'data-footnote-note': attributes.note } : {}
        ),
      },
      index: {
        default: 0,
        parseHTML: (element: HTMLElement) => parseInt(
          element.getAttribute('data-footnote-index') || '0',
          10
        ) || 0,
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-footnote-index': String(attributes.index || 0),
        }),
      },
    };
  },

  parseHTML() {
    return [
      { tag: 'sup[data-footnote-id]' },
      { tag: 'sup[data-footnote-note]' },
    ];
  },

  renderHTML({ node, HTMLAttributes }) {
    const id = (node.attrs.id as string) || createFootnoteID();
    const index = String(node.attrs.index || '?');

    return [
      'sup',
      mergeAttributes(HTMLAttributes, {
        class: 'footnote-reference',
        contenteditable: 'false',
        title: (node.attrs.note as string) || '',
      }),
      ['a', { href: `#footnote-${id}` }, index],
    ];
  },

  addNodeView() {
    return ({ node, getPos, editor }) => {
      const element = document.createElement('sup');
      element.className = 'footnote-reference';
      element.contentEditable = 'false';
      element.draggable = true;

      const updateElement = (currentNode: any) => {
        element.textContent = String(currentNode.attrs.index || '?');
        element.title = 'Click to edit footnote. Drag to move it.';
        element.dataset.footnoteId = (currentNode.attrs.id as string) || '';
        element.dataset.footnoteIndex = String(currentNode.attrs.index || 0);
        element.dataset.footnoteNote = (currentNode.attrs.note as string) || '';
      };

      const handleClick = (event: MouseEvent) => {
        event.preventDefault();
        event.stopPropagation();

        if (typeof getPos !== 'function') return;
        const pos = getPos();
        if (typeof pos === 'number') {
          editor.view.dispatch(
            editor.state.tr.setSelection(NodeSelection.create(editor.state.doc, pos))
          );

          const id = (node.attrs.id as string) || '';
          if (id) {
            requestAnimationFrame(() => {
              focusFootnoteEditor(id);
            });
          }
        }
      };

      const handleDragStart = () => {
        if (typeof getPos !== 'function') return;
        const pos = getPos();
        if (typeof pos === 'number') {
          editor.view.dispatch(
            editor.state.tr.setSelection(NodeSelection.create(editor.state.doc, pos))
          );
        }
      };

      updateElement(node);
      element.addEventListener('click', handleClick);
      element.addEventListener('dragstart', handleDragStart);

      return {
        dom: element,
        update(updatedNode) {
          if (updatedNode.type.name !== FOOTNOTE_NODE_NAME) return false;
          updateElement(updatedNode);
          return true;
        },
        selectNode() {
          element.classList.add('is-selected');
        },
        deselectNode() {
          element.classList.remove('is-selected');
        },
        destroy() {
          element.removeEventListener('click', handleClick);
          element.removeEventListener('dragstart', handleDragStart);
        },
      };
    };
  },

  addProseMirrorPlugins() {
    const type = this.type;

    return [
      new Plugin({
        key: new PluginKey('footnoteSync'),
        appendTransaction(transactions, _oldState, newState) {
          if (!transactions.some((transaction) => transaction.docChanged)) {
            return null;
          }

          let transaction = newState.tr;
          let changed = false;
          let index = 1;

          newState.doc.descendants((node, pos) => {
            if (node.type !== type) return;

            const id = typeof node.attrs.id === 'string' && node.attrs.id.trim()
              ? node.attrs.id
              : createFootnoteID();
            const note = normalizeFootnoteNote(typeof node.attrs.note === 'string' ? node.attrs.note : '');

            if (node.attrs.id !== id || node.attrs.note !== note || node.attrs.index !== index) {
              transaction = transaction.setNodeMarkup(pos, type, {
                ...node.attrs,
                id,
                note,
                index,
              });
              changed = true;
            }

            index += 1;
          });

          return changed ? transaction : null;
        },
      }),
    ];
  },
});

const linkPreviewElement = document.getElementById('link-preview');
let linkPreviewHref = '';
let linkPreviewIsHovered = false;
let linkAnchorIsHovered = false;
let linkPreviewHideTimer: number | null = null;

function clearLinkPreviewHideTimer() {
  if (linkPreviewHideTimer !== null) {
    window.clearTimeout(linkPreviewHideTimer);
    linkPreviewHideTimer = null;
  }
}

function hideLinkPreview() {
  clearLinkPreviewHideTimer();
  linkPreviewHref = '';
  linkPreviewIsHovered = false;
  linkAnchorIsHovered = false;
  if (!linkPreviewElement) return;
  linkPreviewElement.classList.remove('is-visible');
  linkPreviewElement.setAttribute('aria-hidden', 'true');
}

function scheduleHideLinkPreview() {
  clearLinkPreviewHideTimer();
  linkPreviewHideTimer = window.setTimeout(() => {
    linkPreviewHideTimer = null;
    if (!linkPreviewIsHovered && !linkAnchorIsHovered) {
      hideLinkPreview();
    }
  }, 180);
}

function isLinkOpenable(href: string): boolean {
  if (!href) return false;
  try {
    const url = new URL(href, document.baseURI);
    return url.protocol === 'http:' || url.protocol === 'https:' || url.protocol === 'mailto:';
  } catch {
    return false;
  }
}

function openLinkInExternalApp(href: string) {
  if (!isLinkOpenable(href)) return;
  sendToSwift('openURL', { url: href });
}

function positionLinkPreview(event: MouseEvent) {
  if (!linkPreviewElement) return;

  const offset = 14;
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;
  const previewRect = linkPreviewElement.getBoundingClientRect();

  let left = event.clientX + offset;
  let top = event.clientY + offset;

  if (left + previewRect.width > viewportWidth - 12) {
    left = Math.max(12, viewportWidth - previewRect.width - 12);
  }

  if (top + previewRect.height > viewportHeight - 12) {
    top = Math.max(12, event.clientY - previewRect.height - offset);
  }

  linkPreviewElement.style.left = `${left}px`;
  linkPreviewElement.style.top = `${top}px`;
}

function showLinkPreview(anchor: HTMLAnchorElement, event: MouseEvent) {
  if (!linkPreviewElement) return;

  const href = anchor.getAttribute('href')?.trim() ?? '';
  if (!href) {
    hideLinkPreview();
    return;
  }

  linkAnchorIsHovered = true;
  clearLinkPreviewHideTimer();
  linkPreviewHref = href;
  linkPreviewElement.textContent = href;
  linkPreviewElement.classList.add('is-visible');
  linkPreviewElement.setAttribute('aria-hidden', 'false');
  linkPreviewElement.setAttribute('role', 'link');
  linkPreviewElement.setAttribute('title', 'Click to open · ⌘-click on link to open');
  positionLinkPreview(event);
}

function attachLinkHoverPreview(editor: Editor) {
  const root = editor.view.dom as HTMLElement;

  root.addEventListener('mousemove', (event) => {
    const target = event.target;
    if (!(target instanceof Element)) {
      linkAnchorIsHovered = false;
      scheduleHideLinkPreview();
      return;
    }

    const anchor = target.closest('a[href]');
    if (anchor instanceof HTMLAnchorElement && root.contains(anchor)) {
      showLinkPreview(anchor, event);
      return;
    }

    linkAnchorIsHovered = false;
    scheduleHideLinkPreview();
  });

  root.addEventListener('mouseleave', () => {
    linkAnchorIsHovered = false;
    scheduleHideLinkPreview();
  });

  root.addEventListener('mousedown', (event) => {
    if (event.target instanceof Element) {
      const anchor = event.target.closest('a[href]');
      if (anchor instanceof HTMLAnchorElement && root.contains(anchor) && event.metaKey) {
        event.preventDefault();
        event.stopPropagation();
        return;
      }
    }
    hideLinkPreview();
  });

  root.addEventListener('click', (event) => {
    if (!event.metaKey || event.button !== 0) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest('a[href]');
    if (!(anchor instanceof HTMLAnchorElement) || !root.contains(anchor)) return;
    const href = anchor.getAttribute('href')?.trim() ?? '';
    if (!href || !isLinkOpenable(href)) return;
    event.preventDefault();
    event.stopPropagation();
    openLinkInExternalApp(href);
    hideLinkPreview();
  });

  root.addEventListener('dragstart', hideLinkPreview);
  document.addEventListener('scroll', hideLinkPreview, true);

  if (linkPreviewElement) {
    linkPreviewElement.addEventListener('mouseenter', () => {
      linkPreviewIsHovered = true;
      clearLinkPreviewHideTimer();
    });
    linkPreviewElement.addEventListener('mouseleave', () => {
      linkPreviewIsHovered = false;
      scheduleHideLinkPreview();
    });
    linkPreviewElement.addEventListener('mousedown', (event) => {
      event.preventDefault();
      event.stopPropagation();
    });
    linkPreviewElement.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      const href = linkPreviewHref;
      hideLinkPreview();
      openLinkInExternalApp(href);
    });
  }
}

const MIN_IMAGE_WIDTH = 80;
const MIN_CROP_SIZE = 0.08;
const IMAGE_RESIZE_HANDLES: ImageHandleDirection[] = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];

function normalizeImageLayout(value: unknown): ImageLayout {
  return value === 'block' || value === 'float-left' || value === 'float-right' ? value : 'inline';
}

function normalizeImageAlign(value: unknown): ImageAlign {
  return value === 'left' || value === 'right' ? value : 'center';
}

function numericImageAttr(value: unknown, fallback: number): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = parseFloat(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function normalizedCropNumber(value: unknown, fallback: number): number {
  return Math.min(1, Math.max(0, numericImageAttr(value, fallback)));
}

function cropRectFromAttrs(attrs: Record<string, unknown>): ImageCropRect {
  const x = normalizedCropNumber(attrs.cropX, 0);
  const y = normalizedCropNumber(attrs.cropY, 0);
  const width = Math.min(1 - x, Math.max(MIN_CROP_SIZE, normalizedCropNumber(attrs.cropWidth, 1)));
  const height = Math.min(1 - y, Math.max(MIN_CROP_SIZE, normalizedCropNumber(attrs.cropHeight, 1)));

  return {
    x,
    y,
    width,
    height,
  };
}

function cropAttrsFromRect(crop: ImageCropRect): Record<string, number> {
  const normalized = constrainCropRect(crop);
  return {
    cropX: roundImageNumber(normalized.x),
    cropY: roundImageNumber(normalized.y),
    cropWidth: roundImageNumber(normalized.width),
    cropHeight: roundImageNumber(normalized.height),
  };
}

function cropDataAttrsFromRect(crop: ImageCropRect): Record<string, string> {
  const normalized = constrainCropRect(crop);
  return {
    'data-crop-x': String(roundImageNumber(normalized.x)),
    'data-crop-y': String(roundImageNumber(normalized.y)),
    'data-crop-width': String(roundImageNumber(normalized.width)),
    'data-crop-height': String(roundImageNumber(normalized.height)),
  };
}

function isDefaultCrop(crop: ImageCropRect): boolean {
  return crop.x <= 0.0001 &&
    crop.y <= 0.0001 &&
    crop.width >= 0.9999 &&
    crop.height >= 0.9999;
}

function constrainCropRect(crop: ImageCropRect): ImageCropRect {
  const x = Math.min(1 - MIN_CROP_SIZE, Math.max(0, crop.x));
  const y = Math.min(1 - MIN_CROP_SIZE, Math.max(0, crop.y));
  const width = Math.min(1 - x, Math.max(MIN_CROP_SIZE, crop.width));
  const height = Math.min(1 - y, Math.max(MIN_CROP_SIZE, crop.height));

  return { x, y, width, height };
}

function roundImageNumber(value: number): number {
  return Number(value.toFixed(4));
}

function dimensionFromHTMLElement(element: HTMLElement, attributeName: string): string | null {
  const styleValue = element.style.getPropertyValue(attributeName).trim();
  if (styleValue) return styleValue;

  const attributeValue = element.getAttribute(attributeName)?.trim();
  if (!attributeValue) return null;
  return /^\d+(\.\d+)?$/.test(attributeValue) ? `${attributeValue}px` : attributeValue;
}

function dimensionStyle(value: unknown): string | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return `${Math.round(value)}px`;
  }

  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function pixelDimension(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value !== 'string') return null;

  const trimmed = value.trim();
  const match = trimmed.match(/^(-?\d+(?:\.\d+)?)px$/);
  if (match) return parseFloat(match[1]);
  if (/^\d+(\.\d+)?$/.test(trimmed)) return parseFloat(trimmed);
  return null;
}

function pixelDimensionAttr(value: number): string {
  return `${Math.round(Math.max(MIN_IMAGE_WIDTH, value))}px`;
}

function imageLayoutStyleParts(layout: ImageLayout, align: ImageAlign): string[] {
  if (layout === 'float-left') {
    return ['float: left', 'display: block', 'margin: 0.35em 1em 0.65em 0'];
  }

  if (layout === 'float-right') {
    return ['float: right', 'display: block', 'margin: 0.35em 0 0.65em 1em'];
  }

  if (layout === 'block') {
    const margin =
      align === 'left'
        ? '0.75em auto 0.75em 0'
        : align === 'right'
          ? '0.75em 0 0.75em auto'
          : '0.75em auto';
    return ['display: block', `margin: ${margin}`];
  }

  return ['display: inline-block', 'vertical-align: baseline', 'margin: 0 0.15em'];
}

function insertedImageAttrs(src: string): Record<string, unknown> {
  return {
    src,
    layout: 'block',
    align: 'center',
  };
}

function selectedImageNode(editor: Editor): { node: any; pos: number } | null {
  const selection = editor.state.selection;
  if (!(selection instanceof NodeSelection)) return null;
  if (selection.node.type.name !== 'image') return null;
  return {
    node: selection.node,
    pos: selection.from,
  };
}

function updateSelectedImageAttrs(editor: Editor, attrs: Record<string, unknown>): boolean {
  const selected = selectedImageNode(editor);
  if (!selected) return false;

  const currentNode = editor.state.doc.nodeAt(selected.pos);
  if (!currentNode || currentNode.type.name !== 'image') return false;

  editor.view.dispatch(
    editor.state.tr.setNodeMarkup(selected.pos, undefined, {
      ...currentNode.attrs,
      ...attrs,
    })
  );
  editor.view.focus();
  return true;
}

function setSelectedImageLayout(editor: Editor, value: string): boolean {
  switch (value) {
    case 'block-left':
      return updateSelectedImageAttrs(editor, { layout: 'block', align: 'left' });
    case 'block-right':
      return updateSelectedImageAttrs(editor, { layout: 'block', align: 'right' });
    case 'block':
    case 'block-center':
      return updateSelectedImageAttrs(editor, { layout: 'block', align: 'center' });
    case 'float-left':
      return updateSelectedImageAttrs(editor, { layout: 'float-left', align: 'left' });
    case 'float-right':
      return updateSelectedImageAttrs(editor, { layout: 'float-right', align: 'right' });
    case 'inline':
      return updateSelectedImageAttrs(editor, { layout: 'inline', align: 'center' });
    default:
      return false;
  }
}

function resetSelectedImageCrop(editor: Editor): boolean {
  return updateSelectedImageAttrs(editor, {
    cropX: 0,
    cropY: 0,
    cropWidth: 1,
    cropHeight: 1,
  });
}

const DocumentImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      width: {
        default: null,
        parseHTML: (element: HTMLElement) => dimensionFromHTMLElement(element, 'width'),
        renderHTML: () => ({}),
      },
      height: {
        default: null,
        parseHTML: (element: HTMLElement) => dimensionFromHTMLElement(element, 'height'),
        renderHTML: () => ({}),
      },
      layout: {
        default: 'inline',
        parseHTML: (element: HTMLElement) => element.dataset.imageLayout || 'inline',
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-image-layout': normalizeImageLayout(attributes.layout),
        }),
      },
      align: {
        default: 'center',
        parseHTML: (element: HTMLElement) => element.dataset.imageAlign || 'center',
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-image-align': normalizeImageAlign(attributes.align),
        }),
      },
      cropX: {
        default: 0,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.cropX, 0),
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-crop-x': String(numericImageAttr(attributes.cropX, 0)),
        }),
      },
      cropY: {
        default: 0,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.cropY, 0),
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-crop-y': String(numericImageAttr(attributes.cropY, 0)),
        }),
      },
      cropWidth: {
        default: 1,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.cropWidth, 1),
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-crop-width': String(numericImageAttr(attributes.cropWidth, 1)),
        }),
      },
      cropHeight: {
        default: 1,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.cropHeight, 1),
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-crop-height': String(numericImageAttr(attributes.cropHeight, 1)),
        }),
      },
      naturalWidth: {
        default: null,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.naturalWidth, 0) || null,
        renderHTML: (attributes: Record<string, unknown>) => {
          const width = numericImageAttr(attributes.naturalWidth, 0);
          return width > 0 ? { 'data-natural-width': String(width) } : {};
        },
      },
      naturalHeight: {
        default: null,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.naturalHeight, 0) || null,
        renderHTML: (attributes: Record<string, unknown>) => {
          const height = numericImageAttr(attributes.naturalHeight, 0);
          return height > 0 ? { 'data-natural-height': String(height) } : {};
        },
      },
    };
  },
  renderHTML({ node, HTMLAttributes }) {
    const attrs = node.attrs as Record<string, unknown>;
    const layout = normalizeImageLayout(attrs.layout);
    const align = normalizeImageAlign(attrs.align);
    const crop = cropRectFromAttrs(attrs);
    const widthStyle = dimensionStyle(attrs.width);
    const heightStyle = dimensionStyle(attrs.height);
    const naturalWidth = numericImageAttr(attrs.naturalWidth, 0);
    const naturalHeight = numericImageAttr(attrs.naturalHeight, 0);
    const baseAttrs = mergeAttributes(this.options.HTMLAttributes, HTMLAttributes, {
      class: 'editor-image',
      'data-image-layout': layout,
      'data-image-align': align,
      ...cropDataAttrsFromRect(crop),
    });
    const existingStyle = typeof baseAttrs.style === 'string' ? baseAttrs.style : '';
    delete baseAttrs.style;

    if (!isDefaultCrop(crop)) {
      const widthPx = pixelDimension(attrs.width);
      if (widthPx && naturalWidth > 0 && naturalHeight > 0) {
        const frameHeight = widthPx * ((naturalHeight * crop.height) / (naturalWidth * crop.width));
        const imageWidth = widthPx / crop.width;
        const imageHeight = frameHeight / crop.height;
        const wrapperStyle = [
          existingStyle,
          ...imageLayoutStyleParts(layout, align),
          'position: relative',
          'overflow: hidden',
          'line-height: 0',
          `width: ${Math.round(widthPx)}px`,
          `height: ${Math.round(frameHeight)}px`,
        ].filter(Boolean).join('; ');
        const imgStyle = [
          'position: absolute',
          `left: ${Math.round(-crop.x * imageWidth)}px`,
          `top: ${Math.round(-crop.y * imageHeight)}px`,
          `width: ${Math.round(imageWidth)}px`,
          `height: ${Math.round(imageHeight)}px`,
          'max-width: none',
          'margin: 0',
        ].join('; ');

        return [
          'span',
          {
            class: 'editor-image-crop',
            style: wrapperStyle,
            'data-image-layout': layout,
            'data-image-align': align,
          },
          ['img', mergeAttributes(baseAttrs, { style: imgStyle })],
        ];
      }
    }

    const style = [
      existingStyle,
      ...imageLayoutStyleParts(layout, align),
      widthStyle ? `width: ${widthStyle}` : '',
      heightStyle ? `height: ${heightStyle}` : '',
    ].filter(Boolean).join('; ');

    return ['img', style ? mergeAttributes(baseAttrs, { style }) : baseAttrs];
  },
  addNodeView() {
    return ({ node, getPos, editor }) => {
      let currentNode = node;
      let isSelected = false;
      let isCropping = false;
      let draftWidth: number | null = null;
      let draftCrop: ImageCropRect | null = null;

      const container = document.createElement('span');
      container.className = 'document-image';
      container.contentEditable = 'false';

      const frame = document.createElement('span');
      frame.className = 'document-image-frame';
      container.appendChild(frame);

      const img = document.createElement('img');
      img.className = 'editor-image';
      frame.appendChild(img);

      const resizeHandles = IMAGE_RESIZE_HANDLES.map((direction) => {
        const handle = document.createElement('span');
        handle.className = `document-image-handle document-image-resize-handle document-image-handle-${direction}`;
        handle.dataset.direction = direction;
        container.appendChild(handle);
        return handle;
      });

      const cropHandles = IMAGE_RESIZE_HANDLES.map((direction) => {
        const handle = document.createElement('span');
        handle.className = `document-image-handle document-image-crop-handle document-image-handle-${direction}`;
        handle.dataset.direction = direction;
        frame.appendChild(handle);
        return handle;
      });

      const toolbar = document.createElement('span');
      toolbar.className = 'document-image-toolbar';
      container.appendChild(toolbar);

      const currentAttrs = (): Record<string, unknown> => ({
        ...currentNode.attrs,
        ...(draftWidth !== null ? { width: pixelDimensionAttr(draftWidth) } : {}),
        ...(draftCrop !== null ? cropAttrsFromRect(draftCrop) : {}),
      });

      const naturalSize = (attrs: Record<string, unknown>) => {
        const naturalWidth = numericImageAttr(attrs.naturalWidth, img.naturalWidth || 0);
        const naturalHeight = numericImageAttr(attrs.naturalHeight, img.naturalHeight || 0);
        if (naturalWidth <= 0 || naturalHeight <= 0) return null;
        return { width: naturalWidth, height: naturalHeight };
      };

      const measuredFrameWidth = (): number => {
        const rect = frame.getBoundingClientRect();
        if (rect.width > 0) return rect.width;
        const imageRect = img.getBoundingClientRect();
        if (imageRect.width > 0) return imageRect.width;
        return pixelDimension(currentAttrs().width) ?? MIN_IMAGE_WIDTH;
      };

      const imageMaxWidth = (): number => {
        const root = editor.view.dom as HTMLElement;
        const rootWidth = root.getBoundingClientRect().width;
        return Math.max(MIN_IMAGE_WIDTH, rootWidth || 720);
      };

      const selectImage = () => {
        if (typeof getPos !== 'function') return;
        const pos = getPos();
        if (typeof pos !== 'number') return;
        editor.view.dispatch(editor.state.tr.setSelection(NodeSelection.create(editor.state.doc, pos)));
        editor.view.focus();
      };

      const updateAttrs = (attrs: Record<string, unknown>) => {
        if (typeof getPos !== 'function') return;
        const pos = getPos();
        if (typeof pos !== 'number') return;
        const existingNode = editor.state.doc.nodeAt(pos);
        if (!existingNode || existingNode.type.name !== 'image') return;

        editor.view.dispatch(
          editor.state.tr.setNodeMarkup(pos, undefined, {
            ...existingNode.attrs,
            ...attrs,
          })
        );
        editor.view.focus();
      };

      const persistNaturalSize = (): Record<string, number> => {
        if (img.naturalWidth <= 0 || img.naturalHeight <= 0) return {};
        return {
          naturalWidth: img.naturalWidth,
          naturalHeight: img.naturalHeight,
        };
      };

      const render = () => {
        const attrs = currentAttrs();
        const layout = normalizeImageLayout(attrs.layout);
        const align = normalizeImageAlign(attrs.align);
        const crop = cropRectFromAttrs(attrs);
        const widthStyle = dimensionStyle(attrs.width);
        const widthPx = draftWidth ?? pixelDimension(attrs.width);
        const size = naturalSize(attrs);

        container.className = [
          'document-image',
          `document-image-layout-${layout}`,
          `document-image-align-${align}`,
          isSelected ? 'is-selected' : '',
          isCropping ? 'is-cropping' : '',
          !isDefaultCrop(crop) ? 'is-cropped' : '',
        ].filter(Boolean).join(' ');
        container.dataset.layout = layout;
        container.dataset.align = align;

        img.src = attrs.src as string;
        img.alt = (attrs.alt as string) || '';
        img.title = (attrs.title as string) || '';

        frame.style.width = draftWidth !== null ? `${Math.round(draftWidth)}px` : (widthStyle || '');

        if (!isDefaultCrop(crop) && size && widthPx) {
          const frameHeight = widthPx * ((size.height * crop.height) / (size.width * crop.width));
          const imageWidth = widthPx / crop.width;
          const imageHeight = frameHeight / crop.height;

          frame.style.height = `${Math.round(frameHeight)}px`;
          img.style.position = 'absolute';
          img.style.left = `${Math.round(-crop.x * imageWidth)}px`;
          img.style.top = `${Math.round(-crop.y * imageHeight)}px`;
          img.style.width = `${Math.round(imageWidth)}px`;
          img.style.height = `${Math.round(imageHeight)}px`;
          img.style.maxWidth = 'none';
        } else {
          frame.style.height = '';
          img.style.position = '';
          img.style.left = '';
          img.style.top = '';
          img.style.width = widthStyle ? '100%' : '';
          img.style.height = 'auto';
          img.style.maxWidth = '';
        }

        Array.from(toolbar.querySelectorAll<HTMLButtonElement>('button[data-image-command]')).forEach((button) => {
          const command = button.dataset.imageCommand || '';
          button.classList.toggle(
            'is-active',
            command === layout ||
              command === `${layout}-${align}` ||
              (command === 'block-center' && layout === 'block' && align === 'center') ||
              (command === 'crop' && isCropping)
          );
        });
      };

      const commitResize = () => {
        if (draftWidth === null) return;
        updateAttrs({
          width: pixelDimensionAttr(draftWidth),
          height: null,
          ...persistNaturalSize(),
        });
        draftWidth = null;
      };

      const startResize = (event: MouseEvent, direction: ImageHandleDirection) => {
        event.preventDefault();
        event.stopPropagation();
        selectImage();
        isCropping = false;

        const startX = event.clientX;
        const startY = event.clientY;
        const startWidth = measuredFrameWidth();
        const attrs = currentAttrs();
        const crop = cropRectFromAttrs(attrs);
        const size = naturalSize(attrs);
        const aspect = size ? (size.height * crop.height) / (size.width * crop.width) : 1;

        const onMouseMove = (moveEvent: MouseEvent) => {
          const dx = moveEvent.clientX - startX;
          const dy = moveEvent.clientY - startY;
          let delta = 0;

          if (direction.includes('e')) delta = dx;
          if (direction.includes('w')) delta = -dx;
          if (direction === 'n' || direction === 's') {
            delta = (direction === 'n' ? -dy : dy) / Math.max(aspect, 0.1);
          }

          draftWidth = Math.min(imageMaxWidth(), Math.max(MIN_IMAGE_WIDTH, startWidth + delta));
          render();
        };

        const onMouseUp = () => {
          document.removeEventListener('mousemove', onMouseMove);
          document.removeEventListener('mouseup', onMouseUp);
          commitResize();
        };

        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
      };

      const commitCrop = () => {
        if (!draftCrop) return;
        const width = pixelDimension(currentAttrs().width) ?? measuredFrameWidth();
        updateAttrs({
          width: pixelDimensionAttr(width),
          ...cropAttrsFromRect(draftCrop),
          ...persistNaturalSize(),
        });
        draftCrop = null;
      };

      const startCropHandleDrag = (event: MouseEvent, direction: ImageHandleDirection) => {
        if (!isCropping) return;
        event.preventDefault();
        event.stopPropagation();
        selectImage();

        const startX = event.clientX;
        const startY = event.clientY;
        const startCrop = cropRectFromAttrs(currentAttrs());
        const frameRect = frame.getBoundingClientRect();
        const frameWidth = Math.max(1, frameRect.width);
        const frameHeight = Math.max(1, frameRect.height);

        const onMouseMove = (moveEvent: MouseEvent) => {
          const dx = ((moveEvent.clientX - startX) / frameWidth) * startCrop.width;
          const dy = ((moveEvent.clientY - startY) / frameHeight) * startCrop.height;
          let next = { ...startCrop };

          if (direction.includes('w')) {
            const right = startCrop.x + startCrop.width;
            next.x = Math.min(right - MIN_CROP_SIZE, Math.max(0, startCrop.x + dx));
            next.width = right - next.x;
          }

          if (direction.includes('e')) {
            next.width = Math.min(1 - startCrop.x, Math.max(MIN_CROP_SIZE, startCrop.width + dx));
          }

          if (direction.includes('n')) {
            const bottom = startCrop.y + startCrop.height;
            next.y = Math.min(bottom - MIN_CROP_SIZE, Math.max(0, startCrop.y + dy));
            next.height = bottom - next.y;
          }

          if (direction.includes('s')) {
            next.height = Math.min(1 - startCrop.y, Math.max(MIN_CROP_SIZE, startCrop.height + dy));
          }

          draftCrop = constrainCropRect(next);
          render();
        };

        const onMouseUp = () => {
          document.removeEventListener('mousemove', onMouseMove);
          document.removeEventListener('mouseup', onMouseUp);
          commitCrop();
        };

        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
      };

      const startCropPan = (event: MouseEvent) => {
        if (!isCropping) return;
        if (event.target instanceof Element && event.target.closest('.document-image-handle, .document-image-toolbar')) {
          return;
        }

        event.preventDefault();
        event.stopPropagation();
        selectImage();

        const startX = event.clientX;
        const startY = event.clientY;
        const startCrop = cropRectFromAttrs(currentAttrs());
        const frameRect = frame.getBoundingClientRect();
        const frameWidth = Math.max(1, frameRect.width);
        const frameHeight = Math.max(1, frameRect.height);

        const onMouseMove = (moveEvent: MouseEvent) => {
          const dx = ((moveEvent.clientX - startX) / frameWidth) * startCrop.width;
          const dy = ((moveEvent.clientY - startY) / frameHeight) * startCrop.height;
          draftCrop = constrainCropRect({
            ...startCrop,
            x: Math.min(1 - startCrop.width, Math.max(0, startCrop.x - dx)),
            y: Math.min(1 - startCrop.height, Math.max(0, startCrop.y - dy)),
          });
          render();
        };

        const onMouseUp = () => {
          document.removeEventListener('mousemove', onMouseMove);
          document.removeEventListener('mouseup', onMouseUp);
          commitCrop();
        };

        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
      };

      const setLayout = (layout: ImageLayout, align: ImageAlign = 'center') => {
        updateAttrs({ layout, align });
      };

      const toggleCropMode = () => {
        selectImage();
        isCropping = !isCropping;
        if (isCropping && !pixelDimension(currentAttrs().width)) {
          updateAttrs({
            width: pixelDimensionAttr(measuredFrameWidth()),
            ...persistNaturalSize(),
          });
        }
        render();
      };

      const resetCrop = () => {
        isCropping = false;
        updateAttrs({
          cropX: 0,
          cropY: 0,
          cropWidth: 1,
          cropHeight: 1,
        });
      };

      const addToolbarButton = (
        command: string,
        label: string,
        title: string,
        action: () => void
      ) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.dataset.imageCommand = command;
        button.textContent = label;
        button.title = title;
        button.addEventListener('mousedown', (event) => {
          event.preventDefault();
          event.stopPropagation();
        });
        button.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          action();
        });
        toolbar.appendChild(button);
      };

      addToolbarButton('inline', 'Inline', 'Inline image', () => setLayout('inline', 'center'));
      addToolbarButton('block-center', 'Center', 'Centered image', () => setLayout('block', 'center'));
      addToolbarButton('float-left', 'Left', 'Float left', () => setLayout('float-left', 'left'));
      addToolbarButton('float-right', 'Right', 'Float right', () => setLayout('float-right', 'right'));
      addToolbarButton('crop', 'Crop', 'Crop image', toggleCropMode);
      addToolbarButton('reset-crop', 'Reset', 'Reset crop', resetCrop);

      const onContainerMouseDown = (event: MouseEvent) => {
        if (event.target instanceof Element && event.target.closest('.document-image-toolbar, .document-image-handle')) {
          return;
        }

        selectImage();
        if (isCropping) {
          startCropPan(event);
        }
      };

      const onImageLoad = () => {
        render();
      };

      container.addEventListener('mousedown', onContainerMouseDown);
      img.addEventListener('load', onImageLoad);

      resizeHandles.forEach((handle) => {
        handle.addEventListener('mousedown', (event) => {
          startResize(event, handle.dataset.direction as ImageHandleDirection);
        });
      });

      cropHandles.forEach((handle) => {
        handle.addEventListener('mousedown', (event) => {
          startCropHandleDrag(event, handle.dataset.direction as ImageHandleDirection);
        });
      });

      render();

      return {
        dom: container,
        update(updatedNode) {
          if (updatedNode.type.name !== 'image') return false;
          currentNode = updatedNode;
          draftWidth = null;
          draftCrop = null;
          render();
          return true;
        },
        selectNode() {
          isSelected = true;
          render();
        },
        deselectNode() {
          isSelected = false;
          isCropping = false;
          draftWidth = null;
          draftCrop = null;
          render();
        },
        stopEvent(event) {
          if (!(event.target instanceof Element)) return false;
          return Boolean(
            event.target.closest('.document-image-toolbar, .document-image-handle') ||
              (isCropping && event.type.startsWith('mouse'))
          );
        },
        destroy() {
          container.removeEventListener('mousedown', onContainerMouseDown);
          img.removeEventListener('load', onImageLoad);
        },
      };
    };
  },
});

let wordCountDebounceTimer: ReturnType<typeof setTimeout> | null = null;
let contentSyncDebounceTimer: ReturnType<typeof setTimeout> | null = null;
let footnotePanelDebounceTimer: ReturnType<typeof setTimeout> | null = null;
let selectionDebounceTimer: ReturnType<typeof setTimeout> | null = null;
let smartQuotesNormalizationFrame: number | null = null;

function countWords(text: string): number {
  const trimmed = text.trim();
  if (!trimmed) return 0;
  return trimmed.split(/\s+/).length;
}

function lastCharacter(text: string): string {
  return text.length > 0 ? text[text.length - 1] : '';
}

function isWhitespaceCharacter(character: string): boolean {
  return /\s/.test(character);
}

function isAlphaNumericCharacter(character: string): boolean {
  return /[A-Za-z0-9]/.test(character);
}

function isOpeningQuoteContext(character: string): boolean {
  return !character || isWhitespaceCharacter(character) || /[\([{<\u2013\u2014-]/.test(character) || character === '\u201C' || character === '\u2018';
}

function startsWithApostropheElision(text: string): boolean {
  const lower = text.toLowerCase();
  if (/^[a-z]'/.test(lower)) return true;
  return [
    'tis',
    'twas',
    'twere',
    'cause',
    'cuz',
    'em',
    'til',
    'bout',
    'round',
  ].some((prefix) => lower.startsWith(prefix));
}

function shouldOpenDoubleQuote(text: string, index: number, previousCharacter: string): boolean {
  const nextCharacter = text[index + 1] || '';
  if (!nextCharacter || isWhitespaceCharacter(nextCharacter)) return false;
  return isOpeningQuoteContext(previousCharacter);
}

function shouldOpenSingleQuote(text: string, index: number, previousCharacter: string): boolean {
  const nextCharacter = text[index + 1] || '';
  if (!nextCharacter || isWhitespaceCharacter(nextCharacter)) return false;
  if (isAlphaNumericCharacter(previousCharacter)) return false;
  if (/[0-9]/.test(nextCharacter)) return false;
  if (startsWithApostropheElision(text.slice(index + 1))) return false;
  return isOpeningQuoteContext(previousCharacter);
}

function smartifyQuotes(text: string): string {
  let result = '';

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    const previousCharacter = lastCharacter(result);

    if (character === '"') {
      result += shouldOpenDoubleQuote(text, index, previousCharacter) ? '\u201C' : '\u201D';
    } else if (character === "'") {
      result += shouldOpenSingleQuote(text, index, previousCharacter) ? '\u2018' : '\u2019';
    } else {
      result += character;
    }
  }

  return result;
}

function smartifyQuotesWithContext(text: string, contextBefore = ''): string {
  if (!text) return text;
  const syntheticPrefix = contextBefore || ' ';
  return smartifyQuotes(`${syntheticPrefix}${text}`).slice(syntheticPrefix.length);
}

function contextCharacterBefore(doc: any, pos: number): string {
  if (pos <= 0) return '';
  return doc.textBetween(Math.max(pos - 1, 0), pos, '', '');
}

function buildSmartQuotesNormalizationTransaction(state: any) {
  let transaction = state.tr;
  let changed = false;

  state.doc.descendants((node: any, pos: number) => {
    if (!node.isText || typeof node.text !== 'string') return;
    if (!node.text.includes('"') && !node.text.includes("'")) return;

    const converted = smartifyQuotesWithContext(
      node.text,
      contextCharacterBefore(state.doc, pos)
    );

    if (converted === node.text) return;

    transaction = transaction.replaceWith(
      pos,
      pos + node.nodeSize,
      state.schema.text(converted, node.marks)
    );
    changed = true;
  });

  if (!changed) {
    return null;
  }

  transaction.setMeta(SMART_QUOTES_TRANSACTION_META, true);
  return transaction;
}

function normalizeDocumentSmartQuotes(editor: Editor): boolean {
  const transaction = buildSmartQuotesNormalizationTransaction(editor.state);
  if (!transaction) {
    return false;
  }

  editor.view.dispatch(transaction);
  return true;
}

function scheduleSmartQuotesNormalization(editor: Editor) {
  if (smartQuotesNormalizationFrame !== null) {
    window.cancelAnimationFrame(smartQuotesNormalizationFrame);
  }

  smartQuotesNormalizationFrame = window.requestAnimationFrame(() => {
    smartQuotesNormalizationFrame = null;
    normalizeDocumentSmartQuotes(editor);
  });
}

/**
 * Parse an HTML string, convert straight quotes to curly in text nodes, return HTML.
 */
function smartifyHTMLQuotes(html: string): string {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  smartifyDOMTextNodes(parsed.body);
  return parsed.body.innerHTML;
}

/**
 * Apply smart quotes to all text nodes in a DOM tree (preserving HTML structure).
 */
function smartifyDOMTextNodes(root: Node, contextBefore = ''): void {
  const ownerDocument = root.ownerDocument ?? document;
  const walker = ownerDocument.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const textNodes: Text[] = [];
  let previousText = contextBefore;
  while (walker.nextNode()) {
    textNodes.push(walker.currentNode as Text);
  }
  for (const node of textNodes) {
    const converted = smartifyQuotesWithContext(node.data, lastCharacter(previousText));
    if (converted !== node.data) {
      node.data = converted;
    }
    previousText = converted;
  }
}

function smartifyHTMLFragment(html: string, contextBefore = ''): string {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  smartifyDOMTextNodes(parsed.body, contextBefore);
  return parsed.body.innerHTML;
}

function singleElementChildIgnoringWhitespace(root: HTMLElement): HTMLElement | null {
  let element: HTMLElement | null = null;

  for (const child of Array.from(root.childNodes)) {
    if (child.nodeType === Node.TEXT_NODE) {
      if (child.textContent?.trim()) return null;
      continue;
    }

    if (child instanceof HTMLElement) {
      if (element) return null;
      element = child;
      continue;
    }

    return null;
  }

  return element;
}

function unwrapSingleParagraphHTML(html: string): string {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  const onlyChild = singleElementChildIgnoringWhitespace(parsed.body);
  if (!onlyChild) return html;

  const tagName = onlyChild.tagName.toLowerCase();
  if (tagName !== 'p' && tagName !== 'div') return html;

  return onlyChild.innerHTML;
}

function isTextblockRange(ed: Editor, from: number, to: number): boolean {
  try {
    const resolvedFrom = ed.state.doc.resolve(from);
    const resolvedTo = ed.state.doc.resolve(Math.max(from, to));
    return resolvedFrom.sameParent(resolvedTo) && resolvedFrom.parent.isTextblock;
  } catch (_) {
    return false;
  }
}

function prepareReplacementHTMLForRange(
  ed: Editor,
  from: number,
  to: number,
  html: string
): string {
  const smartified = smartifyHTMLFragment(html, contextCharacterBefore(ed.state.doc, from));
  return isTextblockRange(ed, from, to)
    ? unwrapSingleParagraphHTML(smartified)
    : smartified;
}

const SmartQuotes = Extension.create({
  name: 'smartQuotes',

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: smartQuotesPluginKey,
        props: {
          handleTextInput(view, from, to, text) {
            const converted = smartifyQuotesWithContext(
              text,
              contextCharacterBefore(view.state.doc, from)
            );

            if (converted === text) {
              return false;
            }

            view.dispatch(view.state.tr.insertText(converted, from, to));
            return true;
          },
        },
        appendTransaction(transactions, _oldState, newState) {
          if (!transactions.some((transaction) => transaction.docChanged)) {
            return null;
          }

          if (transactions.some((transaction) => transaction.getMeta(SMART_QUOTES_TRANSACTION_META))) {
            return null;
          }
          return buildSmartQuotesNormalizationTransaction(newState);
        },
      }),
    ];
  },
});

const PASTE_STRIP_ATTRIBUTES = new Set([
  'style',
  'class',
  'id',
  'color',
  'bgcolor',
  'face',
  'size',
  'align',
  'lang',
  'dir',
  'width',
  'height',
  'cellpadding',
  'cellspacing',
  'border',
]);

const PASTE_PRESERVE_ATTRIBUTES_BY_TAG: Record<string, Set<string>> = {
  a: new Set(['href', 'title', 'target', 'rel']),
  img: new Set(['src', 'alt', 'title', 'width', 'height']),
  ol: new Set(['start', 'type']),
};

function shouldStripPastedAttribute(tagName: string, attrName: string): boolean {
  const lowered = attrName.toLowerCase();
  if (lowered.startsWith('on')) return true;
  if (lowered.startsWith('data-')) return false;
  const preserve = PASTE_PRESERVE_ATTRIBUTES_BY_TAG[tagName];
  if (preserve?.has(lowered)) return false;
  return PASTE_STRIP_ATTRIBUTES.has(lowered);
}

function sanitizePastedHTML(html: string, contextBefore = ''): string {
  const parsed = new DOMParser().parseFromString(stripGeneratedFootnotesSection(html), 'text/html');

  parsed.querySelectorAll(GENERATED_FOOTNOTES_SELECTOR).forEach((element) => element.remove());
  parsed.querySelectorAll('style, meta, link, script, noscript, title').forEach((element) => element.remove());

  parsed.body.querySelectorAll('*').forEach((element) => {
    const tagName = element.tagName.toLowerCase();
    Array.from(element.attributes).forEach((attribute) => {
      if (shouldStripPastedAttribute(tagName, attribute.name)) {
        element.removeAttribute(attribute.name);
      }
    });
  });

  smartifyDOMTextNodes(parsed.body, contextBefore);

  return parsed.body.innerHTML;
}

const editor = new Editor({
  element: document.getElementById('editor')!,
  extensions: [
    StarterKit.configure({
      heading: { levels: [1, 2, 3] },
    }),
    Underline,
    Placeholder.configure({
      placeholder: 'Start writing...',
    }),
    TextAlign.configure({
      types: ['heading', 'paragraph'],
    }),
    Typography,
    SmartQuotes,
    FontFamily,
    TextStyle,
    HoverableLink.configure({
      openOnClick: false,
      HTMLAttributes: {
        rel: 'noopener noreferrer',
        target: '_blank',
      },
    }),
    Color,
    Footnote,
    DocumentImage.configure({
      inline: true,
      allowBase64: true,
    }),
    CommentMark,
    SearchHighlight,
    PendingEditHighlight,
    Extension.create({
      name: 'imagePasteHandler',
      addProseMirrorPlugins() {
        const editorRef = editor;
        return [
          new Plugin({
            props: {
              handlePaste(_view, event) {
                const items = event.clipboardData?.items;
                if (!items) return false;
                for (const item of Array.from(items)) {
                  if (item.type.startsWith('image/')) {
                    event.preventDefault();
                    const file = item.getAsFile();
                    if (!file) continue;
                    const reader = new FileReader();
                    reader.onload = (e) => {
                      const src = e.target?.result as string;
                      editorRef.chain().focus().insertContent({
                        type: 'image',
                        attrs: insertedImageAttrs(src),
                      }).run();
                    };
                    reader.readAsDataURL(file);
                    return true;
                  }
                }
                return false;
              },
              handleDrop(view, event) {
                const files = event.dataTransfer?.files;
                if (!files || files.length === 0) return false;
                for (const file of Array.from(files)) {
                  if (file.type.startsWith('image/')) {
                    event.preventDefault();
                    const reader = new FileReader();
                    reader.onload = (e) => {
                      const src = e.target?.result as string;
                      const coords = view.posAtCoords({
                        left: event.clientX,
                        top: event.clientY,
                      });
                      if (coords) {
                        const tr = view.state.tr.insert(
                          coords.pos,
                          view.state.schema.nodes.image.create(insertedImageAttrs(src))
                        );
                        view.dispatch(tr);
                      } else {
                        editorRef.chain().focus().insertContent({
                          type: 'image',
                          attrs: insertedImageAttrs(src),
                        }).run();
                      }
                    };
                    reader.readAsDataURL(file);
                    return true;
                  }
                }
                return false;
              },
            },
          }),
        ];
      },
    }),
  ],
  content: '',
  autofocus: true,
  editorProps: {
    attributes: {
      class: 'editor-content',
      spellcheck: 'true',
      autocorrect: 'on',
    },
    transformPastedHTML(html, view) {
      return sanitizePastedHTML(html, contextCharacterBefore(view.state.doc, view.state.selection.from));
    },
    transformPastedText(text, _plain, view) {
      return smartifyQuotesWithContext(text, contextCharacterBefore(view.state.doc, view.state.selection.from));
    },
  },
  onUpdate({ editor }) {
    invalidateDerivedDocumentState();
    updatePreservedTextSelection(editor);
    scheduleSelectionUpdate(editor);
    scheduleWordCountUpdate(editor);
    scheduleContentUpdate(editor);
    scheduleFootnotesPanelRender(editor);
    emitCommentsChanged(editor, false, true);
  },
  onSelectionUpdate({ editor }) {
    updatePreservedTextSelection(editor);
    scheduleSelectionUpdate(editor);
  },
});

function setEditorSpellcheckEnabled(enabled: boolean) {
  const dom = editor.view.dom as HTMLElement;
  dom.setAttribute('spellcheck', enabled ? 'true' : 'false');
}

function setEditorAutocorrectEnabled(enabled: boolean) {
  const dom = editor.view.dom as HTMLElement;
  dom.setAttribute('autocorrect', enabled ? 'on' : 'off');
}

// Register callbacks for Swift to call into JS
registerSwiftCallbacks({
  loadContent(html: string) {
    resetEditorSyncState();
    rejectAllPendingEdits(editor);
    editor.commands.setContent(stripGeneratedFootnotesSection(html), false);
    normalizeDocumentSmartQuotes(editor);
    renderFootnotesPanel(editor, true);
    emitWordCountUpdate(editor);
    emitSelectionUpdate(editor);
    emitCommentsChanged(editor, true);
  },
  loadJSONContent(json: string) {
    resetEditorSyncState();
    try {
      rejectAllPendingEdits(editor);
      const parsed = JSON.parse(json);
      editor.commands.setContent(parsed, false);
      normalizeDocumentSmartQuotes(editor);
      renderFootnotesPanel(editor, true);
      emitWordCountUpdate(editor);
      emitSelectionUpdate(editor);
      emitCommentsChanged(editor, true);
    } catch (error) {
      console.error('Failed to load JSON content into editor', error);
    }
  },
  getContent(): string {
    return serializeDocumentHTML(editor);
  },
  getDocumentSnapshot(): string {
    const snapshot = getDocumentTextSnapshot(editor);
    return JSON.stringify({
      html: serializeDocumentHTML(editor),
      json: editor.getJSON(),
      text: snapshot.plainText,
      words: snapshot.words,
      characters: snapshot.characters,
    });
  },
  getPlainText(): string {
    return serializeDocumentPlainText(editor);
  },
  getSelectionClipboardData(): string {
    return JSON.stringify(serializeSelectionClipboardData(editor));
  },
  applyFormat(command: string, value?: string) {
    switch (command) {
      case 'bold':
        editor.chain().focus().toggleBold().run();
        break;
      case 'italic':
        editor.chain().focus().toggleItalic().run();
        break;
      case 'underline':
        editor.chain().focus().toggleUnderline().run();
        break;
      case 'strike':
        editor.chain().focus().toggleStrike().run();
        break;
      case 'heading':
        const level = parseInt(value || '1') as 1 | 2 | 3;
        editor.chain().focus().toggleHeading({ level }).run();
        break;
      case 'paragraph':
        editor.chain().focus().setParagraph().run();
        break;
      case 'bulletList':
        editor.chain().focus().toggleBulletList().run();
        break;
      case 'orderedList':
        editor.chain().focus().toggleOrderedList().run();
        break;
      case 'blockquote':
        editor.chain().focus().toggleBlockquote().run();
        break;
      case 'horizontalRule':
        editor.chain().focus().setHorizontalRule().run();
        break;
      case 'alignLeft':
        editor.chain().focus().setTextAlign('left').run();
        break;
      case 'alignCenter':
        editor.chain().focus().setTextAlign('center').run();
        break;
      case 'alignRight':
        editor.chain().focus().setTextAlign('right').run();
        break;
      case 'alignJustify':
        editor.chain().focus().setTextAlign('justify').run();
        break;
      case 'fontFamily':
        if (value) editor.chain().focus().setFontFamily(value).run();
        break;
      case 'undo':
        editor.chain().focus().undo().run();
        break;
      case 'redo':
        editor.chain().focus().redo().run();
        break;
      case 'insertImage':
        if (value) {
          editor.chain().focus().insertContent({
            type: 'image',
            attrs: insertedImageAttrs(value),
          }).run();
        }
        break;
      case 'setImageLayout':
        if (value) setSelectedImageLayout(editor, value);
        break;
      case 'resetImageCrop':
        resetSelectedImageCrop(editor);
        break;
      case 'setLink':
        if (value) {
          editor.chain().focus().extendMarkRange('link').setLink({ href: value }).run();
        }
        break;
      case 'unlink':
        editor.chain().focus().unsetLink().run();
        break;
      case 'setFootnote':
        if (value) {
          upsertFootnote(editor, value);
        }
        break;
      case 'removeFootnote':
        removeSelectedFootnote(editor);
        break;
      case 'setColor':
        if (value) editor.chain().focus().setColor(value).run();
        break;
      case 'unsetColor':
        editor.chain().focus().unsetColor().run();
        break;
      case 'toggleColor':
        if (value) {
          if (editor.isActive('textStyle', { color: value })) {
            editor.chain().focus().unsetColor().run();
          } else {
            editor.chain().focus().setColor(value).run();
          }
        }
        break;
    }
  },
  focus() {
    editor.commands.focus();
  },
  setSpellcheckEnabled(enabled: boolean) {
    setEditorSpellcheckEnabled(enabled);
  },
  setAutocorrectEnabled(enabled: boolean) {
    setEditorAutocorrectEnabled(enabled);
  },
  setEditable(editable: boolean) {
    editor.setEditable(editable);
  },
  getSelectedText(): string {
    const { from, to } = editor.state.selection;
    return editor.state.doc.textBetween(from, to, ' ');
  },
  setThemeCSS(css: string) {
    let styleEl = document.getElementById('dynamic-theme');
    if (!styleEl) {
      styleEl = document.createElement('style');
      styleEl.id = 'dynamic-theme';
      document.head.appendChild(styleEl);
    }
    styleEl.textContent = css;
  },
  findInDocument(query: string): number {
    activeSearchQuery = query;
    searchResults = findTextInDoc(editor.state.doc, query, MAX_SEARCH_RESULTS);
    currentMatchIdx = searchResults.length > 0 ? 0 : -1;
    updateSearchDecorations(editor);
    if (currentMatchIdx >= 0) scrollToMatch(editor, searchResults[currentMatchIdx]);
    return searchResults.length;
  },
  findNext(): string {
    if (searchResults.length === 0) return JSON.stringify({ index: -1, total: 0 });
    currentMatchIdx = (currentMatchIdx + 1) % searchResults.length;
    updateSearchDecorations(editor);
    scrollToMatch(editor, searchResults[currentMatchIdx]);
    return JSON.stringify({ index: currentMatchIdx, total: searchResults.length });
  },
  findPrevious(): string {
    if (searchResults.length === 0) return JSON.stringify({ index: -1, total: 0 });
    currentMatchIdx = (currentMatchIdx - 1 + searchResults.length) % searchResults.length;
    updateSearchDecorations(editor);
    scrollToMatch(editor, searchResults[currentMatchIdx]);
    return JSON.stringify({ index: currentMatchIdx, total: searchResults.length });
  },
  replaceOne(replacement: string): string {
    if (currentMatchIdx < 0 || currentMatchIdx >= searchResults.length) {
      return JSON.stringify({ index: -1, total: 0 });
    }
    const match = searchResults[currentMatchIdx];
    const tr = editor.state.tr.insertText(replacement, match.from, match.to);
    editor.view.dispatch(tr);
    normalizeDocumentSmartQuotes(editor);
    // Re-search after replacement
    searchResults = findTextInDoc(editor.state.doc, activeSearchQuery);
    if (searchResults.length === 0) {
      currentMatchIdx = -1;
    } else {
      currentMatchIdx = Math.min(currentMatchIdx, searchResults.length - 1);
    }
    updateSearchDecorations(editor);
    if (currentMatchIdx >= 0) scrollToMatch(editor, searchResults[currentMatchIdx]);
    return JSON.stringify({ index: currentMatchIdx, total: searchResults.length });
  },
  replaceAll(replacement: string): number {
    if (searchResults.length === 0) return 0;
    const count = searchResults.length;
    // Replace from end to start to preserve positions
    let tr = editor.state.tr;
    for (let i = searchResults.length - 1; i >= 0; i--) {
      tr = tr.insertText(replacement, searchResults[i].from, searchResults[i].to);
    }
    editor.view.dispatch(tr);
    normalizeDocumentSmartQuotes(editor);
    searchResults = [];
    currentMatchIdx = -1;
    activeSearchQuery = '';
    updateSearchDecorations(editor);
    return count;
  },
  clearFind() {
    searchResults = [];
    currentMatchIdx = -1;
    activeSearchQuery = '';
    updateSearchDecorations(editor);
  },
  deleteSelection() {
    editor.commands.focus();
    editor.view.dispatch(editor.state.tr.deleteSelection());
  },
  replaceSelectionHTML(html: string) {
    const { from } = editor.state.selection;
    editor.chain().focus().insertContent(
      smartifyHTMLFragment(html, contextCharacterBefore(editor.state.doc, from))
    ).run();
    normalizeDocumentSmartQuotes(editor);
  },
  insertHTMLAtCursor(html: string) {
    const { from } = editor.state.selection;
    editor.chain().focus().insertContent(
      smartifyHTMLFragment(html, contextCharacterBefore(editor.state.doc, from))
    ).run();
    normalizeDocumentSmartQuotes(editor);
  },
  findAndReplaceText(find: string, replaceHtml: string, replaceAllOccurrences: boolean): number {
    const maxMatches = replaceAllOccurrences ? MAX_PENDING_FIND_REPLACE_MATCHES + 1 : 2;
    const matches = findTextInDoc(editor.state.doc, find, maxMatches);
    if (matches.length === 0) return 0;
    if (!replaceAllOccurrences && matches.length > 1) {
      return AMBIGUOUS_EDIT_TARGET;
    }
    if (replaceAllOccurrences && matches.length > MAX_PENDING_FIND_REPLACE_MATCHES) {
      return TOO_MANY_MATCHES;
    }
    const toReplace = replaceAllOccurrences ? matches : [matches[0]];
    // Replace from end to start to preserve positions
    for (let i = toReplace.length - 1; i >= 0; i--) {
      const normalizedReplaceHtml = prepareReplacementHTMLForRange(
        editor,
        toReplace[i].from,
        toReplace[i].to,
        replaceHtml,
      );
      editor.chain()
        .insertContentAt({ from: toReplace[i].from, to: toReplace[i].to }, normalizedReplaceHtml)
        .run();
    }
    normalizeDocumentSmartQuotes(editor);
    return toReplace.length;
  },

  // --- Pending Edits API (Cursor-like diff review) ---
  pendingReplaceSelection(id: string, newHtml: string, target?: SelectionEditTarget): number {
    const targetedRange = rangeFromSelectionTarget(editor, target ?? null);
    if (typeof targetedRange === 'number') return targetedRange;

    const { from, to } = targetedRange ?? editor.state.selection;
    if (from === to) return 0;
    return queuePendingEdits(editor, [
      createPendingEdit(editor, {
        id,
        groupId: id,
        kind: 'selection',
        from,
        to,
        newHtml,
      }),
    ], id);
  },
  pendingInsertAtCursor(id: string, newHtml: string, target?: SelectionEditTarget): number {
    const targetedPosition = positionFromInsertionTarget(editor, target ?? null);
    if (targetedPosition === STALE_EDIT_TARGET || targetedPosition === INVALID_EDIT_TARGET) {
      return targetedPosition;
    }

    const from = targetedPosition ?? editor.state.selection.from;
    return queuePendingEdits(editor, [
      createPendingEdit(editor, {
        id,
        groupId: id,
        kind: 'insert',
        from,
        to: from,
        newHtml,
      }),
    ], id);
  },
  pendingFindAndReplace(id: string, find: string, replaceHtml: string, replaceAll: boolean): number {
    const maxMatches = replaceAll ? MAX_PENDING_FIND_REPLACE_MATCHES + 1 : 2;
    const matches = findTextInDoc(editor.state.doc, find, maxMatches);
    if (matches.length === 0) return 0;
    if (!replaceAll && matches.length > 1) {
      return AMBIGUOUS_EDIT_TARGET;
    }
    if (replaceAll && matches.length > MAX_PENDING_FIND_REPLACE_MATCHES) {
      return TOO_MANY_MATCHES;
    }
    const toAdd = replaceAll ? matches : [matches[0]];
    if (!replaceAll) {
      const splitEdits = sentenceSplitPendingEdits(editor, id, matches[0], replaceHtml);
      if (splitEdits.length > 0) {
        return queuePendingEdits(editor, splitEdits, splitEdits[0]?.id ?? null);
      }
    }
    const edits = toAdd.map((match, i) => createPendingEdit(editor, {
      id: replaceAll ? `${id}_${i}` : id,
      groupId: id,
      kind: 'findReplace',
      from: match.from,
      to: match.to,
      newHtml: replaceHtml,
    }));
    return queuePendingEdits(editor, edits, edits[0]?.id ?? null);
  },
  pendingProposeEdit(
    id: string,
    target: ProposedEditTarget,
    replaceHtml: string,
    replaceAll: boolean
  ): number {
    return queueProposedEdit(editor, id, target ?? {}, replaceHtml, replaceAll);
  },
  acceptAllPendingEdits() { acceptAllPendingEdits(editor); },
  rejectAllPendingEdits() { rejectAllPendingEdits(editor); },
  acceptPendingEdit(id: string): boolean { return acceptPendingEdit(editor, id); },
  rejectPendingEdit(id: string): boolean { return rejectPendingEdit(editor, id); },
  focusPendingEdit(id: string): boolean { return focusPendingEdit(editor, id); },
  focusNextPendingEdit(): boolean { return focusRelativePendingEdit(editor, 1); },
  focusPreviousPendingEdit(): boolean { return focusRelativePendingEdit(editor, -1); },
  getPendingEdits(): string { return pendingEditsSummaryJSON(getPendingEditsState(editor.state)); },
  getPendingEditCount(): number { return getPendingEditsState(editor.state).edits.length; },
  getEditContextSnapshot(): string { return JSON.stringify(buildEditContextSnapshot(editor)); },
  addComment(commentId: string): boolean { return addComment(editor, commentId); },
  addCommentAtRange(commentJSON: string): boolean { return addCommentAtRangeFromJSON(editor, commentJSON); },
  updateCommentText(commentId: string, text: string) { updateCommentText(editor, commentId, text); },
  setCommentStatus(commentId: string, status: string) { setCommentStatus(editor, commentId, status); },
  removeComment(commentId: string) { removeComment(editor, commentId); },
  focusComment(commentId: string) { focusComment(editor, commentId); },
  pendingReplaceComment(commentId: string, editId: string, html: string): number {
    return pendingReplaceComment(editor, commentId, editId, html);
  },
  getComments(): string { return JSON.stringify(collectComments(editor)); },
});

attachLinkHoverPreview(editor);
attachCommentActivation(editor);
attachSelectionChangeFallback(editor);
attachSmartQuotesNormalizationFallback(editor);
renderFootnotesPanel(editor);
emitCommentsChanged(editor, true);

// Notify Swift that editor is ready
sendToSwift('editorReady', {});
