import { EditorView } from "@codemirror/view";

export const appTheme = EditorView.theme({
  "&": {
    color: "var(--color-text)",
    backgroundColor: "var(--color-base)",
    height: "100%",
  },
  ".cm-content": {
    caretColor: "var(--color-accent)",
  },
  "&.cm-focused .cm-cursor": {
    borderLeftColor: "var(--color-accent)",
  },
  "&.cm-focused .cm-selectionBackground, ::selection": {
    backgroundColor: "var(--color-accent-subtle)",
  },
  ".cm-panels": {
    backgroundColor: "var(--color-surface)",
    color: "var(--color-text)",
  },
  ".cm-panels.cm-panels-top": {
    borderBottom: "2px solid var(--color-border)",
  },
  ".cm-panels.cm-panels-bottom": {
    borderTop: "2px solid var(--color-border)",
  },
  ".cm-searchMatch": {
    backgroundColor: "var(--color-warning-subtle)",
    outline: "1px solid var(--color-warning)",
  },
  ".cm-searchMatch.cm-searchMatch-selected": {
    backgroundColor: "var(--color-accent-subtle)",
  },
  ".cm-activeLine": {
    backgroundColor: "var(--color-surface)",
  },
  ".cm-selectionMatch": {
    backgroundColor: "var(--color-surface-raised)",
  },
  "&.cm-focused .cm-matchingBracket, &.cm-focused .cm-nonmatchingBracket": {
    backgroundColor: "var(--color-surface-raised)",
    outline: "1px solid var(--color-border-subtle)",
  },
  ".cm-gutters": {
    backgroundColor: "var(--color-surface)",
    color: "var(--color-text-subtle)",
    borderRight: "1px solid var(--color-border-subtle)",
  },
  ".cm-activeLineGutter": {
    backgroundColor: "var(--color-surface-raised)",
    color: "var(--color-text)",
  },
  ".cm-lineNumbers .cm-gutterElement": {
    padding: "0 16px 0 8px",
  },
  ".cm-sem-variable": { color: "var(--color-text)" },
  ".cm-sem-function": { color: "var(--color-accent-fg)" },
  ".cm-sem-constant": { color: "var(--color-warning-fg)" },
  ".cm-sem-property": { color: "var(--color-accent-hover)" },
  ".cm-sem-builtin": { color: "var(--color-danger-fg)" },
  ".cm-sem-keyword": { color: "var(--color-purple-500)", fontWeight: "bold" },
  ".cm-sem-number": { color: "var(--color-success-fg)" },
  ".cm-sem-string": { color: "var(--color-success-fg)" },
  ".cm-sem-color": { color: "var(--color-success-fg)", textDecoration: "underline" },
  ".cm-sem-boolean": { color: "var(--color-danger)" },
  ".cm-sem-operator": { color: "var(--color-text-subtle)" },
  ".cm-sem-punctuation": { color: "var(--color-text-subtle)" },
  ".cm-sem-comment": { color: "var(--color-warning)" },
  ".cm-sem-none": { color: "var(--color-text)" },
});
