import { Editor, mergeAttributes } from '@tiptap/core';
import Link from '@tiptap/extension-link';
import { sendToSwift } from './bridge';

export const HoverableLink = Link.extend({
  renderHTML({ HTMLAttributes }) {
    const href = typeof HTMLAttributes.href === 'string' ? HTMLAttributes.href : '';
    return [
      'a',
      mergeAttributes(this.options.HTMLAttributes, HTMLAttributes, href ? { title: href } : {}),
      0,
    ];
  },
});

const linkPreviewElement = document.getElementById('link-preview');
let linkPreviewHref = '';
let linkPreviewIsHovered = false;
let linkAnchorIsHovered = false;
let linkPreviewHideTimer: number | null = null;

function clearLinkPreviewHideTimer() {
  if (linkPreviewHideTimer !== null) {
    window.clearTimeout(linkPreviewHideTimer);
    linkPreviewHideTimer = null;
  }
}

function hideLinkPreview() {
  clearLinkPreviewHideTimer();
  linkPreviewHref = '';
  linkPreviewIsHovered = false;
  linkAnchorIsHovered = false;
  if (!linkPreviewElement) return;
  linkPreviewElement.classList.remove('is-visible');
  linkPreviewElement.setAttribute('aria-hidden', 'true');
}

function scheduleHideLinkPreview() {
  clearLinkPreviewHideTimer();
  linkPreviewHideTimer = window.setTimeout(() => {
    linkPreviewHideTimer = null;
    if (!linkPreviewIsHovered && !linkAnchorIsHovered) {
      hideLinkPreview();
    }
  }, 180);
}

function isLinkOpenable(href: string): boolean {
  if (!href) return false;
  try {
    const url = new URL(href, document.baseURI);
    return url.protocol === 'http:' || url.protocol === 'https:' || url.protocol === 'mailto:';
  } catch {
    return false;
  }
}

function openLinkInExternalApp(href: string) {
  if (!isLinkOpenable(href)) return;
  sendToSwift('openURL', { url: href });
}

function positionLinkPreview(event: MouseEvent) {
  if (!linkPreviewElement) return;

  const offset = 14;
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;
  const previewRect = linkPreviewElement.getBoundingClientRect();

  let left = event.clientX + offset;
  let top = event.clientY + offset;

  if (left + previewRect.width > viewportWidth - 12) {
    left = Math.max(12, viewportWidth - previewRect.width - 12);
  }

  if (top + previewRect.height > viewportHeight - 12) {
    top = Math.max(12, event.clientY - previewRect.height - offset);
  }

  linkPreviewElement.style.left = `${left}px`;
  linkPreviewElement.style.top = `${top}px`;
}

function showLinkPreview(anchor: HTMLAnchorElement, event: MouseEvent) {
  if (!linkPreviewElement) return;

  const href = anchor.getAttribute('href')?.trim() ?? '';
  if (!href) {
    hideLinkPreview();
    return;
  }

  linkAnchorIsHovered = true;
  clearLinkPreviewHideTimer();
  linkPreviewHref = href;
  linkPreviewElement.textContent = href;
  linkPreviewElement.classList.add('is-visible');
  linkPreviewElement.setAttribute('aria-hidden', 'false');
  linkPreviewElement.setAttribute('role', 'link');
  linkPreviewElement.setAttribute('title', 'Click to open · ⌘-click on link to open');
  positionLinkPreview(event);
}

export function attachLinkHoverPreview(editor: Editor) {
  const root = editor.view.dom as HTMLElement;

  root.addEventListener('mousemove', (event) => {
    const target = event.target;
    if (!(target instanceof Element)) {
      linkAnchorIsHovered = false;
      scheduleHideLinkPreview();
      return;
    }

    const anchor = target.closest('a[href]');
    if (anchor instanceof HTMLAnchorElement && root.contains(anchor)) {
      showLinkPreview(anchor, event);
      return;
    }

    linkAnchorIsHovered = false;
    scheduleHideLinkPreview();
  });

  root.addEventListener('mouseleave', () => {
    linkAnchorIsHovered = false;
    scheduleHideLinkPreview();
  });

  root.addEventListener('mousedown', (event) => {
    if (event.target instanceof Element) {
      const anchor = event.target.closest('a[href]');
      if (anchor instanceof HTMLAnchorElement && root.contains(anchor) && event.metaKey) {
        event.preventDefault();
        event.stopPropagation();
        return;
      }
    }
    hideLinkPreview();
  });

  root.addEventListener('click', (event) => {
    if (!event.metaKey || event.button !== 0) return;
    const target = event.target;
    if (!(target instanceof Element)) return;
    const anchor = target.closest('a[href]');
    if (!(anchor instanceof HTMLAnchorElement) || !root.contains(anchor)) return;
    const href = anchor.getAttribute('href')?.trim() ?? '';
    if (!href || !isLinkOpenable(href)) return;
    event.preventDefault();
    event.stopPropagation();
    openLinkInExternalApp(href);
    hideLinkPreview();
  });

  root.addEventListener('dragstart', hideLinkPreview);
  document.addEventListener('scroll', hideLinkPreview, true);

  if (linkPreviewElement) {
    linkPreviewElement.addEventListener('mouseenter', () => {
      linkPreviewIsHovered = true;
      clearLinkPreviewHideTimer();
    });
    linkPreviewElement.addEventListener('mouseleave', () => {
      linkPreviewIsHovered = false;
      scheduleHideLinkPreview();
    });
    linkPreviewElement.addEventListener('mousedown', (event) => {
      event.preventDefault();
      event.stopPropagation();
    });
    linkPreviewElement.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      const href = linkPreviewHref;
      hideLinkPreview();
      openLinkInExternalApp(href);
    });
  }
}
