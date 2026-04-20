extends RefCounted

## Phase 5.6: Explorer `map_template.ex` uses `/images/characters/rogue1_N.png` / `rogue2_N.png` (N=0..3 for facing).
## **MOV-01:** map markers pick N from the last orthogonal/diagonal grid step (same 0..3 convention as **gama** `Player.gd`).
## **Phase 6:** optional walk in-betweens: `rogue2_{N}_w1.png`, … (same prefix as lit/unlit branch).
## Lit vs unlit matches Explorer `get_player_sprite_path/3` (daylight → always rogue2; else rogue1 iff torch > 0).

const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")
const CHAR_DIR := "res://assets/explorer/images/characters/"
const WALK_ANIM_FPS := 8.0

## Matches **gama** `Player.update_state`: 0 = down (+grid y), 1 = up, 2 = left, 3 = right.
const FACING_DOWN := 0
const FACING_UP := 1
const FACING_LEFT := 2
const FACING_RIGHT := 3


## Explorer: daylight always unlit art; else lit iff `torch_burn_time > 0`. HUD burn **-1** = no torch UI → unlit.
static func torch_lit_for_marker(
	fog_type: String, torch_burn_pct: int, fog_enabled_for_torch_ui: bool
) -> bool:
	if not fog_enabled_for_torch_ui:
		return false
	if DungeonFog.normalize_fog_type(fog_type) == "daylight":
		return false
	return torch_burn_pct > 0


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


static func _texture_for_role_facing_try(role: String, f: int, torch_lit: bool) -> Texture2D:
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
	var first := "rogue1_%s.png" if torch_lit else "rogue2_%s.png"
	var second := "rogue2_%s.png" if torch_lit else "rogue1_%s.png"
	var ta := _load_png(CHAR_DIR + (first % sfx))
	if ta != null:
		return ta
	return _load_png(CHAR_DIR + (second % sfx))


## Optional extra frame for facing `f` (1-based index `walk_i`: *_w1.png, *_w2.png, …).
static func _texture_walk_frame_try(
	role: String, f: int, walk_i: int, torch_lit: bool
) -> Texture2D:
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
	var pf := "rogue1_%d_w%d.png" if torch_lit else "rogue2_%d_w%d.png"
	var ps := "rogue2_%d_w%d.png" if torch_lit else "rogue1_%d_w%d.png"
	var t3 := _load_png(CHAR_DIR + (pf % [fi, walk_i]))
	if t3 != null:
		return t3
	return _load_png(CHAR_DIR + (ps % [fi, walk_i]))


## Base facing frame plus any `*_w1.png`, `*_w2.png`, … for that facing. Single element when no walk extras are synced.
static func walk_frame_textures(role: String, facing: int, torch_lit: bool) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var base := texture_for_role_facing(role, facing, torch_lit)
	if base == null:
		base = _texture_south_only(role, torch_lit)
	if base == null:
		return out
	out.append(base)
	var wi := 1
	while wi <= 32:
		var ex := _texture_walk_frame_try(role, facing, wi, torch_lit)
		if ex == null:
			break
		out.append(ex)
		wi += 1
	return out


## Returns a plain `Texture2D` for the marker: single frame as-is, or `AnimatedTexture` when multiple walk frames exist.
static func make_walk_display_texture(
	role: String, facing: int, torch_lit: bool, fps: float = WALK_ANIM_FPS
) -> Texture2D:
	var fr := walk_frame_textures(role, facing, torch_lit)
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
static func texture_for_role_facing(role: String, facing: int, torch_lit: bool) -> Texture2D:
	var want := posmod(int(facing), 4)
	var t := _texture_for_role_facing_try(role, want, torch_lit)
	if t != null:
		return t
	if want != 0:
		t = _texture_for_role_facing_try(role, 0, torch_lit)
		if t != null:
			return t
	return _texture_south_only(role, torch_lit)


## South-facing token; `torch_lit` picks rogue1 vs rogue2 for rogues.
static func texture_for_role(role: String, torch_lit: bool) -> Texture2D:
	return _texture_south_only(role, torch_lit)


static func _texture_south_only(role: String, torch_lit: bool) -> Texture2D:
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
	var first := "rogue1_0.png" if torch_lit else "rogue2_0.png"
	var second := "rogue2_0.png" if torch_lit else "rogue1_0.png"
	var t2 := _load_png(CHAR_DIR + first)
	if t2 != null:
		return t2
	return _load_png(CHAR_DIR + second)
