import BlockEditor from "./BlockEditor";
import { useSimulationContext } from "./context/SimulationContext";

export default function App() {
  let canvasRef;
  const { bridge, isReady } = useSimulationContext();

  return (
    <>
      <div class="bg-background flex flex-row w-screen h-screen" >
        <BlockEditor />
        {/* The Game Canvas */}
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
