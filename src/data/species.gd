# Auto-generated from prototype/src/data/species.ts — do not edit by hand
class_name SpeciesData

const SPECIES = {
 "fenjelly": {
  "id": "fenjelly",
  "name": "Fenjelly",
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
   ],
   [
    20,
    "packVolley"
   ]
  ],
  "drops": [
   [
    "wool",
    1,
    2
   ],
   [
    "fenjelly_mutton",
    1,
    1
   ]
  ],
  "desc": "Fluffy sheep kin. Produces wool at a ranch.",
  "farm": {
   "item": "wool",
   "per": 60
  },
  "hostile": 0
 },
 "puffmite": {
  "id": "puffmite",
  "name": "Puffmite",
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
   ],
   [
    20,
    "packVolley"
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
  "desc": "Cat-like kin; a jack of all base trades.",
  "hostile": 0
 },
 "fenlump": {
  "id": "fenlump",
  "name": "Fenlump",
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
   ],
   [
    20,
    "packVolley"
   ]
  ],
  "drops": [
   [
    "egg",
    1,
    2
   ],
   [
    "fenlump_poultry",
    1,
    1
   ]
  ],
  "desc": "Tiny bird kin. Lays eggs at a ranch.",
  "farm": {
   "item": "egg",
   "per": 45
  },
  "hostile": 0
 },
 "cindlump": {
  "id": "cindlump",
  "name": "Cindlump",
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
   ],
   [
    20,
    "cinderFeast"
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
  "desc": "Fire fox kin. Keeps furnaces burning.",
  "hostile": 1
 },
 "corlmite": {
  "id": "corlmite",
  "name": "Corlmite",
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
   ],
   [
    20,
    "glacierPike"
   ]
  ],
  "drops": [
   [
    "kin_fluid",
    1,
    1
   ],
   [
    "ice_organ",
    1,
    1
   ]
  ],
  "desc": "Penguin kin; waters crops and cools stores.",
  "hostile": 1
 },
 "dozantler": {
  "id": "dozantler",
  "name": "Dozantler",
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
   ],
   [
    20,
    "packVolley"
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
  "desc": "Stag kin with strong lumbering ability.",
  "hostile": 1
 },
 "sprigmelt": {
  "id": "sprigmelt",
  "name": "Sprigmelt",
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
   ],
   [
    20,
    "sporeFan"
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
  "desc": "Squirrel kin that sows fields.",
  "hostile": 0
 },
 "briargoo": {
  "id": "briargoo",
  "name": "Briargoo",
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
   ],
   [
    20,
    "sporeFan"
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
  "desc": "Monkey kin; agile farmhand.",
  "hostile": 1
 },
 "voltgoo": {
  "id": "voltgoo",
  "name": "Voltgoo",
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
   ],
   [
    20,
    "arcLance"
   ]
  ],
  "drops": [
   [
    "electric_organ",
    1,
    1
   ]
  ],
  "desc": "Static mouse kin; powers generators.",
  "hostile": 1
 },
 "faradlump": {
  "id": "faradlump",
  "name": "Faradlump",
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
   ],
   [
    20,
    "arcLance"
   ]
  ],
  "drops": [
   [
    "electric_organ",
    1,
    1
   ]
  ],
  "desc": "Hedgehog kin that crackles with charge.",
  "hostile": 1
 },
 "loammelt": {
  "id": "loammelt",
  "name": "Loammelt",
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
   ],
   [
    20,
    "faultPike"
   ]
  ],
  "drops": [
   [
    "kin_fluid",
    1,
    1
   ]
  ],
  "desc": "Mud fish; digs and hauls.",
  "hostile": 1
 },
 "shademite": {
  "id": "shademite",
  "name": "Shademite",
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
   ],
   [
    20,
    "soulSiphon"
   ]
  ],
  "drops": [
   [
    "venom_gland",
    1,
    1
   ]
  ],
  "desc": "Gloomy kin that still gets work done.",
  "night": true,
  "hostile": 1
 },
 "shadelump": {
  "id": "shadelump",
  "name": "Shadelump",
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
   ],
   [
    20,
    "soulSiphon"
   ]
  ],
  "drops": [
   [
    "poison_gland",
    1,
    1
   ]
  ],
  "desc": "Dreamy night kin.",
  "night": true,
  "hostile": 1
 },
 "shademelt": {
  "id": "shademelt",
  "name": "Shademelt",
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
   ],
   [
    20,
    "soulSiphon"
   ]
  ],
  "drops": [
   [
    "gold_coin",
    1,
    3
   ]
  ],
  "desc": "Rare cat kin that digs up gold at a ranch.",
  "farm": {
   "item": "gold_coin",
   "per": 90
  },
  "night": true,
  "hostile": 1
 },
 "loampuff": {
  "id": "loampuff",
  "name": "Loampuff",
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
   ],
   [
    20,
    "faultPike"
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
  "desc": "Boar kin that charges recklessly.",
  "hostile": 2
 },
 "nibjelly": {
  "id": "nibjelly",
  "name": "Nibjelly",
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
   ],
   [
    20,
    "packVolley"
   ]
  ],
  "drops": [
   [
    "wool",
    1,
    2
   ]
  ],
  "desc": "Fluffier than Fenjelly; also gives wool.",
  "farm": {
   "item": "wool",
   "per": 70
  },
  "hostile": 0
 },
 "piplump": {
  "id": "piplump",
  "name": "Piplump",
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
   ],
   [
    20,
    "packVolley"
   ]
  ],
  "drops": [
   [
    "milk",
    1,
    2
   ]
  ],
  "desc": "Cow kin producing milk at a ranch.",
  "farm": {
   "item": "milk",
   "per": 60
  },
  "hostile": 0
 },
 "marlump": {
  "id": "marlump",
  "name": "Marlump",
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
   ],
   [
    20,
    "glacierPike"
   ]
  ],
  "drops": [
   [
    "kin_fluid",
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
 "quackbill": {
  "id": "quackbill",
  "name": "Quackbill",
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
   ],
   [
    20,
    "undertowPull"
   ]
  ],
  "drops": [
   [
    "kin_fluid",
    1,
    1
   ],
   [
    "leather",
    1,
    1
   ]
  ],
  "desc": "Duck kin; decent water worker.",
  "hostile": 1
 },
 "ironpact_grunt": {
  "id": "ironpact_grunt",
  "name": "Ironpact Grunt",
  "glyph": "§",
  "color": "#3a3a4a",
  "elements": [
   "dark"
  ],
  "hp": 80,
  "atk": 85,
  "def": 60,
  "speed": 3.0,
  "capturePower": 30,
  "food": 3,
  "san": 60,
  "work": {
   "handiwork": 1
  },
  "skills": [
   [
    1,
    "airCannon"
   ],
   [
    6,
    "darkBall"
   ],
   [
    20,
    "soulSiphon"
   ]
  ],
  "drops": [
   [
    "gold_coin",
    2,
    6
   ],
   [
    "arrow",
    2,
    5
   ]
  ],
  "desc": "A poacher for the Iron Pact. Terrible worker, worse intentions.",
  "hostile": 2
 },
 "ironpact_sweeper": {
  "id": "ironpact_sweeper",
  "name": "Ironpact Sweeper",
  "glyph": "§",
  "color": "#5a2e4a",
  "elements": [
   "dark"
  ],
  "hp": 120,
  "atk": 110,
  "def": 80,
  "speed": 2.8,
  "capturePower": 20,
  "food": 4,
  "san": 60,
  "work": {
   "handiwork": 1,
   "lumbering": 1
  },
  "skills": [
   [
    1,
    "darkBall"
   ],
   [
    10,
    "nightmare"
   ],
   [
    20,
    "soulSiphon"
   ]
  ],
  "drops": [
   [
    "gold_coin",
    4,
    10
   ],
   [
    "musket_ball",
    2,
    5
   ],
   [
    "gunpowder",
    1,
    2
   ]
  ],
  "desc": "Iron Pact muscle. Their idea of negotiation is a rifle butt.",
  "hostile": 2
 }
}



static func species_of(id: String) -> Dictionary:
	var r: Dictionary = SPECIES.get(id, {})
	if r.is_empty():
		r = SpeciesGen.SPECIES.get(id, {})
	return r

const BODY := {
 "fenjelly":"quadruped","puffmite":"kitty","fenlump":"bird","cindlump":"kitty",
 "corlmite":"bird","marlump":"bird","dozantler":"deer","sprigmelt":"mouse",
 "briargoo":"monkey","voltgoo":"mouse","faradlump":"hedgehog","loammelt":"serpent",
 "shademite":"blob","shadelump":"ghost","shademelt":"kitty","loampuff":"boar",
 "nibjelly":"kitty","piplump":"cow","quackbill":"bird","player":"human",
 "ironpact_grunt":"human","ironpact_sweeper":"human"
}
const MOUNTABLE := ["quadruped","deer","cow","boar"]
static func body_of(id: String) -> String:
	if SPECIES.has(id) and BODY.has(id):
		return BODY[id]
	return SpeciesGen.SPECIES.get(id, {}).get("body", "")
static func mountable(id: String) -> bool:
	return body_of(id) in MOUNTABLE
