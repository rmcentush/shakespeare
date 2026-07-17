import { Editor } from '@tiptap/core';
import {
  EditContextBlock,
  EditContextPlaceholder,
  EditContextSnapshot,
  MAX_EDIT_CONTEXT_BLOCKS,
  MAX_EDIT_CONTEXT_BLOCK_TEXT,
  NEARBY_EDIT_CONTEXT_CHARS,
} from './types';
import { hashString } from './utils';
import {
  effectiveTextSelection,
  getDocumentRevision,
  serializeClipboardDataForRange,
  serializeDocumentPlainText,
} from './docSync';
import { selectEditContextBlocks } from './editContextSelection';

// ProseMirror docs are immutable; cache the complete local index by doc
// identity, then select a bounded, cursor-aware view for the Swift bridge.
const editBlockIndexCache = new WeakMap<object, EditContextBlock[]>();

export function buildEditBlockIndex(doc: any): EditContextBlock[] {
  const cached = editBlockIndexCache.get(doc);
  if (cached) return cached;
  const blocks = buildEditBlockIndexUncached(doc);
  editBlockIndexCache.set(doc, blocks);
  return blocks;
}

function truncateForEditContext(text: string): string {
  if (text.length <= MAX_EDIT_CONTEXT_BLOCK_TEXT) return text;
  const headCount = Math.floor(MAX_EDIT_CONTEXT_BLOCK_TEXT / 2);
  const tailCount = MAX_EDIT_CONTEXT_BLOCK_TEXT - headCount;
  return `${text.slice(0, headCount)}\n[...]\n${text.slice(text.length - tailCount)}`;
}

function buildEditBlockIndexUncached(doc: any): EditContextBlock[] {
  const blocks: EditContextBlock[] = [];

  const visit = (node: any, pos: number, path: number[], isRoot: boolean) => {
    if (node.isTextblock) {
      const text = node.textBetween(0, node.content.size, '\n', '\n');
      const pathString = path.join('.');
      const textHash = hashString(text);
      blocks.push({
        id: `block_${pathString || 'root'}_${textHash}`,
        path: pathString,
        type: node.type.name,
        from: pos + 1,
        to: pos + node.nodeSize - 1,
        text: truncateForEditContext(text),
        textHash,
      });
    }

    node.forEach((child: any, offset: number, index: number) => {
      const childPos = (isRoot ? 0 : pos + 1) + offset;
      visit(child, childPos, [...path, index], false);
    });
  };

  visit(doc, 0, [], true);
  return blocks;
}

function textNearPosition(doc: any, pos: number): string {
  const from = Math.max(0, pos - NEARBY_EDIT_CONTEXT_CHARS);
  const to = Math.min(doc.content.size, pos + NEARBY_EDIT_CONTEXT_CHARS);
  return doc.textBetween(from, to, '\n', '\n');
}

function bracketPlaceholdersForBlock(block: EditContextBlock): EditContextPlaceholder[] {
  const placeholders: EditContextPlaceholder[] = [];
  const regex = /\[[^\]\n]{1,160}\]/g;
  let match: RegExpExecArray | null;

  while ((match = regex.exec(block.text)) !== null) {
    placeholders.push({
      blockId: block.id,
      from: block.from + match.index,
      to: block.from + match.index + match[0].length,
      text: match[0],
    });
  }

  return placeholders;
}

function bracketPlaceholders(blocks: EditContextBlock[]): EditContextPlaceholder[] {
  return blocks.flatMap(bracketPlaceholdersForBlock).slice(0, 80);
}

export function buildEditContextSnapshot(editor: Editor): EditContextSnapshot {
  const plainText = serializeDocumentPlainText(editor);
  const activeSelection = effectiveTextSelection(editor);
  const selection = activeSelection
    ? {
      from: activeSelection.from,
      to: activeSelection.to,
      text: activeSelection.text,
      html: serializeClipboardDataForRange(editor, activeSelection.from, activeSelection.to).html,
      words: activeSelection.words,
      characters: activeSelection.characters,
    }
    : null;

  const cursorPosition = selection?.to ?? editor.state.selection.from;
  const blocks = selectEditContextBlocks(
    buildEditBlockIndex(editor.state.doc),
    cursorPosition,
    MAX_EDIT_CONTEXT_BLOCKS
  );

  return {
    revision: getDocumentRevision(),
    documentHash: hashString(plainText),
    plainText,
    cursorPosition,
    nearbyText: textNearPosition(editor.state.doc, cursorPosition),
    selection,
    blocks,
    placeholders: bracketPlaceholders(blocks),
  };
}
