extends SceneTree

## Headless: scan seeds for traditional "up" map where spawn has an orthogonally adjacent locked_door or locked_trapped_door.

const TraditionalGen := preload("res://dungeon/generator/traditional_generator.gd")
const GridWalk := preload("res://dungeon/movement/grid_walkability.gd")


func _init() -> void:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var max_seed := 8000
	var i := 0
	while i < args.size():
		if str(args[i]) == "--max-seed" and i + 1 < args.size():
			max_seed = int(str(args[i + 1]))
			i += 1
		i += 1

	for seed in range(max_seed + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var grid: Dictionary = TraditionalGen.generate(rng, "up")["grid"]
		var spawn := GridWalk.find_starting_cell(grid)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = spawn + d
			var t: String = GridWalk.tile_at(grid, c)
			if GridWalk.is_locked_door_tile(t):
				print("FOUND_SEED=", seed, " spawn=", spawn, " locked_neighbor=", c, " tile=", t)
				quit(0)
				return
	push_error("No seed 0.." + str(max_seed) + " with adjacent locked door from spawn")
	quit(2)
