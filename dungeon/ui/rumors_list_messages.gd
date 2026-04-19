extends RefCounted

## Static copy for the rumors list window vs Explorer HEEx
## `DungeonWeb.DungeonLive.MapTemplate` (~2653–2691): learned rumors dialog.

const WINDOW_TITLE := "Learned Rumors"

const EMPTY_STATE := "No rumors have been discovered yet. Investigate special features to learn rumors!"

const HINT_WHEN_HAS_RUMORS := "Click on any rumor to view it in detail:"

const PREVIEW_MAX_CHARS := 120


static func list_preview_body(full: String) -> String:
	var one: String = str(full).replace("\n", " ").strip_edges()
	if one.length() > PREVIEW_MAX_CHARS:
		return one.substr(0, PREVIEW_MAX_CHARS) + "..."
	return one


static func list_item_text(index_zero_based: int, full: String) -> String:
	return "%d. %s" % [index_zero_based + 1, list_preview_body(full)]
