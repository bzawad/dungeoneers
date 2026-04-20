extends RefCounted

## Back-compat entry for Phase 1 generation; delegates to `dungeon_generator.gd`.

const DungeonGenerator := preload("res://dungeon/generator/dungeon_generator.gd")


## Legacy tile hints when no theme name is available (editor / tests).
static func tile_themes_for_direction(theme_direction: String) -> Dictionary:
	if theme_direction == "down":
		return {"floor_theme": "brown_cavern.png", "wall_theme": "red_brown_cavern.png"}
	return {"floor_theme": "light_cobblestone.png", "wall_theme": "dark_cobblestone.png"}


static func generate(rng: RandomNumberGenerator, theme_direction: String = "up") -> Dictionary:
	return DungeonGenerator.generate_for_legacy_cli(rng, theme_direction)


static func grid_checksum(grid: Dictionary) -> int:
	return DungeonGenerator.grid_checksum(grid)


static func count_exits(grid: Dictionary) -> int:
	return DungeonGenerator.count_exits(grid)
