import { Editor, Extension } from '@tiptap/core';
import { Plugin, PluginKey } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';
import {
  MAX_SEARCH_RESULTS,
  SearchIndex,
  SearchIndexBuilder,
  SearchMatch,
} from './types';
import { normalizeDocumentSmartQuotes } from './smartQuotes';

const searchPluginKey = new PluginKey('searchHighlight');

let searchResults: SearchMatch[] = [];
let currentMatchIdx = -1;
let activeSearchQuery = '';

// ProseMirror documents are immutable, so caching the search index by
// document identity is a correct invalidation strategy. This avoids
// rebuilding the full-document index on every find/replace call.
let cachedSearchIndexDoc: object | null = null;
let cachedSearchIndex: SearchIndex | null = null;

function documentSearchIndex(doc: any): SearchIndex {
  if (cachedSearchIndex && cachedSearchIndexDoc === doc) return cachedSearchIndex;
  const index = buildDocumentSearchIndex(doc);
  cachedSearchIndexDoc = doc;
  cachedSearchIndex = index;
  return index;
}

function isSearchWhitespace(character: string): boolean {
  return character === '\u00a0' || /\s/.test(character);
}

function foldSearchCharacter(character: string): string {
  switch (character) {
    case '\u2018':
    case '\u2019':
    case '\u201A':
    case '\u201B':
      return "'";
    case '\u201C':
    case '\u201D':
    case '\u201E':
    case '\u201F':
      return '"';
    default:
      return character.toLowerCase();
  }
}

function appendSearchCharacter(
  builder: SearchIndexBuilder,
  character: string,
  from: number,
  to: number
) {
  if (isSearchWhitespace(character)) {
    if (builder.text.length === 0) return;

    if (builder.lastWasWhitespace) {
      const lastRange = builder.ranges[builder.ranges.length - 1];
      if (lastRange) {
        lastRange.from = Math.min(lastRange.from, from);
        lastRange.to = Math.max(lastRange.to, to);
      }
      return;
    }

    builder.text += ' ';
    builder.ranges.push({ from, to });
    builder.lastWasWhitespace = true;
    return;
  }

  const folded = foldSearchCharacter(character);
  for (let i = 0; i < folded.length; i += 1) {
    builder.text += folded[i];
    builder.ranges.push({ from, to });
  }
  builder.lastWasWhitespace = false;
}

function trimTrailingSearchWhitespace(builder: SearchIndexBuilder) {
  while (builder.text.endsWith(' ')) {
    builder.text = builder.text.slice(0, -1);
    builder.ranges.pop();
  }
  builder.lastWasWhitespace = builder.text.endsWith(' ');
}

export function normalizeSearchQuery(query: string): string {
  const builder: SearchIndexBuilder = {
    text: '',
    ranges: [],
    lastWasWhitespace: false,
  };

  for (let i = 0; i < query.length; i += 1) {
    appendSearchCharacter(builder, query[i], i, i + 1);
  }

  trimTrailingSearchWhitespace(builder);
  return builder.text;
}

function buildDocumentSearchIndex(doc: any): SearchIndex {
  const builder: SearchIndexBuilder = {
    text: '',
    ranges: [],
    lastWasWhitespace: false,
  };
  let hasVisitedTextBlock = false;

  doc.descendants((node: any, pos: number) => {
    if (!node.isTextblock) return;

    if (hasVisitedTextBlock) {
      appendSearchCharacter(builder, '\n', pos, pos);
    }
    hasVisitedTextBlock = true;

    node.forEach((child: any, offset: number) => {
      const childPos = pos + 1 + offset;

      if (child.isText && typeof child.text === 'string') {
        for (let i = 0; i < child.text.length; i += 1) {
          appendSearchCharacter(builder, child.text[i], childPos + i, childPos + i + 1);
        }
        return;
      }

      if (child.type?.name === 'hardBreak') {
        appendSearchCharacter(builder, '\n', childPos, childPos + child.nodeSize);
      }
    });

    return false;
  });

  trimTrailingSearchWhitespace(builder);
  return {
    text: builder.text,
    ranges: builder.ranges,
  };
}

export function findTextInDoc(
  doc: any,
  query: string,
  maxMatches = Number.POSITIVE_INFINITY,
  scope: SearchMatch | null = null
): SearchMatch[] {
  const normalizedQuery = normalizeSearchQuery(query);
  if (!normalizedQuery) return [];
  const matches: SearchMatch[] = [];
  const searchIndex = documentSearchIndex(doc);
  const advanceBy = Math.max(normalizedQuery.length, 1);

  let idx = searchIndex.text.indexOf(normalizedQuery);
  while (idx !== -1) {
    const start = searchIndex.ranges[idx];
    const end = searchIndex.ranges[idx + normalizedQuery.length - 1];
    if (start && end) {
      const match = { from: start.from, to: end.to };
      if (!scope || (match.from >= scope.from && match.to <= scope.to)) {
        matches.push(match);
        if (matches.length >= maxMatches) break;
      }
    }
    idx = searchIndex.text.indexOf(normalizedQuery, idx + advanceBy);
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

export const SearchHighlight = Extension.create({
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

// --- Find bar API (called from editor.ts editorAPI registration) ---

export function runFindInDocument(editor: Editor, query: string): number {
  activeSearchQuery = query;
  searchResults = findTextInDoc(editor.state.doc, query, MAX_SEARCH_RESULTS);
  currentMatchIdx = searchResults.length > 0 ? 0 : -1;
  updateSearchDecorations(editor);
  if (currentMatchIdx >= 0) scrollToMatch(editor, searchResults[currentMatchIdx]);
  return searchResults.length;
}

export function runFindNext(editor: Editor): string {
  if (searchResults.length === 0) return JSON.stringify({ index: -1, total: 0 });
  currentMatchIdx = (currentMatchIdx + 1) % searchResults.length;
  updateSearchDecorations(editor);
  scrollToMatch(editor, searchResults[currentMatchIdx]);
  return JSON.stringify({ index: currentMatchIdx, total: searchResults.length });
}

export function runFindPrevious(editor: Editor): string {
  if (searchResults.length === 0) return JSON.stringify({ index: -1, total: 0 });
  currentMatchIdx = (currentMatchIdx - 1 + searchResults.length) % searchResults.length;
  updateSearchDecorations(editor);
  scrollToMatch(editor, searchResults[currentMatchIdx]);
  return JSON.stringify({ index: currentMatchIdx, total: searchResults.length });
}

export function runReplaceOne(editor: Editor, replacement: string): string {
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
}

export function runReplaceAll(editor: Editor, replacement: string): number {
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
}

export function runClearFind(editor: Editor): void {
  searchResults = [];
  currentMatchIdx = -1;
  activeSearchQuery = '';
  updateSearchDecorations(editor);
}
