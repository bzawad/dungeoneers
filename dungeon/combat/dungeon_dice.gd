extends RefCounted

## Explorer `Dungeon.Dice` — parse + roll `NdS` strings using a supplied RNG.


static func parse_dice_string(dice_string: String) -> Vector2i:
	var s := dice_string.strip_edges().to_lower()
	var parts := s.split("d")
	if parts.size() != 2:
		return Vector2i(1, 4)
	var n_dice := parts[0].to_int()
	var n_sides := parts[1].to_int()
	if n_dice < 1 or n_sides < 1:
		return Vector2i(1, 4)
	return Vector2i(n_dice, n_sides)


static func roll_dice_string(rng: RandomNumberGenerator, dice_string: String) -> int:
	var v := parse_dice_string(dice_string)
	var sum := 0
	for _i in range(v.x):
		sum += rng.randi_range(1, v.y)
	return sum
