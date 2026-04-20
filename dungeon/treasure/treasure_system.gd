extends RefCounted

## Explorer `DungeonWeb.DungeonLive.TreasureSystem` + `Dice.roll_dice_string("3d10")` gold (deterministic per cell).

const DungeonGrid := preload("res://dungeon/generator/grid.gd")


static func rng_for_cell(authority_seed: int, cell: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(authority_seed) * 101_236_853
		^ cell.x * 1_000_003
		^ cell.y * 97_643
		^ int(salt) * 12_345_679
	)
	return rng


static func roll_gold_3d10(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, 10) + rng.randi_range(1, 10) + rng.randi_range(1, 10)


static func gold_for_treasure_cell(authority_seed: int, cell: Vector2i) -> int:
	var rng := rng_for_cell(authority_seed, cell, 77)
	return roll_gold_3d10(rng)


## Explorer `map_template.ex` title + `DescriptionService.get_discovery_fallback(:treasure)` body (static port).
static func treasure_discovery_dialog_title() -> String:
	return "Treasure Found!"


static func treasure_discovery_message(gold_amount: int, theme_display_name: String) -> String:
	var theme := (
		theme_display_name if not theme_display_name.strip_edges().is_empty() else "dungeon"
	)
	return (
		"A collection of valuable coins and trinkets worth %d gold, gleaming in the dim light of this %s."
		% [gold_amount, theme]
	)


## After pickup: Explorer `determine_underlying_tile/2` (room → floor, else corridor).
static func underlying_tile_after_collect(cell: Vector2i, rooms: Array) -> String:
	if rooms.is_empty():
		return "floor"
	if DungeonGrid.point_in_any_room(cell, rooms):
		return "floor"
	return "corridor"
