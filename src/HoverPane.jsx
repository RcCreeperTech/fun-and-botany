import { createSignal, onCleanup, Show } from "solid-js"

export default function (props) {
  const [position, setPosition] = createSignal({ x: 0, y: 0 });

  let startX = 0;
  let startY = 0;
  let initialPos = { x: 0, y: 0 };
  function handleMouseDown(e) {
    // prevent text selection while dragging
    e.preventDefault();
    startX = e.x;
    startY = e.y;
    initialPos = position();
    // Attach listeners to DOCUMENT so you don't lose drag if mouse moves fast
    document.addEventListener("mousemove", handleMouseMove);
    document.addEventListener("mouseup", handleMouseUp);
  };

  function handleMouseMove(e) {
    // Calculate how far the mouse moved
    const dx = e.x - startX;
    const dy = e.y - startY;
    setPosition({
      x: initialPos.x + dx,
      y: initialPos.y + dy,
    });
  };

  function handleMouseUp() {
    // Clean up listeners when drag ends
    document.removeEventListener("mousemove", handleMouseMove);
    document.removeEventListener("mouseup", handleMouseUp);
  };

  // Clean up listeners if component unmounts while dragging
  onCleanup(() => {
    document.removeEventListener("mousemove", handleMouseMove);
    document.removeEventListener("mouseup", handleMouseUp);
  });

  return (
    <div
      class="fixed bg-background overflow-hidden min-w-40 rounded-xs shadow-md will-change-transform"
      style={{ transform: `translate3d(${position().x}px, ${position().y}px, 0)` }}
    >
      <div class="cursor-move block bg-chip min-h-5 w-full" onMouseDown={handleMouseDown}>
      </div>
      <div class="pb-4 w-full" >
        <Show when={props.title}>
          <h3 class="select-none">{props.title}</h3>
        </Show>
        {props.children}
      </div>
    </div >
  );
}
