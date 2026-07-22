import type { Editor } from '@tiptap/core';

// Holds the singleton editor instance so feature modules (e.g. pending-edit
// widget click handlers) can reach it without importing editor.ts, which
// would create a module cycle through the entry point.
let editorInstance: Editor | null = null;

export function setEditorInstance(editor: Editor): void {
  editorInstance = editor;
}

export function getEditorInstance(): Editor {
  if (!editorInstance) {
    throw new Error('Editor instance not initialized');
  }
  return editorInstance;
}
