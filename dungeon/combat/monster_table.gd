extends RefCounted

## Loads `res://dungeon/data/monsters.csv` (Explorer `priv/static/data/monsters.csv` mirror).

const ExplorerMapIconSizing := preload("res://dungeon/ui/explorer_map_icon_sizing.gd")
const CSV_PATH := "res://dungeon/data/monsters.csv"

static var _loaded: bool = false
static var _by_lower_name: Dictionary = {}


static func has_named_monster(monster_name: String) -> bool:
	ensure_loaded()
	var key := monster_name.strip_edges().to_lower()
	return _by_lower_name.has(key)


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_by_lower_name.clear()
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		push_warning("[Dungeoneers] monster_table: could not open " + CSV_PATH)
		return
	var header := f.get_csv_line()
	if header.is_empty():
		return
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.is_empty() or row[0].strip_edges().is_empty():
			continue
		var name := str(row[0]).strip_edges()
		if name.is_empty() or name.to_lower() == "name":
			continue
		var role_s := str(row[10]).strip_edges() if row.size() > 10 else ""
		var hunts_p := _parse_hunts_player_csv(row, role_s)
		var align_s := "neutral"
		if row.size() > 13:
			var a_raw := str(row[13]).strip_edges().to_lower()
			if a_raw == "lawful" or a_raw == "chaotic" or a_raw == "neutral":
				align_s = a_raw
		var size_f := 1.0
		if row.size() > 9:
			var sz_raw := str(row[9]).strip_edges()
			if sz_raw.is_valid_float():
				size_f = float(sz_raw)
		var rec := {
			"name": name,
			"image": str(row[1]) if row.size() > 1 else "",
			"armor_class": int(row[2]) if row.size() > 2 else 10,
			"hit_points": int(row[3]) if row.size() > 3 else 1,
			"attack_bonus": int(row[4]) if row.size() > 4 else 0,
			"damage_dice": str(row[5]) if row.size() > 5 else "1d4",
			"weapon": str(row[6]) if row.size() > 6 else "Claw",
			"treasure": str(row[7]).strip_edges() if row.size() > 7 else "",
			"rarity": str(row[8]).strip_edges().to_lower() if row.size() > 8 else "common",
			"size": size_f,
			"role": role_s,
			"hunts_player": hunts_p,
			"alignment": align_s,
		}
		var hp_for_cr: int = int(rec["hit_points"])
		var cr: int = 0
		if row.size() > 12:
			var crs2 := str(row[12]).strip_edges()
			if crs2.is_valid_int():
				cr = int(crs2)
		if cr <= 0:
			cr = clampi(int((hp_for_cr + 3) / 4.0), 1, 20)
		rec["challenge_rating"] = cr
		_by_lower_name[name.to_lower()] = rec


static func _parse_hunts_player_csv(row: PackedStringArray, role_s: String) -> bool:
	if row.size() > 11:
		var hs := str(row[11]).strip_edges().to_lower()
		if hs in ["1", "true", "yes", "y"]:
			return true
		if hs in ["0", "false", "no", "n"]:
			return false
	if role_s == "guard" or role_s == "npc":
		return false
	return true


static func role_for_monster_name(monster_name: String) -> String:
	var def := lookup_monster(monster_name)
	return str(def.get("role", "")).strip_edges().to_lower()


static func lookup_monster(monster_name: String) -> Dictionary:
	ensure_loaded()
	var key := monster_name.strip_edges().to_lower()
	if _by_lower_name.has(key):
		return (_by_lower_name[key] as Dictionary).duplicate(true)
	## Fallback: weak starter foe if theme lists a name not in CSV (should be rare after GEN-01 export).
	if _by_lower_name.has("rat"):
		return (_by_lower_name["rat"] as Dictionary).duplicate(true)
	return {}


static func instance_from_name(monster_name: String) -> Dictionary:
	var def := lookup_monster(monster_name)
	if def.is_empty():
		return {}
	var hp: int = maxi(1, int(def.get("hit_points", 1)))
	var m := def.duplicate(true)
	m["current_hit_points"] = hp
	m["max_hit_points"] = hp
	return m


static func challenge_rating_named(monster_name: String) -> int:
	var def := lookup_monster(monster_name)
	if def.is_empty():
		return 1
	return maxi(1, int(def.get("challenge_rating", 1)))


## Iteration for quest targets / tooling (read-only duplicate rows).
static func all_monsters() -> Array:
	ensure_loaded()
	var r: Array = []
	for k in _by_lower_name:
		r.append((_by_lower_name[k] as Dictionary).duplicate(true))
	return r


static func pick_random_global_by_rarity_max_cr(
	rarity: String, max_cr: int, rng: RandomNumberGenerator
) -> String:
	ensure_loaded()
	var want := rarity.strip_edges().to_lower()
	var cap := maxi(1, max_cr)
	var pool: Array[String] = []
	for k in _by_lower_name:
		var rec: Dictionary = _by_lower_name[k]
		if str(rec.get("rarity", "common")).to_lower() != want:
			continue
		if int(rec.get("challenge_rating", 99)) > cap:
			continue
		pool.append(str(rec.get("name", "Rat")))
	if pool.is_empty():
		return "Rat"
	return pool[rng.randi_range(0, pool.size() - 1)]


## Explorer `map_template.ex` map icon tiers — delegates to [`explorer_map_icon_sizing.gd`].
static func monster_map_token_base_px(size: float) -> int:
	return ExplorerMapIconSizing.base_px_from_size(size)
