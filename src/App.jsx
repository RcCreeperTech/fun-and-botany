import { createSignal, onMount, onCleanup } from "solid-js";
import { useSimulationContext } from "./context/SimulationContext";
import CodeEditor from "./components/CodeEditor";

export default function App() {
  let canvasRef;
  const { bridge, isReady } = useSimulationContext();
  let compilerWorker;
  const [sourceCode, setSourceCode] = createSignal("// Write your procedural rules here\n");
  const [tokens, setTokens] = createSignal(null);
  const [diagnostics, setDiagnostics] = createSignal([]);

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
        setTokens(payload)
      } else if (type === 'DIAGNOSTICS_RESULT') {
        setDiagnostics(payload)
      }
    };
  });

  onCleanup(() => { if (compilerWorker) compilerWorker.terminate(); });

  const handleDocChange = (edit) => {
    if (compilerWorker) {
      compilerWorker.postMessage({
        type: 'SOURCE_EDIT',
        payload: edit
      });
    }
  };

  return (
    <>
      <div class="bg-background flex flex-row w-screen h-screen" >

        <div class="flex-2 w-full h-full z-20 flex flex-col">
          <CodeEditor
            initialCode={sourceCode()}
            onDocChange={handleDocChange}
            tokens={tokens()}
            diagnostics={diagnostics()}
          />
        </div>

        <canvas
          ref={canvasRef}
          id="gl-canvas"
          class="flex-3 w-full h-full block inset-0 z-10"
          width={0}
          height={0}
        />
      </div>
    </>
  );
}
