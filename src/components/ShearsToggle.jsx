import { createSignal } from "solid-js";

export default function ShearsToggle(props) {
  const [isPruning, setIsPruning] = createSignal(false);

  return (
    <button
      onClick={() => {
        const nextState = !isPruning();
        setIsPruning(nextState);
        props.onToggle(nextState);
      }}
      class={`
        absolute top-1 right-1 z-50 w-6 h-6 bg-gray-800 border border-gray-600
        text-gray-300 hover:text-white rounded-lg shadow-lg flex items-center
        justify-center transition-all duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)]
        cursor-pointer
        ${
          isPruning()
            ? "bg-red-500 text-text border-red-600"
            : "bg-gray-800 text-text border-gray-600 hover:text-text"
        }
        /* Inactivity Slide Animation (only triggers when collapsed) */
        ${!props.isCollapsed || !props.isIdle ? "opacity-100" : "opacity-0"}
      `}
      title={"Toggle Shears"}
    >
      <div class="relative w-4 h-4 flex items-center justify-center">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <circle cx="6" cy="6" r="3"></circle>
          <circle cx="6" cy="18" r="3"></circle>
          <line x1="20" y1="4" x2="8.12" y2="15.88"></line>
          <line x1="14.47" y1="14.48" x2="20" y2="20"></line>
          <line x1="8.12" y1="8.12" x2="12" y2="12"></line>
        </svg>
      </div>
    </button>
  );
}
