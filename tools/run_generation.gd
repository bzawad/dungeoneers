extends SceneTree

## Headless: `godot4 --headless --path . --script res://tools/run_generation.gd -- --seed 42`
## Prints one JSON line with generation stats (Phase 1 traditional slice).
## Legacy `--theme up|down` uses the same theme JSON as `DungeonGenerator.generate_for_legacy_cli` and honors `--dungeon-level`.

const DungeonGenerator := preload("res://dungeon/generator/dungeon_generator.gd")
const DungeonThemes := preload("res://dungeon/generator/dungeon_themes.gd")


func _init() -> void:
	var seed: int = 1
	var theme := "up"
	var theme_name := ""
	var dungeon_level: int = 1
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := str(args[i])
		if a == "--seed" and i + 1 < args.size():
			seed = int(str(args[i + 1]))
			i += 1
		elif a == "--theme" and i + 1 < args.size():
			theme = str(args[i + 1])
			i += 1
		elif a == "--theme-name" and i + 1 < args.size():
			theme_name = str(args[i + 1])
			i += 1
		elif a == "--dungeon-level" and i + 1 < args.size():
			dungeon_level = int(str(args[i + 1]))
			i += 1
		i += 1

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var result: Dictionary
	if not theme_name.strip_edges().is_empty():
		DungeonThemes.load_themes()
		var td: Dictionary = DungeonThemes.find_theme_by_name(theme_name.strip_edges())
		if td.is_empty():
			push_error("[run_generation] unknown theme-name: " + theme_name)
			quit(1)
			return
		result = DungeonGenerator.generate_with_theme_data(rng, td, 1, dungeon_level)
	else:
		result = DungeonGenerator.generate_for_legacy_cli_with_level(rng, theme, dungeon_level)

	if dungeon_level >= 2 and not str(result.get("theme", "")).strip_edges().is_empty():
		_verify_torch_in_first_spawn_area(result, dungeon_level)

	var has_trapped := false
	var g: Variant = result.get("grid", {})
	if g is Dictionary:
		for _k in g:
			if str(g[_k]) == "trapped_treasure":
				has_trapped = true
				break

	var summary := {
		"phase": 1,
		"seed": seed,
		"dungeon_level": dungeon_level,
		"theme_direction": str(result.get("theme_direction", theme)),
		"theme": str(result.get("theme", "")),
		"generation_type": str(result.get("generation_type", "dungeon")),
		"fog_type": str(result.get("fog_type", "dark")),
		"floor_theme": str(result.get("floor_theme", "")),
		"wall_theme": str(result.get("wall_theme", "")),
		"width": result.get("width", 0),
		"height": result.get("height", 0),
		"transition_theme": str(result.get("transition_theme", "")),
		"room_count": result["room_count"],
		"corridor_count": result["corridor_count"],
		"exit_count": result["exit_count"],
		"floor_cells": result["floor_cells"],
		"corridor_cells": result["corridor_cells"],
		"door_cells": result["door_cells"],
		"grid_checksum": DungeonGenerator.grid_checksum(result["grid"]),
		"has_trapped_treasure": has_trapped,
	}
	var json := JSON.new()
	print(json.stringify(summary))
	quit(0)


func _verify_torch_in_first_spawn_area(result: Dictionary, dungeon_level: int) -> void:
	if str(result.get("fog_type", "")) == "daylight":
		return
	var grid: Variant = result.get("grid", null)
	var rooms: Variant = result.get("rooms", null)
	if grid == null or not grid is Dictionary or rooms == null or not rooms is Array:
		return
	var g: Dictionary = grid
	var rs: Array = rooms
	if rs.is_empty():
		return
	var first: Variant = rs[0]
	if first is not Dictionary:
		return
	var r: Dictionary = first as Dictionary
	var cells: Array = r.get("cells", []) as Array
	if not cells.is_empty():
		for c in cells:
			if c is Vector2i and str(g.get(c as Vector2i, "")) == "torch":
				return
		push_error(
			(
				"[run_generation] torch parity: dungeon_level=%d but no torch in first area cells"
				% dungeon_level
			)
		)
		quit(1)
		return
	if not r.has_all(["x", "y", "width", "height"]):
		return
	var rx: int = int(r["x"])
	var ry: int = int(r["y"])
	var rw: int = int(r["width"])
	var rh: int = int(r["height"])
	for x in range(rx, rx + rw):
		for y in range(ry, ry + rh):
			if str(g.get(Vector2i(x, y), "")) == "torch":
				return
	push_error(
		(
			"[run_generation] torch parity: dungeon_level=%d but no torch in first room bounds"
			% dungeon_level
		)
	)
	quit(1)
