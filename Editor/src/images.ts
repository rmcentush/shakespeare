import { Editor, mergeAttributes } from '@tiptap/core';
import Image from '@tiptap/extension-image';
import { NodeSelection } from '@tiptap/pm/state';
import {
  ImageAlign,
  ImageCropRect,
  ImageHandleDirection,
  ImageLayout,
} from './types';

const MIN_IMAGE_WIDTH = 80;
const MIN_CROP_SIZE = 0.08;
const IMAGE_RESIZE_HANDLES: ImageHandleDirection[] = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];

export function normalizeImageLayout(value: unknown): ImageLayout {
  return value === 'block' || value === 'float-left' || value === 'float-right' ? value : 'inline';
}

export function normalizeImageAlign(value: unknown): ImageAlign {
  return value === 'left' || value === 'right' ? value : 'center';
}

function numericImageAttr(value: unknown, fallback: number): number {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const parsed = parseFloat(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return fallback;
}

function normalizedCropNumber(value: unknown, fallback: number): number {
  return Math.min(1, Math.max(0, numericImageAttr(value, fallback)));
}

function cropRectFromAttrs(attrs: Record<string, unknown>): ImageCropRect {
  const x = normalizedCropNumber(attrs.cropX, 0);
  const y = normalizedCropNumber(attrs.cropY, 0);
  const width = Math.min(1 - x, Math.max(MIN_CROP_SIZE, normalizedCropNumber(attrs.cropWidth, 1)));
  const height = Math.min(1 - y, Math.max(MIN_CROP_SIZE, normalizedCropNumber(attrs.cropHeight, 1)));

  return {
    x,
    y,
    width,
    height,
  };
}

function cropAttrsFromRect(crop: ImageCropRect): Record<string, number> {
  const normalized = constrainCropRect(crop);
  return {
    cropX: roundImageNumber(normalized.x),
    cropY: roundImageNumber(normalized.y),
    cropWidth: roundImageNumber(normalized.width),
    cropHeight: roundImageNumber(normalized.height),
  };
}

function cropDataAttrsFromRect(crop: ImageCropRect): Record<string, string> {
  const normalized = constrainCropRect(crop);
  return {
    'data-crop-x': String(roundImageNumber(normalized.x)),
    'data-crop-y': String(roundImageNumber(normalized.y)),
    'data-crop-width': String(roundImageNumber(normalized.width)),
    'data-crop-height': String(roundImageNumber(normalized.height)),
  };
}

function isDefaultCrop(crop: ImageCropRect): boolean {
  return crop.x <= 0.0001 &&
    crop.y <= 0.0001 &&
    crop.width >= 0.9999 &&
    crop.height >= 0.9999;
}

function constrainCropRect(crop: ImageCropRect): ImageCropRect {
  const x = Math.min(1 - MIN_CROP_SIZE, Math.max(0, crop.x));
  const y = Math.min(1 - MIN_CROP_SIZE, Math.max(0, crop.y));
  const width = Math.min(1 - x, Math.max(MIN_CROP_SIZE, crop.width));
  const height = Math.min(1 - y, Math.max(MIN_CROP_SIZE, crop.height));

  return { x, y, width, height };
}

function roundImageNumber(value: number): number {
  return Number(value.toFixed(4));
}

function dimensionFromHTMLElement(element: HTMLElement, attributeName: string): string | null {
  const styleValue = element.style.getPropertyValue(attributeName).trim();
  if (styleValue) return styleValue;

  const attributeValue = element.getAttribute(attributeName)?.trim();
  if (!attributeValue) return null;
  return /^\d+(\.\d+)?$/.test(attributeValue) ? `${attributeValue}px` : attributeValue;
}

function dimensionStyle(value: unknown): string | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return `${Math.round(value)}px`;
  }

  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function pixelDimension(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value !== 'string') return null;

  const trimmed = value.trim();
  const match = trimmed.match(/^(-?\d+(?:\.\d+)?)px$/);
  if (match) return parseFloat(match[1]);
  if (/^\d+(\.\d+)?$/.test(trimmed)) return parseFloat(trimmed);
  return null;
}

function pixelDimensionAttr(value: number): string {
  return `${Math.round(Math.max(MIN_IMAGE_WIDTH, value))}px`;
}

function imageLayoutStyleParts(layout: ImageLayout, align: ImageAlign): string[] {
  if (layout === 'float-left') {
    return ['float: left', 'display: block', 'margin: 0.35em 1em 0.65em 0'];
  }

  if (layout === 'float-right') {
    return ['float: right', 'display: block', 'margin: 0.35em 0 0.65em 1em'];
  }

  if (layout === 'block') {
    const margin =
      align === 'left'
        ? '0.75em auto 0.75em 0'
        : align === 'right'
          ? '0.75em 0 0.75em auto'
          : '0.75em auto';
    return ['display: block', `margin: ${margin}`];
  }

  return ['display: inline-block', 'vertical-align: baseline', 'margin: 0 0.15em'];
}

export function insertedImageAttrs(src: string): Record<string, unknown> {
  return {
    src,
    alt: null,
    decorative: false,
    layout: 'block',
    align: 'center',
  };
}

export function selectedImageNode(editor: Editor): { node: any; pos: number } | null {
  const selection = editor.state.selection;
  if (!(selection instanceof NodeSelection)) return null;
  if (selection.node.type.name !== 'image') return null;
  return {
    node: selection.node,
    pos: selection.from,
  };
}

function updateSelectedImageAttrs(editor: Editor, attrs: Record<string, unknown>): boolean {
  const selected = selectedImageNode(editor);
  if (!selected) return false;

  const currentNode = editor.state.doc.nodeAt(selected.pos);
  if (!currentNode || currentNode.type.name !== 'image') return false;

  editor.view.dispatch(
    editor.state.tr.setNodeMarkup(selected.pos, undefined, {
      ...currentNode.attrs,
      ...attrs,
    })
  );
  editor.view.focus();
  return true;
}

export function setSelectedImageLayout(editor: Editor, value: string): boolean {
  switch (value) {
    case 'block-left':
      return updateSelectedImageAttrs(editor, { layout: 'block', align: 'left' });
    case 'block-right':
      return updateSelectedImageAttrs(editor, { layout: 'block', align: 'right' });
    case 'block':
    case 'block-center':
      return updateSelectedImageAttrs(editor, { layout: 'block', align: 'center' });
    case 'float-left':
      return updateSelectedImageAttrs(editor, { layout: 'float-left', align: 'left' });
    case 'float-right':
      return updateSelectedImageAttrs(editor, { layout: 'float-right', align: 'right' });
    case 'inline':
      return updateSelectedImageAttrs(editor, { layout: 'inline', align: 'center' });
    default:
      return false;
  }
}

export function resetSelectedImageCrop(editor: Editor): boolean {
  return updateSelectedImageAttrs(editor, {
    cropX: 0,
    cropY: 0,
    cropWidth: 1,
    cropHeight: 1,
  });
}

export function setSelectedImageAlt(editor: Editor, value: string): boolean {
  const alt = value.trim().slice(0, 1_000);
  return updateSelectedImageAttrs(editor, { alt: alt || null, decorative: false });
}

export function setSelectedImageDecorative(editor: Editor, decorative: boolean): boolean {
  return updateSelectedImageAttrs(editor, {
    decorative,
    ...(decorative ? { alt: '' } : {}),
  });
}

export const DocumentImage = Image.extend({
  addAttributes() {
    return {
      ...this.parent?.(),
      width: {
        default: null,
        parseHTML: (element: HTMLElement) => dimensionFromHTMLElement(element, 'width'),
        renderHTML: () => ({}),
      },
      height: {
        default: null,
        parseHTML: (element: HTMLElement) => dimensionFromHTMLElement(element, 'height'),
        renderHTML: () => ({}),
      },
      layout: {
        default: 'inline',
        parseHTML: (element: HTMLElement) => element.dataset.imageLayout || 'inline',
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-image-layout': normalizeImageLayout(attributes.layout),
        }),
      },
      align: {
        default: 'center',
        parseHTML: (element: HTMLElement) => element.dataset.imageAlign || 'center',
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-image-align': normalizeImageAlign(attributes.align),
        }),
      },
      decorative: {
        default: false,
        parseHTML: (element: HTMLElement) => element.dataset.imageDecorative === 'true',
        renderHTML: (attributes: Record<string, unknown>) => (
          attributes.decorative ? { 'data-image-decorative': 'true' } : {}
        ),
      },
      cropX: {
        default: 0,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.cropX, 0),
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-crop-x': String(numericImageAttr(attributes.cropX, 0)),
        }),
      },
      cropY: {
        default: 0,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.cropY, 0),
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-crop-y': String(numericImageAttr(attributes.cropY, 0)),
        }),
      },
      cropWidth: {
        default: 1,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.cropWidth, 1),
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-crop-width': String(numericImageAttr(attributes.cropWidth, 1)),
        }),
      },
      cropHeight: {
        default: 1,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.cropHeight, 1),
        renderHTML: (attributes: Record<string, unknown>) => ({
          'data-crop-height': String(numericImageAttr(attributes.cropHeight, 1)),
        }),
      },
      naturalWidth: {
        default: null,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.naturalWidth, 0) || null,
        renderHTML: (attributes: Record<string, unknown>) => {
          const width = numericImageAttr(attributes.naturalWidth, 0);
          return width > 0 ? { 'data-natural-width': String(width) } : {};
        },
      },
      naturalHeight: {
        default: null,
        parseHTML: (element: HTMLElement) => numericImageAttr(element.dataset.naturalHeight, 0) || null,
        renderHTML: (attributes: Record<string, unknown>) => {
          const height = numericImageAttr(attributes.naturalHeight, 0);
          return height > 0 ? { 'data-natural-height': String(height) } : {};
        },
      },
    };
  },
  renderHTML({ node, HTMLAttributes }) {
    const attrs = node.attrs as Record<string, unknown>;
    const layout = normalizeImageLayout(attrs.layout);
    const align = normalizeImageAlign(attrs.align);
    const crop = cropRectFromAttrs(attrs);
    const widthStyle = dimensionStyle(attrs.width);
    const heightStyle = dimensionStyle(attrs.height);
    const naturalWidth = numericImageAttr(attrs.naturalWidth, 0);
    const naturalHeight = numericImageAttr(attrs.naturalHeight, 0);
    const decorative = attrs.decorative === true;
    const suppliedAlt = typeof attrs.alt === 'string' ? attrs.alt.trim() : '';
    const baseAttrs = mergeAttributes(this.options.HTMLAttributes, HTMLAttributes, {
      class: 'editor-image',
      alt: decorative ? '' : (suppliedAlt || 'Image without a description'),
      ...(decorative ? { 'data-image-decorative': 'true' } : {}),
      'data-image-layout': layout,
      'data-image-align': align,
      ...cropDataAttrsFromRect(crop),
    });
    const existingStyle = typeof baseAttrs.style === 'string' ? baseAttrs.style : '';
    delete baseAttrs.style;

    if (!isDefaultCrop(crop)) {
      const widthPx = pixelDimension(attrs.width);
      if (widthPx && naturalWidth > 0 && naturalHeight > 0) {
        const frameHeight = widthPx * ((naturalHeight * crop.height) / (naturalWidth * crop.width));
        const imageWidth = widthPx / crop.width;
        const imageHeight = frameHeight / crop.height;
        const wrapperStyle = [
          existingStyle,
          ...imageLayoutStyleParts(layout, align),
          'position: relative',
          'overflow: hidden',
          'line-height: 0',
          `width: ${Math.round(widthPx)}px`,
          `height: ${Math.round(frameHeight)}px`,
        ].filter(Boolean).join('; ');
        const imgStyle = [
          'position: absolute',
          `left: ${Math.round(-crop.x * imageWidth)}px`,
          `top: ${Math.round(-crop.y * imageHeight)}px`,
          `width: ${Math.round(imageWidth)}px`,
          `height: ${Math.round(imageHeight)}px`,
          'max-width: none',
          'margin: 0',
        ].join('; ');

        return [
          'span',
          {
            class: 'editor-image-crop',
            style: wrapperStyle,
            'data-image-layout': layout,
            'data-image-align': align,
          },
          ['img', mergeAttributes(baseAttrs, { style: imgStyle })],
        ];
      }
    }

    const style = [
      existingStyle,
      ...imageLayoutStyleParts(layout, align),
      widthStyle ? `width: ${widthStyle}` : '',
      heightStyle ? `height: ${heightStyle}` : '',
    ].filter(Boolean).join('; ');

    return ['img', style ? mergeAttributes(baseAttrs, { style }) : baseAttrs];
  },
  addNodeView() {
    return ({ node, getPos, editor }) => {
      let currentNode = node;
      let isSelected = false;
      let isCropping = false;
      let draftWidth: number | null = null;
      let draftCrop: ImageCropRect | null = null;

      const container = document.createElement('span');
      container.className = 'document-image';
      container.contentEditable = 'false';

      const frame = document.createElement('span');
      frame.className = 'document-image-frame';
      container.appendChild(frame);

      const img = document.createElement('img');
      img.className = 'editor-image';
      frame.appendChild(img);

      const resizeHandles = IMAGE_RESIZE_HANDLES.map((direction) => {
        const handle = document.createElement('span');
        handle.className = `document-image-handle document-image-resize-handle document-image-handle-${direction}`;
        handle.dataset.direction = direction;
        container.appendChild(handle);
        return handle;
      });

      const cropHandles = IMAGE_RESIZE_HANDLES.map((direction) => {
        const handle = document.createElement('span');
        handle.className = `document-image-handle document-image-crop-handle document-image-handle-${direction}`;
        handle.dataset.direction = direction;
        frame.appendChild(handle);
        return handle;
      });

      const toolbar = document.createElement('span');
      toolbar.className = 'document-image-toolbar';
      container.appendChild(toolbar);

      const currentAttrs = (): Record<string, unknown> => ({
        ...currentNode.attrs,
        ...(draftWidth !== null ? { width: pixelDimensionAttr(draftWidth) } : {}),
        ...(draftCrop !== null ? cropAttrsFromRect(draftCrop) : {}),
      });

      const naturalSize = (attrs: Record<string, unknown>) => {
        const naturalWidth = numericImageAttr(attrs.naturalWidth, img.naturalWidth || 0);
        const naturalHeight = numericImageAttr(attrs.naturalHeight, img.naturalHeight || 0);
        if (naturalWidth <= 0 || naturalHeight <= 0) return null;
        return { width: naturalWidth, height: naturalHeight };
      };

      const measuredFrameWidth = (): number => {
        const rect = frame.getBoundingClientRect();
        if (rect.width > 0) return rect.width;
        const imageRect = img.getBoundingClientRect();
        if (imageRect.width > 0) return imageRect.width;
        return pixelDimension(currentAttrs().width) ?? MIN_IMAGE_WIDTH;
      };

      const imageMaxWidth = (): number => {
        const root = editor.view.dom as HTMLElement;
        const rootWidth = root.getBoundingClientRect().width;
        return Math.max(MIN_IMAGE_WIDTH, rootWidth || 720);
      };

      const selectImage = () => {
        if (typeof getPos !== 'function') return;
        const pos = getPos();
        if (typeof pos !== 'number') return;
        editor.view.dispatch(editor.state.tr.setSelection(NodeSelection.create(editor.state.doc, pos)));
        editor.view.focus();
      };

      const updateAttrs = (attrs: Record<string, unknown>) => {
        if (typeof getPos !== 'function') return;
        const pos = getPos();
        if (typeof pos !== 'number') return;
        const existingNode = editor.state.doc.nodeAt(pos);
        if (!existingNode || existingNode.type.name !== 'image') return;

        editor.view.dispatch(
          editor.state.tr.setNodeMarkup(pos, undefined, {
            ...existingNode.attrs,
            ...attrs,
          })
        );
        editor.view.focus();
      };

      const persistNaturalSize = (): Record<string, number> => {
        if (img.naturalWidth <= 0 || img.naturalHeight <= 0) return {};
        return {
          naturalWidth: img.naturalWidth,
          naturalHeight: img.naturalHeight,
        };
      };

      const render = () => {
        const attrs = currentAttrs();
        const layout = normalizeImageLayout(attrs.layout);
        const align = normalizeImageAlign(attrs.align);
        const crop = cropRectFromAttrs(attrs);
        const widthStyle = dimensionStyle(attrs.width);
        const widthPx = draftWidth ?? pixelDimension(attrs.width);
        const size = naturalSize(attrs);

        container.className = [
          'document-image',
          `document-image-layout-${layout}`,
          `document-image-align-${align}`,
          isSelected ? 'is-selected' : '',
          isCropping ? 'is-cropping' : '',
          !isDefaultCrop(crop) ? 'is-cropped' : '',
        ].filter(Boolean).join(' ');
        container.dataset.layout = layout;
        container.dataset.align = align;

        img.src = attrs.src as string;
        const decorative = attrs.decorative === true;
        const suppliedAlt = typeof attrs.alt === 'string' ? attrs.alt.trim() : '';
        img.alt = decorative ? '' : (suppliedAlt || 'Image without a description');
        img.title = (attrs.title as string) || '';

        frame.style.width = draftWidth !== null ? `${Math.round(draftWidth)}px` : (widthStyle || '');

        if (!isDefaultCrop(crop) && size && widthPx) {
          const frameHeight = widthPx * ((size.height * crop.height) / (size.width * crop.width));
          const imageWidth = widthPx / crop.width;
          const imageHeight = frameHeight / crop.height;

          frame.style.height = `${Math.round(frameHeight)}px`;
          img.style.position = 'absolute';
          img.style.left = `${Math.round(-crop.x * imageWidth)}px`;
          img.style.top = `${Math.round(-crop.y * imageHeight)}px`;
          img.style.width = `${Math.round(imageWidth)}px`;
          img.style.height = `${Math.round(imageHeight)}px`;
          img.style.maxWidth = 'none';
        } else {
          frame.style.height = '';
          img.style.position = '';
          img.style.left = '';
          img.style.top = '';
          img.style.width = widthStyle ? '100%' : '';
          img.style.height = 'auto';
          img.style.maxWidth = '';
        }

        Array.from(toolbar.querySelectorAll<HTMLButtonElement>('button[data-image-command]')).forEach((button) => {
          const command = button.dataset.imageCommand || '';
          button.classList.toggle(
            'is-active',
            command === layout ||
              command === `${layout}-${align}` ||
              (command === 'block-center' && layout === 'block' && align === 'center') ||
              (command === 'crop' && isCropping)
          );
        });
      };

      const commitResize = () => {
        if (draftWidth === null) return;
        updateAttrs({
          width: pixelDimensionAttr(draftWidth),
          height: null,
          ...persistNaturalSize(),
        });
        draftWidth = null;
      };

      const startResize = (event: MouseEvent, direction: ImageHandleDirection) => {
        event.preventDefault();
        event.stopPropagation();
        selectImage();
        isCropping = false;

        const startX = event.clientX;
        const startY = event.clientY;
        const startWidth = measuredFrameWidth();
        const attrs = currentAttrs();
        const crop = cropRectFromAttrs(attrs);
        const size = naturalSize(attrs);
        const aspect = size ? (size.height * crop.height) / (size.width * crop.width) : 1;

        const onMouseMove = (moveEvent: MouseEvent) => {
          const dx = moveEvent.clientX - startX;
          const dy = moveEvent.clientY - startY;
          let delta = 0;

          if (direction.includes('e')) delta = dx;
          if (direction.includes('w')) delta = -dx;
          if (direction === 'n' || direction === 's') {
            delta = (direction === 'n' ? -dy : dy) / Math.max(aspect, 0.1);
          }

          draftWidth = Math.min(imageMaxWidth(), Math.max(MIN_IMAGE_WIDTH, startWidth + delta));
          render();
        };

        const onMouseUp = () => {
          document.removeEventListener('mousemove', onMouseMove);
          document.removeEventListener('mouseup', onMouseUp);
          commitResize();
        };

        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
      };

      const commitCrop = () => {
        if (!draftCrop) return;
        const width = pixelDimension(currentAttrs().width) ?? measuredFrameWidth();
        updateAttrs({
          width: pixelDimensionAttr(width),
          ...cropAttrsFromRect(draftCrop),
          ...persistNaturalSize(),
        });
        draftCrop = null;
      };

      const startCropHandleDrag = (event: MouseEvent, direction: ImageHandleDirection) => {
        if (!isCropping) return;
        event.preventDefault();
        event.stopPropagation();
        selectImage();

        const startX = event.clientX;
        const startY = event.clientY;
        const startCrop = cropRectFromAttrs(currentAttrs());
        const frameRect = frame.getBoundingClientRect();
        const frameWidth = Math.max(1, frameRect.width);
        const frameHeight = Math.max(1, frameRect.height);

        const onMouseMove = (moveEvent: MouseEvent) => {
          const dx = ((moveEvent.clientX - startX) / frameWidth) * startCrop.width;
          const dy = ((moveEvent.clientY - startY) / frameHeight) * startCrop.height;
          let next = { ...startCrop };

          if (direction.includes('w')) {
            const right = startCrop.x + startCrop.width;
            next.x = Math.min(right - MIN_CROP_SIZE, Math.max(0, startCrop.x + dx));
            next.width = right - next.x;
          }

          if (direction.includes('e')) {
            next.width = Math.min(1 - startCrop.x, Math.max(MIN_CROP_SIZE, startCrop.width + dx));
          }

          if (direction.includes('n')) {
            const bottom = startCrop.y + startCrop.height;
            next.y = Math.min(bottom - MIN_CROP_SIZE, Math.max(0, startCrop.y + dy));
            next.height = bottom - next.y;
          }

          if (direction.includes('s')) {
            next.height = Math.min(1 - startCrop.y, Math.max(MIN_CROP_SIZE, startCrop.height + dy));
          }

          draftCrop = constrainCropRect(next);
          render();
        };

        const onMouseUp = () => {
          document.removeEventListener('mousemove', onMouseMove);
          document.removeEventListener('mouseup', onMouseUp);
          commitCrop();
        };

        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
      };

      const startCropPan = (event: MouseEvent) => {
        if (!isCropping) return;
        if (event.target instanceof Element && event.target.closest('.document-image-handle, .document-image-toolbar')) {
          return;
        }

        event.preventDefault();
        event.stopPropagation();
        selectImage();

        const startX = event.clientX;
        const startY = event.clientY;
        const startCrop = cropRectFromAttrs(currentAttrs());
        const frameRect = frame.getBoundingClientRect();
        const frameWidth = Math.max(1, frameRect.width);
        const frameHeight = Math.max(1, frameRect.height);

        const onMouseMove = (moveEvent: MouseEvent) => {
          const dx = ((moveEvent.clientX - startX) / frameWidth) * startCrop.width;
          const dy = ((moveEvent.clientY - startY) / frameHeight) * startCrop.height;
          draftCrop = constrainCropRect({
            ...startCrop,
            x: Math.min(1 - startCrop.width, Math.max(0, startCrop.x - dx)),
            y: Math.min(1 - startCrop.height, Math.max(0, startCrop.y - dy)),
          });
          render();
        };

        const onMouseUp = () => {
          document.removeEventListener('mousemove', onMouseMove);
          document.removeEventListener('mouseup', onMouseUp);
          commitCrop();
        };

        document.addEventListener('mousemove', onMouseMove);
        document.addEventListener('mouseup', onMouseUp);
      };

      const setLayout = (layout: ImageLayout, align: ImageAlign = 'center') => {
        updateAttrs({ layout, align });
      };

      const toggleCropMode = () => {
        selectImage();
        isCropping = !isCropping;
        if (isCropping && !pixelDimension(currentAttrs().width)) {
          updateAttrs({
            width: pixelDimensionAttr(measuredFrameWidth()),
            ...persistNaturalSize(),
          });
        }
        render();
      };

      const resetCrop = () => {
        isCropping = false;
        updateAttrs({
          cropX: 0,
          cropY: 0,
          cropWidth: 1,
          cropHeight: 1,
        });
      };

      const addToolbarButton = (
        command: string,
        label: string,
        title: string,
        action: () => void
      ) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.dataset.imageCommand = command;
        button.textContent = label;
        button.title = title;
        button.addEventListener('mousedown', (event) => {
          event.preventDefault();
          event.stopPropagation();
        });
        button.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          action();
        });
        toolbar.appendChild(button);
      };

      addToolbarButton('inline', 'Inline', 'Inline image', () => setLayout('inline', 'center'));
      addToolbarButton('block-center', 'Center', 'Centered image', () => setLayout('block', 'center'));
      addToolbarButton('float-left', 'Left', 'Float left', () => setLayout('float-left', 'left'));
      addToolbarButton('float-right', 'Right', 'Float right', () => setLayout('float-right', 'right'));
      addToolbarButton('crop', 'Crop', 'Crop image', toggleCropMode);
      addToolbarButton('reset-crop', 'Reset', 'Reset crop', resetCrop);

      const onContainerMouseDown = (event: MouseEvent) => {
        if (event.target instanceof Element && event.target.closest('.document-image-toolbar, .document-image-handle')) {
          return;
        }

        selectImage();
        if (isCropping) {
          startCropPan(event);
        }
      };

      const onImageLoad = () => {
        render();
      };

      container.addEventListener('mousedown', onContainerMouseDown);
      img.addEventListener('load', onImageLoad);

      resizeHandles.forEach((handle) => {
        handle.addEventListener('mousedown', (event) => {
          startResize(event, handle.dataset.direction as ImageHandleDirection);
        });
      });

      cropHandles.forEach((handle) => {
        handle.addEventListener('mousedown', (event) => {
          startCropHandleDrag(event, handle.dataset.direction as ImageHandleDirection);
        });
      });

      render();

      return {
        dom: container,
        update(updatedNode) {
          if (updatedNode.type.name !== 'image') return false;
          currentNode = updatedNode;
          draftWidth = null;
          draftCrop = null;
          render();
          return true;
        },
        selectNode() {
          isSelected = true;
          render();
        },
        deselectNode() {
          isSelected = false;
          isCropping = false;
          draftWidth = null;
          draftCrop = null;
          render();
        },
        stopEvent(event) {
          if (!(event.target instanceof Element)) return false;
          return Boolean(
            event.target.closest('.document-image-toolbar, .document-image-handle') ||
              (isCropping && event.type.startsWith('mouse'))
          );
        },
        destroy() {
          container.removeEventListener('mousedown', onContainerMouseDown);
          img.removeEventListener('load', onImageLoad);
        },
      };
    };
  },
});
