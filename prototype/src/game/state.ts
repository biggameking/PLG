// Game state construction + shared helpers (inventory, log, xp, spawning).
import { GameState, Pal, Player, statAt, uid, XP_FOR_LEVEL, PAL_XP_FOR_LEVEL, DAY_LEN } from "./types.ts";
import { SPECIES } from "../data/species.ts";
import { World } from "./world.ts";
import { Rng } from "../engine/rng.ts";
import { ITEMS } from "../data/items.ts";

export function newGame(seed: number): GameState {
  const p: Player = {
    x: 0, y: 0,
    hp: 100, maxHp: 100, hunger: 0, stamina: 100,
    level: 1, xp: 0, techPoints: 3, captureLevel: 1,
    facing: 0, attackT: 0, dodgeT: 0,
    inv: new Map(), weapon: null, sphereSel: 0,
    unlocked: new Set(["kinbox", "club", "kin_orb", "straw_bed_placeholder"]),
  };
  p.unlocked.delete("straw_bed_placeholder");
  const s: GameState = {
    t: DAY_LEN * 0.3, day: 1, timeOfDay: 0.3, mode: "play",
    worldSeed: seed, player: p,
    pals: [], party: [], palparty: [], activePal: -1, box: [],
    structures: [], jobs: [], projectiles: [], spheres: [], drops: [], floaters: [],
    log: [], baseCenter: null, nextUid: 1,
    aimSphere: false, craftStation: -1, buildSel: null, buildX: 0, buildY: 0,
    camShake: 0,
  };
  // starter kit
  addItem(s, "wood", 10); addItem(s, "stone", 8); addItem(s, "lumenite", 8);
  addItem(s, "red_berries", 6); addItem(s, "kin_orb", 3); addItem(s, "wooden_club", 1);
  p.weapon = "wooden_club";
  return s;
}

export function log(s: GameState, msg: string): void {
  s.log.push(msg);
  if (s.log.length > 6) s.log.shift();
}

export function addItem(s: GameState, id: string, n: number): void {
  s.player.inv.set(id, (s.player.inv.get(id) ?? 0) + n);
}
export function itemCount(s: GameState, id: string): number {
  return s.player.inv.get(id) ?? 0;
}
export function takeItem(s: GameState, id: string, n: number): boolean {
  const have = itemCount(s, id);
  if (have < n) return false;
  if (have === n) s.player.inv.delete(id); else s.player.inv.set(id, have - n);
  return true;
}
export function canAfford(s: GameState, cost: [string, number][]): boolean {
  return cost.every(([id, n]) => itemCount(s, id) >= n);
}
export function payCost(s: GameState, cost: [string, number][]): boolean {
  if (!canAfford(s, cost)) return false;
  for (const [id, n] of cost) takeItem(s, id, n);
  return true;
}

export function mkPal(s: GameState, speciesId: string, level: number, x: number, y: number, mode: Pal["mode"]): Pal {
  const sp = SPECIES[speciesId];
  const talent = Math.floor(Math.random() * 101);
  const maxHp = statAt(sp.hp, level, talent);
  const p: Pal = {
    uid: uid(s), speciesId, level, xp: 0,
    hp: maxHp, maxHp, talent,
    san: sp.san, hunger: 30,
    statuses: [], mode,
    x, y, homeX: x, homeY: y,
    aggroUid: -1, jobUid: -1, workT: 0,
    carrying: null, wanderT: 0, dir: 1, skillCd: 0,
  };
  if (mode !== "box") s.pals.push(p);
  return p;
}

export function grantXp(s: GameState, n: number): void {
  const p = s.player;
  p.xp += n;
  while (p.xp >= XP_FOR_LEVEL(p.level)) {
    p.xp -= XP_FOR_LEVEL(p.level);
    p.level++;
    p.techPoints += 1;
    p.maxHp += 8;
    p.hp = Math.min(p.maxHp, p.hp + 40);
    if (p.level % 3 === 0) p.captureLevel++;
    log(s, `Level up! You are now level ${p.level} (+1 tech point)`);
    floater(s, p.x, p.y - 1, "LEVEL UP", "#e8d44d");
  }
}

export function palGrantXp(s: GameState, pal: Pal, n: number): void {
  pal.xp += n;
  while (pal.xp >= PAL_XP_FOR_LEVEL(pal.level)) {
    pal.xp -= PAL_XP_FOR_LEVEL(pal.level);
    pal.level++;
    const sp = SPECIES[pal.speciesId];
    pal.maxHp = statAt(sp.hp, pal.level, pal.talent ?? 0);
    pal.hp = pal.maxHp;
    floater(s, pal.x, pal.y - 1, `${sp.name} → Lv${pal.level}`, "#9acd32");
  }
}

export function floater(s: GameState, x: number, y: number, str: string, color: string): void {
  s.floaters.push({ x, y, s: str, color, t: 0 });
  if (s.floaters.length > 40) s.floaters.shift();
}

export function isNight(s: GameState): boolean {
  return s.timeOfDay > 0.62 || s.timeOfDay < 0.18;
}

export function ownedSpheres(s: GameState): string[] {
  const tiers = ["kin_orb", "mega_orb", "giga_orb", "ultra_orb", "legendary_orb"];
  return tiers.filter((id) => itemCount(s, id) > 0);
}

export function rngFromState(s: GameState): Rng {
  return new Rng(Math.floor(s.t * 1000) + s.nextUid * 7919);
}
