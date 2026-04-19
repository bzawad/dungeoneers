extends RefCounted

## Phase 5 (P7-12): Explorer `map_template.ex` raster overlays on revealed cells — paths mirror
## `Dungeon.Generator.Features.get_special_feature_image_path/1` and static `/images/*.png` icons.

const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")

const _REGISTRY_JSON := "res://dungeon/data/special_feature_registry.json"
const _IMAGES := "res://assets/explorer/images/"
const _ROOT_FEATURE_IMAGES := ["chest.png", "torch.png", "healing_potion.png", "pile_of_bones.png"]

static var _registry_loaded: bool = false
## Lowercased feature name → { "image": String, "size": float }
static var _feature_row_by_lower: Dictionary = {}
static var _texture_cache: Dictionary = {}  # res path String → Texture2D


static func _abs_res(path: String) -> String:
	return ProjectSettings.globalize_path(path)


static func _ensure_registry() -> void:
	if _registry_loaded:
		return
	_registry_loaded = true
	var txt := FileAccess.get_file_as_string(_REGISTRY_JSON)
	if txt.is_empty():
		return
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or parsed is not Array:
		return
	for item in parsed as Array:
		if item is not Dictionary:
			continue
		var d: Dictionary = item
		var nm := str(d.get("name", "")).strip_edges()
		if nm.is_empty():
			continue
		_feature_row_by_lower[nm.to_lower()] = {
			"image": str(d.get("image", "barrel.png")).strip_edges(),
			"size": float(d.get("size", 1.0)),
		}


static func feature_image_filename_for_name(feature_name: String) -> String:
	_ensure_registry()
	var row: Variant = _feature_row_by_lower.get(feature_name.strip_edges().to_lower())
	if row is Dictionary:
		return str((row as Dictionary).get("image", "barrel.png"))
	return "barrel.png"


static func feature_display_size_for_name(feature_name: String) -> float:
	_ensure_registry()
	var row2: Variant = _feature_row_by_lower.get(feature_name.strip_edges().to_lower())
	if row2 is Dictionary:
		return float((row2 as Dictionary).get("size", 1.0))
	return 1.0


static func explorer_res_path_for_feature_image(image_file: String) -> String:
	var fn := image_file.strip_edges()
	if fn.is_empty():
		fn = "barrel.png"
	if fn in _ROOT_FEATURE_IMAGES:
		return _IMAGES + fn
	return _IMAGES + "special_features/" + fn


## Last `|` segment is the canonical feature name (`special_feature|F1|Altar` or `special_feature|Altar|Altar`).
static func feature_name_from_special_tile(tile_str: String) -> String:
	if not tile_str.begins_with("special_feature|"):
		return ""
	var parts := tile_str.split("|")
	if parts.is_empty():
		return ""
	return parts[parts.size() - 1].strip_edges()


static func texture_from_explorer_png_res(res_path: String) -> Texture2D:
	var p := res_path.strip_edges()
	if p.is_empty():
		return null
	if _texture_cache.has(p):
		return _texture_cache[p] as Texture2D
	var ap := _abs_res(p)
	if not FileAccess.file_exists(ap):
		return null
	var img := Image.load_from_file(ap)
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[p] = tex
	return tex


static func _icon_px(cell_px: int, explorer_px: int = 32) -> int:
	return maxi(8, int(round(float(explorer_px) * float(cell_px) / 48.0)))


static func _feature_icon_px(cell_px: int, feature_name: String) -> int:
	var fsz := feature_display_size_for_name(feature_name)
	var px := int(round(fsz * float(cell_px)))
	return clampi(px, 8, int(float(cell_px) * 2.75))


static func _link_big_px(cell_px: int) -> int:
	return maxi(cell_px, int(round(96.0 * float(cell_px) / 48.0)))


## Returns up to two overlay dicts: `texture`, `px` (Vector2 top-left within cell), `size` (Vector2), `z` (int).
static func overlay_layers_for_tile(
	tile_str: String, cell_px: int, _fog_enabled: bool, _fog_clicked_cells: Dictionary
) -> Array:
	var out: Array = []
	var s := tile_str.strip_edges()
	if s.is_empty():
		return out

	if s == "treasure":
		var t1 := texture_from_explorer_png_res(_IMAGES + "chest.png")
		if t1 != null:
			var ip := _icon_px(cell_px)
			var off := (cell_px - ip) * 0.5
			out.append({"texture": t1, "px": Vector2(off, off), "size": Vector2(ip, ip), "z": 0})
		return out

	if s == "room_trap":
		var tt := texture_from_explorer_png_res(_IMAGES + "trap.png")
		if tt != null:
			var ir := _icon_px(cell_px)
			var offr := (cell_px - ir) * 0.5
			out.append({"texture": tt, "px": Vector2(offr, offr), "size": Vector2(ir, ir), "z": 0})
		return out

	if s == "torch":
		var tt2 := texture_from_explorer_png_res(_IMAGES + "torch.png")
		if tt2 != null:
			var it := _icon_px(cell_px)
			var ot := (cell_px - it) * 0.5
			out.append({"texture": tt2, "px": Vector2(ot, ot), "size": Vector2(it, it), "z": 0})
		return out

	if s in ["bread", "cheese", "grapes", "healing_potion", "pile_of_bones"]:
		var fn := s + ".png"
		var tf := texture_from_explorer_png_res(_IMAGES + fn)
		if tf != null:
			var ic := _icon_px(cell_px)
			var oc := (cell_px - ic) * 0.5
			out.append({"texture": tf, "px": Vector2(oc, oc), "size": Vector2(ic, ic), "z": 0})
		return out

	if s.begins_with("quest_item|"):
		var tq := texture_from_explorer_png_res(_IMAGES + "special_item.png")
		if tq != null:
			var iq := _icon_px(cell_px)
			var oq := (cell_px - iq) * 0.5
			out.append({"texture": tq, "px": Vector2(oq, oq), "size": Vector2(iq, iq), "z": 0})
		return out

	if s.begins_with("special_feature|"):
		var fname := feature_name_from_special_tile(s)
		if fname.is_empty() or fname.to_lower() == "pillar":
			return out
		var img_fn := feature_image_filename_for_name(fname)
		var res_p := explorer_res_path_for_feature_image(img_fn)
		var tfeat := texture_from_explorer_png_res(res_p)
		if tfeat != null:
			var iff := _feature_icon_px(cell_px, fname)
			var off_f := (cell_px - iff) * 0.5
			(
				out
				. append(
					{
						"texture": tfeat,
						"px": Vector2(off_f, off_f),
						"size": Vector2(iff, iff),
						"z": 0,
					}
				)
			)
		return out

	if s.begins_with("starting_waypoint|"):
		var tw0 := texture_from_explorer_png_res(_IMAGES + "map_links/outdoor_waypoint1.png")
		if tw0 != null:
			var iw := _icon_px(cell_px, 48)
			var ow := (cell_px - iw) * 0.5
			out.append({"texture": tw0, "px": Vector2(ow, ow), "size": Vector2(iw, iw), "z": 0})
		return out

	if s.begins_with("waypoint|"):
		var parts_w := s.split("|")
		var idx := 1
		if parts_w.size() >= 2:
			idx = clampi(int(parts_w[1]), 1, 4)
		var path_w := _IMAGES + ("map_links/outdoor_waypoint%d.png" % idx)
		var tw := texture_from_explorer_png_res(path_w)
		if tw != null:
			var iw2 := _icon_px(cell_px, 48)
			var ow2 := (cell_px - iw2) * 0.5
			out.append({"texture": tw, "px": Vector2(ow2, ow2), "size": Vector2(iw2, iw2), "z": 0})
		return out

	if (
		s.begins_with("cavern_entrance|")
		or s.begins_with("dungeon_entrance|")
		or s.begins_with("cavern_exit|")
		or s.begins_with("dungeon_exit|")
	):
		var parts_l := s.split("|")
		var nlink := 1
		if parts_l.size() >= 2:
			nlink = maxi(1, int(parts_l[1]))
		var base := ""
		if s.begins_with("cavern_entrance|"):
			base = "cavern_entrance%d.png" % nlink
		elif s.begins_with("dungeon_entrance|"):
			base = "dungeon_entrance%d.png" % nlink
		elif s.begins_with("cavern_exit|"):
			base = "cavern_exit%d.png" % nlink
		else:
			base = "dungeon_exit%d.png" % nlink
		var tl := texture_from_explorer_png_res(_IMAGES + "map_links/" + base)
		if tl != null:
			var big := _link_big_px(cell_px)
			var off_l := (cell_px - big) * 0.5
			(
				out
				. append(
					{
						"texture": tl,
						"px": Vector2(off_l, off_l),
						"size": Vector2(big, big),
						"z": 0,
					}
				)
			)
		return out

	return out


## Builds overlay layers; `cell` is required for `trapped_treasure` trap badge (Explorer `show_door_trap?`).
static func overlay_layers_for_tile_at_cell(
	tile_str: String, cell: Vector2i, cell_px: int, fog_enabled: bool, fog_clicked_cells: Dictionary
) -> Array:
	var s := tile_str.strip_edges()
	if s == "trapped_treasure":
		var out_t: Array = []
		var tc := texture_from_explorer_png_res(_IMAGES + "chest.png")
		if tc != null:
			var ipc := _icon_px(cell_px)
			var offc := (cell_px - ipc) * 0.5
			out_t.append(
				{"texture": tc, "px": Vector2(offc, offc), "size": Vector2(ipc, ipc), "z": 0}
			)
		if DungeonFog.show_trap_icon_on_cell(fog_enabled, fog_clicked_cells, cell):
			var ttb := texture_from_explorer_png_res(_IMAGES + "trap.png")
			if ttb != null:
				var badge := _icon_px(cell_px, 18)
				var margin := maxi(1, int(round(float(cell_px) * 0.04)))
				(
					out_t
					. append(
						{
							"texture": ttb,
							"px": Vector2(float(cell_px - badge - margin), float(margin)),
							"size": Vector2(badge, badge),
							"z": 1,
						}
					)
				)
		return out_t
	return overlay_layers_for_tile(tile_str, cell_px, fog_enabled, fog_clicked_cells)


## Headless / CI: paths only (no PNG bytes required).
static func expected_png_res_for_tile(tile_str: String) -> String:
	var s := tile_str.strip_edges()
	if s == "treasure" or s == "trapped_treasure":
		return _IMAGES + "chest.png"
	if s == "room_trap":
		return _IMAGES + "trap.png"
	if s == "torch":
		return _IMAGES + "torch.png"
	if s in ["bread", "cheese", "grapes", "healing_potion", "pile_of_bones"]:
		return _IMAGES + s + ".png"
	if s.begins_with("quest_item|"):
		return _IMAGES + "special_item.png"
	if s.begins_with("special_feature|"):
		var fn := feature_name_from_special_tile(s)
		if fn.is_empty() or fn.to_lower() == "pillar":
			return ""
		return explorer_res_path_for_feature_image(feature_image_filename_for_name(fn))
	if s.begins_with("starting_waypoint|"):
		return _IMAGES + "map_links/outdoor_waypoint1.png"
	if s.begins_with("waypoint|"):
		var parts := s.split("|")
		var idx := 1
		if parts.size() >= 2:
			idx = clampi(int(parts[1]), 1, 4)
		return _IMAGES + ("map_links/outdoor_waypoint%d.png" % idx)
	if s.begins_with("cavern_entrance|"):
		return _IMAGES + "map_links/cavern_entrance1.png"
	if s.begins_with("dungeon_entrance|"):
		return _IMAGES + "map_links/dungeon_entrance1.png"
	if s.begins_with("cavern_exit|"):
		return _IMAGES + "map_links/cavern_exit1.png"
	if s.begins_with("dungeon_exit|"):
		return _IMAGES + "map_links/dungeon_exit1.png"
	return ""


static func assert_registry_has_images_for_ci() -> void:
	_ensure_registry()
	if _feature_row_by_lower.is_empty():
		push_error("map_cell_overlay_art: registry empty")
		return
	for k in ["altar", "barrel", "brazier"]:
		if not _feature_row_by_lower.has(k):
			push_error("map_cell_overlay_art: missing registry key " + k)
			return
		var row: Dictionary = _feature_row_by_lower[k] as Dictionary
		if str(row.get("image", "")).is_empty():
			push_error("map_cell_overlay_art: empty image for " + k)
			return
