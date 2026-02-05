import { SimulationProvider } from "./context/SimulationContext";
import { render } from "solid-js/web";
import App from "./App";

const root = document.getElementById("root");
render(
  () =>
    <SimulationProvider>
      <App />,
    </SimulationProvider>,
  root
);
