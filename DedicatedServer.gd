extends Control

## GUI / headless entry for a long-running ENet host (P7-10). Gameplay matches [code]Main.gd --server[/code].
## Run: [code]godot4 --path dungeoneers DedicatedServer.tscn[/code] (optional [code]--headless[/code], [code]--port[/code], …).
## The scene root **must** be named [code]Main[/code] (see [code]DedicatedServer.tscn[/code]) so high-level multiplayer RPC paths match [code]Main.tscn[/code] clients.
##
## **Ops / logs:** stdout from this process is plain text. For rotation under a service manager, pipe or redirect
## (e.g. shell `>>` to dated files, or your platform’s log shipper). Same idea as [code]gama/start_server.sh[/code] loop + PID file.
## Optional [code]--metrics-interval-sec N[/code] prints one machine-parsable line per interval; [code]--metrics-file path[/code] appends the same line.
## [code]--debug-net[/code] enables replication net size logs (Phase 8), same as [code]Main.gd --server[/code].

const DEFAULT_PORT := 12345
const MAX_CLIENTS := 8
const MAX_LOG_LINES := 120

const DungeonServerBootstrap := preload("res://dungeon/network/dungeon_server_bootstrap.gd")

var _rep: Node
var _net_host: Node
var _listen_port: int = DEFAULT_PORT
var _server_exit_after_sec: float = 0.0
var _metrics_interval_sec: float = 0.0
var _metrics_file_path: String = ""
var _metrics_timer: Timer = null
var _log_lines: PackedStringArray = PackedStringArray()

var _label_title: Label
var _label_listen: Label
var _label_world: Label
var _label_peers: Label
var _log_view: RichTextLabel
var _btn_quit: Button
var _refresh_timer: Timer
## Cached for world line when `server_world_meta_changed` fires (fog toggle is session-static).
var _fog_ui_str: String = "on"


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	_build_ui()

	var args := DungeonServerBootstrap.merge_cmdline_args()
	var headless := (
		DisplayServer.get_name() == "headless"
		or DungeonServerBootstrap.args_has(args, "--headless")
	)
	_parse_host_cli(args)

	if _listen_port < 1 or _listen_port > 65535:
		push_warning("[Dungeoneers] invalid --port; using default ", DEFAULT_PORT)
		_listen_port = DEFAULT_PORT

	var cfg := _host_flags_from_args(args)
	var r: Dictionary = DungeonServerBootstrap.start_minimal_server_on(
		self,
		cfg.dungeon_seed,
		cfg.dungeon_theme,
		_listen_port,
		cfg.player_role,
		cfg.fog_enabled,
		cfg.fog_radius,
		cfg.fog_type_cli,
		cfg.torch_reveals,
		cfg.smoke_torch_expire_probe,
		MAX_CLIENTS
	)
	if not bool(r.get("ok", false)):
		_append_log(str(r.get("error", "Server start failed")))
		if headless:
			get_tree().quit(1)
		else:
			_label_listen.text = "Listen: FAILED (see log)"
		return

	_rep = r["replication"]
	_net_host = r["net_host"]
	if bool(cfg.get("debug_net", false)) and _rep.has_method("set_debug_net"):
		_rep.set_debug_net(true)

	_append_log(
		(
			"[Dungeoneers] Dedicated server UI — seed=%s theme=%s checksum=%s port=%s"
			% [
				str(r.get("chosen_seed", 0)),
				str(r.get("theme", "")),
				str(r.get("checksum", 0)),
				str(_listen_port),
			]
		)
	)
	var exit_note := (
		"(no auto-exit)"
		if _server_exit_after_sec <= 0.0
		else "(exit after %.1fs)" % _server_exit_after_sec
	)
	var listen_msg := (
		"[Dungeoneers] ENet server listening on %s %s" % [str(_listen_port), exit_note]
	)
	print(listen_msg)
	_append_log(listen_msg)

	_label_listen.text = "Listening on port %s (%s)" % [str(_listen_port), exit_note]
	_fog_ui_str = "on" if bool(r.get("fog_enabled", true)) else "off"
	_label_world.text = (
		"Seed %s  theme %s  checksum %s  fog %s"
		% [
			str(r.get("chosen_seed", 0)),
			str(r.get("theme", "")),
			str(r.get("checksum", 0)),
			_fog_ui_str,
		]
	)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_net_host.quit_after_seconds(_server_exit_after_sec)
	if _rep.has_signal("server_world_meta_changed"):
		_rep.server_world_meta_changed.connect(_on_server_world_meta_changed)
	if _metrics_interval_sec > 0.0:
		_metrics_timer = Timer.new()
		_metrics_timer.wait_time = _metrics_interval_sec
		_metrics_timer.timeout.connect(_on_metrics_timer)
		add_child(_metrics_timer)
		_metrics_timer.start()
		_on_metrics_timer()

	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 0.5
	_refresh_timer.timeout.connect(_refresh_peer_label)
	add_child(_refresh_timer)
	_refresh_timer.start()
	_refresh_peer_label()

	if headless:
		_btn_quit.visible = false


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	_label_title = Label.new()
	_label_title.text = "Dungeoneers — dedicated server"
	_label_title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(_label_title)

	_label_listen = Label.new()
	_label_listen.text = "Listen: …"
	vbox.add_child(_label_listen)

	_label_world = Label.new()
	_label_world.text = "World: …"
	vbox.add_child(_label_world)

	_label_peers = Label.new()
	_label_peers.text = "Connected peers: 0"
	vbox.add_child(_label_peers)

	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_following = true
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.custom_minimum_size = Vector2(0, 220)
	_log_view.fit_content = false
	vbox.add_child(_log_view)

	_btn_quit = Button.new()
	_btn_quit.text = "Quit server"
	_btn_quit.pressed.connect(func() -> void: get_tree().quit(0))
	vbox.add_child(_btn_quit)


func _parse_host_cli(args: PackedStringArray) -> void:
	var i := 0
	while i < args.size():
		var a := String(args[i])
		match a:
			"--port":
				if i + 1 < args.size():
					_listen_port = int(String(args[i + 1]))
					i += 1
			"--server-exit-after":
				if i + 1 < args.size():
					_server_exit_after_sec = float(String(args[i + 1]))
					i += 1
			"--metrics-interval-sec":
				if i + 1 < args.size():
					_metrics_interval_sec = maxf(0.0, float(String(args[i + 1])))
					i += 1
			"--metrics-file":
				if i + 1 < args.size():
					_metrics_file_path = String(args[i + 1])
					i += 1
			_:
				pass
		i += 1


func _host_flags_from_args(args: PackedStringArray) -> Dictionary:
	var dungeon_seed := -1
	var dungeon_theme := "up"
	var player_role := "rogue"
	var fog_enabled := true
	var fog_radius := -1
	var fog_type_cli := ""
	var torch_reveals := true
	var smoke_torch_expire_probe := false
	var debug_net := false

	var i := 0
	while i < args.size():
		var a := String(args[i])
		match a:
			"--seed":
				if i + 1 < args.size():
					dungeon_seed = int(String(args[i + 1]))
					i += 1
			"--theme":
				if i + 1 < args.size():
					dungeon_theme = String(args[i + 1])
					i += 1
			"--role":
				if i + 1 < args.size():
					player_role = String(args[i + 1])
					i += 1
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
			"--smoke-torch-expire-probe":
				smoke_torch_expire_probe = true
			"--debug-net":
				debug_net = true
			_:
				pass
		i += 1

	return {
		"dungeon_seed": dungeon_seed,
		"dungeon_theme": dungeon_theme,
		"player_role": player_role,
		"fog_enabled": fog_enabled,
		"fog_radius": fog_radius,
		"fog_type_cli": fog_type_cli,
		"torch_reveals": torch_reveals,
		"smoke_torch_expire_probe": smoke_torch_expire_probe,
		"debug_net": debug_net,
	}


func _append_log(line: String) -> void:
	_log_lines.append(line)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	if _log_view != null:
		_log_view.clear()
		for ln in _log_lines:
			_log_view.append_text(ln + "\n")


func _refresh_peer_label() -> void:
	if _label_peers == null or multiplayer.multiplayer_peer == null:
		return
	var peers := multiplayer.get_peers()
	var parts: PackedStringArray = PackedStringArray()
	for p in peers:
		parts.append(str(p))
	_label_peers.text = "Connected peers: %d [%s]" % [peers.size(), ", ".join(parts)]


func _on_peer_connected(id: int) -> void:
	_append_log("[net] peer_connected id=%s" % str(id))
	_refresh_peer_label()


func _on_peer_disconnected(id: int) -> void:
	_append_log("[net] peer_disconnected id=%s" % str(id))
	_refresh_peer_label()


func _on_server_world_meta_changed(
	seed: int,
	theme_dir: String,
	checksum: int,
	theme_name: String,
	dungeon_level: int,
	connected_client_count: int
) -> void:
	if _label_world == null:
		return
	_append_log(
		(
			"[world] map authority updated seed=%s checksum=%s level=%s theme=%s clients=%s dir=%s"
			% [
				str(seed),
				str(checksum),
				str(dungeon_level),
				theme_name,
				str(connected_client_count),
				theme_dir,
			]
		)
	)
	_label_world.text = (
		"Seed %s  dir %s  checksum %s  fog %s  |  %s  L%d  ·  ENet clients %d"
		% [
			str(seed),
			theme_dir,
			str(checksum),
			_fog_ui_str,
			theme_name,
			dungeon_level,
			connected_client_count,
		]
	)


func _on_metrics_timer() -> void:
	if _rep == null:
		return
	var line := ""
	if _rep.has_method("dedicated_metrics_line_for_host"):
		line = str(_rep.call("dedicated_metrics_line_for_host"))
	if line.is_empty():
		return
	print(line)
	if not _metrics_file_path.is_empty():
		var f: FileAccess
		if FileAccess.file_exists(_metrics_file_path):
			f = FileAccess.open(_metrics_file_path, FileAccess.READ_WRITE)
		else:
			f = FileAccess.open(_metrics_file_path, FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_string(line + "\n")
			f.close()
