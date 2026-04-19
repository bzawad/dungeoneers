extends RefCounted

## Server-side map transition planning (Explorer `DungeonWeb.DungeonLive.MapTransitionSystem` + helpers).
## Clients never run this for truth: they apply **`rpc_receive_authority_dungeon`** after the server
## picks a new seed and broadcasts (same idea as **`gama`** `request_map_transition` → server
## **`_handle_player_map_transition`** → **`receive_map_transition`** with fresh map state).

const DungeonThemes := preload("res://dungeon/generator/dungeon_themes.gd")
const DungeonGenerator := preload("res://dungeon/generator/dungeon_generator.gd")


static func destination_type_from_map_link_tile(tile: String) -> String:
	if tile.begins_with("cavern_entrance|"):
		return "cavern"
	if tile.begins_with("dungeon_entrance|"):
		return "dungeon"
	if tile.begins_with("cavern_exit|") or tile.begins_with("dungeon_exit|"):
		return "outdoor"
	return ""


static func get_random_destination_theme(
	rng: RandomNumberGenerator, destination_type: String, current_theme: Dictionary
) -> String:
	var themes: Array = DungeonThemes.get_themes_by_type(destination_type)
	var filtered: Array = []
	var cur_is_city := str(current_theme.get("generation_type", "")) == "city"
	for t in themes:
		if t is Dictionary:
			var d: Dictionary = t as Dictionary
			if cur_is_city and str(d.get("generation_type", "")) == "city":
				continue
			filtered.append(d)
	var pool: Array = filtered if not filtered.is_empty() else themes
	if pool.is_empty():
		var fb: Dictionary = DungeonGenerator.generate_with_player_level(rng, 1, 1)
		return str(fb.get("theme", "Ancient Castle"))
	var pick: Dictionary = pool[rng.randi_range(0, pool.size() - 1)] as Dictionary
	return str(pick.get("name", ""))


static func next_dungeon_level_after_theme_change(
	current_theme_name: String, new_theme_name: String, current_dungeon_level: int
) -> int:
	if current_theme_name == new_theme_name:
		return current_dungeon_level + 1
	return 1


## Returns `{ "theme_name": String, "dungeon_level": int }` or empty `{}` if invalid.
static func compute_transition(
	kind: String,
	raw_tile: String,
	current_theme_name: String,
	current_dungeon_level: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var cur_theme: Dictionary = DungeonThemes.find_theme_by_name(current_theme_name)
	if cur_theme.is_empty():
		cur_theme = DungeonThemes.find_theme_by_name(
			"Ancient Castle" if current_theme_name != "Dark Caverns" else "Dark Caverns"
		)
	var gen := str(cur_theme.get("generation_type", "dungeon"))
	match kind:
		"stair":
			return {
				"theme_name": current_theme_name,
				"dungeon_level":
				next_dungeon_level_after_theme_change(
					current_theme_name, current_theme_name, current_dungeon_level
				),
			}
		"waypoint":
			if gen == "city" or gen == "outdoor":
				var dest_type := "outdoor" if gen == "city" else "city"
				var dest_name := get_random_destination_theme(rng, dest_type, cur_theme)
				if dest_name.is_empty():
					return {}
				var new_level := next_dungeon_level_after_theme_change(
					current_theme_name, dest_name, current_dungeon_level
				)
				return {"theme_name": dest_name, "dungeon_level": new_level}
			return {
				"theme_name": current_theme_name,
				"dungeon_level":
				next_dungeon_level_after_theme_change(
					current_theme_name, current_theme_name, current_dungeon_level
				),
			}
		"map_link":
			var dtype := destination_type_from_map_link_tile(raw_tile)
			if dtype.is_empty():
				return {}
			var dest_theme := get_random_destination_theme(rng, dtype, cur_theme)
			if dest_theme.is_empty():
				return {}
			var nl := next_dungeon_level_after_theme_change(
				current_theme_name, dest_theme, current_dungeon_level
			)
			return {"theme_name": dest_theme, "dungeon_level": nl}
		_:
			return {}
