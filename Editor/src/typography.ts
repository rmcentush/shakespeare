import { Editor, Extension } from '@tiptap/core';
import { Mark, type Node as ProseMirrorNode } from '@tiptap/pm/model';
import { Plugin } from '@tiptap/pm/state';

export const BASE_FONT_FAMILY = 'Georgia';
export const BASE_FONT_SIZE = '18px';
export const BASE_LINE_HEIGHT = '1.7';

const AVAILABLE_FONT_FAMILIES = new Set([
  'Georgia',
  'Palatino',
  'Baskerville',
  'Times New Roman',
  'Helvetica Neue',
  '-apple-system',
]);

export interface FormattingAttributeState {
  value: string;
  mixed: boolean;
}

interface DefaultTypography {
  fontFamily: string;
  fontSize: string;
  lineHeight: string;
}

let defaultTypography: DefaultTypography = {
  fontFamily: BASE_FONT_FAMILY,
  fontSize: BASE_FONT_SIZE,
  lineHeight: BASE_LINE_HEIGHT,
};

function normalizedDecimal(value: number): string {
  return value.toFixed(2).replace(/\.00$/, '').replace(/(\.\d)0$/, '$1');
}

export function normalizeFontFamily(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return AVAILABLE_FONT_FAMILIES.has(trimmed) ? trimmed : null;
}

export function normalizeFontSize(value: unknown): string | null {
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  const match = String(value).trim().match(/^(\d+(?:\.\d+)?)\s*(?:px)?$/i);
  if (!match) return null;

  const size = Number(match[1]);
  if (!Number.isFinite(size) || size < 12 || size > 28) return null;
  return `${normalizedDecimal(size)}px`;
}

export function normalizeLineHeight(value: unknown): string | null {
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  const lineHeight = Number(String(value).trim());
  if (!Number.isFinite(lineHeight) || lineHeight < 1 || lineHeight > 2.5) return null;
  return normalizedDecimal(lineHeight);
}

function normalizeTextStyleValue(attribute: string, value: unknown): string {
  switch (attribute) {
    case 'fontFamily':
      return typeof value === 'string' ? value.trim() : '';
    case 'fontSize':
      return normalizeFontSize(value) || '';
    case 'color':
      return typeof value === 'string' ? value.trim().toLowerCase() : '';
    default:
      return '';
  }
}

export function selectedTextStyleAttribute(
  editor: Editor,
  attribute: 'fontFamily' | 'fontSize' | 'color'
): FormattingAttributeState {
  const { from, to, empty } = editor.state.selection;

  if (empty) {
    return {
      value: normalizeTextStyleValue(
        attribute,
        editor.getAttributes('textStyle')[attribute]
      ),
      mixed: false,
    };
  }

  const values = new Set<string>();
  editor.state.doc.nodesBetween(from, to, (node, position) => {
    if (!node.isText) return;
    const overlapsSelection = position < to && position + node.nodeSize > from;
    if (!overlapsSelection) return;

    const textStyle = node.marks.find((mark) => mark.type.name === 'textStyle');
    values.add(normalizeTextStyleValue(attribute, textStyle?.attrs[attribute]));
  });

  if (values.size === 0) return { value: '', mixed: false };
  return {
    value: values.size === 1 ? [...values][0] : '',
    mixed: values.size > 1,
  };
}

function defaultBlockStyleKey(node: ProseMirrorNode): string {
  if (node.type.name === 'heading') {
    return `heading:${String(node.attrs.level || '')}`;
  }
  return node.type.name;
}

export function selectedLineHeight(editor: Editor): FormattingAttributeState {
  const { from, to } = editor.state.selection;
  const values = new Map<string, string>();

  editor.state.doc.nodesBetween(from, to, (node) => {
    if (node.type.name !== 'paragraph' && node.type.name !== 'heading') return;
    const value = normalizeLineHeight(node.attrs.lineHeight) || '';
    const comparisonKey = value || `default:${defaultBlockStyleKey(node)}`;
    values.set(comparisonKey, value);
  });

  if (values.size === 0) return { value: '', mixed: false };
  if (
    values.size === 1 &&
    [...values.values()][0] === '' &&
    !documentHasUserContent(editor.state.doc) &&
    defaultTypography.lineHeight !== BASE_LINE_HEIGHT
  ) {
    return { value: defaultTypography.lineHeight, mixed: false };
  }
  return {
    value: values.size === 1 ? [...values.values()][0] : '',
    mixed: values.size > 1,
  };
}

export function selectedTextAlignment(editor: Editor): string {
  const { from, to } = editor.state.selection;
  const alignments = new Set<string>();

  editor.state.doc.nodesBetween(from, to, (node) => {
    if (node.type.name !== 'paragraph' && node.type.name !== 'heading') return;
    const alignment = typeof node.attrs.textAlign === 'string'
      ? node.attrs.textAlign
      : 'left';
    alignments.add(alignment || 'left');
  });

  if (alignments.size === 0) return 'left';
  return alignments.size === 1 ? [...alignments][0] : 'mixed';
}

function documentHasUserContent(doc: ProseMirrorNode): boolean {
  let hasContent = false;
  doc.descendants((node) => {
    if ((node.isText && Boolean(node.text?.length)) || (node.isAtom && !node.isText)) {
      hasContent = true;
      return false;
    }
    return !hasContent;
  });
  return hasContent;
}

function applyDefaultMarksToEmptyEditor(editor: Editor): boolean {
  if (documentHasUserContent(editor.state.doc)) return false;
  const textStyle = editor.state.schema.marks.textStyle;
  if (!textStyle) return false;

  const currentMarks = editor.state.storedMarks ?? editor.state.selection.$head.marks();
  const currentTextStyle = currentMarks.find((mark) => mark.type === textStyle);
  const attributes = {
    ...(currentTextStyle?.attrs || {}),
    fontFamily: defaultTypography.fontFamily === BASE_FONT_FAMILY
      ? null
      : defaultTypography.fontFamily,
    fontSize: defaultTypography.fontSize === BASE_FONT_SIZE
      ? null
      : defaultTypography.fontSize,
  };
  const nextMarks = currentMarks.filter((mark) => mark.type !== textStyle);
  if (Object.values(attributes).some(Boolean)) {
    nextMarks.push(textStyle.create(attributes));
  }
  if (Mark.sameSet(currentMarks, nextMarks)) return false;

  editor.view.dispatch(editor.state.tr.setStoredMarks(nextMarks));
  return true;
}

export function setDefaultTypography(
  editor: Editor,
  fontFamily: unknown,
  fontSize: unknown,
  lineHeight: unknown
): boolean {
  defaultTypography = {
    fontFamily: normalizeFontFamily(fontFamily) || BASE_FONT_FAMILY,
    fontSize: normalizeFontSize(fontSize) || BASE_FONT_SIZE,
    lineHeight: normalizeLineHeight(lineHeight) || BASE_LINE_HEIGHT,
  };
  return applyDefaultMarksToEmptyEditor(editor);
}

export function restoreDefaultTypographyForEmptyEditor(editor: Editor): boolean {
  return applyDefaultMarksToEmptyEditor(editor);
}

export function applyFontSize(editor: Editor, value: unknown): boolean {
  const fontSize = normalizeFontSize(value);
  if (!fontSize) return false;
  return editor.chain().focus().setMark('textStyle', { fontSize }).run();
}

export function applyLineHeight(editor: Editor, value: unknown): boolean {
  const lineHeight = normalizeLineHeight(value);
  if (!lineHeight) return false;
  return editor.chain()
    .focus()
    .updateAttributes('paragraph', { lineHeight })
    .updateAttributes('heading', { lineHeight })
    .run();
}

export function unsetLineHeight(editor: Editor): boolean {
  return editor.chain()
    .focus()
    .resetAttributes('paragraph', 'lineHeight')
    .resetAttributes('heading', 'lineHeight')
    .run();
}

export const FontSize = Extension.create({
  name: 'fontSize',
  addGlobalAttributes() {
    return [{
      types: ['textStyle'],
      attributes: {
        fontSize: {
          default: null,
          parseHTML: (element) => normalizeFontSize(element.style.fontSize),
          renderHTML: (attributes) => {
            const fontSize = normalizeFontSize(attributes.fontSize);
            return fontSize ? { style: `font-size: ${fontSize}` } : {};
          },
        },
      },
    }];
  },
});

export const LineHeight = Extension.create({
  name: 'lineHeight',
  addGlobalAttributes() {
    return [{
      types: ['paragraph', 'heading'],
      attributes: {
        lineHeight: {
          default: null,
          parseHTML: (element) => normalizeLineHeight(element.style.lineHeight),
          renderHTML: (attributes) => {
            const lineHeight = normalizeLineHeight(attributes.lineHeight);
            return lineHeight ? { style: `line-height: ${lineHeight}` } : {};
          },
        },
      },
    }];
  },
  addProseMirrorPlugins() {
    return [new Plugin({
      appendTransaction(transactions, oldState, newState) {
        if (!transactions.some((transaction) => transaction.docChanged)) return null;
        if (documentHasUserContent(oldState.doc) || !documentHasUserContent(newState.doc)) {
          return null;
        }
        if (defaultTypography.lineHeight === BASE_LINE_HEIGHT) return null;

        const transaction = newState.tr;
        newState.doc.descendants((node, position) => {
          if (
            (node.type.name === 'paragraph' || node.type.name === 'heading') &&
            node.content.size > 0
          ) {
            transaction.setNodeMarkup(position, undefined, {
              ...node.attrs,
              lineHeight: defaultTypography.lineHeight,
            });
            return false;
          }
          return true;
        });
        return transaction.docChanged ? transaction : null;
      },
    })];
  },
});
