export default function CompileButton(props) {
  return (
    <button
      onClick={props.onClick}
      class={`
        absolute bottom-6 right-6 z-50 w-10 h-10 text-white rounded-full
        shadow-lg shadow-black/40 flex items-center justify-center
        transition-colors duration-300 hover:scale-105 active:scale-95
        cursor-pointer
        ${props.hasErrors ? "bg-red-600 hover:bg-red-500" : "bg-green-600 hover:bg-green-500"}
        `}
      title={props.hasErrors ? "Errors found" : "Compile & Run"}
    >
      <div class="relative w-8 h-8 flex items-center justify-center">
        {/* Play Triangle Icon */}
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          class={`absolute w-8 h-8 ml-1 transition-all duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${
            props.hasErrors
              ? "scale-0 opacity-0 rotate-90"
              : "scale-100 opacity-100 rotate-0"
          }`}
        >
          <path
            fill-rule="evenodd"
            d="M4.5 5.653c0-1.426 1.529-2.33 2.779-1.643l11.54 6.348c1.295.712 1.295 2.573 0 3.285L7.28 19.991c-1.25.687-2.779-.217-2.779-1.643V5.653z"
            clip-rule="evenodd"
          />
        </svg>

        {/* Error Square Icon */}
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          class={`absolute w-7 h-7 transition-all duration-300 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${
            props.hasErrors
              ? "scale-120 opacity-100 rotate-0"
              : "scale-0 opacity-0 -rotate-90"
          }`}
        >
          <rect x="5" y="5" width="14" height="14" rx="3" ry="3" />
        </svg>
      </div>
    </button>
  );
}
