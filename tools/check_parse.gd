extends SceneTree

## Headless entry for `./checks.sh`: load core resources so parse/type errors fail CI.


func _init() -> void:
	var paths: PackedStringArray = [
		"res://Main.gd",
		"res://Main.tscn",
		"res://dungeon/generator/grid.gd",
		"res://dungeon/generator/rooms.gd",
		"res://dungeon/generator/corridors.gd",
		"res://dungeon/generator/features_dungeon.gd",
		"res://dungeon/generator/traditional_generator.gd",
		"res://dungeon/generator/dungeon_generator.gd",
		"res://dungeon/generator/dungeon_themes.gd",
		"res://dungeon/generator/organic_areas.gd",
		"res://dungeon/generator/map_link_system.gd",
		"res://dungeon/map_transition_system.gd",
		"res://dungeon/world/world_labels_messages.gd",
		"res://dungeon/world/special_feature_investigation.gd",
		"res://dungeon/world/special_feature_trap_copy.gd",
		"res://dungeon/generator/generator_features.gd",
		"res://dungeon/generator/cities_generator.gd",
		"res://dungeon/fog/fog_of_war.gd",
		"res://dungeon/movement/grid_pathfinding.gd",
		"res://dungeon/movement/grid_walkability.gd",
		"res://dungeon/ui/dungeon_grid_view.gd",
		"res://dungeon/ui/encounter_map_token.gd",
		"res://dungeon/ui/party_marker_art.gd",
		"res://dungeon/treasure/treasure_system.gd",
		"res://dungeon/world/consumable_pickup.gd",
		"res://dungeon/world/player_quests.gd",
		"res://dungeon/world/special_item_table.gd",
		"res://dungeon/encounter/encounter_system.gd",
		"res://dungeon/combat/dungeon_dice.gd",
		"res://dungeon/combat/player_combat_stats.gd",
		"res://dungeon/progression/player_progression.gd",
		"res://dungeon/progression/player_talents.gd",
		"res://dungeon/progression/player_alignment.gd",
		"res://dungeon/combat/monster_table.gd",
		"res://dungeon/monster/monster_turn_system.gd",
		"res://dungeon/combat/combat_resolver.gd",
		"res://dungeon/audio/explorer_audio.gd",
		"res://dungeon/ui/rumors_list_messages.gd",
		"res://dungeon/ui/explorer_modal_chrome.gd",
		"res://dungeon/ui/dungeon_session.gd",
		"res://dungeon/ui/dungeon_tile_assets.gd",
		"res://dungeon/ui/map_cell_overlay_art.gd",
		"res://dungeon/ui/torch_flicker_fx.gd",
		"res://dungeon/ui/dungeon_door_overlays.gd",
		"res://dungeon/network/dungeon_replication.gd",
		"res://dungeon/network/grid_tile_patch_codec.gd",
		"res://dungeon/network/join_metadata.gd",
		"res://dungeon/network/dungeon_network_host.gd",
		"res://dungeon/network/dungeon_server_bootstrap.gd",
		"res://DedicatedServer.gd",
		"res://DedicatedServer.tscn",
		"res://tools/run_generation.gd",
	]
	for path in paths:
		if ResourceLoader.load(path) == null:
			push_error("check_parse: failed to load " + path)
			quit(1)
			return
	const CombatResolver := preload("res://dungeon/combat/combat_resolver.gd")
	const PlayerCombatStats := preload("res://dungeon/combat/player_combat_stats.gd")
	const EncounterSys := preload("res://dungeon/encounter/encounter_system.gd")
	var gcell := Vector2i(10, 10)
	var gseed := 12_345
	var o1: Dictionary = CombatResolver.simulate_encounter_fight(gseed, gcell, "Rat")
	var o2: Dictionary = CombatResolver.simulate_encounter_fight(gseed, gcell, "Rat")
	if str(o1.get("body", "")) != str(o2.get("body", "")):
		push_error("check_parse: combat log non-deterministic")
		quit(1)
		return
	if not bool(o1.get("victory", false)):
		push_error("check_parse: golden combat expected victory vs Rat")
		quit(1)
		return
	var oi: Dictionary = CombatResolver.play_interactive_to_end(
		gseed, gcell, "Rat", PlayerCombatStats.starting_hit_points_for_role("rogue")
	)
	if str(oi.get("body", "")) != str(o1.get("body", "")):
		push_error("check_parse: interactive combat log diverges from auto-resolve")
		quit(1)
		return
	if int(oi.get("player_hp_end", -1)) != int(o1.get("player_hp_end", -2)):
		push_error("check_parse: interactive combat HP end diverges")
		quit(1)
		return
	var of1: Dictionary = CombatResolver.simulate_encounter_fight(gseed, gcell, "Rat", "fighter")
	var oif: Dictionary = CombatResolver.play_interactive_to_end(
		gseed, gcell, "Rat", PlayerCombatStats.starting_hit_points_for_role("fighter"), "fighter"
	)
	if str(of1.get("body", "")) != str(oif.get("body", "")):
		push_error("check_parse: fighter interactive combat log diverges from auto-resolve")
		quit(1)
		return
	if int(oif.get("player_hp_end", -1)) != int(of1.get("player_hp_end", -2)):
		push_error("check_parse: fighter interactive combat HP end diverges")
		quit(1)
		return
	var flee_cell := Vector2i(7, 8)
	var flee_seed := 2
	var sf1: Variant = CombatResolver.create_interactive_combat(
		flee_seed, flee_cell, "Rat", 4, "rogue"
	)
	sf1.advance_flee()
	var oflee1: Dictionary = sf1.build_finish_outcome()
	var sf2: Variant = CombatResolver.create_interactive_combat(
		flee_seed, flee_cell, "Rat", 4, "rogue"
	)
	sf2.advance_flee()
	var oflee2: Dictionary = sf2.build_finish_outcome()
	if str(oflee1.get("body", "")) != str(oflee2.get("body", "")):
		push_error("check_parse: combat flee log non-deterministic")
		quit(1)
		return
	if not bool(oflee1.get("flee_success", false)):
		push_error("check_parse: golden combat flee expected success (seed=2 cell=(7,8))")
		quit(1)
		return
	if int(oflee1.get("xp_gain", 0)) != EncounterSys.EVADE_XP:
		push_error("check_parse: combat flee xp expected EVADE_XP")
		quit(1)
		return
	var golden_flee_body := (
		"No surprise. The Rat notices your approach. (Rolled 3 on d6)\n"
		+ "— Round 1 —\n"
		+ "Initiative: You rolled 2, monster rolled 3. Monster goes first!\n"
		+ "Rat attacks with Bite! Rolled 14 + 0 = 14 vs AC 12. HIT for 1 damage!\n"
		+ "You attempt to flee! Rat gets a free attack with Bite! Rolled 9 + 0 = 9 vs AC 12. MISS!\n"
		+ "Success! You manage to escape from combat.\n\n"
		+ "(Rolled 10 + 3 dexterity = 13 vs DC 12)"
	)
	if str(oflee1.get("body", "")) != golden_flee_body:
		push_error(
			"check_parse: combat flee body drifted from golden (update if RNG pipeline changes)"
		)
		quit(1)
		return
	const DungeonGrid := preload("res://dungeon/generator/grid.gd")
	const DungeonTileAssets := preload("res://dungeon/ui/dungeon_tile_assets.gd")
	var sample_rooms: Array = [{"x": 4, "y": 4, "width": 4, "height": 4}]
	## `floor` vs `corridor` forces distinct hash seeds (encounter tiles can collide for unrelated cells).
	var a_in_room := DungeonTileAssets.terrain_source_atlas(
		Vector2i(5, 5), "floor", "dungeon", sample_rooms
	)
	var a_in_corr := DungeonTileAssets.terrain_source_atlas(
		Vector2i(1, 0), "corridor", "dungeon", sample_rooms
	)
	if a_in_room == a_in_corr:
		push_error("check_parse: room vs corridor terrain atlas expected to differ")
		quit(1)
		return
	if not DungeonGrid.should_use_floor_texture(Vector2i(5, 5), sample_rooms, "dungeon"):
		push_error("check_parse: should_use_floor_texture expected true in room")
		quit(1)
		return
	if DungeonGrid.should_use_floor_texture(Vector2i(30, 30), sample_rooms, "dungeon"):
		push_error("check_parse: should_use_floor_texture expected false in corridor")
		quit(1)
		return
	var city_rooms: Array = [{"type": "building", "cells": [Vector2i(1, 1)]}]
	if not DungeonGrid.should_use_floor_texture(Vector2i(1, 1), city_rooms, "city"):
		push_error("check_parse: city building should use floor texture")
		quit(1)
		return
	const WorldLabelsMsg := preload("res://dungeon/world/world_labels_messages.gd")
	var pr1: Dictionary = WorldLabelsMsg.room_label_payload("room_label|R1", "", "")
	if not str(pr1.get("message", "")).contains("The entrance chamber"):
		push_error("check_parse: world_labels R1 DescriptionService fallback drift")
		quit(1)
		return
	var pr2: Dictionary = WorldLabelsMsg.room_label_payload("room_label|R3", "Swamp", "down")
	if not str(pr2.get("message", "")).contains("A chamber within this Swamp"):
		push_error("check_parse: world_labels room fallback drift")
		quit(1)
		return
	var pc: Dictionary = WorldLabelsMsg.corridor_label_payload("corridor_label|C2", "", "")
	if not str(pc.get("message", "")).contains("A passage winding through"):
		push_error("check_parse: world_labels corridor fallback drift")
		quit(1)
		return
	var pa: Dictionary = WorldLabelsMsg.area_label_payload("area_label|A1", "", "")
	if not str(pa.get("message", "")).contains("An open area within"):
		push_error("check_parse: world_labels area fallback drift")
		quit(1)
		return
	var pb: Dictionary = WorldLabelsMsg.building_label_payload("building_label|B9", "Metro", "")
	if not str(pb.get("message", "")).contains("An interesting discovery"):
		push_error("check_parse: world_labels building generic fallback drift")
		quit(1)
		return
	var psf: Dictionary = WorldLabelsMsg.special_feature_payload(
		"special_feature|sf|Altar", "Castle", ""
	)
	if str(psf.get("title", "")) != "Something Interesting!":
		push_error("check_parse: world_labels special_feature title drift")
		quit(1)
		return
	var msf := str(psf.get("message", ""))
	if not msf.contains("**Altar**") or not msf.contains("intriguing altar"):
		push_error("check_parse: world_labels feature fallback drift")
		quit(1)
		return
	if msf.contains("Planner tag"):
		push_error("check_parse: world_labels special_feature should not expose planner tail")
		quit(1)
		return
	var d_closed := WorldLabelsMsg.door_location_fallback_body("closed", "TestTheme", "")
	if (
		not d_closed.contains("sturdy")
		or not d_closed.contains("closed door")
		or not d_closed.contains("TestTheme")
	):
		push_error("check_parse: world_labels door closed fallback drift")
		quit(1)
		return
	var d_unp := WorldLabelsMsg.door_location_fallback_body("unpickable", "T", "")
	if not d_unp.contains("can no longer be picked"):
		push_error("check_parse: world_labels door unpickable fallback drift")
		quit(1)
		return
	var st_body := WorldLabelsMsg.stair_location_fallback_body("up", "Th", "")
	if not st_body.contains("upward staircase") or not st_body.contains("Th"):
		push_error("check_parse: world_labels stair fallback drift")
		quit(1)
		return
	var stw: Dictionary = WorldLabelsMsg.stair_world_interaction_payload("stair_up", "TN", "up")
	var stw_m := str(stw.get("message", ""))
	if not stw_m.contains("upward staircase") or not stw_m.contains("Press OK to climb"):
		push_error("check_parse: world_labels stair interaction drift")
		quit(1)
		return
	var stw2: Dictionary = WorldLabelsMsg.stair_world_interaction_payload("stair_down", "", "")
	var stw2_m := str(stw2.get("message", ""))
	if not stw2_m.contains("downward staircase") or not stw2_m.contains("Press OK to descend"):
		push_error("check_parse: world_labels stair down interaction drift")
		quit(1)
		return
	var wpw: Dictionary = WorldLabelsMsg.waypoint_world_interaction_payload(
		"waypoint|2", "Forest", ""
	)
	var wpw_m := str(wpw.get("message", ""))
	if (
		not wpw_m.contains("Waypoint Discovered")
		or not wpw_m.contains("(2)")
		or not wpw_m.contains("Forest")
		or not wpw_m.contains("Press OK to travel")
	):
		push_error("check_parse: world_labels waypoint interaction drift")
		quit(1)
		return
	if WorldLabelsMsg.waypoint_number_from_raw_tile("waypoint|3") != 3:
		push_error("check_parse: world_labels waypoint number parse")
		quit(1)
		return
	if WorldLabelsMsg.stair_direction_from_raw_tile("stair_up") != "up":
		push_error("check_parse: world_labels stair direction parse")
		quit(1)
		return
	var rtrap_m := WorldLabelsMsg.room_trap_world_interaction_body("Metro", "down")
	if (
		not rtrap_m.contains("**Hidden Trap!**")
		or not rtrap_m.contains("Metro")
		or not rtrap_m.contains("floor gives way")
	):
		push_error("check_parse: world_labels room trap fallback drift")
		quit(1)
		return
	const GridPath := preload("res://dungeon/movement/grid_pathfinding.gd")
	var _path_set_floor := func(grid: Dictionary, cells: Array) -> void:
		for c in cells:
			grid[c as Vector2i] = "floor"
	var empty_revealed := {}
	var empty_unlocked := {}
	var empty_trap := {}
	## Straight corridor: A* length must match BFS reference.
	var g_straight: Dictionary = {}
	(
		_path_set_floor
		. call(
			g_straight,
			[
				Vector2i(10, 10),
				Vector2i(11, 10),
				Vector2i(12, 10),
				Vector2i(13, 10),
			]
		)
	)
	var p_stra := GridPath.find_path_8dir(
		g_straight, Vector2i(10, 10), Vector2i(13, 10), empty_revealed, false, empty_unlocked
	)
	var b_stra := GridPath.find_path_8dir_bfs_reference(
		g_straight, Vector2i(10, 10), Vector2i(13, 10), empty_revealed, false, empty_unlocked
	)
	if p_stra.size() != b_stra.size() or p_stra.size() != 3:
		push_error("check_parse: pathfinding straight corridor length mismatch")
		quit(1)
		return
	## L-shaped unique path (single shortest route).
	var g_l: Dictionary = {}
	(
		_path_set_floor
		. call(
			g_l,
			[
				Vector2i(2, 2),
				Vector2i(3, 2),
				Vector2i(4, 2),
				Vector2i(4, 3),
				Vector2i(4, 4),
			]
		)
	)
	var p_l := GridPath.find_path_8dir(
		g_l, Vector2i(2, 2), Vector2i(4, 4), empty_revealed, false, empty_unlocked
	)
	var b_l := GridPath.find_path_8dir_bfs_reference(
		g_l, Vector2i(2, 2), Vector2i(4, 4), empty_revealed, false, empty_unlocked
	)
	if p_l.size() != b_l.size() or p_l.size() != 3:
		push_error("check_parse: pathfinding L-shape length mismatch")
		quit(1)
		return
	## Shortest king route uses one diagonal (3,2)→(4,3); orth-only corridor would be 4 steps.
	var want_l := PackedVector2Array([Vector2(3, 2), Vector2(4, 3), Vector2(4, 4)])
	if p_l.size() != want_l.size():
		push_error("check_parse: pathfinding L-shape A* path size drift")
		quit(1)
		return
	for wi in range(want_l.size()):
		if p_l[wi] != want_l[wi]:
			push_error("check_parse: pathfinding L-shape A* path cell drift")
			quit(1)
			return
	## No path through wall gap.
	var g_block: Dictionary = {}
	_path_set_floor.call(g_block, [Vector2i(20, 20), Vector2i(21, 20), Vector2i(23, 20)])
	var p_blk := GridPath.find_path_8dir(
		g_block, Vector2i(20, 20), Vector2i(23, 20), empty_revealed, false, empty_unlocked
	)
	var b_blk := GridPath.find_path_8dir_bfs_reference(
		g_block, Vector2i(20, 20), Vector2i(23, 20), empty_revealed, false, empty_unlocked
	)
	if p_blk.size() != 0 or b_blk.size() != 0:
		push_error("check_parse: pathfinding blocked expected empty path")
		quit(1)
		return
	var pv_prefix := PackedVector2Array([Vector2(11, 10), Vector2(12, 10), Vector2(13, 10)])
	if (
		GridPath.king_step_count_along_path_prefix(Vector2i(10, 10), pv_prefix, Vector2i(12, 10))
		!= 2
	):
		push_error("check_parse: king_step_count_along_path_prefix mid")
		quit(1)
		return
	if (
		GridPath.king_step_count_along_path_prefix(Vector2i(10, 10), pv_prefix, Vector2i(10, 10))
		!= 0
	):
		push_error("check_parse: king_step_count_along_path_prefix start")
		quit(1)
		return
	if (
		GridPath.king_step_count_along_path_prefix(Vector2i(10, 10), pv_prefix, Vector2i(99, 99))
		!= -1
	):
		push_error("check_parse: king_step_count_along_path_prefix off-path")
		quit(1)
		return
	const PlayerProgression := preload("res://dungeon/progression/player_progression.gd")
	if PlayerProgression.xp_required_for_level(1) != 0:
		push_error("check_parse: xp_required_for_level(1) expected 0")
		quit(1)
		return
	if PlayerProgression.xp_required_for_level(2) != 500:
		push_error("check_parse: xp_required_for_level(2) expected 500")
		quit(1)
		return
	if PlayerProgression.xp_required_for_level(3) != 1500:
		push_error("check_parse: xp_required_for_level(3) expected 1500")
		quit(1)
		return
	if PlayerProgression.xp_required_for_level(4) != 3000:
		push_error("check_parse: xp_required_for_level(4) expected 3000")
		quit(1)
		return
	if PlayerProgression.calculate_level(0) != 1 or PlayerProgression.calculate_level(499) != 1:
		push_error("check_parse: calculate_level low XP expected 1")
		quit(1)
		return
	if PlayerProgression.calculate_level(500) != 2 or PlayerProgression.calculate_level(1499) != 2:
		push_error("check_parse: calculate_level tier 2 boundary")
		quit(1)
		return
	if PlayerProgression.calculate_level(1500) != 3:
		push_error("check_parse: calculate_level(1500) expected 3")
		quit(1)
		return
	if (
		PlayerProgression.xp_needed_for_next_level(0) != 500
		or PlayerProgression.xp_needed_for_next_level(250) != 250
		or PlayerProgression.xp_needed_for_next_level(500) != 1000
	):
		push_error("check_parse: xp_needed_for_next_level golden values")
		quit(1)
		return
	if (
		not PlayerProgression.leveled_up(0, 500)
		or PlayerProgression.leveled_up(250, 499)
		or not PlayerProgression.leveled_up(499, 500)
		or not PlayerProgression.leveled_up(1000, 1500)
	):
		push_error("check_parse: leveled_up golden values")
		quit(1)
		return
	const PlayerAlignment := preload("res://dungeon/progression/player_alignment.gd")
	const MonsterTurn := preload("res://dungeon/monster/monster_turn_system.gd")
	const MonsterTable := preload("res://dungeon/combat/monster_table.gd")
	if PlayerAlignment.starting_alignment() != 0:
		push_error("check_parse: starting_alignment expected 0")
		quit(1)
		return
	if PlayerAlignment.description_from_value(1) != "lawful":
		push_error("check_parse: description_from_value positive")
		quit(1)
		return
	if PlayerAlignment.description_from_value(-1) != "chaotic":
		push_error("check_parse: description_from_value negative")
		quit(1)
		return
	if PlayerAlignment.description_from_value(0) != "neutral":
		push_error("check_parse: description_from_value zero")
		quit(1)
		return
	if not PlayerAlignment.npc_hostile_to_player("lawful", -5):
		push_error("check_parse: lawful vs chaotic player should clash")
		quit(1)
		return
	if PlayerAlignment.npc_hostile_to_player("lawful", 0):
		push_error("check_parse: lawful vs neutral should not clash")
		quit(1)
		return
	if not PlayerAlignment.npc_hostile_to_player("chaotic", 3):
		push_error("check_parse: chaotic vs lawful player should clash")
		quit(1)
		return
	var def_guard: Dictionary = MonsterTable.lookup_monster("Guard")
	if str(def_guard.get("alignment", "")) != "lawful":
		push_error("check_parse: Guard CSV alignment expected lawful")
		quit(1)
		return
	if MonsterTurn.effective_hunts(def_guard, false, 0):
		push_error("check_parse: peaceful guard neutral player should not hunt")
		quit(1)
		return
	if not MonsterTurn.effective_hunts(def_guard, true, 0):
		push_error("check_parse: guards_hostile should make guard hunt")
		quit(1)
		return
	if not MonsterTurn.effective_hunts(def_guard, false, -3):
		push_error("check_parse: chaotic player vs lawful guard should hunt")
		quit(1)
		return
	var def_rat: Dictionary = MonsterTable.lookup_monster("Rat")
	if MonsterTurn.effective_hunts(def_rat, false, 0):
		push_error(
			"check_parse: Rat should not hunt neutral visitor (Explorer hunts_player?: false)"
		)
		quit(1)
		return
	var def_merch: Dictionary = MonsterTable.lookup_monster("Merchant")
	if MonsterTurn.effective_hunts(def_merch, false, 0):
		push_error("check_parse: Merchant npc should not hunt neutral player")
		quit(1)
		return
	if not MonsterTurn.effective_hunts(def_merch, false, -2):
		push_error("check_parse: Merchant should hunt chaotic player (alignment clash)")
		quit(1)
		return
	MonsterTable.ensure_loaded()
	if MonsterTable.all_monsters().size() != 111:
		push_error(
			"check_parse: expected 111 monster rows (Explorer export + Kobold Slinger theme gap-fill)"
		)
		quit(1)
		return
	const GenFeat := preload("res://dungeon/generator/generator_features.gd")
	var themes_json := FileAccess.get_file_as_string("res://dungeon/data/themes.json")
	var themes_parsed: Variant = JSON.parse_string(themes_json)
	if themes_parsed == null or not themes_parsed is Array:
		push_error("check_parse: themes.json parse failed")
		quit(1)
		return
	var theme_ref_names: Dictionary = {}
	for td in themes_parsed as Array:
		if not td is Dictionary:
			continue
		var tdic: Dictionary = td as Dictionary
		for key in ["monsters", "indoor_monsters", "outdoor_monsters"]:
			var monsters_raw: Variant = tdic.get(key, [])
			if not monsters_raw is Array:
				continue
			for me in monsters_raw as Array:
				if me is Dictionary:
					var mname := str((me as Dictionary).get("name", "")).strip_edges()
					if not mname.is_empty():
						theme_ref_names[mname] = true
	for nm in theme_ref_names:
		if not MonsterTable.has_named_monster(str(nm)):
			push_error("check_parse: theme references unknown monster " + str(nm))
			quit(1)
			return
	var rng_theme := RandomNumberGenerator.new()
	rng_theme.seed = 99_999
	var pleasant0: Dictionary = (themes_parsed as Array)[0] as Dictionary
	var picked0 := GenFeat.pick_monster_for_theme_with_fog_type(pleasant0, rng_theme, 1, 1)
	if picked0.is_empty():
		push_error("check_parse: Pleasant Woods theme should pick a monster")
		quit(1)
		return
	if not MonsterTable.has_named_monster(picked0):
		push_error("check_parse: theme pick should resolve in monster_table")
		quit(1)
		return
	var reg_json := FileAccess.get_file_as_string(
		"res://dungeon/data/special_feature_registry.json"
	)
	var reg_parsed: Variant = JSON.parse_string(reg_json)
	if reg_parsed == null or not reg_parsed is Array:
		push_error("check_parse: special_feature_registry.json parse failed")
		quit(1)
		return
	if (reg_parsed as Array).size() != 55:
		push_error(
			"check_parse: expected 55 special feature registry rows (Explorer Features export)"
		)
		quit(1)
		return
	for reg_item in reg_parsed as Array:
		if reg_item is not Dictionary:
			continue
		var rd: Dictionary = reg_item
		var img := str(rd.get("image", "")).strip_edges()
		if img.is_empty():
			push_error("check_parse: registry row missing image for " + str(rd.get("name", "")))
			quit(1)
			return
	const MapCellOverlayArt := preload("res://dungeon/ui/map_cell_overlay_art.gd")
	MapCellOverlayArt.assert_registry_has_images_for_ci()
	var exp_chest := MapCellOverlayArt.expected_png_res_for_tile("treasure")
	if not exp_chest.ends_with("/images/chest.png"):
		push_error("check_parse: map overlay treasure path drift")
		quit(1)
		return
	if not MapCellOverlayArt.expected_png_res_for_tile("special_feature|F1|Barrel").ends_with(
		"/special_features/barrel.png"
	):
		push_error("check_parse: map overlay special feature path drift")
		quit(1)
		return
	if MapCellOverlayArt.expected_png_res_for_tile("special_feature|F1|Pillar") != "":
		push_error("check_parse: pillar should not use flat overlay path")
		quit(1)
		return
	if not MapCellOverlayArt.expected_png_res_for_tile("waypoint|2").ends_with(
		"/map_links/outdoor_waypoint2.png"
	):
		push_error("check_parse: map overlay waypoint path drift")
		quit(1)
		return
	for seed_i in range(30):
		var rfeat := RandomNumberGenerator.new()
		rfeat.seed = 10_001 + seed_i
		var empty_special_theme := {"special_features": []}
		var picked_feat := GenFeat.pick_special_feature_name(empty_special_theme, rfeat)
		if picked_feat.is_empty() or not GenFeat.special_feature_registry_has(picked_feat):
			push_error(
				"check_parse: empty-theme special feature pick must resolve in registry (GEN-02)"
			)
			quit(1)
			return
	var city_enc_theme: Dictionary = {
		"fog_type": "daylight",
		"monsters": [],
		"indoor_monsters": [{"name": "Merchant", "rarity": "common"}],
	}
	for seed_ce in range(80):
		var rng_ce := RandomNumberGenerator.new()
		rng_ce.seed = 50_000 + seed_ce
		var got_m := GenFeat.pick_monster_for_city_encounter(city_enc_theme, true, rng_ce, 1)
		var theme_clone: Dictionary = city_enc_theme.duplicate()
		theme_clone["monsters"] = (city_enc_theme.get("indoor_monsters", []) as Array).duplicate()
		var rng_ce2 := RandomNumberGenerator.new()
		rng_ce2.seed = 50_000 + seed_ce
		var want_m := GenFeat.pick_monster_for_theme_with_fog_type(theme_clone, rng_ce2, 1, 1)
		if got_m != want_m:
			push_error(
				"check_parse: city encounter pick must match Explorer monsters swap + fog pick (Phase 7)"
			)
			quit(1)
			return
	var cf_theme: Dictionary = {
		"indoor_features":
		[
			{"name": "Desk", "rarity": "common"},
			{"name": "Table", "rarity": "common"},
		],
		"special_features": [{"name": "Barrel", "rarity": "common"}],
	}
	for seed_cf in range(600):
		var rng_cf := RandomNumberGenerator.new()
		rng_cf.seed = 60_000 + seed_cf
		var fn := GenFeat.pick_city_feature_name(cf_theme, true, rng_cf)
		if fn != "Desk" and fn != "Table":
			push_error("check_parse: city indoor feature must draw only from theme list (Phase 7)")
			quit(1)
			return
	var rng_empty_feat := RandomNumberGenerator.new()
	rng_empty_feat.seed = 70_007
	if not GenFeat.pick_city_feature_name({"indoor_features": []}, true, rng_empty_feat).is_empty():
		push_error("check_parse: empty city feature list must not pick a name (Phase 7)")
		quit(1)
		return
	var vp_cells: Array[Vector2i] = [Vector2i(5, 5), Vector2i(6, 6)]
	var raw_x := "encounter|Etest|Rat"
	var grid_resolve: Dictionary = {
		Vector2i(5, 5): "corridor",
		Vector2i(6, 6): raw_x,
	}
	var rlive := MonsterTurn.resolve_live_encounter_cell(
		grid_resolve, vp_cells, Vector2i(5, 5), raw_x
	)
	if rlive != Vector2i(6, 6):
		push_error("check_parse: resolve_live_encounter_cell should find moved encounter tile")
		quit(1)
		return
	var player_h := Vector2i(10, 15)
	var c_rat_a := Vector2i(10, 12)
	## Within `MAX_MONSTER_MOVE_EDGES` (4) orthogonal steps of an adjacent-to-player cell (Explorer viewport test).
	var c_rat_b := Vector2i(13, 15)
	## `monsters.csv` Rat has `hunts_player=0`; use a hunter so `process_monster_reduce_pass` includes the cells.
	var raw_ra := "encounter|EciA|Bandit"
	var raw_rb := "encounter|EciB|Bandit"
	var grid_h: Dictionary = {}
	for xh in range(64):
		for yh in range(48):
			grid_h[Vector2i(xh, yh)] = "corridor"
	grid_h[player_h] = "corridor"
	grid_h[c_rat_a] = raw_ra
	grid_h[c_rat_b] = raw_rb
	var found_order_seed := -1
	for seed_h in range(0, 400_000):
		if MonsterTurn.monster_hearing_roll_value(seed_h, 42, c_rat_a) >= MonsterTurn.HEARING_DC:
			continue
		if MonsterTurn.monster_hearing_roll_value(seed_h, 42, c_rat_b) < MonsterTurn.HEARING_DC:
			continue
		found_order_seed = seed_h
		break
	if found_order_seed < 0:
		push_error("check_parse: could not find seed for monster reduce ordering test")
		quit(1)
		return
	var grid_h2 := grid_h.duplicate()
	var combat_h := MonsterTurn.process_monster_reduce_pass(
		grid_h2, [], {}, false, {}, found_order_seed, 42, player_h, false, 0, Callable()
	)
	if str(grid_h2.get(c_rat_a, "")) != raw_ra:
		push_error("check_parse: first snapshot rat should not move when hearing fails")
		quit(1)
		return
	if combat_h.x < 0 and str(grid_h2.get(c_rat_b, "")) == raw_rb:
		push_error("check_parse: second rat should move or trigger combat when hearing succeeds")
		quit(1)
		return
	var k1: Dictionary = PlayerAlignment.npc_or_guard_kill_replication_effects(
		"npc", "lawful", false
	)
	if (
		int(k1.get("alignment_delta", 99)) != -5
		or not bool(k1.get("trigger_guards_hostile", false))
		or not bool(k1.get("increments_npcs_killed", false))
	):
		push_error("check_parse: kill_effects lawful npc")
		quit(1)
		return
	var k2: Dictionary = PlayerAlignment.npc_or_guard_kill_replication_effects(
		"npc", "chaotic", false
	)
	if (
		int(k2.get("alignment_delta", 99)) != 0
		or not bool(k2.get("trigger_guards_hostile", false))
		or not bool(k2.get("increments_npcs_killed", false))
	):
		push_error("check_parse: kill_effects chaotic npc still triggers hostility")
		quit(1)
		return
	var k3: Dictionary = PlayerAlignment.npc_or_guard_kill_replication_effects(
		"npc", "lawful", true
	)
	if (
		int(k3.get("alignment_delta", 99)) != 0
		or bool(k3.get("trigger_guards_hostile", true))
		or bool(k3.get("increments_npcs_killed", true))
	):
		push_error("check_parse: kill_effects when guards already hostile")
		quit(1)
		return
	var k4: Dictionary = PlayerAlignment.npc_or_guard_kill_replication_effects(
		"guard", "neutral", false
	)
	if (
		int(k4.get("alignment_delta", 99)) != -5
		or not bool(k4.get("trigger_guards_hostile", false))
		or not bool(k4.get("increments_npcs_killed", false))
	):
		push_error("check_parse: kill_effects neutral guard")
		quit(1)
		return
	var k5: Dictionary = PlayerAlignment.npc_or_guard_kill_replication_effects(
		"rat", "chaotic", false
	)
	if (
		int(k5.get("alignment_delta", 99)) != 0
		or bool(k5.get("trigger_guards_hostile", true))
		or bool(k5.get("increments_npcs_killed", true))
	):
		push_error("check_parse: kill_effects non-npc role")
		quit(1)
		return
	const SpecialItemTable := preload("res://dungeon/world/special_item_table.gd")
	var si_cell := Vector2i(3, 9)
	var si_seed := 55_019
	var si_salt := 712_004_321
	var it1: Dictionary = SpecialItemTable.pick_deterministic(si_seed, si_cell, si_salt)
	var it2: Dictionary = SpecialItemTable.pick_deterministic(si_seed, si_cell, si_salt)
	if str(it1.get("key", "")) != str(it2.get("key", "")):
		push_error("check_parse: special item pick non-deterministic")
		quit(1)
		return
	if it1.is_empty() or str(it1.get("name", "")).is_empty():
		push_error("check_parse: special item pick empty")
		quit(1)
		return
	var unc: Array = SpecialItemTable.by_rarity("uncommon")
	if unc.size() < 6:
		push_error("check_parse: special_items.json uncommon count")
		quit(1)
		return
	var bag: Dictionary = SpecialItemTable.lookup_by_key("bag_of_holding")
	if str(bag.get("name", "")) != "Bag of Holding":
		push_error("check_parse: special item lookup_by_key")
		quit(1)
		return
	var list_msg := SpecialItemTable.format_list_view_message(bag)
	if not list_msg.contains("Bag of Holding") or not list_msg.contains(" - "):
		push_error("check_parse: format_list_view_message")
		quit(1)
		return
	if SpecialItemTable.format_list_view_message({}) != "Unknown item":
		push_error("check_parse: format_list_view_message empty dict")
		quit(1)
		return
	# P7-04: Explorer dismiss_special_item does not grant gold; gold_value is for quests.
	# Keep a stable row so quest/economy tooling can key off the field; discovery copy stays XP-only.
	var dagger_si: Dictionary = SpecialItemTable.lookup_by_key("dagger_of_the_silent_step")
	if int(dagger_si.get("gold_value", -1)) != 50:
		push_error("check_parse: dagger_of_the_silent_step gold_value golden (P7-04 data)")
		quit(1)
		return
	var disc_dagger := SpecialItemTable.format_discovery_message(dagger_si)
	if disc_dagger.contains(" gp") or disc_dagger.contains("gold coins"):
		push_error("check_parse: discovery dialog must not offer gold on dismiss (Explorer P7-04)")
		quit(1)
		return
	var base_pst: Dictionary = PlayerCombatStats.for_role_with_progression("rogue", 0, 0, 0, 0)
	var base_sl := {
		"max_hit_points": int(base_pst.get("max_hit_points", 0)),
		"armor_class": int(base_pst.get("armor_class", 0)),
		"attack_bonus": int(base_pst.get("attack_bonus", 0)),
	}
	var m1: Dictionary = SpecialItemTable.merge_equipment_into_stat_line(
		base_sl, ["whisperfang", "shadowweave_cloak"]
	)
	if int(m1.get("max_hit_points", 0)) != 6:
		push_error("check_parse: equipment max_hp (cloak armor_bonus to HP)")
		quit(1)
		return
	if int(m1.get("armor_class", 0)) != 14:
		push_error("check_parse: equipment AC")
		quit(1)
		return
	if int(m1.get("attack_bonus", 0)) != 3:
		push_error("check_parse: equipment attack")
		quit(1)
		return
	if (
		str(m1.get("player_weapon", "")) != "Whisperfang"
		or str(m1.get("weapon_damage_dice", "")) != "1d6"
	):
		push_error("check_parse: weapon slot override")
		quit(1)
		return
	var eq_f: Dictionary = SpecialItemTable.get_equipped_items_by_keys(
		["ring_of_evasion", "ring_of_protection"]
	)
	if str((eq_f.get("finger", {}) as Dictionary).get("key", "")) != "ring_of_protection":
		push_error("check_parse: finger slot highest xp_value")
		quit(1)
		return
	var ev_row: Dictionary = SpecialItemTable.lookup_by_key("ring_of_evasion")
	if SpecialItemTable.inventory_status_for_item(ev_row, eq_f) != "Stored":
		push_error("check_parse: inventory_status Stored for losing ring")
		quit(1)
		return
	var prot_row: Dictionary = SpecialItemTable.lookup_by_key("ring_of_protection")
	if SpecialItemTable.inventory_status_for_item(prot_row, eq_f) != "Worn":
		push_error("check_parse: inventory_status Worn")
		quit(1)
		return
	var golden_key := str(it1.get("key", ""))
	for j in range(40):
		var alt: Dictionary = SpecialItemTable.pick_deterministic(si_seed + j, si_cell, si_salt)
		if str(alt.get("key", "")) != golden_key:
			golden_key = ""
			break
	if not golden_key.is_empty():
		push_error("check_parse: special item pick ignored seed salt (constant item)")
		quit(1)
		return
	const SFInv := preload("res://dungeon/world/special_feature_investigation.gd")
	const TrapCopy := preload("res://dungeon/world/special_feature_trap_copy.gd")
	var qs_cell := Vector2i(11, 22)
	var qs_name := "Quicksand"
	var trap_seed := -1
	var trap_dmg := -1
	for s in range(1, 12000):
		var ev: Dictionary = SFInv.evaluate(s, qs_cell, qs_name)
		if str(ev.get("kind", "")) == "trap":
			trap_seed = s
			trap_dmg = int(ev.get("damage", 0))
			break
	if trap_seed < 0 or trap_dmg < 1 or trap_dmg > 6:
		push_error("check_parse: expected Quicksand trap outcome in seed scan")
		quit(1)
		return
	var ev_q1: Dictionary = SFInv.evaluate(trap_seed, qs_cell, qs_name)
	var ev_q2: Dictionary = SFInv.evaluate(trap_seed, qs_cell, qs_name)
	if str(ev_q1.get("kind", "")) != "trap" or int(ev_q1.get("damage", 0)) != trap_dmg:
		push_error("check_parse: Quicksand trap evaluation drift")
		quit(1)
		return
	if str(ev_q2.get("kind", "")) != "trap" or int(ev_q2.get("damage", 0)) != trap_dmg:
		push_error("check_parse: Quicksand trap non-deterministic")
		quit(1)
		return
	var tc_a := TrapCopy.message_for(qs_name, trap_seed, qs_cell)
	var tc_b := TrapCopy.message_for(qs_name, trap_seed, qs_cell)
	if tc_a.is_empty() or tc_a != tc_b:
		push_error("check_parse: feature trap copy empty or non-deterministic")
		quit(1)
		return
	var tc_alt := TrapCopy.message_for("Altar", 404_404, Vector2i(2, 3))
	if tc_alt.is_empty():
		push_error("check_parse: feature trap copy default empty")
		quit(1)
		return
	if not (
		tc_a.contains("wet sand")
		or tc_a.contains("Dry surface")
		or tc_a.contains("crust looks solid")
	):
		push_error("check_parse: Quicksand trap copy golden (expected curated by_feature lines)")
		quit(1)
		return
	var pit_cell := Vector2i(5, 6)
	var pit_name := "Pit"
	var pit_seed := -1
	for sp in range(1, 25000):
		var evp: Dictionary = SFInv.evaluate(sp, pit_cell, pit_name)
		if str(evp.get("kind", "")) == "trap":
			pit_seed = sp
			break
	if pit_seed < 0:
		push_error("check_parse: expected Pit trap outcome in seed scan")
		quit(1)
		return
	var tc_pit := TrapCopy.message_for(pit_name, pit_seed, pit_cell)
	var tc_pit2 := TrapCopy.message_for(pit_name, pit_seed, pit_cell)
	if tc_pit != tc_pit2 or tc_pit.is_empty():
		push_error("check_parse: Pit trap copy empty or non-deterministic")
		quit(1)
		return
	if not (tc_pit.contains("False boards") or tc_pit.contains("rotten cover")):
		push_error("check_parse: Pit trap copy golden (expected curated by_feature lines)")
		quit(1)
		return
	var path_sf := "res://dungeon/data/special_feature_contents.json"
	var path_tr := "res://dungeon/data/feature_investigation_trap_copy.json"
	var txt_sf := FileAccess.get_file_as_string(path_sf)
	var txt_tr := FileAccess.get_file_as_string(path_tr)
	if txt_sf.is_empty() or txt_tr.is_empty():
		push_error("check_parse: feature trap parity JSON missing")
		quit(1)
		return
	var parsed_sf: Variant = JSON.parse_string(txt_sf)
	var parsed_tr: Variant = JSON.parse_string(txt_tr)
	if not parsed_sf is Dictionary or not parsed_tr is Dictionary:
		push_error("check_parse: feature trap parity JSON parse")
		quit(1)
		return
	var d_sf: Dictionary = parsed_sf as Dictionary
	var d_tr: Dictionary = parsed_tr as Dictionary
	var by_feat_chk: Variant = d_tr.get("by_feature", {})
	if not by_feat_chk is Dictionary:
		push_error("check_parse: trap copy by_feature not dict")
		quit(1)
		return
	var bf_chk: Dictionary = by_feat_chk as Dictionary
	for feat_key in d_sf.keys():
		var row_chk: Variant = d_sf[feat_key]
		if not row_chk is Dictionary:
			continue
		var tch: int = int((row_chk as Dictionary).get("trap_chance", 0))
		if tch <= 0:
			continue
		var fk := str(feat_key)
		if not bf_chk.has(fk):
			push_error("check_parse: trap copy missing by_feature for " + fk)
			quit(1)
			return
		var lines_chk: Variant = bf_chk[fk]
		if not lines_chk is Array:
			push_error("check_parse: trap copy lines not array for " + fk)
			quit(1)
			return
		var nonempty_lines := 0
		for line_chk in lines_chk as Array:
			if str(line_chk).strip_edges().length() > 0:
				nonempty_lines += 1
		if nonempty_lines < 2:
			push_error("check_parse: trap copy need >=2 nonempty lines for " + fk)
			quit(1)
			return
	const PlayerQuests := preload("res://dungeon/world/player_quests.gd")
	var pq_cell := Vector2i(3, 4)
	var pq_a: Dictionary = PlayerQuests.create_special_item_quest_from_rumor(
		42_424, 7, pq_cell, "Ancient Castle", 4, 1
	)
	var pq_b: Dictionary = PlayerQuests.create_special_item_quest_from_rumor(
		42_424, 7, pq_cell, "Ancient Castle", 4, 1
	)
	if str(pq_a.get("id", "")) != str(pq_b.get("id", "")):
		push_error("check_parse: quest id non-deterministic")
		quit(1)
		return
	if str(pq_a.get("type", "")) != "special_item" or str(pq_a.get("status", "")) != "active":
		push_error("check_parse: quest type/status")
		quit(1)
		return
	var xp_need: int = maxi(0, int(pq_a.get("xp_reward", 0)))
	if xp_need < 1:
		push_error("check_parse: quest xp_reward")
		quit(1)
		return
	var tiny_grid: Dictionary = {}
	tiny_grid[Vector2i(9, 9)] = "floor"
	var place_q: Vector2i = PlayerQuests.find_quest_item_placement(
		tiny_grid, 99, str(pq_a.get("id", "x"))
	)
	if place_q != Vector2i(9, 9):
		push_error("check_parse: quest item placement")
		quit(1)
		return
	var rumors_in: Array = [
		"other",
		(
			"x «"
			+ str(pq_a.get("magic_item_name", ""))
			+ "» y «"
			+ str(pq_a.get("target_theme", ""))
			+ "» z"
		)
	]
	var rumors_out: Array = PlayerQuests.filter_rumors_after_special_quest_complete(rumors_in, pq_a)
	if rumors_out.size() != 1 or str(rumors_out[0]) != "other":
		push_error("check_parse: quest rumor filter")
		quit(1)
		return
	var pq_pack := PlayerQuests.serialize_quests_for_rpc([pq_a])
	var pq_back: Array = PlayerQuests.deserialize_quests_from_rpc(pq_pack)
	if (
		pq_back.size() != 1
		or str((pq_back[0] as Dictionary).get("id", "")) != str(pq_a.get("id", ""))
	):
		push_error("check_parse: quest serialize roundtrip")
		quit(1)
		return
	# Phase 2: Explorer `QuestItemSystem` — no gold on special-item quest pickup (`reward_gold` unused at dismiss).
	var comp_body := PlayerQuests.completion_dialog_body(pq_a, 4)
	var comp_want := (
		"You found Bag of Holding of Cultist Lair! The rumor was true!\n\n"
		+ "You also received 50 XP!\n\n"
		+ "Your quest for the Bag of Holding has been completed successfully on level 4!"
	)
	if comp_body != comp_want:
		push_error("check_parse: completion_dialog_body special_item drift")
		quit(1)
		return
	var rumor_full := PlayerQuests.format_rumor_note("Trail whisper.", pq_a)
	if rumor_full.find("Trail whisper.") == -1:
		push_error("check_parse: format_rumor_note pool prefix")
		quit(1)
		return
	if rumor_full.find("Quest Discovered: Find Bag of Holding of Cultist Lair") == -1:
		push_error("check_parse: format_rumor_note quest headline")
		quit(1)
		return
	if (
		rumor_full.find(
			"Legend speaks of a powerful Bag of Holding hidden somewhere in the Cultist Lair."
		)
		== -1
	):
		push_error("check_parse: format_rumor_note explorer fallback paragraph")
		quit(1)
		return
	var rumor_no_pool := PlayerQuests.format_rumor_note("", pq_a)
	if rumor_no_pool.find("Trail whisper.") != -1:
		push_error("check_parse: format_rumor_note empty pool")
		quit(1)
		return
	if rumor_no_pool != PlayerQuests.rumor_fallback_body_for_quest(pq_a):
		push_error("check_parse: format_rumor_note empty pool equals fallback")
		quit(1)
		return
	var rumors_real: Array = ["other", rumor_no_pool]
	var rumors_rm: Array = PlayerQuests.filter_rumors_after_special_quest_complete(
		rumors_real, pq_a
	)
	if rumors_rm.size() != 1 or str(rumors_rm[0]) != "other":
		push_error("check_parse: filter_rumors after format_rumor_note body")
		quit(1)
		return
	var kq_seed := 55_555
	var kq_cell := Vector2i(11, 12)
	var g1: int = PlayerQuests.calculate_quest_reward_gold_deterministic(kq_seed, 3, kq_cell, 5)
	var g2: int = PlayerQuests.calculate_quest_reward_gold_deterministic(kq_seed, 3, kq_cell, 5)
	if g1 != g2 or g1 < 1:
		push_error("check_parse: kill-quest gold reward non-deterministic or empty")
		quit(1)
		return
	if g1 != 40:
		push_error("check_parse: kill-quest gold reward golden drift (update if RNG changes)")
		quit(1)
		return
	var kq_syn: Dictionary = {
		"quest_giver": "Merchant",
		"tldr_description": "Kill Rat in Swamp",
		"reward_gold": 37,
		"quest_alignment": "lawful",
	}
	var kq_rumor := PlayerQuests.kill_quest_rumor_line(kq_syn)
	if kq_rumor != "Quest from Merchant: Kill Rat in Swamp":
		push_error("check_parse: kill_quest_rumor_line golden drift")
		quit(1)
		return
	var rumors_kill: Array = ["other rumor", kq_rumor, "tail"]
	var rumors_filt: Array = PlayerQuests.filter_rumors_kill_quest_exact(rumors_kill, kq_syn)
	if (
		rumors_filt.size() != 2
		or str(rumors_filt[0]) != "other rumor"
		or str(rumors_filt[1]) != "tail"
	):
		push_error("check_parse: filter_rumors_kill_quest_exact")
		quit(1)
		return
	const RumorsListMessages := preload("res://dungeon/ui/rumors_list_messages.gd")
	if RumorsListMessages.WINDOW_TITLE != "Learned Rumors":
		push_error("check_parse: RumorsListMessages.WINDOW_TITLE drift")
		quit(1)
		return
	if (
		RumorsListMessages.EMPTY_STATE
		!= "No rumors have been discovered yet. Investigate special features to learn rumors!"
	):
		push_error("check_parse: RumorsListMessages.EMPTY_STATE drift")
		quit(1)
		return
	if RumorsListMessages.HINT_WHEN_HAS_RUMORS != "Click on any rumor to view it in detail:":
		push_error("check_parse: RumorsListMessages.HINT_WHEN_HAS_RUMORS drift")
		quit(1)
		return
	var r120 := ""
	for _ri in range(120):
		r120 += "R"
	if RumorsListMessages.list_preview_body(r120) != r120:
		push_error("check_parse: RumorsListMessages.list_preview_body 120 no ellipsis")
		quit(1)
		return
	var r121 := r120 + "X"
	var want121 := r120 + "..."
	if RumorsListMessages.list_preview_body(r121) != want121:
		push_error("check_parse: RumorsListMessages.list_preview_body 121 ellipsis")
		quit(1)
		return
	if RumorsListMessages.list_item_text(2, "hello\nworld") != "3. hello world":
		push_error("check_parse: RumorsListMessages.list_item_text golden drift")
		quit(1)
		return
	if PlayerQuests.kill_quest_alignment_delta(kq_syn) != 37:
		push_error("check_parse: kill_quest_alignment_delta lawful")
		quit(1)
		return
	kq_syn["quest_alignment"] = "chaotic"
	if PlayerQuests.kill_quest_alignment_delta(kq_syn) != -37:
		push_error("check_parse: kill_quest_alignment_delta chaotic")
		quit(1)
		return
	var ach_si: Dictionary = {
		"type": "special_item",
		"tldr_description": "Find the Orb in the Deep",
		"target_theme": "Ancient Castle",
		"magic_item_name": "Test Orb",
		"magic_item_key": "",
		"xp_reward": 99,
	}
	var got_si := PlayerQuests.achievement_text_for_completed_quest(ach_si)
	var want_si := (
		"Quest Completed: Find the Orb in the Deep\n\n"
		+ "You successfully found the Test Orb in the Ancient Castle! This legendary artifact was worth 99 XP."
	)
	if got_si != want_si:
		push_error("check_parse: achievement_text special_item drift")
		quit(1)
		return
	var ach_mk: Dictionary = {
		"type": "monster_kill",
		"tldr_description": "Slay the Beast",
		"target_monster": "Ogre",
		"target_theme": "Swamp",
		"quest_giver": "Captain",
		"reward_gold": 40,
		"xp_reward": 40,
	}
	var got_mk := PlayerQuests.achievement_text_for_completed_quest(ach_mk)
	var want_mk := (
		"Quest Completed: Slay the Beast\n\n"
		+ "You successfully defeated the Ogre in the Swamp! Captain will be grateful for your heroic deed. You earned 40 gold and 40 XP."
	)
	if got_mk != want_mk:
		push_error("check_parse: achievement_text monster_kill drift")
		quit(1)
		return
	var ach_nk: Dictionary = {
		"type": "npc_kill",
		"tldr_description": "Eliminate the spy",
		"target_npc": "Merchant",
		"target_theme": "City",
		"quest_giver": "Shadow",
		"reward_gold": 25,
		"xp_reward": 30,
	}
	var got_nk := PlayerQuests.achievement_text_for_completed_quest(ach_nk)
	var want_nk := (
		"Quest Completed: Eliminate the spy\n\n"
		+ "You successfully eliminated the Merchant in the City! Shadow will be pleased with your work. You earned 25 gold and 30 XP."
	)
	if got_nk != want_nk:
		push_error("check_parse: achievement_text npc_kill drift")
		quit(1)
		return
	var ach_def: Dictionary = {"type": "escort", "tldr_description": "Walk home", "xp_reward": 12}
	var got_def := PlayerQuests.achievement_text_for_completed_quest(ach_def)
	if (
		got_def
		!= "Quest Completed: Walk home\n\nYour quest has been completed successfully! You earned 12 XP."
	):
		push_error("check_parse: achievement_text default drift")
		quit(1)
		return
	const PlayerTalents := preload("res://dungeon/progression/player_talents.gd")
	var hp_g := PlayerTalents.roll_level_hit_points_deterministic(888_001, 2, 2)
	if hp_g != 3:
		push_error("check_parse: level-up HP roll golden drift")
		quit(1)
		return
	var r_g: Dictionary = PlayerTalents.roll_random_talent_deterministic(888_001, 2, 2)
	if int(r_g.get("branch", 0)) != 2 or int(r_g.get("bonus", 0)) != 1:
		push_error("check_parse: level-up talent roll golden drift")
		quit(1)
		return
	var sec_g := PlayerTalents.format_talent_secondary_message(r_g, hp_g)
	var ach_g := PlayerTalents.achievement_text_for_level_up(2, hp_g, sec_g)
	var want_lv_ach := (
		"Level 2 Achieved!\n\n"
		+ "You have reached level 2! You gained 3 hit points from leveling up! Talent: You gained +1 to Attack Bonus!"
	)
	if ach_g != want_lv_ach:
		push_error("check_parse: level-up achievement text drift")
		quit(1)
		return
	var t0 := PlayerTalents.default_talents()
	var r_hp: Dictionary = {
		"branch": 1, "bonus": 2, "message": "You gained +2 to Maximum Hit Points!"
	}
	var t1 := PlayerTalents.apply_talent_roll_to_dict(t0, r_hp)
	if int(t1.get("hit_points", 0)) != 2:
		push_error("check_parse: apply_talent_roll hp")
		quit(1)
		return
	var pst_prog: Dictionary = PlayerCombatStats.for_role_with_progression("rogue", 5, 2, 1, 1)
	if int(pst_prog.get("max_hit_points", 0)) != 11:
		push_error("check_parse: for_role_with_progression max_hp")
		quit(1)
		return
	if int(pst_prog.get("attack_bonus", 0)) != 2:
		push_error("check_parse: for_role_with_progression attack")
		quit(1)
		return
	if int(pst_prog.get("armor_class", 0)) != 13:
		push_error("check_parse: for_role_with_progression ac")
		quit(1)
		return
	const JoinMetadata := preload("res://dungeon/network/join_metadata.gd")
	var raw_ctl := "  a" + String.chr(1) + "b" + String.chr(9)
	if JoinMetadata.normalize_display_name(raw_ctl) != "ab":
		push_error("check_parse: join display_name normalize controls")
		quit(1)
		return
	var long_nm := ""
	for _j in range(50):
		long_nm += "x"
	if JoinMetadata.normalize_display_name(long_nm).length() != JoinMetadata.DISPLAY_NAME_MAX_LEN:
		push_error("check_parse: join display_name max length")
		quit(1)
		return
	if JoinMetadata.display_name_for_network_peer("", 7) != "Player 7":
		push_error("check_parse: join display_name network fallback")
		quit(1)
		return
	if JoinMetadata.display_name_for_solo("") != "Explorer":
		push_error("check_parse: join display_name solo fallback")
		quit(1)
		return
	if JoinMetadata.display_name_for_solo("  Sage  ") != "Sage":
		push_error("check_parse: join display_name solo trim")
		quit(1)
		return
	if JoinMetadata.truncate_for_map_marker("Bob") != "Bob":
		push_error("check_parse: join map_marker truncate short")
		quit(1)
		return
	var long_marker := ""
	for _lm in range(40):
		long_marker += "M"
	var tm := JoinMetadata.truncate_for_map_marker(long_marker)
	if tm.length() != JoinMetadata.MAP_MARKER_LABEL_MAX_LEN:
		push_error("check_parse: join map_marker truncate length")
		quit(1)
		return
	if not tm.ends_with("\u2026"):
		push_error("check_parse: join map_marker truncate ellipsis")
		quit(1)
		return
	if JoinMetadata.welcome_hud_tail({}) != "":
		push_error("check_parse: join welcome_hud_tail empty welcome")
		quit(1)
		return
	if JoinMetadata.welcome_hud_tail({"listen_port": 0, "party_peer_count": 3}) != "":
		push_error("check_parse: join welcome_hud_tail zero port")
		quit(1)
		return
	if (
		JoinMetadata.welcome_hud_tail({"listen_port": 12345, "party_peer_count": 2})
		!= "  |  Server TCP 12345 · party 2"
	):
		push_error("check_parse: join welcome_hud_tail text")
		quit(1)
		return
	const ExplorerAudioScript := preload("res://dungeon/audio/explorer_audio.gd")
	const _explorer_combat_sound_ids: Array[String] = [
		"fight",
		"monster_hit",
		"monster_miss",
		"player_hit",
		"player_miss",
	]
	for _ci in range(_explorer_combat_sound_ids.size()):
		var _csid: String = _explorer_combat_sound_ids[_ci]
		var _cbn := ExplorerAudioScript.combat_sfx_basename_for_sound_id(_csid)
		var _cexp := _csid + ".mp3"
		if _cbn != _cexp:
			push_error("check_parse: explorer_audio combat_sfx basename %s" % _csid)
			quit(1)
			return
	if not ExplorerAudioScript.combat_sfx_basename_for_sound_id("unknown_sound").is_empty():
		push_error("check_parse: explorer_audio combat_sfx unknown empty")
		quit(1)
		return
	for _pi in range(ExplorerAudioScript.EXPLORER_PLAY_AUDIO_SOUND_IDS.size()):
		var _play_id: String = ExplorerAudioScript.EXPLORER_PLAY_AUDIO_SOUND_IDS[_pi]
		var _asset := "res://assets/explorer/audio/" + _play_id + ".mp3"
		if not ResourceLoader.exists(_asset):
			push_error("check_parse: explorer_audio missing play_audio asset %s" % _asset)
			quit(1)
			return
	if ExplorerAudioScript.clamp_wander_resume_seconds(null, 3.5) != 3.5:
		push_error("check_parse: explorer_audio clamp null stream")
		quit(1)
		return
	var empty_ogg := AudioStreamOggVorbis.new()
	if ExplorerAudioScript.clamp_wander_resume_seconds(empty_ogg, 7.25) != 7.25:
		push_error("check_parse: explorer_audio clamp zero-length stream")
		quit(1)
		return
	var wander_st: Resource = ResourceLoader.load(
		"res://assets/explorer/audio/dungeon_wanderer1.mp3"
	)
	if wander_st is AudioStream:
		var wlen := (wander_st as AudioStream).get_length()
		if wlen > 1.0:
			var cap := wlen - 0.05
			var c_big := ExplorerAudioScript.clamp_wander_resume_seconds(
				wander_st as AudioStream, 1.0e9
			)
			if absf(c_big - cap) > 0.02:
				push_error("check_parse: explorer_audio clamp vs stream length")
				quit(1)
				return
	## Door/treasure trap disarm RNG (Explorer DC 15, `1d2` door damage) — static helper for CI + parity with `_roll_trap_disarm`.
	const DungeonReplication := preload("res://dungeon/network/dungeon_replication.gd")
	if int(DungeonReplication.WELCOME_SCHEMA_VERSION) != 9:
		push_error("check_parse: WELCOME_SCHEMA_VERSION expected 9 (Phase 3 join metadata)")
		quit(1)
		return
	const TRAP_DISARM_DC := 15
	if absf(DungeonReplication.MONSTER_COMBAT_UI_DELAY_SEC - 0.4) > 0.0001:
		push_error("check_parse: MONSTER_COMBAT_UI_DELAY_SEC expected 0.4 (Explorer send_after)")
		quit(1)
		return
	if int(DungeonReplication.TRAP_DISARM_XP_TREASURE) != 10:
		push_error("check_parse: TRAP_DISARM_XP_TREASURE must match Explorer trap disarm XP")
		quit(1)
		return
	if not bool(DungeonReplication.LIVE_TILE_PATCH_RPC_BATCHING):
		push_error(
			"check_parse: LIVE_TILE_PATCH_RPC_BATCHING must stay true (Phase 8 live tile RPC coalescing)"
		)
		quit(1)
		return
	for s in range(200):
		for x in range(3):
			for y in range(3):
				var c := Vector2i(x, y)
				for db in [0, 2, 5]:
					var rd: Dictionary = DungeonReplication.roll_trap_disarm_deterministic(
						s, 1, c, db
					)
					var d20: int = int(rd["d20"])
					var dmg: int = int(rd["dmg"])
					var tot: int = int(rd["total"])
					if d20 < 1 or d20 > 20 or dmg < 1 or dmg > 2:
						push_error("check_parse: door trap disarm roll range")
						quit(1)
						return
					if int(rd["bonus"]) != db:
						push_error("check_parse: door trap disarm bonus passthrough")
						quit(1)
						return
					if tot != d20 + db:
						push_error("check_parse: door trap disarm total")
						quit(1)
						return
					if bool(rd["ok"]) != (tot >= TRAP_DISARM_DC):
						push_error("check_parse: door trap disarm ok vs DC")
						quit(1)
						return
					if DungeonReplication.roll_trap_disarm_deterministic(s, 1, c, db) != rd:
						push_error("check_parse: door trap disarm determinism")
						quit(1)
						return
	## FOG-01: torch-expire fog reset must match Explorer `initialize_revealed_with_light` (R1 + player disk + lights).
	## Player far from R1 so an R1 interior cell is only revealed via the R1 branch, not the player Chebyshev disk.
	const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")
	var fog_grid: Dictionary = {}
	var r1_room := {"number": "R1", "x": 4, "y": 4, "width": 3, "height": 3}
	for x in range(4, 7):
		for y in range(4, 7):
			fog_grid[Vector2i(x, y)] = "floor"
	var fog_player := Vector2i(40, 40)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var fog_pc := fog_player + Vector2i(dx, dy)
			if not fog_grid.has(fog_pc):
				fog_grid[fog_pc] = "floor"
	var fog_rooms: Array = [r1_room]
	var fog_rev: Dictionary = {}
	DungeonFog.seed_initial_revealed_with_light(fog_rev, fog_grid, fog_player, fog_rooms, "dim")
	if not bool(fog_rev.get(Vector2i(5, 5), false)):
		push_error(
			"check_parse: FOG-01 seed_initial_revealed_with_light must reveal R1 away from player disk"
		)
		quit(1)
		return
	## FOG-02: static light disk radius follows theme fog_type (dim > dark around a torch).
	var fog_lt: Dictionary = {}
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			fog_lt[Vector2i(dx, dy)] = "floor"
	for dx2 in range(-2, 3):
		for dy2 in range(-2, 3):
			fog_lt[Vector2i(10 + dx2, dy2)] = "floor"
	fog_lt[Vector2i(10, 0)] = "torch"
	var fog_dim_lt: Dictionary = {}
	var fog_dark_lt: Dictionary = {}
	DungeonFog.seed_initial_revealed_with_light(fog_dim_lt, fog_lt, Vector2i(0, 0), [], "dim")
	DungeonFog.seed_initial_revealed_with_light(fog_dark_lt, fog_lt, Vector2i(0, 0), [], "dark")
	if fog_dim_lt.size() <= fog_dark_lt.size():
		push_error(
			"check_parse: FOG-02 dim fog must reveal strictly more cells than dark (static torch)"
		)
		quit(1)
		return
	if (
		not bool(fog_dim_lt.get(Vector2i(12, 0), false))
		or bool(fog_dark_lt.get(Vector2i(12, 0), false))
	):
		push_error(
			"check_parse: FOG-02 torch at (10,0): dim must reveal (12,0), dark must not (Chebyshev r=2 vs 1)"
		)
		quit(1)
		return
	const PartyMarkerArt := preload("res://dungeon/ui/party_marker_art.gd")
	if PartyMarkerArt.facing_from_grid_step(Vector2i(1, 0)) != PartyMarkerArt.FACING_RIGHT:
		push_error("check_parse: MOV-01 facing step (+1,0) -> right")
		quit(1)
		return
	if PartyMarkerArt.facing_from_grid_step(Vector2i(-1, 0)) != PartyMarkerArt.FACING_LEFT:
		push_error("check_parse: MOV-01 facing step (-1,0) -> left")
		quit(1)
		return
	if PartyMarkerArt.facing_from_grid_step(Vector2i(0, 1)) != PartyMarkerArt.FACING_DOWN:
		push_error("check_parse: MOV-01 facing step (0,+1) -> down")
		quit(1)
		return
	if PartyMarkerArt.facing_from_grid_step(Vector2i(0, -1)) != PartyMarkerArt.FACING_UP:
		push_error("check_parse: MOV-01 facing step (0,-1) -> up")
		quit(1)
		return
	if PartyMarkerArt.facing_from_grid_step(Vector2i(2, -1)) != PartyMarkerArt.FACING_RIGHT:
		push_error("check_parse: MOV-01 diagonal prefers horizontal facing")
		quit(1)
		return
	if PartyMarkerArt.facing_from_grid_step(Vector2i(-1, 1)) != PartyMarkerArt.FACING_LEFT:
		push_error("check_parse: MOV-01 diagonal (-1,1) prefers horizontal -> left")
		quit(1)
		return
	var walk_frames := PartyMarkerArt.walk_frame_textures("rogue", 0, false)
	if walk_frames.size() != 1:
		push_error(
			"check_parse: Phase 6 default assets must expose exactly one walk frame per facing (got ",
			str(walk_frames.size()),
			")"
		)
		quit(1)
		return
	if walk_frames[0] == null:
		push_error(
			"check_parse: Phase 6 walk_frame_textures base must be non-null for rogue facing 0"
		)
		quit(1)
		return
	## FOG-01 follow-up: traditional rect R1 — Explorer `get_room_surrounding_squares` includes y = ry+rh+1 (extra row below).
	var r1_rect := {"number": "R1", "x": 20, "y": 20, "width": 2, "height": 2}
	var fog_grid_rect: Dictionary = {}
	for x in range(20, 22):
		for y in range(20, 22):
			fog_grid_rect[Vector2i(x, y)] = "floor"
	var fog_player_rect := Vector2i(40, 40)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var fog_pr := fog_player_rect + Vector2i(dx, dy)
			if not fog_grid_rect.has(fog_pr):
				fog_grid_rect[fog_pr] = "floor"
	var fog_rev_rect: Dictionary = {}
	DungeonFog.seed_initial_revealed_with_light(
		fog_rev_rect, fog_grid_rect, fog_player_rect, [r1_rect], "dim"
	)
	if not bool(fog_rev_rect.get(Vector2i(20, 23), false)):
		push_error(
			"check_parse: FOG-01 rect R1 must reveal Explorer bottom surround row (y=ry+rh+1)"
		)
		quit(1)
		return
	## FOG-01 follow-up: cavern `cells` R1 — union of 8-neighbors outside interior (Explorer `get_cavern_surrounding_squares`).
	var r1_cav := {"number": "R1", "cells": [Vector2i(10, 10), Vector2i(11, 10), Vector2i(10, 11)]}
	var fog_grid_cav: Dictionary = {}
	for c in r1_cav["cells"]:
		fog_grid_cav[c as Vector2i] = "floor"
	var fog_player_cav := Vector2i(40, 40)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var fog_pcav := fog_player_cav + Vector2i(dx, dy)
			if not fog_grid_cav.has(fog_pcav):
				fog_grid_cav[fog_pcav] = "floor"
	var fog_rev_cav: Dictionary = {}
	DungeonFog.seed_initial_revealed_with_light(
		fog_rev_cav, fog_grid_cav, fog_player_cav, [r1_cav], "dim"
	)
	if not bool(fog_rev_cav.get(Vector2i(9, 9), false)):
		push_error("check_parse: FOG-01 cavern R1 must reveal diagonal neighbor (9,9)")
		quit(1)
		return
	if not bool(fog_rev_cav.get(Vector2i(12, 10), false)):
		push_error("check_parse: FOG-01 cavern R1 must reveal east neighbor (12,10)")
		quit(1)
		return
	if not bool(fog_rev_cav.get(Vector2i(11, 12), false)):
		push_error("check_parse: FOG-01 cavern R1 must reveal south-east neighbor (11,12)")
		quit(1)
		return
	const ExplorerModalChrome := preload("res://dungeon/ui/explorer_modal_chrome.gd")
	var chrome_err := ExplorerModalChrome.assert_distinct_schemes_and_variants()
	if not chrome_err.is_empty():
		push_error("check_parse: explorer_modal_chrome — " + chrome_err)
		quit(1)
		return
	quit(0)
