extends RefCounted

## P7-09: optional join display name — sanitize only (no LLM). Explorer web has no direct Godot twin; this is co-op UX metadata.
## Phase 3: `welcome` dict may include `listen_port`, `party_peer_count`, `server_boot_unix_sec` (see `WELCOME_SCHEMA_VERSION` in `dungeon_replication.gd`).

const DISPLAY_NAME_MAX_LEN := 32
const MAP_MARKER_LABEL_MAX_LEN := 14


## Strip edges, drop ASCII control chars and DEL; cap length. May return empty (caller picks fallback).
static func normalize_display_name(raw: String) -> String:
	var t := raw.strip_edges()
	var out := ""
	for i in range(t.length()):
		if out.length() >= DISPLAY_NAME_MAX_LEN:
			break
		var c: int = t.unicode_at(i)
		if c >= 32 and c != 127:
			out += String.chr(c)
	return out.strip_edges()


static func display_name_for_network_peer(raw: String, peer_id: int) -> String:
	var n := normalize_display_name(raw)
	if n.is_empty():
		return "Player " + str(peer_id)
	return n


static func display_name_for_solo(raw: String) -> String:
	var n := normalize_display_name(raw)
	if n.is_empty():
		return "Explorer"
	return n


## Short label under map tokens (P7-09); headless-safe for CI.
## Non-empty when the host advertised a TCP port (networked sessions). For HUD / logs; solo leaves `listen_port` 0.
static func welcome_hud_tail(welcome: Dictionary) -> String:
	var lp := int(welcome.get("listen_port", 0))
	var pc := maxi(1, int(welcome.get("party_peer_count", 1)))
	if lp <= 0:
		return ""
	return "  |  Server TCP %d · party %d" % [lp, pc]


static func truncate_for_map_marker(raw: String, max_len: int = MAP_MARKER_LABEL_MAX_LEN) -> String:
	var t := raw.strip_edges()
	if t.is_empty():
		return ""
	var cap := maxi(4, max_len)
	if t.length() <= cap:
		return t
	return t.substr(0, cap - 1) + "\u2026"
