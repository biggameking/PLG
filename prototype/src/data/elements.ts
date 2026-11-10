// element chart: each element is super-effective vs ~1 element,
// resisted by itself. Neutral is weak vs Dark, strong vs nothing.
export type Element =
  | "neutral" | "fire" | "water" | "grass" | "electric"
  | "ice" | "ground" | "dark" | "dragon";

// effectiveness[attacker][defender] = multiplier
export const CHART: Record<Element, Partial<Record<Element, number>>> = {
  neutral: {},
  fire: { grass: 2, ice: 2, fire: 0.5 },
  water: { fire: 2, water: 0.5 },
  grass: { ground: 2, grass: 0.5 },
  electric: { water: 2, electric: 0.5 },
  ice: { dragon: 2, ice: 0.5 },
  ground: { electric: 2, ground: 0.5 },
  dark: { neutral: 2, dark: 0.5 },
  dragon: { dark: 2, dragon: 0.5 },
};

export function effectiveness(atk: Element, defs: Element[]): number {
  let m = 1;
  for (const d of defs) m *= CHART[atk][d] ?? 1;
  return m;
}

export const ELEMENT_COLOR: Record<Element, string> = {
  neutral: "#c8d3d5",
  fire: "#e8963c",
  water: "#4d9de0",
  grass: "#4caf50",
  electric: "#e8d44d",
  ice: "#4dd0e1",
  ground: "#8a6d4d",
  dark: "#c678dd",
  dragon: "#b05ce0",
};

export const ELEMENT_GLYPH: Record<Element, string> = {
  neutral: "○", fire: "♦", water: "≈", grass: "♣", electric: "ϟ",
  ice: "*", ground: "▲", dark: "◘", dragon: "Ω",
};
