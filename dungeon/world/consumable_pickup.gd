extends RefCounted

## Explorer `FoodSystem`, `HealingPotionSystem` — deterministic rolls per authority seed + cell.

const TreasureSys := preload("res://dungeon/treasure/treasure_system.gd")

const TORCH_PICKUP_XP := 15
## Fallback XP when standing on `quest_item|…` with no matching active quest (parity guard).
const QUEST_ITEM_STUB_XP := 25


static func food_roll_and_actual(
	authority_seed: int, cell: Vector2i, hp: int, max_hp: int
) -> Dictionary:
	var rng := TreasureSys.rng_for_cell(authority_seed, cell, 601)
	var roll: int = rng.randi_range(1, 2)
	var cap: int = maxi(0, max_hp - hp)
	var actual: int = mini(roll, cap)
	return {"roll": roll, "actual": actual}


static func food_display_name(tile: String) -> String:
	match tile:
		"bread":
			return "a chunk of fresh bread"
		"cheese":
			return "a wedge of aged cheese"
		"grapes":
			return "a cluster of grapes"
		_:
			return "some food"


static func food_message(tile: String, _roll: int, actual: int, hp: int, max_hp: int) -> String:
	var fname := food_display_name(tile)
	var base := "You found %s! " % fname
	if hp >= max_hp:
		return base + "You're already at full health, but the food still tastes lawful."
	if actual > 0:
		var sfix := "" if actual == 1 else "s"
		return base + "It restores %d hit point%s. (%d/%d HP)" % [actual, sfix, hp + actual, max_hp]
	return base + "You're too healthy to benefit from it right now."


static func potion_roll_and_actual(
	authority_seed: int, cell: Vector2i, hp: int, max_hp: int
) -> Dictionary:
	var rng := TreasureSys.rng_for_cell(authority_seed, cell, 602)
	var roll: int = rng.randi_range(1, 6)
	var cap: int = maxi(0, max_hp - hp)
	var actual: int = mini(roll, cap)
	return {"roll": roll, "actual": actual}


static func potion_message() -> String:
	return (
		"You found a healing potion! It has been added to your inventory. "
		+ "You can use it later when needed."
	)


static func quest_item_stub_message(raw_tile: String) -> String:
	var tail: String = (
		raw_tile.trim_prefix("quest_item|") if raw_tile.begins_with("quest_item|") else raw_tile
	)
	return (
		"You recover a quest relic"
		+ ((": " + tail) if not tail.is_empty() else "")
		+ ".\n\n(No active quest matches this relic — awarding fallback XP only.)"
	)
