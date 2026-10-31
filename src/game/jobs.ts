// Job board: structures emit jobs; base pals claim and work them;
// transporters haul produce to chests / food to the feed box.
import { GameState, Pal, Job, Structure, BASE_RADIUS, uid } from "./types.ts";
import { STRUCTURES } from "../data/structures.ts";
import { ITEMS } from "../data/items.ts";
import { workRate, WORK_LABEL } from "../data/work.ts";
import { SPECIES } from "../data/species.ts";
import { floater, log, rngFromState } from "./state.ts";
import { World } from "./world.ts";

// ---------- shared storage network (chests) ----------
export function storageStructures(s: GameState): Structure[] {
  return s.structures.filter((st) => STRUCTURES[st.defId].storage && !STRUCTURES[st.defId].feedBox);
}
export function feedBoxes(s: GameState): Structure[] {
  return s.structures.filter((st) => STRUCTURES[st.defId].feedBox);
}
export function storageHas(s: GameState, itemId: string, n: number): boolean {
  let total = 0;
  for (const st of s.structures) {
    total += st.buffer.get(itemId) ?? 0;
    if (total >= n) return true;
  }
  return false;
}
export function storageTake(s: GameState, itemId: string, n: number): boolean {
  if (!storageHas(s, itemId, n)) return false;
  let left = n;
  for (const st of s.structures) {
    if (left <= 0) break;
    const have = st.buffer.get(itemId) ?? 0;
    const take = Math.min(have, left);
    if (take > 0) {
      st.buffer.set(itemId, have - take);
      if (st.buffer.get(itemId) === 0) st.buffer.delete(itemId);
      left -= take;
    }
  }
  return true;
}
export function storageAdd(st: Structure, itemId: string, n: number): void {
  st.buffer.set(itemId, (st.buffer.get(itemId) ?? 0) + n);
}

function stationSpeed(s: GameState, st: Structure): number {
  // powered by a charged generator within base → 1.5x
  const gen = s.structures.find((g) => g.defId === "generator" && g.charge > 0);
  return gen ? 1.5 : 1;
}

// ---------- job generation ----------
// Called each frame: emit jobs for structures that need them.
export function refreshJobs(s: GameState, world: World, dt: number): void {
  for (const st of s.structures) {
    const def = STRUCTURES[st.defId];
    const cx = st.x + def.w / 2, cy = st.y + def.h / 2;

    // continuous work stations
    if (def.job && def.job.kind !== "workbench") {
      const existing = s.jobs.find((j) => j.structureUid === st.uid && j.kind === def.job!.kind);
      if (!existing) {
        const hasInputs = !def.job.consumes || def.job.consumes.every(([id, n]) => storageHas(s, id, n));
        if (hasInputs) {
          s.jobs.push({
            uid: uid(s), kind: def.job.kind, structureUid: st.uid,
            workType: def.job.workType, x: cx, y: cy,
            amount: def.job.amount, progress: 0, claimedBy: -1,
          });
        }
      }
    }

    // farm field stages
    if (def.farmField) {
      st.farm = st.farm ?? { stage: "empty", growth: 0, water: 0 };
      const f = st.farm;
      if (f.stage === "empty" && !s.jobs.some((j) => j.structureUid === st.uid && j.kind === "plant")) {
        const seed = st.defId === "berry_farm" ? "berry_seeds" : "wheat_seeds";
        if (storageHas(s, seed, 1)) {
          s.jobs.push({ uid: uid(s), kind: "plant", structureUid: st.uid, workType: "planting", x: cx, y: cy, amount: 40, progress: 0, claimedBy: -1 });
        }
      } else if (f.stage === "growing") {
        f.water = Math.max(0, f.water - dt / 90); // dries out over ~90s
        if (f.water < 0.4 && !s.jobs.some((j) => j.structureUid === st.uid && j.kind === "water")) {
          s.jobs.push({ uid: uid(s), kind: "water", structureUid: st.uid, workType: "watering", x: cx, y: cy, amount: 30, progress: 0, claimedBy: -1 });
        }
        if (f.water > 0) f.growth = Math.min(1, f.growth + dt / 180); // ~3min to mature
        if (f.growth >= 1) {
          f.stage = "ready";
          s.jobs.push({ uid: uid(s), kind: "harvest", structureUid: st.uid, workType: "gathering", x: cx, y: cy, amount: 45, progress: 0, claimedBy: -1 });
        }
      }
    }

    // ranch: one steady job
    if (def.ranch && !s.jobs.some((j) => j.structureUid === st.uid)) {
      s.jobs.push({ uid: uid(s), kind: "ranch", structureUid: st.uid, workType: "farming", x: cx, y: cy, amount: 99999, progress: 0, claimedBy: -1 });
    }

    // transport: for each structure buffer holding produce, emit transport jobs
    for (const [itemId, n] of st.buffer) {
      if (n <= 0) continue;
      const isFood = ITEMS[itemId]?.kind === "food";
      const target = isFood ? feedBoxes(s)[0] : storageStructures(s)[0];
      if (!target) continue;
      if (st === target) continue;
      if (s.jobs.some((j) => j.kind === "transport" && j.structureUid === st.uid && j.payload === itemId)) continue;
      s.jobs.push({
        uid: uid(s), kind: "transport", structureUid: st.uid, workType: "transporting",
        x: cx, y: cy, amount: 1, progress: 0, claimedBy: -1, payload: itemId,
      });
    }
  }
}

// ---------- assignment ----------
export function bestJobFor(s: GameState, p: Pal, base: { x: number; y: number }, radius: number): Job | null {
  const sp = SPECIES[p.speciesId];
  let best: Job | null = null;
  let bestScore = -1;
  for (const j of s.jobs) {
    if (j.claimedBy !== -1) continue;
    const lvl = sp.work[j.workType] ?? 0;
    if (lvl <= 0) continue;
    const d = Math.hypot(j.x - base.x, j.y - base.y);
    if (d > radius) continue;
    const score = lvl * 100 - d;
    if (score > bestScore) { bestScore = score; best = j; }
  }
  return best;
}

export function claimJob(s: GameState, j: Job, p: Pal): void {
  j.claimedBy = p.uid;
  p.jobUid = j.uid;
  p.workT = 0;
}

export function unclaimJob(s: GameState, jobUid: number): void {
  const j = s.jobs.find((o) => o.uid === jobUid);
  if (j) j.claimedBy = -1;
}

export function removeJob(s: GameState, j: Job): void {
  const claimer = s.pals.find((p) => p.uid === j.claimedBy);
  if (claimer) claimer.jobUid = -1;
  s.jobs = s.jobs.filter((o) => o.uid !== j.uid);
}

// forward declaration for structures.ts
export function completeJob(s: GameState, j: Job, p?: Pal): void {
  const st = s.structures.find((o) => o.uid === j.structureUid);
  if (!st) { removeJob(s, j); return; }
  const def = STRUCTURES[st.defId];
  const rng = rngFromState(s);

  switch (j.kind) {
    case "lumber":
    case "mine":
    case "crush":
    case "smelt":
    case "power": {
      if (def.job?.consumes && !storageTake(s, def.job.consumes[0][0], def.job.consumes[0][1])) {
        removeJob(s, j);
        return;
      }
      for (const [id, n] of def.job?.produces ?? []) storageAdd(st, id, n);
      j.progress = 0; // loop job
      if (j.kind === "power") st.charge = Math.min(100, st.charge + 15);
      return;
    }
    case "ranch": {
      // handled continuously in doJobTick; never completes normally
      j.progress = 0;
      return;
    }
    case "plant": {
      const seed = st.defId === "berry_farm" ? "berry_seeds" : "wheat_seeds";
      if (storageTake(s, seed, 1) && st.farm) {
        st.farm.stage = "growing"; st.farm.growth = 0.05; st.farm.water = 0.6;
      }
      removeJob(s, j); return;
    }
    case "water": {
      if (st.farm) st.farm.water = Math.min(1, st.farm.water + 0.7);
      removeJob(s, j); return;
    }
    case "harvest": {
      if (st.farm) {
        st.farm.stage = "empty"; st.farm.growth = 0;
        const out = st.defId === "berry_farm" ? ["red_berries", 5] : ["wheat", 4];
        storageAdd(st, out[0] as string, out[1] as number);
        if (rng.chance(0.6)) {
          const seed = st.defId === "berry_farm" ? "berry_seeds" : "wheat_seeds";
          storageAdd(st, seed, 1); // partial seed return
        }
      }
      removeJob(s, j); return;
    }
    case "workbench": {
      // completes via craftProgress in structures.ts
      removeJob(s, j); return;
    }
    case "transport": {
      if (p && p.carrying) {
        const [id, n] = p.carrying;
        const isFood = ITEMS[id]?.kind === "food";
        const target = isFood ? feedBoxes(s)[0] : storageStructures(s)[0];
        if (target) storageAdd(target, id, n);
        p.carrying = null;
      }
      removeJob(s, j); return;
    }
    default:
      removeJob(s, j);
  }
}

// One work-tick by pal p on job j (called when pal is at the job).
export function doJobTick(s: GameState, p: Pal, j: Job, dt: number): void {
  const sp = SPECIES[p.speciesId];
  const st = s.structures.find((o) => o.uid === j.structureUid);
  const mult = st ? stationSpeed(s, st) : 1;
  const rate = workRate(sp.work[j.workType] ?? 1) * mult;

  if (j.kind === "transport") {
    // pick up stack at structure, carry to destination
    if (!p.carrying && st) {
      const id = j.payload!;
      const n = st.buffer.get(id) ?? 0;
      if (n <= 0) { removeJob(s, j); return; }
      const take = Math.min(n, 10);
      st.buffer.set(id, n - take);
      if (st.buffer.get(id) === 0) st.buffer.delete(id);
      p.carrying = [id, take];
    }
    // walking handled by ai.ts (job.x/y redirects to target after pickup)
    const isFood = p.carrying ? ITEMS[p.carrying[0]]?.kind === "food" : false;
    const target = isFood ? feedBoxes(s)[0] : storageStructures(s)[0];
    if (!target) { removeJob(s, j); return; }
    const tdef = STRUCTURES[target.defId];
    j.x = target.x + tdef.w / 2; j.y = target.y + tdef.h / 2;
    const d = Math.hypot(p.x - j.x, p.y - j.y);
    if (d < 1.4 && p.carrying) completeJob(s, j, p);
    return;
  }

  if (j.kind === "ranch") {
    // grazing: accumulate; every `per` work-points drop produce
    p.workT += rate * dt;
    const farm = SPECIES[p.speciesId].farm;
    if (farm && p.workT >= farm.per) {
      p.workT = 0;
      if (st) storageAdd(st, farm.item, 1);
      floater(s, p.x, p.y - 0.8, "+1 " + farm.item, "#9acd32");
    }
    return;
  }

  j.progress += rate * dt;
  if (st && j.kind === "workbench") st.craftProgress = j.progress;
  if (j.progress >= j.amount) completeJob(s, j, p);
}
