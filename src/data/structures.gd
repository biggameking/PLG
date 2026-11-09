# Auto-generated from prototype/src/data/structures.ts — do not edit by hand
class_name StructureData

const STRUCTURES = {
 "palbox": {
  "id": "palbox",
  "name": "Palbox",
  "glyph": "☼",
  "color": "#4dd0e1",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "paldium",
    4
   ],
   [
    "wood",
    6
   ],
   [
    "stone",
    6
   ]
  ],
  "anchor": true,
  "light": 4,
  "desc": "Base anchor. Deploy stored pals; manage party."
 },
 "pal_bed": {
  "id": "pal_bed",
  "name": "Pal Bed",
  "glyph": "▭",
  "color": "#ede0c8",
  "w": 2,
  "h": 1,
  "cost": [
   [
    "wood",
    8
   ],
   [
    "fiber",
    4
   ]
  ],
  "bed": 1,
  "desc": "A bed for a pal to sleep and restore SAN."
 },
 "feed_box": {
  "id": "feed_box",
  "name": "Feed Box",
  "glyph": "π",
  "color": "#b8a468",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "wood",
    6
   ]
  ],
  "feedBox": true,
  "storage": 8,
  "desc": "Pals eat from it automatically."
 },
 "campfire": {
  "id": "campfire",
  "name": "Campfire",
  "glyph": "♦",
  "color": "#e8963c",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "wood",
    6
   ],
   [
    "stone",
    3
   ]
  ],
  "light": 5,
  "job": {
   "kind": "workbench",
   "workType": "kindling",
   "amount": 30,
   "produces": [],
   "consumes": []
  },
  "desc": "Cooks food, gives light. Needs no pal for cooking."
 },
 "workbench": {
  "id": "workbench",
  "name": "Primitive Workbench",
  "glyph": "⚒",
  "color": "#7f8c8d",
  "w": 2,
  "h": 1,
  "cost": [
   [
    "wood",
    10
   ],
   [
    "stone",
    4
   ]
  ],
  "job": {
   "kind": "workbench",
   "workType": "handiwork",
   "amount": 0
  },
  "desc": "Queue items; handiwork pals or you build them."
 },
 "logging_site": {
  "id": "logging_site",
  "name": "Logging Site",
  "glyph": "↑",
  "color": "#4d7d47",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "wood",
    12
   ],
   [
    "stone",
    4
   ],
   [
    "fiber",
    4
   ]
  ],
  "job": {
   "kind": "lumber",
   "workType": "lumbering",
   "amount": 60,
   "produces": [
    [
     "wood",
     2
    ]
   ]
  },
  "desc": "A lumbering pal produces wood here."
 },
 "stone_pit": {
  "id": "stone_pit",
  "name": "Stone Pit",
  "glyph": "◙",
  "color": "#6b6f72",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "wood",
    8
   ],
   [
    "stone",
    12
   ]
  ],
  "job": {
   "kind": "mine",
   "workType": "mining",
   "amount": 60,
   "produces": [
    [
     "stone",
     2
    ]
   ]
  },
  "desc": "A mining pal produces stone here."
 },
 "ore_mine": {
  "id": "ore_mine",
  "name": "Ore Excavation Site",
  "glyph": "▓",
  "color": "#a0622d",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "wood",
    10
   ],
   [
    "stone",
    15
   ],
   [
    "nails",
    4
   ]
  ],
  "job": {
   "kind": "mine",
   "workType": "mining",
   "amount": 90,
   "produces": [
    [
     "ore",
     1
    ]
   ]
  },
  "desc": "A mining pal digs ore here."
 },
 "crusher": {
  "id": "crusher",
  "name": "Crusher",
  "glyph": "▲",
  "color": "#4d9de0",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "wood",
    15
   ],
   [
    "stone",
    10
   ]
  ],
  "job": {
   "kind": "crush",
   "workType": "watering",
   "amount": 50,
   "produces": [
    [
     "paldium",
     1
    ]
   ],
   "consumes": [
    [
     "stone",
     5
    ]
   ]
  },
  "desc": "Water-powered crusher: 5 stone → 1 paldium."
 },
 "furnace": {
  "id": "furnace",
  "name": "Primitive Furnace",
  "glyph": "▲",
  "color": "#e8963c",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "stone",
    15
   ],
   [
    "wood",
    10
   ],
   [
    "flame_organ",
    2
   ]
  ],
  "light": 3,
  "job": {
   "kind": "smelt",
   "workType": "kindling",
   "amount": 80,
   "produces": [
    [
     "ingot",
     1
    ]
   ],
   "consumes": [
    [
     "ore",
     2
    ]
   ]
  },
  "desc": "Kindling pal smelts 2 ore → 1 ingot."
 },
 "mill": {
  "id": "mill",
  "name": "Mill",
  "glyph": "Ω",
  "color": "#7f8c8d",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "wood",
    15
   ],
   [
    "stone",
    8
   ],
   [
    "cloth",
    2
   ]
  ],
  "job": {
   "kind": "crush",
   "workType": "watering",
   "amount": 60,
   "produces": [
    [
     "flour",
     1
    ]
   ],
   "consumes": [
    [
     "wheat",
     3
    ]
   ]
  },
  "desc": "Grinds 3 wheat → 1 flour (water-powered)."
 },
 "berry_farm": {
  "id": "berry_farm",
  "job": {"kind": "farm", "workType": "farming", "amount": 90, "produces": [["red_berries", 2]]},
  "name": "Berry Plantation",
  "glyph": "♣",
  "color": "#e64533",
  "w": 3,
  "h": 2,
  "cost": [
   [
    "wood",
    8
   ],
   [
    "fiber",
    6
   ],
   [
    "berry_seeds",
    3
   ]
  ],
  "farmField": true,
  "desc": "Grows red berries: plant → water → gather."
 },
 "wheat_farm": {
  "id": "wheat_farm",
  "job": {"kind": "farm", "workType": "planting", "amount": 120, "produces": [["wheat", 2]]},
  "name": "Wheat Plantation",
  "glyph": "ψ",
  "color": "#b8a468",
  "w": 3,
  "h": 2,
  "cost": [
   [
    "wood",
    8
   ],
   [
    "fiber",
    6
   ],
   [
    "wheat_seeds",
    3
   ]
  ],
  "farmField": true,
  "desc": "Grows wheat: plant → water → gather."
 },
 "gathering_site": {
  "id": "gathering_site",
  "name": "Gathering Site",
  "glyph": "❧",
  "color": "#7d9a4a",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "wood",
    8
   ],
   [
    "fiber",
    4
   ]
  ],
  "job": {"kind": "gather", "workType": "gathering", "amount": 80, "produces": [["mushroom", 1]]},
  "desc": "A gathering pal forages mushrooms here."
 },
 "pharmacy": {
  "id": "pharmacy",
  "name": "Pharmacy",
  "glyph": "✚",
  "color": "#8fd0a0",
  "w": 2,
  "h": 1,
  "cost": [
   [
    "wood",
    12
   ],
   [
    "paldium",
    2
   ]
  ],
  "job": {"kind": "brew", "workType": "medicine", "amount": 150, "produces": [["low_medical", 1]]},
  "desc": "A medicine pal brews basic remedies here."
 },
 "cooler": {
  "id": "cooler",
  "name": "Ice Box",
  "glyph": "❄",
  "color": "#a8dff0",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "wood",
    10
   ],
   [
    "stone",
    8
   ]
  ],
  "job": {"kind": "chill", "workType": "cooling", "amount": 120, "produces": [["ice_organ", 1]]},
  "desc": "A cooling pal condenses ice organs here."
 },
 "oil_extractor": {
  "id": "oil_extractor",
  "name": "Oil Extractor",
  "glyph": "⛽",
  "color": "#4d565c",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "ingot",
    6
   ],
   [
    "nails",
    4
   ]
  ],
  "job": {"kind": "pump", "workType": "oilExtraction", "amount": 240, "produces": [["polymer", 1]]},
  "desc": "An oil-extracting pal refines polymer here."
 },
 "sphere_factory": {
  "id": "sphere_factory",
  "name": "Sphere Works",
  "glyph": "◉",
  "color": "#4dd0e1",
  "w": 2,
  "h": 1,
  "cost": [
   [
    "wood",
    20
   ],
   [
    "stone",
    15
   ],
   [
    "paldium",
    5
   ],
   [
    "ingot",
    4
   ]
  ],
  "job": {"kind": "assemble", "workType": "handiwork", "amount": 200,
   "consumes": [["paldium", 1], ["wood", 1], ["stone", 1]],
   "produces": [["pal_sphere", 1]]},
  "desc": "Palworld's assembly line — a handy pal rolls a sphere off the belt."
 },
 "expedition_post": {
  "id": "expedition_post",
  "name": "Expedition Post",
  "glyph": "⚑",
  "color": "#c9a15a",
  "w": 2,
  "h": 1,
  "cost": [
   [
    "wood",
    30
   ],
   [
    "stone",
    15
   ],
   [
    "ingot",
    4
   ],
   [
    "cloth",
    2
   ]
  ],
  "job": {"kind": "expedition", "workType": "gathering", "amount": 600},
  "desc": "Assign a gatherer and it marches off-post, returning with a haul keyed to its element."
 },
 "sphere_factory_2": {
  "id": "sphere_factory_2",
  "name": "Giga Works",
  "glyph": "◉",
  "color": "#4dd0e1",
  "w": 2,
  "h": 1,
  "cost": [
   [
    "stone",
    20
   ],
   [
    "ingot",
    8
   ],
   [
    "paldium",
    10
   ],
   [
    "electric_organ",
    4
   ]
  ],
  "job": {"kind": "assemble", "workType": "handiwork", "amount": 300,
   "consumes": [["paldium", 3], ["ingot", 2], ["electric_organ", 1]],
   "produces": [["giga_sphere", 1]]},
  "desc": "Palworld assembly line II — the organ-fed belt rolls giga spheres."
 },
 "pal_condenser": {
  "id": "pal_condenser",
  "name": "Pal Condenser",
  "glyph": "★",
  "color": "#7a5ac9",
  "w": 2,
  "h": 1,
  "cost": [
   [
    "paldium",
    4
   ],
   [
    "ingot",
    6
   ]
  ],
  "desc": "Fuse same-species pals into the active pal's star rank."
 },
 "ranch": {
  "id": "ranch",
  "name": "Ranch",
  "glyph": "⌂",
  "color": "#8a6d4d",
  "w": 4,
  "h": 3,
  "cost": [
   [
    "wood",
    20
   ],
   [
    "stone",
    10
   ],
   [
    "fiber",
    8
   ]
  ],
  "ranch": true,
  "desc": "Assign farming pals; they produce goods."
 },
 "chest": {
  "id": "chest",
  "name": "Wooden Chest",
  "glyph": "□",
  "color": "#8a6d4d",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "wood",
    8
   ]
  ],
  "storage": 12,
  "desc": "Pals transport produce here."
 },
 "generator": {
  "id": "generator",
  "name": "Power Generator",
  "glyph": "ϟ",
  "color": "#e8d44d",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "ingot",
    10
   ],
   [
    "electric_organ",
    5
   ]
  ],
  "job": {
   "kind": "power",
   "workType": "electricity",
   "amount": 40
  },
  "desc": "An electric pal charges it; powered stations work 50% faster."
 },
 "torch": {
  "id": "torch",
  "name": "Torch",
  "glyph": "†",
  "color": "#e8963c",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "wood",
    2
   ],
   [
    "fiber",
    1
   ]
  ],
  "light": 4,
  "desc": "Simple light source."
 },
 "waypoint": {
  "id": "waypoint",
  "name": "Waypoint",
  "glyph": "◇",
  "color": "#7fc8f8",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "stone",
    20
   ],
   [
    "paldium",
    5
   ]
  ],
  "light": 5,
  "hp": 400,
  "desc": "Palworld fast-travel stone: touch it to blink back to your palbox."
 },
 "straw_bed": {
  "id": "straw_bed",
  "name": "Straw Bed",
  "glyph": "▭",
  "color": "#b8a468",
  "w": 2,
  "h": 1,
  "cost": [
   [
    "wood",
    10
   ],
   [
    "fiber",
    8
   ]
  ],
  "playerBed": true,
  "desc": "Sleep to skip to morning and heal."
 },
 "incubator": {
  "id": "incubator",
  "name": "Egg Incubator",
  "glyph": "◍",
  "color": "#f2a0b5",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "paldium",
    2
   ],
   [
    "stone",
    10
   ],
   [
    "cloth",
    2
   ]
  ],
  "incubator": true,
  "hp": 200,
  "light": 2,
  "desc": "Hatches pal eggs over time. A nearby campfire speeds it up."
 },
 "wooden_wall": {
  "id": "wooden_wall",
  "name": "Wooden Wall",
  "glyph": "┃",
  "color": "#8a6d4d",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "wood",
    2
   ]
  ],
  "hp": 300,
  "desc": "Blocks movement. Raiders must chew through it."
 },
 "spikes": {
  "id": "spikes",
  "name": "Wooden Spikes",
  "glyph": "╳",
  "color": "#a98a5e",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "wood",
    4
   ],
   [
    "stone",
    2
   ]
  ],
  "walkable": true,
  "spike": 6,
  "hp": 100,
  "desc": "Hostiles stepping on it bleed. Walkable, but rude."
 },
 "hot_spring": {
  "id": "hot_spring",
  "name": "Hot Spring",
  "glyph": "♨",
  "color": "#7ec8e3",
  "w": 2,
  "h": 2,
  "cost": [
   [
    "stone",
    20
   ],
   [
    "wood",
    10
   ],
   [
    "paldium",
    3
   ]
  ],
  "spring": 1,
  "hp": 250,
  "light": 1,
  "desc": "Steam does wonders. Base pals recover SAN faster than any bed."
 },
 "monitoring_stand": {
  "id": "monitoring_stand",
  "name": "Monitoring Stand",
  "glyph": "⚑",
  "color": "#d06a6a",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "wood",
    10
   ],
   [
    "stone",
    10
   ],
   [
    "ingot",
    2
   ]
  ],
  "stand": true,
  "hp": 200,
  "desc": "Overseer post: +40% work speed base-wide, but SAN drains half again as fast."
 },
 "watch_tower": {
  "id": "watch_tower",
  "name": "Watch Tower",
  "glyph": "♜",
  "color": "#c9a86a",
  "w": 1,
  "h": 1,
  "cost": [
   [
    "wood",
    20
   ],
   [
    "stone",
    10
   ],
   [
    "ingot",
    2
   ]
  ],
  "turret": 14,
  "hp": 300,
  "light": 1,
  "desc": "Looses an arrow at the nearest raider or riled wild pal every few seconds."
 }
}

const TECH = [
 {
  "id": "workbench",
  "name": "Primitive Workbench",
  "tier": 1,
  "cost": 1
 },
 {
  "id": "spear",
  "name": "Stone Spear",
  "tier": 1,
  "cost": 1
 },
 {
  "id": "pal_bed",
  "name": "Pal Bed",
  "tier": 1,
  "cost": 1
 },
 {
  "id": "feed_box",
  "name": "Feed Box",
  "tier": 1,
  "cost": 1
 },
 {
  "id": "campfire",
  "name": "Campfire",
  "tier": 1,
  "cost": 1
 },
 {
  "id": "logging_site",
  "name": "Logging Site",
  "tier": 2,
  "cost": 2
 },
 {
  "id": "stone_pit",
  "name": "Stone Pit",
  "tier": 2,
  "cost": 2
 },
 {
  "id": "berry_farm",
  "name": "Berry Plantation",
  "tier": 2,
  "cost": 2
 },
 {
  "id": "bow",
  "name": "Bow",
  "tier": 2,
  "cost": 2
 },
 {
  "id": "wooden_wall",
  "name": "Wooden Wall",
  "tier": 2,
  "cost": 1
 },
 {
  "id": "arrow",
  "name": "Arrow",
  "tier": 2,
  "cost": 1
 },
 {
  "id": "ranch",
  "name": "Ranch",
  "tier": 3,
  "cost": 2
 },
 {
  "id": "chest",
  "name": "Wooden Chest",
  "tier": 3,
  "cost": 1
 },
 {
  "id": "crusher",
  "name": "Crusher",
  "tier": 3,
  "cost": 2
 },
 {
  "id": "torch",
  "name": "Torch",
  "tier": 3,
  "cost": 1
 },
 {
  "id": "wheat_farm",
  "name": "Wheat Plantation",
  "tier": 3,
  "cost": 2
 },
 {
  "id": "straw_bed",
  "name": "Straw Bed",
  "tier": 3,
  "cost": 1
 },
 {
  "id": "gathering_site",
  "name": "Gathering Site",
  "tier": 3,
  "cost": 1
 },
 {
  "id": "spikes",
  "name": "Wooden Spikes",
  "tier": 3,
  "cost": 1
 },
 {
  "id": "furnace",
  "name": "Primitive Furnace",
  "tier": 4,
  "cost": 3
 },
 {
  "id": "mill",
  "name": "Mill",
  "tier": 4,
  "cost": 2
 },
 {
  "id": "incubator",
  "name": "Egg Incubator",
  "tier": 4,
  "cost": 2,
  "parts": 2
 },
 {
  "id": "glider",
  "name": "Glider",
  "tier": 4,
  "cost": 2
 },
 {
  "id": "grappling_hook",
  "name": "Grappling Hook",
  "tier": 5,
  "cost": 2
 },
 {
  "id": "saddle",
  "name": "Pal Saddle",
  "tier": 3,
  "cost": 1
 },
 {
  "id": "wave_saddle",
  "name": "Wave Saddle",
  "tier": 3,
  "cost": 1
 },
 {
  "id": "sky_saddle",
  "name": "Sky Saddle",
  "tier": 4,
  "cost": 2
 },
 {
  "id": "meat_cleaver",
  "name": "Meat Cleaver",
  "tier": 3,
  "cost": 1
 },
 {
  "id": "waypoint",
  "name": "Waypoint",
  "tier": 4,
  "cost": 2
 },
 {
  "id": "hot_spring",
  "name": "Hot Spring",
  "tier": 5,
  "cost": 3
 },
 {
  "id": "monitoring_stand",
  "name": "Monitoring Stand",
  "tier": 5,
  "cost": 2,
  "parts": 2
 },
 {
  "id": "mega_sphere",
  "name": "Mega Sphere",
  "tier": 4,
  "cost": 2
 },
 {
  "id": "axe",
  "name": "Metal Axe",
  "tier": 4,
  "cost": 2
 },
 {
  "id": "pick",
  "name": "Metal Pickaxe",
  "tier": 4,
  "cost": 2
 },
 {
  "id": "ore_mine",
  "name": "Ore Excavation Site",
  "tier": 5,
  "cost": 3
 },
 {
  "id": "generator",
  "name": "Power Generator",
  "tier": 5,
  "cost": 3
 },
 {
  "id": "giga_sphere",
  "name": "Giga Sphere",
  "tier": 5,
  "cost": 3
 },
 {
  "id": "pharmacy",
  "name": "Pharmacy",
  "tier": 5,
  "cost": 2
 },
 {
  "id": "musket",
  "name": "Musket",
  "tier": 6,
  "cost": 3,
  "parts": 3
 },
 {
  "id": "cooler",
  "name": "Ice Box",
  "tier": 6,
  "cost": 2
 },
 {
  "id": "oil_extractor",
  "name": "Oil Extractor",
  "tier": 7,
  "cost": 3,
  "parts": 4
 },
 {
  "id": "musket_ball",
  "name": "Musket Ball",
  "tier": 6,
  "cost": 1
 },
 {
  "id": "pal_condenser",
  "name": "Pal Condenser",
  "tier": 6,
  "cost": 3,
  "parts": 3
 },
 {
  "id": "ultra_sphere",
  "name": "Ultra Sphere",
  "tier": 7,
  "cost": 4
 },
 {
  "id": "legendary_sphere",
  "name": "Legendary Sphere",
  "tier": 8,
  "cost": 5
 },
 {
  "id": "watch_tower",
  "name": "Watch Tower",
  "tier": 4,
  "cost": 2,
  "parts": 1
 },
 {
  "id": "foxparks_harness",
  "name": "Foxparks Harness",
  "tier": 4,
  "cost": 2
 },
 {
  "id": "lifmunk_smg",
  "name": "Lifmunk SMG",
  "tier": 4,
  "cost": 2
 },
 {
  "id": "tanzee_rifle",
  "name": "Tanzee Assault Rifle",
  "tier": 5,
  "cost": 2
 },
 {
  "id": "pengullet_launcher",
  "name": "Pengullet Launcher",
  "tier": 6,
  "cost": 2,
  "parts": 1
 },
 {
  "id": "sphere_launcher",
  "name": "Sphere Launcher",
  "tier": 5,
  "cost": 2,
  "parts": 2
 },
 {
  "id": "sphere_factory",
  "name": "Sphere Works",
  "tier": 5,
  "cost": 3,
  "parts": 1
 },
 {
  "id": "expedition_post",
  "name": "Expedition Post",
  "tier": 7,
  "cost": 3,
  "parts": 1
 },
 {
  "id": "sphere_factory_2",
  "name": "Giga Works",
  "tier": 8,
  "cost": 4,
  "parts": 2
 }
]

