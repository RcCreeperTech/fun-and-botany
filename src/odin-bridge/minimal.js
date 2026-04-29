import { WasmMemoryInterface } from "./memory"
import { setupDefaultImportsMinimal } from "./imports"

export default class OdinBridgeMinimal {
  constructor() {
    this.initialized = false;
    this.wmi = null;
    this.exports = {};
    this.odin_ctx = {};
    this.sim_meta = null;
    this.sim_ptr = null;
  }

  /**
   * @param {string} path           - Path to the WASM module to run
   * @param {?int}   intSize        - Size of the integer type, `js_wasm32` = 4, `js_wasm64p32` = 8
   * @param {?int}   pointerSize    - Size of the pointer type
   */
  async initialize({ path, intSize = 4, pointerSize = 4 }) {
    this.wmi = new WasmMemoryInterface({ intSize: intSize, pointerSize: pointerSize });

    let imports = setupDefaultImportsMinimal(this.wmi);

    const wasm = await WebAssembly.instantiateStreaming(fetch(path), imports);

    // Need to late bind these because they depend on the wasm
    this.exports = wasm.instance.exports;
    this.odin_ctx = this.exports.default_context_ptr();
    this.wmi.memory = this.exports.memory;

    // Run the @init functions and main in the wasm blob
    this.exports._start();

    this.initialized = true;
  }

}
