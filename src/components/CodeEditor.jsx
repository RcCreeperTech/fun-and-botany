import { onMount, onCleanup, createEffect } from "solid-js";
import { EditorState } from "@codemirror/state";
import { EditorView, keymap, lineNumbers } from "@codemirror/view";
import { defaultKeymap } from "@codemirror/commands";
import { appTheme } from "./editorTheme";
import { semanticTokensField, updateSemanticTokens } from "./semanticTokens";

export default function CodeEditor(props) {
  let containerRef;
  let view;

  onMount(() => {
    // Phase 1: Core extension composition
    // Placeholder for Phase 2 & 3: We will inject the custom syntax highlighting
    // and Web Worker linter extensions into this array later.
    const extensions = [
      appTheme,
      lineNumbers(),
      semanticTokensField,
      keymap.of(defaultKeymap),
      // Listen for document changes and bubble them up to the main thread state
      EditorView.updateListener.of((update) => {
        if (update.docChanged && props.onDocChange) {
          // Iterate over every individual edit in this transaction
          update.changes.iterChanges((fromA, toA, fromB, toB, inserted) => {
            props.onDocChange({
              editStart: fromA,
              editLen: toA - fromA, // How many characters were replaced/deleted
              text: inserted.toString() // The new text being inserted
            });
          });

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
