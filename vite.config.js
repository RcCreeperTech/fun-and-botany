// TODO: Remove this once bun dev server works again
import { defineConfig } from "vite";
import solidPlugin from "vite-plugin-solid";

export default defineConfig({
  plugins: [solidPlugin()],
  server: {
    port: 3000,
  },
  build: {
    target: "esnext", // Needed for Top-level await / Wasm
  },
});
