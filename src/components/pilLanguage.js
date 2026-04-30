import { StateField, StateEffect, EditorState } from "@codemirror/state";
import { Decoration, hoverTooltip, keymap } from "@codemirror/view";
import { RangeSetBuilder } from "@codemirror/state";
import { EditorView, ViewPlugin } from "@codemirror/view";
import { applyCompletion, getIndent, needsClosingEnd, findEnclosingIfIndent } from "./editorUtils"
import { foldService, getIndentUnit, indentService } from "@codemirror/language";
import 'vanilla-colorful/hex-alpha-color-picker.js';

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

    if (kind === 9) { // Color
      // Extract the string, e.g., "#FF0000FF" or "#FF_00_00_FF"
      const rawHex = doc.sliceString(offset, offset + length);
      const cleanHex = rawHex.replace(/_/g, ""); // Strip underscores
      const isLegalHexCode = cleanHex.length == 9;
      const color = (isLegalHexCode) ? cleanHex : "white";

      // HTML/CSS supports 8-digit hex (RRGGBBAA) natively
      builder.add(offset, offset + length, Decoration.mark({
        attributes: {
          style:
            `color: ${color};
             font-weight: bold;
             padding: 0 2px;
             border-bottom: 2px solid ${color};`
        }
      }));
    } else {
      builder.add(offset, offset + length, tokenMarks[kind] || tokenMarks[0]);
    }

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

const colorPickerPlugin = ViewPlugin.fromClass(class {
  constructor(view) {
    this.view = view;
    this.container = document.createElement("div");

    this.container.className =
      `fixed z-50 p-3 rounded-xl shadow-2xl
       bg-background border border-gray-800
       transition-all duration-200 ease-in-out
       opacity-0 pointer-events-none translate-y-1`;

    this.picker = document.createElement("hex-alpha-color-picker");
    this.container.appendChild(this.picker);
    document.body.appendChild(this.container);

    this.isDragging = false;
    this.activeRange = null;
    this.hideTimeout = null;

    this.picker.addEventListener("mousedown", () => { this.isDragging = true; });
    window.addEventListener("mouseup", () => {
      if (this.isDragging) {
        this.isDragging = false;
        if (!this.container.matches(':hover')) this.scheduleHide();
      }
    });

    this.container.addEventListener("mouseenter", () => this.cancelHide());
    this.container.addEventListener("mouseleave", () => {
      if (!this.isDragging) this.scheduleHide();
    });

    this.onMouseMove = this.onMouseMove.bind(this);
    this.onMouseLeave = this.onMouseLeave.bind(this);
    this.view.dom.addEventListener("mousemove", this.onMouseMove);
    this.view.dom.addEventListener("mouseleave", this.onMouseLeave);

    this.picker.addEventListener("color-changed", (e) => {
      if (!this.activeRange) return;

      let newHex = e.detail.value.toUpperCase();

      if (newHex.length === 7) newHex += "FF";

      const { from, to } = this.activeRange;
      this.view.dispatch({ changes: { from, to, insert: newHex } });

      this.activeRange.to = from + newHex.length;
    });
  }

  scheduleHide() {
    if (this.hideTimeout) return;
    // Wait 300ms before actually fading out
    this.hideTimeout = setTimeout(() => this.hide(), 300);
  }

  cancelHide() {
    if (this.hideTimeout) {
      clearTimeout(this.hideTimeout);
      this.hideTimeout = null;
    }
  }

  onMouseMove(e) {
    if (this.isDragging) return;

    const pos = this.view.posAtCoords({ x: e.clientX, y: e.clientY });
    if (!pos) return this.scheduleHide();

    const line = this.view.state.doc.lineAt(pos);
    let start = pos, end = pos;

    while (start > line.from && /[\da-fA-F_#]/.test(line.text[start - 1 - line.from])) start--;
    while (end < line.to && /[\da-fA-F_#]/.test(line.text[end - line.from])) end++;

    const startCoords = this.view.coordsAtPos(start);
    const endCoords = this.view.coordsAtPos(end);
    if (!startCoords || !endCoords || e.clientX < startCoords.left || e.clientX > endCoords.right) {
      return this.scheduleHide();
    }

    const word = line.text.slice(start - line.from, end - line.from);
    if (/^#[\da-fA-F_]+$/.test(word)) {
      const cleanHex = word.replace(/_/g, "");
      if (cleanHex.length === 9) {
        this.cancelHide();
        return this.show(start, end, cleanHex);
      }
    }

    this.scheduleHide();
  }

  onMouseLeave(e) {
    if (e.relatedTarget === this.container || this.container.contains(e.relatedTarget)) return;
    if (!this.isDragging) this.scheduleHide();
  }

  show(from, to, color) {
    this.activeRange = { from, to };
    this.picker.color = color;

    // Apply Tailwind classes to trigger the fade-in and slide-up animation
    this.container.classList.remove("opacity-0", "pointer-events-none", "translate-y-1");
    this.container.classList.add("opacity-100", "pointer-events-auto", "translate-y-0");

    const coords = this.view.coordsAtPos(from);
    if (coords) {
      this.container.style.left = coords.left + "px";
      this.container.style.top = (coords.bottom + 8) + "px";
    }
  }

  hide() {
    // Apply Tailwind classes to trigger the fade-out and slide-down animation
    this.container.classList.remove("opacity-100", "pointer-events-auto", "translate-y-0");
    this.container.classList.add("opacity-0", "pointer-events-none", "translate-y-1");

    this.activeRange = null;
    this.hideTimeout = null;
  }

  destroy() {
    this.view.dom.removeEventListener("mousemove", this.onMouseMove);
    this.view.dom.removeEventListener("mouseleave", this.onMouseLeave);
    this.container.remove();
  }
});

export function pilLanguage() {
  return [
    pilLanguageData,
    pilIndentService,
    pilFoldService,
    semanticTokensField,
    colorPickerPlugin,
    keymap.of([autoClose]) // Bundle language-specific keys here
  ];
}
