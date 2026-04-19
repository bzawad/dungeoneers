extends RefCounted

const Grid := preload("res://dungeon/generator/grid.gd")
const Rooms := preload("res://dungeon/generator/rooms.gd")

## Port of `Dungeon.Generator.Corridors`.


static func connect_rooms(grid: Dictionary, rooms: Array) -> Dictionary:
	if rooms.is_empty():
		return {"grid": grid, "corridors": []}
	if rooms.size() == 1:
		return {"grid": grid, "corridors": []}

	var corridors: Array = []
	var acc_grid := grid
	var tail_plus_head: Array = rooms.slice(1)
	tail_plus_head.append(rooms[0])

	for i in rooms.size():
		var room1: Dictionary = rooms[i]
		var room2: Dictionary = tail_plus_head[i]
		var corridor_number := "C%d" % (corridors.size() + 1)
		var c1 := Rooms.center(room1)
		var c2 := Rooms.center(room2)
		var built := _create_corridor_with_tracking(acc_grid, c1, c2)
		acc_grid = built["grid"]
		corridors.append({"number": corridor_number, "path": built["path"]})

	return {"grid": acc_grid, "corridors": corridors}


static func add_labels(grid: Dictionary, corridors: Array, rooms: Array) -> void:
	for corridor in corridors:
		var path: Array = corridor["path"]
		var pure: Array[Vector2i] = []
		for p in path:
			var pos: Vector2i = p
			if grid.get(pos, "") == "corridor" and not Grid.point_in_any_room(pos, rooms):
				pure.append(pos)
		if pure.size() > 2:
			var mid: int = pure.size() >> 1
			var lp: Vector2i = pure[mid]
			grid[lp] = "corridor_label|" + str(corridor["number"])


static func _create_corridor_with_tracking(
	grid: Dictionary, p1: Vector2i, p2: Vector2i
) -> Dictionary:
	var safe := _find_safe_corridor_route(grid, p1, p2)
	var safe_x2: int = safe.x
	var safe_y1: int = safe.y
	var h := _create_horizontal_tunnel_with_tracking(grid, p1.x, safe_x2, safe_y1)
	var v := _create_vertical_tunnel_with_tracking(h["grid"], safe_y1, p2.y, safe_x2)
	var full_path: Array = []
	full_path.append_array(h["path"])
	full_path.append_array(v["path"])
	return {"grid": v["grid"], "path": full_path}


static func _find_safe_corridor_route(grid: Dictionary, p1: Vector2i, p2: Vector2i) -> Vector2i:
	if _path_too_close_to_rooms(grid, p1, p2):
		var offset_y := p1.y + 2 if p1.y < p2.y else p1.y - 2
		var offset_x := p2.x - 2 if p1.x < p2.x else p2.x + 2
		return Vector2i(offset_x, offset_y)
	return Vector2i(p2.x, p1.y)


static func _path_too_close_to_rooms(grid: Dictionary, p1: Vector2i, p2: Vector2i) -> bool:
	var min_x: int = mini(p1.x, p2.x)
	var max_x: int = maxi(p1.x, p2.x)
	for x in range(min_x, max_x + 1):
		if (
			Grid.room_nearby(grid, Vector2i(x, p1.y - 1))
			or Grid.room_nearby(grid, Vector2i(x, p1.y + 1))
		):
			return true
	var min_y: int = mini(p1.y, p2.y)
	var max_y: int = maxi(p1.y, p2.y)
	for y in range(min_y, max_y + 1):
		if (
			Grid.room_nearby(grid, Vector2i(p2.x - 1, y))
			or Grid.room_nearby(grid, Vector2i(p2.x + 1, y))
		):
			return true
	return false


static func _create_horizontal_tunnel_with_tracking(
	grid: Dictionary, x1: int, x2: int, y: int
) -> Dictionary:
	var min_x: int = mini(x1, x2)
	var max_x: int = maxi(x1, x2)
	var path: Array = []
	var g := grid.duplicate()
	for x in range(min_x, max_x + 1):
		path.append(Vector2i(x, y))
		var pos := Vector2i(x, y)
		if g.get(pos, "") != "floor":
			g[pos] = "corridor"
	return {"grid": g, "path": path}


static func _create_vertical_tunnel_with_tracking(
	grid: Dictionary, y1: int, y2: int, x: int
) -> Dictionary:
	var min_y: int = mini(y1, y2)
	var max_y: int = maxi(y1, y2)
	var path: Array = []
	var g := grid.duplicate()
	for y in range(min_y, max_y + 1):
		path.append(Vector2i(x, y))
		var pos := Vector2i(x, y)
		if g.get(pos, "") != "floor":
			g[pos] = "corridor"
	return {"grid": g, "path": path}
