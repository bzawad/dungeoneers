extends RefCounted

## Port of remaining `Dungeon.Generator.Features` placement used by Phase 1 pipelines.

const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const OrganicAreas := preload("res://dungeon/generator/organic_areas.gd")
const MonsterTable := preload("res://dungeon/combat/monster_table.gd")

const SPECIAL_FEATURE_REGISTRY_PATH := "res://dungeon/data/special_feature_registry.json"

static var _special_registry_loaded: bool = false
static var _special_names_by_rarity: Dictionary = {}  # tier String -> Array[String]
static var _special_all_names: PackedStringArray = PackedStringArray()
static var _special_name_lower_to_canonical: Dictionary = {}


static func _ensure_special_registry() -> void:
	if _special_registry_loaded:
		return
	_special_registry_loaded = true
	_special_names_by_rarity.clear()
	_special_all_names = PackedStringArray()
	_special_name_lower_to_canonical.clear()
	for tier in ["common", "uncommon", "rare", "elite"]:
		_special_names_by_rarity[tier] = []
	var txt := FileAccess.get_file_as_string(SPECIAL_FEATURE_REGISTRY_PATH)
	if txt.is_empty():
		push_warning("[GeneratorFeatures] missing " + SPECIAL_FEATURE_REGISTRY_PATH)
		return
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or parsed is not Array:
		return
	for item in parsed as Array:
		if item is not Dictionary:
			continue
		var d: Dictionary = item
		var nm := str(d.get("name", "")).strip_edges()
		if nm.is_empty():
			continue
		var rar := str(d.get("rarity", "common")).strip_edges().to_lower()
		if not rar in ["common", "uncommon", "rare", "elite"]:
			rar = "common"
		_special_name_lower_to_canonical[nm.to_lower()] = nm
		_special_all_names.append(nm)
		(_special_names_by_rarity[rar] as Array).append(nm)


static func special_feature_registry_has(feature_name: String) -> bool:
	_ensure_special_registry()
	return _special_name_lower_to_canonical.has(feature_name.strip_edges().to_lower())


## Explorer `determine_feature_rarity` (60 / 25 / 12 / 3) — not the same as monster rarity.
static func _determine_special_feature_rarity_roll(rng: RandomNumberGenerator) -> String:
	var n := rng.randi_range(1, 100)
	if n <= 60:
		return "common"
	if n <= 85:
		return "uncommon"
	if n <= 97:
		return "rare"
	return "elite"


static func _next_lower_feature_rarity(r: String) -> String:
	match r.to_lower():
		"elite":
			return "rare"
		"rare":
			return "uncommon"
		"uncommon":
			return "common"
		_:
			return "common"


static func pick_random_special_feature_by_rarity_global(rng: RandomNumberGenerator) -> String:
	_ensure_special_registry()
	if _special_all_names.is_empty():
		return "Barrel"
	var tier := _determine_special_feature_rarity_roll(rng)
	for _i in range(5):
		var bucket: Variant = _special_names_by_rarity.get(tier, [])
		if bucket is Array:
			var arr: Array = bucket as Array
			if not arr.is_empty():
				return str(arr[rng.randi_range(0, arr.size() - 1)])
		var nt := _next_lower_feature_rarity(tier)
		if nt == tier:
			break
		tier = nt
	return str(_special_all_names[rng.randi_range(0, _special_all_names.size() - 1)])


static func _filter_special_feature_entries(features: Array) -> Array:
	var out: Array = []
	for item in features:
		if item is not Dictionary:
			continue
		var d: Dictionary = item as Dictionary
		var raw_nm := str(d.get("name", "")).strip_edges()
		if raw_nm.is_empty():
			continue
		if not special_feature_registry_has(raw_nm):
			continue
		var canon: String = str(_special_name_lower_to_canonical.get(raw_nm.to_lower(), raw_nm))
		var rar := str(d.get("rarity", "common")).strip_edges().to_lower()
		out.append({"name": canon, "rarity": rar})
	return out


static func find_cavern_position(
	grid: Dictionary, cavern: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var cells: Array = cavern.get("cells", []) as Array
	var pool: Array[Vector2i] = []
	for c in cells:
		if c is not Vector2i:
			continue
		var p := c as Vector2i
		var t: String = str(grid.get(p, ""))
		if t == "floor" or t == "corridor":
			pool.append(p)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func find_guaranteed_floor_in_cavern(
	grid: Dictionary, cavern: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var cells: Array = cavern.get("cells", []) as Array
	var pool: Array[Vector2i] = []
	for c in cells:
		if c is Vector2i and str(grid.get(c, "")) == "floor":
			pool.append(c)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## Matches Explorer `Dungeon.Monster.determine_rarity/0` (60 / 25 / 10 / 5).
static func _determine_rarity_elixir_style(rng: RandomNumberGenerator) -> String:
	var n := rng.randi_range(1, 100)
	if n <= 60:
		return "common"
	if n <= 85:
		return "uncommon"
	if n <= 95:
		return "rare"
	return "elite"


static func _rarity_tier(rng: RandomNumberGenerator) -> String:
	return _determine_rarity_elixir_style(rng)


static func _next_lower_rarity(r: String) -> String:
	match r.to_lower():
		"elite":
			return "rare"
		"rare":
			return "uncommon"
		"uncommon":
			return "common"
		_:
			return "common"


static func _theme_monster_entries(theme: Dictionary) -> Array:
	var raw: Variant = theme.get("monsters", [])
	var arr: Array = raw as Array if raw is Array else []
	MonsterTable.ensure_loaded()
	var out: Array = []
	for e in arr:
		var n := _monster_entry_name(e)
		if n.is_empty():
			continue
		if MonsterTable.has_named_monster(n):
			out.append(e)
	return out


static func _monster_entry_name(entry: Variant) -> String:
	if entry is Dictionary:
		return str(entry.get("name", "")).strip_edges()
	return ""


static func _monster_entry_rarity(entry: Variant) -> String:
	if entry is Dictionary:
		return str(entry.get("rarity", "common")).strip_edges().to_lower()
	return "common"


static func _select_names_by_rarity(entries: Array, rarity: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var want := rarity.to_lower()
	for e in entries:
		if _monster_entry_rarity(e) == want:
			var n := _monster_entry_name(e)
			if not n.is_empty():
				out.append(n)
	return out


static func _select_names_cr(entries: Array, rarity: String, level: int) -> PackedStringArray:
	var out: PackedStringArray = []
	var want := rarity.to_lower()
	var lo := maxi(1, level - 2)
	var hi := level
	for e in entries:
		if _monster_entry_rarity(e) != want:
			continue
		var n := _monster_entry_name(e)
		if n.is_empty():
			continue
		var cr := MonsterTable.challenge_rating_named(n)
		if cr >= lo and cr <= hi:
			out.append(n)
	return out


static func _any_theme_monster_name(entries: Array, rng: RandomNumberGenerator) -> String:
	var alln: PackedStringArray = []
	for e in entries:
		var n := _monster_entry_name(e)
		if not n.is_empty():
			alln.append(n)
	if alln.is_empty():
		return MonsterTable.pick_random_global_by_rarity_max_cr("common", 20, rng)
	return alln[rng.randi_range(0, alln.size() - 1)]


static func _fallback_theme_level(entries: Array, level: int, rng: RandomNumberGenerator) -> String:
	var pref: PackedStringArray = []
	var lo2 := maxi(1, level - 2)
	var hi2 := level + 1
	for e in entries:
		var n := _monster_entry_name(e)
		if n.is_empty():
			continue
		var cr := MonsterTable.challenge_rating_named(n)
		if cr >= lo2 and cr <= hi2:
			pref.append(n)
	if not pref.is_empty():
		return pref[rng.randi_range(0, pref.size() - 1)]
	var below: PackedStringArray = []
	for e2 in entries:
		var n2 := _monster_entry_name(e2)
		if n2.is_empty():
			continue
		if MonsterTable.challenge_rating_named(n2) <= level:
			below.append(n2)
	if not below.is_empty():
		var best_cr := 0
		for nm in below:
			best_cr = maxi(best_cr, MonsterTable.challenge_rating_named(nm))
		var best: PackedStringArray = []
		for nm2 in below:
			if MonsterTable.challenge_rating_named(nm2) == best_cr:
				best.append(nm2)
		return best[rng.randi_range(0, best.size() - 1)]
	return MonsterTable.pick_random_global_by_rarity_max_cr("common", level, rng)


static func _pick_theme_monster_daylight(
	entries: Array, rarity: String, rng: RandomNumberGenerator
) -> String:
	var tier := rarity
	for _j in range(5):
		var picked := _select_names_by_rarity(entries, tier)
		if not picked.is_empty():
			return picked[rng.randi_range(0, picked.size() - 1)]
		var nt := _next_lower_rarity(tier)
		if nt == tier:
			break
		tier = nt
	return _any_theme_monster_name(entries, rng)


static func _pick_theme_monster_dim_or_dark(
	entries: Array, rarity: String, level: int, rng: RandomNumberGenerator
) -> String:
	var tier := rarity
	for _i in range(5):
		var picked := _select_names_cr(entries, tier, level)
		if not picked.is_empty():
			return picked[rng.randi_range(0, picked.size() - 1)]
		var nt := _next_lower_rarity(tier)
		if nt == tier:
			break
		tier = nt
	return _fallback_theme_level(entries, level, rng)


## Explorer `Monster.get_random_monster_for_theme_with_fog_type/3` (theme JSON + fog + level).
static func pick_monster_for_theme_with_fog_type(
	theme: Dictionary, rng: RandomNumberGenerator, map_level: int, player_level: int
) -> String:
	MonsterTable.ensure_loaded()
	var rarity := _determine_rarity_elixir_style(rng)
	var fog := str(theme.get("fog_type", "dark")).strip_edges().to_lower()
	var level := maxi(1, maxi(map_level, player_level))
	var entries := _theme_monster_entries(theme)
	if entries.is_empty():
		return MonsterTable.pick_random_global_by_rarity_max_cr(rarity, level, rng)
	if fog == "daylight":
		return _pick_theme_monster_daylight(entries, rarity, rng)
	return _pick_theme_monster_dim_or_dark(entries, rarity, level, rng)


static func pick_weighted_name_from_theme_list(
	features: Array, rng: RandomNumberGenerator, tier: String
) -> String:
	var filtered := _filter_special_feature_entries(features)
	var src: Array = filtered if not filtered.is_empty() else features
	var names: Array[String] = []
	for item in src:
		if item is Dictionary:
			var nm := str(item.get("name", "")).strip_edges()
			if nm.is_empty():
				continue
			var rar := str(item.get("rarity", "common")).strip_edges().to_lower()
			if rar == tier.strip_edges().to_lower():
				names.append(nm)
	if names.is_empty():
		for item2 in src:
			if item2 is Dictionary:
				var n2 := str((item2 as Dictionary).get("name", "")).strip_edges()
				if not n2.is_empty() and (filtered.is_empty() or special_feature_registry_has(n2)):
					names.append(n2)
	if names.is_empty():
		return pick_random_special_feature_by_rarity_global(rng)
	return names[rng.randi_range(0, names.size() - 1)]


static func pick_monster(
	theme: Dictionary, rng: RandomNumberGenerator, map_level: int = 1, player_level: int = 1
) -> String:
	return pick_monster_for_theme_with_fog_type(theme, rng, map_level, player_level)


static func pick_special_feature_name(theme: Dictionary, rng: RandomNumberGenerator) -> String:
	var filtered := _filter_special_feature_entries(theme.get("special_features", []) as Array)
	if filtered.is_empty():
		return pick_random_special_feature_by_rarity_global(rng)
	var rarity := _determine_special_feature_rarity_roll(rng)
	var tier := rarity
	for _i in range(5):
		var names: Array[String] = []
		for it in filtered:
			if it is not Dictionary:
				continue
			var d: Dictionary = it as Dictionary
			if str(d.get("rarity", "common")).strip_edges().to_lower() == tier:
				var nm := str(d.get("name", "")).strip_edges()
				if not nm.is_empty():
					names.append(nm)
		if not names.is_empty():
			return names[rng.randi_range(0, names.size() - 1)]
		var nt := _next_lower_feature_rarity(tier)
		if nt == tier:
			break
		tier = nt
	var fallback: PackedStringArray = []
	for it2 in filtered:
		if it2 is Dictionary:
			var n2 := str((it2 as Dictionary).get("name", "")).strip_edges()
			if not n2.is_empty():
				fallback.append(n2)
	if fallback.is_empty():
		return pick_random_special_feature_by_rarity_global(rng)
	return fallback[rng.randi_range(0, fallback.size() - 1)]


static func add_room_traps(grid: Dictionary, rooms: Array, rng: RandomNumberGenerator) -> void:
	if rooms.size() < 2:
		return
	for i in range(1, rooms.size()):
		if rng.randi_range(1, 20) != 1:
			continue
		var room: Dictionary = rooms[i]
		var p: Variant = _find_room_side_position(grid, room, rng)
		if p != null:
			grid[p] = "room_trap"


static func _find_room_side_position(
	grid: Dictionary, room: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["width"]
	var rh: int = room["height"]
	var cx: int = rx + (rw >> 1)
	var cy: int = ry + (rh >> 1)
	var pool: Array[Vector2i] = []
	for x in range(rx, rx + rw):
		for y in range(ry, ry + rh):
			if absi(x - cx) <= 1 and absi(y - cy) <= 1:
				continue
			var p := Vector2i(x, y)
			if grid.get(p, "") == "floor":
				pool.append(p)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func add_encounters_traditional(
	grid: Dictionary,
	rooms: Array,
	corridors: Array,
	theme: Dictionary,
	rng: RandomNumberGenerator,
	max_level: int
) -> void:
	var counter := 0
	if rooms.size() > 1:
		for i in range(1, rooms.size()):
			if rng.randi_range(1, 3) > 2:
				continue
			var room: Dictionary = rooms[i]
			var p: Variant = _find_room_side_position(grid, room, rng)
			if p != null:
				counter += 1
				var m := pick_monster(theme, rng, max_level, max_level)
				grid[p] = "encounter|E%d|%s" % [counter, m]
	for corridor in corridors:
		if corridor is not Dictionary:
			continue
		if rng.randi_range(1, 4) != 1:
			continue
		var path: Array = (corridor as Dictionary).get("path", []) as Array
		var pure: Array[Vector2i] = []
		for pt in path:
			if pt is not Vector2i:
				continue
			var q := pt as Vector2i
			if str(grid.get(q, "")) != "corridor":
				continue
			if DungeonGrid.point_in_any_room(q, rooms):
				continue
			pure.append(q)
		if pure.is_empty():
			continue
		var cp := pure[rng.randi_range(0, pure.size() - 1)]
		counter += 1
		var m2 := pick_monster(theme, rng, max_level, max_level)
		grid[cp] = "encounter|E%d|%s" % [counter, m2]


static func add_treasures_traditional(
	grid: Dictionary, rooms: Array, corridors: Array, rng: RandomNumberGenerator
) -> void:
	if rooms.size() > 1:
		for i in range(1, rooms.size()):
			if rng.randi_range(1, 2) != 1:
				continue
			var room: Dictionary = rooms[i]
			var p: Variant = _find_treasure_pos_room(grid, room, rng)
			if p != null:
				grid[p] = "trapped_treasure" if rng.randi_range(1, 10) == 1 else "treasure"
	for corridor in corridors:
		if corridor is not Dictionary:
			continue
		if rng.randi_range(1, 4) != 1:
			continue
		var path: Array = (corridor as Dictionary).get("path", []) as Array
		var pure: Array[Vector2i] = []
		for pt in path:
			if pt is not Vector2i:
				continue
			var q := pt as Vector2i
			if (
				DungeonGrid.position_available_for_treasure(grid, q)
				and not DungeonGrid.point_in_any_room(q, rooms)
			):
				pure.append(q)
		if pure.is_empty():
			continue
		var cp := pure[rng.randi_range(0, pure.size() - 1)]
		grid[cp] = "trapped_treasure" if rng.randi_range(1, 4) == 1 else "treasure"


static func _find_treasure_pos_room(
	grid: Dictionary, room: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["width"]
	var rh: int = room["height"]
	var cx: int = rx + (rw >> 1)
	var cy: int = ry + (rh >> 1)
	var pool: Array[Vector2i] = []
	for x in range(rx, rx + rw):
		for y in range(ry, ry + rh):
			if absi(x - cx) <= 1 and absi(y - cy) <= 1:
				continue
			var p := Vector2i(x, y)
			if DungeonGrid.position_available_for_treasure(grid, p):
				pool.append(p)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func add_food_traditional(
	grid: Dictionary, rooms: Array, rng: RandomNumberGenerator
) -> void:
	if rooms.size() < 2:
		return
	for i in range(1, rooms.size()):
		if rng.randi_range(1, 4) != 1:
			continue
		var room: Dictionary = rooms[i]
		var p: Variant = _find_food_pos(grid, room, rng)
		if p == null:
			continue
		var foods: Array[String] = ["bread", "cheese", "grapes"]
		grid[p] = foods[rng.randi_range(0, foods.size() - 1)]


static func _find_food_pos(
	grid: Dictionary, room: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	return _find_floor_not_center(grid, room, rng)


static func _find_floor_not_center(
	grid: Dictionary, room: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["width"]
	var rh: int = room["height"]
	var cx: int = rx + (rw >> 1)
	var cy: int = ry + (rh >> 1)
	var pool: Array[Vector2i] = []
	for x in range(rx, rx + rw):
		for y in range(ry, ry + rh):
			if absi(x - cx) <= 1 and absi(y - cy) <= 1:
				continue
			var p := Vector2i(x, y)
			if grid.get(p, "") == "floor":
				pool.append(p)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func add_healing_potions_traditional(
	grid: Dictionary, rooms: Array, corridors: Array, rng: RandomNumberGenerator
) -> void:
	if rooms.size() > 1:
		for i in range(1, rooms.size()):
			if rng.randi_range(1, 20) > 5:
				continue
			var p: Variant = _find_floor_not_center(grid, rooms[i], rng)
			if p != null:
				grid[p] = "healing_potion"
	for corridor in corridors:
		if corridor is not Dictionary:
			continue
		if rng.randi_range(1, 20) > 5:
			continue
		var path: Array = (corridor as Dictionary).get("path", []) as Array
		var pure: Array[Vector2i] = []
		for pt in path:
			if pt is not Vector2i:
				continue
			var q := pt as Vector2i
			var t: String = str(grid.get(q, ""))
			if (t == "floor" or t == "corridor") and not DungeonGrid.point_in_any_room(q, rooms):
				pure.append(q)
		if pure.is_empty():
			continue
		grid[pure[rng.randi_range(0, pure.size() - 1)]] = "healing_potion"


static func add_torches_traditional(
	grid: Dictionary, rooms: Array, rng: RandomNumberGenerator
) -> void:
	if rooms.size() < 2:
		return
	for i in range(1, rooms.size()):
		if rng.randi_range(1, 2) != 1:
			continue
		var p: Variant = _find_floor_not_center(grid, rooms[i], rng)
		if p != null:
			grid[p] = "torch"


## Explorer `Features.add_torches_with_level/3` (R1 torch when `dungeon_level` >= 2).
static func add_torches_traditional_with_level(
	grid: Dictionary, rooms: Array, dungeon_level: int, rng: RandomNumberGenerator
) -> void:
	if rooms.is_empty():
		return
	if dungeon_level >= 2:
		var p0: Variant = _find_floor_not_center(grid, rooms[0], rng)
		if p0 != null:
			grid[p0] = "torch"
	if rooms.size() < 2:
		return
	for i in range(1, rooms.size()):
		if rng.randi_range(1, 2) != 1:
			continue
		var p: Variant = _find_floor_not_center(grid, rooms[i], rng)
		if p != null:
			grid[p] = "torch"


static func add_special_features_traditional(
	grid: Dictionary, rooms: Array, theme: Dictionary, rng: RandomNumberGenerator
) -> void:
	if rooms.size() < 2:
		return
	for i in range(1, rooms.size()):
		var room: Dictionary = rooms[i]
		var area: int = int(room["width"]) * int(room["height"])
		var nfeat := _calc_feature_count(area, rng)
		var fc := 1
		for _j in nfeat:
			var p: Variant = _find_feature_pos(grid, room, rng)
			if p == null:
				break
			var fname := pick_special_feature_name(theme, rng)
			grid[p] = "special_feature|F%d|%s" % [fc, fname]
			fc += 1


static func _calc_feature_count(room_area: int, rng: RandomNumberGenerator) -> int:
	if room_area < 30:
		return 0 if rng.randi_range(1, 10) > 3 else 1
	if room_area < 80:
		var r := rng.randi_range(1, 10)
		if r <= 2:
			return 0
		if r <= 7:
			return 1
		return 2
	var r2 := rng.randi_range(1, 10)
	if r2 == 1:
		return 0
	if r2 <= 3:
		return 1
	if r2 <= 7:
		return 2
	return 3


static func _find_feature_pos(
	grid: Dictionary, room: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["width"]
	var rh: int = room["height"]
	var cx: int = rx + (rw >> 1)
	var cy: int = ry + (rh >> 1)
	var pool: Array[Vector2i] = []
	for x in range(rx, rx + rw):
		for y in range(ry, ry + rh):
			if absi(x - cx) <= 1 and absi(y - cy) <= 1:
				continue
			var p := Vector2i(x, y)
			if DungeonGrid.position_available_for_treasure(grid, p):
				pool.append(p)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func add_staircases_to_caverns(
	grid: Dictionary, caverns: Array, theme_direction: String, rng: RandomNumberGenerator
) -> void:
	if caverns.is_empty():
		return
	var first: Dictionary = caverns[0]
	var p0: Variant = find_guaranteed_floor_in_cavern(grid, first, rng)
	if p0 == null:
		var c := OrganicAreas.center(first)
		grid[c] = "floor"
		p0 = c
	grid[p0] = "starting_stair|S"
	var num_stairs := rng.randi_range(1, 3)
	var rest: Array = caverns.slice(1)
	_shuffle_array(rest, rng)
	var placed := 0
	for cavern in rest:
		if placed >= num_stairs:
			break
		if cavern is not Dictionary:
			continue
		var fp: Variant = find_cavern_position(grid, cavern, rng)
		if fp == null:
			continue
		var st := "stair_up" if theme_direction == "up" else "stair_down"
		if theme_direction == "lateral":
			st = "stair_down"
		grid[fp] = st
		placed += 1


static func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func add_encounters_to_caverns(
	grid: Dictionary, caverns: Array, theme: Dictionary, rng: RandomNumberGenerator, max_level: int
) -> void:
	if caverns.size() <= 1:
		return
	var counter := 0
	for i in range(1, caverns.size()):
		if rng.randi_range(1, 3) > 2:
			continue
		var cavern: Dictionary = caverns[i]
		var p: Variant = find_cavern_position(grid, cavern, rng)
		if p == null:
			continue
		counter += 1
		grid[p] = "encounter|E%d|%s" % [counter, pick_monster(theme, rng, max_level, max_level)]


static func add_treasures_to_caverns(
	grid: Dictionary, caverns: Array, rng: RandomNumberGenerator
) -> void:
	for cavern in caverns:
		if cavern is not Dictionary:
			continue
		if rng.randi_range(1, 2) != 1:
			continue
		var p: Variant = find_cavern_position(grid, cavern, rng)
		if p == null:
			continue
		grid[p] = "trapped_treasure" if rng.randi_range(1, 4) == 1 else "treasure"


static func add_food_to_caverns(
	grid: Dictionary, caverns: Array, rng: RandomNumberGenerator
) -> void:
	if caverns.size() <= 1:
		return
	for i in range(1, caverns.size()):
		if rng.randi_range(1, 4) != 1:
			continue
		var p: Variant = find_cavern_position(grid, caverns[i], rng)
		if p == null:
			continue
		var foods: Array[String] = ["bread", "cheese", "grapes"]
		grid[p] = foods[rng.randi_range(0, foods.size() - 1)]


static func add_healing_potions_to_caverns(
	grid: Dictionary, caverns: Array, rng: RandomNumberGenerator
) -> void:
	for cavern in caverns:
		if cavern is not Dictionary:
			continue
		if rng.randi_range(1, 20) > 5:
			continue
		var p: Variant = find_cavern_position(grid, cavern, rng)
		if p != null:
			grid[p] = "healing_potion"


static func add_torches_to_caverns(
	grid: Dictionary, caverns: Array, rng: RandomNumberGenerator
) -> void:
	if caverns.size() <= 1:
		return
	for i in range(1, caverns.size()):
		if rng.randi_range(1, 2) != 1:
			continue
		var p: Variant = find_cavern_position(grid, caverns[i], rng)
		if p != null:
			grid[p] = "torch"


## Explorer `Features.add_torches_to_caverns_with_level/3`.
static func add_torches_to_caverns_with_level(
	grid: Dictionary, caverns: Array, dungeon_level: int, rng: RandomNumberGenerator
) -> void:
	if caverns.is_empty():
		return
	if dungeon_level >= 2:
		var first: Dictionary = caverns[0]
		var p0: Variant = find_cavern_position(grid, first, rng)
		if p0 != null:
			grid[p0] = "torch"
	if caverns.size() <= 1:
		return
	for i in range(1, caverns.size()):
		if rng.randi_range(1, 2) != 1:
			continue
		var p: Variant = find_cavern_position(grid, caverns[i], rng)
		if p != null:
			grid[p] = "torch"


static func add_special_features_to_caverns(
	grid: Dictionary, caverns: Array, theme: Dictionary, rng: RandomNumberGenerator
) -> void:
	if caverns.size() <= 1:
		return
	for i in range(1, caverns.size()):
		var cavern: Dictionary = caverns[i]
		var cells: Array = cavern.get("cells", []) as Array
		var ncells: int = cells.size()
		var base: int = int(float(ncells) / 20.0)
		var r := rng.randi_range(1, 20)
		var bonus := 0
		if r > 7 and r <= 14:
			bonus = 1
		elif r > 14:
			bonus = 2
		var nfeat: int = maxi(1, base + bonus)
		var fc := 1
		for _j in nfeat:
			var p: Variant = find_cavern_position(grid, cavern, rng)
			if p == null:
				break
			var fname := pick_special_feature_name(theme, rng)
			grid[p] = "special_feature|F%d|%s" % [fc, fname]
			fc += 1


static func add_waypoints_to_areas(
	grid: Dictionary, areas: Array, rng: RandomNumberGenerator
) -> void:
	if areas.is_empty():
		return
	var first: Dictionary = areas[0]
	var p0: Variant = _find_waypoint_pos(grid, first, rng)
	if p0 == null:
		var c := OrganicAreas.center(first)
		grid[c] = "floor"
		p0 = c
	grid[p0] = "starting_waypoint|S"
	var nextra := rng.randi_range(1, 2)
	var rest: Array = areas.slice(1)
	_place_waypoints(grid, rest, nextra, rng)


static func _find_waypoint_pos(
	grid: Dictionary, area: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var cells: Array = area.get("cells", []) as Array
	var c := OrganicAreas.center(area)
	var pool: Array[Vector2i] = []
	for cell in cells:
		if cell is not Vector2i:
			continue
		var p := cell as Vector2i
		if str(grid.get(p, "")) != "floor":
			continue
		if absi(p.x - c.x) > 1 or absi(p.y - c.y) > 1:
			pool.append(p)
	if pool.is_empty():
		for cell2 in cells:
			if cell2 is Vector2i and str(grid.get(cell2, "")) == "floor":
				pool.append(cell2)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _place_waypoints(
	grid: Dictionary, areas: Array, count: int, rng: RandomNumberGenerator
) -> void:
	if count <= 0 or areas.is_empty():
		return
	var area: Dictionary = areas[0]
	var rest: Array = areas.slice(1)
	var p: Variant = _find_waypoint_pos(grid, area, rng)
	if p == null:
		_place_waypoints(grid, rest, count, rng)
		return
	grid[p] = "waypoint|%d" % rng.randi_range(1, 4)
	_place_waypoints(grid, rest, count - 1, rng)


static func add_city_linking_waypoints(
	grid: Dictionary, areas: Array, rng: RandomNumberGenerator
) -> void:
	var shuffled := areas.duplicate()
	_shuffle_array(shuffled, rng)
	_place_waypoints(grid, shuffled, mini(2, shuffled.size()), rng)


## Explorer `Enum.random(features)` on theme indoor/outdoor feature lists (no global registry).
static func pick_city_feature_name(
	theme: Dictionary, indoor: bool, rng: RandomNumberGenerator
) -> String:
	var arr: Array
	if indoor:
		arr = theme.get("indoor_features", []) as Array
	else:
		arr = theme.get("outdoor_features", []) as Array
	if arr.is_empty():
		return ""
	var entry: Variant = arr[rng.randi_range(0, arr.size() - 1)]
	if entry is Dictionary:
		return str((entry as Dictionary).get("name", "")).strip_edges()
	if entry is String:
		return str(entry).strip_edges()
	return ""


## Explorer `get_monster_for_city_block/3` — swap `monsters` with indoor/outdoor list for fog/CR picks.
static func pick_monster_for_city_encounter(
	theme: Dictionary, indoor: bool, rng: RandomNumberGenerator, max_level: int
) -> String:
	var mlist: Array
	if indoor:
		mlist = theme.get("indoor_monsters", []) as Array
	else:
		mlist = theme.get("outdoor_monsters", []) as Array
	if mlist.is_empty():
		return pick_monster(theme, rng, max_level, max_level)
	var theme_city: Dictionary = theme.duplicate()
	theme_city["monsters"] = mlist.duplicate()
	return pick_monster_for_theme_with_fog_type(theme_city, rng, max_level, max_level)


static func add_city_special_features(
	grid: Dictionary, city_blocks: Array, theme: Dictionary, rng: RandomNumberGenerator
) -> void:
	for block in city_blocks:
		if block is not Dictionary:
			continue
		var b: Dictionary = block
		var typ := str(b.get("type", ""))
		if typ == "building":
			var indoor_f: Array = theme.get("indoor_features", []) as Array
			if indoor_f.is_empty():
				continue
			if rng.randf() >= 0.3:
				continue
			_place_city_feature_cell(grid, b, true, theme, rng)
		elif typ == "road_intersection":
			var outdoor_f: Array = theme.get("outdoor_features", []) as Array
			if outdoor_f.is_empty():
				continue
			if rng.randf() >= 0.4:
				continue
			_place_city_feature_cell(grid, b, false, theme, rng)


static func _place_city_feature_cell(
	grid: Dictionary, block: Dictionary, indoor: bool, theme: Dictionary, rng: RandomNumberGenerator
) -> void:
	var cells: Array = []
	if indoor:
		cells = block.get("floor_cells", []) as Array
	else:
		cells = block.get("cells", []) as Array
	var pool: Array[Vector2i] = []
	for c in cells:
		if c is not Vector2i:
			continue
		var p := c as Vector2i
		var want := "floor" if indoor else "road"
		if str(grid.get(p, "")) == want:
			pool.append(p)
	if pool.is_empty():
		return
	var pos := pool[rng.randi_range(0, pool.size() - 1)]
	var nm := pick_city_feature_name(theme, indoor, rng)
	if nm.is_empty():
		return
	grid[pos] = "special_feature|%s|%s" % [nm, nm]


static func add_encounters_to_city_areas(
	grid: Dictionary,
	city_blocks: Array,
	theme: Dictionary,
	rng: RandomNumberGenerator,
	max_level: int
) -> void:
	if city_blocks.size() <= 1:
		return
	var counter := 0
	for i in range(1, city_blocks.size()):
		if rng.randi_range(1, 3) > 2:
			continue
		var block: Dictionary = city_blocks[i]
		var p: Variant = _find_city_block_pos(grid, block, rng)
		if p == null:
			continue
		counter += 1
		var indoor := str(block.get("type", "")) == "building"
		var mname := pick_monster_for_city_encounter(theme, indoor, rng, max_level)
		grid[p] = "encounter|E%d|%s" % [counter, mname]


static func find_waypoint_position(
	grid: Dictionary, area: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	return _find_waypoint_pos(grid, area, rng)


static func find_city_block_position(
	grid: Dictionary, block: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	return _find_city_block_pos(grid, block, rng)


static func _city_cell_near_map_edge(p: Vector2i, margin: int) -> bool:
	return (
		p.x <= margin
		or p.x >= DungeonGrid.MAP_WIDTH - margin - 1
		or p.y <= margin
		or p.y >= DungeonGrid.MAP_HEIGHT - margin - 1
	)


## Explorer `find_city_waypoint_position/3` (margin 12 toward map edge, then any road in block).
static func find_city_waypoint_position(
	grid: Dictionary, block: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var cells: Array = block.get("cells", []) as Array
	var edge_pool: Array[Vector2i] = []
	var all_pool: Array[Vector2i] = []
	for c in cells:
		if c is not Vector2i:
			continue
		var p := c as Vector2i
		if str(grid.get(p, "")) != "road":
			continue
		all_pool.append(p)
		if _city_cell_near_map_edge(p, 12):
			edge_pool.append(p)
	var use: Array[Vector2i] = edge_pool if not edge_pool.is_empty() else all_pool
	if use.is_empty():
		return null
	return use[rng.randi_range(0, use.size() - 1)]


static func _find_city_block_pos(
	grid: Dictionary, block: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var typ := str(block.get("type", ""))
	var pool: Array[Vector2i] = []
	var cells: Array
	if typ == "building":
		cells = block.get("floor_cells", []) as Array
		for c in cells:
			if c is Vector2i and str(grid.get(c, "")) == "floor":
				pool.append(c)
	else:
		cells = block.get("cells", []) as Array
		for c in cells:
			if c is Vector2i and str(grid.get(c, "")) == "road":
				pool.append(c)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


## Explorer `Dungeon.Generator.Features.special_feature_creates_light?/1` (subset used by fog init).
const _CREATES_LIGHT_FEATURE_NAMES := {
	"altar": true,
	"brazier": true,
	"campfire": true,
	"candle": true,
	"fireplace": true,
}


static func special_feature_tile_emits_light(tile_str: String) -> bool:
	if not tile_str.begins_with("special_feature|"):
		return false
	var parts := tile_str.split("|")
	if parts.size() < 3:
		return false
	return _CREATES_LIGHT_FEATURE_NAMES.has(parts[2].strip_edges().to_lower())
