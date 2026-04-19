extends RefCounted

## Phase 6: small on-map token for `encounter|…|MonsterName` using Explorer `images/monsters/*.png` sync.

const MonsterTable := preload("res://dungeon/combat/monster_table.gd")
const MON_DIR := "res://assets/explorer/images/monsters/"


static func monster_name_from_encounter_tile(tile: String) -> String:
	if not tile.begins_with("encounter|"):
		return ""
	var parts := tile.split("|")
	return parts[2].strip_edges() if parts.size() > 2 else ""


static func texture_for_encounter_tile(tile: String) -> Texture2D:
	var mname := monster_name_from_encounter_tile(tile)
	if mname.is_empty():
		return null
	var def: Dictionary = MonsterTable.lookup_monster(mname)
	var img := str(def.get("image", "")).strip_edges()
	if img.is_empty():
		return null
	var path := MON_DIR + img
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as Texture2D
