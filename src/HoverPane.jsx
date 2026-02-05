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

  function container_styles() {
    return {
      position: "fixed",
      transform: `translate3d(${position().x}px, ${position().y}px, 0)`,
      background: "var(--color_background--surface)",
      overflow: "hidden",
      "min-width": "10rem",
      "border-radius": "0.1rem",
      "box-shadow": "0 4px 6px rgba(0,0,0,0.5)",
      "will-change": "transform", // Browser hint that this element is dynamic
    }
  };
  const handle_styles = {
    cursor: "move",
    display: "block",
    background: "var(--color_background--chip)",
    "min-height": "1.2rem",
    width: "100%",
  };
  const content_styles = {
    padding: "0 0.9rem",
    width: "100%",
  };


  return (
    <div style={container_styles()} >
      <div style={handle_styles} onMouseDown={handleMouseDown}>
      </div>
      <div style={content_styles}>
        <Show when={props.title}>
          <h3 style={{ "user-select": "none" }}>{props.title}</h3>
        </Show>
        {props.children}
      </div>
    </div >
  );
}
