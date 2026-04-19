extends RefCounted

## Full auto-resolve encounter combat (Explorer `CombatSystem` + `Dice` semantics, CSV monsters).

const DungeonDice := preload("res://dungeon/combat/dungeon_dice.gd")
const MonsterTable := preload("res://dungeon/combat/monster_table.gd")
const PlayerCombatStats := preload("res://dungeon/combat/player_combat_stats.gd")


class CombatStream:
	var authority_seed: int
	var cell: Vector2i
	var ctr: int = 0

	func _init(p_seed: int, p_cell: Vector2i) -> void:
		authority_seed = p_seed
		cell = p_cell

	func next_rng() -> RandomNumberGenerator:
		var rng := RandomNumberGenerator.new()
		rng.seed = (
			authority_seed * 1_103_515_245 ^ cell.x * 10_013 ^ cell.y * 79_199 ^ ctr * 12_345_679
		)
		ctr += 1
		return rng

	func roll_nd(n: int, sides: int) -> int:
		var rng := next_rng()
		var t := 0
		for _i in range(n):
			t += rng.randi_range(1, sides)
		return t

	func roll_dice_string(ds: String) -> int:
		return DungeonDice.roll_dice_string(next_rng(), ds)


static func _initiative_log(p_roll: int, m_roll: int, player_first: bool) -> String:
	if player_first:
		return (
			"Initiative: You rolled "
			+ str(p_roll)
			+ ", monster rolled "
			+ str(m_roll)
			+ ". You go first!"
		)
	return (
		"Initiative: You rolled "
		+ str(p_roll)
		+ ", monster rolled "
		+ str(m_roll)
		+ ". Monster goes first!"
	)


static func _lines_to_body(lines: PackedStringArray) -> String:
	var b := String()
	for i in range(lines.size()):
		if i > 0:
			b += "\n"
		b += lines[i]
	return b


static func _finish_victory(
	lines: PackedStringArray,
	stream: CombatStream,
	mon: Dictionary,
	disp_name: String,
	player_hp: int
) -> Dictionary:
	lines.append(disp_name + " is defeated!")
	var treasure_raw: String = str(mon.get("treasure", "")).strip_edges()
	var treasure_gold := 0
	if not treasure_raw.is_empty():
		treasure_gold = stream.roll_dice_string(treasure_raw)
	var max_m: int = maxi(1, int(mon.get("max_hit_points", int(mon.get("hit_points", 1)))))
	var xp_gain: int = max_m + treasure_gold
	return {
		"victory": true,
		"title": "Victory",
		"body": _lines_to_body(lines),
		"player_hp_end": player_hp,
		"tile_replacement": "pile_of_bones",
		"treasure_gold": treasure_gold,
		"xp_gain": xp_gain,
		"monster_display_name": disp_name,
		"monster_name_key": str(mon.get("name", "")).strip_edges(),
	}


static func _finish_defeat(lines: PackedStringArray, disp_name: String) -> Dictionary:
	lines.append("You have been defeated!")
	return {
		"victory": false,
		"title": "Defeat",
		"body": _lines_to_body(lines),
		"player_hp_end": 0,
		"tile_replacement": "restore_floor",
		"treasure_gold": 0,
		"xp_gain": 0,
		"monster_display_name": disp_name,
	}


static func simulate_encounter_fight(
	authority_seed: int, cell: Vector2i, monster_name: String, player_role: String = "rogue"
) -> Dictionary:
	var lines: PackedStringArray = []
	var stream := CombatStream.new(authority_seed, cell)
	var mon: Dictionary = MonsterTable.instance_from_name(monster_name)
	var disp_name: String = (
		str(mon.get("name", monster_name)) if not mon.is_empty() else monster_name
	)
	if mon.is_empty():
		lines.append("Unknown creature '" + monster_name + "' — using Rat stats from table.")
		mon = MonsterTable.instance_from_name("Rat")
		disp_name = str(mon.get("name", "Rat"))

	var monster_hp: int = int(mon.get("current_hit_points", 1))
	var monster_ac: int = int(mon.get("armor_class", 10))
	var m_atk: int = int(mon.get("attack_bonus", 0))
	var m_dice: String = str(mon.get("damage_dice", "1d4"))
	var m_weapon: String = str(mon.get("weapon", "Attack"))

	var pst: Dictionary = PlayerCombatStats.for_role(player_role)
	var player_hp: int = int(pst.get("hit_points", PlayerCombatStats.BASE_PLAYER_HIT_POINTS))
	var player_ac: int = int(pst.get("armor_class", PlayerCombatStats.BASE_ARMOR_CLASS))
	var atk_b: int = int(pst.get("attack_bonus", PlayerCombatStats.BASE_ATTACK_BONUS))
	var wpn: String = str(pst.get("player_weapon", PlayerCombatStats.BASE_PLAYER_WEAPON))
	var w_dice: String = str(
		pst.get("weapon_damage_dice", PlayerCombatStats.BASE_WEAPON_DAMAGE_DICE)
	)

	var surprise: int = stream.roll_nd(1, 6)
	if surprise <= 2:
		lines.append(
			(
				"Surprise! You catch the "
				+ disp_name
				+ " off guard! (Rolled "
				+ str(surprise)
				+ " on d6)"
			)
		)
		var rng_bs1 := stream.next_rng()
		var r1: int = rng_bs1.randi_range(1, 20)
		var rng_bs2 := stream.next_rng()
		var r2: int = rng_bs2.randi_range(1, 20)
		var best: int = maxi(r1, r2)
		var tot: int = best + atk_b
		if tot >= monster_ac:
			var d1: int = stream.roll_dice_string(w_dice)
			var d2: int = stream.roll_dice_string(w_dice)
			var td: int = d1 + d2
			monster_hp = maxi(0, monster_hp - td)
			lines.append(
				(
					"BACKSTAB! Backstab with advantage! Rolled "
					+ str(r1)
					+ " and "
					+ str(r2)
					+ ", taking "
					+ str(best)
					+ " + "
					+ str(atk_b)
					+ " = "
					+ str(tot)
					+ " vs AC "
					+ str(monster_ac)
					+ ". HIT for "
					+ str(td)
					+ " damage! ("
					+ str(d1)
					+ " + "
					+ str(d2)
					+ ")"
				)
			)
		else:
			lines.append(
				(
					"BACKSTAB ATTEMPT! Backstab with advantage! Rolled "
					+ str(r1)
					+ " and "
					+ str(r2)
					+ ", taking "
					+ str(best)
					+ " + "
					+ str(atk_b)
					+ " = "
					+ str(tot)
					+ " vs AC "
					+ str(monster_ac)
					+ ". MISS!"
				)
			)
		if monster_hp <= 0:
			return _finish_victory(lines, stream, mon, disp_name, player_hp)
		lines.append("The element of surprise is lost! Rolling for initiative...")
	else:
		lines.append(
			(
				"No surprise. The "
				+ disp_name
				+ " notices your approach. (Rolled "
				+ str(surprise)
				+ " on d6)"
			)
		)

	var fight_round: int = 1
	var safety := 0
	while player_hp > 0 and monster_hp > 0:
		safety += 1
		if safety > 500:
			lines.append("Combat aborted (round cap).")
			return {
				"victory": false,
				"title": "Combat",
				"body": _lines_to_body(lines),
				"player_hp_end": player_hp,
				"tile_replacement": "",
				"treasure_gold": 0,
				"xp_gain": 0,
				"monster_display_name": disp_name,
			}

		lines.append("— Round " + str(fight_round) + " —")
		var p_ini := stream.roll_nd(1, 6)
		var m_ini := stream.roll_nd(1, 6)
		var player_first2: bool = p_ini >= m_ini
		lines.append(_initiative_log(p_ini, m_ini, player_first2))

		var turn_order: Array[String] = []
		if player_first2:
			turn_order.assign(["player", "monster"])
		else:
			turn_order.assign(["monster", "player"])

		for who in turn_order:
			if player_hp <= 0 or monster_hp <= 0:
				break
			if who == "player":
				var rng_pa := stream.next_rng()
				var ar: int = rng_pa.randi_range(1, 20)
				var tat: int = ar + atk_b
				if tat >= monster_ac:
					var dmg: int = stream.roll_dice_string(w_dice)
					monster_hp = maxi(0, monster_hp - dmg)
					lines.append(
						(
							"Player attacks with "
							+ wpn
							+ "! Rolled "
							+ str(ar)
							+ " + "
							+ str(atk_b)
							+ " = "
							+ str(tat)
							+ " vs AC "
							+ str(monster_ac)
							+ ". HIT for "
							+ str(dmg)
							+ " damage!"
						)
					)
				else:
					lines.append(
						(
							"Player attacks with "
							+ wpn
							+ "! Rolled "
							+ str(ar)
							+ " + "
							+ str(atk_b)
							+ " = "
							+ str(tat)
							+ " vs AC "
							+ str(monster_ac)
							+ ". MISS!"
						)
					)
				if monster_hp <= 0:
					return _finish_victory(lines, stream, mon, disp_name, player_hp)
			else:
				var rng_ma := stream.next_rng()
				var mr: int = rng_ma.randi_range(1, 20)
				var mtot: int = mr + m_atk
				if mtot >= player_ac:
					var mdmg: int = stream.roll_dice_string(m_dice)
					player_hp = maxi(0, player_hp - mdmg)
					lines.append(
						(
							disp_name
							+ " attacks with "
							+ m_weapon
							+ "! Rolled "
							+ str(mr)
							+ " + "
							+ str(m_atk)
							+ " = "
							+ str(mtot)
							+ " vs AC "
							+ str(player_ac)
							+ ". HIT for "
							+ str(mdmg)
							+ " damage!"
						)
					)
				else:
					lines.append(
						(
							disp_name
							+ " attacks with "
							+ m_weapon
							+ "! Rolled "
							+ str(mr)
							+ " + "
							+ str(m_atk)
							+ " = "
							+ str(mtot)
							+ " vs AC "
							+ str(player_ac)
							+ ". MISS!"
						)
					)
				if player_hp <= 0:
					return _finish_defeat(lines, disp_name)

		fight_round += 1

	if player_hp <= 0:
		return _finish_defeat(lines, disp_name)
	return _finish_victory(lines, stream, mon, disp_name, player_hp)


## Phase 6: Explorer-shaped **interactive** combat (player Attack advances; server resolves monster + rounds).
class InteractiveCombatSession:
	extends RefCounted
	const _MonsterTable := preload("res://dungeon/combat/monster_table.gd")
	const _PlayerCombatStats := preload("res://dungeon/combat/player_combat_stats.gd")
	const _EncounterSys := preload("res://dungeon/encounter/encounter_system.gd")

	var stream: CombatStream
	var cell: Vector2i
	var mon: Dictionary = {}
	var disp_name: String = ""
	var monster_hp: int = 0
	var monster_ac: int = 10
	var monster_max_hp: int = 1
	var m_atk: int = 0
	var m_dice: String = "1d4"
	var m_weapon: String = "Attack"
	var player_hp: int = 0
	var player_ac: int = 10
	var atk_b: int = 0
	var wpn: String = ""
	var w_dice: String = "1d4"
	var player_role: String = "rogue"
	var monster_name_key: String = ""

	var surprise_attack_available: bool = false
	var awaiting_surprise_action: bool = false
	var combat_round: int = 0
	var current_turn: String = "player"
	var awaiting_player: bool = true
	var player_has_acted: bool = false
	var monster_has_acted: bool = false
	var finished: bool = false
	var victory: bool = false
	var log_lines: PackedStringArray = []
	var _sfx_events: PackedStringArray = []
	var _treasure_gold: int = 0
	var _xp_gain: int = 0
	var _tile_rep: String = ""
	var _safety_rounds: int = 0
	var _flee_success: bool = false

	func _init() -> void:
		pass

	func _append(line: String) -> void:
		log_lines.append(line)

	func _title_for_ui() -> String:
		if awaiting_surprise_action and surprise_attack_available:
			return "Surprise Attack!"
		if combat_round > 0:
			return "Combat Round %d" % combat_round
		return "Combat"

	func _lines_to_body_local(lines: PackedStringArray) -> String:
		var b := String()
		for i in range(lines.size()):
			if i > 0:
				b += "\n"
			b += lines[i]
		return b

	func _initiative_log_local(p_roll: int, m_roll: int, player_first: bool) -> String:
		if player_first:
			return (
				"Initiative: You rolled "
				+ str(p_roll)
				+ ", monster rolled "
				+ str(m_roll)
				+ ". You go first!"
			)
		return (
			"Initiative: You rolled "
			+ str(p_roll)
			+ ", monster rolled "
			+ str(m_roll)
			+ ". Monster goes first!"
		)

	func _snapshot() -> Dictionary:
		var sfx_arr: Array = []
		for i in range(_sfx_events.size()):
			sfx_arr.append(_sfx_events[i])
		return {
			"title": _title_for_ui(),
			"log_full": _lines_to_body_local(log_lines),
			"player_hp": player_hp,
			"monster_hp": monster_hp,
			"monster_max_hp": monster_max_hp,
			"monster_display": disp_name,
			"awaiting_player": awaiting_player and not finished,
			"can_attack":
			(
				awaiting_player
				and not finished
				and (surprise_attack_available or current_turn == "player")
			),
			"can_flee": awaiting_player and not finished,
			"finished": finished,
			"victory": victory,
			"flee_success": _flee_success,
			"surprise_attack": surprise_attack_available and awaiting_surprise_action,
			"sfx_events": sfx_arr,
		}

	func _setup_monster(monster_name: String) -> void:
		mon = _MonsterTable.instance_from_name(monster_name)
		disp_name = str(mon.get("name", monster_name)) if not mon.is_empty() else monster_name
		if mon.is_empty():
			_append("Unknown creature '" + monster_name + "' — using Rat stats from table.")
			mon = _MonsterTable.instance_from_name("Rat")
			disp_name = str(mon.get("name", "Rat"))
		monster_hp = int(mon.get("current_hit_points", 1))
		monster_max_hp = int(mon.get("max_hit_points", monster_hp))
		monster_ac = int(mon.get("armor_class", 10))
		m_atk = int(mon.get("attack_bonus", 0))
		m_dice = str(mon.get("damage_dice", "1d4"))
		m_weapon = str(mon.get("weapon", "Attack"))

	func _init_opening(
		authority_seed: int,
		p_cell: Vector2i,
		monster_name: String,
		start_player_hp: int,
		p_role: String,
		stat_line: Dictionary = {}
	) -> void:
		stream = CombatStream.new(authority_seed, p_cell)
		cell = p_cell
		player_role = p_role.strip_edges().to_lower() if not p_role.is_empty() else "rogue"
		monster_name_key = monster_name.strip_edges()
		finished = false
		victory = false
		_flee_success = false
		_treasure_gold = 0
		_xp_gain = 0
		_tile_rep = ""
		log_lines.clear()
		var pst: Dictionary = _PlayerCombatStats.for_role(player_role)
		if not stat_line.is_empty():
			if stat_line.has("max_hit_points"):
				pst["max_hit_points"] = int(stat_line["max_hit_points"])
			if stat_line.has("armor_class"):
				pst["armor_class"] = int(stat_line["armor_class"])
			if stat_line.has("attack_bonus"):
				pst["attack_bonus"] = int(stat_line["attack_bonus"])
			var pw := str(stat_line.get("player_weapon", "")).strip_edges()
			if not pw.is_empty():
				pst["player_weapon"] = pw
			var wd := str(stat_line.get("weapon_damage_dice", "")).strip_edges()
			if not wd.is_empty():
				pst["weapon_damage_dice"] = wd
		var cap: int = int(pst.get("max_hit_points", _PlayerCombatStats.BASE_MAX_HIT_POINTS))
		player_hp = clampi(start_player_hp, 0, cap)
		player_ac = int(pst.get("armor_class", _PlayerCombatStats.BASE_ARMOR_CLASS))
		atk_b = int(pst.get("attack_bonus", _PlayerCombatStats.BASE_ATTACK_BONUS))
		wpn = str(pst.get("player_weapon", _PlayerCombatStats.BASE_PLAYER_WEAPON))
		w_dice = str(pst.get("weapon_damage_dice", _PlayerCombatStats.BASE_WEAPON_DAMAGE_DICE))
		_setup_monster(monster_name)
		var surprise: int = stream.roll_nd(1, 6)
		if surprise <= 2:
			_append(
				(
					"Surprise! You catch the "
					+ disp_name
					+ " off guard! (Rolled "
					+ str(surprise)
					+ " on d6)"
				)
			)
			surprise_attack_available = true
			awaiting_surprise_action = true
			combat_round = 0
			awaiting_player = true
		else:
			_append(
				(
					"No surprise. The "
					+ disp_name
					+ " notices your approach. (Rolled "
					+ str(surprise)
					+ " on d6)"
				)
			)
			surprise_attack_available = false
			awaiting_surprise_action = false
			_open_round_one_from_initiative()

	func _open_round_one_from_initiative() -> void:
		combat_round = 1
		player_has_acted = false
		monster_has_acted = false
		_append("— Round " + str(combat_round) + " —")
		var p_ini := stream.roll_nd(1, 6)
		var m_ini := stream.roll_nd(1, 6)
		var player_first: bool = p_ini >= m_ini
		_append(_initiative_log_local(p_ini, m_ini, player_first))
		current_turn = "player" if player_first else "monster"
		awaiting_player = current_turn == "player"
		if current_turn == "monster":
			_monster_attack_turn()

	func _finish_victory_session() -> void:
		finished = true
		victory = true
		_flee_success = false
		log_lines.append(disp_name + " is defeated!")
		var treasure_raw: String = str(mon.get("treasure", "")).strip_edges()
		_treasure_gold = 0
		if not treasure_raw.is_empty():
			_treasure_gold = stream.roll_dice_string(treasure_raw)
		var max_m: int = maxi(1, int(mon.get("max_hit_points", int(mon.get("hit_points", 1)))))
		_xp_gain = max_m + _treasure_gold
		_tile_rep = "pile_of_bones"

	func _finish_defeat_session(defeat_line: String = "You have been defeated!") -> void:
		finished = true
		victory = false
		_flee_success = false
		_append(defeat_line)
		_tile_rep = "restore_floor"

	func _finish_flee_success_session(evade_msg: String) -> void:
		finished = true
		victory = false
		_flee_success = true
		_xp_gain = _EncounterSys.EVADE_XP
		_treasure_gold = 0
		_tile_rep = "flee_clear_encounter"
		_append(evade_msg)

	func _flee_free_monster_attack() -> void:
		var rng_ma := stream.next_rng()
		var mr: int = rng_ma.randi_range(1, 20)
		var mtot: int = mr + m_atk
		if mtot >= player_ac:
			var mdmg: int = stream.roll_dice_string(m_dice)
			player_hp = maxi(0, player_hp - mdmg)
			_append(
				(
					"You attempt to flee! "
					+ disp_name
					+ " gets a free attack with "
					+ m_weapon
					+ "! Rolled "
					+ str(mr)
					+ " + "
					+ str(m_atk)
					+ " = "
					+ str(mtot)
					+ " vs AC "
					+ str(player_ac)
					+ ". HIT for "
					+ str(mdmg)
					+ " damage!"
				)
			)
			_sfx_events.append("monster_hit")
		else:
			_append(
				(
					"You attempt to flee! "
					+ disp_name
					+ " gets a free attack with "
					+ m_weapon
					+ "! Rolled "
					+ str(mr)
					+ " + "
					+ str(m_atk)
					+ " = "
					+ str(mtot)
					+ " vs AC "
					+ str(player_ac)
					+ ". MISS!"
				)
			)
			_sfx_events.append("monster_miss")

	func _monster_attack_turn() -> void:
		var rng_ma := stream.next_rng()
		var mr: int = rng_ma.randi_range(1, 20)
		var mtot: int = mr + m_atk
		if mtot >= player_ac:
			var mdmg: int = stream.roll_dice_string(m_dice)
			player_hp = maxi(0, player_hp - mdmg)
			_append(
				(
					disp_name
					+ " attacks with "
					+ m_weapon
					+ "! Rolled "
					+ str(mr)
					+ " + "
					+ str(m_atk)
					+ " = "
					+ str(mtot)
					+ " vs AC "
					+ str(player_ac)
					+ ". HIT for "
					+ str(mdmg)
					+ " damage!"
				)
			)
			_sfx_events.append("monster_hit")
		else:
			_append(
				(
					disp_name
					+ " attacks with "
					+ m_weapon
					+ "! Rolled "
					+ str(mr)
					+ " + "
					+ str(m_atk)
					+ " = "
					+ str(mtot)
					+ " vs AC "
					+ str(player_ac)
					+ ". MISS!"
				)
			)
			_sfx_events.append("monster_miss")
		monster_has_acted = true
		if player_hp <= 0:
			_finish_defeat_session()
			return
		if player_has_acted:
			_maybe_advance_round()
		else:
			current_turn = "player"
			awaiting_player = true

	func _player_normal_attack() -> void:
		var rng_pa := stream.next_rng()
		var ar: int = rng_pa.randi_range(1, 20)
		var tat: int = ar + atk_b
		if tat >= monster_ac:
			var dmg: int = stream.roll_dice_string(w_dice)
			monster_hp = maxi(0, monster_hp - dmg)
			_append(
				(
					"Player attacks with "
					+ wpn
					+ "! Rolled "
					+ str(ar)
					+ " + "
					+ str(atk_b)
					+ " = "
					+ str(tat)
					+ " vs AC "
					+ str(monster_ac)
					+ ". HIT for "
					+ str(dmg)
					+ " damage!"
				)
			)
			_sfx_events.append("player_hit")
		else:
			_append(
				(
					"Player attacks with "
					+ wpn
					+ "! Rolled "
					+ str(ar)
					+ " + "
					+ str(atk_b)
					+ " = "
					+ str(tat)
					+ " vs AC "
					+ str(monster_ac)
					+ ". MISS!"
				)
			)
			_sfx_events.append("player_miss")
		player_has_acted = true
		if monster_hp <= 0:
			_finish_victory_session()
			return
		current_turn = "monster"
		awaiting_player = false
		_monster_attack_turn()

	func _surprise_backstab_then_transition() -> void:
		var rng_bs1 := stream.next_rng()
		var r1: int = rng_bs1.randi_range(1, 20)
		var rng_bs2 := stream.next_rng()
		var r2: int = rng_bs2.randi_range(1, 20)
		var best: int = maxi(r1, r2)
		var tot: int = best + atk_b
		if tot >= monster_ac:
			var d1: int = stream.roll_dice_string(w_dice)
			var d2: int = stream.roll_dice_string(w_dice)
			var td: int = d1 + d2
			monster_hp = maxi(0, monster_hp - td)
			_append(
				(
					"BACKSTAB! Backstab with advantage! Rolled "
					+ str(r1)
					+ " and "
					+ str(r2)
					+ ", taking "
					+ str(best)
					+ " + "
					+ str(atk_b)
					+ " = "
					+ str(tot)
					+ " vs AC "
					+ str(monster_ac)
					+ ". HIT for "
					+ str(td)
					+ " damage! ("
					+ str(d1)
					+ " + "
					+ str(d2)
					+ ")"
				)
			)
			_sfx_events.append("player_hit")
		else:
			_append(
				(
					"BACKSTAB ATTEMPT! Backstab with advantage! Rolled "
					+ str(r1)
					+ " and "
					+ str(r2)
					+ ", taking "
					+ str(best)
					+ " + "
					+ str(atk_b)
					+ " = "
					+ str(tot)
					+ " vs AC "
					+ str(monster_ac)
					+ ". MISS!"
				)
			)
			_sfx_events.append("player_miss")
		surprise_attack_available = false
		awaiting_surprise_action = false
		if monster_hp <= 0:
			_finish_victory_session()
			return
		_append("The element of surprise is lost! Rolling for initiative...")
		_open_round_one_from_initiative()

	func _maybe_advance_round() -> void:
		if finished:
			return
		if not (player_has_acted and monster_has_acted):
			return
		_safety_rounds += 1
		if _safety_rounds > 500:
			_append("Combat aborted (round cap).")
			_finish_defeat_session()
			return
		combat_round += 1
		player_has_acted = false
		monster_has_acted = false
		_append("— Round " + str(combat_round) + " —")
		var p_ini := stream.roll_nd(1, 6)
		var m_ini := stream.roll_nd(1, 6)
		var player_first: bool = p_ini >= m_ini
		_append(_initiative_log_local(p_ini, m_ini, player_first))
		current_turn = "player" if player_first else "monster"
		awaiting_player = current_turn == "player"
		if current_turn == "monster":
			_monster_attack_turn()

	func advance_player_attack() -> Dictionary:
		_sfx_events.clear()
		if finished:
			return _snapshot()
		if awaiting_surprise_action and surprise_attack_available:
			_surprise_backstab_then_transition()
			return _snapshot()
		if not awaiting_player or current_turn != "player":
			return _snapshot()
		_player_normal_attack()
		if finished:
			return _snapshot()
		if player_has_acted and monster_has_acted:
			_maybe_advance_round()
		return _snapshot()

	## Explorer `CombatSystem.flee_combat` + `process_flee_evade` (free hit then DC 12 d20+DEX).
	func advance_flee() -> Dictionary:
		_sfx_events.clear()
		if finished:
			return _snapshot()
		if not awaiting_player:
			return _snapshot()
		_flee_free_monster_attack()
		if player_hp <= 0:
			_finish_defeat_session("You have been defeated while trying to flee!")
			return _snapshot()
		var rng_ev := stream.next_rng()
		var ev_d20: int = rng_ev.randi_range(1, 20)
		var dex_b: int = _EncounterSys.dex_bonus_for_role(player_role)
		var ev_tot: int = ev_d20 + dex_b
		var ev_ok: bool = ev_tot >= _EncounterSys.EVADE_DC
		var ev_msg: String
		if ev_ok:
			ev_msg = (
				"Success! You manage to escape from combat.\n\n(Rolled "
				+ str(ev_d20)
				+ " + "
				+ str(dex_b)
				+ " dexterity = "
				+ str(ev_tot)
				+ " vs DC "
				+ str(_EncounterSys.EVADE_DC)
				+ ")"
			)
			_finish_flee_success_session(ev_msg)
		else:
			ev_msg = (
				"Failed! You cannot escape the encounter and must fight.\n\n(Rolled "
				+ str(ev_d20)
				+ " + "
				+ str(dex_b)
				+ " dexterity = "
				+ str(ev_tot)
				+ " vs DC "
				+ str(_EncounterSys.EVADE_DC)
				+ ")"
			)
			_append(ev_msg)
			var kept_hp: int = player_hp
			_init_opening(stream.authority_seed, cell, monster_name_key, kept_hp, player_role, {})
		return _snapshot()

	func build_finish_outcome() -> Dictionary:
		var title_out := "Victory" if victory else ("Escaped" if _flee_success else "Defeat")
		return {
			"victory": victory,
			"flee_success": _flee_success,
			"title": title_out,
			"body": _lines_to_body_local(log_lines),
			"player_hp_end": player_hp,
			"tile_replacement": _tile_rep,
			"treasure_gold": _treasure_gold,
			"xp_gain": _xp_gain,
			"monster_display_name": disp_name,
			"monster_name_key": monster_name_key,
		}


static func create_interactive_combat(
	authority_seed: int,
	cell: Vector2i,
	monster_name: String,
	start_player_hp: int,
	player_role: String = "rogue",
	stat_line: Dictionary = {}
) -> InteractiveCombatSession:
	var s := InteractiveCombatSession.new()
	s._init_opening(authority_seed, cell, monster_name, start_player_hp, player_role, stat_line)
	return s


## Headless / tests: advance until terminal; must match `simulate_encounter_fight` RNG consumption for same clicks.
static func play_interactive_to_end(
	authority_seed: int,
	cell: Vector2i,
	monster_name: String,
	start_player_hp: int,
	player_role: String = "rogue",
	stat_line: Dictionary = {}
) -> Dictionary:
	var s := create_interactive_combat(
		authority_seed, cell, monster_name, start_player_hp, player_role, stat_line
	)
	var guard := 0
	while not s.finished:
		guard += 1
		if guard > 2000:
			break
		s.advance_player_attack()
	return s.build_finish_outcome()
