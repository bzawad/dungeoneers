extends RefCounted
## Explorer [`DialogComponent`](dungeon_explorer/lib/dungeon_web/components/dialog_component.ex) /
## DaisyUI-ish colors as Godot theme overrides (Phase 4 / P7-11).

const SCROLL_BODY_MAX_PX := 256
const BTN_MIN_HEIGHT_PX := 40
## Modal footer rows with `.icon` (door, encounter, special feature, combat): matches `dungeon_session` compact rows.
const MODAL_ACTION_BTN_MIN_HEIGHT_PX := 32
const MODAL_ACTION_ICON_MAX_WIDTH_PX := 20
## Explorer `DialogComponent` default `max_width` → Tailwind `max-w-lg` (32rem).
const DIALOG_MAX_W_PX := 512
## Readable column floor (treasure modal 480px; avoids AcceptDialog+autowrap collapsing to a skinny column).
const DIALOG_TARGET_BODY_W_PX := 480


static func normalize_scheme(scheme: String) -> String:
	var s := scheme.strip_edges().to_lower()
	match s:
		"blue", "green", "red", "yellow", "gray":
			return s
		_:
			return "blue"


## Tailwind `border-*-400` approximations from `dialog_component.ex`.
static func border_color_for_scheme(scheme: String) -> Color:
	match normalize_scheme(scheme):
		"blue":
			return Color8(0x60, 0xA5, 0xFA)
		"green":
			return Color8(0x4A, 0xDE, 0x80)
		"red":
			return Color8(0xF8, 0x71, 0x71)
		"yellow":
			return Color8(0xFA, 0xCC, 0x15)
		"gray", _:
			return Color8(0x9C, 0xA3, 0xAF)


## Title: `text-*-100` (gray uses white like Explorer `text-white`).
static func title_color_for_scheme(scheme: String) -> Color:
	match normalize_scheme(scheme):
		"blue":
			return Color8(0xDB, 0xEA, 0xFE)
		"green":
			return Color8(0xDC, 0xFC, 0xE7)
		"red":
			return Color8(0xFE, 0xE2, 0xE2)
		"yellow":
			return Color8(0xFE, 0xF9, 0xC3)
		"gray", _:
			return Color8(0xFF, 0xFF, 0xFF)


## Body: `text-*-200` (Explorer dialog content).
static func content_color_for_scheme(scheme: String) -> Color:
	match normalize_scheme(scheme):
		"blue":
			return Color8(0xBF, 0xDB, 0xFE)
		"green":
			return Color8(0xBB, 0xF7, 0xD0)
		"red":
			return Color8(0xFE, 0xCA, 0xCA)
		"yellow":
			return Color8(0xFE, 0xF0, 0x8A)
		"gray", _:
			return Color8(0xE5, 0xE7, 0xEB)


static func panel_stylebox_for_scheme(scheme: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.06, 0.92)
	sb.border_color = border_color_for_scheme(scheme)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	return sb


static func style_window_panel(w: Window, scheme: String) -> void:
	if w == null:
		return
	var sb := panel_stylebox_for_scheme(scheme)
	w.add_theme_stylebox_override(&"panel", sb)


static func apply_accept_dialog_scheme(
	d: AcceptDialog, scheme: String, ok_variant: String = "primary"
) -> void:
	if d == null:
		return
	style_window_panel(d, scheme)
	style_labels_under_control(d, content_color_for_scheme(scheme))
	var ok := d.get_ok_button()
	if ok != null:
		style_button(ok, ok_variant, false)


## `ConfirmationDialog` follows host OS button order (often Cancel left, OK right). Explorer modals use
## **primary left, Skip / Cancel right** (same as custom `HBoxContainer` footers in `dungeon_session`).
static func arrange_confirmation_footer_primary_left_cancel_right(
	ok_btn: Button, cancel_btn: Button
) -> void:
	if ok_btn == null or cancel_btn == null:
		return
	var p := ok_btn.get_parent()
	if p == null or cancel_btn.get_parent() != p:
		return
	if ok_btn.get_index() > cancel_btn.get_index():
		p.move_child(ok_btn, cancel_btn.get_index())


## Cap width and wrap body text like Explorer `DialogComponent` (`max-w-lg` + `whitespace-pre-wrap`).
static func configure_accept_dialog_body_layout(
	d: AcceptDialog, max_width_px: int = DIALOG_MAX_W_PX
) -> void:
	if d == null:
		return
	var cap := maxi(280, max_width_px)
	d.max_size = Vector2i(cap, 100000)
	var min_w := mini(DIALOG_TARGET_BODY_W_PX, cap)
	d.min_size = Vector2i(min_w, 0)
	var lb: Label = d.get_label()
	if lb == null:
		return
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func style_accept_dialog(d: AcceptDialog, scheme: String) -> void:
	apply_accept_dialog_scheme(d, scheme, "primary")


static func style_labels_under_control(root: Node, content_color: Color) -> void:
	if root == null:
		return
	_style_labels_recursive(root, content_color)


static func _style_labels_recursive(n: Node, content_color: Color) -> void:
	if n is Button:
		return
	if n is Label:
		var lb := n as Label
		lb.add_theme_color_override(&"font_color", content_color)
	for c in n.get_children():
		_style_labels_recursive(c, content_color)


static func style_title_label(lb: Label, scheme: String) -> void:
	if lb == null:
		return
	lb.add_theme_color_override(&"font_color", title_color_for_scheme(scheme))
	lb.add_theme_font_size_override(&"font_size", 18)


static func style_body_label(lb: Label, scheme: String) -> void:
	if lb == null:
		return
	lb.add_theme_color_override(&"font_color", content_color_for_scheme(scheme))


static func style_button(btn: Button, variant: String, disabled: bool) -> void:
	if btn == null:
		return
	var v := variant.strip_edges().to_lower()
	var bg := Color8(0x25, 0x63, 0xEB)
	var fg := Color8(0xFF, 0xFF, 0xFF)
	match v:
		"secondary":
			bg = Color8(0x4B, 0x55, 0x63)
			fg = Color8(0xF3, 0xF4, 0xF6)
		"success":
			bg = Color8(0x16, 0xA3, 0x4A)
			fg = Color8(0xFF, 0xFF, 0xFF)
		"warning":
			bg = Color8(0xEA, 0xB3, 0x08)
			fg = Color8(0x11, 0x11, 0x11)
		"error":
			bg = Color8(0xDC, 0x26, 0x26)
			fg = Color8(0xFF, 0xFF, 0xFF)
		"info":
			bg = Color8(0x0E, 0xA5, 0xE9)
			fg = Color8(0xFF, 0xFF, 0xFF)
		"primary", _:
			pass
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_right = 14.0
	sb.content_margin_bottom = 8.0
	btn.add_theme_stylebox_override(&"normal", sb.duplicate())
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = bg.lightened(0.08)
	btn.add_theme_stylebox_override(&"hover", sb_h)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = bg.darkened(0.12)
	btn.add_theme_stylebox_override(&"pressed", sb_p)
	btn.add_theme_color_override(&"font_color", fg)
	btn.add_theme_color_override(&"font_hover_color", fg)
	btn.add_theme_color_override(&"font_pressed_color", fg)
	btn.custom_minimum_size.y = maxf(btn.custom_minimum_size.y, float(BTN_MIN_HEIGHT_PX))
	btn.disabled = disabled
	btn.focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	if disabled:
		btn.modulate = Color(1.0, 1.0, 1.0, 0.5)
	else:
		btn.modulate = Color.WHITE


## Call after `style_button` on modal action buttons so Explorer-sized PNG icons do not dominate the row.
static func tighten_button_for_modal_icon_row(btn: Button) -> void:
	if btn == null:
		return
	const MARGIN_H := 10.0
	const MARGIN_V := 4.0
	btn.custom_minimum_size = Vector2(0, MODAL_ACTION_BTN_MIN_HEIGHT_PX)
	btn.add_theme_font_size_override(&"font_size", 14)
	btn.add_theme_constant_override(&"icon_max_width", MODAL_ACTION_ICON_MAX_WIDTH_PX)
	for sn: StringName in [&"normal", &"hover", &"pressed"]:
		var sb0: Variant = btn.get_theme_stylebox(sn)
		if sb0 is StyleBoxFlat:
			var sb := (sb0 as StyleBoxFlat).duplicate() as StyleBoxFlat
			sb.content_margin_left = MARGIN_H
			sb.content_margin_right = MARGIN_H
			sb.content_margin_top = MARGIN_V
			sb.content_margin_bottom = MARGIN_V
			btn.add_theme_stylebox_override(sn, sb)


## Outer plate + list fill so the scroll body matches Explorer list dialogs (`bg-gray-800` frame).
static func wrap_item_list_in_plated_panel(il: ItemList) -> PanelContainer:
	if il == null:
		return null
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color8(0x1F, 0x29, 0x37)
	outer.border_color = Color8(0x4B, 0x55, 0x63)
	outer.set_border_width_all(1)
	outer.set_corner_radius_all(6)
	# Do NOT add vertical padding here: the calling windows already give the list a fixed
	# `SCROLL_BODY_MAX_PX` minimum height, and extra margins would push footer buttons out.
	outer.set_content_margin_all(0)
	pc.add_theme_stylebox_override(&"panel", outer)
	il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	il.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inner := StyleBoxFlat.new()
	inner.bg_color = Color8(0x1F, 0x29, 0x37)
	inner.set_border_width_all(0)
	inner.set_corner_radius_all(4)
	il.add_theme_stylebox_override(&"panel", inner)
	il.add_theme_color_override(&"font_color", Color8(0xE5, 0xE7, 0xEB))
	il.add_theme_color_override(&"guide_color", Color8(0x4B, 0x55, 0x63))
	pc.add_child(il)
	return pc


static func scheme_for_encounter_resolution_title(title: String) -> String:
	match title:
		"Treasure found", "Victory", "Quest accepted":
			return "green"
		"Rumor":
			return "gray"
		"Special item":
			return "blue"
		"Trap triggered", "Defeat", "Evade failed", "Feature trap":
			return "red"
		"Achievement":
			return "yellow"
		"Declined":
			return "gray"
		_:
			return "blue"


static func ok_variant_for_encounter_resolution_title(title: String) -> String:
	match title:
		"Treasure found", "Victory", "Quest accepted":
			return "success"
		"Rumor":
			return "info"
		"Special item":
			return "primary"
		"Declined":
			return "secondary"
		_:
			return "primary"


static func scheme_for_door_action(action: String, message: String) -> String:
	var msg := message.to_lower()
	match action:
		"pass":
			return "green"
		"break_result":
			if msg.contains("fail") or msg.contains("unable") or msg.contains("not break"):
				return "red"
			return "green"
		"trap_disarm_result":
			if msg.contains("fail") or msg.contains("damage"):
				return "red"
			return "green"
		"trap_sprung", "trap_detected":
			return "red"
		_:
			return "gray"


static func scheme_for_world_kind_title(kind: String, title: String) -> String:
	if kind == "encounter_npc":
		return "blue"
	if kind == "quest_item_pickup" and title == "Quest Completed!":
		return "blue"
	if kind == "treasure":
		return "green"
	if kind == "waypoint":
		return "green"
	if kind == "stair" or kind == "map_link":
		return "blue"
	if kind == "trapped_treasure_undetected" or kind == "room_trap_undetected":
		return "yellow"
	return "green"


static func ok_variant_for_world_kind(kind: String, title: String) -> String:
	if kind == "encounter_npc":
		return "secondary"
	if kind == "quest_item_pickup" and title == "Quest Completed!":
		return "success"
	if kind == "treasure":
		return "success"
	if kind in ["food_pickup", "healing_potion_pickup", "torch_pickup"]:
		return "success"
	return "primary"


## CI sanity: schemes differ; variants differ.
static func assert_distinct_schemes_and_variants() -> String:
	var seen_border: Dictionary = {}
	for s in ["blue", "green", "red", "yellow", "gray"]:
		var c := border_color_for_scheme(s)
		var k := "%d,%d,%d" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]
		if seen_border.has(k):
			return "duplicate border for scheme " + s
		seen_border[k] = true
	var cols: Array[Color] = []
	for v in ["primary", "secondary", "success", "warning", "error", "info"]:
		var b := Button.new()
		style_button(b, v, false)
		var sb := b.get_theme_stylebox(&"normal") as StyleBoxFlat
		if sb == null:
			b.free()
			return "missing stylebox for " + v
		cols.append(sb.bg_color)
		b.free()
	for i in range(cols.size()):
		for j in range(i + 1, cols.size()):
			if cols[i].is_equal_approx(cols[j]):
				return "variant colors too close"
	return ""
