import { Editor, Node as TiptapNode, mergeAttributes } from '@tiptap/core';
import { NodeSelection, Plugin, PluginKey, Transaction } from '@tiptap/pm/state';
import {
  FOOTNOTE_NODE_NAME,
  FOOTNOTE_PANEL_DEBOUNCE_MS,
  FocusedFootnoteEditorState,
  FootnoteDetails,
} from './types';
import { escapeHTML } from './utils';
import { smartifyQuotes } from './smartQuotes';
import { getDocumentTextSnapshot } from './docSync';

let footnotePanelDebounceTimer: ReturnType<typeof setTimeout> | null = null;
let lastRenderedFootnotesStructureSignature: string | null = null;

export function resetFootnotePanelState(): void {
  if (footnotePanelDebounceTimer) clearTimeout(footnotePanelDebounceTimer);
  lastRenderedFootnotesStructureSignature = null;
}

// Cached per-document footnote presence. ProseMirror docs are immutable, so a
// WeakMap keyed on the doc object is a correct cache; entries are seeded on
// the no-footnote fast path so consecutive keystrokes never rescan.
const footnotePresence = new WeakMap<object, boolean>();

function scanDocForFootnote(doc: any, type: any): boolean {
  let found = false;
  doc.descendants((node: any) => {
    if (found) return false;
    if (node.type === type) found = true;
    return !found;
  });
  return found;
}

function docContainsFootnote(doc: any, type: any): boolean {
  const cached = footnotePresence.get(doc);
  if (cached !== undefined) return cached;
  const result = scanDocForFootnote(doc, type);
  footnotePresence.set(doc, result);
  return result;
}

function sliceContainsFootnote(slice: any, type: any): boolean {
  const content = slice?.content;
  if (!content || typeof content.descendants !== 'function') return false;
  let found = false;
  content.descendants((node: any) => {
    if (found) return false;
    if (node.type === type) found = true;
    return !found;
  });
  return found;
}

export function transactionTouchesFootnotes(transaction: Transaction): boolean {
  if (!transaction.docChanged) return false;
  const type = transaction.doc.type.schema.nodes[FOOTNOTE_NODE_NAME];
  if (!type) return false;

  if (docContainsFootnote(transaction.before, type)) {
    footnotePresence.set(transaction.doc, true);
    return true;
  }

  const insertedFootnote = transaction.steps.some((step) => (
    sliceContainsFootnote((step as any).slice, type)
  ));
  footnotePresence.set(transaction.doc, insertedFootnote);
  return insertedFootnote;
}

function normalizeFootnoteNote(note: string): string {
  return smartifyQuotes(note.replace(/\r\n?/g, '\n'));
}

function createFootnoteID(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `footnote-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

export function collectFootnotes(doc: any): FootnoteDetails[] {
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

export function buildGeneratedFootnotesHTML(footnotes: FootnoteDetails[]): string {
  if (footnotes.length === 0) return '';

  const items = footnotes.map((footnote) => {
    const noteHTML = escapeHTML(footnote.note).replace(/\n/g, '<br>');
    return `<li id="footnote-${escapeHTML(footnote.id)}">${noteHTML}</li>`;
  });

  return `<section class="generated-footnotes" data-generated-footnotes="true"><hr><ol>${items.join('')}</ol></section>`;
}

export function footnotesSignature(footnotes: FootnoteDetails[]): string {
  return footnotes
    .map((footnote) => `${footnote.id}\u001f${footnote.index}\u001f${footnote.note}`)
    .join('\u001e');
}

export function footnotesStructureSignature(footnotes: FootnoteDetails[]): string {
  return footnotes
    .map((footnote) => `${footnote.id}\u001f${footnote.index}`)
    .join('\u001e');
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

export function renderFootnotesPanel(editor: Editor, force = false) {
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

export function scheduleFootnotesPanelRender(editor: Editor) {
  if (footnotePanelDebounceTimer) clearTimeout(footnotePanelDebounceTimer);
  footnotePanelDebounceTimer = setTimeout(() => {
    renderFootnotesPanel(editor);
  }, FOOTNOTE_PANEL_DEBOUNCE_MS);
}

export function getSelectedFootnote(editor: Editor): { node: any; pos: number } | null {
  const { selection } = editor.state;
  if (selection instanceof NodeSelection && selection.node.type.name === FOOTNOTE_NODE_NAME) {
    return { node: selection.node, pos: selection.from };
  }
  return null;
}

export function upsertFootnote(editor: Editor, note: string) {
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

export function removeSelectedFootnote(editor: Editor) {
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

export const Footnote = TiptapNode.create({
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
        appendTransaction(transactions, oldState, newState) {
          if (!transactions.some((transaction) => transaction.docChanged)) {
            return null;
          }

          // Fast path: when the document had no footnotes and none were
          // inserted, skip the full renumbering walk entirely.
          if (!docContainsFootnote(oldState.doc, type)) {
            const insertedFootnote = transactions.some((transaction) =>
              transaction.steps.some((step: any) => sliceContainsFootnote((step as any).slice, type)));
            if (!insertedFootnote) {
              footnotePresence.set(newState.doc, false);
              return null;
            }
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
