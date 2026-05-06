import { createSignal, onMount, onCleanup, createEffect } from "solid-js";
import { useSimulationContext } from "./context/SimulationContext";
import CodeEditor from "./components/CodeEditor";
import { willow, candy, palm, steven, twister } from "./Presets";
import ShearsToggle from "./components/ShearsToggle";
import PanelToggle from "./components/PanelToggle";
import CompileButton from "./components/CompileButton";
import Toast from "./components/Toast";

export default function App() {
  let canvasRef;
  const { bridge, isReady } = useSimulationContext();
  let compilerWorker;
  const [sourceCode, setSourceCode] = createSignal(twister);
  const [tokens, setTokens] = createSignal(null);
  const [diagnostics, setDiagnostics] = createSignal([]);
  const hasErrors = () => diagnostics().length > 0;
  const [isEditorCollapsed, setIsEditorCollapsed] = createSignal(false);
  const [isIdle, setIsIdle] = createSignal(false);
  let idleTimeoutId;

  function wakeUpUI() {
    setIsIdle(false);
    clearTimeout(idleTimeoutId);

    if (isEditorCollapsed()) {
      idleTimeoutId = setTimeout(() => {
        setIsIdle(true);
      }, 2500);
    }
  }

  // Re-evaluate the timer whenever the user explicitly clicks the toggle button
  createEffect(() => {
    wakeUpUI();
  });

  onMount(() => {
    window.addEventListener("mousemove", wakeUpUI);
    window.addEventListener("keydown", wakeUpUI);
  });

  onCleanup(() => {
    window.removeEventListener("mousemove", wakeUpUI);
    window.removeEventListener("keydown", wakeUpUI);
    clearTimeout(idleTimeoutId);
  });

  onMount(() => {
    compilerWorker = new Worker(
      new URL("./workers/compiler.worker.js", import.meta.url),
      { type: "module" },
    );

    compilerWorker.onmessage = (e) => {
      const { type, payload } = e.data;
      if (type === "INIT_SUCCESS") {
        console.log("Compiler Worker initialized.");
        // Push the initial code to the worker so their buffers match from frame 0
        compilerWorker.postMessage({
          type: "SOURCE_EDIT",
          payload: [{ editStart: 0, editLen: 0, text: sourceCode() }],
        });
      } else if (type === "INIT_ERROR") {
        console.error("Worker failed to start:", payload);
      } else if (type === "TOKENS_RESULT") {
        setTokens(payload);
      } else if (type === "DIAGNOSTICS_RESULT") {
        setDiagnostics(payload);
      } else if (type === "COMPILE_SUCCESS") {
        bridge.loadProgram(payload);
      }
    };
  });

  onCleanup(() => {
    if (compilerWorker) compilerWorker.terminate();
  });

  function handleDocChange(edit) {
    if (compilerWorker) {
      compilerWorker.postMessage({
        type: "SOURCE_EDIT",
        payload: edit,
      });
    }
  }

  let toastApi;
  function handleCompileClick() {
    if (hasErrors()) {
      toastApi?.show("Compile errors must be resolved before running.");
      return;
    }

    if (compilerWorker) {
      compilerWorker.postMessage({ type: "COMPILE" });
    }
  }

  return (
    <>
      <div
        class={`
          bg-background flex flex-row w-screen h-screen relative overflow-hidden
          ${isIdle() && isEditorCollapsed() ? "cursor-none" : ""}
          `}
      >
        <ShearsToggle
          isIdle={isIdle()}
          isCollapsed={isEditorCollapsed()}
          onToggle={(nextState) => {
            bridge.togglePruning(nextState);
          }}
        />
        <PanelToggle
          isIdle={isIdle()}
          isCollapsed={isEditorCollapsed()}
          onToggle={() => setIsEditorCollapsed(!isEditorCollapsed())}
        />
        <div
          class={`
            h-full z-20 flex flex-col relative overflow-hidden
            transition-[width] duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)]
            ${isEditorCollapsed() ? "w-0 border-r-0" : "w-[40%] border-r border-gray-800"}
            `}
        >
          <Toast setRef={(api) => (toastApi = api)} />
          <div class={`w-full h-8 bg-surface-raised`}></div>
          <CodeEditor
            initialCode={sourceCode()}
            onDocChange={handleDocChange}
            tokens={tokens()}
            diagnostics={diagnostics()}
          />

          <CompileButton hasErrors={hasErrors()} onClick={handleCompileClick} />
        </div>

        <canvas
          ref={canvasRef}
          id="gl-canvas"
          class={`
            min-w-0 h-full block inset-0 z-10 transition-[width]
            duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)]
            ${isEditorCollapsed() ? "w-full" : "w-[60%]"}
            `}
          width={0}
          height={0}
        />
      </div>
    </>
  );
}
