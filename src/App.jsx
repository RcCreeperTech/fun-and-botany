import BlockEditor from "./BlockEditor";
import { useSimulationContext } from "./context/SimulationContext";

export default function App() {
  let canvasRef;
  const { bridge, isReady } = useSimulationContext();

  return (
    <>
      <div
        style={{
          width: "100vw",
          height: "100vh",
          background: "#222",
          display: "flex",
        }}
      >
        <BlockEditor style={{ flex: 2 }} />
        {/* The Game Canvas */}
        <canvas
          ref={canvasRef}
          id="gl-canvas"
          style={{
            flex: 3,
            display: "block",
            width: "100%",
            height: "100%",
            inset: 0,
            "z-index": 1,
          }}
          width={0}
          height={0}
        />
      </div>
    </>
  );
}
