import { createStore, unwrap, reconcile, produce } from "solid-js/store";
import { createSignal, For, Switch, Match } from "solid-js";
import { useDroppable, DragDropProvider } from "@dnd-kit/solid";
import { CollisionPriority } from "@dnd-kit/abstract";
import { useSortable } from "@dnd-kit/solid/sortable";

let _uid = 0;
function nextUID() {
  return ++_uid;
}

function Block(props) {
  const sortable = useSortable({
    type: "block",
    accept: ["instruction", "block"],
    collisionPriority: CollisionPriority.Low,
    get id() {
      return props.id;
    },
    get index() {
      return props.index;
    },
  });

  return (
    <div
      style={{
        display: "flex",
        "flex-direction": "column",
        padding: "0.4rem",
        "padding-bottom": "3rem",
        margin: "1rem 0.4rem",
        background: "red",
        border: "1px solid white",
        width: "fit-content",
      }}
      ref={sortable.ref}
    >
      <div
        style={{
          display: "inline-block",
          padding: "0 0.5rem",
          margin: "0.2rem 0.2rem",
          "border-bottom": "1px solid white",
        }}
        ref={sortable.handleRef}
      >
        {props.data.name} ID: {props.id}
      </div>
      <For each={props.data.children}>
        {(child, index) => (
          <Switch>
            <Match when={child.kind === "block"}>
              <Block {...child} index={index()} />
            </Match>
            <Match when={child.kind === "instruction"}>
              <DummyInstruction
                {...child}
                index={index()}
                parentId={props.id}
              />
            </Match>
          </Switch>
        )}
      </For>
    </div>
  );
}

function DummyInstruction(props) {
  const sortable = useSortable({
    type: "instruction",
    get id() {
      return props.id;
    },
    get index() {
      return props.index;
    },
    get data() {
      return { parentId: props.parentId };
    },
  });

  return (
    <div
      style={{
        padding: "0.4rem 1.4rem",
        margin: "0.2rem",
        background: "blue",
        width: "fit-content",
      }}
      ref={sortable.ref}
    >
      DummyInstruction {props.id}
    </div>
  );
}

function findNodeContext(nodes, searchId) {
  if (!nodes) return null;
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];

    if (node.id === searchId) {
      return { container: nodes, index: i, node: node };
    }

    if (node.kind === "block") {
      const found = findNodeContext(node.data.children, searchId);
      if (found) return found;
    }
  }
  return null;
}

function isDescendant(node, searchId) {
  if (node.kind !== "block") return false;
  for (const child of node.data.children) {
    if (child.id === searchId || isDescendant(child, searchId)) return true;
  }
  return false;
}

function RootDropZone() {
  const droppable = useDroppable({
    id: "root-drop-zone",
    accept: ["block"],
  });
  return (
    <div
      ref={droppable.ref}
      style={{ flex: "1", "min-height": "3rem", background: "green" }}
    />
  );
}

export default function BlockEditor(props) {
  // TreeNode {
  //     id: number,
  //     kind: "block" | "instruction",
  //     data: {
  //         block: {
  //             name: string,
  //             children: List<TreeNode>,
  //         }
  //         instruction: void,
  //     }
  // }

  function MakeInstruction() {
    return {
      id: nextUID(),
      kind: "instruction",
    };
  }

  function MakeBlock(name, children) {
    const result = {
      id: nextUID(),
      kind: "block",
      data: { name: name, children: children },
    };
    return result;
  }

  function initializeStore() {
    // prettier-ignore
    const init = {
      blocks: [
        MakeBlock("Setup", [
          MakeBlock("Init", [MakeInstruction()]),
          MakeInstruction(),
            MakeInstruction(),
            MakeInstruction(),
            MakeInstruction(),
        ]),
        MakeBlock("Tick", [MakeInstruction()]),
      ]
    };
    return init;
  }

  const [editorStore, setEditorStore] = createStore(initializeStore());
  const [parent, setParent] = createSignal(undefined);
  let editorStoreSnapshot = null;

  return (
    <DragDropProvider
      onDragStart={(e) => {
        console.log("Drag started with", e);
        editorStoreSnapshot = structuredClone(unwrap(editorStore));
      }}
      onDragEnd={(event) => {
        if (event.canceled) {
          setEditorStore(reconcile(editorStoreSnapshot));
        }
        setParent(event.operation.target?.id);
      }}
      onDragOver={(e) => {
        if (e.defaultPrevented) return;
        const { source, target, canceled } = e.operation;
        if (!source || !target || canceled) return;
        if (source.id === target.id) return;

        setEditorStore(
          produce((draft) => {
            const sourceCtx = findNodeContext(draft.blocks, source.id);
            if (!sourceCtx) return;

            if (target.id === "root-drop-zone") {
              if (isDescendant(sourceCtx.node, target.id)) return;
              const [movedItem] = sourceCtx.container.splice(
                sourceCtx.index,
                1,
              );
              draft.blocks.push(movedItem);
              return;
            }

            const targetCtx = findNodeContext(draft.blocks, target.id);
            if (!targetCtx) return;
            if (isDescendant(sourceCtx.node, target.id)) return;

            const rect = target.element.getBoundingClientRect();
            const pointerY = e.operation.position.current.y;
            const EDGE_PX = 12;

            const inTopEdge = pointerY < rect.top + EDGE_PX;
            const inBottomEdge = pointerY > rect.bottom - EDGE_PX;
            const nestInside =
              targetCtx.node.kind === "block" && !inTopEdge && !inBottomEdge;

            // Adjust for index shift when operating in the same container
            const sameContainer = sourceCtx.container === targetCtx.container;
            const adjustedTargetIndex =
              sameContainer && sourceCtx.index < targetCtx.index
                ? targetCtx.index - 1
                : targetCtx.index;

            const [movedItem] = sourceCtx.container.splice(sourceCtx.index, 1);

            const droppingIntoBlock =
              targetCtx.node.kind === "block" &&
              sourceCtx.node.kind === "instruction";

            if (droppingIntoBlock) {
              targetCtx.node.data.children.push(movedItem);
            } else {
              targetCtx.container.splice(adjustedTargetIndex, 0, movedItem);
            }
          }),
        );
      }}
    >
      <div
        style={{
          width: "100%",
          height: "100%",
          background: "#121218",
          display: "flex",
          "flex-direction": "column",
          ...props.style,
        }}
      >
        <For each={editorStore.blocks} fallback={<div>No Blocks :(</div>}>
          {(block, index) => <Block {...block} index={index()} />}
        </For>
        <RootDropZone />
      </div>
    </DragDropProvider>
  );
}
