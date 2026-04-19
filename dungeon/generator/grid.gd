extends RefCounted

## Port of `Dungeon.Generator.Grid` (dimensions + helpers).

const MAP_WIDTH := 64
const MAP_HEIGHT := 48


static func initialize() -> Dictionary:
	var grid: Dictionary = {}
	for x in MAP_WIDTH:
		for y in MAP_HEIGHT:
			grid[Vector2i(x, y)] = "wall"
	return grid


static func get_tile(grid: Dictionary, x: int, y: int) -> String:
	return grid.get(Vector2i(x, y), "wall")


static func point_in_any_room(pos: Vector2i, rooms: Array) -> bool:
	for room in rooms:
		if room is Dictionary:
			if room.has("cells"):
				for c in room["cells"]:
					if c is Vector2i and (c as Vector2i) == pos:
						return true
			elif room.has_all(["x", "y", "width", "height"]):
				var rx: int = room["x"]
				var ry: int = room["y"]
				var rw: int = room["width"]
				var rh: int = room["height"]
				if pos.x >= rx and pos.x < rx + rw and pos.y >= ry and pos.y < ry + rh:
					return true
	return false


## Explorer `Renderer.point_in_city_building?/2` — only `type: building` cell lists count as “interior”.
static func point_in_city_building(pos: Vector2i, rooms: Array) -> bool:
	for room in rooms:
		if room is Dictionary and str(room.get("type", "")) == "building":
			for c in room.get("cells", []):
				if c is Vector2i and (c as Vector2i) == pos:
					return true
	return false


## Explorer `Renderer.should_use_floor_texture?/3` — floor vs road/corridor tileset for overlays.
static func should_use_floor_texture(pos: Vector2i, rooms: Array, generation_type: String) -> bool:
	var gt := generation_type.strip_edges()
	if gt == "city":
		return point_in_city_building(pos, rooms)
	return point_in_any_room(pos, rooms)


static func position_available_for_treasure(grid: Dictionary, pos: Vector2i) -> bool:
	var t: String = grid.get(pos, "wall")
	return t == "floor" or t == "corridor"


static func room_nearby(grid: Dictionary, pos: Vector2i) -> bool:
	return grid.get(pos, "wall") == "floor"
