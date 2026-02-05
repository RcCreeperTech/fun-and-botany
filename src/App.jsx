import { useSimulationContext } from "./context/SimulationContext";
import HoverPane from "./HoverPane"
import { Show } from "solid-js";
import { SimTweaker } from "./SimTweaker";

export default function App() {
  let canvasRef;
  const { bridge, isReady } = useSimulationContext();

  return (
    <div style={{ width: "100vw", height: "100vh", background: "#222" }}>
      {/* UI Overlay */}
      <div style={{ position: "fixed", color: "white", padding: "1rem" }}>
        <h1>Plant Engine</h1>
        <p>Status: {isReady() ? "Running 🟢" : "Loading 🟡"}</p>
      </div>

      <HoverPane title="Simulation Settings">
        <Show when={isReady()} fallback={<p>Loading simulation metadata...</p>}>
          <For each={bridge.simulationParameters}>
            {(params) => <SimTweaker {...params} />}
          </For>
        </Show>
      </HoverPane>

      {/* The Game Canvas */}
      <canvas
        ref={canvasRef}
        id="gl-canvas"
        style={{ display: "block", width: "100%", height: "100%", inset: 0, "z-index": 1 }}
        width={0}
        height={0}
      />
    </div>
  );
}
