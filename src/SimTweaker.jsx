import { createEffect, createSignal, For } from "solid-js";
import { Dynamic } from "solid-js/web";
import { useSimulationContext } from "./context/SimulationContext";

// --- Sub-Components ---
function SelectInput(props) {
  const { bridge } = props;
  return (
    <select
      value={props.value}
      onInput={props.onInput}
      style={{ width: "100%", padding: "4px" }}
    >
      <For each={props.options}>
        {(opt) => <option value={opt}>{opt}</option>}
      </For>
    </select>
  );
}


const ColorInput = (props) => (
  <div style={{ display: "flex", gap: "5px", width: "100%" }}>
    <input
      type="color"
      value={props.value}
      onInput={props.onInput}
      style={{ width: "40px", height: "30px", border: "none", padding: 0 }}
    />
    <input
      type="text"
      value={props.value}
      onInput={props.onInput}
      style={{ flex: 1, "font-family": "monospace" }}
    />
  </div>
);

// Fallback for standard numbers or strings
function NumberInput(props) {
  const [value, setValue] = createSignal();
  const { bridge, isReady } = useSimulationContext();
  createEffect(() => {
    if (isReady()) {
      setValue(bridge.readParam(props.full_path));
    }
  });
  return (
    <input
      type="number"
      value={value()}
      onInput={(e) => {
        setValue(e.target.value)
        bridge.updateParam(props.full_path, value());
      }}
    />
  );
}

function RangeInput(props) {
  const [value, setValue] = createSignal();
  const { bridge, isReady } = useSimulationContext();
  createEffect(() => {
    if (isReady()) {
      setValue(bridge.readParam(props.full_path));
    }
  });
  return (
    <div style={{ display: "flex", "align-items": "center", width: "100%" }}>
      <input
        type="range"
        min={props.min}
        max={props.max}
        step={props.step || (props.max - props.min) / 100}
        value={value()}
        style={{ flex: 1 }}
        onInput={(e) => {
          setValue(e.target.value)
          bridge.updateParam(props.full_path, value());
        }}
      />
      <div style={{ "min-width": "3rem", "text-align": "right", "font-variant-numeric": "tabular-nums" }}>
        {Number(value()).toFixed(2)}
      </div>
    </div>
  );
}

function getInputComponent(props) {
  switch (props.type) {
    case "f32":
      if (props.min !== undefined && props.max !== undefined) {
        return RangeInput;
      }
      return NumberInput;
    default: return (<p>TODO: Implement the {props.type} component</p>);
  }
}

export function SimTweaker(props) {

  return (
    <div style={{
      display: "flex",
      "align-items": "center",
      margin: "5px 0",
      "font-family": "sans-serif",
      "font-size": "14px"
    }}>
      <div style={{ display: "inline-block", padding: "0 0.5rem" }}>{props.name}</div>
      <div style={{ flex: 1 }}>
        <Dynamic component={getInputComponent(props)} {...props} />
      </div>
    </div>
  );
}
