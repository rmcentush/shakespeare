import { GENERATED_FOOTNOTES_SELECTOR } from './types';
import { smartifyDOMTextNodes } from './smartQuotes';

export function stripGeneratedFootnotesSection(html: string): string {
  if (!html.includes('data-generated-footnotes')) {
    return html;
  }

  const parsed = new DOMParser().parseFromString(html, 'text/html');
  parsed.querySelectorAll(GENERATED_FOOTNOTES_SELECTOR).forEach((element) => element.remove());
  return parsed.body.innerHTML;
}

const PASTE_STRIP_ATTRIBUTES = new Set([
  'style',
  'class',
  'id',
  'color',
  'bgcolor',
  'face',
  'size',
  'align',
  'lang',
  'dir',
  'width',
  'height',
  'cellpadding',
  'cellspacing',
  'border',
]);

const PASTE_PRESERVE_ATTRIBUTES_BY_TAG: Record<string, Set<string>> = {
  a: new Set(['href', 'title', 'target', 'rel']),
  img: new Set(['src', 'alt', 'title', 'width', 'height']),
  ol: new Set(['start', 'type']),
};

function shouldStripPastedAttribute(tagName: string, attrName: string): boolean {
  const lowered = attrName.toLowerCase();
  if (lowered.startsWith('on')) return true;
  if (lowered.startsWith('data-')) return false;
  const preserve = PASTE_PRESERVE_ATTRIBUTES_BY_TAG[tagName];
  if (preserve?.has(lowered)) return false;
  return PASTE_STRIP_ATTRIBUTES.has(lowered);
}

export function sanitizePastedHTML(html: string, contextBefore = ''): string {
  const parsed = new DOMParser().parseFromString(stripGeneratedFootnotesSection(html), 'text/html');

  parsed.querySelectorAll(GENERATED_FOOTNOTES_SELECTOR).forEach((element) => element.remove());
  parsed.querySelectorAll('style, meta, link, script, noscript, title').forEach((element) => element.remove());

  parsed.body.querySelectorAll('*').forEach((element) => {
    const tagName = element.tagName.toLowerCase();
    Array.from(element.attributes).forEach((attribute) => {
      if (shouldStripPastedAttribute(tagName, attribute.name)) {
        element.removeAttribute(attribute.name);
      }
    });
  });

  smartifyDOMTextNodes(parsed.body, contextBefore);

  return parsed.body.innerHTML;
}
