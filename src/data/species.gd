# Auto-generated from prototype/src/data/species.ts — do not edit by hand
class_name SpeciesData

const SPECIES = {
 "lamball": {
  "id": "lamball",
  "name": "Lamball",
  "glyph": "λ",
  "color": "#ede0c8",
  "elements": [
   "neutral"
  ],
  "hp": 70,
  "atk": 70,
  "def": 70,
  "speed": 2.6,
  "capturePower": 40,
  "food": 2,
  "san": 70,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "airCannon"
   ],
   [
    10,
    "healingBreeze"
   ]
  ],
  "drops": [
   [
    "wool",
    1,
    2
   ],
   [
    "lamball_mutton",
    1,
    1
   ]
  ],
  "desc": "Fluffy sheep pal. Produces wool at a ranch.",
  "farm": {
   "item": "wool",
   "per": 60
  },
  "hostile": 0
 },
 "cattiva": {
  "id": "cattiva",
  "name": "Cattiva",
  "glyph": "c",
  "color": "#f2a0b5",
  "elements": [
   "neutral"
  ],
  "hp": 70,
  "atk": 70,
  "def": 70,
  "speed": 2.8,
  "capturePower": 40,
  "food": 1,
  "san": 60,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "gathering": 1,
   "mining": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "airCannon"
   ]
  ],
  "drops": [
   [
    "red_berries",
    1,
    2
   ],
   [
    "fiber",
    1,
    1
   ]
  ],
  "desc": "Cat-like pal; a jack of all base trades.",
  "hostile": 0
 },
 "chikipi": {
  "id": "chikipi",
  "name": "Chikipi",
  "glyph": "k",
  "color": "#e8f0f2",
  "elements": [
   "neutral"
  ],
  "hp": 60,
  "atk": 60,
  "def": 60,
  "speed": 2.5,
  "capturePower": 30,
  "food": 1,
  "san": 60,
  "work": {
   "gathering": 1,
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ]
  ],
  "drops": [
   [
    "egg",
    1,
    2
   ],
   [
    "chikipi_poultry",
    1,
    1
   ]
  ],
  "desc": "Tiny bird pal. Lays eggs at a ranch.",
  "farm": {
   "item": "egg",
   "per": 45
  },
  "hostile": 0
 },
 "foxparks": {
  "id": "foxparks",
  "name": "Foxparks",
  "glyph": "f",
  "color": "#e8963c",
  "elements": [
   "fire"
  ],
  "hp": 75,
  "atk": 80,
  "def": 65,
  "speed": 3,
  "capturePower": 55,
  "food": 2,
  "san": 70,
  "work": {
   "kindling": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "flameBurst"
   ],
   [
    12,
    "ignitionBreath"
   ]
  ],
  "drops": [
   [
    "leather",
    1,
    1
   ],
   [
    "flame_organ",
    1,
    1
   ]
  ],
  "desc": "Fire fox pal. Keeps furnaces burning.",
  "hostile": 1
 },
 "pengullet": {
  "id": "pengullet",
  "name": "Pengullet",
  "glyph": "p",
  "color": "#4d9de0",
  "elements": [
   "water",
   "ice"
  ],
  "hp": 70,
  "atk": 70,
  "def": 70,
  "speed": 2.4,
  "capturePower": 50,
  "food": 2,
  "san": 70,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "watering": 1,
   "cooling": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "hydroJet"
   ],
   [
    10,
    "iceMissile"
   ]
  ],
  "drops": [
   [
    "pal_fluid",
    1,
    1
   ],
   [
    "ice_organ",
    1,
    1
   ]
  ],
  "desc": "Penguin pal; waters crops and cools stores.",
  "hostile": 1
 },
 "eikthyrdeer": {
  "id": "eikthyrdeer",
  "name": "Eikthyrdeer",
  "glyph": "e",
  "color": "#d4b96e",
  "elements": [
   "neutral"
  ],
  "hp": 95,
  "atk": 80,
  "def": 75,
  "speed": 3.4,
  "capturePower": 65,
  "food": 3,
  "san": 80,
  "work": {
   "lumbering": 2
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    6,
    "airCannon"
   ],
   [
    14,
    "stoneShot"
   ]
  ],
  "drops": [
   [
    "leather",
    1,
    2
   ],
   [
    "horn",
    1,
    1
   ]
  ],
  "desc": "Stag pal with strong lumbering ability.",
  "hostile": 1
 },
 "lifmunk": {
  "id": "lifmunk",
  "name": "Lifmunk",
  "glyph": "l",
  "color": "#4caf50",
  "elements": [
   "grass"
  ],
  "hp": 70,
  "atk": 70,
  "def": 70,
  "speed": 3,
  "capturePower": 50,
  "food": 1,
  "san": 70,
  "work": {
   "planting": 1,
   "handiwork": 1,
   "lumbering": 1,
   "gathering": 1,
   "medicine": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "seedMachine"
   ],
   [
    10,
    "grassTornado"
   ]
  ],
  "drops": [
   [
    "fiber",
    1,
    2
   ],
   [
    "tomato_seeds",
    1,
    1
   ]
  ],
  "desc": "Squirrel pal that sows fields.",
  "hostile": 0
 },
 "tanzee": {
  "id": "tanzee",
  "name": "Tanzee",
  "glyph": "t",
  "color": "#9acd32",
  "elements": [
   "grass"
  ],
  "hp": 75,
  "atk": 75,
  "def": 70,
  "speed": 3.2,
  "capturePower": 55,
  "food": 2,
  "san": 70,
  "work": {
   "planting": 1,
   "handiwork": 1,
   "lumbering": 1,
   "transporting": 1,
   "gathering": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "seedMachine"
   ],
   [
    12,
    "grassTornado"
   ]
  ],
  "drops": [
   [
    "fiber",
    1,
    2
   ],
   [
    "mushroom",
    1,
    1
   ]
  ],
  "desc": "Monkey pal; agile farmhand.",
  "hostile": 1
 },
 "sparkit": {
  "id": "sparkit",
  "name": "Sparkit",
  "glyph": "s",
  "color": "#e8d44d",
  "elements": [
   "electric"
  ],
  "hp": 65,
  "atk": 80,
  "def": 60,
  "speed": 3.1,
  "capturePower": 60,
  "food": 1,
  "san": 70,
  "work": {
   "electricity": 1,
   "handiwork": 1,
   "transporting": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "shockwave"
   ],
   [
    12,
    "lightningStrike"
   ]
  ],
  "drops": [
   [
    "electric_organ",
    1,
    1
   ]
  ],
  "desc": "Static mouse pal; powers generators.",
  "hostile": 1
 },
 "jolthog": {
  "id": "jolthog",
  "name": "Jolthog",
  "glyph": "j",
  "color": "#e8e05c",
  "elements": [
   "electric"
  ],
  "hp": 70,
  "atk": 75,
  "def": 60,
  "speed": 3,
  "capturePower": 55,
  "food": 1,
  "san": 60,
  "work": {
   "electricity": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "shockwave"
   ]
  ],
  "drops": [
   [
    "electric_organ",
    1,
    1
   ]
  ],
  "desc": "Hedgehog pal that crackles with charge.",
  "hostile": 1
 },
 "dumud": {
  "id": "dumud",
  "name": "Dumud",
  "glyph": "d",
  "color": "#b8935f",
  "elements": [
   "ground"
  ],
  "hp": 90,
  "atk": 70,
  "def": 80,
  "speed": 2,
  "capturePower": 55,
  "food": 3,
  "san": 80,
  "work": {
   "watering": 1,
   "mining": 1,
   "transporting": 1,
   "oilExtraction": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "sandBlast"
   ],
   [
    12,
    "stoneShot"
   ]
  ],
  "drops": [
   [
    "pal_fluid",
    1,
    1
   ]
  ],
  "desc": "Mud fish; digs and hauls.",
  "hostile": 1
 },
 "depresso": {
  "id": "depresso",
  "name": "Depresso",
  "glyph": "D",
  "color": "#6fa8d1",
  "elements": [
   "dark"
  ],
  "hp": 70,
  "atk": 75,
  "def": 65,
  "speed": 2.6,
  "capturePower": 50,
  "food": 1,
  "san": 60,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "mining": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "darkBall"
   ],
   [
    10,
    "nightmare"
   ]
  ],
  "drops": [
   [
    "venom_gland",
    1,
    1
   ]
  ],
  "desc": "Gloomy pal that still gets work done.",
  "night": true,
  "hostile": 1
 },
 "daedream": {
  "id": "daedream",
  "name": "Daedream",
  "glyph": "δ",
  "color": "#c678dd",
  "elements": [
   "dark"
  ],
  "hp": 70,
  "atk": 80,
  "def": 65,
  "speed": 2.7,
  "capturePower": 60,
  "food": 2,
  "san": 80,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "gathering": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "darkBall"
   ],
   [
    12,
    "nightmare"
   ]
  ],
  "drops": [
   [
    "poison_gland",
    1,
    1
   ]
  ],
  "desc": "Dreamy night pal.",
  "night": true,
  "hostile": 1
 },
 "mau": {
  "id": "mau",
  "name": "Mau",
  "glyph": "m",
  "color": "#a8b5c4",
  "elements": [
   "dark"
  ],
  "hp": 75,
  "atk": 75,
  "def": 70,
  "speed": 2.9,
  "capturePower": 65,
  "food": 2,
  "san": 70,
  "work": {
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "darkBall"
   ]
  ],
  "drops": [
   [
    "gold_coin",
    1,
    3
   ]
  ],
  "desc": "Rare cat pal that digs up gold at a ranch.",
  "farm": {
   "item": "gold_coin",
   "per": 90
  },
  "night": true,
  "hostile": 1
 },
 "rushoar": {
  "id": "rushoar",
  "name": "Rushoar",
  "glyph": "R",
  "color": "#d1813c",
  "elements": [
   "ground"
  ],
  "hp": 85,
  "atk": 85,
  "def": 75,
  "speed": 3.5,
  "capturePower": 60,
  "food": 3,
  "san": 70,
  "work": {
   "mining": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "sandBlast"
   ],
   [
    12,
    "stoneShot"
   ]
  ],
  "drops": [
   [
    "leather",
    1,
    2
   ],
   [
    "stone",
    2,
    4
   ]
  ],
  "desc": "Boar pal that charges recklessly.",
  "hostile": 2
 },
 "cremis": {
  "id": "cremis",
  "name": "Cremis",
  "glyph": "C",
  "color": "#f5eee0",
  "elements": [
   "neutral"
  ],
  "hp": 75,
  "atk": 70,
  "def": 70,
  "speed": 2.7,
  "capturePower": 50,
  "food": 2,
  "san": 70,
  "work": {
   "gathering": 1,
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "airCannon"
   ]
  ],
  "drops": [
   [
    "wool",
    1,
    2
   ]
  ],
  "desc": "Fluffier than Lamball; also gives wool.",
  "farm": {
   "item": "wool",
   "per": 70
  },
  "hostile": 0
 },
 "mozzarina": {
  "id": "mozzarina",
  "name": "Mozzarina",
  "glyph": "M",
  "color": "#ede0c8",
  "elements": [
   "neutral"
  ],
  "hp": 90,
  "atk": 70,
  "def": 80,
  "speed": 2.2,
  "capturePower": 60,
  "food": 3,
  "san": 80,
  "work": {
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "airCannon"
   ]
  ],
  "drops": [
   [
    "milk",
    1,
    2
   ]
  ],
  "desc": "Cow pal producing milk at a ranch.",
  "farm": {
   "item": "milk",
   "per": 60
  },
  "hostile": 0
 },
 "penking": {
  "id": "penking",
  "name": "Penking",
  "glyph": "P",
  "color": "#4d9de0",
  "elements": [
   "water",
   "ice"
  ],
  "hp": 120,
  "atk": 95,
  "def": 90,
  "speed": 2.4,
  "capturePower": 90,
  "food": 4,
  "san": 90,
  "work": {
   "handiwork": 2,
   "transporting": 2,
   "watering": 2,
   "cooling": 2,
   "mining": 2
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    3,
    "hydroJet"
   ],
   [
    8,
    "iceMissile"
   ],
   [
    16,
    "blizzard"
   ]
  ],
  "drops": [
   [
    "pal_fluid",
    2,
    4
   ],
   [
    "ice_organ",
    2,
    3
   ]
  ],
  "desc": "Regal penguin; master of base work.",
  "hostile": 2
 },
 "fuack": {
  "id": "fuack",
  "name": "Fuack",
  "glyph": "F",
  "color": "#4dd0e1",
  "elements": [
   "water"
  ],
  "hp": 70,
  "atk": 70,
  "def": 65,
  "speed": 2.6,
  "capturePower": 50,
  "food": 2,
  "san": 70,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "watering": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "hydroJet"
   ]
  ],
  "drops": [
   [
    "pal_fluid",
    1,
    1
   ],
   [
    "leather",
    1,
    1
   ]
  ],
  "desc": "Duck pal; decent water worker.",
  "hostile": 1
 }
}

const SPECIES_LIST = [
 {
  "id": "lamball",
  "name": "Lamball",
  "glyph": "λ",
  "color": "#ede0c8",
  "elements": [
   "neutral"
  ],
  "hp": 70,
  "atk": 70,
  "def": 70,
  "speed": 2.6,
  "capturePower": 40,
  "food": 2,
  "san": 70,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "airCannon"
   ],
   [
    10,
    "healingBreeze"
   ]
  ],
  "drops": [
   [
    "wool",
    1,
    2
   ],
   [
    "lamball_mutton",
    1,
    1
   ]
  ],
  "desc": "Fluffy sheep pal. Produces wool at a ranch.",
  "farm": {
   "item": "wool",
   "per": 60
  },
  "hostile": 0
 },
 {
  "id": "cattiva",
  "name": "Cattiva",
  "glyph": "c",
  "color": "#f2a0b5",
  "elements": [
   "neutral"
  ],
  "hp": 70,
  "atk": 70,
  "def": 70,
  "speed": 2.8,
  "capturePower": 40,
  "food": 1,
  "san": 60,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "gathering": 1,
   "mining": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "airCannon"
   ]
  ],
  "drops": [
   [
    "red_berries",
    1,
    2
   ],
   [
    "fiber",
    1,
    1
   ]
  ],
  "desc": "Cat-like pal; a jack of all base trades.",
  "hostile": 0
 },
 {
  "id": "chikipi",
  "name": "Chikipi",
  "glyph": "k",
  "color": "#e8f0f2",
  "elements": [
   "neutral"
  ],
  "hp": 60,
  "atk": 60,
  "def": 60,
  "speed": 2.5,
  "capturePower": 30,
  "food": 1,
  "san": 60,
  "work": {
   "gathering": 1,
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ]
  ],
  "drops": [
   [
    "egg",
    1,
    2
   ],
   [
    "chikipi_poultry",
    1,
    1
   ]
  ],
  "desc": "Tiny bird pal. Lays eggs at a ranch.",
  "farm": {
   "item": "egg",
   "per": 45
  },
  "hostile": 0
 },
 {
  "id": "foxparks",
  "name": "Foxparks",
  "glyph": "f",
  "color": "#e8963c",
  "elements": [
   "fire"
  ],
  "hp": 75,
  "atk": 80,
  "def": 65,
  "speed": 3,
  "capturePower": 55,
  "food": 2,
  "san": 70,
  "work": {
   "kindling": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "flameBurst"
   ],
   [
    12,
    "ignitionBreath"
   ]
  ],
  "drops": [
   [
    "leather",
    1,
    1
   ],
   [
    "flame_organ",
    1,
    1
   ]
  ],
  "desc": "Fire fox pal. Keeps furnaces burning.",
  "hostile": 1
 },
 {
  "id": "pengullet",
  "name": "Pengullet",
  "glyph": "p",
  "color": "#4d9de0",
  "elements": [
   "water",
   "ice"
  ],
  "hp": 70,
  "atk": 70,
  "def": 70,
  "speed": 2.4,
  "capturePower": 50,
  "food": 2,
  "san": 70,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "watering": 1,
   "cooling": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "hydroJet"
   ],
   [
    10,
    "iceMissile"
   ]
  ],
  "drops": [
   [
    "pal_fluid",
    1,
    1
   ],
   [
    "ice_organ",
    1,
    1
   ]
  ],
  "desc": "Penguin pal; waters crops and cools stores.",
  "hostile": 1
 },
 {
  "id": "eikthyrdeer",
  "name": "Eikthyrdeer",
  "glyph": "e",
  "color": "#d4b96e",
  "elements": [
   "neutral"
  ],
  "hp": 95,
  "atk": 80,
  "def": 75,
  "speed": 3.4,
  "capturePower": 65,
  "food": 3,
  "san": 80,
  "work": {
   "lumbering": 2
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    6,
    "airCannon"
   ],
   [
    14,
    "stoneShot"
   ]
  ],
  "drops": [
   [
    "leather",
    1,
    2
   ],
   [
    "horn",
    1,
    1
   ]
  ],
  "desc": "Stag pal with strong lumbering ability.",
  "hostile": 1
 },
 {
  "id": "lifmunk",
  "name": "Lifmunk",
  "glyph": "l",
  "color": "#4caf50",
  "elements": [
   "grass"
  ],
  "hp": 70,
  "atk": 70,
  "def": 70,
  "speed": 3,
  "capturePower": 50,
  "food": 1,
  "san": 70,
  "work": {
   "planting": 1,
   "handiwork": 1,
   "lumbering": 1,
   "gathering": 1,
   "medicine": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "seedMachine"
   ],
   [
    10,
    "grassTornado"
   ]
  ],
  "drops": [
   [
    "fiber",
    1,
    2
   ],
   [
    "tomato_seeds",
    1,
    1
   ]
  ],
  "desc": "Squirrel pal that sows fields.",
  "hostile": 0
 },
 {
  "id": "tanzee",
  "name": "Tanzee",
  "glyph": "t",
  "color": "#9acd32",
  "elements": [
   "grass"
  ],
  "hp": 75,
  "atk": 75,
  "def": 70,
  "speed": 3.2,
  "capturePower": 55,
  "food": 2,
  "san": 70,
  "work": {
   "planting": 1,
   "handiwork": 1,
   "lumbering": 1,
   "transporting": 1,
   "gathering": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "seedMachine"
   ],
   [
    12,
    "grassTornado"
   ]
  ],
  "drops": [
   [
    "fiber",
    1,
    2
   ],
   [
    "mushroom",
    1,
    1
   ]
  ],
  "desc": "Monkey pal; agile farmhand.",
  "hostile": 1
 },
 {
  "id": "sparkit",
  "name": "Sparkit",
  "glyph": "s",
  "color": "#e8d44d",
  "elements": [
   "electric"
  ],
  "hp": 65,
  "atk": 80,
  "def": 60,
  "speed": 3.1,
  "capturePower": 60,
  "food": 1,
  "san": 70,
  "work": {
   "electricity": 1,
   "handiwork": 1,
   "transporting": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "shockwave"
   ],
   [
    12,
    "lightningStrike"
   ]
  ],
  "drops": [
   [
    "electric_organ",
    1,
    1
   ]
  ],
  "desc": "Static mouse pal; powers generators.",
  "hostile": 1
 },
 {
  "id": "jolthog",
  "name": "Jolthog",
  "glyph": "j",
  "color": "#e8e05c",
  "elements": [
   "electric"
  ],
  "hp": 70,
  "atk": 75,
  "def": 60,
  "speed": 3,
  "capturePower": 55,
  "food": 1,
  "san": 60,
  "work": {
   "electricity": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "shockwave"
   ]
  ],
  "drops": [
   [
    "electric_organ",
    1,
    1
   ]
  ],
  "desc": "Hedgehog pal that crackles with charge.",
  "hostile": 1
 },
 {
  "id": "dumud",
  "name": "Dumud",
  "glyph": "d",
  "color": "#b8935f",
  "elements": [
   "ground"
  ],
  "hp": 90,
  "atk": 70,
  "def": 80,
  "speed": 2,
  "capturePower": 55,
  "food": 3,
  "san": 80,
  "work": {
   "watering": 1,
   "mining": 1,
   "transporting": 1,
   "oilExtraction": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "sandBlast"
   ],
   [
    12,
    "stoneShot"
   ]
  ],
  "drops": [
   [
    "pal_fluid",
    1,
    1
   ]
  ],
  "desc": "Mud fish; digs and hauls.",
  "hostile": 1
 },
 {
  "id": "depresso",
  "name": "Depresso",
  "glyph": "D",
  "color": "#6fa8d1",
  "elements": [
   "dark"
  ],
  "hp": 70,
  "atk": 75,
  "def": 65,
  "speed": 2.6,
  "capturePower": 50,
  "food": 1,
  "san": 60,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "mining": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "darkBall"
   ],
   [
    10,
    "nightmare"
   ]
  ],
  "drops": [
   [
    "venom_gland",
    1,
    1
   ]
  ],
  "desc": "Gloomy pal that still gets work done.",
  "night": true,
  "hostile": 1
 },
 {
  "id": "daedream",
  "name": "Daedream",
  "glyph": "δ",
  "color": "#c678dd",
  "elements": [
   "dark"
  ],
  "hp": 70,
  "atk": 80,
  "def": 65,
  "speed": 2.7,
  "capturePower": 60,
  "food": 2,
  "san": 80,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "gathering": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "darkBall"
   ],
   [
    12,
    "nightmare"
   ]
  ],
  "drops": [
   [
    "poison_gland",
    1,
    1
   ]
  ],
  "desc": "Dreamy night pal.",
  "night": true,
  "hostile": 1
 },
 {
  "id": "mau",
  "name": "Mau",
  "glyph": "m",
  "color": "#a8b5c4",
  "elements": [
   "dark"
  ],
  "hp": 75,
  "atk": 75,
  "def": 70,
  "speed": 2.9,
  "capturePower": 65,
  "food": 2,
  "san": 70,
  "work": {
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "darkBall"
   ]
  ],
  "drops": [
   [
    "gold_coin",
    1,
    3
   ]
  ],
  "desc": "Rare cat pal that digs up gold at a ranch.",
  "farm": {
   "item": "gold_coin",
   "per": 90
  },
  "night": true,
  "hostile": 1
 },
 {
  "id": "rushoar",
  "name": "Rushoar",
  "glyph": "R",
  "color": "#d1813c",
  "elements": [
   "ground"
  ],
  "hp": 85,
  "atk": 85,
  "def": 75,
  "speed": 3.5,
  "capturePower": 60,
  "food": 3,
  "san": 70,
  "work": {
   "mining": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "sandBlast"
   ],
   [
    12,
    "stoneShot"
   ]
  ],
  "drops": [
   [
    "leather",
    1,
    2
   ],
   [
    "stone",
    2,
    4
   ]
  ],
  "desc": "Boar pal that charges recklessly.",
  "hostile": 2
 },
 {
  "id": "cremis",
  "name": "Cremis",
  "glyph": "C",
  "color": "#f5eee0",
  "elements": [
   "neutral"
  ],
  "hp": 75,
  "atk": 70,
  "def": 70,
  "speed": 2.7,
  "capturePower": 50,
  "food": 2,
  "san": 70,
  "work": {
   "gathering": 1,
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "airCannon"
   ]
  ],
  "drops": [
   [
    "wool",
    1,
    2
   ]
  ],
  "desc": "Fluffier than Lamball; also gives wool.",
  "farm": {
   "item": "wool",
   "per": 70
  },
  "hostile": 0
 },
 {
  "id": "mozzarina",
  "name": "Mozzarina",
  "glyph": "M",
  "color": "#ede0c8",
  "elements": [
   "neutral"
  ],
  "hp": 90,
  "atk": 70,
  "def": 80,
  "speed": 2.2,
  "capturePower": 60,
  "food": 3,
  "san": 80,
  "work": {
   "farming": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    5,
    "airCannon"
   ]
  ],
  "drops": [
   [
    "milk",
    1,
    2
   ]
  ],
  "desc": "Cow pal producing milk at a ranch.",
  "farm": {
   "item": "milk",
   "per": 60
  },
  "hostile": 0
 },
 {
  "id": "penking",
  "name": "Penking",
  "glyph": "P",
  "color": "#4d9de0",
  "elements": [
   "water",
   "ice"
  ],
  "hp": 120,
  "atk": 95,
  "def": 90,
  "speed": 2.4,
  "capturePower": 90,
  "food": 4,
  "san": 90,
  "work": {
   "handiwork": 2,
   "transporting": 2,
   "watering": 2,
   "cooling": 2,
   "mining": 2
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    3,
    "hydroJet"
   ],
   [
    8,
    "iceMissile"
   ],
   [
    16,
    "blizzard"
   ]
  ],
  "drops": [
   [
    "pal_fluid",
    2,
    4
   ],
   [
    "ice_organ",
    2,
    3
   ]
  ],
  "desc": "Regal penguin; master of base work.",
  "hostile": 2
 },
 {
  "id": "fuack",
  "name": "Fuack",
  "glyph": "F",
  "color": "#4dd0e1",
  "elements": [
   "water"
  ],
  "hp": 70,
  "atk": 70,
  "def": 65,
  "speed": 2.6,
  "capturePower": 50,
  "food": 2,
  "san": 70,
  "work": {
   "handiwork": 1,
   "transporting": 1,
   "watering": 1
  },
  "skills": [
   [
    1,
    "tackle"
   ],
   [
    4,
    "hydroJet"
   ]
  ],
  "drops": [
   [
    "pal_fluid",
    1,
    1
   ],
   [
    "leather",
    1,
    1
   ]
  ],
  "desc": "Duck pal; decent water worker.",
  "hostile": 1
 }
]

