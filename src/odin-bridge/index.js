import { WasmMemoryInterface } from "./memory"
import { setupDefaultImports } from "./imports"
import { getElement } from "./dom";

/**
 * Define a `@export step :: proc(delta_time: f64) -> (keep_going: bool) {`
 * in your app and it will get called every frame.
 * return `false` to stop the execution of the module.
 */
export default class OdinBridge {
  constructor() {
    this.initialized = false;
    this.wmi = null;
    this.exports = {};
    this.odin_ctx = {};
    this.prevTimeStamp = undefined;
    this.sim_meta = null;
    this.sim_ptr = null;
  }

  /**
   * @param {string} path           - Path to the WASM module to run
   * @param {?string} canvasElement - id of the canvas element to render to
   * @param {?int}   intSize        - Size of the integer type, `js_wasm32` = 4, `js_wasm64p32` = 8
   * @param {?int}   pointerSize    - Size of the pointer type
   */
  async initialize({ path, canvasElement, intSize = 4, pointerSize = 4 }) {
    this.wmi = new WasmMemoryInterface({ intSize: intSize, pointerSize: pointerSize });
    let imports = setupDefaultImports(this.wmi, this.exports, this.odin_ctx);
    const wasm = await WebAssembly.instantiateStreaming(fetch(path), imports);
    // Need to late bind these because they depend on the wasm
    this.exports = wasm.instance.exports;
    this.odin_ctx = this.exports.default_context_ptr();
    this.wmi.memory = this.exports.memory;

    this.exports._start();

    const t = this.exports.get_sim_state_schema_json(this.odin_ctx);
    const s = this.wmi.loadFfiString(t);
    this.sim_meta = JSON.parse(s);
    this.sim_ptr = this.exports.get_sim_state_ptr(this.odin_ctx);

    // console.log(this.sim_meta);

    if (canvasElement !== undefined) {
      const canvas = getElement(canvasElement);

      this.resizeObserver = new ResizeObserver((entries) => {
        for (let entry of entries) {
          const dpr = window.devicePixelRatio || 1;
          const displayWidth = entry.contentRect.width;
          const displayHeight = entry.contentRect.height;

          const actualWidth = Math.floor(displayWidth * dpr);
          const actualHeight = Math.floor(displayHeight * dpr);

          if (canvas.width !== actualWidth || canvas.height !== actualHeight) {
            canvas.width = actualWidth;
            canvas.height = actualHeight;
            this.exports.window_resize(displayWidth, displayHeight, dpr, this.odin_ctx);
            // Resize events can interrupt the requestAnimationFrame callback
            // because css can steal priority for the browser re-paint
            this.prevTimeStamp = undefined;
          }
        }
      });
      this.resizeObserver.observe(canvas); // TODO: Cleanup
    }

    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) {
        // We just came back to the tab.
        // Reset prevTimeStamp to undefined or the current time
        // so the next step() calculates a fresh dt of 0
        this.prevTimeStamp = undefined;
      }
    });

    this.initialized = true;
  }



  get simulationParameters() {
    let result = [];
    for (const full_path of this.sim_meta.ui_params) {
      const info = this.sim_meta.schema[full_path];
      result.push({
        full_path: full_path,
        ...info
      });
    }
    return result;
  }

  /**
   * @param {string}                 full_path - The name of the ui parameter to update
   * @param {string | bool | number} value     - The new value of the field
   */
  updateParam(full_path, value) {
    if (!this.sim_meta.ui_params.includes(full_path)) {
      return new Error(`Tried to update an unknown param ${key.toString()}. fields = ${this.sim_meta.ui_params}`);
    }


    const info = this.sim_meta.schema[full_path];
    switch (info.type) {
      case "f32":
        const address = this.sim_ptr + info.offset;
        this.wmi.storeF32(address, value);
        console.log(`Wrote value (${value}) to address :${address}: writing param ${full_path}`)
        break;
      default:
        return new Error(`Unable to write to param "${full_path}" of type ${info.type}`);
    }
  }

  /**
   * @param {string} full_path - The location of the ui parameter to read
   */
  readParam(full_path) {
    if (!this.sim_meta.ui_params.includes(full_path)) {
      return new Error(`Tried to read an unknown param ${key.toString()}. fields = ${this.sim_meta.ui_params}`);
    }

    const info = this.sim_meta.schema[full_path];
    switch (info.type) {
      case "f32":
        const address = this.sim_ptr + info.offset;
        const value = this.wmi.loadF32(address);
        console.log(`Loaded value (${value}) from address :${address}: reading param ${full_path}`)
        return value;
      default:
        return new Error(`Unable to read param "${full_path}" of type ${info.type}`);
    }
  }

  run() {
    if (!this.initialized) {
      throw new Error("Tried to run unitialized wasm instance. Try running `initialize({...})` first");
    }

    if (this.exports.step) {
      // NOTE: This has to be an arrow function because otherwise it would not
      // be bound to the class instance meaning that the closure would not
      // capture `this` ... JS is a great language
      const doStep = (timestamp) => {
        this.step(timestamp);
        window.requestAnimationFrame(doStep);
      }
      window.requestAnimationFrame(doStep);
    } else {
      exports._end();
    }
  }

  step(currTimeStamp) {
    if (this.prevTimeStamp == undefined) {
      this.prevTimeStamp = currTimeStamp;
    }

    const dt = (currTimeStamp - this.prevTimeStamp) * 0.001;
    if (dt == 0) return; // No point in running before dt is stable

    if (!this.exports.step(dt, this.odin_ctx)) {
      this.exports._end();
      return;
    }

    this.prevTimeStamp = currTimeStamp;
  }

  loadProgram(bytecode) {
    const len = bytecode.length;
    const ptr = this.exports.ffi_alloc_buffer(len, this.odin_ctx);
    console.log("loadProgram", JSON.parse(bytecode), ptr, len)
    this.wmi.storeString(ptr, bytecode)

    this.exports.load_program_and_restart(ptr, len, this.odin_ctx);

    this.exports.ffi_free_buffer(ptr, this.odin_ctx);
  }

}
