// Work suitabilities — Palworld's base-job system.
export type Work =
  | "kindling" | "watering" | "planting" | "electricity"
  | "handiwork" | "gathering" | "lumbering" | "mining"
  | "medicine" | "cooling" | "transporting" | "farming";

export const WORK_LABEL: Record<Work, string> = {
  kindling: "Kindling",
  watering: "Watering",
  planting: "Planting",
  electricity: "Electricity",
  handiwork: "Handiwork",
  gathering: "Gathering",
  lumbering: "Lumbering",
  mining: "Mining",
  medicine: "Medicine",
  cooling: "Cooling",
  transporting: "Transporting",
  farming: "Farming",
};

export const WORK_GLYPH: Record<Work, string> = {
  kindling: "♦", watering: "≈", planting: "♣", electricity: "ϟ",
  handiwork: "⚒", gathering: "☰", lumbering: "↑", mining: "◙",
  medicine: "✚", cooling: "*", transporting: "►", farming: "♥",
};

// How much work a Lv-suitability pal does per second of effort.
export function workRate(level: number): number {
  return level <= 0 ? 0 : level * level * 3; // L1=3, L2=12, L3=27, L4=48
}
