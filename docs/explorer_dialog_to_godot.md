# Explorer LiveView dialog semantics → Dungeoneers (Godot)

**Map grid rasters & labels (Phase 5 / P7-12):** see [`explorer_map_to_godot.md`](explorer_map_to_godot.md).

Authoritative Explorer sources: [`dialog_component.ex`](../../dungeon_explorer/lib/dungeon_web/components/dialog_component.ex) (modal chrome), [`map_template.ex`](../../dungeon_explorer/lib/dungeon_web/live/dungeon_live/map_template.ex) (per-flow `color_scheme` / buttons). Godot implementation: [`explorer_modal_chrome.gd`](../dungeon/ui/explorer_modal_chrome.gd), applied from [`dungeon_session.gd`](../dungeon/ui/dungeon_session.gd).

## Class / CSS → Godot mapping

| Explorer / Tailwind | Godot |
|----------------------|--------|
| Outer `fixed inset-0 bg-black bg-opacity-25` | Native modal `Window` / `AcceptDialog` dimming (no extra `ColorRect`; OS draws dim behind `popup_window`). |
| Inner card `bg-black/25 backdrop-blur-sm rounded-lg shadow-xl border-2 border-{scheme}-400` | `Window.add_theme_stylebox_override("panel", StyleBoxFlat)` via `ExplorerModalChrome.style_window_panel` — solid dark fill + 2px border (blur not replicated). |
| Title `text-lg font-bold text-{scheme}-100` (gray → `text-white`) | `ExplorerModalChrome.style_title_label` → `font_size` 18 + `font_color`. |
| Body `whitespace-pre-wrap text-{scheme}-200` | `Label` + `style_body_label` or `style_labels_under_control` on `AcceptDialog` subtree (skips `Button` children). |
| Scroll `max-h-64 overflow-y-auto` (~256px) | `ScrollContainer.custom_minimum_size.y = ExplorerModalChrome.SCROLL_BODY_MAX_PX` (256). |
| `btn` + Daisy variant (`btn-primary`, …) | `ExplorerModalChrome.style_button` — `StyleBoxFlat` normal/hover/pressed + `font_color`; `disabled` + `modulate` alpha 0.5. |
| `btn-disabled opacity-50 cursor-not-allowed` | `Button.disabled` + `modulate = Color(1,1,1,0.5)` (when used). |
| Form sliders (client-only settings) | `ExplorerModalChrome.style_hslider` — dark track + scheme-tinted `grabber_area` / highlight (e.g. Audio window `gray`). |

## Primary modals checklist (Phase 4 acceptance)

| Modal family | Explorer reference | Dungeoneers |
|--------------|---------------------|-------------|
| **Doors** | Unlock `gray`; open door `green`; trap flows red/yellow/green via state | `_ensure_door_prompt_window` / `_apply_door_window_chrome` — custom `Window` with Explorer-style header (icon + title), body scroll (fixed max height, no vertical expand so footer is not clipped); **open door**: **Enter** + **Cancel**; **unlock**: **Pick Lock** (`lockpicks.png`, `primary`) + **Cancel** (`cancel.png`, `secondary`); **break door**: **Break door** + **Cancel**; other flows use a single **OK**. |
| **Location / labels** | `title="Location Info"`, `green`, **Continue** = `success` | `_ensure_label_location_window` / `_apply_label_location_window_chrome` — custom `Window` (not `AcceptDialog`); header icon from tile kind (`room.png`, `corridor.png`, `magnifying_glass.png`, `castle.png`); body centered. |
| **Combat** | `color_scheme="red"`, `max_width={false}`, `scrollable={false}` | `_ensure_combat_window` / `_apply_combat_window_chrome` |
| **Treasure** (resolution) | Treasure dialog `green` | `_on_encounter_resolution_dialog` title `"Treasure found"` → `apply_accept_dialog_scheme` |
| **Rumors** | Rumor dialog `gray`; list overlay gray border | List: `_apply_rumors_list_window_chrome`; detail: `AcceptDialog` via encounter resolution |
| **Special items** | Special item `blue`; list like rumors | `_apply_special_items_list_window_chrome`; detail title `"Special item"` |
| **Traps / disarm** (treasure/room) | Trap detection `red` until success (`green`); Disarm + Skip with icons | `_ensure_trapped_treasure_window` / `_ensure_room_trap_window` — `red` panel/body, scroll `SHRINK_BEGIN` + `SCROLL_BODY_MAX_PX`, **Disarm** (`lockpicks.png`) + **Skip** (`cancel.png`), compact icon row |
| **Audio** (client volumes) | N/A in Explorer web; match meta list tone (`gray` border) | `_ensure_audio_settings_window` / `_apply_audio_settings_window_chrome` — `gray` panel + body labels, `style_hslider` on SFX/Music, **Close** = `secondary` |

**Manual spot-check:** open each window in a net session and confirm border tint, body text readability, and primary vs secondary buttons match Explorer tone.

## Keyboard (dungeon session modals)

After each modal is shown, [`dungeon_session.gd`](../dungeon/ui/dungeon_session.gd) defers `grab_focus()` onto the **primary** control (Explorer-left / primary-styled action, `AcceptDialog` OK, or list **View**). **Enter** and **Space** activate the focused `Button` via Godot’s default control handling.

**Escape** / window `close_requested` follows the **secondary** path where one exists (e.g. Evade on encounter choice, Skip on trapped-treasure and room-trap prompts, cancel on stairs / map link / waypoint). Single-action dialogs (e.g. treasure discovery with only Collect) treat Escape like the primary action so client and server stay aligned. **Combat** while active intentionally does not dismiss on Escape (Explorer has no dismiss); the close handler remains a no-op.

WASD grid movement is suppressed whenever any of these modals is visible (see `_modal_blocks_grid_input` in the same file).

## CI

[`check_parse.gd`](../tools/check_parse.gd) calls `ExplorerModalChrome.assert_distinct_schemes_and_variants()` so scheme borders and button variants stay distinct.
