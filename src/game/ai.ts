// Pal brains: wild wander/flee/aggro, partner follow+combat, base worker jobs.
import { GameState, Pal, BASE_RADIUS } from "./types.ts";
import { SPECIES } from "../data/species.ts";
import { SKILLS } from "../data/skills.ts";
import { World } from "./world.ts";
import { isNight, floater, log, palGrantXp } from "./state.ts";
import { activePartner, castSkill, hasStatus } from "./combat.ts";
import { killPal } from "./entities.ts";
import { bestJobFor, doJobTick, claimJob, unclaimJob, completeJob } from "./jobs.ts";
import { feedStock } from "./structures.ts";
import { ITEMS } from "../data/items.ts";
import { Rng } from "../engine/rng.ts";

const rng = new Rng(12345);

function moveToward(world: World, p: Pal, tx: number, ty: number, speed: number, dt: number): void {
  const dx = tx - p.x, dy = ty - p.y;
  const d = Math.hypot(dx, dy);
  if (d < 0.02) return;
  const sp = SPECIES[p.speciesId];
  let mv = Math.min(speed * dt, d);
  if (hasStatus(p, "freeze", 0) || hasStatus(p, "sleep", 0)) mv = 0;
  if (hasStatus(p, "shock", 0)) mv *= 0.6;
  const nx = p.x + (dx / d) * mv;
  const ny = p.y + (dy / d) * mv;
  p.dir = dx > 0 ? 1 : -1;
  if (!world.blocked(nx, p.y, p.x, p.y)) p.x = nx;
  if (!world.blocked(p.x, ny, p.x, p.y)) p.y = ny;
}

function wander(world: World, p: Pal, dt: number, radius: number): void {
  p.wanderT -= dt;
  if (p.wanderT <= 0) {
    p.wanderT = 1.5 + rng.next() * 3;
    const a = rng.next() * Math.PI * 2;
    const r = rng.next() * radius;
    p.homeX = p.x + Math.cos(a) * r;
    p.homeY = p.y + Math.sin(a) * r;
  }
  const sp = SPECIES[p.speciesId];
  moveToward(world, p, p.homeX, p.homeY, sp.speed * 0.5, dt);
}

function distTo(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function tickStatuses(s: GameState, p: Pal, dt: number): void {
  p.statuses = p.statuses.filter((st) => st.until > s.t);
  for (const st of p.statuses) {
    if (st.kind === "burn" || st.kind === "poison") {
      p.hp -= 1.2 * dt;
      if (p.hp <= 0 && p.mode === "wild") killPal(s, p, true);
    }
  }
  // SAN / hunger
  if (p.mode === "base" && p.jobUid >= 0) {
    p.san = Math.max(0, p.san - dt * 0.25);
    p.hunger = Math.min(100, p.hunger + dt * 0.6);
  } else {
    p.hunger = Math.min(100, p.hunger + dt * 0.15);
  }
}

export function updatePals(s: GameState, world: World, dt: number): void {
  for (const p of [...s.pals]) {
    tickStatuses(s, p, dt);
    p.skillCd = Math.max(0, p.skillCd - dt);
    if (hasStatus(p, "sleep", s.t) || hasStatus(p, "freeze", s.t)) continue;
    if (p.mode === "wild") wildBrain(s, world, p, dt);
    else if (p.mode === "partner") partnerBrain(s, world, p, dt);
    else if (p.mode === "base") baseBrain(s, world, p, dt);
  }
}

// ---------- wild ----------
function wildBrain(s: GameState, world: World, p: Pal, dt: number): void {
  const sp = SPECIES[p.speciesId];
  const pd = distTo(p, s.player);
  const partner = activePartner(s);
  const sleeping = isNight(s) && !sp.night && p.aggroUid < 0;

  if (sleeping) {
    if (rng.chance(dt * 0.5)) return; // mostly idle at night
  }

  // aggro states: aggroUid 0=player, -2=partner, >=0 pal uid
  if (p.aggroUid === 0) {
    // chase and attack player
    if (pd > 9) { p.aggroUid = -1; }
    else if (pd < 7 && (sp.hostile ?? 1) === 0 && p.hp < p.maxHp * 0.5) {
      // timid + hurt → flee
      flee(s, world, p, s.player, dt);
      return;
    }
    wildAttack(s, world, p, s.player, dt, pd, 0);
    return;
  }
  if (p.aggroUid === -2 && partner) {
    const dd = distTo(p, partner);
    if (dd > 10) { p.aggroUid = -1; }
    else wildAttack(s, world, p, partner, dt, dd, partner.uid);
    return;
  }
  if (p.aggroUid >= 1) {
    const t = s.pals.find((o) => o.uid === p.aggroUid);
    if (!t || t.mode === "wild") p.aggroUid = -1;
    else {
      wildAttack(s, world, p, t, dt, distTo(p, t), t.uid);
      return;
    }
    if (p.aggroUid >= 1) p.aggroUid = -1;
  }

  // proximity aggro for aggressive species
  if ((sp.hostile ?? 1) === 2 && pd < 6 && !sleeping) {
    p.aggroUid = 0;
    floater(s, p.x, p.y - 0.9, "!", "#e64533");
    return;
  }

  // timid: flee when player close
  if ((sp.hostile ?? 1) === 0 && pd < 4) {
    flee(s, world, p, s.player, dt);
    return;
  }
  wander(world, p, dt, 6);
}

function flee(s: GameState, world: World, p: Pal, from: { x: number; y: number }, dt: number): void {
  const dx = p.x - from.x, dy = p.y - from.y;
  const d = Math.hypot(dx, dy) || 1;
  moveToward(world, p, p.x + (dx / d) * 5, p.y + (dy / d) * 5, SPECIES[p.speciesId].speed, dt);
}

function wildAttack(s: GameState, world: World, p: Pal, target: { x: number; y: number }, dt: number, d: number, targetUid: number): void {
  const sp = SPECIES[p.speciesId];
  const skills = sp.skills.filter(([lv]) => p.level >= lv).map(([, id]) => SKILLS[id]).filter(Boolean);
  const usable = skills.filter((k) => k.range >= d - 0.5);
  if (p.skillCd <= 0 && usable.length) {
    const sk = usable[Math.floor(rng.next() * usable.length)];
    castSkill(s, p, sk, target.x, target.y, false);
    p.skillCd = sk.cooldown;
    return;
  }
  // approach target (keep at ~2.5 tiles for ranged, melee for tackle)
  const wantD = skills.some((k) => k.range > 3) ? 3.5 : 1.2;
  if (d > wantD) moveToward(world, p, target.x, target.y, sp.speed, dt);
  else if (d < wantD - 1.5) {
    const dx = p.x - target.x, dy = p.y - target.y;
    const dd = Math.hypot(dx, dy) || 1;
    moveToward(world, p, p.x + dx / dd * 2, p.y + dy / dd * 2, sp.speed * 0.7, dt);
  }
}

// ---------- partner ----------
function partnerBrain(s: GameState, world: World, p: Pal, dt: number): void {
  const sp = SPECIES[p.speciesId];
  const pd = distTo(p, s.player);

  // find closest threatening wild pal (aggro'd or nearby aggressive)
  let foe: Pal | null = null;
  let fd = 999;
  for (const q of s.pals) {
    if (q.mode !== "wild" || q.hp <= 0) continue;
    const d = distTo(p, q);
    const qSp = SPECIES[q.speciesId];
    const engage = q.aggroUid >= 0 || q.aggroUid === -2 || ((qSp.hostile ?? 1) >= 1 && d < 5) || distTo(s.player, q) < 6;
    if (engage && d < fd) { fd = d; foe = q; }
  }

  if (foe && fd < 14) {
    // fight: approach to skill range, cast on cooldown
    const skills = sp.skills.filter(([lv]) => p.level >= lv).map(([, id]) => SKILLS[id]).filter((k) => k.power > 0);
    const best = skills.filter((k) => k.range >= fd - 0.5 && k.kind !== "self");
    if (p.skillCd <= 0 && best.length) {
      const sk = best.sort((a, b) => b.power - a.power)[0];
      castSkill(s, p, sk, foe.x, foe.y, true);
      p.skillCd = sk.cooldown;
      palGrantXp(s, p, 2);
      return;
    }
    const wantD = skills.some((k) => k.range > 4) ? 4 : 1.3;
    if (fd > wantD) moveToward(world, p, foe.x, foe.y, sp.speed, dt);
    // heal pulse if it knows it and player is hurt
    const heal = sp.skills.map(([, id]) => SKILLS[id]).find((k) => k.kind === "self" && k.power < 0);
    if (heal && p.skillCd <= 0 && (s.player.hp < s.player.maxHp * 0.5 || p.hp < p.maxHp * 0.4)) {
      castSkill(s, p, heal, p.x, p.y, true);
      p.skillCd = heal.cooldown;
    }
    return;
  }

  // follow player
  if (pd > 2.2) {
    moveToward(world, p, s.player.x, s.player.y, Math.max(sp.speed, 3.4), dt);
  } else {
    wanderAround(world, p, s.player.x, s.player.y, 1.6, dt);
  }
}

function wanderAround(world: World, p: Pal, cx: number, cy: number, r: number, dt: number): void {
  p.wanderT -= dt;
  if (p.wanderT <= 0) {
    p.wanderT = 2 + rng.next() * 2.5;
    const a = rng.next() * Math.PI * 2;
    p.homeX = cx + Math.cos(a) * r;
    p.homeY = cy + Math.sin(a) * r;
  }
  moveToward(world, p, p.homeX, p.homeY, SPECIES[p.speciesId].speed * 0.4, dt);
}

// ---------- base workers ----------
function baseBrain(s: GameState, world: World, p: Pal, dt: number): void {
  const sp = SPECIES[p.speciesId];
  const base = s.baseCenter;
  if (!base) { wander(world, p, dt, 6); return; }

  // sleeping at night or recovering SAN
  const tired = p.san < 18;
  if (isNight(s) || tired) {
    const bed = nearestStructure(s, p, (st) => st.bed === true);
    if (bed) {
      if (distTo(p, bed) > 0.7) moveToward(world, p, bed.x, bed.y, sp.speed * 0.8, dt);
      else {
        p.san = Math.min(sp.san, p.san + dt * 6); // sleep restores SAN fast
        p.hp = Math.min(p.maxHp, p.hp + dt * 4);
      }
    } else {
      // ground-nap: slow recovery
      p.san = Math.min(sp.san, p.san + dt * 2.5);
      wander(world, p, dt, 2);
    }
    if (p.jobUid >= 0) { unclaimJob(s, p.jobUid); p.jobUid = -1; }
    return;
  }

  // hungry: find feed box
  if (p.hunger > 55) {
    const fb = nearestFeedBox(s, p);
    if (fb) {
      if (distTo(p, fb) > 0.8) moveToward(world, p, fb.x, fb.y, sp.speed * 0.9, dt);
      else {
        // consume one food item from the feed box buffer
        const fid = [...fb.buffer.keys()].find((id) => ITEMS[id]?.kind === "food");
        if (fid) {
          fb.buffer.set(fid, (fb.buffer.get(fid) ?? 1) - 1);
          if ((fb.buffer.get(fid) ?? 0) <= 0) fb.buffer.delete(fid);
          p.hunger = Math.max(0, p.hunger - 55);
          p.san = Math.min(sp.san, p.san + 8);
          floater(s, p.x, p.y - 0.8, "yum", "#4caf50");
        }
      }
      return;
    } else if (p.hunger > 85) {
      // starving: SAN drains, slack off
      p.san = Math.max(0, p.san - dt * 1.5);
    }
  }

  // claim or continue a job
  if (p.jobUid < 0) {
    const job = bestJobFor(s, p, base, BASE_RADIUS);
    if (job) claimJob(s, job, p);
    else { wanderAround(world, p, base.x, base.y, 8, dt); return; }
  }
  const job = s.jobs.find((j) => j.uid === p.jobUid);
  if (!job) { p.jobUid = -1; return; }
  if (distTo(p, job) > 1.3) {
    moveToward(world, p, job.x, job.y, sp.speed * 0.9, dt);
  } else {
    doJobTick(s, p, job, dt);
  }
}

interface StructureLike { x: number; y: number; bed?: boolean; feedBox?: boolean; feedStock?: number; buffer: Map<string, number>; defId: string; uid: number }
function nearestStructure(s: GameState, p: Pal, pred: (st: StructureLike) => boolean): StructureLike | null {
  let best: StructureLike | null = null;
  let bd = 999;
  for (const st of s.structures) {
    const sl = st as unknown as StructureLike;
    if (!pred(sl)) continue;
    const d = distTo(p, { x: sl.x + 0.5, y: sl.y + 0.5 });
    if (d < bd) { bd = d; best = sl; }
  }
  return best;
}

function nearestFeedBox(s: GameState, p: Pal): StructureLike | null {
  return nearestStructure(s, p, (st) => st.feedBox === true && feedStock(st as never) > 0);
}
