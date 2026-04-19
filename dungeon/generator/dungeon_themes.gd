extends RefCounted

## Loads `Dungeon.Themes` data exported to `res://dungeon/data/themes.json`.

const THEMES_PATH := "res://dungeon/data/themes.json"

static var _themes_cache: Array = []


static func load_themes() -> Array:
	if not _themes_cache.is_empty():
		return _themes_cache
	var f := FileAccess.open(THEMES_PATH, FileAccess.READ)
	if f == null:
		push_error("[DungeonThemes] missing " + THEMES_PATH)
		return []
	var txt := f.get_as_text()
	var p := JSON.new()
	var err := p.parse(txt)
	if err != OK:
		push_error("[DungeonThemes] JSON parse error " + str(err))
		return []
	var root = p.data
	if root is Array:
		_themes_cache = root as Array
	return _themes_cache


static func find_theme_by_name(theme_name: String) -> Dictionary:
	for t in load_themes():
		if t is Dictionary and str(t.get("name", "")) == theme_name:
			return t as Dictionary
	return {}


static func get_random_theme(rng: RandomNumberGenerator) -> Dictionary:
	var arr := load_themes()
	if arr.is_empty():
		return {}
	return arr[rng.randi_range(0, arr.size() - 1)] as Dictionary


static func get_themes_by_type(generation_type: String) -> Array:
	var out: Array = []
	for t in load_themes():
		if t is Dictionary and str((t as Dictionary).get("generation_type", "")) == generation_type:
			out.append(t)
	return out
