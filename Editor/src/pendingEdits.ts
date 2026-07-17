import { Editor, Extension } from '@tiptap/core';
import { Plugin, PluginKey, TextSelection } from '@tiptap/pm/state';
import { Decoration, DecorationSet, EditorView } from '@tiptap/pm/view';
import { sendToSwift } from './bridge';
import { getEditorInstance } from './instance';
import {
  ACCEPTED_LLM_EDIT_COLOR,
  MAX_PENDING_EDITS,
  PendingEdit,
  PendingEditKind,
  PendingEditMetadata,
  PersonalizationOutcomeSnapshot,
  SearchMatch,
  TOO_MANY_PENDING_EDITS,
} from './types';
import { plainTextFromHTML } from './utils';
import { findTextInDoc } from './search';
import {
  contextCharacterBefore,
  prepareReplacementHTMLForRange,
  scheduleSmartQuotesNormalization,
  smartifyHTMLFragment,
} from './smartQuotes';
import {
  getDocumentRevision,
  mapPositionFromRevision,
} from './docSync';
import { classifyPersonalizationOutcome } from './personalizationOutcome';

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

interface TrackedPersonalizationDecision {
  actionId: string;
  decision: 'accept' | 'reject';
  originalText: string;
  proposedText: string;
  from: number;
  to: number;
  revision: number;
}

const trackedPersonalizationDecisions = new Map<string, TrackedPersonalizationDecision>();
const MAX_TRACKED_PERSONALIZATION_DECISIONS = 200;

function rememberPersonalizationDecision(decision: TrackedPersonalizationDecision) {
  trackedPersonalizationDecisions.set(decision.actionId, decision);
  while (trackedPersonalizationDecisions.size > MAX_TRACKED_PERSONALIZATION_DECISIONS) {
    const oldest = trackedPersonalizationDecisions.keys().next().value;
    if (typeof oldest !== 'string') break;
    trackedPersonalizationDecisions.delete(oldest);
  }
}

function closestReplacementRange(ed: Editor, edit: PendingEdit): SearchMatch {
  if (!edit.replacementText.trim()) {
    const position = Math.min(edit.from, ed.state.doc.content.size);
    return { from: position, to: position };
  }

  const matches = findTextInDoc(ed.state.doc, edit.replacementText);
  return matches.reduce<SearchMatch | null>((closest, match) => {
    if (!closest) return match;
    return Math.abs(match.from - edit.from) < Math.abs(closest.from - edit.from)
      ? match
      : closest;
  }, null) ?? {
    from: Math.min(edit.from, ed.state.doc.content.size),
    to: Math.min(edit.from, ed.state.doc.content.size),
  };
}

function trackPersonalizationDecision(
  ed: Editor,
  edit: PendingEdit,
  payload: ReturnType<typeof editDecisionPayload>
) {
  const range = payload.decision === 'accept'
    ? closestReplacementRange(ed, edit)
    : { from: edit.from, to: edit.to };
  rememberPersonalizationDecision({
    actionId: payload.eventId,
    decision: payload.decision,
    originalText: edit.originalText,
    proposedText: edit.replacementText,
    from: range.from,
    to: range.to,
    revision: getDocumentRevision(),
  });
}

export function resetPersonalizationOutcomeTracking() {
  trackedPersonalizationDecisions.clear();
}

export function acknowledgePersonalizationOutcomes(actionIds: string[]) {
  actionIds.forEach((id) => trackedPersonalizationDecisions.delete(id));
}

export function collectPersonalizationOutcomes(ed: Editor): PersonalizationOutcomeSnapshot[] {
  return Array.from(trackedPersonalizationDecisions.values()).map((tracked) => {
    // Map the outside edges so a writer replacing the entire tracked passage
    // still yields the replacement text instead of a collapsed range.
    const mappedFrom = mapPositionFromRevision(tracked.revision, tracked.from, -1);
    const mappedTo = mapPositionFromRevision(tracked.revision, tracked.to, 1);
    if (mappedFrom === null || mappedTo === null || mappedTo < mappedFrom) {
      return {
        actionId: tracked.actionId,
        outcome: 'unresolvable',
        finalText: '',
        confidence: 0,
        trainingEligible: false,
      };
    }

    const finalText = ed.state.doc.textBetween(mappedFrom, mappedTo, '\n', '\n');
    return {
      actionId: tracked.actionId,
      ...classifyPersonalizationOutcome(
        tracked.decision,
        tracked.originalText,
        tracked.proposedText,
        finalText
      ),
    };
  });
}

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
    trackPersonalizationDecision(ed, edit, decisionPayload);
    scheduleSmartQuotesNormalization(ed);
  }

  return result;
}

export function rejectPendingEdit(ed: Editor, id: string): boolean {
  const state = getPendingEditsState(ed.state);
  const edit = getPendingEditById(state, id);
  if (!edit) return false;
  const decisionPayload = editDecisionPayload(ed, edit, 'reject');
  const result = dispatchPendingEditAction(ed, { type: 'reject', id });
  if (result) {
    sendToSwift('editDecision', decisionPayload);
    trackPersonalizationDecision(ed, edit, decisionPayload);
  }
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
    decisionPayloads.forEach((payload, index) => {
      sendToSwift('editDecision', payload);
      trackPersonalizationDecision(ed, sorted[index], payload);
    });
    scheduleSmartQuotesNormalization(ed);
  }

  return result;
}

export function rejectAllPendingEdits(ed: Editor, emitDecisions = true): boolean {
  const state = getPendingEditsState(ed.state);
  if (state.edits.length === 0) return false;
  const decisionPayloads = emitDecisions
    ? state.edits.map((edit) => ({ edit, payload: editDecisionPayload(ed, edit, 'reject') }))
    : [];
  if (emitDecisions) {
    decisionPayloads.forEach(({ payload }) => sendToSwift('editDecision', payload));
  }
  const result = dispatchPendingEditAction(ed, { type: 'rejectAll' });
  if (result) {
    decisionPayloads.forEach(({ edit, payload }) => {
      trackPersonalizationDecision(ed, edit, payload);
    });
  }
  return result;
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
