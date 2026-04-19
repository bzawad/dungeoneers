extends RefCounted

## Explorer `SpecialFeatureSystem.process_feature_investigation` + `Dungeon.Dice.chance_succeeds?/1`
## (ordered: treasure → special_item → rumor → trap → monster → nothing). Deterministic from seed + cell.

const JSON_PATH := "res://dungeon/data/special_feature_contents.json"

static var _registry: Dictionary = {}
static var _registry_loaded: bool = false


static func _ensure_registry() -> void:
	if _registry_loaded:
		return
	_registry_loaded = true
	_registry.clear()
	var txt := FileAccess.get_file_as_string(JSON_PATH)
	if txt.is_empty():
		push_warning("[Dungeoneers] special_feature_investigation: missing " + JSON_PATH)
		return
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		_registry = parsed as Dictionary
	else:
		push_warning("[Dungeoneers] special_feature_investigation: invalid JSON")


static func _default_config() -> Dictionary:
	return {
		"treasure_chance": 0,
		"special_item_chance": 0,
		"rumor_chance": 0,
		"trap_chance": 0,
		"monster_chance": 0,
		"monster_list": [],
	}


static func contents_config_for_feature(feature_name: String) -> Dictionary:
	_ensure_registry()
	var key := feature_name.strip_edges()
	if _registry.has(key):
		var d: Dictionary = _registry[key]
		var out := _default_config()
		for k in out.keys():
			if d.has(k):
				if k == "monster_list" and d[k] is Array:
					out[k] = (d[k] as Array).duplicate()
				elif str(k).ends_with("_chance"):
					out[k] = int(d[k])
		return out
	return _default_config()


static func feature_name_from_tile(raw_tile: String) -> String:
	## `special_feature|F1|Barrel` → Barrel
	var parts := raw_tile.split("|")
	if parts.size() >= 3:
		return str(parts[2]).strip_edges()
	if parts.size() == 2:
		return str(parts[1]).strip_edges()
	return "Unknown"


static func _rng(authority_seed: int, cell: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(authority_seed) * 908_633_393
		^ cell.x * 71_603
		^ cell.y * 1_000_003
		^ int(salt) * 12_345_679
	)
	return rng


## Returns `kind` in treasure|special_item|rumor|trap|monster|nothing plus payload fields.
static func evaluate(authority_seed: int, cell: Vector2i, feature_name: String) -> Dictionary:
	var cfg := contents_config_for_feature(feature_name)
	var rng := _rng(authority_seed, cell, 88_721_331)

	if int(cfg.get("treasure_chance", 0)) > 0:
		var r1 := rng.randi_range(1, 100)
		if r1 <= int(cfg.get("treasure_chance", 0)):
			var gold := rng.randi_range(1, 10) + 5
			return {"kind": "treasure", "gold": gold}

	if int(cfg.get("special_item_chance", 0)) > 0:
		var r2 := rng.randi_range(1, 100)
		if r2 <= int(cfg.get("special_item_chance", 0)):
			return {"kind": "special_item"}

	if int(cfg.get("rumor_chance", 0)) > 0:
		var r3 := rng.randi_range(1, 100)
		if r3 <= int(cfg.get("rumor_chance", 0)):
			var pool: Array[String] = [
				"Travelers speak of lights moving where no torch should burn.",
				"An old merchant muttered about sealed doors and missing patrols.",
				"You overhear a worried guard mention strange noises below the chapel.",
			]
			var rumor := pool[rng.randi_range(0, pool.size() - 1)]
			return {"kind": "rumor", "rumor": rumor}

	if int(cfg.get("trap_chance", 0)) > 0:
		var r4 := rng.randi_range(1, 100)
		if r4 <= int(cfg.get("trap_chance", 0)):
			## Explorer `handle_trap_investigation_result` rolls 1d6 for feature traps.
			var dmg := rng.randi_range(1, 6)
			return {"kind": "trap", "damage": dmg}

	var mch := int(cfg.get("monster_chance", 0))
	if mch > 0:
		var r5 := rng.randi_range(1, 100)
		if r5 <= mch:
			var lst: Array = cfg.get("monster_list", [])
			if lst is Array and not lst.is_empty():
				var pick := str(lst[rng.randi_range(0, lst.size() - 1)]).strip_edges()
				if not pick.is_empty():
					return {"kind": "monster", "monster": pick}

	return {"kind": "nothing"}
