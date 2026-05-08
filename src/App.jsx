import {
  createSignal,
  onMount,
  onCleanup,
  createEffect,
  untrack,
} from "solid-js";
import { useSimulationContext } from "./context/SimulationContext";
import CodeEditor from "./components/CodeEditor";
import { presets } from "./Presets";
import ShearsToggle from "./components/ShearsToggle";
import PanelToggle from "./components/PanelToggle";
import CompileButton from "./components/CompileButton";
import Toast from "./components/Toast";
import Selector from "./components/Selector";

const initialExample = "twister";

export default function App() {
  let canvasRef;
  const { bridge, isReady } = useSimulationContext();
  let compilerWorker;
  const [sourceCode, setSourceCode] = createSignal(presets[initialExample]);
  const [tokens, setTokens] = createSignal(null);
  const [diagnostics, setDiagnostics] = createSignal([]);
  const hasErrors = () => diagnostics().length > 0;
  const [isEditorCollapsed, setIsEditorCollapsed] = createSignal(false);
  const [isIdle, setIsIdle] = createSignal(false);
  let idleTimeoutId;

  const presetKeys = Object.keys(presets);
  const [activePresetKey, setActivePresetKey] = createSignal(initialExample);
  const [isDemoMode, setIsDemoMode] = createSignal(false);

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

  createEffect(() => {
    if (!isDemoMode()) return;

    const advanceDemo = () => {
      untrack(() => {
        const currentIndex = presetKeys.indexOf(activePresetKey());
        const nextIndex = (currentIndex + 1) % presetKeys.length;
        const nextKey = presetKeys[nextIndex];

        setActivePresetKey(nextKey);
        setSourceCode(presets[nextKey]);
      });
    };

    advanceDemo();
    const interval = setInterval(() => advanceDemo(), 1000 * 45); // Every 45 seconds

    onCleanup(() => clearInterval(interval));
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

  function handleDocChange(edit, isUserEdit) {
    if (isUserEdit) {
      setIsDemoMode(false);
      setActivePresetKey(null);
    }
    if (compilerWorker) {
      compilerWorker.postMessage({
        type: "SOURCE_EDIT",
        payload: edit,
      });

      if (isDemoMode() && !isUserEdit) {
        compilerWorker.postMessage({ type: "COMPILE" });
      }
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
          <div class={`w-full bg-surface-raised`}>
            <Selector
              value={activePresetKey()}
              onSelect={(key, payload) => {
                setIsIdle(false);
                setActivePresetKey(key);
                setSourceCode(payload);
              }}
              items={presets}
            />
            <button
              onClick={() => setIsDemoMode(!isDemoMode())}
              class={`px-3 py-1.5 text-xs font-bold uppercase tracking-wider rounded-md transition-colors ${
                isDemoMode()
                  ? "bg-warning text-on-accent animate-pulse"
                  : "bg-surface text-text border border-border hover:bg-surface-raised"
              }`}
            >
              {isDemoMode() ? "Demo Active" : "Start Demo"}
            </button>
          </div>
          <CodeEditor
            value={sourceCode()}
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
