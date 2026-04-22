extends Node

## Phase 3–4: authority dungeon + moves + fog + doors (click → `rpc_door_prompt` → confirm RPCs).

const TraditionalGen := preload("res://dungeon/generator/traditional_generator.gd")
const DungeonGenerator := preload("res://dungeon/generator/dungeon_generator.gd")
const DungeonThemes := preload("res://dungeon/generator/dungeon_themes.gd")
const MapTransition := preload("res://dungeon/map_transition_system.gd")
const MapLinkSystem := preload("res://dungeon/generator/map_link_system.gd")
const GridWalk := preload("res://dungeon/movement/grid_walkability.gd")
const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")
const DungeonFeatures := preload("res://dungeon/generator/features_dungeon.gd")
const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const TreasureSys := preload("res://dungeon/treasure/treasure_system.gd")
const EncounterSys := preload("res://dungeon/encounter/encounter_system.gd")
const WorldLabelsMsg := preload("res://dungeon/world/world_labels_messages.gd")
const SpecialFeatInv := preload("res://dungeon/world/special_feature_investigation.gd")
const SpecialFeatureTrapCopy := preload("res://dungeon/world/special_feature_trap_copy.gd")
const SpecialItemTable := preload("res://dungeon/world/special_item_table.gd")
const CombatResolver := preload("res://dungeon/combat/combat_resolver.gd")
const PlayerCombatStats := preload("res://dungeon/combat/player_combat_stats.gd")
const MonsterTable := preload("res://dungeon/combat/monster_table.gd")
const MonsterTurn := preload("res://dungeon/monster/monster_turn_system.gd")
const GridPath := preload("res://dungeon/movement/grid_pathfinding.gd")
const ConsumablePickup := preload("res://dungeon/world/consumable_pickup.gd")
const PlayerQuests := preload("res://dungeon/world/player_quests.gd")
const PlayerProgression := preload("res://dungeon/progression/player_progression.gd")
const PlayerTalents := preload("res://dungeon/progression/player_talents.gd")
const PlayerAlignment := preload("res://dungeon/progression/player_alignment.gd")
const JoinMetadata := preload("res://dungeon/network/join_metadata.gd")
const GridTilePatchCodec := preload("res://dungeon/network/grid_tile_patch_codec.gd")

## ENet host / dedicated server peer id in Godot high-level multiplayer.
const SERVER_PEER_ID := 1
## Local single-player / editor: synthetic peer id (no ENet); must not collide with SERVER_PEER_ID.
const SOLO_LOCAL_PEER_ID := 2

## CMB-02: Explorer `monster_turn_system.ex` schedules `{:trigger_monster_combat}` after 400ms so the monster move animation can play.
const MONSTER_COMBAT_UI_DELAY_SEC := 0.4
## Explorer `CombatSystem` — `Process.send_after(..., 1000)` before `process_monster_turn` / round monster-first.
const COMBAT_MONSTER_STRIKE_DELAY_SEC := 1.0
## Set to `>= 0` in tests (`check_parse.gd`) to skip real-time delay; default **-1** = use `MONSTER_COMBAT_UI_DELAY_SEC`.
static var monster_combat_ui_delay_sec_for_tests: float = -1.0
## Explorer `PathfindingHook` cadence — delay between authoritative path cells (`dungeon_session.gd` `PATH_VISUAL_STEP_SEC` historically).
const PATH_MOVE_STEP_SEC := 0.072
## Set to `>= 0` in tests to apply path steps without wall-clock delay; default **-1** = use `PATH_MOVE_STEP_SEC`.
static var path_move_step_sec_for_tests: float = -1.0

## Bumped when welcome/dungeon RPC fields change incompatibly (6 = `authority_player_level`; 7 = tail `own_display_name` on `rpc_receive_authority_dungeon` + welcome `display_name`; 8 = tail `peer_display_names` dict on RPC + welcome + `rpc_peer_display_names_snapshot`; 9 = tail `listen_port`, `server_boot_unix_sec`, `party_peer_count` on RPC + welcome).
const WELCOME_SCHEMA_VERSION := 9

signal authority_dungeon_synchronized(
	seed: int, theme: String, grid: Dictionary, welcome: Dictionary
)
## Dedicated / listen-host ops: emitted on the **server** when the authority map changes (stairs / waypoints / links). Not used for solo local.
signal server_world_meta_changed(
	seed: int,
	theme_dir: String,
	checksum: int,
	theme_name: String,
	dungeon_level: int,
	connected_client_count: int
)
signal authority_dungeon_failed(reason: String)
signal player_position_updated(peer_id: int, cell: Vector2i, role: String, torch_burn_pct: int)
signal fog_reveal_delta(cells: PackedVector2Array)
## Full replace of revealed cells (torch expired / server resync).
signal fog_full_resync(cells: PackedVector2Array)
## Explorer `clicked_squares` subset — fog manual reveal + door-trap glyph under fog.
signal fog_clicked_cells_delta(cells: PackedVector2Array)
signal fog_clicked_cells_snapshot(cells: PackedVector2Array)
signal unlocked_doors_snapshot(cells: PackedVector2Array)
signal unlocked_doors_delta(cells: PackedVector2Array)
signal unpickable_doors_snapshot(cells: PackedVector2Array)
signal unpickable_doors_delta(cells: PackedVector2Array)
signal trap_inspected_doors_snapshot(cells: PackedVector2Array)
signal trap_inspected_doors_delta(cells: PackedVector2Array)
## Explorer `skip_detected_trap` — clear trap-inspected overlay so detection can roll again.
signal trap_inspected_doors_remove_delta(cells: PackedVector2Array)
## Door trap removed after disarm (Explorer `remove_detected_trap` → `locked_door` / `door`).
signal trap_defused_doors_snapshot(cells: PackedVector2Array)
signal trap_defused_doors_delta(cells: PackedVector2Array)
## Client: door interaction prompt (Explorer `DoorSystem` click → trap survey / unlock / pass).
signal door_prompt_offered(action: String, cell: Vector2i, message: String)
## Phase 5: world interactions + map transitions + treasure / room-trap pickup (authoritative grid patches).
signal world_interaction_offered(kind: String, cell: Vector2i, title: String, message: String)
## Single-cell authority mutation (treasure taken, room trap cleared, …).
signal authority_tile_patched(cell: Vector2i, new_tile: String)
## Local peer gold/XP/HP (Explorer `player_gold` / `player_xp`; HP from `PlayerStats` base slice).
## `torch_burn_pct` 0–100, or **-1** when fog is off (HUD hides torch). `torch_spares` = max(0, total−1), or **-1** with daylight (HUD omits spare count).
## `level` / `xp_to_next` are **this peer's** Explorer `PlayerStats` curve; dungeon regen uses **max** party level (see `_authority_recompute_player_level_from_party_xp`).
## `player_alignment` is Explorer `player_alignment` (numeric; shifts in P7-03+).
## `npcs_killed` mirrors Explorer `npcs_killed_count` (peaceful npc/guard while guards not hostile).
## `healing_potion_count` — Explorer `healing_potion_count` inventory. Combat line mirrors Explorer dashboard assigns.
signal player_local_stats_changed(
	gold: int,
	xp: int,
	hp: int,
	max_hp: int,
	torch_burn_pct: int,
	torch_spares: int,
	level: int,
	xp_to_next: int,
	player_alignment: int,
	npcs_killed: int,
	healing_potion_count: int,
	armor_class: int,
	attack_bonus: int,
	weapon_name: String,
	weapon_damage_dice: String
)
## Phase 5: Explorer `rumors` assign — replicated list for HUD / future rumors dialog.
signal player_rumors_updated(rumors: PackedStringArray)
## P7-04: Explorer `special_items` — item keys (see `special_items.json`).
signal player_special_items_updated(keys: PackedStringArray)
## P7-05: Explorer `quests` — JSON rows (`Dungeon.Quest` special_item slice).
signal player_quests_updated(quest_rows: PackedStringArray)
## P7-07: Explorer `achievements` — one string per completed quest (MVP: quest completions only).
signal player_achievements_updated(lines: PackedStringArray)
## P7-01: Explorer `show_level_up_dialog` — static copy + talent line; dismiss appends achievement (P7-07).
signal level_up_dialog_offered(new_level: int, primary_message: String, talent_message: String)
## P7-09: sanitized co-op display name (welcome dict + optional late `rpc_own_display_name`).
signal player_display_name_changed(display_name: String)
## P7-09: all party display names for map markers (keys: peer id int; values: string). Updated on welcome + join/disconnect.
signal peer_display_names_updated(peer_display_names: Dictionary)
## Phase 5.4: fight / evade outcome modal (AcceptDialog); failed evade is evade copy only until Phase 6 combat UI.
signal encounter_resolution_dialog(title: String, message: String)
## Phase 6: per-turn combat UI (HP + log + Attack); final snapshot includes `outcome_title` / `outcome_body` when `finished`.
signal combat_state_changed(snapshot: Dictionary)
## Phase 6: Explorer `DoorSystem` — first successful **break door** on a map sets `guards_hostile` (for future wandering guards / encounters).
signal guards_hostile_changed(hostile: bool)
## Explorer `Movement.check_secret_doors_adjacent` — revealed secret door cells (global on map).
signal secret_doors_delta(cells: PackedVector2Array)
signal secret_doors_snapshot(cells: PackedVector2Array)

var _authority_seed: int = 0
var _authority_theme: String = "up"
var _authority_checksum: int = 0
var _authority_grid: Dictionary = {}
## Full theme name from generation (`Ancient Castle`, …). Clients regenerate with this + `_dungeon_level`.
var _authority_theme_name: String = ""
var _dungeon_level: int = 1
var _player_level: int = 1
var _generation_type: String = "dungeon"
## Generator room rects/cells (Explorer `dungeon.rooms`) for treasure floor/corridor restoration.
var _authority_rooms: Array = []
## Explorer `dungeon.corridors` — corridor paths for `FogOfWar.reveal_area_labels`.
var _authority_corridors: Array = []
## Server: per-peer loot stats (co-op keyed by peer_id).
var _server_gold: Dictionary = {}
var _server_xp: Dictionary = {}
## Server: Explorer `player_alignment` (lawful/chaotic gates); replicated with local stats.
var _server_player_alignment: Dictionary = {}
## Explorer `npcs_killed_count` — per peer; reset on new floor (`_server_apply_map_transition`).
var _server_npcs_killed_by_peer: Dictionary = {}
## Explorer `healing_potion_count` — carried potions (pickup adds; HUD drink consumes).
var _server_healing_potions_by_peer: Dictionary = {}
## Server: peer combat HP (Explorer `player_hit_points`; talents + rolled level HP in **P7-01**).
var _server_player_hp: Dictionary = {}
var _server_player_max_hp: Dictionary = {}
## P7-01: Explorer `talent_bonuses` / `level_hit_points` (server-authoritative; deterministic rolls).
var _server_talent_bonuses_by_peer: Dictionary = {}
var _server_level_hp_total_by_peer: Dictionary = {}
var _server_level_up_queue_by_peer: Dictionary = {}
var _server_level_up_waiting: Dictionary = {}
## Phase 6: authoritative interactive combat (one session per peer).
var _server_combat_by_peer: Dictionary = {}
## CMB-02: per-peer serial bumped when scheduling delayed encounter; cleared on map transition; `erase` on disconnect.
var _monster_combat_delay_serial_by_peer: Dictionary = {}
## Interactive combat: bump invalidates pending `SceneTreeTimer` before deferred monster strike (Explorer 1s beat).
var _combat_monster_strike_serial_by_peer: Dictionary = {}
## Server: stepped `rpc_request_path_move` — bump invalidates pending `SceneTreeTimer` callbacks (Explorer one `move_player` per tile).
var _path_move_serial_by_peer: Dictionary = {}
## Server: peer_id -> remaining `Vector2i` steps (king-adjacent cells to enter in order).
var _path_move_queue_by_peer: Dictionary = {}
## Server: peer_id -> locked door cell to open after the queue drains (Explorer path stops before door).
var _path_move_door_after_by_peer: Dictionary = {}
## Fallback role in welcome if a peer never sends `rpc_client_join_request` in time.
var _welcome_role_echo: String = "rogue"
var _next_party_slot: int = 0
var _peer_party_slots: Dictionary = {}
var _peer_roles: Dictionary = {}
## P7-09: server-only; ENet `peer_id` -> final display string (never empty after join RPC).
var _peer_display_names: Dictionary = {}
## Server: peer_id -> cell; client: own spawn only (for smoke / helpers).
var _player_positions: Dictionary = {}
var _client_spawn_cell: Vector2i = Vector2i.ZERO
## Server: peer_id -> revealed cells (Vector2i keys). Client: own revealed (from welcome + deltas).
var _revealed_by_peer: Dictionary = {}
var _client_revealed: Dictionary = {}
## Server: peer_id -> (Vector2i -> true). Client: own fog-clicked cells (Explorer `clicked_squares`).
var _clicked_fog_by_peer: Dictionary = {}
var _client_fog_clicked: Dictionary = {}
var _fog_enabled: bool = true
var _fog_radius: int = 1
## Explorer `fog_type` string (daylight / dim / dark); drives default radius when override is absent.
var _fog_type: String = "dark"
## When false, moves do not expand fog (Explorer `torch_will_be_active` / last-step burn); daylight forces true.
var _torch_reveals_moves: bool = true
## Server: global unlocked locked-door cells (Explorer `unlocked_doors`). Client: replicated copy.
var _unlocked_doors: Dictionary = {}
var _client_unlocked_doors: Dictionary = {}
## Server: failed lock-picks (Explorer `unpickable_doors`). Replicated for UI.
var _unpickable_doors: Dictionary = {}
var _client_unpickable_doors: Dictionary = {}
## Server: door trap detection survey completed for this cell (Explorer trap gate before unlock/pass).
var _door_trap_checked: Dictionary = {}
## Server: trap spotted (DC 15) and awaiting disarm roll.
var _trap_disarm_pending: Dictionary = {}
## Server + client: door cells whose trap mechanism was removed (tile effective → plain door / locked_door).
var _trap_defused_doors: Dictionary = {}
var _client_trap_defused: Dictionary = {}
## Client: replicated trap-inspected door cells (Explorer `show_trap` on map).
var _client_trap_inspected_doors: Dictionary = {}
## Optional tag for `godot4 --client … --client-label foo` so parallel client logs are distinguishable.
var _client_log_label: String = ""
## `-1` = networked or uninitialized; `SOLO_LOCAL_PEER_ID` = `Main` local session (no multiplayer peer).
var _solo_offline_peer: int = -1
## P7-09: last solo `display_name` echoed on `authority_dungeon_synchronized` (map transitions reuse).
var _solo_cached_display_name: String = "Explorer"
## Client: last `rpc_combat_state` / solo combat snapshot (for headless probe).
var _last_combat_snapshot: Dictionary = {}
## Server: `trapped_treasure` cell awaiting disarm roll after successful DC 15 detect.
var _treasure_trap_disarm_pending: Dictionary = {}
## Server: `room_trap` cell awaiting disarm after successful DC 15 detect (Explorer `Movement` + trap detection).
var _room_trap_disarm_pending: Dictionary = {}
## Server: rumor dialog shown; award `RUMOR_XP` on `client_request_rumor_dismiss` (Explorer `dismiss_rumor`).
var _server_rumor_xp_pending: Dictionary = {}
## Server: peer_id -> rumor strings (Explorer `assigns.rumors`).
var _server_rumors_by_peer: Dictionary = {}
## Server: peer_id -> Array of quest dictionaries (Explorer `assigns.quests` + `npc_quests` merged JSON rows).
var _server_quests_by_peer: Dictionary = {}
## Server: peer_id -> Array of achievement strings (`dungeon_live.ex` `dismiss_quest_completed` append).
var _server_achievements_by_peer: Dictionary = {}
## Server: peer awaiting **Accept/Decline** on an NPC-offered kill quest (`NpcQuestSystem` offer flow).
var _server_pending_npc_quest: Dictionary = {}
## Server: peer_id -> Array of special item keys (`special_items.json`).
var _server_special_items_by_peer: Dictionary = {}
## Server: XP to award when client dismisses the current "Special item" dialog (Explorer `dismiss_special_item`).
var _server_special_item_dismiss_xp_pending: Dictionary = {}
## Server: peer_id -> Dictionary with Vector2i keys — special feature cells investigated this map.
var _server_investigated_features: Dictionary = {}
## Server: peer_id -> Dictionary — auto "Something Interesting!" dialog already offered this map (step-once).
var _server_feature_discovery_prompted: Dictionary = {}
## Explorer `map_link_descriptions` — destination theme name committed per cell for dialog + transition.
var _server_map_link_destination_by_cell: Dictionary = {}
## Explorer `waypoint_descriptions` — destination theme per cell for city/outdoor waypoint travel.
var _server_waypoint_destination_by_cell: Dictionary = {}
## Server: peer awaiting feature-trap damage after first dialog (Explorer trap dialog → `dismiss_trap`).
var _server_feature_trap_pending: Dictionary = {}
## Server: peer awaiting "Ambush!" OK before `start_combat` (Explorer defers `surprise_monster_combat` one turn).
var _server_feature_ambush_pending: Dictionary = {}
## Server: cumulative logical tile overrides vs pristine seed regen (late join + live coalesced `rpc_authority_tile_patch_batch`).
var _server_authority_tile_patches: Dictionary = {}
## Client (networked): grid after welcome + all `rpc_authority_tile_patch` (for headless probes / parity checks).
var _client_merged_grid: Dictionary = {}

## Phase 4.7: Explorer `torch_burn_time` / `torch_count` (percent 0–100 while active torch burns).
const TORCH_BURN_FULL := 100
const DOOR_TRAP_DETECT_DC := 15
## Explorer treasure-trap detection uses same DC 15 as doors (`attempt_trap_detection`).
const TREASURE_TRAP_DETECT_DC := 15
const TRAP_DISARM_DC := 15
## Explorer `handle_successful_trap_disarm` awards 10 XP for trap disarm (treasure + room skull).
const TRAP_DISARM_XP_TREASURE := 10
## Explorer `dismiss_rumor` awards 25 XP on first rumor note.
const RUMOR_XP := 25
## Explorer `TreasureSystem.check_treasure_special_item` uses 5% on chest dismiss.
const SPECIAL_ITEM_CHANCE_ON_TREASURE := 5
## Deterministic salts for `SpecialItemTable.pick_deterministic` (distinct from investigation roll salts).
const SPECIAL_ITEM_PICK_SALT_FEATURE := 712_004_321
const SPECIAL_ITEM_PICK_SALT_TREASURE := 712_004_322
const BREAK_DOOR_DC := 13
## Explorer `door_system.ex` `award_xp(10, "door broken")` on successful break.
const BREAK_DOOR_XP := 10
## Explorer `DoorSystem.pick_lock` `award_xp(5, "lock picked")`.
const LOCK_PICK_XP := 5
const FOG_DELTA_PACK_THRESHOLD := 36
## Explorer `Movement.process_fog_revelation`: XP per newly revealed **disk** cell = `(1 + dungeon_level)`; skipped for daylight.
## Server: successful breaks this map (Explorer `doors_broken_count`); first break sets `guards_hostile`.
var _authority_doors_broken_count: int = 0
var _authority_guards_hostile: bool = false
## Client: last value from `rpc_guards_hostile_sync` / solo mirror.
var _client_guards_hostile: bool = false
## Server: globally revealed `secret_door` cells (any peer detection). Client: RPC mirror.
var _revealed_secret_doors: Dictionary = {}
var _client_revealed_secret_doors: Dictionary = {}
var _torch_burn_by_peer: Dictionary = {}
var _torch_count_by_peer: Dictionary = {}
## Headless `--smoke-torch-expire-probe`: after welcome, set joining peer torch to last step before expire.
var _smoke_torch_expire_probe_server: bool = false
## P7-15: `--debug-net` logs packed patch batch sizes on the server.
var _debug_net: bool = false
## Phase 8 / P7-14: coalesce live `rpc_authority_tile_patch` into one end-of-frame `rpc_authority_tile_patch_batch`.
const LIVE_TILE_PATCH_RPC_BATCHING := true
var _live_tile_patch_rpc_pending: Dictionary = {}
var _live_tile_patch_rpc_flush_queued: bool = false
## Phase 3: ENet listen port and process boot time (UTC unix sec) for welcome payload; set via `set_server_listen_metadata`.
var _server_listen_port: int = 0
var _server_boot_unix_sec: int = 0


func set_smoke_torch_expire_probe_server(enabled: bool) -> void:
	_smoke_torch_expire_probe_server = enabled


func set_client_log_label(label: String) -> void:
	_client_log_label = label


func set_debug_net(enabled: bool) -> void:
	_debug_net = enabled


## Call once after `create_server` succeeds (see `dungeon_server_bootstrap.gd`). Idempotent boot timestamp.
func set_server_listen_metadata(listen_port: int) -> void:
	_server_listen_port = clampi(listen_port, 0, 65535)
	if _server_boot_unix_sec <= 0:
		_server_boot_unix_sec = int(Time.get_unix_time_from_system())


## One-line host metrics for `--metrics-interval-sec` (dedicated / `Main --server`); empty if not server.
func dedicated_metrics_line_for_host() -> String:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return "dungeoneers_host role=server peers=0 (no multiplayer_peer)"
	var n := multiplayer.get_peers().size()
	var uptime_s := 0
	if _server_boot_unix_sec > 0:
		uptime_s = maxi(0, int(Time.get_unix_time_from_system()) - _server_boot_unix_sec)
	return (
		"dungeoneers_host peers=%d seed=%d checksum=%d dungeon_level=%d theme_name=%s fog_type=%s listen_port=%d uptime_s=%d"
		% [
			n,
			_authority_seed,
			_authority_checksum,
			_dungeon_level,
			_authority_theme_name,
			_fog_type,
			_server_listen_port,
			uptime_s,
		]
	)


func _dng_print(msg: String) -> void:
	if _client_log_label.is_empty():
		print("[Dungeoneers] ", msg)
	else:
		print("[Dungeoneers][", _client_log_label, "] ", msg)


func _normalize_join_role(requested: String) -> String:
	var t := requested.strip_edges()
	if t.is_empty():
		return _welcome_role_echo if not _welcome_role_echo.is_empty() else "rogue"
	if t.length() > 48:
		t = t.substr(0, 48)
	return t


func configure_authority(
	authority_seed: int,
	theme: String,
	checksum: int,
	welcome_role_echo: String,
	authority_grid: Dictionary,
	fog_enabled: bool = true,
	fog_radius_override: int = -1,
	fog_type_arg: String = "",
	torch_reveals_moves: bool = true,
	generation_meta: Dictionary = {}
) -> void:
	_authority_seed = authority_seed
	_authority_theme = theme
	_authority_checksum = checksum
	_welcome_role_echo = welcome_role_echo if not welcome_role_echo.is_empty() else "rogue"
	_authority_grid = authority_grid
	_authority_theme_name = str(generation_meta.get("theme_name", "")).strip_edges()
	if _authority_theme_name.is_empty():
		_authority_theme_name = "Ancient Castle" if theme == "up" else "Dark Caverns"
	_dungeon_level = maxi(1, int(generation_meta.get("dungeon_level", 1)))
	_player_level = maxi(1, int(generation_meta.get("player_level", 1)))
	_generation_type = str(generation_meta.get("generation_type", "dungeon")).strip_edges()
	if _generation_type.is_empty():
		_generation_type = "dungeon"
	var rms: Variant = generation_meta.get("rooms", [])
	if rms is Array:
		_authority_rooms = (rms as Array).duplicate()
	else:
		_authority_rooms.clear()
	var crm: Variant = generation_meta.get("corridors", [])
	if crm is Array:
		_authority_corridors = (crm as Array).duplicate()
	else:
		_authority_corridors.clear()
	_revealed_secret_doors.clear()
	_server_gold.clear()
	_server_xp.clear()
	_server_player_alignment.clear()
	_server_npcs_killed_by_peer.clear()
	_server_healing_potions_by_peer.clear()
	_server_player_hp.clear()
	_server_player_max_hp.clear()
	_server_talent_bonuses_by_peer.clear()
	_server_level_hp_total_by_peer.clear()
	_server_level_up_queue_by_peer.clear()
	_server_level_up_waiting.clear()
	_fog_enabled = fog_enabled
	if fog_type_arg.strip_edges().is_empty():
		var meta_ft := str(generation_meta.get("fog_type", "")).strip_edges()
		if not meta_ft.is_empty():
			_fog_type = DungeonFog.normalize_fog_type(meta_ft)
		else:
			DungeonThemes.load_themes()
			var theme_row_fog: Dictionary = DungeonThemes.find_theme_by_name(_authority_theme_name)
			var exported_fog := str(theme_row_fog.get("fog_type", "")).strip_edges()
			if not exported_fog.is_empty():
				_fog_type = DungeonFog.normalize_fog_type(exported_fog)
			else:
				## Theme missing from export: legacy stair-direction default (matches `generate_for_legacy_cli` names).
				_fog_type = DungeonFog.normalize_fog_type("dark" if theme == "down" else "dim")
	else:
		_fog_type = DungeonFog.normalize_fog_type(fog_type_arg)
	if fog_radius_override >= 0:
		_fog_radius = clampi(fog_radius_override, 0, 8)
	else:
		_fog_radius = DungeonFog.fog_radius_for_type(_fog_type)
	_torch_reveals_moves = torch_reveals_moves or (_fog_type == "daylight")
	_next_party_slot = 0
	_peer_party_slots.clear()
	_peer_roles.clear()
	_peer_display_names.clear()
	_player_positions.clear()
	_revealed_by_peer.clear()
	_client_revealed.clear()
	_client_revealed_secret_doors.clear()
	_unlocked_doors.clear()
	_client_unlocked_doors.clear()
	_unpickable_doors.clear()
	_client_unpickable_doors.clear()
	_door_trap_checked.clear()
	_trap_disarm_pending.clear()
	_trap_defused_doors.clear()
	_client_trap_defused.clear()
	_client_trap_inspected_doors.clear()
	_clicked_fog_by_peer.clear()
	_client_fog_clicked.clear()
	_torch_burn_by_peer.clear()
	_torch_count_by_peer.clear()
	_server_combat_by_peer.clear()
	_combat_monster_strike_serial_by_peer.clear()
	_path_move_serial_by_peer.clear()
	_path_move_queue_by_peer.clear()
	_path_move_door_after_by_peer.clear()
	_treasure_trap_disarm_pending.clear()
	_room_trap_disarm_pending.clear()
	_server_rumor_xp_pending.clear()
	_server_rumors_by_peer.clear()
	_server_quests_by_peer.clear()
	_server_achievements_by_peer.clear()
	_server_pending_npc_quest.clear()
	_server_special_items_by_peer.clear()
	_server_special_item_dismiss_xp_pending.clear()
	_server_investigated_features.clear()
	_server_feature_discovery_prompted.clear()
	_server_map_link_destination_by_cell.clear()
	_server_waypoint_destination_by_cell.clear()
	_server_feature_trap_pending.clear()
	_server_feature_ambush_pending.clear()
	_server_authority_tile_patches.clear()
	_live_tile_patch_rpc_pending.clear()
	_live_tile_patch_rpc_flush_queued = false
	_client_merged_grid.clear()
	_authority_doors_broken_count = 0
	_authority_guards_hostile = false
	_client_guards_hostile = false
	_solo_offline_peer = -1
	_solo_cached_display_name = "Explorer"
	_server_listen_port = 0
	_server_boot_unix_sec = 0


func _using_solo_local() -> bool:
	return _solo_offline_peer >= 0


func _notify_client_fog_delta(peer_id: int, delta: PackedVector2Array) -> void:
	if delta.is_empty():
		return
	if _using_solo_local() and peer_id == _solo_offline_peer:
		for i in range(delta.size()):
			var vi := Vector2i(int(delta[i].x), int(delta[i].y))
			_client_revealed[vi] = true
		fog_reveal_delta.emit(delta)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		if delta.size() >= FOG_DELTA_PACK_THRESHOLD:
			rpc_fog_reveal_delta_packed.rpc_id(peer_id, DungeonFog.pack_fog_delta_cells(delta))
		else:
			rpc_fog_reveal_delta.rpc_id(peer_id, delta)


func _notify_client_player_sync(peer_id: int, cell: Vector2i) -> void:
	var role_s := str(_peer_roles.get(peer_id, "rogue"))
	var burn := _torch_burn_value(peer_id)
	if _using_solo_local() and peer_id == _solo_offline_peer:
		_client_spawn_cell = cell
		player_position_updated.emit(peer_id, cell, role_s, burn)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_player_position_sync.rpc(peer_id, cell.x, cell.y, role_s, burn)


func _notify_unlocked_doors_delta(cells: PackedVector2Array) -> void:
	if _using_solo_local():
		for i in range(cells.size()):
			var vi := Vector2i(int(cells[i].x), int(cells[i].y))
			_client_unlocked_doors[vi] = true
		unlocked_doors_delta.emit(cells)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_unlocked_doors_delta.rpc(cells)


func _notify_unpickable_doors_delta(cells: PackedVector2Array) -> void:
	if _using_solo_local():
		for i in range(cells.size()):
			var vi2 := Vector2i(int(cells[i].x), int(cells[i].y))
			_client_unpickable_doors[vi2] = true
		unpickable_doors_delta.emit(cells)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_unpickable_doors_delta.rpc(cells)


func _broadcast_unpickable_snapshot() -> void:
	var unpick_snap := PackedVector2Array()
	for k in _unpickable_doors:
		unpick_snap.append(Vector2(k))
	if _using_solo_local():
		_client_unpickable_doors.clear()
		for i in range(unpick_snap.size()):
			_client_unpickable_doors[Vector2i(int(unpick_snap[i].x), int(unpick_snap[i].y))] = true
		unpickable_doors_snapshot.emit(unpick_snap)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_unpickable_doors_snapshot.rpc(unpick_snap)


func _notify_trap_inspected_doors_delta(cells: PackedVector2Array) -> void:
	if _using_solo_local():
		for i in range(cells.size()):
			var vit := Vector2i(int(cells[i].x), int(cells[i].y))
			_client_trap_inspected_doors[vit] = true
		trap_inspected_doors_delta.emit(cells)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_trap_inspected_doors_delta.rpc(cells)


func _notify_trap_inspected_doors_remove_delta(cells: PackedVector2Array) -> void:
	if _using_solo_local():
		for i in range(cells.size()):
			var vit := Vector2i(int(cells[i].x), int(cells[i].y))
			_client_trap_inspected_doors.erase(vit)
		trap_inspected_doors_remove_delta.emit(cells)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_trap_inspected_doors_remove_delta.rpc(cells)


func _notify_trap_defused_doors_delta(cells: PackedVector2Array) -> void:
	if _using_solo_local():
		for i in range(cells.size()):
			var vd := Vector2i(int(cells[i].x), int(cells[i].y))
			_client_trap_defused[vd] = true
		trap_defused_doors_delta.emit(cells)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_trap_defused_doors_delta.rpc(cells)


func _authority_effective_tile(cell: Vector2i) -> String:
	return GridWalk.tile_effective(_authority_grid, cell, _trap_defused_doors)


func _deliver_door_prompt_to_peer(
	peer_id: int, action: String, cell: Vector2i, message: String
) -> void:
	if _using_solo_local() and peer_id == _solo_offline_peer:
		door_prompt_offered.emit(action, cell, message)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_door_prompt.rpc_id(peer_id, action, cell.x, cell.y, message)


func _deliver_world_interaction_to_peer(
	peer_id: int, kind: String, cell: Vector2i, title: String, message: String
) -> void:
	if _using_solo_local() and peer_id == _solo_offline_peer:
		world_interaction_offered.emit(kind, cell, title, message)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_world_interaction_offer.rpc_id(peer_id, kind, cell.x, cell.y, title, message)


## After `configure_authority`, seeds one local player and emits `authority_dungeon_synchronized` (no ENet).
func begin_solo_local_session(join_role: String, solo_display_name: String = "") -> void:
	_solo_cached_display_name = JoinMetadata.display_name_for_solo(solo_display_name)
	_solo_offline_peer = SOLO_LOCAL_PEER_ID
	_peer_party_slots[_solo_offline_peer] = 0
	_server_gold[_solo_offline_peer] = 0
	_server_xp[_solo_offline_peer] = 0
	_server_player_alignment[_solo_offline_peer] = PlayerAlignment.starting_alignment()
	_server_npcs_killed_by_peer[_solo_offline_peer] = 0
	var norm := _normalize_join_role(join_role)
	_peer_roles[_solo_offline_peer] = norm
	var solo_st: Dictionary = PlayerCombatStats.for_role(norm)
	_server_player_max_hp[_solo_offline_peer] = int(
		solo_st.get("max_hit_points", PlayerCombatStats.BASE_MAX_HIT_POINTS)
	)
	_server_player_hp[_solo_offline_peer] = int(
		solo_st.get("hit_points", PlayerCombatStats.BASE_PLAYER_HIT_POINTS)
	)
	_server_talent_bonuses_by_peer[_solo_offline_peer] = PlayerTalents.default_talents().duplicate(
		true
	)
	_server_level_hp_total_by_peer[_solo_offline_peer] = 0
	_server_recompute_max_hp_store(_solo_offline_peer)
	var occupied_now: Array = []
	for p in _player_positions.values():
		occupied_now.append(p)
	var spawn: Vector2i = GridWalk.find_spawn_cell(_authority_grid, occupied_now)
	_player_positions[_solo_offline_peer] = spawn
	_init_peer_torch(_solo_offline_peer)

	var theme_norm := _authority_theme
	if theme_norm != "up" and theme_norm != "down":
		theme_norm = "up"
	# IMPORTANT: In solo-local mode, the authority grid is already in memory.
	# Do not attempt to re-generate the grid from seed/theme_name; RNG consumption differs
	# (random theme selection advances RNG before generation), which can cause checksum mismatch.
	var grid: Dictionary = _authority_grid
	var theme_d: Dictionary = {}
	if not _authority_theme_name.strip_edges().is_empty():
		DungeonThemes.load_themes()
		theme_d = DungeonThemes.find_theme_by_name(_authority_theme_name.strip_edges())
		if theme_d.is_empty():
			var msg0 := "solo unknown theme_name: " + _authority_theme_name
			push_error("[Dungeoneers] " + msg0)
			_solo_offline_peer = -1
			_player_positions.clear()
			_revealed_by_peer.clear()
			_peer_roles.erase(SOLO_LOCAL_PEER_ID)
			authority_dungeon_failed.emit(msg0)
			return

	if _fog_enabled:
		_seed_initial_fog_for_peer(_solo_offline_peer, spawn)
	else:
		_revealed_by_peer.erase(_solo_offline_peer)

	var fr := clampi(_fog_radius, 0, 8)
	var ft := DungeonFog.normalize_fog_type(_fog_type)
	var welcome := {
		"schema_version": WELCOME_SCHEMA_VERSION,
		"assigned_slot": 0,
		"role": norm,
		"player_id": _solo_offline_peer,
		"spawn_x": spawn.x,
		"spawn_y": spawn.y,
		"fog_enabled": _fog_enabled,
		"fog_radius": fr,
		"fog_type": ft,
		"torch_reveals_moves": _torch_reveals_moves,
		"floor_theme": str(theme_d.get("floor_theme", "")),
		"wall_theme": str(theme_d.get("wall_theme", "")),
		"theme_name": _authority_theme_name,
		"dungeon_level": _dungeon_level,
		"authority_player_level": _player_level,
		"generation_type": str(theme_d.get("generation_type", _generation_type)),
		"rooms": _authority_rooms.duplicate() if _authority_rooms is Array else [],
		"corridors": _authority_corridors.duplicate() if _authority_corridors is Array else [],
		"road_theme": str(theme_d.get("road_theme", "")),
		"shrub_theme": str(theme_d.get("shrub_theme", "")),
		"display_name": _solo_cached_display_name,
		"peer_display_names": {_solo_offline_peer: _solo_cached_display_name},
		"listen_port": 0,
		"server_boot_unix_sec": 0,
		"party_peer_count": 1,
	}
	_dng_print(
		(
			"Solo local session spawn="
			+ str(spawn)
			+ " fog_type="
			+ ft
			+ " fog_radius="
			+ str(fr)
			+ " torch_reveals="
			+ str(_torch_reveals_moves)
		)
	)
	authority_dungeon_synchronized.emit(_authority_seed, theme_norm, grid, welcome)
	guards_hostile_changed.emit(_authority_guards_hostile)
	player_position_updated.emit(
		_solo_offline_peer, spawn, norm, _torch_burn_value(_solo_offline_peer)
	)
	_authority_recompute_player_level_from_party_xp()
	var th0 := _torch_hud_burn_and_spares_for_peer(_solo_offline_peer)
	var sx0 := int(_server_xp.get(_solo_offline_peer, 0))
	var sl0 := PlayerProgression.calculate_level(sx0)
	var sn0 := PlayerProgression.xp_needed_for_next_level(sx0)
	var pot0 := int(_server_healing_potions_by_peer.get(_solo_offline_peer, 0))
	var sl0b: Dictionary = _server_stat_line_for_combat(_solo_offline_peer)
	player_local_stats_changed.emit(
		int(_server_gold.get(_solo_offline_peer, 0)),
		sx0,
		int(
			_server_player_hp.get(
				_solo_offline_peer, PlayerCombatStats.starting_hit_points_for_role(norm)
			)
		),
		int(
			_server_player_max_hp.get(
				_solo_offline_peer, PlayerCombatStats.max_hit_points_for_role(norm)
			)
		),
		th0.x,
		th0.y,
		sl0,
		sn0,
		int(_server_player_alignment.get(_solo_offline_peer, PlayerAlignment.starting_alignment())),
		int(_server_npcs_killed_by_peer.get(_solo_offline_peer, 0)),
		pot0,
		int(sl0b.get("armor_class", PlayerCombatStats.BASE_ARMOR_CLASS)),
		int(sl0b.get("attack_bonus", PlayerCombatStats.BASE_ATTACK_BONUS)),
		str(sl0b.get("player_weapon", "")).strip_edges(),
		str(sl0b.get("weapon_damage_dice", "")).strip_edges()
	)
	_server_broadcast_special_items_to_peer(_solo_offline_peer)
	_server_broadcast_quests_to_peer(_solo_offline_peer)
	_server_broadcast_achievements_to_peer(_solo_offline_peer)


func attach_server_handlers() -> void:
	if not multiplayer.peer_connected.is_connected(_on_server_peer_connected):
		multiplayer.peer_connected.connect(_on_server_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_server_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_server_peer_disconnected)


func client_submit_join_request(requested_role: String, display_name: String = "") -> void:
	if _using_solo_local():
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_client_join_request.rpc_id(SERVER_PEER_ID, requested_role, display_name)


func client_request_move(target_x: int, target_y: int) -> void:
	if _using_solo_local():
		_server_handle_request_move(_solo_offline_peer, Vector2i(target_x, target_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_move.rpc_id(SERVER_PEER_ID, target_x, target_y)


func client_request_path_move(path: PackedVector2Array) -> void:
	if _using_solo_local():
		if not path.is_empty():
			_server_handle_path_move(_solo_offline_peer, path)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	if path.is_empty():
		return
	rpc_request_path_move.rpc_id(SERVER_PEER_ID, path)


func client_request_fog_square_click(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_fog_square_click(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_fog_square_click.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_unlock_door(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_unlock_door(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_unlock_door.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_door_click(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_door_click(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_door_click.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_door_confirm(action: String, cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_door_confirm(_solo_offline_peer, action, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_door_confirm.rpc_id(SERVER_PEER_ID, action, cell_x, cell_y)


func client_request_world_interaction(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_world_interaction(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_world_interaction.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_map_transition_confirm(kind: String, cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_map_transition_confirm(_solo_offline_peer, kind, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_map_transition_confirm.rpc_id(SERVER_PEER_ID, kind, cell_x, cell_y)


func client_request_treasure_dismiss(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_treasure_dismiss(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_treasure_dismiss.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_pickup_dismiss(kind: String, cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_pickup_dismiss(_solo_offline_peer, kind, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_pickup_dismiss.rpc_id(SERVER_PEER_ID, kind, cell_x, cell_y)


func client_request_use_healing_potion() -> void:
	if _using_solo_local():
		_server_handle_use_healing_potion(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_use_healing_potion.rpc_id(SERVER_PEER_ID)


func client_request_room_trap_undetected_ack(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_room_trap_undetected_ack(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_room_trap_undetected_ack.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_room_trap_skip_disarm(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_room_trap_skip_disarm(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_room_trap_skip_disarm.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_room_trap_disarm(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_room_trap_disarm(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_room_trap_disarm.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_rumor_dismiss() -> void:
	if _using_solo_local():
		_server_handle_rumor_dismiss(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_rumor_dismiss.rpc_id(SERVER_PEER_ID)


func client_request_special_item_dismiss() -> void:
	if _using_solo_local():
		_server_handle_special_item_dismiss(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_special_item_dismiss.rpc_id(SERVER_PEER_ID)


func client_request_encounter_fight(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_encounter_fight(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_encounter_fight.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_encounter_evade(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_encounter_evade(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_encounter_evade.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_npc_quest_accept() -> void:
	if _using_solo_local():
		_server_handle_npc_quest_accept(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_npc_quest_accept.rpc_id(SERVER_PEER_ID)


func client_request_npc_quest_decline() -> void:
	if _using_solo_local():
		_server_handle_npc_quest_decline(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_npc_quest_decline.rpc_id(SERVER_PEER_ID)


func client_request_combat_player_attack() -> void:
	if _using_solo_local():
		_server_handle_combat_player_attack(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_combat_player_attack.rpc_id(SERVER_PEER_ID)


func client_request_combat_flee() -> void:
	if _using_solo_local():
		_server_handle_combat_flee(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_combat_flee.rpc_id(SERVER_PEER_ID)


func client_request_level_up_dismiss() -> void:
	if _using_solo_local():
		_server_handle_client_level_up_dismiss(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_level_up_dismiss.rpc_id(SERVER_PEER_ID)


func is_solo_local_session() -> bool:
	return _using_solo_local()


func client_request_revival() -> void:
	if _using_solo_local():
		_server_handle_revival_request(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_revival.rpc_id(SERVER_PEER_ID)


## Explorer `death_new_game` / `generate_new` — solo only (full regen + fresh stats).
func solo_local_request_new_game() -> void:
	if not _using_solo_local():
		return
	var role := str(_peer_roles.get(_solo_offline_peer, "rogue"))
	var dn := str(_solo_cached_display_name)
	var fog_e := _fog_enabled
	var fog_r := _fog_radius
	var fog_t := _fog_type
	var torch_rm := _torch_reveals_moves
	var theme_norm := _authority_theme
	if theme_norm != "up" and theme_norm != "down":
		theme_norm = "up"
	var new_seed := randi()
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	var result: Dictionary = TraditionalGen.generate(rng, theme_norm)
	var grid: Dictionary = result["grid"] as Dictionary
	var checksum := TraditionalGen.grid_checksum(grid)
	var theme_disp := str(result.get("theme", "")).strip_edges()
	if theme_disp.is_empty():
		theme_disp = "Ancient Castle" if theme_norm == "up" else "Dark Caverns"
	var gen_meta := {
		"theme_name": theme_disp,
		"dungeon_level": 1,
		"player_level": 1,
		"generation_type": str(result.get("generation_type", "dungeon")),
		"rooms": result.get("rooms", []),
		"corridors": result.get("corridors", []),
		"fog_type": str(result.get("fog_type", "")),
	}
	configure_authority(
		new_seed, theme_norm, checksum, role, grid, fog_e, fog_r, fog_t, torch_rm, gen_meta
	)
	begin_solo_local_session(role, dn)
	print("[Dungeoneers] solo_local_request_new_game seed=", new_seed)


func _notify_authority_tile_patch(cell: Vector2i, new_tile: String) -> void:
	authority_tile_patched.emit(cell, new_tile)
	if not _using_solo_local() and multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_server_authority_tile_patches[cell] = new_tile
	if _using_solo_local():
		return
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		_server_queue_live_authority_tile_patch_rpc(cell, new_tile)


func _server_queue_live_authority_tile_patch_rpc(cell: Vector2i, new_tile: String) -> void:
	_live_tile_patch_rpc_pending[cell] = new_tile
	if _live_tile_patch_rpc_flush_queued:
		return
	_live_tile_patch_rpc_flush_queued = true
	call_deferred("_flush_live_authority_tile_patch_rpc_queue")


func _flush_live_authority_tile_patch_rpc_queue() -> void:
	_live_tile_patch_rpc_flush_queued = false
	if _using_solo_local() or multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		_live_tile_patch_rpc_pending.clear()
		return
	if _live_tile_patch_rpc_pending.is_empty():
		return
	var pending: Dictionary = _live_tile_patch_rpc_pending.duplicate(true)
	_live_tile_patch_rpc_pending.clear()
	var packed: PackedByteArray = GridTilePatchCodec.pack_sorted_patches(pending)
	if packed.is_empty():
		var nfb := 0
		for cell_fb in pending:
			var ntfb: String = str(pending[cell_fb])
			rpc_authority_tile_patch.rpc(cell_fb.x, cell_fb.y, ntfb)
			nfb += 1
		print("[Dungeoneers] live_tile_patch_rpc_fallback count=", nfb)
		return
	if _debug_net:
		print(
			"[Dungeoneers] net_debug tile_patch_batch_live patches=",
			pending.size(),
			" packed_bytes=",
			packed.size()
		)
	rpc_authority_tile_patch_batch.rpc(packed)


## Late join replays logical tile overrides. **P7-14 / P7-15:** one `rpc_authority_tile_patch_batch` with a packed blob
## (`GridTilePatchCodec`) replaces **N** per-cell `rpc_authority_tile_patch` calls (same tile strings, fewer envelopes).
## **Before / after (fixed probe):** three short-string patches encode to **44 bytes** in `res://tools/check_grid_tile_patch_codec.gd`
## vs **N** separate RPCs previously. Use **`--debug-net`** on server/client to print `packed_bytes=` for real sessions.
func _replay_authority_tile_patches_to_peer(peer_id: int) -> void:
	if _using_solo_local():
		return
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	if _server_authority_tile_patches.is_empty():
		return
	var packed: PackedByteArray = GridTilePatchCodec.pack_sorted_patches(
		_server_authority_tile_patches
	)
	if packed.is_empty():
		var nfb := 0
		for cell_fb in _server_authority_tile_patches:
			var ntfb: String = str(_server_authority_tile_patches[cell_fb])
			rpc_authority_tile_patch.rpc_id(peer_id, cell_fb.x, cell_fb.y, ntfb)
			nfb += 1
		print("[Dungeoneers] late_join_replay_patches_fallback peer_id=", peer_id, " count=", nfb)
		return
	if _debug_net:
		print(
			"[Dungeoneers] net_debug tile_patch_batch peer_id=",
			peer_id,
			" patches=",
			_server_authority_tile_patches.size(),
			" packed_bytes=",
			packed.size()
		)
	rpc_authority_tile_patch_batch.rpc_id(peer_id, packed)
	print(
		"[Dungeoneers] late_join_replay_patches peer_id=",
		peer_id,
		" count=",
		_server_authority_tile_patches.size(),
		" packed_batch=1"
	)


func _torch_hud_burn_and_spares_for_peer(peer_id: int) -> Vector2i:
	if not _fog_enabled:
		return Vector2i(-1, -1)
	if _torch_daylight():
		return Vector2i(TORCH_BURN_FULL, -1)
	var burn := _torch_burn_value(peer_id)
	var spare := maxi(0, int(_torch_count_by_peer.get(peer_id, 1)) - 1)
	return Vector2i(burn, spare)


func _server_award_exploration_xp_for_disk_new(peer_id: int, disk_new: int) -> void:
	if disk_new <= 0:
		return
	if not _fog_enabled:
		return
	if _torch_daylight():
		return
	var add: int = disk_new * (1 + _dungeon_level)
	_server_add_xp_with_level_up(peer_id, add)
	print(
		"[Dungeoneers] exploration_xp peer_id=", peer_id, " new_disk_cells=", disk_new, " xp+=", add
	)


## Co-op monster/theme scaling: **max** Explorer `calculate_level` among peers with a position on this map.
## No-op if `_player_positions` is empty (e.g. join-role RPC before spawn is reserved).
func _authority_recompute_player_level_from_party_xp() -> void:
	if _player_positions.is_empty():
		return
	var mx := 1
	for pid in _player_positions.keys():
		var xpv := int(_server_xp.get(int(pid), 0))
		mx = maxi(mx, PlayerProgression.calculate_level(xpv))
	_player_level = mx


func _emit_stats_for_peer(peer_id: int) -> void:
	_authority_recompute_player_level_from_party_xp()
	var g := int(_server_gold.get(peer_id, 0))
	var xp := int(_server_xp.get(peer_id, 0))
	var plv := PlayerProgression.calculate_level(xp)
	var xnext := PlayerProgression.xp_needed_for_next_level(xp)
	var r_for_stats := str(_peer_roles.get(peer_id, "rogue"))
	var hp := int(
		_server_player_hp.get(peer_id, PlayerCombatStats.starting_hit_points_for_role(r_for_stats))
	)
	var mx := int(
		_server_player_max_hp.get(peer_id, PlayerCombatStats.max_hit_points_for_role(r_for_stats))
	)
	var torch_h := _torch_hud_burn_and_spares_for_peer(peer_id)
	var pal := int(_server_player_alignment.get(peer_id, PlayerAlignment.starting_alignment()))
	var nk := int(_server_npcs_killed_by_peer.get(peer_id, 0))
	var pot := int(_server_healing_potions_by_peer.get(peer_id, 0))
	var sl_emit: Dictionary = _server_stat_line_for_combat(peer_id)
	var ac_e := int(sl_emit.get("armor_class", PlayerCombatStats.BASE_ARMOR_CLASS))
	var ab_e := int(sl_emit.get("attack_bonus", PlayerCombatStats.BASE_ATTACK_BONUS))
	var wn_e := str(sl_emit.get("player_weapon", "")).strip_edges()
	var wd_e := str(sl_emit.get("weapon_damage_dice", "")).strip_edges()
	if _using_solo_local() and peer_id == _solo_offline_peer:
		player_local_stats_changed.emit(
			g, xp, hp, mx, torch_h.x, torch_h.y, plv, xnext, pal, nk, pot, ac_e, ab_e, wn_e, wd_e
		)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		## Listen host: `call_remote` RPCs do not run on the sender — mirror `level_up_dialog_offered` local emit.
		if peer_id == multiplayer.get_unique_id():
			player_local_stats_changed.emit(
				g,
				xp,
				hp,
				mx,
				torch_h.x,
				torch_h.y,
				plv,
				xnext,
				pal,
				nk,
				pot,
				ac_e,
				ab_e,
				wn_e,
				wd_e
			)
		else:
			rpc_player_local_stats.rpc_id(
				peer_id,
				g,
				xp,
				hp,
				mx,
				torch_h.x,
				torch_h.y,
				plv,
				xnext,
				pal,
				nk,
				pot,
				ac_e,
				ab_e,
				wn_e,
				wd_e
			)


func _server_peer_talents_dict(peer_id: int) -> Dictionary:
	var v: Variant = _server_talent_bonuses_by_peer.get(peer_id, null)
	if v is Dictionary:
		return (v as Dictionary).duplicate(true)
	var d: Dictionary = PlayerTalents.default_talents().duplicate(true)
	_server_talent_bonuses_by_peer[peer_id] = d.duplicate(true)
	return d.duplicate(true)


func _server_set_peer_talents(peer_id: int, d: Dictionary) -> void:
	_server_talent_bonuses_by_peer[peer_id] = d.duplicate(true)


func _server_stat_line_for_combat(peer_id: int) -> Dictionary:
	var role := str(_peer_roles.get(peer_id, "rogue"))
	var t := _server_peer_talents_dict(peer_id)
	var lh: int = int(_server_level_hp_total_by_peer.get(peer_id, 0))
	var pst: Dictionary = (
		PlayerCombatStats
		. for_role_with_progression(
			role,
			lh,
			int(t.get("hit_points", 0)),
			int(t.get("attack", 0)),
			int(t.get("dexterity", 0)),
		)
	)
	var base_line := {
		"max_hit_points": int(pst.get("max_hit_points", PlayerCombatStats.BASE_MAX_HIT_POINTS)),
		"armor_class": int(pst.get("armor_class", PlayerCombatStats.BASE_ARMOR_CLASS)),
		"attack_bonus": int(pst.get("attack_bonus", PlayerCombatStats.BASE_ATTACK_BONUS)),
		"player_weapon": str(pst.get("player_weapon", "")).strip_edges(),
		"weapon_damage_dice": str(pst.get("weapon_damage_dice", "")).strip_edges(),
	}
	var keys_ar: Array = _server_special_items_by_peer.get(peer_id, []) as Array
	return SpecialItemTable.merge_equipment_into_stat_line(base_line, keys_ar)


func _server_recompute_max_hp_store(peer_id: int) -> void:
	var sl := _server_stat_line_for_combat(peer_id)
	_server_player_max_hp[peer_id] = int(
		sl.get("max_hit_points", PlayerCombatStats.BASE_MAX_HIT_POINTS)
	)


func _server_add_xp_with_level_up(peer_id: int, delta: int) -> void:
	if delta == 0:
		return
	var old_xp: int = int(_server_xp.get(peer_id, 0))
	var new_xp: int = old_xp + delta
	_server_xp[peer_id] = new_xp
	if PlayerProgression.leveled_up(old_xp, new_xp):
		_server_apply_one_level_up(peer_id, new_xp)


func _server_apply_one_level_up(peer_id: int, new_xp: int) -> void:
	var nl: int = PlayerProgression.calculate_level(new_xp)
	var lh_gain: int = PlayerTalents.roll_level_hit_points_deterministic(
		_authority_seed, peer_id, nl
	)
	var roll: Dictionary = PlayerTalents.roll_random_talent_deterministic(
		_authority_seed, peer_id, nl
	)
	var talents: Dictionary = _server_peer_talents_dict(peer_id)
	talents = PlayerTalents.apply_talent_roll_to_dict(talents, roll)
	_server_set_peer_talents(peer_id, talents)
	var prev_lh: int = int(_server_level_hp_total_by_peer.get(peer_id, 0))
	_server_level_hp_total_by_peer[peer_id] = prev_lh + lh_gain
	_server_recompute_max_hp_store(peer_id)
	var cap: int = int(_server_player_max_hp.get(peer_id, 1))
	var cur_hp: int = int(_server_player_hp.get(peer_id, cap))
	var total_hp_gain: int = lh_gain
	if int(roll.get("branch", 0)) == 1:
		total_hp_gain += int(roll.get("bonus", 0))
	cur_hp = mini(cur_hp + total_hp_gain, cap)
	_server_player_hp[peer_id] = cur_hp
	var primary: String = PlayerTalents.level_up_primary_message(nl, lh_gain)
	var second: String = PlayerTalents.format_talent_secondary_message(roll, lh_gain)
	var ach_line: String = PlayerTalents.achievement_text_for_level_up(nl, lh_gain, second)
	if not _server_level_up_queue_by_peer.has(peer_id):
		_server_level_up_queue_by_peer[peer_id] = []
	var q: Array = _server_level_up_queue_by_peer[peer_id] as Array
	(
		q
		. append(
			{
				"new_level": nl,
				"level_hp_gain": lh_gain,
				"primary": primary,
				"secondary": second,
				"achievement": ach_line,
			}
		)
	)
	_server_try_deliver_level_up(peer_id)


func _server_try_deliver_level_up(peer_id: int) -> void:
	if bool(_server_level_up_waiting.get(peer_id, false)):
		return
	var qv: Variant = _server_level_up_queue_by_peer.get(peer_id, null)
	if qv == null or not qv is Array:
		return
	var q: Array = qv as Array
	if q.is_empty():
		return
	var entry: Dictionary = q[0] as Dictionary
	_server_level_up_waiting[peer_id] = true
	var nl: int = int(entry.get("new_level", 1))
	var p1: String = str(entry.get("primary", ""))
	var p2: String = str(entry.get("secondary", ""))
	_server_deliver_level_up_dialog(peer_id, nl, p1, p2)


func _server_deliver_level_up_dialog(peer_id: int, nl: int, p1: String, p2: String) -> void:
	if _using_solo_local() and peer_id == _solo_offline_peer:
		level_up_dialog_offered.emit(nl, p1, p2)
		return
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		if peer_id == multiplayer.get_unique_id():
			level_up_dialog_offered.emit(nl, p1, p2)
		else:
			rpc_level_up_dialog.rpc_id(peer_id, nl, p1, p2)


func _server_handle_revival_request(sender: int) -> void:
	if not _player_positions.has(sender):
		return
	var role_r := str(_peer_roles.get(sender, "rogue"))
	_server_recompute_max_hp_store(sender)
	var mx_hp := int(
		_server_player_max_hp.get(sender, PlayerCombatStats.max_hit_points_for_role(role_r))
	)
	_server_player_hp[sender] = mx_hp
	_server_gold[sender] = 0
	_emit_stats_for_peer(sender)
	print("[Dungeoneers] revival_request peer_id=", sender)


func _server_handle_client_level_up_dismiss(sender: int) -> void:
	if not bool(_server_level_up_waiting.get(sender, false)):
		return
	var qv2: Variant = _server_level_up_queue_by_peer.get(sender, null)
	if qv2 == null or not qv2 is Array:
		return
	var q2: Array = qv2 as Array
	if q2.is_empty():
		_server_level_up_waiting.erase(sender)
		return
	var done: Dictionary = q2.pop_front() as Dictionary
	_server_level_up_waiting[sender] = false
	var ach: String = str(done.get("achievement", "")).strip_edges()
	if not ach.is_empty():
		_server_peer_achievements_array(sender).append(ach)
		_server_broadcast_achievements_to_peer(sender)
	_server_try_deliver_level_up(sender)


func _server_handle_treasure_dismiss(sender: int, cell: Vector2i) -> void:
	if not _player_positions.has(sender):
		return
	var rt: String = GridWalk.tile_at(_authority_grid, cell)
	if rt == "trapped_treasure":
		print("[Dungeoneers] treasure_dismiss rejected: still trapped cell=", cell)
		return
	if rt != "treasure":
		print("[Dungeoneers] treasure_dismiss rejected: tile=", rt, " peer_id=", sender)
		return
	var revealed: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, revealed, true):
		print("[Dungeoneers] treasure_dismiss rejected: fog peer_id=", sender)
		return
	var g: int = TreasureSys.gold_for_treasure_cell(_authority_seed, cell)
	_server_gold[sender] = int(_server_gold.get(sender, 0)) + g
	_server_add_xp_with_level_up(sender, g)
	var new_t: String = TreasureSys.underlying_tile_after_collect(cell, _authority_rooms)
	_authority_grid[cell] = new_t
	_notify_authority_tile_patch(cell, new_t)
	_emit_stats_for_peer(sender)
	print(
		"[Dungeoneers] treasure_dismiss peer_id=",
		sender,
		" cell=",
		cell,
		" gold+xp=",
		g,
		" tile=",
		new_t
	)
	var rng_si := _rng_door_cell(sender, cell, 501)
	if rng_si.randi_range(1, 100) <= SPECIAL_ITEM_CHANCE_ON_TREASURE:
		_server_offer_special_item_discovery(sender, cell, SPECIAL_ITEM_PICK_SALT_TREASURE)


func _pickup_kind_for_raw_tile(raw: String) -> String:
	if raw == "bread" or raw == "cheese" or raw == "grapes":
		return "food_pickup"
	if raw == "healing_potion":
		return "healing_potion_pickup"
	if raw == "torch":
		return "torch_pickup"
	if raw.begins_with("quest_item|"):
		return "quest_item_pickup"
	return ""


func _pickup_offer_payload(peer_id: int, cell: Vector2i, raw_tile: String) -> Dictionary:
	var kind := _pickup_kind_for_raw_tile(raw_tile)
	if kind.is_empty():
		return {}
	var role_p := str(_peer_roles.get(peer_id, "rogue"))
	var hp0 := int(
		_server_player_hp.get(peer_id, PlayerCombatStats.starting_hit_points_for_role(role_p))
	)
	var mx0 := int(
		_server_player_max_hp.get(peer_id, PlayerCombatStats.max_hit_points_for_role(role_p))
	)
	if kind == "food_pickup":
		var fr: Dictionary = ConsumablePickup.food_roll_and_actual(_authority_seed, cell, hp0, mx0)
		return {
			"kind": kind,
			"title": "Food Found!",
			"message":
			ConsumablePickup.food_message(raw_tile, int(fr["roll"]), int(fr["actual"]), hp0, mx0),
		}
	if kind == "healing_potion_pickup":
		ConsumablePickup.potion_roll_and_actual(_authority_seed, cell, hp0, mx0)
		return {
			"kind": kind,
			"title": "Healing Potion Found!",
			"message": ConsumablePickup.potion_message(),
		}
	if kind == "torch_pickup":
		return {
			"kind": kind,
			"title": "Torch Found!",
			"message": "You found a torch! It has been added to your inventory.",
		}
	if kind == "quest_item_pickup":
		var qid0: String = PlayerQuests.parse_quest_id_from_tile(raw_tile)
		var qd0: Dictionary = PlayerQuests.find_quest_by_id(
			_server_peer_quests_array(peer_id), qid0
		)
		if qd0.is_empty() or str(qd0.get("status", "")) != "active":
			return {}
		return {
			"kind": kind,
			"title": "Quest Completed!",
			"message": PlayerQuests.completion_dialog_body(qd0, _dungeon_level),
		}
	push_warning("[Dungeoneers] _pickup_offer_payload unknown kind=", kind)
	return {}


func _server_maybe_post_move_pickup(peer_id: int, dst: Vector2i) -> bool:
	if _server_combat_by_peer.has(peer_id):
		return false
	if not _player_positions.has(peer_id):
		return false
	var raw_d: String = GridWalk.tile_at(_authority_grid, dst)
	var pk := _pickup_kind_for_raw_tile(raw_d)
	if pk.is_empty():
		return false
	var rev_p: Dictionary = _revealed_for_peer(peer_id)
	if _fog_enabled and not DungeonFog.square_revealed(dst, rev_p, true):
		return false
	var pack_m: Dictionary = _pickup_offer_payload(peer_id, dst, raw_d)
	if pack_m.is_empty():
		return false
	_deliver_world_interaction_to_peer(
		peer_id,
		str(pack_m["kind"]),
		dst,
		str(pack_m["title"]),
		str(pack_m["message"]),
	)
	print(
		"[Dungeoneers] post_move_pickup peer_id=", peer_id, " kind=", pack_m["kind"], " cell=", dst
	)
	return true


## Explorer `Movement.process_special_feature` on non-pathfinding step — once per cell per map.
func _server_maybe_post_move_special_feature(
	peer_id: int, dst: Vector2i, allow_prompt: bool
) -> bool:
	if not allow_prompt:
		return false
	if _server_combat_by_peer.has(peer_id):
		return false
	if not _player_positions.has(peer_id):
		return false
	if _player_positions[peer_id] != dst:
		return false
	var raw_sf: String = GridWalk.tile_at(_authority_grid, dst)
	if not raw_sf.begins_with("special_feature|"):
		return false
	var rev_sf: Dictionary = _revealed_for_peer(peer_id)
	if _fog_enabled and not DungeonFog.square_revealed(dst, rev_sf, true):
		return false
	var dk := _server_investigated_feature_key(dst)
	var subp: Variant = _server_feature_discovery_prompted.get(peer_id, null)
	if subp is Dictionary and (subp as Dictionary).get(dk, false) == true:
		return false
	var eff_sf: String = _authority_effective_tile(dst)
	var pack_sf: Dictionary = _world_interaction_payload("special_feature", raw_sf, eff_sf, dst)
	_deliver_world_interaction_to_peer(
		peer_id,
		"special_feature",
		dst,
		str(pack_sf["title"]),
		str(pack_sf["message"]),
	)
	var subn: Dictionary = {}
	if subp is Dictionary:
		subn = (subp as Dictionary).duplicate()
	subn[dk] = true
	_server_feature_discovery_prompted[peer_id] = subn
	print("[Dungeoneers] post_move_special_feature peer_id=", peer_id, " cell=", dst)
	return true


## Explorer `Movement` stair / waypoint / map_link dialogs when stepping onto the tile (non-pathfinding).
func _server_maybe_post_move_stand_navigation(
	peer_id: int, dst: Vector2i, allow_prompt: bool
) -> void:
	if not allow_prompt:
		return
	if _server_combat_by_peer.has(peer_id):
		return
	if not _player_positions.has(peer_id):
		return
	if _player_positions[peer_id] != dst:
		return
	var raw_nav: String = GridWalk.tile_at(_authority_grid, dst)
	var nav_kind := GridWalk.world_interaction_stand_kind(raw_nav)
	if nav_kind != "stair" and nav_kind != "waypoint" and nav_kind != "map_link":
		return
	if nav_kind == "waypoint" and raw_nav.begins_with("starting_waypoint|"):
		return
	var rev_nav: Dictionary = _revealed_for_peer(peer_id)
	if _fog_enabled and not DungeonFog.square_revealed(dst, rev_nav, true):
		return
	var eff_nav: String = _authority_effective_tile(dst)
	var pack_nav: Dictionary = _world_interaction_payload(nav_kind, raw_nav, eff_nav, dst)
	_deliver_world_interaction_to_peer(
		peer_id,
		nav_kind,
		dst,
		str(pack_nav["title"]),
		str(pack_nav["message"]),
	)
	print(
		"[Dungeoneers] post_move_stand_navigation peer_id=",
		peer_id,
		" kind=",
		nav_kind,
		" cell=",
		dst,
	)


func _server_handle_use_healing_potion(sender: int) -> void:
	if not _player_positions.has(sender):
		return
	if _server_combat_by_peer.has(sender):
		return
	var cnt_h: int = int(_server_healing_potions_by_peer.get(sender, 0))
	if cnt_h <= 0:
		return
	var role_h := str(_peer_roles.get(sender, "rogue"))
	var hp_h := int(
		_server_player_hp.get(sender, PlayerCombatStats.starting_hit_points_for_role(role_h))
	)
	var mx_h := int(
		_server_player_max_hp.get(sender, PlayerCombatStats.max_hit_points_for_role(role_h))
	)
	if hp_h >= mx_h:
		return
	var rng_d := RandomNumberGenerator.new()
	rng_d.randomize()
	var heal_amt: int = rng_d.randi_range(1, 6)
	_server_player_hp[sender] = mini(mx_h, hp_h + heal_amt)
	_server_healing_potions_by_peer[sender] = cnt_h - 1
	_emit_stats_for_peer(sender)
	print(
		"[Dungeoneers] use_healing_potion peer_id=",
		sender,
		" heal=",
		heal_amt,
		" potions_left=",
		_server_healing_potions_by_peer.get(sender, 0)
	)


func _server_handle_pickup_dismiss(sender: int, kind: String, cell: Vector2i) -> void:
	if not _player_positions.has(sender):
		return
	if _player_positions[sender] != cell:
		print("[Dungeoneers] pickup_dismiss rejected: not on cell peer_id=", sender)
		return
	var raw_p: String = GridWalk.tile_at(_authority_grid, cell)
	if _pickup_kind_for_raw_tile(raw_p) != kind:
		print("[Dungeoneers] pickup_dismiss rejected: tile/kind mismatch ", raw_p, " ", kind)
		return
	var rev_d: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, rev_d, true):
		return
	var role_d := str(_peer_roles.get(sender, "rogue"))
	var hp_now := int(
		_server_player_hp.get(sender, PlayerCombatStats.starting_hit_points_for_role(role_d))
	)
	var mx_now := int(
		_server_player_max_hp.get(sender, PlayerCombatStats.max_hit_points_for_role(role_d))
	)
	match kind:
		"food_pickup":
			var fd: Dictionary = ConsumablePickup.food_roll_and_actual(
				_authority_seed, cell, hp_now, mx_now
			)
			var heal_f: int = int(fd["actual"])
			_server_player_hp[sender] = mini(mx_now, hp_now + heal_f)
			_authority_grid[cell] = "floor"
			_notify_authority_tile_patch(cell, "floor")
			_emit_stats_for_peer(sender)
			print("[Dungeoneers] food_pickup peer_id=", sender, " cell=", cell, " heal=", heal_f)
		"healing_potion_pickup":
			## Explorer `dismiss_healing_potion`: add to inventory, remove tile, XP — no heal until HUD drink.
			var prev_p: int = int(_server_healing_potions_by_peer.get(sender, 0))
			_server_healing_potions_by_peer[sender] = prev_p + 1
			_server_add_xp_with_level_up(sender, ConsumablePickup.HEALING_POTION_DISCOVERY_XP)
			var under_p: String = TreasureSys.underlying_tile_after_collect(cell, _authority_rooms)
			_authority_grid[cell] = under_p
			_notify_authority_tile_patch(cell, under_p)
			_emit_stats_for_peer(sender)
			print(
				"[Dungeoneers] healing_potion_pickup peer_id=",
				sender,
				" cell=",
				cell,
				" potions=",
				_server_healing_potions_by_peer.get(sender, 0)
			)
		"torch_pickup":
			var cnt_t := int(_torch_count_by_peer.get(sender, 1))
			var burn_t := _torch_burn_value(sender)
			if cnt_t <= 0 and burn_t <= 0:
				_torch_count_by_peer[sender] = 1
				_torch_burn_by_peer[sender] = TORCH_BURN_FULL
			else:
				_torch_count_by_peer[sender] = cnt_t + 1
				if burn_t < 2:
					_torch_burn_by_peer[sender] = TORCH_BURN_FULL
			_server_add_xp_with_level_up(sender, ConsumablePickup.TORCH_PICKUP_XP)
			var under_t: String = TreasureSys.underlying_tile_after_collect(cell, _authority_rooms)
			_authority_grid[cell] = under_t
			_notify_authority_tile_patch(cell, under_t)
			_emit_stats_for_peer(sender)
			print(
				"[Dungeoneers] torch_pickup peer_id=",
				sender,
				" cell=",
				cell,
				" torches=",
				_torch_count_by_peer.get(sender, 1)
			)
		"quest_item_pickup":
			var qid_pick: String = PlayerQuests.parse_quest_id_from_tile(raw_p)
			var qd_pick: Dictionary = PlayerQuests.find_quest_by_id(
				_server_peer_quests_array(sender), qid_pick
			)
			if qd_pick.is_empty() or str(qd_pick.get("status", "")) != "active":
				print(
					"[Dungeoneers] pickup_dismiss rejected: quest_item no active quest peer_id=",
					sender,
					" cell=",
					cell
				)
				return
			## Explorer `QuestItemSystem.complete_quest_discovery`: XP + item only — no `player_gold`
			## for special-item quest completion (`reward_gold` on struct is not awarded on pickup).
			var xp_q: int = maxi(0, int(qd_pick.get("xp_reward", 0)))
			_server_add_xp_with_level_up(sender, xp_q)
			var item_key_q := str(qd_pick.get("magic_item_key", "")).strip_edges()
			if not item_key_q.is_empty():
				var keys_ar: Array = _server_special_items_by_peer.get(sender, []) as Array
				var already_q := false
				for kxq in keys_ar:
					if str(kxq) == item_key_q:
						already_q = true
						break
				if not already_q:
					keys_ar.append(item_key_q)
					_server_special_items_by_peer[sender] = keys_ar
					_server_broadcast_special_items_to_peer(sender)
			var q_snap: Dictionary = qd_pick.duplicate(true)
			PlayerQuests.mark_quest_completed_in_list(_server_peer_quests_array(sender), qid_pick)
			_server_append_quest_achievement(sender, q_snap)
			var rumors_old: Array = _server_rumors_by_peer.get(sender, []) as Array
			var rumors_new: Array = PlayerQuests.filter_rumors_after_special_quest_complete(
				rumors_old, qd_pick
			)
			_server_rumors_by_peer[sender] = rumors_new
			_server_broadcast_rumors_to_peer(sender)
			_server_broadcast_quests_to_peer(sender)
			print("[Dungeoneers] quest_item_pickup peer_id=", sender, " cell=", cell, " xp+=", xp_q)
			var under_q: String = TreasureSys.underlying_tile_after_collect(cell, _authority_rooms)
			_authority_grid[cell] = under_q
			_notify_authority_tile_patch(cell, under_q)
			_emit_stats_for_peer(sender)
		_:
			push_warning("[Dungeoneers] pickup_dismiss unknown kind=", kind)


func _server_convert_room_trap_to_floor(cell: Vector2i) -> void:
	if GridWalk.tile_at(_authority_grid, cell) != "room_trap":
		return
	_authority_grid[cell] = "floor"
	_notify_authority_tile_patch(cell, "floor")
	_room_trap_disarm_pending.erase(cell)


func _first_adjacent_room_trap_cell(player_cell: Vector2i, revealed: Dictionary) -> Vector2i:
	## Same neighbor order as Explorer `find_adjacent_room_traps/3`.
	var offs: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	for d: Vector2i in offs:
		var tc := player_cell + d
		if _fog_enabled and not DungeonFog.square_revealed(tc, revealed, true):
			continue
		if GridWalk.tile_at(_authority_grid, tc) == "room_trap":
			return tc
	return Vector2i(-1, -1)


## Explorer `Movement.process_room_traps` / tile trap tuple: dialogs that set `final_show_trap_dialog` and
## block `process_all_encounters` — **not** plain `treasure` (encounter can preempt treasure in `process_all_dialogs`).
func _server_post_move_trap_modals_blocking_encounter(peer_id: int, dst: Vector2i) -> Dictionary:
	var showed := false
	var blocks_enc := false
	if _server_combat_by_peer.has(peer_id) or not _player_positions.has(peer_id):
		return {"showed_modal": false, "blocks_adjacent_encounter": false}
	var raw_dst: String = GridWalk.tile_at(_authority_grid, dst)
	var revealed_m: Dictionary = _revealed_for_peer(peer_id)
	if raw_dst == "trapped_treasure":
		if (not _fog_enabled) or DungeonFog.square_revealed(dst, revealed_m, true):
			_server_handle_trapped_treasure_interaction(peer_id, dst)
			showed = true
			blocks_enc = true
		return {"showed_modal": showed, "blocks_adjacent_encounter": blocks_enc}
	if raw_dst == "room_trap":
		if (not _fog_enabled) or DungeonFog.square_revealed(dst, revealed_m, true):
			_server_handle_room_trap_interaction(peer_id, dst)
			showed = true
			blocks_enc = true
		return {"showed_modal": showed, "blocks_adjacent_encounter": blocks_enc}
	var trap_cell := _first_adjacent_room_trap_cell(dst, revealed_m)
	if trap_cell.x >= 0:
		_server_handle_room_trap_interaction(peer_id, trap_cell)
		showed = true
		blocks_enc = true
	return {"showed_modal": showed, "blocks_adjacent_encounter": blocks_enc}


func _server_maybe_post_move_plain_treasure_discovery(peer_id: int, dst: Vector2i) -> bool:
	if _server_combat_by_peer.has(peer_id) or not _player_positions.has(peer_id):
		return false
	var raw_dst: String = GridWalk.tile_at(_authority_grid, dst)
	if raw_dst != "treasure":
		return false
	var revealed_m: Dictionary = _revealed_for_peer(peer_id)
	if _fog_enabled and not DungeonFog.square_revealed(dst, revealed_m, true):
		return false
	var eff_tr: String = _authority_effective_tile(dst)
	var pack_tr: Dictionary = _world_interaction_payload("treasure", raw_dst, eff_tr, dst)
	_deliver_world_interaction_to_peer(
		peer_id, "treasure", dst, str(pack_tr["title"]), str(pack_tr["message"])
	)
	print("[Dungeoneers] post_move_treasure peer_id=", peer_id, " cell=", dst)
	return true


## Explorer `Movement.check_adjacent_encounters_at_position` + `evaluate_monster_for_adjacency` — king-adjacent
## untriggered encounter (NPC excluded; peaceful guards excluded). No fog check on the encounter cell (torch-out sensing).
func _server_first_adjacent_monster_encounter_cell(peer_id: int, player_cell: Vector2i) -> Vector2i:
	var offs: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	var p_al := int(_server_player_alignment.get(peer_id, PlayerAlignment.starting_alignment()))
	for d: Vector2i in offs:
		var c := player_cell + d
		var raw: String = GridWalk.tile_at(_authority_grid, c)
		if not raw.begins_with("encounter|"):
			continue
		var mname: String = _encounter_monster_name_from_tile(raw)
		var def: Dictionary = MonsterTable.lookup_monster(mname)
		var role: String = str(def.get("role", "")).strip_edges().to_lower()
		if role == "npc":
			continue
		if role == "guard":
			var m_align := str(def.get("alignment", "neutral")).strip_edges().to_lower()
			var hostile := PlayerAlignment.npc_hostile_to_player(m_align, p_al)
			if not _authority_guards_hostile and not hostile:
				continue
		return c
	return Vector2i(-1, -1)


func _server_maybe_post_move_adjacent_encounter(
	peer_id: int, player_cell: Vector2i, allow_prompt: bool
) -> bool:
	if not allow_prompt:
		return false
	if _server_combat_by_peer.has(peer_id):
		return false
	if not _player_positions.has(peer_id):
		return false
	if _player_positions[peer_id] != player_cell:
		return false
	var enc_cell := _server_first_adjacent_monster_encounter_cell(peer_id, player_cell)
	if enc_cell.x < 0:
		return false
	var eff: String = _authority_effective_tile(enc_cell)
	if not eff.begins_with("encounter|"):
		return false
	var eb: Dictionary = _world_interaction_encounter_branch(peer_id, enc_cell, eff)
	var send_kind: String = str(eb.get("kind", "encounter"))
	var pack_r := {"title": str(eb.get("title", "")), "message": str(eb.get("message", ""))}
	if send_kind == "npc_quest_offer":
		var qv: Variant = eb.get("quest", null)
		if qv is Dictionary:
			_server_pending_npc_quest[peer_id] = {
				"cell": enc_cell,
				"quest": (qv as Dictionary).duplicate(true),
			}
	_deliver_world_interaction_to_peer(
		peer_id, send_kind, enc_cell, str(pack_r["title"]), str(pack_r["message"])
	)
	print("[Dungeoneers] post_move_adjacent_encounter peer_id=", peer_id, " cell=", enc_cell)
	return true


func _roll_room_trap_detect(peer_id: int, cell: Vector2i) -> Dictionary:
	var rng := _rng_door_cell(peer_id, cell, 219)
	var d20: int = rng.randi_range(1, 20)
	return {"ok": d20 >= TREASURE_TRAP_DETECT_DC, "d20": d20}


func _roll_room_trap_disarm_attempt(peer_id: int, cell: Vector2i) -> Dictionary:
	## Explorer `TrapSystem.calculate_trap_damage(:room_trap)` → 1d4; failed disarm uses that damage.
	var rng := _rng_door_cell(peer_id, cell, 196)
	var d20: int = rng.randi_range(1, 20)
	var bonus: int = _dex_pick_bonus_for_peer(peer_id)
	var total: int = d20 + bonus
	var dmg: int = rng.randi_range(1, 4)
	return {"ok": total >= TRAP_DISARM_DC, "d20": d20, "bonus": bonus, "total": total, "dmg": dmg}


func _server_handle_room_trap_interaction(sender: int, cell: Vector2i) -> void:
	if GridWalk.tile_at(_authority_grid, cell) != "room_trap":
		return
	var rev: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, rev, true):
		return
	var det: Dictionary = _roll_room_trap_detect(sender, cell)
	var d20v: int = int(det["d20"])
	if bool(det["ok"]):
		_room_trap_disarm_pending[cell] = true
		var msg_ok := (
			"Your keen senses detect a hidden trap in this room!\n\n"
			+ "(Detected with roll "
			+ str(d20v)
			+ " vs DC "
			+ str(TREASURE_TRAP_DETECT_DC)
			+ ")\n\nAttempt to disarm (d20 + DEX vs DC "
			+ str(TRAP_DISARM_DC)
			+ "), or back away for now."
		)
		_deliver_world_interaction_to_peer(
			sender, "room_trap_detected", cell, "You've found a trap!", msg_ok
		)
	else:
		var msg_fail := (
			"You fail to spot the hazard in time (rolled "
			+ str(d20v)
			+ " vs DC "
			+ str(TREASURE_TRAP_DETECT_DC)
			+ ").\n\nThe mechanism lurches — brace yourself!\n\nPress Continue."
		)
		_deliver_world_interaction_to_peer(sender, "room_trap_undetected", cell, "Trap!", msg_fail)


func _server_handle_room_trap_undetected_ack(sender: int, cell: Vector2i) -> void:
	if GridWalk.tile_at(_authority_grid, cell) != "room_trap":
		print("[Dungeoneers] room_trap_undetected_ack rejected tile cell=", cell)
		return
	var rev_u: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, rev_u, true):
		return
	var rng_u := _rng_door_cell(sender, cell, 314)
	var dmg_u: int = rng_u.randi_range(1, 4)
	_server_convert_room_trap_to_floor(cell)
	var hp_u: int = _server_apply_hp_damage_to_peer(sender, dmg_u)
	print("[Dungeoneers] room_trap_undetected_ack peer_id=", sender, " dmg=", dmg_u, " hp=", hp_u)
	if hp_u <= 0:
		_deliver_encounter_resolution_to_peer(
			sender,
			"Death",
			"The mechanism crushes you — your adventure ends here.",
		)


func _server_handle_room_trap_skip_disarm(sender: int, cell: Vector2i) -> void:
	if not _room_trap_disarm_pending.has(cell):
		print("[Dungeoneers] room_trap_skip rejected not pending cell=", cell)
		return
	if GridWalk.tile_at(_authority_grid, cell) != "room_trap":
		_room_trap_disarm_pending.erase(cell)
		return
	_room_trap_disarm_pending.erase(cell)
	print("[Dungeoneers] room_trap_skip peer_id=", sender, " cell=", cell)


func _server_handle_room_trap_disarm(sender: int, cell: Vector2i) -> void:
	if not _room_trap_disarm_pending.has(cell):
		print("[Dungeoneers] room_trap_disarm rejected not pending cell=", cell)
		return
	if GridWalk.tile_at(_authority_grid, cell) != "room_trap":
		_room_trap_disarm_pending.erase(cell)
		return
	_room_trap_disarm_pending.erase(cell)
	var r_dis: Dictionary = _roll_room_trap_disarm_attempt(sender, cell)
	if bool(r_dis["ok"]):
		_server_add_xp_with_level_up(sender, TRAP_DISARM_XP_TREASURE)
		_server_convert_room_trap_to_floor(cell)
		_emit_stats_for_peer(sender)
		var d20_ok: int = int(r_dis["d20"])
		var bon_ok: int = int(r_dis["bonus"])
		var tot_ok: int = int(r_dis["total"])
		_deliver_encounter_resolution_to_peer(
			sender,
			"Trap disarmed",
			(
				"You successfully disarm the trap!\n(Rolled "
				+ str(d20_ok)
				+ " + "
				+ str(bon_ok)
				+ " DEX = "
				+ str(tot_ok)
				+ " vs DC "
				+ str(TRAP_DISARM_DC)
				+ ")\n\nThe hazard is neutralized (+"
				+ str(TRAP_DISARM_XP_TREASURE)
				+ " XP)."
			)
		)
		print("[Dungeoneers] room_trap_disarm_success peer_id=", sender, " cell=", cell)
	else:
		var dmg_f: int = int(r_dis["dmg"])
		_server_convert_room_trap_to_floor(cell)
		var hp_f: int = _server_apply_hp_damage_to_peer(sender, dmg_f)
		var d20_b: int = int(r_dis["d20"])
		var bon_b: int = int(r_dis["bonus"])
		var tot_b: int = int(r_dis["total"])
		_deliver_encounter_resolution_to_peer(
			sender,
			"Trap triggered",
			(
				"You fail to disarm the trap and trigger it!\n(Rolled "
				+ str(d20_b)
				+ " + "
				+ str(bon_b)
				+ " DEX = "
				+ str(tot_b)
				+ " vs DC "
				+ str(TRAP_DISARM_DC)
				+ ")\n\nYou take "
				+ str(dmg_f)
				+ " damage."
			)
		)
		if hp_f <= 0:
			_deliver_encounter_resolution_to_peer(
				sender, "Death", "The blades bite deep — you collapse."
			)
		print("[Dungeoneers] room_trap_disarm_fail peer_id=", sender, " dmg=", dmg_f, " hp=", hp_f)


func _server_handle_rumor_dismiss(sender: int) -> void:
	if not bool(_server_rumor_xp_pending.get(sender, false)):
		return
	_server_rumor_xp_pending.erase(sender)
	_server_add_xp_with_level_up(sender, RUMOR_XP)
	_emit_stats_for_peer(sender)
	print("[Dungeoneers] rumor_dismiss peer_id=", sender, " xp+=", RUMOR_XP)


func _encounter_monster_name_from_tile(effective_tile: String) -> String:
	var parts := effective_tile.split("|")
	return parts[2] if parts.size() > 2 else "monster"


func _server_encounter_cell_ok(sender: int, cell: Vector2i) -> bool:
	if not _player_positions.has(sender):
		print("[Dungeoneers] encounter rejected: unknown peer_id=", sender)
		return false
	var revealed: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, revealed, true):
		print("[Dungeoneers] encounter rejected: fog peer_id=", sender, " cell=", cell)
		return false
	var eff: String = _authority_effective_tile(cell)
	if GridWalk.world_interaction_remote_kind(eff) != "encounter":
		print(
			"[Dungeoneers] encounter rejected: not encounter tile peer_id=", sender, " cell=", cell
		)
		return false
	var pos_e: Vector2i = _player_positions[sender]
	if pos_e != cell and not GridWalk.is_king_adjacent(pos_e, cell):
		print(
			"[Dungeoneers] encounter rejected: not adjacent peer_id=",
			sender,
			" player=",
			pos_e,
			" cell=",
			cell,
		)
		return false
	return true


func _deliver_encounter_resolution_to_peer(peer_id: int, title: String, message: String) -> void:
	if _using_solo_local() and peer_id == _solo_offline_peer:
		encounter_resolution_dialog.emit(title, message)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_encounter_resolution.rpc_id(peer_id, title, message)


func _deliver_combat_snapshot_to_peer(peer_id: int, snapshot: Dictionary) -> void:
	_last_combat_snapshot = snapshot.duplicate(true)
	if _using_solo_local() and peer_id == _solo_offline_peer:
		combat_state_changed.emit(snapshot)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_combat_state.rpc_id(peer_id, snapshot)


func _server_apply_combat_outcome(sender: int, cell: Vector2i, outcome: Dictionary) -> void:
	if bool(outcome.get("flee_success", false)):
		var role_f := str(_peer_roles.get(sender, "rogue"))
		var mx_f: int = int(
			_server_player_max_hp.get(sender, PlayerCombatStats.max_hit_points_for_role(role_f))
		)
		var hp_f: int = clampi(int(outcome.get("player_hp_end", 0)), 0, mx_f)
		_server_player_hp[sender] = hp_f
		var xpf: int = maxi(0, int(outcome.get("xp_gain", 0)))
		_server_add_xp_with_level_up(sender, xpf)
		var eff_f: String = str(_authority_grid.get(cell, ""))
		if eff_f.begins_with("encounter|"):
			var repl_f: String = MonsterTurn.underlying_after_encounter_leaves(
				cell, _authority_rooms
			)
			_authority_grid[cell] = repl_f
			_notify_authority_tile_patch(cell, repl_f)
		_emit_stats_for_peer(sender)
		print("[Dungeoneers] combat_flee_success peer_id=", sender, " cell=", cell, " xp+=", xpf)
		return
	var victory: bool = bool(outcome.get("victory", false))
	var role_o := str(_peer_roles.get(sender, "rogue"))
	var mx_cap: int = int(
		_server_player_max_hp.get(sender, PlayerCombatStats.max_hit_points_for_role(role_o))
	)
	var hp_end: int = clampi(int(outcome.get("player_hp_end", 0)), 0, mx_cap)
	var tile_rep: String = str(outcome.get("tile_replacement", ""))
	_server_player_hp[sender] = hp_end
	if victory:
		var mname_kill := str(outcome.get("monster_name_key", "")).strip_edges()
		if mname_kill.is_empty():
			var eff_kill: String = _authority_effective_tile(cell)
			if eff_kill.begins_with("encounter|"):
				mname_kill = _encounter_monster_name_from_tile(eff_kill)
		if not mname_kill.is_empty():
			var def_kill: Dictionary = MonsterTable.lookup_monster(mname_kill)
			var fx: Dictionary = PlayerAlignment.npc_or_guard_kill_replication_effects(
				str(def_kill.get("role", "")),
				str(def_kill.get("alignment", "neutral")),
				_authority_guards_hostile
			)
			var d_al: int = int(fx.get("alignment_delta", 0))
			if d_al != 0:
				var cur_al := int(
					_server_player_alignment.get(sender, PlayerAlignment.starting_alignment())
				)
				_server_player_alignment[sender] = cur_al + d_al
			if bool(fx.get("trigger_guards_hostile", false)):
				if not _authority_guards_hostile:
					_authority_guards_hostile = true
					print(
						"[Dungeoneers] guards_hostile=true reason=peaceful_npc_or_guard_kill peer_id=",
						sender,
						" monster=",
						mname_kill
					)
					_broadcast_guards_hostile()
			if bool(fx.get("increments_npcs_killed", false)):
				var prev_nk := int(_server_npcs_killed_by_peer.get(sender, 0))
				_server_npcs_killed_by_peer[sender] = prev_nk + 1
		var tg: int = maxi(0, int(outcome.get("treasure_gold", 0)))
		var xpg: int = maxi(0, int(outcome.get("xp_gain", 0)))
		_server_gold[sender] = int(_server_gold.get(sender, 0)) + tg
		_server_add_xp_with_level_up(sender, xpg)
		if not mname_kill.is_empty():
			var q_done: Dictionary = PlayerQuests.find_active_kill_quest_for_victory(
				_server_peer_quests_array(sender), mname_kill, _authority_theme_name
			)
			if not q_done.is_empty():
				var qid_done := str(q_done.get("id", "")).strip_edges()
				var rg_done: int = maxi(0, int(q_done.get("reward_gold", 0)))
				var xp_done: int = maxi(0, int(q_done.get("xp_reward", rg_done)))
				_server_gold[sender] = int(_server_gold.get(sender, 0)) + rg_done
				_server_add_xp_with_level_up(sender, xp_done)
				var dqk: int = PlayerQuests.kill_quest_alignment_delta(q_done)
				if dqk != 0:
					var cur_aq := int(
						_server_player_alignment.get(sender, PlayerAlignment.starting_alignment())
					)
					_server_player_alignment[sender] = cur_aq + dqk
				var q_snap_kill: Dictionary = q_done.duplicate(true)
				PlayerQuests.mark_quest_completed_in_list(
					_server_peer_quests_array(sender), qid_done
				)
				_server_append_quest_achievement(sender, q_snap_kill)
				var arr_rm: Array = _server_rumors_by_peer.get(sender, []) as Array
				_server_rumors_by_peer[sender] = PlayerQuests.filter_rumors_kill_quest_exact(
					arr_rm, q_done
				)
				_server_broadcast_rumors_to_peer(sender)
				_server_broadcast_quests_to_peer(sender)
				var append_q: String = PlayerQuests.kill_quest_completion_append_body(
					q_done, mname_kill, _authority_theme_name
				)
				outcome["body"] = str(outcome.get("body", "")) + "\n\n" + append_q
		if tile_rep == "pile_of_bones":
			_authority_grid[cell] = "pile_of_bones"
			_notify_authority_tile_patch(cell, "pile_of_bones")
	elif tile_rep == "restore_floor":
		var in_room: bool = DungeonGrid.point_in_any_room(cell, _authority_rooms)
		var repl: String = "floor" if in_room else "corridor"
		_authority_grid[cell] = repl
		_notify_authority_tile_patch(cell, repl)
	_emit_stats_for_peer(sender)
	print(
		"[Dungeoneers] encounter_fight_resolved peer_id=",
		sender,
		" cell=",
		cell,
		" victory=",
		victory,
		" player_hp=",
		hp_end
	)


func _server_cancel_combat_monster_strike_timer(peer_id: int) -> void:
	_combat_monster_strike_serial_by_peer[peer_id] = (
		int(_combat_monster_strike_serial_by_peer.get(peer_id, 0)) + 1
	)


func _server_apply_finished_combat_to_snapshot(snap: Dictionary, outcome: Dictionary) -> void:
	snap["finished"] = true
	snap["victory"] = bool(outcome.get("victory", false))
	snap["flee_success"] = bool(outcome.get("flee_success", false))
	snap["victory_treasure_gold"] = maxi(0, int(outcome.get("treasure_gold", 0)))
	snap["outcome_title"] = str(outcome.get("title", "Combat"))
	snap["outcome_body"] = str(outcome.get("body", ""))
	snap["log_full"] = str(outcome.get("body", ""))


func _server_schedule_pending_monster_strike(peer_id: int) -> void:
	if not _using_solo_local() and not multiplayer.is_server():
		return
	var session_chk: Variant = _server_combat_by_peer.get(peer_id)
	if session_chk == null:
		return
	if not session_chk.monster_turn_pending():
		return
	_server_cancel_combat_monster_strike_timer(peer_id)
	var serial := int(_combat_monster_strike_serial_by_peer.get(peer_id, 0))
	var delay_timer := get_tree().create_timer(COMBAT_MONSTER_STRIKE_DELAY_SEC, false, false, true)
	delay_timer.timeout.connect(
		func() -> void: _server_fire_pending_monster_strike(peer_id, serial), CONNECT_ONE_SHOT
	)


func _server_fire_pending_monster_strike(peer_id: int, serial: int) -> void:
	if not is_instance_valid(self):
		return
	if not _using_solo_local() and not multiplayer.is_server():
		return
	if int(_combat_monster_strike_serial_by_peer.get(peer_id, 0)) != serial:
		return
	var session: Variant = _server_combat_by_peer.get(peer_id)
	if session == null:
		return
	if not session.monster_turn_pending():
		return
	var combat_cell: Vector2i = session.cell
	var snap: Dictionary = session.advance_monster_turn()
	snap["cell_x"] = combat_cell.x
	snap["cell_y"] = combat_cell.y
	if session.finished:
		var outcome: Dictionary = session.build_finish_outcome()
		_server_combat_by_peer.erase(peer_id)
		_server_apply_combat_outcome(peer_id, combat_cell, outcome)
		_server_apply_finished_combat_to_snapshot(snap, outcome)
		_deliver_combat_snapshot_to_peer(peer_id, snap)
		return
	_deliver_combat_snapshot_to_peer(peer_id, snap)
	if session.monster_turn_pending():
		_server_schedule_pending_monster_strike(peer_id)


func _server_handle_encounter_fight(sender: int, cell: Vector2i) -> void:
	_server_cancel_pending_monster_combat_delay_for_peer(sender)
	_server_pending_npc_quest.erase(sender)
	if not _server_encounter_cell_ok(sender, cell):
		return
	var eff: String = _authority_effective_tile(cell)
	var mname: String = _encounter_monster_name_from_tile(eff)
	var role_c := str(_peer_roles.get(sender, "rogue"))
	var start_hp: int = int(
		_server_player_hp.get(sender, PlayerCombatStats.starting_hit_points_for_role(role_c))
	)
	_server_cancel_combat_monster_strike_timer(sender)
	var session := CombatResolver.create_interactive_combat(
		_authority_seed, cell, mname, start_hp, role_c, _server_stat_line_for_combat(sender)
	)
	_server_combat_by_peer[sender] = session
	var snap: Dictionary = session._snapshot()
	snap["cell_x"] = cell.x
	snap["cell_y"] = cell.y
	_deliver_combat_snapshot_to_peer(sender, snap)
	if session.monster_turn_pending():
		_server_schedule_pending_monster_strike(sender)


func _server_handle_combat_player_attack(sender: int) -> void:
	var session: Variant = _server_combat_by_peer.get(sender)
	if session == null:
		return
	var cell: Vector2i = session.cell
	var snap: Dictionary = session.advance_player_attack()
	snap["cell_x"] = cell.x
	snap["cell_y"] = cell.y
	if session.finished:
		_server_cancel_combat_monster_strike_timer(sender)
		var outcome: Dictionary = session.build_finish_outcome()
		_server_combat_by_peer.erase(sender)
		_server_apply_combat_outcome(sender, cell, outcome)
		_server_apply_finished_combat_to_snapshot(snap, outcome)
		_deliver_combat_snapshot_to_peer(sender, snap)
		return
	if session.monster_turn_pending():
		_deliver_combat_snapshot_to_peer(sender, snap)
		_server_schedule_pending_monster_strike(sender)
		return
	_deliver_combat_snapshot_to_peer(sender, snap)


func _server_handle_combat_flee(sender: int) -> void:
	var session_f: Variant = _server_combat_by_peer.get(sender)
	if session_f == null:
		return
	var cell_f: Vector2i = session_f.cell
	var snap_f: Dictionary = session_f.advance_flee()
	snap_f["cell_x"] = cell_f.x
	snap_f["cell_y"] = cell_f.y
	if session_f.finished:
		_server_cancel_combat_monster_strike_timer(sender)
		var outcome_f: Dictionary = session_f.build_finish_outcome()
		_server_combat_by_peer.erase(sender)
		_server_apply_combat_outcome(sender, cell_f, outcome_f)
		_server_apply_finished_combat_to_snapshot(snap_f, outcome_f)
	_deliver_combat_snapshot_to_peer(sender, snap_f)
	if not session_f.finished and session_f.monster_turn_pending():
		_server_schedule_pending_monster_strike(sender)


func _server_handle_encounter_evade(sender: int, cell: Vector2i) -> void:
	_server_pending_npc_quest.erase(sender)
	if not _server_encounter_cell_ok(sender, cell):
		return
	var role: String = str(_peer_roles.get(sender, "rogue"))
	var r: Dictionary = EncounterSys.roll_evade(_authority_seed, cell, role)
	var d20: int = int(r["d20"])
	var bonus: int = int(r["bonus"])
	var total: int = int(r["total"])
	var ok: bool = bool(r["success"])
	var evade_msg: String = EncounterSys.format_evade_message(d20, bonus, total, ok)
	if ok:
		_server_add_xp_with_level_up(sender, EncounterSys.EVADE_XP)
		_emit_stats_for_peer(sender)
		print(
			"[Dungeoneers] encounter_evade_success peer_id=",
			sender,
			" cell=",
			cell,
			" xp+=",
			EncounterSys.EVADE_XP
		)
		_deliver_encounter_resolution_to_peer(sender, "Evade", evade_msg)
		return
	print("[Dungeoneers] encounter_evade_failed peer_id=", sender, " cell=", cell)
	_deliver_encounter_resolution_to_peer(sender, "Evade failed", evade_msg)


func _server_handle_npc_quest_accept(sender: int) -> void:
	var pend: Variant = _server_pending_npc_quest.get(sender, null)
	if pend == null or not pend is Dictionary:
		return
	var pd: Dictionary = pend as Dictionary
	var q: Variant = pd.get("quest", null)
	var cvar: Variant = pd.get("cell", null)
	if not q is Dictionary or not cvar is Vector2i:
		_server_pending_npc_quest.erase(sender)
		return
	var quest: Dictionary = (q as Dictionary).duplicate(true)
	var cell_p: Vector2i = cvar as Vector2i
	_server_pending_npc_quest.erase(sender)
	if not _player_positions.has(sender):
		return
	var pos_accept: Vector2i = _player_positions[sender] as Vector2i
	## Match `GridWalk.should_remote_world_interaction_click` for `"encounter"` (king-adjacent)
	## plus same-cell (NPC/guard encounter tiles can be walkable).
	if pos_accept != cell_p and not GridWalk.is_king_adjacent(pos_accept, cell_p):
		print(
			"[Dungeoneers] npc_quest_accept rejected: not adjacent to offer cell peer_id=", sender
		)
		return
	var eff_p: String = _authority_effective_tile(cell_p)
	if GridWalk.world_interaction_remote_kind(eff_p) != "encounter":
		print("[Dungeoneers] npc_quest_accept rejected: no encounter peer_id=", sender)
		return
	_server_peer_quests_array(sender).append(quest)
	var rum_line: String = PlayerQuests.kill_quest_rumor_line(quest)
	var arr_u: Array = _server_rumors_by_peer.get(sender, []) as Array
	var nar: Array = []
	nar.append(rum_line)
	for x in arr_u:
		nar.append(str(x))
	_server_rumors_by_peer[sender] = nar
	_server_broadcast_rumors_to_peer(sender)
	_server_broadcast_quests_to_peer(sender)
	_server_try_spawn_kill_quest_encounters_for_peer(sender)
	_deliver_encounter_resolution_to_peer(
		sender,
		"Quest accepted",
		"The quest is recorded in your Rumors list. Seek your mark when you reach the right lands.",
	)
	print("[Dungeoneers] npc_quest_accept peer_id=", sender, " quest_id=", quest.get("id", ""))


func _server_handle_npc_quest_decline(sender: int) -> void:
	if _server_pending_npc_quest.erase(sender):
		_deliver_encounter_resolution_to_peer(sender, "Declined", "You decline the quest offer.")


## Headless client: manual fog reveal (Explorer `process_square_reveal`); requires fog on (see `--smoke-fog-reveal-probe`).
func run_headless_fog_reveal_smoke_probe() -> void:
	if multiplayer.is_server():
		return
	if not _fog_enabled:
		print("[Dungeoneers] fog_reveal_probe skipped (--no-fog)")
		return
	await get_tree().process_frame
	var spawn := _client_spawn_cell
	var fr: int = clampi(_fog_radius, 0, 8)
	var pick: Vector2i = Vector2i(-1, -1)
	for y in range(DungeonGrid.MAP_HEIGHT):
		for x in range(DungeonGrid.MAP_WIDTH):
			var c := Vector2i(x, y)
			if _client_revealed.get(c, false):
				continue
			if not DungeonFog.can_reveal_fog_click_cell(c, _client_revealed, true, spawn, fr):
				continue
			pick = c
			break
		if pick.x >= 0:
			break
	if pick.x < 0:
		print("[Dungeoneers] fog_reveal_probe skipped (no unrevealed cell in click range)")
		return
	var before: int = _client_revealed.size()
	client_request_fog_square_click(pick.x, pick.y)
	for _i in range(8):
		await get_tree().process_frame
	var after: int = _client_revealed.size()
	if after <= before:
		push_error(
			"[Dungeoneers] fog_reveal_probe failed: revealed count did not grow (before=",
			before,
			" after=",
			after,
			")"
		)
	else:
		print("[Dungeoneers] fog_reveal_probe ok cell=", pick, " revealed+", str(after - before))


## Headless client: after welcome, try an illegal move then one legal orthogonal step (see `--smoke-move-probe`).
func run_headless_move_smoke_probe() -> void:
	if multiplayer.is_server():
		return
	var cur := _client_spawn_cell
	var grid := _authority_grid_ref_for_client()
	client_request_move(-3, -3)
	await get_tree().process_frame
	client_request_move(cur.x + 2, cur.y)
	await get_tree().process_frame
	var dest := _first_orthogonal_walkable(cur, grid)
	if dest != cur:
		client_request_move(dest.x, dest.y)
	await get_tree().process_frame


## Headless: server arms torch to 1% + one torch; one orthogonal move triggers expire + fog reset (see `--smoke-torch-expire-probe`).
func run_headless_torch_expire_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var cur := _client_spawn_cell
	var grid := _authority_grid_ref_for_client()
	var dest := _first_orthogonal_walkable(cur, grid)
	if dest == cur:
		push_error("[Dungeoneers] smoke_torch_expire_probe failed: no orthogonal walkable step")
		return
	client_request_move(dest.x, dest.y)
	for _f in range(24):
		await get_tree().process_frame


## Headless: if a locked door is orthogonally adjacent to spawn, try walk (fail), unlock, walk (ok).
func run_headless_door_unlock_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid := _authority_grid_ref_for_client()
	var spawn := _client_spawn_cell
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]
	for d: Vector2i in dirs:
		var t: Vector2i = spawn + d
		var tile: String = GridWalk.tile_at(grid, t)
		if GridWalk.is_locked_door_tile(tile):
			var door_cell: Vector2i = t
			var probe_state: Array = ["live"]
			var on_prompt := func(offered_action: String, cell: Vector2i, _msg: String) -> void:
				if probe_state[0] != "live" or cell != door_cell:
					return
				if offered_action == "trap_detected":
					client_request_door_confirm("trap_disarm", cell.x, cell.y)
				elif offered_action == "trap_disarm_result":
					client_request_door_confirm("trap_disarm_ack", cell.x, cell.y)
				elif offered_action == "trap_sprung":
					client_request_door_confirm("trap_sprung_ack", cell.x, cell.y)
				elif offered_action == "unlock":
					client_request_door_confirm("unlock", cell.x, cell.y)
					probe_state[0] = "done"
			door_prompt_offered.connect(on_prompt)
			client_request_move(door_cell.x, door_cell.y)
			await get_tree().process_frame
			client_request_door_click(door_cell.x, door_cell.y)
			await get_tree().process_frame
			await get_tree().process_frame
			await get_tree().process_frame
			client_request_move(door_cell.x, door_cell.y)
			await get_tree().process_frame
			return
	print("[Dungeoneers] door_unlock_probe skipped (no adjacent locked door from spawn)")


## Headless helper: walkable king-neighbor of [target] reachable from [spawn] (Explorer encounter click).
func _headless_first_reachable_king_neighbor(
	grid: Dictionary, spawn: Vector2i, target: Vector2i
) -> Vector2i:
	var offs: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	for d: Vector2i in offs:
		var s: Vector2i = target + d
		var t_eff: String = GridWalk.tile_effective(grid, s, _client_trap_defused)
		if not GridWalk.is_walkable_for_pathfinding_at(
			t_eff, s, _client_unlocked_doors, _client_guards_hostile
		):
			continue
		var pth := GridPath.find_path_4dir(
			grid,
			spawn,
			s,
			_client_revealed,
			_fog_enabled,
			_client_unlocked_doors,
			_client_trap_defused,
			_client_guards_hostile
		)
		if not pth.is_empty():
			return s
	return Vector2i(-1, -1)


## Headless: path beside encounter, then `world_interaction` (Explorer adjacent encounter click).
func run_headless_world_interaction_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid_wi: Dictionary = _authority_grid_ref_for_client()
	var spawn_wi: Vector2i = _client_spawn_cell
	for y in range(DungeonGrid.MAP_HEIGHT):
		for x in range(DungeonGrid.MAP_WIDTH):
			var enc := Vector2i(x, y)
			var raw_enc: String = GridWalk.tile_at(grid_wi, enc)
			if GridWalk.world_interaction_remote_kind(raw_enc) != "encounter":
				continue
			var stand_wi: Vector2i = _headless_first_reachable_king_neighbor(grid_wi, spawn_wi, enc)
			if stand_wi.x < 0:
				continue
			if stand_wi != spawn_wi:
				var path_wi := GridPath.find_path_4dir(
					grid_wi,
					spawn_wi,
					stand_wi,
					_client_revealed,
					_fog_enabled,
					_client_unlocked_doors,
					_client_trap_defused,
					_client_guards_hostile
				)
				if path_wi.is_empty():
					continue
				client_request_path_move(path_wi)
				for _pw in range(36):
					await get_tree().process_frame
			client_request_world_interaction(enc.x, enc.y)
			for _i in range(12):
				await get_tree().process_frame
			return
	print("[Dungeoneers] world_interaction_probe skipped (no encounter tile on grid)")


## Headless: path onto first `treasure` cell, then dismiss (Explorer step-to-loot).
func run_headless_treasure_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid_tr: Dictionary = _authority_grid_ref_for_client()
	var spawn_tr: Vector2i = _client_spawn_cell
	for y in range(DungeonGrid.MAP_HEIGHT):
		for x in range(DungeonGrid.MAP_WIDTH):
			var c := Vector2i(x, y)
			var raw: String = GridWalk.tile_at(grid_tr, c)
			if raw != "treasure":
				continue
			var path_tr := GridPath.find_path_4dir(
				grid_tr,
				spawn_tr,
				c,
				_client_revealed,
				_fog_enabled,
				_client_unlocked_doors,
				_client_trap_defused,
				_client_guards_hostile
			)
			if path_tr.is_empty():
				continue
			client_request_path_move(path_tr)
			for _i in range(36):
				await get_tree().process_frame
			client_request_treasure_dismiss(c.x, c.y)
			for _j in range(12):
				await get_tree().process_frame
			return
	print("[Dungeoneers] treasure_probe skipped (no plain treasure tile on grid)")


## Headless: after another client changed the map, verify first `treasure` scan cell is not still `treasure` (late-join patch replay).
func run_headless_late_join_tile_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	if _client_merged_grid.is_empty():
		print("[Dungeoneers] late_join_tile_probe skipped (empty merged grid)")
		return
	var grid_pr := _authority_grid_ref_for_client()
	var first_tr := Vector2i(-1, -1)
	for y_pr in range(DungeonGrid.MAP_HEIGHT):
		for x_pr in range(DungeonGrid.MAP_WIDTH):
			var c_pr := Vector2i(x_pr, y_pr)
			if GridWalk.tile_at(grid_pr, c_pr) == "treasure":
				first_tr = c_pr
				break
		if first_tr.x >= 0:
			break
	if first_tr.x < 0:
		print("[Dungeoneers] late_join_tile_probe skipped (no treasure in pristine scan)")
		return
	var merged_tile := str(_client_merged_grid.get(first_tr, ""))
	if merged_tile.is_empty():
		merged_tile = GridWalk.tile_at(grid_pr, first_tr)
	if merged_tile == "treasure":
		push_error(
			"[Dungeoneers] late_join_tile_probe failed: cell ",
			first_tr,
			" still treasure (patches not applied?)"
		)
		return
	print("[Dungeoneers] late_join_tile_probe ok cell=", first_tr, " tile=", merged_tile)


## Headless: path-move onto `torch` / food / `healing_potion`, then `pickup_dismiss` (Explorer consumable + torch tiles).
func run_headless_pickup_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid_pk: Dictionary = _authority_grid_ref_for_client()
	var spawn_pk: Vector2i = _client_spawn_cell
	var wants_pk: PackedStringArray = PackedStringArray(
		["torch", "bread", "cheese", "grapes", "healing_potion"]
	)
	for wi in range(wants_pk.size()):
		var want: String = String(wants_pk[wi])
		for y_pk in range(DungeonGrid.MAP_HEIGHT):
			for x_pk in range(DungeonGrid.MAP_WIDTH):
				var c_pk := Vector2i(x_pk, y_pk)
				if GridWalk.tile_at(grid_pk, c_pk) != want:
					continue
				var path_pk := GridPath.find_path_4dir(
					grid_pk,
					spawn_pk,
					c_pk,
					_client_revealed,
					_fog_enabled,
					_client_unlocked_doors,
					_client_trap_defused,
					_client_guards_hostile
				)
				if path_pk.is_empty():
					continue
				var last_pk: Vector2 = path_pk[path_pk.size() - 1]
				if Vector2i(int(last_pk.x), int(last_pk.y)) != c_pk:
					continue
				client_request_path_move(path_pk)
				for _pm in range(36):
					await get_tree().process_frame
				var kind_pk := _pickup_kind_for_raw_tile(want)
				client_request_pickup_dismiss(kind_pk, c_pk.x, c_pk.y)
				for _p2 in range(12):
					await get_tree().process_frame
				return
	print(
		"[Dungeoneers] pickup_probe skipped (no reachable torch/food/potion from spawn for this map)"
	)


## Headless: path onto first `trapped_treasure` cell, then resolve trap flow + loot (Explorer step-to-interact).
func run_headless_trapped_treasure_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid_tt: Dictionary = _authority_grid_ref_for_client()
	var pick_tt := Vector2i(-1, -1)
	for y_tt in range(DungeonGrid.MAP_HEIGHT):
		for x_tt in range(DungeonGrid.MAP_WIDTH):
			var c_tt := Vector2i(x_tt, y_tt)
			var raw_tt: String = GridWalk.tile_at(grid_tt, c_tt)
			if raw_tt == "trapped_treasure":
				pick_tt = c_tt
				break
		if pick_tt.x >= 0:
			break
	if pick_tt.x < 0:
		print("[Dungeoneers] trapped_treasure_probe skipped (no trapped_treasure tile on grid)")
		return
	var spawn_tt: Vector2i = _client_spawn_cell
	var path_tt := GridPath.find_path_4dir(
		grid_tt,
		spawn_tt,
		pick_tt,
		_client_revealed,
		_fog_enabled,
		_client_unlocked_doors,
		_client_trap_defused,
		_client_guards_hostile
	)
	if path_tt.is_empty():
		print(
			"[Dungeoneers] trapped_treasure_probe skipped (no path spawn=",
			spawn_tt,
			" to trapped_treasure=",
			pick_tt,
			")"
		)
		return
	var phase_tt: Array[String] = ["move"]

	var on_world_tt := func(kind: String, cell: Vector2i, _t: String, _m: String) -> void:
		if cell != pick_tt:
			return
		if phase_tt[0] == "move" and kind == "trapped_treasure_undetected":
			phase_tt[0] = "ack"
			client_request_trapped_treasure_undetected_ack(cell.x, cell.y)
		elif phase_tt[0] == "move" and kind == "trapped_treasure_detected":
			phase_tt[0] = "disarm"
			client_request_trapped_treasure_disarm(cell.x, cell.y)
		elif phase_tt[0] == "ack" and kind == "treasure":
			phase_tt[0] = "loot"
			client_request_treasure_dismiss(cell.x, cell.y)
		elif phase_tt[0] == "disarm" and kind == "treasure":
			phase_tt[0] = "loot"
			client_request_treasure_dismiss(cell.x, cell.y)

	world_interaction_offered.connect(on_world_tt)
	client_request_path_move(path_tt)
	for _f_tt in range(48):
		await get_tree().process_frame
	if world_interaction_offered.is_connected(on_world_tt):
		world_interaction_offered.disconnect(on_world_tt)


## Headless: path-move onto first `trapped_treasure` (requires walkable path from spawn; `--no-fog` recommended).
func run_headless_trap_move_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid_tm: Dictionary = _authority_grid_ref_for_client()
	var spawn_tm: Vector2i = _client_spawn_cell
	var target_tm := Vector2i(-1, -1)
	for y_tm in range(DungeonGrid.MAP_HEIGHT):
		for x_tm in range(DungeonGrid.MAP_WIDTH):
			var c_tm := Vector2i(x_tm, y_tm)
			if GridWalk.tile_at(grid_tm, c_tm) == "trapped_treasure":
				target_tm = c_tm
				break
		if target_tm.x >= 0:
			break
	if target_tm.x < 0:
		print("[Dungeoneers] trap_move_probe skipped (no trapped_treasure on grid)")
		print("[Dungeoneers] trap_move_probe finished phase=skipped_no_tile")
		return
	var path_tm := GridPath.find_path_4dir(
		grid_tm,
		spawn_tm,
		target_tm,
		_client_revealed,
		_fog_enabled,
		_client_unlocked_doors,
		_client_trap_defused,
		_client_guards_hostile
	)
	if path_tm.is_empty():
		print(
			"[Dungeoneers] trap_move_probe skipped (no path spawn=",
			spawn_tm,
			" to trapped_treasure=",
			target_tm,
			")"
		)
		print("[Dungeoneers] trap_move_probe finished phase=skipped_no_path")
		return
	var phase_tm: Array[String] = ["move"]
	var on_world_tm := func(kind: String, cell: Vector2i, _t: String, _m: String) -> void:
		if cell != target_tm:
			return
		if phase_tm[0] == "move" and kind == "trapped_treasure_undetected":
			phase_tm[0] = "ack"
			client_request_trapped_treasure_undetected_ack(cell.x, cell.y)
		elif phase_tm[0] == "move" and kind == "trapped_treasure_detected":
			phase_tm[0] = "disarm"
			client_request_trapped_treasure_disarm(cell.x, cell.y)
		elif phase_tm[0] == "ack" and kind == "treasure":
			phase_tm[0] = "loot"
			client_request_treasure_dismiss(cell.x, cell.y)
		elif phase_tm[0] == "disarm" and kind == "treasure":
			phase_tm[0] = "loot"
			client_request_treasure_dismiss(cell.x, cell.y)

	world_interaction_offered.connect(on_world_tm)
	client_request_path_move(path_tm)
	for _f_tm in range(48):
		await get_tree().process_frame
	if world_interaction_offered.is_connected(on_world_tm):
		world_interaction_offered.disconnect(on_world_tm)
	print("[Dungeoneers] trap_move_probe finished phase=", phase_tm[0])


## Headless: path-move to a cell orthogonally/diagonally adjacent to `room_trap` (Explorer adjacent skull detection).
func run_headless_room_trap_adjacent_move_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid_ra: Dictionary = _authority_grid_ref_for_client()
	var spawn_ra: Vector2i = _client_spawn_cell
	var offs_ra: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	var trap_cell_ra := Vector2i(-1, -1)
	var stand_ra := Vector2i(-1, -1)
	for y_ra in range(DungeonGrid.MAP_HEIGHT):
		for x_ra in range(DungeonGrid.MAP_WIDTH):
			var tc_ra := Vector2i(x_ra, y_ra)
			if GridWalk.tile_at(grid_ra, tc_ra) != "room_trap":
				continue
			for d_ra: Vector2i in offs_ra:
				var sc_ra: Vector2i = tc_ra + d_ra
				var t_eff: String = GridWalk.tile_effective(grid_ra, sc_ra, _client_trap_defused)
				if not GridWalk.is_walkable_for_pathfinding_at(
					t_eff, sc_ra, _client_unlocked_doors, _client_guards_hostile
				):
					continue
				var path_ra := GridPath.find_path_4dir(
					grid_ra,
					spawn_ra,
					sc_ra,
					_client_revealed,
					_fog_enabled,
					_client_unlocked_doors,
					_client_trap_defused,
					_client_guards_hostile
				)
				if not path_ra.is_empty():
					trap_cell_ra = tc_ra
					stand_ra = sc_ra
					break
			if trap_cell_ra.x >= 0:
				break
		if trap_cell_ra.x >= 0:
			break
	if trap_cell_ra.x < 0:
		print("[Dungeoneers] room_trap_adj_move_probe skipped (no reachable cell beside room_trap)")
		print("[Dungeoneers] room_trap_adj_move_probe finished phase=skipped_no_trap")
		return
	var phase_ra: Array[String] = ["move"]
	var on_world_ra := func(kind: String, cell: Vector2i, _t: String, _m: String) -> void:
		if cell != trap_cell_ra:
			return
		if phase_ra[0] == "move" and kind == "room_trap_undetected":
			phase_ra[0] = "ack"
			client_request_room_trap_undetected_ack(cell.x, cell.y)
		elif phase_ra[0] == "move" and kind == "room_trap_detected":
			phase_ra[0] = "disarm"
			client_request_room_trap_disarm(cell.x, cell.y)

	world_interaction_offered.connect(on_world_ra)
	client_request_path_move(
		GridPath.find_path_4dir(
			grid_ra,
			spawn_ra,
			stand_ra,
			_client_revealed,
			_fog_enabled,
			_client_unlocked_doors,
			_client_trap_defused,
			_client_guards_hostile
		)
	)
	for _f_ra in range(48):
		await get_tree().process_frame
	if world_interaction_offered.is_connected(on_world_ra):
		world_interaction_offered.disconnect(on_world_ra)
	print(
		"[Dungeoneers] room_trap_adj_move_probe finished phase=",
		phase_ra[0],
		" trap=",
		trap_cell_ra
	)


## Headless: `--no-fog`, first encounter cell → `encounter_evade` RPC (success or fail; server logs `encounter_evade_*`).
func run_headless_encounter_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid_ev: Dictionary = _authority_grid_ref_for_client()
	var spawn_ev: Vector2i = _client_spawn_cell
	for y in range(DungeonGrid.MAP_HEIGHT):
		for x in range(DungeonGrid.MAP_WIDTH):
			var c_ev := Vector2i(x, y)
			var raw_ev: String = GridWalk.tile_at(grid_ev, c_ev)
			if GridWalk.world_interaction_remote_kind(raw_ev) != "encounter":
				continue
			var stand_ev: Vector2i = _headless_first_reachable_king_neighbor(
				grid_ev, spawn_ev, c_ev
			)
			if stand_ev.x < 0:
				continue
			if stand_ev != spawn_ev:
				var path_ev := GridPath.find_path_4dir(
					grid_ev,
					spawn_ev,
					stand_ev,
					_client_revealed,
					_fog_enabled,
					_client_unlocked_doors,
					_client_trap_defused,
					_client_guards_hostile
				)
				if path_ev.is_empty():
					continue
				client_request_path_move(path_ev)
				for _pe in range(36):
					await get_tree().process_frame
			client_request_encounter_evade(c_ev.x, c_ev.y)
			for _i in range(12):
				await get_tree().process_frame
			return
	print("[Dungeoneers] encounter_probe skipped (no encounter tile on grid)")


## Headless: `--no-fog`, first encounter cell → interactive combat (Attack until finished).
func run_headless_combat_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid_cb: Dictionary = _authority_grid_ref_for_client()
	var spawn_cb: Vector2i = _client_spawn_cell
	for y in range(DungeonGrid.MAP_HEIGHT):
		for x in range(DungeonGrid.MAP_WIDTH):
			var c_cb := Vector2i(x, y)
			var raw_cb: String = GridWalk.tile_at(grid_cb, c_cb)
			if GridWalk.world_interaction_remote_kind(raw_cb) != "encounter":
				continue
			var stand_cb: Vector2i = _headless_first_reachable_king_neighbor(
				grid_cb, spawn_cb, c_cb
			)
			if stand_cb.x < 0:
				continue
			if stand_cb != spawn_cb:
				var path_cb := GridPath.find_path_4dir(
					grid_cb,
					spawn_cb,
					stand_cb,
					_client_revealed,
					_fog_enabled,
					_client_unlocked_doors,
					_client_trap_defused,
					_client_guards_hostile
				)
				if path_cb.is_empty():
					continue
				client_request_path_move(path_cb)
				for _pcb in range(36):
					await get_tree().process_frame
			client_request_encounter_fight(c_cb.x, c_cb.y)
			for _wait in range(8):
				await get_tree().process_frame
			var attacks := 0
			while attacks < 400:
				await get_tree().process_frame
				var snap: Dictionary = _last_combat_snapshot
				if bool(snap.get("finished", false)):
					return
				if bool(snap.get("can_attack", false)):
					client_request_combat_player_attack()
					attacks += 1
				elif bool(snap.get("monster_strike_pending", false)):
					pass
				elif snap.is_empty():
					pass
			push_error("[Dungeoneers] combat_probe timed out (no finished snapshot)")
			return
	print("[Dungeoneers] combat_probe skipped (no encounter tile on grid)")


## Headless: `--no-fog`, first label or special-feature cell → `world_interaction` (Phase 5.5).
func run_headless_labels_probe() -> void:
	if multiplayer.is_server():
		return
	await get_tree().process_frame
	var grid_lb: Dictionary = _authority_grid_ref_for_client()
	var spawn_lb: Vector2i = _client_spawn_cell
	## Explorer `clickable_label_tile?` excludes `area_label`. Labels: remote WI when spawn is not
	## king-adjacent to the label. Special features: path to an adjacent stand cell, then WI.
	var want_kinds_lb: Array[String] = [
		"room_label",
		"corridor_label",
		"special_feature",
		"building_label",
	]
	for want_lb in want_kinds_lb:
		for y in range(DungeonGrid.MAP_HEIGHT):
			for x in range(DungeonGrid.MAP_WIDTH):
				var c_lb := Vector2i(x, y)
				var raw_lb: String = GridWalk.tile_at(grid_lb, c_lb)
				if GridWalk.world_interaction_remote_kind(raw_lb) != want_lb:
					continue
				if want_lb == "special_feature":
					var stand_lb: Vector2i = _headless_first_reachable_king_neighbor(
						grid_lb, spawn_lb, c_lb
					)
					if stand_lb.x < 0:
						continue
					if stand_lb != spawn_lb:
						var path_lb := GridPath.find_path_4dir(
							grid_lb,
							spawn_lb,
							stand_lb,
							_client_revealed,
							_fog_enabled,
							_client_unlocked_doors,
							_client_trap_defused,
							_client_guards_hostile
						)
						if path_lb.is_empty():
							continue
						client_request_path_move(path_lb)
						for _plb in range(36):
							await get_tree().process_frame
					client_request_world_interaction(c_lb.x, c_lb.y)
					for _i in range(12):
						await get_tree().process_frame
					return
				if GridWalk.is_king_adjacent(spawn_lb, c_lb):
					continue
				client_request_world_interaction(c_lb.x, c_lb.y)
				for _i in range(12):
					await get_tree().process_frame
				return
	print("[Dungeoneers] labels_probe skipped (no label or special_feature tile on grid)")


func _first_orthogonal_walkable(from: Vector2i, grid: Dictionary) -> Vector2i:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]
	for d: Vector2i in dirs:
		var t: Vector2i = from + d
		var tile: String = GridWalk.tile_at(grid, t)
		if GridWalk.is_walkable_for_movement_at(
			tile, t, _client_unlocked_doors, _client_guards_hostile
		):
			return t
	return from


func _authority_grid_ref_for_client() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = _authority_seed
	if not _authority_theme_name.is_empty():
		var theme_d: Dictionary = DungeonThemes.find_theme_by_name(_authority_theme_name)
		if not theme_d.is_empty():
			var res_named: Dictionary = DungeonGenerator.generate_with_theme_data(
				rng, theme_d, _player_level, _dungeon_level
			)
			return res_named["grid"] as Dictionary
	var theme := _authority_theme
	if theme != "up" and theme != "down":
		theme = "up"
	var result: Dictionary = TraditionalGen.generate(rng, theme)
	return result["grid"] as Dictionary


@rpc("any_peer", "call_remote", "reliable")
func rpc_client_join_request(requested_role: String, display_name: String = "") -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	var norm := _normalize_join_role(requested_role)
	_peer_roles[sender] = norm
	var dn := JoinMetadata.display_name_for_network_peer(display_name, sender)
	_peer_display_names[sender] = dn
	var st_role: Dictionary = PlayerCombatStats.for_role(norm)
	_server_player_max_hp[sender] = int(
		st_role.get("max_hit_points", PlayerCombatStats.BASE_MAX_HIT_POINTS)
	)
	_server_player_hp[sender] = int(
		st_role.get("hit_points", PlayerCombatStats.BASE_PLAYER_HIT_POINTS)
	)
	_emit_stats_for_peer(sender)
	print("[Dungeoneers] join request peer_id=", sender, " role=", norm, " display_name=", dn)
	if multiplayer.multiplayer_peer != null:
		rpc_own_display_name.rpc_id(sender, dn)
	_server_broadcast_peer_display_names_snapshot()


@rpc("authority", "call_remote", "reliable")
func rpc_own_display_name(confirmed: String) -> void:
	if multiplayer.is_server():
		return
	player_display_name_changed.emit(confirmed)


@rpc("authority", "call_local", "reliable")
func rpc_peer_display_names_snapshot(peer_display_names: Dictionary) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	peer_display_names_updated.emit(peer_display_names.duplicate(true))


func _revealed_for_peer(peer_id: int) -> Dictionary:
	if not _revealed_by_peer.has(peer_id):
		_revealed_by_peer[peer_id] = {}
	return _revealed_by_peer[peer_id]


func _clicked_fog_for_peer(peer_id: int) -> Dictionary:
	if not _clicked_fog_by_peer.has(peer_id):
		_clicked_fog_by_peer[peer_id] = {}
	return _clicked_fog_by_peer[peer_id]


func _notify_client_fog_clicked_delta(peer_id: int, delta: PackedVector2Array) -> void:
	if delta.is_empty():
		return
	if _using_solo_local() and peer_id == _solo_offline_peer:
		for i in range(delta.size()):
			var vi := Vector2i(int(delta[i].x), int(delta[i].y))
			_client_fog_clicked[vi] = true
		fog_clicked_cells_delta.emit(delta)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_fog_clicked_cells_delta.rpc_id(peer_id, delta)


func _init_peer_torch(peer_id: int) -> void:
	_torch_count_by_peer[peer_id] = 1
	if _torch_daylight():
		_torch_burn_by_peer[peer_id] = TORCH_BURN_FULL
	else:
		_torch_burn_by_peer[peer_id] = TORCH_BURN_FULL


func _torch_daylight() -> bool:
	return DungeonFog.normalize_fog_type(_fog_type) == "daylight"


func _torch_burn_value(peer_id: int) -> int:
	return int(_torch_burn_by_peer.get(peer_id, TORCH_BURN_FULL))


func _torch_should_expand_fog(peer_id: int) -> bool:
	if not _fog_enabled:
		return false
	if _move_fog_reveal_radius() <= 0:
		return false
	if _torch_daylight():
		return true
	return _torch_burn_value(peer_id) > 1


func _rng_door_cell(peer_id: int, cell: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(_authority_seed) * 1_103_515_245
		^ cell.x * 10_013
		^ cell.y * 79_199
		^ int(peer_id) * 1_000_003
		^ salt * 12_345_679
	)
	return rng


## Deterministic trap-disarm roll (Explorer `execute_disarm_attempt` d20+DEX vs DC 15, door/treasure `1d2` dmg).
static func roll_trap_disarm_deterministic(
	authority_seed: int, peer_id: int, cell: Vector2i, dex_bonus: int
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(authority_seed) * 1_103_515_245
		^ cell.x * 10_013
		^ cell.y * 79_199
		^ int(peer_id) * 1_000_003
		^ 93 * 12_345_679
	)
	var d20: int = rng.randi_range(1, 20)
	var total: int = d20 + dex_bonus
	var dmg: int = rng.randi_range(1, 2)
	return {
		"ok": total >= TRAP_DISARM_DC,
		"d20": d20,
		"bonus": dex_bonus,
		"total": total,
		"dmg": dmg,
	}


func _roll_trap_disarm(peer_id: int, cell: Vector2i) -> Dictionary:
	var bonus: int = _dex_pick_bonus_for_peer(peer_id)
	return roll_trap_disarm_deterministic(int(_authority_seed), peer_id, cell, bonus)


func _server_apply_trap_defused(cell: Vector2i) -> void:
	if _trap_defused_doors.has(cell):
		return
	_trap_defused_doors[cell] = true
	var one := PackedVector2Array()
	one.append(Vector2(cell))
	_notify_trap_defused_doors_delta(one)


func _torch_tick_after_move(peer_id: int, logical_cell: Vector2i) -> bool:
	## Returns true if fog was reset (torch expired with no spare torch).
	if not _fog_enabled:
		return false
	if _torch_daylight():
		return false
	if not _torch_reveals_moves:
		return false
	var burn := _torch_burn_value(peer_id)
	burn = maxi(0, burn - 1)
	_torch_burn_by_peer[peer_id] = burn
	if burn > 0:
		return false
	var cnt := int(_torch_count_by_peer.get(peer_id, 1))
	if cnt > 1:
		_torch_count_by_peer[peer_id] = cnt - 1
		_torch_burn_by_peer[peer_id] = TORCH_BURN_FULL
		print(
			"[Dungeoneers] torch depleted peer_id=",
			peer_id,
			" — lighting spare (",
			cnt - 1,
			" left)"
		)
		return false
	return _server_reset_fog_torch_expired(peer_id, logical_cell)


func _server_reset_fog_torch_expired(peer_id: int, player_cell: Vector2i) -> bool:
	var pos: Vector2i = player_cell
	var revealed: Dictionary = _revealed_for_peer(peer_id)
	revealed.clear()
	## Explorer `handle_info(:torch_expired)` last branch: `FogOfWar.initialize_revealed_with_light/2`
	## (R1 + surroundings, player disk, static light tiles) — same as `_seed_initial_fog_for_peer`.
	DungeonFog.seed_initial_revealed_with_light(
		revealed, _authority_grid, pos, _authority_rooms, _fog_type
	)
	var packed := DungeonFog.pack_revealed_keys(revealed)
	_notify_fog_full_resync(peer_id, packed)
	print("[Dungeoneers] torch expired peer_id=", peer_id, " fog reset cells=", packed.size())
	return true


func _notify_fog_full_resync(peer_id: int, cells: PackedVector2Array) -> void:
	if _using_solo_local() and peer_id == _solo_offline_peer:
		_client_revealed.clear()
		for i in range(cells.size()):
			var vi := Vector2i(int(cells[i].x), int(cells[i].y))
			_client_revealed[vi] = true
		fog_full_resync.emit(cells)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_fog_full_resync.rpc_id(peer_id, cells)


func _cell_occupied_by_other(sender: int, cell: Vector2i) -> bool:
	for pid in _player_positions:
		if int(pid) == sender:
			continue
		if _player_positions[pid] == cell:
			return true
	return false


func _move_fog_reveal_radius() -> int:
	if not _torch_reveals_moves:
		return 0
	return _fog_radius


func _seed_initial_fog_for_peer(peer_id: int, spawn_cell: Vector2i) -> void:
	if not _fog_enabled:
		_revealed_by_peer.erase(peer_id)
		return
	var rev: Dictionary = _revealed_for_peer(peer_id)
	rev.clear()
	DungeonFog.seed_initial_revealed_with_light(
		rev, _authority_grid, spawn_cell, _authority_rooms, _fog_type
	)


func _notify_secret_doors_delta_all(cells: PackedVector2Array) -> void:
	if cells.is_empty():
		return
	if _using_solo_local():
		for i in range(cells.size()):
			var vi := Vector2i(int(cells[i].x), int(cells[i].y))
			_client_revealed_secret_doors[vi] = true
		secret_doors_delta.emit(cells)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_secret_doors_delta.rpc(cells)


func _server_scan_secret_doors_after_move(peer_id: int, new_cell: Vector2i) -> void:
	if (
		not _using_solo_local()
		and (multiplayer.multiplayer_peer == null or not multiplayer.is_server())
	):
		return
	var offsets: Array[Vector2i] = [
		Vector2i(-1, -1),
		Vector2i(0, -1),
		Vector2i(1, -1),
		Vector2i(-1, 0),
		Vector2i(1, 0),
		Vector2i(-1, 1),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	for off in offsets:
		var c: Vector2i = new_cell + off
		var raw: String = str(_authority_grid.get(c, ""))
		if raw != "secret_door":
			continue
		if _revealed_secret_doors.has(c):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = (
			int(_authority_seed) * 1_103_515_245
			^ peer_id * 1_315_423_911
			^ c.x * 524_287
			^ c.y * 65_521
			^ 9_876_543_211
		)
		var roll: int = rng.randi_range(1, 20)
		if roll < 15:
			continue
		_revealed_secret_doors[c] = true
		var one := PackedVector2Array()
		one.append(Vector2(c))
		_notify_secret_doors_delta_all(one)
		print("[Dungeoneers] secret_door revealed peer_id=", peer_id, " cell=", c, " roll=", roll)
		return


func _apply_authorized_move(
	sender: int, target: Vector2i, allow_post_move_prompts: bool = true
) -> void:
	var revealed: Dictionary = _revealed_for_peer(sender)
	_player_positions[sender] = target
	if _fog_enabled:
		var delta := PackedVector2Array()
		if _torch_should_expand_fog(sender):
			var r_disk: int = _move_fog_reveal_radius()
			var disk_new: int = DungeonFog.count_new_disk_reveals(revealed, target, r_disk)
			_server_award_exploration_xp_for_disk_new(sender, disk_new)
			DungeonFog.append_disk_delta(revealed, target, r_disk, delta)
			DungeonFog.append_area_label_cells_into_delta(
				revealed, _authority_grid, target, _authority_rooms, _authority_corridors, delta
			)
		if not delta.is_empty():
			_notify_client_fog_delta(sender, delta)
	_torch_tick_after_move(sender, target)
	print("[Dungeoneers] move accepted peer_id=", sender, " cell=", target)
	_notify_client_player_sync(sender, target)
	var trap_blk: Dictionary = _server_post_move_trap_modals_blocking_encounter(sender, target)
	var trap_show: bool = bool(trap_blk.get("showed_modal", false))
	var trap_blocks_enc: bool = bool(trap_blk.get("blocks_adjacent_encounter", false))
	var enc_modal := false
	if not trap_blocks_enc:
		enc_modal = _server_maybe_post_move_adjacent_encounter(
			sender, target, allow_post_move_prompts
		)
	var treasure_modal := false
	if not trap_show and not enc_modal:
		treasure_modal = _server_maybe_post_move_plain_treasure_discovery(sender, target)
	var traps_modal: bool = trap_show or treasure_modal
	var pickup_modal := false
	if not traps_modal and not enc_modal:
		pickup_modal = _server_maybe_post_move_pickup(sender, target)
	var sf_modal := false
	if not traps_modal and not enc_modal:
		sf_modal = _server_maybe_post_move_special_feature(sender, target, allow_post_move_prompts)
	if not traps_modal and not enc_modal and not pickup_modal and not sf_modal:
		_server_maybe_post_move_stand_navigation(sender, target, allow_post_move_prompts)
	_server_scan_secret_doors_after_move(sender, target)
	_server_process_monster_turns_after_player(sender)
	_emit_stats_for_peer(sender)


func _monster_combat_ui_delay_sec() -> float:
	if monster_combat_ui_delay_sec_for_tests >= 0.0:
		return monster_combat_ui_delay_sec_for_tests
	return MONSTER_COMBAT_UI_DELAY_SEC


func _path_move_step_delay_sec() -> float:
	if path_move_step_sec_for_tests >= 0.0:
		return path_move_step_sec_for_tests
	return PATH_MOVE_STEP_SEC


func _server_cancel_pending_path_move(peer_id: int) -> void:
	_path_move_serial_by_peer[peer_id] = int(_path_move_serial_by_peer.get(peer_id, 0)) + 1
	_path_move_queue_by_peer.erase(peer_id)
	_path_move_door_after_by_peer.erase(peer_id)


func _server_monster_combat_delay_serial_bump(mover_peer: int) -> int:
	var nxt := int(_monster_combat_delay_serial_by_peer.get(mover_peer, 0)) + 1
	_monster_combat_delay_serial_by_peer[mover_peer] = nxt
	return nxt


## Invalidate any `SceneTreeTimer` from `_server_schedule_encounter_fight_delayed` for this peer
## (Explorer CMB-02 parity) so a delayed hunter strike cannot start combat after the player already did.
func _server_cancel_pending_monster_combat_delay_for_peer(peer_id: int) -> void:
	var cur := int(_monster_combat_delay_serial_by_peer.get(peer_id, 0))
	_monster_combat_delay_serial_by_peer[peer_id] = cur + 1


func _server_invalidate_monster_combat_delay_timers() -> void:
	_monster_combat_delay_serial_by_peer.clear()


func _server_schedule_encounter_fight_delayed(mover_peer: int, combat_at: Vector2i) -> void:
	var d := _monster_combat_ui_delay_sec()
	var serial := _server_monster_combat_delay_serial_bump(mover_peer)
	if d <= 0.0:
		_server_handle_encounter_fight(mover_peer, combat_at)
		return
	var delay_timer := get_tree().create_timer(d, false, false)
	delay_timer.timeout.connect(
		func() -> void:
			if not is_instance_valid(self):
				return
			if int(_monster_combat_delay_serial_by_peer.get(mover_peer, 0)) != serial:
				return
			if _server_combat_by_peer.has(mover_peer):
				return
			if not _player_positions.has(mover_peer):
				return
			_server_handle_encounter_fight(mover_peer, combat_at)
	)


func _server_process_monster_turns_after_player(mover_peer: int) -> void:
	if _server_combat_by_peer.has(mover_peer):
		return
	if not _player_positions.has(mover_peer):
		return
	var role_mov := str(_peer_roles.get(mover_peer, "rogue"))
	var hp0 := int(
		_server_player_hp.get(mover_peer, PlayerCombatStats.starting_hit_points_for_role(role_mov))
	)
	if hp0 <= 0:
		return
	var revealed_m: Dictionary = _revealed_for_peer(mover_peer)
	var player_cell: Vector2i = _player_positions[mover_peer]
	var mover_al := int(
		_server_player_alignment.get(mover_peer, PlayerAlignment.starting_alignment())
	)
	# Explorer `MonsterTurnSystem.process_monster_turns/1`: snapshot + `Enum.reduce` — one pass per hunter
	# (CMB-02). Combat is scheduled after `MONSTER_COMBAT_UI_DELAY_SEC` like LiveView `send_after(..., 400)`.
	var combat_at := MonsterTurn.process_monster_reduce_pass(
		_authority_grid,
		_authority_rooms,
		_trap_defused_doors,
		_fog_enabled,
		revealed_m,
		_authority_seed,
		mover_peer,
		player_cell,
		_authority_guards_hostile,
		mover_al,
		Callable(self, "_notify_authority_tile_patch")
	)
	if combat_at.x >= 0:
		_server_schedule_encounter_fight_delayed(mover_peer, combat_at)


func _server_peer_movement_blocked(sender: int) -> bool:
	return _server_combat_by_peer.has(sender) or _server_feature_ambush_pending.has(sender)


## Explorer `Movement.direct_encounter_destination?` + `show_encounter_dialog_for_movement` — moving
## orthogonally onto an `encounter|` cell shows the encounter / NPC modal **without** applying the move first.
func _server_try_deliver_direct_encounter_before_move(
	peer_id: int, from_cell: Vector2i, to_cell: Vector2i
) -> bool:
	if not GridWalk.is_orthogonal_adjacent(from_cell, to_cell):
		return false
	var revealed: Dictionary = _revealed_for_peer(peer_id)
	if _fog_enabled and not DungeonFog.square_revealed(to_cell, revealed, true):
		return false
	var eff: String = _authority_effective_tile(to_cell)
	if not eff.begins_with("encounter|"):
		return false
	var eb: Dictionary = _world_interaction_encounter_branch(peer_id, to_cell, eff)
	var send_kind: String = str(eb.get("kind", "encounter"))
	var pack_r := {"title": str(eb.get("title", "")), "message": str(eb.get("message", ""))}
	if send_kind == "npc_quest_offer":
		var qv: Variant = eb.get("quest", null)
		if qv is Dictionary:
			_server_pending_npc_quest[peer_id] = {
				"cell": to_cell,
				"quest": (qv as Dictionary).duplicate(true),
			}
	_deliver_world_interaction_to_peer(
		peer_id, send_kind, to_cell, str(pack_r["title"]), str(pack_r["message"])
	)
	print(
		"[Dungeoneers] direct_encounter_before_move peer_id=",
		peer_id,
		" cell=",
		to_cell,
		" kind=",
		send_kind
	)
	return true


func _server_try_adjacent_move(sender: int, target: Vector2i) -> bool:
	if not _player_positions.has(sender):
		return false
	if _server_peer_movement_blocked(sender):
		print("[Dungeoneers] move rejected: in combat peer_id=", sender)
		return false
	_server_cancel_pending_path_move(sender)
	var cur: Vector2i = _player_positions[sender]
	if not GridWalk.is_orthogonal_adjacent(cur, target):
		print(
			"[Dungeoneers] move rejected: not orthogonally adjacent peer_id=",
			sender,
			" from=",
			cur,
			" to=",
			target
		)
		return false
	var revealed: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(target, revealed, true):
		print("[Dungeoneers] move rejected: fog peer_id=", sender, " from=", cur, " to=", target)
		return false
	if _cell_occupied_by_other(sender, target):
		print("[Dungeoneers] move rejected: cell occupied peer_id=", sender, " target=", target)
		return false
	if _server_try_deliver_direct_encounter_before_move(sender, cur, target):
		return true
	var move_tile: String = _authority_effective_tile(target)
	if not GridWalk.is_walkable_for_movement_at(
		move_tile, target, _unlocked_doors, _authority_guards_hostile
	):
		print(
			"[Dungeoneers] move rejected: not walkable peer_id=",
			sender,
			" tile=",
			move_tile,
			" at=",
			target
		)
		return false
	_apply_authorized_move(sender, target, true)
	return true


func _server_door_click_valid(sender: int, cell: Vector2i) -> bool:
	if not _player_positions.has(sender):
		return false
	var cur: Vector2i = _player_positions[sender]
	if not GridWalk.is_king_adjacent(cur, cell):
		print("[Dungeoneers] door_click rejected: not adjacent peer_id=", sender, " cell=", cell)
		return false
	var revealed: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, revealed, true):
		print("[Dungeoneers] door_click rejected: fog peer_id=", sender, " cell=", cell)
		return false
	var t: String = _authority_effective_tile(cell)
	if not DungeonFeatures.is_door_tile(t):
		print("[Dungeoneers] door_click rejected: not a door tile peer_id=", sender, " tile=", t)
		return false
	return true


func _world_interaction_encounter_message(effective_tile: String) -> String:
	## Matches `DungeonWeb.DungeonLive.EncounterSystem.generate_encounter_message/2`.
	var parts := effective_tile.split("|")
	var label := parts[1] if parts.size() > 1 else "?"
	var mname := parts[2] if parts.size() > 2 else "monster"
	return "You have an encounter with a " + mname + "! (" + label + ")"


func _world_interaction_payload(
	kind: String, raw_tile: String, effective_tile: String, cell: Vector2i
) -> Dictionary:
	var title := "Notice"
	var msg := ""
	match kind:
		"stair":
			var ps: Dictionary = WorldLabelsMsg.stair_world_interaction_payload(
				raw_tile, _authority_theme_name, _authority_theme
			)
			title = str(ps["title"])
			msg = str(ps["message"])
		"waypoint":
			title = "Waypoint Marker"
			var gen_wp := _generation_type.strip_edges()
			if gen_wp == "city" or gen_wp == "outdoor":
				var dest_wp: String = (
					str(_server_waypoint_destination_by_cell.get(cell, "")).strip_edges()
				)
				if dest_wp.is_empty():
					var dtype_wp := "outdoor" if gen_wp == "city" else "city"
					var cur_td_wp: Dictionary = DungeonThemes.find_theme_by_name(
						_authority_theme_name
					)
					if cur_td_wp.is_empty():
						cur_td_wp = {"generation_type": gen_wp}
					var rng_wp := RandomNumberGenerator.new()
					rng_wp.randomize()
					dest_wp = (
						MapTransition
						. get_random_destination_theme(rng_wp, dtype_wp, cur_td_wp)
						. strip_edges()
					)
					if not dest_wp.is_empty():
						_server_waypoint_destination_by_cell[cell] = dest_wp
				msg = WorldLabelsMsg.waypoint_destination_land_message(dest_wp)
			else:
				var pw: Dictionary = WorldLabelsMsg.waypoint_world_interaction_payload(
					raw_tile, _authority_theme_name, _authority_theme
				)
				msg = str(pw["message"])
		"map_link":
			title = "Passage Found"
			var dest_ml: String = (
				str(_server_map_link_destination_by_cell.get(cell, "")).strip_edges()
			)
			if dest_ml.is_empty():
				var dtype_ml := MapTransition.destination_type_from_map_link_tile(raw_tile)
				if not dtype_ml.is_empty():
					var cur_td: Dictionary = DungeonThemes.find_theme_by_name(_authority_theme_name)
					if cur_td.is_empty():
						cur_td = {"generation_type": _generation_type}
					var rng_ml := RandomNumberGenerator.new()
					rng_ml.randomize()
					dest_ml = (
						MapTransition
						. get_random_destination_theme(rng_ml, dtype_ml, cur_td)
						. strip_edges()
					)
					if not dest_ml.is_empty():
						_server_map_link_destination_by_cell[cell] = dest_ml
			msg = MapLinkSystem.get_map_link_description_for_raw_tile(raw_tile, dest_ml)
		"treasure":
			var g: int = TreasureSys.gold_for_treasure_cell(_authority_seed, cell)
			title = TreasureSys.treasure_discovery_dialog_title()
			msg = TreasureSys.treasure_discovery_message(g, _authority_theme_name)
		"room_trap":
			title = "Trap"
			msg = WorldLabelsMsg.room_trap_world_interaction_body(
				_authority_theme_name, _authority_theme
			)
		"room_label":
			var pr: Dictionary = WorldLabelsMsg.room_label_payload(
				effective_tile, _authority_theme_name, _authority_theme
			)
			title = str(pr["title"])
			msg = str(pr["message"])
		"corridor_label":
			var pc: Dictionary = WorldLabelsMsg.corridor_label_payload(
				effective_tile, _authority_theme_name, _authority_theme
			)
			title = str(pc["title"])
			msg = str(pc["message"])
		"area_label":
			var pa: Dictionary = WorldLabelsMsg.area_label_payload(
				effective_tile, _authority_theme_name, _authority_theme
			)
			title = str(pa["title"])
			msg = str(pa["message"])
		"building_label":
			var pb: Dictionary = WorldLabelsMsg.building_label_payload(
				effective_tile, _authority_theme_name, _authority_theme
			)
			title = str(pb["title"])
			msg = str(pb["message"])
		"special_feature":
			var pf: Dictionary = WorldLabelsMsg.special_feature_payload(
				effective_tile, _authority_theme_name, _authority_theme
			)
			title = str(pf["title"])
			msg = str(pf["message"])
		_:
			msg = "Nothing special happens."
	return {"title": title, "message": msg}


func _world_interaction_encounter_branch(
	peer_id: int, encounter_cell: Vector2i, effective_tile: String
) -> Dictionary:
	var mname: String = _encounter_monster_name_from_tile(effective_tile)
	var role: String = MonsterTable.role_for_monster_name(mname)
	var def_m: Dictionary = MonsterTable.lookup_monster(mname)
	var m_align := str(def_m.get("alignment", "neutral")).strip_edges().to_lower()
	var p_al := int(_server_player_alignment.get(peer_id, PlayerAlignment.starting_alignment()))
	var hostile := PlayerAlignment.npc_hostile_to_player(m_align, p_al)
	var peaceful_npc := role == "npc" and not hostile
	var peaceful_guard := role == "guard" and not _authority_guards_hostile and not hostile
	if peaceful_npc or peaceful_guard:
		var offer: Dictionary = PlayerQuests.try_build_npc_quest_offer_payload(
			_server_peer_quests_array(peer_id),
			mname,
			m_align,
			p_al,
			_authority_theme_name,
			_dungeon_level,
			_authority_seed,
			peer_id,
			encounter_cell
		)
		if str(offer.get("result", "")) == "offer":
			return {
				"kind": "npc_quest_offer",
				"title": str(offer.get("title", "Quest offer")),
				"message": str(offer.get("message", "")),
				"quest": offer.get("quest", {}),
			}
		return {
			"kind": "encounter_npc",
			"title": str(offer.get("title", "Conversation")),
			"message": str(offer.get("message", "Hello.")),
		}
	return {
		"kind": "encounter",
		"title": "You have an encounter!",
		"message": _world_interaction_encounter_message(effective_tile),
	}


func _roll_treasure_trap_detect(peer_id: int, cell: Vector2i) -> Dictionary:
	var rng := _rng_door_cell(peer_id, cell, 211)
	var d20: int = rng.randi_range(1, 20)
	return {"ok": d20 >= TREASURE_TRAP_DETECT_DC, "d20": d20}


func _server_apply_hp_damage_to_peer(peer_id: int, amount: int) -> int:
	var role_l := str(_peer_roles.get(peer_id, "rogue"))
	var hp_l: int = int(
		_server_player_hp.get(peer_id, PlayerCombatStats.starting_hit_points_for_role(role_l))
	)
	hp_l = maxi(0, hp_l - maxi(0, amount))
	_server_player_hp[peer_id] = hp_l
	_emit_stats_for_peer(peer_id)
	return hp_l


func _server_convert_trapped_treasure_to_treasure(cell: Vector2i) -> void:
	if GridWalk.tile_at(_authority_grid, cell) != "trapped_treasure":
		return
	_authority_grid[cell] = "treasure"
	_notify_authority_tile_patch(cell, "treasure")
	_treasure_trap_disarm_pending.erase(cell)


func _server_offer_plain_treasure_pickup(peer_id: int, cell: Vector2i) -> void:
	var g2: int = TreasureSys.gold_for_treasure_cell(_authority_seed, cell)
	var title_tr := TreasureSys.treasure_discovery_dialog_title()
	var msg_pick := TreasureSys.treasure_discovery_message(g2, _authority_theme_name)
	_deliver_world_interaction_to_peer(peer_id, "treasure", cell, title_tr, msg_pick)


func _server_handle_trapped_treasure_interaction(sender: int, cell: Vector2i) -> void:
	if GridWalk.tile_at(_authority_grid, cell) != "trapped_treasure":
		return
	var revealed_t: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, revealed_t, true):
		return
	var det: Dictionary = _roll_treasure_trap_detect(sender, cell)
	var d20v: int = int(det["d20"])
	if bool(det["ok"]):
		_treasure_trap_disarm_pending[cell] = true
		var msg_ok := (
			"Something doesn't feel right about this treasure — you suspect it might be trapped!\n\n"
			+ "(Detected with roll "
			+ str(d20v)
			+ " vs DC "
			+ str(TREASURE_TRAP_DETECT_DC)
			+ ")\n\nAttempt to disarm (d20 + DEX vs DC "
			+ str(TRAP_DISARM_DC)
			+ "), or leave the chest alone for now."
		)
		_deliver_world_interaction_to_peer(
			sender, "trapped_treasure_detected", cell, "You've found a trap!", msg_ok
		)
	else:
		var msg_fail := (
			"You fail to notice the tampering (rolled "
			+ str(d20v)
			+ " vs DC "
			+ str(TREASURE_TRAP_DETECT_DC)
			+ ").\n\nA needle springs from the latch as you reach for the lid!\n\nPress Continue."
		)
		_deliver_world_interaction_to_peer(
			sender, "trapped_treasure_undetected", cell, "Trap!", msg_fail
		)


func _server_handle_trapped_treasure_undetected_ack(sender: int, cell: Vector2i) -> void:
	if GridWalk.tile_at(_authority_grid, cell) != "trapped_treasure":
		print("[Dungeoneers] trapped_treasure_undetected_ack rejected tile cell=", cell)
		return
	var rev_u: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, rev_u, true):
		return
	var rng_u := _rng_door_cell(sender, cell, 313)
	var dmg_u: int = rng_u.randi_range(1, 2)
	var hp_u: int = _server_apply_hp_damage_to_peer(sender, dmg_u)
	_deliver_encounter_resolution_to_peer(
		sender,
		"Trap triggered",
		"The poisoned needle bites deep!\n\nYou take " + str(dmg_u) + " damage.",
	)
	print(
		"[Dungeoneers] trapped_treasure_undetected_ack peer_id=",
		sender,
		" dmg=",
		dmg_u,
		" hp=",
		hp_u
	)
	if hp_u <= 0:
		_deliver_encounter_resolution_to_peer(
			sender,
			"Death",
			"The poisoned needle was the last thing you felt. Your adventure ends here.",
		)
	_server_convert_trapped_treasure_to_treasure(cell)
	if hp_u > 0:
		_server_offer_plain_treasure_pickup(sender, cell)


func _server_handle_trapped_treasure_skip_disarm(sender: int, cell: Vector2i) -> void:
	if not _treasure_trap_disarm_pending.has(cell):
		print("[Dungeoneers] treasure_trap_skip rejected not pending cell=", cell)
		return
	if GridWalk.tile_at(_authority_grid, cell) != "trapped_treasure":
		_treasure_trap_disarm_pending.erase(cell)
		return
	_treasure_trap_disarm_pending.erase(cell)
	print("[Dungeoneers] treasure_trap_skip peer_id=", sender, " cell=", cell)


func _server_handle_trapped_treasure_disarm(sender: int, cell: Vector2i) -> void:
	if not _treasure_trap_disarm_pending.has(cell):
		print("[Dungeoneers] treasure_trap_disarm rejected not pending cell=", cell)
		return
	if GridWalk.tile_at(_authority_grid, cell) != "trapped_treasure":
		_treasure_trap_disarm_pending.erase(cell)
		return
	_treasure_trap_disarm_pending.erase(cell)
	var r_dis_t: Dictionary = _roll_trap_disarm(sender, cell)
	if bool(r_dis_t["ok"]):
		_server_add_xp_with_level_up(sender, TRAP_DISARM_XP_TREASURE)
		_server_convert_trapped_treasure_to_treasure(cell)
		_emit_stats_for_peer(sender)
		var d20_ok: int = int(r_dis_t["d20"])
		var bon_ok: int = int(r_dis_t["bonus"])
		var tot_ok: int = int(r_dis_t["total"])
		_deliver_encounter_resolution_to_peer(
			sender,
			"Trap disarmed",
			(
				"You successfully disarm the trap!\n(Rolled "
				+ str(d20_ok)
				+ " + "
				+ str(bon_ok)
				+ " DEX = "
				+ str(tot_ok)
				+ " vs DC "
				+ str(TRAP_DISARM_DC)
				+ ")\n\nThe chest is safe to open (+"
				+ str(TRAP_DISARM_XP_TREASURE)
				+ " XP)."
			)
		)
		_server_offer_plain_treasure_pickup(sender, cell)
		print("[Dungeoneers] treasure_trap_disarm_success peer_id=", sender, " cell=", cell)
	else:
		var dmg_f: int = int(r_dis_t["dmg"])
		_server_convert_trapped_treasure_to_treasure(cell)
		var hp_f: int = _server_apply_hp_damage_to_peer(sender, dmg_f)
		var d20_b: int = int(r_dis_t["d20"])
		var bon_b: int = int(r_dis_t["bonus"])
		var tot_b: int = int(r_dis_t["total"])
		_deliver_encounter_resolution_to_peer(
			sender,
			"Trap triggered",
			(
				"You fail to disarm the trap and trigger it!\n(Rolled "
				+ str(d20_b)
				+ " + "
				+ str(bon_b)
				+ " DEX = "
				+ str(tot_b)
				+ " vs DC "
				+ str(TRAP_DISARM_DC)
				+ ")\n\nYou take "
				+ str(dmg_f)
				+ " damage."
			)
		)
		if hp_f > 0:
			_server_offer_plain_treasure_pickup(sender, cell)
		else:
			_deliver_encounter_resolution_to_peer(
				sender, "Death", "The mechanism bites deep — you collapse."
			)
		print(
			"[Dungeoneers] treasure_trap_disarm_fail peer_id=", sender, " dmg=", dmg_f, " hp=", hp_f
		)


func _server_investigated_feature_key(cell: Vector2i) -> String:
	return str(cell.x) + "," + str(cell.y)


func _server_peer_already_investigated_feature(peer_id: int, cell: Vector2i) -> bool:
	var sub: Variant = _server_investigated_features.get(peer_id, null)
	if sub is Dictionary:
		return (sub as Dictionary).get(_server_investigated_feature_key(cell), false) == true
	return false


func _server_mark_feature_investigated(peer_id: int, cell: Vector2i) -> void:
	var sub2: Dictionary = {}
	var ex: Variant = _server_investigated_features.get(peer_id, null)
	if ex is Dictionary:
		sub2 = (ex as Dictionary).duplicate()
	sub2[_server_investigated_feature_key(cell)] = true
	_server_investigated_features[peer_id] = sub2


func _server_broadcast_rumors_to_peer(peer_id: int) -> void:
	var arr: Array = _server_rumors_by_peer.get(peer_id, [])
	var pack: PackedStringArray = PackedStringArray()
	for s in arr:
		pack.append(str(s))
	if _using_solo_local() and peer_id == _solo_offline_peer:
		player_rumors_updated.emit(pack)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_player_rumors.rpc_id(peer_id, pack)


func _server_pack_special_item_keys(peer_id: int) -> PackedStringArray:
	var arr: Array = _server_special_items_by_peer.get(peer_id, [])
	var pack: PackedStringArray = PackedStringArray()
	for s in arr:
		pack.append(str(s))
	return pack


func _server_broadcast_special_items_to_peer(peer_id: int) -> void:
	var pack := _server_pack_special_item_keys(peer_id)
	if _using_solo_local() and peer_id == _solo_offline_peer:
		player_special_items_updated.emit(pack)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_player_special_items.rpc_id(peer_id, pack)
	# Wearable armor_bonus increases max HP (Explorer `calculate_total_stats`).
	if (
		(_using_solo_local() and peer_id == _solo_offline_peer)
		or (multiplayer.multiplayer_peer != null and multiplayer.is_server())
	):
		_server_recompute_max_hp_store(peer_id)
		_emit_stats_for_peer(peer_id)


func _server_peer_quests_array(peer_id: int) -> Array:
	var qv: Variant = _server_quests_by_peer.get(peer_id, null)
	if qv is Array:
		return qv as Array
	var arr: Array = []
	_server_quests_by_peer[peer_id] = arr
	return arr


func _server_broadcast_quests_to_peer(peer_id: int) -> void:
	var qpack := PlayerQuests.serialize_quests_for_rpc(_server_peer_quests_array(peer_id))
	if _using_solo_local() and peer_id == _solo_offline_peer:
		player_quests_updated.emit(qpack)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_player_quests.rpc_id(peer_id, qpack)


func _server_peer_achievements_array(peer_id: int) -> Array:
	var av: Variant = _server_achievements_by_peer.get(peer_id, null)
	if av is Array:
		return av as Array
	var aarr: Array = []
	_server_achievements_by_peer[peer_id] = aarr
	return aarr


func _server_append_quest_achievement(peer_id: int, quest_snapshot: Dictionary) -> void:
	var line: String = PlayerQuests.achievement_text_for_completed_quest(quest_snapshot)
	if line.strip_edges().is_empty():
		return
	_server_peer_achievements_array(peer_id).append(line)
	_server_broadcast_achievements_to_peer(peer_id)


func _server_broadcast_achievements_to_peer(peer_id: int) -> void:
	var arr_a: Array = _server_achievements_by_peer.get(peer_id, [])
	var pack_a := PackedStringArray()
	for s in arr_a:
		pack_a.append(str(s))
	if _using_solo_local() and peer_id == _solo_offline_peer:
		player_achievements_updated.emit(pack_a)
	elif multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_player_achievements.rpc_id(peer_id, pack_a)


func _server_cell_with_quest_item_tile(quest_id: String) -> Vector2i:
	var want := PlayerQuests.quest_item_tile(quest_id)
	for k in _authority_grid:
		if str(_authority_grid[k]) == want:
			return k as Vector2i
	return Vector2i(-1, -1)


func _server_try_place_active_quest_items_for_peer(peer_id: int) -> void:
	var qarr: Array = _server_peer_quests_array(peer_id)
	for q in qarr:
		if not q is Dictionary:
			continue
		var qd: Dictionary = q as Dictionary
		if not PlayerQuests.should_spawn_quest_item_on_map(qd, _authority_theme_name):
			continue
		var qid := str(qd.get("id", "")).strip_edges()
		if qid.is_empty():
			continue
		var existing := _server_cell_with_quest_item_tile(qid)
		if existing.x >= 0 and existing.y >= 0:
			continue
		var place: Vector2i = PlayerQuests.find_quest_item_placement(
			_authority_grid, _authority_seed, qid
		)
		if place.x < 0:
			continue
		var prev: String = GridWalk.tile_at(_authority_grid, place)
		if prev != "floor" and prev != "corridor":
			continue
		var tile_s := PlayerQuests.quest_item_tile(qid)
		_authority_grid[place] = tile_s
		_notify_authority_tile_patch(place, tile_s)
		print("[Dungeoneers] quest_item_spawn peer_id=", peer_id, " cell=", place, " id=", qid)
	_server_try_spawn_kill_quest_encounters_for_peer(peer_id)


func _server_try_spawn_kill_quest_encounters_for_peer(peer_id: int) -> void:
	var qarr2: Array = _server_peer_quests_array(peer_id)
	for q2 in qarr2:
		if not q2 is Dictionary:
			continue
		var qk: Dictionary = q2 as Dictionary
		if not PlayerQuests.should_spawn_kill_quest_on_map(qk, _authority_theme_name):
			continue
		var tgt: String = PlayerQuests.kill_quest_target_name(qk)
		if tgt.is_empty():
			continue
		if PlayerQuests.grid_has_kill_target_encounter(_authority_grid, tgt):
			continue
		var qid_k := str(qk.get("id", "")).strip_edges()
		var place_k: Vector2i = PlayerQuests.find_kill_quest_encounter_placement(
			_authority_grid, _authority_seed, qid_k, tgt
		)
		if place_k.x < 0:
			continue
		var prev_k: String = GridWalk.tile_at(_authority_grid, place_k)
		if prev_k != "floor" and prev_k != "corridor":
			continue
		var tile_k := PlayerQuests.kill_quest_encounter_tile(tgt)
		_authority_grid[place_k] = tile_k
		_notify_authority_tile_patch(place_k, tile_k)
		print(
			"[Dungeoneers] kill_quest_encounter_spawn peer_id=",
			peer_id,
			" cell=",
			place_k,
			" target=",
			tgt
		)


func _server_try_place_active_quest_items_for_all_peers() -> void:
	for pid in _player_positions.keys():
		_server_try_place_active_quest_items_for_peer(int(pid))


func _server_offer_special_item_discovery(peer_id: int, cell: Vector2i, pick_salt: int) -> bool:
	if int(_server_special_item_dismiss_xp_pending.get(peer_id, 0)) > 0:
		return false
	var item: Dictionary = SpecialItemTable.pick_deterministic(_authority_seed, cell, pick_salt)
	if item.is_empty():
		return false
	var key := str(item.get("key", "")).strip_edges()
	if key.is_empty():
		return false
	var prev: Array = _server_special_items_by_peer.get(peer_id, []) as Array
	var narr: Array = []
	for x in prev:
		narr.append(str(x))
	narr.append(key)
	_server_special_items_by_peer[peer_id] = narr
	var xp_aw := maxi(0, int(item.get("xp_value", 0)))
	_server_special_item_dismiss_xp_pending[peer_id] = xp_aw
	_server_broadcast_special_items_to_peer(peer_id)
	_deliver_encounter_resolution_to_peer(
		peer_id,
		"Special item",
		SpecialItemTable.format_discovery_message(item),
	)
	return true


func _server_handle_special_item_dismiss(sender: int) -> void:
	## Explorer dungeon_live.ex dismiss_special_item: XP only on first discovery (flat 20 there;
	## here xp_value from JSON). No player_gold change. Item gold_value is for quest rewards
	## (Explorer quest.ex). P7-04 dismiss gold N/A — parity is no gold on this path.
	var pending := int(_server_special_item_dismiss_xp_pending.get(sender, 0))
	if pending <= 0:
		return
	_server_special_item_dismiss_xp_pending.erase(sender)
	_server_add_xp_with_level_up(sender, pending)
	_emit_stats_for_peer(sender)
	print("[Dungeoneers] special_item_dismiss peer_id=", sender, " xp+=", pending)


func _server_handle_feature_investigate(sender: int, cell: Vector2i) -> void:
	if not _player_positions.has(sender):
		return
	if _server_feature_trap_pending.has(sender):
		_deliver_encounter_resolution_to_peer(
			sender,
			"Search",
			"Deal with the sprung trap first — your hands are still shaking from the last needle.",
		)
		return
	if _server_feature_ambush_pending.has(sender):
		_deliver_encounter_resolution_to_peer(
			sender,
			"Search",
			"You are still reeling from what leapt out of the feature — gather yourself before searching again.",
		)
		return
	var rev_f: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, rev_f, true):
		return
	var pos_f: Vector2i = _player_positions[sender]
	if pos_f != cell and not GridWalk.is_king_adjacent(pos_f, cell):
		print(
			"[Dungeoneers] feature_investigate rejected: not adjacent peer_id=",
			sender,
			" player=",
			pos_f,
			" cell=",
			cell,
		)
		return
	var raw_f: String = GridWalk.tile_at(_authority_grid, cell)
	if not raw_f.begins_with("special_feature|"):
		print("[Dungeoneers] feature_investigate rejected: not special_feature cell=", cell)
		return
	if _server_peer_already_investigated_feature(sender, cell):
		_deliver_encounter_resolution_to_peer(
			sender, "Search", "You have already searched this feature thoroughly."
		)
		return
	var fname: String = SpecialFeatInv.feature_name_from_tile(raw_f)
	var res: Dictionary = SpecialFeatInv.evaluate(_authority_seed, cell, fname)
	var kind: String = str(res.get("kind", "nothing"))
	match kind:
		"treasure":
			var gold_i: int = int(res.get("gold", 5))
			_server_gold[sender] = int(_server_gold.get(sender, 0)) + gold_i
			_server_add_xp_with_level_up(sender, gold_i)
			_emit_stats_for_peer(sender)
			_deliver_encounter_resolution_to_peer(
				sender,
				"Treasure found",
				"Hidden in the " + fname + ": " + str(gold_i) + " gold coins!",
			)
			_server_mark_feature_investigated(sender, cell)
		"special_item":
			if _server_offer_special_item_discovery(sender, cell, SPECIAL_ITEM_PICK_SALT_FEATURE):
				_server_mark_feature_investigated(sender, cell)
			else:
				_deliver_encounter_resolution_to_peer(
					sender,
					"Nothing",
					"You search the " + fname + " thoroughly but find nothing of interest.",
				)
				_server_mark_feature_investigated(sender, cell)
		"rumor":
			var rumor_s: String = str(res.get("rumor", ""))
			var qlist: Array = _server_peer_quests_array(sender)
			var qnew: Dictionary = PlayerQuests.create_special_item_quest_from_rumor(
				_authority_seed, sender, cell, _authority_theme_name, _dungeon_level, qlist.size()
			)
			qlist.append(qnew)
			_server_quests_by_peer[sender] = qlist
			var rumor_full: String = PlayerQuests.format_rumor_note(rumor_s, qnew)
			var arr_r: Array = _server_rumors_by_peer.get(sender, [])
			arr_r.append(rumor_full)
			_server_rumors_by_peer[sender] = arr_r
			_server_broadcast_rumors_to_peer(sender)
			_server_broadcast_quests_to_peer(sender)
			_server_try_place_active_quest_items_for_peer(sender)
			_server_rumor_xp_pending[sender] = true
			_deliver_encounter_resolution_to_peer(
				sender,
				"Rumor",
				(
					rumor_full
					+ "\n\nClose this note to record the lead and gain "
					+ str(RUMOR_XP)
					+ " XP."
				),
			)
			_server_mark_feature_investigated(sender, cell)
		"trap":
			var dmg_tr: int = int(res.get("damage", 1))
			var flavor: String = SpecialFeatureTrapCopy.message_for(fname, _authority_seed, cell)
			_server_feature_trap_pending[sender] = {
				"cell_x": cell.x,
				"cell_y": cell.y,
				"damage": dmg_tr,
			}
			_server_mark_feature_investigated(sender, cell)
			_deliver_encounter_resolution_to_peer(
				sender,
				"Feature trap",
				flavor + "\n\nPress OK to take the hit and continue.",
			)
		"monster":
			var mstr: String = str(res.get("monster", "Rat"))
			_deliver_encounter_resolution_to_peer(
				sender, "Ambush!", "A " + mstr + " bursts from the " + fname + "!"
			)
			_server_feature_ambush_pending[sender] = {
				"cell_x": cell.x,
				"cell_y": cell.y,
				"monster": mstr,
			}
			_server_mark_feature_investigated(sender, cell)
		_:
			_deliver_encounter_resolution_to_peer(
				sender,
				"Nothing",
				"You search the " + fname + " thoroughly but find nothing of interest.",
			)
			_server_mark_feature_investigated(sender, cell)
	print("[Dungeoneers] feature_investigate peer_id=", sender, " cell=", cell, " kind=", kind)


func _server_handle_feature_ambush_ack(sender: int) -> void:
	var pend_a: Variant = _server_feature_ambush_pending.get(sender, null)
	if pend_a == null or not pend_a is Dictionary:
		return
	var da: Dictionary = pend_a as Dictionary
	_server_feature_ambush_pending.erase(sender)
	var acx: int = int(da.get("cell_x", 0))
	var acy: int = int(da.get("cell_y", 0))
	var amon: String = str(da.get("monster", "Rat"))
	_server_start_combat_with_monster(sender, Vector2i(acx, acy), amon)


func _server_handle_feature_trap_dismiss(sender: int) -> void:
	var pend: Variant = _server_feature_trap_pending.get(sender, null)
	if pend == null or not pend is Dictionary:
		return
	var d: Dictionary = pend as Dictionary
	_server_feature_trap_pending.erase(sender)
	var dmg: int = maxi(0, int(d.get("damage", 0)))
	var hp_after: int = _server_apply_hp_damage_to_peer(sender, dmg)
	print(
		"[Dungeoneers] feature_trap_dismiss peer_id=", sender, " dmg=", dmg, " hp_after=", hp_after
	)
	if hp_after <= 0:
		_deliver_encounter_resolution_to_peer(
			sender,
			"Death",
			"A tiny dart — and the world goes dark.",
		)


func _server_start_combat_with_monster(sender: int, rng_cell: Vector2i, mname: String) -> void:
	_server_cancel_pending_monster_combat_delay_for_peer(sender)
	_server_pending_npc_quest.erase(sender)
	if not _player_positions.has(sender):
		return
	var role_cm := str(_peer_roles.get(sender, "rogue"))
	var start_hp_cm: int = int(
		_server_player_hp.get(sender, PlayerCombatStats.starting_hit_points_for_role(role_cm))
	)
	_server_cancel_combat_monster_strike_timer(sender)
	var session_cm := CombatResolver.create_interactive_combat(
		_authority_seed, rng_cell, mname, start_hp_cm, role_cm, _server_stat_line_for_combat(sender)
	)
	_server_combat_by_peer[sender] = session_cm
	var snap_cm: Dictionary = session_cm._snapshot()
	snap_cm["cell_x"] = rng_cell.x
	snap_cm["cell_y"] = rng_cell.y
	_deliver_combat_snapshot_to_peer(sender, snap_cm)
	if session_cm.monster_turn_pending():
		_server_schedule_pending_monster_strike(sender)


func _server_handle_world_interaction(sender: int, cell: Vector2i) -> void:
	if not _player_positions.has(sender):
		print("[Dungeoneers] world_interaction rejected: unknown peer_id=", sender)
		return
	var revealed: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, revealed, true):
		print("[Dungeoneers] world_interaction rejected: fog peer_id=", sender, " cell=", cell)
		return
	var raw_tile: String = GridWalk.tile_at(_authority_grid, cell)
	var eff_tile: String = _authority_effective_tile(cell)
	var stand_kind := GridWalk.world_interaction_stand_kind(raw_tile)
	if stand_kind != "":
		var pos: Vector2i = _player_positions[sender]
		if pos != cell:
			print(
				"[Dungeoneers] world_interaction rejected: must stand on tile peer_id=",
				sender,
				" kind=",
				stand_kind,
				" cell=",
				cell
			)
			return
		var pack_s: Dictionary
		if (
			stand_kind == "food_pickup"
			or stand_kind == "healing_potion_pickup"
			or stand_kind == "torch_pickup"
			or stand_kind == "quest_item_pickup"
		):
			pack_s = _pickup_offer_payload(sender, cell, raw_tile)
			if pack_s.is_empty():
				return
		else:
			pack_s = _world_interaction_payload(stand_kind, raw_tile, eff_tile, cell)
		var send_stand: String = str(pack_s.get("kind", stand_kind))
		_deliver_world_interaction_to_peer(
			sender, send_stand, cell, str(pack_s["title"]), str(pack_s["message"])
		)
		print(
			"[Dungeoneers] world_interaction stand peer_id=",
			sender,
			" kind=",
			send_stand,
			" cell=",
			cell
		)
		return
	var remote_kind := GridWalk.world_interaction_remote_kind(eff_tile)
	if remote_kind != "":
		if not GridWalk.should_remote_world_interaction_click(
			_player_positions[sender], cell, remote_kind
		):
			print(
				"[Dungeoneers] world_interaction rejected: Explorer click routing peer_id=",
				sender,
				" cell=",
				cell,
				" kind=",
				remote_kind
			)
			return
		if remote_kind == "trapped_treasure":
			_server_handle_trapped_treasure_interaction(sender, cell)
			print(
				"[Dungeoneers] world_interaction remote peer_id=",
				sender,
				" kind=trapped_treasure_flow cell=",
				cell
			)
			return
		if remote_kind == "room_trap":
			_server_handle_room_trap_interaction(sender, cell)
			print(
				"[Dungeoneers] world_interaction remote peer_id=",
				sender,
				" kind=room_trap_flow cell=",
				cell
			)
			return
		var send_kind: String = remote_kind
		var pack_r: Dictionary
		if remote_kind == "encounter":
			var eb: Dictionary = _world_interaction_encounter_branch(sender, cell, eff_tile)
			send_kind = str(eb.get("kind", "encounter"))
			pack_r = {"title": str(eb.get("title", "")), "message": str(eb.get("message", ""))}
			if send_kind == "npc_quest_offer":
				var qv: Variant = eb.get("quest", null)
				if qv is Dictionary:
					_server_pending_npc_quest[sender] = {
						"cell": cell,
						"quest": (qv as Dictionary).duplicate(true),
					}
		else:
			pack_r = _world_interaction_payload(remote_kind, raw_tile, eff_tile, cell)
		_deliver_world_interaction_to_peer(
			sender, send_kind, cell, str(pack_r["title"]), str(pack_r["message"])
		)
		print(
			"[Dungeoneers] world_interaction remote peer_id=",
			sender,
			" kind=",
			send_kind,
			" cell=",
			cell
		)
		return
	push_warning(
		"[Dungeoneers] world_interaction: no handler for tile peer_id=",
		sender,
		" cell=",
		cell,
		" raw=",
		raw_tile
	)


func _server_clear_door_and_trap_state() -> void:
	_unlocked_doors.clear()
	_unpickable_doors.clear()
	_door_trap_checked.clear()
	_trap_disarm_pending.clear()
	_treasure_trap_disarm_pending.clear()
	_room_trap_disarm_pending.clear()
	_trap_defused_doors.clear()
	_clicked_fog_by_peer.clear()
	_revealed_secret_doors.clear()
	_authority_doors_broken_count = 0
	_authority_guards_hostile = false
	_broadcast_guards_hostile()


func _server_handle_map_transition_confirm(sender: int, kind: String, cell: Vector2i) -> void:
	if not _player_positions.has(sender):
		print("[Dungeoneers] map_transition rejected: unknown peer_id=", sender)
		return
	if kind != "stair" and kind != "waypoint" and kind != "map_link":
		return
	var pos: Vector2i = _player_positions[sender]
	if pos != cell:
		print("[Dungeoneers] map_transition rejected: not on tile peer_id=", sender, " cell=", cell)
		return
	var raw_tile: String = GridWalk.tile_at(_authority_grid, cell)
	if GridWalk.world_interaction_stand_kind(raw_tile) != kind:
		print("[Dungeoneers] map_transition rejected: tile kind mismatch peer_id=", sender)
		return
	var revealed: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(cell, revealed, true):
		print("[Dungeoneers] map_transition rejected: fog peer_id=", sender)
		return
	_server_apply_map_transition(kind, raw_tile, cell)
	print("[Dungeoneers] map_transition ok peer_id=", sender, " kind=", kind, " cell=", cell)


func _server_regenerate_slice_for_welcome() -> Dictionary:
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = _authority_seed
	if not _authority_theme_name.is_empty():
		var td: Dictionary = DungeonThemes.find_theme_by_name(_authority_theme_name)
		if not td.is_empty():
			return DungeonGenerator.generate_with_theme_data(
				rng2, td, _player_level, _dungeon_level
			)
	var tleg := _authority_theme
	if tleg != "up" and tleg != "down":
		tleg = "up"
	return TraditionalGen.generate(rng2, tleg)


func _server_apply_map_transition(
	kind: String, raw_tile: String, transition_cell: Vector2i
) -> void:
	_server_invalidate_monster_combat_delay_timers()
	for pm_pid in _player_positions.keys():
		_server_cancel_pending_path_move(int(pm_pid))
	var gen_before := _generation_type.strip_edges()
	var stored_map_link_theme := ""
	if kind == "map_link":
		stored_map_link_theme = (
			str(_server_map_link_destination_by_cell.get(transition_cell, "")).strip_edges()
		)
	var stored_waypoint_theme := ""
	if kind == "waypoint" and (gen_before == "city" or gen_before == "outdoor"):
		stored_waypoint_theme = (
			str(_server_waypoint_destination_by_cell.get(transition_cell, "")).strip_edges()
		)
	_server_map_link_destination_by_cell.clear()
	_server_waypoint_destination_by_cell.clear()
	var plan: Dictionary = {}
	if kind == "map_link" and not stored_map_link_theme.is_empty():
		var td_store: Dictionary = DungeonThemes.find_theme_by_name(stored_map_link_theme)
		if not td_store.is_empty():
			plan = {
				"theme_name": stored_map_link_theme,
				"dungeon_level":
				MapTransition.next_dungeon_level_after_theme_change(
					_authority_theme_name, stored_map_link_theme, _dungeon_level
				),
			}
	if (
		plan.is_empty()
		and kind == "waypoint"
		and (gen_before == "city" or gen_before == "outdoor")
		and not stored_waypoint_theme.is_empty()
	):
		var td_wp: Dictionary = DungeonThemes.find_theme_by_name(stored_waypoint_theme)
		if not td_wp.is_empty():
			plan = {
				"theme_name": stored_waypoint_theme,
				"dungeon_level":
				MapTransition.next_dungeon_level_after_theme_change(
					_authority_theme_name, stored_waypoint_theme, _dungeon_level
				),
			}
	if plan.is_empty():
		var plan_rng := RandomNumberGenerator.new()
		plan_rng.randomize()
		plan = MapTransition.compute_transition(
			kind, raw_tile, _authority_theme_name, _dungeon_level, plan_rng
		)
	if plan.is_empty():
		push_warning("[Dungeoneers] map_transition: planner returned empty")
		return
	var next_theme_name: String = str(plan.get("theme_name", "")).strip_edges()
	var next_dungeon_level: int = maxi(1, int(plan.get("dungeon_level", 1)))
	if next_theme_name.is_empty():
		return
	var theme_data: Dictionary = DungeonThemes.find_theme_by_name(next_theme_name)
	if theme_data.is_empty():
		push_warning("[Dungeoneers] map_transition: unknown theme ", next_theme_name)
		return
	_authority_recompute_player_level_from_party_xp()
	var grid_rng := RandomNumberGenerator.new()
	grid_rng.randomize()
	var new_seed: int = int(grid_rng.seed)
	grid_rng.seed = new_seed
	var gen: Dictionary = DungeonGenerator.generate_with_theme_data(
		grid_rng, theme_data, _player_level, next_dungeon_level
	)
	var new_grid: Dictionary = gen["grid"] as Dictionary
	var chk: int = TraditionalGen.grid_checksum(new_grid)
	_authority_seed = new_seed
	_authority_grid = new_grid
	_server_authority_tile_patches.clear()
	_live_tile_patch_rpc_pending.clear()
	_live_tile_patch_rpc_flush_queued = false
	_authority_checksum = chk
	_authority_theme_name = str(gen.get("theme", next_theme_name))
	_dungeon_level = next_dungeon_level
	_generation_type = str(gen.get("generation_type", _generation_type))
	var rm2: Variant = gen.get("rooms", [])
	if rm2 is Array:
		_authority_rooms = (rm2 as Array).duplicate()
	else:
		_authority_rooms.clear()
	var cr3: Variant = gen.get("corridors", [])
	if cr3 is Array:
		_authority_corridors = (cr3 as Array).duplicate()
	else:
		_authority_corridors.clear()
	var dir_raw := str(theme_data.get("direction", "up"))
	_authority_theme = dir_raw if (dir_raw == "up" or dir_raw == "down") else "up"
	_fog_type = DungeonFog.normalize_fog_type(str(gen.get("fog_type", _fog_type)))
	_fog_radius = DungeonFog.fog_radius_for_type(_fog_type)
	_torch_reveals_moves = _torch_reveals_moves or (_fog_type == "daylight")
	_server_clear_door_and_trap_state()
	var peer_ids: Array = _player_positions.keys()
	peer_ids.sort()
	var occupied: Array = []
	var new_positions: Dictionary = {}
	for pid in peer_ids:
		var sp: Vector2i = GridWalk.find_spawn_cell(_authority_grid, occupied)
		occupied.append(sp)
		new_positions[int(pid)] = sp
	for pid2 in peer_ids:
		var pidi := int(pid2)
		_player_positions[pidi] = new_positions[pidi]
		_server_npcs_killed_by_peer[pidi] = 0
		_init_peer_torch(pidi)
		if _fog_enabled:
			_seed_initial_fog_for_peer(pidi, _player_positions[pidi])
		else:
			_revealed_by_peer.erase(pidi)
	if _using_solo_local():
		_server_try_place_active_quest_items_for_all_peers()
		var slice: Dictionary = _server_regenerate_slice_for_welcome()
		var solo_cell: Vector2i = _player_positions[_solo_offline_peer]
		var fr := clampi(_fog_radius, 0, 8)
		var ft := DungeonFog.normalize_fog_type(_fog_type)
		var wel := {
			"schema_version": WELCOME_SCHEMA_VERSION,
			"assigned_slot": int(_peer_party_slots.get(_solo_offline_peer, 0)),
			"role": str(_peer_roles.get(_solo_offline_peer, "rogue")),
			"player_id": _solo_offline_peer,
			"spawn_x": solo_cell.x,
			"spawn_y": solo_cell.y,
			"fog_enabled": _fog_enabled,
			"fog_radius": fr,
			"fog_type": ft,
			"torch_reveals_moves": _torch_reveals_moves,
			"floor_theme": str(slice.get("floor_theme", "")),
			"wall_theme": str(slice.get("wall_theme", "")),
			"theme_name": _authority_theme_name,
			"dungeon_level": _dungeon_level,
			"authority_player_level": _player_level,
			"generation_type": str(slice.get("generation_type", "dungeon")),
			"rooms": slice.get("rooms", []),
			"corridors": slice.get("corridors", []),
			"road_theme": str(slice.get("road_theme", "")),
			"shrub_theme": str(slice.get("shrub_theme", "")),
			"display_name": _solo_cached_display_name,
			"peer_display_names": {_solo_offline_peer: _solo_cached_display_name},
			"listen_port": 0,
			"server_boot_unix_sec": 0,
			"party_peer_count": 1,
		}
		authority_dungeon_synchronized.emit(_authority_seed, _authority_theme, new_grid, wel)
		player_position_updated.emit(
			_solo_offline_peer,
			solo_cell,
			str(_peer_roles.get(_solo_offline_peer, "rogue")),
			_torch_burn_value(_solo_offline_peer)
		)
		_emit_stats_for_peer(_solo_offline_peer)
		_server_broadcast_special_items_to_peer(_solo_offline_peer)
		_server_broadcast_quests_to_peer(_solo_offline_peer)
		_server_broadcast_achievements_to_peer(_solo_offline_peer)
		return
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		for pid3 in peer_ids:
			var p3 := int(pid3)
			var role_w := str(_peer_roles.get(p3, _welcome_role_echo))
			var spawn_p: Vector2i = _player_positions[p3]
			var slot_p := int(_peer_party_slots.get(p3, 0))
			_rpc_receive_payload_to_peer(
				p3, slot_p, role_w, spawn_p, _authority_theme_name, _dungeon_level
			)
			_push_door_snapshots_to_peer(p3)
			_emit_stats_for_peer(p3)
			_server_broadcast_special_items_to_peer(p3)
			_server_broadcast_quests_to_peer(p3)
			_server_broadcast_achievements_to_peer(p3)
		_broadcast_all_positions()
		call_deferred("_server_try_place_active_quest_items_for_all_peers")
		var n_clients := multiplayer.get_peers().size()
		server_world_meta_changed.emit(
			_authority_seed,
			_authority_theme,
			_authority_checksum,
			_authority_theme_name,
			_dungeon_level,
			n_clients
		)


func _server_own_display_name_for_authority_rpc(peer_id: int) -> String:
	if _peer_display_names.has(peer_id):
		return str(_peer_display_names[peer_id])
	return JoinMetadata.display_name_for_network_peer("", peer_id)


func _server_peer_display_names_snapshot() -> Dictionary:
	var out: Dictionary = {}
	for pid in _player_positions:
		var id := int(pid)
		out[id] = _server_own_display_name_for_authority_rpc(id)
	return out


func _server_broadcast_peer_display_names_snapshot() -> void:
	if _using_solo_local():
		return
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var snap := _server_peer_display_names_snapshot()
	rpc_peer_display_names_snapshot.rpc(snap)


func _rpc_receive_payload_to_peer(
	peer_id: int,
	assigned_slot: int,
	role_for_welcome: String,
	spawn: Vector2i,
	theme_name: String,
	dungeon_level: int
) -> void:
	var own_dn := _server_own_display_name_for_authority_rpc(peer_id)
	var name_snap := _server_peer_display_names_snapshot()
	var party_n := _player_positions.size()
	if party_n < 1:
		party_n = 1
	var boot_sec := _server_boot_unix_sec
	if boot_sec <= 0:
		boot_sec = int(Time.get_unix_time_from_system())
	rpc_receive_authority_dungeon.rpc_id(
		peer_id,
		_authority_seed,
		_authority_theme,
		_authority_checksum,
		WELCOME_SCHEMA_VERSION,
		assigned_slot,
		role_for_welcome,
		spawn.x,
		spawn.y,
		_fog_enabled,
		_fog_radius,
		_fog_type,
		_torch_reveals_moves,
		theme_name,
		dungeon_level,
		_player_level,
		own_dn,
		name_snap,
		_server_listen_port,
		boot_sec,
		party_n
	)


func _broadcast_guards_hostile() -> void:
	_client_guards_hostile = _authority_guards_hostile
	guards_hostile_changed.emit(_authority_guards_hostile)
	if _using_solo_local():
		return
	if multiplayer.multiplayer_peer != null and multiplayer.is_server():
		rpc_guards_hostile_sync.rpc(_authority_guards_hostile)


func guards_hostile() -> bool:
	return _client_guards_hostile


func _push_door_snapshots_to_peer(peer_id: int) -> void:
	var unlocked_snap := PackedVector2Array()
	for k in _unlocked_doors:
		unlocked_snap.append(Vector2(k))
	rpc_unlocked_doors_snapshot.rpc_id(peer_id, unlocked_snap)
	var unpick_snap := PackedVector2Array()
	for k2 in _unpickable_doors:
		unpick_snap.append(Vector2(k2))
	rpc_unpickable_doors_snapshot.rpc_id(peer_id, unpick_snap)
	var trap_snap := PackedVector2Array()
	for kt in _door_trap_checked:
		trap_snap.append(Vector2(kt))
	rpc_trap_inspected_doors_snapshot.rpc_id(peer_id, trap_snap)
	var def_snap := PackedVector2Array()
	for kd in _trap_defused_doors:
		def_snap.append(Vector2(kd))
	rpc_trap_defused_doors_snapshot.rpc_id(peer_id, def_snap)
	var sec_snap := PackedVector2Array()
	for ks in _revealed_secret_doors:
		sec_snap.append(Vector2(ks))
	rpc_secret_doors_snapshot.rpc_id(peer_id, sec_snap)
	var click_snap := PackedVector2Array()
	for kc in _clicked_fog_for_peer(peer_id):
		click_snap.append(Vector2(kc))
	rpc_fog_clicked_cells_snapshot.rpc_id(peer_id, click_snap)


func _server_apply_unlock(cell: Vector2i) -> void:
	if _unlocked_doors.has(cell):
		return
	_unlocked_doors[cell] = true
	var one := PackedVector2Array()
	one.append(Vector2(cell))
	_notify_unlocked_doors_delta(one)


func _server_broadcast_trap_inspected(cell: Vector2i) -> void:
	var one := PackedVector2Array()
	one.append(Vector2(cell))
	_notify_trap_inspected_doors_delta(one)


func _dex_pick_bonus_for_peer(peer_id: int) -> int:
	return PlayerCombatStats.dex_pick_bonus_for_role(str(_peer_roles.get(peer_id, "rogue")))


func _roll_lock_pick(peer_id: int, cell: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	# Deterministic per dungeon + cell (not peer_id) so smoke seeds stay stable across ENet ids.
	rng.seed = int(_authority_seed) * 1103515245 ^ cell.x * 1013 ^ cell.y * 7919 ^ 2_463_136_393
	var d20: int = rng.randi_range(1, 20)
	var bonus: int = _dex_pick_bonus_for_peer(peer_id)
	var total: int = d20 + bonus
	return {"success": total >= 12, "d20": d20, "bonus": bonus, "total": total}


func _unlock_prompt_message(cell: Vector2i, peer_id: int) -> String:
	if _unpickable_doors.has(cell):
		return WorldLabelsMsg.door_location_fallback_body(
			"unpickable", _authority_theme_name, _authority_theme
		)
	var door_body := WorldLabelsMsg.door_location_fallback_body(
		"locked", _authority_theme_name, _authority_theme
	)
	var b: int = _dex_pick_bonus_for_peer(peer_id)
	return (
		door_body
		+ "\n\nPick the lock? Rolls d20 + DEX (bonus +"
		+ str(b)
		+ ") vs DC 12. Confirm to roll."
	)


func _server_apply_unpickable(cell: Vector2i) -> void:
	if _unpickable_doors.has(cell):
		return
	_unpickable_doors[cell] = true
	var one := PackedVector2Array()
	one.append(Vector2(cell))
	_notify_unpickable_doors_delta(one)


func _server_try_pick_unlock(sender: int, cell: Vector2i) -> void:
	var t: String = _authority_effective_tile(cell)
	if not GridWalk.is_locked_door_tile(t):
		print("[Dungeoneers] pick_unlock rejected: not locked tile=", t)
		return
	if _unlocked_doors.has(cell):
		print("[Dungeoneers] pick_unlock ignored: already unlocked ", cell)
		return
	if _unpickable_doors.has(cell):
		print("[Dungeoneers] pick_unlock rejected: unpickable cell=", cell)
		return
	var r: Dictionary = _roll_lock_pick(sender, cell)
	if bool(r["success"]):
		_server_apply_unlock(cell)
		_server_add_xp_with_level_up(sender, LOCK_PICK_XP)
		_emit_stats_for_peer(sender)
		print(
			"[Dungeoneers] lock_pick success peer_id=",
			sender,
			" cell=",
			cell,
			" d20=",
			r["d20"],
			" bonus=",
			r["bonus"],
			" total=",
			r["total"],
			" xp+=",
			LOCK_PICK_XP
		)
		print("[Dungeoneers] door unlock accepted peer_id=", sender, " cell=", cell)
	else:
		_server_apply_unpickable(cell)
		print(
			"[Dungeoneers] lock_pick failed peer_id=",
			sender,
			" cell=",
			cell,
			" d20=",
			r["d20"],
			" bonus=",
			r["bonus"],
			" total=",
			r["total"],
			" (DC 12)"
		)


func _server_handle_request_move(sender: int, target: Vector2i) -> void:
	if not _player_positions.has(sender):
		push_warning("[Dungeoneers] move rejected: unknown peer_id=", sender)
		return
	_server_try_adjacent_move(sender, target)


func _server_handle_fog_square_click(sender: int, cell: Vector2i) -> void:
	if (
		not _using_solo_local()
		and (multiplayer.multiplayer_peer == null or not multiplayer.is_server())
	):
		return
	if not _player_positions.has(sender):
		push_warning("[Dungeoneers] fog_square_click rejected: unknown peer_id=", sender)
		return
	if not _fog_enabled:
		return
	if (
		cell.x < 0
		or cell.y < 0
		or cell.x >= DungeonGrid.MAP_WIDTH
		or cell.y >= DungeonGrid.MAP_HEIGHT
	):
		return
	var player_cell: Vector2i = _player_positions[sender]
	var revealed: Dictionary = _revealed_for_peer(sender)
	var fr: int = clampi(_fog_radius, 0, 8)
	if not DungeonFog.can_reveal_fog_click_cell(cell, revealed, true, player_cell, fr):
		print("[Dungeoneers] fog_square_click rejected peer_id=", sender, " cell=", cell)
		return
	var clk: Dictionary = _clicked_fog_for_peer(sender)
	var click_delta := PackedVector2Array()
	if not clk.has(cell):
		clk[cell] = true
		click_delta.append(Vector2(cell))
	var fog_delta := PackedVector2Array()
	if not revealed.has(cell):
		var r_disk: int = clampi(_fog_radius, 0, 8)
		for c in DungeonFog.disk_cells(cell, r_disk):
			if not revealed.has(c):
				revealed[c] = true
				fog_delta.append(Vector2(c))
		DungeonFog.append_area_label_cells_into_delta(
			revealed, _authority_grid, cell, _authority_rooms, _authority_corridors, fog_delta
		)
	if not fog_delta.is_empty():
		_notify_client_fog_delta(sender, fog_delta)
	if not click_delta.is_empty():
		_notify_client_fog_clicked_delta(sender, click_delta)
	if not fog_delta.is_empty() or not click_delta.is_empty():
		print("[Dungeoneers] fog_square_click ok peer_id=", sender, " cell=", cell)


## Validates a client path (fog sim only; torch ticks on real `_apply_authorized_move` per step). Returns
## `steps` cells to walk in order, and optional `door_after` when the path stops before a locked door.
func _server_validate_path_move_build(sender: int, path: PackedVector2Array) -> Dictionary:
	var out: Dictionary = {"ok": false}
	if not _player_positions.has(sender):
		return out
	if path.is_empty():
		return out
	var cur: Vector2i = _player_positions[sender]
	var sim_r: Dictionary = {}
	for k in _revealed_for_peer(sender):
		sim_r[k] = true
	var steps: Array[Vector2i] = []
	var door_after: Variant = null
	for i in range(path.size()):
		var target := Vector2i(int(path[i].x), int(path[i].y))
		if not GridWalk.is_orthogonal_adjacent(cur, target):
			print(
				"[Dungeoneers] path move rejected: not orthogonally adjacent peer_id=",
				sender,
				" step=",
				i,
				" from=",
				cur,
				" to=",
				target
			)
			return out
		if _fog_enabled and not DungeonFog.square_revealed(target, sim_r, true):
			print(
				"[Dungeoneers] path move rejected: fog peer_id=",
				sender,
				" step=",
				i,
				" to=",
				target
			)
			return out
		var step_tile: String = _authority_effective_tile(target)
		if GridWalk.is_locked_door_tile(step_tile) and not _unlocked_doors.has(target):
			door_after = target
			break
		if not GridWalk.is_walkable_for_movement_at(
			step_tile, target, _unlocked_doors, _authority_guards_hostile
		):
			print(
				"[Dungeoneers] path move rejected: not walkable peer_id=",
				sender,
				" step=",
				i,
				" tile=",
				step_tile
			)
			return out
		if _cell_occupied_by_other(sender, target):
			print("[Dungeoneers] path move rejected: occupied peer_id=", sender, " step=", i)
			return out
		steps.append(target)
		cur = target
		if _fog_enabled and _torch_should_expand_fog(sender):
			var r_path: int = _move_fog_reveal_radius()
			DungeonFog.reveal_chebyshev_disk_into(sim_r, target, r_path)
	out["ok"] = true
	out["steps"] = steps
	out["door_after"] = door_after
	return out


func _server_schedule_path_move_tick(sender: int, serial: int) -> void:
	if not is_inside_tree():
		return
	var d := _path_move_step_delay_sec()
	if d <= 0.0:
		call_deferred("_server_path_move_tick", sender, serial)
		return
	var delay_timer := get_tree().create_timer(d, false, false)
	delay_timer.timeout.connect(func() -> void: _server_path_move_tick(sender, serial))


func _server_path_move_tick(sender: int, serial: int) -> void:
	if not is_instance_valid(self):
		return
	if int(_path_move_serial_by_peer.get(sender, 0)) != serial:
		return
	if not _player_positions.has(sender):
		return
	if _server_peer_movement_blocked(sender):
		_server_cancel_pending_path_move(sender)
		return
	var q: Variant = _path_move_queue_by_peer.get(sender, null)
	if q == null or (q is Array and (q as Array).is_empty()):
		if _path_move_door_after_by_peer.has(sender):
			var dc: Vector2i = _path_move_door_after_by_peer[sender]
			_path_move_door_after_by_peer.erase(sender)
			_path_move_queue_by_peer.erase(sender)
			_server_handle_door_click(sender, dc)
		return
	var arr: Array = q as Array
	var raw0: Variant = arr[0]
	var nxt: Vector2i
	if raw0 is Vector2i:
		nxt = raw0 as Vector2i
	elif raw0 is Vector2:
		var w0 := raw0 as Vector2
		nxt = Vector2i(int(w0.x), int(w0.y))
	else:
		_server_cancel_pending_path_move(sender)
		return
	var cur: Vector2i = _player_positions[sender]
	if not GridWalk.is_orthogonal_adjacent(cur, nxt):
		print("[Dungeoneers] path move aborted: not orthogonally adjacent peer_id=", sender)
		_server_cancel_pending_path_move(sender)
		return
	var revealed: Dictionary = _revealed_for_peer(sender)
	if _fog_enabled and not DungeonFog.square_revealed(nxt, revealed, true):
		print("[Dungeoneers] path move aborted: fog peer_id=", sender)
		_server_cancel_pending_path_move(sender)
		return
	if _cell_occupied_by_other(sender, nxt):
		print("[Dungeoneers] path move aborted: occupied peer_id=", sender)
		_server_cancel_pending_path_move(sender)
		return
	var step_was_last: bool = arr.size() == 1
	if step_was_last and _server_try_deliver_direct_encounter_before_move(sender, cur, nxt):
		_server_cancel_pending_path_move(sender)
		return
	var move_tile: String = _authority_effective_tile(nxt)
	if not GridWalk.is_walkable_for_movement_at(
		move_tile, nxt, _unlocked_doors, _authority_guards_hostile
	):
		print("[Dungeoneers] path move aborted: not walkable peer_id=", sender)
		_server_cancel_pending_path_move(sender)
		return
	arr.remove_at(0)
	_apply_authorized_move(sender, nxt, step_was_last)
	if _server_peer_movement_blocked(sender):
		_server_cancel_pending_path_move(sender)
		return
	if arr.is_empty():
		_path_move_queue_by_peer.erase(sender)
		if _path_move_door_after_by_peer.has(sender):
			var dc2: Vector2i = _path_move_door_after_by_peer[sender]
			_path_move_door_after_by_peer.erase(sender)
			_server_handle_door_click(sender, dc2)
		return
	_path_move_queue_by_peer[sender] = arr
	_server_schedule_path_move_tick(sender, serial)


func _server_begin_authorized_path_walk(
	sender: int, all_steps: Array[Vector2i], door_after: Variant
) -> void:
	var serial := int(_path_move_serial_by_peer.get(sender, 0))
	if all_steps.is_empty():
		if door_after != null and door_after is Vector2i:
			var d0 := door_after as Vector2i
			print("[Dungeoneers] path move accepted peer_id=", sender, " steps=0 door=", d0)
			_server_handle_door_click(sender, d0)
		return
	var rest: Array[Vector2i] = all_steps.duplicate()
	var first: Vector2i = rest.pop_front()
	var single_step_path: bool = all_steps.size() == 1
	if single_step_path:
		var cur_path: Vector2i = _player_positions[sender]
		if not _cell_occupied_by_other(sender, first):
			if _server_try_deliver_direct_encounter_before_move(sender, cur_path, first):
				print(
					"[Dungeoneers] path move intercepted at encounter peer_id=",
					sender,
					" cell=",
					first
				)
				return
	_apply_authorized_move(sender, first, single_step_path)
	if _server_peer_movement_blocked(sender):
		_server_cancel_pending_path_move(sender)
		return
	if rest.is_empty():
		if door_after != null and door_after is Vector2i:
			_server_handle_door_click(sender, door_after as Vector2i)
		print("[Dungeoneers] path move accepted peer_id=", sender, " dst=", first)
		return
	_path_move_queue_by_peer[sender] = rest
	if door_after != null and door_after is Vector2i:
		_path_move_door_after_by_peer[sender] = door_after as Vector2i
	print("[Dungeoneers] path move accepted peer_id=", sender, " steps=", all_steps.size())
	_server_schedule_path_move_tick(sender, serial)


func _server_handle_path_move(sender: int, path: PackedVector2Array) -> void:
	if not _player_positions.has(sender):
		push_warning("[Dungeoneers] path move rejected: unknown peer_id=", sender)
		return
	if path.is_empty():
		return
	if _server_peer_movement_blocked(sender):
		print("[Dungeoneers] path move rejected: in combat peer_id=", sender)
		return
	_server_cancel_pending_path_move(sender)
	var built: Dictionary = _server_validate_path_move_build(sender, path)
	if not bool(built.get("ok", false)):
		return
	var steps_raw: Variant = built.get("steps", null)
	var steps: Array[Vector2i] = []
	if steps_raw is Array:
		for s in steps_raw as Array:
			if s is Vector2i:
				steps.append(s as Vector2i)
			elif s is Vector2:
				var v2 := s as Vector2
				steps.append(Vector2i(int(v2.x), int(v2.y)))
			else:
				steps.append(Vector2i(int(s.x), int(s.y)))
	var door_after: Variant = built.get("door_after", null)
	_server_begin_authorized_path_walk(sender, steps, door_after)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_move(target_x: int, target_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_server_handle_request_move(sender, Vector2i(target_x, target_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_path_move(path: PackedVector2Array) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_server_handle_path_move(sender, path)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_fog_square_click(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_server_handle_fog_square_click(sender, Vector2i(cell_x, cell_y))


@rpc("authority", "call_remote", "reliable")
func rpc_fog_reveal_delta(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_revealed[vi] = true
	fog_reveal_delta.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_fog_reveal_delta_packed(data: PackedByteArray) -> void:
	if multiplayer.is_server():
		return
	var cells := DungeonFog.unpack_fog_delta_cells(data)
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_revealed[vi] = true
	fog_reveal_delta.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_fog_full_resync(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	_client_revealed.clear()
	for i in range(cells.size()):
		var vi2 := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_revealed[vi2] = true
	fog_full_resync.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_fog_clicked_cells_delta(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_fog_clicked[vi] = true
	fog_clicked_cells_delta.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_fog_clicked_cells_snapshot(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	_client_fog_clicked.clear()
	for j in range(cells.size()):
		var vj := Vector2i(int(cells[j].x), int(cells[j].y))
		_client_fog_clicked[vj] = true
	fog_clicked_cells_snapshot.emit(cells)


func _server_chain_after_trap_survey(
	sender: int, cell: Vector2i, flavor_prefix: String = ""
) -> void:
	var t: String = _authority_effective_tile(cell)
	var lead := ""
	if not flavor_prefix.is_empty():
		lead = flavor_prefix + "\n\n"
	if GridWalk.is_locked_door_tile(t) and not _unlocked_doors.has(cell):
		_deliver_door_prompt_to_peer(
			sender, "unlock", cell, lead + _unlock_prompt_message(cell, sender)
		)
	elif t == "trapped_door":
		var pass_body := WorldLabelsMsg.door_location_fallback_body(
			"open", _authority_theme_name, _authority_theme
		)
		_deliver_door_prompt_to_peer(sender, "pass", cell, lead + pass_body)
	else:
		push_warning("[Dungeoneers] trap chain: unexpected tile=", t)


func _server_handle_unlock_door(sender: int, cell: Vector2i) -> void:
	if not _server_door_click_valid(sender, cell):
		return
	var t: String = _authority_effective_tile(cell)
	if not GridWalk.is_locked_door_tile(t):
		print("[Dungeoneers] unlock rejected: not locked door tile=", t, " at=", cell)
		return
	if _unlocked_doors.has(cell):
		print("[Dungeoneers] unlock ignored: already unlocked ", cell)
		return
	_server_apply_unlock(cell)
	print("[Dungeoneers] door unlock accepted peer_id=", sender, " cell=", cell)


## Explorer `attempt_trap_detection` — roll immediately on door click (no separate survey confirm).
func _server_roll_door_trap_detection(sender: int, cell: Vector2i, _raw_t: String) -> void:
	var rng_t := _rng_door_cell(sender, cell, 31)
	var det: int = rng_t.randi_range(1, 20)
	_door_trap_checked[cell] = true
	_server_broadcast_trap_inspected(cell)
	if det >= DOOR_TRAP_DETECT_DC:
		_trap_disarm_pending[cell] = true
		_deliver_door_prompt_to_peer(
			sender,
			"trap_detected",
			cell,
			(
				"You notice something suspicious about this door - there appears to be a trap mechanism! "
				+ "(Detected with roll "
				+ str(det)
				+ " vs DC "
				+ str(DOOR_TRAP_DETECT_DC)
				+ ")\n\nWhat would you like to do?"
			)
		)
	else:
		var dmg: int = rng_t.randi_range(1, 2)
		var msg_bad := (
			"You failed to spot the trap in time! (Detection roll "
			+ str(det)
			+ " vs DC "
			+ str(DOOR_TRAP_DETECT_DC)
			+ ")\n\nA needle snicks out — you take "
			+ str(dmg)
			+ " damage."
		)
		var hp_survey: int = _server_apply_hp_damage_to_peer(sender, dmg)
		if hp_survey <= 0:
			_deliver_encounter_resolution_to_peer(sender, "Trap triggered", msg_bad)
			_deliver_encounter_resolution_to_peer(
				sender, "Death", "The poison runs cold — you collapse."
			)
		else:
			_deliver_door_prompt_to_peer(sender, "trap_sprung", cell, msg_bad)
	print("[Dungeoneers] trap survey peer_id=", sender, " cell=", cell, " det_roll=", det)


func _server_handle_door_click(sender: int, cell: Vector2i) -> void:
	if not _server_door_click_valid(sender, cell):
		return
	var raw_t: String = GridWalk.tile_at(_authority_grid, cell)
	var t: String = _authority_effective_tile(cell)
	if _trap_disarm_pending.has(cell):
		_deliver_door_prompt_to_peer(
			sender,
			"trap_detected",
			cell,
			"You spotted a trap on this door earlier.\n\nWhat would you like to do?"
		)
		print("[Dungeoneers] door_click re-offer trap_detected peer_id=", sender, " cell=", cell)
		return
	if (
		_unpickable_doors.has(cell)
		and GridWalk.is_locked_door_tile(t)
		and not _unlocked_doors.has(cell)
	):
		var break_lead := WorldLabelsMsg.door_location_fallback_body(
			"unpickable", _authority_theme_name, _authority_theme
		)
		_deliver_door_prompt_to_peer(
			sender,
			"break_door",
			cell,
			(
				break_lead
				+ "\n\nTry to break it down? Rolls d20 vs DC "
				+ str(BREAK_DOOR_DC)
				+ ". Confirm to roll."
			)
		)
		print("[Dungeoneers] door_click offer break_door peer_id=", sender, " cell=", cell)
		return
	if (
		GridWalk.is_trapped_door_tile(raw_t)
		and not _trap_defused_doors.has(cell)
		and not _door_trap_checked.has(cell)
	):
		_server_roll_door_trap_detection(sender, cell, raw_t)
		return
	if GridWalk.is_locked_door_tile(t) and not _unlocked_doors.has(cell):
		_deliver_door_prompt_to_peer(sender, "unlock", cell, _unlock_prompt_message(cell, sender))
		print("[Dungeoneers] door_click offer unlock peer_id=", sender, " cell=", cell)
		return
	if GridWalk.is_walkable_for_movement_at(t, cell, _unlocked_doors, _authority_guards_hostile):
		var pass_open := WorldLabelsMsg.door_location_fallback_body(
			"open", _authority_theme_name, _authority_theme
		)
		_deliver_door_prompt_to_peer(sender, "pass", cell, pass_open)
		print("[Dungeoneers] door_click offer pass peer_id=", sender, " cell=", cell)
		return
	push_warning("[Dungeoneers] door_click: unexpected tile=", t, " at=", cell)


func _server_handle_door_confirm(sender: int, action: String, cell: Vector2i) -> void:
	if action != "blocked" and not _server_door_click_valid(sender, cell):
		print("[Dungeoneers] door_confirm rejected peer_id=", sender, " cell=", cell)
		return
	var raw_t: String = GridWalk.tile_at(_authority_grid, cell)
	var t: String = _authority_effective_tile(cell)
	if action == "blocked":
		return
	if action == "trap_skip_disarm":
		if not _trap_disarm_pending.has(cell):
			print("[Dungeoneers] trap_skip_disarm rejected: not pending cell=", cell)
			return
		_trap_disarm_pending.erase(cell)
		_door_trap_checked.erase(cell)
		var rm_inspected := PackedVector2Array()
		rm_inspected.append(Vector2(cell))
		_notify_trap_inspected_doors_remove_delta(rm_inspected)
		print("[Dungeoneers] trap_skip_disarm peer_id=", sender, " cell=", cell)
		return
	if action == "trap_disarm_ack":
		if not _door_trap_checked.has(cell) or _trap_disarm_pending.has(cell):
			print("[Dungeoneers] trap_disarm_ack rejected cell=", cell)
			return
		if not _trap_defused_doors.has(cell):
			print("[Dungeoneers] trap_disarm_ack rejected: trap not defused cell=", cell)
			return
		_server_chain_after_trap_survey(sender, cell, "")
		return
	if action == "trap_disarm":
		if not _trap_disarm_pending.has(cell):
			print("[Dungeoneers] trap_disarm rejected: not pending cell=", cell)
			return
		if not GridWalk.is_trapped_door_tile(raw_t):
			print("[Dungeoneers] trap_disarm rejected: raw tile=", raw_t)
			return
		_trap_disarm_pending.erase(cell)
		var r_dis := _roll_trap_disarm(sender, cell)
		var bonus: int = int(r_dis["bonus"])
		var d20v: int = int(r_dis["d20"])
		var tot: int = int(r_dis["total"])
		var dmg: int = int(r_dis["dmg"])
		if bool(r_dis["ok"]):
			_server_apply_trap_defused(cell)
			_server_add_xp_with_level_up(sender, TRAP_DISARM_XP_TREASURE)
			_emit_stats_for_peer(sender)
			_deliver_door_prompt_to_peer(
				sender,
				"trap_disarm_result",
				cell,
				(
					"You successfully disarm the trap!\n(Rolled "
					+ str(d20v)
					+ " + "
					+ str(bonus)
					+ " dexterity = "
					+ str(tot)
					+ " vs DC "
					+ str(TRAP_DISARM_DC)
					+ ")\n\nThe trap is now safe to pass.\n\nYou gain "
					+ str(TRAP_DISARM_XP_TREASURE)
					+ " XP."
				)
			)
			print("[Dungeoneers] trap disarm success peer_id=", sender, " cell=", cell)
		else:
			## Explorer `handle_failed_trap_disarm`: remove trap, apply `TrapSystem` damage, then dialog.
			_server_apply_trap_defused(cell)
			var fail_msg := (
				"You fail to disarm the trap and trigger it!\n(Rolled "
				+ str(d20v)
				+ " + "
				+ str(bonus)
				+ " dexterity = "
				+ str(tot)
				+ " vs DC "
				+ str(TRAP_DISARM_DC)
				+ ")\n\nYou take "
				+ str(dmg)
				+ " damage."
			)
			var hp_after: int = _server_apply_hp_damage_to_peer(sender, dmg)
			if hp_after <= 0:
				_deliver_encounter_resolution_to_peer(sender, "Trap triggered", fail_msg)
				_deliver_encounter_resolution_to_peer(
					sender, "Death", "The mechanism bites deep — you collapse."
				)
			else:
				_deliver_door_prompt_to_peer(sender, "trap_disarm_result", cell, fail_msg)
			print(
				"[Dungeoneers] trap disarm fail peer_id=",
				sender,
				" cell=",
				cell,
				" dmg=",
				dmg,
				" hp=",
				hp_after
			)
		return
	if action == "trap_sprung_ack":
		if not _door_trap_checked.has(cell):
			print("[Dungeoneers] trap_sprung_ack rejected: trap not surveyed cell=", cell)
			return
		_server_chain_after_trap_survey(sender, cell, "")
		return
	if action == "break_door":
		if not GridWalk.is_locked_door_tile(t):
			print("[Dungeoneers] break_door rejected: not locked tile=", t)
			return
		if not _unpickable_doors.has(cell) or _unlocked_doors.has(cell):
			print("[Dungeoneers] break_door rejected: not unpickable locked door cell=", cell)
			return
		var rng_br := _rng_door_cell(sender, cell, 77)
		var br: int = rng_br.randi_range(1, 20)
		var broke_ok := br >= BREAK_DOOR_DC
		if broke_ok:
			_unpickable_doors.erase(cell)
			_broadcast_unpickable_snapshot()
			_server_apply_unlock(cell)
			_authority_doors_broken_count += 1
			var guard_alert := ""
			if _authority_doors_broken_count == 1 and not _authority_guards_hostile:
				_authority_guards_hostile = true
				guard_alert = "\n\nThe racket alerts nearby guards — they are now hostile toward you."
				print("[Dungeoneers] guards_hostile=true reason=door_breaking peer_id=", sender)
				_broadcast_guards_hostile()
			_server_add_xp_with_level_up(sender, BREAK_DOOR_XP)
			_emit_stats_for_peer(sender)
			_deliver_door_prompt_to_peer(
				sender,
				"break_result",
				cell,
				(
					"You break down the door with force!\n(Rolled "
					+ str(br)
					+ " vs DC "
					+ str(BREAK_DOOR_DC)
					+ ")\n\nThe loud crash echoes through the dungeon. The door is now unlocked."
					+ guard_alert
				)
			)
			print(
				"[Dungeoneers] break_door success peer_id=",
				sender,
				" cell=",
				cell,
				" roll=",
				br,
				" xp+=",
				BREAK_DOOR_XP
			)
		else:
			_deliver_door_prompt_to_peer(
				sender,
				"break_result",
				cell,
				(
					"You fail to break down the door.\n(Rolled "
					+ str(br)
					+ " vs DC "
					+ str(BREAK_DOOR_DC)
					+ ")\n\nDespite the noise, the door remains locked."
				)
			)
			print("[Dungeoneers] break_door fail peer_id=", sender, " cell=", cell, " roll=", br)
		return
	if action == "unlock":
		if not GridWalk.is_locked_door_tile(t):
			print("[Dungeoneers] door_confirm unlock rejected: not locked tile=", t)
			return
		if _unlocked_doors.has(cell):
			print("[Dungeoneers] door_confirm unlock ignored: already unlocked ", cell)
			return
		_server_try_pick_unlock(sender, cell)
		return
	if action == "pass":
		if _server_try_adjacent_move(sender, cell):
			print("[Dungeoneers] door_confirm pass peer_id=", sender, " cell=", cell)
		else:
			print("[Dungeoneers] door_confirm pass rejected peer_id=", sender, " cell=", cell)
		return
	print("[Dungeoneers] door_confirm rejected: unknown action=", action)


## Dev / headless bypass: instant unlock without DC 12 roll (Explorer `door_confirm` uses pick_lock).
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_unlock_door(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_server_handle_unlock_door(sender, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_door_click(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_server_handle_door_click(sender, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_door_confirm(action: String, cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_server_handle_door_confirm(sender, action, Vector2i(cell_x, cell_y))


@rpc("authority", "call_remote", "reliable")
func rpc_door_prompt(action: String, cell_x: int, cell_y: int, message: String) -> void:
	if multiplayer.is_server():
		return
	door_prompt_offered.emit(action, Vector2i(cell_x, cell_y), message)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_world_interaction(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_server_handle_world_interaction(sender, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_map_transition_confirm(kind: String, cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_server_handle_map_transition_confirm(sender, kind, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_treasure_dismiss(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sender2 := multiplayer.get_remote_sender_id()
	if sender2 == 0:
		return
	_server_handle_treasure_dismiss(sender2, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_pickup_dismiss(kind: String, cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_pk := multiplayer.get_remote_sender_id()
	if sender_pk == 0:
		return
	_server_handle_pickup_dismiss(sender_pk, kind, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_use_healing_potion() -> void:
	if not multiplayer.is_server():
		return
	var sender_ph := multiplayer.get_remote_sender_id()
	if sender_ph == 0:
		return
	_server_handle_use_healing_potion(sender_ph)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_room_trap_undetected_ack(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var s_rt1 := multiplayer.get_remote_sender_id()
	if s_rt1 == 0:
		return
	_server_handle_room_trap_undetected_ack(s_rt1, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_room_trap_skip_disarm(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var s_rt2 := multiplayer.get_remote_sender_id()
	if s_rt2 == 0:
		return
	_server_handle_room_trap_skip_disarm(s_rt2, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_room_trap_disarm(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var s_rt3 := multiplayer.get_remote_sender_id()
	if s_rt3 == 0:
		return
	_server_handle_room_trap_disarm(s_rt3, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_rumor_dismiss() -> void:
	if not multiplayer.is_server():
		return
	var s_rm := multiplayer.get_remote_sender_id()
	if s_rm == 0:
		return
	_server_handle_rumor_dismiss(s_rm)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_special_item_dismiss() -> void:
	if not multiplayer.is_server():
		return
	var s_si := multiplayer.get_remote_sender_id()
	if s_si == 0:
		return
	_server_handle_special_item_dismiss(s_si)


func client_request_trapped_treasure_undetected_ack(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_trapped_treasure_undetected_ack(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_trapped_treasure_undetected_ack.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_trapped_treasure_skip_disarm(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_trapped_treasure_skip_disarm(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_trapped_treasure_skip_disarm.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_trapped_treasure_disarm(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_trapped_treasure_disarm(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_trapped_treasure_disarm.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_feature_investigate(cell_x: int, cell_y: int) -> void:
	if _using_solo_local():
		_server_handle_feature_investigate(_solo_offline_peer, Vector2i(cell_x, cell_y))
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_feature_investigate.rpc_id(SERVER_PEER_ID, cell_x, cell_y)


func client_request_feature_trap_dismiss() -> void:
	if _using_solo_local():
		_server_handle_feature_trap_dismiss(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_feature_trap_dismiss.rpc_id(SERVER_PEER_ID)


func client_request_feature_ambush_ack() -> void:
	if _using_solo_local():
		_server_handle_feature_ambush_ack(_solo_offline_peer)
		return
	if multiplayer.is_server():
		return
	if multiplayer.multiplayer_peer == null:
		return
	rpc_request_feature_ambush_ack.rpc_id(SERVER_PEER_ID)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_trapped_treasure_undetected_ack(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var s4 := multiplayer.get_remote_sender_id()
	if s4 == 0:
		return
	_server_handle_trapped_treasure_undetected_ack(s4, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_trapped_treasure_skip_disarm(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var s5 := multiplayer.get_remote_sender_id()
	if s5 == 0:
		return
	_server_handle_trapped_treasure_skip_disarm(s5, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_trapped_treasure_disarm(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var s6 := multiplayer.get_remote_sender_id()
	if s6 == 0:
		return
	_server_handle_trapped_treasure_disarm(s6, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_feature_investigate(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var s7 := multiplayer.get_remote_sender_id()
	if s7 == 0:
		return
	_server_handle_feature_investigate(s7, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_feature_trap_dismiss() -> void:
	if not multiplayer.is_server():
		return
	var s_trap := multiplayer.get_remote_sender_id()
	if s_trap == 0:
		return
	_server_handle_feature_trap_dismiss(s_trap)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_feature_ambush_ack() -> void:
	if not multiplayer.is_server():
		return
	var s_amb := multiplayer.get_remote_sender_id()
	if s_amb == 0:
		return
	_server_handle_feature_ambush_ack(s_amb)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_encounter_fight(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var sf := multiplayer.get_remote_sender_id()
	if sf == 0:
		return
	_server_handle_encounter_fight(sf, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_encounter_evade(cell_x: int, cell_y: int) -> void:
	if not multiplayer.is_server():
		return
	var se := multiplayer.get_remote_sender_id()
	if se == 0:
		return
	_server_handle_encounter_evade(se, Vector2i(cell_x, cell_y))


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_npc_quest_accept() -> void:
	if not multiplayer.is_server():
		return
	var sq := multiplayer.get_remote_sender_id()
	if sq == 0:
		return
	_server_handle_npc_quest_accept(sq)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_npc_quest_decline() -> void:
	if not multiplayer.is_server():
		return
	var sd := multiplayer.get_remote_sender_id()
	if sd == 0:
		return
	_server_handle_npc_quest_decline(sd)


@rpc("authority", "call_remote", "reliable")
func rpc_encounter_resolution(title: String, message: String) -> void:
	if multiplayer.is_server():
		return
	encounter_resolution_dialog.emit(title, message)


@rpc("authority", "call_remote", "reliable")
func rpc_guards_hostile_sync(hostile: bool) -> void:
	if multiplayer.is_server():
		return
	_client_guards_hostile = hostile
	guards_hostile_changed.emit(hostile)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_combat_player_attack() -> void:
	if not multiplayer.is_server():
		return
	var sa := multiplayer.get_remote_sender_id()
	if sa == 0:
		return
	_server_handle_combat_player_attack(sa)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_combat_flee() -> void:
	if not multiplayer.is_server():
		return
	var sf := multiplayer.get_remote_sender_id()
	if sf == 0:
		return
	_server_handle_combat_flee(sf)


@rpc("authority", "call_remote", "reliable")
func rpc_combat_state(snapshot: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_last_combat_snapshot = snapshot.duplicate(true)
	combat_state_changed.emit(snapshot)


@rpc("authority", "call_remote", "reliable")
func rpc_authority_tile_patch(cx: int, cy: int, new_tile: String) -> void:
	if multiplayer.is_server():
		return
	var patch_cell := Vector2i(cx, cy)
	_client_merged_grid[patch_cell] = new_tile
	authority_tile_patched.emit(patch_cell, new_tile)


@rpc("authority", "call_remote", "reliable")
func rpc_authority_tile_patch_batch(packed: PackedByteArray) -> void:
	if multiplayer.is_server():
		return
	var lst: Array = GridTilePatchCodec.unpack_patches(packed)
	if lst.is_empty() and not packed.is_empty():
		push_error("[Dungeoneers] rpc_authority_tile_patch_batch: unpack failed")
		return
	for e in lst:
		if not e is Dictionary:
			continue
		var d: Dictionary = e as Dictionary
		var cvar: Variant = d.get("cell", Vector2i(-1, -1))
		if not cvar is Vector2i:
			continue
		var pc: Vector2i = cvar as Vector2i
		var nt: String = str(d.get("tile", ""))
		_client_merged_grid[pc] = nt
		authority_tile_patched.emit(pc, nt)


@rpc("authority", "call_remote", "reliable")
func rpc_player_local_stats(
	gold: int,
	xp: int,
	hp: int,
	max_hp: int,
	torch_burn_pct: int,
	torch_spares: int,
	level: int,
	xp_to_next: int,
	player_alignment: int,
	npcs_killed: int,
	healing_potion_count: int,
	armor_class: int,
	attack_bonus: int,
	weapon_name: String,
	weapon_damage_dice: String
) -> void:
	if multiplayer.is_server():
		return
	player_local_stats_changed.emit(
		gold,
		xp,
		hp,
		max_hp,
		torch_burn_pct,
		torch_spares,
		level,
		xp_to_next,
		player_alignment,
		npcs_killed,
		healing_potion_count,
		armor_class,
		attack_bonus,
		weapon_name,
		weapon_damage_dice
	)


@rpc("authority", "call_remote", "reliable")
func rpc_world_interaction_offer(
	kind: String, cell_x: int, cell_y: int, title: String, message: String
) -> void:
	if multiplayer.is_server():
		return
	world_interaction_offered.emit(kind, Vector2i(cell_x, cell_y), title, message)


@rpc("authority", "call_remote", "reliable")
func rpc_player_rumors(rumors: PackedStringArray) -> void:
	if multiplayer.is_server():
		return
	player_rumors_updated.emit(rumors)


@rpc("authority", "call_remote", "reliable")
func rpc_player_special_items(keys: PackedStringArray) -> void:
	if multiplayer.is_server():
		return
	player_special_items_updated.emit(keys)


@rpc("authority", "call_remote", "reliable")
func rpc_player_quests(quest_rows: PackedStringArray) -> void:
	if multiplayer.is_server():
		return
	player_quests_updated.emit(quest_rows)


@rpc("authority", "call_remote", "reliable")
func rpc_player_achievements(lines: PackedStringArray) -> void:
	if multiplayer.is_server():
		return
	player_achievements_updated.emit(lines)


@rpc("authority", "call_remote", "reliable")
func rpc_level_up_dialog(new_level: int, primary_message: String, talent_message: String) -> void:
	if multiplayer.is_server():
		return
	level_up_dialog_offered.emit(new_level, primary_message, talent_message)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_level_up_dismiss() -> void:
	if not multiplayer.is_server():
		return
	var sd := multiplayer.get_remote_sender_id()
	if sd == 0:
		return
	_server_handle_client_level_up_dismiss(sd)


@rpc("any_peer", "call_remote", "reliable")
func rpc_request_revival() -> void:
	if not multiplayer.is_server():
		return
	var sr := multiplayer.get_remote_sender_id()
	if sr == 0:
		return
	_server_handle_revival_request(sr)


@rpc("authority", "call_remote", "reliable")
func rpc_unlocked_doors_delta(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_unlocked_doors[vi] = true
	unlocked_doors_delta.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_unlocked_doors_snapshot(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	_client_unlocked_doors.clear()
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_unlocked_doors[vi] = true
	unlocked_doors_snapshot.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_unpickable_doors_delta(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_unpickable_doors[vi] = true
	unpickable_doors_delta.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_unpickable_doors_snapshot(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	_client_unpickable_doors.clear()
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_unpickable_doors[vi] = true
	unpickable_doors_snapshot.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_trap_inspected_doors_delta(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_trap_inspected_doors[vi] = true
	trap_inspected_doors_delta.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_trap_inspected_doors_remove_delta(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_trap_inspected_doors.erase(vi)
	trap_inspected_doors_remove_delta.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_trap_inspected_doors_snapshot(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	_client_trap_inspected_doors.clear()
	for i in range(cells.size()):
		var vi := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_trap_inspected_doors[vi] = true
	trap_inspected_doors_snapshot.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_trap_defused_doors_delta(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	for i in range(cells.size()):
		var vdf := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_trap_defused[vdf] = true
	trap_defused_doors_delta.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_trap_defused_doors_snapshot(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	_client_trap_defused.clear()
	for i in range(cells.size()):
		var vds := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_trap_defused[vds] = true
	trap_defused_doors_snapshot.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_secret_doors_delta(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	for i in range(cells.size()):
		var vs := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_revealed_secret_doors[vs] = true
	secret_doors_delta.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_secret_doors_snapshot(cells: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	_client_revealed_secret_doors.clear()
	for i in range(cells.size()):
		var vs2 := Vector2i(int(cells[i].x), int(cells[i].y))
		_client_revealed_secret_doors[vs2] = true
	secret_doors_snapshot.emit(cells)


@rpc("authority", "call_remote", "reliable")
func rpc_player_position_sync(
	peer_id: int, x: int, y: int, role: String = "rogue", torch_burn_pct: int = TORCH_BURN_FULL
) -> void:
	var cell := Vector2i(x, y)
	if not multiplayer.is_server() and peer_id == multiplayer.get_unique_id():
		_client_spawn_cell = cell
	player_position_updated.emit(peer_id, cell, role, torch_burn_pct)


func _on_server_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var slot := _next_party_slot
	_next_party_slot += 1
	## Reserve spawn immediately so concurrent join coroutines do not pick the same cell.
	var occupied_now: Array = []
	for p in _player_positions.values():
		occupied_now.append(p)
	var spawn: Vector2i = GridWalk.find_spawn_cell(_authority_grid, occupied_now)
	_player_positions[peer_id] = spawn
	_peer_party_slots[peer_id] = slot
	_server_gold[peer_id] = 0
	_server_xp[peer_id] = 0
	_server_player_alignment[peer_id] = PlayerAlignment.starting_alignment()
	_server_npcs_killed_by_peer[peer_id] = 0
	var join_role2 := str(_peer_roles.get(peer_id, _welcome_role_echo))
	var st_join: Dictionary = PlayerCombatStats.for_role(join_role2)
	_server_player_max_hp[peer_id] = int(
		st_join.get("max_hit_points", PlayerCombatStats.BASE_MAX_HIT_POINTS)
	)
	_server_player_hp[peer_id] = int(
		st_join.get("hit_points", PlayerCombatStats.BASE_PLAYER_HIT_POINTS)
	)
	_server_talent_bonuses_by_peer[peer_id] = PlayerTalents.default_talents().duplicate(true)
	_server_level_hp_total_by_peer[peer_id] = 0
	_server_recompute_max_hp_store(peer_id)
	_init_peer_torch(peer_id)
	if _fog_enabled:
		_seed_initial_fog_for_peer(peer_id, spawn)
	else:
		_revealed_by_peer.erase(peer_id)
	_deliver_authority_to_peer_when_ready(peer_id, slot, spawn)


func _deliver_authority_to_peer_when_ready(
	peer_id: int, assigned_slot: int, spawn: Vector2i
) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	if not multiplayer.is_server():
		return
	var role_for_welcome: String = str(_peer_roles.get(peer_id, _welcome_role_echo))
	_rpc_receive_payload_to_peer(
		peer_id, assigned_slot, role_for_welcome, spawn, _authority_theme_name, _dungeon_level
	)
	_push_door_snapshots_to_peer(peer_id)
	_replay_authority_tile_patches_to_peer(peer_id)
	rpc_guards_hostile_sync.rpc_id(peer_id, _authority_guards_hostile)
	if _smoke_torch_expire_probe_server and _fog_enabled and not _torch_daylight():
		_torch_burn_by_peer[peer_id] = 1
		_torch_count_by_peer[peer_id] = 1
		print("[Dungeoneers] smoke_torch_expire_probe armed peer_id=", peer_id)
	_emit_stats_for_peer(peer_id)
	_server_broadcast_rumors_to_peer(peer_id)
	_server_broadcast_special_items_to_peer(peer_id)
	_server_broadcast_quests_to_peer(peer_id)
	_server_broadcast_achievements_to_peer(peer_id)
	_broadcast_all_positions()
	print(
		"[Dungeoneers] Sent authority dungeon to peer_id=",
		peer_id,
		" assigned_slot=",
		assigned_slot,
		" role=",
		role_for_welcome,
		" spawn=",
		spawn,
		" fog_type=",
		_fog_type,
		" fog_radius=",
		_fog_radius,
		" torch_reveals=",
		_torch_reveals_moves
	)


func _on_server_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_server_rumors_by_peer.erase(peer_id)
	_server_quests_by_peer.erase(peer_id)
	_server_achievements_by_peer.erase(peer_id)
	_server_pending_npc_quest.erase(peer_id)
	_server_special_items_by_peer.erase(peer_id)
	_server_special_item_dismiss_xp_pending.erase(peer_id)
	_server_feature_trap_pending.erase(peer_id)
	_server_feature_ambush_pending.erase(peer_id)
	_server_feature_discovery_prompted.erase(peer_id)
	_server_investigated_features.erase(peer_id)
	_server_rumor_xp_pending.erase(peer_id)
	_server_combat_by_peer.erase(peer_id)
	_server_cancel_combat_monster_strike_timer(peer_id)
	_combat_monster_strike_serial_by_peer.erase(peer_id)
	_monster_combat_delay_serial_by_peer.erase(peer_id)
	_peer_roles.erase(peer_id)
	_peer_display_names.erase(peer_id)
	_peer_party_slots.erase(peer_id)
	_server_gold.erase(peer_id)
	_server_xp.erase(peer_id)
	_server_player_alignment.erase(peer_id)
	_server_npcs_killed_by_peer.erase(peer_id)
	_server_healing_potions_by_peer.erase(peer_id)
	_server_player_hp.erase(peer_id)
	_server_player_max_hp.erase(peer_id)
	_server_talent_bonuses_by_peer.erase(peer_id)
	_server_level_hp_total_by_peer.erase(peer_id)
	_server_level_up_queue_by_peer.erase(peer_id)
	_server_level_up_waiting.erase(peer_id)
	_server_cancel_pending_path_move(peer_id)
	_path_move_serial_by_peer.erase(peer_id)
	_player_positions.erase(peer_id)
	_revealed_by_peer.erase(peer_id)
	_clicked_fog_by_peer.erase(peer_id)
	_torch_burn_by_peer.erase(peer_id)
	_torch_count_by_peer.erase(peer_id)
	print("[Dungeoneers] peer disconnected peer_id=", peer_id)
	_server_broadcast_peer_display_names_snapshot()


func _broadcast_all_positions() -> void:
	if not multiplayer.is_server():
		return
	for pid in _player_positions:
		var c: Vector2i = _player_positions[pid]
		var rid := int(pid)
		var rrole := str(_peer_roles.get(rid, "rogue"))
		rpc_player_position_sync.rpc(rid, c.x, c.y, rrole, _torch_burn_value(rid))


@rpc("authority", "call_remote", "reliable")
func rpc_receive_authority_dungeon(
	authority_seed: int,
	theme: String,
	checksum: int,
	schema_version: int,
	assigned_slot: int,
	welcome_role: String,
	spawn_x: int,
	spawn_y: int,
	fog_enabled: bool,
	fog_radius: int,
	fog_type: String,
	torch_reveals_moves: bool,
	theme_name: String,
	dungeon_level: int,
	authority_player_level: int,
	own_display_name: String,
	peer_display_names: Dictionary,
	listen_port: int,
	server_boot_unix_sec: int,
	party_peer_count: int
) -> void:
	if schema_version != WELCOME_SCHEMA_VERSION:
		var msg := (
			"unsupported welcome schema_version="
			+ str(schema_version)
			+ " (expected "
			+ str(WELCOME_SCHEMA_VERSION)
			+ ")"
		)
		push_error("[Dungeoneers] " + msg)
		authority_dungeon_failed.emit(msg)
		return

	var theme_norm := theme
	if theme_norm != "up" and theme_norm != "down":
		theme_norm = "up"
	var rng := RandomNumberGenerator.new()
	rng.seed = authority_seed
	var result: Dictionary
	var grid: Dictionary
	var theme_nm := str(theme_name).strip_edges()
	var plv_welcome := maxi(1, authority_player_level)
	if not theme_nm.is_empty():
		var theme_d: Dictionary = DungeonThemes.find_theme_by_name(theme_nm)
		if theme_d.is_empty():
			var msg2 := "unknown theme_name in welcome: " + theme_nm
			push_error("[Dungeoneers] " + msg2)
			authority_dungeon_failed.emit(msg2)
			return
		result = DungeonGenerator.generate_with_theme_data(
			rng, theme_d, plv_welcome, maxi(1, dungeon_level)
		)
		grid = result["grid"] as Dictionary
	else:
		result = TraditionalGen.generate(rng, theme_norm)
		grid = result["grid"] as Dictionary
	var local_checksum := TraditionalGen.grid_checksum(grid)
	if local_checksum != checksum:
		var msg := (
			"grid_checksum mismatch: client="
			+ str(local_checksum)
			+ " server="
			+ str(checksum)
			+ " seed="
			+ str(authority_seed)
			+ " theme="
			+ theme_norm
			+ " theme_name="
			+ theme_nm
		)
		push_error("[Dungeoneers] " + msg)
		authority_dungeon_failed.emit(msg)
		return

	var my_id := multiplayer.get_unique_id()
	_authority_seed = authority_seed
	_authority_theme = theme_norm
	_authority_theme_name = theme_nm
	_dungeon_level = maxi(1, dungeon_level)
	_player_level = plv_welcome
	_client_spawn_cell = Vector2i(spawn_x, spawn_y)
	_client_revealed.clear()
	_client_revealed_secret_doors.clear()
	_client_unlocked_doors.clear()
	_client_unpickable_doors.clear()
	_client_trap_inspected_doors.clear()
	_client_trap_defused.clear()
	_client_fog_clicked.clear()
	var fr := clampi(fog_radius, 0, 8)
	var ft := DungeonFog.normalize_fog_type(fog_type)
	_fog_enabled = fog_enabled
	_fog_radius = fr
	_fog_type = ft
	_torch_reveals_moves = torch_reveals_moves
	if fog_enabled:
		var r_rooms: Array = []
		var rr: Variant = result.get("rooms", [])
		if rr is Array:
			r_rooms = (rr as Array).duplicate()
		DungeonFog.seed_initial_revealed_with_light(
			_client_revealed, grid, Vector2i(spawn_x, spawn_y), r_rooms, ft
		)
	var lp_w := clampi(listen_port, 0, 65535)
	var boot_w := maxi(0, server_boot_unix_sec)
	var party_w := maxi(1, party_peer_count)
	var welcome := {
		"schema_version": schema_version,
		"assigned_slot": assigned_slot,
		"role": welcome_role,
		"player_id": my_id,
		"spawn_x": spawn_x,
		"spawn_y": spawn_y,
		"fog_enabled": fog_enabled,
		"fog_radius": fr,
		"fog_type": ft,
		"torch_reveals_moves": torch_reveals_moves,
		"floor_theme": str(result.get("floor_theme", "")),
		"wall_theme": str(result.get("wall_theme", "")),
		"theme_name": theme_nm,
		"dungeon_level": _dungeon_level,
		"authority_player_level": plv_welcome,
		"generation_type": str(result.get("generation_type", "dungeon")),
		"rooms": result.get("rooms", []),
		"corridors": result.get("corridors", []),
		"road_theme": str(result.get("road_theme", "")),
		"shrub_theme": str(result.get("shrub_theme", "")),
		"display_name": own_display_name,
		"peer_display_names": peer_display_names.duplicate(true),
		"listen_port": lp_w,
		"server_boot_unix_sec": boot_w,
		"party_peer_count": party_w,
	}
	_client_guards_hostile = false
	guards_hostile_changed.emit(false)
	_dng_print(
		(
			"Client welcome schema_version="
			+ str(schema_version)
			+ " assigned_slot="
			+ str(assigned_slot)
			+ " role="
			+ welcome_role
			+ " display_name="
			+ own_display_name
			+ " spawn="
			+ str(Vector2i(spawn_x, spawn_y))
			+ " | replicated dungeon seed="
			+ str(authority_seed)
			+ " theme="
			+ theme_norm
			+ " checksum="
			+ str(local_checksum)
			+ " fog_type="
			+ ft
			+ " torch_reveals="
			+ str(torch_reveals_moves)
			+ " listen_port="
			+ str(lp_w)
			+ " party_peer_count="
			+ str(party_w)
			+ " (ok) player_id="
			+ str(my_id)
		)
	)
	_client_merged_grid = grid.duplicate()
	authority_dungeon_synchronized.emit(authority_seed, theme_norm, grid, welcome)
