extends RefCounted

## Full Phase 1 port of `Dungeon.Generator` dispatch (`generate_with_theme_data/1` pipeline).

const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const DungeonRooms := preload("res://dungeon/generator/rooms.gd")
const DungeonCorridors := preload("res://dungeon/generator/corridors.gd")
const DungeonFeaturesDungeon := preload("res://dungeon/generator/features_dungeon.gd")
const DungeonThemes := preload("res://dungeon/generator/dungeon_themes.gd")
const OrganicAreas := preload("res://dungeon/generator/organic_areas.gd")
const MapLinkSystem := preload("res://dungeon/generator/map_link_system.gd")
const GeneratorFeatures := preload("res://dungeon/generator/generator_features.gd")
const CitiesGenerator := preload("res://dungeon/generator/cities_generator.gd")


static func count_exits(grid: Dictionary) -> int:
	var n := 0
	for v in grid.values():
		if not v is String:
			continue
		var s: String = v
		if s == "stair_up" or s == "stair_down":
			n += 1
		elif s.begins_with("starting_stair|"):
			n += 1
		elif s.begins_with("starting_waypoint|") or s.begins_with("waypoint|"):
			n += 1
	return n


static func generate_for_legacy_cli(
	rng: RandomNumberGenerator, theme_direction: String
) -> Dictionary:
	return generate_for_legacy_cli_with_level(rng, theme_direction, 1)


## Legacy `up` / `down` CLI with dungeon level (torch parity vs `generate_with_theme_data/...`).
static func generate_for_legacy_cli_with_level(
	rng: RandomNumberGenerator, theme_direction: String, dungeon_level: int = 1
) -> Dictionary:
	DungeonThemes.load_themes()
	var theme_name := "Ancient Castle" if theme_direction == "up" else "Dark Caverns"
	var theme: Dictionary = DungeonThemes.find_theme_by_name(theme_name)
	if theme.is_empty():
		push_warning("[DungeonGenerator] theme not found: " + theme_name)
		return _minimal_traditional(rng, theme_direction)
	return generate_with_theme_data(rng, theme, 1, dungeon_level)


static func generate_with_theme_name(rng: RandomNumberGenerator, theme_name: String) -> Dictionary:
	DungeonThemes.load_themes()
	var theme: Dictionary = DungeonThemes.find_theme_by_name(theme_name)
	if theme.is_empty():
		push_warning("[DungeonGenerator] unknown theme " + theme_name)
		return generate_for_legacy_cli(rng, "up")
	return generate_with_theme_data(rng, theme, 1, 1)


## Mirrors `Dungeon.Generator.generate_with_player_level/2` (random theme + level fields for future parity).
static func generate_with_player_level(
	rng: RandomNumberGenerator, player_level: int, dungeon_level: int = 1
) -> Dictionary:
	DungeonThemes.load_themes()
	var theme: Dictionary = DungeonThemes.get_random_theme(rng)
	if theme.is_empty():
		return generate_for_legacy_cli(rng, "up")
	var t2: Dictionary = theme.duplicate()
	t2["player_level"] = player_level
	t2["dungeon_level"] = dungeon_level
	return generate_with_theme_data(rng, t2, player_level, dungeon_level)


## Explorer `Generator.generate_with_theme_type_and_levels/3` (random theme of a generation type).
static func generate_with_theme_type_and_levels(
	rng: RandomNumberGenerator, generation_type: String, player_level: int, dungeon_level: int
) -> Dictionary:
	DungeonThemes.load_themes()
	var themes: Array = DungeonThemes.get_themes_by_type(generation_type)
	if themes.is_empty():
		return generate_with_player_level(rng, player_level, dungeon_level)
	var theme: Dictionary = themes[rng.randi_range(0, themes.size() - 1)] as Dictionary
	return generate_with_theme_data(rng, theme, player_level, dungeon_level)


## Explorer `Generator.generate_with_theme_type/1` (random theme of type; levels default to 1).
static func generate_with_theme_type(
	rng: RandomNumberGenerator, generation_type: String
) -> Dictionary:
	return generate_with_theme_type_and_levels(rng, generation_type, 1, 1)


## Explorer `generate_with_theme_data_and_level/2` — single level for player + dungeon (torch rules).
static func generate_with_theme_data_and_level(
	rng: RandomNumberGenerator, theme: Dictionary, level: int
) -> Dictionary:
	return generate_with_theme_data(rng, theme, level, level)


static func generate_with_theme_data(
	rng: RandomNumberGenerator, theme: Dictionary, player_level: int = 1, dungeon_level: int = 1
) -> Dictionary:
	var gt := str(theme.get("generation_type", "dungeon"))
	var theme_dir := str(theme.get("direction", "up"))
	var max_level: int = maxi(player_level, dungeon_level)
	match gt:
		"cavern":
			return _generate_cavern(rng, theme, theme_dir, max_level, dungeon_level)
		"outdoor":
			return _generate_outdoor(rng, theme, theme_dir, max_level, dungeon_level)
		"city":
			return _generate_city(rng, theme, max_level)
		_:
			return _generate_traditional(rng, theme, theme_dir, max_level, dungeon_level)


static func grid_checksum(grid: Dictionary) -> int:
	var h := 0
	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var s: String = str(grid.get(Vector2i(x, y), "wall"))
			h = int(h) ^ s.hash()
	return h


static func _minimal_traditional(rng: RandomNumberGenerator, theme_direction: String) -> Dictionary:
	var grid := DungeonGrid.initialize()
	var rooms := DungeonRooms.generate(rng)
	DungeonRooms.place_on_grid(grid, rooms)
	var conn := DungeonCorridors.connect_rooms(grid, rooms)
	grid = conn["grid"]
	var corridors: Array = conn["corridors"]
	DungeonFeaturesDungeon.add_pillars(grid, rooms, rng)
	DungeonRooms.add_labels(grid, rooms)
	DungeonCorridors.add_labels(grid, corridors, rooms)
	DungeonFeaturesDungeon.add_doors(grid, corridors, rooms, rng)
	DungeonFeaturesDungeon.add_staircases(grid, rooms, theme_direction, rng)
	_ensure_minimum_exits_dungeon(grid, rooms, theme_direction, rng)
	## Theme JSON missing (`find_theme_by_name` empty): same stair-direction fog default as welcome fallback.
	var legacy_fog := "dark" if theme_direction == "down" else "dim"
	return _result_dict(
		grid,
		rooms,
		corridors,
		theme_direction,
		legacy_fog,
		"light_cobblestone.png",
		"dark_cobblestone.png",
		"dungeon"
	)


static func _generate_traditional(
	rng: RandomNumberGenerator,
	theme: Dictionary,
	theme_dir: String,
	max_level: int,
	dungeon_level: int
) -> Dictionary:
	var grid := DungeonGrid.initialize()
	var rooms := DungeonRooms.generate(rng)
	DungeonRooms.place_on_grid(grid, rooms)
	var conn := DungeonCorridors.connect_rooms(grid, rooms)
	grid = conn["grid"]
	var corridors: Array = conn["corridors"]
	DungeonFeaturesDungeon.add_pillars(grid, rooms, rng)
	DungeonRooms.add_labels(grid, rooms)
	DungeonCorridors.add_labels(grid, corridors, rooms)
	DungeonFeaturesDungeon.add_doors(grid, corridors, rooms, rng)
	MapLinkSystem.add_map_links(grid, rooms, theme, rng)
	DungeonFeaturesDungeon.add_staircases(grid, rooms, theme_dir, rng)
	_ensure_minimum_exits_dungeon(grid, rooms, theme_dir, rng)
	GeneratorFeatures.add_room_traps(grid, rooms, rng)
	GeneratorFeatures.add_encounters_traditional(grid, rooms, corridors, theme, rng, max_level)
	GeneratorFeatures.add_treasures_traditional(grid, rooms, corridors, rng)
	GeneratorFeatures.add_food_traditional(grid, rooms, rng)
	GeneratorFeatures.add_healing_potions_traditional(grid, rooms, corridors, rng)
	if str(theme.get("fog_type", "")) != "daylight":
		GeneratorFeatures.add_torches_traditional_with_level(grid, rooms, dungeon_level, rng)
	GeneratorFeatures.add_special_features_traditional(grid, rooms, theme, rng)
	var fog := str(theme.get("fog_type", "dim"))
	return _result_dict(
		grid,
		rooms,
		corridors,
		theme_dir,
		fog,
		str(theme.get("floor_theme", "")),
		str(theme.get("wall_theme", "")),
		"dungeon",
		str(theme.get("name", "")),
		theme
	)


static func _generate_cavern(
	rng: RandomNumberGenerator,
	theme: Dictionary,
	theme_dir: String,
	max_level: int,
	dungeon_level: int
) -> Dictionary:
	var org := OrganicAreas.generate(rng)
	var grid: Dictionary = org["grid"]
	var caverns: Array = org["areas"]
	OrganicAreas.add_area_labels(grid, caverns)
	GeneratorFeatures.add_staircases_to_caverns(grid, caverns, theme_dir, rng)
	_ensure_minimum_exits_caverns(grid, caverns, theme_dir, rng)
	MapLinkSystem.add_map_links(grid, caverns, theme, rng)
	GeneratorFeatures.add_encounters_to_caverns(grid, caverns, theme, rng, max_level)
	GeneratorFeatures.add_treasures_to_caverns(grid, caverns, rng)
	GeneratorFeatures.add_food_to_caverns(grid, caverns, rng)
	GeneratorFeatures.add_healing_potions_to_caverns(grid, caverns, rng)
	if str(theme.get("fog_type", "")) != "daylight":
		GeneratorFeatures.add_torches_to_caverns_with_level(grid, caverns, dungeon_level, rng)
	GeneratorFeatures.add_special_features_to_caverns(grid, caverns, theme, rng)
	var fog := str(theme.get("fog_type", "dark"))
	return _result_dict(
		grid,
		caverns,
		[],
		theme_dir,
		fog,
		str(theme.get("floor_theme", "")),
		str(theme.get("wall_theme", "")),
		"cavern",
		str(theme.get("name", "")),
		theme
	)


static func _generate_outdoor(
	rng: RandomNumberGenerator,
	theme: Dictionary,
	theme_dir: String,
	max_level: int,
	dungeon_level: int
) -> Dictionary:
	var org := OrganicAreas.generate(rng)
	var grid: Dictionary = org["grid"]
	var areas: Array = org["areas"]
	OrganicAreas.add_area_labels(grid, areas)
	GeneratorFeatures.add_waypoints_to_areas(grid, areas, rng)
	GeneratorFeatures.add_city_linking_waypoints(grid, areas, rng)
	_ensure_minimum_exits_outdoor(grid, areas, rng)
	MapLinkSystem.add_map_links(grid, areas, theme, rng)
	GeneratorFeatures.add_encounters_to_caverns(grid, areas, theme, rng, max_level)
	GeneratorFeatures.add_treasures_to_caverns(grid, areas, rng)
	GeneratorFeatures.add_food_to_caverns(grid, areas, rng)
	GeneratorFeatures.add_healing_potions_to_caverns(grid, areas, rng)
	if str(theme.get("fog_type", "")) != "daylight":
		GeneratorFeatures.add_torches_to_caverns_with_level(grid, areas, dungeon_level, rng)
	GeneratorFeatures.add_special_features_to_caverns(grid, areas, theme, rng)
	var fog := str(theme.get("fog_type", "dim"))
	return _result_dict(
		grid,
		areas,
		[],
		theme_dir,
		fog,
		str(theme.get("floor_theme", "")),
		str(theme.get("wall_theme", "")),
		"outdoor",
		str(theme.get("name", "")),
		theme
	)


static func _generate_city(
	rng: RandomNumberGenerator, theme: Dictionary, max_level: int
) -> Dictionary:
	var theme_dir := str(theme.get("direction", "lateral"))
	var res := CitiesGenerator.generate(theme, rng)
	var grid: Dictionary = res["grid"]
	var city_blocks: Array = res["city_blocks"]
	CitiesGenerator.add_labels(grid, city_blocks, rng)
	_add_city_starting_waypoint(grid, rng)
	_place_city_extra_waypoints(grid, city_blocks, rng)
	_ensure_minimum_exits_outdoor(grid, city_blocks, rng)
	MapLinkSystem.add_map_links(grid, city_blocks, theme, rng)
	GeneratorFeatures.add_encounters_to_city_areas(grid, city_blocks, theme, rng, max_level)
	GeneratorFeatures.add_treasures_to_caverns(grid, city_blocks, rng)
	GeneratorFeatures.add_food_to_caverns(grid, city_blocks, rng)
	GeneratorFeatures.add_healing_potions_to_caverns(grid, city_blocks, rng)
	if str(theme.get("fog_type", "")) != "daylight":
		GeneratorFeatures.add_torches_to_caverns(grid, city_blocks, rng)
	GeneratorFeatures.add_city_special_features(grid, city_blocks, theme, rng)
	var fog := str(theme.get("fog_type", "daylight"))
	return _result_dict(
		grid,
		city_blocks,
		[],
		theme_dir,
		fog,
		str(theme.get("floor_theme", "")),
		str(theme.get("wall_theme", "")),
		"city",
		str(theme.get("name", "")),
		theme,
		str(theme.get("road_theme", "")),
		str(theme.get("shrub_theme", ""))
	)


static func _add_city_starting_waypoint(grid: Dictionary, rng: RandomNumberGenerator) -> void:
	var p: Variant = _find_edge_road(grid, rng)
	if p == null:
		p = _find_any_road(grid, rng)
	if p == null:
		var c := Vector2i(DungeonGrid.MAP_WIDTH >> 1, DungeonGrid.MAP_HEIGHT >> 1)
		grid[c] = "road"
		p = c
	grid[p] = "starting_waypoint|S"


static func _find_edge_road(grid: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var margin := 8
	var pool: Array[Vector2i] = []
	for x in DungeonGrid.MAP_WIDTH:
		for y in DungeonGrid.MAP_HEIGHT:
			if str(grid.get(Vector2i(x, y), "")) != "road":
				continue
			if (
				x <= margin
				or x >= DungeonGrid.MAP_WIDTH - margin - 1
				or y <= margin
				or y >= DungeonGrid.MAP_HEIGHT - margin - 1
			):
				pool.append(Vector2i(x, y))
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _find_any_road(grid: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var pool: Array[Vector2i] = []
	for x in DungeonGrid.MAP_WIDTH:
		for y in DungeonGrid.MAP_HEIGHT:
			if str(grid.get(Vector2i(x, y), "")) == "road":
				pool.append(Vector2i(x, y))
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _place_city_extra_waypoints(
	grid: Dictionary, city_blocks: Array, rng: RandomNumberGenerator
) -> void:
	var roads: Array = []
	for b in city_blocks:
		if b is Dictionary and str((b as Dictionary).get("type", "")) == "road_intersection":
			roads.append(b)
	if roads.is_empty():
		return
	var want: int = rng.randi_range(1, 2)
	_place_city_waypoints_rec(grid, roads, 0, want, rng)


static func _place_city_waypoints_rec(
	grid: Dictionary, roads: Array, start_idx: int, remaining: int, rng: RandomNumberGenerator
) -> void:
	if remaining <= 0 or start_idx >= roads.size():
		return
	var block: Dictionary = roads[start_idx]
	var p: Variant = GeneratorFeatures.find_city_waypoint_position(grid, block, rng)
	if p == null:
		_place_city_waypoints_rec(grid, roads, start_idx + 1, remaining, rng)
	else:
		grid[p] = "waypoint|%d" % rng.randi_range(1, 4)
		_place_city_waypoints_rec(grid, roads, start_idx + 1, remaining - 1, rng)


static func _result_dict(
	grid: Dictionary,
	rooms: Array,
	corridors: Array,
	theme_dir: String,
	fog_type: String,
	floor_theme: String,
	wall_theme: String,
	generation_type: String,
	theme_name: String = "",
	theme_data: Dictionary = {},
	road_theme: String = "",
	shrub_theme: String = ""
) -> Dictionary:
	var door_n := 0
	for v in grid.values():
		if v is String and DungeonFeaturesDungeon.is_door_tile(v):
			door_n += 1
	var out := {
		"grid": grid,
		"rooms": rooms,
		"corridors": corridors,
		"theme_direction": theme_dir,
		"fog_type": fog_type,
		"floor_theme": floor_theme,
		"wall_theme": wall_theme,
		"generation_type": generation_type,
		"theme": theme_name,
		"theme_data": theme_data,
		"width": DungeonGrid.MAP_WIDTH,
		"height": DungeonGrid.MAP_HEIGHT,
		"exit_count": count_exits(grid),
		"room_count": rooms.size(),
		"corridor_count": corridors.size(),
		"floor_cells": _count_tile(grid, "floor"),
		"corridor_cells": _count_tile(grid, "corridor"),
		"door_cells": door_n,
	}
	var tt := str(theme_data.get("transition_theme", "")).strip_edges()
	if not tt.is_empty():
		out["transition_theme"] = tt
	if not road_theme.is_empty():
		out["road_theme"] = road_theme
	if not shrub_theme.is_empty():
		out["shrub_theme"] = shrub_theme
	return out


static func _count_tile(grid: Dictionary, needle: String) -> int:
	var n := 0
	for v in grid.values():
		if v == needle:
			n += 1
	return n


static func _ensure_minimum_exits_dungeon(
	grid: Dictionary,
	rooms: Array,
	theme_direction: String,
	rng: RandomNumberGenerator,
	minimum: int = 2
) -> void:
	var cur := count_exits(grid)
	if cur >= minimum:
		return
	var needed: int = minimum - cur
	if rooms.size() < 2:
		return
	var avail: Array = rooms.slice(1)
	DungeonFeaturesDungeon._shuffle_in_place(avail, rng)
	DungeonFeaturesDungeon._place_staircases(grid, avail, needed, theme_direction, rng)


static func _ensure_minimum_exits_caverns(
	grid: Dictionary,
	caverns: Array,
	theme_direction: String,
	rng: RandomNumberGenerator,
	minimum: int = 2
) -> void:
	while count_exits(grid) < minimum and caverns.size() > 1:
		var placed := false
		var avail: Array = caverns.slice(1)
		_shuffle_array(avail, rng)
		for cavern in avail:
			if cavern is not Dictionary:
				continue
			var p: Variant = GeneratorFeatures.find_cavern_position(grid, cavern, rng)
			if p == null:
				continue
			var st := "stair_up" if theme_direction == "up" else "stair_down"
			if theme_direction == "lateral":
				st = "stair_down"
			grid[p] = st
			placed = true
			if count_exits(grid) >= minimum:
				return
		if not placed:
			return


static func _ensure_minimum_exits_outdoor(
	grid: Dictionary, areas: Array, rng: RandomNumberGenerator, minimum: int = 2
) -> void:
	while count_exits(grid) < minimum and areas.size() > 1:
		var placed := false
		var avail: Array = areas.slice(1)
		_shuffle_array(avail, rng)
		for area in avail:
			if area is not Dictionary:
				continue
			var p: Variant = GeneratorFeatures.find_waypoint_position(grid, area, rng)
			if p == null:
				continue
			grid[p] = "waypoint|%d" % rng.randi_range(1, 4)
			placed = true
			if count_exits(grid) >= minimum:
				return
		if not placed:
			return


static func _shuffle_array(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
