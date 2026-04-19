extends RefCounted

const Grid := preload("res://dungeon/generator/grid.gd")

## Subset of `Dungeon.Generator.Features` needed for Phase 1 traditional maps
## (pillars, doors, staircases + helpers).

const DOOR_TILES: PackedStringArray = [
	"door",
	"locked_door",
	"trapped_door",
	"locked_trapped_door",
	"secret_door",
]


static func is_door_tile(t: String) -> bool:
	for d in DOOR_TILES:
		if d == t:
			return true
	return false


static func add_pillars(grid: Dictionary, rooms: Array, rng: RandomNumberGenerator) -> void:
	for room in rooms:
		if room["width"] >= 8 and room["height"] >= 8 and rng.randi_range(1, 2) == 1:
			_add_pillars_to_room(grid, room)


static func add_doors(
	grid: Dictionary, corridors: Array, rooms: Array, rng: RandomNumberGenerator
) -> void:
	for corridor in corridors:
		_place_doors_for_corridor(grid, corridor, rooms, rng)


static func add_staircases(
	grid: Dictionary, rooms: Array, theme_direction: String, rng: RandomNumberGenerator
) -> void:
	if rooms.is_empty():
		return
	var first: Dictionary = rooms[0]
	_add_starting_staircase(grid, first, rng)
	var other: Array = rooms.slice(1)
	var num_stairs := rng.randi_range(1, 4)
	var avail: Array = other.duplicate()
	_shuffle_in_place(avail, rng)
	_place_staircases(grid, avail, num_stairs, theme_direction, rng)


static func find_staircase_position(
	grid: Dictionary, room: Dictionary, rng: RandomNumberGenerator
) -> Variant:
	var potential: Array[Vector2i] = []
	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["width"]
	var rh: int = room["height"]
	for x in range(rx, rx + rw):
		for y in range(ry, ry + rh):
			var p := Vector2i(x, y)
			if grid.get(p, "") == "floor":
				potential.append(p)
	var cx: int = rx + (rw >> 1)
	var cy: int = ry + (rh >> 1)
	var preferred: Array[Vector2i] = []
	for p in potential:
		if absi(p.x - cx) > 1 or absi(p.y - cy) > 1:
			preferred.append(p)
	var pool: Array[Vector2i] = preferred if not preferred.is_empty() else potential
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _add_pillars_to_room(grid: Dictionary, room: Dictionary) -> void:
	var cx: int = room["x"] + (int(room["width"]) >> 1)
	var cy: int = room["y"] + (int(room["height"]) >> 1)
	var positions: Array[Vector2i] = [
		Vector2i(cx, cy),
		Vector2i(cx + 1, cy),
		Vector2i(cx, cy + 1),
		Vector2i(cx + 1, cy + 1),
	]
	var index := 1
	for p in positions:
		grid[p] = "special_feature|P%d|Pillar" % index
		index += 1


static func _place_doors_for_corridor(
	grid: Dictionary, corridor: Dictionary, rooms: Array, rng: RandomNumberGenerator
) -> void:
	var door_positions := _find_corridor_room_intersections(corridor["path"], rooms, grid)
	var k: int = mini(2, door_positions.size())
	var chosen := _take_random_positions(door_positions, k, rng)
	for p in chosen:
		grid[p] = _random_door_type(rng)


static func _random_door_type(rng: RandomNumberGenerator) -> String:
	if rng.randi_range(1, 10) == 1:
		return "secret_door"
	var locked := rng.randi_range(1, 5) == 1
	var trapped := rng.randi_range(1, 20) == 1
	if locked and trapped:
		return "locked_trapped_door"
	if locked:
		return "locked_door"
	if trapped:
		return "trapped_door"
	return "door"


static func _find_corridor_room_intersections(
	corridor_path: Array, rooms: Array, grid: Dictionary
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var neigh: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	for p in corridor_path:
		var pos: Vector2i = p as Vector2i
		if grid.get(pos, "") != "corridor":
			continue
		var ok := false
		for d: Vector2i in neigh:
			var adj: Vector2i = pos + d
			if Grid.get_tile(grid, adj.x, adj.y) == "floor" and Grid.point_in_any_room(adj, rooms):
				ok = true
				break
		if ok and _valid_door_position(grid, pos, rooms):
			out.append(pos)
	return out


static func _valid_door_position(grid: Dictionary, pos: Vector2i, rooms: Array) -> bool:
	var x := pos.x
	var y := pos.y
	var dirs: Array[Dictionary] = [
		{"adj": Vector2i(x - 1, y), "o": "west"},
		{"adj": Vector2i(x + 1, y), "o": "east"},
		{"adj": Vector2i(x, y - 1), "o": "north"},
		{"adj": Vector2i(x, y + 1), "o": "south"},
	]
	var orientation := ""
	for d in dirs:
		var adj: Vector2i = d["adj"] as Vector2i
		if Grid.get_tile(grid, adj.x, adj.y) == "floor" and Grid.point_in_any_room(adj, rooms):
			orientation = d["o"] as String
			break
	if orientation.is_empty():
		return false
	return _check_door_barrier(grid, pos, orientation)


static func _tile_is_barrier(t: String) -> bool:
	return t == "wall" or is_door_tile(t)


static func _check_door_barrier(grid: Dictionary, pos: Vector2i, orientation: String) -> bool:
	var x := pos.x
	var y := pos.y
	match orientation:
		"north", "south":
			return (
				_tile_is_barrier(Grid.get_tile(grid, x + 1, y))
				and _tile_is_barrier(Grid.get_tile(grid, x - 1, y))
			)
		"east", "west":
			return (
				_tile_is_barrier(Grid.get_tile(grid, x, y - 1))
				and _tile_is_barrier(Grid.get_tile(grid, x, y + 1))
			)
	return false


static func _add_starting_staircase(
	grid: Dictionary, room: Dictionary, rng: RandomNumberGenerator
) -> void:
	var p: Variant = find_staircase_position(grid, room, rng)
	if p != null:
		grid[p] = "starting_stair|S"


static func _place_staircases(
	grid: Dictionary, rooms: Array, count: int, theme_direction: String, rng: RandomNumberGenerator
) -> void:
	if count <= 0 or rooms.is_empty():
		return
	var room: Dictionary = rooms[0]
	var rest: Array = rooms.slice(1)
	var p: Variant = find_staircase_position(grid, room, rng)
	if p == null:
		_place_staircases(grid, rest, count, theme_direction, rng)
		return
	var stair := "stair_up" if theme_direction == "up" else "stair_down"
	grid[p] = stair
	_place_staircases(grid, rest, count - 1, theme_direction, rng)


static func _shuffle_in_place(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


static func _take_random_positions(
	src: Array[Vector2i], k: int, rng: RandomNumberGenerator
) -> Array[Vector2i]:
	if k <= 0 or src.is_empty():
		return []
	var pool: Array = src.duplicate()
	_shuffle_in_place(pool, rng)
	var out: Array[Vector2i] = []
	for i in mini(k, pool.size()):
		out.append(pool[i])
	return out
