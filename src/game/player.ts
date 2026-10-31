// Player movement, actions, harvesting, interactions.
import { GameState, Player, Pal, BASE_RADIUS, statAt, uid } from "./types.ts";
import { ITEMS } from "../data/items.ts";
import { SPECIES } from "../data/species.ts";
import { World, T } from "./world.ts";
import { addItem, takeItem, itemCount, log, floater, isNight, ownedSpheres } from "./state.ts";
import { dropItem } from "./entities.ts";
import { castSkill, throwSphere, catchChance, activePartner, hitPal } from "./combat.ts";
import { SKILLS } from "../data/skills.ts";
import { structureNear, depositFood, depositAll, withdrawAll, feedStock, playerWorkTick } from "./structures.ts";
import { STRUCTURES } from "../data/structures.ts";
import { Input } from "../engine/input.ts";

const PLAYER_SPEED = 4.2;

export function updatePlayer(s: GameState, world: World, input: Input, dt: number, camW: number, camH: number, camX: number, camY: number): void {
  const p = s.player;
  p.attackT = Math.max(0, p.attackT - dt);
  p.dodgeT = Math.max(0, p.dodgeT - dt);

  // movement (WASD / arrows)
  let mx = 0, my = 0;
  if (input.down("w") || input.down("arrowup")) my -= 1;
  if (input.down("s") || input.down("arrowdown")) my += 1;
  if (input.down("a") || input.down("arrowleft")) mx -= 1;
  if (input.down("d") || input.down("arrowright")) mx += 1;
  const sprint = input.down("shift") && p.stamina > 1;
  const speed = PLAYER_SPEED * (sprint ? 1.55 : 1);
  if (mx || my) {
    const d = Math.hypot(mx, my);
    const nx = p.x + (mx / d) * speed * dt;
    const ny = p.y + (my / d) * speed * dt;
    if (!world.blocked(nx, p.y, p.x, p.y)) p.x = nx;
    if (!world.blocked(p.x, ny, p.x, p.y)) p.y = ny;
    p.facing = mx !== 0 ? Math.sign(mx) : p.facing;
    if (sprint) p.stamina = Math.max(0, p.stamina - dt * 12);
  }
  p.stamina = Math.min(100, p.stamina + dt * 9);

  // dodge roll: brief burst + i-frames
  if (input.hit(" ") && p.stamina > 15 && (mx || my)) {
    p.dodgeT = 0.28;
    p.stamina -= 15;
  }
  if (p.dodgeT > 0 && (mx || my)) {
    const d = Math.hypot(mx, my);
    const nx = p.x + (mx / d) * speed * 2.2 * dt;
    const ny = p.y + (my / d) * speed * 2.2 * dt;
    if (!world.blocked(nx, p.y, p.x, p.y)) p.x = nx;
    if (!world.blocked(p.x, ny, p.x, p.y)) p.y = ny;
  }

  // hunger
  p.hunger = Math.min(100, p.hunger + dt * 0.35);
  if (p.hunger >= 99) p.hp = Math.max(1, p.hp - dt * 1.5); // starving drains hp

  // mouse world position
  const mwx = (input.mouse.x + camX) / 16;
  const mwy = (input.mouse.y + camY) / 18;

  // sphere aim mode toggle (Q or right-click equivalent: key '4')
  if (input.hit("q")) s.aimSphere = !s.aimSphere && ownedSpheres(s).length > 0;
  if (input.hit("r")) {
    const tiers = ownedSpheres(s);
    if (tiers.length) p.sphereSel = (p.sphereSel + 1) % tiers.length;
  }

  // throw sphere on click while aiming
  if (s.aimSphere && input.mouse.clicked) {
    const tiers = ownedSpheres(s);
    const sid = tiers[Math.min(p.sphereSel, tiers.length - 1)];
    const target = nearestWild(s, mwx, mwy, 3.5);
    if (sid && target && Math.hypot(target.x - p.x, target.y - p.y) < 10) {
      takeItem(s, sid, 1);
      throwSphere(s, sid, target, target.x, target.y);
    }
  }

  // attack on click (not aiming)
  if (!s.aimSphere && input.mouse.down && p.attackT <= 0) {
    playerAttack(s, world, mwx, mwy);
  }

  // interact
  if (input.hit("e")) interact(s, world, mwx, mwy);
  // hold-to-work on job structures
  if (input.down("e") && !input.hit("e")) {
    const st = structureNear(s, p.x, p.y, 2.2);
    if (st) playerWorkTick(s, st, dt);
  }

  // swap active party pal: keys 1-5
  for (let i = 0; i < 5; i++) {
    if (input.hit(String(i + 1)) && i < s.party.length && i !== s.activePal) {
      const palUid = s.party[i];
      const pal = s.palparty.find((o) => o.uid === palUid) ?? s.pals.find((o) => o.uid === palUid);
      if (!pal) continue;
      const prev = activePartner(s);
      if (prev) {
        prev.mode = "box";
        s.pals = s.pals.filter((o) => o.uid !== prev.uid);
        s.palparty.push(prev);
      }
      s.palparty = s.palparty.filter((o) => o.uid !== pal.uid);
      pal.mode = "partner";
      pal.x = p.x + 0.8; pal.y = p.y + 0.8;
      if (!s.pals.includes(pal)) s.pals.push(pal);
      s.activePal = i;
      log(s, `${SPECIES[pal.speciesId].name} deployed.`);
    }
  }
}

function nearestWild(s: GameState, x: number, y: number, r: number): Pal | null {
  let best: Pal | null = null, bd = 1e9;
  for (const p of s.pals) {
    if (p.mode !== "wild" || p.hp <= 0) continue;
    const d = Math.hypot(p.x - x, p.y - y);
    if (d < r && d < bd) { bd = d; best = p; }
  }
  return best;
}

function playerAttack(s: GameState, world: World, tx: number, ty: number): void {
  const p = s.player;
  const weapon = p.weapon ? ITEMS[p.weapon] : null;
  const w = weapon?.weapon ?? { dmg: 8, range: 1.6, cd: 0.4 };
  p.attackT = w.cd;
  const dx = tx - p.x, dy = ty - p.y;
  const d = Math.hypot(dx, dy) || 1;
  const reach = Math.min(w.range, d);

  // ranged weapons consume ammo → become skill projectiles
  if (w.ammo) {
    if (!takeItem(s, w.ammo, 1)) { log(s, `No ${ITEMS[w.ammo].name} left.`); return; }
    castSkill(s, p, {
      id: "playershot", name: w.ammo, element: "neutral", power: w.dmg, cooldown: w.cd,
      range: w.range, kind: "projectile", projectileSpeed: 16, desc: "",
    }, p.x + dx / d * w.range, p.y + dy / d * w.range, true);
    return;
  }

  // melee sweep at reach point
  const hx = p.x + dx / d * reach, hy = p.y + dy / d * reach;
  let hitAny = false;
  for (const q of [...s.pals]) {
    if (q.mode !== "wild") continue;
    if (Math.hypot(q.x - hx, q.y - hy) < 1.1) {
      const mult = 1;
      const dmg = Math.max(1, Math.round(w.dmg * (0.9 + Math.random() * 0.2)));
      hitPal(s, q, dmg, mult, true);
      hitAny = true;
    }
  }
  // harvest nodes
  const tx0 = Math.floor(hx), ty0 = Math.floor(hy);
  const t = world.get(tx0, ty0);
  if (t === "tree" || t === "rock" || t === "ore") {
    const i = world.idx(tx0, ty0);
    const toolBonus = (p.weapon === "metal_axe" && t === "tree") || (p.weapon === "metal_pickaxe" && (t === "rock" || t === "ore")) ? 2.5 : 1;
    world.hp[i] -= w.dmg * toolBonus;
    hitAny = true;
    if (world.hp[i] <= 0) {
      const [itemId, lo, hi] = t === "tree" ? ["wood", 2, 4] : t === "rock" ? ["stone", 2, 4] : (world.zoneAt(tx0, ty0) >= 1 && Math.random() < 0.6) ? ["ore", 1, 2] : ["paldium", 1, 2];
      const n = lo + Math.floor(Math.random() * (hi - lo + 1));
      dropItem(s, itemId, n, tx0 + 0.5, ty0 + 0.5);
      if (t === "tree" && Math.random() < 0.4) dropItem(s, "fiber", 1 + Math.floor(Math.random() * 2), tx0 + 0.5, ty0 + 0.5);
      world.set(tx0, ty0, t === "tree" ? "grass" : "dirt");
      world.hp[i] = 0;
    }
  }
  if (hitAny) s.camShake = Math.min(s.camShake + 0.08, 0.3);
}

function interact(s: GameState, world: World, mx: number, my: number): void {
  const p = s.player;
  // structure interactions first
  const st = structureNear(s, p.x, p.y, 2.2) ?? structureNear(s, mx, my, 1.5);
  if (st) {
    const def = STRUCTURES[st.defId];
    if (def.anchor) { s.mode = "palbox"; return; }
    if (st.defId === "workbench") { s.mode = "craft"; s.craftStation = st.uid; return; }
    if (def.feedBox) { depositFood(s, st); return; }
    if (def.storage && st.buffer.size) { withdrawAll(s, st); return; }
    if (def.storage) { depositAll(s, st); return; }
    if (def.playerBed) {
      // sleep to morning
      s.timeOfDay = 0.25;
      s.day += s.timeOfDay < 0.25 ? 0 : 0; // day roll handled in main tick
      s.player.hp = s.player.maxHp;
      s.player.hunger = Math.min(100, s.player.hunger + 25);
      log(s, "You slept until morning. HP restored.");
      return;
    }
    // station buffer with items → collect
    if (st.buffer.size) { withdrawAll(s, st); return; }
    return;
  }
  // pick up drops
  const drop = s.drops.find((d) => Math.hypot(d.x - p.x, d.y - p.y) < 1.3);
  if (drop) {
    addItem(s, drop.itemId, drop.count);
    s.drops = s.drops.filter((d) => d.uid !== drop.uid);
    return;
  }
}
