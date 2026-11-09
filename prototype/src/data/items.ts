// Items, food stats, sphere stats, weapons, and craft recipes.
export interface ItemDef {
  id: string;
  name: string;
  glyph: string;
  color: string;
  kind: "material" | "food" | "sphere" | "weapon" | "ammo" | "medicine" | "seed" | "gear" | "fruit" | "usable";
  stack: number;
  food?: number;     // nutrition restored
  hp?: number;       // hp restored
  san?: number;      // SAN restored (for pals)
  spherePower?: number; // capture stat
  weapon?: { dmg: number; range: number; cd: number; ammo?: string };
  heal?: number;
  usable?: boolean;  // can be activated from the inventory panel
  elem?: string;     // skill-fruit element
  tech?: string;     // tech node gating its recipe
  price?: number;    // merchant trade value in gold coins
  desc: string;
}

export const ITEMS: Record<string, ItemDef> = {
  // raw materials
  wood: { id: "wood", name: "Wood", glyph: "≡", color: "#8a6d4d", kind: "material", stack: 999, desc: "Basic building material." },
  stone: { id: "stone", name: "Stone", glyph: "■", color: "#6b6f72", kind: "material", stack: 999, desc: "Basic building material." },
  fiber: { id: "fiber", name: "Fiber", glyph: "∽", color: "#9acd32", kind: "material", stack: 999, desc: "Plant fibers for cordage." },
  paldium: { id: "paldium", name: "Paldium Fragment", glyph: "◊", color: "#4dd0e1", kind: "material", stack: 999, desc: "Glowing fragment; sphere crafting." },
  ore: { id: "ore", name: "Ore", glyph: "▓", color: "#a0622d", kind: "material", stack: 999, desc: "Smelt into ingots." },
  ingot: { id: "ingot", name: "Ingot", glyph: "▬", color: "#e8d44d", kind: "material", stack: 999, desc: "Refined metal." },
  nails: { id: "nails", name: "Nails", glyph: "†", color: "#7f8c8d", kind: "material", stack: 999, desc: "Iron nails." },
  leather: { id: "leather", name: "Leather", glyph: "▒", color: "#8a6d4d", kind: "material", stack: 999, desc: "Tanned hide." },
  wool: { id: "wool", name: "Wool", glyph: "◘", color: "#ede0c8", kind: "material", stack: 999, desc: "Soft wool." },
  cloth: { id: "cloth", name: "Cloth", glyph: "≋", color: "#e8f0f2", kind: "material", stack: 999, desc: "Woven cloth." },
  flame_organ: { id: "flame_organ", name: "Flame Organ", glyph: "♦", color: "#e8963c", kind: "material", stack: 999, desc: "Fire-aspected organ." },
  ice_organ: { id: "ice_organ", name: "Ice Organ", glyph: "*", color: "#4dd0e1", kind: "material", stack: 999, desc: "Ice-aspected organ." },
  electric_organ: { id: "electric_organ", name: "Electric Organ", glyph: "ϟ", color: "#e8d44d", kind: "material", stack: 999, desc: "Electric organ." },
  pal_fluid: { id: "pal_fluid", name: "Pal Fluid", glyph: "○", color: "#4d9de0", kind: "material", stack: 999, desc: "Fluid from water pals." },
  venom_gland: { id: "venom_gland", name: "Venom Gland", glyph: "•", color: "#c678dd", kind: "material", stack: 999, desc: "Toxic gland." },
  poison_gland: { id: "poison_gland", name: "Poison Gland", glyph: "•", color: "#8a4d99", kind: "material", stack: 999, desc: "Dark-tinged gland." },
  horn: { id: "horn", name: "Horn", glyph: "⌒", color: "#b8a468", kind: "material", stack: 999, desc: "Sturdy horn." },
  bone: { id: "bone", name: "Bone", glyph: "†", color: "#e8f0f2", kind: "material", stack: 999, desc: "Pal bone." },
  gold_coin: { id: "gold_coin", name: "Gold Coin", glyph: "$", color: "#e8d44d", kind: "material", stack: 9999, desc: "Currency." },
  gunpowder: { id: "gunpowder", name: "Gunpowder", glyph: "·", color: "#4d565c", kind: "material", stack: 999, desc: "Explosive powder." },

  // food
  red_berries: { id: "red_berries", name: "Red Berries", glyph: "•", color: "#e64533", kind: "food", stack: 999, food: 15, hp: 0, desc: "Common snack." },
  baked_berries: { id: "baked_berries", name: "Baked Berries", glyph: "•", color: "#e8963c", kind: "food", stack: 999, food: 25, desc: "Warmer, tastier." },
  mushroom: { id: "mushroom", name: "Mushroom", glyph: "♣", color: "#a08830", kind: "food", stack: 999, food: 12, desc: "Forest fungus." },
  egg: { id: "egg", name: "Egg", glyph: "○", color: "#ede0c8", kind: "food", stack: 999, food: 20, desc: "Chikipi egg." },
  milk: { id: "milk", name: "Milk", glyph: "○", color: "#e8f0f2", kind: "food", stack: 999, food: 15, desc: "Fresh milk." },
  wheat: { id: "wheat", name: "Wheat", glyph: "ψ", color: "#b8a468", kind: "food", stack: 999, food: 5, desc: "Mill into flour." },
  flour: { id: "flour", name: "Flour", glyph: "░", color: "#ede0c8", kind: "material", stack: 999, desc: "For baking." },
  bread: { id: "bread", name: "Bread", glyph: "▒", color: "#b8a468", kind: "food", stack: 999, food: 40, desc: "Filling loaf." },
  jam_bun: { id: "jam_bun", name: "Jam-filled Bun", glyph: "▒", color: "#e8963c", kind: "food", stack: 999, food: 55, desc: "Sweet bun." },
  chikipi_poultry: { id: "chikipi_poultry", name: "Chikipi Poultry", glyph: "♦", color: "#f2a0b5", kind: "food", stack: 999, food: 30, desc: "Poultry meat." },
  lamball_mutton: { id: "lamball_mutton", name: "Lamball Mutton", glyph: "♦", color: "#e64533", kind: "food", stack: 999, food: 35, desc: "Mutton." },
  fried_egg: { id: "fried_egg", name: "Fried Egg", glyph: "⊙", color: "#e8d44d", kind: "food", stack: 999, food: 40, desc: "Cooked egg." },
  cake: { id: "cake", name: "Cake", glyph: "▒", color: "#f2a0b5", kind: "food", stack: 999, food: 80, san: 15, desc: "Raises SAN a lot." },

  // seeds
  berry_seeds: { id: "berry_seeds", name: "Berry Seeds", glyph: "·", color: "#e64533", kind: "seed", stack: 999, desc: "Plant at a plantation." },
  wheat_seeds: { id: "wheat_seeds", name: "Wheat Seeds", glyph: "·", color: "#b8a468", kind: "seed", stack: 999, desc: "Plant at a plantation." },
  tomato_seeds: { id: "tomato_seeds", name: "Tomato Seeds", glyph: "·", color: "#9acd32", kind: "seed", stack: 999, desc: "Plant at a plantation." },

  // spheres (capture stat mirrors Palworld's tiers)
  pal_sphere: { id: "pal_sphere", name: "Pal Sphere", glyph: "◐", color: "#4d9de0", kind: "sphere", stack: 50, spherePower: 26, desc: "Standard sphere." },
  mega_sphere: { id: "mega_sphere", name: "Mega Sphere", glyph: "◐", color: "#4caf50", kind: "sphere", stack: 50, spherePower: 42, desc: "Improved sphere." },
  giga_sphere: { id: "giga_sphere", name: "Giga Sphere", glyph: "◐", color: "#e8d44d", kind: "sphere", stack: 50, spherePower: 58, desc: "Strong sphere." },
  ultra_sphere: { id: "ultra_sphere", name: "Ultra Sphere", glyph: "◐", color: "#e8963c", kind: "sphere", stack: 50, spherePower: 75, desc: "Very strong sphere." },
  legendary_sphere: { id: "legendary_sphere", name: "Legendary Sphere", glyph: "◐", color: "#e64533", kind: "sphere", stack: 50, spherePower: 95, desc: "Best sphere." },

  // weapons / tools
  wooden_club: { id: "wooden_club", name: "Wooden Club", glyph: "/", color: "#8a6d4d", kind: "weapon", stack: 1, weapon: { dmg: 15, range: 1.8, cd: 0.5 }, desc: "Crude melee weapon." },
  stone_spear: { id: "stone_spear", name: "Stone Spear", glyph: "↑", color: "#7f8c8d", kind: "weapon", stack: 1, weapon: { dmg: 25, range: 2.4, cd: 0.6 }, desc: "Poke from afar." },
  bow: { id: "bow", name: "Bow", glyph: ")", color: "#8a6d4d", kind: "weapon", stack: 1, weapon: { dmg: 20, range: 10, cd: 0.7, ammo: "arrow" }, desc: "Shoots arrows." },
  musket: { id: "musket", name: "Musket", glyph: "┐", color: "#5d4934", kind: "weapon", stack: 1, weapon: { dmg: 60, range: 12, cd: 2.2, ammo: "musket_ball" }, desc: "Slow but heavy shot." },
  metal_axe: { id: "metal_axe", name: "Metal Axe", glyph: "┤", color: "#7f8c8d", kind: "weapon", stack: 1, weapon: { dmg: 18, range: 1.8, cd: 0.55 }, desc: "Chops trees faster; decent weapon." },
  metal_pickaxe: { id: "metal_pickaxe", name: "Metal Pickaxe", glyph: "┬", color: "#7f8c8d", kind: "weapon", stack: 1, weapon: { dmg: 18, range: 1.8, cd: 0.55 }, desc: "Mines rocks faster; decent weapon." },
  arrow: { id: "arrow", name: "Arrow", glyph: "→", color: "#b8a468", kind: "ammo", stack: 999, desc: "Bow ammo." },
  musket_ball: { id: "musket_ball", name: "Musket Ball", glyph: "•", color: "#4d565c", kind: "ammo", stack: 999, desc: "Musket ammo." },

  // medicine
  low_medical: { id: "low_medical", name: "Low Grade Medical Supplies", glyph: "✚", color: "#4caf50", kind: "medicine", stack: 50, heal: 50, desc: "Heals pals/player." },
  medical_supplies: { id: "medical_supplies", name: "Medical Supplies", glyph: "✚", color: "#4dd0e1", kind: "medicine", stack: 50, heal: 150, desc: "Strong medicine." },

  // traversal gear + skill fruits
  glider: { id: "glider", name: "Glider", glyph: "▲", color: "#a8dff0", kind: "gear", stack: 1, tech: "glider", price: 120, desc: "Ride the wind: descend any cliff safely while carried." },
  saddle: { id: "saddle", name: "Pal Saddle", glyph: "◠", color: "#8a6d4d", kind: "gear", stack: 1, tech: "saddle", price: 90, desc: "Palworld saddle: required in the pack to ride any mount, land or air." },
  fishing_rod: { id: "fishing_rod", name: "Fishing Rod", glyph: "⁀", color: "#7fb069", kind: "gear", stack: 1, price: 80, desc: "Cast at the water's edge: bites bring loot — sometimes a live catch." },
  gauntlet_sigil: { id: "gauntlet_sigil", name: "Gauntlet Sigil", glyph: "♜", color: "#b06ee8", kind: "usable", usable: true, stack: 3, price: 0, desc: "Starts a 3-wave trial at your palbox. Tower rules: only the strong walk out." },
  ancient_part: { id: "ancient_part", name: "Ancient Part", glyph: "❖", color: "#9c8bd4", kind: "material", stack: 99, price: 40, desc: "Scrap from a lost age. Bosses drop it; ancient tech hungers for it." },
  meat_cleaver: { id: "meat_cleaver", name: "Meat Cleaver", glyph: "⚔", color: "#c0392b", kind: "weapon", stack: 1, tech: "meat_cleaver", price: 140, weapon: { dmg: 30, range: 1.6, cd: 0.5 }, desc: "Palworld's grim tool: butcher a boxed pal for its drops (palbox ✕)." },
  skill_fruit_neutral: { id: "skill_fruit_neutral", name: "Neutral Skill Fruit", glyph: "●", color: "#c8d3d5", kind: "fruit", usable: true, stack: 10, elem: "neutral", price: 60, desc: "Teaches the active pal a neutral move." },
  skill_fruit_fire: { id: "skill_fruit_fire", name: "Fire Skill Fruit", glyph: "●", color: "#e8963c", kind: "fruit", usable: true, stack: 10, elem: "fire", price: 60, desc: "Teaches the active pal a fire move." },
  skill_fruit_water: { id: "skill_fruit_water", name: "Water Skill Fruit", glyph: "●", color: "#4d9de0", kind: "fruit", usable: true, stack: 10, elem: "water", price: 60, desc: "Teaches the active pal a water move." },
  skill_fruit_grass: { id: "skill_fruit_grass", name: "Grass Skill Fruit", glyph: "●", color: "#4caf50", kind: "fruit", usable: true, stack: 10, elem: "grass", price: 60, desc: "Teaches the active pal a grass move." },
  skill_fruit_electric: { id: "skill_fruit_electric", name: "Electric Skill Fruit", glyph: "●", color: "#e8d44d", kind: "fruit", usable: true, stack: 10, elem: "electric", price: 60, desc: "Teaches the active pal an electric move." },
  skill_fruit_ice: { id: "skill_fruit_ice", name: "Ice Skill Fruit", glyph: "●", color: "#a8dff0", kind: "fruit", usable: true, stack: 10, elem: "ice", price: 60, desc: "Teaches the active pal an ice move." },
  skill_fruit_ground: { id: "skill_fruit_ground", name: "Ground Skill Fruit", glyph: "●", color: "#b8935f", kind: "fruit", usable: true, stack: 10, elem: "ground", price: 60, desc: "Teaches the active pal a ground move." },
  skill_fruit_dark: { id: "skill_fruit_dark", name: "Dark Skill Fruit", glyph: "●", color: "#7a5ac9", kind: "fruit", usable: true, stack: 10, elem: "dark", price: 60, desc: "Teaches the active pal a dark move." },
  skill_fruit_dragon: { id: "skill_fruit_dragon", name: "Dragon Skill Fruit", glyph: "●", color: "#e64533", kind: "fruit", usable: true, stack: 10, elem: "dragon", price: 80, desc: "Teaches the active pal a dragon move." },
};

export interface Recipe {
  id: string;
  out: [string, number];
  cost: [string, number][];
  station: "hand" | "workbench" | "campfire" | "furnace";
  work: number; // work points to complete (player does 30/s, pals use workRate)
}

export const RECIPES: Recipe[] = [
  { id: "club", out: ["wooden_club", 1], cost: [["wood", 5]], station: "hand", work: 30 },
  { id: "spear", out: ["stone_spear", 1], cost: [["wood", 8], ["stone", 4]], station: "workbench", work: 80 },
  { id: "bow", out: ["bow", 1], cost: [["wood", 10], ["fiber", 8]], station: "workbench", work: 100 },
  { id: "arrow", out: ["arrow", 6], cost: [["wood", 2], ["stone", 1]], station: "workbench", work: 40 },
  { id: "musket", out: ["musket", 1], cost: [["ingot", 10], ["wood", 10], ["gunpowder", 5]], station: "workbench", work: 400 },
  { id: "musket_ball", out: ["musket_ball", 5], cost: [["ingot", 1], ["gunpowder", 1]], station: "workbench", work: 60 },
  { id: "axe", out: ["metal_axe", 1], cost: [["ingot", 5], ["wood", 5]], station: "workbench", work: 200 },
  { id: "pick", out: ["metal_pickaxe", 1], cost: [["ingot", 5], ["wood", 5]], station: "workbench", work: 200 },
  { id: "nails", out: ["nails", 4], cost: [["ingot", 1]], station: "workbench", work: 40 },
  { id: "cloth", out: ["cloth", 2], cost: [["wool", 3]], station: "workbench", work: 60 },
  { id: "pal_sphere", out: ["pal_sphere", 1], cost: [["paldium", 3], ["wood", 3], ["stone", 3]], station: "workbench", work: 90 },
  { id: "mega_sphere", out: ["mega_sphere", 1], cost: [["paldium", 6], ["ingot", 3], ["wood", 5]], station: "workbench", work: 180 },
  { id: "giga_sphere", out: ["giga_sphere", 1], cost: [["paldium", 12], ["ingot", 6], ["electric_organ", 2]], station: "workbench", work: 300 },
  { id: "ultra_sphere", out: ["ultra_sphere", 1], cost: [["paldium", 20], ["ingot", 10], ["ice_organ", 3], ["flame_organ", 3]], station: "workbench", work: 500 },
  { id: "legendary_sphere", out: ["legendary_sphere", 1], cost: [["paldium", 35], ["ingot", 15], ["poison_gland", 4], ["electric_organ", 4]], station: "workbench", work: 800 },
  { id: "low_med", out: ["low_medical", 2], cost: [["red_berries", 5], ["mushroom", 3]], station: "workbench", work: 80 },
  { id: "med", out: ["medical_supplies", 1], cost: [["pal_fluid", 3], ["venom_gland", 2], ["cloth", 2]], station: "workbench", work: 200 },
  { id: "baked_berries", out: ["baked_berries", 2], cost: [["red_berries", 3]], station: "campfire", work: 30 },
  { id: "fried_egg", out: ["fried_egg", 1], cost: [["egg", 1]], station: "campfire", work: 20 },
  { id: "jam_bun", out: ["jam_bun", 1], cost: [["flour", 1], ["red_berries", 2]], station: "campfire", work: 60 },
  { id: "flour", out: ["flour", 1], cost: [["wheat", 3]], station: "workbench", work: 40 },
  { id: "bread", out: ["bread", 1], cost: [["flour", 2]], station: "campfire", work: 80 },
  { id: "cake", out: ["cake", 1], cost: [["flour", 2], ["milk", 2], ["egg", 1], ["red_berries", 3]], station: "campfire", work: 150 },
  { id: "gunpowder", out: ["gunpowder", 2], cost: [["venom_gland", 1], ["stone", 2]], station: "workbench", work: 40 },
  { id: "glider", out: ["glider", 1], cost: [["cloth", 4], ["fiber", 10], ["leather", 2]], station: "workbench", work: 120 },
  { id: "saddle", out: ["saddle", 1], cost: [["leather", 3], ["fiber", 8], ["wood", 4]], station: "workbench", work: 100 },
  { id: "fishing_rod", out: ["fishing_rod", 1], cost: [["wood", 8], ["fiber", 6], ["paldium", 2]], station: "workbench", work: 80 },
  { id: "meat_cleaver", out: ["meat_cleaver", 1], cost: [["ingot", 4], ["wood", 2]], station: "workbench", work: 90 },
];
