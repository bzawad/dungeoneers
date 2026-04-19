extends Node

## Local session: generate a dungeon and show it (first step toward `DungeonWeb.DungeonLive` mount).

const TraditionalGen := preload("res://dungeon/generator/traditional_generator.gd")
const DungeonGridView := preload("res://dungeon/ui/dungeon_grid_view.gd")
const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")
const GridPathfinding := preload("res://dungeon/movement/grid_pathfinding.gd")
const GridWalk := preload("res://dungeon/movement/grid_walkability.gd")
const DungeonTileAssets := preload("res://dungeon/ui/dungeon_tile_assets.gd")
const PlayerAlignment := preload("res://dungeon/progression/player_alignment.gd")
const SpecialItemTable := preload("res://dungeon/world/special_item_table.gd")
const JoinMetadata := preload("res://dungeon/network/join_metadata.gd")
const RumorsListMessages := preload("res://dungeon/ui/rumors_list_messages.gd")
const ExplorerAudioScript := preload("res://dungeon/audio/explorer_audio.gd")
const ExplorerModalChrome := preload("res://dungeon/ui/explorer_modal_chrome.gd")

var last_seed: int = 0
var _path_grid: Dictionary = {}
var _net_local_cell: Vector2i = Vector2i.ZERO
var _local_peer_id: int = -1
var _client_revealed: Dictionary = {}
var _client_unlocked: Dictionary = {}
var _client_fog_clicked: Dictionary = {}
var _welcome_fog_on: bool = false
var _net_rep: Node = null
var _grid_view: Node2D = null

var _door_window: Window = null
var _door_message: Label = null
var _door_prompt_icon: TextureRect = null
var _door_ok_button: Button = null
var _door_break_row: HBoxContainer = null
var _door_break_btn: Button = null
var _door_cancel_btn: Button = null
var _pending_door_action: String = ""
var _pending_door_cell: Vector2i = Vector2i.ZERO
var _trap_defused: Dictionary = {}
var _world_dialog: AcceptDialog = null
var _pending_world_kind: String = ""
var _pending_world_cell: Vector2i = Vector2i.ZERO
var _special_feature_window: Window = null
var _special_feature_message_label: Label = null
var _special_feature_investigate_btn: Button = null
var _special_feature_close_btn: Button = null
var _pending_special_feature_cell: Vector2i = Vector2i.ZERO
var _treasure_trap_window: Window = null
var _treasure_trap_message_label: Label = null
var _treasure_trap_disarm_btn: Button = null
var _treasure_trap_leave_btn: Button = null
var _pending_trapped_treasure_cell: Vector2i = Vector2i.ZERO
var _room_trap_window: Window = null
var _room_trap_message_label: Label = null
var _room_trap_disarm_btn: Button = null
var _room_trap_leave_btn: Button = null
var _pending_room_trap_cell: Vector2i = Vector2i.ZERO
var _rumors_lines: PackedStringArray = PackedStringArray()
var _rumors_list_btn: Button = null
var _rumors_list_window: Window = null
var _rumors_item_list: ItemList = null
var _rumors_list_hint: Label = null
var _rumors_view_btn: Button = null
var _rumors_close_btn: Button = null
var _quest_rows: PackedStringArray = PackedStringArray()
var _special_item_keys: PackedStringArray = PackedStringArray()
var _special_items_list_btn: Button = null
var _special_items_list_window: Window = null
var _special_items_item_list: ItemList = null
var _special_items_list_hint: Label = null
var _special_items_view_btn: Button = null
var _special_items_close_btn: Button = null
var _achievements_lines: PackedStringArray = PackedStringArray()
var _achievements_list_btn: Button = null
var _achievements_list_window: Window = null
var _achievements_item_list: ItemList = null
var _achievements_list_hint: Label = null
var _achievements_view_btn: Button = null
var _achievements_close_btn: Button = null
var _encounter_window: Window = null
var _encounter_message_label: Label = null
var _encounter_fight_btn: Button = null
var _encounter_evade_btn: Button = null
var _pending_encounter_cell: Vector2i = Vector2i.ZERO
var _npc_quest_offer_window: Window = null
var _npc_quest_offer_label: Label = null
var _npc_quest_accept_btn: Button = null
var _npc_quest_decline_btn: Button = null
var _pending_npc_quest_cell: Vector2i = Vector2i.ZERO
var _encounter_res_dialog: AcceptDialog = null
var _level_up_dialog: AcceptDialog = null
var _combat_window: Window = null
var _combat_title_label: Label = null
var _combat_log_label: Label = null
var _combat_hp_label: Label = null
var _combat_attack_btn: Button = null
var _combat_flee_btn: Button = null
var _combat_finish_timer: Variant = null
## Last encounter cell for Fight / Evade (Evade fail must start combat like Explorer `handle_failed_encounter_evade`).
var _last_encounter_fight_cell: Vector2i = Vector2i.ZERO
var _pending_victory_treasure_gold: int = 0
var _combat_finish_title: String = ""
var _combat_finish_body: String = ""
var _combat_finish_victory: bool = false
var _combat_finish_flee_success: bool = false
var _combat_finish_treasure: int = 0
var _cb_net_player_pos: Callable
var _cb_net_fog_delta: Callable
var _cb_net_fog_full: Callable
var _cb_secret_doors_snap: Callable
var _cb_secret_doors_delta: Callable
var _cb_fog_clicked_snap: Callable
var _cb_fog_clicked_delta: Callable
var _net_view_signals_bound: bool = false
var _secret_door_notice: AcceptDialog = null
var _stats_layer: CanvasLayer = null
var _stats_label: Label = null
var _audio_settings_btn: Button = null
var _audio_settings_window: Window = null
var _audio_sfx_slider: HSlider = null
var _audio_music_slider: HSlider = null
var _hud_guards_hostile: bool = false
var _last_gold: int = 0
var _last_xp: int = 0
var _last_hp: int = 0
var _last_max_hp: int = 0
var _last_level: int = 1
var _last_xp_to_next: int = 500
var _last_player_alignment: int = 0
## Explorer `npcs_killed_count` (replicated via `player_local_stats_changed`).
var _last_npcs_killed: int = 0
## P7-09: co-op / solo display name from welcome + `player_display_name_changed`.
var _last_display_name: String = "Explorer"
## Phase 3: from welcome (`listen_port` / `party_peer_count`); empty for solo.
var _welcome_join_hud_tail: String = ""
## P7-09: map marker labels — peer_id (int) → display string (authority / `peer_display_names_updated`).
var _peer_display_names_by_id: Dictionary = {}
var _last_peer_cells: Dictionary = {}
var _last_peer_roles: Dictionary = {}
## From `player_local_stats_changed`: burn 0–100, spares ≥0; burn **-1** = hide torch (no fog).
var _hud_torch_burn: int = -1
var _hud_torch_spares: int = -1

## AUD-01: client-only stepped marker + `play_move_step` per edge; server still sends one position sync per path.
const PATH_VISUAL_STEP_SEC := 0.072
var _path_visual_gen: int = 0
var _path_visual_active: bool = false
var _path_visual_path: PackedVector2Array = PackedVector2Array()
var _path_visual_start: Vector2i = Vector2i.ZERO
var _path_visual_display: Vector2i = Vector2i.ZERO
var _path_visual_next_idx: int = 0
var _path_visual_audio_edges: int = 0
var _path_step_timer: Timer = null
var _explorer_audio_cache: Node = null


## Resolve project autoload: `Engine.get_singleton` can be null; `get_tree().root` may be a SubViewport root.
func _explorer_audio() -> ExplorerAudioScript:
	if _explorer_audio_cache != null and is_instance_valid(_explorer_audio_cache):
		return _explorer_audio_cache as ExplorerAudioScript
	var n: Node = null
	var roots: Array[Node] = []
	if is_inside_tree():
		roots.append(get_tree().root)
	var main_loop := Engine.get_main_loop()
	if main_loop is SceneTree:
		var mr := (main_loop as SceneTree).root
		if mr != null and not roots.has(mr):
			roots.append(mr)
	for r in roots:
		if r == null:
			continue
		n = r.get_node_or_null(NodePath("ExplorerAudio"))
		if n != null:
			break
		for c in r.get_children():
			if str(c.name) == "ExplorerAudio":
				n = c
				break
		if n != null:
			break
	if n == null:
		n = Engine.get_singleton(&"ExplorerAudio") as Node
	if n != null:
		_explorer_audio_cache = n
		return n as ExplorerAudioScript
	# Last resort: local node so `_ready` runs (pools / buses); only when autoload is missing.
	var fb := ExplorerAudioScript.new()
	fb.name = "ExplorerAudioEmbedded"
	add_child(fb)
	_explorer_audio_cache = fb
	push_warning(
		"[Dungeoneers] ExplorerAudio autoload not found; embedded fallback under DungeonSession (audio may duplicate if fixed later)."
	)
	return fb as ExplorerAudioScript


func start_local(authority_seed: int, theme_direction: String) -> void:
	var rng := RandomNumberGenerator.new()
	if authority_seed >= 0:
		rng.seed = authority_seed
	else:
		rng.randomize()
	last_seed = int(rng.seed)
	var theme := theme_direction
	if theme != "up" and theme != "down":
		theme = "up"
	var result: Dictionary = TraditionalGen.generate(rng, theme)
	var view: Node2D = DungeonGridView.new()
	view.name = "DungeonGridView"
	add_child(view)
	_grid_view = view
	view.setup_from_grid(
		result["grid"],
		str(result.get("floor_theme", "")),
		str(result.get("wall_theme", "")),
		str(result.get("generation_type", "dungeon")),
		result.get("rooms", []) if result.get("rooms", []) is Array else [],
		str(result.get("road_theme", "")),
		str(result.get("shrub_theme", ""))
	)
	view.set_view_center_from_cell(DungeonGridView.find_starting_cell_for_camera(result["grid"]))
	view.configure_fog(false, {}, str(result.get("fog_type", "dim")))
	_ensure_stats_hud()
	_refresh_stats_hud_text()


func start_from_grid(
	grid: Dictionary,
	seed_for_log: int,
	net_rep: Node = null,
	local_peer_id: int = -1,
	welcome: Dictionary = {}
) -> void:
	_cancel_path_visual()
	last_seed = seed_for_log
	_path_grid = grid
	_local_peer_id = local_peer_id
	var view: Node2D = DungeonGridView.new()
	view.name = "DungeonGridView"
	add_child(view)
	_grid_view = view
	var rooms_w: Array = []
	if welcome.get("rooms", []) is Array:
		rooms_w = welcome.get("rooms", []) as Array
	view.setup_from_grid(
		grid,
		str(welcome.get("floor_theme", "")),
		str(welcome.get("wall_theme", "")),
		str(welcome.get("generation_type", "dungeon")),
		rooms_w,
		str(welcome.get("road_theme", "")),
		str(welcome.get("shrub_theme", ""))
	)
	if net_rep != null and local_peer_id >= 0:
		_net_rep = net_rep
		_net_local_cell = Vector2i(int(welcome.get("spawn_x", 0)), int(welcome.get("spawn_y", 0)))
		_welcome_fog_on = bool(welcome.get("fog_enabled", true))
		_client_revealed.clear()
		_client_unlocked.clear()
		_client_fog_clicked.clear()
		_trap_defused.clear()
		if _welcome_fog_on:
			var r_rooms: Array = []
			if welcome.get("rooms", []) is Array:
				r_rooms = welcome.get("rooms", []) as Array
			var ft0 := str(welcome.get("fog_type", "dim"))
			DungeonFog.seed_initial_revealed_with_light(
				_client_revealed, grid, _net_local_cell, r_rooms, ft0
			)
		view.configure_fog(_welcome_fog_on, _client_revealed, str(welcome.get("fog_type", "dim")))
		view.init_network_markers(local_peer_id)
		view.set_view_center_from_cell(_net_local_cell)
		_apply_display_name_from_welcome(welcome)
		_apply_welcome_peer_display_names(welcome)
		_welcome_join_hud_tail = JoinMetadata.welcome_hud_tail(welcome)
		# Show the player marker immediately at the spawn cell — `player_position_updated`
		# fires during the authority sync, before `start_from_grid` connects to the signal,
		# so the initial position would otherwise be invisible until the first move.
		view.sync_peer_marker(
			local_peer_id,
			_net_local_cell,
			str(welcome.get("role", "rogue")),
			_marker_label_text(local_peer_id)
		)
		_cb_net_player_pos = _on_net_player_position.bind(view)
		_cb_net_fog_delta = _on_net_fog_delta.bind(view)
		_cb_net_fog_full = _on_net_fog_full_resync.bind(view)
		_cb_secret_doors_snap = _on_secret_doors_snapshot.bind(view)
		_cb_secret_doors_delta = _on_secret_doors_delta.bind(view)
		_cb_fog_clicked_snap = _on_fog_clicked_cells_snapshot.bind(view)
		_cb_fog_clicked_delta = _on_fog_clicked_cells_delta.bind(view)
		net_rep.player_position_updated.connect(_cb_net_player_pos)
		net_rep.fog_reveal_delta.connect(_cb_net_fog_delta)
		net_rep.fog_full_resync.connect(_cb_net_fog_full)
		net_rep.secret_doors_snapshot.connect(_cb_secret_doors_snap)
		net_rep.secret_doors_delta.connect(_cb_secret_doors_delta)
		net_rep.fog_clicked_cells_snapshot.connect(_cb_fog_clicked_snap)
		net_rep.fog_clicked_cells_delta.connect(_cb_fog_clicked_delta)
		net_rep.unlocked_doors_snapshot.connect(_on_unlocked_doors_snapshot)
		net_rep.unlocked_doors_delta.connect(_on_unlocked_doors_delta)
		net_rep.trap_inspected_doors_snapshot.connect(_on_trap_inspected_doors_snapshot)
		net_rep.trap_inspected_doors_delta.connect(_on_trap_inspected_doors_delta)
		net_rep.trap_defused_doors_snapshot.connect(_on_trap_defused_doors_snapshot)
		net_rep.trap_defused_doors_delta.connect(_on_trap_defused_doors_delta)
		net_rep.door_prompt_offered.connect(_on_door_prompt_offered)
		net_rep.world_interaction_offered.connect(_on_world_interaction_offered)
		net_rep.authority_tile_patched.connect(_on_authority_tile_patched)
		net_rep.player_local_stats_changed.connect(_on_player_local_stats_changed)
		net_rep.encounter_resolution_dialog.connect(_on_encounter_resolution_dialog)
		net_rep.combat_state_changed.connect(_on_combat_state_changed)
		if net_rep.has_signal("player_rumors_updated"):
			net_rep.player_rumors_updated.connect(_on_player_rumors_updated)
		if net_rep.has_signal("player_special_items_updated"):
			net_rep.player_special_items_updated.connect(_on_player_special_items_updated)
		if net_rep.has_signal("player_quests_updated"):
			net_rep.player_quests_updated.connect(_on_player_quests_updated)
		if net_rep.has_signal("player_achievements_updated"):
			net_rep.player_achievements_updated.connect(_on_player_achievements_updated)
		if net_rep.has_signal("level_up_dialog_offered"):
			net_rep.level_up_dialog_offered.connect(_on_level_up_dialog_offered)
		if net_rep.has_signal("player_display_name_changed"):
			net_rep.player_display_name_changed.connect(_on_player_display_name_changed)
		if net_rep.has_signal("peer_display_names_updated"):
			net_rep.peer_display_names_updated.connect(_on_peer_display_names_updated)
		if not net_rep.guards_hostile_changed.is_connected(_on_guards_hostile_changed):
			net_rep.guards_hostile_changed.connect(_on_guards_hostile_changed)
		_net_view_signals_bound = true
		_ensure_door_prompt_window()
		_ensure_encounter_choice_window()
		set_process_unhandled_input(true)
		view.cell_clicked.connect(func(c: Vector2i) -> void: _on_net_grid_clicked(c, net_rep, view))
		_explorer_audio().start_wander_music_from_seed(seed_for_log)
		if net_rep.has_method("guards_hostile"):
			_on_guards_hostile_changed(bool(net_rep.call("guards_hostile")))
		if view.has_method("set_guards_hostile"):
			view.set_guards_hostile(_hud_guards_hostile)
		_ensure_stats_hud()
		_refresh_stats_hud_text()


## Full dungeon swap (Phase 5.2 map transition): new grid + fog + spawn; net signals stay bound once.
func reload_from_authority(grid: Dictionary, seed_for_log: int, welcome: Dictionary) -> void:
	if _net_rep == null or _local_peer_id < 0:
		return
	_cancel_path_visual()
	_clear_combat_finish_timer()
	if _rumors_list_window != null and _rumors_list_window.visible:
		_rumors_list_window.hide()
		_set_grid_hover_polish_for_modal(false)
	if _special_items_list_window != null and _special_items_list_window.visible:
		_special_items_list_window.hide()
		_set_grid_hover_polish_for_modal(false)
	if _achievements_list_window != null and _achievements_list_window.visible:
		_achievements_list_window.hide()
		_set_grid_hover_polish_for_modal(false)
	if _level_up_dialog != null and _level_up_dialog.visible:
		_level_up_dialog.hide()
		_set_grid_hover_polish_for_modal(false)
	if _net_view_signals_bound:
		_net_rep.player_position_updated.disconnect(_cb_net_player_pos)
		_net_rep.fog_reveal_delta.disconnect(_cb_net_fog_delta)
		_net_rep.fog_full_resync.disconnect(_cb_net_fog_full)
		if _net_rep.secret_doors_snapshot.is_connected(_cb_secret_doors_snap):
			_net_rep.secret_doors_snapshot.disconnect(_cb_secret_doors_snap)
		if _net_rep.secret_doors_delta.is_connected(_cb_secret_doors_delta):
			_net_rep.secret_doors_delta.disconnect(_cb_secret_doors_delta)
		if _net_rep.fog_clicked_cells_snapshot.is_connected(_cb_fog_clicked_snap):
			_net_rep.fog_clicked_cells_snapshot.disconnect(_cb_fog_clicked_snap)
		if _net_rep.fog_clicked_cells_delta.is_connected(_cb_fog_clicked_delta):
			_net_rep.fog_clicked_cells_delta.disconnect(_cb_fog_clicked_delta)
		if (
			_net_rep.has_signal("player_display_name_changed")
			and _net_rep.player_display_name_changed.is_connected(_on_player_display_name_changed)
		):
			_net_rep.player_display_name_changed.disconnect(_on_player_display_name_changed)
		if (
			_net_rep.has_signal("peer_display_names_updated")
			and _net_rep.peer_display_names_updated.is_connected(_on_peer_display_names_updated)
		):
			_net_rep.peer_display_names_updated.disconnect(_on_peer_display_names_updated)
		_net_view_signals_bound = false
	last_seed = seed_for_log
	_path_grid = grid
	_net_local_cell = Vector2i(int(welcome.get("spawn_x", 0)), int(welcome.get("spawn_y", 0)))
	_welcome_fog_on = bool(welcome.get("fog_enabled", true))
	_client_revealed.clear()
	_client_unlocked.clear()
	_client_fog_clicked.clear()
	_trap_defused.clear()
	if _welcome_fog_on:
		var r_rooms2: Array = []
		if welcome.get("rooms", []) is Array:
			r_rooms2 = welcome.get("rooms", []) as Array
		var ft1 := str(welcome.get("fog_type", "dim"))
		DungeonFog.seed_initial_revealed_with_light(
			_client_revealed, grid, _net_local_cell, r_rooms2, ft1
		)
	if _grid_view != null:
		_grid_view.queue_free()
		_grid_view = null
	var view: Node2D = DungeonGridView.new()
	view.name = "DungeonGridView"
	add_child(view)
	_grid_view = view
	var rooms_r: Array = []
	if welcome.get("rooms", []) is Array:
		rooms_r = welcome.get("rooms", []) as Array
	view.setup_from_grid(
		grid,
		str(welcome.get("floor_theme", "")),
		str(welcome.get("wall_theme", "")),
		str(welcome.get("generation_type", "dungeon")),
		rooms_r,
		str(welcome.get("road_theme", "")),
		str(welcome.get("shrub_theme", ""))
	)
	view.configure_fog(_welcome_fog_on, _client_revealed, str(welcome.get("fog_type", "dim")))
	view.init_network_markers(_local_peer_id)
	view.set_view_center_from_cell(_net_local_cell)
	_apply_display_name_from_welcome(welcome)
	_apply_welcome_peer_display_names(welcome)
	_welcome_join_hud_tail = JoinMetadata.welcome_hud_tail(welcome)
	# Show the player marker at the new spawn cell immediately after reload.
	view.sync_peer_marker(
		_local_peer_id,
		_net_local_cell,
		str(welcome.get("role", "rogue")),
		_marker_label_text(_local_peer_id)
	)
	_cb_net_player_pos = _on_net_player_position.bind(view)
	_cb_net_fog_delta = _on_net_fog_delta.bind(view)
	_cb_net_fog_full = _on_net_fog_full_resync.bind(view)
	_cb_secret_doors_snap = _on_secret_doors_snapshot.bind(view)
	_cb_secret_doors_delta = _on_secret_doors_delta.bind(view)
	_cb_fog_clicked_snap = _on_fog_clicked_cells_snapshot.bind(view)
	_cb_fog_clicked_delta = _on_fog_clicked_cells_delta.bind(view)
	_net_rep.player_position_updated.connect(_cb_net_player_pos)
	_net_rep.fog_reveal_delta.connect(_cb_net_fog_delta)
	_net_rep.fog_full_resync.connect(_cb_net_fog_full)
	_net_rep.secret_doors_snapshot.connect(_cb_secret_doors_snap)
	_net_rep.secret_doors_delta.connect(_cb_secret_doors_delta)
	_net_rep.fog_clicked_cells_snapshot.connect(_cb_fog_clicked_snap)
	_net_rep.fog_clicked_cells_delta.connect(_cb_fog_clicked_delta)
	if _net_rep.has_signal("player_display_name_changed"):
		_net_rep.player_display_name_changed.connect(_on_player_display_name_changed)
	if _net_rep.has_signal("peer_display_names_updated"):
		_net_rep.peer_display_names_updated.connect(_on_peer_display_names_updated)
	_net_view_signals_bound = true
	view.cell_clicked.connect(func(c: Vector2i) -> void: _on_net_grid_clicked(c, _net_rep, view))
	if view.has_method("set_guards_hostile"):
		view.set_guards_hostile(_hud_guards_hostile)
	_explorer_audio().start_wander_music_from_seed(seed_for_log)


func _ensure_secret_door_notice_dialog() -> void:
	if _secret_door_notice != null:
		return
	_secret_door_notice = AcceptDialog.new()
	_secret_door_notice.name = "SecretDoorNotice"
	_secret_door_notice.title = "Secret door"
	_secret_door_notice.ok_button_text = "OK"
	_secret_door_notice.unresizable = true
	_secret_door_notice.confirmed.connect(_on_secret_door_notice_confirmed)
	_secret_door_notice.canceled.connect(_on_secret_door_notice_confirmed)
	add_child(_secret_door_notice)
	ExplorerModalChrome.apply_accept_dialog_scheme(_secret_door_notice, "blue", "primary")


func _on_secret_door_notice_confirmed() -> void:
	_explorer_audio().play_click()
	if _secret_door_notice != null:
		_secret_door_notice.hide()
	_set_grid_hover_polish_for_modal(false)


func _ensure_door_prompt_window() -> void:
	if _door_window != null:
		return
	_door_window = Window.new()
	_door_window.name = "DoorPromptWindow"
	_door_window.title = "Door"
	_door_window.size = Vector2i(520, 320)
	_door_window.popup_window = true
	_door_window.unresizable = true
	_door_window.transient = true
	_door_window.exclusive = true
	_door_window.visible = false
	_door_window.close_requested.connect(_on_door_window_close_requested)
	add_child(_door_window)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_door_window.add_child(margin)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(vb)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var door_icon_rect := TextureRect.new()
	door_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	door_icon_rect.custom_minimum_size = Vector2(56, 56)
	var lock_tex := DungeonTileAssets.load_lock_icon_texture()
	if lock_tex != null:
		door_icon_rect.texture = lock_tex
	hb.add_child(door_icon_rect)
	_door_prompt_icon = door_icon_rect

	var door_msg_scroll := ScrollContainer.new()
	door_msg_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	door_msg_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	door_msg_scroll.custom_minimum_size = Vector2(120, ExplorerModalChrome.SCROLL_BODY_MAX_PX)
	_door_message = Label.new()
	_door_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_door_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	door_msg_scroll.add_child(_door_message)
	hb.add_child(door_msg_scroll)
	vb.add_child(hb)

	_door_ok_button = Button.new()
	_door_ok_button.text = "OK"
	_door_ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_door_ok_button.pressed.connect(_on_door_ok_pressed)
	vb.add_child(_door_ok_button)

	_door_break_row = HBoxContainer.new()
	_door_break_row.visible = false
	_door_break_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_door_break_row.add_theme_constant_override("separation", 12)
	_door_break_btn = Button.new()
	_door_break_btn.text = "Break door"
	_door_break_btn.pressed.connect(_on_door_break_pressed)
	_door_break_row.add_child(_door_break_btn)
	_door_cancel_btn = Button.new()
	_door_cancel_btn.text = "Cancel"
	_door_cancel_btn.pressed.connect(_on_door_cancel_pressed)
	_door_break_row.add_child(_door_cancel_btn)
	vb.add_child(_door_break_row)


func _ensure_encounter_choice_window() -> void:
	if _encounter_window != null:
		return
	_encounter_window = Window.new()
	_encounter_window.name = "EncounterChoiceWindow"
	_encounter_window.title = "Encounter"
	_encounter_window.size = Vector2i(520, 240)
	_encounter_window.popup_window = true
	_encounter_window.unresizable = true
	_encounter_window.transient = true
	_encounter_window.exclusive = true
	_encounter_window.visible = false
	_encounter_window.close_requested.connect(_on_encounter_window_close_requested)
	add_child(_encounter_window)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_encounter_window.add_child(margin)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(vb)

	_encounter_message_label = Label.new()
	_encounter_message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_encounter_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_encounter_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_encounter_message_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_encounter_fight_btn = Button.new()
	_encounter_fight_btn.text = "Fight"
	_encounter_fight_btn.pressed.connect(_on_encounter_fight_pressed)
	row.add_child(_encounter_fight_btn)
	_encounter_evade_btn = Button.new()
	_encounter_evade_btn.text = "Evade"
	_encounter_evade_btn.pressed.connect(_on_encounter_evade_pressed)
	row.add_child(_encounter_evade_btn)
	vb.add_child(row)

	_apply_encounter_choice_window_chrome()


func _apply_encounter_choice_window_chrome() -> void:
	if _encounter_window == null:
		return
	ExplorerModalChrome.style_window_panel(_encounter_window, "yellow")
	if _encounter_message_label != null:
		ExplorerModalChrome.style_body_label(_encounter_message_label, "yellow")
	if _encounter_fight_btn != null:
		ExplorerModalChrome.style_button(_encounter_fight_btn, "warning", false)
	if _encounter_evade_btn != null:
		ExplorerModalChrome.style_button(_encounter_evade_btn, "secondary", false)


func _ensure_npc_quest_offer_window() -> void:
	if _npc_quest_offer_window != null:
		return
	_npc_quest_offer_window = Window.new()
	_npc_quest_offer_window.name = "NpcQuestOfferWindow"
	_npc_quest_offer_window.title = "Quest"
	_npc_quest_offer_window.size = Vector2i(520, 360)
	_npc_quest_offer_window.popup_window = true
	_npc_quest_offer_window.unresizable = true
	_npc_quest_offer_window.transient = true
	_npc_quest_offer_window.exclusive = true
	_npc_quest_offer_window.visible = false
	_npc_quest_offer_window.close_requested.connect(_on_npc_quest_offer_close_requested)
	add_child(_npc_quest_offer_window)

	var margin_nq := MarginContainer.new()
	margin_nq.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_nq.add_theme_constant_override("margin_left", 14)
	margin_nq.add_theme_constant_override("margin_right", 14)
	margin_nq.add_theme_constant_override("margin_top", 12)
	margin_nq.add_theme_constant_override("margin_bottom", 12)
	_npc_quest_offer_window.add_child(margin_nq)

	var vb_nq := VBoxContainer.new()
	vb_nq.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_nq.add_child(vb_nq)

	var nq_scroll := ScrollContainer.new()
	nq_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nq_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nq_scroll.custom_minimum_size = Vector2(0, ExplorerModalChrome.SCROLL_BODY_MAX_PX)
	vb_nq.add_child(nq_scroll)
	_npc_quest_offer_label = Label.new()
	_npc_quest_offer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_quest_offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nq_scroll.add_child(_npc_quest_offer_label)

	var row_nq := HBoxContainer.new()
	row_nq.alignment = BoxContainer.ALIGNMENT_CENTER
	row_nq.add_theme_constant_override("separation", 16)
	_npc_quest_accept_btn = Button.new()
	_npc_quest_accept_btn.text = "Accept"
	_npc_quest_accept_btn.pressed.connect(_on_npc_quest_accept_pressed)
	row_nq.add_child(_npc_quest_accept_btn)
	_npc_quest_decline_btn = Button.new()
	_npc_quest_decline_btn.text = "Decline"
	_npc_quest_decline_btn.pressed.connect(_on_npc_quest_decline_pressed)
	row_nq.add_child(_npc_quest_decline_btn)
	vb_nq.add_child(row_nq)

	_apply_npc_quest_offer_window_chrome()


func _apply_npc_quest_offer_window_chrome() -> void:
	if _npc_quest_offer_window == null:
		return
	ExplorerModalChrome.style_window_panel(_npc_quest_offer_window, "yellow")
	if _npc_quest_offer_label != null:
		ExplorerModalChrome.style_body_label(_npc_quest_offer_label, "yellow")
	if _npc_quest_accept_btn != null:
		ExplorerModalChrome.style_button(_npc_quest_accept_btn, "success", false)
	if _npc_quest_decline_btn != null:
		ExplorerModalChrome.style_button(_npc_quest_decline_btn, "secondary", false)


func _hide_npc_quest_offer_window() -> void:
	if _npc_quest_offer_window != null:
		_npc_quest_offer_window.hide()
	_set_grid_hover_polish_for_modal(false)


func _on_npc_quest_offer_close_requested() -> void:
	_on_npc_quest_decline_pressed()


func _on_npc_quest_accept_pressed() -> void:
	_explorer_audio().play_click()
	var c_nq := _pending_npc_quest_cell
	_hide_npc_quest_offer_window()
	_pending_npc_quest_cell = Vector2i.ZERO
	if _net_rep != null and c_nq != Vector2i.ZERO:
		_net_rep.client_request_npc_quest_accept()


func _on_npc_quest_decline_pressed() -> void:
	_explorer_audio().play_click()
	var c_nd := _pending_npc_quest_cell
	_hide_npc_quest_offer_window()
	_pending_npc_quest_cell = Vector2i.ZERO
	if _net_rep != null and c_nd != Vector2i.ZERO:
		_net_rep.client_request_npc_quest_decline()


func _ensure_encounter_resolution_dialog() -> void:
	if _encounter_res_dialog != null:
		return
	_encounter_res_dialog = AcceptDialog.new()
	_encounter_res_dialog.name = "EncounterResolutionDialog"
	_encounter_res_dialog.ok_button_text = "OK"
	_encounter_res_dialog.unresizable = true
	_encounter_res_dialog.confirmed.connect(_on_encounter_res_confirmed)
	_encounter_res_dialog.canceled.connect(_on_encounter_res_canceled)
	add_child(_encounter_res_dialog)


func _ensure_level_up_dialog() -> void:
	if _level_up_dialog != null:
		return
	_level_up_dialog = AcceptDialog.new()
	_level_up_dialog.name = "LevelUpDialog"
	_level_up_dialog.title = "Level up"
	_level_up_dialog.ok_button_text = "Continue"
	_level_up_dialog.unresizable = true
	_level_up_dialog.confirmed.connect(_on_level_up_dialog_confirmed)
	_level_up_dialog.canceled.connect(_on_level_up_dialog_canceled)
	add_child(_level_up_dialog)


func _on_level_up_dialog_offered(
	_new_level: int, primary_message: String, talent_message: String
) -> void:
	_ensure_level_up_dialog()
	_level_up_dialog.title = "Level %d" % int(_new_level)
	_level_up_dialog.dialog_text = primary_message + "\n\n" + talent_message
	ExplorerModalChrome.apply_accept_dialog_scheme(_level_up_dialog, "yellow", "success")
	_explorer_audio().play_level_up_hit()
	_level_up_dialog.popup_centered()
	_set_grid_hover_polish_for_modal(true)


func _on_level_up_dialog_confirmed() -> void:
	if _level_up_dialog != null:
		_level_up_dialog.hide()
	_set_grid_hover_polish_for_modal(false)
	_explorer_audio().play_click()
	if _net_rep != null:
		_net_rep.client_request_level_up_dismiss()


func _on_level_up_dialog_canceled() -> void:
	_on_level_up_dialog_confirmed()


func _hide_encounter_choice_window() -> void:
	if _encounter_window != null:
		_encounter_window.hide()
	_set_grid_hover_polish_for_modal(false)


func _on_encounter_window_close_requested() -> void:
	_hide_encounter_choice_window()
	_pending_encounter_cell = Vector2i.ZERO
	_last_encounter_fight_cell = Vector2i.ZERO


func _on_encounter_fight_pressed() -> void:
	_clear_combat_finish_timer()
	## Explorer `fight_encounter` — `play_audio` `fight` before `CombatSystem.start_combat` (no click).
	_explorer_audio().play_combat_sfx("fight", "")
	var c := _pending_encounter_cell
	_last_encounter_fight_cell = c
	_hide_encounter_choice_window()
	_pending_encounter_cell = Vector2i.ZERO
	if _net_rep != null and c != Vector2i.ZERO:
		_net_rep.client_request_encounter_fight(c.x, c.y)


func _on_encounter_evade_pressed() -> void:
	_explorer_audio().play_click()
	var c2 := _pending_encounter_cell
	_last_encounter_fight_cell = c2
	_hide_encounter_choice_window()
	_pending_encounter_cell = Vector2i.ZERO
	if _net_rep != null and c2 != Vector2i.ZERO:
		_net_rep.client_request_encounter_evade(c2.x, c2.y)


func _on_encounter_resolution_dialog(title: String, message: String) -> void:
	if title != "Victory":
		_pending_victory_treasure_gold = 0
	_ensure_encounter_resolution_dialog()
	_encounter_res_dialog.title = title
	_encounter_res_dialog.dialog_text = message
	var sch_r := ExplorerModalChrome.scheme_for_encounter_resolution_title(title)
	ExplorerModalChrome.apply_accept_dialog_scheme(
		_encounter_res_dialog,
		sch_r,
		ExplorerModalChrome.ok_variant_for_encounter_resolution_title(title)
	)
	if title == "Trap triggered":
		## Explorer `TrapSystem.apply_damage` / door-treasure disarm fail — `monster_hit` when trap deals HP.
		_explorer_audio().play_combat_sfx("monster_hit", "")
	if title == "Treasure found":
		_explorer_audio().play_chest_open()
	_encounter_res_dialog.popup_centered()
	_set_grid_hover_polish_for_modal(true)


func _on_encounter_res_confirmed() -> void:
	var dlg_title := ""
	if _encounter_res_dialog != null:
		dlg_title = _encounter_res_dialog.title
	if _encounter_res_dialog != null:
		_encounter_res_dialog.hide()
	_set_grid_hover_polish_for_modal(false)
	if dlg_title == "Rumor" and _net_rep != null:
		_explorer_audio().play_pickup()
		_net_rep.client_request_rumor_dismiss()
	if dlg_title == "Special item" and _net_rep != null:
		_explorer_audio().play_pickup()
		_net_rep.client_request_special_item_dismiss()
	if dlg_title == "Feature trap" and _net_rep != null:
		## Explorer `TrapSystem.apply_damage` — `monster_hit` only when HP loss applies.
		_explorer_audio().play_combat_sfx("monster_hit", "")
		_net_rep.client_request_feature_trap_dismiss()
	if dlg_title == "Quest accepted":
		_explorer_audio().play_pickup()
	if dlg_title == "Declined":
		_explorer_audio().play_click()
	if dlg_title == "Achievement":
		_explorer_audio().play_click()
	if dlg_title == "Treasure found":
		_explorer_audio().play_coins()
	if dlg_title == "Evade failed" and _net_rep != null:
		## Explorer `handle_failed_encounter_evade` — `fight` then `start_combat`.
		_explorer_audio().play_combat_sfx("fight", "")
		var fc := _last_encounter_fight_cell
		if fc != Vector2i.ZERO:
			_net_rep.client_request_encounter_fight(fc.x, fc.y)
	if dlg_title == "Victory":
		if _pending_victory_treasure_gold > 0:
			_explorer_audio().play_coins()
		_explorer_audio().resume_wander_after_combat(last_seed)
	elif dlg_title == "Defeat":
		_explorer_audio().stop_death_music()
		_explorer_audio().resume_wander_after_combat(last_seed)
	_pending_victory_treasure_gold = 0


func _on_encounter_res_canceled() -> void:
	var dlg_title2 := ""
	if _encounter_res_dialog != null:
		dlg_title2 = _encounter_res_dialog.title
	if _encounter_res_dialog != null:
		_encounter_res_dialog.hide()
	_set_grid_hover_polish_for_modal(false)
	if dlg_title2 == "Rumor" and _net_rep != null:
		_explorer_audio().play_pickup()
		_net_rep.client_request_rumor_dismiss()
	if dlg_title2 == "Special item" and _net_rep != null:
		_explorer_audio().play_pickup()
		_net_rep.client_request_special_item_dismiss()
	if dlg_title2 == "Feature trap" and _net_rep != null:
		_explorer_audio().play_combat_sfx("monster_hit", "")
		_net_rep.client_request_feature_trap_dismiss()
	if dlg_title2 == "Quest accepted":
		_explorer_audio().play_pickup()
	if dlg_title2 == "Declined":
		_explorer_audio().play_click()
	if dlg_title2 == "Achievement":
		_explorer_audio().play_click()
	if dlg_title2 == "Treasure found":
		_explorer_audio().play_coins()
	if dlg_title2 == "Evade failed" and _net_rep != null:
		_explorer_audio().play_combat_sfx("fight", "")
		var fc2 := _last_encounter_fight_cell
		if fc2 != Vector2i.ZERO:
			_net_rep.client_request_encounter_fight(fc2.x, fc2.y)
	if dlg_title2 == "Defeat":
		_explorer_audio().stop_death_music()
		_explorer_audio().resume_wander_after_combat(last_seed)
	_pending_victory_treasure_gold = 0


func _ensure_combat_window() -> void:
	if _combat_window != null:
		return
	_combat_window = Window.new()
	_combat_window.name = "CombatWindow"
	_combat_window.title = "Combat"
	_combat_window.size = Vector2i(480, 420)
	_combat_window.popup_window = true
	_combat_window.unresizable = true
	_combat_window.transient = true
	_combat_window.exclusive = true
	_combat_window.visible = false
	_combat_window.close_requested.connect(_on_combat_window_close_requested)
	add_child(_combat_window)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_combat_window.add_child(margin)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_combat_title_label = Label.new()
	_combat_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_combat_title_label)

	_combat_hp_label = Label.new()
	_combat_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_combat_hp_label)

	_combat_log_label = Label.new()
	_combat_log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_combat_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_combat_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_combat_log_label)

	var combat_btn_row := HBoxContainer.new()
	combat_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	combat_btn_row.add_theme_constant_override("separation", 12)
	vb.add_child(combat_btn_row)
	_combat_attack_btn = Button.new()
	_combat_attack_btn.text = "Attack"
	_combat_attack_btn.pressed.connect(_on_combat_attack_pressed)
	combat_btn_row.add_child(_combat_attack_btn)
	_combat_flee_btn = Button.new()
	_combat_flee_btn.text = "Flee"
	_combat_flee_btn.pressed.connect(_on_combat_flee_pressed)
	combat_btn_row.add_child(_combat_flee_btn)

	_apply_combat_window_chrome()


func _apply_combat_window_chrome() -> void:
	if _combat_window == null:
		return
	ExplorerModalChrome.style_window_panel(_combat_window, "red")
	if _combat_title_label != null:
		ExplorerModalChrome.style_title_label(_combat_title_label, "red")
	if _combat_hp_label != null:
		ExplorerModalChrome.style_body_label(_combat_hp_label, "red")
	if _combat_log_label != null:
		ExplorerModalChrome.style_body_label(_combat_log_label, "red")
	var atk_var := "primary"
	if _combat_attack_btn != null and str(_combat_attack_btn.text).contains("Backstab"):
		atk_var = "warning"
	if _combat_attack_btn != null:
		ExplorerModalChrome.style_button(_combat_attack_btn, atk_var, _combat_attack_btn.disabled)
	if _combat_flee_btn != null:
		ExplorerModalChrome.style_button(_combat_flee_btn, "secondary", _combat_flee_btn.disabled)


func _on_combat_window_close_requested() -> void:
	if _combat_window != null:
		_combat_window.hide()
	_set_grid_hover_polish_for_modal(false)


func _on_combat_attack_pressed() -> void:
	_explorer_audio().play_click()
	if _net_rep != null:
		_net_rep.client_request_combat_player_attack()


func _on_combat_flee_pressed() -> void:
	_explorer_audio().play_click()
	if _net_rep != null:
		_net_rep.client_request_combat_flee()


func _play_combat_sfx_from_snapshot(snapshot: Dictionary) -> void:
	var raw: Variant = snapshot.get("sfx_events", [])
	if raw is Array:
		var disp := str(snapshot.get("monster_display", ""))
		for x in raw:
			_explorer_audio().play_combat_sfx(str(x), disp)


func _clear_combat_finish_timer() -> void:
	if _combat_finish_timer == null:
		return
	var finish_timer := _combat_finish_timer as SceneTreeTimer
	if finish_timer.timeout.is_connected(_on_combat_finish_timer_tick):
		finish_timer.timeout.disconnect(_on_combat_finish_timer_tick)
	_combat_finish_timer = null


func _on_combat_finish_timer_tick() -> void:
	_combat_finish_timer = null
	if _combat_window != null:
		_combat_window.hide()
	_set_grid_hover_polish_for_modal(false)
	if _combat_finish_victory:
		_pending_victory_treasure_gold = _combat_finish_treasure
	elif _combat_finish_flee_success:
		_pending_victory_treasure_gold = 0
		_explorer_audio().resume_wander_after_combat(last_seed)
	else:
		_pending_victory_treasure_gold = 0
		_explorer_audio().play_death_sting()
		_explorer_audio().start_death_music()
	_on_encounter_resolution_dialog(_combat_finish_title, _combat_finish_body)


func _on_combat_state_changed(snapshot: Dictionary) -> void:
	if _net_rep == null:
		return
	if bool(snapshot.get("finished", false)):
		_play_combat_sfx_from_snapshot(snapshot)
		_ensure_combat_window()
		if _combat_title_label != null:
			_combat_title_label.text = str(snapshot.get("outcome_title", "Combat"))
		if _combat_hp_label != null:
			_combat_hp_label.text = ""
		if _combat_log_label != null:
			_combat_log_label.text = str(snapshot.get("outcome_body", snapshot.get("log_full", "")))
		if _combat_attack_btn != null:
			_combat_attack_btn.disabled = true
		if _combat_flee_btn != null:
			_combat_flee_btn.disabled = true
		_combat_finish_flee_success = bool(snapshot.get("flee_success", false))
		if _combat_window != null:
			_combat_window.title = str(snapshot.get("outcome_title", "Combat"))
			_apply_combat_window_chrome()
			_combat_window.popup_centered()
		_set_grid_hover_polish_for_modal(true)
		_clear_combat_finish_timer()
		_combat_finish_title = str(snapshot.get("outcome_title", "Combat"))
		_combat_finish_body = str(snapshot.get("outcome_body", snapshot.get("log_full", "")))
		_combat_finish_victory = bool(snapshot.get("victory", false))
		_combat_finish_treasure = int(snapshot.get("victory_treasure_gold", 0))
		var finish_delay_timer := get_tree().create_timer(1.0)
		_combat_finish_timer = finish_delay_timer
		finish_delay_timer.timeout.connect(_on_combat_finish_timer_tick, CONNECT_ONE_SHOT)
		return
	_play_combat_sfx_from_snapshot(snapshot)
	## Explorer `CombatSystem.start_combat` → `play_combat_music` every entry; `start_combat_music` no-ops if already combat.
	_explorer_audio().start_combat_music()
	_ensure_combat_window()
	if _combat_title_label != null:
		_combat_title_label.text = str(snapshot.get("title", "Combat"))
	if _combat_hp_label != null:
		_combat_hp_label.text = (
			"You: %d HP  |  %s: %d / %d HP"
			% [
				int(snapshot.get("player_hp", 0)),
				str(snapshot.get("monster_display", "?")),
				int(snapshot.get("monster_hp", 0)),
				int(snapshot.get("monster_max_hp", 1)),
			]
		)
	if _combat_log_label != null:
		_combat_log_label.text = str(snapshot.get("log_full", ""))
	if _combat_attack_btn != null:
		var surp: bool = bool(snapshot.get("surprise_attack", false))
		_combat_attack_btn.text = "Backstab" if surp else "Attack"
		_combat_attack_btn.disabled = not bool(snapshot.get("can_attack", false))
	if _combat_flee_btn != null:
		_combat_flee_btn.disabled = not bool(snapshot.get("can_flee", false))
	if _combat_window != null:
		_combat_window.title = str(snapshot.get("title", "Combat"))
		_apply_combat_window_chrome()
		_combat_window.popup_centered()
	_set_grid_hover_polish_for_modal(true)


func _on_net_fog_full_resync(cells: PackedVector2Array, view: Node2D) -> void:
	_client_revealed.clear()
	_client_fog_clicked.clear()
	for i in range(cells.size()):
		_client_revealed[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	if view.has_method("apply_fog_full_resync"):
		view.apply_fog_full_resync(cells)


func _on_fog_clicked_cells_snapshot(cells: PackedVector2Array, view: Node2D) -> void:
	_client_fog_clicked.clear()
	for i in range(cells.size()):
		_client_fog_clicked[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	if view.has_method("apply_fog_clicked_cells_snapshot"):
		view.apply_fog_clicked_cells_snapshot(cells)


func _on_fog_clicked_cells_delta(cells: PackedVector2Array, view: Node2D) -> void:
	for i in range(cells.size()):
		_client_fog_clicked[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	if view.has_method("apply_fog_clicked_cells_delta"):
		view.apply_fog_clicked_cells_delta(cells)


func _on_secret_doors_snapshot(cells: PackedVector2Array, view: Node2D) -> void:
	if view.has_method("apply_secret_doors_snapshot"):
		view.apply_secret_doors_snapshot(cells)


func _on_secret_doors_delta(cells: PackedVector2Array, view: Node2D) -> void:
	if view.has_method("apply_secret_doors_delta"):
		view.apply_secret_doors_delta(cells)
	for i in range(cells.size()):
		var c := Vector2i(int(cells[i].x), int(cells[i].y))
		if GridWalk.is_king_adjacent(_net_local_cell, c):
			_ensure_secret_door_notice_dialog()
			if _secret_door_notice != null and not _secret_door_notice.visible:
				_secret_door_notice.dialog_text = "You spot a hidden door in the wall!"
				_secret_door_notice.popup_centered()
				_set_grid_hover_polish_for_modal(true)
			break


func _on_unlocked_doors_snapshot(cells: PackedVector2Array) -> void:
	_client_unlocked.clear()
	for i in range(cells.size()):
		_client_unlocked[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	if _grid_view != null and _grid_view.has_method("apply_unlocked_doors_snapshot"):
		_grid_view.call("apply_unlocked_doors_snapshot", cells)


func _on_unlocked_doors_delta(cells: PackedVector2Array) -> void:
	if cells.size() > 0:
		_explorer_audio().play_door_open()
	for i in range(cells.size()):
		_client_unlocked[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	if _grid_view != null and _grid_view.has_method("apply_unlocked_doors_delta"):
		_grid_view.call("apply_unlocked_doors_delta", cells)


func _on_trap_inspected_doors_snapshot(cells: PackedVector2Array) -> void:
	if _grid_view != null and _grid_view.has_method("apply_trap_inspected_doors_snapshot"):
		_grid_view.call("apply_trap_inspected_doors_snapshot", cells)


func _on_trap_inspected_doors_delta(cells: PackedVector2Array) -> void:
	if _grid_view != null and _grid_view.has_method("apply_trap_inspected_doors_delta"):
		_grid_view.call("apply_trap_inspected_doors_delta", cells)


func _on_trap_defused_doors_snapshot(cells: PackedVector2Array) -> void:
	_trap_defused.clear()
	for i in range(cells.size()):
		_trap_defused[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	if _grid_view != null and _grid_view.has_method("apply_trap_defused_doors_snapshot"):
		_grid_view.call("apply_trap_defused_doors_snapshot", cells)


func _on_trap_defused_doors_delta(cells: PackedVector2Array) -> void:
	for i in range(cells.size()):
		_trap_defused[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	if _grid_view != null and _grid_view.has_method("apply_trap_defused_doors_delta"):
		_grid_view.call("apply_trap_defused_doors_delta", cells)


func _on_door_prompt_offered(action: String, cell: Vector2i, message: String) -> void:
	if _net_rep == null:
		return
	_ensure_door_prompt_window()
	_pending_door_action = action
	_pending_door_cell = cell
	_door_message.text = message
	## Explorer `TrapSystem.apply_damage` — `monster_hit` when door disarm fails (non-lethal uses this modal).
	if action == "trap_disarm_result" and message.contains("fail to disarm"):
		_explorer_audio().play_combat_sfx("monster_hit", "")
	if _door_ok_button != null:
		_door_ok_button.visible = action != "break_door"
	if _door_break_row != null:
		_door_break_row.visible = action == "break_door"
	if _door_prompt_icon != null:
		match action:
			"trap_stub", "trap_sprung", "trap_detected", "trap_disarm_result":
				var tt := DungeonTileAssets.load_trap_icon_texture()
				_door_prompt_icon.texture = tt
				_door_prompt_icon.visible = tt != null
			"pass":
				var dt := DungeonTileAssets.load_door_pass_modal_texture()
				_door_prompt_icon.texture = dt
				_door_prompt_icon.visible = dt != null
			"break_door", "break_result":
				var bt := DungeonTileAssets.load_break_door_icon_texture()
				if bt == null:
					bt = DungeonTileAssets.load_lock_icon_texture()
				_door_prompt_icon.texture = bt
				_door_prompt_icon.visible = bt != null
			_:
				var lt := DungeonTileAssets.load_lock_icon_texture()
				_door_prompt_icon.texture = lt
				_door_prompt_icon.visible = lt != null
	_apply_door_window_chrome()
	_door_window.popup_centered()
	_set_grid_hover_polish_for_modal(true)


func _apply_world_dialog_chrome() -> void:
	if _world_dialog == null:
		return
	var k := _pending_world_kind
	var t := _world_dialog.title
	var sch_w := ExplorerModalChrome.scheme_for_world_kind_title(k, t)
	var ok_v := ExplorerModalChrome.ok_variant_for_world_kind(k, t)
	ExplorerModalChrome.apply_accept_dialog_scheme(_world_dialog, sch_w, ok_v)


func _apply_door_window_chrome() -> void:
	if _door_window == null:
		return
	var sch := ExplorerModalChrome.scheme_for_door_action(_pending_door_action, _door_message.text)
	ExplorerModalChrome.style_window_panel(_door_window, sch)
	if _door_message != null:
		ExplorerModalChrome.style_body_label(_door_message, sch)
	if _door_ok_button != null:
		ExplorerModalChrome.style_button(_door_ok_button, "primary", false)
	if _door_break_btn != null:
		ExplorerModalChrome.style_button(_door_break_btn, "primary", false)
	if _door_cancel_btn != null:
		ExplorerModalChrome.style_button(_door_cancel_btn, "secondary", false)


func _set_grid_hover_polish_for_modal(blocked: bool) -> void:
	if _grid_view != null and _grid_view.has_method("set_hover_polish_enabled"):
		_grid_view.call("set_hover_polish_enabled", not blocked)


func _on_door_ok_pressed() -> void:
	_explorer_audio().play_click()
	if _door_window != null:
		_door_window.hide()
	_set_grid_hover_polish_for_modal(false)
	if _pending_door_action.is_empty() or _net_rep == null:
		return
	var a := _pending_door_action
	var cx := _pending_door_cell.x
	var cy := _pending_door_cell.y
	_pending_door_action = ""
	if a == "break_result":
		return
	if a == "trap_disarm_result":
		_net_rep.client_request_door_confirm("trap_disarm_ack", cx, cy)
		return
	if a == "trap_detected":
		_net_rep.client_request_door_confirm("trap_disarm", cx, cy)
		return
	if a == "trap_sprung":
		_net_rep.client_request_door_confirm("trap_sprung_ack", cx, cy)
		return
	_net_rep.client_request_door_confirm(a, cx, cy)


func _on_door_break_pressed() -> void:
	_explorer_audio().play_banging()
	if _door_window != null:
		_door_window.hide()
	_set_grid_hover_polish_for_modal(false)
	if _net_rep == null or _pending_door_action != "break_door":
		_pending_door_action = ""
		return
	var cx := _pending_door_cell.x
	var cy := _pending_door_cell.y
	_pending_door_action = ""
	_net_rep.client_request_door_confirm("break_door", cx, cy)


func _on_door_cancel_pressed() -> void:
	if _door_window != null:
		_door_window.hide()
	_set_grid_hover_polish_for_modal(false)
	_pending_door_action = ""


func _on_door_window_close_requested() -> void:
	if _door_window != null:
		_door_window.hide()
	_set_grid_hover_polish_for_modal(false)
	_pending_door_action = ""


func _can_interact_door_cell(cell: Vector2i) -> bool:
	if not GridWalk.is_king_adjacent(_net_local_cell, cell):
		return false
	if _welcome_fog_on and not _client_revealed.get(cell, false):
		return false
	var t: String = GridWalk.tile_effective(_path_grid, cell, _trap_defused)
	return GridWalk.is_interactable_door_cell_tile(t)


func _cell_revealed_for_interaction(cell: Vector2i) -> bool:
	if not _welcome_fog_on:
		return true
	return _client_revealed.get(cell, false)


func _ensure_world_interaction_dialog() -> void:
	if _world_dialog != null:
		return
	_world_dialog = AcceptDialog.new()
	_world_dialog.name = "WorldInteractionDialog"
	_world_dialog.ok_button_text = "OK"
	_world_dialog.unresizable = true
	_world_dialog.confirmed.connect(_on_world_dialog_confirmed)
	_world_dialog.canceled.connect(_on_world_dialog_canceled)
	add_child(_world_dialog)


func _ensure_special_feature_remote_window() -> void:
	if _special_feature_window != null:
		return
	_special_feature_window = Window.new()
	_special_feature_window.name = "SpecialFeatureRemoteWindow"
	_special_feature_window.title = "Feature"
	_special_feature_window.size = Vector2i(520, 300)
	_special_feature_window.popup_window = true
	_special_feature_window.unresizable = true
	_special_feature_window.transient = true
	_special_feature_window.exclusive = true
	_special_feature_window.visible = false
	_special_feature_window.close_requested.connect(_on_special_feature_window_close_requested)
	add_child(_special_feature_window)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_special_feature_window.add_child(margin)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(vb)
	var sf_scroll := ScrollContainer.new()
	sf_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sf_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sf_scroll.custom_minimum_size = Vector2(0, ExplorerModalChrome.SCROLL_BODY_MAX_PX)
	vb.add_child(sf_scroll)
	_special_feature_message_label = Label.new()
	_special_feature_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_special_feature_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sf_scroll.add_child(_special_feature_message_label)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_special_feature_investigate_btn = Button.new()
	_special_feature_investigate_btn.text = "Investigate"
	_special_feature_investigate_btn.pressed.connect(_on_special_feature_investigate_pressed)
	row.add_child(_special_feature_investigate_btn)
	_special_feature_close_btn = Button.new()
	_special_feature_close_btn.text = "Close"
	_special_feature_close_btn.pressed.connect(_on_special_feature_close_pressed)
	row.add_child(_special_feature_close_btn)
	vb.add_child(row)

	_apply_special_feature_window_chrome()


func _apply_special_feature_window_chrome() -> void:
	if _special_feature_window == null:
		return
	ExplorerModalChrome.style_window_panel(_special_feature_window, "blue")
	if _special_feature_message_label != null:
		ExplorerModalChrome.style_body_label(_special_feature_message_label, "blue")
	if _special_feature_investigate_btn != null:
		ExplorerModalChrome.style_button(_special_feature_investigate_btn, "primary", false)
	if _special_feature_close_btn != null:
		ExplorerModalChrome.style_button(_special_feature_close_btn, "secondary", false)


func _on_special_feature_window_close_requested() -> void:
	if _special_feature_window != null:
		_special_feature_window.hide()
	_set_grid_hover_polish_for_modal(false)
	_pending_special_feature_cell = Vector2i.ZERO


func _on_special_feature_close_pressed() -> void:
	_explorer_audio().play_click()
	_on_special_feature_window_close_requested()


func _on_special_feature_investigate_pressed() -> void:
	_explorer_audio().play_click()
	var c := _pending_special_feature_cell
	if _net_rep != null and c != Vector2i.ZERO:
		_net_rep.client_request_feature_investigate(c.x, c.y)
	_on_special_feature_window_close_requested()


func _ensure_trapped_treasure_window() -> void:
	if _treasure_trap_window != null:
		return
	_treasure_trap_window = Window.new()
	_treasure_trap_window.name = "TrappedTreasureWindow"
	_treasure_trap_window.title = "Trap"
	_treasure_trap_window.size = Vector2i(520, 280)
	_treasure_trap_window.popup_window = true
	_treasure_trap_window.unresizable = true
	_treasure_trap_window.transient = true
	_treasure_trap_window.exclusive = true
	_treasure_trap_window.visible = false
	_treasure_trap_window.close_requested.connect(_on_trapped_treasure_window_close_requested)
	add_child(_treasure_trap_window)
	var margin2 := MarginContainer.new()
	margin2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin2.add_theme_constant_override("margin_left", 14)
	margin2.add_theme_constant_override("margin_right", 14)
	margin2.add_theme_constant_override("margin_top", 12)
	margin2.add_theme_constant_override("margin_bottom", 12)
	_treasure_trap_window.add_child(margin2)
	var vb2 := VBoxContainer.new()
	vb2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin2.add_child(vb2)
	var tt_scroll := ScrollContainer.new()
	tt_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tt_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tt_scroll.custom_minimum_size = Vector2(0, ExplorerModalChrome.SCROLL_BODY_MAX_PX)
	vb2.add_child(tt_scroll)
	_treasure_trap_message_label = Label.new()
	_treasure_trap_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_treasure_trap_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tt_scroll.add_child(_treasure_trap_message_label)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 16)
	_treasure_trap_disarm_btn = Button.new()
	_treasure_trap_disarm_btn.text = "Disarm"
	_treasure_trap_disarm_btn.pressed.connect(_on_trapped_treasure_disarm_pressed)
	row2.add_child(_treasure_trap_disarm_btn)
	_treasure_trap_leave_btn = Button.new()
	_treasure_trap_leave_btn.text = "Leave"
	_treasure_trap_leave_btn.pressed.connect(_on_trapped_treasure_leave_pressed)
	row2.add_child(_treasure_trap_leave_btn)
	vb2.add_child(row2)

	_apply_trapped_treasure_window_chrome()


func _apply_trapped_treasure_window_chrome() -> void:
	if _treasure_trap_window == null:
		return
	ExplorerModalChrome.style_window_panel(_treasure_trap_window, "yellow")
	if _treasure_trap_message_label != null:
		ExplorerModalChrome.style_body_label(_treasure_trap_message_label, "yellow")
	if _treasure_trap_disarm_btn != null:
		ExplorerModalChrome.style_button(_treasure_trap_disarm_btn, "primary", false)
	if _treasure_trap_leave_btn != null:
		ExplorerModalChrome.style_button(_treasure_trap_leave_btn, "secondary", false)


func _on_trapped_treasure_window_close_requested() -> void:
	if _treasure_trap_window != null:
		_treasure_trap_window.hide()
	_set_grid_hover_polish_for_modal(false)
	_pending_trapped_treasure_cell = Vector2i.ZERO


func _on_trapped_treasure_leave_pressed() -> void:
	_explorer_audio().play_click()
	var c := _pending_trapped_treasure_cell
	if _net_rep != null and c != Vector2i.ZERO:
		_net_rep.client_request_trapped_treasure_skip_disarm(c.x, c.y)
	_on_trapped_treasure_window_close_requested()


func _on_trapped_treasure_disarm_pressed() -> void:
	_explorer_audio().play_click()
	var c2 := _pending_trapped_treasure_cell
	if _net_rep != null and c2 != Vector2i.ZERO:
		_net_rep.client_request_trapped_treasure_disarm(c2.x, c2.y)
	_on_trapped_treasure_window_close_requested()


func _ensure_room_trap_window() -> void:
	if _room_trap_window != null:
		return
	_room_trap_window = Window.new()
	_room_trap_window.name = "RoomTrapWindow"
	_room_trap_window.title = "Trap"
	_room_trap_window.size = Vector2i(520, 280)
	_room_trap_window.popup_window = true
	_room_trap_window.unresizable = true
	_room_trap_window.transient = true
	_room_trap_window.exclusive = true
	_room_trap_window.visible = false
	_room_trap_window.close_requested.connect(_on_room_trap_window_close_requested)
	add_child(_room_trap_window)
	var margin_rt := MarginContainer.new()
	margin_rt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_rt.add_theme_constant_override("margin_left", 14)
	margin_rt.add_theme_constant_override("margin_right", 14)
	margin_rt.add_theme_constant_override("margin_top", 12)
	margin_rt.add_theme_constant_override("margin_bottom", 12)
	_room_trap_window.add_child(margin_rt)
	var vb_rt := VBoxContainer.new()
	vb_rt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_rt.add_child(vb_rt)
	var rt_scroll := ScrollContainer.new()
	rt_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rt_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt_scroll.custom_minimum_size = Vector2(0, ExplorerModalChrome.SCROLL_BODY_MAX_PX)
	vb_rt.add_child(rt_scroll)
	_room_trap_message_label = Label.new()
	_room_trap_message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_trap_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt_scroll.add_child(_room_trap_message_label)
	var row_rt := HBoxContainer.new()
	row_rt.alignment = BoxContainer.ALIGNMENT_CENTER
	row_rt.add_theme_constant_override("separation", 16)
	_room_trap_disarm_btn = Button.new()
	_room_trap_disarm_btn.text = "Disarm"
	_room_trap_disarm_btn.pressed.connect(_on_room_trap_disarm_pressed)
	row_rt.add_child(_room_trap_disarm_btn)
	_room_trap_leave_btn = Button.new()
	_room_trap_leave_btn.text = "Leave"
	_room_trap_leave_btn.pressed.connect(_on_room_trap_leave_pressed)
	row_rt.add_child(_room_trap_leave_btn)
	vb_rt.add_child(row_rt)

	_apply_room_trap_window_chrome()


func _apply_room_trap_window_chrome() -> void:
	if _room_trap_window == null:
		return
	ExplorerModalChrome.style_window_panel(_room_trap_window, "yellow")
	if _room_trap_message_label != null:
		ExplorerModalChrome.style_body_label(_room_trap_message_label, "yellow")
	if _room_trap_disarm_btn != null:
		ExplorerModalChrome.style_button(_room_trap_disarm_btn, "primary", false)
	if _room_trap_leave_btn != null:
		ExplorerModalChrome.style_button(_room_trap_leave_btn, "secondary", false)


func _on_room_trap_window_close_requested() -> void:
	if _room_trap_window != null:
		_room_trap_window.hide()
	_set_grid_hover_polish_for_modal(false)
	_pending_room_trap_cell = Vector2i.ZERO


func _on_room_trap_leave_pressed() -> void:
	_explorer_audio().play_click()
	var c := _pending_room_trap_cell
	if _net_rep != null and c != Vector2i.ZERO:
		_net_rep.client_request_room_trap_skip_disarm(c.x, c.y)
	_on_room_trap_window_close_requested()


func _on_room_trap_disarm_pressed() -> void:
	_explorer_audio().play_click()
	var c2 := _pending_room_trap_cell
	if _net_rep != null and c2 != Vector2i.ZERO:
		_net_rep.client_request_room_trap_disarm(c2.x, c2.y)
	_on_room_trap_window_close_requested()


func _on_player_quests_updated(rows: PackedStringArray) -> void:
	_quest_rows = rows
	_refresh_stats_hud_text()


func _on_player_achievements_updated(lines: PackedStringArray) -> void:
	_achievements_lines = lines
	_refresh_stats_hud_text()
	if _achievements_item_list != null and _achievements_list_window != null:
		if _achievements_list_window.visible:
			_refresh_achievements_list_items()


func _apply_display_name_from_welcome(welcome: Dictionary) -> void:
	var d := str(welcome.get("display_name", "")).strip_edges()
	if d.is_empty():
		d = "Explorer"
	_last_display_name = d
	_refresh_stats_hud_text()


func _on_player_display_name_changed(new_display_name: String) -> void:
	var d := new_display_name.strip_edges()
	if d.is_empty():
		return
	_last_display_name = d
	if _local_peer_id >= 0:
		_peer_display_names_by_id[_local_peer_id] = d
		_refresh_cached_marker_for_peer(_local_peer_id)
	_refresh_stats_hud_text()


func _peer_id_from_dict_key(k: Variant) -> int:
	if k is int:
		return k as int
	var ks := str(k).strip_edges()
	if ks.is_valid_int():
		return int(ks)
	return -1


func _merge_peer_display_names_from_dict(raw: Dictionary) -> void:
	for k in raw:
		var id := _peer_id_from_dict_key(k)
		if id < 0:
			continue
		_peer_display_names_by_id[id] = str(raw[k])


func _marker_label_text(peer_id: int) -> String:
	if not _peer_display_names_by_id.has(peer_id):
		return ""
	return JoinMetadata.truncate_for_map_marker(str(_peer_display_names_by_id[peer_id]))


func _apply_welcome_peer_display_names(welcome: Dictionary) -> void:
	_peer_display_names_by_id.clear()
	_last_peer_cells.clear()
	_last_peer_roles.clear()
	var raw: Variant = welcome.get("peer_display_names", {})
	if raw is Dictionary:
		_merge_peer_display_names_from_dict(raw as Dictionary)
	var my_id := int(welcome.get("player_id", _local_peer_id))
	if my_id >= 0 and not _peer_display_names_by_id.has(my_id):
		var dn := str(welcome.get("display_name", "")).strip_edges()
		if dn.is_empty():
			dn = "Explorer"
		_peer_display_names_by_id[my_id] = dn


func _on_peer_display_names_updated(names: Dictionary) -> void:
	_merge_peer_display_names_from_dict(names)
	_refresh_all_cached_peer_markers()


func _refresh_cached_marker_for_peer(peer_id: int) -> void:
	if _grid_view == null:
		return
	if not _last_peer_cells.has(peer_id):
		return
	var cell: Vector2i = _last_peer_cells[peer_id] as Vector2i
	var role := str(_last_peer_roles.get(peer_id, "rogue"))
	if _grid_view.has_method("sync_peer_marker"):
		_grid_view.sync_peer_marker(peer_id, cell, role, _marker_label_text(peer_id))


func _refresh_all_cached_peer_markers() -> void:
	if _grid_view == null:
		return
	for k in _last_peer_cells:
		var pid := int(k)
		_refresh_cached_marker_for_peer(pid)


func _active_quest_count() -> int:
	var n := 0
	for i in range(_quest_rows.size()):
		var v: Variant = JSON.parse_string(str(_quest_rows[i]))
		if v is Dictionary and str((v as Dictionary).get("status", "")) == "active":
			n += 1
	return n


func _on_player_rumors_updated(rumors: PackedStringArray) -> void:
	_rumors_lines = rumors
	_refresh_stats_hud_text()


func _on_player_special_items_updated(keys: PackedStringArray) -> void:
	_special_item_keys = keys
	_refresh_stats_hud_text()
	if _special_items_list_window != null and _special_items_list_window.visible:
		_refresh_special_items_list_items()


func _on_world_interaction_offered(
	kind: String, cell: Vector2i, title: String, message: String
) -> void:
	if _net_rep == null:
		return
	if kind == "encounter":
		_pending_encounter_cell = cell
		_ensure_encounter_choice_window()
		_encounter_window.title = title
		if _encounter_message_label != null:
			_encounter_message_label.text = message
		_encounter_window.popup_centered()
		_set_grid_hover_polish_for_modal(true)
		return
	if kind == "npc_quest_offer":
		_pending_npc_quest_cell = cell
		_ensure_npc_quest_offer_window()
		_npc_quest_offer_window.title = title
		if _npc_quest_offer_label != null:
			_npc_quest_offer_label.text = message
		_npc_quest_offer_window.popup_centered()
		_set_grid_hover_polish_for_modal(true)
		return
	if kind == "encounter_npc":
		_pending_world_kind = "encounter_npc"
		_pending_world_cell = cell
		_ensure_world_interaction_dialog()
		_world_dialog.title = title
		_world_dialog.dialog_text = message
		_world_dialog.ok_button_text = "Leave"
		_apply_world_dialog_chrome()
		_world_dialog.popup_centered()
		_set_grid_hover_polish_for_modal(true)
		return
	if kind == "special_feature":
		_pending_special_feature_cell = cell
		_ensure_special_feature_remote_window()
		_special_feature_window.title = title
		if _special_feature_message_label != null:
			_special_feature_message_label.text = message
		_special_feature_window.popup_centered()
		_set_grid_hover_polish_for_modal(true)
		return
	if kind == "trapped_treasure_detected":
		_pending_trapped_treasure_cell = cell
		_ensure_trapped_treasure_window()
		_treasure_trap_window.title = title
		if _treasure_trap_message_label != null:
			_treasure_trap_message_label.text = message
		_treasure_trap_window.popup_centered()
		_set_grid_hover_polish_for_modal(true)
		return
	if kind == "trapped_treasure_undetected":
		_pending_world_kind = "trapped_treasure_undetected"
		_pending_world_cell = cell
		_ensure_world_interaction_dialog()
		_world_dialog.title = title
		_world_dialog.dialog_text = message
		_world_dialog.ok_button_text = "Continue"
		_apply_world_dialog_chrome()
		_world_dialog.popup_centered()
		_set_grid_hover_polish_for_modal(true)
		return
	if kind == "room_trap_detected":
		_pending_room_trap_cell = cell
		_ensure_room_trap_window()
		_room_trap_window.title = title
		if _room_trap_message_label != null:
			_room_trap_message_label.text = message
		_room_trap_window.popup_centered()
		_set_grid_hover_polish_for_modal(true)
		return
	if kind == "room_trap_undetected":
		_pending_world_kind = "room_trap_undetected"
		_pending_world_cell = cell
		_ensure_world_interaction_dialog()
		_world_dialog.title = title
		_world_dialog.dialog_text = message
		_world_dialog.ok_button_text = "Continue"
		_apply_world_dialog_chrome()
		_world_dialog.popup_centered()
		_set_grid_hover_polish_for_modal(true)
		return
	_pending_world_kind = kind
	_pending_world_cell = cell
	_ensure_world_interaction_dialog()
	_world_dialog.ok_button_text = "OK"
	_world_dialog.title = title
	_world_dialog.dialog_text = message
	if kind == "quest_item_pickup" and title == "Quest Completed!":
		## Explorer `quest_item_system.ex` `complete_quest_discovery` — `orch_hit` when completion dialog opens.
		_explorer_audio().play_quest_completion_fanfare()
	if kind == "treasure":
		_explorer_audio().play_chest_open()
	_apply_world_dialog_chrome()
	_world_dialog.popup_centered()
	_set_grid_hover_polish_for_modal(true)


func _on_world_dialog_canceled() -> void:
	_pending_world_kind = ""
	_pending_world_cell = Vector2i.ZERO
	if _world_dialog != null:
		_world_dialog.hide()
	_set_grid_hover_polish_for_modal(false)


func _on_world_dialog_confirmed() -> void:
	var k0 := _pending_world_kind
	var c0 := _pending_world_cell
	_pending_world_kind = ""
	_pending_world_cell = Vector2i.ZERO
	if _world_dialog != null:
		_world_dialog.hide()
	_set_grid_hover_polish_for_modal(false)
	if _net_rep == null:
		return
	var k := k0
	var c := c0
	if k == "stair" or k == "waypoint" or k == "map_link":
		## Explorer `use_stair` — stairs only (no generic click).
		_explorer_audio().play_stairs()
		_net_rep.client_request_map_transition_confirm(k, c.x, c.y)
	elif k == "treasure":
		## Explorer `TreasureSystem.dismiss_treasure` — `coins` on collect (not click).
		_explorer_audio().play_coins()
		_net_rep.client_request_treasure_dismiss(c.x, c.y)
	elif k == "trapped_treasure_undetected" or k == "room_trap_undetected":
		## Explorer `TrapSystem.apply_damage` — `monster_hit` when trap damage is applied (Continue after surprise).
		_explorer_audio().play_combat_sfx("monster_hit", "")
		if k == "trapped_treasure_undetected":
			_net_rep.client_request_trapped_treasure_undetected_ack(c.x, c.y)
		else:
			_net_rep.client_request_room_trap_undetected_ack(c.x, c.y)
	elif (
		k == "food_pickup"
		or k == "healing_potion_pickup"
		or k == "torch_pickup"
		or k == "quest_item_pickup"
	):
		# Explorer dismiss food / potion / torch / `dismiss_quest_completed` pickup — pickup only (no click).
		_explorer_audio().play_pickup()
		_net_rep.client_request_pickup_dismiss(k, c.x, c.y)
	else:
		_explorer_audio().play_click()


func _ensure_stats_hud() -> void:
	if _stats_label != null:
		return
	_stats_layer = CanvasLayer.new()
	_stats_layer.layer = 30
	add_child(_stats_layer)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.offset_left = 8
	margin.offset_top = 8
	_stats_layer.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	_stats_label = Label.new()
	_stats_label.text = "Gold: 0  Lv 1  XP: 0 (500 to next)  HP: 0/0"
	_stats_label.add_theme_font_size_override("font_size", 16)
	_stats_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stats_label)
	_rumors_list_btn = Button.new()
	_rumors_list_btn.name = "RumorsListButton"
	_rumors_list_btn.text = "Rumors"
	_rumors_list_btn.tooltip_text = "View collected rumors (Explorer show_rumors_list)"
	_rumors_list_btn.visible = false
	_rumors_list_btn.pressed.connect(_on_rumors_list_button_pressed)
	row.add_child(_rumors_list_btn)
	_special_items_list_btn = Button.new()
	_special_items_list_btn.name = "SpecialItemsListButton"
	_special_items_list_btn.text = "Special items"
	_special_items_list_btn.tooltip_text = "View carried special items (Explorer show_special_items_list)"
	_special_items_list_btn.visible = false
	_special_items_list_btn.pressed.connect(_on_special_items_list_button_pressed)
	row.add_child(_special_items_list_btn)
	_achievements_list_btn = Button.new()
	_achievements_list_btn.name = "AchievementsListButton"
	_achievements_list_btn.text = "Achievements"
	_achievements_list_btn.tooltip_text = "View quest achievements (Explorer show_achievements_list)"
	_achievements_list_btn.visible = false
	_achievements_list_btn.pressed.connect(_on_achievements_list_button_pressed)
	row.add_child(_achievements_list_btn)
	_audio_settings_btn = Button.new()
	_audio_settings_btn.name = "AudioSettingsButton"
	_audio_settings_btn.text = "Audio"
	_audio_settings_btn.tooltip_text = "SFX and music volume (Phase 7.5 AUD-04)"
	_audio_settings_btn.pressed.connect(_on_audio_settings_button_pressed)
	row.add_child(_audio_settings_btn)


func _ensure_audio_settings_window() -> void:
	if _audio_settings_window != null:
		return
	_audio_settings_window = Window.new()
	_audio_settings_window.name = "AudioSettingsWindow"
	_audio_settings_window.title = "Audio"
	_audio_settings_window.size = Vector2i(400, 200)
	_audio_settings_window.popup_window = true
	_audio_settings_window.unresizable = true
	_audio_settings_window.transient = true
	_audio_settings_window.exclusive = true
	_audio_settings_window.visible = false
	_audio_settings_window.close_requested.connect(_on_audio_settings_window_close_requested)
	add_child(_audio_settings_window)
	var margin_a := MarginContainer.new()
	margin_a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_a.add_theme_constant_override("margin_left", 14)
	margin_a.add_theme_constant_override("margin_right", 14)
	margin_a.add_theme_constant_override("margin_top", 12)
	margin_a.add_theme_constant_override("margin_bottom", 12)
	_audio_settings_window.add_child(margin_a)
	var vb_a := VBoxContainer.new()
	vb_a.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb_a.add_theme_constant_override("separation", 12)
	margin_a.add_child(vb_a)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Volumes apply to this client only (SFX and Music buses). Settings are saved automatically."
	vb_a.add_child(hint)
	var row_s := HBoxContainer.new()
	row_s.add_theme_constant_override("separation", 10)
	var ls := Label.new()
	ls.text = "SFX"
	ls.custom_minimum_size = Vector2(56, 0)
	row_s.add_child(ls)
	_audio_sfx_slider = HSlider.new()
	_audio_sfx_slider.min_value = 0.0
	_audio_sfx_slider.max_value = 100.0
	_audio_sfx_slider.step = 1.0
	_audio_sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_sfx_slider.value_changed.connect(_on_audio_sfx_slider_changed)
	row_s.add_child(_audio_sfx_slider)
	vb_a.add_child(row_s)
	var row_m := HBoxContainer.new()
	row_m.add_theme_constant_override("separation", 10)
	var lm := Label.new()
	lm.text = "Music"
	lm.custom_minimum_size = Vector2(56, 0)
	row_m.add_child(lm)
	_audio_music_slider = HSlider.new()
	_audio_music_slider.min_value = 0.0
	_audio_music_slider.max_value = 100.0
	_audio_music_slider.step = 1.0
	_audio_music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_music_slider.value_changed.connect(_on_audio_music_slider_changed)
	row_m.add_child(_audio_music_slider)
	vb_a.add_child(row_m)
	var close_row := HBoxContainer.new()
	close_row.alignment = BoxContainer.ALIGNMENT_END
	var close_audio := Button.new()
	close_audio.text = "Close"
	close_audio.pressed.connect(_hide_audio_settings_window)
	close_row.add_child(close_audio)
	vb_a.add_child(close_row)


func _sync_audio_sliders_from_saved() -> void:
	if _audio_sfx_slider == null or _audio_music_slider == null:
		return
	var sfx_pct := int(round(_explorer_audio().get_saved_sfx_linear() * 100.0))
	var mu_pct := int(round(_explorer_audio().get_saved_music_linear() * 100.0))
	_audio_sfx_slider.set_value_no_signal(clampi(sfx_pct, 0, 100))
	_audio_music_slider.set_value_no_signal(clampi(mu_pct, 0, 100))


func _on_audio_settings_button_pressed() -> void:
	_explorer_audio().play_click()
	_ensure_audio_settings_window()
	_sync_audio_sliders_from_saved()
	_audio_settings_window.popup_centered()
	_set_grid_hover_polish_for_modal(true)


func _hide_audio_settings_window() -> void:
	if _audio_settings_window != null and _audio_settings_window.visible:
		_explorer_audio().play_click()
		_audio_settings_window.hide()
		_set_grid_hover_polish_for_modal(false)


func _on_audio_settings_window_close_requested() -> void:
	_hide_audio_settings_window()


func _persist_audio_volumes_from_sliders() -> void:
	if _audio_sfx_slider == null or _audio_music_slider == null:
		return
	var sfx_l := clampf(float(_audio_sfx_slider.value) / 100.0, 0.0, 1.0)
	var mu_l := clampf(float(_audio_music_slider.value) / 100.0, 0.0, 1.0)
	_explorer_audio().save_bus_volumes_linear(sfx_l, mu_l)


func _on_audio_sfx_slider_changed(_v: float) -> void:
	_persist_audio_volumes_from_sliders()


func _on_audio_music_slider_changed(_v: float) -> void:
	_persist_audio_volumes_from_sliders()


func _on_authority_tile_patched(c: Vector2i, new_tile: String) -> void:
	var prev: String = str(_path_grid.get(c, ""))
	_path_grid[c] = new_tile
	if (
		(prev == "treasure" or prev == "trapped_treasure")
		and (new_tile == "floor" or new_tile == "corridor")
	):
		_explorer_audio().play_coins()
	if _grid_view != null and _grid_view.has_method("apply_logical_tile_change"):
		_grid_view.apply_logical_tile_change(c, new_tile)


func _on_guards_hostile_changed(hostile: bool) -> void:
	_hud_guards_hostile = hostile
	if _grid_view != null and _grid_view.has_method("set_guards_hostile"):
		_grid_view.set_guards_hostile(hostile)
	_refresh_stats_hud_text()


func _refresh_stats_hud_text() -> void:
	if _stats_label == null:
		return
	if _rumors_list_btn != null:
		_rumors_list_btn.visible = _net_rep != null
		if _net_rep != null:
			var n := _rumors_lines.size()
			_rumors_list_btn.text = "Rumors" if n == 0 else ("Rumors (" + str(n) + ")")
			_rumors_list_btn.disabled = false
	if _special_items_list_btn != null:
		_special_items_list_btn.visible = _net_rep != null
		if _net_rep != null:
			var ns := _special_item_keys.size()
			_special_items_list_btn.text = (
				"Special items" if ns == 0 else ("Special items (" + str(ns) + ")")
			)
			_special_items_list_btn.disabled = false
	if _achievements_list_btn != null:
		_achievements_list_btn.visible = _net_rep != null
		if _net_rep != null:
			var na := _achievements_lines.size()
			_achievements_list_btn.text = (
				"Achievements" if na == 0 else ("Achievements (" + str(na) + ")")
			)
			_achievements_list_btn.disabled = false
	var tail := "  |  Guards: hostile" if _hud_guards_hostile else ""
	if _rumors_lines.size() > 0:
		tail += "  |  Rumors: " + str(_rumors_lines.size())
	if _special_item_keys.size() > 0:
		tail += "  |  Special items: " + str(_special_item_keys.size())
	var aq := _active_quest_count()
	if aq > 0:
		tail += "  |  Active quests: " + str(aq)
	if _achievements_lines.size() > 0:
		tail += "  |  Achievements: " + str(_achievements_lines.size())
	if _hud_torch_burn >= 0:
		if _hud_torch_spares >= 0:
			tail += "  |  Torch: " + str(_hud_torch_burn) + "%  Spares: " + str(_hud_torch_spares)
		else:
			tail += "  |  Torch: daylight"
	else:
		tail += "  |  Torch: n/a"
	tail += "  |  Align: " + PlayerAlignment.description_from_value(_last_player_alignment)
	if _last_npcs_killed > 0:
		tail += "  |  NPC kills: " + str(_last_npcs_killed)
	if _net_rep != null and not _last_display_name.is_empty():
		tail += "  |  Name: " + _last_display_name
	if not _welcome_join_hud_tail.is_empty():
		tail += _welcome_join_hud_tail
	_stats_label.text = (
		"Gold: "
		+ str(_last_gold)
		+ "  Lv "
		+ str(_last_level)
		+ "  XP: "
		+ str(_last_xp)
		+ " ("
		+ str(_last_xp_to_next)
		+ " to next)  HP: "
		+ str(_last_hp)
		+ "/"
		+ str(_last_max_hp)
		+ tail
	)


func _ensure_rumors_list_window() -> void:
	if _rumors_list_window != null:
		return
	_rumors_list_window = Window.new()
	_rumors_list_window.name = "RumorsListWindow"
	_rumors_list_window.title = RumorsListMessages.WINDOW_TITLE
	_rumors_list_window.size = Vector2i(520, 360)
	_rumors_list_window.popup_window = true
	_rumors_list_window.unresizable = true
	_rumors_list_window.transient = true
	_rumors_list_window.exclusive = true
	_rumors_list_window.visible = false
	_rumors_list_window.close_requested.connect(_on_rumors_list_window_close_requested)
	add_child(_rumors_list_window)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_rumors_list_window.add_child(margin)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	_rumors_list_hint = Label.new()
	_rumors_list_hint.name = "RumorsListHint"
	_rumors_list_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_rumors_list_hint)

	_rumors_item_list = ItemList.new()
	_rumors_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rumors_item_list.custom_minimum_size = Vector2(0, ExplorerModalChrome.SCROLL_BODY_MAX_PX)
	_rumors_item_list.allow_reselect = true
	_rumors_item_list.select_mode = ItemList.SELECT_SINGLE
	_rumors_item_list.item_activated.connect(_on_rumor_item_activated)
	vb.add_child(_rumors_item_list)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	_rumors_view_btn = Button.new()
	_rumors_view_btn.text = "View"
	_rumors_view_btn.pressed.connect(_on_rumor_view_pressed)
	row.add_child(_rumors_view_btn)
	_rumors_close_btn = Button.new()
	_rumors_close_btn.text = "Close"
	_rumors_close_btn.pressed.connect(_hide_rumors_list_window)
	row.add_child(_rumors_close_btn)
	vb.add_child(row)

	_apply_rumors_list_window_chrome()


func _apply_rumors_list_window_chrome() -> void:
	if _rumors_list_window == null:
		return
	ExplorerModalChrome.style_window_panel(_rumors_list_window, "gray")
	if _rumors_list_hint != null:
		ExplorerModalChrome.style_body_label(_rumors_list_hint, "gray")
	if _rumors_item_list != null:
		ExplorerModalChrome.style_item_list_for_explorer_list(_rumors_item_list)
	if _rumors_view_btn != null:
		ExplorerModalChrome.style_button(_rumors_view_btn, "primary", false)
	if _rumors_close_btn != null:
		ExplorerModalChrome.style_button(_rumors_close_btn, "secondary", false)


func _on_rumors_list_button_pressed() -> void:
	if _net_rep == null:
		return
	_explorer_audio().play_click()
	_ensure_rumors_list_window()
	_refresh_rumors_list_items()
	_rumors_list_window.popup_centered()
	_set_grid_hover_polish_for_modal(true)


func _refresh_rumors_list_items() -> void:
	if _rumors_item_list == null:
		return
	_rumors_item_list.clear()
	if _rumors_list_hint != null:
		if _rumors_lines.is_empty():
			_rumors_list_hint.text = RumorsListMessages.EMPTY_STATE
		else:
			_rumors_list_hint.text = RumorsListMessages.HINT_WHEN_HAS_RUMORS
	for i in range(_rumors_lines.size()):
		var full: String = str(_rumors_lines[i])
		_rumors_item_list.add_item(RumorsListMessages.list_item_text(i, full))


func _hide_rumors_list_window() -> void:
	if _rumors_list_window != null and _rumors_list_window.visible:
		_explorer_audio().play_click()
		_rumors_list_window.hide()
		_set_grid_hover_polish_for_modal(false)


func _on_rumors_list_window_close_requested() -> void:
	_hide_rumors_list_window()


func _on_rumor_view_pressed() -> void:
	if _rumors_item_list == null:
		return
	var sel: PackedInt32Array = _rumors_item_list.get_selected_items()
	if sel.is_empty():
		return
	_open_rumor_detail_from_index(int(sel[0]))


func _on_rumor_item_activated(index: int) -> void:
	_open_rumor_detail_from_index(index)


func _open_rumor_detail_from_index(index: int) -> void:
	if index < 0 or index >= _rumors_lines.size():
		return
	_explorer_audio().play_click()
	if _rumors_list_window != null:
		_rumors_list_window.hide()
	_set_grid_hover_polish_for_modal(true)
	var body: String = str(_rumors_lines[index])
	_ensure_encounter_resolution_dialog()
	_encounter_res_dialog.title = "Rumor"
	_encounter_res_dialog.dialog_text = body
	var sch_rm := ExplorerModalChrome.scheme_for_encounter_resolution_title("Rumor")
	ExplorerModalChrome.apply_accept_dialog_scheme(
		_encounter_res_dialog,
		sch_rm,
		ExplorerModalChrome.ok_variant_for_encounter_resolution_title("Rumor")
	)
	_encounter_res_dialog.popup_centered()


func _ensure_special_items_list_window() -> void:
	if _special_items_list_window != null:
		return
	_special_items_list_window = Window.new()
	_special_items_list_window.name = "SpecialItemsListWindow"
	_special_items_list_window.title = "Special items"
	_special_items_list_window.size = Vector2i(520, 360)
	_special_items_list_window.popup_window = true
	_special_items_list_window.unresizable = true
	_special_items_list_window.transient = true
	_special_items_list_window.exclusive = true
	_special_items_list_window.visible = false
	_special_items_list_window.close_requested.connect(
		_on_special_items_list_window_close_requested
	)
	add_child(_special_items_list_window)

	var margin_si := MarginContainer.new()
	margin_si.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_si.add_theme_constant_override("margin_left", 14)
	margin_si.add_theme_constant_override("margin_right", 14)
	margin_si.add_theme_constant_override("margin_top", 12)
	margin_si.add_theme_constant_override("margin_bottom", 12)
	_special_items_list_window.add_child(margin_si)

	var vb_si := VBoxContainer.new()
	vb_si.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb_si.add_theme_constant_override("separation", 10)
	margin_si.add_child(vb_si)

	_special_items_list_hint = Label.new()
	_special_items_list_hint.name = "SpecialItemsListHint"
	_special_items_list_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb_si.add_child(_special_items_list_hint)

	_special_items_item_list = ItemList.new()
	_special_items_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_special_items_item_list.custom_minimum_size = Vector2(
		0, ExplorerModalChrome.SCROLL_BODY_MAX_PX
	)
	_special_items_item_list.allow_reselect = true
	_special_items_item_list.select_mode = ItemList.SELECT_SINGLE
	_special_items_item_list.item_activated.connect(_on_special_item_item_activated)
	vb_si.add_child(_special_items_item_list)

	var row_si := HBoxContainer.new()
	row_si.alignment = BoxContainer.ALIGNMENT_CENTER
	row_si.add_theme_constant_override("separation", 16)
	_special_items_view_btn = Button.new()
	_special_items_view_btn.text = "View"
	_special_items_view_btn.pressed.connect(_on_special_item_view_pressed)
	row_si.add_child(_special_items_view_btn)
	_special_items_close_btn = Button.new()
	_special_items_close_btn.text = "Close"
	_special_items_close_btn.pressed.connect(_hide_special_items_list_window)
	row_si.add_child(_special_items_close_btn)
	vb_si.add_child(row_si)

	_apply_special_items_list_window_chrome()


func _apply_special_items_list_window_chrome() -> void:
	if _special_items_list_window == null:
		return
	ExplorerModalChrome.style_window_panel(_special_items_list_window, "gray")
	if _special_items_list_hint != null:
		ExplorerModalChrome.style_body_label(_special_items_list_hint, "gray")
	if _special_items_item_list != null:
		ExplorerModalChrome.style_item_list_for_explorer_list(_special_items_item_list)
	if _special_items_view_btn != null:
		ExplorerModalChrome.style_button(_special_items_view_btn, "primary", false)
	if _special_items_close_btn != null:
		ExplorerModalChrome.style_button(_special_items_close_btn, "secondary", false)


func _on_special_items_list_button_pressed() -> void:
	if _net_rep == null:
		return
	_explorer_audio().play_click()
	_ensure_special_items_list_window()
	_refresh_special_items_list_items()
	_special_items_list_window.popup_centered()
	_set_grid_hover_polish_for_modal(true)


func _refresh_special_items_list_items() -> void:
	if _special_items_item_list == null:
		return
	_special_items_item_list.clear()
	if _special_items_list_hint != null:
		if _special_item_keys.is_empty():
			_special_items_list_hint.text = ("No special items yet. Search features or open treasure for a chance to find one.")
		else:
			_special_items_list_hint.text = ("Select an item and press View or double-click (Explorer view_special_item).")
	var keys_arr: Array = []
	for j in range(_special_item_keys.size()):
		keys_arr.append(str(_special_item_keys[j]))
	var equipped_map: Dictionary = SpecialItemTable.get_equipped_items_by_keys(keys_arr)
	for i in range(_special_item_keys.size()):
		var key := str(_special_item_keys[i])
		var item: Dictionary = SpecialItemTable.lookup_by_key(key)
		var label := SpecialItemTable.format_list_view_message(item)
		var st := SpecialItemTable.inventory_status_for_item(item, equipped_map)
		label += "  (" + st + ")"
		if label.length() > 112:
			label = label.substr(0, 109) + "..."
		_special_items_item_list.add_item("%d. %s" % [i + 1, label])


func _hide_special_items_list_window() -> void:
	if _special_items_list_window != null and _special_items_list_window.visible:
		_explorer_audio().play_click()
		_special_items_list_window.hide()
		_set_grid_hover_polish_for_modal(false)


func _on_special_items_list_window_close_requested() -> void:
	_hide_special_items_list_window()


func _on_special_item_view_pressed() -> void:
	if _special_items_item_list == null:
		return
	var sel_si: PackedInt32Array = _special_items_item_list.get_selected_items()
	if sel_si.is_empty():
		return
	_open_special_item_detail_from_index(int(sel_si[0]))


func _on_special_item_item_activated(index: int) -> void:
	_open_special_item_detail_from_index(index)


func _open_special_item_detail_from_index(index: int) -> void:
	if index < 0 or index >= _special_item_keys.size():
		return
	_explorer_audio().play_click()
	if _special_items_list_window != null:
		_special_items_list_window.hide()
	_set_grid_hover_polish_for_modal(true)
	var key2 := str(_special_item_keys[index])
	var item2: Dictionary = SpecialItemTable.lookup_by_key(key2)
	var keys_arr2: Array = []
	for j2 in range(_special_item_keys.size()):
		keys_arr2.append(str(_special_item_keys[j2]))
	var eq2: Dictionary = SpecialItemTable.get_equipped_items_by_keys(keys_arr2)
	var st2 := SpecialItemTable.inventory_status_for_item(item2, eq2)
	var body_si := SpecialItemTable.format_list_view_message(item2)
	body_si += (
		"\n\n" + ("Status: " + st2 + " (auto-equip highest XP per slot, Explorer PlayerStats).")
	)
	_ensure_encounter_resolution_dialog()
	_encounter_res_dialog.title = "Special item"
	_encounter_res_dialog.dialog_text = body_si
	var sch_si := ExplorerModalChrome.scheme_for_encounter_resolution_title("Special item")
	ExplorerModalChrome.apply_accept_dialog_scheme(
		_encounter_res_dialog,
		sch_si,
		ExplorerModalChrome.ok_variant_for_encounter_resolution_title("Special item")
	)
	_encounter_res_dialog.popup_centered()


func _ensure_achievements_list_window() -> void:
	if _achievements_list_window != null:
		return
	_achievements_list_window = Window.new()
	_achievements_list_window.name = "AchievementsListWindow"
	_achievements_list_window.title = "Achievements"
	_achievements_list_window.size = Vector2i(520, 360)
	_achievements_list_window.popup_window = true
	_achievements_list_window.unresizable = true
	_achievements_list_window.transient = true
	_achievements_list_window.exclusive = true
	_achievements_list_window.visible = false
	_achievements_list_window.close_requested.connect(_on_achievements_list_window_close_requested)
	add_child(_achievements_list_window)

	var margin_ac := MarginContainer.new()
	margin_ac.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin_ac.add_theme_constant_override("margin_left", 14)
	margin_ac.add_theme_constant_override("margin_right", 14)
	margin_ac.add_theme_constant_override("margin_top", 12)
	margin_ac.add_theme_constant_override("margin_bottom", 12)
	_achievements_list_window.add_child(margin_ac)

	var vb_ac := VBoxContainer.new()
	vb_ac.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb_ac.add_theme_constant_override("separation", 10)
	margin_ac.add_child(vb_ac)

	_achievements_list_hint = Label.new()
	_achievements_list_hint.name = "AchievementsListHint"
	_achievements_list_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb_ac.add_child(_achievements_list_hint)

	_achievements_item_list = ItemList.new()
	_achievements_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_achievements_item_list.custom_minimum_size = Vector2(0, ExplorerModalChrome.SCROLL_BODY_MAX_PX)
	_achievements_item_list.allow_reselect = true
	_achievements_item_list.select_mode = ItemList.SELECT_SINGLE
	_achievements_item_list.item_activated.connect(_on_achievement_item_activated)
	vb_ac.add_child(_achievements_item_list)

	var row_ac := HBoxContainer.new()
	row_ac.alignment = BoxContainer.ALIGNMENT_CENTER
	row_ac.add_theme_constant_override("separation", 16)
	_achievements_view_btn = Button.new()
	_achievements_view_btn.text = "View"
	_achievements_view_btn.pressed.connect(_on_achievement_view_pressed)
	row_ac.add_child(_achievements_view_btn)
	_achievements_close_btn = Button.new()
	_achievements_close_btn.text = "Close"
	_achievements_close_btn.pressed.connect(_hide_achievements_list_window)
	row_ac.add_child(_achievements_close_btn)
	vb_ac.add_child(row_ac)

	_apply_achievements_list_window_chrome()


func _apply_achievements_list_window_chrome() -> void:
	if _achievements_list_window == null:
		return
	ExplorerModalChrome.style_window_panel(_achievements_list_window, "gray")
	if _achievements_list_hint != null:
		ExplorerModalChrome.style_body_label(_achievements_list_hint, "gray")
	if _achievements_item_list != null:
		ExplorerModalChrome.style_item_list_for_explorer_list(_achievements_item_list)
	if _achievements_view_btn != null:
		ExplorerModalChrome.style_button(_achievements_view_btn, "primary", false)
	if _achievements_close_btn != null:
		ExplorerModalChrome.style_button(_achievements_close_btn, "secondary", false)


func _on_achievements_list_button_pressed() -> void:
	if _net_rep == null:
		return
	_explorer_audio().play_click()
	_ensure_achievements_list_window()
	_refresh_achievements_list_items()
	_achievements_list_window.popup_centered()
	_set_grid_hover_polish_for_modal(true)


func _refresh_achievements_list_items() -> void:
	if _achievements_item_list == null:
		return
	_achievements_item_list.clear()
	if _achievements_list_hint != null:
		if _achievements_lines.is_empty():
			_achievements_list_hint.text = "No quest achievements yet. Complete a quest to record one here."
		else:
			_achievements_list_hint.text = ("Select an entry and press View or double-click (Explorer view_achievement).")
	for i in range(_achievements_lines.size()):
		var full_ac: String = str(_achievements_lines[i])
		var one_ac: String = full_ac.replace("\n", " ").strip_edges()
		if one_ac.length() > 96:
			one_ac = one_ac.substr(0, 93) + "..."
		_achievements_item_list.add_item("%d. %s" % [i + 1, one_ac])


func _hide_achievements_list_window() -> void:
	if _achievements_list_window != null and _achievements_list_window.visible:
		_explorer_audio().play_click()
		_achievements_list_window.hide()
		_set_grid_hover_polish_for_modal(false)


func _on_achievements_list_window_close_requested() -> void:
	_hide_achievements_list_window()


func _on_achievement_view_pressed() -> void:
	if _achievements_item_list == null:
		return
	var sel_ac: PackedInt32Array = _achievements_item_list.get_selected_items()
	if sel_ac.is_empty():
		return
	_open_achievement_detail_from_index(int(sel_ac[0]))


func _on_achievement_item_activated(index: int) -> void:
	_open_achievement_detail_from_index(index)


func _open_achievement_detail_from_index(index: int) -> void:
	if index < 0 or index >= _achievements_lines.size():
		return
	_explorer_audio().play_click()
	if _achievements_list_window != null:
		_achievements_list_window.hide()
	_set_grid_hover_polish_for_modal(true)
	var body_ac := str(_achievements_lines[index])
	_ensure_encounter_resolution_dialog()
	_encounter_res_dialog.title = "Achievement"
	_encounter_res_dialog.dialog_text = body_ac
	var sch_ac := ExplorerModalChrome.scheme_for_encounter_resolution_title("Achievement")
	ExplorerModalChrome.apply_accept_dialog_scheme(
		_encounter_res_dialog,
		sch_ac,
		ExplorerModalChrome.ok_variant_for_encounter_resolution_title("Achievement")
	)
	_encounter_res_dialog.popup_centered()


func _on_player_local_stats_changed(
	gold: int,
	xp: int,
	hp: int,
	max_hp: int,
	torch_burn_pct: int,
	torch_spares: int,
	level: int,
	xp_to_next: int,
	player_alignment: int,
	npcs_killed: int
) -> void:
	_last_gold = gold
	_last_xp = xp
	_last_hp = hp
	_last_max_hp = max_hp
	_last_level = level
	_last_xp_to_next = xp_to_next
	_last_player_alignment = player_alignment
	_last_npcs_killed = npcs_killed
	_hud_torch_burn = torch_burn_pct
	_hud_torch_spares = torch_spares
	_ensure_stats_hud()
	_refresh_stats_hud_text()


func _ensure_path_step_timer() -> void:
	if _path_step_timer != null:
		return
	_path_step_timer = Timer.new()
	_path_step_timer.name = "PathVisualStepTimer"
	_path_step_timer.one_shot = true
	_path_step_timer.timeout.connect(_on_path_visual_step_timer)
	add_child(_path_step_timer)


func _cancel_path_visual() -> void:
	_path_visual_gen += 1
	if _path_step_timer != null and is_instance_valid(_path_step_timer):
		_path_step_timer.stop()
	_path_visual_active = false
	_path_visual_path.clear()
	_path_visual_next_idx = 0
	_path_visual_audio_edges = 0


func _start_path_visual(path: PackedVector2Array, _view: Node2D) -> void:
	_cancel_path_visual()
	if path.is_empty() or _local_peer_id < 0:
		return
	_path_visual_active = true
	_path_visual_path = path.duplicate()
	_path_visual_start = _net_local_cell
	_path_visual_display = _net_local_cell
	_path_visual_next_idx = 0
	_path_visual_audio_edges = 0
	_ensure_path_step_timer()
	_path_step_timer.set_meta("path_vis_gen", _path_visual_gen)
	_path_step_timer.start(PATH_VISUAL_STEP_SEC)


func _on_path_visual_step_timer() -> void:
	if _path_step_timer == null or not is_instance_valid(_path_step_timer):
		return
	var run_g := int(_path_step_timer.get_meta("path_vis_gen", -999))
	if run_g != _path_visual_gen or not _path_visual_active:
		return
	if _path_visual_next_idx >= _path_visual_path.size():
		return
	var nxt := Vector2i(
		int(_path_visual_path[_path_visual_next_idx].x),
		int(_path_visual_path[_path_visual_next_idx].y)
	)
	if not GridWalk.is_king_adjacent(_path_visual_display, nxt):
		_cancel_path_visual()
		return
	_path_visual_display = nxt
	_path_visual_next_idx += 1
	var role_v := str(_last_peer_roles.get(_local_peer_id, "rogue"))
	if _grid_view != null and _grid_view.has_method("sync_peer_marker"):
		_grid_view.sync_peer_marker(
			_local_peer_id, _path_visual_display, role_v, _marker_label_text(_local_peer_id)
		)
	_last_peer_cells[_local_peer_id] = _path_visual_display
	_explorer_audio().play_move_step()
	_path_visual_audio_edges += 1
	if _path_visual_next_idx < _path_visual_path.size():
		_path_step_timer.set_meta("path_vis_gen", _path_visual_gen)
		_path_step_timer.start(PATH_VISUAL_STEP_SEC)


func _on_net_fog_delta(cells: PackedVector2Array, view: Node2D) -> void:
	for i in range(cells.size()):
		_client_revealed[Vector2i(int(cells[i].x), int(cells[i].y))] = true
	if view.has_method("apply_fog_reveal_delta"):
		view.apply_fog_reveal_delta(cells)


func _on_net_grid_clicked(c: Vector2i, net_rep: Node, view: Node2D) -> void:
	if _welcome_fog_on and not _client_revealed.get(c, false):
		if view.has_method("clear_path_preview"):
			view.clear_path_preview()
		net_rep.client_request_fog_square_click(c.x, c.y)
		return
	if _can_interact_door_cell(c):
		if view.has_method("clear_path_preview"):
			view.clear_path_preview()
		net_rep.client_request_door_click(c.x, c.y)
		return
	if _local_peer_id >= 0:
		if c == _net_local_cell:
			var raw_self: String = GridWalk.tile_at(_path_grid, c)
			if GridWalk.world_interaction_stand_kind(raw_self) != "":
				if _cell_revealed_for_interaction(c):
					if view.has_method("clear_path_preview"):
						view.clear_path_preview()
					net_rep.client_request_world_interaction(c.x, c.y)
				return
		var eff_c: String = GridWalk.tile_effective(_path_grid, c, _trap_defused)
		if (
			GridWalk.world_interaction_remote_kind(eff_c) != ""
			and _cell_revealed_for_interaction(c)
		):
			if view.has_method("clear_path_preview"):
				view.clear_path_preview()
			net_rep.client_request_world_interaction(c.x, c.y)
			return
	if _path_visual_active:
		if view.has_method("clear_path_preview"):
			view.clear_path_preview()
		return
	var path := GridPathfinding.find_path_8dir(
		_path_grid,
		_net_local_cell,
		c,
		_client_revealed,
		_welcome_fog_on,
		_client_unlocked,
		_trap_defused,
		_hud_guards_hostile
	)
	if path.is_empty():
		if view.has_method("clear_path_preview"):
			view.clear_path_preview()
		return
	if path.size() == 1:
		if view.has_method("clear_path_preview"):
			view.clear_path_preview()
		var v := path[0]
		var eff_v: String = GridWalk.tile_effective(
			_path_grid, Vector2i(int(v.x), int(v.y)), _trap_defused
		)
		if GridWalk.should_offer_door_prompt_before_move(
			eff_v, Vector2i(int(v.x), int(v.y)), _client_unlocked
		):
			net_rep.client_request_door_click(int(v.x), int(v.y))
			return
		net_rep.client_request_move(int(v.x), int(v.y))
	else:
		if view.has_method("set_path_preview"):
			view.set_path_preview(path)
		_start_path_visual(path, view)
		net_rep.client_request_path_move(path)


func _on_net_player_position(peer_id: int, cell: Vector2i, role: String, view: Node2D) -> void:
	if peer_id == _local_peer_id:
		if _path_visual_active:
			var n_edges := GridPathfinding.king_step_count_along_path_prefix(
				_path_visual_start, _path_visual_path, cell
			)
			if n_edges >= 0:
				while _path_visual_audio_edges < n_edges:
					_explorer_audio().play_move_step()
					_path_visual_audio_edges += 1
			_cancel_path_visual()
			_net_local_cell = cell
		else:
			var prev_cell := _net_local_cell
			_net_local_cell = cell
			if prev_cell != cell:
				_explorer_audio().play_move_step()
		if view.has_method("clear_path_preview"):
			view.clear_path_preview()
	if view.has_method("sync_peer_marker"):
		_last_peer_cells[peer_id] = cell
		_last_peer_roles[peer_id] = role
		view.sync_peer_marker(peer_id, cell, role, _marker_label_text(peer_id))


func _unhandled_input(event: InputEvent) -> void:
	if _net_rep == null or _local_peer_id < 0:
		return
	if _secret_door_notice != null and _secret_door_notice.visible:
		return
	if _door_window != null and _door_window.visible:
		return
	if _encounter_window != null and _encounter_window.visible:
		return
	if _encounter_res_dialog != null and _encounter_res_dialog.visible:
		return
	if _rumors_list_window != null and _rumors_list_window.visible:
		return
	if _special_items_list_window != null and _special_items_list_window.visible:
		return
	if _combat_window != null and _combat_window.visible:
		return
	if _world_dialog != null and _world_dialog.visible:
		return
	if _path_visual_active:
		return
	var e := event as InputEventKey
	if e == null or not e.pressed or e.echo:
		return
	if e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
		return
	var d := _key_to_move_delta_from_event(e)
	if d == Vector2i.ZERO:
		return
	var target := _net_local_cell + d
	if _grid_view != null and _grid_view.has_method("clear_path_preview"):
		_grid_view.clear_path_preview()
	if _can_interact_door_cell(target):
		_net_rep.client_request_door_click(target.x, target.y)
	else:
		_net_rep.client_request_move(target.x, target.y)
	get_viewport().set_input_as_handled()


## Matches `DungeonWeb.DungeonLive.Movement` @key_directions (orthogonal only).
func _key_to_move_delta_from_event(e: InputEventKey) -> Vector2i:
	var k := e.physical_keycode
	if k == KEY_NONE:
		k = e.keycode
	match k:
		KEY_W, KEY_UP:
			return Vector2i(0, -1)
		KEY_S, KEY_DOWN:
			return Vector2i(0, 1)
		KEY_A, KEY_LEFT:
			return Vector2i(-1, 0)
		KEY_D, KEY_RIGHT:
			return Vector2i(1, 0)
		_:
			return Vector2i.ZERO
