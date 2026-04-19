extends RefCounted

## Explorer-aligned subset of `DungeonWeb.DungeonLive.FogOfWar` (Chebyshev / "square" radius).

const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const DungeonFeatures := preload("res://dungeon/generator/features_dungeon.gd")
const MapLinkSystem := preload("res://dungeon/generator/map_link_system.gd")
const GeneratorFeatures := preload("res://dungeon/generator/generator_features.gd")


static func square_revealed(cell: Vector2i, revealed: Dictionary, fog_enabled: bool) -> bool:
	if not fog_enabled:
		return true
	return revealed.has(cell)


## Explorer `FogOfWar.show_door_trap?/4` — trap badge on doors / trapped treasure when fog is off or cell was clicked.
static func show_trap_icon_on_cell(
	fog_enabled: bool, fog_clicked_cells: Dictionary, cell: Vector2i
) -> bool:
	if not fog_enabled:
		return true
	return fog_clicked_cells.has(cell)


## Explorer `FogOfWar.can_reveal_square?/5` — click-to-reveal minesweeper (axis box radius from player).
static func can_reveal_fog_click_cell(
	click_cell: Vector2i,
	revealed: Dictionary,
	fog_enabled: bool,
	player_cell: Vector2i,
	fog_radius: int
) -> bool:
	if not fog_enabled:
		return false
	if revealed.has(click_cell):
		return true
	var r: int = maxi(0, fog_radius)
	return absi(click_cell.x - player_cell.x) <= r and absi(click_cell.y - player_cell.y) <= r


static func normalize_fog_type(fog_type: String) -> String:
	var t := fog_type.strip_edges().to_lower()
	match t:
		"daylight", "dim", "dark":
			return t
		_:
			return "dark"


static func fog_radius_for_type(fog_type: String) -> int:
	match normalize_fog_type(fog_type):
		"daylight":
			return 5
		"dim":
			return 2
		"dark", _:
			return 1


static func reveal_chebyshev_disk_into(revealed: Dictionary, center: Vector2i, radius: int) -> void:
	for c in disk_cells(center, radius):
		revealed[c] = true


static func disk_cells(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if maxi(absi(dx), absi(dy)) > radius:
				continue
			var p := center + Vector2i(dx, dy)
			if p.x < 0 or p.y < 0 or p.x >= DungeonGrid.MAP_WIDTH or p.y >= DungeonGrid.MAP_HEIGHT:
				continue
			out.append(p)
	return out


static func count_new_disk_reveals(revealed: Dictionary, center: Vector2i, radius: int) -> int:
	var n := 0
	for c in disk_cells(center, radius):
		if not revealed.has(c):
			n += 1
	return n


static func append_disk_delta(
	revealed: Dictionary, center: Vector2i, radius: int, out_delta: PackedVector2Array
) -> void:
	for c in disk_cells(center, radius):
		if revealed.has(c):
			continue
		revealed[c] = true
		out_delta.append(Vector2(c))


## Pack revealed keys for a full fog RPC (Phase 4.7 resync).
static func pack_revealed_keys(revealed: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in revealed:
		if k is Vector2i:
			out.append(Vector2(k as Vector2i))
	return out


## Phase 4.7: compact fog delta (uint16 count + uint16 x,y pairs, little-endian). Map fits 64×48.
static func pack_fog_delta_cells(cells: PackedVector2Array) -> PackedByteArray:
	var n: int = cells.size()
	var b := PackedByteArray()
	b.resize(2 + n * 4)
	b.encode_u16(0, n)
	var o := 2
	for i in range(n):
		var v: Vector2 = cells[i]
		b.encode_u16(o, clampi(int(v.x), 0, 65535))
		o += 2
		b.encode_u16(o, clampi(int(v.y), 0, 65535))
		o += 2
	return b


static func unpack_fog_delta_cells(data: PackedByteArray) -> PackedVector2Array:
	var out := PackedVector2Array()
	if data.size() < 2:
		return out
	var n: int = int(data.decode_u16(0))
	if n < 0 or 2 + n * 4 > data.size():
		push_warning(
			"[Dungeoneers] unpack_fog_delta_cells: invalid payload size=", data.size(), " n=", n
		)
		return out
	var o := 2
	for _i in range(n):
		var x := int(data.decode_u16(o))
		o += 2
		var y := int(data.decode_u16(o))
		o += 2
		out.append(Vector2(x, y))
	return out


static func _room_interior_cells(room: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if room.get("cells", null) != null:
		for c in room["cells"]:
			if c is Vector2i:
				out.append(c as Vector2i)
		return out
	var rx: int = int(room.get("x", 0))
	var ry: int = int(room.get("y", 0))
	var rw: int = int(room.get("width", 0))
	var rh: int = int(room.get("height", 0))
	for x in range(rx, rx + rw):
		for y in range(ry, ry + rh):
			out.append(Vector2i(x, y))
	return out


static func _add_room_and_surroundings_into(revealed: Dictionary, room: Dictionary) -> void:
	var interior: Array[Vector2i] = _room_interior_cells(room)
	var interior_set: Dictionary = {}
	for c in interior:
		interior_set[c] = true
		revealed[c] = true
	if room.get("cells", null) != null:
		for c in interior:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var p: Vector2i = c + Vector2i(dx, dy)
					if (
						p.x < 0
						or p.y < 0
						or p.x >= DungeonGrid.MAP_WIDTH
						or p.y >= DungeonGrid.MAP_HEIGHT
					):
						continue
					if interior_set.has(p):
						continue
					revealed[p] = true
		return
	var rx: int = int(room.get("x", 0))
	var ry: int = int(room.get("y", 0))
	var rw: int = int(room.get("width", 0))
	var rh: int = int(room.get("height", 0))
	## Explorer `get_room_surrounding_squares` rect: `y <- (room_y - 1)..(room_y + height + 1)` inclusive
	## (one row deeper below interior than a naive `rh+2` strip). GD `range` end is exclusive → `ry + rh + 2`.
	for x in range(rx - 1, rx + rw + 1):
		for y in range(ry - 1, ry + rh + 2):
			if x < 0 or y < 0 or x >= DungeonGrid.MAP_WIDTH or y >= DungeonGrid.MAP_HEIGHT:
				continue
			var p := Vector2i(x, y)
			if interior_set.has(p):
				continue
			revealed[p] = true


static func _tile_emits_static_light(tile: String) -> bool:
	if tile == "torch":
		return true
	if MapLinkSystem.map_link_tile(tile):
		return true
	if tile.begins_with("quest_item|"):
		return true
	return GeneratorFeatures.special_feature_tile_emits_light(tile)


## Explorer `FogOfWar.initialize_revealed_with_light/2` (R1 + surroundings, player disk, light sources).
static func seed_initial_revealed_with_light(
	revealed: Dictionary, grid: Dictionary, player_cell: Vector2i, rooms: Array, fog_type: String
) -> void:
	for r in rooms:
		if r is Dictionary and str((r as Dictionary).get("number", "")) == "R1":
			_add_room_and_surroundings_into(revealed, r as Dictionary)
			break
	var fr: int = fog_radius_for_type(fog_type)
	reveal_chebyshev_disk_into(revealed, player_cell, fr)
	for k in grid:
		if not k is Vector2i:
			continue
		var s: String = str(grid[k])
		if _tile_emits_static_light(s):
			reveal_chebyshev_disk_into(revealed, k as Vector2i, fr)


static func _find_room_number_at_cell(player_cell: Vector2i, rooms: Array) -> String:
	for room in rooms:
		if room is not Dictionary:
			continue
		var rd: Dictionary = room as Dictionary
		for c in rd.get("cells", []):
			if c is Vector2i and (c as Vector2i) == player_cell:
				return str(rd.get("number", ""))
		if rd.has_all(["x", "y", "width", "height"]):
			var rx: int = int(rd["x"])
			var ry: int = int(rd["y"])
			var rw: int = int(rd["width"])
			var rh: int = int(rd["height"])
			if (
				player_cell.x >= rx
				and player_cell.x < rx + rw
				and player_cell.y >= ry
				and player_cell.y < ry + rh
			):
				return str(rd.get("number", ""))
	return ""


static func _find_room_label_cell(grid: Dictionary, room_number: String) -> Vector2i:
	if room_number.is_empty():
		return Vector2i(-1, -1)
	var want := "room_label|" + room_number
	for k in grid:
		if not k is Vector2i:
			continue
		if str(grid[k]) == want:
			return k as Vector2i
	return Vector2i(-1, -1)


static func _corridor_context_tile(t: String) -> bool:
	return t == "corridor" or DungeonFeatures.is_door_tile(t)


static func _player_on_corridor_path(player_cell: Vector2i, corridors: Array) -> bool:
	for cor in corridors:
		if cor is not Dictionary:
			continue
		for p in (cor as Dictionary).get("path", []):
			if p is Vector2i and (p as Vector2i) == player_cell:
				return true
	return false


static func _find_nearby_corridor_label_cell(grid: Dictionary, player_cell: Vector2i) -> Vector2i:
	var search_r := 3
	for rad in range(0, search_r + 1):
		for dy in range(-search_r, search_r + 1):
			for dx in range(-search_r, search_r + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var check := player_cell + Vector2i(dx, dy)
				if (
					check.x < 0
					or check.y < 0
					or check.x >= DungeonGrid.MAP_WIDTH
					or check.y >= DungeonGrid.MAP_HEIGHT
				):
					continue
				var s: String = str(grid.get(check, ""))
				if s.begins_with("corridor_label|"):
					return check
	return Vector2i(-1, -1)


## Explorer `FogOfWar.reveal_area_labels/3` — cells to add to `revealed` when the player moves.
static func collect_area_label_reveal_cells(
	grid: Dictionary, player_cell: Vector2i, rooms: Array, corridors: Array
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rnum := _find_room_number_at_cell(player_cell, rooms)
	if not rnum.is_empty():
		var rlc := _find_room_label_cell(grid, rnum)
		if rlc.x >= 0:
			out.append(rlc)
	var here: String = str(grid.get(player_cell, ""))
	if _corridor_context_tile(here) or _player_on_corridor_path(player_cell, corridors):
		var clc := _find_nearby_corridor_label_cell(grid, player_cell)
		if clc.x >= 0:
			out.append(clc)
	return out


static func append_area_label_cells_into_delta(
	revealed: Dictionary,
	grid: Dictionary,
	player_cell: Vector2i,
	rooms: Array,
	corridors: Array,
	out_delta: PackedVector2Array
) -> void:
	for c in collect_area_label_reveal_cells(grid, player_cell, rooms, corridors):
		if revealed.has(c):
			continue
		revealed[c] = true
		out_delta.append(Vector2(c))
