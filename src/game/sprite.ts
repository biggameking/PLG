// Pal sprites: pixel-art bitmaps — each logical pixel is one glyph cell
// worth of color (the user's "every character is a pixel" idea). Sprites
// are generated procedurally: a 24x20 pixel buffer per body plan, filled
// with ellipse/disc/rect ops, auto-outlined (dark edge like DF premium
// tilesets), tinted by a 3-tone palette, prerendered to a canvas per
// species+walk-frame, then blitted ~2x2 tiles on screen.
import { Pal } from "./types.ts";
import { Species } from "../data/species.ts";
import { ELEMENT_GLYPH, ELEMENT_COLOR } from "../data/elements.ts";
import { Renderer, CELL_W, CELL_H, MICRO_W, MICRO_H } from "../engine/renderer.ts";
import { hash2 } from "../engine/rng.ts";

const W = 24, H = 20;
const SCALE = 1.0; // sprite pixels are micro cells; 24x20 chars = 96x100px

// pixel indices: 1 primary, 2 secondary, 3 accent, 4 dark, 5 white
type Pix = Uint8Array; // W*H

function newPix(): Pix { return new Uint8Array(W * H); }
function set(b: Pix, x: number, y: number, c: number): void {
  if (x >= 0 && x < W && y >= 0 && y < H) b[y * W + x] = c;
}
function rect(b: Pix, x0: number, y0: number, x1: number, y1: number, c: number): void {
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) set(b, x, y, c);
}
function ellipse(b: Pix, cx: number, cy: number, rx: number, ry: number, c: number): void {
  for (let y = Math.floor(cy - ry); y <= cy + ry; y++)
    for (let x = Math.floor(cx - rx); x <= cx + rx; x++) {
      const dx = (x - cx) / rx, dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1) set(b, x, y, c);
    }
}
function disc(b: Pix, cx: number, cy: number, r: number, c: number): void { ellipse(b, cx, cy, r, r, c); }
// scatter spikes along top edge of body
function spikes(b: Pix, x0: number, x1: number, y: number, c: number): void {
  for (let x = x0; x <= x1; x++) { set(b, x, y - ((x - x0) % 2), c); set(b, x, y - 1 - ((x - x0) % 2), c); }
}

// ---- body plans: each draws into a 24x20 buffer; f = walk frame 0/1 ----
// legs get +1/-1 px per frame; heads face right (dir>0), flipped on draw.
const PLANS: Record<string, (b: Pix, f: number) => void> = {
  quadruped(b, f) {
    const s = f ? 1 : 0;
    rect(b, 5, 15 + s, 7, 18 + s, 1); rect(b, 9, 15 + (1 - s), 11, 18 + (1 - s), 1);
    rect(b, 14, 15 + (1 - s), 16, 18 + (1 - s), 1); rect(b, 18, 15 + s, 20, 18 + s, 1);
    ellipse(b, 11, 12, 7, 5, 1);                    // body
    disc(b, 17, 8, 4, 1);                           // head
    rect(b, 16, 4, 17, 6, 3); rect(b, 20, 4, 21, 6, 3); // ears
    rect(b, 3, 9, 4, 11, 3);                        // tail
    ellipse(b, 11, 14, 5, 3, 2);                    // belly
    set(b, 18, 7, 4); set(b, 19, 7, 5);             // eye + glint
    set(b, 21, 10, 4);                              // nose
  },
  kitty(b, f) {
    const s = f ? 1 : 0;
    rect(b, 7, 15 + s, 8, 18 + s, 1); rect(b, 15, 15 + (1 - s), 16, 18 + (1 - s), 1);
    ellipse(b, 11, 12, 6, 4, 1);
    disc(b, 17, 8, 4, 1);
    set(b, 15, 4, 3); set(b, 16, 5, 3);             // ear L
    set(b, 20, 4, 3); set(b, 19, 5, 3);             // ear R
    rect(b, 4, 5, 5, 8, 3); set(b, 4, 4, 3);        // tail up
    ellipse(b, 11, 14, 4, 2, 2);
    set(b, 18, 7, 4); set(b, 19, 7, 5); set(b, 21, 9, 4);
  },
  bird(b, f) {
    const s = f ? 1 : 0;
    set(b, 10, 16 + s, 4); set(b, 11, 16 + s, 4); set(b, 10, 17 + s, 4); // leg L
    set(b, 14, 16 + (1 - s), 4); set(b, 15, 16 + (1 - s), 4); set(b, 15, 17 + (1 - s), 4); // leg R
    ellipse(b, 12, 11, 6, 6, 1);                    // round body
    disc(b, 13, 5, 3, 1);                           // head on top
    rect(b, 16, 4, 18, 5, 3);                       // beak
    ellipse(b, 10, 11, 3, 4, 2);                    // wing
    set(b, 12, 2, 3); set(b, 13, 1, 3);             // tuft
    ellipse(b, 12, 14, 4, 3, 2);                    // belly
    set(b, 14, 4, 4); set(b, 15, 4, 5);             // eye
    set(b, 19, 5, 3);                               // beak tip
  },
  mouse(b, f) {
    const s = f ? 1 : 0;
    rect(b, 9, 15 + s, 10, 17 + s, 1); rect(b, 14, 15 + (1 - s), 15, 17 + (1 - s), 1);
    disc(b, 12, 12, 5, 1);
    disc(b, 17, 9, 3, 1);                           // head
    disc(b, 15, 5, 2, 3); disc(b, 19, 5, 2, 3);     // big round ears
    rect(b, 5, 13, 7, 14, 3); set(b, 4, 13, 3);     // thin tail
    disc(b, 12, 14, 3, 2);
    set(b, 18, 8, 4); set(b, 19, 8, 5); set(b, 20, 10, 4);
  },
  hedgehog(b, f) {
    const s = f ? 1 : 0;
    rect(b, 7, 16 + s, 9, 18 + s, 2); rect(b, 15, 16 + (1 - s), 17, 18 + (1 - s), 2);
    ellipse(b, 12, 13, 8, 5, 1);
    spikes(b, 5, 19, 8, 3);                          // quill row
    spikes(b, 7, 17, 6, 3);
    disc(b, 19, 11, 3, 1);                           // snout head
    ellipse(b, 12, 15, 6, 2, 2);
    set(b, 20, 10, 4); set(b, 21, 10, 5); set(b, 22, 12, 4);
  },
  deer(b, f) {
    const s = f ? 1 : 0;
    rect(b, 5, 15 + s, 7, 18 + s, 1); rect(b, 9, 15 + (1 - s), 11, 18 + (1 - s), 1);
    rect(b, 14, 15 + (1 - s), 16, 18 + (1 - s), 1); rect(b, 18, 15 + s, 20, 18 + s, 1);
    ellipse(b, 11, 12, 7, 5, 1);
    disc(b, 17, 8, 3, 1);
    // antlers: two branching strokes
    rect(b, 15, 3, 15, 5, 3); set(b, 14, 2, 3); set(b, 16, 2, 3); set(b, 13, 3, 3);
    rect(b, 20, 3, 20, 5, 3); set(b, 19, 2, 3); set(b, 21, 2, 3); set(b, 22, 3, 3);
    set(b, 3, 10, 3); set(b, 2, 9, 3);               // stub tail
    ellipse(b, 11, 14, 5, 3, 2);
    set(b, 17, 7, 4); set(b, 18, 7, 5); set(b, 19, 9, 4);
    // flank spots
    set(b, 8, 11, 2); set(b, 12, 10, 2); set(b, 10, 13, 2);
  },
  boar(b, f) {
    const s = f ? 1 : 0;
    rect(b, 5, 15 + s, 7, 18 + s, 1); rect(b, 9, 15 + (1 - s), 11, 18 + (1 - s), 1);
    rect(b, 14, 15 + (1 - s), 16, 18 + (1 - s), 1); rect(b, 18, 15 + s, 20, 18 + s, 1);
    ellipse(b, 11, 12, 8, 5, 1);
    rect(b, 8, 7, 16, 9, 3);                         // mane ridge
    rect(b, 18, 9, 21, 12, 1);                       // head block
    rect(b, 21, 11, 22, 12, 2);                      // snout
    set(b, 19, 13, 5); set(b, 20, 13, 5);            // tusk
    set(b, 3, 10, 3); set(b, 2, 9, 3);
    ellipse(b, 10, 14, 6, 3, 2);
    set(b, 19, 10, 4); set(b, 22, 11, 4);
  },
  cow(b, f) {
    const s = f ? 1 : 0;
    rect(b, 5, 15 + s, 7, 18 + s, 1); rect(b, 9, 15 + (1 - s), 11, 18 + (1 - s), 1);
    rect(b, 14, 15 + (1 - s), 16, 18 + (1 - s), 1); rect(b, 18, 15 + s, 20, 18 + s, 1);
    ellipse(b, 11, 12, 8, 5, 1);
    disc(b, 18, 8, 3, 1);
    rect(b, 14, 4, 15, 5, 3); rect(b, 21, 4, 22, 5, 3); // horns
    rect(b, 19, 10, 21, 12, 2);                       // muzzle
    set(b, 3, 10, 3); set(b, 2, 11, 3); set(b, 2, 12, 3); // tail tuft
    ellipse(b, 11, 14, 6, 3, 2);
    set(b, 18, 7, 4); set(b, 19, 7, 5);
    // spots
    disc(b, 8, 10, 2, 2); disc(b, 14, 12, 1, 2);
  },
  monkey(b, f) {
    const s = f ? 1 : 0;
    rect(b, 9, 16 + s, 10, 18 + s, 1); rect(b, 13, 16 + (1 - s), 14, 18 + (1 - s), 1);
    ellipse(b, 12, 11, 5, 5, 1);                     // upright body
    disc(b, 12, 5, 3, 1);                            // head on top
    rect(b, 6, 9 + s, 7, 12 + s, 1);                 // arm L
    rect(b, 17, 9 + (1 - s), 18, 12 + (1 - s), 1);   // arm R
    disc(b, 9, 4, 1, 3); disc(b, 15, 4, 1, 3);       // round ears
    // curled tail
    set(b, 5, 13, 3); set(b, 4, 12, 3); set(b, 4, 11, 3); set(b, 5, 10, 3);
    disc(b, 12, 12, 2, 2);                           // belly patch
    disc(b, 12, 6, 1, 2);                            // face patch
    set(b, 13, 4, 4); set(b, 14, 4, 5); set(b, 14, 6, 4);
  },
  blob(b, f) {
    const s = f ? 1 : 0;
    ellipse(b, 12, 13 + s, 8, 6, 1);
    ellipse(b, 12, 10 + s, 6, 5, 1);
    ellipse(b, 12, 15 + s, 6, 3, 2);                 // belly
    set(b, 10, 9 + s, 4); set(b, 15, 9 + s, 4);      // eyes
    set(b, 11, 9 + s, 5); set(b, 16, 9 + s, 5);
    rect(b, 11, 12 + s, 13, 12 + s, 4);              // mouth
    set(b, 12, 5 + s, 3); set(b, 13, 4 + s, 3);      // drip on top
  },
  serpent(b, f) {
    // S-curve body: discs along a sine path, thicker at head
    const pts: [number, number, number][] = [[4, 16, 2], [7, 14 + f, 3], [11, 12, 3], [15, 10 - f, 3], [18, 7, 4]];
    for (const [x, y, r] of pts) disc(b, x, y, r, 1);
    disc(b, 18, 7, 4, 1);                            // head
    rect(b, 15, 3, 16, 5, 3); set(b, 20, 3, 3); set(b, 21, 4, 3); // crest
    set(b, 2, 16, 3); set(b, 1, 15, 3);              // tail tip
    ellipse(b, 12, 13, 7, 3, 2);                     // belly shade
    set(b, 19, 6, 4); set(b, 20, 6, 5); set(b, 22, 8, 4); // eye + fang
  },
  human(b, f) {
    const s = f ? 1 : 0;
    rect(b, 9, 15 + s, 11, 18 + s, 2);               // leg L
    rect(b, 13, 15 + (1 - s), 15, 18 + (1 - s), 2);  // leg R
    ellipse(b, 12, 11, 5, 5, 1);                     // torso
    disc(b, 12, 4, 4, 3);                            // head (skin tone)
    rect(b, 8, 2, 16, 4, 3);                         // hair cap
    rect(b, 6, 9 + s, 7, 12 + s, 1);                 // arm L
    rect(b, 17, 9 + (1 - s), 18, 12 + (1 - s), 1);   // arm R
    ellipse(b, 12, 13, 4, 3, 2);                     // tunic bottom
    set(b, 14, 4, 4); set(b, 15, 4, 5);              // eye
    set(b, 11, 6, 4); set(b, 13, 6, 4);              // eyes front? keep one side eye
  },
  ghost(b, f) {
    const s = f ? 1 : 0;
    ellipse(b, 12, 10 + s, 7, 7, 1);                 // dome
    // wavy trailing bottom
    for (let x = 6; x <= 18; x++) set(b, x, 16 + s + ((x % 2) ? 1 : 0), 1);
    set(b, 8, 17 + s, 1); set(b, 12, 17 + s, 1); set(b, 16, 17 + s, 1);
    set(b, 10, 9 + s, 4); set(b, 15, 9 + s, 4);      // eyes
    set(b, 11, 9 + s, 5); set(b, 16, 9 + s, 5);
    set(b, 12, 12 + s, 4); set(b, 13, 12 + s, 4);    // mouth
    set(b, 5, 12 + s, 3); set(b, 4, 11 + s, 3);      // wisp L
    set(b, 19, 12 + s, 3); set(b, 20, 11 + s, 3);    // wisp R
  },
};

interface SpriteDef { plan: keyof typeof PLANS; colors: [string, string, string]; }

const SPRITES: Record<string, SpriteDef> = {
  lamball:     { plan: "quadruped", colors: ["#ede0c8", "#d8c9ab", "#f2a0b5"] },
  cattiva:     { plan: "kitty",     colors: ["#f2a0b5", "#e085a0", "#ffffff"] },
  chikipi:     { plan: "bird",      colors: ["#f5f2ea", "#e8e0cc", "#e64533"] },
  foxparks:    { plan: "kitty",     colors: ["#e8963c", "#c97e2a", "#ffd54f"] },
  pengullet:   { plan: "bird",      colors: ["#4d9de0", "#2b5d8a", "#e8d44d"] },
  penking:     { plan: "bird",      colors: ["#3f94c8", "#2b5d8a", "#ffd54f"] },
  eikthyrdeer: { plan: "deer",      colors: ["#d4b96e", "#b8945a", "#8a6d4d"] },
  lifmunk:     { plan: "mouse",     colors: ["#4caf50", "#3d9143", "#9acd32"] },
  tanzee:      { plan: "monkey",    colors: ["#9acd32", "#7a9d2a", "#d4b96e"] },
  sparkit:     { plan: "mouse",     colors: ["#e8d44d", "#c9b23a", "#ff9a3c"] },
  jolthog:     { plan: "hedgehog",  colors: ["#e8e05c", "#c9bf45", "#8a6d4d"] },
  dumud:       { plan: "serpent",   colors: ["#b8935f", "#96794d", "#8fd1a0"] },
  depresso:    { plan: "blob",      colors: ["#6fa8d1", "#5a8db0", "#4d6f8a"] },
  daedream:    { plan: "ghost",     colors: ["#c678dd", "#a45ec0", "#e08ee8"] },
  mau:         { plan: "kitty",     colors: ["#a8b5c4", "#8a98a8", "#e8d44d"] },
  rushoar:     { plan: "boar",      colors: ["#d1813c", "#a96a2f", "#f5eee0"] },
  cremis:      { plan: "kitty",     colors: ["#f5eee0", "#d8d0be", "#e8963c"] },
  mozzarina:   { plan: "cow",       colors: ["#ede0c8", "#c9b89e", "#e8d44d"] },
  fuack:       { plan: "bird",      colors: ["#4dd0e1", "#35a8b8", "#e8d44d"] },
  $player:     { plan: "human",     colors: ["#d17b3c", "#4d9de0", "#e8c9a0"] },
};

function shade(hex: string, f: number): string {
  const m = /^#(..)(..)(..)$/.exec(hex);
  if (!m) return hex;
  const c = (i: number) => Math.max(0, Math.min(255, Math.floor(parseInt(m[i], 16) * f)));
  return `rgb(${c(1)},${c(2)},${c(3)})`;
}
function darken(hex: string, f: number): string { return shade(hex, f); }
function dim(hex: string): string { return darken(hex, 0.45); }

// cache: speciesId -> [frame0, frame1] canvases
const texCache = new Map<string, [HTMLCanvasElement, HTMLCanvasElement]>();

// luminance ramp: every sprite pixel is drawn as a tiny character, picked
// by how bright its shaded color is — the sprite IS a block of text.
const RAMP = ["·", ":", "░", "▒", "▓", "█"];
function rampFor(lum: number, h: number): string {
  const i = Math.max(0, Math.min(RAMP.length - 1, Math.floor(lum / 256 * RAMP.length)));
  // neighbors in the ramp get swapped by hash for organic texture
  return RAMP[Math.max(0, Math.min(RAMP.length - 1, i + (h < 0.25 ? -1 : h > 0.8 ? 1 : 0)))];
}
function lum(col: string): number {
  const m = /rgb\((\d+),(\d+),(\d+)\)/.exec(col) ?? /^#(..)(..)(..)$/.exec(col);
  if (!m) return 128;
  const r = parseInt(m[1], 16), g = parseInt(m[2], 16), b = parseInt(m[3], 16);
  return r * 0.3 + g * 0.55 + b * 0.15;
}

function buildTex(r: Renderer, id: string, frame: number): HTMLCanvasElement {
  const def = SPRITES[id];
  const b = newPix();
  PLANS[def.plan](b, frame);
  const cvs = document.createElement("canvas");
  cvs.width = W * MICRO_W; cvs.height = H * MICRO_H;
  const c2 = cvs.getContext("2d")!;
  const pal: string[] = [def.colors[0], def.colors[1], def.colors[2], "#1a1d20", "#ffffff"];
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const c = b[y * W + x];
    if (!c) continue;
    const h = hash2(x, y, 31);
    // volume shading: dark outline on open edges, rim light on top edges,
    // belly shade in lower quarter, slight per-pixel jitter inside.
    const openL = !b[y * W + x - 1], openR = !b[y * W + x + 1];
    const openT = y === 0 || !b[(y - 1) * W + x], openB = y === H - 1 || !b[(y + 1) * W + x];
    const open = openL || openR || openT || openB;
    let col = pal[c - 1];
    if (open) col = shade(col, 0.5);
    else if (openT) col = shade(col, 1.45);            // rim light
    else if (y > H * 0.72) col = shade(col, 0.82);     // ground shade
    else col = shade(col, 0.94 + h * 0.12);            // interior jitter
    const g = open ? (h < 0.5 ? "░" : "▒") : rampFor(lum(col), h);
    r.microInto(c2, x * MICRO_W, y * MICRO_H, g, col);
  }
  return cvs;
}

function tex(r: Renderer, id: string, frame: number): HTMLCanvasElement | null {
  if (!SPRITES[id]) return null;
  let t = texCache.get(id);
  if (!t) { t = [buildTex(r, id, 0), buildTex(r, id, 1)]; texCache.set(id, t); }
  return t[frame];
}

const lastPos = new Map<number, { x: number; y: number }>();

/** Draw a pal's pixel-art sprite, anchored bottom-center at its position. */
export function drawPal(r: Renderer, p: Pal, sp: Species, camX: number, camY: number, time: number, asleep: boolean): void {
  const def = SPRITES[p.speciesId];
  if (!def) {
    r.tileAt(p.x - 0.5, p.y - 0.5, sp.glyph, asleep ? "#4d565c" : sp.color);
    return;
  }
  const prev = lastPos.get(p.uid);
  const moving = prev ? Math.hypot(p.x - prev.x, p.y - prev.y) > 0.02 : false;
  lastPos.set(p.uid, { x: p.x, y: p.y });
  const frame = moving ? Math.floor(time * 6 + p.uid) % 2 : 0;
  const img = tex(r, p.speciesId, frame)!;

  const dw = W * MICRO_W * SCALE, dh = H * MICRO_H * SCALE;
  const bob = moving && frame === 1 ? -3 : (asleep ? 2 : 0);
  const dx = p.x * CELL_W - dw / 2 - camX;
  const dy = p.y * CELL_H - dh + CELL_H - camY + bob;

  const ctx = r.ctx;
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  if (asleep) ctx.globalAlpha = 0.55;
  if (p.dir < 0) {
    ctx.translate(dx + dw / 2, 0); ctx.scale(-1, 1); ctx.translate(-(dx + dw / 2), 0);
  }
  ctx.drawImage(img, dx, dy, dw, dh);
  ctx.restore();

  // element badge floats by the head
  const el = sp.elements[0];
  const ex = p.x * CELL_W + (p.dir < 0 ? -dw / 2 - 8 : dw / 2 + 2) - camX;
  const ey = dy - CELL_H * 0.55;
  r.glyph(ex, ey, ELEMENT_GLYPH[el], asleep ? dim(ELEMENT_COLOR[el]) : ELEMENT_COLOR[el]);
}

/** Draw the player as a pixel human, anchored bottom-center. */
export function drawHuman(r: Renderer, x: number, y: number, dir: number, camX: number, camY: number, time: number, moving: boolean): void {
  const frame = moving ? Math.floor(time * 6) % 2 : 0;
  const img = tex(r, "$player", frame)!;
  const dw = W * MICRO_W * SCALE, dh = H * MICRO_H * SCALE;
  const bob = moving && frame === 1 ? -3 : 0;
  const dx = x * CELL_W - dw / 2 - camX;
  const dy = y * CELL_H - dh + CELL_H - camY + bob;
  const ctx = r.ctx;
  ctx.save();
  ctx.imageSmoothingEnabled = false;
  if (dir < 0) {
    ctx.translate(dx + dw / 2, 0); ctx.scale(-1, 1); ctx.translate(-(dx + dw / 2), 0);
  }
  ctx.drawImage(img, dx, dy, dw, dh);
  ctx.restore();
}
