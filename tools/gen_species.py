# Generates src/data/species_gen.gd: extra species + passive traits.
# Patches gen_assets.py SPRITES dict so art renders for every new id.
import io, json, os, re

R = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'

# id: (name, body, [c0,c1,c2], fluff, [elements], tier, work{}, drops[[item,min,max]], desc, hostile)
NEW = [
 ("pyrejelly","Pyrejelly","blob",["#e8734a","#c9552f","#ffd54f"],.25,["fire"],0,{"kindling":1},[["flame_organ",1,2]],"Tiny flame sprite.",0),
 ("branpurr","Branpurr","kitty",["#c93a4d","#a32c3d","#f5eee0"],.3,["fire"],1,{"kindling":1},[["flame_organ",1,2],["leather",1,1]],"Mischievous fire imp.",1),
 ("scalfang","Scalfang","quadruped",["#d1813c","#a96a2f","#ffd54f"],.2,["fire"],1,{"kindling":2},[["flame_organ",1,3],["horn",1,1]],"Inferno fox mount.",1),
 ("pyresmith","Pyresmith","human",["#8a3d5c","#6d2e48","#e8734a"],.1,["fire","dark"],2,{"kindling":3,"handiwork":2},[["flame_organ",2,4],["bone",1,2]],"Rampaging inferno berserker.",2),
 ("cindpaw","Cindpaw","quadruped",["#c9552f","#9e3f22","#ffd76e"],.15,["fire"],2,{"kindling":2},[["flame_organ",2,4],["leather",1,2]],"Fire-maned hellhound.",2),
 ("branling","Branling","human",["#a83232","#7d2525","#e8c9a0"],.1,["fire"],2,{"kindling":2,"handiwork":2},[["bone",1,2],["flame_organ",1,3]],"Fire-blade ronin kin.",2),
 ("pyreplume","Pyreplume","bird",["#e8734a","#c9552f","#3a3a4a"],.15,["fire"],2,{"kindling":3,"transporting":2},[["flame_organ",2,4],["bone",1,2]],"Phoenix-tier fire raptor.",2),
 ("flarbeak","Flarbeak","bird",["#e8452f","#c93522","#ffd76e"],.2,["fire"],3,{"kindling":3},[["flame_organ",3,6],["gold_coin",1,3]],"Vermillion fire god-bird.",2),
 ("cindchew","Cindchew","cow",["#8a4a4a","#6d3838","#e8734a"],.1,["fire"],3,{"kindling":4,"mining":2},[["flame_organ",3,6],["stone",2,4]],"Magma-hide behemoth.",2),
 ("bubwrith","Bubwrith","serpent",["#5ab8d1","#4296b0","#9be8d8"],.2,["water"],0,{"watering":1},[["pal_fluid",1,2]],"Seaweed water serpent.",0),
 ("frostfang","Frostfang","quadruped",["#8fd1e8","#68b0d1","#f5eee0"],.3,["ice","dragon"],1,{"cooling":1,"transporting":1},[["ice_organ",1,2],["leather",1,1]],"Otter-dragon glide kin.",0),
 ("bringloom","Bringloom","ghost",["#7ec8e3","#5aa8c4","#c8e8f5"],.15,["water"],1,{"watering":2},[["pal_fluid",1,3]],"Floating manta ray.",0),
 ("lazpuff","Lazpuff","blob",["#a8d8c8","#85bfae","#f5eee0"],.35,["water"],0,{"watering":1},[["pal_fluid",1,1]],"Teapot elephant sprinkler.",0),
 ("ripbell","Ripbell","cow",["#6d9dc5","#5480a8","#8fd1a0"],.15,["water","dragon"],2,{"watering":2,"transporting":2},[["pal_fluid",2,4],["bone",1,2]],"Giant sleepy water-saur.",0),
 ("ripwrith","Ripwrith","serpent",["#4d7db8","#3a6196","#9be8d8"],.1,["water","dragon"],2,{"watering":3},[["pal_fluid",2,5],["horn",1,2]],"Rain-dance water dragon.",1),
 ("tidscale","Tidscale","serpent",["#3a5a8a","#2d4770","#8fd1e8"],.1,["water","dragon"],3,{"watering":4},[["pal_fluid",4,6],["horn",2,3]],"Sea leviathan emperor.",2),
 ("bubgoo","Bubgoo","blob",["#5a8db0","#47708c","#8fd1e8"],.2,["water"],1,{"watering":2,"handiwork":1},[["pal_fluid",1,3],["gold_coin",1,1]],"Scheming goblin fish.",1),
 ("dewmane","Dewmane","quadruped",["#e8c46a","#c9a34d","#4dd0e1"],.3,["water"],1,{"watering":1,"transporting":1},[["pal_fluid",1,2],["leather",1,1]],"Surfing retriever kin.",0),
 ("hushnib","Hushnib","mouse",["#f2b8d1","#d193ad","#f5eee0"],.4,["neutral"],0,{"handiwork":1,"gathering":1},[["leather",1,1],["wool",1,1]],"Ribbon-eared bunny.",0),
 ("thornmelt","Thornmelt","blob",["#b8d77c","#96ba5e","#f5eee0"],.35,["grass"],0,{"planting":1},[["red_berries",2,4],["berry_seeds",1,2]],"Pudgy leaf-hopper.",0),
 ("mossjelly","Mossjelly","blob",["#e8d44d","#c9b23a","#f5eee0"],.4,["grass"],0,{"planting":1,"farming":1},[["red_berries",1,3]],"Honey-drip bee buddy.",0),
 ("wortling","Wortling","human",["#e8d44d","#b89a2f","#3a3a4a"],.1,["grass"],1,{"planting":2,"medicine":1},[["red_berries",1,3],["venom_gland",1,1]],"Bee-knight royal guard.",1),
 ("thornhoof","Thornhoof","quadruped",["#7cb86a","#5e9a4e","#e8d44d"],.25,["grass"],1,{"planting":1,"lumbering":1},[["red_berries",1,3],["wool",1,1]],"Bramble-backed grazer.",0),
 ("petalantler","Petalantler","deer",["#a8c97a","#88a85c","#f2b8d1"],.25,["grass"],1,{"planting":2},[["red_berries",2,4],["horn",1,1]],"Berry-branch deer.",0),
 ("leaftrot","Leaftrot","quadruped",["#c9b8d1","#a89ab8","#9be8d8"],.2,["grass"],2,{"planting":2,"transporting":1},[["horn",1,2],["leather",1,2]],"Cherry-blossom sauropod.",0),
 ("briarmaw","Briarmaw","quadruped",["#8fc46a","#6da350","#e8734a"],.2,["grass","dragon"],1,{"planting":2,"lumbering":1},[["horn",1,2],["red_berries",1,3]],"Fruit-crest grass drake.",1),
 ("briarchim","Briarchim","monkey",["#6dc48a","#4ea36a","#e8d44d"],.2,["grass"],1,{"planting":2,"handiwork":2,"transporting":1},[["leather",1,2],["wool",1,1]],"Nimble forest scout.",0),
 ("fernchim","Fernchim","monkey",["#7cb86a","#5e9a4e","#b8935f"],.15,["grass"],2,{"planting":2,"lumbering":3,"handiwork":2},[["leather",2,3],["bone",1,1]],"Forest-titan gorilla.",1),
 ("tawtail","Tawtail","kitty",["#e8b8d1","#c998b8","#f5eee0"],.3,["neutral"],1,{"gathering":1,"transporting":1},[["leather",1,2],["wool",1,1]],"Big grinning big-cat.",0),
 ("mossveil","Mossveil","ghost",["#e8d44d","#c9a82f","#3a3a4a"],.15,["grass"],2,{"planting":3,"medicine":2,"handiwork":1},[["venom_gland",1,2],["red_berries",2,4]],"Queen bee matriarch.",1),
 ("ivyveil","Ivyveil","ghost",["#c9a8e8","#a885c9","#f5eee0"],.25,["grass"],1,{"planting":1,"medicine":1},[["red_berries",1,3]],"Lilac forest sprite.",0),
 ("mosswisp","Mosswisp","ghost",["#e8c98a","#c9a85e","#f5eee0"],.3,["grass"],1,{"planting":2,"medicine":1},[["fiber",2,4]],"Cinnamon moth pollinator.",0),
 ("fernveil","Fernveil","ghost",["#d8c8e8","#b8a8c9","#f5eee0"],.35,["grass"],0,{"planting":1},[["red_berries",1,2]],"Drowsy lily spirit.",0),
 ("floraling","Floraling","ghost",["#f2b8d1","#d193ad","#9be8a0"],.3,["grass"],1,{"planting":2,"medicine":1},[["red_berries",2,4]],"Blooming petal dancer.",0),
 ("statstride","Statstride","deer",["#e8d44d","#c9a82f","#4dd0e1"],.15,["electric"],1,{"electricity":2},[["electric_organ",1,3],["horn",1,1]],"Thunderbolt unicorn.",1),
 ("zapplume","Zapplume","bird",["#e8d44d","#c9b23a","#3a3a4a"],.15,["electric"],2,{"electricity":2,"transporting":2},[["electric_organ",2,4],["bone",1,2]],"Storm-claw thunderbird.",2),
 ("zaptrot","Zaptrot","quadruped",["#7ac9e8","#5aa8c9","#e8d44d"],.15,["electric"],2,{"electricity":3},[["electric_organ",2,4],["leather",1,2]],"Lightning-speed hound.",2),
 ("sparkwhisk","Sparkwhisk","mouse",["#e8e0a8","#c9be85","#e8d44d"],.3,["electric"],0,{"electricity":1,"handiwork":1},[["electric_organ",1,2]],"Sparkling sky-mouse.",0),
 ("tambeak","Tambeak","bird",["#e8a83c","#c9852a","#3a3a4a"],.25,["neutral"],0,{"gathering":1},[["gunpowder",1,3],["bone",1,1]],"Exploding toucan trouble.",1),
 ("statchew","Statchew","cow",["#8a7a5a","#6d5e45","#e8d44d"],.1,["electric"],3,{"electricity":3,"handiwork":2},[["electric_organ",3,6],["leather",2,3]],"Minigun-armed storm bear.",2),
 ("rimemane","Rimemane","quadruped",["#b8d8e8","#96b8c9","#f5eee0"],.3,["ice"],1,{"cooling":1,"gathering":1},[["ice_organ",1,2],["wool",1,1]],"Floofy tail-sweeper.",0),
 ("glaclump","Glaclump","blob",["#c8e8f5","#a5c9d8","#f5eee0"],.4,["ice"],0,{"cooling":1},[["ice_organ",1,2]],"Chilly little snowball.",0),
 ("snovmool","Snovmool","cow",["#a8b8c9","#8899aa","#f5eee0"],.15,["ice"],2,{"cooling":2,"transporting":3,"lumbering":1},[["ice_organ",2,4],["leather",1,2]],"Walrus-tusk cargo beast.",0),
 ("glacmane","Glacmane","quadruped",["#d8d8e8","#b8b8d1","#8fd1e8"],.25,["ice"],2,{"cooling":2,"farming":1},[["ice_organ",2,3],["fiber",2,3]],"Silken frost moth-beast.",0),
 ("snovfawn","Snovfawn","deer",["#a8c9e8","#85a8c9","#f5eee0"],.2,["ice"],1,{"cooling":1,"lumbering":1},[["ice_organ",1,3],["horn",1,1]],"Reindeer ice stag.",0),
 ("snovstride","Snovstride","deer",["#8fc9e8","#6aa8c9","#f5eee0"],.1,["ice"],3,{"cooling":4},[["ice_organ",4,6],["horn",2,3]],"Legendary winged ice steed.",2),
 ("snowtail","Snowtail","kitty",["#a8d8e8","#85b8c9","#e8f5fa"],.25,["ice"],0,{"cooling":1},[["ice_organ",1,2],["gold_coin",1,2]],"Icy Shademelt variant.",0),
 ("chilgloom","Chilgloom","ghost",["#8fb8a8","#6d9685","#f5eee0"],.3,["ice"],0,{"cooling":1,"transporting":1},[["ice_organ",1,1]],"Gliding scarf-tangler.",0),
 ("terrnib","Terrnib","mouse",["#8a7a6a","#6d5f52","#d8b8a8"],.3,["ground"],0,{"mining":1,"handiwork":1},[["stone",1,3],["bone",1,1]],"Dig-happy cave mole.",0),
 ("loamquill","Loamquill","hedgehog",["#a8885a","#8a6d45","#d8c9a0"],.15,["ground"],1,{"mining":2},[["stone",2,4],["ore",1,2]],"Drill-shell tortoise.",0),
 ("terrkin","Terrkin","human",["#5a5a8a","#44446d","#e8c9a0"],.1,["ground"],2,{"mining":3,"handiwork":4,"transporting":2},[["stone",2,4],["gold_coin",1,3],["bone",1,2]],"Desert god workaholic.",1),
 ("grithoof","Grithoof","quadruped",["#8a6d5a","#6d5443","#d89a5a"],.15,["ground","fire"],2,{"mining":3,"kindling":2},[["ore",2,4],["flame_organ",1,3]],"Magma-shell forge beast.",1),
 ("tammane","Tammane","quadruped",["#8a8a9a","#6d6d7d","#f5eee0"],.15,["neutral"],1,{"gathering":2,"transporting":1},[["leather",1,3],["bone",1,2]],"Howling pack wolf.",1),
 ("bramplume","Bramplume","bird",["#7a9db8","#5d82a0","#e8d44d"],.15,["neutral"],1,{"gathering":2},[["bone",1,2],["leather",1,1]],"Gliding gun-talon.",1),
 ("murkwing","Murkwing","bird",["#5a5a6a","#44445a","#e8c98a"],.2,["dark"],1,{"handiwork":1,"gathering":1},[["bone",1,1],["gold_coin",1,2]],"Sneaky phantom crow.",1),
 ("worthand","Worthand","human",["#7ab86a","#5d9a4e","#e8c9a0"],.15,["grass"],1,{"planting":1,"handiwork":2,"gathering":1},[["leather",1,2],["red_berries",1,2]],"Forest archer kin.",0),
 ("puffchim","Puffchim","monkey",["#7a6a5a","#5d5243","#d8c9a0"],.2,["neutral"],1,{"lumbering":2,"handiwork":1},[["leather",1,2],["bone",1,1]],"Rowdy muscle monkey.",1),
 ("mimspike","Mimspike","hedgehog",["#f5d8e8","#d8b8c9","#f5eee0"],.45,["neutral"],0,{"farming":1},[["wool",2,4]],"Cotton-candy puffball.",0),
 ("mimtrot","Mimtrot","quadruped",["#e8b8c9","#c998ad","#f5eee0"],.3,["neutral"],0,{"farming":1,"transporting":1},[["wool",1,3],["leather",1,1]],"Pink pack alpaca.",0),
 ("doztail","Doztail","kitty",["#e8c9a8","#c9a888","#f5eee0"],.35,["neutral"],0,{"gathering":1},[["leather",1,1],["gold_coin",1,1]],"Lucky little fox.",0),
 ("hushsmith","Hushsmith","human",["#d88aa8","#b86a8a","#f5eee0"],.2,["neutral"],1,{"handiwork":2,"medicine":1,"transporting":1},[["pal_fluid",1,2],["leather",1,1]],"Heart-shaped salamander.",0),
 ("noctmane","Noctmane","quadruped",["#5a5a7a","#43435e","#c9d8e8"],.15,["dark"],1,{"handiwork":2},[["bone",1,2],["leather",1,2]],"Moonlit dark wolf.",1),
 ("shadehand","Shadehand","human",["#7a6a8a","#5d526d","#e8d44d"],.2,["dark"],1,{"medicine":1,"handiwork":1},[["bone",1,1],["venom_gland",1,1]],"Owl-sage dark wizard.",0),
 ("noctgloom","Noctgloom","ghost",["#8a7ad1","#6d5eb0","#f5eee0"],.25,["dark"],0,{"watering":1,"transporting":1},[["pal_fluid",1,2],["venom_gland",1,1]],"Vampire squid friend.",0),
 ("grimling","Grimling","human",["#8aa8d1","#6a85b0","#f5eee0"],.2,["dark"],1,{"handiwork":3,"medicine":1,"transporting":1},[["pal_fluid",1,2],["gold_coin",1,2]],"Lunar time-mage.",0),
 ("shadegloom","Shadegloom","ghost",["#8a6a9a","#6d517d","#f5eee0"],.3,["dark"],0,{"medicine":1},[["venom_gland",1,1]],"Night-whisper wisp.",0),
 ("shadewisp","Shadewisp","ghost",["#6a8a7a","#526d5e","#c9e8d8"],.25,["dark"],1,{"mining":1,"handiwork":1},[["venom_gland",1,2],["bone",1,1]],"Skull-lantern wanderer.",0),
 ("duskpurr","Duskpurr","kitty",["#9a7ab8","#7d5e9a","#e8d44d"],.25,["dark"],1,{"handiwork":1,"medicine":1},[["venom_gland",1,2],["wool",1,1]],"Bewitching night cat.",0),
 ("veilkin","Veilkin","human",["#b87a9a","#96587d","#f5eee0"],.2,["dark"],1,{"handiwork":2,"kindling":1},[["venom_gland",1,2],["flame_organ",1,1]],"Fox-witch spellcaster.",0),
 ("shadesmith","Shadesmith","human",["#4a3a5a","#3a2d47","#e8d44d"],.1,["dark","ground"],3,{"mining":3,"lumbering":2},[["venom_gland",3,5],["bone",2,3]],"Scorpion death-knight.",2),
 ("veilplume","Veilplume","bird",["#5a4a7a","#443761","#e8452f"],.1,["dark"],3,{"gathering":3,"electricity":2},[["venom_gland",3,5],["bone",2,3]],"Void-rift war raptor.",2),
 ("shadekin","Shadekin","human",["#6a5a7a","#53455e","#e8452f"],.1,["dark"],3,{"gathering":3,"mining":2},[["bone",3,5],["gold_coin",2,4]],"Abyssal doom knight.",2),
 ("noctplume","Noctplume","bird",["#6a5a8a","#53456d","#a8d8e8"],.15,["dark","electric"],2,{"transporting":2,"electricity":1},[["electric_organ",2,3],["venom_gland",1,2]],"Storm-soul herald.",2),
 ("duskwing","Duskwing","blob",["#8a7a9a","#6d5f7d","#d8c9a0"],.25,["dark"],0,{"gathering":1,"transporting":1},[["venom_gland",1,1]],"Squeaky night bat.",0),
 ("scalbeak","Scalbeak","bird",["#5a8ad1","#4370b0","#e8d44d"],.1,["dragon"],3,{"gathering":4},[["horn",3,5],["pal_fluid",2,4]],"Supersonic sky dragon.",2),
 ("nibhand","Nibhand","human",["#d8d8e8","#b8b8d1","#e8c9a0"],.1,["neutral"],3,{"mining":3,"handiwork":2},[["gold_coin",3,5],["bone",2,3]],"Sacred paladin legend.",1),
 ("scalcrest","Scalcrest","bird",["#8a9ad1","#6a7cb0","#f5eee0"],.15,["dragon"],2,{"gathering":2,"transporting":2},[["horn",1,3],["pal_fluid",1,3]],"Feathered dream drake.",0),
 ("wyrmhoof","Wyrmhoof","quadruped",["#4a4a6a","#383853","#e8452f"],.1,["dragon","dark"],3,{"mining":3,"handiwork":2},[["horn",3,5],["venom_gland",2,4]],"Metal-jawed void dragon.",2),
 ("vermtrot","Vermtrot","quadruped",["#a8c9e8","#85a8c9","#f5eee0"],.15,["dragon"],2,{"lumbering":2},[["horn",1,3],["leather",1,2]],"Gentle glade dragon.",0),
 ("embquill","Embquill","hedgehog",["#e88a4a","#c96d2f","#ffd76e"],.3,["fire"],1,{"kindling":1,"mining":1},[["flame_organ",1,3]],"Ember-quill burrower.",0),
 ("dewpuff","Dewpuff","blob",["#5ac9d1","#42a8b0","#f5eee0"],.3,["water"],0,{"watering":1},[["pal_fluid",1,2]],"Starfish water-drop.",0),
 ("faradwisp","Faradwisp","ghost",["#8ad1e8","#68b0c9","#e8d44d"],.3,["electric"],0,{"electricity":1,"transporting":1},[["electric_organ",1,2]],"Thundercloud puff.",0),
 ("soltalon","Soltalon","bird",["#e8a85a","#c98542","#3a3a4a"],.2,["fire"],1,{"kindling":1,"transporting":1},[["flame_organ",1,3]],"Soot-winged falcon.",1),
 ("lazburr","Lazburr","hedgehog",["#6a8a5a","#526d45","#d8c9a0"],.2,["water","ground"],1,{"watering":1,"mining":1},[["pal_fluid",1,3],["stone",1,2]],"Swamp-shell ambusher.",1),
 ("rimewhisk","Rimewhisk","mouse",["#c9e8f5","#a5c9d8","#f5eee0"],.4,["ice"],0,{"cooling":1,"gathering":1},[["ice_organ",1,1],["wool",1,1]],"Snow-hare hopper.",0),
 ("wortquill","Wortquill","hedgehog",["#7a8a6a","#5e6d52","#c9b88a"],.2,["grass","ground"],1,{"planting":1,"mining":1},[["stone",1,3],["red_berries",1,2]],"Thorn-back boulder.",0),
 ("noctfang","Noctfang","serpent",["#5a4a6a","#453a53","#e8452f"],.1,["dark","dragon"],3,{"mining":3,"handiwork":2},[["venom_gland",3,5],["horn",2,4]],"Abyss serpent overlord.",2),
 ("sprigveil","Sprigveil","ghost",["#c9d8a8","#a8b885","#e8d44d"],.3,["grass"],1,{"planting":1,"electricity":1},[["red_berries",1,3],["electric_organ",1,1]],"Biolume firefly sage.",0),
 ("digsnout","Digsnout","boar",["#8a7a6a","#6d5f52","#d8c9a0"],.15,["ground"],1,{"mining":2,"gathering":1},[["stone",2,4],["leather",1,2]],"Cliff-breaking boar.",1),
 ("bubgloom","Bubgloom","ghost",["#a8e8d8","#85c9b8","#f5eee0"],.35,["water"],0,{"watering":1,"cooling":1},[["pal_fluid",1,2]],"Steam-sprite kettle kin.",0),
 ("brancrest","Brancrest","bird",["#9a6a4a","#7d523a","#e8734a"],.15,["fire","neutral"],1,{"kindling":1,"gathering":1},[["gunpowder",1,3],["bone",1,1]],"Fuse-headed war bird.",1),
 ("embpaw","Embpaw","quadruped",["#e8734a","#c9552f","#f5eee0"],.3,["fire"],0,{"kindling":1,"transporting":1},[["flame_organ",1,2]],"Ember-tailed camp pup.",0),
 ("gritmite","Gritmite","hedgehog",["#a89468","#8a7452","#d8c9a0"],.35,["ground"],0,{"mining":1,"gathering":1},[["stone",1,3],["bone",1,1]],"Pill-bug dirt burrower.",0),
 ("corlfang","Corlfang","serpent",["#3a7a9a","#2d6080","#9be8d8"],.15,["water"],2,{"watering":2,"transporting":2},[["pal_fluid",2,4],["raw_fish",1,2]],"Tide-hunting brine serpent.",1),
 ("sparkhaunt","Sparkhaunt","ghost",["#5a5ae8","#3a3aa8","#e8d44d"],.1,["electric","dark"],3,{"electricity":3,"gathering":2},[["electric_organ",3,5],["venom_gland",1,2]],"Storm-wraith of the deep wilds.",2),
]

TIER_STATS = {0: (70,70,70,40,35,2,70), 1: (82,82,76,52,45,3,75), 2: (96,96,86,70,60,4,80), 3: (115,115,98,88,80,5,90)}
ELEM_SKILLS = {"neutral":["tackle","airCannon"],"fire":["flameBurst","ignitionBreath"],"water":["hydroJet","aquaBurst"],
 "grass":["seedMachine","grassTornado"],"electric":["shockwave","lightningStrike"],"ice":["iceMissile","blizzard"],
 "ground":["sandBlast","stoneShot"],"dark":["darkBall","nightmare"],"dragon":["dragonBurst","dragonCanon"]}

def gen():
    entries = []
    sprites = {}
    for sid,name,body,cols,fluff,elems,tier,work,drops,desc,hostile in NEW:
        hp,atk,de_,speed,cap,food,san = TIER_STATS[tier]
        e0, e1 = elems[0], elems[-1]
        skl = [[1, ELEM_SKILLS[e0][0]], [7, ELEM_SKILLS[e0][1]]]
        if e1 != e0:
            skl.append([12, ELEM_SKILLS[e1][0]])
        if tier >= 2:
            skl.append([15, ELEM_SKILLS[e1][1]])
        skills = [[l, s] for l, s in skl]
        ent = {"id":sid,"name":name,"glyph":name[0].lower(),"color":cols[0],"elements":elems,
               "hp":hp,"atk":atk,"def":de_,"speed":speed,"capturePower":cap,"food":food,"san":san,
               "work":work,"skills":skills,"drops":drops,"desc":desc,"hostile":hostile,"body":body}
        entries.append(ent)
        sprites[sid] = (body, cols, fluff)

    out = 'class_name SpeciesGen\n\nconst SPECIES = ' + json.dumps({e["id"]:e for e in entries}, indent=1) + '\n\n'
    zmap = {0: [], 1: [], 2: [], 3: []}
    for row in NEW:
        zmap[row[6]].append(row[0])
    out += 'const ZONE = ' + json.dumps(zmap) + '\n\n'
    out += '''static func species_of(id: String) -> Dictionary:
	return SPECIES.get(id, {})

static func zone_pool(z: int) -> Array:
	return ZONE.get(str(z), [])

static var _zone_of := {}
static func habitat(sid: String) -> int:
	# Kindex habitat: which wild band this species calls home (-1 = none)
	if _zone_of.is_empty():
		for z in ZONE:
			for s2 in ZONE[z]:
				_zone_of[s2] = int(z)
	return int(_zone_of.get(sid, -1))
'''
    io.open(R+'src/data/species_gen.gd','w',encoding='utf-8').write(out)

    # passives
    pas = {"burly":{"name":"Burly","def":1.15},"ferocious":{"name":"Ferocious","atk":1.15},
     "swift":{"name":"Swift","speed":1.12},"lucky":{"name":"Lucky","atk":1.05,"def":1.05},
     "pacifist":{"name":"Pacifist","atk":0.9,"san":1.3},"glutton":{"name":"Glutton","food":1.5},
     "artisan":{"name":"Artisan","work":1.25},"zen":{"name":"Zen","san":1.25},
     "coward":{"name":"Coward","atk":0.9,"speed":1.15},"hooligan":{"name":"Hooligan","atk":1.1,"san":0.9}}
    pout = 'class_name PassiveData\n\nconst PASSIVES = ' + json.dumps(pas,indent=1) + '\n'
    io.open(R+'src/data/passives.gd','w',encoding='utf-8').write(pout)

    # register sprites in gen_assets — replace any block we wrote last time
    # so re-runs stay clean instead of stacking duplicate update tables
    ga = io.open(R+'tools/gen_assets.py',encoding='utf-8').read()
    ga = re.sub(r'\nSPRITES\.update\(\{[\s\S]*?\n\}\)\n', '\n', ga)
    block = '\nSPRITES.update({\n' + ''.join(f'    "{sid}": ("{b}", {json.dumps(c)}, {fl}),\n' for sid,(b,c,fl) in sprites.items()) + '})\n\n'
    ga = ga.replace('if __name__ == "__main__":', block + 'if __name__ == "__main__":')
    io.open(R+'tools/gen_assets.py','w',encoding='utf-8').write(ga)
    print('species:', len(entries))

gen()
