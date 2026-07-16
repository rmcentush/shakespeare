// Shared interfaces, type aliases, and constants used across editor feature modules.

// --- Search / Find & Replace ---
export interface SearchMatch {
  from: number;
  to: number;
}

export interface SearchIndexRange {
  from: number;
  to: number;
}

export interface SearchIndex {
  text: string;
  ranges: SearchIndexRange[];
}

export interface SearchIndexBuilder {
  text: string;
  ranges: SearchIndexRange[];
  lastWasWhitespace: boolean;
}

export interface FootnoteDetails {
  id: string;
  index: number;
  note: string;
  pos: number;
}

export interface EditorSelectionState {
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

export type ImageLayout = 'inline' | 'block' | 'float-left' | 'float-right';
export type ImageAlign = 'left' | 'center' | 'right';
export type ImageHandleDirection = 'n' | 'ne' | 'e' | 'se' | 's' | 'sw' | 'w' | 'nw';

export interface ImageCropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export interface DocumentTextSnapshot {
  revision: number;
  footnotes: FootnoteDetails[];
  footnotesSignature: string;
  footnotesStructureSignature: string;
  plainText: string;
  words: number;
  characters: number;
}

export interface SelectionClipboardData {
  html: string;
  text: string;
  imageSources: string[];
  singleImageSource: string | null;
}

export interface FocusedFootnoteEditorState {
  id: string;
  selectionStart: number;
  selectionEnd: number;
  scrollTop: number;
}

export interface PreservedTextSelection {
  from: number;
  to: number;
  text: string;
  words: number;
  characters: number;
  revision: number;
}

export interface EditContextBlock {
  id: string;
  path: string;
  type: string;
  from: number;
  to: number;
  text: string;
  textHash: string;
}

export interface EditContextPlaceholder {
  blockId: string;
  from: number;
  to: number;
  text: string;
}

export interface EditContextSelection {
  from: number;
  to: number;
  text: string;
  html: string;
  words: number;
  characters: number;
}

export interface EditContextSnapshot {
  revision: number;
  documentHash: string;
  plainText: string;
  cursorPosition: number;
  nearbyText: string;
  selection: EditContextSelection | null;
  blocks: EditContextBlock[];
  placeholders: EditContextPlaceholder[];
}

export interface ProposedEditTarget {
  block_id?: string;
  exact_original?: string;
  prefix?: string;
  suffix?: string;
  occurrence_index?: number;
  document_revision?: number;
  document_hash?: string;
}

export interface SelectionEditTarget {
  from?: number;
  to?: number;
  text?: string;
  position?: number;
  document_revision?: number;
  document_hash?: string;
}

export interface SentenceRange {
  from: number;
  to: number;
  text: string;
}

// --- Pending Edits (Cursor-like diff review) ---
export type PendingEditKind = 'selection' | 'insert' | 'findReplace' | 'delete';
export type PendingEditStatus = 'pending' | 'conflicted';

export interface PendingEdit {
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

// --- Limits ---
export const MAX_SEARCH_RESULTS = 500;
export const MAX_PENDING_EDITS = 120;
export const MAX_PENDING_FIND_REPLACE_MATCHES = 60;
export const MAX_EDIT_CONTEXT_BLOCKS = 160;
export const MAX_EDIT_CONTEXT_BLOCK_TEXT = 900;
export const NEARBY_EDIT_CONTEXT_CHARS = 900;

// Tool execution result codes returned to Swift from the editorAPI edit
// methods. Must match ToolExecutionResult in AssistantChatViewModel.swift.
export const TOO_MANY_MATCHES = -1;
export const TOO_MANY_PENDING_EDITS = -2;
export const AMBIGUOUS_EDIT_TARGET = -3;
export const STALE_EDIT_TARGET = -4;
export const INVALID_EDIT_TARGET = -5;

export const ACCEPTED_LLM_EDIT_COLOR = '#319795';
export const FOOTNOTE_NODE_NAME = 'footnote';
export const GENERATED_FOOTNOTES_SELECTOR = 'section[data-generated-footnotes="true"]';
export const CONTENT_SYNC_DEBOUNCE_MS = 1000;
export const COMMENTS_SYNC_DEBOUNCE_MS = 250;
export const FOOTNOTE_PANEL_DEBOUNCE_MS = 180;
export const SELECTION_SYNC_DEBOUNCE_MS = 80;
