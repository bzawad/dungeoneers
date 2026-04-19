extends Node2D

## Phase 2–4: grid + click→move RPC; peer markers; fog.
## Phase 2 polish: Explorer `cursor-pointer` / tile affordance — hover rim on revealed cells, pointer vs forbidden on fog.
## When `res://assets/explorer/images/` PNGs exist, use 64px atlas terrain + door/stair/pillar decor (`dungeon_tile_assets.gd`).
## Camera: **Explorer `DungeonWeb.DungeonLive`** sliding window (`update_viewport_for_player` / `get_viewport_size/1`),
## not a scaled overview of the full map. Desktop uses a 16×16 cell window; narrow windows (<1024px) use 6×6 (mobile).

const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")
const DungeonTileAssets := preload("res://dungeon/ui/dungeon_tile_assets.gd")
const DungeonDoorOverlays := preload("res://dungeon/ui/dungeon_door_overlays.gd")
const GridWalk := preload("res://dungeon/movement/grid_walkability.gd")
const PartyMarkerArt := preload("res://dungeon/ui/party_marker_art.gd")
const EncounterMapToken := preload("res://dungeon/ui/encounter_map_token.gd")

signal cell_clicked(cell: Vector2i)

## Matches `dungeon_live.ex`: `handle_event("screen_size", %{"width" => width}, ...)` → `:mobile` when width < 1024.
const EXPLORER_VIEWPORT_BREAKPOINT_PX := 1024
## `get_viewport_size/1` in `dungeon_live.ex` — max cells shown (then `min` with dungeon size).
const EXPLORER_VIEWPORT_CELLS_DESKTOP := Vector2i(16, 16)
const EXPLORER_VIEWPORT_CELLS_MOBILE := Vector2i(6, 6)

const GAMA_STYLE_MAX_ZOOM := 2.0
## Allow strong zoom-out so a 16×64px-tall strip still fits very short windows (viewport mode).
const VIEWPORT_ZOOM_CLAMP_MIN := 0.08
const CAMERA_VIEW_MARGIN := 0.92

const CELL_PX_LEGACY := 12
const PALETTE_COUNT_LEGACY := 20
const FOG_ATLAS_X_LEGACY := 19

var _cell_px: int = CELL_PX_LEGACY
var _use_bundled_pngs: bool = false

var _terrain_under_fog_layer: TileMapLayer
var _tile_layer: TileMapLayer
var _decor_layer: TileMapLayer
## Explorer `dungeon.generation_type` + `rooms` for floor vs corridor tileset (`renderer.ex`).
var _generation_type: String = "dungeon"
var _rooms: Array = []
var _players_root: Node2D
var _local_peer_id: int = -1
var _peer_markers: Dictionary = {}
## MOV-01: last cell + facing per peer for map token direction (gama-style 0..3).
var _peer_marker_last_cell: Dictionary = {}
var _peer_marker_last_facing: Dictionary = {}
var _logical_grid: Dictionary = {}
var _fog_enabled: bool = false
var _revealed: Dictionary = {}
var _fog_type: String = "dim"
var _path_preview_root: Node2D
var _path_preview_cells: Dictionary = {}
var _door_overlay: Node2D = null
var _client_unlocked_doors: Dictionary = {}
var _client_trap_inspected_doors: Dictionary = {}
var _client_trap_defused_doors: Dictionary = {}
var _revealed_secret_doors: Dictionary = {}
## Explorer `clicked_squares` — fog manual reveal; drives trap glyph on fogged doors.
var _fog_clicked_cells: Dictionary = {}
var _guards_hostile: bool = false
var _camera_for_fit: Camera2D = null
var _camera_world_center: Vector2 = Vector2.ZERO
## Cell the Explorer-style viewport is centered on (re-clamped on window resize).
var _camera_focus_cell: Vector2i = Vector2i.ZERO
var _follow_local_camera: bool = false

var _hover_polish_enabled: bool = true
var _hover_root: Node2D
var _hover_panel: Panel
var _last_hover_cell: Vector2i = Vector2i(-9999, -9999)
var _last_cursor: int = -1

var _labels_root: Node2D
var _cell_labels: Dictionary = {}  # Vector2i → Label
var _encounter_tokens_root: Node2D = null
var _encounter_token_by_cell: Dictionary = {}  # Vector2i → TextureRect


func set_guards_hostile(hostile: bool) -> void:
	_guards_hostile = hostile


func apply_secret_doors_snapshot(cells: PackedVector2Array) -> void:
	_revealed_secret_doors.clear()
	for i in range(cells.size()):
		_revealed_secret_doors[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


func apply_secret_doors_delta(cells: PackedVector2Array) -> void:
	for i in range(cells.size()):
		_revealed_secret_doors[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


func apply_fog_clicked_cells_snapshot(cells: PackedVector2Array) -> void:
	_fog_clicked_cells.clear()
	for i in range(cells.size()):
		_fog_clicked_cells[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


func apply_fog_clicked_cells_delta(cells: PackedVector2Array) -> void:
	for i in range(cells.size()):
		_fog_clicked_cells[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


## Disable hover highlight + cursor overrides while a modal (e.g. door `Window`) owns input (`dungeon_session.gd`).
func set_hover_polish_enabled(enabled: bool) -> void:
	_hover_polish_enabled = enabled
	if not enabled:
		_apply_cursor_shape(DisplayServer.CURSOR_ARROW)
		_clear_hover_visual()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_apply_cursor_shape(DisplayServer.CURSOR_ARROW)


func setup_from_grid(
	grid: Dictionary,
	floor_theme_file: String = "",
	wall_theme_file: String = "",
	generation_type: String = "dungeon",
	rooms: Array = [],
	road_theme_file: String = "",
	shrub_theme_file: String = ""
) -> void:
	_camera_focus_cell = Vector2i(DungeonGrid.MAP_WIDTH >> 1, DungeonGrid.MAP_HEIGHT >> 1)
	_logical_grid = grid
	_generation_type = generation_type.strip_edges()
	if _generation_type.is_empty():
		_generation_type = "dungeon"
	_rooms = rooms.duplicate() if rooms is Array else []
	_use_bundled_pngs = DungeonTileAssets.bundled_pngs_present()
	_cell_px = DungeonTileAssets.CELL_MAP_PX if _use_bundled_pngs else CELL_PX_LEGACY

	if _use_bundled_pngs:
		var u := TileMapLayer.new()
		u.name = "TerrainUnderFog"
		u.z_index = -1
		add_child(u)
		_terrain_under_fog_layer = u

	var terrain := TileMapLayer.new()
	terrain.name = "Tiles"
	add_child(terrain)
	_tile_layer = terrain

	_path_preview_root = Node2D.new()
	_path_preview_root.name = "PathPreview"
	_path_preview_root.z_index = 4
	add_child(_path_preview_root)

	_hover_root = Node2D.new()
	_hover_root.name = "HoverHighlight"
	_hover_root.z_index = 3
	add_child(_hover_root)
	_hover_panel = Panel.new()
	_hover_panel.name = "HoverCell"
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.visible = false
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(1.0, 1.0, 1.0, 0.07)
	hb.set_border_width_all(maxi(1, int(round(float(_cell_px) * 0.06))))
	hb.border_color = Color(1.0, 0.95, 0.75, 0.55)
	_hover_panel.add_theme_stylebox_override("panel", hb)
	_hover_root.add_child(_hover_panel)
	set_process(true)

	_labels_root = Node2D.new()
	_labels_root.name = "Labels"
	_labels_root.z_index = 5
	add_child(_labels_root)

	if _use_bundled_pngs:
		var ts: TileSet = DungeonTileAssets.build_tile_set_from_bundled_pngs(
			floor_theme_file, wall_theme_file, road_theme_file, shrub_theme_file
		)
		if DungeonTileAssets.SRC_FLOOR < 0 or DungeonTileAssets.SRC_WALL < 0:
			push_warning(
				(
					"[Dungeoneers] Bundled PNGs found but TileSet build failed; using legacy palette. "
					+ "Ensure PNGs exist under res://assets/explorer/images/ (run tools/sync_explorer_assets.sh)."
				)
			)
			_use_bundled_pngs = false
			_cell_px = CELL_PX_LEGACY
			if _terrain_under_fog_layer != null:
				_terrain_under_fog_layer.queue_free()
				_terrain_under_fog_layer = null
			_build_tileset_legacy(terrain)
		else:
			if _terrain_under_fog_layer != null:
				_terrain_under_fog_layer.tile_set = ts
			_decor_layer = TileMapLayer.new()
			_decor_layer.name = "Decor"
			_decor_layer.z_index = 1
			add_child(_decor_layer)
			_tile_layer.tile_set = ts
			_decor_layer.tile_set = ts
			_apply_generation_layer_modulate()
			_door_overlay = DungeonDoorOverlays.new()
			_door_overlay.name = "DoorOverlays"
			_door_overlay.z_index = 2
			add_child(_door_overlay)
	else:
		_build_tileset_legacy(terrain)

	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var cell := Vector2i(x, y)
			var s: String = str(grid.get(cell, "wall"))
			_paint_cell(cell, s)

	_build_cell_labels(grid)

	_camera_world_center = _explorer_clamped_view_center_world(_camera_focus_cell)
	var cam := Camera2D.new()
	cam.name = "DungeonCamera"
	cam.position = _camera_world_center
	cam.enabled = true
	add_child(cam)
	cam.make_current()
	_camera_for_fit = cam
	call_deferred("_fit_camera", cam)
	call_deferred("_deferred_refit_camera")
	_refresh_door_overlays()
	_ensure_encounter_tokens_root()
	_sync_encounter_monster_tokens()


func _ensure_encounter_tokens_root() -> void:
	if _encounter_tokens_root != null:
		return
	_encounter_tokens_root = Node2D.new()
	_encounter_tokens_root.name = "EncounterTokens"
	_encounter_tokens_root.z_index = 6
	add_child(_encounter_tokens_root)


func _remove_encounter_token(cell: Vector2i) -> void:
	var enc_rect: TextureRect = _encounter_token_by_cell.get(cell) as TextureRect
	if enc_rect != null and is_instance_valid(enc_rect):
		enc_rect.queue_free()
	_encounter_token_by_cell.erase(cell)


func _sync_encounter_monster_tokens() -> void:
	if _tile_layer == null:
		return
	_ensure_encounter_tokens_root()
	var want: Dictionary = {}
	for y in range(DungeonGrid.MAP_HEIGHT):
		for x in range(DungeonGrid.MAP_WIDTH):
			var cell := Vector2i(x, y)
			var s: String = str(_logical_grid.get(cell, "wall"))
			var is_revealed: bool = not _fog_enabled or bool(_revealed.get(cell, false))
			if not is_revealed or not s.begins_with("encounter|"):
				continue
			var tex: Texture2D = EncounterMapToken.texture_for_encounter_tile(s)
			if tex == null:
				continue
			want[cell] = tex
	for c in _encounter_token_by_cell.keys():
		if not want.has(c):
			_remove_encounter_token(c)
	for cell2 in want.keys():
		var t2: Texture2D = want[cell2] as Texture2D
		var existing: TextureRect = _encounter_token_by_cell.get(cell2) as TextureRect
		if existing != null and is_instance_valid(existing):
			existing.texture = t2
			continue
		var enc_rect := TextureRect.new()
		enc_rect.texture = t2
		enc_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		enc_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		enc_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inset := float(_cell_px) * 0.12
		enc_rect.position = Vector2(
			float(cell2.x * _cell_px) + inset, float(cell2.y * _cell_px) + inset
		)
		enc_rect.size = Vector2(float(_cell_px) - 2.0 * inset, float(_cell_px) - 2.0 * inset)
		enc_rect.modulate = Color(1.0, 1.0, 1.0, 0.92)
		_encounter_tokens_root.add_child(enc_rect)
		_encounter_token_by_cell[cell2] = enc_rect


func _apply_generation_layer_modulate() -> void:
	## Explorer `floor_tile_opacity_class/1` — subtle whole-layer tint (tileset remains primary detail).
	var m := Color(1.0, 1.0, 1.0, 1.0)
	match _generation_type:
		"dungeon":
			m = Color(0.94, 0.94, 0.96, 1.0)
		"cavern":
			m = Color(0.96, 0.96, 0.97, 1.0)
		"outdoor":
			m = Color(0.98, 0.98, 0.99, 1.0)
		"city":
			m = Color(1.0, 1.0, 1.0, 1.0)
		_:
			m = Color(0.93, 0.93, 0.95, 1.0)
	if _tile_layer != null:
		_tile_layer.modulate = m
	if _decor_layer != null:
		_decor_layer.modulate = m
	if _terrain_under_fog_layer != null:
		_terrain_under_fog_layer.modulate = Color(m.r * 0.58, m.g * 0.58, m.b * 0.58, 1.0)


func _process(_delta: float) -> void:
	_update_hover_polish()


func _cell_is_revealed_for_hover(cell: Vector2i) -> bool:
	if not _fog_enabled:
		return true
	return _revealed.get(cell, false)


## Revealed tile the player might care about (walkable / door / feature) — slightly tighter than full grid hover.
func _cell_is_interaction_target(cell: Vector2i) -> bool:
	if not _cell_is_revealed_for_hover(cell):
		return false
	var t: String = GridWalk.tile_effective(_logical_grid, cell, _client_trap_defused_doors)
	if GridWalk.is_interactable_door_cell_tile(t):
		return true
	if GridWalk.world_interaction_remote_kind(t) != "":
		return true
	return GridWalk.is_walkable_for_movement_at(t, cell, _client_unlocked_doors, _guards_hostile)


func _apply_cursor_shape(shape: int) -> void:
	if shape == _last_cursor:
		return
	_last_cursor = shape
	DisplayServer.cursor_set_shape(shape)


func _clear_hover_visual() -> void:
	_last_hover_cell = Vector2i(-9999, -9999)
	if _hover_panel != null and is_instance_valid(_hover_panel):
		_hover_panel.visible = false


func _paint_hover_cell(cell: Vector2i) -> void:
	if _hover_panel == null or not is_instance_valid(_hover_panel):
		return
	if cell == _last_hover_cell and _hover_panel.visible:
		return
	_last_hover_cell = cell
	_hover_panel.visible = true
	_hover_panel.position = Vector2(float(cell.x * _cell_px), float(cell.y * _cell_px))
	_hover_panel.size = Vector2(float(_cell_px), float(_cell_px))


func _update_hover_polish() -> void:
	if not _hover_polish_enabled or _tile_layer == null or not is_visible_in_tree():
		_apply_cursor_shape(DisplayServer.CURSOR_ARROW)
		_clear_hover_visual()
		return
	var local_on_layer := _tile_layer.get_local_mouse_position()
	var cell := _tile_layer.local_to_map(local_on_layer)
	if (
		cell.x < 0
		or cell.y < 0
		or cell.x >= DungeonGrid.MAP_WIDTH
		or cell.y >= DungeonGrid.MAP_HEIGHT
	):
		_apply_cursor_shape(DisplayServer.CURSOR_ARROW)
		_clear_hover_visual()
		return
	if not _cell_is_revealed_for_hover(cell):
		_apply_cursor_shape(DisplayServer.CURSOR_FORBIDDEN)
		_clear_hover_visual()
		return
	# Explorer `dungeon-tile` uses `cursor-pointer` on the whole interactive grid.
	_apply_cursor_shape(DisplayServer.CURSOR_POINTING_HAND)
	if _cell_is_interaction_target(cell):
		_paint_hover_cell(cell)
	else:
		_clear_hover_visual()


func apply_unlocked_doors_snapshot(cells: PackedVector2Array) -> void:
	_client_unlocked_doors.clear()
	for i in range(cells.size()):
		_client_unlocked_doors[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


func apply_unlocked_doors_delta(cells: PackedVector2Array) -> void:
	for i in range(cells.size()):
		_client_unlocked_doors[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


func apply_trap_inspected_doors_snapshot(cells: PackedVector2Array) -> void:
	_client_trap_inspected_doors.clear()
	for i in range(cells.size()):
		_client_trap_inspected_doors[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


func apply_trap_inspected_doors_delta(cells: PackedVector2Array) -> void:
	for i in range(cells.size()):
		_client_trap_inspected_doors[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


func apply_trap_defused_doors_snapshot(cells: PackedVector2Array) -> void:
	_client_trap_defused_doors.clear()
	for i in range(cells.size()):
		_client_trap_defused_doors[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


func apply_trap_defused_doors_delta(cells: PackedVector2Array) -> void:
	for i in range(cells.size()):
		_client_trap_defused_doors[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_door_overlays()


func _refresh_door_overlays() -> void:
	if _door_overlay == null or not is_instance_valid(_door_overlay):
		return
	if _door_overlay.has_method("refresh"):
		_door_overlay.call(
			"refresh",
			_logical_grid,
			_cell_px,
			_fog_enabled,
			_revealed,
			_client_unlocked_doors,
			_client_trap_inspected_doors,
			_client_trap_defused_doors,
			_revealed_secret_doors,
			_fog_clicked_cells
		)


func _deferred_refit_camera() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var cam := _camera_for_fit
	if is_instance_valid(cam):
		_fit_camera(cam)
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	var cam := _camera_for_fit
	if is_instance_valid(cam):
		_fit_camera(cam)


func init_network_markers(local_peer_id: int) -> void:
	_local_peer_id = local_peer_id
	_follow_local_camera = local_peer_id >= 0
	if _players_root != null:
		return
	_players_root = Node2D.new()
	_players_root.name = "Players"
	_players_root.z_index = 10
	add_child(_players_root)


## Centers the Explorer-style viewport on `cell`, clamped to map bounds (see `dungeon_live.ex` `update_viewport_for_player/2`).
func set_view_center_from_cell(cell: Vector2i) -> void:
	_camera_focus_cell = cell
	if _camera_for_fit != null and is_instance_valid(_camera_for_fit):
		_fit_camera(_camera_for_fit)


static func find_starting_cell_for_camera(grid: Dictionary) -> Vector2i:
	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var s: String = str(grid.get(Vector2i(x, y), ""))
			if s.begins_with("starting_stair"):
				return Vector2i(x, y)
	return Vector2i(DungeonGrid.MAP_WIDTH >> 1, DungeonGrid.MAP_HEIGHT >> 1)


func configure_fog(enabled: bool, revealed: Dictionary, fog_type: String = "dim") -> void:
	_fog_enabled = enabled
	_revealed = revealed.duplicate()
	if not enabled:
		_fog_clicked_cells.clear()
	_fog_type = DungeonFog.normalize_fog_type(fog_type)
	_refresh_all_cells()


func apply_fog_reveal_delta(cells: PackedVector2Array) -> void:
	for i in range(cells.size()):
		_revealed[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_all_cells()


func apply_fog_full_resync(cells: PackedVector2Array) -> void:
	_revealed.clear()
	_fog_clicked_cells.clear()
	for i in range(cells.size()):
		_revealed[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	_refresh_all_cells()


## Server replicated mutation (treasure taken, room trap cleared, …).
func apply_logical_tile_change(cell: Vector2i, s: String) -> void:
	_logical_grid[cell] = s
	if _tile_layer == null:
		return
	if _fog_enabled and not _revealed.get(cell, false):
		_sync_encounter_monster_tokens()
		return
	_paint_cell(cell, s)
	_refresh_door_overlays()
	# If a tile patch removes a labelled cell (e.g. room_trap → floor), hide the label.
	_refresh_label_visibility(cell, true)
	_sync_encounter_monster_tokens()


func _paint_cell(cell: Vector2i, s: String) -> void:
	if _use_bundled_pngs:
		var tid := DungeonTileAssets.terrain_source_id(s, _generation_type)
		if tid < 0:
			return
		var ac := DungeonTileAssets.terrain_source_atlas(cell, s, _generation_type, _rooms)
		_tile_layer.set_cell(cell, tid, ac)
		if _decor_layer != null:
			var deco: Dictionary = DungeonTileAssets.decor_source_atlas(cell, s)
			if deco.is_empty():
				_decor_layer.erase_cell(cell)
			else:
				var ds: int = int(deco["src"])
				if ds >= 0:
					_decor_layer.set_cell(cell, ds, deco["atlas"] as Vector2i)
	else:
		_tile_layer.set_cell(cell, 0, _atlas_coords_for_cell_legacy(cell, s))


func _paint_cell_to_layer(layer: TileMapLayer, cell: Vector2i, s: String) -> void:
	if layer == null:
		return
	if _use_bundled_pngs:
		var tid2 := DungeonTileAssets.terrain_source_id(s, _generation_type)
		if tid2 < 0:
			return
		var ac2 := DungeonTileAssets.terrain_source_atlas(cell, s, _generation_type, _rooms)
		layer.set_cell(cell, tid2, ac2)
	else:
		layer.set_cell(cell, 0, _atlas_coords_for_cell_legacy(cell, s))


func _refresh_all_cells() -> void:
	if _tile_layer == null:
		return
	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var cell := Vector2i(x, y)
			var s: String = str(_logical_grid.get(cell, "wall"))
			var is_revealed: bool = not _fog_enabled or bool(_revealed.get(cell, false))
			if not is_revealed:
				if _terrain_under_fog_layer != null and _use_bundled_pngs:
					_paint_cell_to_layer(_terrain_under_fog_layer, cell, s)
				if _use_bundled_pngs:
					var fc: Dictionary = DungeonTileAssets.fog_cell_for_type(_fog_type)
					var fs: int = int(fc["src"])
					if fs >= 0:
						_tile_layer.set_cell(cell, fs, fc["atlas"] as Vector2i)
					if _decor_layer != null:
						_decor_layer.erase_cell(cell)
				else:
					_tile_layer.set_cell(cell, 0, Vector2i(FOG_ATLAS_X_LEGACY, 0))
			else:
				if _terrain_under_fog_layer != null:
					_terrain_under_fog_layer.erase_cell(cell)
				_paint_cell(cell, s)
			_refresh_label_visibility(cell, is_revealed)
	_refresh_door_overlays()
	_sync_encounter_monster_tokens()


func set_path_preview(path: PackedVector2Array) -> void:
	clear_path_preview()
	if _path_preview_root == null or path.size() < 2:
		return
	var inset := _cell_px * 0.18
	for i in range(1, path.size()):
		var cell := Vector2i(int(path[i].x), int(path[i].y))
		if _path_preview_cells.has(cell):
			continue
		var r := ColorRect.new()
		r.color = Color(0.95, 0.82, 0.2, 0.38)
		r.position = Vector2(cell.x * _cell_px + inset, cell.y * _cell_px + inset)
		r.size = Vector2(_cell_px - 2.0 * inset, _cell_px - 2.0 * inset)
		_path_preview_root.add_child(r)
		_path_preview_cells[cell] = r


func clear_path_preview() -> void:
	if _path_preview_root == null:
		return
	for c in _path_preview_root.get_children():
		c.queue_free()
	_path_preview_cells.clear()


func sync_peer_marker(
	peer_id: int, cell: Vector2i, role: String = "rogue", display_label: String = ""
) -> void:
	if _players_root == null:
		return
	var prev: Variant = _peer_marker_last_cell.get(peer_id, null)
	var facing: int = PartyMarkerArt.FACING_DOWN
	if prev is Vector2i:
		var pv: Vector2i = prev as Vector2i
		if pv == cell:
			facing = int(_peer_marker_last_facing.get(peer_id, PartyMarkerArt.FACING_DOWN))
		else:
			facing = PartyMarkerArt.facing_from_grid_step(cell - pv)
	_peer_marker_last_cell[peer_id] = cell
	_peer_marker_last_facing[peer_id] = facing

	var tex: Texture2D = PartyMarkerArt.texture_for_role_facing(role, facing)
	if tex == null:
		tex = PartyMarkerArt.texture_for_role(role)
	var want_tex := tex != null
	var existing: Control = _peer_markers.get(peer_id) as Control
	var need_rebuild := existing == null
	if existing != null:
		var was_tex := existing is TextureRect
		if want_tex != was_tex:
			need_rebuild = true
		elif str(existing.get_meta("marker_role", "")) != role:
			need_rebuild = true
		elif str(existing.get_meta("marker_label", "")) != display_label:
			need_rebuild = true
		elif want_tex and existing is TextureRect:
			var tr_exist := existing as TextureRect
			if tr_exist.texture != tex:
				tr_exist.texture = tex
			tr_exist.set_meta("marker_facing", facing)
	if need_rebuild and existing != null:
		existing.queue_free()
		_peer_markers.erase(peer_id)
		existing = null

	var r: Control
	if existing == null:
		if want_tex:
			var marker_rect := TextureRect.new()
			marker_rect.name = "PlayerMarker_%d" % peer_id
			marker_rect.set_meta("marker_role", role)
			marker_rect.set_meta("marker_label", display_label)
			marker_rect.set_meta("marker_facing", facing)
			marker_rect.texture = tex
			marker_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			marker_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			marker_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			marker_rect.z_index = 1 if peer_id == _local_peer_id else 0
			_players_root.add_child(marker_rect)
			_peer_markers[peer_id] = marker_rect
			r = marker_rect
		else:
			var p := Panel.new()
			p.name = "PlayerMarker_%d" % peer_id
			p.set_meta("marker_role", role)
			p.set_meta("marker_label", display_label)
			var sb := StyleBoxFlat.new()
			var bw := maxi(1, int(_cell_px * 0.06))
			sb.set_border_width_all(bw)
			p.add_theme_stylebox_override("panel", sb)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.z_index = 1 if peer_id == _local_peer_id else 0
			_players_root.add_child(p)
			_peer_markers[peer_id] = p
			r = p
	else:
		r = existing
		r.set_meta("marker_label", display_label)

	var inset := _cell_px * 0.1
	var side := _cell_px - 2.0 * inset
	var target_pos := Vector2(cell.x * _cell_px + inset, cell.y * _cell_px + inset)
	var target_size := Vector2(side, side)

	if r is TextureRect:
		var tr2 := r as TextureRect
		if peer_id == _local_peer_id:
			tr2.modulate = Color(0.88, 1.0, 0.92, 1.0)
		else:
			tr2.modulate = Color(1.0, 0.94, 0.82, 1.0)
	elif r is Panel:
		var rad := int(side * 0.5)
		var sb2 := r.get_theme_stylebox("panel") as StyleBoxFlat
		if sb2 != null:
			sb2.corner_radius_top_left = rad
			sb2.corner_radius_top_right = rad
			sb2.corner_radius_bottom_right = rad
			sb2.corner_radius_bottom_left = rad
			if peer_id == _local_peer_id:
				sb2.bg_color = Color(0.12, 0.72, 0.32, 0.42)
				sb2.border_color = Color(0.75, 1.0, 0.82, 0.95)
			else:
				sb2.bg_color = Color(0.92, 0.68, 0.08, 0.42)
				sb2.border_color = Color(1.0, 0.95, 0.7, 0.95)

	if r.position.distance_to(target_pos) > 0.5 and is_inside_tree():
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(r, "position", target_pos, 0.12)
		tw.parallel().tween_property(r, "size", target_size, 0.12)
		tw.finished.connect(
			func() -> void: _update_peer_marker_name_label(r, display_label, r.size)
		)
	else:
		r.position = target_pos
		r.size = target_size
	_update_peer_marker_name_label(r, display_label, target_size)

	if _follow_local_camera and peer_id == _local_peer_id and _camera_for_fit != null:
		_camera_focus_cell = cell
		_fit_camera(_camera_for_fit)


func _update_peer_marker_name_label(
	marker: Control, display_label: String, token_size: Vector2
) -> void:
	var trimmed := display_label.strip_edges()
	var lbl := marker.get_node_or_null("NameLabel") as Label
	if trimmed.is_empty():
		if lbl != null:
			lbl.queue_free()
		return
	if lbl == null:
		lbl = Label.new()
		lbl.name = "NameLabel"
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.clip_text = true
		lbl.add_theme_font_size_override("font_size", maxi(8, int(_cell_px * 0.22)))
		marker.add_child(lbl)
	lbl.text = trimmed
	var w := maxf(token_size.x + 8.0, _cell_px * 1.2)
	lbl.position = Vector2((token_size.x - w) * 0.5, token_size.y + 1.0)
	lbl.size = Vector2(w, maxf(14.0, _cell_px * 0.36))


func _unhandled_input(event: InputEvent) -> void:
	if _tile_layer == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var local_on_layer := _tile_layer.get_local_mouse_position()
			var cell := _tile_layer.local_to_map(local_on_layer)
			if (
				cell.x >= 0
				and cell.y >= 0
				and cell.x < DungeonGrid.MAP_WIDTH
				and cell.y < DungeonGrid.MAP_HEIGHT
			):
				cell_clicked.emit(cell)
				get_viewport().set_input_as_handled()


func _cell_center_world(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * _cell_px, (float(cell.y) + 0.5) * _cell_px)


func _explorer_max_cells_for_window(viewport_width_px: int) -> Vector2i:
	if viewport_width_px < EXPLORER_VIEWPORT_BREAKPOINT_PX:
		return EXPLORER_VIEWPORT_CELLS_MOBILE
	return EXPLORER_VIEWPORT_CELLS_DESKTOP


func _explorer_visible_cell_span(viewport_width_px: int) -> Vector2i:
	var cap := _explorer_max_cells_for_window(viewport_width_px)
	return Vector2i(mini(cap.x, DungeonGrid.MAP_WIDTH), mini(cap.y, DungeonGrid.MAP_HEIGHT))


func _explorer_clamped_view_center_world(focus_cell: Vector2i) -> Vector2:
	var vp := get_viewport()
	var vw_px := EXPLORER_VIEWPORT_BREAKPOINT_PX
	if vp != null:
		vw_px = int(vp.get_visible_rect().size.x)
	var span := _explorer_visible_cell_span(vw_px)
	var map_w := float(DungeonGrid.MAP_WIDTH * _cell_px)
	var map_h := float(DungeonGrid.MAP_HEIGHT * _cell_px)
	var p := _cell_center_world(focus_cell)
	var half_w := float(span.x * _cell_px) * 0.5
	var half_h := float(span.y * _cell_px) * 0.5
	var cx: float
	var cy: float
	if span.x >= DungeonGrid.MAP_WIDTH:
		cx = map_w * 0.5
	else:
		cx = clampf(p.x, half_w, map_w - half_w)
	if span.y >= DungeonGrid.MAP_HEIGHT:
		cy = map_h * 0.5
	else:
		cy = clampf(p.y, half_h, map_h - half_h)
	return Vector2(cx, cy)


func _fit_camera(cam: Camera2D) -> void:
	var vp := cam.get_viewport()
	if vp == null:
		return
	var vs: Vector2 = vp.get_visible_rect().size
	if vs.x < 2.0 or vs.y < 2.0:
		return
	_camera_world_center = _explorer_clamped_view_center_world(_camera_focus_cell)
	var span := _explorer_visible_cell_span(int(vs.x))
	var vis_px := Vector2(float(span.x * _cell_px), float(span.y * _cell_px))
	var z_fit: float = minf(vs.x / vis_px.x, vs.y / vis_px.y)
	var z: float = clampf(z_fit * CAMERA_VIEW_MARGIN, VIEWPORT_ZOOM_CLAMP_MIN, GAMA_STYLE_MAX_ZOOM)
	cam.zoom = Vector2(z, z)
	cam.position = _camera_world_center


## Returns the short label text to draw on top of a tile (empty string = no label).
## Mirrors Explorer `map_template.ex` room/corridor/area/building/stair/special_feature overlays.
static func _label_text_for_tile(s: String) -> String:
	if s.begins_with("starting_stair"):
		var parts := s.split("|")
		if parts.size() >= 2 and not parts[1].is_empty():
			return parts[1]
		return "S"
	if s == "stair_up":
		return "U"
	if s == "stair_down":
		return "D"
	if s.begins_with("room_label"):
		var parts := s.split("|")
		if parts.size() >= 2:
			return parts[1]
		return "R"
	if s.begins_with("corridor_label"):
		var parts := s.split("|")
		if parts.size() >= 2:
			return parts[1]
		return "C"
	if s.begins_with("area_label"):
		var parts_a := s.split("|")
		if parts_a.size() >= 2 and not parts_a[1].is_empty():
			return parts_a[1]
		return "A"
	if s.begins_with("building_label"):
		var parts_b := s.split("|")
		if parts_b.size() >= 2 and not parts_b[1].is_empty():
			return parts_b[1]
		return "B"
	if s.begins_with("special_feature"):
		var parts := s.split("|")
		# `special_feature|F1|Pillar` — use the feature id (F1, W1, …)
		if parts.size() >= 2:
			return parts[1]
		return "F"
	return ""


func _build_cell_labels(grid: Dictionary) -> void:
	if _labels_root == null:
		return
	_cell_labels.clear()
	var font_size := maxi(8, int(_cell_px * 0.28))
	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var cell := Vector2i(x, y)
			var s: String = str(grid.get(cell, "wall"))
			var text := _label_text_for_tile(s)
			if text.is_empty():
				continue
			var lbl := Label.new()
			lbl.text = text
			lbl.add_theme_font_size_override("font_size", font_size)
			lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
			lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
			lbl.add_theme_constant_override("shadow_offset_x", 1)
			lbl.add_theme_constant_override("shadow_offset_y", 1)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lbl.position = Vector2(float(cell.x * _cell_px), float(cell.y * _cell_px))
			lbl.size = Vector2(float(_cell_px), float(_cell_px))
			lbl.visible = true
			_labels_root.add_child(lbl)
			_cell_labels[cell] = lbl


func _refresh_label_visibility(cell: Vector2i, revealed: bool) -> void:
	var lbl: Label = _cell_labels.get(cell) as Label
	if lbl != null and is_instance_valid(lbl):
		lbl.visible = revealed


func _build_tileset_legacy(tilemap: TileMapLayer) -> void:
	var colors: Array[Color] = [
		Color(0.12, 0.1, 0.14),
		Color(0.45, 0.4, 0.35),
		Color(0.35, 0.32, 0.28),
		Color(0.55, 0.38, 0.22),
		Color(0.42, 0.28, 0.18),
		Color(0.5, 0.35, 0.2),
		Color(0.48, 0.25, 0.22),
		Color(0.35, 0.22, 0.18),
		Color(0.25, 0.45, 0.35),
		Color(0.2, 0.35, 0.5),
		Color(0.55, 0.5, 0.2),
		Color(0.3, 0.65, 0.75),
		Color(0.35, 0.45, 0.85),
		Color(0.55, 0.55, 0.58),
		Color(0.75, 0.2, 0.75),
		Color(0.6, 0.15, 0.15),
		Color(0.15, 0.45, 0.2),
		Color(0.5, 0.45, 0.15),
		Color(0.25, 0.25, 0.35),
		Color(0.05, 0.05, 0.08),
	]
	var img := Image.create(
		CELL_PX_LEGACY * PALETTE_COUNT_LEGACY, CELL_PX_LEGACY, false, Image.FORMAT_RGBA8
	)
	for i in PALETTE_COUNT_LEGACY:
		var c: Color = colors[i]
		for xx in CELL_PX_LEGACY:
			for yy in CELL_PX_LEGACY:
				img.set_pixel(i * CELL_PX_LEGACY + xx, yy, c)
	var tex := ImageTexture.create_from_image(img)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(CELL_PX_LEGACY, CELL_PX_LEGACY)
	for i in PALETTE_COUNT_LEGACY:
		atlas.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL_PX_LEGACY, CELL_PX_LEGACY)
	ts.add_source(atlas, 0)
	tilemap.tile_set = ts


func _atlas_coords_for_cell_legacy(_cell: Vector2i, s: String) -> Vector2i:
	if s == "wall":
		return Vector2i(0, 0)
	if s == "floor":
		return Vector2i(1, 0)
	if s == "corridor" or s == "road":
		return Vector2i(2, 0)
	if s == "shrub":
		return Vector2i(7, 0)
	if s == "locked_trapped_door":
		return Vector2i(6, 0)
	if s == "locked_door":
		return Vector2i(4, 0)
	if s == "trapped_door":
		return Vector2i(5, 0)
	if s == "secret_door":
		return Vector2i(3, 0)
	if s == "door":
		return Vector2i(3, 0)
	if s == "stair_up":
		return Vector2i(7, 0)
	if s == "stair_down":
		return Vector2i(8, 0)
	if s.begins_with("starting_stair"):
		return Vector2i(9, 0)
	if s.begins_with("room_label"):
		return Vector2i(10, 0)
	if s.begins_with("corridor_label"):
		return Vector2i(11, 0)
	if s.begins_with("special_feature"):
		return Vector2i(12, 0)
	if s == "room_trap" or s == "trapped_treasure":
		return Vector2i(15, 0)
	if s.begins_with("encounter"):
		return Vector2i(16, 0)
	if s.begins_with("waypoint") or s.begins_with("starting_waypoint"):
		return Vector2i(17, 0)
	var fb := DungeonGrid.should_use_floor_texture(_cell, _rooms, _generation_type)
	if fb:
		return Vector2i(1, 0)
	return Vector2i(2, 0)
