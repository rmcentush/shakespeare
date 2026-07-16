import { Editor, Extension, type JSONContent } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import Underline from '@tiptap/extension-underline';
import Placeholder from '@tiptap/extension-placeholder';
import TextAlign from '@tiptap/extension-text-align';
import Typography from '@tiptap/extension-typography';
import FontFamily from '@tiptap/extension-font-family';
import TextStyle from '@tiptap/extension-text-style';
import Color from '@tiptap/extension-color';
import { Plugin } from '@tiptap/pm/state';
import { sendToSwift, registerSwiftCallbacks } from './bridge';
import { setEditorInstance } from './instance';
import {
  AMBIGUOUS_EDIT_TARGET,
  INVALID_EDIT_TARGET,
  MAX_PENDING_FIND_REPLACE_MATCHES,
  PendingEditMetadata,
  ProposedEditTarget,
  STALE_EDIT_TARGET,
  SelectionEditTarget,
  TOO_MANY_MATCHES,
} from './types';
import {
  SmartQuotes,
  contextCharacterBefore,
  normalizeDocumentSmartQuotes,
  prepareReplacementHTMLForRange,
  smartifyHTMLFragment,
  smartifyQuotesWithContext,
} from './smartQuotes';
import {
  SearchHighlight,
  findTextInDoc,
  runClearFind,
  runFindInDocument,
  runFindNext,
  runFindPrevious,
  runReplaceAll,
  runReplaceOne,
} from './search';
import {
  isSafeDocumentImageSource,
  sanitizeDocumentHTML,
  sanitizeDocumentJSON,
  sanitizePastedHTML,
} from './sanitize';
import {
  attachSelectionChangeFallback,
  attachSmartQuotesNormalizationFallback,
  emitSelectionUpdate,
  getDocumentTextSnapshot,
  getDocumentRevision,
  mapPositionFromRevision,
  noteDocumentChanged,
  resetDocSyncState,
  scheduleContentUpdate,
  scheduleSelectionUpdate,
  serializeDocumentHTML,
  serializeDocumentPlainText,
  serializeSelectionClipboardData,
  updatePreservedTextSelection,
} from './docSync';
import {
  Footnote,
  removeSelectedFootnote,
  renderFootnotesPanel,
  resetFootnotePanelState,
  scheduleFootnotesPanelRender,
  transactionTouchesFootnotes,
  upsertFootnote,
} from './footnotes';
import {
  DocumentImage,
  insertedImageAttrs,
  resetSelectedImageCrop,
  setSelectedImageLayout,
} from './images';
import { HoverableLink, attachLinkHoverPreview } from './linkPreview';
import {
  CommentMark,
  addComment,
  addCommentAtRangeFromJSON,
  attachCommentActivation,
  collectComments,
  emitCommentsChanged,
  focusComment,
  pendingReplaceComment,
  removeComment,
  resetCommentsSignature,
  scheduleCommentsChanged,
  setCommentStatus,
  updateCommentText,
} from './comments';
import {
  PendingEditHighlight,
  acceptAllPendingEdits,
  acceptPendingEdit,
  acknowledgePersonalizationOutcomes,
  collectPersonalizationOutcomes,
  createPendingEdit,
  focusPendingEdit,
  focusRelativePendingEdit,
  getPendingEditsState,
  pendingEditsSummaryJSON,
  positionFromInsertionTarget,
  queuePendingEdits,
  queueProposedEdit,
  rangeFromSelectionTarget,
  rejectAllPendingEdits,
  rejectPendingEdit,
  resetPersonalizationOutcomeTracking,
  replacementPendingEdits,
} from './pendingEdits';
import { buildEditContextSnapshot } from './editContext';
import { attachProofreading } from './proofreading';

function resetEditorSyncState() {
  resetDocSyncState();
  resetFootnotePanelState();
  resetCommentsSignature();
  pendingImageImports.clear();
  resetPersonalizationOutcomeTracking();
}

interface PendingImageImport {
  from: number;
  to: number;
  revision: number;
}

const pendingImageImports = new Map<string, PendingImageImport>();
const MAX_IMAGE_IMPORT_BYTES = 25 * 1024 * 1024;

function requestImageImport(file: File, from: number, to: number) {
  if (file.size > MAX_IMAGE_IMPORT_BYTES) {
    window.alert('Images must be 25 MB or smaller.');
    return;
  }

  const requestId = crypto.randomUUID();
  pendingImageImports.set(requestId, {
    from,
    to,
    revision: getDocumentRevision(),
  });

  const reader = new FileReader();
  reader.onload = (event) => {
    const dataURL = event.target?.result;
    if (typeof dataURL !== 'string') {
      pendingImageImports.delete(requestId);
      return;
    }
    sendToSwift('imageImportRequested', {
      requestId,
      dataURL,
      filename: file.name,
    });
  };
  reader.onerror = () => pendingImageImports.delete(requestId);
  reader.readAsDataURL(file);
}

function completeImageImport(requestId: string, source: string, errorMessage = '') {
  const pending = pendingImageImports.get(requestId);
  pendingImageImports.delete(requestId);
  if (!pending) return;
  if (!source || !isSafeDocumentImageSource(source)) {
    if (errorMessage) console.error('Image import failed:', errorMessage);
    return;
  }

  const mappedFrom = mapPositionFromRevision(pending.revision, pending.from, 1);
  const mappedTo = mapPositionFromRevision(pending.revision, pending.to, -1);
  if (mappedFrom === null || mappedTo === null) return;

  const from = Math.min(mappedFrom, editor.state.doc.content.size);
  const to = Math.min(Math.max(mappedTo, from), editor.state.doc.content.size);
  const image = editor.state.schema.nodes.image.create(insertedImageAttrs(source));
  editor.view.dispatch(editor.state.tr.replaceRangeWith(from, to, image));
}

const editor = new Editor({
  element: document.getElementById('editor')!,
  extensions: [
    StarterKit.configure({
      heading: { levels: [1, 2, 3] },
    }),
    Underline,
    Placeholder.configure({
      placeholder: 'Start writing, paste a draft, or press ⌘O to open one…',
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
      allowBase64: false,
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
                    const { from, to } = editorRef.state.selection;
                    requestImageImport(file, from, to);
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
                    const coords = view.posAtCoords({
                      left: event.clientX,
                      top: event.clientY,
                    });
                    const position = coords?.pos ?? editorRef.state.selection.from;
                    requestImageImport(file, position, position);
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
      spellcheck: 'false',
      autocorrect: 'on',
    },
    transformPastedHTML(html, view) {
      return sanitizePastedHTML(html, contextCharacterBefore(view.state.doc, view.state.selection.from));
    },
    transformPastedText(text, _plain, view) {
      return smartifyQuotesWithContext(text, contextCharacterBefore(view.state.doc, view.state.selection.from));
    },
  },
  onUpdate({ editor, transaction }) {
    noteDocumentChanged(transaction);
    updatePreservedTextSelection(editor);
    scheduleSelectionUpdate(editor);
    scheduleContentUpdate(editor);
    if (transactionTouchesFootnotes(transaction)) {
      scheduleFootnotesPanelRender(editor);
    }
    scheduleCommentsChanged(editor, true);
  },
  onSelectionUpdate({ editor }) {
    updatePreservedTextSelection(editor);
    scheduleSelectionUpdate(editor);
  },
});

setEditorInstance(editor);
const proofreading = attachProofreading(editor);

function setEditorSpellcheckEnabled(enabled: boolean) {
  const dom = editor.view.dom as HTMLElement;
  dom.setAttribute('spellcheck', enabled ? 'true' : 'false');
}

function setEditorAutocorrectEnabled(enabled: boolean) {
  const dom = editor.view.dom as HTMLElement;
  dom.setAttribute('autocorrect', enabled ? 'on' : 'off');
}

function setEditorZoomScale(scale: number) {
  const normalizedScale = Number.isFinite(scale) ? Math.min(Math.max(scale, 0.5), 2) : 1;
  document.documentElement.style.setProperty('--editor-zoom-scale', normalizedScale.toString());
}

// Register callbacks for Swift to call into JS
registerSwiftCallbacks({
  loadContent(html: string) {
    resetEditorSyncState();
    rejectAllPendingEdits(editor, false);
    editor.commands.setContent(sanitizeDocumentHTML(html), false);
    normalizeDocumentSmartQuotes(editor);
    renderFootnotesPanel(editor, true);
    emitSelectionUpdate(editor);
    emitCommentsChanged(editor, true);
  },
  loadJSONContent(json: string) {
    resetEditorSyncState();
    try {
      rejectAllPendingEdits(editor, false);
      const parsed = sanitizeDocumentJSON(JSON.parse(json));
      if (!parsed || typeof parsed !== 'object') {
        throw new Error('Document JSON must contain an object root');
      }
      editor.commands.setContent(parsed as JSONContent, false);
      normalizeDocumentSmartQuotes(editor);
      renderFootnotesPanel(editor, true);
      emitSelectionUpdate(editor);
      emitCommentsChanged(editor, true);
    } catch (error) {
      console.error('Failed to load JSON content into editor', error);
    }
  },
  getContent(): string {
    return serializeDocumentHTML(editor);
  },
  getDocumentSnapshot(): unknown {
    const snapshot = getDocumentTextSnapshot(editor);
    return {
      html: serializeDocumentHTML(editor),
      json: editor.getJSON(),
      text: snapshot.plainText,
      words: snapshot.words,
      characters: snapshot.characters,
      personalizationOutcomes: collectPersonalizationOutcomes(editor),
    };
  },
  acknowledgePersonalizationOutcomes(actionIds: string[]) {
    acknowledgePersonalizationOutcomes(Array.isArray(actionIds) ? actionIds : []);
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
  setProofreadingOptions(spelling: boolean, grammar: boolean, dialect: string) {
    proofreading.setOptions(spelling, grammar, dialect);
  },
  setAIGrammarIssues(json: string) {
    proofreading.setAIGrammarIssues(json);
  },
  resetProofreadingDictionary() {
    proofreading.resetDictionary();
  },
  getProofreadingState(): string {
    return proofreading.stateJSON();
  },
  getGrammarContextSnapshot(): string {
    return proofreading.grammarContextJSON();
  },
  completeImageImport(requestId: string, source: string, errorMessage = '') {
    completeImageImport(requestId, source, errorMessage);
  },
  setZoomScale(scale: number) {
    setEditorZoomScale(scale);
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
    return runFindInDocument(editor, query);
  },
  findNext(): string {
    return runFindNext(editor);
  },
  findPrevious(): string {
    return runFindPrevious(editor);
  },
  replaceOne(replacement: string): string {
    return runReplaceOne(editor, replacement);
  },
  replaceAll(replacement: string): number {
    return runReplaceAll(editor, replacement);
  },
  clearFind() {
    runClearFind(editor);
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
  pendingReplaceSelection(
    id: string,
    newHtml: string,
    target?: SelectionEditTarget,
    metadata?: PendingEditMetadata
  ): number {
    const targetedRange = rangeFromSelectionTarget(editor, target ?? null);
    if (typeof targetedRange === 'number') return targetedRange;

    const { from, to } = targetedRange ?? editor.state.selection;
    if (from === to) return 0;
    const edits = replacementPendingEdits(editor, id, { from, to }, newHtml, 'selection').map((edit) => ({
      ...edit,
      learningCategory: metadata?.learningCategory ?? '',
      rationale: metadata?.rationale ?? '',
      instruction: metadata?.instruction ?? '',
    }));
    return queuePendingEdits(editor, edits, edits[0]?.id ?? null);
  },
  pendingInsertAtCursor(
    id: string,
    newHtml: string,
    target?: SelectionEditTarget,
    metadata?: PendingEditMetadata
  ): number {
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
        metadata,
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
    const edits = toAdd.flatMap((match, i) => {
      const groupId = replaceAll ? `${id}_${i}` : id;
      return replacementPendingEdits(editor, groupId, match, replaceHtml, 'findReplace');
    });
    return queuePendingEdits(editor, edits, edits[0]?.id ?? null);
  },
  pendingProposeEdit(
    id: string,
    target: ProposedEditTarget,
    replaceHtml: string,
    replaceAll: boolean,
    metadata?: PendingEditMetadata
  ): number {
    return queueProposedEdit(editor, id, target ?? {}, replaceHtml, replaceAll, metadata);
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
