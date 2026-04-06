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

let searchResults: SearchMatch[] = [];
let currentMatchIdx = -1;
let activeSearchQuery = '';
const SEARCH_STOP = Symbol('search-stop');
const MAX_SEARCH_RESULTS = 500;
const MAX_PENDING_EDITS = 120;
const MAX_PENDING_FIND_REPLACE_MATCHES = 60;
const TOO_MANY_MATCHES = -1;
const TOO_MANY_PENDING_EDITS = -2;
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
type PendingEditKind = 'selection' | 'insert' | 'findReplace';
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
  | { type: 'reject'; id: string }
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
  if (id.startsWith('orality_')) return 'Orality';
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
  return {
    id: options.id,
    groupId: options.groupId,
    kind: options.kind,
    source,
    label: buildPendingEditLabel(source, options.kind),
    from: options.from,
    to: options.to,
    newHtml: options.newHtml,
    originalText: ed.state.doc.textBetween(options.from, options.to, '\n', '\n'),
    replacementText: plainTextFromHTML(options.newHtml),
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
      Decoration.widget(edit.to, () => createPendingEditWidget(edit, isActive), { side: 1 })
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

function focusPendingEdit(ed: Editor, id: string): boolean {
  const state = getPendingEditsState(ed.state);
  const edit = getPendingEditById(state, id);
  if (!edit) return false;
  dispatchPendingEditAction(ed, { type: 'focus', id });
  ed.chain()
    .focus()
    .setTextSelection({ from: edit.from, to: Math.max(edit.from, edit.to) })
    .run();
  return true;
}

function acceptPendingEdit(ed: Editor, id: string): boolean {
  const state = getPendingEditsState(ed.state);
  const edit = getPendingEditById(state, id);
  if (!edit || edit.status === 'conflicted') return false;

  return ed.chain()
    .command(({ tr }) => {
      tr.setMeta(pendingEditPluginKey, { type: 'accept', id } satisfies PendingEditAction);
      return true;
    })
    .insertContentAt({ from: edit.from, to: edit.to }, edit.newHtml)
    .run();
}

function rejectPendingEdit(ed: Editor, id: string): boolean {
  const state = getPendingEditsState(ed.state);
  if (!state.edits.some((edit) => edit.id === id)) return false;
  return dispatchPendingEditAction(ed, { type: 'reject', id });
}

function acceptAllPendingEdits(ed: Editor): boolean {
  const state = getPendingEditsState(ed.state);
  if (state.edits.length === 0) return false;

  const sorted = [...state.edits].sort((a, b) => b.from - a.from);
  let chain = ed.chain().command(({ tr }) => {
    tr.setMeta(pendingEditPluginKey, { type: 'acceptAll' } satisfies PendingEditAction);
    return true;
  });

  for (const edit of sorted) {
    chain = chain.insertContentAt({ from: edit.from, to: edit.to }, edit.newHtml);
  }

  return chain.run();
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
  rangeStart: number;
  rangeEnd: number;
}

const CommentMark = Mark.create({
  name: 'comment',
  inclusive: false,
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
  rangeStart: number;
  rangeEnd: number;
  fragments: CommentFragment[];
}

interface CommentMarkAttributes {
  commentId: string;
  commentText: string;
  commentCreatedAt: number;
}

function parseCommentTimestamp(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function getCommentMarkAttributes(mark: any): CommentMarkAttributes | null {
  if (mark.type.name !== 'comment') return null;

  const commentId = typeof mark.attrs.commentId === 'string' ? mark.attrs.commentId : '';
  if (!commentId) return null;

  return {
    commentId,
    commentText: typeof mark.attrs.commentText === 'string' ? mark.attrs.commentText : '',
    commentCreatedAt: parseCommentTimestamp(mark.attrs.commentCreatedAt),
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
        rangeStart: pos,
        rangeEnd: to,
        fragments: [],
      };

      existing.text = attrs.commentText;
      existing.createdAt = attrs.commentCreatedAt;
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
    rangeStart: comment.rangeStart,
    rangeEnd: comment.rangeEnd,
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

function commentsSignature(comments: CommentData[]): string {
  return comments
    .map((comment) => (
      `${comment.commentId}\u001f${comment.text}\u001f${comment.selectedText}\u001f${comment.createdAt}\u001f${comment.rangeStart}\u001f${comment.rangeEnd}`
    ))
    .join('\u001e');
}

function emitCommentsChanged(editor: Editor, force = false) {
  const comments = collectComments(editor);
  const signature = commentsSignature(comments);

  if (!force && lastSentCommentsSignature === signature) {
    return;
  }

  lastSentCommentsSignature = signature;
  sendToSwift('commentsChanged', { comments });
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
        commentId,
        commentText: '',
        commentCreatedAt: Date.now(),
      })
    );

  editor.view.dispatch(tr);
  preservedTextSelection = {
    ...selection,
    revision: documentRevision,
  };
  editor.commands.focus();

  emitCommentsChanged(editor);
  return true;
}

function updateCommentText(editor: Editor, commentId: string, text: string) {
  const { tr } = editor.state;
  let changed = false;
  editor.state.doc.descendants((node, pos) => {
    if (!node.isText) return;
    for (const mark of node.marks) {
      if (mark.type.name === 'comment' && mark.attrs.commentId === commentId) {
        const newMark = mark.type.create({
          ...mark.attrs,
          commentText: text,
        });
        tr.removeMark(pos, pos + node.nodeSize, mark);
        tr.addMark(pos, pos + node.nodeSize, newMark);
        changed = true;
      }
    }
  });
  if (changed) {
    editor.view.dispatch(tr);
    emitCommentsChanged(editor);
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
    emitCommentsChanged(editor);
  }
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
        return rejectAllPendingEdits(this.editor);
      },
      'Mod-Shift-Enter': () => {
        return acceptAllPendingEdits(this.editor);
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

function findTextInDoc(doc: any, query: string, maxMatches = Number.POSITIVE_INFINITY): SearchMatch[] {
  if (!query) return [];
  const matches: SearchMatch[] = [];
  const lowerQuery = query.toLowerCase();

  try {
    doc.descendants((node: any, pos: number) => {
      if (!node.isText) return;
      const text = node.text!.toLowerCase();
      let idx = text.indexOf(lowerQuery);
      while (idx !== -1) {
        matches.push({ from: pos + idx, to: pos + idx + query.length });
        if (matches.length >= maxMatches) {
          throw SEARCH_STOP;
        }
        idx = text.indexOf(lowerQuery, idx + 1);
      }
    });
  } catch (error) {
    if (error !== SEARCH_STOP) throw error;
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
  return smartifyQuotes(note.replace(/\r\n?/g, '\n')).trim();
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

function autoResizeFootnoteEditor(textarea: HTMLTextAreaElement) {
  textarea.style.height = 'auto';
  textarea.style.height = `${textarea.scrollHeight}px`;
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

  const editorElement = container.querySelector(
    `.editor-footnote-editor[data-footnote-id="${id}"]`
  );

  if (!(editorElement instanceof HTMLTextAreaElement)) {
    return false;
  }

  editorElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
  editorElement.focus();

  if (placeCaretAtEnd) {
    const end = editorElement.value.length;
    editorElement.setSelectionRange(end, end);
  }

  return true;
}

function updateFootnoteNote(editor: Editor, id: string, note: string) {
  const footnote = getFootnoteByID(editor, id);
  if (!footnote) return;

  const currentNode = editor.state.doc.nodeAt(footnote.pos);
  if (!currentNode) return;

  editor.view.dispatch(
    editor.state.tr.setNodeMarkup(footnote.pos, undefined, {
      ...currentNode.attrs,
      note,
    })
  );
}

function captureFocusedFootnoteEditorState(container: HTMLElement): FocusedFootnoteEditorState | null {
  const activeElement = document.activeElement;
  if (!(activeElement instanceof HTMLTextAreaElement)) return null;

  const id = activeElement.dataset.footnoteId;
  if (!id || !container.contains(activeElement)) return null;

  return {
    id,
    selectionStart: activeElement.selectionStart ?? activeElement.value.length,
    selectionEnd: activeElement.selectionEnd ?? activeElement.value.length,
    scrollTop: activeElement.scrollTop,
  };
}

function restoreFocusedFootnoteEditorState(
  container: HTMLElement,
  state: FocusedFootnoteEditorState | null
) {
  if (!state) return;

  const editorElement = container.querySelector(
    `.editor-footnote-editor[data-footnote-id="${state.id}"]`
  );

  if (!(editorElement instanceof HTMLTextAreaElement)) {
    return;
  }

  editorElement.focus();
  editorElement.setSelectionRange(state.selectionStart, state.selectionEnd);
  editorElement.scrollTop = state.scrollTop;
}

function syncFootnotePanelValues(container: HTMLElement, footnotes: FootnoteDetails[]) {
  const editors = new Map<string, HTMLTextAreaElement>();
  container.querySelectorAll('.editor-footnote-editor').forEach((element) => {
    if (element instanceof HTMLTextAreaElement && element.dataset.footnoteId) {
      editors.set(element.dataset.footnoteId, element);
    }
  });

  footnotes.forEach((footnote) => {
    const editorElement = editors.get(footnote.id);
    if (!editorElement) return;
    if (document.activeElement === editorElement) return;

    if (editorElement.value !== footnote.note) {
      editorElement.value = footnote.note;
      autoResizeFootnoteEditor(editorElement);
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

    const note = document.createElement('textarea');
    note.className = 'editor-footnote-editor';
    note.dataset.footnoteId = footnote.id;
    note.value = footnote.note;
    note.rows = 1;
    note.spellcheck = true;
    note.placeholder = 'Footnote text';
    note.addEventListener('focus', () => {
      selectFootnoteReference(editor, footnote.id);
    });
    note.addEventListener('input', () => {
      autoResizeFootnoteEditor(note);
      updateFootnoteNote(editor, footnote.id, note.value);
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
    autoResizeFootnoteEditor(note);
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
    a.footnoteText === b.footnoteText;
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
  const normalizedNote = normalizeFootnoteNote(note);
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

function hideLinkPreview() {
  if (!linkPreviewElement) return;
  linkPreviewElement.classList.remove('is-visible');
  linkPreviewElement.setAttribute('aria-hidden', 'true');
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

  const href = anchor.getAttribute('href')?.trim();
  if (!href) {
    hideLinkPreview();
    return;
  }

  linkPreviewElement.textContent = href;
  linkPreviewElement.classList.add('is-visible');
  linkPreviewElement.setAttribute('aria-hidden', 'false');
  positionLinkPreview(event);
}

function attachLinkHoverPreview(editor: Editor) {
  const root = editor.view.dom as HTMLElement;

  root.addEventListener('mousemove', (event) => {
    const target = event.target;
    if (!(target instanceof Element)) {
      hideLinkPreview();
      return;
    }

    const anchor = target.closest('a[href]');
    if (anchor instanceof HTMLAnchorElement && root.contains(anchor)) {
      showLinkPreview(anchor, event);
      return;
    }

    hideLinkPreview();
  });

  root.addEventListener('mouseleave', hideLinkPreview);
  root.addEventListener('mousedown', hideLinkPreview);
  root.addEventListener('dragstart', hideLinkPreview);
  document.addEventListener('scroll', hideLinkPreview, true);
}

const ResizableImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      width: {
        default: null,
        parseHTML: (element: HTMLElement) => element.style.width || element.getAttribute('width') || null,
        renderHTML: (attributes: Record<string, unknown>) => {
          if (!attributes.width) return {};
          return { style: `width: ${attributes.width}` };
        },
      },
    };
  },
  addNodeView() {
    return ({ node, getPos, editor }) => {
      const container = document.createElement('span');
      container.className = 'image-resizer';

      const img = document.createElement('img');
      img.src = node.attrs.src as string;
      if (node.attrs.alt) img.alt = node.attrs.alt as string;
      if (node.attrs.title) img.title = node.attrs.title as string;
      img.className = 'editor-image';
      if (node.attrs.width) {
        img.style.width = node.attrs.width as string;
      }
      container.appendChild(img);

      const handle = document.createElement('div');
      handle.className = 'resize-handle';
      container.appendChild(handle);

      let startX: number;
      let startWidth: number;

      const onMouseMove = (e: MouseEvent) => {
        const newWidth = Math.max(50, startWidth + (e.clientX - startX));
        img.style.width = `${newWidth}px`;
      };

      const onMouseUp = () => {
        document.removeEventListener('mousemove', onMouseMove);
        document.removeEventListener('mouseup', onMouseUp);
        if (typeof getPos === 'function') {
          const pos = getPos();
          if (typeof pos === 'number') {
            const currentNode = editor.state.doc.nodeAt(pos);
            if (currentNode) {
              editor.view.dispatch(
                editor.state.tr.setNodeMarkup(pos, undefined, {
                  ...currentNode.attrs,
                  width: `${img.offsetWidth}px`,
                })
              );
            }
          }
        }
      };

      const onMouseDown = (e: MouseEvent) => {
        e.preventDefault();
        e.stopPropagation();
        startX = e.clientX;
        startWidth = img.offsetWidth;
        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
      };

      handle.addEventListener('mousedown', onMouseDown);

      return {
        dom: container,
        update(updatedNode) {
          if (updatedNode.type.name !== 'image') return false;
          img.src = updatedNode.attrs.src as string;
          img.alt = (updatedNode.attrs.alt as string) || '';
          img.title = (updatedNode.attrs.title as string) || '';
          if (updatedNode.attrs.width) {
            img.style.width = updatedNode.attrs.width as string;
          } else {
            img.style.width = '';
          }
          return true;
        },
        destroy() {
          handle.removeEventListener('mousedown', onMouseDown);
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

/**
 * Convert straight quotes to curly/smart quotes.
 * Handles double quotes, single quotes, and apostrophes.
 */
function smartifyQuotes(text: string): string {
  // Double quotes: opening after start-of-string, whitespace, or opening punctuation
  text = text.replace(/(^|[\s(\[{])"/g, '$1\u201C'); // "
  text = text.replace(/"/g, '\u201D'); // "

  // Single quotes / apostrophes:
  // Opening after start-of-string, whitespace, or opening punctuation
  text = text.replace(/(^|[\s(\[{])'/g, '$1\u2018'); // '
  // Everything else (mid-word apostrophes, closing quotes)
  text = text.replace(/'/g, '\u2019'); // '

  return text;
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
 * Apply smart quotes to all text nodes in a DOM tree (preserving HTML structure).
 */
function smartifyDOMTextNodes(root: Node): void {
  const ownerDocument = root.ownerDocument ?? document;
  const walker = ownerDocument.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const textNodes: Text[] = [];
  let previousText = '';
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

const PASTE_STYLE_PROPERTIES = [
  'font-family',
  'background',
  'background-color',
  '-webkit-text-fill-color',
];

function sanitizePastedHTML(html: string): string {
  const parsed = new DOMParser().parseFromString(stripGeneratedFootnotesSection(html), 'text/html');

  parsed.querySelectorAll(GENERATED_FOOTNOTES_SELECTOR).forEach((element) => element.remove());
  parsed.querySelectorAll('style, meta, link').forEach((element) => element.remove());

  parsed.body.querySelectorAll('*').forEach((element) => {
    PASTE_STYLE_PROPERTIES.forEach((property) => {
      element.style.removeProperty(property);
    });

    ['color', 'bgcolor', 'face'].forEach((attribute) => {
      element.removeAttribute(attribute);
    });

    if (!element.getAttribute('style')?.trim()) {
      element.removeAttribute('style');
    }
  });

  smartifyDOMTextNodes(parsed.body);

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
    ResizableImage.configure({
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
                      editorRef.chain().focus().setImage({ src }).run();
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
                          view.state.schema.nodes.image.create({ src })
                        );
                        view.dispatch(tr);
                      } else {
                        editorRef.chain().focus().setImage({ src }).run();
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
    transformPastedHTML(html) {
      return sanitizePastedHTML(html);
    },
    transformPastedText(text) {
      return smartifyQuotes(text);
    },
  },
  onUpdate({ editor }) {
    invalidateDerivedDocumentState();
    updatePreservedTextSelection(editor);
    scheduleSelectionUpdate(editor);
    scheduleWordCountUpdate(editor);
    scheduleContentUpdate(editor);
    scheduleFootnotesPanelRender(editor);
    emitCommentsChanged(editor);
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
          editor.chain().focus().setImage({ src: value }).run();
        }
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
  replaceSelectionHTML(html: string) {
    editor.chain().focus().insertContent(html).run();
    normalizeDocumentSmartQuotes(editor);
  },
  insertHTMLAtCursor(html: string) {
    editor.chain().focus().insertContent(html).run();
    normalizeDocumentSmartQuotes(editor);
  },
  findAndReplaceText(find: string, replaceHtml: string, replaceAllOccurrences: boolean): number {
    const maxMatches = replaceAllOccurrences ? MAX_PENDING_FIND_REPLACE_MATCHES + 1 : 1;
    const matches = findTextInDoc(editor.state.doc, find, maxMatches);
    if (matches.length === 0) return 0;
    if (replaceAllOccurrences && matches.length > MAX_PENDING_FIND_REPLACE_MATCHES) {
      return TOO_MANY_MATCHES;
    }
    const toReplace = replaceAllOccurrences ? matches : [matches[0]];
    // Replace from end to start to preserve positions
    for (let i = toReplace.length - 1; i >= 0; i--) {
      editor.chain()
        .insertContentAt({ from: toReplace[i].from, to: toReplace[i].to }, replaceHtml)
        .run();
    }
    normalizeDocumentSmartQuotes(editor);
    return toReplace.length;
  },

  // --- Pending Edits API (Cursor-like diff review) ---
  pendingReplaceSelection(id: string, newHtml: string): number {
    const { from, to } = editor.state.selection;
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
  pendingInsertAtCursor(id: string, newHtml: string): number {
    const { from } = editor.state.selection;
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
    const maxMatches = replaceAll ? MAX_PENDING_FIND_REPLACE_MATCHES + 1 : 1;
    const matches = findTextInDoc(editor.state.doc, find, maxMatches);
    if (matches.length === 0) return 0;
    if (replaceAll && matches.length > MAX_PENDING_FIND_REPLACE_MATCHES) {
      return TOO_MANY_MATCHES;
    }
    const toAdd = replaceAll ? matches : [matches[0]];
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
  acceptAllPendingEdits() { acceptAllPendingEdits(editor); },
  rejectAllPendingEdits() { rejectAllPendingEdits(editor); },
  acceptPendingEdit(id: string): boolean { return acceptPendingEdit(editor, id); },
  rejectPendingEdit(id: string): boolean { return rejectPendingEdit(editor, id); },
  focusPendingEdit(id: string): boolean { return focusPendingEdit(editor, id); },
  getPendingEdits(): string { return pendingEditsSummaryJSON(getPendingEditsState(editor.state)); },
  getPendingEditCount(): number { return getPendingEditsState(editor.state).edits.length; },
  addComment(commentId: string): boolean { return addComment(editor, commentId); },
  updateCommentText(commentId: string, text: string) { updateCommentText(editor, commentId, text); },
  removeComment(commentId: string) { removeComment(editor, commentId); },
  focusComment(commentId: string) { focusComment(editor, commentId); },
  getComments(): string { return JSON.stringify(collectComments(editor)); },
});

attachLinkHoverPreview(editor);
attachSelectionChangeFallback(editor);
attachSmartQuotesNormalizationFallback(editor);
renderFootnotesPanel(editor);
emitCommentsChanged(editor, true);

// Notify Swift that editor is ready
sendToSwift('editorReady', {});
