// JS ↔ Swift bridge via WKScriptMessageHandler

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        editorBridge?: {
          postMessage(message: string): void;
        };
      };
    };
  }
}

export type BridgeMessageType =
  | 'editorReady'
  | 'contentChanged'
  | 'contentUpdate'
  | 'selectionChanged'
  | 'wordCount'
  | 'pendingEditUpdate'
  | 'commentsChanged'
  | 'commentActivated'
  | 'openURL';

export interface BridgeMessage {
  type: BridgeMessageType;
  payload: unknown;
}

export function sendToSwift(type: BridgeMessageType, payload: unknown = {}): void {
  const message: BridgeMessage = { type, payload };
  const json = JSON.stringify(message);
  window.webkit?.messageHandlers?.editorBridge?.postMessage(json);
}

// Swift calls these functions on the JS side
export function registerSwiftCallbacks(callbacks: {
  loadContent: (html: string) => void;
  loadJSONContent: (json: string) => void;
  getContent: () => string;
  getDocumentSnapshot: () => string;
  getPlainText: () => string;
  getSelectionClipboardData: () => string;
  applyFormat: (command: string, value?: string) => void;
  focus: () => void;
  setEditable: (editable: boolean) => void;
  setSpellcheckEnabled: (enabled: boolean) => void;
  setAutocorrectEnabled: (enabled: boolean) => void;
  setZoomScale: (scale: number) => void;
  getSelectedText: () => string;
  setThemeCSS: (css: string) => void;
  findInDocument: (query: string) => number;
  findNext: () => string;
  findPrevious: () => string;
  replaceOne: (replacement: string) => string;
  replaceAll: (replacement: string) => number;
  clearFind: () => void;
  deleteSelection: () => void;
  replaceSelectionHTML: (html: string) => void;
  insertHTMLAtCursor: (html: string) => void;
  findAndReplaceText: (find: string, replaceHtml: string, replaceAllOccurrences: boolean) => number;
  pendingReplaceSelection: (id: string, html: string, target?: any) => number;
  pendingInsertAtCursor: (id: string, html: string, target?: any) => number;
  pendingFindAndReplace: (id: string, find: string, replaceHtml: string, replaceAll: boolean) => number;
  pendingProposeEdit: (id: string, target: any, replaceHtml: string, replaceAll: boolean) => number;
  acceptAllPendingEdits: () => void;
  rejectAllPendingEdits: () => void;
  acceptPendingEdit: (id: string) => boolean;
  rejectPendingEdit: (id: string) => boolean;
  focusPendingEdit: (id: string) => boolean;
  focusNextPendingEdit: () => boolean;
  focusPreviousPendingEdit: () => boolean;
  getPendingEdits: () => string;
  getPendingEditCount: () => number;
  getEditContextSnapshot: () => string;
  addComment: (commentId: string) => boolean;
  addCommentAtRange: (commentJSON: string) => boolean;
  updateCommentText: (commentId: string, text: string) => void;
  setCommentStatus: (commentId: string, status: string) => void;
  removeComment: (commentId: string) => void;
  focusComment: (commentId: string) => void;
  pendingReplaceComment: (commentId: string, editId: string, html: string) => number;
  getComments: () => string;
}): void {
  (window as any).editorAPI = callbacks;
}
