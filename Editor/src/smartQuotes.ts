import { Editor, Extension } from '@tiptap/core';
import { Plugin, PluginKey } from '@tiptap/pm/state';
import { isAlphaNumericCharacter, isWhitespaceCharacter, lastCharacter } from './utils';

const smartQuotesPluginKey = new PluginKey('smartQuotes');
const SMART_QUOTES_TRANSACTION_META = 'smartQuotesNormalized';

let smartQuotesNormalizationFrame: number | null = null;

function isOpeningQuoteContext(character: string): boolean {
  return !character || isWhitespaceCharacter(character) || /[\([{<\u2013\u2014-]/.test(character) || character === '\u201C' || character === '\u2018';
}

function startsWithApostropheElision(text: string): boolean {
  const lower = text.toLowerCase();
  if (/^[a-z]'/.test(lower)) return true;
  return [
    'tis',
    'twas',
    'twere',
    'cause',
    'cuz',
    'em',
    'til',
    'bout',
    'round',
  ].some((prefix) => lower.startsWith(prefix));
}

function shouldOpenDoubleQuote(text: string, index: number, previousCharacter: string): boolean {
  const nextCharacter = text[index + 1] || '';
  if (!nextCharacter || isWhitespaceCharacter(nextCharacter)) return false;
  return isOpeningQuoteContext(previousCharacter);
}

function shouldOpenSingleQuote(text: string, index: number, previousCharacter: string): boolean {
  const nextCharacter = text[index + 1] || '';
  if (!nextCharacter || isWhitespaceCharacter(nextCharacter)) return false;
  if (isAlphaNumericCharacter(previousCharacter)) return false;
  if (/[0-9]/.test(nextCharacter)) return false;
  if (startsWithApostropheElision(text.slice(index + 1))) return false;
  return isOpeningQuoteContext(previousCharacter);
}

export function smartifyQuotes(text: string): string {
  let result = '';

  for (let index = 0; index < text.length; index += 1) {
    const character = text[index];
    const previousCharacter = lastCharacter(result);

    if (character === '"') {
      result += shouldOpenDoubleQuote(text, index, previousCharacter) ? '\u201C' : '\u201D';
    } else if (character === "'") {
      result += shouldOpenSingleQuote(text, index, previousCharacter) ? '\u2018' : '\u2019';
    } else {
      result += character;
    }
  }

  return result;
}

export function smartifyQuotesWithContext(text: string, contextBefore = ''): string {
  if (!text) return text;
  const syntheticPrefix = contextBefore || ' ';
  return smartifyQuotes(`${syntheticPrefix}${text}`).slice(syntheticPrefix.length);
}

export function contextCharacterBefore(doc: any, pos: number): string {
  if (pos <= 0) return '';
  return doc.textBetween(Math.max(pos - 1, 0), pos, '', '');
}

function buildSmartQuotesNormalizationTransaction(state: any) {
  let transaction = state.tr;
  let changed = false;

  state.doc.descendants((node: any, pos: number) => {
    if (!node.isText || typeof node.text !== 'string') return;
    if (!node.text.includes('"') && !node.text.includes("'")) return;

    const converted = smartifyQuotesWithContext(
      node.text,
      contextCharacterBefore(state.doc, pos)
    );

    if (converted === node.text) return;

    transaction = transaction.replaceWith(
      pos,
      pos + node.nodeSize,
      state.schema.text(converted, node.marks)
    );
    changed = true;
  });

  if (!changed) {
    return null;
  }

  transaction.setMeta(SMART_QUOTES_TRANSACTION_META, true);
  return transaction;
}

export function normalizeDocumentSmartQuotes(editor: Editor): boolean {
  const transaction = buildSmartQuotesNormalizationTransaction(editor.state);
  if (!transaction) {
    return false;
  }

  editor.view.dispatch(transaction);
  return true;
}

export function scheduleSmartQuotesNormalization(editor: Editor) {
  if (smartQuotesNormalizationFrame !== null) {
    window.cancelAnimationFrame(smartQuotesNormalizationFrame);
  }

  smartQuotesNormalizationFrame = window.requestAnimationFrame(() => {
    smartQuotesNormalizationFrame = null;
    normalizeDocumentSmartQuotes(editor);
  });
}

/**
 * Apply smart quotes to all text nodes in a DOM tree (preserving HTML structure).
 */
export function smartifyDOMTextNodes(root: Node, contextBefore = ''): void {
  const ownerDocument = root.ownerDocument ?? document;
  const walker = ownerDocument.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const textNodes: Text[] = [];
  let previousText = contextBefore;
  while (walker.nextNode()) {
    textNodes.push(walker.currentNode as Text);
  }
  for (const node of textNodes) {
    const converted = smartifyQuotesWithContext(node.data, lastCharacter(previousText));
    if (converted !== node.data) {
      node.data = converted;
    }
    previousText = converted;
  }
}

export function smartifyHTMLFragment(html: string, contextBefore = ''): string {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  smartifyDOMTextNodes(parsed.body, contextBefore);
  return parsed.body.innerHTML;
}

function singleElementChildIgnoringWhitespace(root: HTMLElement): HTMLElement | null {
  let element: HTMLElement | null = null;

  for (const child of Array.from(root.childNodes)) {
    if (child.nodeType === Node.TEXT_NODE) {
      if (child.textContent?.trim()) return null;
      continue;
    }

    if (child instanceof HTMLElement) {
      if (element) return null;
      element = child;
      continue;
    }

    return null;
  }

  return element;
}

function unwrapSingleParagraphHTML(html: string): string {
  const parsed = new DOMParser().parseFromString(html, 'text/html');
  const onlyChild = singleElementChildIgnoringWhitespace(parsed.body);
  if (!onlyChild) return html;

  const tagName = onlyChild.tagName.toLowerCase();
  if (tagName !== 'p' && tagName !== 'div') return html;

  return onlyChild.innerHTML;
}

function isTextblockRange(ed: Editor, from: number, to: number): boolean {
  try {
    const resolvedFrom = ed.state.doc.resolve(from);
    const resolvedTo = ed.state.doc.resolve(Math.max(from, to));
    return resolvedFrom.sameParent(resolvedTo) && resolvedFrom.parent.isTextblock;
  } catch (_) {
    return false;
  }
}

export function prepareReplacementHTMLForRange(
  ed: Editor,
  from: number,
  to: number,
  html: string
): string {
  const smartified = smartifyHTMLFragment(html, contextCharacterBefore(ed.state.doc, from));
  return isTextblockRange(ed, from, to)
    ? unwrapSingleParagraphHTML(smartified)
    : smartified;
}

export const SmartQuotes = Extension.create({
  name: 'smartQuotes',

  addProseMirrorPlugins() {
    return [
      new Plugin({
        key: smartQuotesPluginKey,
        props: {
          handleTextInput(view, from, to, text) {
            const converted = smartifyQuotesWithContext(
              text,
              contextCharacterBefore(view.state.doc, from)
            );

            if (converted === text) {
              return false;
            }

            view.dispatch(view.state.tr.insertText(converted, from, to));
            return true;
          },
        },
        appendTransaction(transactions, _oldState, newState) {
          if (!transactions.some((transaction) => transaction.docChanged)) {
            return null;
          }

          if (transactions.some((transaction) => transaction.getMeta(SMART_QUOTES_TRANSACTION_META))) {
            return null;
          }
          return buildSmartQuotesNormalizationTransaction(newState);
        },
      }),
    ];
  },
});
