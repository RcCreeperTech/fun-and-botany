import { createSignal, onMount, onCleanup, For } from "solid-js";

export default function Selector(props) {
  const [isOpen, setIsOpen] = createSignal(false);

  const keys = () => Object.keys(props.items || {});

  let containerRef;

  onMount(() => {
    const handleOutsideClick = (e) => {
      if (containerRef && !containerRef.contains(e.target)) {
        setIsOpen(false);
      }
    };
    document.addEventListener("pointerdown", handleOutsideClick);
    onCleanup(() =>
      document.removeEventListener("pointerdown", handleOutsideClick),
    );
  });

  function handleSelect(key) {
    setIsOpen(false);
    if (props.onSelect) {
      console.log("Triggering", key);
      props.onSelect(key, props.items[key]);
    }
  }

  return (
    <div class="relative inline-block text-left w-36 p-1" ref={containerRef}>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen())}
        class={`
          flex items-center justify-between w-full px-4 py-1 text-sm
          font-medium transition-colors border rounded-md shadow-sm bg-surface
          text-text border-border hover:bg-surface-raised`}
      >
        <span class="truncate">{props.value || "Select an option..."}</span>

        <svg
          class={`w-4 h-4 ml-2 transition-transform duration-200 text-text-subtle ${
            isOpen() ? "rotate-180" : ""
          }`}
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
          aria-hidden="true"
        >
          <path
            fill-rule="evenodd"
            d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
            clip-rule="evenodd"
          />
        </svg>
      </button>

      <div
        class={`
          absolute z-50 w-full mt-2 origin-top border rounded-md shadow-lg
          bg-surface border-border transition-all duration-200 ease-out
          ${isOpen() ? "opacity-100 scale-y-100 visible" : "opacity-0 scale-y-95 invisible"}
        `}
      >
        <div
          class="py-1 overflow-auto rounded-md max-h-60"
          role="menu"
          aria-orientation="vertical"
        >
          <For each={keys()}>
            {(key) => (
              <button
                type="button"
                onClick={() => handleSelect(key)}
                class={`block w-full px-4 py-2 text-left text-sm transition-colors
                  ${
                    props.value === key
                      ? "bg-accent-subtle text-accent-fg font-medium"
                      : "text-text hover:bg-surface-raised"
                  }
                `}
                role="menuitem"
              >
                {key}
              </button>
            )}
          </For>
        </div>
      </div>
    </div>
  );
}
