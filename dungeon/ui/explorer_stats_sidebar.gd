extends Control
class_name ExplorerStatsSidebar

## Explorer `map_template.ex` desktop character dashboard — left column cards + icons.

signal rumors_pressed
signal special_items_pressed
signal achievements_pressed
signal drink_potion_pressed
signal audio_pressed

const PlayerProgression := preload("res://dungeon/progression/player_progression.gd")
const ExplorerModalChrome := preload("res://dungeon/ui/explorer_modal_chrome.gd")

const _CARD_BG := Color8(0x37, 0x41, 0x55)
const _CARD_BORDER := Color8(0x4b, 0x55, 0x66)
const _PANEL_BG := Color8(0x1e, 0x29, 0x3b)
const _PANEL_BORDER := Color8(0x30, 0x41, 0x5c)

var _texture_cb: Callable = Callable()

var _title: Label
var _outer: PanelContainer
var _scroll: ScrollContainer
var _body: VBoxContainer

var _hp_bar: ProgressBar
var _hp_value: Label
var _torch_card: Control
var _torch_value: Label
var _torch_bar: ProgressBar

var _heal_count: Label
var _drink_btn: Button

var _level_lbl: Label
var _xp_value: Label
var _xp_next: Label
var _xp_bar: ProgressBar

var _ac_val: Label
var _ab_val: Label
var _wpn_val: Label
var _dmg_val: Label
var _gold_val: Label
var _spec_val: Label
var _rum_val: Label
var _ach_val: Label
var _align_val: Label
var _align_bar: ProgressBar

var _btn_rumors: Button
var _btn_spec: Button
var _btn_ach: Button
var _audio_btn: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func set_texture_loader(cb: Callable) -> void:
	_texture_cb = cb


func _tex(basename: String) -> Texture2D:
	if _texture_cb.is_valid():
		var v: Variant = _texture_cb.call(basename)
		if v is Texture2D:
			return v as Texture2D
	return null


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _CARD_BG
	sb.set_border_width_all(1)
	sb.border_color = _CARD_BORDER
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	return sb


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = _PANEL_BG
	sb.set_border_width_all(1)
	sb.border_color = _PANEL_BORDER
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	return sb


func _mini_icon_rect(tex: Texture2D) -> TextureRect:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(22, 22)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = tex
	return tr


func _apply_bar_theme(bar: ProgressBar, fill: Color) -> void:
	var sb_bg := StyleBoxFlat.new()
	sb_bg.bg_color = Color8(0x4b, 0x55, 0x66)
	sb_bg.set_corner_radius_all(3)
	var sb_fill := StyleBoxFlat.new()
	sb_fill.bg_color = fill
	sb_fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override(&"background", sb_bg)
	bar.add_theme_stylebox_override(&"fill", sb_fill)


func _thin_bar(bar: ProgressBar, fill: Color) -> void:
	bar.custom_minimum_size = Vector2(0, 5)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 0.0
	_apply_bar_theme(bar, fill)


func _style_tile_button(btn: Button) -> void:
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_stylebox_override(&"normal", _card_style())
	btn.add_theme_stylebox_override(&"hover", _card_style())
	btn.add_theme_stylebox_override(&"pressed", _card_style())


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(268, 0)

	_outer = PanelContainer.new()
	_outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_outer.mouse_filter = Control.MOUSE_FILTER_STOP
	_outer.add_theme_stylebox_override(&"panel", _panel_style())
	add_child(_outer)

	var outer_v := VBoxContainer.new()
	outer_v.add_theme_constant_override(&"separation", 8)
	outer_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_outer.add_child(outer_v)

	_title = Label.new()
	_title.text = "Dungeon - Level 1"
	_title.add_theme_font_size_override(&"font_size", 16)
	_title.add_theme_color_override(&"font_color", Color8(0xf9, 0xfa, 0xfb))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer_v.add_child(_title)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	outer_v.add_child(_scroll)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	# HP | Torch
	var row_ht := HBoxContainer.new()
	row_ht.add_theme_constant_override(&"separation", 6)
	row_ht.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(row_ht)

	var hp_card := PanelContainer.new()
	hp_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_card.add_theme_stylebox_override(&"panel", _card_style())
	row_ht.add_child(hp_card)
	var hp_v := VBoxContainer.new()
	hp_v.add_theme_constant_override(&"separation", 4)
	hp_card.add_child(hp_v)
	var hp_top := HBoxContainer.new()
	hp_top.add_theme_constant_override(&"separation", 4)
	hp_top.add_child(_mini_icon_rect(_tex("heart.png")))
	var hp_lbl := Label.new()
	hp_lbl.text = "HP"
	hp_lbl.add_theme_font_size_override(&"font_size", 13)
	hp_lbl.add_theme_color_override(&"font_color", Color8(0xd1, 0xd5, 0xdb))
	hp_top.add_child(hp_lbl)
	_hp_value = Label.new()
	_hp_value.text = "0/0"
	_hp_value.add_theme_font_size_override(&"font_size", 13)
	_hp_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hp_top.add_child(_hp_value)
	hp_v.add_child(hp_top)
	_hp_bar = ProgressBar.new()
	_thin_bar(_hp_bar, Color8(0x22, 0xc5, 0x5e))
	hp_v.add_child(_hp_bar)

	_torch_card = PanelContainer.new()
	_torch_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_torch_card.add_theme_stylebox_override(&"panel", _card_style())
	row_ht.add_child(_torch_card)
	var torch_v := VBoxContainer.new()
	torch_v.add_theme_constant_override(&"separation", 4)
	_torch_card.add_child(torch_v)
	var torch_top := HBoxContainer.new()
	torch_top.add_theme_constant_override(&"separation", 4)
	torch_top.add_child(_mini_icon_rect(_tex("torch.png")))
	var torch_lbl := Label.new()
	torch_lbl.text = "Torch"
	torch_lbl.add_theme_font_size_override(&"font_size", 13)
	torch_lbl.add_theme_color_override(&"font_color", Color8(0xd1, 0xd5, 0xdb))
	torch_top.add_child(torch_lbl)
	_torch_value = Label.new()
	_torch_value.text = "(1)"
	_torch_value.add_theme_font_size_override(&"font_size", 13)
	_torch_value.add_theme_color_override(&"font_color", Color8(0xd1, 0xd5, 0xdb))
	_torch_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_torch_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	torch_top.add_child(_torch_value)
	torch_v.add_child(torch_top)
	_torch_bar = ProgressBar.new()
	_thin_bar(_torch_bar, Color8(0xf5, 0x9e, 0x0b))
	torch_v.add_child(_torch_bar)

	# Healing
	var heal_card := PanelContainer.new()
	heal_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal_card.add_theme_stylebox_override(&"panel", _card_style())
	_body.add_child(heal_card)
	var heal_row := HBoxContainer.new()
	heal_row.add_theme_constant_override(&"separation", 6)
	heal_card.add_child(heal_row)
	heal_row.add_child(_mini_icon_rect(_tex("healing_potion.png")))
	_heal_count = Label.new()
	_heal_count.text = "Healing (0)"
	_heal_count.add_theme_font_size_override(&"font_size", 13)
	_heal_count.add_theme_color_override(&"font_color", Color8(0xd1, 0xd5, 0xdb))
	_heal_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal_row.add_child(_heal_count)
	_drink_btn = Button.new()
	_drink_btn.text = "Drink"
	_drink_btn.tooltip_text = "Use one healing potion (Explorer use_healing_potion)"
	_drink_btn.pressed.connect(func() -> void: drink_potion_pressed.emit())
	heal_row.add_child(_drink_btn)
	ExplorerModalChrome.style_button(_drink_btn, "success", true)

	# Level / XP
	var xp_card := PanelContainer.new()
	xp_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_card.add_theme_stylebox_override(&"panel", _card_style())
	_body.add_child(xp_card)
	var xp_v := VBoxContainer.new()
	xp_v.add_theme_constant_override(&"separation", 4)
	xp_card.add_child(xp_v)
	var xp_top := HBoxContainer.new()
	xp_top.add_theme_constant_override(&"separation", 4)
	xp_top.add_child(_mini_icon_rect(_tex("xp.png")))
	_level_lbl = Label.new()
	_level_lbl.text = "Level 1"
	_level_lbl.add_theme_font_size_override(&"font_size", 13)
	_level_lbl.add_theme_color_override(&"font_color", Color8(0xd1, 0xd5, 0xdb))
	xp_top.add_child(_level_lbl)
	_xp_value = Label.new()
	_xp_value.text = "0 XP"
	_xp_value.add_theme_font_size_override(&"font_size", 13)
	_xp_value.add_theme_color_override(&"font_color", Color8(0xc0, 0x84, 0xfc))
	_xp_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_top.add_child(_xp_value)
	xp_v.add_child(xp_top)
	_xp_bar = ProgressBar.new()
	_thin_bar(_xp_bar, Color8(0xa8, 0x55, 0xf7))
	xp_v.add_child(_xp_bar)
	_xp_next = Label.new()
	_xp_next.text = "500 XP to next level"
	_xp_next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_next.add_theme_font_size_override(&"font_size", 11)
	_xp_next.add_theme_color_override(&"font_color", Color8(0x9c, 0xa3, 0xaf))
	xp_v.add_child(_xp_next)

	# AC | AB
	var row_ac := HBoxContainer.new()
	row_ac.add_theme_constant_override(&"separation", 6)
	row_ac.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(row_ac)
	var ac_card := PanelContainer.new()
	ac_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ac_card.add_theme_stylebox_override(&"panel", _card_style())
	row_ac.add_child(ac_card)
	var ac_row := HBoxContainer.new()
	ac_row.add_theme_constant_override(&"separation", 4)
	ac_card.add_child(ac_row)
	ac_row.add_child(_mini_icon_rect(_tex("shield.png")))
	var ac_l := Label.new()
	ac_l.text = "AC"
	ac_l.add_theme_font_size_override(&"font_size", 13)
	ac_l.add_theme_color_override(&"font_color", Color8(0xd1, 0xd5, 0xdb))
	ac_row.add_child(ac_l)
	_ac_val = Label.new()
	_ac_val.text = "12"
	_ac_val.add_theme_font_size_override(&"font_size", 13)
	_ac_val.add_theme_color_override(&"font_color", Color8(0x60, 0xa5, 0xfa))
	_ac_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ac_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ac_row.add_child(_ac_val)

	var ab_card := PanelContainer.new()
	ab_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ab_card.add_theme_stylebox_override(&"panel", _card_style())
	row_ac.add_child(ab_card)
	var ab_row := HBoxContainer.new()
	ab_row.add_theme_constant_override(&"separation", 4)
	ab_card.add_child(ab_row)
	ab_row.add_child(_mini_icon_rect(_tex("bullseye.png")))
	var ab_l := Label.new()
	ab_l.text = "AB"
	ab_l.add_theme_font_size_override(&"font_size", 13)
	ab_l.add_theme_color_override(&"font_color", Color8(0xd1, 0xd5, 0xdb))
	ab_row.add_child(ab_l)
	_ab_val = Label.new()
	_ab_val.text = "+1"
	_ab_val.add_theme_font_size_override(&"font_size", 13)
	_ab_val.add_theme_color_override(&"font_color", Color8(0x4a, 0xde, 0x80))
	_ab_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ab_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ab_row.add_child(_ab_val)

	# Weapon | Damage
	var row_wd := HBoxContainer.new()
	row_wd.add_theme_constant_override(&"separation", 6)
	row_wd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(row_wd)
	var w_card := PanelContainer.new()
	w_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w_card.add_theme_stylebox_override(&"panel", _card_style())
	row_wd.add_child(w_card)
	var w_row := HBoxContainer.new()
	w_row.add_theme_constant_override(&"separation", 4)
	w_card.add_child(w_row)
	w_row.add_child(_mini_icon_rect(_tex("shortsword.png")))
	_wpn_val = Label.new()
	_wpn_val.text = "Dagger"
	_wpn_val.add_theme_font_size_override(&"font_size", 13)
	_wpn_val.add_theme_color_override(&"font_color", Color8(0xff, 0xff, 0xff))
	_wpn_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wpn_val.clip_text = true
	w_row.add_child(_wpn_val)

	var d_card := PanelContainer.new()
	d_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	d_card.add_theme_stylebox_override(&"panel", _card_style())
	row_wd.add_child(d_card)
	var d_row := HBoxContainer.new()
	d_row.add_theme_constant_override(&"separation", 4)
	d_card.add_child(d_row)
	d_row.add_child(_mini_icon_rect(_tex("damage.png")))
	_dmg_val = Label.new()
	_dmg_val.text = "1d4"
	_dmg_val.add_theme_font_size_override(&"font_size", 13)
	_dmg_val.add_theme_color_override(&"font_color", Color8(0xf8, 0x71, 0x71))
	_dmg_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dmg_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	d_row.add_child(_dmg_val)

	# Gold | Special
	var row_gs := HBoxContainer.new()
	row_gs.add_theme_constant_override(&"separation", 6)
	row_gs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(row_gs)
	var g_card := PanelContainer.new()
	g_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g_card.add_theme_stylebox_override(&"panel", _card_style())
	row_gs.add_child(g_card)
	var g_row := HBoxContainer.new()
	g_row.add_theme_constant_override(&"separation", 4)
	g_card.add_child(g_row)
	g_row.add_child(_mini_icon_rect(_tex("gold.png")))
	_gold_val = Label.new()
	_gold_val.text = "0 gp"
	_gold_val.add_theme_font_size_override(&"font_size", 13)
	_gold_val.add_theme_color_override(&"font_color", Color8(0xfb, 0xbf, 0x24))
	_gold_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gold_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	g_row.add_child(_gold_val)

	_btn_spec = Button.new()
	_btn_spec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tile_button(_btn_spec)
	var spec_inner := HBoxContainer.new()
	spec_inner.add_theme_constant_override(&"separation", 4)
	_btn_spec.add_child(spec_inner)
	spec_inner.add_child(_mini_icon_rect(_tex("special_item.png")))
	_spec_val = Label.new()
	_spec_val.text = "0"
	_spec_val.add_theme_font_size_override(&"font_size", 13)
	_spec_val.add_theme_color_override(&"font_color", Color8(0x9c, 0xa3, 0xaf))
	_spec_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spec_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	spec_inner.add_child(_spec_val)
	_btn_spec.pressed.connect(func() -> void: special_items_pressed.emit())
	row_gs.add_child(_btn_spec)

	# Rumors | Achievements
	var row_ra := HBoxContainer.new()
	row_ra.add_theme_constant_override(&"separation", 6)
	row_ra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(row_ra)

	_btn_rumors = Button.new()
	_btn_rumors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tile_button(_btn_rumors)
	var rum_inner := HBoxContainer.new()
	rum_inner.add_theme_constant_override(&"separation", 4)
	_btn_rumors.add_child(rum_inner)
	rum_inner.add_child(_mini_icon_rect(_tex("open_scroll.png")))
	_rum_val = Label.new()
	_rum_val.text = "0"
	_rum_val.add_theme_font_size_override(&"font_size", 13)
	_rum_val.add_theme_color_override(&"font_color", Color8(0x9c, 0xa3, 0xaf))
	_rum_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rum_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rum_inner.add_child(_rum_val)
	_btn_rumors.pressed.connect(func() -> void: rumors_pressed.emit())
	row_ra.add_child(_btn_rumors)

	_btn_ach = Button.new()
	_btn_ach.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_tile_button(_btn_ach)
	var ach_inner := HBoxContainer.new()
	ach_inner.add_theme_constant_override(&"separation", 4)
	_btn_ach.add_child(ach_inner)
	ach_inner.add_child(_mini_icon_rect(_tex("victory.png")))
	_ach_val = Label.new()
	_ach_val.text = "0"
	_ach_val.add_theme_font_size_override(&"font_size", 13)
	_ach_val.add_theme_color_override(&"font_color", Color8(0x9c, 0xa3, 0xaf))
	_ach_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ach_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ach_inner.add_child(_ach_val)
	_btn_ach.pressed.connect(func() -> void: achievements_pressed.emit())
	row_ra.add_child(_btn_ach)

	# Alignment
	var al_card := PanelContainer.new()
	al_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	al_card.add_theme_stylebox_override(&"panel", _card_style())
	_body.add_child(al_card)
	var al_col := VBoxContainer.new()
	al_col.add_theme_constant_override(&"separation", 4)
	al_card.add_child(al_col)
	var al_row := HBoxContainer.new()
	al_row.add_theme_constant_override(&"separation", 4)
	al_col.add_child(al_row)
	al_row.add_child(_mini_icon_rect(_tex("scale.png")))
	var al_l := Label.new()
	al_l.text = "Alignment"
	al_l.add_theme_font_size_override(&"font_size", 13)
	al_l.add_theme_color_override(&"font_color", Color8(0xd1, 0xd5, 0xdb))
	al_row.add_child(al_l)
	_align_val = Label.new()
	_align_val.text = "Neutral"
	_align_val.add_theme_font_size_override(&"font_size", 13)
	_align_val.add_theme_color_override(&"font_color", Color8(0xd1, 0xd5, 0xdb))
	_align_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_align_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	al_row.add_child(_align_val)
	_align_bar = ProgressBar.new()
	_thin_bar(_align_bar, Color8(0x9c, 0xa3, 0xaf))
	al_col.add_child(_align_bar)

	_audio_btn = Button.new()
	_audio_btn.text = "Audio"
	_audio_btn.tooltip_text = "SFX and music volume"
	_audio_btn.pressed.connect(func() -> void: audio_pressed.emit())
	_body.add_child(_audio_btn)
	ExplorerModalChrome.style_button(_audio_btn, "secondary", false)


func refresh(p: Dictionary) -> void:
	var theme_title: String = str(p.get("theme_title", "Dungeon")).strip_edges()
	var dlv: int = maxi(1, int(p.get("dungeon_level", 1)))
	_title.text = theme_title + " - Level " + str(dlv)

	var hp: int = int(p.get("hp", 0))
	var mx: int = maxi(1, int(p.get("max_hp", 1)))
	var hp_frac: float = clampf(float(hp) / float(mx), 0.0, 1.0)
	_hp_value.text = str(hp) + "/" + str(mx)
	_hp_bar.value = hp_frac * 100.0
	var fill_hp := Color8(0x22, 0xc5, 0x5e)
	if hp_frac <= 0.3:
		fill_hp = Color8(0xef, 0x44, 0x44)
	elif hp_frac <= 0.6:
		fill_hp = Color8(0xea, 0xb3, 0x08)
	_apply_bar_theme(_hp_bar, fill_hp)

	var show_torch: bool = bool(p.get("show_torch", false))
	_torch_card.visible = show_torch
	if show_torch:
		var burn: int = int(p.get("torch_burn_pct", 0))
		var spare: int = int(p.get("torch_spares", 0))
		var total_torch: int = spare + 1
		_torch_value.text = "(" + str(total_torch) + ")"
		_torch_bar.value = float(clampi(burn, 0, 100))

	var pot_c: int = maxi(0, int(p.get("healing_potion_count", 0)))
	_heal_count.text = "Healing (" + str(pot_c) + ")"
	var can_drink: bool = bool(p.get("can_use_potion", false))
	ExplorerModalChrome.style_button(_drink_btn, "success", not can_drink)

	var xp: int = maxi(0, int(p.get("xp", 0)))
	var lv: int = maxi(1, int(p.get("level", 1)))
	var xp_to_next: int = maxi(0, int(p.get("xp_to_next", 0)))
	_level_lbl.text = "Level " + str(lv)
	_xp_value.text = str(xp) + " XP"
	_xp_next.text = str(xp_to_next) + " XP to next level"
	var cur_lv_xp: int = PlayerProgression.xp_required_for_level(lv)
	var next_lv_xp: int = PlayerProgression.xp_required_for_level(lv + 1)
	var span: int = maxi(1, next_lv_xp - cur_lv_xp)
	var prog: int = maxi(0, xp - cur_lv_xp)
	_xp_bar.value = (float(prog) / float(span)) * 100.0

	_ac_val.text = str(int(p.get("armor_class", 0)))
	_ab_val.text = "+" + str(int(p.get("attack_bonus", 0)))
	var wn: String = str(p.get("weapon_name", "")).strip_edges()
	if wn.length() > 10:
		wn = wn.substr(0, 10)
	_wpn_val.text = wn if not wn.is_empty() else "—"
	_dmg_val.text = str(p.get("weapon_damage_dice", "—"))

	_gold_val.text = str(int(p.get("gold", 0))) + " gp"
	var ns: int = maxi(0, int(p.get("special_item_count", 0)))
	_spec_val.text = str(ns)
	_spec_val.add_theme_color_override(
		&"font_color", Color8(0xff, 0xff, 0xff) if ns > 0 else Color8(0x9c, 0xa3, 0xaf)
	)

	var nr: int = maxi(0, int(p.get("rumors_count", 0)))
	_rum_val.text = str(nr)
	_rum_val.add_theme_color_override(
		&"font_color", Color8(0xff, 0xff, 0xff) if nr > 0 else Color8(0x9c, 0xa3, 0xaf)
	)

	var na: int = maxi(0, int(p.get("achievements_count", 0)))
	_ach_val.text = str(na)
	_ach_val.add_theme_color_override(
		&"font_color", Color8(0xff, 0xff, 0xff) if na > 0 else Color8(0x9c, 0xa3, 0xaf)
	)

	var ad: String = str(p.get("alignment_desc", "neutral")).strip_edges()
	if ad.is_empty():
		ad = "neutral"
	_align_val.text = ad.substr(0, 1).to_upper() + ad.substr(1)
	var al_col_c := Color8(0xd1, 0xd5, 0xdb)
	var av: int = int(p.get("alignment_value", 0))
	if av > 0:
		al_col_c = Color8(0x60, 0xa5, 0xfa)
	elif av < 0:
		al_col_c = Color8(0xf0, 0x71, 0xbc)
	_align_val.add_theme_color_override(&"font_color", al_col_c)
	var afill := Color8(0x60, 0xa5, 0xfa)
	if av < 0:
		afill = Color8(0xf0, 0x71, 0xbc)
	elif av == 0:
		afill = Color8(0x9c, 0xa3, 0xaf)
	_apply_bar_theme(_align_bar, afill)
	var aw: float = clampf(0.5 + float(av) / 20.0, 0.08, 1.0)
	_align_bar.value = aw * 100.0

	var net_ok: bool = bool(p.get("session_active", false))
	_btn_rumors.visible = net_ok
	_btn_spec.visible = net_ok
	_btn_ach.visible = net_ok

	var gh: bool = bool(p.get("guards_hostile", false))
	_title.tooltip_text = (
		("Guards: hostile — " if gh else "")
		+ "Theme "
		+ theme_title
		+ ", dungeon level "
		+ str(dlv)
	)
