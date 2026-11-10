// All UI: HUD, inventory, kinbox management, build menu, tech tree, craft, help, death.
import { GameState, Pal, WORLD_W, WORLD_H, XP_FOR_LEVEL } from "./types.ts";
import { ITEMS, RECIPES } from "../data/items.ts";
import { SPECIES } from "../data/species.ts";
import { SKILLS } from "../data/skills.ts";
import { STRUCTURES, TECH } from "../data/structures.ts";
import { WORK_GLYPH, WORK_LABEL } from "../data/work.ts";
import { ELEMENT_GLYPH, ELEMENT_COLOR } from "../data/elements.ts";
import { Renderer, CELL_W, CELL_H } from "../engine/renderer.ts";
import { C } from "../engine/palette.ts";
import { Input } from "../engine/input.ts";
import { itemCount, addItem, takeItem, ownedSpheres, log, isNight } from "./state.ts";
import { catchChance, activePartner } from "./combat.ts";
import { deployedPals, toBox, toParty, deployToBase, palLabel } from "./kinbox.ts";
import { queueCraft, feedStock } from "./structures.ts";
import { wildPals } from "./entities.ts";

// ---- tiny immediate-mode button helper ----
interface Btn { x: number; y: number; w: number; h: number; label: string; id: string; disabled?: boolean }
const btns: Btn[] = [];
function button(r: Renderer, input: Input, x: number, y: number, w: number, label: string, disabled = false): boolean {
  const id = `${x},${y},${label}`;
  const hovered = !disabled && input.mouse.x >= x * CELL_W && input.mouse.x < (x + w) * CELL_W &&
    input.mouse.y >= y * CELL_H && input.mouse.y < (y + 1) * CELL_H;
  const color = disabled ? C.fgDark : hovered ? C.yellow : C.fg;
  const bg = disabled ? C.bgPanel : hovered ? C.bgPanel2 : C.bgPanel;
  r.rect(x, y, w, 1, bg);
  r.text(x + 1, y, label.slice(0, w - 2), color);
  const clicked = hovered && input.mouse.clicked;
  return clicked;
}

function palRow(r: Renderer, x: number, y: number, w: number, p: Pal, s: GameState): void {
  const sp = SPECIES[p.speciesId];
  r.glyph(x * CELL_W, y * CELL_H, sp.glyph, sp.color);
  r.text(x + 2, y, `${sp.name} Lv${p.level} T${p.talent ?? 0}`, C.fg);
  r.bar(x + 2, y, 0, 0, "fg" as never); // noop keep signature
  const hpw = Math.min(6, Math.floor(w * 0.25));
  r.bar(x + w - hpw - 1, y, hpw, p.hp / p.maxHp, "green" as never);
  const sw = 3;
  for (let i = 0; i < sp.elements.length; i++)
    r.glyph((x + w - hpw - 3 - (sp.elements.length - i)) * CELL_W, y * CELL_H, ELEMENT_GLYPH[sp.elements[i]], ELEMENT_COLOR[sp.elements[i]]);
}

function workTags(sp: import("../data/species.ts").Species): string {
  return Object.entries(sp.work).map(([k, v]) => `${WORK_GLYPH[k as keyof typeof WORK_GLYPH]}${v}`).join(" ");
}

// ---------- HUD ----------
export function drawHUD(r: Renderer, s: GameState, input: Input, camX: number, camY: number): void {
  const p = s.player;
  // top-left: day/time/level
  const hh = Math.floor(s.timeOfDay * 24), mm = Math.floor((s.timeOfDay * 24 % 1) * 60);
  r.text(1, 0, `Day ${s.day} ${String(hh).padStart(2, "0")}:${String(mm).padStart(2, "0")}  ${isNight(s) ? "☾" : "☀"}`, C.fg);
  r.text(1, 1, `Lv${p.level}  TP:${p.techPoints}`, C.cyan);
  // vitals
  r.text(1, 3, "HP", C.red); r.bar(4, 3, 14, p.hp / p.maxHp, "red" as never);
  r.text(1, 4, "FD", C.orange); r.bar(4, 4, 14, 1 - p.hunger / 100, "orange" as never);
  r.text(1, 5, "ST", C.lime); r.bar(4, 5, 14, p.stamina / 100, "lime" as never);
  // xp thin bar
  r.bar(1, 6, 17, p.xp / XP_FOR_LEVEL(p.level), "cyan" as never);

  // party strip (bottom-left)
  const baseY = r.rows - 3;
  for (let i = 0; i < s.party.length; i++) {
    const pal = (s.palparty.find((o) => o.uid === s.party[i]) ?? s.pals.find((o) => o.uid === s.party[i]))!;
    const sp = SPECIES[pal.speciesId];
    const sel = i === s.activePal;
    const x = 1 + i * 7;
    r.rect(x, baseY, 6, 3, sel ? C.bgPanel2 : C.bgPanel);
    if (sel) { r.glyph(x * CELL_W, baseY * CELL_H, ">", C.cyan); }
    r.glyph((x + 1) * CELL_W, baseY * CELL_H, sp.glyph, sp.color);
    r.text(x + 2, baseY, `${i + 1}`, C.fgDim);
    r.glyph((x + 1) * CELL_W, (baseY + 1) * CELL_H, "❤", C.red);
    r.bar(x + 2, baseY + 1, 4, pal.hp / pal.maxHp, "red" as never);
    r.bar(x + 1, baseY + 2, 5, pal.san / sp.san, "magenta" as never);
  }

  // weapon + orb hotbar (bottom-center)
  const w = p.weapon ? ITEMS[p.weapon] : null;
  r.text(1, r.rows - 1, `[${w ? w.glyph : "-"}] ${w ? w.name : "Fists"}`, C.fg);
  const tiers = ownedSpheres(s);
  if (tiers.length) {
    const sid = tiers[Math.min(p.sphereSel, tiers.length - 1)];
    r.text(20, r.rows - 1, `Q ${s.aimSphere ? "◉" : "◐"} ${ITEMS[sid].name} x${itemCount(s, sid)} (R swap)`, s.aimSphere ? C.cyan : C.fgDim);
  }

  // log (above hotbar, right side) — translucent backing for readability
  for (let i = 0; i < s.log.length; i++) {
    const ly = r.rows - 1 - s.log.length + i;
    r.rect(r.cols - 42, ly, 42, 1, "rgba(8,10,14,0.72)");
    r.text(r.cols - 42, ly, s.log[i].slice(0, 40), i === s.log.length - 1 ? C.fg : C.fgDim);
  }

  // interaction hint
  r.rect(0, r.rows - 2, 50, 1, "rgba(8,10,14,0.55)");
  r.text(1, r.rows - 2, "E interact · I inv · B build · T tech · H help", "#8b9a9e");
}

// ---------- orb aim overlay ----------
export function drawAim(r: Renderer, s: GameState, input: Input, camX: number, camY: number): void {
  const mwx = (input.mouse.x + camX) / CELL_W;
  const mwy = (input.mouse.y + camY) / CELL_H;
  const tiers = ownedSpheres(s);
  if (!tiers.length) return;
  const sid = tiers[Math.min(s.player.sphereSel, tiers.length - 1)];
  for (const p of wildPals(s)) {
    if (Math.hypot(p.x - mwx, p.y - mwy) > 3) continue;
    const chance = catchChance(s, p, ITEMS[sid].spherePower ?? 26, false);
    const px = p.x * CELL_W - camX, py = p.y * CELL_H - camY;
    r.glyph(px, py - CELL_H, "◎", C.cyan);
    r.textPx(px - 2 * CELL_W, py - 2 * CELL_H, `${Math.round(chance * 100)}%`, C.cyan);
  }
}

// ---------- inventory ----------
export function drawInventory(r: Renderer, s: GameState, input: Input): void {
  const w = 46, h = Math.min(r.rows - 4, 24), x = Math.floor((r.cols - w) / 2), y = 3;
  r.panel(x, y, w, h, "INVENTORY  (click: use/equip · E/eatable, W/equip)");
  const rows: [string, number][] = [...s.player.inv.entries()].filter(([, n]) => n > 0);
  let i = 0;
  for (const [id, n] of rows) {
    const it = ITEMS[id];
    if (!it) continue;
    const cy = y + 2 + i;
    if (cy > y + h - 2) break;
    r.glyph((x + 2) * CELL_W, cy * CELL_H, it.glyph, it.color);
    r.text(x + 4, cy, `${it.name} x${n}`, C.fg);
    r.text(x + w - 18, cy, it.kind, C.fgDim);
    const hovered = input.mouse.x >= (x + 1) * CELL_W && input.mouse.x < (x + w - 1) * CELL_W &&
      input.mouse.y >= cy * CELL_H && input.mouse.y < (cy + 1) * CELL_H;
    if (hovered) r.rect(x + 1, cy, w - 2, 1, "rgba(80,120,140,0.25)");
    if (hovered && input.mouse.clicked) {
      if (it.kind === "food") {
        takeItem(s, id, 1);
        s.player.hunger = Math.max(0, s.player.hunger - (it.food ?? 10));
        s.player.hp = Math.min(s.player.maxHp, s.player.hp + (it.hp ?? 0));
        log(s, `Ate ${it.name}.`);
      } else if (it.kind === "weapon") {
        s.player.weapon = s.player.weapon === id ? null : id;
        log(s, s.player.weapon ? `Equipped ${it.name}.` : "Unarmed.");
      } else if (it.kind === "medicine") {
        takeItem(s, id, 1);
        s.player.hp = Math.min(s.player.maxHp, s.player.hp + (it.heal ?? 30));
        log(s, `Used ${it.name}.`);
      } else if (it.kind === "orb") {
        s.aimSphere = true;
        s.mode = "play";
        log(s, "Aim and click a kin to throw.");
      }
    }
    i++;
  }
  r.text(x + 2, y + h - 1, `gold: ${itemCount(s, "gold_coin")}   [I/Esc close]`, C.dkyellow);
}

// ---------- kinbox ----------
export function drawKinbox(r: Renderer, s: GameState, input: Input): void {
  const w = Math.min(86, r.cols - 6), h = Math.min(r.rows - 4, 26), x = Math.floor((r.cols - w) / 2), y = 2;
  r.panel(x, y, w, h, "KINBOX MANAGEMENT");
  const partyPals = s.party.map((u) => s.palparty.find((o) => o.uid === u) ?? s.pals.find((o) => o.uid === u)).filter(Boolean) as Pal[];
  const base = deployedPals(s);
  const colW = Math.floor((w - 6) / 3);
  r.text(x + 2, y + 1, `PARTY ${partyPals.length}/5`, C.cyan);
  r.text(x + 2 + colW, y + 1, `BASE ${base.length}`, C.lime);
  r.text(x + 2 + 2 * colW, y + 1, `BOX ${s.box.length}`, C.fgDim);

  const sel: { pal: Pal | null; mode: "party" | "base" | "box" | null } = { pal: null, mode: null };
  const drawCol = (list: Pal[], col: number, mode: "party" | "base" | "box") => {
    list.forEach((p, i) => {
      const cy = y + 3 + i;
      if (cy > y + h - 5) return;
      const cx = x + 2 + col * colW;
      const sp = SPECIES[p.speciesId];
      r.glyph(cx * CELL_W, cy * CELL_H, sp.glyph, sp.color);
      r.text(cx + 2, cy, `${sp.name} ${p.level}`, C.fg);
      r.text(cx + 14, cy, workTags(sp), C.fgDim);
      const hovered = input.mouse.x >= cx * CELL_W && input.mouse.x < (cx + colW - 1) * CELL_W &&
        input.mouse.y >= cy * CELL_H && input.mouse.y < (cy + 1) * CELL_H;
      if (hovered) r.rect(cx, cy, colW - 1, 1, "rgba(80,120,140,0.25)");
      if (hovered && input.mouse.clicked) { sel.pal = p; sel.mode = mode; }
    });
  };
  drawCol(partyPals, 0, "party");
  drawCol(base, 1, "base");
  drawCol(s.box, 2, "box");

  // action row
  const ay = y + h - 3;
  r.text(x + 2, ay, "click a kin, then:", C.fgDim);
  if (sel.pal && sel.mode) {
    const p = sel.pal;
    r.text(x + 2, ay - 1, `▸ ${palLabel(p)} (${sel.mode})`, C.yellow);
    if (sel.mode !== "party" && button(r, input, x + 20, ay, 14, "→ Party", s.party.length >= 5)) toParty(s, p);
    if (sel.mode !== "base" && button(r, input, x + 36, ay, 13, "→ Base", !s.baseCenter)) deployToBase(s, p);
    if (sel.mode !== "box" && button(r, input, x + 51, ay, 12, "→ Box", false)) toBox(s, p);
    if (sel.mode === "party" && button(r, input, x + 65, ay, 14, "Deploy", false)) {
      const prev = activePartner(s);
      if (prev) { prev.mode = "box"; s.pals = s.pals.filter(o => o.uid !== prev.uid); s.palparty.push(prev); }
      s.palparty = s.palparty.filter((o) => o.uid !== p.uid);
      p.mode = "partner"; p.x = s.player.x + 1; p.y = s.player.y;
      if (!s.pals.includes(p)) s.pals.push(p);
      s.activePal = s.party.indexOf(p.uid);
    }
  }
  r.text(x + 2, y + h - 1, "[P/Esc close]", C.fgDim);
}

// ---------- build ----------
export function drawBuild(r: Renderer, s: GameState, input: Input): { sel: string | null } {
  const w = 52, h = Math.min(r.rows - 4, 26), x = Math.floor((r.cols - w) / 2), y = 2;
  r.panel(x, y, w, h, "BUILD  (click to place)");
  let i = 0;
  let sel: string | null = null;
  for (const def of Object.values(STRUCTURES)) {
    if (!s.player.unlocked.has(def.id)) continue;
    const cy = y + 2 + i;
    if (cy > y + h - 2) break;
    const afford = def.cost.every(([id, n]) => itemCount(s, id) >= n);
    const cost = def.cost.map(([id, n]) => `${ITEMS[id].glyph}${n}`).join("");
    r.glyph((x + 2) * CELL_W, cy * CELL_H, def.glyph, def.color);
    const label = `${def.name} ${def.w}x${def.h}`;
    if (button(r, input, x + 1, cy, w - 2, `${def.glyph} ${label.padEnd(24)} ${cost}`, !afford)) sel = def.id;
    i++;
  }
  r.text(x + 2, y + h - 1, "click → ghost → LMB place · RMB/Esc cancel   [B close]", C.fgDim);
  return { sel };
}

// ---------- tech ----------
export function drawTech(r: Renderer, s: GameState, input: Input): void {
  const w = 56, h = Math.min(r.rows - 4, 28), x = Math.floor((r.cols - w) / 2), y = 1;
  r.panel(x, y, w, h, `TECHNOLOGY  (points: ${s.player.techPoints})`);
  let i = 0;
  for (const t of TECH) {
    const cy = y + 2 + i;
    if (cy > y + h - 2) break;
    const has = s.player.unlocked.has(t.id);
    const label = `T${t.tier} ${t.name}`;
    if (has) r.text(x + 2, cy, `✓ ${label}`, C.dkgreen);
    else {
      const afford = s.player.techPoints >= t.cost;
      if (button(r, input, x + 1, cy, w - 2, `  ${label}   [${t.cost} TP]`, !afford)) {
        s.player.techPoints -= t.cost;
        s.player.unlocked.add(t.id);
        log(s, `Unlocked ${t.name}.`);
      }
    }
    i++;
  }
  r.text(x + 2, y + h - 1, "earn TP by leveling up   [T/Esc close]", C.fgDim);
}

// ---------- craft ----------
export function drawCraft(r: Renderer, s: GameState, input: Input): void {
  const st = s.structures.find((o) => o.uid === s.craftStation);
  const stationName = st ? STRUCTURES[st.defId].name : "Craft";
  const station = st ? st.defId : "workbench";
  const w = 60, h = Math.min(r.rows - 4, 26), x = Math.floor((r.cols - w) / 2), y = 2;
  r.panel(x, y, w, h, `${stationName.toUpperCase()}  (click to queue)`);
  let i = 0;
  for (const rec of RECIPES) {
    const want = station === "campfire" ? "campfire" : station === "furnace" ? "furnace" : station === "workbench" ? "workbench" : "hand";
    if (rec.station !== want && !(station === "workbench" && rec.station === "hand")) continue;
    const outIt = ITEMS[rec.out[0]];
    if (!outIt) continue;
    // recipes require tech unlock if their id is in TECH
    const techNode = TECH.find((t) => t.id === rec.id);
    if (techNode && !s.player.unlocked.has(rec.id)) continue;
    const cy = y + 2 + i;
    if (cy > y + h - 5) break;
    const cost = rec.cost.map(([id, n]) => `${ITEMS[id].glyph}${n}`).join("");
    const afford = rec.cost.every(([id, n]) => itemCount(s, id) >= n);
    if (button(r, input, x + 1, cy, w - 2, `${outIt.glyph} ${outIt.name} x${rec.out[1]}   ${cost}   ${rec.work}w`, !afford)) {
      if (st) queueCraft(s, st, rec.id);
      else {
        // hand crafting (instant for 'hand' station)
        if (rec.station === "hand" && afford) {
          rec.cost.forEach(([id, n]) => takeItem(s, id, n));
          addItem(s, rec.out[0], rec.out[1]);
          log(s, `Crafted ${outIt.name} x${rec.out[1]}.`);
        }
      }
    }
    i++;
  }
  if (st && st.craftQueue.length) {
    r.text(x + 2, y + h - 3, `queue: ${st.craftQueue.map((q) => ITEMS[RECIPES.find(rr => rr.id === q)!.out[0]].name).join(" → ")}`, C.cyan);
    r.bar(x + 2, y + h - 2, w - 6, st.craftProgress / Math.max(1, RECIPES.find(rr => rr.id === st.craftQueue[0])?.work ?? 1), "cyan" as never);
  }
  r.text(x + 2, y + h - 1, "kin work the queue (or hold E at station)   [Esc close]", C.fgDim);
}

// ---------- help ----------
export function drawHelp(r: Renderer, s: GameState, input: Input): void {
  const w = 64, h = 24, x = Math.floor((r.cols - w) / 2), y = 3;
  r.panel(x, y, w, h, "PLG — how to play");
  const lines = [
    "WASD/arrows  move        SHIFT sprint      SPACE dodge roll",
    "LMB          attack / harvest tree·rock·ore",
    "Q            toggle orb-aim   → click a kin to throw",
    "R            cycle orb type (when aiming)",
    "1-5          swap active party kin",
    "E            interact / pick up / hold to work a station",
    "I            inventory     B build     T tech     P kinbox",
    "Esc          close menus / cancel build",
    "",
    "Goal: catch kin, build a base, put kin to work.",
    "Weaken a kin (low HP) to raise catch chance.",
    "Kin work stations matching their suitabilities:",
    "  kindling→furnace watering→crusher planting→farm",
    "  lumbering→logging mining→pit handiwork→bench",
    "  gathering→harvest transporting→haul farming→ranch",
    "  electricity→generator cooling·medicine→future",
    "",
    "Kin eat from a Feed Box and sleep in Kin Beds.",
    "Low SAN → kin slack off. Keep them fed and rested.",
    "",
    "Press H or Esc to close.",
  ];
  lines.forEach((ln, i) => r.text(x + 2, y + 1 + i, ln, i === 0 ? C.white : C.fg));
}

// ---------- death ----------
export function drawDead(r: Renderer, s: GameState, input: Input): void {
  const w = 40, h = 7, x = Math.floor((r.cols - w) / 2), y = Math.floor(r.rows / 2) - 3;
  r.panel(x, y, w, h, "KNOCKED OUT");
  r.text(x + 2, y + 2, "You wake up at your Kinbox, bruised.", C.fg);
  if (button(r, input, x + 2, y + 4, 16, "Respawn", false) || input.hit("return") || input.hit("enter")) {
    s.mode = "play";
    s.player.hp = Math.floor(s.player.maxHp * 0.5);
    const c = s.baseCenter ?? { x: WORLD_W / 2, y: WORLD_H / 2 };
    s.player.x = c.x; s.player.y = c.y;
    s.player.hunger = Math.min(100, s.player.hunger + 20);
  }
}
