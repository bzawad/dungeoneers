extends RefCounted

## Explorer `Dungeon.Quest` + rumor / NPC quest flows (`QuestItemSystem`, `NpcQuestSystem`).
## Static copy and deterministic tables — no LLM (see ../../../FINAL_TASKS.md, Out of scope).

const DungeonThemes := preload("res://dungeon/generator/dungeon_themes.gd")
const SpecialItemTable := preload("res://dungeon/world/special_item_table.gd")
const MonsterTable := preload("res://dungeon/combat/monster_table.gd")
const PlayerAlignment := preload("res://dungeon/progression/player_alignment.gd")
const GridWalk := preload("res://dungeon/movement/grid_walkability.gd")
const DungeonGrid := preload("res://dungeon/generator/grid.gd")

const QUEST_ITEM_PICK_SALT := 919_000_337


static func stable_quest_id(
	peer_id: int, feature_cell: Vector2i, authority_seed: int, quest_index_for_id: int
) -> String:
	var h: int = hash(
		(
			str(peer_id)
			+ "|"
			+ str(feature_cell.x)
			+ "|"
			+ str(feature_cell.y)
			+ "|"
			+ str(authority_seed)
			+ "|"
			+ str(quest_index_for_id)
		)
	)
	if h == 0:
		h = 1
	return "qi_" + ("%x" % abs(h))


static func _rng_quest(
	authority_seed: int, peer_id: int, cell: Vector2i, salt: int
) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(authority_seed)
		^ peer_id * 50_023
		^ cell.x * 710_273
		^ cell.y * 1_300_337
		^ int(salt) * 97_031
	)
	return rng


static func _theme_names_excluding(exclude: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var ex := exclude.strip_edges()
	for t in DungeonThemes.load_themes():
		if t is Dictionary:
			var nm := str((t as Dictionary).get("name", "")).strip_edges()
			if nm.is_empty() or nm == ex:
				continue
			out.append(nm)
	return out


static func pick_target_theme_deterministic(
	authority_seed: int, peer_id: int, cell: Vector2i, current_theme_name: String
) -> String:
	var pool := _theme_names_excluding(current_theme_name)
	if pool.is_empty():
		for t2 in DungeonThemes.load_themes():
			if t2 is Dictionary:
				var nm2 := str((t2 as Dictionary).get("name", "")).strip_edges()
				if not nm2.is_empty():
					pool.append(nm2)
	if pool.is_empty():
		return current_theme_name
	var names: Array = []
	for i in range(pool.size()):
		names.append(str(pool[i]))
	names.sort()
	var rng := _rng_quest(authority_seed, peer_id, cell, 404_231)
	var idx: int = rng.randi_range(0, names.size() - 1)
	return str(names[idx])


static func create_special_item_quest_from_rumor(
	authority_seed: int,
	peer_id: int,
	feature_cell: Vector2i,
	current_theme_name: String,
	dungeon_level: int,
	quest_index_for_id: int
) -> Dictionary:
	var qid := stable_quest_id(peer_id, feature_cell, authority_seed, quest_index_for_id)
	var target_theme := pick_target_theme_deterministic(
		authority_seed, peer_id, feature_cell, current_theme_name
	)
	var item: Dictionary = SpecialItemTable.pick_deterministic(
		authority_seed, feature_cell, QUEST_ITEM_PICK_SALT + quest_index_for_id
	)
	var key := str(item.get("key", "")).strip_edges()
	var nm := str(item.get("name", "Relic")).strip_edges()
	var base_xp: int = maxi(0, int(item.get("xp_value", 20)))
	var xp_reward: int = base_xp + maxi(1, dungeon_level) * 5
	var reward_gold: int = maxi(0, int(item.get("gold_value", 0)))
	var desc := "Find the " + nm + " in the " + target_theme
	return {
		"id": qid,
		"type": "special_item",
		"status": "active",
		"description": desc,
		"tldr_description": desc,
		"target_theme": target_theme,
		"magic_item_key": key,
		"magic_item_name": nm,
		"xp_reward": xp_reward,
		"reward_gold": reward_gold,
	}


## Explorer `DescriptionService.get_investigation_fallback(:rumor, …)` (LLM off), plain text.
static func rumor_fallback_body_for_quest(quest: Dictionary) -> String:
	var nm := str(quest.get("magic_item_name", "")).strip_edges()
	var tt := str(quest.get("target_theme", "")).strip_edges()
	if nm.is_empty():
		var k0 := str(quest.get("magic_item_key", "")).strip_edges()
		if not k0.is_empty():
			var lk: Dictionary = SpecialItemTable.lookup_by_key(k0)
			nm = str(lk.get("name", "")).strip_edges()
	if nm.is_empty():
		nm = "mysterious artifact"
	if tt.is_empty():
		tt = "distant lands"
	var key := str(quest.get("magic_item_key", "")).strip_edges()
	var item: Dictionary = SpecialItemTable.lookup_by_key(key) if not key.is_empty() else {}
	var cat := str(item.get("category", "")).strip_edges()
	if cat.is_empty():
		cat = "artifact"
	var headline := "Quest Discovered: Find " + nm + " of " + tt
	var body := (
		"Legend speaks of a powerful "
		+ nm
		+ " hidden somewhere in the "
		+ tt
		+ ". Ancient texts suggest that this "
		+ cat
		+ " possesses remarkable properties and would be invaluable to any adventurer brave enough to seek it out. The tales are vague on its exact location, but they all agree: the "
		+ nm
		+ " awaits discovery by a worthy explorer."
	)
	return headline + "\n\n" + body


static func format_rumor_note(pool_flavor: String, quest: Dictionary) -> String:
	var pool := pool_flavor.strip_edges()
	var block := rumor_fallback_body_for_quest(quest)
	if pool.is_empty():
		return block
	return pool + "\n\n" + block


static func should_spawn_quest_item_on_map(quest: Dictionary, map_theme_name: String) -> bool:
	if str(quest.get("type", "")) != "special_item":
		return false
	if str(quest.get("status", "")) != "active":
		return false
	return str(quest.get("target_theme", "")).strip_edges() == map_theme_name.strip_edges()


static func find_quest_item_placement(
	grid: Dictionary, authority_seed: int, quest_id: String
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var c := Vector2i(x, y)
			var t: String = GridWalk.tile_at(grid, c)
			if t != "floor" and t != "corridor":
				continue
			candidates.append(c)
	if candidates.is_empty():
		return Vector2i(-1, -1)
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash(quest_id + "|" + str(authority_seed)))
	var pick: int = rng.randi_range(0, candidates.size() - 1)
	return candidates[pick]


static func quest_item_tile(quest_id: String) -> String:
	return "quest_item|" + quest_id


static func parse_quest_id_from_tile(raw: String) -> String:
	if not raw.begins_with("quest_item|"):
		return ""
	return raw.substr("quest_item|".length()).strip_edges()


static func find_quest_by_id(quests: Array, qid: String) -> Dictionary:
	for q in quests:
		if q is Dictionary and str((q as Dictionary).get("id", "")) == qid:
			return (q as Dictionary).duplicate(true)
	return {}


static func mark_quest_completed_in_list(quests: Array, qid: String) -> void:
	for i in range(quests.size()):
		var q: Dictionary = quests[i] as Dictionary
		if str(q.get("id", "")) == qid:
			q["status"] = "completed"
			quests[i] = q
			return


static func filter_rumors_after_special_quest_complete(rumors: Array, quest: Dictionary) -> Array:
	var nm: String = str(quest.get("magic_item_name", "")).strip_edges()
	var tt: String = str(quest.get("target_theme", "")).strip_edges()
	if nm.is_empty() or tt.is_empty():
		return rumors.duplicate()
	var out: Array = []
	for r in rumors:
		var s := str(r)
		if s.find(nm) != -1 and s.find(tt) != -1:
			continue
		out.append(r)
	return out


## Explorer `map_template.ex` quest completed dialog + `Quest.complete_quest/2` completion line.
static func completion_dialog_body(quest: Dictionary, dungeon_level: int) -> String:
	var nm := str(quest.get("magic_item_name", "")).strip_edges()
	var key := str(quest.get("magic_item_key", "")).strip_edges()
	if nm.is_empty() and not key.is_empty():
		var lk: Dictionary = SpecialItemTable.lookup_by_key(key)
		nm = str(lk.get("name", "")).strip_edges()
	if nm.is_empty():
		nm = "mysterious item"
	var tt := str(quest.get("target_theme", "")).strip_edges()
	if tt.is_empty():
		tt = "distant halls"
	var xp: int = maxi(0, int(quest.get("xp_reward", 0)))
	var tldr := "You found " + nm + " of " + tt + "! The rumor was true!"
	var xp_line := "You also received " + str(xp) + " XP!"
	var narrative := (
		"Your quest for the "
		+ nm
		+ " has been completed successfully on level "
		+ str(dungeon_level)
		+ "!"
	)
	return tldr + "\n\n" + xp_line + "\n\n" + narrative


static func serialize_quests_for_rpc(quests: Array) -> PackedStringArray:
	var pack := PackedStringArray()
	for q in quests:
		if q is Dictionary:
			pack.append(JSON.stringify(q as Dictionary))
	return pack


static func deserialize_quests_from_rpc(pack: PackedStringArray) -> Array:
	var out: Array = []
	for i in range(pack.size()):
		var v: Variant = JSON.parse_string(str(pack[i]))
		if v is Dictionary:
			out.append((v as Dictionary).duplicate(true))
	return out


static func stable_npc_quest_id(
	peer_id: int, encounter_cell: Vector2i, authority_seed: int, salt: int
) -> String:
	var h: int = hash(
		(
			"npcq|"
			+ str(peer_id)
			+ "|"
			+ str(encounter_cell.x)
			+ "|"
			+ str(encounter_cell.y)
			+ "|"
			+ str(authority_seed)
			+ "|"
			+ str(salt)
		)
	)
	if h == 0:
		h = 1
	return "qnk_" + ("%x" % abs(h))


static func calculate_quest_reward_gold_deterministic(
	authority_seed: int, peer_id: int, cell: Vector2i, dungeon_level: int
) -> int:
	var rng := _rng_quest(authority_seed, peer_id, cell, 707_707)
	var roll10: int = rng.randi_range(1, 10)
	return 10 + maxi(1, dungeon_level) * 5 + roll10


## Explorer `dungeon_live.ex` `dismiss_quest_completed` achievement_text (static; no LLM).
static func achievement_text_for_completed_quest(quest: Dictionary) -> String:
	var tldr_h := str(quest.get("tldr_description", "")).strip_edges()
	if tldr_h.is_empty():
		tldr_h = str(quest.get("description", "")).strip_edges()
	var typ := str(quest.get("type", "")).strip_edges()
	if typ == "special_item":
		var key_si := str(quest.get("magic_item_key", "")).strip_edges()
		var item_si: Dictionary = {}
		if not key_si.is_empty():
			item_si = SpecialItemTable.lookup_by_key(key_si)
		var magic_item_name := str(quest.get("magic_item_name", "")).strip_edges()
		if magic_item_name.is_empty():
			magic_item_name = str(item_si.get("name", "")).strip_edges()
		if magic_item_name.is_empty():
			magic_item_name = "mysterious item"
		var magic_item_category := str(item_si.get("category", "")).strip_edges()
		if magic_item_category.is_empty():
			magic_item_category = "artifact"
		var tt_si := str(quest.get("target_theme", "")).strip_edges()
		var xp_si: int = maxi(0, int(quest.get("xp_reward", 0)))
		return (
			"Quest Completed: "
			+ tldr_h
			+ "\n\nYou successfully found the "
			+ magic_item_name
			+ " in the "
			+ tt_si
			+ "! This legendary "
			+ magic_item_category
			+ " was worth "
			+ str(xp_si)
			+ " XP."
		)
	if typ == "npc_kill":
		var tgt_npc := str(quest.get("target_npc", "")).strip_edges()
		var tt_n := str(quest.get("target_theme", "")).strip_edges()
		var qg_n := str(quest.get("quest_giver", "")).strip_edges()
		var rg_n: int = maxi(0, int(quest.get("reward_gold", 0)))
		var xp_n: int = maxi(0, int(quest.get("xp_reward", rg_n)))
		return (
			"Quest Completed: "
			+ tldr_h
			+ "\n\nYou successfully eliminated the "
			+ tgt_npc
			+ " in the "
			+ tt_n
			+ "! "
			+ qg_n
			+ " will be pleased with your work. You earned "
			+ str(rg_n)
			+ " gold and "
			+ str(xp_n)
			+ " XP."
		)
	if typ == "monster_kill":
		var tgt_m := str(quest.get("target_monster", "")).strip_edges()
		var tt_m := str(quest.get("target_theme", "")).strip_edges()
		var qg_m := str(quest.get("quest_giver", "")).strip_edges()
		var rg_m: int = maxi(0, int(quest.get("reward_gold", 0)))
		var xp_m: int = maxi(0, int(quest.get("xp_reward", rg_m)))
		return (
			"Quest Completed: "
			+ tldr_h
			+ "\n\nYou successfully defeated the "
			+ tgt_m
			+ " in the "
			+ tt_m
			+ "! "
			+ qg_m
			+ " will be grateful for your heroic deed. You earned "
			+ str(rg_m)
			+ " gold and "
			+ str(xp_m)
			+ " XP."
		)
	var xp_d: int = maxi(0, int(quest.get("xp_reward", 0)))
	return (
		"Quest Completed: "
		+ tldr_h
		+ "\n\nYour quest has been completed successfully! You earned "
		+ str(xp_d)
		+ " XP."
	)


static func kill_quest_rumor_line(quest: Dictionary) -> String:
	var giver := str(quest.get("quest_giver", "Unknown")).strip_edges()
	var tldr := str(quest.get("tldr_description", "")).strip_edges()
	return "Quest from " + giver + ": " + tldr


static func filter_rumors_kill_quest_exact(rumors: Array, quest: Dictionary) -> Array:
	var line := kill_quest_rumor_line(quest)
	var out: Array = []
	for r in rumors:
		if str(r) == line:
			continue
		out.append(r)
	return out


static func _pick_chaotic_kill_target_name(
	dungeon_level: int, rng: RandomNumberGenerator
) -> String:
	var cap_cr: int = clampi(dungeon_level + 4, 2, 12)
	var pool: Array[String] = []
	for rec in MonsterTable.all_monsters():
		if not rec is Dictionary:
			continue
		var d: Dictionary = rec as Dictionary
		if str(d.get("alignment", "")).strip_edges().to_lower() != "chaotic":
			continue
		var role := str(d.get("role", "")).strip_edges().to_lower()
		if role == "npc" or role == "guard":
			continue
		if int(d.get("challenge_rating", 99)) > cap_cr:
			continue
		var nm := str(d.get("name", "")).strip_edges()
		if not nm.is_empty():
			pool.append(nm)
	if pool.is_empty():
		return "Goblin"
	pool.sort()
	return pool[rng.randi_range(0, pool.size() - 1)]


static func _pick_lawful_npc_target_name(rng: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	for rec in MonsterTable.all_monsters():
		if not rec is Dictionary:
			continue
		var d: Dictionary = rec as Dictionary
		if str(d.get("role", "")).strip_edges().to_lower() != "npc":
			continue
		if str(d.get("alignment", "")).strip_edges().to_lower() != "lawful":
			continue
		var nm := str(d.get("name", "")).strip_edges()
		if not nm.is_empty():
			pool.append(nm)
	if pool.is_empty():
		return "Merchant"
	pool.sort()
	return pool[rng.randi_range(0, pool.size() - 1)]


## Explorer `Dungeon.Quest.create_npc_quest/4` — returns empty if giver refuses (alignment enemies).
static func create_npc_kill_quest_dict(
	authority_seed: int,
	peer_id: int,
	encounter_cell: Vector2i,
	giver_monster_name: String,
	giver_alignment: String,
	player_alignment_value: int,
	current_theme_name: String,
	dungeon_level: int,
	quest_salt: int
) -> Dictionary:
	var ga := giver_alignment.strip_edges().to_lower()
	var pd := PlayerAlignment.description_from_value(player_alignment_value)
	var rng := _rng_quest(authority_seed, peer_id, encounter_cell, 500_000 + quest_salt)
	var reward := calculate_quest_reward_gold_deterministic(
		authority_seed, peer_id, encounter_cell, dungeon_level
	)
	var target_theme := pick_target_theme_deterministic(
		authority_seed, peer_id, encounter_cell, current_theme_name
	)
	var qid := stable_npc_quest_id(peer_id, encounter_cell, authority_seed, quest_salt)
	if ga == "lawful":
		if pd == "chaotic":
			return {}
		var tgt := _pick_chaotic_kill_target_name(dungeon_level, rng)
		var tldr := "Kill " + tgt + " in " + target_theme
		return {
			"id": qid,
			"type": "monster_kill",
			"status": "active",
			"description":
			(
				"Slay the "
				+ tgt
				+ " that terrorizes the "
				+ target_theme
				+ ". Reward: "
				+ str(reward)
				+ " gold."
			),
			"target_theme": target_theme,
			"reward_gold": reward,
			"xp_reward": reward,
			"quest_giver": giver_monster_name,
			"quest_giver_theme": current_theme_name,
			"quest_alignment": "lawful",
			"target_monster": tgt,
			"target_npc": "",
			"tldr_description": tldr,
			"quest_source": "npc",
		}
	if ga == "chaotic":
		if pd == "lawful":
			return {}
		var tgt_npc := _pick_lawful_npc_target_name(rng)
		var tldr2 := "Kill " + tgt_npc + " in " + target_theme
		return {
			"id": qid,
			"type": "npc_kill",
			"status": "active",
			"description":
			(
				"Eliminate the "
				+ tgt_npc
				+ " who opposes our cause in the "
				+ target_theme
				+ ". Reward: "
				+ str(reward)
				+ " gold."
			),
			"target_theme": target_theme,
			"reward_gold": reward,
			"xp_reward": reward,
			"quest_giver": giver_monster_name,
			"quest_giver_theme": current_theme_name,
			"quest_alignment": "chaotic",
			"target_monster": "",
			"target_npc": tgt_npc,
			"tldr_description": tldr2,
			"quest_source": "npc",
		}
	## Neutral giver → monster_kill for all alignments (Explorer `create_monster_kill_quest`).
	var tgt_n := _pick_chaotic_kill_target_name(dungeon_level, rng)
	var tldr_n := "Kill " + tgt_n + " in " + target_theme
	return {
		"id": qid,
		"type": "monster_kill",
		"status": "active",
		"description":
		(
			"Slay the "
			+ tgt_n
			+ " that terrorizes the "
			+ target_theme
			+ ". Reward: "
			+ str(reward)
			+ " gold."
		),
		"target_theme": target_theme,
		"reward_gold": reward,
		"xp_reward": reward,
		"quest_giver": giver_monster_name,
		"quest_giver_theme": current_theme_name,
		"quest_alignment": "lawful",
		"target_monster": tgt_n,
		"target_npc": "",
		"tldr_description": tldr_n,
		"quest_source": "npc",
	}


## Explorer `NpcQuestSystem.get_quest_data_for_monster` — `result` is offer | chat | close.
static func try_build_npc_quest_offer_payload(
	quests: Array,
	giver_monster_name: String,
	giver_alignment: String,
	player_alignment_value: int,
	current_theme_name: String,
	dungeon_level: int,
	authority_seed: int,
	peer_id: int,
	encounter_cell: Vector2i
) -> Dictionary:
	for q in quests:
		if not q is Dictionary:
			continue
		var qd: Dictionary = q as Dictionary
		if str(qd.get("status", "")) != "active":
			continue
		if str(qd.get("quest_giver", "")) == giver_monster_name:
			return {
				"result": "chat",
				"title": "Conversation",
				"message":
				(
					giver_monster_name
					+ ' says: "You already have an active quest from me. Complete it first before I can offer you another!"'
				),
			}
		if (
			str(qd.get("quest_giver", "")) == giver_monster_name
			and str(qd.get("quest_giver_theme", "")) == current_theme_name
		):
			return {
				"result": "chat",
				"title": "Conversation",
				"message":
				(
					giver_monster_name
					+ " says: \"I've already given you a quest here in the "
					+ current_theme_name
					+ ". I don't have anything else for you in this area.\""
				),
			}
	var idx := 0
	for qq in quests:
		if qq is Dictionary and str((qq as Dictionary).get("quest_source", "")) == "npc":
			idx += 1
	var new_q: Dictionary = create_npc_kill_quest_dict(
		authority_seed,
		peer_id,
		encounter_cell,
		giver_monster_name,
		giver_alignment,
		player_alignment_value,
		current_theme_name,
		dungeon_level,
		idx
	)
	if new_q.is_empty():
		return {
			"result": "chat",
			"title": "Conversation",
			"message":
			giver_monster_name + ' says: "I do not have anything for you right now. Safe travels!"',
		}
	return {
		"result": "offer",
		"title": "Quest offer",
		"message":
		giver_monster_name + " offers you a quest:\n\n" + str(new_q.get("description", "")),
		"quest": new_q,
	}


static func kill_quest_encounter_tile(target_name: String) -> String:
	var safe := target_name.strip_edges().replace("|", " ")
	return "encounter|Quest|" + safe


static func should_spawn_kill_quest_on_map(quest: Dictionary, map_theme_name: String) -> bool:
	var t := str(quest.get("type", ""))
	if t != "monster_kill" and t != "npc_kill":
		return false
	if str(quest.get("status", "")) != "active":
		return false
	return str(quest.get("target_theme", "")).strip_edges() == map_theme_name.strip_edges()


static func kill_quest_target_name(quest: Dictionary) -> String:
	var t := str(quest.get("type", ""))
	if t == "npc_kill":
		return str(quest.get("target_npc", "")).strip_edges()
	return str(quest.get("target_monster", "")).strip_edges()


static func find_kill_quest_encounter_placement(
	grid: Dictionary,
	_authority_seed: int,
	_quest_id: String,
	_target_name: String,
	rooms_or_areas: Array = [],
	rng_override: RandomNumberGenerator = null
) -> Vector2i:
	# Explorer-style preference: structure positions (rooms/areas) + corridor positions, then fallback.
	var structure_positions: Array[Vector2i] = _quest_spawn_structure_positions(
		grid, rooms_or_areas
	)
	var corridor_positions: Array[Vector2i] = _quest_spawn_corridor_positions(grid, rooms_or_areas)
	var candidates: Array[Vector2i] = []
	for c in structure_positions:
		candidates.append(c)
	for c2 in corridor_positions:
		candidates.append(c2)
	if candidates.is_empty():
		for y in DungeonGrid.MAP_HEIGHT:
			for x in DungeonGrid.MAP_WIDTH:
				var c3 := Vector2i(x, y)
				var t3: String = GridWalk.tile_at(grid, c3)
				if t3 != "floor" and t3 != "corridor":
					continue
				candidates.append(c3)
	if candidates.is_empty():
		return Vector2i(-1, -1)

	var rng := rng_override
	if rng == null:
		rng = RandomNumberGenerator.new()
		# User requested Explorer-like randomness (not seeded from authority).
		rng.randomize()
	var pick: int = rng.randi_range(0, candidates.size() - 1)
	return candidates[pick]


static func _quest_spawn_structure_positions(
	grid: Dictionary, rooms_or_areas: Array
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ent in rooms_or_areas:
		if ent is not Dictionary:
			continue
		var d := ent as Dictionary
		# Traditional rooms: x,y,width,height.
		if d.has("x") and d.has("y") and d.has("width") and d.has("height"):
			var rx: int = int(d.get("x", 0))
			var ry: int = int(d.get("y", 0))
			var rw: int = int(d.get("width", 0))
			var rh: int = int(d.get("height", 0))
			var cx := rx + (rw >> 1)
			var cy := ry + (rh >> 1)
			for x in range(rx, rx + rw):
				for y in range(ry, ry + rh):
					var c := Vector2i(x, y)
					if GridWalk.tile_at(grid, c) != "floor":
						continue
					# Avoid label-center conflicts (Explorer: avoid center ±1).
					if abs(x - cx) <= 1 and abs(y - cy) <= 1:
						continue
					out.append(c)
			continue
		# Organic areas/caverns: cells array.
		var cells: Array = d.get("cells", []) as Array
		if cells.is_empty():
			continue
		var center := _quest_spawn_area_center(cells)
		for raw in cells:
			if raw is not Vector2i:
				continue
			var c2 := raw as Vector2i
			if GridWalk.tile_at(grid, c2) != "floor":
				continue
			if abs(c2.x - center.x) <= 1 and abs(c2.y - center.y) <= 1:
				continue
			out.append(c2)
	return out


static func _quest_spawn_area_center(cells: Array) -> Vector2i:
	if cells.is_empty():
		return Vector2i(DungeonGrid.MAP_WIDTH >> 1, DungeonGrid.MAP_HEIGHT >> 1)
	var sx := 0
	var sy := 0
	var n := 0
	for raw in cells:
		if raw is not Vector2i:
			continue
		var c := raw as Vector2i
		sx += c.x
		sy += c.y
		n += 1
	if n <= 0:
		return Vector2i(DungeonGrid.MAP_WIDTH >> 1, DungeonGrid.MAP_HEIGHT >> 1)
	return Vector2i(int(float(sx) / float(n)), int(float(sy) / float(n)))


static func _quest_spawn_corridor_positions(
	grid: Dictionary, rooms_or_areas: Array
) -> Array[Vector2i]:
	# Explorer corridors exist for traditional dungeons; for areas/caverns most paths are "floor".
	var has_traditional := false
	for ent in rooms_or_areas:
		if ent is Dictionary:
			var d := ent as Dictionary
			if d.has("x") and d.has("y") and d.has("width") and d.has("height"):
				has_traditional = true
				break
	if not has_traditional:
		return []
	var out: Array[Vector2i] = []
	for y in DungeonGrid.MAP_HEIGHT:
		for x in DungeonGrid.MAP_WIDTH:
			var c := Vector2i(x, y)
			if GridWalk.tile_at(grid, c) != "corridor":
				continue
			if _quest_spawn_point_in_any_traditional_room(c, rooms_or_areas):
				continue
			out.append(c)
	return out


static func _quest_spawn_point_in_any_traditional_room(p: Vector2i, rooms_or_areas: Array) -> bool:
	for ent in rooms_or_areas:
		if ent is not Dictionary:
			continue
		var d := ent as Dictionary
		if not (d.has("x") and d.has("y") and d.has("width") and d.has("height")):
			continue
		var rx: int = int(d.get("x", 0))
		var ry: int = int(d.get("y", 0))
		var rw: int = int(d.get("width", 0))
		var rh: int = int(d.get("height", 0))
		if p.x >= rx and p.x < rx + rw and p.y >= ry and p.y < ry + rh:
			return true
	return false


static func grid_has_kill_target_encounter(grid: Dictionary, target_name: String) -> bool:
	var want := kill_quest_encounter_tile(target_name)
	for k in grid:
		if str(grid[k]) == want:
			return true
	return false


static func find_active_kill_quest_for_victory(
	quests: Array, defeated_monster_name: String, map_theme_name: String
) -> Dictionary:
	var dname := defeated_monster_name.strip_edges()
	for q in quests:
		if not q is Dictionary:
			continue
		var qd: Dictionary = q as Dictionary
		if str(qd.get("status", "")) != "active":
			continue
		var t := str(qd.get("type", ""))
		if t != "monster_kill" and t != "npc_kill":
			continue
		if str(qd.get("target_theme", "")).strip_edges() != map_theme_name.strip_edges():
			continue
		if t == "monster_kill" and str(qd.get("target_monster", "")).strip_edges() == dname:
			return qd.duplicate(true)
		if t == "npc_kill" and str(qd.get("target_npc", "")).strip_edges() == dname:
			return qd.duplicate(true)
	return {}


static func kill_quest_completion_append_body(
	quest: Dictionary, _defeated_name: String, _map_theme_name: String
) -> String:
	# Reuse Explorer-aligned copy that explicitly includes rewards.
	# Keep args (_defeated_name/_map_theme_name) to preserve call sites and future flexibility.
	return achievement_text_for_completed_quest(quest)


static func kill_quest_alignment_delta(quest: Dictionary) -> int:
	var g: int = maxi(0, int(quest.get("reward_gold", 0)))
	var qa := str(quest.get("quest_alignment", "lawful")).strip_edges().to_lower()
	if qa == "lawful":
		return g
	return -g
