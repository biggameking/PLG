// Glyph-grid renderer: every visual is a colored character cell, Dwarf-Fortress style.
// Glyphs are pre-baked into an atlas per (glyph, color) for fast drawImage compositing.
import { C, ColorName } from "./palette.ts";

export const CELL_W = 16;
export const CELL_H = 18;

export class Renderer {
  ctx: CanvasRenderingContext2D;
  canvas: HTMLCanvasElement;
  camX = 0; // world pixel offset of top-left of viewport
  camY = 0;
  cols = 0;
  rows = 0;
  private atlas = new Map<string, HTMLCanvasElement>();

  constructor(canvas: HTMLCanvasElement) {
    this.canvas = canvas;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("no 2d context");
    this.ctx = ctx;
    this.resize();
  }

  resize(): void {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = this.canvas.clientWidth * dpr;
    const h = this.canvas.clientHeight * dpr;
    if (this.canvas.width !== w || this.canvas.height !== h) {
      this.canvas.width = w;
      this.canvas.height = h;
    }
    this.cols = Math.ceil(w / CELL_W);
    this.rows = Math.ceil(h / CELL_H);
  }

  get w(): number {
    return this.canvas.width;
  }
  get h(): number {
    return this.canvas.height;
  }

  private tile(glyph: string, fg: string): HTMLCanvasElement {
    const key = glyph + "|" + fg;
    let t = this.atlas.get(key);
    if (!t) {
      t = document.createElement("canvas");
      t.width = CELL_W;
      t.height = CELL_H;
      const g = t.getContext("2d")!;
      g.font = `${CELL_H - 2}px ui-monospace, "Cascadia Mono", "JetBrains Mono", Consolas, monospace`;
      g.textAlign = "center";
      g.textBaseline = "middle";
      g.fillStyle = fg;
      g.fillText(glyph, CELL_W / 2, CELL_H / 2 + 1);
      this.atlas.set(key, t);
    }
    return t;
  }

  /** Draw a glyph at pixel position (screen space). */
  glyph(px: number, py: number, ch: string, fg: ColorName | string, bg?: string): void {
    const x = Math.floor(px);
    const y = Math.floor(py);
    if (bg) {
      this.ctx.fillStyle = bg;
      this.ctx.fillRect(x, y, CELL_W, CELL_H);
    }
    const f = (C as Record<string, string>)[fg as string] ?? fg;
    this.ctx.drawImage(this.tile(ch, f), x, y);
  }

  /** Draw a glyph at world-tile coords through the camera. */
  tileAt(tx: number, ty: number, ch: string, fg: ColorName | string, bg?: string): void {
    this.glyph(tx * CELL_W - this.camX, ty * CELL_H - this.camY, ch, fg, bg);
  }

  /** Draw text in screen cell coords. */
  text(cx: number, cy: number, s: string, fg: ColorName | string, bg?: string): void {
    for (let i = 0; i < s.length; i++) {
      this.glyph(cx * CELL_W + i * CELL_W, cy * CELL_H, s[i], fg, bg);
    }
  }

  /** Draw text at pixel position. */
  textPx(x: number, y: number, s: string, fg: ColorName | string, bg?: string): void {
    for (let i = 0; i < s.length; i++) {
      this.glyph(x + i * CELL_W, y, s[i], fg, bg);
    }
  }

  rect(cx: number, cy: number, w: number, h: number, color: string): void {
    this.ctx.fillStyle = color;
    this.ctx.fillRect(cx * CELL_W, cy * CELL_H, w * CELL_W, h * CELL_H);
  }

  rectPx(x: number, y: number, w: number, h: number, color: string): void {
    this.ctx.fillStyle = color;
    this.ctx.fillRect(x, y, w, h);
  }

  /** Box-drawing panel border (single-line CP437). */
  panel(cx: number, cy: number, w: number, h: number, title = ""): void {
    this.rect(cx, cy, w, h, C.bgPanel);
    const top = "┌" + "─".repeat(w - 2) + "┐";
    const bot = "└" + "─".repeat(w - 2) + "┘";
    this.text(cx, cy, top, C.border);
    this.text(cx, cy + h - 1, bot, C.border);
    for (let y = cy + 1; y < cy + h - 1; y++) {
      this.glyph(cx * CELL_W, y * CELL_H, "│", C.border);
      this.glyph((cx + w - 1) * CELL_W, y * CELL_H, "│", C.border);
    }
    if (title) {
      this.text(cx + 2, cy, ` ${title} `, C.cyan);
    }
  }

  /** Horizontal progress bar made of █ / ░ cells. */
  bar(cx: number, cy: number, w: number, frac: number, fg: ColorName, back = C.fgDark): void {
    const filled = Math.round(Math.max(0, Math.min(1, frac)) * w);
    for (let i = 0; i < w; i++) {
      this.glyph((cx + i) * CELL_W, cy * CELL_H, i < filled ? "█" : "░", i < filled ? fg : back);
    }
  }

  /** World-space pixel overlay fill (lighting, flashes). */
  fill(color: string): void {
    this.ctx.fillStyle = color;
    this.ctx.fillRect(0, 0, this.w, this.h);
  }

  /** Radial light overlay: darken everything, punch light circles. */
  nightOverlay(alpha: number, lights: { x: number; y: number; r: number }[]): void {
    if (alpha <= 0.01) return;
    const ctx = this.ctx;
    ctx.save();
    ctx.fillStyle = `rgba(6,8,16,${alpha})`;
    ctx.fillRect(0, 0, this.w, this.h);
    ctx.globalCompositeOperation = "destination-out";
    for (const l of lights) {
      const g = ctx.createRadialGradient(l.x, l.y, 0, l.x, l.y, l.r);
      g.addColorStop(0, `rgba(0,0,0,${Math.min(1, alpha * 1.6)})`);
      g.addColorStop(1, "rgba(0,0,0,0)");
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(l.x, l.y, l.r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
  }

  clear(): void {
    this.ctx.fillStyle = C.bg;
    this.ctx.fillRect(0, 0, this.w, this.h);
  }
}
