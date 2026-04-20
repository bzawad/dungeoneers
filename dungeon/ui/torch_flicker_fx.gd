extends RefCounted

const PartyMarkerArt := preload("res://dungeon/ui/party_marker_art.gd")

## Explorer `map_template.ex`: ~0.8s ease-in-out infinite alternate on torch halos (opacity + scale).
## Tweens are created on the **glow node** so parent move tweens (e.g. `DungeonGridView`) never kill them.

const GLOW_TEXTURE_PATH := "res://assets/effects/glow_circle_96.png"
const FLICKER_HALF_SEC := 0.4
const META_TWEEN := "torch_flicker_tween"

static var _glow_tex: Texture2D


static func glow_texture() -> Texture2D:
	if _glow_tex != null:
		return _glow_tex
	if ResourceLoader.exists(GLOW_TEXTURE_PATH):
		_glow_tex = load(GLOW_TEXTURE_PATH) as Texture2D
	return _glow_tex


static func prepare_glow_rect(tex: TextureRect) -> void:
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	tex.material = mat
	var t := glow_texture()
	if t != null:
		tex.texture = t


static func kill_tween(host: Node, meta_key: String = META_TWEEN) -> void:
	if host == null or not host.has_meta(meta_key):
		return
	var twv: Variant = host.get_meta(meta_key)
	if twv is Tween:
		(twv as Tween).kill()
	host.remove_meta(meta_key)


## Runs on `glow` so it is not replaced by `create_tween()` on the grid view. Meta stored on `host_for_meta`.
static func start_torch_flicker_tween(
	glow: CanvasItem, host_for_meta: Node, meta_key: String = META_TWEEN
) -> void:
	kill_tween(host_for_meta, meta_key)
	if glow == null or not is_instance_valid(glow):
		return
	var tw := glow.create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.set_parallel(true)
	tw.tween_property(glow, "modulate:a", 0.92, FLICKER_HALF_SEC).from(0.58)
	tw.tween_property(glow, "scale", Vector2(1.06, 1.06), FLICKER_HALF_SEC).from(
		Vector2(0.93, 0.93)
	)
	tw.set_parallel(false)
	tw.set_parallel(true)
	tw.tween_property(glow, "modulate:a", 0.58, FLICKER_HALF_SEC)
	tw.tween_property(glow, "scale", Vector2(0.93, 0.93), FLICKER_HALF_SEC)
	host_for_meta.set_meta(meta_key, tw)


## Torch hand bias vs Explorer `get_torch_glow_position/1` (48px cell semantics).
static func layout_player_torch_halo(glow: Control, facing: int, side: float) -> void:
	var d := side / 48.0
	var halo := side * 1.45
	var pos := (Vector2(side, side) - Vector2(halo, halo)) * 0.5
	var bias := Vector2.ZERO
	match facing:
		PartyMarkerArt.FACING_DOWN:
			bias = Vector2(5.0 * d, 3.0 * d)
		PartyMarkerArt.FACING_UP:
			bias = Vector2(-5.0 * d, 3.0 * d)
		PartyMarkerArt.FACING_LEFT:
			bias = Vector2(-5.0 * d, 3.0 * d)
		PartyMarkerArt.FACING_RIGHT:
			bias = Vector2(5.0 * d, 3.0 * d)
		_:
			bias = Vector2(5.0 * d, 3.0 * d)
	glow.position = pos + bias
	glow.size = Vector2(halo, halo)
	glow.pivot_offset = glow.size * 0.5


static func layout_cell_torch_underlay(glow: Control, cell_px: int) -> void:
	var h := float(cell_px) * 1.22
	var off := (float(cell_px) - h) * 0.5
	glow.position = Vector2(off, off)
	glow.size = Vector2(h, h)
	glow.pivot_offset = glow.size * 0.5
