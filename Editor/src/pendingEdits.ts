import { Editor, Extension } from '@tiptap/core';
import { Plugin, PluginKey, TextSelection } from '@tiptap/pm/state';
import { Decoration, DecorationSet, EditorView } from '@tiptap/pm/view';
import { sendToSwift } from './bridge';
import { getEditorInstance } from './instance';
import {
  ACCEPTED_LLM_EDIT_COLOR,
  AMBIGUOUS_EDIT_TARGET,
  EditContextBlock,
  INVALID_EDIT_TARGET,
  MAX_PENDING_EDITS,
  MAX_PENDING_FIND_REPLACE_MATCHES,
  PendingEdit,
  PendingEditKind,
  PendingEditMetadata,
  ProposedEditTarget,
  STALE_EDIT_TARGET,
  SearchMatch,
  SelectionEditTarget,
  SentenceRange,
  TOO_MANY_MATCHES,
  TOO_MANY_PENDING_EDITS,
} from './types';
import { escapeHTML, hashString, plainTextFromHTML } from './utils';
import { findTextInDoc, normalizeSearchQuery } from './search';
import {
  contextCharacterBefore,
  prepareReplacementHTMLForRange,
  scheduleSmartQuotesNormalization,
  smartifyHTMLFragment,
} from './smartQuotes';
import {
  getDocumentRevision,
  mapPositionFromRevision,
  mapRangeFromRevision,
  serializeDocumentPlainText,
} from './docSync';
import { buildEditBlockIndex } from './editContext';

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


function inferPendingEditSource(id: string): string {
  if (id.startsWith('edit_')) return 'Assistant';
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

export function createPendingEdit(
  ed: Editor,
  options: {
    id: string;
    groupId: string;
    kind: PendingEditKind;
    from: number;
    to: number;
    newHtml: string;
    metadata?: PendingEditMetadata;
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
    learningCategory: options.metadata?.learningCategory ?? '',
    rationale: options.metadata?.rationale ?? '',
    instruction: options.metadata?.instruction ?? '',
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
    focusPendingEdit(getEditorInstance(), edit.id);
  });

  const previewContent = document.createElement('span');
  previewContent.className = 'pending-edit-preview-content';
  if (edit.status === 'conflicted') {
    previewContent.textContent = 'Conflict';
  } else if (edit.newHtml.trim().length > 0) {
    previewContent.textContent = edit.replacementText || 'Rich content';
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
      acceptPendingEdit(getEditorInstance(), edit.id);
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
    rejectPendingEdit(getEditorInstance(), edit.id);
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

export function getPendingEditsState(state: any): PendingEditsPluginState {
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

export function queuePendingEdits(
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
    target.document_revision !== getDocumentRevision()
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

export function rangeFromSelectionTarget(ed: Editor, target: SelectionEditTarget | null): SearchMatch | number | null {
  if (!target) return null;

  const from = typeof target.from === 'number' ? target.from : -1;
  const to = typeof target.to === 'number' ? target.to : -1;
  if (from < 0 || to <= from) return INVALID_EDIT_TARGET;

  // If the document changed since the target was captured, map its positions
  // forward through the intervening transactions; the text check below
  // verifies the mapped range still holds the same content.
  let range: SearchMatch = { from, to };
  const revision = typeof target.document_revision === 'number' ? target.document_revision : null;
  if (revision !== null && revision !== getDocumentRevision()) {
    const mapped = mapRangeFromRevision(revision, from, to);
    if (!mapped) return STALE_EDIT_TARGET;
    range = mapped;
  } else if (revision === null && !targetDocumentIsCurrent(ed, target)) {
    return STALE_EDIT_TARGET;
  }

  if (range.to > ed.state.doc.content.size) return INVALID_EDIT_TARGET;

  if (typeof target.text === 'string') {
    const currentText = ed.state.doc.textBetween(range.from, range.to, '\n', '\n');
    if (currentText !== target.text) return STALE_EDIT_TARGET;
  }

  return range;
}

export function positionFromInsertionTarget(ed: Editor, target: SelectionEditTarget | null): number | null {
  if (!target) return null;

  let position = typeof target.position === 'number'
    ? target.position
    : (typeof target.from === 'number' ? target.from : -1);
  if (position < 0) return INVALID_EDIT_TARGET;

  const revision = typeof target.document_revision === 'number' ? target.document_revision : null;
  if (revision !== null && revision !== getDocumentRevision()) {
    const mapped = mapPositionFromRevision(revision, position, 1);
    if (mapped === null) return STALE_EDIT_TARGET;
    position = mapped;
  } else if (revision === null && !targetDocumentIsCurrent(ed, target)) {
    return STALE_EDIT_TARGET;
  }

  if (position > ed.state.doc.content.size) return INVALID_EDIT_TARGET;
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
  // Content-addressed targets locate text by exact_original plus
  // prefix/suffix context, so a stale document_revision/document_hash is not
  // a failure: we simply re-resolve against the current document. This lets
  // the user keep typing while assistant edits stream in.
  const exactOriginal = target.exact_original ?? '';
  if (!normalizeSearchQuery(exactOriginal)) return INVALID_EDIT_TARGET;

  let scope: SearchMatch | null = null;
  if (target.block_id) {
    const block = findEditContextBlock(ed, target.block_id);
    if (block) {
      scope = { from: block.from, to: block.to };
    } else if (targetDocumentIsCurrent(ed, target)) {
      // The document is unchanged, so the block id itself is bogus.
      return STALE_EDIT_TARGET;
    }
    // Otherwise the block moved or was edited since the snapshot; fall back
    // to an unscoped search and rely on prefix/suffix disambiguation.
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

function containsBlockLevelMarkup(html: string): boolean {
  return /<\/?(address|article|aside|blockquote|dd|div|dl|dt|figcaption|figure|footer|h[1-6]|header|hr|li|main|nav|ol|p|pre|section|table|tbody|td|th|thead|tr|ul)\b/i.test(html);
}

function textFromHTMLPreservingWhitespace(html: string): string {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  return (parsed.body.textContent || '').replace(/\u00a0/g, ' ');
}

interface DiffToken {
  text: string;
  start: number;
  end: number;
}

interface DiffOp {
  type: 'equal' | 'insert' | 'delete';
  oldIndex: number;
  newIndex: number;
}

interface DiffSegment {
  type: 'equal' | 'change';
  oldStart: number;
  oldEnd: number;
  newStart: number;
  newEnd: number;
}

function nonWhitespaceTokens(text: string): DiffToken[] {
  const tokens: DiffToken[] = [];
  const regex = /\S+/g;
  let match: RegExpExecArray | null;

  while ((match = regex.exec(text)) !== null) {
    tokens.push({
      text: match[0],
      start: match.index,
      end: match.index + match[0].length,
    });
  }

  return tokens;
}

function diffTokenOps(oldTokens: DiffToken[], newTokens: DiffToken[]): DiffOp[] {
  const rows = oldTokens.length + 1;
  const columns = newTokens.length + 1;
  const table: number[][] = Array.from({ length: rows }, () => Array(columns).fill(0));

  for (let i = oldTokens.length - 1; i >= 0; i -= 1) {
    for (let j = newTokens.length - 1; j >= 0; j -= 1) {
      if (oldTokens[i].text === newTokens[j].text) {
        table[i][j] = table[i + 1][j + 1] + 1;
      } else {
        table[i][j] = Math.max(table[i + 1][j], table[i][j + 1]);
      }
    }
  }

  const ops: DiffOp[] = [];
  let oldIndex = 0;
  let newIndex = 0;
  while (oldIndex < oldTokens.length && newIndex < newTokens.length) {
    if (oldTokens[oldIndex].text === newTokens[newIndex].text) {
      ops.push({ type: 'equal', oldIndex, newIndex });
      oldIndex += 1;
      newIndex += 1;
    } else if (table[oldIndex + 1][newIndex] >= table[oldIndex][newIndex + 1]) {
      ops.push({ type: 'delete', oldIndex, newIndex });
      oldIndex += 1;
    } else {
      ops.push({ type: 'insert', oldIndex, newIndex });
      newIndex += 1;
    }
  }

  while (oldIndex < oldTokens.length) {
    ops.push({ type: 'delete', oldIndex, newIndex });
    oldIndex += 1;
  }

  while (newIndex < newTokens.length) {
    ops.push({ type: 'insert', oldIndex, newIndex });
    newIndex += 1;
  }

  return ops;
}

function pushDiffSegment(
  segments: DiffSegment[],
  type: DiffSegment['type'],
  oldStart: number,
  oldEnd: number,
  newStart: number,
  newEnd: number
) {
  if (oldStart === oldEnd && newStart === newEnd) return;

  const previous = segments[segments.length - 1];
  if (previous && previous.type === type) {
    previous.oldEnd = oldEnd;
    previous.newEnd = newEnd;
    return;
  }

  segments.push({ type, oldStart, oldEnd, newStart, newEnd });
}

function diffSegments(oldTokens: DiffToken[], newTokens: DiffToken[]): DiffSegment[] {
  const segments: DiffSegment[] = [];
  for (const op of diffTokenOps(oldTokens, newTokens)) {
    if (op.type === 'equal') {
      pushDiffSegment(segments, 'equal', op.oldIndex, op.oldIndex + 1, op.newIndex, op.newIndex + 1);
    } else if (op.type === 'delete') {
      pushDiffSegment(segments, 'change', op.oldIndex, op.oldIndex + 1, op.newIndex, op.newIndex);
    } else {
      pushDiffSegment(segments, 'change', op.oldIndex, op.oldIndex, op.newIndex, op.newIndex + 1);
    }
  }
  return segments;
}

function coalescedChangesFromSegments(segments: DiffSegment[], unchangedTokenThreshold = 3): DiffSegment[] {
  const changes: DiffSegment[] = [];
  let pending: DiffSegment | null = null;
  let unchangedSincePending = 0;

  for (const segment of segments) {
    if (segment.type === 'equal') {
      if (pending) {
        unchangedSincePending += segment.oldEnd - segment.oldStart;
      }
      continue;
    }

    if (!pending) {
      pending = { ...segment };
      unchangedSincePending = 0;
      continue;
    }

    if (unchangedSincePending < unchangedTokenThreshold) {
      pending.oldEnd = segment.oldEnd;
      pending.newEnd = segment.newEnd;
    } else {
      changes.push(pending);
      pending = { ...segment };
    }
    unchangedSincePending = 0;
  }

  if (pending) changes.push(pending);
  return changes;
}

function docPositionAtTextOffset(doc: any, from: number, to: number, offset: number): number | null {
  if (offset <= 0) return from;

  let textOffset = 0;
  let found: number | null = null;

  doc.nodesBetween(from, to, (node: any, pos: number) => {
    if (found !== null) return false;

    if (node.isText && typeof node.text === 'string') {
      const start = Math.max(from, pos);
      const end = Math.min(to, pos + node.text.length);
      if (end <= start) return undefined;

      const nodeStart = start - pos;
      const nodeEnd = end - pos;
      const length = nodeEnd - nodeStart;
      if (textOffset + length >= offset) {
        found = start + (offset - textOffset);
        return false;
      }

      textOffset += length;
      return undefined;
    }

    if (node.type?.name === 'hardBreak') {
      if (textOffset + 1 >= offset) {
        found = Math.min(Math.max(pos, from), to);
        return false;
      }
      textOffset += 1;
    }

    return undefined;
  });

  if (found !== null) return found;
  return offset === textOffset ? to : null;
}

function wordMinimizedPendingEdits(
  ed: Editor,
  groupId: string,
  match: SearchMatch,
  replaceHtml: string,
  kind: PendingEditKind
): PendingEdit[] {
  if (containsBlockLevelMarkup(replaceHtml)) return [];
  if (replaceHtml.trim().length === 0) return [];

  const originalText = ed.state.doc.textBetween(match.from, match.to, '\n', '\n');
  const replacementText = textFromHTMLPreservingWhitespace(replaceHtml);

  if (replacementText === originalText) return [];
  if (normalizeSearchQuery(replacementText) === normalizeSearchQuery(originalText)) return [];

  const originalTokens = nonWhitespaceTokens(originalText);
  const replacementTokens = nonWhitespaceTokens(replacementText);
  if (originalTokens.length === 0 || replacementTokens.length === 0) return [];
  if (originalTokens.length + replacementTokens.length > 900) return [];

  const segments = diffSegments(originalTokens, replacementTokens);
  const changedSegments = coalescedChangesFromSegments(segments, 3);
  if (changedSegments.length === 0) return [];

  const coversWholeMatch = changedSegments.length === 1 &&
    changedSegments[0].oldStart === 0 &&
    changedSegments[0].oldEnd === originalTokens.length;
  if (coversWholeMatch) return [];

  const edits: PendingEdit[] = [];
  for (let index = 0; index < changedSegments.length; index += 1) {
    const change = changedSegments[index];
    let originalStart = change.oldStart > 0 ? originalTokens[change.oldStart - 1].end : 0;
    let originalEnd = change.oldEnd < originalTokens.length
      ? originalTokens[change.oldEnd].start
      : originalText.length;
    let replacementStart = change.newStart > 0 ? replacementTokens[change.newStart - 1].end : 0;
    let replacementEnd = change.newEnd < replacementTokens.length
      ? replacementTokens[change.newEnd].start
      : replacementText.length;

    let replacementFragment = replacementText.slice(replacementStart, replacementEnd);

    // TipTap's HTML insertion parser may drop leading/trailing plain spaces in
    // a fragment. Include the neighboring unchanged token at that edge so the
    // accepted edit does not glue words together.
    if (/^\s/.test(replacementFragment) && change.oldStart > 0 && change.newStart > 0) {
      originalStart = originalTokens[change.oldStart - 1].start;
      replacementStart = replacementTokens[change.newStart - 1].start;
    }

    if (/\s$/.test(replacementFragment) && change.oldEnd < originalTokens.length && change.newEnd < replacementTokens.length) {
      originalEnd = originalTokens[change.oldEnd].end;
      replacementEnd = replacementTokens[change.newEnd].end;
    }

    if (originalStart === originalEnd && replacementStart === replacementEnd) {
      continue;
    }

    const from = docPositionAtTextOffset(ed.state.doc, match.from, match.to, originalStart);
    const to = docPositionAtTextOffset(ed.state.doc, match.from, match.to, originalEnd);
    if (from === null || to === null || from > to) return [];

    replacementFragment = replacementText.slice(replacementStart, replacementEnd);
    if (from === to && replacementFragment.length === 0) continue;

    const currentFragment = ed.state.doc.textBetween(from, to, '\n', '\n');
    const originalFragment = originalText.slice(originalStart, originalEnd);
    if (currentFragment !== originalFragment) return [];

    edits.push(createPendingEdit(ed, {
      id: `${groupId}_word_${index}`,
      groupId,
      kind,
      from,
      to,
      newHtml: escapeHTML(replacementFragment),
    }));
  }

  return edits.length === 0 ? [] : edits;
}

export function sentenceSplitPendingEdits(
  ed: Editor,
  groupId: string,
  match: SearchMatch,
  replaceHtml: string,
  kind: PendingEditKind = 'findReplace'
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
      kind,
      from: scopedMatches[0].from,
      to: scopedMatches[0].to,
      newHtml: escapeHTML(replacementSentence.text),
    }));
  }

  return changed;
}

export function replacementPendingEdits(
  ed: Editor,
  groupId: string,
  match: SearchMatch,
  replaceHtml: string,
  kind: PendingEditKind
): PendingEdit[] {
  const wordEdits = wordMinimizedPendingEdits(ed, groupId, match, replaceHtml, kind);
  if (wordEdits.length > 0) return wordEdits;

  const splitEdits = sentenceSplitPendingEdits(ed, groupId, match, replaceHtml, kind);
  if (splitEdits.length > 0) return splitEdits;

  return [
    createPendingEdit(ed, {
      id: groupId,
      groupId,
      kind,
      from: match.from,
      to: match.to,
      newHtml: replaceHtml,
    }),
  ];
}

export function queueProposedEdit(
  ed: Editor,
  id: string,
  target: ProposedEditTarget,
  replaceHtml: string,
  replaceAll: boolean,
  metadata?: PendingEditMetadata
): number {
  const resolved = resolveProposedEditMatches(ed, target, replaceAll);
  if (typeof resolved === 'number') return resolved;
  if (resolved.length === 0) return 0;

  const edits: PendingEdit[] = [];
  resolved.forEach((match, matchIndex) => {
    const groupId = replaceAll ? `${id}_${matchIndex}` : id;
    edits.push(...replacementPendingEdits(ed, groupId, match, replaceHtml, 'findReplace').map((edit) => ({
      ...edit,
      learningCategory: metadata?.learningCategory ?? '',
      rationale: metadata?.rationale ?? '',
      instruction: metadata?.instruction ?? '',
    })));
  });

  return queuePendingEdits(ed, edits, edits[0]?.id ?? null);
}

export function focusPendingEdit(ed: Editor, id: string): boolean {
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

export function focusRelativePendingEdit(ed: Editor, delta: 1 | -1): boolean {
  const state = getPendingEditsState(ed.state);
  if (state.edits.length === 0) return false;

  const currentIndex = currentPendingEditIndex(state);
  const baseIndex = currentIndex >= 0 ? currentIndex : (delta > 0 ? -1 : 0);
  const nextIndex = (baseIndex + delta + state.edits.length) % state.edits.length;
  return focusPendingEdit(ed, state.edits[nextIndex].id);
}

function isLLMEdit(edit: PendingEdit): boolean {
  return edit.source === 'Assistant' || edit.groupId.startsWith('edit_') || edit.id.startsWith('edit_');
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

function surroundingSentenceForEdit(ed: Editor, edit: PendingEdit): string {
  const before = ed.state.doc.textBetween(Math.max(0, edit.from - 600), edit.from, '\n', '\n');
  const current = edit.originalText;
  const after = ed.state.doc.textBetween(edit.to, Math.min(ed.state.doc.content.size, edit.to + 600), '\n', '\n');
  const context = `${before}${current}${after}`;
  const anchorStart = before.length;
  const anchorEnd = anchorStart + current.length;

  let start = 0;
  for (let index = anchorStart - 1; index >= 0; index -= 1) {
    if (/[.!?\n]/.test(context[index])) {
      start = index + 1;
      break;
    }
  }

  let end = context.length;
  for (let index = anchorEnd; index < context.length; index += 1) {
    if (/[.!?\n]/.test(context[index])) {
      end = index + 1;
      break;
    }
  }

  return context.slice(start, end).trim();
}

function editDecisionPayload(ed: Editor, edit: PendingEdit, decision: 'accept' | 'reject') {
  return {
    eventId: `${edit.id}_${decision}_${Date.now()}`,
    decision,
    source: edit.source,
    kind: edit.kind,
    originalText: edit.originalText,
    replacementText: edit.replacementText,
    surroundingSentence: surroundingSentenceForEdit(ed, edit),
    groupId: edit.groupId,
    learningCategory: edit.learningCategory,
    rationale: edit.rationale,
    instruction: edit.instruction,
    timestamp: Date.now(),
  };
}

function emitEditDecision(ed: Editor, edit: PendingEdit, decision: 'accept' | 'reject') {
  sendToSwift('editDecision', editDecisionPayload(ed, edit, decision));
}

export function acceptPendingEdit(ed: Editor, id: string): boolean {
  const state = getPendingEditsState(ed.state);
  const edit = getPendingEditById(state, id);
  if (!edit || edit.status === 'conflicted') return false;
  if (!isPendingEditStillApplicable(ed, edit)) {
    markPendingEditConflicted(ed, id, 'The document changed around this suggestion.');
    return false;
  }

  const decisionPayload = editDecisionPayload(ed, edit, 'accept');
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
    sendToSwift('editDecision', decisionPayload);
    scheduleSmartQuotesNormalization(ed);
  }

  return result;
}

export function rejectPendingEdit(ed: Editor, id: string): boolean {
  const state = getPendingEditsState(ed.state);
  const edit = getPendingEditById(state, id);
  if (!edit) return false;
  const result = dispatchPendingEditAction(ed, { type: 'reject', id });
  if (result) emitEditDecision(ed, edit, 'reject');
  return result;
}

export function acceptAllPendingEdits(ed: Editor): boolean {
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
  const decisionPayloads = sorted.map((edit) => editDecisionPayload(ed, edit, 'accept'));
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
    decisionPayloads.forEach((payload) => sendToSwift('editDecision', payload));
    scheduleSmartQuotesNormalization(ed);
  }

  return result;
}

export function rejectAllPendingEdits(ed: Editor, emitDecisions = true): boolean {
  const state = getPendingEditsState(ed.state);
  if (state.edits.length === 0) return false;
  if (emitDecisions) {
    state.edits.forEach((edit) => emitEditDecision(ed, edit, 'reject'));
  }
  return dispatchPendingEditAction(ed, { type: 'rejectAll' });
}

export function pendingEditsSummaryJSON(state: PendingEditsPluginState): string {
  return JSON.stringify({
    activeEditId: state.activeEditId,
    edits: state.edits.map((edit, index) => serializePendingEdit(edit, index, state.activeEditId)),
  });
}

export const PendingEditHighlight = Extension.create({
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
        view(_view) {
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
