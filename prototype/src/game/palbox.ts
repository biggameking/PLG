// Kinbox operations: party <-> box <-> base deployment.
import { GameState, Pal } from "./types.ts";
import { SPECIES } from "../data/species.ts";
import { log } from "./state.ts";
import { activePartner } from "./combat.ts";

export function palLabel(p: Pal): string {
  const sp = SPECIES[p.speciesId];
  return `${sp.name} Lv${p.level}`;
}

export function deployedPals(s: GameState): Pal[] {
  return s.pals.filter((p) => p.mode === "base");
}

export function deployToBase(s: GameState, p: Pal): void {
  if (!s.baseCenter) { log(s, "Build a Kinbox first."); return; }
  // remove from all holding areas
  s.box = s.box.filter((o) => o.uid !== p.uid);
  s.palparty = s.palparty.filter((o) => o.uid !== p.uid);
  s.party = s.party.filter((u) => u !== p.uid);
  p.mode = "base";
  p.x = s.baseCenter.x + 1.5;
  p.y = s.baseCenter.y + 1.5;
  if (!s.pals.includes(p)) s.pals.push(p);
  log(s, `${SPECIES[p.speciesId].name} deployed to base.`);
}

export function toBox(s: GameState, p: Pal): void {
  s.palparty = s.palparty.filter((o) => o.uid !== p.uid);
  s.pals = s.pals.filter((o) => o.uid !== p.uid);
  s.party = s.party.filter((u) => u !== p.uid);
  s.box = s.box.filter((o) => o.uid !== p.uid);
  p.mode = "box";
  p.jobUid = -1;
  s.box.push(p);
  if (s.activePal >= 0 && s.party.length === 0) s.activePal = -1;
  else if (s.activePal >= s.party.length) s.activePal = s.party.length - 1;
  log(s, `${SPECIES[p.speciesId].name} moved to Kinbox.`);
}

export function toParty(s: GameState, p: Pal): boolean {
  if (s.party.length >= 5) { log(s, "Party is full (5)."); return false; }
  s.box = s.box.filter((o) => o.uid !== p.uid);
  s.palparty = s.palparty.filter((o) => o.uid !== p.uid);
  s.pals = s.pals.filter((o) => o.uid !== p.uid); // recall from base if deployed
  p.jobUid = -1;
  p.mode = "box";
  s.party.push(p.uid);
  s.palparty.push(p);
  log(s, `${SPECIES[p.speciesId].name} joined party.`);
  return true;
}
