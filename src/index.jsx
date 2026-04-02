import { SimulationProvider } from "./context/SimulationContext";
import { render } from "solid-js/web";
import { applyTheme } from './theme'
import App from "./App";

// Runs before render to avoid flash of wrong theme
applyTheme()

// Listen for OS changes when the user has 'system' selected
window
  .matchMedia('(prefers-color-scheme: dark)')
  .addEventListener('change', applyTheme)

const root = document.getElementById("root");
render(
  () => (
    <>
      <SimulationProvider>
        <App />
      </SimulationProvider>
    </>
  ),

  root
);
