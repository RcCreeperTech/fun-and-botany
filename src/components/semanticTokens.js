import { StateField, StateEffect } from "@codemirror/state";
import { Decoration } from "@codemirror/view";
import { RangeSetBuilder } from "@codemirror/state";
import { EditorView } from "@codemirror/view";

export const updateSemanticTokens = StateEffect.define();

const tokenClasses = [
  "cm-sem-none",        // 0
  "cm-sem-variable",    // 1
  "cm-sem-function",    // 2
  "cm-sem-constant",    // 3
  "cm-sem-property",    // 4
  "cm-sem-builtin",     // 5
  "cm-sem-keyword",     // 6
  "cm-sem-number",      // 7
  "cm-sem-string",      // 8
  "cm-sem-color",       // 9
  "cm-sem-boolean",     // 10
  "cm-sem-operator",    // 11
  "cm-sem-punctuation", // 12
  "cm-sem-comment"      // 13
];

const tokenMarks = tokenClasses.map(cls => Decoration.mark({ class: cls }));

export const semanticTokensField = StateField.define({
  create() {
    return Decoration.none;
  },
  update(decorations, tr) {
    // Shift existing decorations automatically as the user types
    // This prevents flickering while waiting for the worker to return the new AST
    decorations = decorations.map(tr.changes);

    // Apply new tokens when the worker replies
    for (let e of tr.effects) {
      if (e.is(updateSemanticTokens)) {
        return buildDecorations(e.value, tr.state.doc);
      }
    }
    return decorations;
  },
  provide: f => EditorView.decorations.from(f) // Injects them into the render pipeline
});

function buildDecorations(tokens, doc) {
  const builder = new RangeSetBuilder();

  let lastOffset = -1;

  tokens.forEach(({ offset, length, info }) => {
    const kind = info & 0xFF; // Lower 8 bits is the enum value

    if (!length || offset < 0 || offset + length > doc.length) { return; }
    if (offset === lastOffset) { return; }

    builder.add(offset, offset + length, tokenMarks[kind] || tokenMarks[0]);
    lastOffset = offset;
  });

  return builder.finish();
}
