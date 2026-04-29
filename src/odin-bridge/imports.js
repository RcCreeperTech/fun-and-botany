import { writeToConsole } from "./logging"
import { WebGLInterface } from "./webgl";
import { DomInterface } from "./dom";

/**
* @param {WasmMemoryInterface} wmi - Used to interface with the wasm modules memory
*/
export function setupDefaultImportsMinimal(wmi) {
  return {
    env: { memory: wmi.memory },
    odin_env: {
      write: (fd, ptr, len) => {
        if (len == 0) return;
        const str = wmi.loadString(ptr, len);
        if (fd == 1) {
          writeToConsole(str, false);
          return;
        } else if (fd == 2) {
          writeToConsole(str, true);
          return;
        } else {
          throw new Error("Invalid fd to 'write'" + str.replace(/\n/, ' '));
        }
      },
      trap: () => { throw new Error() },
      abort: () => { Module.abort() },

      sqrt: Math.sqrt,
      sin: Math.sin,
      cos: Math.cos,
      pow: Math.pow,
      fmuladd: (x, y, z) => x * y + z,
      ln: Math.log,
      exp: Math.exp,
      ldexp: (x, exp) => x * Math.pow(2, exp),

      tick_now: () => performance.now(),
      time_now: () => BigInt(Date.now()),
      tick_now: () => performance.now(),

      rand_bytes: (ptr, len) => {
        const view = new Uint8Array(wmi.memory.buffer, Number(ptr), Number(len))
        crypto.getRandomValues(view)
      },
    },
  }
}

/**
* @param {WasmMemoryInterface} wmi - Used to interface with the wasm modules memory
* @param {any} exports - exported symbols from the wasm module
* @param {int} odin_ctx - pointer to the default context for odin
 */
export function setupDefaultImports(wmi, exports, odin_ctx) {

  let minimal = setupDefaultImportsMinimal(wmi);
  let webglContext = new WebGLInterface(wmi);
  let domInterface = new DomInterface(wmi, exports, odin_ctx);

  return {
    ...minimal,
    "odin_dom": domInterface.getInterface(),
    "webgl": webglContext.getWebGL1Interface(),
    "webgl2": webglContext.getWebGL2Interface(),
  };
};
