import { Editor, Extension } from '@tiptap/core';
import { Plugin, PluginKey } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';
import { sendToSwift } from './bridge';
import {
  getDocumentRevision,
  mapPositionFromRevision,
} from './docSync';
import {
  createPendingEdit,
  getPendingEditsState,
  queuePendingEdits,
} from './pendingEdits';
import { findWritingGaps } from './writingGaps';

interface WritingGap {
  from: number;
  to: number;
  raw: string;
  instruction: string;
  isBlock: boolean;
}

interface GapFillRequest {
  requestId: string;
  from: number;
  to: number;
  revision: number;
  raw: string;
  instruction: string;
  isBlock: boolean;
  status: 'loading' | 'error';
  errorMessage: string;
}

const gapSuggestionsPluginKey = new PluginKey<DecorationSet>('writingGaps');
const gapFillRequests = new Map<string, GapFillRequest>();

function escapeHTML(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function plainTextAsHTML(value: string): string {
  return escapeHTML(value)
    .replace(/\r\n?/g, '\n')
    .replaceAll('\n', '<br>');
}

function writingGapsInDocument(doc: any): WritingGap[] {
  const gaps: WritingGap[] = [];

  doc.descendants((node: any, blockPosition: number) => {
    if (!node.isTextblock) return;
    if (node.type.name === 'codeBlock') return false;

    let runText = '';
    let runFrom = -1;
    let expectedNextPosition = -1;
    const flushRun = () => {
      if (runFrom < 0 || !runText) return;
      for (const match of findWritingGaps(runText)) {
        const from = runFrom + match.index;
        const to = from + match.raw.length;
        gaps.push({
          from,
          to,
          raw: match.raw,
          instruction: match.instruction,
          isBlock: node.textContent.trim() === match.raw,
        });
      }
      runText = '';
      runFrom = -1;
      expectedNextPosition = -1;
    };

    node.descendants((child: any, childPosition: number) => {
      if (!child.isText || typeof child.text !== 'string') {
        if (child.isLeaf) flushRun();
        return;
      }
      const absolutePosition = blockPosition + 1 + childPosition;
      if (runFrom >= 0 && absolutePosition !== expectedNextPosition) flushRun();
      if (runFrom < 0) runFrom = absolutePosition;
      runText += child.text;
      expectedNextPosition = absolutePosition + child.nodeSize;
    });
    flushRun();
    return false;
  });

  return gaps.slice(0, 120);
}

function pendingEditCoversGap(state: any, gap: WritingGap): boolean {
  return getPendingEditsState(state).edits.some((edit) => (
    edit.from <= gap.from && edit.to >= gap.to
  ));
}

function mappedRequestRange(request: GapFillRequest): { from: number; to: number } | null {
  const from = mapPositionFromRevision(request.revision, request.from, 1);
  const to = mapPositionFromRevision(request.revision, request.to, -1);
  if (from === null || to === null || to <= from) return null;
  return { from, to };
}

function requestForGap(gap: WritingGap): GapFillRequest | null {
  for (const request of gapFillRequests.values()) {
    const range = mappedRequestRange(request);
    if (range?.from === gap.from && range.to === gap.to && request.raw === gap.raw) {
      return request;
    }
  }
  return null;
}

function refreshGapDecorations(editor: Editor) {
  editor.view.dispatch(editor.state.tr.setMeta(gapSuggestionsPluginKey, 'refresh'));
}

function currentTextForRange(editor: Editor, from: number, to: number): string {
  if (from < 0 || to <= from || to > editor.state.doc.content.size) return '';
  return editor.state.doc.textBetween(from, to, '\n', '\n');
}

function requestGapFill(editor: Editor, gap: WritingGap): boolean {
  if (!editor.isEditable || currentTextForRange(editor, gap.from, gap.to) !== gap.raw) return false;
  if (pendingEditCoversGap(editor.state, gap)) return false;

  const existing = requestForGap(gap);
  if (existing?.status === 'loading') return true;
  if (existing) gapFillRequests.delete(existing.requestId);

  editor.chain().focus().setTextSelection({ from: gap.from, to: gap.to }).run();
  const requestId = crypto.randomUUID();
  const request: GapFillRequest = {
    requestId,
    from: gap.from,
    to: gap.to,
    revision: getDocumentRevision(),
    raw: gap.raw,
    instruction: gap.instruction,
    isBlock: gap.isBlock,
    status: 'loading',
    errorMessage: '',
  };
  gapFillRequests.set(requestId, request);
  refreshGapDecorations(editor);
  sendToSwift('gapFillRequested', {
    requestId,
    from: request.from,
    to: request.to,
    revision: request.revision,
    placeholder: request.raw,
    instruction: request.instruction,
    isBlock: request.isBlock,
  });
  return true;
}

function gapActionButton(editor: Editor, gap: WritingGap): HTMLElement {
  const request = requestForGap(gap);
  const button = document.createElement('button');
  button.type = 'button';
  button.className = [
    'writing-gap-action',
    request?.status === 'loading' ? 'is-loading' : '',
    request?.status === 'error' ? 'is-error' : '',
  ].filter(Boolean).join(' ');
  button.contentEditable = 'false';
  button.setAttribute('aria-label', request?.status === 'error'
    ? 'Try this gap suggestion again'
    : 'Suggest text for this gap');
  button.title = request?.status === 'loading'
    ? 'Writing a suggestion…'
    : request?.status === 'error'
      ? (request.errorMessage || 'Could not write this gap. Click to try again.')
      : 'Write this gap (⌘↵)';
  button.textContent = request?.status === 'loading'
    ? '…'
    : request?.status === 'error' ? '!' : '✦';
  button.addEventListener('mousedown', (event) => {
    event.preventDefault();
    event.stopPropagation();
  });
  button.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopPropagation();
    requestGapFill(editor, gap);
  });
  return button;
}

function buildGapDecorations(editor: Editor, state: any): DecorationSet {
  const decorations: Decoration[] = [];
  const { from: selectionFrom, to: selectionTo } = state.selection;

  for (const gap of writingGapsInDocument(state.doc)) {
    if (pendingEditCoversGap(state, gap)) continue;
    const active = selectionFrom <= gap.to && selectionTo >= gap.from;
    decorations.push(Decoration.inline(gap.from, gap.to, {
      class: active ? 'writing-gap writing-gap-active' : 'writing-gap',
      'data-writing-gap': 'true',
    }));
    decorations.push(Decoration.widget(gap.to, () => gapActionButton(editor, gap), {
      key: `writing-gap-action-${gap.from}-${gap.to}-${gap.raw}`,
      side: 1,
      ignoreSelection: true,
      stopEvent: (event) => (
        event.target instanceof Element &&
        event.target.closest('.writing-gap-action') !== null
      ),
    }));
  }

  return DecorationSet.create(state.doc, decorations);
}

function gapAtSelection(editor: Editor): WritingGap | null {
  const { from, to } = editor.state.selection;
  return writingGapsInDocument(editor.state.doc).find((gap) => (
    from <= gap.to && to >= gap.from && !pendingEditCoversGap(editor.state, gap)
  )) ?? null;
}

export function completeGapFill(
  editor: Editor,
  requestId: string,
  replacementText: string,
  rationale = '',
  errorMessage = ''
) {
  const request = gapFillRequests.get(requestId);
  if (!request) return;

  const fail = (message: string) => {
    request.status = 'error';
    request.errorMessage = message;
    refreshGapDecorations(editor);
  };

  if (errorMessage) {
    fail(errorMessage);
    return;
  }
  const text = replacementText.trim();
  if (!text || text.length > 4_000 || text.includes('[[') || text.includes(']]')) {
    fail('The suggestion was not usable. Click to try again.');
    return;
  }

  const range = mappedRequestRange(request);
  if (!range || currentTextForRange(editor, range.from, range.to) !== request.raw) {
    gapFillRequests.delete(requestId);
    refreshGapDecorations(editor);
    return;
  }
  const gap: WritingGap = { ...request, from: range.from, to: range.to };
  if (pendingEditCoversGap(editor.state, gap)) {
    gapFillRequests.delete(requestId);
    refreshGapDecorations(editor);
    return;
  }

  const editId = `edit_gap_${requestId}`;
  const edit = createPendingEdit(editor, {
    id: editId,
    groupId: editId,
    kind: 'selection',
    from: range.from,
    to: range.to,
    newHtml: plainTextAsHTML(text),
    metadata: {
      learningCategory: 'style',
      rationale: rationale.trim().slice(0, 500),
      instruction: request.instruction || 'Continue the surrounding text naturally.',
    },
  });

  gapFillRequests.delete(requestId);
  if (queuePendingEdits(editor, [edit], edit.id) <= 0) {
    request.status = 'error';
    request.errorMessage = 'Finish another suggestion, then try this gap again.';
    gapFillRequests.set(requestId, request);
    refreshGapDecorations(editor);
  }
}

export function resetGapSuggestionState() {
  gapFillRequests.clear();
}

export const WritingGapSuggestions = Extension.create({
  name: 'writingGapSuggestions',

  addKeyboardShortcuts() {
    return {
      'Mod-Enter': () => {
        const gap = gapAtSelection(this.editor);
        return gap ? requestGapFill(this.editor, gap) : false;
      },
    };
  },

  addProseMirrorPlugins() {
    const editor = this.editor;
    return [
      new Plugin<DecorationSet>({
        key: gapSuggestionsPluginKey,
        state: {
          init(_, state) {
            return buildGapDecorations(editor, state);
          },
          apply(tr, previous, _oldState, newState) {
            if (!tr.docChanged && !tr.selectionSet && !tr.getMeta(gapSuggestionsPluginKey)) {
              return previous;
            }
            return buildGapDecorations(editor, newState);
          },
        },
        props: {
          decorations(state) {
            return gapSuggestionsPluginKey.getState(state) ?? DecorationSet.empty;
          },
        },
      }),
    ];
  },
});
