// Shared game types.
import { SPECIES, Species } from "../data/species.ts";
import { Work } from "../data/work.ts";
import { StatusKind } from "../data/skills.ts";

export const WORLD_W = 220;
export const WORLD_H = 220;
export const BASE_RADIUS = 22;
export const DAY_LEN = 480; // seconds per full day cycle

export interface Vec { x: number; y: number }

export interface StatusFx {
  kind: StatusKind;
  until: number; // game-time seconds when it expires
}

export interface Pal {
  uid: number;
  speciesId: string;
  level: number;
  xp: number;
  hp: number;
  maxHp: number;
  san: number;
  hunger: number;   // 0..100, 100 = starving
  statuses: StatusFx[];
  mode: "wild" | "partner" | "base" | "box";
  x: number; y: number;
  homeX: number; homeY: number;
  aggroUid: number; // uid of entity it's attacking (-1 none)
  jobUid: number;   // claimed job instance id (-1 none)
  workT: number;    // seconds spent on current job step
  carrying: [string, number] | null;
  wanderT: number;
  dir: number;      // facing for glyph flip
  skillCd: number;
  mount?: boolean;
}

export function species(p: Pal): Species {
  return SPECIES[p.speciesId];
}

export interface Projectile {
  uid: number;
  skillId: string;
  x: number; y: number;
  vx: number; vy: number;
  owner: "player" | "pal" | "wild";
  ownerUid: number;
  power: number;
  ttl: number;
}

export interface ItemDrop {
  uid: number;
  itemId: string;
  count: number;
  x: number; y: number;
  t: number; // age
}

export interface Sphere {
  uid: number;
  itemId: string;
  x: number; y: number;
  tx: number; ty: number; // target pal position
  targetUid: number;
  t: number;
}

export interface Job {
  uid: number;
  kind: string;
  structureUid: number;
  workType: Work;
  x: number; y: number;
  amount: number;  // work points needed
  progress: number;
  claimedBy: number; // pal uid or -1
  payload?: string;  // recipe id / item id context
}

export interface Structure {
  uid: number;
  defId: string;
  x: number; y: number; // top-left tile
  farm?: { stage: "empty" | "growing" | "ready"; growth: number; water: number };
  buffer: Map<string, number>; // produced output awaiting transport / stored items
  craftQueue: string[];        // recipe ids queued (workbench) — stores recipe id
  craftProgress: number;
  charge: number;              // generator stored charge
}

export interface Player {
  x: number; y: number;
  hp: number; maxHp: number;
  hunger: number;
  stamina: number;
  level: number; xp: number;
  techPoints: number;
  captureLevel: number; // capture-power bonus level (stat of pal efficacy)
  facing: number;
  attackT: number;
  dodgeT: number;
  inv: Map<string, number>;
  weapon: string | null;
  sphereSel: number; // index into owned sphere tiers for throwing
  unlocked: Set<string>;
}

export type GameMode = "play" | "build" | "inv" | "palbox" | "tech" | "craft" | "help" | "dead";

export interface FloatingText { x: number; y: number; s: string; color: string; t: number }

export interface GameState {
  t: number;           // seconds elapsed
  day: number;
  timeOfDay: number;   // 0..1
  mode: GameMode;
  worldSeed: number;
  player: Player;
  pals: Pal[];         // entities in world (wild, partner, base)
  party: number[];     // pal uids in party (max 5)
  palparty: Pal[];     // party pals currently in their ball (not deployed)
  activePal: number;   // index into party of deployed partner (-1 none)
  box: Pal[];          // palbox storage (not entities)
  structures: Structure[];
  jobs: Job[];
  projectiles: Projectile[];
  spheres: Sphere[];
  drops: ItemDrop[];
  floaters: FloatingText[];
  log: string[];       // message log (bottom-left)
  baseCenter: { x: number; y: number } | null;
  nextUid: number;
  aimSphere: boolean;
  craftStation: number; // structure uid open in craft UI (-1 none)
  buildSel: string | null; // structure id being placed
  buildX: number; buildY: number;
  camShake: number;
}

export const XP_FOR_LEVEL = (lv: number) => 20 + lv * lv * 12;
export const PAL_XP_FOR_LEVEL = (lv: number) => 15 + lv * lv * 10;

export function statAt(base: number, level: number): number {
  return Math.floor(base * (1 + (level - 1) * 0.08));
}

export function uid(s: GameState): number {
  return s.nextUid++;
}
