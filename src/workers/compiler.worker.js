import OdinBridgeMinimal from "../odin-bridge/minimal.js";

let bridge = new OdinBridgeMinimal();

async function initCompiler() {
  try {
    await bridge.initialize({ path: '/compiler_web_worker.wasm', intSize: 4, pointerSize: 4 })
    postMessage({ type: 'INIT_SUCCESS' });
  } catch (error) {
    console.error("Worker Wasm Init Error:", error);
    postMessage({ type: 'INIT_ERROR', payload: error.message });
  }
}

function sourceEdit(editStart, editLen, text) {
  let textPtr = 0;
  let textLen = 0;
  if (text.length != 0) { // Allocate a string
    let encoder = new TextEncoder();
    let textBytes = encoder.encode(text);
    textLen = textBytes.length;
    textPtr = bridge.exports.ffi_alloc_buffer(textLen, bridge.odin_ctx);
    let dst = new Uint8Array(bridge.wmi.memory.buffer, textPtr, textLen);
    dst.set(textBytes);
  }

  bridge.exports.apply_edit(
    editStart,
    editLen,
    textPtr,
    textLen,
    bridge.odin_ctx
  );

  if (textPtr != 0) bridge.exports.ffi_free_buffer(textPtr, bridge.odin_ctx);
}

function getTokens() {
  const sliceStructPtr = bridge.exports.get_semantic_tokens(bridge.odin_ctx);

  const dataPtr = bridge.wmi.loadPtr(sliceStructPtr);
  const arrayLen = bridge.wmi.loadInt(sliceStructPtr + bridge.wmi.pointerSize);

  // Each Semantic_Token has four 32-bit fields
  const token_u32_size = 3;
  const tokenData = new Uint32Array(
    bridge.wmi.memory.buffer,
    dataPtr,
    arrayLen * token_u32_size,
  );
  let outTokens = []
  for (let i = 0; i < tokenData.length; i += 3) {
    outTokens.push({
      offset: tokenData[i],
      length: tokenData[i + 1],
      info: tokenData[i + 2]
    })
  }

  return outTokens
}

self.onmessage = async (e) => {
  const { type, payload } = e.data;
  if (!bridge.initialized) return;

  switch (type) {
    case 'SOURCE_EDIT':
      const { editStart, editLen, text } = payload;
      sourceEdit(editStart, editLen, text)
      const tokenData = getTokens();
      if (tokenData.length > 0) {
        // Send the flat array back to the main thread
        // We slice it to copy the data out of the Wasm memory buffer before the
        // FFI arena gets cleared on the next call.
        postMessage({
          type: 'TOKENS_RESULT',
          payload: tokenData.slice()
        });
      }
      break;
    case 'GET_TOKENS':
      break;
    case 'COMPILE':

      // Future Phase 3 logic:
      // 1. Allocate memory for payload.sourceCode via Wasm export
      // 2. wmi.storeString(ptr, payload.sourceCode)
      // 3. wasmInstance.exports.compile_source(ptr, len, odinCtx)
      // 4. Read results back using wmi

      console.log("Worker received source code snippet.");
      break;
  }
};

initCompiler();
