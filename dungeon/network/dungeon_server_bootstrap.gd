extends RefCounted
class_name DungeonServerBootstrap

## Shared authority dungeon + ENet listen setup for [code]Main.gd --server[/code] and [code]DedicatedServer[/code].

const TraditionalGen := preload("res://dungeon/generator/traditional_generator.gd")
const DungeonGenerator := preload("res://dungeon/generator/dungeon_generator.gd")
const DungeonReplication := preload("res://dungeon/network/dungeon_replication.gd")
const DungeonNetworkHost := preload("res://dungeon/network/dungeon_network_host.gd")
const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")


static func merge_cmdline_args() -> PackedStringArray:
	var merged: PackedStringArray = OS.get_cmdline_args()
	for a in OS.get_cmdline_user_args():
		merged.append(a)
	return merged


static func args_has(args: PackedStringArray, needle: String) -> bool:
	for a in args:
		if String(a) == needle:
			return true
	return false


## Returns keys: [code]ok[/code], [code]error[/code], [code]replication[/code], [code]net_host[/code],
## [code]chosen_seed[/code], [code]theme[/code], [code]checksum[/code], [code]listen_port[/code],
## [code]fog_enabled[/code], [code]log_fog_type[/code], [code]log_fog_radius[/code], [code]effective_torch[/code].
static func start_minimal_server_on(
	parent: Node,
	dungeon_seed: int,
	_dungeon_theme: String,
	listen_port: int,
	welcome_role_echo: String,
	fog_enabled: bool,
	fog_radius_override: int,
	fog_type_cli: String,
	torch_reveals_moves: bool,
	smoke_torch_expire_probe: bool,
	max_clients: int = 8
) -> Dictionary:
	var s_rng := RandomNumberGenerator.new()
	var chosen_seed := dungeon_seed
	if chosen_seed < 0:
		chosen_seed = randi()
	s_rng.seed = chosen_seed

	# Explorer parity: new game starts from a random theme, not legacy up/down.
	var authority: Dictionary = DungeonGenerator.generate_with_player_level(s_rng, 1, 1)
	var checksum := TraditionalGen.grid_checksum(authority["grid"])
	var theme_dir_raw := str(authority.get("theme_direction", "up")).strip_edges()
	var theme_dir_norm := (
		theme_dir_raw if (theme_dir_raw == "up" or theme_dir_raw == "down") else "up"
	)
	var gen_meta_srv := {
		"theme_name": str(authority.get("theme", "")),
		"dungeon_level": 1,
		"generation_type": str(authority.get("generation_type", "dungeon")),
		"rooms": authority.get("rooms", []),
		"corridors": authority.get("corridors", []),
		"fog_type": str(authority.get("fog_type", "")),
	}
	var log_fog_type := str(authority.get("fog_type", "dark"))
	if not fog_type_cli.strip_edges().is_empty():
		log_fog_type = DungeonFog.normalize_fog_type(fog_type_cli)
	var log_fog_radius := (
		clampi(fog_radius_override, 0, 8)
		if fog_radius_override >= 0
		else DungeonFog.fog_radius_for_type(log_fog_type)
	)
	var effective_torch := (
		torch_reveals_moves or (DungeonFog.normalize_fog_type(log_fog_type) == "daylight")
	)
	print(
		"[Dungeoneers] Server authority dungeon seed=",
		chosen_seed,
		" theme=",
		theme_dir_norm,
		" theme_name=",
		str(authority.get("theme", "")),
		" checksum=",
		checksum,
		" fog_enabled=",
		fog_enabled,
		" fog_type=",
		log_fog_type,
		" fog_radius=",
		log_fog_radius,
		" torch_reveals_moves=",
		effective_torch
	)

	var rep: Node = DungeonReplication.new()
	rep.name = "DungeonReplication"
	parent.add_child(rep)
	rep.configure_authority(
		chosen_seed,
		theme_dir_norm,
		checksum,
		welcome_role_echo,
		authority["grid"],
		fog_enabled,
		fog_radius_override,
		fog_type_cli,
		torch_reveals_moves,
		gen_meta_srv
	)
	if smoke_torch_expire_probe:
		rep.set_smoke_torch_expire_probe_server(true)

	var net_host: Node = DungeonNetworkHost.new()
	net_host.name = "DungeonNetworkHost"
	parent.add_child(net_host)
	if not net_host.start_listen(listen_port, max_clients):
		var err_msg := (
			"[Dungeoneers] minimal server: create_server failed (port "
			+ str(listen_port)
			+ " in use? try --port <other> or stop processes on this port)"
		)
		push_error(err_msg)
		net_host.queue_free()
		rep.queue_free()
		return {
			"ok": false,
			"error": err_msg,
			"replication": null,
			"net_host": null,
			"chosen_seed": chosen_seed,
			"theme": theme_dir_norm,
			"checksum": checksum,
			"listen_port": listen_port,
			"fog_enabled": fog_enabled,
			"log_fog_type": log_fog_type,
			"log_fog_radius": log_fog_radius,
			"effective_torch": effective_torch,
		}

	rep.attach_server_handlers()
	rep.set_server_listen_metadata(listen_port)

	return {
		"ok": true,
		"error": "",
		"replication": rep,
		"net_host": net_host,
		"chosen_seed": chosen_seed,
		"theme": theme_dir_norm,
		"checksum": checksum,
		"listen_port": listen_port,
		"fog_enabled": fog_enabled,
		"log_fog_type": log_fog_type,
		"log_fog_radius": log_fog_radius,
		"effective_torch": effective_torch,
	}
