extends RefCounted

## Explorer `Dungeon.PlayerStats` talents + per-level HP die (`@hit_points_die` d4) for Phase 7 level-up.
## Rolls are **deterministic** from `(authority_seed, peer_id, new_level)` — LiveView used `Enum.random`.

const HIT_POINTS_DIE_SIDES := 4


static func default_talents() -> Dictionary:
	return {"hit_points": 0, "attack": 0, "dexterity": 0}


static func _rng_level_up(
	authority_seed: int, peer_id: int, new_level: int, salt: int
) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(authority_seed)
		^ int(peer_id) * 1_009_033
		^ int(new_level) * 8_008_009
		^ int(salt) * 404_231
		^ 0x4C564C55
	)
	return rng


## Returns `{"branch":int,"bonus":int,"message":String}` branch 1=hp talent, 2=attack, 3=dexterity.
static func roll_random_talent_deterministic(
	authority_seed: int, peer_id: int, new_level: int
) -> Dictionary:
	var rng := _rng_level_up(authority_seed, peer_id, new_level, 1)
	var branch: int = rng.randi_range(1, 3)
	if branch == 1:
		var hit_point_bonus: int = rng.randi_range(1, 4)
		return {
			"branch": 1,
			"bonus": hit_point_bonus,
			"message": "You gained +%d to Maximum Hit Points!" % hit_point_bonus,
		}
	if branch == 2:
		return {"branch": 2, "bonus": 1, "message": "You gained +1 to Attack Bonus!"}
	return {"branch": 3, "bonus": 1, "message": "You gained +1 to Dexterity Bonus!"}


static func roll_level_hit_points_deterministic(
	authority_seed: int, peer_id: int, new_level: int
) -> int:
	var rng := _rng_level_up(authority_seed, peer_id, new_level, 2)
	return rng.randi_range(1, HIT_POINTS_DIE_SIDES)


static func apply_talent_roll_to_dict(talents: Dictionary, roll: Dictionary) -> Dictionary:
	var out := talents.duplicate(true)
	var br: int = int(roll.get("branch", 0))
	var bonus: int = int(roll.get("bonus", 0))
	if br == 1:
		out["hit_points"] = int(out.get("hit_points", 0)) + bonus
	elif br == 2:
		out["attack"] = int(out.get("attack", 0)) + bonus
	elif br == 3:
		out["dexterity"] = int(out.get("dexterity", 0)) + bonus
	return out


## Plain-text level line for the dialog (Explorer markdown stripped for Godot `AcceptDialog`).
static func level_up_primary_message(new_level: int, level_hp_gain: int) -> String:
	return (
		"Level %d Achieved!\n\nCongratulations! You have reached level %d!\n\nYou gained %d hit points from leveling up!"
		% [new_level, new_level, level_hp_gain]
	)


## Second body block (Explorer `talent_gained` assign).
static func format_talent_secondary_message(roll: Dictionary, level_hp_gain: int) -> String:
	var br: int = int(roll.get("branch", 0))
	var bonus: int = int(roll.get("bonus", 0))
	var base_msg: String = str(roll.get("message", ""))
	if br == 1:
		return "Talent: " + base_msg + "\n\nTotal hit points gained: " + str(level_hp_gain + bonus)
	return "Talent: " + base_msg


## Explorer `dismiss_level_up` achievement string (static template).
static func achievement_text_for_level_up(
	new_level: int, level_hp_gain: int, talent_secondary_plain: String
) -> String:
	var t := talent_secondary_plain.strip_edges()
	return (
		"Level %d Achieved!\n\nYou have reached level %d! You gained %d hit points from leveling up! %s"
		% [new_level, new_level, level_hp_gain, t]
	)
