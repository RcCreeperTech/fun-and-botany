import { createSignal, onMount, onCleanup, createEffect } from "solid-js";
import { useSimulationContext } from "./context/SimulationContext";
import CodeEditor from "./components/CodeEditor";
import { willow, candy, palm, steven, twister } from "./Presets"

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
  };

  // Re-evaluate the timer whenever the user explicitly clicks the toggle button
  createEffect(() => { wakeUpUI(); });

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
      new URL('./workers/compiler.worker.js', import.meta.url),
      { type: 'module' }
    );

    compilerWorker.onmessage = (e) => {
      const { type, payload } = e.data;
      if (type === 'INIT_SUCCESS') {
        console.log("Compiler Worker initialized.");
        // Push the initial code to the worker so their buffers match from frame 0
        compilerWorker.postMessage({
          type: 'SOURCE_EDIT',
          payload: [{ editStart: 0, editLen: 0, text: sourceCode() }]
        });
      } else if (type === 'INIT_ERROR') {
        console.error("Worker failed to start:", payload);
      } else if (type === 'TOKENS_RESULT') {
        setTokens(payload);
      } else if (type === 'DIAGNOSTICS_RESULT') {
        setDiagnostics(payload);
      } else if (type === 'COMPILE_SUCCESS') {
        bridge.loadProgram(payload);
      }
    };
  });

  onCleanup(() => { if (compilerWorker) compilerWorker.terminate(); });

  function handleDocChange(edit) {
    if (compilerWorker) {
      compilerWorker.postMessage({
        type: 'SOURCE_EDIT',
        payload: edit
      });
    }
  };

  let toastApi;
  function handleCompileClick() {
    if (hasErrors()) {
      toastApi?.show("Compile errors must be resolved before running.");
      return;
    }

    if (compilerWorker) {
      compilerWorker.postMessage({ type: 'COMPILE' });
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
          onToggle={(nextState) => { bridge.togglePruning(nextState); }}
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
          <Toast setRef={(api) => toastApi = api} />
          <div
            class={`w-full h-8 bg-surface-raised`}
          >
          </div>
          <CodeEditor
            initialCode={sourceCode()}
            onDocChange={handleDocChange}
            tokens={tokens()}
            diagnostics={diagnostics()}
          />

          <CompileButton
            hasErrors={hasErrors()}
            onClick={handleCompileClick}
          />
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
      </div >
    </>
  );
}

function Toast(props) {
  const [message, setMessage] = createSignal(null);
  const [show, setShow] = createSignal(false);
  let timeoutId;

  if (props.setRef) {
    props.setRef({
      show: (msg) => {
        setMessage(msg);
        setShow(true);
        if (timeoutId) clearTimeout(timeoutId);
        timeoutId = setTimeout(() => setShow(false), 2000);
      }
    });
  }

  onCleanup(() => { if (timeoutId) clearTimeout(timeoutId) })

  return (
    <div
      class={`
        absolute top-6 left-1/2 -translate-x-1/2 z-50 flex items-center
        gap-2 bg-red-900 border border-red-700 text-red-100 px-4 py-3 rounded-lg
        shadow-xl transition-all duration-400 ease-out
        ${show() ?
          "opacity-100 translate-y-0" :
          "opacity-0 -translate-y-4 pointer-events-none"
        }`}
    >
      {/* Exclamation Icon */}
      <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 shrink-0" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
      </svg>
      <span class="font-medium text-sm">{message() || ""}</span>
    </div>
  );
}

function CompileButton(props) {
  return (
    <button
      onClick={props.onClick}
      class={`
        absolute bottom-6 right-6 z-50 w-10 h-10 text-white rounded-full
        shadow-lg shadow-black/40 flex items-center justify-center
        transition-colors duration-300 hover:scale-105 active:scale-95
        cursor-pointer
        ${props.hasErrors ? "bg-red-600 hover:bg-red-500" : "bg-green-600 hover:bg-green-500"}
        `}
      title={props.hasErrors ? "Errors found" : "Compile & Run"}
    >
      <div class="relative w-8 h-8 flex items-center justify-center">
        {/* Play Triangle Icon */}
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          class={`absolute w-8 h-8 ml-1 transition-all duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${props.hasErrors ? "scale-0 opacity-0 rotate-90" : "scale-100 opacity-100 rotate-0"
            }`}
        >
          <path fill-rule="evenodd" d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.348c1.295.712 1.295 2.573 0 3.285L7.28 19.991c-1.25.687-2.779-.217-2.779-1.643V5.653z" clip-rule="evenodd" />
        </svg>

        {/* Error Square Icon */}
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          class={`absolute w-7 h-7 transition-all duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${props.hasErrors ? "scale-120 opacity-100 rotate-0" : "scale-0 opacity-0 -rotate-90"
            }`}
        >
          <rect x="5" y="5" width="14" height="14" rx="3" ry="3" />
        </svg>
      </div>
    </button>
  );
}

function PanelToggle(props) {
  return (
    <button
      onClick={props.onToggle}
      class={`
        absolute top-1 z-50 w-6 h-6 bg-gray-800 border border-gray-600
        text-gray-300 hover:text-white rounded-lg shadow-lg flex items-center
        justify-center transition-all duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)]
        cursor-pointer

        /* Position Animation: 40% (minus button width & padding) vs left edge */
        ${props.isCollapsed ? "left-1" : "left-[calc(40%-(--spacing(7)))]"}

        /* Inactivity Slide Animation (only triggers when collapsed) */
        ${!props.isCollapsed || !props.isIdle ? "translate-x-0 opacity-100" : "-translate-x-24 opacity-0"}
      `}
      title={props.isCollapsed ? "Show Editor" : "Hide Editor"}
    >
      <div class="relative w-6 h-6 flex items-center justify-center">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          class={`absolute w-5 h-5 transition-transform duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${props.isCollapsed ? "rotate-180" : "rotate-0"
            }`}
        >
          <path d="M18 17l-5-5 5-5M11 17l-5-5 5-5" />
        </svg>
      </div>
    </button>
  );
}


function ShearsToggle(props) {
  const [isPruning, setIsPruning] = createSignal(false);

  return (
    <button
      onClick={() => {
        const nextState = !isPruning();
        setIsPruning(nextState);
        props.onToggle(nextState);
      }}
      class={`
        absolute top-1 right-1 z-50 w-6 h-6 bg-gray-800 border border-gray-600
        text-gray-300 hover:text-white rounded-lg shadow-lg flex items-center
        justify-center transition-all duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)]
        cursor-pointer
        ${isPruning() ?
          "bg-red-500 text-text border-red-600" :
          "bg-gray-800 text-text border-gray-600 hover:text-text"}
        /* Inactivity Slide Animation (only triggers when collapsed) */
        ${!props.isCollapsed || !props.isIdle ? "opacity-100" : "opacity-0"}
      `}
      title={"Toggle Shears"}
    >
      <div class="relative w-4 h-4 flex items-center justify-center">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <circle cx="6" cy="6" r="3"></circle>
          <circle cx="6" cy="18" r="3"></circle>
          <line x1="20" y1="4" x2="8.12" y2="15.88"></line>
          <line x1="14.47" y1="14.48" x2="20" y2="20"></line>
          <line x1="8.12" y1="8.12" x2="12" y2="12"></line>
        </svg>
      </div>
    </button>
  );
}
