extends Node

## Thin ENet listen bootstrap for **`--server`** (Phase 3). `Main.gd` still owns dungeon generation
## and `DungeonReplication.configure_authority`; this node only binds the peer and optional exit timer.

signal listen_failed(port: int, message: String)

const DEFAULT_MAX_CLIENTS := 8


func start_listen(port: int, max_clients: int = DEFAULT_MAX_CLIENTS) -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(port, max_clients) != OK:
		listen_failed.emit(port, "create_server failed")
		return false
	multiplayer.multiplayer_peer = peer
	return true


func quit_after_seconds(seconds: float) -> void:
	if seconds <= 0.0 or not is_finite(seconds):
		return
	get_tree().create_timer(maxf(0.1, seconds)).timeout.connect(func() -> void: get_tree().quit(0))
