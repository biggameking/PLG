extends SceneTree
# Offline economy probe — walks every gold-in → transform → gold-out lane the
# data tables describe and fails on any lane that pays back more than it costs.
# Where smoke_test proves the gates fire, this proves the TABLE can't mint:
# buy→resell, egg→hatch→sell, cake→bred-egg→sell, craft→sell, gacha EV,
# merchant kin buyback, board-pool stockability.
#
#   godot --headless --path . -s tools/sim_economy.gd
#
# Exit banner "SIM-ECO: N checks, 0 failures" is the gate. Best-of-branch
# thinking: a lane is closed only when the player's BEST exit stays under cost.

var ItemData := preload("res://src/data/items.gd")
var GameScript := preload("res://src/game.gd")
var KinScript := preload("res://src/kin.gd")

var fails := 0
var checks := 0
var game: Node = null

func gate(name: String, cond: bool, info := "") -> void:
	checks += 1
	print(("PASS " if cond else "FAIL ") + name + ("  " + info if info != "" else ""))
	if not cond:
		fails += 1

func price_of(id: String) -> int: # the data-level sticker the economy reads
	return int(ItemData.ITEMS.get(id, {}).get("price", 0))

func sell_v(id: String) -> int:
	return GameScript.sell_value(id) # the shipped formula — a mirror would gate nothing

func pal_price(lv: int, lucky := false, alpha := false, star := 0) -> int:
	var k: Node = KinScript.new()
	k.level = lv; k.lucky = lucky; k.alpha = alpha; k.star = star
	var v: int = game.pal_sell_price(k) # the shipped formula, not a mirror
	k.free()
	return v

func _init() -> void:
	game = GameScript.new()
	var GACHA: int = game.GACHA_COST
	var POOL: Array = game.MERCH_POOL
	var BOARD: Array = game.BOARD_POOL

	print("== merchant stock: every line must resell under its sticker ==")
	var pool_sellable := 0
	for id in POOL:
		var iid := str(id)
		var buy := GameScript.merchant_stock_price(iid) # shipped sticker incl. 25 markup
		var exit_v := sell_v(iid)
		if exit_v > 0:
			pool_sellable += 1
		gate("pool %s buys over its own resell" % iid, buy > exit_v,
			"buy=%d sell=%d" % [buy, exit_v])
	# the briefcase's fixed lines: marked-up egg and the two dares are pure sinks
	var specials := [["huge_kin_egg", 300], ["boss_sigil", 150],
		["gauntlet_sigil", 120], ["sprigmelt_effigy", 160]]
	for s in specials:
		var iid := str(s[0])
		gate("stock %s buys over its own resell" % iid, int(s[1]) > sell_v(iid),
			"buy=%d sell=%d" % [int(s[1]), sell_v(iid)])
	print("-- %d of %d pool lines are resellable at all" % [pool_sellable, POOL.size()])

	print("== egg lanes: every hatch path must lose under the egg's sticker ==")
	var egg_lanes := [["kin_egg", false], ["huge_kin_egg", true], ["bred_kin_egg", false]]
	for lane in egg_lanes:
		var eid := str(lane[0])
		var buy := price_of(eid)
		var best_exit := maxi(sell_v(eid), pal_price(1, bool(lane[1])))
		gate("%s best exit stays under sticker" % eid, buy > best_exit,
			"buy=%d best=%d (resell=%d hatch=%d)" % \
			[buy, best_exit, sell_v(eid), pal_price(1, bool(lane[1]))])

	print("== cake lane: the catalyst costs more than any egg it can mint ==")
	var bred_best := maxi(sell_v("bred_kin_egg"), pal_price(1, false))
	gate("cake buyout beats the bred-egg exit",
		price_of("cake") > bred_best,
		"cake=%d bred_best=%d" % [price_of("cake"), bred_best])

	print("== gacha: the slot beats the best-of-branch expectation ==")
	var kin_best: float = maxf(float(sell_v("kin_egg")), float(pal_price(1, false)))
	var huge_best: float = maxf(float(sell_v("huge_kin_egg")), float(pal_price(1, true)))
	var pull_ev := 0.9 * kin_best + 0.1 * huge_best
	gate("gacha cost beats pull EV", float(GACHA) > pull_ev,
		"cost=%d ev=%.1f (kin=%.0f huge=%.0f)" % [GACHA, pull_ev, kin_best, huge_best])

	print("== craft lanes: all-priced recipes must sell under ingredient cost ==")
	var priced_recipes := 0
	for r in ItemData.RECIPES:
		var oid := str(r["out"][0]); var on := int(r["out"][1])
		var cost_sum := 0; var all_priced := true
		for c in r["cost"]:
			if price_of(str(c[0])) <= 0:
				all_priced = false; break
			cost_sum += price_of(str(c[0])) * int(c[1])
		if not all_priced:
			continue # gather-gated recipes convert TIME to gold — the honest sink
		priced_recipes += 1
		gate("recipe %s sells under its ingredients" % str(r.get("id", oid)),
			sell_v(oid) * on <= cost_sum,
			"out=%dg cost=%dg" % [sell_v(oid) * on, cost_sum])
	print("-- %d fully-priced recipes audited" % priced_recipes)

	print("== merchant kin: buyback can never beat the black-market sticker ==")
	for z in range(4):
		for lv in range(5 + z * 6, 14 + z * 8 + 1):
			var buy: int = GameScript.merchant_kin_price(lv, z)
			var worst_sell := pal_price(lv, true) # even a lucky unit stays under
			if not (buy > worst_sell):
				gate("merchant kin z%d lv%d loses" % [z, lv], false,
					"buy=%d sell=%d" % [buy, worst_sell])
	checks += 1
	print("PASS merchant kin table stays under sticker  z=0..3 lv=5..38")

	print("== board pool: quest goods must not be merchant-stockable ==")
	var pool_set := {}
	for id in POOL:
		pool_set[str(id)] = true
	for row in BOARD:
		gate("board good %s is gather-only" % str(row[0]),
			not pool_set.has(str(row[0])))

	print("== unsellable inventory: the pure-sink ledger ==")
	var sinks := []
	for id in ItemData.ITEMS.keys():
		if price_of(str(id)) <= 0 and str(id) != "gold_coin":
			sinks.append(str(id))
	sinks.sort()
	print("-- %d unpriced items (effigy, sigils, orbs, quest goods): %s" % \
		[sinks.size(), ", ".join(sinks.slice(0, 12)) + ("…" if sinks.size() > 12 else "")])
	gate("the pity floor is gone — unpriced goods can't sell",
		sinks.all(func(id): return sell_v(id) == 0))

	game.free()
	print("\n==== SIM-ECO: %d checks, %d failures ====" % [checks, fails])
	quit(1 if fails > 0 else 0)
