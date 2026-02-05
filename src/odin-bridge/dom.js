export function getElement(name) {
  if (name) {
    return document.getElementById(name);
  }
  return undefined;
}

export class DomInterface {
  /**
   * @param {WasmMemoryInterface} wmi - Used to interface with the wasm modules memory
   * @param {any} exports - exported symbols from the wasm module
   * @param {int} odin_ctx - pointer to the default context for odin
   */
  constructor(wmi, exports, odin_ctx) {
    this.wmi = wmi;
    this.exports = exports;
    this.odin_ctx = odin_ctx;
    this.event_temp = {};
    this.listenerMap = new Map();
  }

  onEventReceived(event_data, data, callback) {
    this.event_temp.data = event_data;

    this.exports.odin_dom_do_event_callback(data, callback, this.odin_ctx);

    this.event_temp.data = null;
  };

  listener_key(id, name, data, callback, useCapture) {
    return `${id}-${name}-data:${data}-callback:${callback}-useCapture:${useCapture}`;
  };

  getInterface() {
    return {
      init_event_raw: (ep) => {
        const W = this.wmi.intSize;
        let offset = ep;
        let off = (amount, alignment) => {
          if (alignment === undefined) {
            alignment = Math.min(amount, W);
          }
          if (offset % alignment != 0) {
            offset += alignment - (offset % alignment);
          }
          let x = offset;
          offset += amount;
          return x;
        };

        let align = (alignment) => {
          const modulo = offset & (alignment - 1);
          if (modulo != 0) {
            offset += alignment - modulo
          }
        };

        if (!this.event_temp.data) {
          return;
        }

        let e = this.event_temp.data.event;

        this.wmi.storeU32(off(4), this.event_temp.data.name_code);
        if (e.target == document) {
          this.wmi.storeU32(off(4), 1);
        } else if (e.target == window) {
          this.wmi.storeU32(off(4), 2);
        } else {
          this.wmi.storeU32(off(4), 0);
        }
        if (e.currentTarget == document) {
          this.wmi.storeU32(off(4), 1);
        } else if (e.currentTarget == window) {
          this.wmi.storeU32(off(4), 2);
        } else {
          this.wmi.storeU32(off(4), 0);
        }

        align(W);

        this.wmi.storeI32(off(W), this.event_temp.data.id_ptr);
        this.wmi.storeUint(off(W), this.event_temp.data.id_len);

        align(8);
        this.wmi.storeF64(off(8), e.timeStamp * 1e-3);

        this.wmi.storeU8(off(1), e.eventPhase);
        let options = 0;
        if (!!e.bubbles) { options |= 1 << 0; }
        if (!!e.cancelable) { options |= 1 << 1; }
        if (!!e.composed) { options |= 1 << 2; }
        this.wmi.storeU8(off(1), options);
        this.wmi.storeU8(off(1), !!e.isComposing);
        this.wmi.storeU8(off(1), !!e.isTrusted);

        align(8);
        if (e instanceof WheelEvent) {
          this.wmi.storeF64(off(8), e.deltaX);
          this.wmi.storeF64(off(8), e.deltaY);
          this.wmi.storeF64(off(8), e.deltaZ);
          this.wmi.storeU32(off(4), e.deltaMode);
        } else if (e instanceof MouseEvent) {
          this.wmi.storeI64(off(8), e.screenX);
          this.wmi.storeI64(off(8), e.screenY);
          this.wmi.storeI64(off(8), e.clientX);
          this.wmi.storeI64(off(8), e.clientY);
          this.wmi.storeI64(off(8), e.offsetX);
          this.wmi.storeI64(off(8), e.offsetY);
          this.wmi.storeI64(off(8), e.pageX);
          this.wmi.storeI64(off(8), e.pageY);
          this.wmi.storeI64(off(8), e.movementX);
          this.wmi.storeI64(off(8), e.movementY);

          this.wmi.storeU8(off(1), !!e.ctrlKey);
          this.wmi.storeU8(off(1), !!e.shiftKey);
          this.wmi.storeU8(off(1), !!e.altKey);
          this.wmi.storeU8(off(1), !!e.metaKey);

          this.wmi.storeI16(off(2), e.button);
          this.wmi.storeU16(off(2), e.buttons);

          if (e instanceof PointerEvent) {
            this.wmi.storeF64(off(8), e.altitudeAngle);
            this.wmi.storeF64(off(8), e.azimuthAngle);
            this.wmi.storeInt(off(W), e.persistentDeviceId);
            this.wmi.storeInt(off(W), e.pointerId);
            this.wmi.storeInt(off(W), e.width);
            this.wmi.storeInt(off(W), e.height);
            this.wmi.storeF64(off(8), e.pressure);
            this.wmi.storeF64(off(8), e.tangentialPressure);
            this.wmi.storeF64(off(8), e.tiltX);
            this.wmi.storeF64(off(8), e.tiltY);
            this.wmi.storeF64(off(8), e.twist);
            if (e.pointerType == "pen") {
              this.wmi.storeU8(off(1), 1);
            } else if (e.pointerType == "touch") {
              this.wmi.storeU8(off(1), 2);
            } else {
              this.wmi.storeU8(off(1), 0);
            }
            this.wmi.storeU8(off(1), !!e.isPrimary);
          }

        } else if (e instanceof KeyboardEvent) {
          // Note: those strings are constructed
          // on the native side from buffers that
          // are filled later, so skip them
          const keyPtr = off(W * 2, W);
          const codePtr = off(W * 2, W);

          this.wmi.storeU8(off(1), e.location);

          this.wmi.storeU8(off(1), !!e.ctrlKey);
          this.wmi.storeU8(off(1), !!e.shiftKey);
          this.wmi.storeU8(off(1), !!e.altKey);
          this.wmi.storeU8(off(1), !!e.metaKey);

          this.wmi.storeU8(off(1), !!e.repeat);

          this.wmi.storeI32(off(4), e.charCode);

          this.wmi.storeInt(off(W, W), e.key.length)
          this.wmi.storeInt(off(W, W), e.code.length)
          this.wmi.storeString(off(32, 1), e.key);
          this.wmi.storeString(off(32, 1), e.code);
        } else if (e.type === 'scroll') {
          this.wmi.storeF64(off(8, 8), window.scrollX);
          this.wmi.storeF64(off(8, 8), window.scrollY);
        } else if (e.type === 'visibilitychange') {
          this.wmi.storeU8(off(1), !document.hidden);
        } else if (e instanceof GamepadEvent) {
          const idPtr = off(W * 2, W);
          const mappingPtr = off(W * 2, W);

          this.wmi.storeI32(off(W, W), e.gamepad.index);
          this.wmi.storeU8(off(1), !!e.gamepad.connected);
          this.wmi.storeF64(off(8, 8), e.gamepad.timestamp);

          this.wmi.storeInt(off(W, W), e.gamepad.buttons.length);
          this.wmi.storeInt(off(W, W), e.gamepad.axes.length);

          for (let i = 0; i < 64; i++) {
            if (i < e.gamepad.buttons.length) {
              let b = e.gamepad.buttons[i];
              this.wmi.storeF64(off(8, 8), b.value);
              this.wmi.storeU8(off(1), !!b.pressed);
              this.wmi.storeU8(off(1), !!b.touched);
            } else {
              off(16, 8);
            }
          }
          for (let i = 0; i < 16; i++) {
            if (i < e.gamepad.axes.length) {
              let a = e.gamepad.axes[i];
              this.wmi.storeF64(off(8, 8), a);
            } else {
              off(8, 8);
            }
          }

          let idLength = e.gamepad.id.length;
          let id = e.gamepad.id;
          if (idLength > 96) {
            idLength = 96;
            id = id.slice(0, 93) + '...';
          }

          let mappingLength = e.gamepad.mapping.length;
          let mapping = e.gamepad.mapping;
          if (mappingLength > 64) {
            mappingLength = 61;
            mapping = mapping.slice(0, 61) + '...';
          }

          this.wmi.storeInt(off(W, W), idLength);
          this.wmi.storeInt(off(W, W), mappingLength);
          this.wmi.storeString(off(96, 1), id);
          this.wmi.storeString(off(64, 1), mapping);
        }
      },

      add_event_listener: (id_ptr, id_len, name_ptr, name_len, name_code, data, callback, use_capture) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let name = this.wmi.loadString(name_ptr, name_len);
        let element = getElement(id);
        if (element == undefined) {
          return false;
        }
        let key = listener_key(id, name, data, callback, !!use_capture);
        if (this.listenerMap.has(key)) {
          return false;
        }

        let listener = (e) => {
          let event_data = {};
          event_data.id_ptr = id_ptr;
          event_data.id_len = id_len;
          event_data.event = e;
          event_data.name_code = name_code;

          onEventReceived(event_data, data, callback);
        };
        this.listenerMap.set(key, listener);
        element.addEventListener(name, listener, !!use_capture);
        return true;
      },

      add_window_event_listener: (name_ptr, name_len, name_code, data, callback, use_capture) => {
        let name = this.wmi.loadString(name_ptr, name_len);
        let element = window;
        let key = listener_key('window', name, data, callback, !!use_capture);
        if (this.listenerMap.has(key)) {
          return false;
        }

        let listener = (e) => {
          let event_data = {};
          event_data.id_ptr = 0;
          event_data.id_len = 0;
          event_data.event = e;
          event_data.name_code = name_code;

          onEventReceived(event_data, data, callback);
        };
        this.listenerMap.set(key, listener);
        element.addEventListener(name, listener, !!use_capture);
        return true;
      },

      add_document_event_listener: (name_ptr, name_len, name_code, data, callback, use_capture) => {
        let name = this.wmi.loadString(name_ptr, name_len);
        let element = document;
        let key = listener_key('document', name, data, callback, !!use_capture);
        if (this.listenerMap.has(key)) {
          return false;
        }

        let listener = (e) => {
          let event_data = {};
          event_data.id_ptr = 0;
          event_data.id_len = 0;
          event_data.event = e;
          event_data.name_code = name_code;

          onEventReceived(event_data, data, callback);
        };
        this.listenerMap.set(key, listener);
        element.addEventListener(name, listener, !!use_capture);
        return true;
      },

      remove_event_listener: (id_ptr, id_len, name_ptr, name_len, data, callback, use_capture) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let name = this.wmi.loadString(name_ptr, name_len);
        let element = getElement(id);
        if (element == undefined) {
          return false;
        }

        let key = listener_key(id, name, data, callback, !!use_capture);
        let listener = this.listenerMap.get(key);
        if (listener === undefined) {
          return false;
        }
        this.listenerMap.delete(key);

        element.removeEventListener(name, listener, !!use_capture);
        return true;
      },
      remove_window_event_listener: (name_ptr, name_len, data, callback, use_capture) => {
        let name = this.wmi.loadString(name_ptr, name_len);
        let element = window;

        let key = listener_key('window', name, data, callback, !!use_capture);
        let listener = this.listenerMap.get(key);
        if (listener === undefined) {
          return false;
        }
        this.listenerMap.delete(key);

        element.removeEventListener(name, listener, !!use_capture);
        return true;
      },
      remove_document_event_listener: (name_ptr, name_len, data, callback, use_capture) => {
        let name = this.wmi.loadString(name_ptr, name_len);
        let element = document;

        let key = listener_key('document', name, data, callback, !!use_capture);
        let listener = this.listenerMap.get(key);
        if (listener === undefined) {
          return false;
        }
        this.listenerMap.delete(key);

        element.removeEventListener(name, listener, !!use_capture);
        return true;
      },

      event_stop_propagation: () => {
        if (this.event_temp.data && this.event_temp.data.event) {
          this.event_temp.data.event.stopPropagation();
        }
      },
      event_stop_immediate_propagation: () => {
        if (this.event_temp.data && this.event_temp.data.event) {
          this.event_temp.data.event.stopImmediatePropagation();
        }
      },
      event_prevent_default: () => {
        if (this.event_temp.data && this.event_temp.data.event) {
          this.event_temp.data.event.preventDefault();
        }
      },

      dispatch_custom_event: (id_ptr, id_len, name_ptr, name_len, options_bits) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let name = this.wmi.loadString(name_ptr, name_len);
        let options = {
          bubbles: (options_bits & (1 << 0)) !== 0,
          cancelable: (options_bits & (1 << 1)) !== 0,
          composed: (options_bits & (1 << 2)) !== 0,
        };

        let element = getElement(id);
        if (element) {
          element.dispatchEvent(new Event(name, options));
          return true;
        }
        return false;
      },

      get_gamepad_state: (gamepad_id, ep) => {
        let index = gamepad_id;
        let gps = navigator.getGamepads();
        if (0 <= index && index < gps.length) {
          let gamepad = gps[index];
          if (!gamepad) {
            return false;
          }

          const W = this.wmi.intSize;
          let offset = ep;
          let off = (amount, alignment) => {
            if (alignment === undefined) {
              alignment = Math.min(amount, W);
            }
            if (offset % alignment != 0) {
              offset += alignment - (offset % alignment);
            }
            let x = offset;
            offset += amount;
            return x;
          };

          let align = (alignment) => {
            const modulo = offset & (alignment - 1);
            if (modulo != 0) {
              offset += alignment - modulo
            }
          };


          const idPtr = off(W * 2, W);
          const mappingPtr = off(W * 2, W);

          this.wmi.storeI32(off(W), gamepad.index);
          this.wmi.storeU8(off(1), !!gamepad.connected);
          this.wmi.storeF64(off(8), gamepad.timestamp);

          this.wmi.storeInt(off(W), gamepad.buttons.length);
          this.wmi.storeInt(off(W), gamepad.axes.length);

          for (let i = 0; i < 64; i++) {
            if (i < gamepad.buttons.length) {
              let b = gamepad.buttons[i];
              this.wmi.storeF64(off(8, 8), b.value);
              this.wmi.storeU8(off(1), !!b.pressed);
              this.wmi.storeU8(off(1), !!b.touched);
            } else {
              off(16, 8);
            }
          }
          for (let i = 0; i < 16; i++) {
            if (i < gamepad.axes.length) {
              this.wmi.storeF64(off(8, 8), gamepad.axes[i]);
            } else {
              off(8, 8);
            }
          }

          let idLength = gamepad.id.length;
          let id = gamepad.id;
          if (idLength > 96) {
            idLength = 96;
            id = id.slice(0, 93) + '...';
          }

          let mappingLength = gamepad.mapping.length;
          let mapping = gamepad.mapping;
          if (mappingLength > 64) {
            mappingLength = 61;
            mapping = mapping.slice(0, 61) + '...';
          }

          this.wmi.storeInt(off(W, W), idLength);
          this.wmi.storeInt(off(W, W), mappingLength);
          this.wmi.storeString(off(96, 1), id);
          this.wmi.storeString(off(64, 1), mapping);

          return true;
        }
        return false;
      },

      get_element_value_f64: (id_ptr, id_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let element = getElement(id);
        return element ? element.value : 0;
      },
      get_element_value_string: (id_ptr, id_len, buf_ptr, buf_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let element = getElement(id);
        if (element) {
          let str = element.value;
          if (buf_len > 0 && buf_ptr) {
            let n = Math.min(buf_len, str.length);
            str = str.substring(0, n);
            this.mem.loadBytes(buf_ptr, buf_len).set(new TextEncoder().encode(str))
            return n;
          }
        }
        return 0;
      },
      get_element_value_string_length: (id_ptr, id_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let element = getElement(id);
        if (element) {
          return element.value.length;
        }
        return 0;
      },
      get_element_min_max: (ptr_array2_f64, id_ptr, id_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let element = getElement(id);
        if (element) {
          let values = this.wmi.loadF64Array(ptr_array2_f64, 2);
          values[0] = element.min;
          values[1] = element.max;
        }
      },
      set_element_value_f64: (id_ptr, id_len, value) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let element = getElement(id);
        if (element) {
          element.value = value;
        }
      },
      set_element_value_string: (id_ptr, id_len, value_ptr, value_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let value = this.wmi.loadString(value_ptr, value_len);
        let element = getElement(id);
        if (element) {
          element.value = value;
        }
      },

      set_element_style: (id_ptr, id_len, key_ptr, key_len, value_ptr, value_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let key = this.wmi.loadString(key_ptr, key_len);
        let value = this.wmi.loadString(value_ptr, value_len);
        let element = getElement(id);
        if (element) {
          element.style[key] = value;
        }
      },

      get_element_key_f64: (id_ptr, id_len, key_ptr, key_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let key = this.wmi.loadString(key_ptr, key_len);
        let element = getElement(id);
        return element ? element[key] : 0;
      },
      get_element_key_string: (id_ptr, id_len, key_ptr, key_len, buf_ptr, buf_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let key = this.wmi.loadString(key_ptr, key_len);
        let element = getElement(id);
        if (element) {
          let str = element[key];
          if (buf_len > 0 && buf_ptr) {
            let n = Math.min(buf_len, str.length);
            str = str.substring(0, n);
            this.mem.loadBytes(buf_ptr, buf_len).set(new TextEncoder().encode(str))
            return n;
          }
        }
        return 0;
      },
      get_element_key_string_length: (id_ptr, id_len, key_ptr, key_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let key = this.wmi.loadString(key_ptr, key_len);
        let element = getElement(id);
        if (element && element[key]) {
          return element[key].length;
        }
        return 0;
      },

      set_element_key_f64: (id_ptr, id_len, key_ptr, key_len, value) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let key = this.wmi.loadString(key_ptr, key_len);
        let element = getElement(id);
        if (element) {
          element[key] = value;
        }
      },
      set_element_key_string: (id_ptr, id_len, key_ptr, key_len, value_ptr, value_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let key = this.wmi.loadString(key_ptr, key_len);
        let value = this.wmi.loadString(value_ptr, value_len);
        let element = getElement(id);
        if (element) {
          element[key] = value;
        }
      },


      get_bounding_client_rect: (rect_ptr, id_ptr, id_len) => {
        let id = this.wmi.loadString(id_ptr, id_len);
        let element = getElement(id);
        if (element) {
          let values = this.wmi.loadF64Array(rect_ptr, 4);
          let rect = element.getBoundingClientRect();
          values[0] = rect.left;
          values[1] = rect.top;
          values[2] = rect.right - rect.left;
          values[3] = rect.bottom - rect.top;
        }
      },
      window_get_rect: (rect_ptr) => {
        let values = this.wmi.loadF64Array(rect_ptr, 4);
        values[0] = window.screenX;
        values[1] = window.screenY;
        values[2] = window.screen.width;
        values[3] = window.screen.height;
      },

      window_get_scroll: (pos_ptr) => {
        let values = this.wmi.loadF64Array(pos_ptr, 2);
        values[0] = window.scrollX;
        values[1] = window.scrollY;
      },
      window_set_scroll: (x, y) => {
        window.scroll(x, y);
      },

      device_pixel_ratio: () => {
        return window.devicePixelRatio || 1;
      },

    };
  }
}
