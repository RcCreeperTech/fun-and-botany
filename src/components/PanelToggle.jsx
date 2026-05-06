export default function PanelToggle(props) {
  return (
    <button
      onClick={props.onToggle}
      class={`
        absolute top-1 z-50 w-6 h-6 bg-gray-800 border border-gray-600
        text-gray-300 hover:text-white rounded-lg shadow-lg flex items-center
        justify-center transition-all duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)]
        cursor-pointer

        /* Position Animation: 40% (minus button width & padding) vs left edge */
        ${props.isCollapsed ? "left-1" : "left-[calc(40%-(--spacing(7)))]"}

        /* Inactivity Slide Animation (only triggers when collapsed) */
        ${!props.isCollapsed || !props.isIdle ? "translate-x-0 opacity-100" : "-translate-x-24 opacity-0"}
      `}
      title={props.isCollapsed ? "Show Editor" : "Hide Editor"}
    >
      <div class="relative w-6 h-6 flex items-center justify-center">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
          class={`absolute w-5 h-5 transition-transform duration-500 ease-[cubic-bezier(0.34,1.56,0.64,1)] ${
            props.isCollapsed ? "rotate-180" : "rotate-0"
          }`}
        >
          <path d="M18 17l-5-5 5-5M11 17l-5-5 5-5" />
        </svg>
      </div>
    </button>
  );
}
