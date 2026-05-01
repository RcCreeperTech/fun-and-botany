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

function getDiagnostics() {
  const sliceStructPtr = bridge.exports.get_diagnostics(bridge.odin_ctx);

  const dataPtr = bridge.wmi.loadPtr(sliceStructPtr);
  const arrayLen = bridge.wmi.loadInt(sliceStructPtr + bridge.wmi.pointerSize);

  const diag_u32_size = 4;
  const diagData = bridge.wmi.loadU32Array(
    dataPtr,
    arrayLen * diag_u32_size
  );

  let outDiagnostics = [];
  for (let i = 0; i < diagData.length; i += diag_u32_size) {
    const offset = diagData[i];
    const length = diagData[i + 1];
    const msgPtr = diagData[i + 2];
    const msgLen = diagData[i + 3];

    // Decode the string bytes directly from Wasm memory
    const message = bridge.wmi.loadString(msgPtr, msgLen);

    outDiagnostics.push({
      offset: offset,
      length: length,
      message: message,
      severity: "error",
    });
  }

  return outDiagnostics;
}

self.onmessage = async (e) => {
  const { type, payload } = e.data;
  if (!bridge.initialized) return;

  switch (type) {
    case 'SOURCE_EDIT': {
      const edits = payload;
      // Apply all edits in the reversed order
      for (const edit of edits) {
        sourceEdit(edit.editStart, edit.editLen, edit.text);
      }

      const tokenData = getTokens();
      if (tokenData.length > 0) {
        postMessage({
          type: 'TOKENS_RESULT',
          payload: tokenData.slice()
        });
      }

      const diagnosticData = getDiagnostics();
      postMessage({
        type: 'DIAGNOSTICS_RESULT',
        payload: diagnosticData.slice()
      });
    }
      break;
    case 'COMPILE': {
      if (!bridge.exports.can_compile_program(bridge.odin_ctx)) {
        postMessage({ type: 'COMPILE_ERROR', payload: "Compilation failed." });
        return;
      }

      const bytecodeSlicePtr = bridge.exports.get_compiled_bytecode(bridge.odin_ctx);
      const bytecode = bridge.wmi.loadFfiString(bytecodeSlicePtr);
      const parsedProgram = JSON.parse(bytecode);
      console.log("Compiled Program AST:", parsedProgram);
    }
      break;
  }
};

initCompiler();
