// Structure placement + interactions (build, harvest stations, chests, beds, kinbox).
import { GameState, Structure, BASE_RADIUS, WORLD_W, WORLD_H, uid } from "./types.ts";
import { STRUCTURES } from "../data/structures.ts";
import { ITEMS, RECIPES, Recipe } from "../data/items.ts";
import { World, T } from "./world.ts";
import { canAfford, payCost, addItem, itemCount, takeItem, log, floater } from "./state.ts";
import { storageStructures, feedBoxes, storageAdd, completeJob } from "./jobs.ts";

export function placeStructure(s: GameState, world: World, defId: string, x: number, y: number): boolean {
  const def = STRUCTURES[defId];
  if (!def) return false;
  if (def.anchor && s.structures.some((st) => st.defId === "kinbox")) {
    log(s, "You already have a Kinbox.");
    return false;
  }
  if (!payCost(s, def.cost)) {
    log(s, "Not enough materials.");
    return false;
  }
  const st: Structure = {
    uid: uid(s), defId, x, y,
    buffer: new Map(), craftQueue: [], craftProgress: 0, charge: 0,
    farm: def.farmField ? { stage: "empty", growth: 0, water: 0 } : undefined,
  };
  s.structures.push(st);
  for (let ty = y; ty < y + def.h; ty++)
    for (let tx = x; tx < x + def.w; tx++)
      world.structures.add(world.idx(tx, ty));
  if (def.anchor) {
    s.baseCenter = { x: x + 1, y: y + 1 };
    log(s, "Kinbox established! This is now your base.");
  }
  log(s, `Built ${def.name}.`);
  return true;
}

export function canPlaceAt(world: World, defId: string, x: number, y: number): boolean {
  const def = STRUCTURES[defId];
  if (!world.flatAt(x, y, def.w, def.h)) return false; // no building across cliff edges
  for (let ty = y; ty < y + def.h; ty++) {
    for (let tx = x; tx < x + def.w; tx++) {
      if (!world.inBounds(tx, ty) || world.blocked(tx, ty) || world.get(tx, ty) === T.water) return false;
    }
  }
  return true;
}

export function structureAt(s: GameState, tx: number, ty: number): Structure | null {
  for (const st of s.structures) {
    const def = STRUCTURES[st.defId];
    if (tx >= st.x && tx < st.x + def.w && ty >= st.y && ty < st.y + def.h) return st;
  }
  return null;
}

export function structureNear(s: GameState, x: number, y: number, r: number): Structure | null {
  let best: Structure | null = null;
  let bd = 1e9;
  for (const st of s.structures) {
    const def = STRUCTURES[st.defId];
    const d = Math.hypot(st.x + def.w / 2 - x, st.y + def.h / 2 - y);
    if (d < r && d < bd) { bd = d; best = st; }
  }
  return best;
}

export function feedStock(st: { buffer: Map<string, number> }): number {
  let n = 0;
  for (const [id, c] of st.buffer) if (ITEMS[id]?.kind === "food") n += c;
  return n;
}

// Deposit food from player inventory into a feed box.
export function depositFood(s: GameState, st: Structure): void {
  let moved = 0;
  for (const [id, n] of [...s.player.inv]) {
    if (ITEMS[id]?.kind !== "food") continue;
    takeItem(s, id, n);
    storageAdd(st, id, n);
    moved += n;
  }
  if (moved) log(s, `Stocked feed box with ${moved} food.`);
}

// Deposit all non-food materials into a chest.
export function depositAll(s: GameState, st: Structure): void {
  let moved = 0;
  for (const [id, n] of [...s.player.inv]) {
    const it = ITEMS[id];
    if (!it || it.kind === "weapon" || it.kind === "sphere") continue;
    takeItem(s, id, n);
    storageAdd(st, id, n);
    moved += n;
  }
  if (moved) log(s, `Deposited ${moved} items.`);
}

export function withdrawAll(s: GameState, st: Structure): void {
  let moved = 0;
  for (const [id, n] of st.buffer) {
    addItem(s, id, n);
    moved += n;
  }
  st.buffer.clear();
  if (moved) log(s, `Withdrew ${moved} items.`);
}

// Queue a recipe at a workbench (emits a workbench job per recipe).
export function queueCraft(s: GameState, st: Structure, recipeId: string): boolean {
  const r = RECIPES.find((o) => o.id === recipeId);
  if (!r) return false;
  if (!canAfford(s, r.cost)) { log(s, "Missing materials."); return false; }
  payCost(s, r.cost);
  st.craftQueue.push(recipeId);
  log(s, `Queued ${ITEMS[r.out[0]].name} x${r.out[1]}.`);
  return true;
}

// Advance the top of a bench's craft queue; returns true when it produces.
export function craftTick(s: GameState, st: Structure, points: number): boolean {
  const rid = st.craftQueue[0];
  if (!rid) return false;
  const r = RECIPES.find((o) => o.id === rid)!;
  st.craftProgress += points;
  if (st.craftProgress >= r.work) {
    st.craftProgress = 0;
    st.craftQueue.shift();
    storageAdd(st, r.out[0], r.out[1]);
    floater(s, st.x + 1, st.y, `${ITEMS[r.out[0]].name} x${r.out[1]}`, "#4dd0e1");
    return true;
  }
  return false;
}

export function updateStructures(s: GameState, world: World, dt: number): void {
  for (const st of s.structures) {
    const def = STRUCTURES[st.defId];
    // workbench: create one job at a time for its queue
    if (def.job?.kind === "workbench" && st.craftQueue.length) {
      const rid = st.craftQueue[0];
      const r = RECIPES.find((o) => o.id === rid);
      if (r && !s.jobs.some((j) => j.structureUid === st.uid && j.kind === "workbench")) {
        s.jobs.push({
          uid: uid(s), kind: "workbench", structureUid: st.uid,
          workType: "handiwork", x: st.x + def.w / 2, y: st.y + def.h / 2,
          amount: r.work, progress: st.craftProgress, claimedBy: -1, payload: rid,
        });
      }
      const job = s.jobs.find((j) => j.structureUid === st.uid && j.kind === "workbench");
      if (job) {
        job.progress = st.craftProgress;
        job.amount = r!.work;
        if (st.craftQueue[0] !== job.payload) { // queue shifted
          job.payload = st.craftQueue[0];
        }
      }
    }
    // generator charge decays
    if (st.defId === "generator") st.charge = Math.max(0, st.charge - dt * 0.4);
  }
}

// called when a workbench job completes via jobs.ts
export function onWorkbenchJobDone(s: GameState, st: Structure): void {
  craftTick(s, st, 1e9); // force-complete current recipe
}

// Player channels a job by holding E on the structure.
export function playerWorkTick(s: GameState, st: Structure, dt: number): void {
  const job = s.jobs.find((j) => j.structureUid === st.uid && j.kind !== "transport");
  if (job) {
    job.progress += 30 * dt;
    if (job.kind === "workbench") st.craftProgress = job.progress;
    if (job.progress >= job.amount) {
      completeJob(s, job);
    }
  } else if (st.craftQueue.length) {
    craftTick(s, st, 30 * dt);
  }
}
