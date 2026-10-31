// PLG — entry point: game loop, camera, render pipeline, mode dispatch.
import { Renderer, CELL_W, CELL_H } from "./engine/renderer.ts";
import { Input } from "./engine/input.ts";
import { C } from "./engine/palette.ts";
import { newGame, addItem, itemCount, isNight, log, ownedSpheres } from "./game/state.ts";
import { World, T, chunkCanvas, CHUNK_TILES } from "./game/world.ts";
import { updateSpawns, dropItem } from "./game/entities.ts";
import { updatePals } from "./game/ai.ts";
import { updateProjectiles, updateSpheres, activePartner, catchChance } from "./game/combat.ts";
import { refreshJobs } from "./game/jobs.ts";
import { updateStructures, placeStructure, canPlaceAt, structureNear } from "./game/structures.ts";
import { updatePlayer } from "./game/player.ts";
import * as ui from "./game/ui.ts";
import { drawPal, drawHuman } from "./game/sprite.ts";
import { ITEMS } from "./data/items.ts";
import { SPECIES } from "./data/species.ts";
import { SKILLS } from "./data/skills.ts";
import { STRUCTURES } from "./data/structures.ts";
import { wildPals } from "./game/entities.ts";
import { GameState, DAY_LEN, WORLD_W, WORLD_H, BASE_RADIUS, Pal } from "./game/types.ts";

const canvas = document.getElementById("game") as HTMLCanvasElement;
const r = new Renderer(canvas);
const input = new Input(canvas);

const seed = Math.floor(Math.random() * 1e9);
const world = new World();
const spawn = world.generate(seed);
const s = newGame(seed);
s.player.x = spawn.spawnX + 0.5;
s.player.y = spawn.spawnY + 0.5;
s.mode = "help";

log(s, "Welcome to PLG. Press H for help.");
(window as unknown as { __game: unknown }).__game = { s, world };

// ---------- build ghost ----------
function updateBuildGhost(dt: number): void {
  if (!s.buildSel) return;
  const def = STRUCTURES[s.buildSel];
  const mwx = Math.floor((input.mouse.x + r.camX) / CELL_W);
  const mwy = Math.floor((input.mouse.y + r.camY) / CELL_H);
  s.buildX = Math.max(0, Math.min(WORLD_W - def.w, mwx - Math.floor(def.w / 2)));
  s.buildY = Math.max(0, Math.min(WORLD_H - def.h, mwy - Math.floor(def.h / 2)));
  if (input.mouse.clicked || input.hit("e")) {
    if (canPlaceAt(world, s.buildSel, s.buildX, s.buildY)) {
      if (placeStructure(s, world, s.buildSel, s.buildX, s.buildY)) {
        s.buildSel = null;
        s.mode = "play";
      }
    } else {
      log(s, "Can't build there.");
    }
  }
  if (input.hit("escape")) { s.buildSel = null; s.mode = "play"; }
}

// ---------- mode dispatch ----------
function update(dt: number): void {
  s.t += dt;
  s.timeOfDay = (s.t % DAY_LEN) / DAY_LEN;
  if (s.timeOfDay < 0.02 && !dayTicked) { s.day++; dayTicked = true; }
  if (s.timeOfDay > 0.05) dayTicked = false;

  // global keys (menus)
  if (input.hit("escape")) {
    if (s.mode !== "play") { s.mode = "play"; s.buildSel = null; }
    else s.aimSphere = false;
  }
  if (s.mode !== "dead") {
    if (input.hit("i") && s.mode !== "build" && !s.buildSel) s.mode = s.mode === "inv" ? "play" : "inv";
    if (input.hit("b") && !s.buildSel) s.mode = s.mode === "build" ? "play" : "build";
    if (input.hit("t")) s.mode = s.mode === "tech" ? "play" : "tech";
    if (input.hit("p")) s.mode = s.mode === "palbox" ? "play" : "palbox";
    if (input.hit("h")) s.mode = s.mode === "help" ? "play" : "help";
  }

  if (s.mode === "play") {
    updatePlayer(s, world, input, dt, r.cols, r.rows, r.camX, r.camY);
    updateBuildGhost(dt);
  } else if (s.mode === "build") {
    updateBuildGhost(dt);
    updatePlayer(s, world, input, dt, r.cols, r.rows, r.camX, r.camY); // still move while picking? keep world alive
  }

  // world always simulates (pals keep working while menus open — DF style)
  updatePals(s, world, dt);
  updateSpawns(s, world, dt);
  updateProjectiles(s, world, dt);
  updateSpheres(s, dt);
  updateStructures(s, world, dt);
  refreshJobs(s, world, dt);

  // drops: pickup by walking over
  for (const d of [...s.drops]) {
    d.t += dt;
    if (Math.hypot(d.x - s.player.x, d.y - s.player.y) < 0.9) {
      addItem(s, d.itemId, d.count);
      s.drops = s.drops.filter((o) => o.uid !== d.uid);
    }
  }
  // floaters age
  for (const f of [...s.floaters]) f.t += dt;
  s.floaters = s.floaters.filter((f) => f.t < 1.6);
  s.camShake = Math.max(0, s.camShake - dt * 1.5);

  // camera follows player (px = tile*cell)
  const px = s.player.x * CELL_W, py = s.player.y * CELL_H;
  const shake = s.camShake * 10;
  r.camX = Math.max(0, Math.min(WORLD_W * CELL_W - r.w, px - r.w / 2)) + (Math.random() - 0.5) * shake;
  r.camY = Math.max(0, Math.min(WORLD_H * CELL_H - r.h, py - r.h / 2)) + (Math.random() - 0.5) * shake;
}
let dayTicked = false;
let lastPX: number | null = null, lastPY = 0;

// ---------- render ----------
function render(): void {
  r.clear();
  // terrain: pixel-art tiles baked per 16x16 chunk (cached canvases)
  const CHPX = CHUNK_TILES * CELL_W, CHPY = CHUNK_TILES * CELL_H;
  const ch0x = Math.floor(r.camX / CHPX), ch0y = Math.floor(r.camY / CHPY);
  const ch1x = Math.floor((r.camX + r.w) / CHPX), ch1y = Math.floor((r.camY + r.h) / CHPY);
  for (let cy = ch0y; cy <= ch1y; cy++) {
    for (let cx = ch0x; cx <= ch1x; cx++) {
      if (cx < 0 || cy < 0 || cx * CHUNK_TILES >= WORLD_W || cy * CHUNK_TILES >= WORLD_H) continue;
      r.ctx.drawImage(chunkCanvas(world, seed, cx, cy), cx * CHPX - r.camX, cy * CHPY - r.camY);
    }
  }

  // base radius tint
  if (s.baseCenter) {
    const bx = s.baseCenter.x, by = s.baseCenter.y;
    for (let y = Math.max(0, by - BASE_RADIUS); y < Math.min(WORLD_H, by + BASE_RADIUS); y += 2) {
      for (let x = Math.max(0, bx - BASE_RADIUS); x < Math.min(WORLD_W, bx + BASE_RADIUS); x += 2) {
        if (Math.hypot(x - bx, y - by) > BASE_RADIUS && Math.hypot(x - bx, y - by) < BASE_RADIUS + 1.5)
          r.tileAt(x, y, "·", "#2b8a99");
      }
    }
  }

  // structures
  for (const st of s.structures) {
    const def = STRUCTURES[st.defId];
    for (let ty = st.y; ty < st.y + def.h; ty++) {
      for (let tx = st.x; tx < st.x + def.w; tx++) {
        r.tileAt(tx, ty, "░", "#31393f", "#1a2126");
      }
    }
    r.tileAt(st.x, st.y, def.glyph, def.color, "#1a2126");
    if (def.w > 1 && def.h > 1) r.tileAt(st.x + def.w - 1, st.y + def.h - 1, def.glyph, def.color, "#1a2126");
    // farm stage indicator
    if (st.farm) {
      const ch = st.farm.stage === "empty" ? "░" : st.farm.stage === "growing" ? "," : "♣";
      r.tileAt(st.x + 1, st.y, ch, st.farm.stage === "ready" ? "#e64533" : "#4caf50");
    }
    if (st.defId === "generator" && st.charge > 0) r.tileAt(st.x, st.y, "ϟ", "#e8d44d");
  }

  // build ghost
  if (s.buildSel) {
    const def = STRUCTURES[s.buildSel];
    const ok = canPlaceAt(world, s.buildSel, s.buildX, s.buildY);
    for (let ty = s.buildY; ty < s.buildY + def.h; ty++)
      for (let tx = s.buildX; tx < s.buildX + def.w; tx++)
        r.tileAt(tx, ty, ok ? "▒" : "✕", ok ? "#4caf50" : "#e64533");
  }

  // drops
  for (const d of s.drops) {
    const it = ITEMS[d.itemId];
    if (it) r.tileAt(d.x - 0.5, d.y - 0.5, it.glyph, it.color);
  }

  // pals — composite mini-sprites
  for (const p of s.pals) {
    const sp = SPECIES[p.speciesId];
    const sleeping = isNight(s) && !sp.night && p.mode === "wild" && p.aggroUid < 0;
    r.shadow(p.x * CELL_W - r.camX, p.y * CELL_H - r.camY + 5, CELL_W * 1.5);
    drawPal(r, p, sp, r.camX, r.camY, s.t, sleeping);
    // hp bar over damaged pals
    if (p.hp < p.maxHp && p.mode !== "box") {
      const px = (p.x - 0.5) * CELL_W - r.camX, py = (p.y - 2.0) * CELL_H - r.camY;
      r.rectPx(px - 4, py, 22, 3, "#330");
      r.ctx.fillStyle = "#e64533";
      r.ctx.fillRect(px - 4, py, 22 * (p.hp / p.maxHp), 3);
    }
    // status icons: sleeping Zzz / working ⚒ / aggro !
    if (sleeping) r.tileAt(p.x + 0.6, p.y - 2.2, "z", "#8b9a9e");
    else if (p.mode === "base" && p.jobUid >= 0) r.tileAt(p.x + 0.6, p.y - 2.2, "⚒", "#b0bec5");
    else if (p.aggroUid >= 0 || p.aggroUid === -2) r.tileAt(p.x + 0.6, p.y - 2.2, "!", "#ff7d6e");
  }

  // player
  const pmoving = lastPX !== null && Math.hypot(s.player.x - lastPX, s.player.y - lastPY) > 0.02;
  lastPX = s.player.x; lastPY = s.player.y;
  r.shadow(s.player.x * CELL_W - r.camX, s.player.y * CELL_H - r.camY + 5, CELL_W * 1.2);
  drawHuman(r, s.player.x, s.player.y, s.player.facing, r.camX, r.camY, s.t, pmoving);
  if (s.player.dodgeT > 0) {
    r.ctx.globalAlpha = 0.4;
    drawHuman(r, s.player.x, s.player.y, s.player.facing, r.camX, r.camY, s.t, pmoving);
    r.ctx.globalAlpha = 1;
  }

  // projectiles
  for (const pr of s.projectiles) {
    const sk = SKILLS[pr.skillId];
    const g = sk.element === "fire" ? "♦" : sk.element === "water" ? "≈" : sk.element === "electric" ? "ϟ" : sk.element === "ice" ? "*" : sk.element === "dark" ? "◘" : "•";
    r.tileAt(pr.x - 0.5, pr.y - 0.5, g, "#ffffff");
  }

  // spheres in flight
  for (const sp of s.spheres) {
    r.tileAt(sp.x - 0.5, sp.y - 0.5, "◐", ITEMS[sp.itemId]?.color ?? "#4d9de0");
  }

  // floaters
  for (const f of s.floaters) {
    r.textPx((f.x - 0.5) * CELL_W - r.camX, (f.y - 0.5 - f.t * 0.8) * CELL_H - r.camY, f.s, f.color);
  }

  // dawn/dusk warm tint
  const tod = s.timeOfDay;
  const dawn = Math.max(0, 0.30 - Math.abs(tod - 0.28)) / 0.30;
  const dusk = Math.max(0, 0.25 - Math.abs(tod - 0.80)) / 0.25;
  const warm = Math.max(dawn, dusk) * 0.10;
  if (warm > 0.005) r.fill(`rgba(255,138,60,${warm.toFixed(3)})`);

  // night lighting
  const nightA = isNight(s) ? 0.55 : 0;
  if (nightA > 0) {
    const lights = [{ x: s.player.x * CELL_W - r.camX, y: s.player.y * CELL_H - r.camY, r: 130 }];
    for (const st of s.structures) {
      const def = STRUCTURES[st.defId];
      if (def.light) {
        lights.push({
          x: (st.x + def.w / 2) * CELL_W - r.camX,
          y: (st.y + def.h / 2) * CELL_H - r.camY,
          r: def.light * CELL_W,
        });
      }
    }
    r.nightOverlay(nightA, lights);
  }

  r.vignette();

  // UI layers
  ui.drawHUD(r, s, input, r.camX, r.camY);
  if (s.aimSphere) ui.drawAim(r, s, input, r.camX, r.camY);
  switch (s.mode) {
    case "inv": ui.drawInventory(r, s, input); break;
    case "palbox": ui.drawPalbox(r, s, input); break;
    case "build": {
      const res = ui.drawBuild(r, s, input);
      if (res.sel) { s.buildSel = res.sel; s.mode = "play"; }
      break;
    }
    case "tech": ui.drawTech(r, s, input); break;
    case "craft": ui.drawCraft(r, s, input); break;
    case "help": ui.drawHelp(r, s, input); break;
    case "dead": ui.drawDead(r, s, input); break;
  }
}

let last = performance.now();
function frame(now: number): void {
  const dt = Math.min(0.1, (now - last) / 1000);
  last = now;
  r.resize();
  update(dt);
  render();
  input.endFrame();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
