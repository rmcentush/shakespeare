import { Editor, Mark, mergeAttributes } from '@tiptap/core';
import { TextSelection } from '@tiptap/pm/state';
import { sendToSwift } from './bridge';
import { createPendingEdit, queuePendingEdits } from './pendingEdits';
import { sanitizeModelReplacementHTML } from './sanitize';
import { COMMENTS_SYNC_DEBOUNCE_MS } from './types';
import {
  effectiveTextSelection,
  getDocumentRevision,
  setPreservedTextSelection,
} from './docSync';

let lastSentCommentsSignature: string | null = null;
let commentsSyncTimer: ReturnType<typeof setTimeout> | null = null;
let pendingDocumentChanged = false;

export function resetCommentsSignature(): void {
  if (commentsSyncTimer) clearTimeout(commentsSyncTimer);
  commentsSyncTimer = null;
  pendingDocumentChanged = false;
  lastSentCommentsSignature = null;
}

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

export const CommentMark = Mark.create({
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

function collectCommentEntriesUncached(doc: any): CommentEntry[] {
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

export function attachCommentActivation(editor: Editor) {
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

export function emitCommentsChanged(editor: Editor, force = false, documentChanged = false) {
  const comments = collectComments(editor);
  const signature = commentsSignature(comments);

  if (!force && lastSentCommentsSignature === signature) {
    return;
  }

  lastSentCommentsSignature = signature;
  sendToSwift('commentsChanged', { comments, documentChanged });
}

export function scheduleCommentsChanged(editor: Editor, documentChanged = false) {
  pendingDocumentChanged ||= documentChanged;
  if (commentsSyncTimer) clearTimeout(commentsSyncTimer);
  commentsSyncTimer = setTimeout(() => {
    commentsSyncTimer = null;
    const changed = pendingDocumentChanged;
    pendingDocumentChanged = false;
    emitCommentsChanged(editor, false, changed);
  }, COMMENTS_SYNC_DEBOUNCE_MS);
}

export function addComment(editor: Editor, commentId: string): boolean {
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
  setPreservedTextSelection({
    ...selection,
    revision: getDocumentRevision(),
  });
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

export function addCommentAtRangeFromJSON(editor: Editor, json: string): boolean {
  const input = parsedCommentInput(json);
  return input ? addCommentAtRange(editor, input) : false;
}

export function updateCommentText(editor: Editor, commentId: string, text: string) {
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

export function setCommentStatus(editor: Editor, commentId: string, status: string) {
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

export function removeComment(editor: Editor, commentId: string) {
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

export function pendingReplaceComment(editor: Editor, commentId: string, editId: string, html: string): number {
  if (!html.trim()) return 0;

  const sanitizedHTML = sanitizeModelReplacementHTML(html);
  if (!sanitizedHTML.trim()) return 0;

  const comment = findCommentEntry(editor, commentId);
  if (!comment) return 0;

  const edit = createPendingEdit(editor, {
    id: editId,
    groupId: editId,
    kind: 'selection',
    from: comment.rangeStart,
    to: comment.rangeEnd,
    newHtml: sanitizedHTML,
    metadata: {
      learningCategory: comment.kind,
      rationale: comment.text,
      instruction: 'Apply the editorial suggestion while preserving the writer\'s intent.',
    },
  });

  return queuePendingEdits(editor, [edit], edit.id);
}

export function focusComment(editor: Editor, commentId: string) {
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

// ProseMirror docs are immutable; cache collected entries by doc identity so
// repeated reads within one revision walk the document once.
const commentEntriesCache = new WeakMap<object, CommentEntry[]>();

function collectCommentEntries(doc: any): CommentEntry[] {
  const cached = commentEntriesCache.get(doc);
  if (cached) return cached;
  const entries = collectCommentEntriesUncached(doc);
  commentEntriesCache.set(doc, entries);
  return entries;
}
