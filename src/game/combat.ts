// Damage model, skill casting, projectiles, statuses.
import { GameState, Pal, Projectile, Player, statAt, uid } from "./types.ts";
import { SPECIES } from "../data/species.ts";
import { SKILLS, SkillDef, StatusKind } from "../data/skills.ts";
import { ITEMS } from "../data/items.ts";
import { effectiveness } from "../data/elements.ts";
import { floater, log, palGrantXp, grantXp } from "./state.ts";
import { killPal } from "./entities.ts";
import { World } from "./world.ts";
import { Rng } from "../engine/rng.ts";

export function damage(attackerAtk: number, power: number, defenderDef: number, elemMult: number, rng: Rng): number {
  // power * (2*atk)/(atk + 2*def) * elem * 0.9..1.1, min 1
  const raw = power * (2 * attackerAtk) / Math.max(1, attackerAtk + 2 * defenderDef);
  return Math.max(1, Math.round(raw * elemMult * (0.9 + rng.next() * 0.2)));
}

export function hasStatus(p: Pal, kind: StatusKind, t: number): boolean {
  return p.statuses.some((s) => s.kind === kind && s.until > t);
}

function addStatus(s: GameState, p: Pal, kind: StatusKind, dur: number): void {
  if (kind === "none") return;
  const ex = p.statuses.find((x) => x.kind === kind);
  if (ex) ex.until = Math.max(ex.until, s.t + dur);
  else p.statuses.push({ kind, until: s.t + dur });
  const label = { burn: "burned", soak: "soaked", shock: "shocked", freeze: "frozen", poison: "poisoned", sleep: "asleep" }[kind];
  floater(s, p.x, p.y - 0.8, label, "#c678dd");
}

export function hitPal(s: GameState, p: Pal, dmg: number, elemMult: number, byPlayer: boolean, status?: { kind: StatusKind; chance: number; dur: number }): void {
  p.hp -= dmg;
  const tag = elemMult >= 2 ? `${dmg}!` : elemMult <= 0.6 ? `${dmg}·` : `${dmg}`;
  floater(s, p.x + (Math.random() - 0.5) * 0.5, p.y - 0.7, tag, elemMult >= 2 ? "#e8d44d" : "#e8f0f2");
  if (status && Math.random() < status.chance) addStatus(s, p, status.kind, status.dur);
  if (p.mode === "wild") {
    // provoke: fight back if aggressive, flee chance if timid
    const sp = SPECIES[p.speciesId];
    if ((sp.hostile ?? 1) === 0 && p.hp > 0 && Math.random() < 0.5) {
      p.aggroUid = -1; // keep fleeing
    } else {
      p.aggroUid = byPlayer ? 0 : -2; // 0 = player, -2 = partner pal (nearest partner)
    }
  }
  if (p.hp <= 0) killPal(s, p, byPlayer);
}

export function activePartner(s: GameState): Pal | null {
  if (s.activePal < 0 || s.activePal >= s.party.length) return null;
  const p = s.pals.find((o) => o.uid === s.party[s.activePal]);
  return p && p.mode === "partner" ? p : null;
}

export function castSkill(s: GameState, caster: Pal | Player, skill: SkillDef, tx: number, ty: number, byPlayer: boolean): void {
  const cx = "inv" in caster ? caster.x : caster.x;
  const cy = caster.y;
  const dx = tx - cx, dy = ty - cy;
  const d = Math.hypot(dx, dy) || 1;
  if (skill.kind === "projectile") {
    const sp = skill.projectileSpeed ?? 10;
    s.projectiles.push({
      uid: uid(s), skillId: skill.id,
      x: cx, y: cy,
      vx: dx / d * sp, vy: dy / d * sp,
      owner: "inv" in caster ? "player" : (caster as Pal).mode === "wild" ? "wild" : "pal",
      ownerUid: "inv" in caster ? 0 : (caster as Pal).uid,
      power: skill.power,
      ttl: skill.range / sp + 0.3,
    });
  } else if (skill.kind === "burst") {
    // radial burst — hit every enemy within range
    applyBurst(s, caster, skill, byPlayer);
  } else if (skill.kind === "lunge") {
    // melee: hit target tile area
    applyLunge(s, caster, skill, tx, ty, byPlayer);
  } else if (skill.kind === "self") {
    // heal allies: partner pal heals player + itself
    if (skill.power < 0) {
      const amt = -skill.power;
      s.player.hp = Math.min(s.player.maxHp, s.player.hp + amt);
      floater(s, s.player.x, s.player.y - 0.8, `+${amt}`, "#4caf50");
      if (!("inv" in caster)) {
        const cp = caster as Pal;
        cp.hp = Math.min(cp.maxHp, cp.hp + amt);
        floater(s, cp.x, cp.y - 0.8, `+${amt}`, "#4caf50");
      }
    }
  }
}

function atkDefOf(caster: Pal | Player): [number, number] {
  if ("inv" in caster) return [30 + caster.level * 4, 0];
  const sp = SPECIES[(caster as Pal).speciesId];
  const lv = (caster as Pal).level;
  return [statAt(sp.atk, lv), statAt(sp.def, lv)];
}

function applyBurst(s: GameState, caster: Pal | Player, skill: SkillDef, byPlayer: boolean): void {
  const rng = new Rng(Math.floor(s.t * 1000) + s.nextUid);
  const [atk] = atkDefOf(caster);
  const cx = caster.x, cy = caster.y;
  for (const p of [...s.pals]) {
    if (p.mode !== "wild") continue;
    if (Math.hypot(p.x - cx, p.y - cy) > skill.range) continue;
    const mult = effectiveness(skill.element, SPECIES[p.speciesId].elements);
    const dmg = damage(atk, skill.power, statAt(SPECIES[p.speciesId].def, p.level), mult, rng);
    hitPal(s, p, dmg, mult, byPlayer, skill.status);
  }
  s.camShake = Math.min(s.camShake + 0.3, 0.6);
}

function applyLunge(s: GameState, caster: Pal | Player, skill: SkillDef, tx: number, ty: number, byPlayer: boolean): void {
  const rng = new Rng(Math.floor(s.t * 1000) + s.nextUid);
  const [atk] = atkDefOf(caster);
  for (const p of [...s.pals]) {
    if (p.mode !== "wild") continue;
    if (Math.hypot(p.x - tx, p.y - ty) > 1.2) continue;
    const mult = effectiveness(skill.element, SPECIES[p.speciesId].elements);
    const dmg = damage(atk, skill.power, statAt(SPECIES[p.speciesId].def, p.level), mult, rng);
    hitPal(s, p, dmg, mult, byPlayer, skill.status);
  }
}

export function updateProjectiles(s: GameState, world: World, dt: number): void {
  const rng = new Rng(Math.floor(s.t * 1000));
  for (const pr of [...s.projectiles]) {
    pr.x += pr.vx * dt;
    pr.y += pr.vy * dt;
    pr.ttl -= dt;
    const skill = SKILLS[pr.skillId];
    let dead = pr.ttl <= 0 || world.blocked(pr.x, pr.y);
    if (!dead) {
      if (pr.owner === "wild") {
        // hits player or partner
        const pl = s.player;
        if (Math.hypot(pl.x - pr.x, pl.y - pr.y) < 0.5 && s.player.dodgeT <= 0) {
          hurtPlayer(s, skill.power, pr.ownerUid);
          dead = true;
        } else {
          const partner = activePartner(s);
          if (partner && Math.hypot(partner.x - pr.x, partner.y - pr.y) < 0.5) {
            const mult = effectiveness(skill.element, SPECIES[partner.speciesId].elements);
            const dmg = damage(statAt(SPECIES[s.pals.find(q=>q.uid===pr.ownerUid)?.speciesId ?? "lamball"].atk, s.pals.find(q=>q.uid===pr.ownerUid)?.level ?? 1), skill.power, statAt(SPECIES[partner.speciesId].def, partner.level), mult, rng);
            hitPal(s, partner, dmg, mult, true, skill.status);
            dead = true;
          }
        }
      } else {
        // player/partner shots hit wild pals
        for (const p of s.pals) {
          if (p.mode !== "wild") continue;
          if (Math.hypot(p.x - pr.x, p.y - pr.y) < 0.55) {
            const ownerAtk = pr.owner === "player" ? 30 + s.player.level * 4 : statAt(SPECIES[s.pals.find(q => q.uid === pr.ownerUid)?.speciesId ?? "lamball"].atk, s.pals.find(q => q.uid === pr.ownerUid)?.level ?? 1);
            const mult = effectiveness(skill.element, SPECIES[p.speciesId].elements);
            const dmg = damage(ownerAtk, skill.power, statAt(SPECIES[p.speciesId].def, p.level), mult, rng);
            hitPal(s, p, dmg, mult, true, skill.status);
            dead = true;
            break;
          }
        }
      }
    }
    if (dead) s.projectiles = s.projectiles.filter((o) => o.uid !== pr.uid);
  }
}

export function hurtPlayer(s: GameState, power: number, fromUid: number): void {
  const attacker = s.pals.find((p) => p.uid === fromUid);
  const atk = attacker ? statAt(SPECIES[attacker.speciesId].atk, attacker.level) : 20;
  const rng = new Rng(Math.floor(s.t * 1000) + fromUid);
  const def = 20 + s.player.level * 3;
  const dmg = Math.max(1, Math.round(power * (2 * atk) / Math.max(1, atk + 2 * def) * (0.9 + rng.next() * 0.2)));
  s.player.hp -= dmg;
  floater(s, s.player.x, s.player.y - 0.8, `-${dmg}`, "#e64533");
  s.camShake = Math.min(s.camShake + 0.2, 0.5);
  if (s.player.hp <= 0) {
    s.player.hp = 0;
    s.mode = "dead";
    log(s, "You were knocked out...");
  }
}

// ---- capture ----

export interface CaptureInfo {
  chance: number;
  sphereId: string;
}

export function catchChance(s: GameState, p: Pal, spherePower: number, behind: boolean): number {
  const sp = SPECIES[p.speciesId];
  const hpFrac = Math.max(0, p.hp) / p.maxHp;
  const hpFactor = 1.8 - 1.3 * hpFrac; // low HP → up to 1.8x
  const statusBonus = p.statuses.length > 0 ? 1.2 : 1;
  const backBonus = behind ? 1.15 : 1;
  const capLv = 1 + 0.04 * (s.player.captureLevel - 1);
  const raw = (spherePower * hpFactor * statusBonus * backBonus * capLv) / (sp.capturePower * 1.6);
  return Math.max(0.03, Math.min(0.97, raw));
}

export function throwSphere(s: GameState, sphereId: string, target: Pal, tx: number, ty: number): void {
  const behind = isBehind(s, target);
  s.spheres.push({
    uid: uid(s), itemId: sphereId,
    x: s.player.x, y: s.player.y, tx, ty,
    targetUid: target.uid, t: 0,
  });
}

function isBehind(s: GameState, p: Pal): boolean {
  // "behind" = pal's facing dir points away from player
  const dx = s.player.x - p.x, dy = s.player.y - p.y;
  const d = Math.hypot(dx, dy) || 1;
  return (dx / d) * p.dir < -0.3;
}

export function updateSpheres(s: GameState, dt: number): void {
  for (const sp of [...s.spheres]) {
    sp.t += dt;
    // fly toward target over ~0.25s
    const k = Math.min(1, sp.t / 0.25);
    sp.x = sp.x + (sp.tx - sp.x) * k * 0.4;
    sp.y = sp.y + (sp.ty - sp.y) * k * 0.4;
    if (sp.t < 0.45) continue;
    const target = s.pals.find((p) => p.uid === sp.targetUid);
    s.spheres = s.spheres.filter((o) => o.uid !== sp.uid);
    if (!target || target.mode !== "wild" || target.hp <= 0) continue;
    const chance = catchChance(s, target, ITEMS[sp.itemId].spherePower ?? 26, isBehind(s, target));
    resolveCapture(s, target, chance);
  }
}

function resolveCapture(s: GameState, target: Pal, chance: number): void {
  const roll = Math.random();
  if (roll < chance) {
    // captured!
    const sp = SPECIES[target.speciesId];
    s.pals = s.pals.filter((o) => o.uid !== target.uid);
    target.hp = Math.max(target.hp, 1);
    target.statuses = [];
    target.aggroUid = -1; target.jobUid = -1;
    if (s.party.length < 5) {
      target.hp = Math.max(1, Math.floor(target.maxHp * 0.5));
      s.party.push(target.uid);
      if (s.activePal === -1) {
        target.mode = "partner";
        s.pals.push(target);
        s.activePal = 0;
      } else {
        target.mode = "box";
        s.palparty.push(target);
      }
      log(s, `Caught ${sp.name} Lv${target.level}! Added to party.`);
    } else {
      target.mode = "box";
      s.box.push(target);
      log(s, `Caught ${sp.name} Lv${target.level}! Sent to Palbox.`);
    }
    const xp = Math.floor((8 + target.level * 4) * 1.5);
    grantXp(s, xp);
    floater(s, target.x, target.y - 0.9, "★ CAUGHT!", "#4dd0e1");
  } else {
    const sp = SPECIES[target.speciesId];
    floater(s, target.x, target.y - 0.9, "…broke free", "#e8963c");
    log(s, `${sp.name} broke free (${Math.round(chance * 100)}%)`);
    // alert: it flees or aggros
    const spc = SPECIES[target.speciesId];
    target.aggroUid = (spc.hostile ?? 1) >= 1 ? 0 : -1;
  }
}
