import assert from 'node:assert/strict';
import test from 'node:test';
import { getMarkAttributes, getSchema } from '@tiptap/core';
import FontFamily from '@tiptap/extension-font-family';
import TextStyle from '@tiptap/extension-text-style';
import TextAlign from '@tiptap/extension-text-align';
import StarterKit from '@tiptap/starter-kit';
import { EditorState, TextSelection } from '@tiptap/pm/state';
import {
  FontSize,
  LineHeight,
  normalizeFontFamily,
  normalizeFontSize,
  normalizeLineHeight,
  selectedLineHeight,
  selectedTextAlignment,
  selectedTextStyleAttribute,
  setDefaultTypography,
} from '../src/typography.ts';

const schema = getSchema([
  StarterKit.configure({ heading: { levels: [1, 2, 3] } }),
  TextAlign.configure({ types: ['heading', 'paragraph'] }),
  FontFamily,
  TextStyle,
  FontSize,
  LineHeight,
]);

function editorFor(state) {
  return {
    state,
    getAttributes(name) {
      return name === 'textStyle' ? getMarkAttributes(state, 'textStyle') : {};
    },
  };
}

function mutableEditorFor(initialState) {
  let state = initialState;
  const editor = {
    get state() {
      return state;
    },
    getAttributes(name) {
      return name === 'textStyle' ? getMarkAttributes(state, 'textStyle') : {};
    },
    view: {
      dispatch(transaction) {
        state = state.apply(transaction);
      },
    },
  };
  return { editor, state: () => state };
}

test('typography values are normalized to the supported toolbar ranges', () => {
  assert.equal(normalizeFontFamily('Georgia'), 'Georgia');
  assert.equal(normalizeFontFamily('Comic Sans MS'), null);
  assert.equal(normalizeFontSize('20px'), '20px');
  assert.equal(normalizeFontSize('18.50'), '18.5px');
  assert.equal(normalizeFontSize('72px'), null);
  assert.equal(normalizeLineHeight('1.70'), '1.7');
  assert.equal(normalizeLineHeight('3'), null);
});

test('font size survives the canonical ProseMirror JSON round trip', () => {
  const mark = schema.marks.textStyle.create({
    fontFamily: 'Palatino',
    fontSize: '22px',
  });
  const document = schema.node('doc', null, [
    schema.node('paragraph', { lineHeight: '1.9' }, [
      schema.text('Persisted typography', [mark]),
    ]),
  ]);

  const restored = schema.nodeFromJSON(document.toJSON());
  const paragraph = restored.firstChild;
  const text = paragraph?.firstChild;
  assert.equal(paragraph?.attrs.lineHeight, '1.9');
  assert.equal(text?.marks[0]?.attrs.fontFamily, 'Palatino');
  assert.equal(text?.marks[0]?.attrs.fontSize, '22px');
});

test('mixed inline typography is reported instead of borrowing the first mark', () => {
  const sized = schema.marks.textStyle.create({ fontSize: '20px' });
  const document = schema.node('doc', null, [
    schema.node('paragraph', null, [
      schema.text('large', [sized]),
      schema.text('plain'),
    ]),
  ]);
  const state = EditorState.create({
    schema,
    doc: document,
    selection: TextSelection.create(document, 1, document.content.size - 1),
  });

  assert.deepEqual(
    selectedTextStyleAttribute(editorFor(state), 'fontSize'),
    { value: '', mixed: true }
  );
});

test('collapsed selections report the stored font size for future text', () => {
  const document = schema.node('doc', null, [
    schema.node('paragraph', null, [schema.text('text')]),
  ]);
  let state = EditorState.create({
    schema,
    doc: document,
    selection: TextSelection.create(document, 3),
  });
  state = state.apply(
    state.tr.addStoredMark(schema.marks.textStyle.create({ fontSize: '24px' }))
  );

  assert.deepEqual(
    selectedTextStyleAttribute(editorFor(state), 'fontSize'),
    { value: '24px', mixed: false }
  );
});

test('line height reports mixed paragraph formatting across a selection', () => {
  const document = schema.node('doc', null, [
    schema.node('paragraph', { lineHeight: '1.5' }, [schema.text('one')]),
    schema.node('paragraph', { lineHeight: '2' }, [schema.text('two')]),
  ]);
  const state = EditorState.create({
    schema,
    doc: document,
    selection: TextSelection.create(document, 1, document.content.size - 1),
  });

  assert.deepEqual(selectedLineHeight(editorFor(state)), { value: '', mixed: true });
});

test('mixed block alignment does not masquerade as left alignment', () => {
  const document = schema.node('doc', null, [
    schema.node('paragraph', { textAlign: null }, [schema.text('left')]),
    schema.node('paragraph', { textAlign: 'center' }, [schema.text('center')]),
  ]);
  const state = EditorState.create({
    schema,
    doc: document,
    selection: TextSelection.create(document, 1, document.content.size - 1),
  });

  assert.equal(selectedTextAlignment(editorFor(state)), 'mixed');
});

test('new-document defaults use stored marks without changing the empty document', () => {
  const document = schema.node('doc', null, [schema.node('paragraph')]);
  const initialState = EditorState.create({ schema, doc: document });
  const mutable = mutableEditorFor(initialState);

  assert.equal(setDefaultTypography(mutable.editor, 'Palatino', 24, 2), true);
  assert.equal(mutable.state().doc.eq(document), true);
  assert.equal(getMarkAttributes(mutable.state(), 'textStyle').fontFamily, 'Palatino');
  assert.equal(getMarkAttributes(mutable.state(), 'textStyle').fontSize, '24px');
  assert.deepEqual(selectedLineHeight(mutable.editor), { value: '2', mixed: false });

  setDefaultTypography(mutable.editor, 'Georgia', 18, 1.7);
  assert.equal(mutable.state().storedMarks?.length, 0);
});
