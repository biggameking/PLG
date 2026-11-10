// Wild pal population, drops, deaths.
import { GameState, Pal } from "./types.ts";
import { SPECIES } from "../data/species.ts";
import { Rng } from "../engine/rng.ts";
import { mkPal, isNight, log, floater, grantXp } from "./state.ts";
import { uid } from "./types.ts";
import { World } from "./world.ts";

const ZONE_LEVELS: [number, number][] = [[1, 5], [4, 10], [9, 16], [14, 22]];
const MAX_WILD = 22;
const DESPAWN_R = 95;
const SPAWN_R_MIN = 45, SPAWN_R_MAX = 80;

const ZONE_SPECIES: string[][] = [
  ["fenjelly", "puffmite", "fenlump", "sprigmelt", "cindlump", "nibjelly", "fenlump"],
  ["briargoo", "voltgoo", "faradlump", "loammelt", "quackbill", "fenjelly", "dozantler", "shademite"],
  ["loampuff", "shademite", "shadelump", "loammelt", "dozantler", "piplump", "shademelt"],
  ["marlump", "loampuff", "shademelt", "piplump", "shadelump", "loammelt"],
];

export function wildPals(s: GameState): Pal[] {
  return s.pals.filter((p) => p.mode === "wild");
}

export function updateSpawns(s: GameState, world: World, dt: number): void {
  const rng = new Rng(Math.floor(s.t * 977) + 13);
  const px = s.player.x, py = s.player.y;
  s.pals = s.pals.filter((p) => {
    if (p.mode !== "wild") return true;
    return Math.hypot(p.x - px, p.y - py) < DESPAWN_R;
  });
  if (wildPals(s).length >= MAX_WILD) return;
  if (!rng.chance(dt * 0.9)) return;

  for (let tries = 0; tries < 12; tries++) {
    const ang = rng.next() * Math.PI * 2;
    const r = SPAWN_R_MIN + rng.next() * (SPAWN_R_MAX - SPAWN_R_MIN);
    const x = Math.floor(px + Math.cos(ang) * r);
    const y = Math.floor(py + Math.sin(ang) * r);
    if (!world.inBounds(x, y) || world.blocked(x, y)) continue;
    const zone = world.zoneAt(x, y);
    let table = ZONE_SPECIES[zone];
    const filtered = table.filter((id) => isNight(s) ? true : !SPECIES[id].night);
    table = filtered.length ? filtered : table;
    const id = table[Math.floor(rng.next() * table.length)];
    const [lo, hi] = ZONE_LEVELS[zone];
    mkPal(s, id, lo + Math.floor(rng.next() * (hi - lo + 1)), x + 0.5, y + 0.5, "wild");
    break;
  }
}

export function dropItem(s: GameState, itemId: string, count: number, x: number, y: number): void {
  const rng = new Rng(Math.floor(s.t * 1000) + count * 31 + s.nextUid);
  s.drops.push({
    uid: uid(s), itemId, count,
    x: x + (rng.next() - 0.5) * 0.8,
    y: y + (rng.next() - 0.5) * 0.8,
    t: 0,
  });
}

export function killPal(s: GameState, p: Pal, byPlayer: boolean): void {
  const sp = SPECIES[p.speciesId];
  floater(s, p.x, p.y, "✕", "#e64533");
  s.camShake = Math.min(s.camShake + 0.15, 0.5);
  if (byPlayer) {
    const rng = new Rng(p.uid * 31 + Math.floor(s.t));
    for (const [itemId, lo, hi] of sp.drops) {
      const n = lo + Math.floor(rng.next() * (hi - lo + 1));
      if (n > 0) dropItem(s, itemId, n, p.x, p.y);
    }
    const xp = 8 + p.level * 4;
    grantXp(s, xp);
    log(s, `${sp.name} was defeated (+${xp} xp)`);
  }
  s.pals = s.pals.filter((o) => o.uid !== p.uid);
}
