// Tile world: generation, collision, harvesting, glyph rendering info.
import { hash2, Rng } from "../engine/rng.ts";
import { CELL_W, CELL_H } from "../engine/renderer.ts";
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
  elev: Uint8Array = new Uint8Array(WORLD_W * WORLD_H); // 0..3 terrain height
  ramp: Uint8Array = new Uint8Array(WORLD_W * WORLD_H); // 1 = slope crossing between levels

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
  elevAt(x: number, y: number): number {
    return this.inBounds(x, y) ? this.elev[this.idx(x, y)] : 0;
  }
  // continuous-position collision; pass from-coords for elevation rules
  blocked(x: number, y: number, fromX?: number, fromY?: number): boolean {
    const tx = Math.floor(x), ty = Math.floor(y);
    const i = this.idx(tx, ty);
    if (!this.inBounds(tx, ty) || SOLID.has(this.tiles[i]) || this.structures.has(i)) return true;
    if (fromX === undefined || fromY === undefined) return false;
    const fi = this.idx(Math.floor(fromX), Math.floor(fromY));
    // elevation changes block movement unless a ramp is involved
    if (this.elev[i] !== this.elev[fi] && !this.ramp[i] && !this.ramp[fi]) return true;
    return false;
  }
  // all footprint cells share one elevation (building on cliffs is disallowed)
  flatAt(x: number, y: number, w: number, h: number): boolean {
    const e = this.elevAt(x, y);
    for (let dy = 0; dy < h; dy++) for (let dx = 0; dx < w; dx++)
      if (this.elevAt(x + dx, y + dy) !== e) return false;
    return true;
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
        // elevation: separate fbm noise quantized to 0..3; water/sand hug level 0
        const el = hash2(x >> 4, y >> 4, seed + 911) * 0.7 + hash2(x >> 1, y >> 1, seed + 912) * 0.3;
        this.elev[i] = t === "water" || t === "sand" ? 0 :
          el < 0.50 ? 1 : el < 0.68 ? 2 : 3;
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
        const i = this.idx(x, y);
        const t = this.tiles[i];
        if (t === "water" || t === "rock" || t === "ore") this.set(x, y, "grass");
        if (t === "tree") this.set(x, y, rng.chance(0.5) ? "grass" : "tree");
        this.elev[i] = 1; // flat spawn plateau
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
    // ramps: slope tiles wherever a land tile borders a different elevation
    for (let y = 0; y < WORLD_H; y++) {
      for (let x = 0; x < WORLD_W; x++) {
        const i = this.idx(x, y);
        const t = this.tiles[i];
        if (t === "water") continue;
        const e0 = this.elev[i];
        const mix = this.elevAt(x - 1, y) !== e0 || this.elevAt(x + 1, y) !== e0 ||
          this.elevAt(x, y - 1) !== e0 || this.elevAt(x, y + 1) !== e0;
        this.ramp[i] = mix && hash2(x, y, seed + 913) < 0.45 ? 1 : 0;
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

// ---------- pixel-art terrain: hand-tuned 16x18px tiles, baked per chunk ----------
const CHUNK = 16; // tiles per chunk edge

const chunkCache = new Map<string, HTMLCanvasElement>();

function drawPixTile(ctx: CanvasRenderingContext2D, world: World, x: number, y: number, seed: number, px: number, py: number): void {
  const t = world.get(x, y);
  const h = (i: number) => hash2(x * 17 + i, y * 17 + i * 3, seed + i);
  const P = (dx: number, dy: number, c: string) => { ctx.fillStyle = c; ctx.fillRect(px + dx, py + dy, 1, 1); };
  const B = (dx: number, dy: number, w: number, hh: number, c: string) => { ctx.fillStyle = c; ctx.fillRect(px + dx, py + dy, w, hh); };

  // grass base shared by land tiles (gives terrain cohesion)
  const grassBase = () => {
    ctx.fillStyle = "#3e7c38"; ctx.fillRect(px, py, CELL_W, CELL_H);
    for (let i = 0; i < 7; i++) P(Math.floor(h(i) * 16), Math.floor(h(i + 3) * 18), h(i + 6) < 0.5 ? "#4d9345" : "#356b30");
    for (let i = 0; i < 4; i++) { const bx = Math.floor(h(i + 9) * 14) + 1, by = Math.floor(h(i + 12) * 16) + 1; P(bx, by, "#57a24d"); P(bx, by - 1, "#6fbf60"); } // blade tips
  };

  const landNearWater = t !== "water" && (
    world.get(x + 1, y) === "water" || world.get(x - 1, y) === "water" ||
    world.get(x, y + 1) === "water" || world.get(x, y - 1) === "water");

  switch (t) {
    case "water": {
      ctx.fillStyle = "#2b6fa8"; ctx.fillRect(px, py, CELL_W, CELL_H);
      ctx.fillStyle = "#2f7cb8"; ctx.fillRect(px, py, CELL_W, 2);
      // wave dashes
      for (let i = 0; i < 4; i++) {
        const wx = Math.floor(h(i) * 13), wy = 2 + Math.floor(h(i + 4) * 14);
        B(wx, wy, 3, 1, h(i + 8) < 0.5 ? "#5aa8d8" : "#4a9ccc");
      }
      for (let i = 0; i < 3; i++) P(Math.floor(h(i + 10) * 16), Math.floor(h(i + 13) * 18), "#3d8fd1");
      // sparkle glints + deep swells
      for (let i = 0; i < 3; i++) if (h(i + 30) < 0.5) P(Math.floor(h(i + 31) * 16), Math.floor(h(i + 34) * 18), "#9adcf4");
      for (let i = 0; i < 2; i++) B(Math.floor(h(i + 36) * 12), 6 + Math.floor(h(i + 38) * 8), 4, 1, "#256194");
      // shoreline: foam + light band on edges that touch land
      const L = world.get(x - 1, y) !== "water", R = world.get(x + 1, y) !== "water";
      const U = world.get(x, y - 1) !== "water", D = world.get(x, y + 1) !== "water";
      if (L) { B(0, 0, 2, CELL_H, "#8fd4e8"); B(2, 0, 1, CELL_H, "#cfeef4"); for (let i = 0; i < 5; i++) if (h(i + 14) < 0.7) P(3, i * 4 + 1, "#ffffff"); }
      if (R) { B(14, 0, 2, CELL_H, "#8fd4e8"); B(13, 0, 1, CELL_H, "#cfeef4"); for (let i = 0; i < 5; i++) if (h(i + 17) < 0.7) P(12, i * 4 + 1, "#ffffff"); }
      if (U) { B(0, 0, CELL_W, 2, "#8fd4e8"); B(0, 2, CELL_W, 1, "#cfeef4"); for (let i = 0; i < 4; i++) if (h(i + 20) < 0.7) P(i * 4 + 1, 3, "#ffffff"); }
      if (D) { B(0, 16, CELL_W, 2, "#8fd4e8"); B(0, 15, CELL_W, 1, "#cfeef4"); for (let i = 0; i < 4; i++) if (h(i + 23) < 0.7) P(i * 4 + 1, 14, "#ffffff"); }
      break;
    }
    case "sand": {
      ctx.fillStyle = "#e0c88a"; ctx.fillRect(px, py, CELL_W, CELL_H);
      for (let i = 0; i < 9; i++) P(Math.floor(h(i) * 16), Math.floor(h(i + 4) * 18), h(i + 7) < 0.5 ? "#d0b070" : "#f0dca0");
      for (let i = 0; i < 3; i++) P(Math.floor(h(i + 10) * 16), Math.floor(h(i + 13) * 18), "#b89858");
      // shells + stones
      for (let i = 0; i < 2; i++) if (h(i + 30) < 0.35) { const sx = Math.floor(h(i + 31) * 14) + 1, sy = Math.floor(h(i + 33) * 15) + 1; P(sx, sy, "#f4ead0"); P(sx + 1, sy, "#e8d5a8"); }
      if (h(36) < 0.2) { const rx = Math.floor(h(37) * 13) + 1, ry = Math.floor(h(38) * 14) + 2; B(rx, ry, 2, 1, "#a8926a"); }
      if (landNearWater) { for (let i = 0; i < 16; i += 4) { P(i, 17, "#c8a868"); P(i, 0, "#c8a868"); } }
      break;
    }
    case "grass": {
      grassBase();
      // occasional wildflowers + pebbles
      if (h(30) < 0.10) { const fx = Math.floor(h(31) * 13) + 1, fy = Math.floor(h(32) * 13) + 2; P(fx, fy, h(33) < 0.5 ? "#ffd54f" : "#ff9ad5"); P(fx, fy + 1, "#4d9345"); }
      if (h(34) < 0.15) { const sx = Math.floor(h(35) * 14) + 1, sy = Math.floor(h(36) * 15) + 1; P(sx, sy, "#8a8f96"); P(sx + 1, sy, "#6e767e"); }
      if (landNearWater) { // damp edge
        if (world.get(x, y + 1) === "water") B(0, 16, CELL_W, 2, "#2f5c2e");
        if (world.get(x, y - 1) === "water") B(0, 0, CELL_W, 2, "#2f5c2e");
        if (world.get(x - 1, y) === "water") B(0, 0, 2, CELL_H, "#2f5c2e");
        if (world.get(x + 1, y) === "water") B(14, 0, 2, CELL_H, "#2f5c2e");
      }
      break;
    }
    case "tallgrass": {
      grassBase();
      for (let i = 0; i < 6; i++) {
        const bx = 1 + Math.floor(h(i) * 13), by = 6 + Math.floor(h(i + 4) * 11);
        B(bx, by - 4, 1, 4, "#5fae55"); P(bx, by - 5, "#8fd47a"); P(bx + 1, by - 3, "#4d9345");
      }
      if (h(20) < 0.18) { const fx = Math.floor(h(21) * 12) + 2, fy = Math.floor(h(22) * 8) + 3; P(fx, fy, "#ffd54f"); P(fx - 1, fy, "#ff9ad5"); P(fx + 1, fy, "#ff9ad5"); P(fx, fy - 1, "#ff9ad5"); P(fx, fy + 1, "#ff9ad5"); }
      break;
    }
    case "flower": {
      grassBase();
      // a small flower cluster
      const fc = ["#ff9ad5", "#ffd54f", "#ff7d6e", "#e08ee8"][Math.floor(h(1) * 4)];
      const fx = 5 + Math.floor(h(2) * 6), fy = 6 + Math.floor(h(3) * 6);
      P(fx, fy - 1, fc); P(fx - 1, fy, fc); P(fx + 1, fy, fc); P(fx, fy + 1, fc); P(fx, fy, "#ffe680");
      P(fx, fy + 2, "#57a24d"); P(fx, fy + 3, "#4d9345");
      const f2x = (fx + 5) % 13 + 1, f2y = fy + 4;
      P(f2x, f2y - 1, "#ffffff"); P(f2x - 1, f2y, "#ffffff"); P(f2x + 1, f2y, "#ffffff"); P(f2x, f2y, "#ffd54f");
      break;
    }
    case "tree": {
      grassBase();
      // trunk
      B(7, 12, 3, 6, "#6f4e2e"); B(7, 12, 1, 6, "#8a6339"); P(9, 13, "#4e3820");
      // canopy blob: dark rim, mid body, light top-left
      ctx.fillStyle = "#2d6628";
      ctx.beginPath(); ctx.ellipse(px + 8, py + 7, 7.5, 6.5, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = "#3f9140";
      ctx.beginPath(); ctx.ellipse(px + 8, py + 7, 6.4, 5.4, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = "#57b458";
      ctx.beginPath(); ctx.ellipse(px + 6.5, py + 5.5, 4, 3.4, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = "#79cc74";
      ctx.beginPath(); ctx.ellipse(px + 6, py + 4.5, 2, 1.6, 0, 0, Math.PI * 2); ctx.fill();
      for (let i = 0; i < 4; i++) P(3 + Math.floor(h(i) * 10), 3 + Math.floor(h(i + 4) * 8), "#2d6628");
      break;
    }
    case "rock": {
      ctx.fillStyle = "#4a4f55"; ctx.fillRect(px, py, CELL_W, CELL_H);
      // boulder facets
      ctx.fillStyle = "#6e767e";
      ctx.beginPath(); ctx.moveTo(px + 2, py + 13); ctx.lineTo(px + 5, py + 5); ctx.lineTo(px + 11, py + 4); ctx.lineTo(px + 14, py + 10); ctx.lineTo(px + 13, py + 14); ctx.lineTo(px + 3, py + 14); ctx.closePath(); ctx.fill();
      ctx.fillStyle = "#8a929a";
      ctx.beginPath(); ctx.moveTo(px + 5, py + 5); ctx.lineTo(px + 11, py + 4); ctx.lineTo(px + 12, py + 7); ctx.lineTo(px + 6, py + 8); ctx.closePath(); ctx.fill();
      ctx.fillStyle = "#5d646c";
      ctx.beginPath(); ctx.moveTo(px + 12, py + 7); ctx.lineTo(px + 14, py + 10); ctx.lineTo(px + 13, py + 14); ctx.lineTo(px + 10, py + 12); ctx.closePath(); ctx.fill();
      P(5, 6, "#aab2ba"); P(6, 6, "#aab2ba");
      for (let i = 0; i < 3; i++) P(Math.floor(h(i) * 15), 15 + Math.floor(h(i + 3) * 3), "#3a3f45");
      break;
    }
    case "ore": {
      ctx.fillStyle = "#4a4f55"; ctx.fillRect(px, py, CELL_W, CELL_H);
      ctx.fillStyle = "#6e767e";
      ctx.beginPath(); ctx.moveTo(px + 2, py + 13); ctx.lineTo(px + 5, py + 5); ctx.lineTo(px + 11, py + 4); ctx.lineTo(px + 14, py + 10); ctx.lineTo(px + 13, py + 14); ctx.lineTo(px + 3, py + 14); ctx.closePath(); ctx.fill();
      // gold veins
      P(6, 6, "#ffd54f"); P(7, 7, "#ffb347"); P(8, 7, "#ffd54f"); P(9, 9, "#ff9a3c");
      P(11, 6, "#ffb347"); P(10, 11, "#ffd54f"); P(5, 10, "#ffb347"); P(7, 12, "#ff9a3c");
      break;
    }
    case "floor": {
      ctx.fillStyle = "#6b5a45"; ctx.fillRect(px, py, CELL_W, CELL_H);
      for (let i = 0; i < 18; i += 6) B(0, i, CELL_W, 1, "#54462f");
      B(0, 0, 1, CELL_H, "#54462f"); B(10, 0, 1, CELL_H, "#54462f");
      for (let i = 0; i < 4; i++) P(2 + Math.floor(h(i) * 12), 2 + Math.floor(h(i + 4) * 14), "#7d6a52");
      break;
    }
    case "dirt": {
      ctx.fillStyle = "#7a5c3d"; ctx.fillRect(px, py, CELL_W, CELL_H);
      for (let i = 0; i < 8; i++) P(Math.floor(h(i) * 16), Math.floor(h(i + 4) * 18), h(i + 7) < 0.5 ? "#8a6d4d" : "#6a4e33");
      for (let i = 0; i < 3; i++) P(Math.floor(h(i + 10) * 15), Math.floor(h(i + 13) * 17), "#96ab68");
      break;
    }
    default: grassBase();
  }

  // ---- elevation: cliff skirts, side faces, slope steps, altitude tint ----
  const i = world.idx(x, y), e0 = world.elev[i];
  if (t !== "water") {
    if (e0 > world.elevAt(x, y + 1)) { // south cliff face
      B(0, CELL_H - 6, CELL_W, 6, "#37332c");
      B(0, CELL_H - 6, CELL_W, 1, "#57503f");            // rim highlight
      B(0, CELL_H - 3, CELL_W, 1, "#2b2822");            // strata line
      for (let k = 0; k < 3; k++) P(Math.floor(h(k + 26) * 15), CELL_H - 4 + Math.floor(h(k + 29) * 2), "#4a453c");
    }
    if (e0 > world.elevAt(x + 1, y)) { // east face
      B(CELL_W - 2, 0, 2, CELL_H, "#332f28");
      B(CELL_W - 2, 0, 1, CELL_H, "#4a4436");
    }
    if (e0 > world.elevAt(x - 1, y)) { // west face
      B(0, 0, 2, CELL_H, "#332f28");
      B(1, 0, 1, CELL_H, "#4a4436");
    }
    if (world.ramp[i]) { // dirt stairs: horizontal steps climbing south→north
      for (let k = 0; k < 4; k++) {
        B(2 + k * 3, 14 - k * 4, 2, 1, "#8a6f4d");
        B(2 + k * 3, 15 - k * 4, 2, 3, "#6a5238");
        P(1 + k * 3, 15 - k * 4, "#4a3a28"); P(4 + k * 3, 15 - k * 4, "#4a3a28");
      }
    }
  }
  // altitude tint: higher ground reads brighter, basin reads darker
  if (e0 >= 2) { ctx.fillStyle = "rgba(255,250,230,0.055)"; ctx.fillRect(px, py, CELL_W, CELL_H); }
  else if (e0 === 0 && t !== "water") { ctx.fillStyle = "rgba(0,20,30,0.05)"; ctx.fillRect(px, py, CELL_W, CELL_H); }
}

/** Baked 16x16-tile chunk canvas of pixel-art terrain (cached). */
export function chunkCanvas(world: World, seed: number, cx: number, cy: number): HTMLCanvasElement {
  const key = cx + "," + cy;
  let cvs = chunkCache.get(key);
  if (cvs) return cvs;
  cvs = document.createElement("canvas");
  cvs.width = CHUNK * CELL_W; cvs.height = CHUNK * CELL_H;
  const ctx = cvs.getContext("2d")!;
  ctx.imageSmoothingEnabled = false;
  ctx.fillStyle = "#2b6fa8";
  ctx.fillRect(0, 0, cvs.width, cvs.height);
  for (let ty = 0; ty < CHUNK; ty++) {
    for (let tx = 0; tx < CHUNK; tx++) {
      drawPixTile(ctx, world, cx * CHUNK + tx, cy * CHUNK + ty, seed, tx * CELL_W, ty * CELL_H);
    }
  }
  chunkCache.set(key, cvs);
  return cvs;
}

export const CHUNK_TILES = CHUNK;
