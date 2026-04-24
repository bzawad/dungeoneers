extends RefCounted

## Explorer `DungeonWeb.DungeonLive.MapTemplate.convert_size_to_css_classes/1` at 48px cell base
## (`size_classes_*` in `map_template.ex`). Shared by on-map **monsters** and **special features**
## (`get_monster_image_size` / `get_feature_image_size`).


static func base_px_from_size(size: float) -> int:
	var s := size
	if s > 3.0:
		return 48
	if s <= 0.5:
		if _size_key_eq(s, 0.25):
			return 12
		if _size_key_eq(s, 0.5):
			return 24
		return 24
	if s <= 1.0:
		if _size_key_eq(s, 0.75):
			return 36
		return 48
	if s <= 2.0:
		if _size_key_eq(s, 1.25):
			return 60
		if _size_key_eq(s, 1.5):
			return 72
		if _size_key_eq(s, 1.75):
			return 84
		if _size_key_eq(s, 2.0):
			return 96
		return 96
	if _size_key_eq(s, 2.25):
		return 108
	if _size_key_eq(s, 2.5):
		return 120
	if _size_key_eq(s, 2.75):
		return 132
	if _size_key_eq(s, 3.0):
		return 144
	return 144


static func _size_key_eq(a: float, b: float) -> bool:
	return absf(a - b) < 0.001
