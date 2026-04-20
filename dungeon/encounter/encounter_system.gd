extends RefCounted

## Explorer `DungeonWeb.DungeonLive` encounter evade (DC 12 d20+DEX).

const PlayerCombatStats := preload("res://dungeon/combat/player_combat_stats.gd")

const EVADE_DC := 12
const EVADE_XP := 5


static func dex_bonus_for_role(role: String) -> int:
	return PlayerCombatStats.dex_pick_bonus_for_role(role)


static func _rng(authority_seed: int, cell: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(authority_seed) * 1_103_515_245
		^ cell.x * 10_013
		^ cell.y * 79_199
		^ int(salt) * 12_345_679
	)
	return rng


## Deterministic per dungeon seed + cell (stable smoke); DEX from role matches Explorer assigns.
static func roll_evade(authority_seed: int, cell: Vector2i, role: String) -> Dictionary:
	var rng := _rng(authority_seed, cell, 3_791_019_331)
	var d20: int = rng.randi_range(1, 20)
	var bonus: int = dex_bonus_for_role(role)
	var total: int = d20 + bonus
	return {"success": total >= EVADE_DC, "d20": d20, "bonus": bonus, "total": total}


static func format_evade_message(d20: int, bonus: int, total: int, success: bool) -> String:
	if success:
		return (
			"Success! You quickly evade the encounter.\n\n(Rolled "
			+ str(d20)
			+ " + "
			+ str(bonus)
			+ " dexterity = "
			+ str(total)
			+ " vs DC "
			+ str(EVADE_DC)
			+ ")"
		)
	return (
		"Failed! You cannot escape the encounter and must fight.\n\n(Rolled "
		+ str(d20)
		+ " + "
		+ str(bonus)
		+ " dexterity = "
		+ str(total)
		+ " vs DC "
		+ str(EVADE_DC)
		+ ")"
	)
