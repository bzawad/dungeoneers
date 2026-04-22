extends RefCounted

## Runtime `TileSet` construction from bundled PNGs under `res://assets/explorer/images/` (no `.import`
## required: uses `Image.load_from_file`). Populate that tree with `./tools/sync_explorer_assets.sh`.

const DungeonGrid := preload("res://dungeon/generator/grid.gd")

const CELL_MAP_PX := 64

const _TILESET_DIR := "res://assets/explorer/images/tilesets/"
const _DEFAULT_FLOOR_PNG := "res://assets/explorer/images/tilesets/light_cracked_stone.png"
const _DEFAULT_WALL_PNG := "res://assets/explorer/images/tilesets/dark_stone_with_vines.png"
const _DEFAULT_ROAD_PNG := "res://assets/explorer/images/tilesets/dirt_and_grass.png"
const _DEFAULT_SHRUB_PNG := "res://assets/explorer/images/tilesets/green_shrubs.png"
const _LOCK_PNG := "res://assets/explorer/images/lock.png"
const _BREAK_DOOR_PNG := "res://assets/explorer/images/break_door.png"
const _TRAP_PNG := "res://assets/explorer/images/trap.png"
const _SECRET_PNG := "res://assets/explorer/images/secret.png"
## Single door art for modal “pass” prompt (optional).
const _DOOR01_PNG := "res://assets/explorer/images/doors/door01.png"
const _PILLAR_PNG := "res://assets/explorer/images/special_features/pillar.png"
const _STAIR_FMT := "res://assets/explorer/images/map_links/dungeon_stairs%d.png"

## Filled by `build_tile_set_from_bundled_pngs()` — use these instead of hardcoded ids.
static var SRC_FLOOR: int = -1
static var SRC_WALL: int = -1
## Legacy alias: dim fog overlay strength (default “dim” band).
static var SRC_FOG: int = -1
static var SRC_FOG_DARK: int = -1
static var SRC_FOG_DIM: int = -1
static var SRC_FOG_DAYLIGHT: int = -1
static var SRC_PILLAR: int = -1
static var SRC_STAIR_STRIP: int = -1
static var SRC_ROAD: int = -1
static var SRC_SHRUB: int = -1


static func _abs_res(path: String) -> String:
	return ProjectSettings.globalize_path(path)


static func bundled_pngs_present() -> bool:
	return (
		FileAccess.file_exists(_abs_res(_DEFAULT_FLOOR_PNG))
		and FileAccess.file_exists(_abs_res(_DEFAULT_WALL_PNG))
	)


static func load_lock_icon_texture() -> Texture2D:
	var img := _image_from_png_res(_LOCK_PNG)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


static func load_break_door_icon_texture() -> Texture2D:
	var img := _image_from_png_res(_BREAK_DOOR_PNG)
	if img == null:
		return null
	if img.get_width() > 96 or img.get_height() > 96:
		img = img.duplicate()
		img.resize(96, 96, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func load_trap_icon_texture() -> Texture2D:
	var img := _image_from_png_res(_TRAP_PNG)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


static func load_secret_icon_texture() -> Texture2D:
	var img := _image_from_png_res(_SECRET_PNG)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


## Small texture for door “pass” modal (optional).
static func load_door_pass_modal_texture() -> Texture2D:
	var img := _image_from_png_res(_DOOR01_PNG)
	if img == null:
		return null
	if img.get_width() > 96 or img.get_height() > 96:
		img = img.duplicate()
		img.resize(96, 96, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _resolved_tileset_png(preferred_filename: String, fallback_res: String) -> String:
	var fn := preferred_filename.strip_edges()
	if fn.is_empty():
		return fallback_res
	var candidate := _TILESET_DIR + fn
	if FileAccess.file_exists(_abs_res(candidate)):
		return candidate
	return fallback_res


static func hash16(x: int, y: int, seed_x: int, seed_y: int) -> int:
	return posmod(x * seed_x + y * seed_y, 16)


static func atlas_xy_from_hash(h: int) -> Vector2i:
	return Vector2i(h % 4, h >> 2)


static func is_wallish_tile(s: String) -> bool:
	if s == "wall":
		return true
	if s == "secret_door":
		return true
	return false


static func is_corridor_tile(s: String) -> bool:
	return s == "corridor" or s == "road" or s.begins_with("corridor_label")


static func is_door_kind(s: String) -> bool:
	return s == "door" or s == "locked_door" or s == "trapped_door" or s == "locked_trapped_door"


static func is_stair_tile(s: String) -> bool:
	return s == "stair_up" or s == "stair_down" or s.begins_with("starting_stair")


static func is_pillar_tile(s: String) -> bool:
	return s.begins_with("special_feature") and s.contains("Pillar")


static func is_shrub_tile(s: String) -> bool:
	return s == "shrub"


static func stair_variant(x: int, y: int) -> int:
	return posmod(x * 53 + y * 67, 4)


static func build_tile_set_from_bundled_pngs(
	floor_theme_file: String = "",
	wall_theme_file: String = "",
	road_theme_file: String = "",
	shrub_theme_file: String = ""
) -> TileSet:
	SRC_FLOOR = -1
	SRC_WALL = -1
	SRC_FOG = -1
	SRC_FOG_DARK = -1
	SRC_FOG_DIM = -1
	SRC_FOG_DAYLIGHT = -1
	SRC_PILLAR = -1
	SRC_STAIR_STRIP = -1
	SRC_ROAD = -1
	SRC_SHRUB = -1

	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL_MAP_PX, CELL_MAP_PX)

	var floor_path := _resolved_tileset_png(floor_theme_file, _DEFAULT_FLOOR_PNG)
	var wall_path := _resolved_tileset_png(wall_theme_file, _DEFAULT_WALL_PNG)
	var road_path := _resolved_tileset_png(road_theme_file, _DEFAULT_ROAD_PNG)
	var shrub_path := _resolved_tileset_png(shrub_theme_file, _DEFAULT_SHRUB_PNG)
	var floor_tex := _texture_from_png_res(floor_path)
	var wall_tex := _texture_from_png_res(wall_path)
	var road_tex := _texture_from_png_res(road_path)
	var shrub_tex := _texture_from_png_res(shrub_path)
	if floor_tex != null:
		SRC_FLOOR = _add_grid_atlas(ts, floor_tex)
	if wall_tex != null:
		SRC_WALL = _add_grid_atlas(ts, wall_tex)
	if road_tex != null:
		SRC_ROAD = _add_grid_atlas(ts, road_tex)
	if shrub_tex != null:
		SRC_SHRUB = _add_grid_atlas(ts, shrub_tex)

	## Explorer `DungeonWeb.DungeonLive.Renderer.fog_opacity_class/1` — solid overlays; `fog.png` is UI-only there.
	var fog_dark_img := Image.create(CELL_MAP_PX, CELL_MAP_PX, false, Image.FORMAT_RGBA8)
	fog_dark_img.fill(Color(0, 0, 0, 0.8))
	var fog_dim_img := Image.create(CELL_MAP_PX, CELL_MAP_PX, false, Image.FORMAT_RGBA8)
	fog_dim_img.fill(Color(0, 0, 0, 0.6))
	var fog_daylight_img := Image.create(CELL_MAP_PX, CELL_MAP_PX, false, Image.FORMAT_RGBA8)
	fog_daylight_img.fill(Color(0.898039, 0.905882, 0.921569, 0.2))
	SRC_FOG_DARK = _add_single_region_atlas(ts, fog_dark_img)
	SRC_FOG_DIM = _add_single_region_atlas(ts, fog_dim_img)
	SRC_FOG_DAYLIGHT = _add_single_region_atlas(ts, fog_daylight_img)
	SRC_FOG = SRC_FOG_DIM

	var pillar_img := _image_from_png_res(_PILLAR_PNG)
	if pillar_img != null:
		if pillar_img.get_width() != CELL_MAP_PX or pillar_img.get_height() != CELL_MAP_PX:
			pillar_img.resize(CELL_MAP_PX, CELL_MAP_PX, Image.INTERPOLATE_LANCZOS)
		SRC_PILLAR = _add_single_region_atlas(ts, pillar_img)

	SRC_STAIR_STRIP = _add_stair_strip_atlas(ts)
	return ts


static func _texture_from_png_res(res_path: String) -> Texture2D:
	var img := _image_from_png_res(res_path)
	if img == null:
		return null
	## Normalize to 4×64 atlas (source PNGs are 256²; avoids loader/import issues).
	if img.get_width() < 256 or img.get_height() < 256:
		var dup := img.duplicate()
		dup.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		img = dup
	return ImageTexture.create_from_image(img)


static func _image_from_png_res(res_path: String) -> Image:
	var p := _abs_res(res_path)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## 4×4 atlas @ 64px (256² texture after `_texture_from_png_res`).
static func _add_grid_atlas(ts: TileSet, tex: Texture2D) -> int:
	var img := tex.get_image()
	if img == null or img.get_width() < 256 or img.get_height() < 256:
		return -1
	var cell := 64
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(cell, cell)
	for yy in 4:
		for xx in 4:
			src.create_tile(Vector2i(xx, yy))
	return ts.add_source(src)


static func _add_single_region_atlas(ts: TileSet, img: Image) -> int:
	var ttex := ImageTexture.create_from_image(img)
	var src := TileSetAtlasSource.new()
	src.texture = ttex
	src.texture_region_size = Vector2i(img.get_width(), img.get_height())
	src.create_tile(Vector2i.ZERO)
	return ts.add_source(src)


static func _add_stair_strip_atlas(ts: TileSet) -> int:
	var strip := Image.create(CELL_MAP_PX * 4, CELL_MAP_PX, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.25, 0.22, 0.2, 1.0))
	for i in 4:
		var path := _STAIR_FMT % (i + 1)
		var im := _image_from_png_res(path)
		if im == null:
			continue
		if im.get_width() != CELL_MAP_PX or im.get_height() != CELL_MAP_PX:
			im.resize(CELL_MAP_PX, CELL_MAP_PX, Image.INTERPOLATE_LANCZOS)
		strip.blit_rect(im, Rect2i(0, 0, CELL_MAP_PX, CELL_MAP_PX), Vector2i(i * CELL_MAP_PX, 0))
	var stex := ImageTexture.create_from_image(strip)
	var src := TileSetAtlasSource.new()
	src.texture = stex
	src.texture_region_size = Vector2i(CELL_MAP_PX, CELL_MAP_PX)
	for xx in 4:
		src.create_tile(Vector2i(xx, 0))
	return ts.add_source(src)


## Explorer `DungeonWeb.DungeonLive.Renderer.get_tile_background_style/3` — hash seeds match `renderer.ex`.
static func terrain_source_atlas(
	cell: Vector2i, tile_str: String, generation_type: String = "dungeon", rooms: Array = []
) -> Vector2i:
	var x := cell.x
	var y := cell.y
	var h: int
	if is_wallish_tile(tile_str):
		h = hash16(x, y, 47, 19)
	elif is_shrub_tile(tile_str):
		h = hash16(x, y, 79, 101)
	elif is_door_kind(tile_str):
		h = hash16(x, y, 37, 23)
	elif is_corridor_tile(tile_str):
		h = hash16(x, y, 43, 31)
	else:
		if DungeonGrid.should_use_floor_texture(cell, rooms, generation_type):
			h = hash16(x, y, 37, 23)
		else:
			h = hash16(x, y, 43, 31)
	return atlas_xy_from_hash(h)


## Explorer `Renderer.get_tile_background_style/3` — which PNG atlas (floor vs road vs wall).
static func terrain_source_id(
	tile_str: String,
	generation_type: String = "dungeon",
	cell: Vector2i = Vector2i.ZERO,
	rooms: Array = []
) -> int:
	if is_wallish_tile(tile_str):
		return SRC_WALL
	if is_shrub_tile(tile_str):
		return SRC_SHRUB if SRC_SHRUB >= 0 else SRC_FLOOR
	if is_door_kind(tile_str):
		return SRC_FLOOR
	if is_corridor_tile(tile_str):
		if generation_type == "city" and SRC_ROAD >= 0:
			return SRC_ROAD
		return SRC_FLOOR
	if generation_type == "city" and SRC_ROAD >= 0:
		if not DungeonGrid.should_use_floor_texture(cell, rooms, generation_type):
			return SRC_ROAD
	return SRC_FLOOR


static func fog_cell() -> Dictionary:
	return fog_cell_for_type("dim")


## `fog_type` should already be normalized (`dark` | `dim` | `daylight`).
static func fog_cell_for_type(fog_type: String) -> Dictionary:
	match fog_type:
		"daylight":
			return {"src": SRC_FOG_DAYLIGHT, "atlas": Vector2i.ZERO}
		"dim":
			return {"src": SRC_FOG_DIM, "atlas": Vector2i.ZERO}
		_:
			return {"src": SRC_FOG_DARK, "atlas": Vector2i.ZERO}


static func decor_source_atlas(cell: Vector2i, tile_str: String) -> Dictionary:
	## Map doors use `dungeon_door_overlays.gd` (half-cell barrier + lock/trap icons), not full-tile door PNGs.
	if is_stair_tile(tile_str):
		var sv := stair_variant(cell.x, cell.y)
		return {"src": SRC_STAIR_STRIP, "atlas": Vector2i(sv, 0)}
	if is_pillar_tile(tile_str):
		return {"src": SRC_PILLAR, "atlas": Vector2i.ZERO}
	return {}
