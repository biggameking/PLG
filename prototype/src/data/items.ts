// Items, food stats, orb stats, weapons, and craft recipes.
export interface ItemDef {
  id: string;
  name: string;
  glyph: string;
  color: string;
  kind: "material" | "food" | "orb" | "weapon" | "ammo" | "medicine" | "seed" | "gear" | "fruit" | "usable";
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
  buff?: { atk?: number; def?: number; spd?: number; t: number }; // the island meal buff — timed % bonus
  desc: string;
}

export const ITEMS: Record<string, ItemDef> = {
  // raw materials
  wood: { id: "wood", name: "Wood", glyph: "≡", color: "#8a6d4d", kind: "material", stack: 999, desc: "Basic building material." },
  stone: { id: "stone", name: "Stone", glyph: "■", color: "#6b6f72", kind: "material", stack: 999, desc: "Basic building material." },
  spoiled_food: { id: "spoiled_food", name: "Spoiled Food", glyph: "☒", color: "#6a5a3a", kind: "material", price: 1, desc: "Rotten scraps — unfit for man or kin. A staffed ice box would have saved it." },
  fertilizer: { id: "fertilizer", name: "Fertilizer", glyph: "❀", color: "#8a9a3a", kind: "material", price: 12, desc: "Rich compost — use it standing by a field and the crops surge for five minutes." },
  raw_fish: { id: "raw_fish", name: "Raw Fish", glyph: "≋", color: "#6aa8d8", kind: "food", perish: true, stack: 999, food: 25, desc: "Fresh from the weir — better cooked." },
  fried_fish: { id: "fried_fish", name: "Fried Fish", glyph: "≋", color: "#d8a84a", kind: "food", stack: 999, food: 55, buff: { spd: 0.15, t: 300 }, desc: "Crisp shore-side fare — +15% speed for a while." },
  glowcap_soup: { id: "glowcap_soup", name: "Glowcap Soup", glyph: "♨", color: "#8ef0a8", kind: "food", stack: 999, food: 30, buff: { glow: 5.0, t: 240 }, desc: "Cave mushrooms simmered down — you glow for a while." },
  spicy_stew: { id: "spicy_stew", name: "Spicy Stew", glyph: "♨", color: "#c04830", kind: "food", stack: 999, food: 65, buff: { warm: 1, t: 300 }, desc: "Campfire chili — an inner hearth no chill can reach, for a while." },
  mint_salad: { id: "mint_salad", name: "Mint Salad", glyph: "❧", color: "#7ac08a", kind: "food", stack: 999, food: 40, buff: { cool: 1, t: 300 }, desc: "Crisp leaves and cold greens — the noon sun slides off you, for a while." },
  kin_bait: { id: "kin_bait", name: "Kin Bait", glyph: "❁", color: "#d8b84a", kind: "material", stack: 999, price: 8, desc: "A honeyed berry mash — toss it out and hungry wild kin come sniffing." },
  treasure_map: { id: "treasure_map", name: "Treasure Map", glyph: "✕", color: "#c9a15a", kind: "material", stack: 999, price: 60, desc: "A surveyor's faded chart — follow the gold mark and dig where it lands." },
  honey: { id: "honey", name: "Honey", glyph: "◍", color: "#e8b830", kind: "food", stack: 999, food: 15, price: 10, desc: "Sweet comb straight from the apiary." },
  honey_bun: { id: "honey_bun", name: "Honey Bun", glyph: "◍", color: "#d89a40", kind: "food", stack: 999, food: 45, buff: { spd: 0.1, t: 300 }, desc: "Glazed and golden — +10% speed for a while." },
  fiber: { id: "fiber", name: "Fiber", glyph: "∽", color: "#9acd32", kind: "material", stack: 999, desc: "Plant fibers for cordage." },
  lumenite: { id: "lumenite", name: "Lumenite Shard", glyph: "◊", color: "#4dd0e1", kind: "material", stack: 999, desc: "Glowing fragment; orb crafting." },
  ore: { id: "ore", name: "Ore", glyph: "▓", color: "#a0622d", kind: "material", stack: 999, desc: "Smelt into ingots." },
  ingot: { id: "ingot", name: "Ingot", glyph: "▬", color: "#e8d44d", kind: "material", stack: 999, desc: "Refined metal." },
  nails: { id: "nails", name: "Nails", glyph: "†", color: "#7f8c8d", kind: "material", stack: 999, desc: "Iron nails." },
  leather: { id: "leather", name: "Leather", glyph: "▒", color: "#8a6d4d", kind: "material", stack: 999, desc: "Tanned hide." },
  wool: { id: "wool", name: "Wool", glyph: "◘", color: "#ede0c8", kind: "material", stack: 999, desc: "Soft wool." },
  cloth: { id: "cloth", name: "Cloth", glyph: "≋", color: "#e8f0f2", kind: "material", stack: 999, desc: "Woven cloth." },
  flame_organ: { id: "flame_organ", name: "Flame Organ", glyph: "♦", color: "#e8963c", kind: "material", stack: 999, desc: "Fire-aspected organ." },
  ice_organ: { id: "ice_organ", name: "Ice Organ", glyph: "*", color: "#4dd0e1", kind: "material", stack: 999, desc: "Ice-aspected organ." },
  electric_organ: { id: "electric_organ", name: "Electric Organ", glyph: "ϟ", color: "#e8d44d", kind: "material", stack: 999, desc: "Electric organ." },
  kin_fluid: { id: "kin_fluid", name: "Kin Fluid", glyph: "○", color: "#4d9de0", kind: "material", stack: 999, desc: "Fluid from water kin." },
  venom_gland: { id: "venom_gland", name: "Venom Gland", glyph: "•", color: "#c678dd", kind: "material", stack: 999, desc: "Toxic gland." },
  poison_gland: { id: "poison_gland", name: "Poison Gland", glyph: "•", color: "#8a4d99", kind: "material", stack: 999, desc: "Dark-tinged gland." },
  horn: { id: "horn", name: "Horn", glyph: "⌒", color: "#b8a468", kind: "material", stack: 999, desc: "Sturdy horn." },
  bone: { id: "bone", name: "Bone", glyph: "†", color: "#e8f0f2", kind: "material", stack: 999, desc: "Kin bone." },
  gold_coin: { id: "gold_coin", name: "Gold Coin", glyph: "$", color: "#e8d44d", kind: "material", stack: 9999, desc: "Currency." },
  gunpowder: { id: "gunpowder", name: "Gunpowder", glyph: "·", color: "#4d565c", kind: "material", stack: 999, desc: "Explosive powder." },

  // food
  red_berries: { id: "red_berries", name: "Red Berries", glyph: "•", color: "#e64533", kind: "food", stack: 999, food: 15, hp: 0, desc: "Common snack." },
  baked_berries: { id: "baked_berries", name: "Baked Berries", glyph: "•", color: "#e8963c", kind: "food", stack: 999, food: 25, desc: "Warmer, tastier." },
  mushroom: { id: "mushroom", name: "Mushroom", glyph: "♣", color: "#a08830", kind: "food", stack: 999, food: 12, desc: "Forest fungus." },
  egg: { id: "egg", name: "Egg", glyph: "○", color: "#ede0c8", kind: "food", stack: 999, food: 20, desc: "Fenlump egg." },
  milk: { id: "milk", name: "Milk", glyph: "○", color: "#e8f0f2", kind: "food", stack: 999, food: 15, desc: "Fresh milk." },
  wheat: { id: "wheat", name: "Wheat", glyph: "ψ", color: "#b8a468", kind: "food", stack: 999, food: 5, desc: "Mill into flour." },
  flour: { id: "flour", name: "Flour", glyph: "░", color: "#ede0c8", kind: "material", stack: 999, desc: "For baking." },
  bread: { id: "bread", name: "Bread", glyph: "▒", color: "#b8a468", kind: "food", stack: 999, food: 40, desc: "Filling loaf." },
  jam_bun: { id: "jam_bun", name: "Jam-filled Bun", glyph: "▒", color: "#e8963c", kind: "food", stack: 999, food: 55, buff: { atk: 0.1, t: 300 }, desc: "Sweet bun. +10% attack for a while." },
  fenlump_poultry: { id: "fenlump_poultry", name: "Fenlump Poultry", glyph: "♦", color: "#f2a0b5", kind: "food", stack: 999, food: 30, desc: "Poultry meat." },
  fenjelly_mutton: { id: "fenjelly_mutton", name: "Fenjelly Mutton", glyph: "♦", color: "#e64533", kind: "food", stack: 999, food: 35, desc: "Mutton." },
  roast_mutton: { id: "roast_mutton", name: "Roast Mutton", glyph: "♦", color: "#b86a30", kind: "food", stack: 999, food: 60, price: 18, buff: { def: 0.1, t: 300 }, desc: "grilled fenjelly — +10% defense for a while." },
  fried_egg: { id: "fried_egg", name: "Fried Egg", glyph: "⊙", color: "#e8d44d", kind: "food", stack: 999, food: 40, buff: { spd: 0.1, t: 300 }, desc: "Cooked egg. +10% speed for a while." },
  cake: { id: "cake", name: "Cake", glyph: "▒", color: "#f2a0b5", kind: "food", stack: 999, food: 80, san: 15, desc: "Raises SAN a lot." },

  // seeds
  berry_seeds: { id: "berry_seeds", name: "Berry Seeds", glyph: "·", color: "#e64533", kind: "seed", stack: 999, desc: "Plant at a plantation." },
  wheat_seeds: { id: "wheat_seeds", name: "Wheat Seeds", glyph: "·", color: "#b8a468", kind: "seed", stack: 999, desc: "Plant at a plantation." },
  tomato_seeds: { id: "tomato_seeds", name: "Tomato Seeds", glyph: "·", color: "#9acd32", kind: "seed", stack: 999, desc: "Plant at a plantation." },

  // orbs (capture stat mirrors tiers)
  kin_orb: { id: "kin_orb", name: "Kin Orb", glyph: "◐", color: "#4d9de0", kind: "orb", stack: 50, spherePower: 26, desc: "Standard orb." },
  mega_orb: { id: "mega_orb", name: "Mega Orb", glyph: "◐", color: "#4caf50", kind: "orb", stack: 50, spherePower: 42, desc: "Improved orb." },
  giga_orb: { id: "giga_orb", name: "Giga Orb", glyph: "◐", color: "#e8d44d", kind: "orb", stack: 50, spherePower: 58, desc: "Strong orb." },
  ultra_orb: { id: "ultra_orb", name: "Ultra Orb", glyph: "◐", color: "#e8963c", kind: "orb", stack: 50, spherePower: 75, desc: "Very strong orb." },
  legendary_orb: { id: "legendary_orb", name: "Legendary Orb", glyph: "◐", color: "#e64533", kind: "orb", stack: 50, spherePower: 95, desc: "Best orb." },

  // weapons / tools
  wooden_club: { id: "wooden_club", name: "Wooden Club", glyph: "/", color: "#8a6d4d", kind: "weapon", stack: 1, weapon: { dmg: 15, range: 1.8, cd: 0.5 }, desc: "Crude melee weapon." },
  stone_spear: { id: "stone_spear", name: "Stone Spear", glyph: "↑", color: "#7f8c8d", kind: "weapon", stack: 1, weapon: { dmg: 25, range: 2.4, cd: 0.6 }, desc: "Poke from afar." },
  bow: { id: "bow", name: "Bow", glyph: ")", color: "#8a6d4d", kind: "weapon", stack: 1, weapon: { dmg: 20, range: 10, cd: 0.7, ammo: "arrow" }, desc: "Shoots arrows." },
  musket: { id: "musket", name: "Musket", glyph: "┐", color: "#5d4934", kind: "weapon", stack: 1, weapon: { dmg: 60, range: 12, cd: 2.2, ammo: "musket_ball" }, desc: "Slow but heavy shot." },
  tranq_gun: { id: "tranq_gun", name: "Tranquilizer Gun", glyph: "¬", color: "#7ab87a", kind: "weapon", stack: 1, weapon: { dmg: 6, range: 10, cd: 1.0, ammo: "tranq_dart" }, desc: "A puff of sedative, not a slug — darts put a wild kin down for the count." },
  metal_axe: { id: "metal_axe", name: "Metal Axe", glyph: "┤", color: "#7f8c8d", kind: "weapon", stack: 1, weapon: { dmg: 18, range: 1.8, cd: 0.55 }, desc: "Chops trees faster; decent weapon." },
  metal_pickaxe: { id: "metal_pickaxe", name: "Metal Pickaxe", glyph: "┬", color: "#7f8c8d", kind: "weapon", stack: 1, weapon: { dmg: 18, range: 1.8, cd: 0.55 }, desc: "Mines rocks faster; decent weapon." },
  arrow: { id: "arrow", name: "Arrow", glyph: "→", color: "#b8a468", kind: "ammo", stack: 999, desc: "Bow ammo." },
  musket_ball: { id: "musket_ball", name: "Musket Ball", glyph: "•", color: "#4d565c", kind: "ammo", stack: 999, desc: "Musket ammo." },
  tranq_dart: { id: "tranq_dart", name: "Tranq Dart", glyph: "⌁", color: "#7ab87a", kind: "ammo", stack: 999, desc: "Venom-coated dart — Tranquilizer Gun ammo." },

  // medicine
  low_medical: { id: "low_medical", name: "Low Grade Medical Supplies", glyph: "✚", color: "#4caf50", kind: "medicine", stack: 50, heal: 50, desc: "Heals kin/player." },
  medical_supplies: { id: "medical_supplies", name: "Medical Supplies", glyph: "✚", color: "#4dd0e1", kind: "medicine", stack: 50, heal: 150, desc: "Strong medicine." },

  // traversal gear + skill fruits
  glider: { id: "glider", name: "Glider", glyph: "▲", color: "#a8dff0", kind: "gear", stack: 1, tech: "glider", price: 120, desc: "Ride the wind: descend any cliff safely while carried." },
  saddle: { id: "saddle", name: "Kin Saddle", glyph: "◠", color: "#8a6d4d", kind: "gear", stack: 1, tech: "saddle", price: 90, desc: "a riding saddle: required in the pack to ride a land mount." },
  sky_saddle: { id: "sky_saddle", name: "Sky Saddle", glyph: "◠", color: "#7fb8e8", kind: "gear", stack: 1, tech: "sky_saddle", price: 160, desc: "a riding saddle: required in the pack to ride a flying mount." },
  wave_saddle: { id: "wave_saddle", name: "Wave Saddle", glyph: "◠", color: "#4d8a8a", kind: "gear", stack: 1, tech: "wave_saddle", price: 140, desc: "a riding saddle: required in the pack to ride a swimming mount." },
  grappling_hook: { id: "grappling_hook", name: "Grappling Hook", glyph: "┌", color: "#b8b8d4", kind: "gear", stack: 1, tech: "grappling_hook", price: 180, desc: "a hookshot: haul yourself UP a cliff face — one-way, no descents." },
  cindlump_harness: { id: "cindlump_harness", name: "Cindlump Harness", glyph: "◠", color: "#e88a4d", kind: "gear", stack: 1, tech: "cindlump_harness", price: 200, desc: "Kin gear: unlocks Cindlump' Flamethrower partner skill." },
  sprigmelt_smg: { id: "sprigmelt_smg", name: "Sprigmelt SMG", glyph: "┐", color: "#8ab86a", kind: "gear", stack: 1, tech: "sprigmelt_smg", price: 240, desc: "Kin gear: unlocks Sprigmelt's SMG Burst partner skill." },
  briargoo_rifle: { id: "briargoo_rifle", name: "Briargoo Assault Rifle", glyph: "┐", color: "#6a9ab8", kind: "gear", stack: 1, tech: "briargoo_rifle", price: 260, desc: "Kin gear: unlocks Briargoo's Rifle Shot partner skill." },
  corlmite_launcher: { id: "corlmite_launcher", name: "Corlmite Launcher", glyph: "⊙", color: "#7ec8e3", kind: "gear", stack: 1, tech: "corlmite_launcher", price: 320, desc: "Kin gear: loads Corlmite for its signature Penguin Cannon." },
  fishing_rod: { id: "fishing_rod", name: "Fishing Rod", glyph: "⁀", color: "#7fb069", kind: "gear", stack: 1, price: 80, desc: "Cast at the water's edge: bites bring loot — sometimes a live catch." },
  gauntlet_sigil: { id: "gauntlet_sigil", name: "Gauntlet Sigil", glyph: "♜", color: "#b06ee8", kind: "usable", usable: true, stack: 3, price: 0, desc: "Starts a 3-wave trial at your kinbox. A crowned keeper faces a fourth, apex wave." },
  ancient_part: { id: "ancient_part", name: "Ancient Part", glyph: "❖", color: "#9c8bd4", kind: "material", stack: 99, price: 40, desc: "Scrap from a lost age. Bosses drop it; ancient tech hungers for it." },
  meat_cleaver: { id: "meat_cleaver", name: "Meat Cleaver", glyph: "⚔", color: "#c0392b", kind: "weapon", stack: 1, tech: "meat_cleaver", price: 140, weapon: { dmg: 30, range: 1.6, cd: 0.5 }, desc: "grim tool: butcher a boxed kin for its drops (kinbox ✕)." },
  skill_fruit_neutral: { id: "skill_fruit_neutral", name: "Neutral Skill Fruit", glyph: "●", color: "#c8d3d5", kind: "fruit", usable: true, stack: 10, elem: "neutral", price: 60, desc: "Teaches the active kin a neutral move." },
  skill_fruit_fire: { id: "skill_fruit_fire", name: "Fire Skill Fruit", glyph: "●", color: "#e8963c", kind: "fruit", usable: true, stack: 10, elem: "fire", price: 60, desc: "Teaches the active kin a fire move." },
  skill_fruit_water: { id: "skill_fruit_water", name: "Water Skill Fruit", glyph: "●", color: "#4d9de0", kind: "fruit", usable: true, stack: 10, elem: "water", price: 60, desc: "Teaches the active kin a water move." },
  skill_fruit_grass: { id: "skill_fruit_grass", name: "Grass Skill Fruit", glyph: "●", color: "#4caf50", kind: "fruit", usable: true, stack: 10, elem: "grass", price: 60, desc: "Teaches the active kin a grass move." },
  skill_fruit_electric: { id: "skill_fruit_electric", name: "Electric Skill Fruit", glyph: "●", color: "#e8d44d", kind: "fruit", usable: true, stack: 10, elem: "electric", price: 60, desc: "Teaches the active kin an electric move." },
  skill_fruit_ice: { id: "skill_fruit_ice", name: "Ice Skill Fruit", glyph: "●", color: "#a8dff0", kind: "fruit", usable: true, stack: 10, elem: "ice", price: 60, desc: "Teaches the active kin an ice move." },
  skill_fruit_ground: { id: "skill_fruit_ground", name: "Ground Skill Fruit", glyph: "●", color: "#b8935f", kind: "fruit", usable: true, stack: 10, elem: "ground", price: 60, desc: "Teaches the active kin a ground move." },
  skill_fruit_dark: { id: "skill_fruit_dark", name: "Dark Skill Fruit", glyph: "●", color: "#7a5ac9", kind: "fruit", usable: true, stack: 10, elem: "dark", price: 60, desc: "Teaches the active kin a dark move." },
  skill_fruit_dragon: { id: "skill_fruit_dragon", name: "Dragon Skill Fruit", glyph: "●", color: "#e64533", kind: "fruit", usable: true, stack: 10, elem: "dragon", price: 80, desc: "Teaches the active kin a dragon move." },

  // trinkets — two accessory slots
  attack_pendant: { id: "attack_pendant", name: "Attack Pendant", glyph: "†", color: "#e8963c", kind: "accessory", stack: 1, price: 150, desc: "a trinket: +12% damage dealt." },
  defense_pendant: { id: "defense_pendant", name: "Defense Pendant", glyph: "⛨", color: "#7fb8e8", kind: "accessory", stack: 1, price: 150, desc: "a trinket: +5 armor." },
  swift_charm: { id: "swift_charm", name: "Swift Charm", glyph: "≫", color: "#8ef0ff", kind: "accessory", stack: 1, price: 150, desc: "a trinket: +10% move speed." },
  mercy_ring: { id: "mercy_ring", name: "Ring of Mercy", glyph: "♡", color: "#f0a0b8", kind: "accessory", stack: 1, price: 300, desc: "a trinket: your blows weaken wild kin but can never drop one below 1 HP." },
  miner_cap: { id: "miner_cap", name: "Miner's Cap", glyph: "◠", color: "#e8c86a", kind: "armor", stack: 1, price: 120, desc: "A leather cap with a carbide lamp — both hands free in the dark." },
  kin_egg: { id: "kin_egg", name: "Kin Egg", usable: true, stack: 5, price: 30, desc: "A wild egg — nest find or market oddity. Use to hatch." },
  bred_kin_egg: { id: "bred_kin_egg", name: "Bred Egg", usable: true, stack: 5, price: 50, desc: "A ranch pairing's egg — its bloodline is on record. Use to hatch." },
  huge_kin_egg: { id: "huge_kin_egg", name: "Huge Kin Egg", usable: true, stack: 5, price: 200, desc: "Something enormous stirs inside. Incubate for a guaranteed Lucky kin." },
  sprigmelt_effigy: { id: "sprigmelt_effigy", name: "Sprigmelt Effigy", stack: 99, price: 0, desc: "A green mouse idol. Spend at the statue (U) to upgrade powers." },
  boss_sigil: { id: "boss_sigil", name: "Boss Sigil", usable: true, stack: 5, price: 0, desc: "Summons a raid boss at your kinbox. Use it. If you dare." },
  coal: { id: "coal", name: "Coal", glyph: "●", color: "#3c3a36", kind: "material", stack: 999, desc: "Fuel for hot work." },
  polymer: { id: "polymer", name: "Polymer", glyph: "⬡", color: "#a45ec0", kind: "material", stack: 999, desc: "Oil-derived material for top-tier gear." },
  schematic_bow: { id: "schematic_bow", name: "Bow Schematic", glyph: "§", color: "#6ab8f0", kind: "material", price: 150, desc: "Blueprint for a reworked bow — keep it in the bag to craft the Mk. II." },
  schematic_musket: { id: "schematic_musket", name: "Musket Schematic", glyph: "§", color: "#6ab8f0", kind: "material", price: 300, desc: "Blueprint for a reworked musket — keep it in the bag to craft the Mk. II." },
  memory_wipe: { id: "memory_wipe", name: "Memory Wiping Medicine", glyph: "◌", color: "#c08cff", kind: "medicine", usable: true, stack: 10, price: 120, desc: "a full respec: refunds every statue perk as stat points." },
  hide_armor: { id: "hide_armor", name: "Hide Armor", kind: "armor", armor: { def: 4, dur: 120 }, warm: 1, stack: 1, price: 40, desc: "Stitched hides. Better than skin — and warmer." },
  metal_armor: { id: "metal_armor", name: "Metal Armor", kind: "armor", armor: { def: 9, dur: 200 }, stack: 1, price: 140, desc: "Plated protection for rough country." },
  tropic_armor: { id: "tropic_armor", name: "Tropical Outfit", kind: "armor", armor: { def: 5, dur: 140 }, cool: 1, stack: 1, price: 90, desc: "Open weave and a wide brim — keeps the southern sun off your neck." },
  dragon_scale: { id: "dragon_scale", name: "Dragonscale Armor", kind: "armor", armor: { def: 14, dur: 300 }, warm: 2, stack: 1, price: 400, desc: "Near-impenetrable plate of shed scales — still warm." },
  bow_mk2: { id: "bow_mk2", name: "Bow Mk. II", glyph: ")", color: "#6ab8f0", kind: "weapon", stack: 1, weapon: { dmg: 32, range: 11, cd: 0.55, ammo: "arrow", dur: 110 }, desc: "Schematic-built: lighter draw, heavier string." },
  musket_mk2: { id: "musket_mk2", name: "Musket Mk. II", glyph: "┐", color: "#6ab8f0", kind: "weapon", stack: 1, weapon: { dmg: 85, range: 13, cd: 2.0, ammo: "musket_ball", dur: 90 }, desc: "Schematic-built: rifled barrel, faster lock." },
  orb_launcher: { id: "orb_launcher", tech: "orb_launcher", name: "Orb Launcher", glyph: "◎", color: "#7a5fa8", kind: "weapon", stack: 1, price: 300, weapon: { dmg: 5, range: 8, cd: 1.0, dur: 40 }, desc: "Hurls your selected orb downrange — catches without creeping close." },
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
  { id: "tranq_gun", out: ["tranq_gun", 1], cost: [["ingot", 8], ["wood", 6], ["poison_gland", 4]], station: "workbench", work: 250 },
  { id: "tranq_dart", out: ["tranq_dart", 8], cost: [["fiber", 2], ["venom_gland", 1]], station: "workbench", work: 40 },
  { id: "axe", out: ["metal_axe", 1], cost: [["ingot", 5], ["wood", 5]], station: "workbench", work: 200 },
  { id: "pick", out: ["metal_pickaxe", 1], cost: [["ingot", 5], ["wood", 5]], station: "workbench", work: 200 },
  { id: "nails", out: ["nails", 4], cost: [["ingot", 1]], station: "workbench", work: 40 },
  { id: "cloth", out: ["cloth", 2], cost: [["wool", 3]], station: "workbench", work: 60 },
  { id: "kin_orb", out: ["kin_orb", 1], cost: [["lumenite", 3], ["wood", 3], ["stone", 3]], station: "workbench", work: 90 },
  { id: "mega_orb", out: ["mega_orb", 1], cost: [["lumenite", 6], ["ingot", 3], ["wood", 5]], station: "workbench", work: 180 },
  { id: "giga_orb", out: ["giga_orb", 1], cost: [["lumenite", 12], ["ingot", 6], ["electric_organ", 2]], station: "workbench", work: 300 },
  { id: "ultra_orb", out: ["ultra_orb", 1], cost: [["lumenite", 20], ["ingot", 10], ["ice_organ", 3], ["flame_organ", 3]], station: "workbench", work: 500 },
  { id: "legendary_orb", out: ["legendary_orb", 1], cost: [["lumenite", 35], ["ingot", 15], ["poison_gland", 4], ["electric_organ", 4]], station: "workbench", work: 800 },
  { id: "low_med", out: ["low_medical", 2], cost: [["red_berries", 5], ["mushroom", 3]], station: "workbench", work: 80 },
  { id: "med", out: ["medical_supplies", 1], cost: [["kin_fluid", 3], ["venom_gland", 2], ["cloth", 2]], station: "workbench", work: 200 },
  { id: "baked_berries", out: ["baked_berries", 2], cost: [["red_berries", 3]], station: "campfire", work: 30 },
  { id: "fried_egg", out: ["fried_egg", 1], cost: [["egg", 1]], station: "campfire", work: 20 },
  { id: "roast_mutton", out: ["roast_mutton", 1], cost: [["fenjelly_mutton", 1]], station: "campfire", work: 40 },
  { id: "fried_fish", out: ["fried_fish", 1], cost: [["raw_fish", 1]], station: "campfire", work: 40 },
  { id: "glowcap_soup", out: ["glowcap_soup", 1], cost: [["mushroom", 3]], station: "campfire", work: 40 },
  { id: "kin_bait", out: ["kin_bait", 2], cost: [["red_berries", 4], ["fiber", 1]], station: "workbench", work: 20 },
  { id: "honey_bun", out: ["honey_bun", 1], cost: [["honey", 2], ["flour", 1]], station: "campfire", work: 50 },
  { id: "spicy_stew", out: ["spicy_stew", 1], cost: [["fenjelly_mutton", 1], ["red_berries", 3]], station: "campfire", work: 50 },
  { id: "mint_salad", out: ["mint_salad", 1], cost: [["mushroom", 2], ["wheat", 1]], station: "workbench", work: 30 },
  { id: "jam_bun", out: ["jam_bun", 1], cost: [["flour", 1], ["red_berries", 2]], station: "campfire", work: 60 },
  { id: "flour", out: ["flour", 1], cost: [["wheat", 3]], station: "workbench", work: 40 },
  { id: "bread", out: ["bread", 1], cost: [["flour", 2]], station: "campfire", work: 80 },
  { id: "cake", out: ["cake", 1], cost: [["flour", 2], ["milk", 2], ["egg", 1], ["red_berries", 3]], station: "campfire", work: 150 },
  { id: "gunpowder", out: ["gunpowder", 2], cost: [["venom_gland", 1], ["stone", 2]], station: "workbench", work: 40 },
  { id: "glider", out: ["glider", 1], cost: [["cloth", 4], ["fiber", 10], ["leather", 2]], station: "workbench", work: 120 },
  { id: "grappling_hook", out: ["grappling_hook", 1], cost: [["ingot", 4], ["fiber", 10], ["lumenite", 3]], station: "workbench", work: 140 },
  { id: "cindlump_harness", out: ["cindlump_harness", 1], cost: [["leather", 4], ["fiber", 8], ["ingot", 2], ["lumenite", 2]], station: "workbench", work: 120 },
  { id: "sprigmelt_smg", out: ["sprigmelt_smg", 1], cost: [["ingot", 6], ["wood", 4], ["lumenite", 3]], station: "workbench", work: 160 },
  { id: "briargoo_rifle", out: ["briargoo_rifle", 1], cost: [["ingot", 8], ["wood", 6], ["lumenite", 4]], station: "workbench", work: 180 },
  { id: "corlmite_launcher", tech: "corlmite_launcher", out: ["corlmite_launcher", 1], cost: [["ingot", 6], ["lumenite", 4], ["ice_organ", 3], ["fiber", 6]], station: "workbench", work: 180 },
  { id: "saddle", out: ["saddle", 1], cost: [["leather", 3], ["fiber", 8], ["wood", 4]], station: "workbench", work: 100 },
  { id: "sky_saddle", out: ["sky_saddle", 1], cost: [["leather", 4], ["fiber", 10], ["lumenite", 2]], station: "workbench", work: 140 },
  { id: "wave_saddle", out: ["wave_saddle", 1], cost: [["leather", 4], ["fiber", 8], ["lumenite", 2]], station: "workbench", work: 120 },
  { id: "fishing_rod", out: ["fishing_rod", 1], cost: [["wood", 8], ["fiber", 6], ["lumenite", 2]], station: "workbench", work: 80 },
  { id: "meat_cleaver", out: ["meat_cleaver", 1], cost: [["ingot", 4], ["wood", 2]], station: "workbench", work: 90 },
  { id: "attack_pendant", out: ["attack_pendant", 1], cost: [["cloth", 3], ["lumenite", 4], ["gold_coin", 20]], station: "workbench", work: 160 },
  { id: "defense_pendant", out: ["defense_pendant", 1], cost: [["cloth", 3], ["ingot", 4], ["gold_coin", 20]], station: "workbench", work: 160 },
  { id: "swift_charm", out: ["swift_charm", 1], cost: [["cloth", 3], ["fiber", 6], ["lumenite", 2]], station: "workbench", work: 160 },
  { id: "mercy_ring", out: ["mercy_ring", 1], cost: [["cloth", 3], ["lumenite", 6], ["gold_coin", 30]], station: "workbench", work: 160 },
  { id: "miner_cap", out: ["miner_cap", 1], cost: [["leather", 6], ["ingot", 4], ["lumenite", 3]], station: "workbench", work: 140 },
];
