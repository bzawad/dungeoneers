extends RefCounted

## Hybrid organic areas: `Dungeon.Generator.Caverns` / `Outdoor` (same algorithm, different labels only).

const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const DungeonRooms := preload("res://dungeon/generator/rooms.gd")
const DungeonCorridors := preload("res://dungeon/generator/corridors.gd")


static func generate(rng: RandomNumberGenerator) -> Dictionary:
	var foundation := _generate_traditional_foundation(rng)
	var conn := foundation["corridors"] as Array
	var rooms: Array = foundation["rooms"] as Array
	var grid: Dictionary = foundation["grid"] as Dictionary
	var areas := _transform_rooms_to_areas(rooms, rng)
	_enhance_grid_with_organic_shapes(grid, areas)
	_transform_corridors_to_wide_paths(grid, conn, rng)
	_apply_organic_growth(grid, areas, rng)
	return {"grid": grid, "areas": areas}


static func center(area: Dictionary) -> Vector2i:
	var cells: Array = area.get("cells", []) as Array
	if cells.is_empty():
		return Vector2i(DungeonGrid.MAP_WIDTH >> 1, DungeonGrid.MAP_HEIGHT >> 1)
	var sx := 0
	var sy := 0
	for c in cells:
		if c is Vector2i:
			sx += (c as Vector2i).x
			sy += (c as Vector2i).y
	var n := cells.size()
	return Vector2i(int(float(sx) / float(n)), int(float(sy) / float(n)))


static func add_area_labels(grid: Dictionary, areas: Array) -> void:
	for area in areas:
		if area is not Dictionary:
			continue
		var a := area as Dictionary
		var c := center(a)
		var p: Variant = _find_label_position(grid, a, c.x, c.y)
		if p != null:
			grid[p] = "area_label|" + str(a.get("number", ""))


static func _find_label_position(grid: Dictionary, area: Dictionary, cx: int, cy: int) -> Variant:
	var candidates: Array[Vector2i] = [
		Vector2i(cx, cy),
		Vector2i(cx - 1, cy),
		Vector2i(cx + 1, cy),
		Vector2i(cx, cy - 1),
		Vector2i(cx, cy + 1),
		Vector2i(cx - 1, cy - 1),
		Vector2i(cx + 1, cy - 1),
		Vector2i(cx - 1, cy + 1),
		Vector2i(cx + 1, cy + 1),
	]
	var cells: Array = area.get("cells", []) as Array
	for p in candidates:
		if _cell_list_contains(cells, p) and grid.get(p, "") == "floor":
			return p
	return null


static func _cell_list_contains(cells: Array, p: Vector2i) -> bool:
	for c in cells:
		if c is Vector2i and (c as Vector2i) == p:
			return true
	return false


static func _generate_traditional_foundation(rng: RandomNumberGenerator) -> Dictionary:
	var grid := DungeonGrid.initialize()
	var rooms := DungeonRooms.generate(rng)
	DungeonRooms.place_on_grid(grid, rooms)
	var conn := DungeonCorridors.connect_rooms(grid, rooms)
	var out_grid: Dictionary = conn["grid"]
	return {"grid": out_grid, "rooms": rooms, "corridors": conn["corridors"]}


static func _transform_rooms_to_areas(rooms: Array, rng: RandomNumberGenerator) -> Array:
	var areas: Array = []
	var idx := 1
	for room in rooms:
		if room is not Dictionary:
			continue
		var r := room as Dictionary
		var cells := _generate_organic_chamber(r, rng)
		areas.append({"cells": cells, "number": "A%d" % idx})
		idx += 1
	return areas


static func _generate_organic_chamber(room: Dictionary, rng: RandomNumberGenerator) -> Array:
	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["width"]
	var rh: int = room["height"]
	var acc: Dictionary = {}
	for x in range(rx, rx + rw):
		for y in range(ry, ry + rh):
			var p := Vector2i(x, y)
			acc[p] = true
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if rng.randf() < 0.4:
					var q: Vector2i = p + d
					acc[q] = true
	var out: Array = []
	for k in acc.keys():
		out.append(k)
	return out


static func _enhance_grid_with_organic_shapes(grid: Dictionary, areas: Array) -> void:
	for area in areas:
		if area is not Dictionary:
			continue
		for c in (area as Dictionary).get("cells", []):
			if c is Vector2i:
				grid[c] = "floor"


static func _transform_corridors_to_wide_paths(
	grid: Dictionary, corridors: Array, rng: RandomNumberGenerator
) -> void:
	for corridor in corridors:
		if corridor is not Dictionary:
			continue
		var path: Array = corridor.get("path", []) as Array
		for pt in path:
			if pt is not Vector2i:
				continue
			var p := pt as Vector2i
			grid[p] = "floor"
			var adjacent: Array[Vector2i] = [
				Vector2i(p.x - 1, p.y),
				Vector2i(p.x + 1, p.y),
				Vector2i(p.x, p.y - 1),
				Vector2i(p.x, p.y + 1)
			]
			for adj in adjacent:
				if (
					adj.x > 0
					and adj.x < DungeonGrid.MAP_WIDTH - 1
					and adj.y > 0
					and adj.y < DungeonGrid.MAP_HEIGHT - 1
					and rng.randf() < 0.5
				):
					grid[adj] = "floor"


static func _apply_organic_growth(
	grid: Dictionary, areas: Array, rng: RandomNumberGenerator
) -> void:
	for area in areas:
		if area is not Dictionary:
			continue
		var cells: Array = (area as Dictionary).get("cells", []) as Array
		var seed_count: int = mini(3, maxi(1, cells.size() >> 3))
		var seeds: Array = []
		var pool := cells.duplicate()
		for _i in seed_count:
			if pool.is_empty():
				break
			var j := rng.randi_range(0, pool.size() - 1)
			seeds.append(pool[j])
			pool.remove_at(j)
		for _iter in 2:
			_grow_blobs_iteration(grid, seeds, rng)


static func _grow_blobs_iteration(
	grid: Dictionary, seeds: Array, rng: RandomNumberGenerator
) -> void:
	var dirs: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(-1, 0),
		Vector2i(-1, 1),
		Vector2i(0, -1),
		Vector2i(0, 1),
		Vector2i(1, -1),
		Vector2i(1, 0),
		Vector2i(1, 1),
	]
	for grow_seed in seeds:
		if grow_seed is not Vector2i:
			continue
		var sx: int = (grow_seed as Vector2i).x
		var sy: int = (grow_seed as Vector2i).y
		var picks := 4
		for _p in picks:
			var d: Vector2i = dirs[rng.randi_range(0, dirs.size() - 1)]
			var nx := sx + d.x
			var ny := sy + d.y
			if (
				nx > 0
				and nx < DungeonGrid.MAP_WIDTH - 1
				and ny > 0
				and ny < DungeonGrid.MAP_HEIGHT - 1
				and rng.randf() < 0.6
			):
				grid[Vector2i(nx, ny)] = "floor"
