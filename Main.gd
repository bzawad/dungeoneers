extends Node

## Entry point for CLI-driven modes (server / client / single-player).
## With a display, default and `--single-player` start a local dungeon session (Phase 2 shell).

const DEFAULT_PORT := 12345
const MAX_CLIENTS := 8

const DungeonSession := preload("res://dungeon/ui/dungeon_session.gd")
const TraditionalGen := preload("res://dungeon/generator/traditional_generator.gd")
const DungeonGenerator := preload("res://dungeon/generator/dungeon_generator.gd")
const DungeonThemes := preload("res://dungeon/generator/dungeon_themes.gd")
const DungeonReplication := preload("res://dungeon/network/dungeon_replication.gd")
const DungeonNetworkHost := preload("res://dungeon/network/dungeon_network_host.gd")

var _client_repl_done: bool = false
var _client_repl_ok: bool = false


func _ready() -> void:
	var args := _all_cmdline_args()
	_run_mode(args)


func _all_cmdline_args() -> PackedStringArray:
	return DungeonServerBootstrap.merge_cmdline_args()


func _args_has(args: PackedStringArray, needle: String) -> bool:
	return DungeonServerBootstrap.args_has(args, needle)


func _run_mode(args: PackedStringArray) -> void:
	var mode := ""
	var server_ip := "127.0.0.1"
	var player_role := "rogue"
	var player_display_name := ""
	var dungeon_seed := -1
	var dungeon_theme := "up"
	var server_exit_after_sec := 12.0
	var client_label := ""
	var listen_port: int = DEFAULT_PORT
	var smoke_move_probe := false
	var smoke_door_unlock_probe := false
	var smoke_world_interaction_probe := false
	var smoke_treasure_probe := false
	var smoke_trapped_treasure_probe := false
	var smoke_trap_move_probe := false
	var smoke_encounter_probe := false
	var smoke_combat_probe := false
	var smoke_labels_probe := false
	var smoke_fog_reveal_probe := false
	var smoke_pickup_probe := false
	var smoke_late_join_tile_probe := false
	var smoke_torch_expire_probe := false
	var fog_enabled := true
	var fog_radius := -1
	var fog_type_cli := ""
	var theme_name_cli := ""
	var torch_reveals := true
	var debug_net := false

	var i := 0
	while i < args.size():
		var a := String(args[i])
		match a:
			"--server", "-s":
				mode = "server"
			"--client", "-c":
				mode = "client"
			"--single-player", "--singleplayer", "-sp":
				mode = "single_player"
			"--ip":
				if i + 1 < args.size():
					server_ip = String(args[i + 1])
					i += 1
			"--role":
				if i + 1 < args.size():
					player_role = String(args[i + 1])
					i += 1
			"--display-name":
				if i + 1 < args.size():
					player_display_name = String(args[i + 1])
					i += 1
			"--seed":
				if i + 1 < args.size():
					dungeon_seed = int(String(args[i + 1]))
					i += 1
			"--theme":
				if i + 1 < args.size():
					dungeon_theme = String(args[i + 1])
					i += 1
			"--theme-name":
				if i + 1 < args.size():
					theme_name_cli = String(args[i + 1])
					i += 1
			"--server-exit-after":
				if i + 1 < args.size():
					server_exit_after_sec = float(String(args[i + 1]))
					i += 1
			"--client-label":
				if i + 1 < args.size():
					client_label = String(args[i + 1])
					i += 1
			"--port":
				if i + 1 < args.size():
					listen_port = int(String(args[i + 1]))
					i += 1
			"--smoke-move-probe":
				smoke_move_probe = true
			"--smoke-door-unlock-probe":
				smoke_door_unlock_probe = true
			"--smoke-world-interaction-probe":
				smoke_world_interaction_probe = true
			"--smoke-treasure-probe":
				smoke_treasure_probe = true
			"--smoke-trapped-treasure-probe":
				smoke_trapped_treasure_probe = true
			"--smoke-trap-move-probe":
				smoke_trap_move_probe = true
			"--smoke-encounter-probe":
				smoke_encounter_probe = true
			"--smoke-combat-probe":
				smoke_combat_probe = true
			"--smoke-labels-probe":
				smoke_labels_probe = true
			"--smoke-fog-reveal-probe":
				smoke_fog_reveal_probe = true
			"--smoke-pickup-probe":
				smoke_pickup_probe = true
			"--smoke-late-join-tile-probe":
				smoke_late_join_tile_probe = true
			"--smoke-torch-expire-probe":
				smoke_torch_expire_probe = true
			"--no-fog":
				fog_enabled = false
			"--fog-radius":
				if i + 1 < args.size():
					fog_radius = int(String(args[i + 1]))
					i += 1
			"--fog-type":
				if i + 1 < args.size():
					fog_type_cli = String(args[i + 1])
					i += 1
			"--no-torch-reveal":
				torch_reveals = false
			"--debug-net":
				debug_net = true
			_:
				pass
		i += 1

	if mode == "" and (DisplayServer.get_name() == "headless" or _args_has(args, "--headless")):
		mode = "server"

	var headless := DisplayServer.get_name() == "headless" or _args_has(args, "--headless")

	if listen_port < 1 or listen_port > 65535:
		push_warning("[Dungeoneers] invalid --port; using default ", DEFAULT_PORT)
		listen_port = DEFAULT_PORT

	match mode:
		"server":
			_start_stub_server(
				dungeon_seed,
				dungeon_theme,
				server_exit_after_sec,
				listen_port,
				player_role,
				fog_enabled,
				fog_radius,
				fog_type_cli,
				torch_reveals,
				smoke_torch_expire_probe,
				debug_net
			)
		"client":
			await _start_network_client(
				server_ip,
				player_role,
				player_display_name,
				headless,
				client_label,
				listen_port,
				smoke_move_probe,
				smoke_door_unlock_probe,
				smoke_world_interaction_probe,
				smoke_treasure_probe,
				smoke_trapped_treasure_probe,
				smoke_trap_move_probe,
				smoke_encounter_probe,
				smoke_combat_probe,
				smoke_labels_probe,
				smoke_fog_reveal_probe,
				smoke_pickup_probe,
				smoke_late_join_tile_probe,
				smoke_torch_expire_probe,
				debug_net
			)
		"single_player":
			if headless:
				print("[Dungeoneers] single-player headless stub (role=", player_role, ")")
				get_tree().quit(0)
			else:
				_start_local_dungeon(
					dungeon_seed,
					dungeon_theme,
					player_role,
					player_display_name,
					fog_enabled,
					fog_radius,
					fog_type_cli,
					torch_reveals,
					theme_name_cli
				)
		_:
			if not headless:
				_start_local_dungeon(
					dungeon_seed,
					dungeon_theme,
					"rogue",
					player_display_name,
					fog_enabled,
					fog_radius,
					fog_type_cli,
					torch_reveals,
					theme_name_cli
				)
			else:
				print(
					"[Dungeoneers] No --server/--client/--single-player flag; ",
					"run from editor or pass CLI flags (see ../FINAL_TASKS.md; archived plan: ../archive/DUNGEONEERS_PORT_PLAN.md)."
				)


func _start_local_dungeon(
	authority_seed: int,
	theme: String,
	player_role: String,
	player_display_name: String,
	fog_enabled: bool,
	fog_radius_override: int,
	fog_type_cli: String,
	torch_reveals_moves: bool,
	theme_name_arg: String = ""
) -> void:
	var theme_norm := theme
	if theme_norm != "up" and theme_norm != "down":
		theme_norm = "up"

	var s_rng := RandomNumberGenerator.new()
	var chosen_seed := authority_seed
	if chosen_seed < 0:
		chosen_seed = randi()
	s_rng.seed = chosen_seed

	var authority: Dictionary
	if not theme_name_arg.strip_edges().is_empty():
		DungeonThemes.load_themes()
		var theme_data: Dictionary = DungeonThemes.find_theme_by_name(theme_name_arg.strip_edges())
		if theme_data.is_empty():
			push_error("[Dungeoneers] unknown --theme-name: ", theme_name_arg)
			get_tree().quit(1)
			return
		authority = DungeonGenerator.generate_with_theme_data(s_rng, theme_data, 1, 1)
		var ddir := str(theme_data.get("direction", "up")).strip_edges()
		theme_norm = ddir if (ddir == "up" or ddir == "down") else "up"
	else:
		authority = TraditionalGen.generate(s_rng, theme_norm)
	var checksum := TraditionalGen.grid_checksum(authority["grid"])
	var gen_meta := {
		"theme_name": str(authority.get("theme", "")),
		"dungeon_level": 1,
		"generation_type": str(authority.get("generation_type", "dungeon")),
		"rooms": authority.get("rooms", []),
		"corridors": authority.get("corridors", []),
		"fog_type": str(authority.get("fog_type", "")),
	}

	var rep: Node = _add_dungeon_replication()
	rep.configure_authority(
		chosen_seed,
		theme_norm,
		checksum,
		player_role,
		authority["grid"],
		fog_enabled,
		fog_radius_override,
		fog_type_cli,
		torch_reveals_moves,
		gen_meta
	)

	var on_sync := func(
		sync_seed: int, sync_theme: String, grid: Dictionary, welcome: Dictionary
	) -> void:
		var existing: Node = get_node_or_null("DungeonSession")
		if existing == null:
			var sess = DungeonSession.new()
			sess.name = "DungeonSession"
			add_child(sess)
			var my_pid := int(welcome.get("player_id", 2))
			sess.start_from_grid(grid, sync_seed, rep, my_pid, welcome)
			print(
				"[Dungeoneers] Local dungeon session (role=",
				player_role,
				" welcome_role=",
				str(welcome.get("role", "")),
				"). seed=",
				sync_seed,
				" theme=",
				sync_theme,
				" fog_enabled=",
				bool(welcome.get("fog_enabled", true))
			)
		else:
			existing.reload_from_authority(grid, sync_seed, welcome)
			print(
				"[Dungeoneers] Local dungeon reloaded seed=",
				sync_seed,
				" theme=",
				sync_theme,
				" level=",
				int(welcome.get("dungeon_level", 1))
			)

	rep.authority_dungeon_synchronized.connect(on_sync)
	rep.authority_dungeon_failed.connect(
		func(_reason: String) -> void: get_tree().quit(1), CONNECT_ONE_SHOT
	)
	rep.begin_solo_local_session(player_role, player_display_name)


func _add_dungeon_replication() -> Node:
	var rep: Node = DungeonReplication.new()
	rep.name = "DungeonReplication"
	add_child(rep)
	return rep


func _start_stub_server(
	dungeon_seed: int,
	dungeon_theme: String,
	server_exit_after_sec: float,
	listen_port: int,
	welcome_role_echo: String,
	fog_enabled: bool,
	fog_radius_override: int,
	fog_type_cli: String,
	torch_reveals_moves: bool,
	smoke_torch_expire_probe: bool = false,
	debug_net: bool = false
) -> void:
	var r: Dictionary = DungeonServerBootstrap.start_stub_server_on(
		self,
		dungeon_seed,
		dungeon_theme,
		listen_port,
		welcome_role_echo,
		fog_enabled,
		fog_radius_override,
		fog_type_cli,
		torch_reveals_moves,
		smoke_torch_expire_probe,
		MAX_CLIENTS
	)
	if not bool(r.get("ok", false)):
		get_tree().quit(1)
		return

	var rep_srv: Node = r["replication"]
	if debug_net and rep_srv.has_method("set_debug_net"):
		rep_srv.set_debug_net(true)

	var net_host: Node = r["net_host"]
	print(
		"[Dungeoneers] ENet server listening on ",
		listen_port,
		" (exit after ",
		server_exit_after_sec,
		"s)"
	)
	net_host.quit_after_seconds(server_exit_after_sec)


func _client_on_authority_ok(
	_seed: int, _theme: String, _grid: Dictionary, _welcome: Dictionary
) -> void:
	_client_repl_done = true
	_client_repl_ok = true


func _client_on_authority_fail(_reason: String) -> void:
	_client_repl_done = true
	_client_repl_ok = false
	push_error("[Dungeoneers] client replication failed: ", _reason)
	_close_multiplayer_if_any()


func _close_multiplayer_if_any() -> void:
	var p := multiplayer.multiplayer_peer
	if p == null:
		return
	if p is ENetMultiplayerPeer:
		(p as ENetMultiplayerPeer).close()
	multiplayer.multiplayer_peer = null


func _start_network_client(
	host: String,
	role: String,
	display_name: String,
	headless: bool,
	client_label: String,
	listen_port: int,
	run_move_probe: bool,
	run_door_unlock_probe: bool,
	run_world_interaction_probe: bool,
	run_treasure_probe: bool,
	run_trapped_treasure_probe: bool,
	run_trap_move_probe: bool,
	run_encounter_probe: bool,
	run_combat_probe: bool,
	run_labels_probe: bool,
	run_fog_reveal_probe: bool,
	run_pickup_probe: bool,
	run_late_join_tile_probe: bool,
	run_torch_expire_probe: bool = false,
	debug_net: bool = false
) -> void:
	var address := host
	if address == "localhost":
		address = "127.0.0.1"

	_client_repl_done = false
	_client_repl_ok = false

	var rep: Node = _add_dungeon_replication()
	if not client_label.is_empty():
		rep.set_client_log_label(client_label)
	if debug_net and rep.has_method("set_debug_net"):
		rep.set_debug_net(true)
	if headless:
		rep.authority_dungeon_synchronized.connect(_client_on_authority_ok)
		rep.authority_dungeon_failed.connect(_client_on_authority_fail)

	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(address, listen_port) != OK:
		push_error("[Dungeoneers] client: create_client failed")
		_close_multiplayer_if_any()
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	print(
		"[Dungeoneers] client connecting to ",
		address,
		":",
		listen_port,
		" role=",
		role,
		" display_name=",
		display_name
	)

	var frames := 0
	while frames < 300:
		var st := peer.get_connection_status()
		if st == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		if st == MultiplayerPeer.CONNECTION_DISCONNECTED:
			push_error("[Dungeoneers] client: disconnected before handshake")
			_close_multiplayer_if_any()
			get_tree().quit(1)
			return
		await get_tree().process_frame
		frames += 1

	if peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		push_warning("[Dungeoneers] client: did not connect in time")
		_close_multiplayer_if_any()
		get_tree().quit(1)
		return

	print(
		"[Dungeoneers] client connected my_peer_id=",
		multiplayer.get_unique_id(),
		"; waiting for authority dungeon…"
	)
	rep.client_submit_join_request(role, display_name)

	if headless:
		frames = 0
		while frames < 300 and not _client_repl_done:
			await get_tree().process_frame
			frames += 1
		if not _client_repl_done:
			push_warning("[Dungeoneers] client: timed out waiting for authority dungeon RPC")
			_close_multiplayer_if_any()
			get_tree().quit(1)
			return
		if not _client_repl_ok:
			_close_multiplayer_if_any()
			get_tree().quit(1)
			return
		if rep != null:
			if run_move_probe:
				await rep.run_headless_move_smoke_probe()
			if run_door_unlock_probe:
				await rep.run_headless_door_unlock_probe()
			if run_world_interaction_probe:
				await rep.run_headless_world_interaction_probe()
			if run_treasure_probe:
				await rep.run_headless_treasure_probe()
			if run_trapped_treasure_probe:
				await rep.run_headless_trapped_treasure_probe()
			if run_trap_move_probe:
				await rep.run_headless_trap_move_probe()
				for _trap_mv_flush in range(8):
					await get_tree().process_frame
				await rep.run_headless_room_trap_adjacent_move_probe()
			if run_encounter_probe:
				await rep.run_headless_encounter_probe()
			if run_combat_probe:
				await rep.run_headless_combat_probe()
			if run_labels_probe:
				await rep.run_headless_labels_probe()
			if run_fog_reveal_probe:
				await rep.run_headless_fog_reveal_smoke_probe()
			if run_pickup_probe:
				await rep.run_headless_pickup_probe()
			if run_late_join_tile_probe:
				await rep.run_headless_late_join_tile_probe()
			if run_torch_expire_probe:
				await rep.run_headless_torch_expire_probe()
		for _flush in range(4):
			await get_tree().process_frame
		_close_multiplayer_if_any()
		get_tree().quit(0)
		return

	# Display client: apply grid when RPC arrives (same frame or later).
	var on_sync := func(
		sync_seed: int, theme: String, grid: Dictionary, welcome: Dictionary
	) -> void:
		var existing_net: Node = get_node_or_null("DungeonSession")
		if existing_net == null:
			var sess = DungeonSession.new()
			sess.name = "DungeonSession"
			add_child(sess)
			var my_pid := multiplayer.get_unique_id()
			sess.start_from_grid(grid, sync_seed, rep, my_pid, welcome)
			var echoed: String = str(welcome.get("role", role))
			print(
				"[Dungeoneers] Network dungeon session (welcome role=",
				echoed,
				" slot=",
				int(welcome.get("assigned_slot", -1)),
				" schema=",
				int(welcome.get("schema_version", 0)),
				" player_id=",
				multiplayer.get_unique_id(),
				"). seed=",
				sync_seed,
				" theme=",
				theme
			)
		else:
			existing_net.reload_from_authority(grid, sync_seed, welcome)
			print("[Dungeoneers] Network dungeon reloaded seed=", sync_seed, " theme=", theme)

	rep.authority_dungeon_synchronized.connect(on_sync)
	rep.authority_dungeon_failed.connect(
		func(_reason: String) -> void:
			_close_multiplayer_if_any()
			get_tree().quit(1),
		CONNECT_ONE_SHOT
	)
