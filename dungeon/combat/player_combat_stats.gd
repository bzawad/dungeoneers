extends RefCounted

## Mirrors `Dungeon.PlayerStats` base rogue (before equipment / talents).
## **Fighter** is a co-op class slice (Explorer LiveView is single rogue stats); fighter uses martial profile.

const BASE_PLAYER_HIT_POINTS := 4
const BASE_MAX_HIT_POINTS := 4
const BASE_PLAYER_WEAPON := "Dagger"
const BASE_WEAPON_DAMAGE_DICE := "1d4"
const BASE_ATTACK_BONUS := 1
## `armor_class/0` = 10 + @base_armor_bonus + dexterity_bonus(0) = 10 + 1 + 1
const BASE_ARMOR_CLASS := 12

const FIGHTER_PLAYER_HIT_POINTS := 10
const FIGHTER_MAX_HIT_POINTS := 10
const FIGHTER_PLAYER_WEAPON := "Longsword"
const FIGHTER_WEAPON_DAMAGE_DICE := "1d8"
const FIGHTER_ATTACK_BONUS := 3
## Chain/shield-style AC for co-op fighter (distinct from rogue 12).
const FIGHTER_ARMOR_CLASS := 15


static func _norm_role(role: String) -> String:
	return role.strip_edges().to_lower()


## Door lock / trap DEX bonus on d20 (Dungeoneers co-op: fighter +2, rogue +3).
static func dex_pick_bonus_for_role(role: String) -> int:
	if _norm_role(role).contains("fighter"):
		return 2
	return 3


## Base combat row for encounter / combat_resolver (HP = max at fight start unless wounded).
static func for_role(role: String) -> Dictionary:
	if _norm_role(role).contains("fighter"):
		return {
			"hit_points": FIGHTER_PLAYER_HIT_POINTS,
			"max_hit_points": FIGHTER_MAX_HIT_POINTS,
			"attack_bonus": FIGHTER_ATTACK_BONUS,
			"armor_class": FIGHTER_ARMOR_CLASS,
			"player_weapon": FIGHTER_PLAYER_WEAPON,
			"weapon_damage_dice": FIGHTER_WEAPON_DAMAGE_DICE,
		}
	return {
		"hit_points": BASE_PLAYER_HIT_POINTS,
		"max_hit_points": BASE_MAX_HIT_POINTS,
		"attack_bonus": BASE_ATTACK_BONUS,
		"armor_class": BASE_ARMOR_CLASS,
		"player_weapon": BASE_PLAYER_WEAPON,
		"weapon_damage_dice": BASE_WEAPON_DAMAGE_DICE,
	}


static func max_hit_points_for_role(role: String) -> int:
	return int(for_role(role).get("max_hit_points", BASE_MAX_HIT_POINTS))


static func starting_hit_points_for_role(role: String) -> int:
	return int(for_role(role).get("hit_points", BASE_PLAYER_HIT_POINTS))


## Explorer `max_hit_points_with_levels` / talent HP: base role max + rolled level HP + talent HP; AC += talent DEX; attack += talent ATK.
static func for_role_with_progression(
	role: String,
	level_hp_from_rolls: int,
	talent_hp: int,
	talent_attack: int,
	talent_dexterity: int
) -> Dictionary:
	var base := for_role(role)
	var mx0: int = int(base.get("max_hit_points", BASE_MAX_HIT_POINTS))
	var mx: int = mx0 + maxi(0, level_hp_from_rolls) + maxi(0, talent_hp)
	var ac: int = int(base.get("armor_class", BASE_ARMOR_CLASS)) + maxi(0, talent_dexterity)
	var atk: int = int(base.get("attack_bonus", BASE_ATTACK_BONUS)) + maxi(0, talent_attack)
	var out := base.duplicate(true)
	out["max_hit_points"] = mx
	out["armor_class"] = ac
	out["attack_bonus"] = atk
	return out
