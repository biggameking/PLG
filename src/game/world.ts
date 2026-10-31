// Tile world: generation, collision, harvesting, glyph rendering info.
import { hash2, Rng } from "../engine/rng.ts";
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
const GREENS = ["#4a7c3f", "#3f6b3a", "#568a48", "#376030"];
const GRASS_BG = ["#12200e", "#14240f", "#101c0d"];
const WATER_TONES = ["#2e6f9e", "#356f9e", "#2a6290"];
const SAND_TONES = ["#c9b578", "#b8a468", "#d0be85"];
const ROCK_TONES = ["#6b6f72", "#5e6366", "#7a7e80", "#565a5e"];
const FLOWER_TONES = ["#c678dd", "#e06c75", "#e5c07b", "#ffffff", "#d16d9e"];
const TREE_TONES = ["#2e6b31", "#3a7d3c", "#265b28"];

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
      if (nearLand) return [h < 0.4 ? "≈" : "~", "#5b9ec4", "#123447"];
      return [h < 0.5 ? "≈" : "~", pick(WATER_TONES, h2), "#0c2637"];
    }
    case "sand": {
      const g = h < 0.6 ? "·" : h < 0.8 ? "," : h < 0.93 ? "\"" : "n";
      return [g, pick(SAND_TONES, h2), h < 0.5 ? "#352e20" : "#3a3223"];
    }
    case "grass": {
      if (h2 < 0.10) return [h < 0.5 ? ";" : "w", "#2c4d28", pick(GRASS_BG, h)]; // dark moss patches
      const g = h < 0.35 ? "'" : h < 0.55 ? "`" : h < 0.75 ? "," : h < 0.88 ? "." : "w";
      const fg = nearWater ? "#3a5f38" : pick(GREENS, h2 * 3.7 % 1);
      return [g, fg, pick(GRASS_BG, h)];
    }
    case "tallgrass": {
      const g = h < 0.5 ? "♣" : h < 0.8 ? "♠" : "w";
      return [g, pick(["#5b9152", "#4d7d47", "#66a15c"], h2), pick(GRASS_BG, h)];
    }
    case "flower": {
      const g = h < 0.4 ? "✿" : h < 0.7 ? "❀" : "✾";
      return [g, pick(FLOWER_TONES, h2), "#14240f"];
    }
    case "tree": {
      return [h < 0.72 ? "♣" : "♠", pick(TREE_TONES, h2), "#0d1a0b"];
    }
    case "rock": {
      const g = h < 0.45 ? "▲" : h < 0.7 ? "▴" : h < 0.85 ? "^" : "n";
      return [g, pick(ROCK_TONES, h2), "#16181b"];
    }
    case "ore": {
      const g = h < 0.6 ? "▓" : h < 0.85 ? "▒" : "◆";
      return [g, pick(["#e8963c", "#d4af37", "#c97e2a"], h2), "#16181b"];
    }
    case "floor": return [h < 0.8 ? "·" : "-", "#4d565c", "#1e242a"];
    case "dirt": return [h < 0.7 ? "·" : ",", "#5d4934", "#201810"];
    default: return ["·", "#3f6b3a"];
  }
}
