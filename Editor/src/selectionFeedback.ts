import { Editor, Extension } from '@tiptap/core';
import { Plugin, PluginKey } from '@tiptap/pm/state';
import { Decoration, DecorationSet } from '@tiptap/pm/view';
import { sendToSwift } from './bridge';
import { selectionIsWithinWritingGap } from './gapSuggestions';

const selectionFeedbackPluginKey = new PluginKey<DecorationSet>('selectionFeedback');

function selectionFeedbackWidget(): HTMLElement {
  const anchor = document.createElement('span');
  anchor.className = 'selection-feedback-anchor';
  anchor.contentEditable = 'false';

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'selection-feedback-action';
  button.textContent = '✦';
  button.title = 'Feedback on selection';
  button.setAttribute('aria-label', 'Ask for feedback on selected text');
  button.addEventListener('mousedown', (event) => {
    event.preventDefault();
    event.stopPropagation();
  });
  button.addEventListener('click', (event) => {
    event.preventDefault();
    event.stopPropagation();
    sendToSwift('selectionFeedbackRequested');
  });
  anchor.appendChild(button);
  return anchor;
}

function buildSelectionFeedbackDecoration(editor: Editor, state: any): DecorationSet {
  const { from, to, empty } = state.selection;
  if (empty || !editor.isEditable) return DecorationSet.empty;
  if (selectionIsWithinWritingGap(state)) return DecorationSet.empty;
  const selectedText = state.doc.textBetween(from, to, '\n', '\n').trim();
  if (!selectedText) return DecorationSet.empty;

  return DecorationSet.create(state.doc, [
    Decoration.widget(to, selectionFeedbackWidget, {
      key: `selection-feedback-${from}-${to}`,
      side: 1,
      ignoreSelection: true,
      stopEvent: (event) => (
        event.target instanceof Element &&
        event.target.closest('.selection-feedback-anchor') !== null
      ),
    }),
  ]);
}

export const SelectionFeedback = Extension.create({
  name: 'selectionFeedback',

  addProseMirrorPlugins() {
    const editor = this.editor;
    return [
      new Plugin<DecorationSet>({
        key: selectionFeedbackPluginKey,
        state: {
          init(_, state) {
            return buildSelectionFeedbackDecoration(editor, state);
          },
          apply(tr, previous, _oldState, newState) {
            if (!tr.docChanged && !tr.selectionSet) return previous;
            return buildSelectionFeedbackDecoration(editor, newState);
          },
        },
        props: {
          decorations(state) {
            return selectionFeedbackPluginKey.getState(state) ?? DecorationSet.empty;
          },
        },
      }),
    ];
  },
});
