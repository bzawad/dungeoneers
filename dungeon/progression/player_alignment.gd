extends RefCounted

## Explorer `Dungeon.PlayerStats` alignment: numeric value, `get_alignment_description/1`.

const LAWFUL := "lawful"
const NEUTRAL := "neutral"
const CHAOTIC := "chaotic"


static func starting_alignment() -> int:
	return 0


static func description_from_value(alignment_value: int) -> String:
	if alignment_value > 0:
		return LAWFUL
	if alignment_value < 0:
		return CHAOTIC
	return NEUTRAL


## Lawful NPC vs chaotic player (and reverse) — matches Explorer encounter / hunt checks.
static func npc_hostile_to_player(monster_alignment: String, player_alignment_value: int) -> bool:
	var ma := monster_alignment.strip_edges().to_lower()
	var pd := description_from_value(player_alignment_value)
	return (ma == LAWFUL and pd == CHAOTIC) or (ma == CHAOTIC and pd == LAWFUL)


## Explorer `CombatSystem.handle_npc_or_guard_kill/2` when `guards_hostile` was false before the kill.
## Returns `alignment_delta` (-5 toward chaotic for lawful|neutral victim, else 0), whether to set map **`guards_hostile`** (true for any peaceful npc/guard kill, including chaotic victim), and **`increments_npcs_killed`** (Explorer `npcs_killed_count` assign).
static func npc_or_guard_kill_replication_effects(
	monster_role: String, monster_alignment: String, guards_already_hostile: bool
) -> Dictionary:
	if guards_already_hostile:
		return {
			"alignment_delta": 0,
			"trigger_guards_hostile": false,
			"increments_npcs_killed": false,
		}
	var r := monster_role.strip_edges().to_lower()
	if r != "npc" and r != "guard":
		return {
			"alignment_delta": 0,
			"trigger_guards_hostile": false,
			"increments_npcs_killed": false,
		}
	var ma := monster_alignment.strip_edges().to_lower()
	var delta := 0
	if ma == LAWFUL or ma == NEUTRAL:
		delta = -5
	return {
		"alignment_delta": delta,
		"trigger_guards_hostile": true,
		"increments_npcs_killed": true,
	}
