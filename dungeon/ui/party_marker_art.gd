extends RefCounted

## Phase 5.6: Explorer `map_template.ex` uses `/images/characters/rogue1_N.png` / `rogue2_N.png` (N=0..3 for facing).
## **MOV-01:** map markers pick N from the last orthogonal/diagonal grid step (same 0..3 convention as **gama** `Player.gd`).
## **Phase 6:** optional walk in-betweens: `rogue2_{N}_w1.png`, `rogue2_{N}_w2.png`, … (same role resolution as facing art).

const CHAR_DIR := "res://assets/explorer/images/characters/"
const WALK_ANIM_FPS := 8.0

## Matches **gama** `Player.update_state`: 0 = down (+grid y), 1 = up, 2 = left, 3 = right.
const FACING_DOWN := 0
const FACING_UP := 1
const FACING_LEFT := 2
const FACING_RIGHT := 3


static func _load_png(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as Texture2D


## Last grid step `cell - prev_cell` → 4-way facing (horizontal preferred on diagonals, like **gama** `ai_system`).
static func facing_from_grid_step(delta: Vector2i) -> int:
	if delta == Vector2i.ZERO:
		return FACING_DOWN
	if absi(delta.x) >= absi(delta.y):
		if delta.x > 0:
			return FACING_RIGHT
		if delta.x < 0:
			return FACING_LEFT
	if delta.y < 0:
		return FACING_UP
	return FACING_DOWN


static func _texture_for_role_facing_try(role: String, f: int) -> Texture2D:
	var r := role.strip_edges().to_lower()
	var sfx := "%d" % f
	if r.contains("fighter"):
		for pat in ["fighter2_%s.png", "fighter1_%s.png", "fighter_%s.png"]:
			var t := _load_png(CHAR_DIR + (pat % sfx))
			if t != null:
				return t
		for pat2 in ["rogue1_%s.png", "rogue2_%s.png"]:
			var t2 := _load_png(CHAR_DIR + (pat2 % sfx))
			if t2 != null:
				return t2
		return null
	for pat3 in ["rogue2_%s.png", "rogue1_%s.png"]:
		var t3 := _load_png(CHAR_DIR + (pat3 % sfx))
		if t3 != null:
			return t3
	return null


## Optional extra frame for facing `f` (1-based index `walk_i`: *_w1.png, *_w2.png, …). Same basename order as `_texture_for_role_facing_try`.
static func _texture_walk_frame_try(role: String, f: int, walk_i: int) -> Texture2D:
	var r := role.strip_edges().to_lower()
	var fi := posmod(int(f), 4)
	if r.contains("fighter"):
		for pat in ["fighter2_%d_w%d.png", "fighter1_%d_w%d.png", "fighter_%d_w%d.png"]:
			var t := _load_png(CHAR_DIR + (pat % [fi, walk_i]))
			if t != null:
				return t
		for pat2 in ["rogue1_%d_w%d.png", "rogue2_%d_w%d.png"]:
			var t2 := _load_png(CHAR_DIR + (pat2 % [fi, walk_i]))
			if t2 != null:
				return t2
		return null
	for pat3 in ["rogue2_%d_w%d.png", "rogue1_%d_w%d.png"]:
		var t3 := _load_png(CHAR_DIR + (pat3 % [fi, walk_i]))
		if t3 != null:
			return t3
	return null


## Base facing frame plus any `*_w1.png`, `*_w2.png`, … for that facing. Single element when no walk extras are synced.
static func walk_frame_textures(role: String, facing: int) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var base := texture_for_role_facing(role, facing)
	if base == null:
		base = _texture_south_only(role)
	if base == null:
		return out
	out.append(base)
	var wi := 1
	while wi <= 32:
		var ex := _texture_walk_frame_try(role, facing, wi)
		if ex == null:
			break
		out.append(ex)
		wi += 1
	return out


## Returns a plain `Texture2D` for the marker: single frame as-is, or `AnimatedTexture` when multiple walk frames exist.
static func make_walk_display_texture(
	role: String, facing: int, fps: float = WALK_ANIM_FPS
) -> Texture2D:
	var fr := walk_frame_textures(role, facing)
	if fr.is_empty():
		return null
	if fr.size() == 1:
		return fr[0]
	var at := AnimatedTexture.new()
	at.frames = fr.size()
	at.fps = fps
	for i in range(fr.size()):
		at.set_frame_texture(i, fr[i])
	return at


## `facing` is `FACING_*` (0..3). Falls back to south (`*_0`) then `_texture_south_only` if art missing for that frame.
static func texture_for_role_facing(role: String, facing: int) -> Texture2D:
	var want := posmod(int(facing), 4)
	var t := _texture_for_role_facing_try(role, want)
	if t != null:
		return t
	if want != 0:
		t = _texture_for_role_facing_try(role, 0)
		if t != null:
			return t
	return _texture_south_only(role)


## South-facing, no-torch set (`rogue2`) matches Explorer daylight / unlit branch for a stable map token.
static func texture_for_role(role: String) -> Texture2D:
	return _texture_south_only(role)


static func _texture_south_only(role: String) -> Texture2D:
	var r := role.strip_edges().to_lower()
	if r.contains("fighter"):
		for rel in ["fighter2_0.png", "fighter1_0.png", "fighter_0.png"]:
			var t0 := _load_png(CHAR_DIR + rel)
			if t0 != null:
				return t0
		var alt := _load_png(CHAR_DIR + "rogue1_0.png")
		if alt != null:
			return alt
		return _load_png(CHAR_DIR + "rogue2_0.png")
	for rel2 in ["rogue2_0.png", "rogue1_0.png"]:
		var t2 := _load_png(CHAR_DIR + rel2)
		if t2 != null:
			return t2
	return null
