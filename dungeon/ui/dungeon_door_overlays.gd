extends Node2D

## Door chrome above the terrain layer: a half-cell black barrier on the room-facing edge of each
## door tile, plus small icons for locked doors, trap-inspected doors, and revealed secret doors.
## Icons use the same optional PNG bundle as the main tile UI (`dungeon_tile_assets.gd`).

const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const GridWalk := preload("res://dungeon/movement/grid_walkability.gd")
const DungeonFeatures := preload("res://dungeon/generator/features_dungeon.gd")
const DungeonTileAssets := preload("res://dungeon/ui/dungeon_tile_assets.gd")

enum Ori { NORTH, SOUTH, EAST, WEST }

var _lock_tex: Texture2D = null
var _trap_tex: Texture2D = null
var _secret_tex: Texture2D = null


func _ensure_textures() -> void:
	if _lock_tex == null:
		_lock_tex = DungeonTileAssets.load_lock_icon_texture()
	if _trap_tex == null:
		_trap_tex = DungeonTileAssets.load_trap_icon_texture()
	if _secret_tex == null:
		_secret_tex = DungeonTileAssets.load_secret_icon_texture()


static func _room_tile_for_door_adjacency(t: String) -> bool:
	if t == "floor":
		return true
	if t == "room_trap" or t == "trapped_treasure" or t == "treasure":
		return true
	if t == "stair_up" or t == "stair_down":
		return true
	if t.begins_with("starting_stair"):
		return true
	if t.begins_with("room_label"):
		return true
	if t.begins_with("corridor_label"):
		return true
	if t.begins_with("special_feature"):
		return true
	if t.begins_with("encounter"):
		return true
	if t.begins_with("waypoint") or t.begins_with("starting_waypoint"):
		return true
	return false


static func door_orientation(grid: Dictionary, cell: Vector2i, tile_str: String) -> int:
	if not DungeonFeatures.is_door_tile(tile_str) and tile_str != "secret_door":
		return Ori.NORTH
	var n := GridWalk.tile_at(grid, cell + Vector2i(0, -1))
	var s := GridWalk.tile_at(grid, cell + Vector2i(0, 1))
	var e := GridWalk.tile_at(grid, cell + Vector2i(1, 0))
	var w := GridWalk.tile_at(grid, cell + Vector2i(-1, 0))
	if _room_tile_for_door_adjacency(n):
		return Ori.NORTH
	if _room_tile_for_door_adjacency(s):
		return Ori.SOUTH
	if _room_tile_for_door_adjacency(e):
		return Ori.EAST
	if _room_tile_for_door_adjacency(w):
		return Ori.WEST
	return Ori.NORTH


static func _icon_px_for_cell(cell_px: int) -> int:
	return maxi(8, int(round(18.0 * float(cell_px) / 48.0)))


static func _inset_px_for_cell(cell_px: int) -> int:
	return maxi(2, int(round(4.0 * float(cell_px) / 48.0)))


func _add_barrier(root: Node2D, cell_px: int, ori: int) -> void:
	var half: int = cell_px >> 1
	var b := ColorRect.new()
	b.color = Color(0, 0, 0, 1)
	match ori:
		Ori.NORTH:
			b.position = Vector2.ZERO
			b.size = Vector2(cell_px, half)
		Ori.SOUTH:
			b.position = Vector2(0, half)
			b.size = Vector2(cell_px, cell_px - half)
		Ori.EAST:
			b.position = Vector2(half, 0)
			b.size = Vector2(cell_px - half, cell_px)
		_:
			b.position = Vector2.ZERO
			b.size = Vector2(half, cell_px)
	root.add_child(b)


func _sprite_icon(tex: Texture2D, center: Vector2, px: int) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.position = center
	if tex != null and tex.get_width() > 0:
		var sc: float = float(px) / float(tex.get_width())
		spr.scale = Vector2(sc, sc)
	return spr


func _should_draw_cell(tile_str: String, cell: Vector2i, revealed_secret_doors: Dictionary) -> bool:
	if tile_str == "secret_door":
		return revealed_secret_doors.has(cell)
	return DungeonFeatures.is_door_tile(tile_str)


func refresh(
	grid: Dictionary,
	cell_px: int,
	fog_enabled: bool,
	revealed: Dictionary,
	unlocked_doors: Dictionary,
	trap_inspected: Dictionary,
	trap_defused: Dictionary,
	revealed_secret_doors: Dictionary,
	fog_clicked_cells: Dictionary = {}
) -> void:
	_ensure_textures()
	for i in range(get_child_count() - 1, -1, -1):
		var ch: Node = get_child(i)
		remove_child(ch)
		ch.free()
	if cell_px < 4:
		return
	var icon_px := _icon_px_for_cell(cell_px)
	var inset := _inset_px_for_cell(cell_px)
	var half: int = cell_px >> 1

	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var cell := Vector2i(x, y)
			var revealed_here: bool = (not fog_enabled) or revealed.get(cell, false)
			var fog_click_trap: bool = (
				fog_enabled
				and (not revealed.get(cell, false))
				and fog_clicked_cells.get(cell, false)
			)
			if not revealed_here and not fog_click_trap:
				continue
			var raw_tile: String = GridWalk.tile_at(grid, cell)
			if (
				fog_click_trap
				and GridWalk.is_trapped_door_tile(raw_tile)
				and not trap_defused.get(cell, false)
			):
				var root_fog := Node2D.new()
				root_fog.position = Vector2(float(cell.x * cell_px), float(cell.y * cell_px))
				add_child(root_fog)
				if _trap_tex != null:
					root_fog.add_child(
						_sprite_icon(
							_trap_tex, Vector2(float(cell_px) * 0.5, float(cell_px) * 0.5), icon_px
						)
					)
				continue
			var t: String = GridWalk.tile_effective(grid, cell, trap_defused)
			if not _should_draw_cell(t, cell, revealed_secret_doors):
				continue

			var ori := door_orientation(grid, cell, t)
			var root := Node2D.new()
			root.position = Vector2(float(cell.x * cell_px), float(cell.y * cell_px))
			add_child(root)
			_add_barrier(root, cell_px, ori)

			var show_trap := trap_inspected.has(cell)
			var is_unlocked := unlocked_doors.has(cell)

			if t == "secret_door":
				if _secret_tex != null:
					var ctr := _barrier_center(cell_px, ori)
					root.add_child(_sprite_icon(_secret_tex, ctr, icon_px))
				continue

			if t == "door":
				continue

			if t == "locked_door":
				if not is_unlocked and _lock_tex != null:
					root.add_child(_sprite_icon(_lock_tex, _barrier_center(cell_px, ori), icon_px))
				continue

			if t == "trapped_door":
				if show_trap and _trap_tex != null:
					root.add_child(_sprite_icon(_trap_tex, _barrier_center(cell_px, ori), icon_px))
				continue

			if t == "locked_trapped_door":
				_paint_locked_trapped(
					root, cell_px, ori, is_unlocked, show_trap, icon_px, inset, half
				)
				continue


static func _barrier_center(cell_px: int, ori: int) -> Vector2:
	var half: int = cell_px >> 1
	match ori:
		Ori.NORTH:
			return Vector2(float(cell_px) * 0.5, float(half) * 0.5)
		Ori.SOUTH:
			return Vector2(float(cell_px) * 0.5, float(half) + float(cell_px - half) * 0.5)
		Ori.EAST:
			return Vector2(float(half) + float(cell_px - half) * 0.5, float(cell_px) * 0.5)
		_:
			return Vector2(float(half) * 0.5, float(cell_px) * 0.5)


func _paint_locked_trapped(
	root: Node2D,
	cell_px: int,
	ori: int,
	is_unlocked: bool,
	show_trap: bool,
	icon_px: int,
	inset: int,
	half: int
) -> void:
	if is_unlocked and show_trap and _trap_tex != null:
		root.add_child(_sprite_icon(_trap_tex, _barrier_center(cell_px, ori), icon_px))
		return
	if not is_unlocked and show_trap and _lock_tex != null and _trap_tex != null:
		_paint_dual_lock_trap(root, cell_px, ori, icon_px, inset, half)
		return
	if not is_unlocked and _lock_tex != null:
		root.add_child(_sprite_icon(_lock_tex, _barrier_center(cell_px, ori), icon_px))


func _paint_dual_lock_trap(
	root: Node2D, cell_px: int, ori: int, icon_px: int, inset: int, half: int
) -> void:
	match ori:
		Ori.NORTH:
			root.add_child(
				_sprite_icon(
					_lock_tex,
					Vector2(float(inset) + float(icon_px) * 0.5, float(half) * 0.5),
					icon_px
				)
			)
			root.add_child(
				_sprite_icon(
					_trap_tex,
					Vector2(float(cell_px - inset) - float(icon_px) * 0.5, float(half) * 0.5),
					icon_px
				)
			)
		Ori.SOUTH:
			var yc := float(half) + float(cell_px - half) * 0.5
			root.add_child(
				_sprite_icon(_lock_tex, Vector2(float(inset) + float(icon_px) * 0.5, yc), icon_px)
			)
			root.add_child(
				_sprite_icon(
					_trap_tex, Vector2(float(cell_px - inset) - float(icon_px) * 0.5, yc), icon_px
				)
			)
		Ori.EAST:
			var xc := float(half) + float(cell_px - half) * 0.5
			root.add_child(
				_sprite_icon(_lock_tex, Vector2(xc, float(inset) + float(icon_px) * 0.5), icon_px)
			)
			root.add_child(
				_sprite_icon(
					_trap_tex, Vector2(xc, float(cell_px - inset) - float(icon_px) * 0.5), icon_px
				)
			)
		_:
			var xcw := float(half) * 0.5
			root.add_child(
				_sprite_icon(_lock_tex, Vector2(xcw, float(inset) + float(icon_px) * 0.5), icon_px)
			)
			root.add_child(
				_sprite_icon(
					_trap_tex, Vector2(xcw, float(cell_px - inset) - float(icon_px) * 0.5), icon_px
				)
			)
