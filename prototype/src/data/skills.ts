// Combat skills (moves). Each pal species learns a few; partner pals auto-cast.
import { Element } from "./elements.ts";

export interface SkillDef {
  id: string;
  name: string;
  element: Element;
  power: number;
  cooldown: number; // seconds
  range: number;    // tiles
  kind: "projectile" | "burst" | "self" | "lunge" | "multi";
  projectileSpeed?: number; // tiles/sec
  pierce?: boolean;  // bolt runs the whole line, one wound per body
  drain?: number;    // fraction of dealt damage refunded as hp
  shots?: number;    // multi: bolts in the fan
  spread_deg?: number; // multi: degrees between fan bolts
  status?: { kind: StatusKind; chance: number; dur: number };
  desc: string;
}

export type StatusKind = "burn" | "soak" | "shock" | "freeze" | "poison" | "sleep" | "none";

export const SKILLS: Record<string, SkillDef> = {
  tackle: { id: "tackle", name: "Tackle", element: "neutral", power: 12, cooldown: 1.1, range: 1.4, kind: "lunge", desc: "Slam into the foe." },
  airCannon: { id: "airCannon", name: "Air Cannon", element: "neutral", power: 25, cooldown: 2.5, range: 9, kind: "projectile", projectileSpeed: 14, desc: "Compressed air shot." },
  sandBlast: { id: "sandBlast", name: "Sand Blast", element: "ground", power: 22, cooldown: 2.2, range: 7, kind: "projectile", projectileSpeed: 12, desc: "Hurls wet sand." },
  stoneShot: { id: "stoneShot", name: "Stone Shot", element: "ground", power: 34, cooldown: 3.5, range: 8, kind: "projectile", projectileSpeed: 11, desc: "Fires a dense rock." },
  flameBurst: { id: "flameBurst", name: "Flame Burst", element: "fire", power: 28, cooldown: 3.0, range: 6, kind: "projectile", projectileSpeed: 11, status: { kind: "burn", chance: 0.35, dur: 4 }, desc: "Fireball that can burn." },
  ignitionBreath: { id: "ignitionBreath", name: "Ignis Breath", element: "fire", power: 40, cooldown: 6.0, range: 5, kind: "burst", status: { kind: "burn", chance: 0.5, dur: 5 }, desc: "Cone of flame." },
  hydroJet: { id: "hydroJet", name: "Hydro Jet", element: "water", power: 26, cooldown: 2.6, range: 8, kind: "projectile", projectileSpeed: 13, status: { kind: "soak", chance: 0.3, dur: 5 }, desc: "High-pressure water." },
  aquaBurst: { id: "aquaBurst", name: "Aqua Burst", element: "water", power: 38, cooldown: 5.5, range: 6, kind: "projectile", projectileSpeed: 10, status: { kind: "soak", chance: 0.5, dur: 6 }, desc: "Exploding water orb." },
  seedMachine: { id: "seedMachine", name: "Seed Machine Gun", element: "grass", power: 18, cooldown: 1.8, range: 8, kind: "projectile", projectileSpeed: 15, desc: "Rapid seed volley." },
  grassTornado: { id: "grassTornado", name: "Grass Tornado", element: "grass", power: 42, cooldown: 6.5, range: 5, kind: "burst", desc: "Spinning leaf storm." },
  shockwave: { id: "shockwave", name: "Shockwave", element: "electric", power: 24, cooldown: 2.4, range: 7, kind: "projectile", projectileSpeed: 16, status: { kind: "shock", chance: 0.3, dur: 3 }, desc: "Fast electric bolt." },
  lightningStrike: { id: "lightningStrike", name: "Lightning Strike", element: "electric", power: 48, cooldown: 7.0, range: 8, kind: "burst", status: { kind: "shock", chance: 0.5, dur: 3 }, desc: "Calls down a bolt." },
  iceMissile: { id: "iceMissile", name: "Ice Missile", element: "ice", power: 30, cooldown: 3.2, range: 9, kind: "projectile", projectileSpeed: 12, status: { kind: "freeze", chance: 0.35, dur: 3 }, desc: "Homing shard of ice." },
  blizzard: { id: "blizzard", name: "Blizzard Spike", element: "ice", power: 45, cooldown: 7.0, range: 6, kind: "burst", status: { kind: "freeze", chance: 0.4, dur: 4 }, desc: "Freezing wind burst." },
  darkBall: { id: "darkBall", name: "Dark Ball", element: "dark", power: 32, cooldown: 3.4, range: 8, kind: "projectile", projectileSpeed: 10, status: { kind: "poison", chance: 0.3, dur: 6 }, desc: "Ball of darkness." },
  nightmare: { id: "nightmare", name: "Nightmare Burst", element: "dark", power: 46, cooldown: 7.5, range: 6, kind: "burst", status: { kind: "sleep", chance: 0.35, dur: 4 }, desc: "Wave of dark energy." },
  dragonBurst: { id: "dragonBurst", name: "Dragon Burst", element: "dragon", power: 44, cooldown: 6.0, range: 8, kind: "projectile", projectileSpeed: 12, desc: "Draconic energy orb." },
  dragonCanon: { id: "dragonCanon", name: "Dragon Cannon", element: "dragon", power: 60, cooldown: 9.0, range: 7, kind: "burst", desc: "Massive dragon blast." },
  healingBreeze: { id: "healingBreeze", name: "Healing Breeze", element: "grass", power: -30, cooldown: 8.0, range: 6, kind: "self", desc: "Heal allies around." },
  packVolley: { id: "packVolley", name: "Pack Volley", element: "neutral", power: 9, cooldown: 2.6, range: 8, kind: "multi", shots: 3, spread_deg: 16, projectileSpeed: 13, desc: "Fan of three shots." },
  sporeFan: { id: "sporeFan", name: "Spore Fan", element: "grass", power: 8, cooldown: 2.8, range: 7, kind: "multi", shots: 3, spread_deg: 18, projectileSpeed: 12, status: { kind: "poison", chance: 0.3, dur: 4 }, desc: "Wide cone of spores." },
  arcLance: { id: "arcLance", name: "Arc Lance", element: "electric", power: 30, cooldown: 3.4, range: 10, kind: "projectile", pierce: true, projectileSpeed: 15, desc: "Bolt that runs foes through." },
  glacierPike: { id: "glacierPike", name: "Glacier Pike", element: "ice", power: 26, cooldown: 3.2, range: 9, kind: "projectile", pierce: true, projectileSpeed: 13, status: { kind: "freeze", chance: 0.25, dur: 2 }, desc: "Ice spike skewering the line." },
  wyrmLance: { id: "wyrmLance", name: "Wyrm Lance", element: "dragon", power: 38, cooldown: 4.2, range: 11, kind: "projectile", pierce: true, projectileSpeed: 14, desc: "Dragonfire that does not stop." },
  soulSiphon: { id: "soulSiphon", name: "Soul Siphon", element: "dark", power: 22, cooldown: 2.8, range: 1.6, kind: "lunge", drain: 0.5, desc: "Bite that feeds the biter." },
  undertowPull: { id: "undertowPull", name: "Undertow Pull", element: "water", power: 20, cooldown: 3.0, range: 8, kind: "projectile", drain: 0.4, projectileSpeed: 12, desc: "The tide takes what it gives." },
  cinderFeast: { id: "cinderFeast", name: "Cinder Feast", element: "fire", power: 18, cooldown: 4.0, range: 3.5, kind: "burst", drain: 0.3, status: { kind: "burn", chance: 0.25, dur: 3 }, desc: "Eats the heat off the room." },
  faultPike: { id: "faultPike", name: "Fault Pike", element: "ground", power: 28, cooldown: 3.0, range: 8, kind: "projectile", pierce: true, projectileSpeed: 11, desc: "A stone seam through the pack." },
};
