// JS ↔ Swift bridge via WKScriptMessageHandler

declare global {
  interface Window {
    webkit?: {
      messageHandlers?: {
        editorBridge?: {
          postMessage(message: unknown): void;
        };
      };
    };
  }
}

export type BridgeMessageType =
  | 'editorReady'
  | 'contentUpdate'
  | 'documentMetrics'
  | 'selectionChanged'
  | 'pendingEditUpdate'
  | 'editDecision'
  | 'commentsChanged'
  | 'commentActivated'
  | 'proofreadingUpdate'
  | 'proofreadingUserStateChanged'
  | 'imageImportRequested'
  | 'openURL';

export interface BridgeMessage {
  type: BridgeMessageType;
  payload: unknown;
}

export function sendToSwift(type: BridgeMessageType, payload: unknown = {}): void {
  const message: BridgeMessage = { type, payload };
  window.webkit?.messageHandlers?.editorBridge?.postMessage(message);
}

// Swift calls these functions on the JS side
export function registerSwiftCallbacks(callbacks: {
  loadContent: (html: string) => boolean;
  loadJSONContent: (json: string) => boolean;
  setEditorEditable: (enabled: boolean) => void;
  getDocumentSnapshot: () => unknown;
  getReferencedAssetSources: () => string;
  acknowledgePersonalizationOutcomes: (actionIds: string[]) => void;
  getPlainText: () => string;
  getSelectionClipboardData: () => string;
  applyFormat: (command: string, value?: string) => void;
  focus: () => void;
  setSpellcheckEnabled: (enabled: boolean) => void;
  setAutocorrectEnabled: (enabled: boolean) => void;
  setProofreadingOptions: (spelling: boolean, grammar: boolean, dialect: string) => void;
  setProofreadingUserState: (json: string) => void;
  setAIGrammarIssues: (json: string) => void;
  resetProofreadingDictionary: () => void;
  getGrammarContextSnapshot: () => string;
  completeImageImport: (requestId: string, source: string, errorMessage?: string) => void;
  setZoomScale: (scale: number) => void;
  getSelectedText: () => string;
  setThemeCSS: (css: string) => void;
  setDefaultTypography: (fontFamily: string, fontSize: number, lineHeight: number) => void;
  findInDocument: (query: string) => number;
  findNext: () => string;
  findPrevious: () => string;
  replaceOne: (replacement: string) => string;
  replaceAll: (replacement: string) => number;
  clearFind: () => void;
  deleteSelection: () => void;
  replaceSelectionHTML: (html: string) => void;
  insertHTMLAtCursor: (html: string) => void;
  acceptAllPendingEdits: () => void;
  rejectAllPendingEdits: () => void;
  acceptPendingEdit: (id: string) => boolean;
  rejectPendingEdit: (id: string) => boolean;
  focusPendingEdit: (id: string) => boolean;
  focusNextPendingEdit: () => boolean;
  focusPreviousPendingEdit: () => boolean;
  getEditContextSnapshot: () => string;
  addComment: (commentId: string) => boolean;
  addCommentAtRange: (commentJSON: string) => boolean;
  updateCommentText: (commentId: string, text: string) => void;
  setCommentStatus: (commentId: string, status: string) => void;
  removeComment: (commentId: string) => void;
  focusComment: (commentId: string) => void;
  pendingReplaceComment: (commentId: string, editId: string, html: string) => number;
}): void {
  (window as any).editorAPI = callbacks;
}
