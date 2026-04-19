extends RefCounted

const Grid := preload("res://dungeon/generator/grid.gd")

## Port of `Dungeon.Generator.Rooms` (traditional rectangles).

const MIN_ROOM_SIZE := 4
const MAX_ROOM_SIZE := 12
const MAX_ROOMS := 12
const MAX_ATTEMPTS := 50


static func generate(rng: RandomNumberGenerator) -> Array:
	var rooms: Array = []
	var attempts := 0
	while attempts < MAX_ATTEMPTS and rooms.size() < MAX_ROOMS:
		var width := rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var height := rng.randi_range(MIN_ROOM_SIZE, MAX_ROOM_SIZE)
		var x := rng.randi_range(1, Grid.MAP_WIDTH - width - 1)
		var y := rng.randi_range(1, Grid.MAP_HEIGHT - height - 1)
		var new_room := {"x": x, "y": y, "width": width, "height": height}
		if _room_overlaps(new_room, rooms):
			attempts += 1
		else:
			rooms.push_front(new_room)
			attempts += 1
	return _add_room_numbers(rooms)


static func place_on_grid(grid: Dictionary, rooms: Array) -> void:
	for room in rooms:
		var rx: int = room["x"]
		var ry: int = room["y"]
		var rw: int = room["width"]
		var rh: int = room["height"]
		for x in range(rx, rx + rw):
			for y in range(ry, ry + rh):
				grid[Vector2i(x, y)] = "floor"


static func add_labels(grid: Dictionary, rooms: Array) -> void:
	for room in rooms:
		var center_x: int = room["x"] + room["width"] / 2
		var center_y: int = room["y"] + room["height"] / 2
		var num: String = room["number"]
		if Grid.get_tile(grid, center_x, center_y) == "floor":
			grid[Vector2i(center_x, center_y)] = "room_label|" + num
		else:
			_find_label_position(grid, room, center_x, center_y, num)


static func center(room: Dictionary) -> Vector2i:
	return Vector2i(room["x"] + room["width"] / 2, room["y"] + room["height"] / 2)


static func _add_room_numbers(rooms: Array) -> Array:
	var out: Array = []
	var idx := 1
	for room in rooms:
		var r: Dictionary = (room as Dictionary).duplicate()
		r["number"] = "R%d" % idx
		out.append(r)
		idx += 1
	return out


static func _room_overlaps(new_room: Dictionary, existing: Array) -> bool:
	for room in existing:
		var er: Dictionary = room as Dictionary
		if not (
			new_room["x"] + new_room["width"] + 1 < er["x"]
			or new_room["x"] > er["x"] + er["width"] + 1
			or new_room["y"] + new_room["height"] + 1 < er["y"]
			or new_room["y"] > er["y"] + er["height"] + 1
		):
			return true
	return false


static func _find_label_position(
	grid: Dictionary, room: Dictionary, cx: int, cy: int, num: String
) -> void:
	var candidates: Array[Vector2i] = [
		Vector2i(cx - 1, cy),
		Vector2i(cx + 1, cy),
		Vector2i(cx, cy - 1),
		Vector2i(cx, cy + 1),
		Vector2i(cx - 1, cy - 1),
		Vector2i(cx + 1, cy - 1),
		Vector2i(cx - 1, cy + 1),
		Vector2i(cx + 1, cy + 1),
	]
	var rx: int = room["x"]
	var ry: int = room["y"]
	var rw: int = room["width"]
	var rh: int = room["height"]
	for p in candidates:
		if p.x >= rx and p.x < rx + rw and p.y >= ry and p.y < ry + rh:
			if Grid.get_tile(grid, p.x, p.y) == "floor":
				grid[p] = "room_label|" + num
				return
