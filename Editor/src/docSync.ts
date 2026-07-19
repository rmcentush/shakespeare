import { Editor, getText, getTextSerializersFromSchema } from '@tiptap/core';
import { TextSelection, Transaction } from '@tiptap/pm/state';
import { Mapping } from '@tiptap/pm/transform';
import { sendToSwift } from './bridge';
import {
  CONTENT_SYNC_DEBOUNCE_MS,
  DocumentTextSnapshot,
  EditorSelectionState,
  FootnoteDetails,
  PreservedTextSelection,
  SELECTION_SYNC_DEBOUNCE_MS,
  SearchMatch,
  SelectionClipboardData,
} from './types';
import { countWords } from './utils';
import {
  buildGeneratedFootnotesHTML,
  collectFootnotes,
  footnotesSignature,
  footnotesStructureSignature,
  getSelectedFootnote,
} from './footnotes';
import { normalizeImageAlign, normalizeImageLayout, selectedImageNode } from './images';
import { scheduleSmartQuotesNormalization } from './smartQuotes';
import {
  selectedLineHeight,
  selectedTextAlignment,
  selectedTextStyleAttribute,
} from './typography';

let documentRevision = 0;
let cachedDocumentTextSnapshot: DocumentTextSnapshot | null = null;
let cachedSerializedHTMLRevision = -1;
let cachedSerializedHTML = '';
let lastSentContentUpdate: { html: string; text: string } | null = null;
let lastSentMetricsRevision = -1;
let lastSentSelectionState: EditorSelectionState | null = null;
let preservedTextSelection: PreservedTextSelection | null = null;
const blockTextCache = new WeakMap<object, { text: string; words: number; hasVisibleText: boolean }>();

let contentSyncDebounceTimer: ReturnType<typeof setTimeout> | null = null;
let selectionDebounceTimer: ReturnType<typeof setTimeout> | null = null;

export function getDocumentRevision(): number {
  return documentRevision;
}

// Rolling history of transaction mappings, one entry per document revision
// bump. Lets edit targets captured at an older revision (e.g. while the assistant is
// streaming and the user keeps typing) be mapped forward to current positions
// instead of being rejected as stale.
interface RevisionMapping {
  revision: number;
  mapping: Mapping;
}

const revisionMappings: RevisionMapping[] = [];
const MAX_REVISION_MAPPINGS = 500;

export function noteDocumentChanged(tr: Transaction | null | undefined): void {
  if (tr?.docChanged) {
    revisionMappings.push({ revision: documentRevision, mapping: tr.mapping });
    if (revisionMappings.length > MAX_REVISION_MAPPINGS) {
      revisionMappings.splice(0, revisionMappings.length - MAX_REVISION_MAPPINGS);
    }
  }
  invalidateDerivedDocumentState();
}

export function mapPositionFromRevision(
  revision: number,
  pos: number,
  assoc: -1 | 1
): number | null {
  if (revision === documentRevision) return pos;
  if (revision > documentRevision) return null;

  const startIndex = revisionMappings.findIndex((entry) => entry.revision === revision);
  if (startIndex === -1) return null;

  let expectedRevision = revision;
  let mapped = pos;
  for (let index = startIndex; index < revisionMappings.length; index += 1) {
    // A gap means some revision bump had no recorded mapping; we can't
    // bridge across it safely.
    if (revisionMappings[index].revision !== expectedRevision) return null;
    mapped = revisionMappings[index].mapping.map(mapped, assoc);
    expectedRevision += 1;
  }

  return expectedRevision === documentRevision ? mapped : null;
}

export function mapRangeFromRevision(
  revision: number,
  from: number,
  to: number
): SearchMatch | null {
  const mappedFrom = mapPositionFromRevision(revision, from, 1);
  const mappedTo = mapPositionFromRevision(revision, to, -1);
  if (mappedFrom === null || mappedTo === null || mappedTo <= mappedFrom) return null;
  return { from: mappedFrom, to: mappedTo };
}

export function setPreservedTextSelection(selection: PreservedTextSelection | null): void {
  preservedTextSelection = selection;
}

export function resetDocSyncState(): void {
  if (contentSyncDebounceTimer) clearTimeout(contentSyncDebounceTimer);
  if (selectionDebounceTimer) clearTimeout(selectionDebounceTimer);

  invalidateDerivedDocumentState();
  revisionMappings.length = 0;
  lastSentContentUpdate = null;
  lastSentMetricsRevision = -1;
  lastSentSelectionState = null;
  preservedTextSelection = null;
}

function cachedDocumentText(editor: Editor): { text: string; words: number } {
  const parts: string[] = [];
  let words = 0;
  const textSerializers = getTextSerializersFromSchema(editor.schema);

  editor.state.doc.forEach((node) => {
    let cached = blockTextCache.get(node);
    if (!cached) {
      // getText(doc) emits a separator for a top-level container's first block
      // child; getText(container) starts that child at position zero and omits
      // it. Restore that boundary so cached top-level pieces join identically.
      const leadingContainerSeparator = node.firstChild?.isBlock ? '\n\n' : '';
      const text = leadingContainerSeparator
        + getText(node, { blockSeparator: '\n\n', textSerializers });
      cached = { text, words: countWords(text), hasVisibleText: text.trim().length > 0 };
      blockTextCache.set(node, cached);
    }
    parts.push(cached.text);
    words += cached.words;
  });

  return { text: parts.join('\n\n'), words };
}

function largeDocumentMetrics(editor: Editor): { words: number; characters: number } {
  const textSerializers = getTextSerializersFromSchema(editor.schema);
  let words = 0;
  let characters = 0;
  let topLevelNodes = 0;
  let hasVisibleText = false;

  editor.state.doc.forEach((node) => {
    let cached = blockTextCache.get(node);
    if (!cached) {
      const leadingContainerSeparator = node.firstChild?.isBlock ? '\n\n' : '';
      const text = leadingContainerSeparator
        + getText(node, { blockSeparator: '\n\n', textSerializers });
      cached = { text, words: countWords(text), hasVisibleText: text.trim().length > 0 };
      blockTextCache.set(node, cached);
    }
    if (topLevelNodes > 0) characters += 2;
    topLevelNodes += 1;
    characters += cached.text.length;
    words += cached.words;
    hasVisibleText ||= cached.hasVisibleText;
  });

  const footnotes = collectFootnotes(editor.state.doc);
  if (footnotes.length > 0) {
    const footnotesText = footnotes
      .map((footnote) => `[${footnote.index}] ${footnote.note}`)
      .join('\n');
    characters += (hasVisibleText ? 2 : 0) + 'Footnotes\n'.length + footnotesText.length;
    words += 1 + countWords(footnotesText);
  }
  return { words, characters };
}

function buildPlainTextSnapshot(editor: Editor, footnotes: FootnoteDetails[]): DocumentTextSnapshot {
  const documentText = cachedDocumentText(editor);
  const text = documentText.text;

  if (footnotes.length === 0) {
    return {
      revision: documentRevision,
      footnotes,
      footnotesSignature: '',
      footnotesStructureSignature: '',
      plainText: text,
      words: documentText.words,
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

export function invalidateDerivedDocumentState() {
  documentRevision += 1;
  cachedDocumentTextSnapshot = null;
  cachedSerializedHTMLRevision = -1;
  cachedSerializedHTML = '';
}

export function getDocumentTextSnapshot(editor: Editor): DocumentTextSnapshot {
  if (cachedDocumentTextSnapshot?.revision === documentRevision) {
    return cachedDocumentTextSnapshot;
  }

  const snapshot = buildPlainTextSnapshot(editor, collectFootnotes(editor.state.doc));
  cachedDocumentTextSnapshot = snapshot;
  return snapshot;
}

export function serializeDocumentPlainText(editor: Editor): string {
  return getDocumentTextSnapshot(editor).plainText;
}

export function serializeDocumentHTML(editor: Editor): string {
  if (cachedSerializedHTMLRevision === documentRevision) {
    return cachedSerializedHTML;
  }

  const content = editor.getHTML();
  const footnotesHTML = buildGeneratedFootnotesHTML(getDocumentTextSnapshot(editor).footnotes);
  cachedSerializedHTML = footnotesHTML ? `${content}${footnotesHTML}` : content;
  cachedSerializedHTMLRevision = documentRevision;
  return cachedSerializedHTML;
}

export function serializeClipboardDataForRange(
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

export function serializeSelectionClipboardData(editor: Editor): SelectionClipboardData {
  const { from, to } = editor.state.selection;
  return serializeClipboardDataForRange(editor, from, to);
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

export function updatePreservedTextSelection(editor: Editor) {
  const selection = currentTextSelection(editor);
  if (selection) {
    preservedTextSelection = selection;
    return;
  }

  if (editorHasFocus(editor)) {
    preservedTextSelection = null;
  }
}

export function effectiveTextSelection(editor: Editor): PreservedTextSelection | null {
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
  const textColor = selectedTextStyleAttribute(editor, 'color');
  const fontFamily = selectedTextStyleAttribute(editor, 'fontFamily');
  const fontSize = selectedTextStyleAttribute(editor, 'fontSize');
  const lineHeight = selectedLineHeight(editor);
  const textAlign = selectedTextAlignment(editor);

  return {
    hasSelection: activeSelection !== null,
    selectedWords: activeSelection?.words || 0,
    selectedCharacters: activeSelection?.characters || 0,
    isBold: editor.isActive('bold'),
    isItalic: editor.isActive('italic'),
    isUnderline: editor.isActive('underline'),
    isStrike: editor.isActive('strike'),
    isBulletList: editor.isActive('bulletList'),
    isOrderedList: editor.isActive('orderedList'),
    isBlockquote: editor.isActive('blockquote'),
    heading: editor.isActive('heading', { level: 1 })
      ? 1
      : editor.isActive('heading', { level: 2 })
        ? 2
        : editor.isActive('heading', { level: 3 })
          ? 3
          : 0,
    textAlign,
    isLink: editor.isActive('link'),
    linkHref: editor.getAttributes('link').href || '',
    textColor: textColor.value,
    isTextColorMixed: textColor.mixed,
    fontFamily: fontFamily.value,
    isFontFamilyMixed: fontFamily.mixed,
    fontSize: fontSize.value,
    isFontSizeMixed: fontSize.mixed,
    lineHeight: lineHeight.value,
    isLineHeightMixed: lineHeight.mixed,
    isFootnote: selectedFootnote !== null,
    footnoteText: (selectedFootnote?.node.attrs.note as string) || '',
    isImage: selectedImage !== null,
    imageLayout: normalizeImageLayout(selectedImageAttrs.layout),
    imageAlign: normalizeImageAlign(selectedImageAttrs.align),
    imageWidth: (selectedImageAttrs.width as string) || '',
    imageHeight: (selectedImageAttrs.height as string) || '',
    imageAlt: (selectedImageAttrs.alt as string) || '',
    imageDecorative: selectedImageAttrs.decorative === true,
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
    a.isStrike === b.isStrike &&
    a.isBulletList === b.isBulletList &&
    a.isOrderedList === b.isOrderedList &&
    a.isBlockquote === b.isBlockquote &&
    a.heading === b.heading &&
    a.textAlign === b.textAlign &&
    a.isLink === b.isLink &&
    a.linkHref === b.linkHref &&
    a.textColor === b.textColor &&
    a.isTextColorMixed === b.isTextColorMixed &&
    a.fontFamily === b.fontFamily &&
    a.isFontFamilyMixed === b.isFontFamilyMixed &&
    a.fontSize === b.fontSize &&
    a.isFontSizeMixed === b.isFontSizeMixed &&
    a.lineHeight === b.lineHeight &&
    a.isLineHeightMixed === b.isLineHeightMixed &&
    a.isFootnote === b.isFootnote &&
    a.footnoteText === b.footnoteText &&
    a.isImage === b.isImage &&
    a.imageLayout === b.imageLayout &&
    a.imageAlign === b.imageAlign &&
    a.imageWidth === b.imageWidth &&
    a.imageHeight === b.imageHeight &&
    a.imageAlt === b.imageAlt &&
    a.imageDecorative === b.imageDecorative;
}

export function emitContentUpdate(editor: Editor) {
  // Large documents remain responsive by keeping the frequent bridge message
  // bounded. Full HTML/JSON/text is captured only at persistence or an explicit
  // feature request.
  if (editor.state.doc.content.size > 512_000) {
    if (lastSentMetricsRevision === documentRevision) return;
    const metrics = largeDocumentMetrics(editor);
    lastSentMetricsRevision = documentRevision;
    sendToSwift('documentMetrics', {
      revision: documentRevision,
      words: metrics.words,
      characters: metrics.characters,
    });
    return;
  }
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

export function emitSelectionUpdate(editor: Editor) {
  const selectionState = buildSelectionState(editor);
  if (selectionStatesEqual(lastSentSelectionState, selectionState)) {
    return;
  }

  lastSentSelectionState = selectionState;
  sendToSwift('selectionChanged', selectionState);
}

export function scheduleSelectionUpdate(editor: Editor) {
  if (selectionDebounceTimer) clearTimeout(selectionDebounceTimer);
  selectionDebounceTimer = setTimeout(() => {
    emitSelectionUpdate(editor);
  }, SELECTION_SYNC_DEBOUNCE_MS);
}

export function scheduleContentUpdate(editor: Editor) {
  if (contentSyncDebounceTimer) clearTimeout(contentSyncDebounceTimer);
  contentSyncDebounceTimer = setTimeout(() => {
    emitContentUpdate(editor);
  }, CONTENT_SYNC_DEBOUNCE_MS);
}

export function attachSelectionChangeFallback(editor: Editor) {
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

export function attachSmartQuotesNormalizationFallback(editor: Editor) {
  const root = editor.view.dom as HTMLElement;
  const normalizeSoon = () => {
    scheduleSmartQuotesNormalization(editor);
  };

  root.addEventListener('paste', normalizeSoon);
  root.addEventListener('drop', normalizeSoon);
}
