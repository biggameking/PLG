// Buildable base structures: cost, footprint, and the jobs they generate.
import { Work } from "./work.ts";

export type JobKind =
  | "mine" | "lumber" | "crush" | "smelt" | "plant" | "water" | "harvest"
  | "workbench" | "ranch" | "transport" | "power";

export interface StructureDef {
  id: string;
  name: string;
  glyph: string;
  color: string;
  w: number; // footprint in tiles
  h: number;
  cost: [string, number][];
  job?: {
    kind: JobKind;
    workType: Work;       // suitability needed
    amount: number;       // work points per cycle
    produces?: [string, number][]; // per cycle output
    consumes?: [string, number][]; // per cycle input
    power?: boolean;      // wants a powered grid nearby
  };
  farmField?: boolean;    // plant-water-harvest cycle
  ranch?: boolean;
  storage?: number;       // slots for transport target
  bed?: number;           // rest slots for pals
  feedBox?: boolean;
  light?: number;         // light radius
  anchor?: boolean;       // kinbox
  hp?: number;            // structural HP — raiders chew through buildings
  walkable?: boolean;     // entities may cross (spikes still hurt hostiles)
  spike?: number;         // damage per tick to hostiles standing on it
  turret?: number;        // damage per shot at the nearest hostile in range
  incubator?: boolean;    // hatches deposited pal eggs on a timer
  spring?: number;        // SAN recovery strength (the island hot spring)
  stand?: boolean;        // monitoring stand: faster work, faster SAN drain
  playerBed?: boolean;
  desc: string;
}

export const STRUCTURES: Record<string, StructureDef> = {
  kinbox: {
    id: "kinbox", name: "Kinbox", glyph: "☼", color: "#4dd0e1", w: 2, h: 2,
    cost: [["lumenite", 4], ["wood", 6], ["stone", 6]],
    anchor: true, light: 4,
    desc: "Base anchor. Deploy stored kin; manage party.",
  },
  kin_bed: {
    id: "kin_bed", name: "Kin Bed", glyph: "▭", color: "#ede0c8", w: 2, h: 1,
    cost: [["wood", 8], ["fiber", 4]],
    bed: 1,
    desc: "A bed for a kin to sleep and restore SAN.",
  },
  feed_box: {
    id: "feed_box", name: "Feed Box", glyph: "π", color: "#b8a468", w: 1, h: 1,
    cost: [["wood", 6]],
    feedBox: true, storage: 8,
    desc: "Kin eat from it automatically.",
  },
  campfire: {
    id: "campfire", name: "Campfire", glyph: "♦", color: "#e8963c", w: 1, h: 1,
    cost: [["wood", 6], ["stone", 3]],
    light: 5, job: { kind: "workbench", workType: "kindling", amount: 30, produces: [], consumes: [] },
    desc: "Cooks food, gives light. Needs no kin for cooking.",
  },
  workbench: {
    id: "workbench", name: "Primitive Workbench", glyph: "⚒", color: "#7f8c8d", w: 2, h: 1,
    cost: [["wood", 10], ["stone", 4]],
    job: { kind: "workbench", workType: "handiwork", amount: 0 },
    desc: "Queue items; handiwork kin or you build them.",
  },
  logging_site: {
    id: "logging_site", name: "Logging Site", glyph: "↑", color: "#4d7d47", w: 2, h: 2,
    cost: [["wood", 12], ["stone", 4], ["fiber", 4]],
    job: { kind: "lumber", workType: "lumbering", amount: 60, produces: [["wood", 2]] },
    desc: "A lumbering kin produces wood here.",
  },
  stone_pit: {
    id: "stone_pit", name: "Stone Pit", glyph: "◙", color: "#6b6f72", w: 2, h: 2,
    cost: [["wood", 8], ["stone", 12]],
    job: { kind: "mine", workType: "mining", amount: 60, produces: [["stone", 2]] },
    desc: "A mining kin produces stone here.",
  },
  ore_mine: {
    id: "ore_mine", name: "Ore Excavation Site", glyph: "▓", color: "#a0622d", w: 2, h: 2,
    cost: [["wood", 10], ["stone", 15], ["nails", 4]],
    job: { kind: "mine", workType: "mining", amount: 90, produces: [["ore", 1]] },
    desc: "A mining kin digs ore here.",
  },
  crusher: {
    id: "crusher", name: "Crusher", glyph: "▲", color: "#4d9de0", w: 2, h: 2,
    cost: [["wood", 15], ["stone", 10]],
    job: { kind: "crush", workType: "watering", amount: 50, produces: [["lumenite", 1]], consumes: [["stone", 5]] },
    desc: "Water-powered crusher: 5 stone → 1 lumenite.",
  },
  furnace: {
    id: "furnace", name: "Primitive Furnace", glyph: "▲", color: "#e8963c", w: 2, h: 2,
    cost: [["stone", 15], ["wood", 10], ["flame_organ", 2]],
    light: 3,
    job: { kind: "smelt", workType: "kindling", amount: 80, produces: [["ingot", 1]], consumes: [["ore", 2]] },
    desc: "Kindling kin smelts 2 ore → 1 ingot.",
  },
  mill: {
    id: "mill", name: "Mill", glyph: "Ω", color: "#7f8c8d", w: 2, h: 2,
    cost: [["wood", 15], ["stone", 8], ["cloth", 2]],
    job: { kind: "crush", workType: "watering", amount: 60, produces: [["flour", 1]], consumes: [["wheat", 3]] },
    desc: "Grinds 3 wheat → 1 flour (water-powered).",
  },
  berry_farm: {
    id: "berry_farm", name: "Berry Plantation", glyph: "♣", color: "#e64533", w: 3, h: 2,
    cost: [["wood", 8], ["fiber", 6], ["berry_seeds", 3]],
    farmField: true,
    desc: "Grows red berries: plant → water → gather.",
  },
  wheat_farm: {
    id: "wheat_farm", name: "Wheat Plantation", glyph: "ψ", color: "#b8a468", w: 3, h: 2,
    cost: [["wood", 8], ["fiber", 6], ["wheat_seeds", 3]],
    farmField: true,
    desc: "Grows wheat: plant → water → gather.",
  },
  ranch: {
    id: "ranch", name: "Ranch", glyph: "⌂", color: "#8a6d4d", w: 4, h: 3,
    cost: [["wood", 20], ["stone", 10], ["fiber", 8]],
    ranch: true,
    desc: "Assign farming kin; they produce goods.",
  },
  chest: {
    id: "chest", name: "Wooden Chest", glyph: "□", color: "#8a6d4d", w: 1, h: 1,
    cost: [["wood", 8]],
    storage: 12,
    desc: "Kin transport produce here.",
  },
  generator: {
    id: "generator", name: "Power Generator", glyph: "ϟ", color: "#e8d44d", w: 2, h: 2,
    cost: [["ingot", 10], ["electric_organ", 5]],
    job: { kind: "power", workType: "electricity", amount: 40 },
    desc: "An electric kin charges it; powered stations work 50% faster.",
  },
  torch: {
    id: "torch", name: "Torch", glyph: "†", color: "#e8963c", w: 1, h: 1,
    cost: [["wood", 2], ["fiber", 1]],
    light: 4,
    desc: "Simple light source.",
  },
  waypoint: {
    id: "waypoint", name: "Waypoint", glyph: "◇", color: "#7fc8f8", w: 1, h: 1,
    cost: [["stone", 20], ["lumenite", 5]],
    light: 5, hp: 400,
    desc: "the island fast-travel stone: touch it to blink back to your kinbox.",
  },
  straw_bed: {
    id: "straw_bed", name: "Straw Bed", glyph: "▭", color: "#b8a468", w: 2, h: 1,
    cost: [["wood", 10], ["fiber", 8]],
    playerBed: true,
    desc: "Sleep to skip to morning and heal.",
  },
  incubator: {
    id: "incubator", name: "Egg Incubator", glyph: "◍", color: "#f2a0b5", w: 2, h: 2,
    cost: [["lumenite", 2], ["stone", 10], ["cloth", 2]],
    incubator: true, hp: 200, light: 2,
    desc: "Hatches kin eggs over time. A nearby campfire speeds it up.",
  },
  wooden_wall: {
    id: "wooden_wall", name: "Wooden Wall", glyph: "┃", color: "#8a6d4d", w: 1, h: 1,
    cost: [["wood", 2]], hp: 300,
    desc: "Blocks movement. Raiders must chew through it.",
  },
  spikes: {
    id: "spikes", name: "Wooden Spikes", glyph: "╳", color: "#a98a5e", w: 1, h: 1,
    cost: [["wood", 4], ["stone", 2]], walkable: true, spike: 6, hp: 100,
    desc: "Hostiles stepping on it bleed. Walkable, but rude.",
  },
  hot_spring: {
    id: "hot_spring", name: "Hot Spring", glyph: "♨", color: "#7ec8e3", w: 2, h: 2,
    cost: [["stone", 20], ["wood", 10], ["lumenite", 3]],
    spring: 1, hp: 250, light: 1,
    desc: "Steam does wonders. Base kin recover SAN faster than any bed.",
  },
  monitoring_stand: {
    id: "monitoring_stand", name: "Monitoring Stand", glyph: "⚑", color: "#d06a6a", w: 1, h: 1,
    cost: [["wood", 10], ["stone", 10], ["ingot", 2]],
    stand: true, hp: 200,
    desc: "Overseer post: +40% work speed base-wide, but SAN drains half again as fast.",
  },
  sphere_factory: {
    id: "sphere_factory", name: "Sphere Works", glyph: "◉", color: "#4dd0e1", w: 2, h: 1,
    cost: [["wood", 20], ["stone", 15], ["lumenite", 5], ["ingot", 4]],
    job: { kind: "assemble", workType: "handiwork", amount: 200,
      consumes: [["lumenite", 1], ["wood", 1], ["stone", 1]],
      produces: [["kin_orb", 1]] },
    desc: "assembly line — a handy kin rolls a sphere off the belt.",
  },
  expedition_post: {
    id: "expedition_post", name: "Expedition Post", glyph: "⚑", color: "#c9a15a", w: 2, h: 1,
    cost: [["wood", 30], ["stone", 15], ["ingot", 4], ["cloth", 2]],
    job: { kind: "expedition", workType: "gathering", amount: 600 },
    desc: "Assign a gatherer and it marches off-post, returning with a haul keyed to its element.",
  },
  sphere_factory_2: {
    id: "sphere_factory_2", name: "Giga Works", glyph: "◉", color: "#4dd0e1", w: 2, h: 1,
    cost: [["stone", 20], ["ingot", 8], ["lumenite", 10], ["electric_organ", 4]],
    job: { kind: "assemble", workType: "handiwork", amount: 300,
      consumes: [["lumenite", 3], ["ingot", 2], ["electric_organ", 1]],
      produces: [["giga_orb", 1]] },
    desc: "the island assembly line II — the organ-fed belt rolls giga spheres.",
  },
  compost_bin: {
    id: "compost_bin", name: "Compost Bin", glyph: "♻", color: "#7a9a4a", w: 1, h: 1,
    cost: [["wood", 10], ["stone", 4]],
    job: { kind: "work", workType: "farming", amount: 90,
      consumes: [["spoiled_food", 2], ["fiber", 1]], produces: [["fertilizer", 1]] },
    desc: "A farming kin turns rot and straw into rich fertilizer — every scrap earns its keep.",
  },
  training_dummy: {
    id: "training_dummy", name: "Training Dummy", glyph: "‡", color: "#a08050", w: 1, h: 1,
    hp: 200,
    cost: [["wood", 15], ["fiber", 6]],
    desc: "A straw sparring partner — idle kin swing on it and grow a little stronger.",
  },
  guard_post: {
    id: "guard_post", name: "Guard Post", glyph: "⚑", color: "#b06a50", w: 1, h: 1,
    hp: 150,
    cost: [["wood", 12], ["stone", 6]],
    job: { kind: "guard", workType: "", amount: 0 },
    desc: "A watch platform — post a kin here and it patrols a wider beat.",
  },
  training_hall: {
    id: "training_hall", name: "Training Hall", glyph: "⚔", color: "#8a6a4a", w: 2, h: 2,
    hp: 220,
    cost: [["wood", 20], ["stone", 15], ["lumenite", 4]],
    job: { kind: "mentor", workType: "", amount: 90 },
    desc: "A drill hall — post a veteran and it passes its moves to the yard's youngsters.",
  },
  sparring_ring: {
    id: "sparring_ring", name: "Sparring Ring", glyph: "⊗", color: "#a87848", w: 2, h: 2,
    hp: 180,
    cost: [["wood", 15], ["cloth", 4]],
    job: { kind: "spar", workType: "", amount: 60 },
    desc: "A roped pit — pair two kin here and they spar on the bell: the winner learns more, both spend spirit.",
  },
  notice_board: {
    id: "notice_board", name: "Notice Board", glyph: "▤", color: "#c9a15a", w: 1, h: 1,
    hp: 80,
    cost: [["wood", 8], ["fiber", 3]],
    desc: "A pitch-pine board — each dawn a fresh request goes up: fill it for coin and credit.",
  },
  fossil_bed: {
    id: "fossil_bed", name: "Fossil Bed", glyph: "☠", color: "#c8b890", w: 1, h: 1,
    hp: 60,
    cost: [],
    desc: "Old bones heaped in the dirt — dig here and the deep past pays out in parts.",
  },
  kin_gacha: {
    id: "kin_gacha", name: "Kin Gacha", glyph: "◉", color: "#e8b830", w: 1, h: 1,
    hp: 120,
    cost: [["wood", 10], ["ingot", 6], ["lumenite", 4]],
    desc: "A brass capsule machine — feed it 20 gold and it rattles out an egg. Mostly ordinary; once in a while it coughs up something huge.",
  },
  snare_trap: {
    id: "snare_trap", name: "Snare Trap", glyph: "⋔", color: "#8a7a5a", w: 1, h: 1,
    hp: 40, walkable: true, snare: true,
    cost: [["wood", 5], ["fiber", 2]],
    desc: "A leaf-litter snare — the first wild kin to step on it is held fast a few seconds. One bite and it's spent.",
  },
  war_banner: {
    id: "war_banner", name: "War Banner", glyph: "⚑", color: "#b84a3a", w: 1, h: 1,
    hp: 100,
    cost: [["wood", 10], ["cloth", 6]],
    desc: "A dyed banner on a tall pole — kin working within sight of its colors put on a little more pace.",
  },
  spyglass: {
    id: "spyglass", name: "Spyglass Tower", glyph: "◎", color: "#7a9ab8", w: 1, h: 1,
    hp: 140,
    cost: [["wood", 12], ["cloth", 4], ["ingot", 2]],
    desc: "A lookout platform with a brass spyglass — every half minute it charts a little more of the wilds around it.",
  },
  well: {
    id: "well", name: "Well", glyph: "◍", color: "#6a8ab0", w: 1, h: 1,
    hp: 120,
    cost: [["stone", 15]],
    desc: "A ring of stone over a driven shaft — fields within its shadow stay watered even in fair skies.",
  },
  lightning_rod: {
    id: "lightning_rod", name: "Lightning Rod", glyph: "↯", color: "#d8c04a", w: 1, h: 1,
    hp: 110,
    cost: [["ingot", 8], ["lumenite", 4]],
    desc: "A copper finger raised at the sky — in a storm it drinks the lightning and banks the charge as organs.",
  },
  kin_cage: {
    id: "kin_cage", name: "Kin Cage", glyph: "▦", color: "#6a7a8a", w: 1, h: 1,
    hp: 150,
    cost: [],
    desc: "Iron bars and a padlock — someone inside is having a very bad day.",
  },
  weather_shrine: {
    id: "weather_shrine", name: "Weather Shrine", glyph: "☂", color: "#7fb8d8", w: 1, h: 1,
    cost: [["stone", 20], ["lumenite", 10]],
    desc: "A sky-touched altar — offer lumenite and the heavens take requests.",
  },
  apiary: {
    id: "apiary", name: "Apiary", glyph: "◍", color: "#d8b830", w: 1, h: 1,
    cost: [["wood", 12], ["fiber", 8]],
    job: { kind: "work", workType: "planting", amount: 120, produces: [["honey", 1]] },
    desc: "A skep of tame bees — a planting kin keeps the comb full.",
  },
  fish_trap: {
    id: "fish_trap", name: "Fish Trap", glyph: "≋", color: "#5a8ac0", w: 1, h: 1,
    needsWater: true,
    cost: [["wood", 15], ["fiber", 6]],
    job: { kind: "work", workType: "watering", amount: 150, produces: [["raw_fish", 1]] },
    desc: "A woven weir at the water's edge — a watering kin works the catch. Build beside water.",
  },
  watch_tower: {
    id: "watch_tower", name: "Watch Tower", glyph: "♜", color: "#c9a86a", w: 1, h: 1,
    cost: [["wood", 20], ["stone", 10], ["ingot", 2]], turret: 14, hp: 300, light: 1,
    desc: "Looses an arrow at the nearest raider or riled wild kin every few seconds.",
  },
};

export interface TechNode {
  id: string;           // structure id or recipe id to unlock
  name: string;
  tier: number;
  cost: number;         // tech points
  parts?: number;       // ancient-tech: consumes ancient_part drops
}

export const TECH: TechNode[] = [
  { id: "workbench", name: "Primitive Workbench", tier: 1, cost: 1 },
  { id: "spear", name: "Stone Spear", tier: 1, cost: 1 },
  { id: "kin_bed", name: "Kin Bed", tier: 1, cost: 1 },
  { id: "feed_box", name: "Feed Box", tier: 1, cost: 1 },
  { id: "campfire", name: "Campfire", tier: 1, cost: 1 },
  { id: "logging_site", name: "Logging Site", tier: 2, cost: 2 },
  { id: "stone_pit", name: "Stone Pit", tier: 2, cost: 2 },
  { id: "berry_farm", name: "Berry Plantation", tier: 2, cost: 2 },
  { id: "bow", name: "Bow", tier: 2, cost: 2 },
  { id: "arrow", name: "Arrow", tier: 2, cost: 1 },
  { id: "ranch", name: "Ranch", tier: 3, cost: 2 },
  { id: "chest", name: "Wooden Chest", tier: 3, cost: 1 },
  { id: "crusher", name: "Crusher", tier: 3, cost: 2 },
  { id: "torch", name: "Torch", tier: 3, cost: 1 },
  { id: "wheat_farm", name: "Wheat Plantation", tier: 3, cost: 2 },
  { id: "straw_bed", name: "Straw Bed", tier: 3, cost: 1 },
  { id: "furnace", name: "Primitive Furnace", tier: 4, cost: 3 },
  { id: "mill", name: "Mill", tier: 4, cost: 2 },
  { id: "mega_orb", name: "Mega Orb", tier: 4, cost: 2 },
  { id: "axe", name: "Metal Axe", tier: 4, cost: 2 },
  { id: "pick", name: "Metal Pickaxe", tier: 4, cost: 2 },
  { id: "ore_mine", name: "Ore Excavation Site", tier: 5, cost: 3 },
  { id: "generator", name: "Power Generator", tier: 5, cost: 3 },
  { id: "giga_orb", name: "Giga Orb", tier: 5, cost: 3 },
  { id: "musket", name: "Musket", tier: 6, cost: 3, parts: 3 },
  { id: "tranq_gun", name: "Tranquilizer Gun", tier: 5, cost: 2, parts: 1 },
  { id: "musket_ball", name: "Musket Ball", tier: 6, cost: 1 },
  { id: "ultra_orb", name: "Ultra Orb", tier: 7, cost: 4 },
  { id: "legendary_orb", name: "Legendary Orb", tier: 8, cost: 5 },
  { id: "wooden_wall", name: "Wooden Wall", tier: 2, cost: 1 },
  { id: "spikes", name: "Wooden Spikes", tier: 3, cost: 1 },
  { id: "incubator", name: "Egg Incubator", tier: 4, cost: 2, parts: 2 },
  { id: "glider", name: "Glider", tier: 4, cost: 2 },
  { id: "grappling_hook", name: "Grappling Hook", tier: 5, cost: 2 },
  { id: "saddle", name: "Kin Saddle", tier: 3, cost: 1 },
  { id: "wave_saddle", name: "Wave Saddle", tier: 3, cost: 1 },
  { id: "sky_saddle", name: "Sky Saddle", tier: 4, cost: 2 },
  { id: "cindlump_harness", name: "Cindlump Harness", tier: 4, cost: 2 },
  { id: "sprigmelt_smg", name: "Sprigmelt SMG", tier: 4, cost: 2 },
  { id: "briargoo_rifle", name: "Briargoo Assault Rifle", tier: 5, cost: 2 },
  { id: "corlmite_launcher", name: "Corlmite Launcher", tier: 6, cost: 2, parts: 1 },
  { id: "meat_cleaver", name: "Meat Cleaver", tier: 3, cost: 1 },
  { id: "waypoint", name: "Waypoint", tier: 4, cost: 2 },
  { id: "hot_spring", name: "Hot Spring", tier: 5, cost: 3 },
  { id: "monitoring_stand", name: "Monitoring Stand", tier: 5, cost: 2, parts: 2 },
  { id: "watch_tower", name: "Watch Tower", tier: 4, cost: 2, parts: 1 },
  { id: "sphere_factory", name: "Sphere Works", tier: 5, cost: 3, parts: 1 },
  { id: "expedition_post", name: "Expedition Post", tier: 7, cost: 3, parts: 1 },
  { id: "sphere_factory_2", name: "Giga Works", tier: 8, cost: 4, parts: 2 },
  { id: "compost_bin", name: "Compost Bin", tier: 2, cost: 1 },
  { id: "fish_trap", name: "Fish Trap", tier: 3, cost: 1 },
  { id: "training_dummy", name: "Training Dummy", tier: 4, cost: 1 },
  { id: "apiary", name: "Apiary", tier: 3, cost: 1 },
  { id: "weather_shrine", name: "Weather Shrine", tier: 6, cost: 2 },
  { id: "guard_post", name: "Guard Post", tier: 4, cost: 1 },
  { id: "training_hall", name: "Training Hall", tier: 5, cost: 2 },
  { id: "sparring_ring", name: "Sparring Ring", tier: 4, cost: 1 },
  { id: "notice_board", name: "Notice Board", tier: 2, cost: 1 },
  { id: "snare_trap", name: "Snare Trap", tier: 2, cost: 1 },
  { id: "kin_gacha", name: "Kin Gacha", tier: 4, cost: 1 },
  { id: "war_banner", name: "War Banner", tier: 4, cost: 1 },
  { id: "spyglass", name: "Spyglass Tower", tier: 5, cost: 2 },
  { id: "well", name: "Well", tier: 3, cost: 1 },
  { id: "lightning_rod", name: "Lightning Rod", tier: 5, cost: 2 },
];
