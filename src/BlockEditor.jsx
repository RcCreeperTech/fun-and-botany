import { createStore, unwrap, reconcile, produce } from "solid-js/store";
import { createSignal, For, Switch, Match, Show } from "solid-js";
import { useDroppable, DragDropProvider } from "@dnd-kit/solid";
import { CollisionPriority } from "@dnd-kit/abstract";
import { useSortable } from "@dnd-kit/solid/sortable";

const DEBUG_MODE = false;

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

  const topEdge = useDroppable({ id: `top:${props.id}` });
  const bottomEdge = useDroppable({ id: `bottom:${props.id}` });

  return (
    <div class="flex flex-col w-fit my-1 rounded-sm" ref={sortable.ref} >
      <div
        class="bg-chip text-on-accent px-2 py-1 text-lg rounded-t-sm"
        ref={(r) => {
          sortable.handleRef(r); topEdge.ref(r)
        }}
      >
        {props.data.name} <span class="text-xs">ID: {props.id}</span>
      </div>
      <div class="flex flex-col bg-surface p-2 min-h-12 border border-border border-solid" >
        <For each={props.data.children}>
          {(child, index) => (
            <Switch>
              <Match when={child.kind === "block"}>
                <Block {...child} index={index()} />
              </Match>
              <Match when={child.kind === "instruction"}>
                <Instruction
                  {...child}
                  index={index()}
                  parentId={props.id}
                />
              </Match>
            </Switch>
          )}
        </For>
      </div>

      <div class="bg-chip inline-block min-h-4 rounded-b-sm" ref={bottomEdge.ref} />
    </div >
  );
}

function InstructionValueSlot(props) {
  const { ref } = useDroppable({ id: `slot:${props.id}`, accept: "label" });

  return (
    <div class="min-w-12 min-h-4 ml-4 px-3 py-0.5 bg-surface border border-solid border-surface-raised rounded-sm inline">
    </div>
  );
}

function Instruction(props) {
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

  const color = () => {
    switch (props.data.kind) {
      case "dummy": return "orange";
      case "const": return "amber";
      case "push": return "lime";
      case "pop": return "cyan";
      case "mul": return "emerald";
      case "div": return "teal";
      case "add": return "sky";
      case "sub": return "rose";
      case "rand": return "indigo";
      case "jump": return "violet";
      case "spawn": return "purple";
      case "get": return "green";
      case "set": return "red";
      default: return "pink";
    }
  }

  return (
    <div
      class={
        `text-on-accent
         text-center text-sm capitalize
         py-1.5 px-2 m-1
         min-w-16 w-fit
         rounded-sm
         bg-${color()}-500`}
      ref={sortable.ref}
    >
      {props.data.kind}
      <Show when={DEBUG_MODE}>
        <span class="text-xs m-1">ID: {props.id}</span>
      </Show>
      <Show when={props.data.kind === "push"}>
        <InstructionValueSlot id={props.id} />
      </Show>
    </div>
  );
}

function lookupId(nodes, searchId) {
  if (!nodes) return null;
  for (let i = 0; i < nodes.length; i++) {
    const node = nodes[i];

    if (node.id === searchId) {
      return { container: nodes, index: i, node: node };
    }

    if (node.kind === "block") {
      const found = lookupId(node.data.children, searchId);
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

function parseId(id) {
  if (typeof id === "string") {
    if (id.startsWith("top:"))
      return { intent: "before", id: Number(id.slice(4)) };
    if (id.startsWith("bottom:"))
      return { intent: "after", id: Number(id.slice(7)) };
  }

  return { intent: "onto", id: id };
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
  //         instruction: {
  //             kind: "dummy"  |
  //                    "const" |
  //                    "push"  |
  //                    "pop"   |
  //                    "mul"   |
  //                    "div"   |
  //                    "add"   |
  //                    "sub"   |
  //                    "rand"  |
  //                    "jump"  |
  //                    "spawn" |
  //                    "get"   |
  //                    "set",
  //             payload: {
  //                 dummy: void,
  //                 pop: void,
  //                 mul: void,
  //                 div: void,
  //                 add: void,
  //                 sub: void,
  //                 rand: void,
  //                 push: <???>,
  //             },
  //         },
  //     }
  // }

  function MakeSimple(name) {
    return {
      id: nextUID(),
      kind: "instruction",
      data: {
        kind: name,
      }
    };
  }

  function MakeDummy() { return MakeSimple("dummy"); }

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
          MakeBlock("Init", [MakeDummy()]),
          MakeSimple("push"),
          MakeSimple("pop"),
          MakeSimple("mul"),
          MakeSimple("div"),
          MakeSimple("add"),
          MakeSimple("sub"),
          MakeSimple("rand"),
        ]),
        MakeBlock("Tick", [MakeDummy()]),
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
            const src = lookupId(draft.blocks, source.id);
            console.assert(src != null)

            const { intent, id: resolvedId } = parseId(target.id);
            const tgt = lookupId(draft.blocks, resolvedId);
            if (tgt == null) return;

            // Only blocks are allowed at root level
            if (tgt.container === draft.blocks && src.node.kind == "instruction") return;

            if (isDescendant(src.node, resolvedId)) return;

            // Remove the node from it's original position
            const [movedItem] = src.container.splice(src.index, 1);


            if (tgt.node.kind === "block") {
              switch (intent) {
                case "before":
                  tgt.container.splice(tgt.index, 0, movedItem);
                  break;
                case "after":
                  tgt.container.splice(tgt.index + 1, 0, movedItem);
                  break;
                case "onto":
                  tgt.node.data.children.push(movedItem);
                  break;
              }
            } else {
              tgt.container.splice(tgt.index, 0, movedItem);
            }
          }),
        );
      }}
    >
      <div class="flex-2 flex flex-col w-full h-full bg-background p-2 overflow-x-hidden overflow-y-scroll" >
        <For each={editorStore.blocks} fallback={<div>No Blocks :(</div>}>
          {(block, index) => <Block {...block} index={index()} />}
        </For>
      </div>
    </DragDropProvider>
  );
}
