import { createSignal } from "solid-js";
import BlockEditor from "./BlockEditor";
import { useSimulationContext } from "./context/SimulationContext";
import CodeEditor from "./components/CodeEditor";

export default function App() {
  let canvasRef;
  const { bridge, isReady } = useSimulationContext();

  const [sourceCode, setSourceCode] = createSignal("");

  const handleDocChange = (newCode) => {
    setSourceCode(newCode);
    // Future: Debounce this and trigger postMessage to the compiler Web Worker
  };

  return (
    <>
      <div class="bg-background flex flex-row w-screen h-screen" >

        <div class="flex-2 w-full h-full z-20 flex flex-col">
          <CodeEditor
            initialCode={sourceCode()}
            onDocChange={handleDocChange}
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
