// Keyboard + mouse state, frame-polled.
export class Input {
  keys = new Set<string>();
  pressed = new Set<string>(); // cleared each frame; true only on the frame a key went down
  mouse = { x: 0, y: 0, down: false, clicked: false, wheel: 0 };
  private canvas: HTMLCanvasElement;

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    window.addEventListener("keydown", (e) => {
      const k = this.norm(e.key);
      if (!this.keys.has(k)) this.pressed.add(k);
      this.keys.add(k);
      if (["arrowup", "arrowdown", "arrowleft", "arrowright", " ", "tab"].includes(k)) e.preventDefault();
    });
    window.addEventListener("keyup", (e) => this.keys.delete(this.norm(e.key)));
    canvas.addEventListener("mousemove", (e) => {
      const r = canvas.getBoundingClientRect();
      this.mouse.x = e.clientX - r.left;
      this.mouse.y = e.clientY - r.top;
    });
    canvas.addEventListener("mousedown", (e) => {
      if (e.button === 0) {
        this.mouse.down = true;
        this.mouse.clicked = true;
      }
    });
    window.addEventListener("mouseup", () => (this.mouse.down = false));
    canvas.addEventListener("wheel", (e) => {
      this.mouse.wheel += Math.sign(e.deltaY);
      e.preventDefault();
    }, { passive: false });
    canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  }

  private norm(k: string): string {
    return k.toLowerCase();
  }

  down(k: string): boolean {
    return this.keys.has(k);
  }
  hit(k: string): boolean {
    return this.pressed.has(k);
  }
  endFrame(): void {
    this.pressed.clear();
    this.mouse.clicked = false;
    this.mouse.wheel = 0;
  }
}
