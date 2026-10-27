// Lua editor: CodeMirror 6 with the Lua stream mode and a theme matched to the shell.

import { EditorState, StateEffect, StateField } from '@codemirror/state'
import { Decoration, EditorView, keymap, lineNumbers, highlightActiveLine, highlightActiveLineGutter, drawSelection, type DecorationSet } from '@codemirror/view'
import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands'
import { StreamLanguage, HighlightStyle, syntaxHighlighting, indentOnInput, bracketMatching } from '@codemirror/language'
import { lua } from '@codemirror/legacy-modes/mode/lua'
import { tags as t } from '@lezer/highlight'

const theme = EditorView.theme(
  {
    '&': { color: '#e6e6e6', backgroundColor: '#141414', height: '100%' },
    '.cm-content': { caretColor: '#ffffff', padding: '10px 0' },
    '.cm-cursor': { borderLeftColor: '#ffffff', borderLeftWidth: '2px' },
    '&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection': { backgroundColor: 'rgba(61,123,253,0.28) !important' },
    '.cm-gutters': { backgroundColor: '#141414', color: '#4d4d4d', border: 'none', paddingRight: '6px' },
    '.cm-activeLine': { backgroundColor: '#1a1a1a' },
    '.cm-activeLineGutter': { backgroundColor: 'transparent', color: '#9a9a9a' },
    '.cm-matchingBracket': { backgroundColor: '#2a2a2a', outline: '1px solid #3a3a3a' },
    '&.cm-focused': { outline: 'none' },
    '.cm-error-line': { backgroundColor: 'rgba(255,112,112,0.14)', boxShadow: 'inset 2px 0 0 #ff7070' },
  },
  { dark: true },
)

// the line a script error points at, cleared on the next edit
const setErrorLine = StateEffect.define<number | null>()
const errorLine = StateField.define<DecorationSet>({
  create: () => Decoration.none,
  update(deco, tr) {
    for (const e of tr.effects) {
      if (e.is(setErrorLine)) {
        if (e.value == null || e.value < 1 || e.value > tr.state.doc.lines) return Decoration.none
        return Decoration.set([Decoration.line({ class: 'cm-error-line' }).range(tr.state.doc.line(e.value).from)])
      }
    }
    return tr.docChanged ? Decoration.none : deco.map(tr.changes)
  },
  provide: (f) => EditorView.decorations.from(f),
})

const highlight = HighlightStyle.define([
  { tag: t.keyword, color: '#f2f2f2', fontWeight: '600' },
  { tag: [t.string, t.special(t.string)], color: '#b5d68c' },
  { tag: t.number, color: '#f0b46c' },
  { tag: t.comment, color: '#6a6a6a', fontStyle: 'italic' },
  { tag: [t.bool, t.null, t.atom], color: '#f0b46c' },
  { tag: [t.variableName, t.name], color: '#e0e0e0' },
  { tag: t.standard(t.variableName), color: '#8fc1ff' },
  { tag: t.operator, color: '#a8a8a8' },
  { tag: t.bracket, color: '#9a9a9a' },
])

export function createEditor(parent: HTMLElement, doc: string, onRun: () => void, onChange: (s: string) => void) {
  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc,
      extensions: [
        lineNumbers(),
        highlightActiveLine(),
        highlightActiveLineGutter(),
        drawSelection(),
        history(),
        indentOnInput(),
        bracketMatching(),
        StreamLanguage.define(lua),
        syntaxHighlighting(highlight),
        EditorState.tabSize.of(4),
        keymap.of([
          { key: 'Mod-Enter', run: () => (onRun(), true) },
          { key: 'Mod-s', run: () => (onRun(), true) },
          indentWithTab,
          ...defaultKeymap,
          ...historyKeymap,
        ]),
        EditorView.updateListener.of((u) => {
          if (u.docChanged) onChange(u.state.doc.toString())
        }),
        theme,
        errorLine,
      ],
    }),
  })
  return {
    view,
    get: () => view.state.doc.toString(),
    set: (s: string) => view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: s } }),
    markError: (line: number | null) => {
      const effects: StateEffect<unknown>[] = [setErrorLine.of(line)]
      if (line != null && line >= 1 && line <= view.state.doc.lines) effects.push(EditorView.scrollIntoView(view.state.doc.line(line).from, { y: 'center' }))
      view.dispatch({ effects })
    },
  }
}
