import { Editor, Extension, Node as TiptapNode, mergeAttributes } from '@tiptap/core';
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
import { Plugin, PluginKey, NodeSelection } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';
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

const searchPluginKey = new PluginKey('searchHighlight');

// --- Pending Edits (Cursor-like diff review) ---
interface PendingEdit {
  id: string;
  from: number;
  to: number;
  newHtml: string;
}

let pendingEdits: PendingEdit[] = [];
let currentEditIdx = -1;
let isApplyingPendingEdit = false;
const pendingEditPluginKey = new PluginKey('pendingEdits');

function updatePendingDecorations(ed: Editor) {
  const tr = ed.state.tr.setMeta(pendingEditPluginKey, true);
  ed.view.dispatch(tr);
}

function scrollToPendingEdit(ed: Editor, edit: PendingEdit) {
  try {
    const domAtPos = ed.view.domAtPos(edit.from);
    const node = domAtPos.node as HTMLElement;
    const el = node.nodeType === Node.TEXT_NODE ? node.parentElement : node;
    el?.scrollIntoView({ behavior: 'smooth', block: 'center' });
  } catch (_) {}
}

function notifyPendingEditCount() {
  sendToSwift('pendingEditUpdate', {
    count: pendingEdits.length,
    currentIndex: currentEditIdx,
  });
}

function acceptCurrentPendingEdit(ed: Editor) {
  if (currentEditIdx < 0 || currentEditIdx >= pendingEdits.length) return;
  const edit = pendingEdits[currentEditIdx];
  const sizeBefore = ed.state.doc.content.size;

  pendingEdits.splice(currentEditIdx, 1);

  isApplyingPendingEdit = true;
  ed.chain().insertContentAt({ from: edit.from, to: edit.to }, edit.newHtml).run();
  isApplyingPendingEdit = false;

  const offset = ed.state.doc.content.size - sizeBefore;
  for (const r of pendingEdits) {
    if (r.from >= edit.to) {
      r.from += offset;
      r.to += offset;
    }
  }

  if (currentEditIdx >= pendingEdits.length) {
    currentEditIdx = pendingEdits.length > 0 ? 0 : -1;
  }
  updatePendingDecorations(ed);
  notifyPendingEditCount();
  if (currentEditIdx >= 0) scrollToPendingEdit(ed, pendingEdits[currentEditIdx]);
}

function rejectCurrentPendingEdit(ed: Editor) {
  if (currentEditIdx < 0 || currentEditIdx >= pendingEdits.length) return;
  pendingEdits.splice(currentEditIdx, 1);
  if (currentEditIdx >= pendingEdits.length) {
    currentEditIdx = pendingEdits.length > 0 ? 0 : -1;
  }
  updatePendingDecorations(ed);
  notifyPendingEditCount();
  if (currentEditIdx >= 0) scrollToPendingEdit(ed, pendingEdits[currentEditIdx]);
}

function acceptAllPendingEdits(ed: Editor) {
  if (pendingEdits.length === 0) return;
  const sorted = [...pendingEdits].sort((a, b) => b.from - a.from);
  pendingEdits = [];
  currentEditIdx = -1;

  isApplyingPendingEdit = true;
  for (const edit of sorted) {
    ed.chain().insertContentAt({ from: edit.from, to: edit.to }, edit.newHtml).run();
  }
  isApplyingPendingEdit = false;

  updatePendingDecorations(ed);
  notifyPendingEditCount();
}

function rejectAllPendingEdits(ed: Editor) {
  pendingEdits = [];
  currentEditIdx = -1;
  updatePendingDecorations(ed);
  notifyPendingEditCount();
}

function canQueuePendingEdits(count: number): boolean {
  return pendingEdits.length + count <= MAX_PENDING_EDITS;
}

const PendingEditHighlight = Extension.create({
  name: 'pendingEditHighlight',

  addKeyboardShortcuts() {
    return {
      'Tab': () => {
        if (pendingEdits.length === 0) return false;
        acceptCurrentPendingEdit(this.editor);
        return true;
      },
      'Shift-Tab': () => {
        if (pendingEdits.length === 0) return false;
        rejectCurrentPendingEdit(this.editor);
        return true;
      },
      'Escape': () => {
        if (pendingEdits.length === 0) return false;
        rejectAllPendingEdits(this.editor);
        return true;
      },
      'Mod-Shift-Enter': () => {
        if (pendingEdits.length === 0) return false;
        acceptAllPendingEdits(this.editor);
        return true;
      },
    };
  },

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: pendingEditPluginKey,
        state: {
          init() { return DecorationSet.empty; },
          apply(tr, oldSet, _oldState, newState) {
            const meta = tr.getMeta(pendingEditPluginKey);
            if (meta !== undefined) {
              if (pendingEdits.length === 0) return DecorationSet.empty;
              const decorations: Decoration[] = [];
              pendingEdits.forEach((edit, i) => {
                const isActive = i === currentEditIdx;
                // Strikethrough on old text
                if (edit.from < edit.to) {
                  decorations.push(
                    Decoration.inline(edit.from, edit.to, {
                      class: isActive ? 'pending-edit-delete pending-edit-active' : 'pending-edit-delete',
                    })
                  );
                }
                // Widget showing new content
                decorations.push(
                  Decoration.widget(edit.to, () => {
                    const span = document.createElement('span');
                    span.className = isActive
                      ? 'pending-edit-insert pending-edit-active'
                      : 'pending-edit-insert';
                    span.contentEditable = 'false';
                    span.innerHTML = edit.newHtml;
                    return span;
                  }, { side: 1 })
                );
              });
              return DecorationSet.create(newState.doc, decorations);
            }
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
  return note.replace(/\r\n?/g, '\n').trim();
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

function appendMultilineText(container: HTMLElement, text: string) {
  const lines = text.split('\n');
  lines.forEach((line, index) => {
    if (index > 0) {
      container.appendChild(document.createElement('br'));
    }
    container.appendChild(document.createTextNode(line));
  });
}

function buildGeneratedFootnotesSection(doc: any): HTMLElement | null {
  const footnotes = collectFootnotes(doc);
  if (footnotes.length === 0) return null;

  const section = document.createElement('section');
  section.className = 'generated-footnotes';
  section.setAttribute('data-generated-footnotes', 'true');

  const divider = document.createElement('hr');
  section.appendChild(divider);

  const list = document.createElement('ol');
  footnotes.forEach((footnote) => {
    const item = document.createElement('li');
    item.id = `footnote-${footnote.id}`;
    appendMultilineText(item, footnote.note);
    list.appendChild(item);
  });

  section.appendChild(list);
  return section;
}

function renderFootnotesPanel(editor: Editor) {
  const container = document.getElementById('footnotes');
  if (!container) return;

  const footnotes = collectFootnotes(editor.state.doc);
  container.replaceChildren();

  if (footnotes.length === 0) {
    container.setAttribute('hidden', 'true');
    return;
  }

  container.removeAttribute('hidden');

  const title = document.createElement('div');
  title.className = 'editor-footnotes-title';
  title.textContent = 'Footnotes';
  container.appendChild(title);

  const list = document.createElement('ol');
  list.className = 'editor-footnotes-list';

  footnotes.forEach((footnote) => {
    const item = document.createElement('li');
    item.id = `editor-footnote-${footnote.id}`;

    const note = document.createElement('span');
    note.className = 'editor-footnote-note';
    appendMultilineText(note, footnote.note);
    item.appendChild(note);

    list.appendChild(item);
  });

  container.appendChild(list);
}

function serializeDocumentHTML(editor: Editor): string {
  const content = editor.getHTML();
  const footnotesSection = buildGeneratedFootnotesSection(editor.state.doc);
  return footnotesSection ? `${content}${footnotesSection.outerHTML}` : content;
}

function serializeDocumentPlainText(editor: Editor): string {
  const text = editor.getText();
  const footnotes = collectFootnotes(editor.state.doc);

  if (footnotes.length === 0) {
    return text;
  }

  const footnotesText = footnotes
    .map((footnote) => `[${footnote.index}] ${footnote.note}`)
    .join('\n');

  return text.trim().length > 0
    ? `${text}\n\nFootnotes\n${footnotesText}`
    : `Footnotes\n${footnotesText}`;
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

      const updateElement = (currentNode: any) => {
        element.textContent = String(currentNode.attrs.index || '?');
        element.title = (currentNode.attrs.note as string) || '';
        element.dataset.footnoteId = (currentNode.attrs.id as string) || '';
        element.dataset.footnoteIndex = String(currentNode.attrs.index || 0);
        element.dataset.footnoteNote = (currentNode.attrs.note as string) || '';
      };

      const handleMouseDown = (event: MouseEvent) => {
        event.preventDefault();
        event.stopPropagation();

        if (typeof getPos !== 'function') return;
        const pos = getPos();
        if (typeof pos === 'number') {
          editor.commands.focus();
          editor.view.dispatch(
            editor.state.tr.setSelection(NodeSelection.create(editor.state.doc, pos))
          );
        }
      };

      updateElement(node);
      element.addEventListener('mousedown', handleMouseDown);

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
          element.removeEventListener('mousedown', handleMouseDown);
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

let debounceTimer: ReturnType<typeof setTimeout> | null = null;
let selectionDebounceTimer: ReturnType<typeof setTimeout> | null = null;

function countWords(text: string): number {
  const trimmed = text.trim();
  if (!trimmed) return 0;
  return trimmed.split(/\s+/).length;
}

const PASTE_STYLE_PROPERTIES = [
  'font-family',
  'color',
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
    },
    transformPastedHTML(html) {
      return sanitizePastedHTML(html);
    },
  },
  onUpdate({ editor }) {
    // If user makes a manual edit while pending edits exist, clear them
    if (pendingEdits.length > 0 && !isApplyingPendingEdit) {
      pendingEdits = [];
      currentEditIdx = -1;
      updatePendingDecorations(editor);
      notifyPendingEditCount();
    }
    renderFootnotesPanel(editor);
    // Debounce content changes to avoid flooding Swift
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
      const html = serializeDocumentHTML(editor);
      const text = serializeDocumentPlainText(editor);
      sendToSwift('contentUpdate', {
        html,
        text,
        words: countWords(text),
        characters: text.length,
      });
    }, 300);
  },
  onSelectionUpdate({ editor }) {
    if (selectionDebounceTimer) clearTimeout(selectionDebounceTimer);
    selectionDebounceTimer = setTimeout(() => {
      const { from, to } = editor.state.selection;
      const selectedFootnote = getSelectedFootnote(editor);
      renderFootnotesPanel(editor);
      sendToSwift('selectionChanged', {
        from,
        to,
        hasSelection: from !== to,
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
      });
    }, 80);
  },
});

// Register callbacks for Swift to call into JS
registerSwiftCallbacks({
  loadContent(html: string) {
    editor.commands.setContent(stripGeneratedFootnotesSection(html), false);
    renderFootnotesPanel(editor);
  },
  loadJSONContent(json: string) {
    try {
      const parsed = JSON.parse(json);
      editor.commands.setContent(parsed, false);
      renderFootnotesPanel(editor);
    } catch (error) {
      console.error('Failed to load JSON content into editor', error);
    }
  },
  getContent(): string {
    return serializeDocumentHTML(editor);
  },
  getDocumentSnapshot(): string {
    const text = serializeDocumentPlainText(editor);
    return JSON.stringify({
      html: serializeDocumentHTML(editor),
      json: editor.getJSON(),
      text,
      words: countWords(text),
      characters: text.length,
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
  },
  insertHTMLAtCursor(html: string) {
    editor.chain().focus().insertContent(html).run();
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
    return toReplace.length;
  },

  // --- Pending Edits API (Cursor-like diff review) ---
  pendingReplaceSelection(id: string, newHtml: string): number {
    const { from, to } = editor.state.selection;
    if (from === to) return 0;
    if (!canQueuePendingEdits(1)) return TOO_MANY_PENDING_EDITS;
    pendingEdits.push({ id, from, to, newHtml });
    if (currentEditIdx < 0) currentEditIdx = 0;
    updatePendingDecorations(editor);
    notifyPendingEditCount();
    scrollToPendingEdit(editor, pendingEdits[pendingEdits.length - 1]);
    return 1;
  },
  pendingInsertAtCursor(id: string, newHtml: string): number {
    const { from } = editor.state.selection;
    if (!canQueuePendingEdits(1)) return TOO_MANY_PENDING_EDITS;
    pendingEdits.push({ id, from, to: from, newHtml });
    if (currentEditIdx < 0) currentEditIdx = 0;
    updatePendingDecorations(editor);
    notifyPendingEditCount();
    scrollToPendingEdit(editor, pendingEdits[pendingEdits.length - 1]);
    return 1;
  },
  pendingFindAndReplace(id: string, find: string, replaceHtml: string, replaceAll: boolean): number {
    const maxMatches = replaceAll ? MAX_PENDING_FIND_REPLACE_MATCHES + 1 : 1;
    const matches = findTextInDoc(editor.state.doc, find, maxMatches);
    if (matches.length === 0) return 0;
    if (replaceAll && matches.length > MAX_PENDING_FIND_REPLACE_MATCHES) {
      return TOO_MANY_MATCHES;
    }
    const toAdd = replaceAll ? matches : [matches[0]];
    if (!canQueuePendingEdits(toAdd.length)) return TOO_MANY_PENDING_EDITS;
    toAdd.forEach((match, i) => {
      pendingEdits.push({ id: `${id}_${i}`, from: match.from, to: match.to, newHtml: replaceHtml });
    });
    if (currentEditIdx < 0) currentEditIdx = 0;
    updatePendingDecorations(editor);
    notifyPendingEditCount();
    scrollToPendingEdit(editor, pendingEdits[pendingEdits.length - toAdd.length]);
    return toAdd.length;
  },
  acceptAllPendingEdits() { acceptAllPendingEdits(editor); },
  rejectAllPendingEdits() { rejectAllPendingEdits(editor); },
  getPendingEditCount(): number { return pendingEdits.length; },
});

attachLinkHoverPreview(editor);
renderFootnotesPanel(editor);

// Notify Swift that editor is ready
sendToSwift('editorReady', {});
