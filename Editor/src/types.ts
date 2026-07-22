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
  isStrike: boolean;
  isBulletList: boolean;
  isOrderedList: boolean;
  isBlockquote: boolean;
  heading: number;
  textAlign: string;
  isLink: boolean;
  linkHref: string;
  textColor: string;
  isTextColorMixed: boolean;
  fontFamily: string;
  isFontFamilyMixed: boolean;
  fontSize: string;
  isFontSizeMixed: boolean;
  lineHeight: string;
  isLineHeightMixed: boolean;
  isFootnote: boolean;
  footnoteText: string;
  isImage: boolean;
  imageLayout: ImageLayout;
  imageAlign: ImageAlign;
  imageWidth: string;
  imageHeight: string;
  imageAlt: string;
  imageDecorative: boolean;
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

// --- Pending edit diff review ---
export type PendingEditKind = 'selection' | 'insert' | 'findReplace' | 'delete';
export type PendingEditStatus = 'pending' | 'conflicted';

export interface PendingEditMetadata {
  learningCategory?: string;
  rationale?: string;
  instruction?: string;
}

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
  learningCategory: string;
  rationale: string;
  instruction: string;
}

export type PersonalizationOutcomeKind =
  | 'accepted_unchanged'
  | 'accepted_modified'
  | 'reverted'
  | 'rejected_unchanged'
  | 'rejected_rewritten'
  | 'later_accepted'
  | 'unresolvable';

export interface PersonalizationOutcomeSnapshot {
  actionId: string;
  outcome: PersonalizationOutcomeKind;
  finalText: string;
  confidence: number;
  trainingEligible: boolean;
}

// --- Limits ---
export const MAX_SEARCH_RESULTS = 500;
export const MAX_PENDING_EDITS = 120;
export const MAX_EDIT_CONTEXT_BLOCKS = 160;
export const MAX_EDIT_CONTEXT_BLOCK_TEXT = 900;
export const NEARBY_EDIT_CONTEXT_CHARS = 900;

export const TOO_MANY_PENDING_EDITS = -2;

export const ACCEPTED_ASSISTED_EDIT_COLOR = '#319795';
export const FOOTNOTE_NODE_NAME = 'footnote';
export const GENERATED_FOOTNOTES_SELECTOR = 'section[data-generated-footnotes="true"]';
export const CONTENT_SYNC_DEBOUNCE_MS = 1000;
export const COMMENTS_SYNC_DEBOUNCE_MS = 250;
export const FOOTNOTE_PANEL_DEBOUNCE_MS = 180;
export const SELECTION_SYNC_DEBOUNCE_MS = 80;
