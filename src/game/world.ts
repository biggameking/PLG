// Tile world: generation, collision, harvesting, glyph rendering info.
import { hash2, Rng } from "../engine/rng.ts";
import { Renderer, CELL_W, CELL_H, MICRO_W, MICRO_H } from "../engine/renderer.ts";
import { WORLD_W, WORLD_H } from "./types.ts";

export type Tile =
  | "water" | "sand" | "grass" | "tallgrass" | "tree" | "rock" | "ore"
  | "floor" | "dirt" | "flower";

export const T = {
  water: "water" as Tile, sand: "sand" as Tile, grass: "grass" as Tile,
  tallgrass: "tallgrass" as Tile, tree: "tree" as Tile, rock: "rock" as Tile,
  ore: "ore" as Tile, floor: "floor" as Tile, dirt: "dirt" as Tile, flower: "flower" as Tile,
};

export const SOLID = new Set<Tile>(["water", "tree", "rock", "ore"]);

export class World {
  tiles: Tile[] = new Array(WORLD_W * WORLD_H);
  hp: number[] = new Array(WORLD_W * WORLD_H); // harvest hp for tree/rock/ore
  structures = new Set<number>();              // tile indices blocked by buildings
  spawnZone: number[] = new Array(WORLD_W * WORLD_H); // 0..3 difficulty band

  idx(x: number, y: number): number {
    return x + y * WORLD_W;
  }
  inBounds(x: number, y: number): boolean {
    return x >= 0 && y >= 0 && x < WORLD_W && y < WORLD_H;
  }
  get(x: number, y: number): Tile {
    return this.inBounds(x, y) ? this.tiles[this.idx(x, y)] : "water";
  }
  set(x: number, y: number, t: Tile): void {
    if (this.inBounds(x, y)) this.tiles[this.idx(x, y)] = t;
  }
  blocked(x: number, y: number): boolean {
    const i = this.idx(Math.floor(x), Math.floor(y));
    return !this.inBounds(Math.floor(x), Math.floor(y)) || SOLID.has(this.tiles[i]) || this.structures.has(i);
  }
  zoneAt(x: number, y: number): number {
    return this.inBounds(x, y) ? this.spawnZone[this.idx(x, y)] : 3;
  }

  generate(seed: number): { spawnX: number; spawnY: number } {
    const rng = new Rng(seed);
    for (let y = 0; y < WORLD_H; y++) {
      for (let x = 0; x < WORLD_W; x++) {
        const i = this.idx(x, y);
        // fbm-ish value noise at two scales
        const e = hash2(x >> 3, y >> 3, seed) * 0.6 + hash2(x >> 1, y >> 1, seed + 7) * 0.4;
        const m = hash2(x >> 2, y >> 2, seed + 31);
        let t: Tile = "grass";
        if (e < 0.30) t = "water";
        else if (e < 0.36) t = "sand";
        else if (m > 0.62 && e > 0.5) t = rng.chance(0.75) ? "tree" : "tallgrass";
        else if (m > 0.58 && e < 0.48) t = rng.chance(0.6) ? "rock" : (rng.chance(0.35) ? "ore" : "grass");
        else if (m < 0.10) t = "flower";
        else if (hash2(x, y, seed + 77) < 0.06) t = "tallgrass";
        this.tiles[i] = t;
        this.hp[i] = t === "tree" ? 30 : t === "rock" ? 60 : t === "ore" ? 90 : 0;
        // zone by distance from map center
        const dx = x - WORLD_W / 2, dy = y - WORLD_H / 2;
        const d = Math.sqrt(dx * dx + dy * dy);
        this.spawnZone[i] = d < 45 ? 0 : d < 75 ? 1 : d < 95 ? 2 : 3;
      }
    }
    // guarantee a clearing near center
    const cx = WORLD_W / 2, cy = WORLD_H / 2;
    for (let y = cy - 8; y < cy + 8; y++) {
      for (let x = cx - 8; x < cx + 8; x++) {
        const t = this.tiles[this.idx(x, y)];
        if (t === "water" || t === "rock" || t === "ore") this.set(x, y, "grass");
        if (t === "tree") this.set(x, y, rng.chance(0.5) ? "grass" : "tree");
      }
    }
    // scatter wild resource tiles: berry bushes & paldium on sand
    for (let y = 0; y < WORLD_H; y++) {
      for (let x = 0; x < WORLD_W; x++) {
        const i = this.idx(x, y);
        if (this.tiles[i] === "tallgrass" && hash2(x, y, seed + 5) < 0.2) this.tiles[i] = "flower"; // flower marks berry bushes visually
        if (this.tiles[i] === "sand" && hash2(x, y, seed + 9) < 0.12) { this.tiles[i] = "ore"; this.hp[i] = 45; } // paldium-ish nodes on sand
      }
    }
    return { spawnX: cx, spawnY: cy };
  }
}

// Tile visuals: [glyph, fg, bg?] — per-tile hash variation + neighbor-aware edges.
const GREENS = ["#5da24c", "#4f9140", "#6db85a", "#58a848"];
const GRASS_BG = ["#1c2f16", "#1e3218", "#1a2b14"];
const WATER_TONES = ["#3d8fd1", "#3590c9", "#4aa3d4"];
const SAND_TONES = ["#ead899", "#dfc98a", "#f2e6ae"];
const ROCK_TONES = ["#8a9096", "#7d868e", "#98a0a8", "#707880"];
const FLOWER_TONES = ["#e08ee8", "#ff7d6e", "#ffd54f", "#ffffff", "#ff9ad5"];
const TREE_TONES = ["#3f9140", "#4faa50", "#359138"];

export function tileLook(world: World, x: number, y: number, seed: number): [string, string, string?] {
  const t = world.get(x, y);
  const h = hash2(x, y, seed);
  const h2 = hash2(x, y, seed + 101);
  const pick = <A,>(arr: A[], v: number): A => arr[Math.min(arr.length - 1, Math.floor(v * arr.length))];

  const nearWater = world.get(x + 1, y) === "water" || world.get(x - 1, y) === "water" ||
    world.get(x, y + 1) === "water" || world.get(x, y - 1) === "water";
  const nearLand = t === "water" && (
    world.get(x + 1, y) !== "water" || world.get(x - 1, y) !== "water" ||
    world.get(x, y + 1) !== "water" || world.get(x, y - 1) !== "water");

  switch (t) {
    case "water": {
      if (nearLand) return [h < 0.4 ? "≈" : "~", "#6fd0ff", "#1a4a63"];
      return [h < 0.5 ? "≈" : "~", pick(WATER_TONES, h2), "#0e3a54"];
    }
    case "sand": {
      const g = h < 0.6 ? "·" : h < 0.8 ? "," : h < 0.93 ? "\"" : "n";
      return [g, pick(SAND_TONES, h2), h < 0.5 ? "#4a3f2c" : "#524730"];
    }
    case "grass": {
      if (h2 < 0.10) return [h < 0.5 ? ";" : "w", "#3d6b35", pick(GRASS_BG, h)]; // dark moss patches
      const g = h < 0.35 ? "'" : h < 0.55 ? "`" : h < 0.75 ? "," : h < 0.88 ? "." : "w";
      const fg = nearWater ? "#4a7a48" : pick(GREENS, h2 * 3.7 % 1);
      return [g, fg, pick(GRASS_BG, h)];
    }
    case "tallgrass": {
      const g = h < 0.5 ? "♣" : h < 0.8 ? "♠" : "w";
      return [g, pick(["#6fc464", "#5fae55", "#7fd474"], h2), pick(GRASS_BG, h)];
    }
    case "flower": {
      const g = h < 0.4 ? "✿" : h < 0.7 ? "❀" : "✾";
      return [g, pick(FLOWER_TONES, h2), "#1e3218"];
    }
    case "tree": {
      return [h < 0.72 ? "♣" : "♠", pick(TREE_TONES, h2), "#14240f"];
    }
    case "rock": {
      const g = h < 0.45 ? "▲" : h < 0.7 ? "▴" : h < 0.85 ? "^" : "n";
      return [g, pick(ROCK_TONES, h2), "#242b31"];
    }
    case "ore": {
      const g = h < 0.6 ? "▓" : h < 0.85 ? "▒" : "◆";
      return [g, pick(["#ffb347", "#ffd54f", "#ff9a3c"], h2), "#242b31"];
    }
    case "floor": return [h < 0.8 ? "·" : "-", "#6b7a85", "#28323a"];
    case "dirt": return [h < 0.7 ? "·" : ",", "#8a6f4d", "#2c2118"];
    default: return ["·", "#4f9140"];
  }
}

// ---------- micro-glyph terrain: every tile is a 4x4 block of tiny chars ----------
// The whole map is baked from characters: zoomed out it reads as pixel art,
// zoomed in you see it's all text — the user's "characters as pixels" model.
const CHUNK = 16; // tiles per chunk edge
const MROWS = 4, MCOLS = 4;
const MY = CELL_H / MROWS; // 4.5 px row pitch

type MicroSpec = { bg: string; density: number; glyph: (h: number, mx: number, my: number) => string; tone: (h: number) => string };

const MICRO: Record<Tile, MicroSpec> = {
  water: {
    bg: "#0e3a54", density: 0.72,
    glyph: (h, mx, my) => my % 2 ? (h < 0.5 ? "≈" : "-") : (h < 0.5 ? "~" : "≈"),
    tone: (h) => ["#3d8fd1", "#3590c9", "#4aa3d4", "#2f7bb8"][Math.floor(h * 4)],
  },
  sand: {
    bg: "#4a3f2c", density: 0.62,
    glyph: (h) => h < 0.5 ? "·" : h < 0.75 ? "," : h < 0.9 ? "\"" : ":",
    tone: (h) => ["#ead899", "#dfc98a", "#c9b070", "#f2e6ae"][Math.floor(h * 4)],
  },
  grass: {
    bg: "#1c2f16", density: 0.55,
    glyph: (h) => h < 0.3 ? "'" : h < 0.5 ? "," : h < 0.65 ? "." : h < 0.8 ? "w" : "v",
    tone: (h) => ["#5da24c", "#4f9140", "#6db85a", "#3d6b35"][Math.floor(h * 4)],
  },
  tallgrass: {
    bg: "#1a2b14", density: 0.8,
    glyph: (h) => h < 0.3 ? "w" : h < 0.55 ? "v" : h < 0.75 ? "'" : "♣",
    tone: (h) => ["#6fc464", "#5fae55", "#7fd474", "#4f9140"][Math.floor(h * 4)],
  },
  flower: {
    bg: "#1e3218", density: 0.55,
    glyph: (h) => h < 0.3 ? "✿" : h < 0.55 ? "❀" : h < 0.8 ? "·" : "'",
    tone: (h) => ["#e08ee8", "#ff7d6e", "#ffd54f", "#ffffff", "#ff9ad5", "#6db85a"][Math.floor(h * 6)],
  },
  tree: {
    bg: "#14240f", density: 0.9,
    glyph: (h, mx, my) => my === 3 ? (mx === 1 || mx === 2 ? "│" : "·") : (h < 0.6 ? "♣" : h < 0.85 ? "♠" : "▲"),
    tone: (h) => ["#3f9140", "#4faa50", "#359138", "#2d7030", "#8a6d4d"][Math.floor(h * 5)],
  },
  rock: {
    bg: "#242b31", density: 0.66,
    glyph: (h) => h < 0.4 ? "▲" : h < 0.65 ? "^" : h < 0.85 ? "n" : "·",
    tone: (h) => ["#8a9096", "#7d868e", "#98a0a8", "#5d666e"][Math.floor(h * 4)],
  },
  ore: {
    bg: "#242b31", density: 0.66,
    glyph: (h) => h < 0.4 ? "▓" : h < 0.7 ? "▒" : h < 0.85 ? "◆" : "·",
    tone: (h) => ["#ffb347", "#ffd54f", "#ff9a3c", "#8a9096"][Math.floor(h * 4)],
  },
  floor: {
    bg: "#28323a", density: 0.5,
    glyph: (h) => h < 0.7 ? "·" : "-",
    tone: (h) => ["#6b7a85", "#5d6a75", "#7a8893"][Math.floor(h * 3)],
  },
  dirt: {
    bg: "#2c2118", density: 0.55,
    glyph: (h) => h < 0.6 ? "·" : h < 0.85 ? "," : ":",
    tone: (h) => ["#8a6f4d", "#9a7f5a", "#6f5839"][Math.floor(h * 3)],
  },
};

const chunkCache = new Map<string, HTMLCanvasElement>();

function drawMicroTile(r: Renderer, ctx: CanvasRenderingContext2D, world: World, x: number, y: number, seed: number, px: number, py: number): void {
  const t = world.get(x, y);
  const spec = MICRO[t] ?? MICRO.grass;
  ctx.fillStyle = spec.bg;
  ctx.fillRect(px, py, CELL_W, CELL_H);
  for (let my = 0; my < MROWS; my++) {
    for (let mx = 0; mx < MCOLS; mx++) {
      const h = hash2(x * 13 + mx * 3 + 1, y * 13 + my * 5 + 2, seed);
      if (h >= spec.density) continue;
      r.microInto(ctx, px + mx * MICRO_W, py + my * MY, spec.glyph(h, mx, my), spec.tone(h));
    }
  }
}

/** Baked 16x16-tile chunk canvas of micro-glyph terrain (cached). */
export function chunkCanvas(r: Renderer, world: World, seed: number, cx: number, cy: number): HTMLCanvasElement {
  const key = cx + "," + cy;
  let cvs = chunkCache.get(key);
  if (cvs) return cvs;
  cvs = document.createElement("canvas");
  cvs.width = CHUNK * CELL_W; cvs.height = CHUNK * CELL_H;
  const ctx = cvs.getContext("2d")!;
  ctx.fillStyle = "#0e3a54";
  ctx.fillRect(0, 0, cvs.width, cvs.height);
  for (let ty = 0; ty < CHUNK; ty++) {
    for (let tx = 0; tx < CHUNK; tx++) {
      drawMicroTile(r, ctx, world, cx * CHUNK + tx, cy * CHUNK + ty, seed, tx * CELL_W, ty * CELL_H);
    }
  }
  chunkCache.set(key, cvs);
  return cvs;
}

export const CHUNK_TILES = CHUNK;
