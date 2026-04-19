extends RefCounted

## Explorer `Dungeon.SpecialItem.random_by_rarity_system/0` + `all_special_items/0` (static data in JSON).
## Rarity: roll 1–100 → ≤60 common, ≤85 uncommon, else rare; empty bucket → pick from full list (Explorer fallback).
## Wearable slots + stat merge: `Dungeon.PlayerStats` `wearable_slots/0`, `get_equipped_items/1`, `calculate_total_stats/3`.

const JSON_PATH := "res://dungeon/data/special_items.json"

## Same order as Explorer `@wearable_slots` (`player_stats.ex`).
const WEARABLE_SLOT_ORDER: Array[String] = [
	"weapon",
	"head",
	"neck",
	"torso",
	"back",
	"belt",
	"wrists",
	"hands",
	"finger",
	"legs",
	"feet",
	"container",
]

static var _items: Array = []
static var _by_key: Dictionary = {}
static var _loaded: bool = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_items.clear()
	_by_key.clear()
	var txt := FileAccess.get_file_as_string(JSON_PATH)
	if txt.is_empty():
		push_warning("[Dungeoneers] special_item_table: missing " + JSON_PATH)
		return
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Array:
		for v in parsed as Array:
			if v is Dictionary:
				var d: Dictionary = v as Dictionary
				var k := str(d.get("key", "")).strip_edges()
				if not k.is_empty():
					_items.append(d)
					_by_key[k] = d
	else:
		push_warning("[Dungeoneers] special_item_table: invalid JSON root")


static func all_items() -> Array:
	_ensure_loaded()
	return _items.duplicate()


static func by_rarity(rarity: String) -> Array:
	_ensure_loaded()
	var want := rarity.strip_edges().to_lower()
	var out: Array = []
	for v in _items:
		if v is Dictionary:
			var d: Dictionary = v as Dictionary
			if str(d.get("rarity", "")).strip_edges().to_lower() == want:
				out.append(d)
	return out


static func _rng_for_pick(authority_seed: int, cell: Vector2i, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(authority_seed) * 1_103_515_245
		^ int(cell.x) * 10_013
		^ int(cell.y) * 79_199
		^ int(salt) * 12_345_679
	)
	return rng


## Deterministic pick: same 60/25/15 rarity gate as Explorer `determine_rarity/0`, then index in bucket.
static func pick_deterministic(authority_seed: int, cell: Vector2i, salt: int) -> Dictionary:
	_ensure_loaded()
	if _items.is_empty():
		return {}
	var rng_pick := _rng_for_pick(authority_seed, cell, salt)
	var r100: int = rng_pick.randi_range(1, 100)
	var rarity: String
	if r100 <= 60:
		rarity = "common"
	elif r100 <= 85:
		rarity = "uncommon"
	else:
		rarity = "rare"
	var pool: Array = by_rarity(rarity)
	if pool.is_empty():
		pool = _items.duplicate()
	var idx: int = rng_pick.randi_range(0, pool.size() - 1)
	return (pool[idx] as Dictionary).duplicate(true)


static func lookup_by_key(key: String) -> Dictionary:
	_ensure_loaded()
	var k := key.strip_edges()
	if _by_key.has(k):
		return (_by_key[k] as Dictionary).duplicate(true)
	return {}


static func format_discovery_message(item: Dictionary) -> String:
	# Explorer first-find dialog: XP line only; no gold (dismiss_special_item does not grant gp).
	var nm := str(item.get("name", "Special item"))
	var desc := str(item.get("description", ""))
	var xp: int = maxi(0, int(item.get("xp_value", 0)))
	var body := nm + "\n\n" + desc
	if xp > 0:
		body += "\n\nPress OK to secure it and gain " + str(xp) + " XP."
	return body


## Explorer `view_special_item`: `name - description` (no XP prompt; re-read does not re-award).
static func format_list_view_message(item: Dictionary) -> String:
	if item.is_empty():
		return "Unknown item"
	var nm := str(item.get("name", "Special item"))
	var desc := str(item.get("description", "")).strip_edges()
	if desc.is_empty():
		return nm
	return nm + " - " + desc


static func _si_int(d: Dictionary, key: String, default_v: int = 0) -> int:
	if not d.has(key):
		return default_v
	return int(d.get(key, default_v))


static func _si_bool(d: Dictionary, key: String, default_v: bool = false) -> bool:
	if not d.has(key):
		return default_v
	return bool(d.get(key, default_v))


static func _si_str(d: Dictionary, key: String, default_v: String = "") -> String:
	return str(d.get(key, default_v)).strip_edges()


## Explorer `get_equipped_items/1`: per slot, wearable with matching `wearable_slot`, highest `xp_value`;
## ties broken by lexicographic `key` (deterministic; Explorer `Enum.max_by` order undefined on ties).
static func get_equipped_items_by_keys(keys: Array) -> Dictionary:
	_ensure_loaded()
	var wearable_items: Array = []
	for key_v in keys:
		var inv_key := str(key_v).strip_edges()
		if inv_key.is_empty():
			continue
		var row: Dictionary = lookup_by_key(inv_key)
		if row.is_empty():
			continue
		if _si_bool(row, "wearable", false):
			var sl := _si_str(row, "wearable_slot")
			if not sl.is_empty():
				wearable_items.append(row)

	var equipped: Dictionary = {}
	for slot in WEARABLE_SLOT_ORDER:
		var best: Dictionary = {}
		var best_xp: int = -1
		var best_key: String = ""
		for it in wearable_items:
			if not it is Dictionary:
				continue
			var d: Dictionary = it as Dictionary
			if _si_str(d, "wearable_slot") != slot:
				continue
			var xp: int = _si_int(d, "xp_value", 0)
			var k2 := _si_str(d, "key")
			if xp > best_xp or (xp == best_xp and k2 > best_key):
				best_xp = xp
				best_key = k2
				best = d.duplicate(true)
		if not best.is_empty():
			equipped[slot] = best
	return equipped


## Explorer `inventory_item_status/2` → "Worn" | "Stored" (non-wearable always Stored).
static func inventory_status_for_item(item: Dictionary, equipped_by_slot: Dictionary) -> String:
	if item.is_empty():
		return "Stored"
	if not _si_bool(item, "wearable", false):
		return "Stored"
	if _si_str(item, "wearable_slot").is_empty():
		return "Stored"
	var slot := _si_str(item, "wearable_slot")
	var eq_v: Variant = equipped_by_slot.get(slot, null)
	if eq_v == null or not eq_v is Dictionary:
		return "Stored"
	var eq: Dictionary = eq_v as Dictionary
	if _si_str(eq, "name") == _si_str(item, "name"):
		return "Worn"
	return "Stored"


## Apply Explorer `calculate_total_stats/3` equipment pass: armor_bonus adds to max HP and AC;
## weapon_bonus to attack; armor_bonus + dexterity_bonus to AC; weapon slot with `damage_bonus` overrides weapon + dice.
static func merge_equipment_into_stat_line(base_line: Dictionary, keys: Array) -> Dictionary:
	var out := base_line.duplicate(true)
	var equipped := get_equipped_items_by_keys(keys)
	var armor_for_hp: int = 0
	var atk_eq: int = 0
	var ac_eq: int = 0
	for slot in WEARABLE_SLOT_ORDER:
		if not equipped.has(slot):
			continue
		var it: Dictionary = equipped[slot] as Dictionary
		var ab: int = _si_int(it, "armor_bonus", 0)
		armor_for_hp += ab
		atk_eq += _si_int(it, "weapon_bonus", 0)
		ac_eq += ab
		ac_eq += _si_int(it, "dexterity_bonus", 0)
	out["max_hit_points"] = int(out.get("max_hit_points", 0)) + armor_for_hp
	out["armor_class"] = int(out.get("armor_class", 0)) + ac_eq
	out["attack_bonus"] = int(out.get("attack_bonus", 0)) + atk_eq
	var wep_v: Variant = equipped.get("weapon", null)
	if wep_v != null and wep_v is Dictionary:
		var w: Dictionary = wep_v as Dictionary
		var dmg := _si_str(w, "damage_bonus")
		if not dmg.is_empty():
			out["player_weapon"] = _si_str(w, "name")
			out["weapon_damage_dice"] = dmg
	return out
