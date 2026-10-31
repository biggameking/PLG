// Pal sprites: multi-cell composite "mini-sprites" (Cogmind-style ASCII
// figures). Each species = body-plan template × 3-tone palette × parts.
// Zones: 0 primary (body/head), 1 secondary (legs/belly), 2 accent (ears/horns/tail).
import { Pal } from "./types.ts";
import { Species } from "../data/species.ts";
import { ELEMENT_GLYPH, ELEMENT_COLOR } from "../data/elements.ts";
import { Renderer, CELL_W, CELL_H } from "../engine/renderer.ts";

interface SpriteDef {
  plan: keyof typeof PLANS;
  colors: [string, string, string]; // primary, secondary, accent
}

// Template rows: 3 chars wide × 2 tall. 'l' = animated leg cell.
const PLANS = {
  quadruped: ["Λ◔~", "l●l"],
  kitty:     ["Λ◔ ", "l●~"],
  bird:      ["(◔)", "l●l"],
  mouse:     ["'◔~", "l●l"],
  hedgehog:  ["≋◔≋", "l●l"],
  deer:      ["Ψ◔~", "l●l"],
  boar:      ["≈◕}", "l●l"],
  cow:       ["Υ◕~", "l●l"],
  monkey:    ["Ʌ◕Ʌ", "l|l"],
  blob:      [" ◔ ", "l●l"],
  serpent:   ["~◉~", " ≈ "],
  ghost:     ["◔~ ", " ~ "],
} as const;

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
};

const LEGS_A = "'";
const LEGS_B = "⌐";
const lastPos = new Map<number, { x: number; y: number }>();

function dim(hex: string): string {
  const m = /^#(..)(..)(..)$/.exec(hex);
  if (!m) return hex;
  const f = 0.45;
  return `rgb(${Math.floor(parseInt(m[1], 16) * f)},${Math.floor(parseInt(m[2], 16) * f)},${Math.floor(parseInt(m[3], 16) * f)})`;
}

/** Draw a pal's composite sprite, anchored bottom-center at its position. */
export function drawPal(r: Renderer, p: Pal, sp: Species, camX: number, camY: number, time: number, asleep: boolean): void {
  const def = SPRITES[p.speciesId];
  if (!def) {
    r.tileAt(p.x - 0.5, p.y - 0.5, sp.glyph, asleep ? "#4d565c" : sp.color);
    return;
  }
  const prev = lastPos.get(p.uid);
  const moving = prev ? Math.hypot(p.x - prev.x, p.y - prev.y) > 0.02 : false;
  lastPos.set(p.uid, { x: p.x, y: p.y });
  const frame = moving ? Math.floor(time * 10 + p.uid) % 2 : 0;
  const bob = moving && frame === 1 ? -2 : (asleep ? 1 : 0);

  const rows = PLANS[def.plan];
  const flip = p.dir < 0;
  const px = (p.x - 1.5) * CELL_W - camX;
  const py = (p.y - 1.9) * CELL_H - camY + bob;
  for (let ry = 0; ry < rows.length; ry++) {
    const row = rows[ry];
    for (let cx = 0; cx < row.length; cx++) {
      const sx = flip ? row.length - 1 - cx : cx;
      const raw = row[sx];
      let ch = raw;
      if (raw === "l") ch = frame ? LEGS_B : LEGS_A;
      if (ch === " ") continue;
      // 'l' legs + '≈' belly → secondary; ornaments/ears/horns/tails → accent; rest → primary
      const zone = raw === "l" || raw === "≈" ? 1 : "Λ~()Ψ≋}ΥɅ'".includes(raw) ? 2 : 0;
      const color = def.colors[zone] ?? def.colors[0];
      r.glyph(px + cx * CELL_W, py + ry * CELL_H, ch, asleep ? dim(color) : color);
    }
  }
  // element badge: tiny element glyph above the head
  const ex = (p.x - 0.9) * CELL_W + (flip ? 34 : -4) - camX;
  const ey = py - CELL_H * 0.9;
  const el = sp.elements[0];
  r.glyph(ex, ey, ELEMENT_GLYPH[el], asleep ? dim(ELEMENT_COLOR[el]) : ELEMENT_COLOR[el]);
}
