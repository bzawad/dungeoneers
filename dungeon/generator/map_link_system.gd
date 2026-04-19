extends RefCounted

## Port of `Dungeon.MapLinkSystem` (entrance/exit placement rules).

const DungeonGrid := preload("res://dungeon/generator/grid.gd")

const START_POINTS: Array[Vector2i] = [
	Vector2i(10, 12), Vector2i(25, 25), Vector2i(15, 15), Vector2i(20, 20)
]


static func add_map_links(
	grid: Dictionary, areas: Array, theme: Dictionary, rng: RandomNumberGenerator
) -> void:
	var gen := str(theme.get("generation_type", "dungeon"))
	match gen:
		"outdoor":
			_place_links(grid, areas.duplicate(), "cavern_entrance", 2, rng)
			_place_links(grid, areas.duplicate(), "dungeon_entrance", 2, rng)
		"dungeon":
			_place_links(grid, areas.duplicate(), "dungeon_exit", 4, rng)
		"cavern":
			_place_links(grid, areas.duplicate(), "cavern_exit", 2, rng)
			_place_links(grid, areas.duplicate(), "dungeon_exit", 2, rng)
		_:
			pass


static func map_link_tile(s: String) -> bool:
	return (
		s.begins_with("cavern_entrance|")
		or s.begins_with("dungeon_entrance|")
		or s.begins_with("cavern_exit|")
		or s.begins_with("dungeon_exit|")
	)


static func get_map_link_positions(grid: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k in grid.keys():
		if k is Vector2i and map_link_tile(str(grid[k])):
			out.append(k)
	return out


static func _place_links(
	grid: Dictionary, areas: Array, link_prefix: String, count: int, rng: RandomNumberGenerator
) -> void:
	_place_links_rec(grid, areas, link_prefix, count, rng)


static func _place_links_rec(
	grid: Dictionary, areas: Array, link_prefix: String, count: int, rng: RandomNumberGenerator
) -> void:
	if count <= 0 or areas.is_empty():
		return
	var area = areas[0]
	areas.remove_at(0)
	var existing := get_map_link_positions(grid)
	var pos: Variant = _find_map_link_position(grid, area, existing, rng)
	if pos == null:
		_place_links_rec(grid, areas, link_prefix, count, rng)
		return
	grid[pos] = "%s|1" % link_prefix
	_place_links_rec(grid, areas, link_prefix, count - 1, rng)


static func _find_map_link_position(
	grid: Dictionary, area: Variant, existing: Array[Vector2i], rng: RandomNumberGenerator
) -> Variant:
	if area is Dictionary and (area as Dictionary).has("cells"):
		return _find_in_cells(grid, (area as Dictionary)["cells"] as Array, existing, rng)
	if area is Dictionary and (area as Dictionary).has_all(["x", "y", "width", "height"]):
		var d: Dictionary = area
		var positions: Array[Vector2i] = []
		for rx in range(d["x"], d["x"] + d["width"]):
			for ry in range(d["y"], d["y"] + d["height"]):
				positions.append(Vector2i(rx, ry))
		return _find_in_room_positions(grid, positions, existing, rng)
	return null


static func _find_in_cells(
	grid: Dictionary, cells: Array, existing: Array[Vector2i], rng: RandomNumberGenerator
) -> Variant:
	var edge := _filter_edge_cells(grid, cells, existing, 8, 12)
	if edge.is_empty():
		return _find_fallback_cell(grid, cells, existing, 5, 8, rng)
	return edge[rng.randi_range(0, edge.size() - 1)]


static func _find_in_room_positions(
	grid: Dictionary,
	room_positions: Array[Vector2i],
	existing: Array[Vector2i],
	rng: RandomNumberGenerator
) -> Variant:
	var good := _filter_room_cells(grid, room_positions, existing, 6, 10)
	if good.is_empty():
		return _find_fallback_room(grid, room_positions, existing, 3, rng)
	return good[rng.randi_range(0, good.size() - 1)]


static func _position_valid_for_map_link(grid: Dictionary, pos: Vector2i) -> bool:
	return grid.get(pos, "") == "floor" and _tile_is_floor(grid, pos)


static func _tile_is_floor(_grid: Dictionary, _pos: Vector2i) -> bool:
	return true


static func _edge_in_cells(cells: Array, pos: Vector2i) -> bool:
	var neigh: Array[Vector2i] = [
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x, pos.y - 1),
		Vector2i(pos.x, pos.y + 1)
	]
	for n in neigh:
		if not _cell_list_contains(cells, n):
			return true
	return false


static func _cell_list_contains(cells: Array, p: Vector2i) -> bool:
	for c in cells:
		if c is Vector2i and (c as Vector2i) == p:
			return true
	return false


static func _min_dist_links(pos: Vector2i, links: Array[Vector2i], min_d: int) -> bool:
	for e in links:
		var d: int = absi(pos.x - e.x) + absi(pos.y - e.y)
		if d < min_d:
			return false
	return true


static func _min_dist_starts(pos: Vector2i, min_d: int) -> bool:
	for s in START_POINTS:
		var d: int = absi(pos.x - s.x) + absi(pos.y - s.y)
		if d < min_d:
			return false
	return true


static func _filter_edge_cells(
	grid: Dictionary, cells: Array, existing: Array[Vector2i], min_link: int, min_start: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		if c is not Vector2i:
			continue
		var p := c as Vector2i
		if not _position_valid_for_map_link(grid, p):
			continue
		if not _edge_in_cells(cells, p):
			continue
		if not _min_dist_links(p, existing, min_link):
			continue
		if not _min_dist_starts(p, min_start):
			continue
		out.append(p)
	return out


static func _find_fallback_cell(
	grid: Dictionary,
	cells: Array,
	existing: Array[Vector2i],
	min_link: int,
	min_start: int,
	rng: RandomNumberGenerator
) -> Variant:
	var pool: Array[Vector2i] = []
	for c in cells:
		if c is not Vector2i:
			continue
		var p := c as Vector2i
		if not _position_valid_for_map_link(grid, p):
			continue
		if not _min_dist_links(p, existing, min_link):
			continue
		if not _min_dist_starts(p, min_start):
			continue
		pool.append(p)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _filter_room_cells(
	grid: Dictionary,
	room_positions: Array[Vector2i],
	existing: Array[Vector2i],
	min_link: int,
	min_start: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for p in room_positions:
		if not _position_valid_for_map_link(grid, p):
			continue
		if not _min_dist_links(p, existing, min_link):
			continue
		if not _min_dist_starts(p, min_start):
			continue
		out.append(p)
	return out


static func _find_fallback_room(
	grid: Dictionary,
	room_positions: Array[Vector2i],
	existing: Array[Vector2i],
	min_link: int,
	rng: RandomNumberGenerator
) -> Variant:
	var pool: Array[Vector2i] = []
	for p in room_positions:
		if not _position_valid_for_map_link(grid, p):
			continue
		if not _min_dist_links(p, existing, min_link):
			continue
		pool.append(p)
	if pool.is_empty():
		return null
	return pool[rng.randi_range(0, pool.size() - 1)]
