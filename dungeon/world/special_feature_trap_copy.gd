extends RefCounted

## Static curated lines for special-feature investigation traps (P5-01). No LLM.

const JSON_PATH := "res://dungeon/data/feature_investigation_trap_copy.json"

static var _data: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_data.clear()
	var txt := FileAccess.get_file_as_string(JSON_PATH)
	if txt.is_empty():
		push_warning("[Dungeoneers] feature trap copy: missing " + JSON_PATH)
		return
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		_data = parsed as Dictionary
	else:
		push_warning("[Dungeoneers] feature trap copy: invalid JSON")


static func _rng_pick_index(
	authority_seed: int, cell: Vector2i, feature_name: String, n: int
) -> int:
	if n <= 1:
		return 0
	var h := (
		int(authority_seed) * 1_039_513
		^ cell.x * 834_927_493
		^ cell.y * 668_265_389
		^ feature_name.hash() * 1_009
	)
	return int(abs(h)) % n


## Deterministic body text for the first-phase trap dialog (Explorer `trap_message` style, static only).
static func message_for(feature_name: String, authority_seed: int, cell: Vector2i) -> String:
	_ensure_loaded()
	var fname := feature_name.strip_edges()
	var by_feat: Variant = _data.get("by_feature", {})
	var lines: Array = []
	if by_feat is Dictionary and (by_feat as Dictionary).has(fname):
		var raw: Variant = (by_feat as Dictionary)[fname]
		if raw is Array:
			lines = raw as Array
	var def: Variant = _data.get("default", [])
	if lines.is_empty() and def is Array:
		lines = def as Array
	if lines.is_empty():
		return "Something in the " + fname + " was not meant to be touched."
	var clean: PackedStringArray = PackedStringArray()
	for x in lines:
		var s := str(x).strip_edges()
		if not s.is_empty():
			clean.append(s)
	if clean.is_empty():
		return "Something in the " + fname + " was not meant to be touched."
	var idx := _rng_pick_index(authority_seed, cell, fname, clean.size())
	return clean[idx]
