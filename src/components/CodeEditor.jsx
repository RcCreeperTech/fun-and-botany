import { onMount, onCleanup, createEffect } from "solid-js";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers } from "@codemirror/view";
import { defaultKeymap, indentWithTab, history, historyKeymap, redo } from "@codemirror/commands";
import { closeBrackets } from "@codemirror/autocomplete"
import { indentUnit, foldGutter } from "@codemirror/language"
import { lintGutter, setDiagnostics } from "@codemirror/lint";
import { appTheme } from "./editorTheme";
import { pilLanguage, updateSemanticTokens } from "./pilLanguage";

export default function CodeEditor(props) {
  let containerRef;
  let view;

  onMount(() => {
    const extensions = [
      appTheme,
      history(),
      lineNumbers(),
      lintGutter(),
      foldGutter(),
      closeBrackets(),
      indentUnit.of("    "),
      pilLanguage(),
      keymap.of([
        ...historyKeymap,
        ...defaultKeymap,
        indentWithTab,
        { key: "Mod-Shift-z", run: redo },
      ]),
      // Listen for document changes and bubble them up to the main thread state
      EditorView.updateListener.of((update) => {
        if (update.docChanged && props.onDocChange) {
          const edits = [];

          update.changes.iterChanges((fromA, toA, fromB, toB, inserted) => {
            edits.push({
              editStart: fromA,
              editLen: toA - fromA,
              text: inserted.toString()
            });
          });

          // Reverse the array so bottom-most edits process first
          edits.reverse();

          props.onDocChange(edits);
        }
      }),
    ];

    const state = EditorState.create({
      doc: props.initialCode || "// Write your plant growth procedural rules here\n",
      extensions,
    });

    view = new EditorView({
      state,
      parent: containerRef,
    });
  });

  createEffect(() => {
    if (view && props.tokens) {
      view.dispatch({
        effects: updateSemanticTokens.of(props.tokens)
      });
    }
  })

  createEffect(() => {
    if (view && props.diagnostics) {
      // Map to CM6 specific format
      const cmDiagnostics = props.diagnostics.map(err => ({
        from: err.offset,
        to: err.offset + err.length,
        severity: err.severity, // "error", "warning", or "info"
        message: err.message,
      }));

      view.dispatch(setDiagnostics(view.state, cmDiagnostics));
    }
  });

  onCleanup(() => {
    if (view) view.destroy();
  });

  return (
    <div
      ref={containerRef}
      class="flex-1 w-full h-full overflow-y-auto border-r border-gray-800 text-sm font-mono"
    ></div>
  );
}
