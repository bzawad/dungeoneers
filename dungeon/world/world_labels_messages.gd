extends RefCounted

## Phase 5.5: Explorer `RoomLabelSystem` / `SpecialFeatureSystem` **view** copy when `DescriptionService` uses static fallbacks (`OLLAMA_MODEL=none` — see `dungeon_explorer/.../description_service.ex` `get_location_fallback` / `get_discovery_fallback` / `get_generic_fallback`).


static func theme_display(theme_name: String, theme_leg: String) -> String:
	var n := theme_name.strip_edges()
	if not n.is_empty():
		return n
	if theme_leg == "down":
		return "Dark Caverns"
	return "Ancient Castle"


## Explorer `context.theme` for fallback prose (display string from authority theme name / leg).
static func _theme_for_fallback(theme_name: String, theme_leg: String) -> String:
	return theme_display(theme_name, theme_leg).strip_edges()


## Explorer `DescriptionService.get_location_fallback(:door, …)` (`door_status`, default `"closed"`).
static func door_location_fallback_body(
	door_status: String, theme_name: String, theme_leg: String
) -> String:
	var st := door_status.strip_edges().to_lower()
	var th := _theme_for_fallback(theme_name, theme_leg)
	if st == "unpickable":
		return (
			"A sturdy locked door made from weathered wood and iron, fitting for this "
			+ th
			+ " setting. The lock mechanism appears damaged from a failed picking attempt and can no longer be picked."
		)
	return (
		"A sturdy "
		+ st
		+ " door made from weathered wood and iron, fitting for this "
		+ th
		+ " setting."
	)


## Explorer `get_location_fallback(:stair, …)` (`stair_direction`, default `"unknown"`).
static func stair_location_fallback_body(
	stair_direction: String, theme_name: String, theme_leg: String
) -> String:
	var d := stair_direction.strip_edges().to_lower()
	if d != "up" and d != "down":
		d = "unknown"
	var th := _theme_for_fallback(theme_name, theme_leg)
	return (
		"A "
		+ d
		+ "ward staircase in this "
		+ th
		+ ". Stone steps disappear into shadows, beckoning you to venture "
		+ d
		+ "ward to the next level."
	)


## Explorer `DescriptionService.get_trap_fallback(:room_trap, %{theme: …})` when LLM is off.
static func room_trap_world_interaction_body(theme_name: String, theme_leg: String) -> String:
	var th := _theme_for_fallback(theme_name, theme_leg)
	return (
		"**Hidden Trap!** You stumbled into a concealed trap in this part of the "
		+ th
		+ ". The floor gives way beneath you!"
	)


## Explorer `get_location_fallback(:waypoint, …)` (`waypoint_number`; Elixir theme default `"outdoor area"` when unset — here `_theme_for_fallback` supplies the authority theme display string).
static func waypoint_location_fallback_body(
	waypoint_number: int, theme_name: String, theme_leg: String
) -> String:
	var th := _theme_for_fallback(theme_name, theme_leg)
	if th.is_empty():
		th = "outdoor area"
	var n := maxi(1, waypoint_number)
	return (
		"**Waypoint Discovered**\n\nYou've found a weathered waypoint marker ("
		+ str(n)
		+ ") standing sentinel in this "
		+ th
		+ ". The ancient stone points deeper into the wilderness, indicating a path to unexplored territory. Do you wish to follow the direction it indicates and venture forth to the next area?"
	)


static func stair_direction_from_raw_tile(raw_tile: String) -> String:
	if raw_tile == "stair_up":
		return "up"
	if raw_tile == "stair_down":
		return "down"
	return "unknown"


static func waypoint_number_from_raw_tile(raw_tile: String) -> int:
	var parts := raw_tile.split("|")
	if parts.size() < 2:
		return 1
	var rest := str(parts[1]).strip_edges()
	if rest.is_valid_int():
		return maxi(1, int(rest))
	return 1


## Explorer `get_or_generate_destination_description` static string (city / outdoor waypoints).
static func waypoint_destination_land_message(destination_theme: String) -> String:
	var dest := destination_theme.strip_edges()
	return (
		"**Waypoint to a Different Land**\n\nA signpost decorated with carvings points towards new lands. It reads: "
		+ dest
		+ ".\n\nDo you wish to travel there?"
	)


## Explorer waypoint dialog icon (`/images/map_links/outdoor_waypoint{n}.png`).
static func waypoint_header_png_relpath(raw_tile: String) -> String:
	if raw_tile.begins_with("starting_waypoint|"):
		return "map_links/outdoor_waypoint1.png"
	var n := clampi(waypoint_number_from_raw_tile(raw_tile), 1, 4)
	return "map_links/outdoor_waypoint%d.png" % n


## Full world-interaction dialog for stairs (body + Explorer-style travel hint).
static func stair_world_interaction_payload(
	raw_tile: String, theme_name: String, theme_leg: String
) -> Dictionary:
	var dir := stair_direction_from_raw_tile(raw_tile)
	var body := stair_location_fallback_body(dir, theme_name, theme_leg)
	var hint := ""
	if dir == "up":
		hint = (
			"**Go Up** continues to the next level and reloads the dungeon map. "
			+ "**Cancel** closes this dialog and leaves you on this floor."
		)
	elif dir == "down":
		hint = (
			"**Go Down** continues to the next level and reloads the dungeon map. "
			+ "**Cancel** closes this dialog and leaves you on this floor."
		)
	else:
		hint = (
			"**Continue** loads the next level and reloads the dungeon map. "
			+ "**Cancel** closes this dialog and leaves you on this floor."
		)
	return {"title": "Staircase", "message": body + "\n\n" + hint}


## Full world-interaction dialog for waypoints (dungeon / cavern — same theme, next level).
## City / outdoor copy is built in `dungeon_replication.gd` via `waypoint_destination_land_message`.
static func waypoint_world_interaction_payload(
	raw_tile: String, theme_name: String, theme_leg: String
) -> Dictionary:
	var n := waypoint_number_from_raw_tile(raw_tile)
	var body := waypoint_location_fallback_body(n, theme_name, theme_leg)
	return {"title": "Waypoint Marker", "message": body}


static func _split_rest(effective_tile: String) -> String:
	var parts := effective_tile.split("|")
	return parts[1] if parts.size() > 1 else "?"


static func _feature_display_name(effective_tile: String) -> Dictionary:
	var parts := effective_tile.split("|")
	if parts.size() >= 3:
		return {"marker": parts[1], "name": parts[2]}
	if parts.size() == 2:
		return {"marker": parts[1], "name": parts[1]}
	return {"marker": "?", "name": "feature"}


static func room_label_payload(
	effective_tile: String, theme_name: String, theme_leg: String
) -> Dictionary:
	var rid := _split_rest(effective_tile)
	var th := _theme_for_fallback(theme_name, theme_leg)
	var body: String
	if rid == "R1":
		body = (
			"The entrance chamber of this "
			+ th
			+ ". The walls stretch upward into darkness, and the air carries the weight of untold mysteries."
		)
	else:
		body = (
			"A chamber within this " + th + ", filled with shadows and the echo of ancient secrets."
		)
	return {
		"title": "Room",
		"message": "Marked **" + rid + "** on the map.\n\n" + body,
	}


static func corridor_label_payload(
	effective_tile: String, theme_name: String, theme_leg: String
) -> Dictionary:
	var cid := _split_rest(effective_tile)
	var th := _theme_for_fallback(theme_name, theme_leg)
	var body := (
		"A passage winding through this "
		+ th
		+ ", where every shadow might hide danger or treasure."
	)
	return {
		"title": "Corridor",
		"message": "Passage **" + cid + "** on the map.\n\n" + body,
	}


static func area_label_payload(
	effective_tile: String, theme_name: String, theme_leg: String
) -> Dictionary:
	var aid := _split_rest(effective_tile)
	var th := _theme_for_fallback(theme_name, theme_leg)
	var body := "An open area within this " + th + "."
	return {
		"title": "Area",
		"message": "Region marker **" + aid + "** in **" + th + "**.\n\n" + body,
	}


static func building_label_payload(
	effective_tile: String, theme_name: String, theme_leg: String
) -> Dictionary:
	var bid := _split_rest(effective_tile)
	var th := _theme_for_fallback(theme_name, theme_leg)
	var body := "An interesting discovery that adds to the mystery and atmosphere of your dungeon exploration."
	return {
		"title": "Building",
		"message": "Structure **" + bid + "** in **" + th + "**.\n\n" + body,
	}


static func special_feature_payload(
	effective_tile: String, theme_name: String, theme_leg: String
) -> Dictionary:
	var info := _feature_display_name(effective_tile)
	var th := _theme_for_fallback(theme_name, theme_leg)
	var label := str(info.get("name", "feature")).strip_edges()
	if label.is_empty():
		label = "mysterious feature"
	var low := label.to_lower()
	var body := (
		"**"
		+ label
		+ "**\n\nAn intriguing "
		+ low
		+ " in this "
		+ th
		+ ". Something about this "
		+ low
		+ " catches your eye and seems worth investigating further."
	)
	## Explorer `map_template.ex` title + `DescriptionService.get_discovery_fallback(:feature)` body (no dev tail).
	return {"title": "Something Interesting!", "message": body}
