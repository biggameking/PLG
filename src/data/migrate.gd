class_name Migrate
# S1 legacy save ids -> renamed ids (species/items/structures).
const ID := {
 "anubis": "terrkin",
 "arsox": "scalfang",
 "astegon": "wyrmhoof",
 "azurobe": "ripwrith",
 "beakon": "zapplume",
 "beegarde": "wortling",
 "blazamut": "cindchew",
 "blazehowl": "cindpaw",
 "blazequil": "embquill",
 "bombird": "brancrest",
 "brackent": "corlfang",
 "bristla": "thornhoof",
 "broncherry": "leaftrot",
 "bushi": "branling",
 "caprity": "petalantler",
 "catress": "duskpurr",
 "cattiva": "puffmite",
 "cawgnito": "murkwing",
 "celaray": "bringloom",
 "chikipi": "fenlump",
 "chillet": "frostfang",
 "cinnamoth": "mosswisp",
 "cragboar": "digsnout",
 "cremis": "nibjelly",
 "daedream": "shadelump",
 "dazzi": "sparkwhisk",
 "depresso": "shademite",
 "digtoise": "loamquill",
 "dinossom": "briarmaw",
 "direhowl": "tammane",
 "dreadmaw": "noctfang",
 "dumud": "loammelt",
 "dustmite": "gritmite",
 "eikthyrdeer": "dozantler",
 "elizabee": "mossveil",
 "elphidran": "vermtrot",
 "emberwing": "soltalon",
 "flambelle": "pyrejelly",
 "flopie": "thornmelt",
 "foxparks": "cindlump",
 "foxparks_harness": "cindlump_harness",
 "frostallion": "snovstride",
 "frostbun": "rimewhisk",
 "fuack": "quackbill",
 "fuddler": "terrnib",
 "galeclaw": "bramplume",
 "giga_sphere": "giga_orb",
 "glimmora": "sprigveil",
 "gobfin": "bubgoo",
 "gorirat": "puffchim",
 "grintale": "tawtail",
 "grizzbolt": "statchew",
 "hangyu": "chilgloom",
 "helzephyr": "noctplume",
 "hoocrates": "shadehand",
 "huge_pal_egg": "huge_kin_egg",
 "hydrostar": "dewpuff",
 "incineram": "pyresmith",
 "jetragon": "scalbeak",
 "jolthog": "faradlump",
 "jormuntide": "tidscale",
 "kelpsea": "bubwrith",
 "killamari": "noctgloom",
 "lamball": "fenjelly",
 "legendary_sphere": "legendary_orb",
 "lifmunk": "sprigmelt",
 "lifmunk_effigy": "sprigmelt_effigy",
 "lifmunk_smg": "sprigmelt_smg",
 "loupmoon": "noctmane",
 "lovander": "hushsmith",
 "lullu": "fernveil",
 "lunaris": "grimling",
 "maraith": "shadewisp",
 "mau": "shademelt",
 "mau_cryst": "snowtail",
 "mega_sphere": "mega_orb",
 "melpaca": "mimtrot",
 "menasting": "shadesmith",
 "mirelurk": "lazburr",
 "mossanda": "fernchim",
 "mozzarina": "piplump",
 "necromus": "shadekin",
 "nox": "shadegloom",
 "pal_bed": "kin_bed",
 "pal_condenser": "kin_condenser",
 "pal_egg": "kin_egg",
 "pal_sphere": "kin_orb",
 "paladius": "nibhand",
 "pal_bait": "kin_bait",
 "pal_fluid": "kin_fluid",
 "palbox": "kinbox",
 "paldium": "lumenite",
 "pengullet": "corlmite",
 "pengullet_launcher": "corlmite_launcher",
 "penking": "marlump",
 "petallia": "floraling",
 "pyropup": "embpaw",
 "quivern": "scalcrest",
 "ragnahawk": "pyreplume",
 "rayhound": "zaptrot",
 "reindrix": "snovfawn",
 "relaxaurus": "ripbell",
 "reptyro": "grithoof",
 "ribbuny": "hushnib",
 "robinquill": "worthand",
 "rooby": "branpurr",
 "rushoar": "loampuff",
 "shadowbeak": "veilplume",
 "sibelyx": "glacmane",
 "sparkit": "voltgoo",
 "sphere_launcher": "orb_launcher",
 "stormpuff": "faradwisp",
 "surfdog": "dewmane",
 "suzaku": "flarbeak",
 "swee": "glaclump",
 "sweepa": "rimemane",
 "sweety": "mossjelly",
 "syndicate_grunt": "ironpact_grunt",
 "syndicate_sweeper": "ironpact_sweeper",
 "tanzee": "briargoo",
 "tanzee_rifle": "briargoo_rifle",
 "teafant": "lazpuff",
 "thornite": "wortquill",
 "thundergeist": "sparkhaunt",
 "tocotoco": "tambeak",
 "tombat": "duskwing",
 "ultra_sphere": "ultra_orb",
 "univolt": "statstride",
 "vaelet": "ivyveil",
 "vapori": "bubgloom",
 "verdash": "briarchim",
 "vixy": "doztail",
 "wixen": "veilkin",
 "woolipop": "mimspike",
 "wumpo": "snovmool",
}

static func rid(x) -> Variant:
	return ID.get(str(x), x)

# Legacy save fields may store old ids inside many shapes. Walk the known
# containers once so a pre-rename save still loads under the new ids.
static func save_dict(d: Dictionary) -> Dictionary:
	if not d.has("kin") and d.has("pals"):
		d["kin"] = d["pals"]
	for dd in d.get("drops", []):
		if dd is Dictionary and dd.has("id"):
			dd["id"] = rid(dd["id"])
	for rc in d.get("crafts", []):
		if rc is Dictionary:
			rc["out"] = rid(rc.get("out", ""))
	if d.get("items") is Dictionary:
		var ni := {}
		for k in d["items"]:
			ni[rid(k)] = d["items"][k]
		d["items"] = ni
	if d.get("catches") is Dictionary:
		var nc := {}
		for k in d["catches"]:
			nc[rid(k)] = d["catches"][k]
		d["catches"] = nc
	if d.get("dex_seen") is Array:
		d["dex_seen"] = d["dex_seen"].map(func(x): return rid(x))
	if d.get("unlocked") is Array:
		d["unlocked"] = d["unlocked"].map(func(x): return rid(x))
	if d.get("mflags") is Dictionary and d["mflags"].has("sphere"):
		d["mflags"]["orb"] = d["mflags"]["sphere"]; d["mflags"].erase("sphere")
	var bq = d.get("board_quest", {})
	if bq is Dictionary:
		bq["id"] = rid(bq.get("id", "")); bq["sp"] = rid(bq.get("sp", ""))
	var seq = d.get("equip", {})
	if seq is Dictionary:
		for s in seq:
			seq[s] = rid(seq[s])
	for pd in d.get("kin", []):
		if pd is Dictionary:
			pd["sp"] = rid(pd.get("sp", ""))
			if pd.get("carry") is Dictionary: # a hauler's load is an item id too
				pd["carry"]["id"] = rid(pd["carry"].get("id", ""))
	var st = d.get("structures", {})
	if st is Dictionary:
		for sk in st:
			var sv = st[sk]
			if sv is not Dictionary:
				continue
			sv["id"] = rid(sv.get("id", ""))
			if sv.get("store") is Dictionary:
				var ns := {}
				for k in sv["store"]:
					ns[rid(k)] = sv["store"][k]
				sv["store"] = ns
			if sv.get("cap") is Dictionary: # serialized cage key is "cap"
				sv["cap"]["sp"] = rid(sv["cap"].get("sp", ""))
			if sv.get("egg") is Array: # serialized ranch key; entries [sp,sp,talent,talent,...]
				for pr in sv["egg"]:
					if pr is Array:
						for i in mini(2, pr.size()):
							pr[i] = rid(pr[i])
			if sv.get("inc") is Dictionary and sv["inc"].get("pair") is Array:
				var ip: Array = sv["inc"]["pair"] # in-flight incubator pair
				for i in mini(2, ip.size()):
					ip[i] = rid(ip[i])
			if sv.get("mimic") is String:
				sv["mimic"] = rid(sv["mimic"])
	for rb in d.get("respawns", []):
		if rb is Dictionary:
			rb["sid"] = rid(rb.get("sid", ""))
	return d
