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

// Tile visuals: [glyph options, fg, bg?]
export function tileLook(t: Tile, x: number, y: number, seed: number): [string, string, string?] {
  const h = hash2(x, y, seed);
  switch (t) {
    case "water": return [h < 0.5 ? "≈" : "~", "#2e6f9e", "#0e2a3d"];
    case "sand": return [h < 0.85 ? "·" : ",", "#b8a468", "#3a3223"];
    case "grass": return [h < 0.8 ? "·" : (h < 0.9 ? "'" : ","), "#3f6b3a", "#14240f"];
    case "tallgrass": return [h < 0.7 ? "♣" : "♠", "#4d7d47", "#14240f"];
    case "flower": return [h < 0.5 ? "✿" : "❀", "#c678dd", "#14240f"];
    case "tree": return ["♣", "#2e6b31", "#0e1c0c"];
    case "rock": return ["▲", "#6b6f72", "#1a1d20"];
    case "ore": return ["▓", "#e8963c", "#1a1d20"];
    case "floor": return ["·", "#4d565c", "#20262c"];
    case "dirt": return ["·", "#5d4934", "#241a10"];
    default: return ["·", "#3f6b3a"];
  }
}
