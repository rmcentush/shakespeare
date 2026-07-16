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

const DOCUMENT_IMAGE_PREFIX = 'shakespeare-document://asset/';

export function isSafeDocumentImageSource(source: unknown): source is string {
  return typeof source === 'string' && source.startsWith(DOCUMENT_IMAGE_PREFIX);
}

function stripUnsafeURLs(root: ParentNode): void {
  root.querySelectorAll('img').forEach((image) => {
    if (!isSafeDocumentImageSource(image.getAttribute('src'))) {
      const alt = image.getAttribute('alt')?.trim();
      image.replaceWith(document.createTextNode(alt ? `[Image: ${alt}]` : ''));
    }
  });
  root.querySelectorAll('a[href]').forEach((link) => {
    const href = link.getAttribute('href')?.trim() || '';
    if (!/^(https?:|mailto:|#)/i.test(href)) {
      link.removeAttribute('href');
      link.removeAttribute('target');
    }
  });
}

export function sanitizeDocumentHTML(html: string): string {
  const parsed = new DOMParser().parseFromString(stripGeneratedFootnotesSection(html), 'text/html');
  parsed.querySelectorAll('script, noscript').forEach((element) => element.remove());
  parsed.body.querySelectorAll('*').forEach((element) => {
    Array.from(element.attributes).forEach((attribute) => {
      if (attribute.name.toLowerCase().startsWith('on')) {
        element.removeAttribute(attribute.name);
      }
    });
  });
  stripUnsafeURLs(parsed.body);
  return parsed.body.innerHTML;
}

export function sanitizeDocumentJSON(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sanitizeDocumentJSON).filter((item) => item !== null);
  }
  if (!value || typeof value !== 'object') return value;

  const node = value as Record<string, unknown>;
  const attrs = node.attrs;
  if (
    node.type === 'image' &&
    (!attrs || typeof attrs !== 'object' || !isSafeDocumentImageSource((attrs as Record<string, unknown>).src))
  ) {
    return null;
  }
  return Object.fromEntries(
    Object.entries(node).map(([key, entry]) => [key, sanitizeDocumentJSON(entry)])
  );
}

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

  stripUnsafeURLs(parsed.body);

  smartifyDOMTextNodes(parsed.body, contextBefore);

  return parsed.body.innerHTML;
}
