import { createEffect, createSignal, For } from "solid-js";
import { Dynamic } from "solid-js/web";
import { useSimulationContext } from "./context/SimulationContext";

// --- Sub-Components ---
function SelectInput(props) {
  const { bridge } = props;
  return (
    <select value={props.value} onInput={props.onInput} class="w-full p-1" >
      <For each={props.options}>
        {(opt) => <option value={opt}>{opt}</option>}
      </For>
    </select>
  );
}


const ColorInput = (props) => (
  <div class="flex gap-1 w-full">
    <input
      type="color"
      value={props.value}
      onInput={props.onInput}
      class="w-10 h-8 border-none p-0"
    />
    <input
      type="text"
      value={props.value}
      onInput={props.onInput}
      class="flex-1 font-mono"
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
    <div class="flex items-center w-full">
      <input
        type="range"
        min={props.min}
        max={props.max}
        step={props.step || (props.max - props.min) / 100}
        value={value()}
        class="flex-1"
        onInput={(e) => {
          setValue(e.target.value)
          bridge.updateParam(props.full_path, value());
        }}
      />
      <div class="min-w-12 text-right tabular-nums">
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
    <div class="flex items-center mx-1 font-sans text-sm" >
      <div class="inline-block py-2">{props.name}</div>
      <div class="flex 1">
        <Dynamic component={getInputComponent(props)} {...props} />
      </div>
    </div>
  );
}
