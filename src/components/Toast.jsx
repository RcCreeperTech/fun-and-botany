import { createSignal, onCleanup } from "solid-js";

export default function Toast(props) {
  const [message, setMessage] = createSignal(null);
  const [show, setShow] = createSignal(false);
  let timeoutId;

  if (props.setRef) {
    props.setRef({
      show: (msg) => {
        setMessage(msg);
        setShow(true);
        if (timeoutId) clearTimeout(timeoutId);
        timeoutId = setTimeout(() => setShow(false), 2000);
      },
    });
  }

  onCleanup(() => {
    if (timeoutId) clearTimeout(timeoutId);
  });

  return (
    <div
      class={`
        absolute top-6 left-1/2 -translate-x-1/2 z-50 flex items-center
        gap-2 bg-red-900 border border-red-700 text-red-100 px-4 py-3 rounded-lg
        shadow-xl transition-all duration-400 ease-out
        ${
          show()
            ? "opacity-100 translate-y-0"
            : "opacity-0 -translate-y-4 pointer-events-none"
        }`}
    >
      {/* Exclamation Icon */}
      <svg
        xmlns="http://www.w3.org/2000/svg"
        class="h-5 w-5 shrink-0"
        viewBox="0 0 20 20"
        fill="currentColor"
      >
        <path
          fill-rule="evenodd"
          d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z"
          clip-rule="evenodd"
        />
      </svg>
      <span class="font-medium text-sm">{message() || ""}</span>
    </div>
  );
}
