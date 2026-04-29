import { StateField, StateEffect, EditorState } from "@codemirror/state";
import { Decoration, keymap } from "@codemirror/view";
import { RangeSetBuilder } from "@codemirror/state";
import { EditorView } from "@codemirror/view";
import { applyCompletion, getIndent, needsClosingEnd, findEnclosingIfIndent } from "./editorUtils"
import { foldService, getIndentUnit, indentService } from "@codemirror/language";

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

const autoClose = {
  key: ":",
  run: (view) => {
    const { state } = view;
    const { from, to, empty } = state.selection.main;

    if (!empty) return false;

    const line = state.doc.lineAt(from);
    const textBefore = line.text.slice(0, from - line.from);

    const match = textBefore.match(/^\s*(def|if|else)\b.*$/);
    if (!match) return false;

    const keyword = match[1];
    const baseIndent = getIndent(textBefore);
    const indentStr = " ".repeat(getIndentUnit(state));

    // Handle 'else' (Snap back to enclosing if)
    if (keyword === "else") {
      const targetIndent = findEnclosingIfIndent(state, line.number);
      if (targetIndent === null) return false;

      // Notice we use targetIndent here instead of baseIndent
      const insertText = `${targetIndent}else:\n${targetIndent}${indentStr}`;

      // Notice we use line.from here to overwrite the entire incorrectly-indented line
      applyCompletion(view, line.from, to, insertText, insertText.length);
      return true;
    }

    // Handle 'def' and 'if'
    const requiresEnd = needsClosingEnd(state, line.number, baseIndent);

    if (requiresEnd) {
      const insertText = `:\n${baseIndent}${indentStr}\n${baseIndent}end`;
      applyCompletion(view, from, to, insertText, 2 + baseIndent.length + indentStr.length);
    } else {
      const insertText = `:\n${baseIndent}${indentStr}`;
      applyCompletion(view, from, to, insertText, insertText.length);
    }

    return true;
  }
};

const pilLanguageData = EditorState.languageData.of(() => [{
  commentTokens: { line: "//" },
  closeBrackets: { brackets: ["("] },
  indentOnInput: /^\s*(end|else)$/,
}]);

const pilFoldService = foldService.of((state, lineStart, lineEnd) => {
  const line = state.doc.lineAt(lineStart);

  // Only start a fold if the line opens a scope (def|if|else)
  if (!line.text.match(/^\s*(def|if|else)\b.*:\s*$/)) return null;
  let depth = 1;

  for (let i = line.number + 1; i <= state.doc.lines; i++) {
    const nextLine = state.doc.line(i);
    const text = nextLine.text;

    if (text.match(/^\s*else\b.*:\s*$/)) {
      if (depth === 1) {
        return { from: line.to, to: nextLine.from - 1 };
      }
    }
    else if (text.match(/^\s*end\b/)) {
      depth--;
      if (depth === 0) {
        return { from: line.to, to: nextLine.from - 1 };
      }
    }
    else if (text.match(/^\s*(def|if)\b.*:\s*$/)) {
      depth++;
    }
  }

  return null;
});

const pilIndentService = indentService.of((context, pos) => {
  const line = context.lineAt(pos);

  // If we are on the first line, indent is 0
  if (line.from === 0) return 0;

  const prevLine = context.lineAt(line.from - 1);

  // Grab the base indentation of the previous line
  let indent = prevLine.text.match(/^\s*/)[0].length;

  if (prevLine.text.match(/:\s*$/)) {
    indent += context.unit;
  }

  if (line.text.match(/^\s*(end|else\b)/)) {
    indent = Math.max(0, indent - context.unit);
  }

  return indent;
});

export function pilLanguage() {
  return [
    pilLanguageData,
    pilIndentService,
    pilFoldService,
    semanticTokensField,
    keymap.of([autoClose]) // Bundle language-specific keys here
  ];
}
