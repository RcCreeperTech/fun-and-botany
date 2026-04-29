import { EditorSelection } from "@codemirror/state";

// Get the leading whitespace of a string
export const getIndent = (text) => text.match(/^\s*/)[0];

// Dispatch the CodeMirror transaction
export const applyCompletion = (view, from, to, insertText, cursorOffset) => {
  view.dispatch({
    changes: { from, to, insert: insertText },
    selection: EditorSelection.cursor(from + cursorOffset),
    scrollIntoView: true
  });
};

// Downward Scanner to check for existing 'end' keywords
export const needsClosingEnd = (state, startLine, baseIndentStr) => {
  const maxScan = Math.min(state.doc.lines, startLine + 100);

  for (let i = startLine + 1; i <= maxScan; i++) {
    const line = state.doc.line(i);
    const trimmed = line.text.trim();
    if (trimmed === "") continue;

    // It already has a matching end
    if (line.text.startsWith(baseIndentStr + "end")) return false;

    // It bled into an outer scope without closing
    const nextIndentLen = getIndent(line.text).length;
    if (nextIndentLen <= baseIndentStr.length && !trimmed.match(/^(else|end)\b/)) {
      return true;
    }
  }
  return true;
};

// Upward Scanner to find the enclosing 'if' and its exact indentation
export const findEnclosingIfIndent = (state, startLine) => {
  let depth = 0;

  for (let i = startLine - 1; i >= 1; i--) {
    const line = state.doc.line(i);
    const trimmed = line.text.trim();
    if (trimmed === "") continue;

    // We hit a closed inner block, increase depth to ignore its opener
    if (trimmed.match(/^end\b/)) {
      depth++;
    }
    // We hit a structural opener
    else if (trimmed.match(/^(def|if)\b.*:\s*$/)) {
      if (depth === 0) {
        // We found the unclosed block that encloses us!
        if (trimmed.match(/^if\b/)) {
          return getIndent(line.text);
        } else {
          return null; // Enclosed by a 'def', so 'else' is invalid here
        }
      }
      depth--; // Match the opener to a previously seen 'end'
    }
  }
  return null;
};
