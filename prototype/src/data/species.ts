// Species (pal) definitions modeled on the island: elements, base stats,
// work suitabilities, food appetite, SAN cost, capture power, drops.
import { Element } from "./elements.ts";
import { Work } from "./work.ts";

export interface Species {
  id: string;
  name: string;
  glyph: string;
  color: string;
  elements: Element[];
  hp: number;      // base stats
  atk: number;
  def: number;
  speed: number;   // tiles/sec move speed
  capturePower: number; // lower = easier to catch
  food: number;    // food units consumed per game-day
  san: number;     // max SAN
  work: Partial<Record<Work, number>>;
  skills: [number, string][]; // [minLevel, skillId]
  drops: [string, number, number][]; // [itemId, min, max]
  desc: string;
  night?: boolean; // prefers night spawns
  hostile?: number; // 0=timid flees, 1=neutral, 2=aggressive
  farm?: { item: string; per: number }; // ranch produce: item every `per` work-points
}

export const SPECIES: Record<string, Species> = {
  fenjelly: {
    id: "fenjelly", name: "Fenjelly", glyph: "λ", color: "#ede0c8",
    elements: ["neutral"], hp: 70, atk: 70, def: 70, speed: 2.6,
    capturePower: 40, food: 2, san: 70,
    work: { handiwork: 1, transporting: 1, farming: 1 },
    skills: [[1, "tackle"], [4, "airCannon"], [10, "healingBreeze"]],
    drops: [["wool", 1, 2], ["fenjelly_mutton", 1, 1]],
    desc: "Fluffy sheep kin. Produces wool at a ranch.",
    farm: { item: "wool", per: 60 }, hostile: 0,
  },
  puffmite: {
    id: "puffmite", name: "Puffmite", glyph: "c", color: "#f2a0b5",
    elements: ["neutral"], hp: 70, atk: 70, def: 70, speed: 2.8,
    capturePower: 40, food: 1, san: 60,
    work: { handiwork: 1, transporting: 1, gathering: 1, mining: 1 },
    skills: [[1, "tackle"], [5, "airCannon"]],
    drops: [["red_berries", 1, 2], ["fiber", 1, 1]],
    desc: "Cat-like kin; a jack of all base trades.", hostile: 0,
  },
  fenlump: {
    id: "fenlump", name: "Fenlump", glyph: "k", color: "#e8f0f2",
    elements: ["neutral"], hp: 60, atk: 60, def: 60, speed: 2.5,
    capturePower: 30, food: 1, san: 60,
    work: { gathering: 1, farming: 1 },
    skills: [[1, "tackle"]],
    drops: [["egg", 1, 2], ["fenlump_poultry", 1, 1]],
    desc: "Tiny bird kin. Lays eggs at a ranch.",
    farm: { item: "egg", per: 45 }, hostile: 0,
  },
  cindlump: {
    id: "cindlump", name: "Cindlump", glyph: "f", color: "#e8963c",
    elements: ["fire"], hp: 75, atk: 80, def: 65, speed: 3.0,
    capturePower: 55, food: 2, san: 70,
    work: { kindling: 1 },
    skills: [[1, "tackle"], [4, "flameBurst"], [12, "ignitionBreath"]],
    drops: [["leather", 1, 1], ["flame_organ", 1, 1]],
    desc: "Fire fox kin. Keeps furnaces burning.", hostile: 1,
  },
  corlmite: {
    id: "corlmite", name: "Corlmite", glyph: "p", color: "#4d9de0",
    elements: ["water", "ice"], hp: 70, atk: 70, def: 70, speed: 2.4,
    capturePower: 50, food: 2, san: 70,
    work: { handiwork: 1, transporting: 1, watering: 1, cooling: 1 },
    skills: [[1, "tackle"], [4, "hydroJet"], [10, "iceMissile"]],
    drops: [["pal_fluid", 1, 1], ["ice_organ", 1, 1]],
    desc: "Penguin kin; waters crops and cools stores.", hostile: 1,
  },
  dozantler: {
    id: "dozantler", name: "Dozantler", glyph: "e", color: "#d4b96e",
    elements: ["neutral"], hp: 95, atk: 80, def: 75, speed: 3.4,
    capturePower: 65, food: 3, san: 80,
    work: { lumbering: 2 },
    skills: [[1, "tackle"], [6, "airCannon"], [14, "stoneShot"]],
    drops: [["leather", 1, 2], ["horn", 1, 1]],
    desc: "Stag kin with strong lumbering ability.", hostile: 1,
  },
  sprigmelt: {
    id: "sprigmelt", name: "Sprigmelt", glyph: "l", color: "#4caf50",
    elements: ["grass"], hp: 70, atk: 70, def: 70, speed: 3.0,
    capturePower: 50, food: 1, san: 70,
    work: { planting: 1, handiwork: 1, lumbering: 1, gathering: 1, medicine: 1 },
    skills: [[1, "tackle"], [4, "seedMachine"], [10, "grassTornado"]],
    drops: [["fiber", 1, 2], ["tomato_seeds", 1, 1]],
    desc: "Squirrel kin that sows fields.", hostile: 0,
  },
  briargoo: {
    id: "briargoo", name: "Briargoo", glyph: "t", color: "#9acd32",
    elements: ["grass"], hp: 75, atk: 75, def: 70, speed: 3.2,
    capturePower: 55, food: 2, san: 70,
    work: { planting: 1, handiwork: 1, lumbering: 1, transporting: 1, gathering: 1 },
    skills: [[1, "tackle"], [4, "seedMachine"], [12, "grassTornado"]],
    drops: [["fiber", 1, 2], ["mushroom", 1, 1]],
    desc: "Monkey kin; agile farmhand.", hostile: 1,
  },
  voltgoo: {
    id: "voltgoo", name: "Voltgoo", glyph: "s", color: "#e8d44d",
    elements: ["electric"], hp: 65, atk: 80, def: 60, speed: 3.1,
    capturePower: 60, food: 1, san: 70,
    work: { electricity: 1, handiwork: 1, transporting: 1 },
    skills: [[1, "tackle"], [4, "shockwave"], [12, "lightningStrike"]],
    drops: [["electric_organ", 1, 1]],
    desc: "Static mouse kin; powers generators.", hostile: 1,
  },
  faradlump: {
    id: "faradlump", name: "Faradlump", glyph: "j", color: "#e8e05c",
    elements: ["electric"], hp: 70, atk: 75, def: 60, speed: 3.0,
    capturePower: 55, food: 1, san: 60,
    work: { electricity: 1 },
    skills: [[1, "tackle"], [4, "shockwave"]],
    drops: [["electric_organ", 1, 1]],
    desc: "Hedgehog kin that crackles with charge.", hostile: 1,
  },
  loammelt: {
    id: "loammelt", name: "Loammelt", glyph: "d", color: "#b8935f",
    elements: ["ground"], hp: 90, atk: 70, def: 80, speed: 2.0,
    capturePower: 55, food: 3, san: 80,
    work: { watering: 1, mining: 1, transporting: 1, oilExtraction: 1 },
    skills: [[1, "tackle"], [5, "sandBlast"], [12, "stoneShot"]],
    drops: [["pal_fluid", 1, 1]],
    desc: "Mud fish; digs and hauls.", hostile: 1,
  },
  shademite: {
    id: "shademite", name: "Shademite", glyph: "D", color: "#6fa8d1",
    elements: ["dark"], hp: 70, atk: 75, def: 65, speed: 2.6,
    capturePower: 50, food: 1, san: 60,
    work: { handiwork: 1, transporting: 1, mining: 1 },
    skills: [[1, "tackle"], [4, "darkBall"], [10, "nightmare"]],
    drops: [["venom_gland", 1, 1]],
    desc: "Gloomy kin that still gets work done.", night: true, hostile: 1,
  },
  shadelump: {
    id: "shadelump", name: "Shadelump", glyph: "δ", color: "#c678dd",
    elements: ["dark"], hp: 70, atk: 80, def: 65, speed: 2.7,
    capturePower: 60, food: 2, san: 80,
    work: { handiwork: 1, transporting: 1, gathering: 1 },
    skills: [[1, "tackle"], [5, "darkBall"], [12, "nightmare"]],
    drops: [["poison_gland", 1, 1]],
    desc: "Dreamy night kin.", night: true, hostile: 1,
  },
  shademelt: {
    id: "shademelt", name: "Shademelt", glyph: "m", color: "#a8b5c4",
    elements: ["dark"], hp: 75, atk: 75, def: 70, speed: 2.9,
    capturePower: 65, food: 2, san: 70,
    work: { farming: 1 },
    skills: [[1, "tackle"], [5, "darkBall"]],
    drops: [["gold_coin", 1, 3]],
    desc: "Rare cat kin that digs up gold at a ranch.",
    farm: { item: "gold_coin", per: 90 }, night: true, hostile: 1,
  },
  loampuff: {
    id: "loampuff", name: "Loampuff", glyph: "R", color: "#d1813c",
    elements: ["ground"], hp: 85, atk: 85, def: 75, speed: 3.5,
    capturePower: 60, food: 3, san: 70,
    work: { mining: 1 },
    skills: [[1, "tackle"], [5, "sandBlast"], [12, "stoneShot"]],
    drops: [["leather", 1, 2], ["stone", 2, 4]],
    desc: "Boar kin that charges recklessly.", hostile: 2,
  },
  nibjelly: {
    id: "nibjelly", name: "Nibjelly", glyph: "C", color: "#f5eee0",
    elements: ["neutral"], hp: 75, atk: 70, def: 70, speed: 2.7,
    capturePower: 50, food: 2, san: 70,
    work: { gathering: 1, farming: 1 },
    skills: [[1, "tackle"], [4, "airCannon"]],
    drops: [["wool", 1, 2]],
    desc: "Fluffier than Fenjelly; also gives wool.",
    farm: { item: "wool", per: 70 }, hostile: 0,
  },
  piplump: {
    id: "piplump", name: "Piplump", glyph: "M", color: "#ede0c8",
    elements: ["neutral"], hp: 90, atk: 70, def: 80, speed: 2.2,
    capturePower: 60, food: 3, san: 80,
    work: { farming: 1 },
    skills: [[1, "tackle"], [5, "airCannon"]],
    drops: [["milk", 1, 2]],
    desc: "Cow kin producing milk at a ranch.",
    farm: { item: "milk", per: 60 }, hostile: 0,
  },
  marlump: {
    id: "marlump", name: "Marlump", glyph: "P", color: "#4d9de0",
    elements: ["water", "ice"], hp: 120, atk: 95, def: 90, speed: 2.4,
    capturePower: 90, food: 4, san: 90,
    work: { handiwork: 2, transporting: 2, watering: 2, cooling: 2, mining: 2 },
    skills: [[1, "tackle"], [3, "hydroJet"], [8, "iceMissile"], [16, "blizzard"]],
    drops: [["pal_fluid", 2, 4], ["ice_organ", 2, 3]],
    desc: "Regal penguin; master of base work.", hostile: 2,
  },
  quackbill: {
    id: "quackbill", name: "Quackbill", glyph: "F", color: "#4dd0e1",
    elements: ["water"], hp: 70, atk: 70, def: 65, speed: 2.6,
    capturePower: 50, food: 2, san: 70,
    work: { handiwork: 1, transporting: 1, watering: 1 },
    skills: [[1, "tackle"], [4, "hydroJet"]],
    drops: [["pal_fluid", 1, 1], ["leather", 1, 1]],
    desc: "Duck kin; decent water worker.", hostile: 1,
  },
};

export const SPECIES_LIST = Object.values(SPECIES);
