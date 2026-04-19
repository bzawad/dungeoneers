extends RefCounted

## Thin slice of `DungeonWeb.DungeonLive.Movement.walkable_for_movement?/2` (locked doors + `unlocked_doors`).
## Godot grid uses string cell values from `traditional_generator.gd`.

const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const DungeonFeatures := preload("res://dungeon/generator/features_dungeon.gd")
const MapLinkSystem := preload("res://dungeon/generator/map_link_system.gd")
const MonsterTable := preload("res://dungeon/combat/monster_table.gd")


static func tile_at(grid: Dictionary, cell: Vector2i) -> String:
	return str(grid.get(cell, "wall"))


## After a successful/failed disarm attempt (Explorer `remove_detected_trap`), door tiles lose their trap half.
static func tile_effective(grid: Dictionary, cell: Vector2i, trap_defused: Dictionary) -> String:
	var s: String = tile_at(grid, cell)
	if trap_defused.get(cell, false):
		if s == "locked_trapped_door":
			return "locked_door"
		if s == "trapped_door":
			return "door"
	return s


static func is_locked_door_tile(s: String) -> bool:
	return s == "locked_door" or s == "locked_trapped_door"


static func is_trapped_door_tile(s: String) -> bool:
	return s == "trapped_door" or s == "locked_trapped_door"


static func is_interactable_door_cell_tile(s: String) -> bool:
	return DungeonFeatures.is_door_tile(s)


static func is_walkable_tile(s: String) -> bool:
	if s == "wall" or s == "shrub":
		return false
	if DungeonFeatures.is_door_tile(s):
		return s == "door" or s == "trapped_door" or s == "secret_door"
	if s == "floor" or s == "corridor" or s == "road":
		return true
	if s == "stair_up" or s == "stair_down":
		return true
	if (
		s.begins_with("starting_stair|")
		or s.begins_with("starting_waypoint|")
		or s.begins_with("waypoint|")
	):
		return true
	if (
		s.begins_with("cavern_entrance|")
		or s.begins_with("dungeon_entrance|")
		or s.begins_with("cavern_exit|")
		or s.begins_with("dungeon_exit|")
	):
		return true
	if s.begins_with("quest_item|"):
		return true
	if (
		s.begins_with("room_label|")
		or s.begins_with("corridor_label|")
		or s.begins_with("area_label|")
		or s.begins_with("building_label|")
	):
		return true
	if (
		s == "treasure"
		or s == "trapped_treasure"
		or s == "torch"
		or s == "healing_potion"
		or s == "bread"
		or s == "cheese"
		or s == "grapes"
		or s == "room_trap"
	):
		return true
	if s == "pile_of_bones":
		return true
	if s.begins_with("special_feature|"):
		return not s.ends_with("|Pillar")
	return false


## Explorer `Movement.npc_walkable?/1` + `guard_walkable?/2` for `encounter|…` tiles.
static func encounter_movement_walkable(tile: String, guards_hostile: bool) -> bool:
	if not tile.begins_with("encounter|"):
		return false
	var parts := tile.split("|")
	var mname := parts[2].strip_edges() if parts.size() > 2 else ""
	var def: Dictionary = MonsterTable.lookup_monster(mname)
	var role := str(def.get("role", "")).strip_edges().to_lower()
	if role == "npc":
		return true
	if role == "guard":
		return not guards_hostile
	return false


static func is_walkable_for_movement_at(
	tile: String, cell: Vector2i, unlocked_doors: Dictionary, guards_hostile: bool = false
) -> bool:
	if is_locked_door_tile(tile):
		return unlocked_doors.has(cell)
	if tile.begins_with("encounter|"):
		return encounter_movement_walkable(tile, guards_hostile)
	return is_walkable_tile(tile)


## Explorer `dungeon_live.ex` `walkable_tile?/1` for **pathfinding** — locked doors count as traversable for BFS;
## server still stops at first unpicked locked door (see `DungeonReplication._server_handle_path_move`).
static func is_walkable_for_pathfinding_at(
	tile: String, cell: Vector2i, unlocked_doors: Dictionary, guards_hostile: bool = false
) -> bool:
	if is_locked_door_tile(tile):
		return true
	return is_walkable_for_movement_at(tile, cell, unlocked_doors, guards_hostile)


## Explorer `Movement.open_door_destination?` / trapped door — single-step move should open door flow first.
static func should_offer_door_prompt_before_move(
	effective_tile: String, cell: Vector2i, unlocked_doors: Dictionary
) -> bool:
	if effective_tile == "door" or is_trapped_door_tile(effective_tile):
		return true
	if is_locked_door_tile(effective_tile) and unlocked_doors.has(cell):
		return true
	return false


static func find_starting_cell(grid: Dictionary) -> Vector2i:
	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var c := Vector2i(x, y)
			var t: String = tile_at(grid, c)
			if t.begins_with("starting_stair|") or t.begins_with("starting_waypoint|"):
				return c
	# Fallback: first walkable floor-ish tile from top-left scan
	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var c2 := Vector2i(x, y)
			if is_walkable_tile(tile_at(grid, c2)):
				return c2
	return Vector2i.ZERO


static func find_spawn_cell(grid: Dictionary, occupied: Array) -> Vector2i:
	var base := find_starting_cell(grid)
	if not _occupied_has(occupied, base):
		return base
	for radius in range(1, 24):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dy) != radius:
					continue
				var p := base + Vector2i(dx, dy)
				if (
					p.x < 0
					or p.y < 0
					or p.x >= DungeonGrid.MAP_WIDTH
					or p.y >= DungeonGrid.MAP_HEIGHT
				):
					continue
				if not is_walkable_tile(tile_at(grid, p)):  # spawn never on locked (not walkable without unlock)
					continue
				if _occupied_has(occupied, p):
					continue
				return p
	return base


static func _occupied_has(occupied: Array, p: Vector2i) -> bool:
	for q in occupied:
		if q is Vector2i and (q as Vector2i) == p:
			return true
	return false


static func is_orthogonal_adjacent(a: Vector2i, b: Vector2i) -> bool:
	var d := a - b
	return (absi(d.x) + absi(d.y)) == 1


## Matches `DungeonWeb.DungeonLive.Movement.adjacent_to_player?/2` (Chebyshev 1, including diagonals).
static func is_king_adjacent(a: Vector2i, b: Vector2i) -> bool:
	if a == b:
		return false
	var d := a - b
	return absi(d.x) <= 1 and absi(d.y) <= 1


## Phase 5: Explorer `click_stair` / `click_waypoint` / `click_map_link` — player must **stand on** the tile.
static func world_interaction_stand_kind(raw_tile: String) -> String:
	if raw_tile == "stair_up" or raw_tile == "stair_down":
		return "stair"
	if raw_tile.begins_with("waypoint|") or raw_tile.begins_with("starting_waypoint|"):
		return "waypoint"
	if MapLinkSystem.map_link_tile(raw_tile):
		return "map_link"
	## Phase 5.7: stand on tile to read pickup dialog (Explorer movement food / potion / torch / quest_item).
	if raw_tile == "bread" or raw_tile == "cheese" or raw_tile == "grapes":
		return "food_pickup"
	if raw_tile == "healing_potion":
		return "healing_potion_pickup"
	if raw_tile == "torch":
		return "torch_pickup"
	if raw_tile.begins_with("quest_item|"):
		return "quest_item_pickup"
	return ""


## Phase 5: Explorer `click_encounter` / treasure investigation — any **revealed** cell (no adjacency rule).
static func world_interaction_remote_kind(effective_tile: String) -> String:
	if effective_tile == "room_trap":
		return "room_trap"
	if effective_tile.begins_with("encounter|"):
		return "encounter"
	if effective_tile == "treasure":
		return "treasure"
	if effective_tile == "trapped_treasure":
		return "trapped_treasure"
	if effective_tile.begins_with("room_label|"):
		return "room_label"
	if effective_tile.begins_with("corridor_label|"):
		return "corridor_label"
	if effective_tile.begins_with("area_label|"):
		return "area_label"
	if effective_tile.begins_with("building_label|"):
		return "building_label"
	if effective_tile.begins_with("special_feature|"):
		return "special_feature"
	return ""
