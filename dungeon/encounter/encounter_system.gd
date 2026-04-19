extends RefCounted

## Explorer `DungeonWeb.DungeonLive` encounter evade (DC 12 d20+DEX) + combat stub lines from `combat_system.ex` (surprise d6, initiative d6).

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


static func surprise_d6(authority_seed: int, cell: Vector2i) -> int:
	return _rng(authority_seed, cell, 4_814_602_293).randi_range(1, 6)


## Opening lines only (Phase 6 will own full combat loop).
static func stub_combat_opening_text(
	authority_seed: int, cell: Vector2i, monster_name: String
) -> String:
	var s: int = surprise_d6(authority_seed, cell)
	var line1: String
	if s <= 2:
		line1 = (
			"Surprise! You catch the " + monster_name + " off guard! (Rolled " + str(s) + " on d6)"
		)
	else:
		line1 = (
			"No surprise. The "
			+ monster_name
			+ " notices your approach. (Rolled "
			+ str(s)
			+ " on d6)"
		)
	var ini_p: int = _rng(authority_seed, cell, 5_521_009_877).randi_range(1, 6)
	var ini_m: int = _rng(authority_seed, cell, 6_103_300_919).randi_range(1, 6)
	var player_first: bool = ini_p >= ini_m
	var who := "you" if player_first else "the monster"
	var ini_line := (
		"Initiative: you "
		+ str(ini_p)
		+ ", foe "
		+ str(ini_m)
		+ " — "
		+ who
		+ " act first.\n\n(Fight runs full server combat when you choose Fight.)"
	)
	return line1 + "\n\n" + ini_line
