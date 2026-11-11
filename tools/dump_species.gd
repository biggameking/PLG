extends SceneTree
## Dump species render params (id/name/color/elements/body) to JSON for the
## art pipeline. Run: godot --headless --path . -s tools/dump_species.gd
func _init() -> void:
	var out := []
	for sid in SpeciesData.SPECIES:
		var d: Dictionary = SpeciesData.SPECIES[sid]
		out.append({"id": sid, "name": d.get("name", sid),
			"color": d.get("color", "#888888"),
			"elements": d.get("elements", []),
			"body": d.get("body", "")})
	for sid in SpeciesGen.SPECIES:
		var d: Dictionary = SpeciesGen.SPECIES[sid]
		out.append({"id": sid, "name": d.get("name", sid),
			"color": d.get("color", "#888888"),
			"elements": d.get("elements", []),
			"body": d.get("body", "")})
	var f := FileAccess.open("res://tools/species_dump.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("dumped ", out.size(), " species")
	quit()
