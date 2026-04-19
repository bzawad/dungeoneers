extends RefCounted

## Mirrors Explorer `Dungeon.PlayerStats` XP → level curve (`@xp_per_level_multiplier` 500).

const XP_PER_LEVEL_MULTIPLIER := 500


static func xp_required_for_level(level: int) -> int:
	var lv := maxi(1, level)
	if lv <= 1:
		return 0
	var sum := 0
	for l in range(1, lv):
		sum += l * XP_PER_LEVEL_MULTIPLIER
	return sum


static func calculate_level(xp: int) -> int:
	var x := maxi(0, xp)
	var level := 1
	while x >= xp_required_for_level(level + 1):
		level += 1
	return level


static func xp_needed_for_next_level(current_xp: int) -> int:
	var x := maxi(0, current_xp)
	var cl := calculate_level(x)
	var next_xp := xp_required_for_level(cl + 1)
	return next_xp - x


static func leveled_up(old_xp: int, new_xp: int) -> bool:
	return calculate_level(old_xp) < calculate_level(new_xp)
