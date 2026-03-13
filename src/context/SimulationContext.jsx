import { createContext, useContext, createSignal, onMount } from "solid-js"
import OdinBridge from "../odin-bridge";

const SimulationContext = createContext();

export function SimulationProvider(props) {
  const bridge = new OdinBridge();
  const [isReady, setReady] = createSignal(false);

  onMount(async () => {
    try {
      console.log("🚀 Starting Engine...");
      await bridge.initialize({ path: "/engine.wasm", canvasElement: "gl-canvas", intSize: 4 });
      bridge.run();
    } catch (err) {
      console.error("Failed to load WASM:", err);
    }
    setReady(true);
  });

  return (
    <SimulationContext.Provider value={{ bridge, isReady }}>
      {props.children}
    </SimulationContext.Provider>
  );
}

export function useSimulationContext() {
  const ctx = useContext(SimulationContext);
  if (!ctx) throw new Error("useSimulation must be used within Provider");
  return ctx;
}
