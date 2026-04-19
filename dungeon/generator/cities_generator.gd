extends RefCounted

## Port of `Dungeon.Generator.Cities`.

const DungeonGrid := preload("res://dungeon/generator/grid.gd")

const BLOCK_W := 12
const BLOCK_H := 10
const ROAD_W := 2


static func generate(theme_data: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var grid := _init_shrubs()
	var blocks := _calc_blocks()
	_carve_horizontal_roads(grid, blocks, theme_data, rng)
	_carve_vertical_roads(grid, blocks, theme_data, rng)
	var placed: Array = []
	var g2 := grid
	for b in blocks:
		if rng.randf() > 0.7:
			continue
		var res := _place_building_in_block(g2, b, theme_data, rng)
		g2 = res["grid"]
		if res.has("building"):
			placed.append(res["building"])
	grid = g2
	_add_shrub_road_variation(grid, rng)
	var city_blocks := _create_city_blocks(placed, blocks)
	return {"grid": grid, "city_blocks": city_blocks}


static func add_labels(grid: Dictionary, city_blocks: Array, _rng: RandomNumberGenerator) -> void:
	var idx := 1
	for block in city_blocks:
		if block is not Dictionary:
			continue
		var b: Dictionary = block
		var c := _center_block(b)
		var p: Variant = _find_city_label_pos(grid, b, c.x, c.y)
		if p == null:
			idx += 1
			continue
		if str(b.get("type", "")) == "building":
			grid[p] = "building_label|B%d" % idx
		else:
			grid[p] = "area_label|R%d" % idx
		idx += 1


static func _center_block(block: Dictionary) -> Vector2i:
	if str(block.get("type", "")) == "building":
		var fc: Array = block.get("floor_cells", []) as Array
		if fc.is_empty():
			return Vector2i(
				int(block["x"]) + (int(block["width"]) >> 1),
				int(block["y"]) + (int(block["height"]) >> 1)
			)
		var sx := 0
		var sy := 0
		for c in fc:
			if c is Vector2i:
				sx += (c as Vector2i).x
				sy += (c as Vector2i).y
		var n := fc.size()
		return Vector2i(int(float(sx) / float(n)), int(float(sy) / float(n)))
	return Vector2i(
		int(block["x"]) + (int(block["width"]) >> 1), int(block["y"]) + (int(block["height"]) >> 1)
	)


static func _find_city_label_pos(grid: Dictionary, block: Dictionary, cx: int, cy: int) -> Variant:
	var want := "floor" if str(block.get("type", "")) == "building" else "road"
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var p := Vector2i(cx + dx, cy + dy)
			if str(grid.get(p, "")) == want:
				return p
	return null


static func _init_shrubs() -> Dictionary:
	var grid: Dictionary = {}
	for x in DungeonGrid.MAP_WIDTH:
		for y in DungeonGrid.MAP_HEIGHT:
			grid[Vector2i(x, y)] = "shrub"
	return grid


static func _road_tile(_theme_data: Dictionary) -> String:
	return "road"


static func _calc_blocks() -> Array:
	var out: Array = []
	var mx := DungeonGrid.MAP_WIDTH
	var my := DungeonGrid.MAP_HEIGHT
	var span_x := BLOCK_W + ROAD_W
	var span_y := BLOCK_H + ROAD_W
	var bx := int(float(mx - ROAD_W) / float(span_x))
	var by := int(float(my - ROAD_W) / float(span_y))
	for ix in range(bx):
		for iy in range(by):
			var x := ix * (BLOCK_W + ROAD_W) + ROAD_W
			var y := iy * (BLOCK_H + ROAD_W) + ROAD_W
			out.append(
				{"x": x, "y": y, "width": BLOCK_W, "height": BLOCK_H, "block_x": ix, "block_y": iy}
			)
	return out


static func _carve_horizontal_roads(
	grid: Dictionary, blocks: Array, theme_data: Dictionary, _rng: RandomNumberGenerator
) -> void:
	var road := _road_tile(theme_data)
	var map_h := DungeonGrid.MAP_HEIGHT
	var map_w := DungeonGrid.MAP_WIDTH
	var ys: Dictionary = {}
	for b in blocks:
		if b is not Dictionary:
			continue
		var d: Dictionary = b
		ys[d["y"] - ROAD_W] = true
		ys[d["y"] + d["height"]] = true
	var ylist: Array = ys.keys()
	ylist.sort()
	if not ys.has(0):
		ylist.insert(0, 0)
	for y0 in ylist:
		var yy: int = int(y0)
		if yy < 0 or yy >= map_h:
			continue
		for road_y in range(yy, mini(yy + ROAD_W, map_h)):
			for x in map_w:
				grid[Vector2i(x, road_y)] = road


static func _carve_vertical_roads(
	grid: Dictionary, blocks: Array, theme_data: Dictionary, _rng: RandomNumberGenerator
) -> void:
	var road := _road_tile(theme_data)
	var map_h := DungeonGrid.MAP_HEIGHT
	var map_w := DungeonGrid.MAP_WIDTH
	var xs: Dictionary = {}
	for b in blocks:
		if b is not Dictionary:
			continue
		var d: Dictionary = b
		xs[d["x"] - ROAD_W] = true
		xs[d["x"] + d["width"]] = true
	var xlist: Array = xs.keys()
	xlist.sort()
	if not xs.has(0):
		xlist.insert(0, 0)
	for x0 in xlist:
		var xx: int = int(x0)
		if xx < 0 or xx >= map_w:
			continue
		for road_x in range(xx, mini(xx + ROAD_W, map_w)):
			for y in map_h:
				grid[Vector2i(road_x, y)] = road


static func _floor_tile(_theme_data: Dictionary) -> String:
	return "floor"


static func _wall_tile(_theme_data: Dictionary) -> String:
	return "wall"


static func _place_building_in_block(
	grid: Dictionary, block: Dictionary, theme_data: Dictionary, rng: RandomNumberGenerator
) -> Dictionary:
	var min_bw := 4
	var min_bh := 4
	var max_bw: int = int(block["width"]) - 2
	var max_bh: int = int(block["height"]) - 2
	var bw: int = rng.randi_range(min_bw, max_bw)
	var bh: int = rng.randi_range(min_bh, max_bh)
	var bx: int = int(block["x"]) + ((int(block["width"]) - bw) >> 1)
	var by: int = int(block["y"]) + ((int(block["height"]) - bh) >> 1)
	var floor_cells: Array = []
	for x in range(bx + 1, bx + bw - 1):
		for y in range(by + 1, by + bh - 1):
			var p := Vector2i(x, y)
			grid[p] = _floor_tile(theme_data)
			floor_cells.append(p)
	var wall_cells: Array[Vector2i] = []
	for x in range(bx, bx + bw):
		wall_cells.append_array([Vector2i(x, by), Vector2i(x, by + bh - 1)])
	for y in range(by, by + bh):
		wall_cells.append_array([Vector2i(bx, y), Vector2i(bx + bw - 1, y)])
	var uniq: Dictionary = {}
	for w in wall_cells:
		uniq[w] = true
	wall_cells = []
	for k in uniq.keys():
		wall_cells.append(k)
	var door_res := _place_door_and_connection(
		grid, wall_cells, bx, by, bw, bh, block, theme_data, rng
	)
	grid = door_res["grid"]
	var door_pos: Vector2i = door_res["door"]
	for w in wall_cells:
		if w == door_pos:
			continue
		grid[w] = _wall_tile(theme_data)
	var building := {
		"type": "building",
		"x": bx,
		"y": by,
		"width": bw,
		"height": bh,
		"floor_cells": floor_cells,
		"wall_cells": wall_cells,
		"door_position": door_pos,
		"cells": floor_cells
	}
	return {"grid": grid, "building": building}


static func _place_door_and_connection(
	grid: Dictionary,
	wall_cells: Array[Vector2i],
	bx: int,
	by: int,
	bw: int,
	bh: int,
	_block: Dictionary,
	theme_data: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var top: Array[Vector2i] = []
	var bottom: Array[Vector2i] = []
	var left: Array[Vector2i] = []
	var right: Array[Vector2i] = []
	for w in wall_cells:
		if w.y == by and w.x > bx and w.x < bx + bw - 1:
			top.append(w)
		if w.y == by + bh - 1 and w.x > bx and w.x < bx + bw - 1:
			bottom.append(w)
		if w.x == bx and w.y > by and w.y < by + bh - 1:
			left.append(w)
		if w.x == bx + bw - 1 and w.y > by and w.y < by + bh - 1:
			right.append(w)
	var sides: Array = []
	if not top.is_empty():
		sides.append({"n": 0, "arr": top})
	if not bottom.is_empty():
		sides.append({"n": 1, "arr": bottom})
	if not left.is_empty():
		sides.append({"n": 2, "arr": left})
	if not right.is_empty():
		sides.append({"n": 3, "arr": right})
	if sides.is_empty():
		return {"grid": grid, "door": Vector2i(bx + (bw >> 1), by)}
	var pick: Dictionary = sides[rng.randi_range(0, sides.size() - 1)]
	var side_arr: Array[Vector2i] = pick["arr"]
	var door: Vector2i = side_arr[rng.randi_range(0, side_arr.size() - 1)]
	var side_n: int = int(pick["n"])
	grid = _create_door_connection(grid, door, side_n, theme_data)
	var door_type := "locked_door" if rng.randi_range(1, 3) == 1 else "door"
	grid[door] = door_type
	return {"grid": grid, "door": door}


static func _create_door_connection(
	grid: Dictionary, door: Vector2i, side_n: int, theme_data: Dictionary
) -> Dictionary:
	var road := _road_tile(theme_data)
	match side_n:
		0:
			for y in range(door.y - 1, -1, -1):
				for x in range(door.x - 1, door.x + 2):
					if x < 0 or x >= DungeonGrid.MAP_WIDTH:
						continue
					var t: String = str(grid.get(Vector2i(x, y), ""))
					if t == road:
						return grid
					if t == "wall" or t == "floor":
						return grid
					grid[Vector2i(x, y)] = road
		1:
			for y in range(door.y + 1, DungeonGrid.MAP_HEIGHT):
				for x in range(door.x - 1, door.x + 2):
					if x < 0 or x >= DungeonGrid.MAP_WIDTH:
						continue
					var t2: String = str(grid.get(Vector2i(x, y), ""))
					if t2 == road:
						return grid
					if t2 == "wall" or t2 == "floor":
						return grid
					grid[Vector2i(x, y)] = road
		2:
			for x in range(door.x - 1, -1, -1):
				for y in range(door.y - 1, door.y + 2):
					if y < 0 or y >= DungeonGrid.MAP_HEIGHT:
						continue
					var t3: String = str(grid.get(Vector2i(x, y), ""))
					if t3 == road:
						return grid
					if t3 == "wall" or t3 == "floor":
						return grid
					grid[Vector2i(x, y)] = road
		_:
			for x in range(door.x + 1, DungeonGrid.MAP_WIDTH):
				for y in range(door.y - 1, door.y + 2):
					if y < 0 or y >= DungeonGrid.MAP_HEIGHT:
						continue
					var t4: String = str(grid.get(Vector2i(x, y), ""))
					if t4 == road:
						return grid
					if t4 == "wall" or t4 == "floor":
						return grid
					grid[Vector2i(x, y)] = road
	return grid


static func _add_shrub_road_variation(grid: Dictionary, rng: RandomNumberGenerator) -> void:
	var road := "road"
	var shrubs: Array[Vector2i] = []
	for x in DungeonGrid.MAP_WIDTH:
		for y in DungeonGrid.MAP_HEIGHT:
			var p := Vector2i(x, y)
			if str(grid.get(p, "")) == "shrub":
				shrubs.append(p)
	for p in shrubs:
		var adj_road := false
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var q: Vector2i = p + d
			if str(grid.get(q, "")) == road:
				adj_road = true
				break
		if adj_road and rng.randi_range(1, 5) == 1:
			grid[p] = road


static func _create_city_blocks(placed: Array, _blocks: Array) -> Array:
	var building_blocks: Array = []
	for b in placed:
		if b is Dictionary:
			var d: Dictionary = b
			var copy := d.duplicate()
			copy["cells"] = d.get("floor_cells", [])
			building_blocks.append(copy)
	var intersections := _road_intersections()
	var all: Array = building_blocks + intersections
	var idx := 1
	for block in all:
		if block is Dictionary:
			if idx == 1:
				(block as Dictionary)["number"] = "R1"
			else:
				var typ := str((block as Dictionary).get("type", ""))
				if typ == "building":
					(block as Dictionary)["number"] = "B%d" % idx
				else:
					(block as Dictionary)["number"] = "R%d" % idx
			idx += 1
	return all


static func _road_intersections() -> Array:
	var mw := DungeonGrid.MAP_WIDTH
	var mh := DungeonGrid.MAP_HEIGHT
	var pts: Array[Vector2i] = [
		Vector2i(mw >> 2, mh >> 2),
		Vector2i((mw * 3) >> 2, mh >> 2),
		Vector2i(mw >> 2, (mh * 3) >> 2),
		Vector2i((mw * 3) >> 2, (mh * 3) >> 2),
		Vector2i(mw >> 1, mh >> 1)
	]
	var out: Array = []
	for c in pts:
		var cells: Array = []
		for ix in range(c.x - 2, c.x + 3):
			for iy in range(c.y - 2, c.y + 3):
				cells.append(Vector2i(ix, iy))
		out.append(
			{
				"type": "road_intersection",
				"x": c.x - 2,
				"y": c.y - 2,
				"width": 5,
				"height": 5,
				"cells": cells
			}
		)
	return out
