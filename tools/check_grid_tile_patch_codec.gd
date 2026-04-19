extends SceneTree

## Headless goldens for `grid_tile_patch_codec.gd` (P7-14). Invoked from `./checks.sh` after `--check-only`
## so format drift fails CI without loading `Main.gd` / autoload-dependent UI scripts.


func _init() -> void:
	const GridTilePatchCodec := preload("res://dungeon/network/grid_tile_patch_codec.gd")
	const TraditionalGen := preload("res://dungeon/generator/traditional_generator.gd")
	if ResourceLoader.load("res://dungeon/network/grid_tile_patch_codec.gd") == null:
		push_error("check_grid_tile_patch_codec: failed to load codec")
		quit(1)
		return
	var gtp_base: Dictionary = {
		Vector2i(0, 0): "floor",
		Vector2i(10, 11): "wall",
	}
	var gtp_patches: Dictionary = {
		Vector2i(10, 11): "door|n",
		Vector2i(2, 20): "treasure",
		Vector2i(1, 3): "floor",
	}
	var gtp_merged := gtp_base.duplicate(true)
	for kk in gtp_patches.keys():
		gtp_merged[kk] = str(gtp_patches[kk])
	var gtp_expect_cs := TraditionalGen.grid_checksum(gtp_merged)
	var gtp_packed: PackedByteArray = GridTilePatchCodec.pack_sorted_patches(gtp_patches)
	if gtp_packed.is_empty():
		push_error("check_grid_tile_patch_codec: pack non-empty patches")
		quit(1)
		return
	if gtp_packed.size() != 44:
		push_error("check_grid_tile_patch_codec: packed size drift (update if wire format changes)")
		quit(1)
		return
	var gtp_list: Array = GridTilePatchCodec.unpack_patches(gtp_packed)
	if gtp_list.size() != 3:
		push_error("check_grid_tile_patch_codec: unpack count")
		quit(1)
		return
	var gtp_via: Dictionary = GridTilePatchCodec.apply_patch_list_to_grid(gtp_list, gtp_base)
	if TraditionalGen.grid_checksum(gtp_via) != gtp_expect_cs:
		push_error("check_grid_tile_patch_codec: checksum after apply_patch_list")
		quit(1)
		return
	var gtp_round: PackedByteArray = GridTilePatchCodec.pack_sorted_patches({})
	if gtp_round.size() != 7:
		push_error("check_grid_tile_patch_codec: empty patch blob size")
		quit(1)
		return
	if not GridTilePatchCodec.unpack_patches(gtp_round).is_empty():
		push_error("check_grid_tile_patch_codec: empty unpack")
		quit(1)
		return
	var gtp_uni: Dictionary = {Vector2i(4, 5): "chest\u2014open"}
	var gtp_uni_p: PackedByteArray = GridTilePatchCodec.pack_sorted_patches(gtp_uni)
	var gtp_uni_l: Array = GridTilePatchCodec.unpack_patches(gtp_uni_p)
	if (
		gtp_uni_l.size() != 1
		or str((gtp_uni_l[0] as Dictionary).get("tile", "")) != "chest\u2014open"
	):
		push_error("check_grid_tile_patch_codec: utf8 roundtrip")
		quit(1)
		return
	quit(0)
