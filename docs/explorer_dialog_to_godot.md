# Explorer LiveView dialog semantics → Dungeoneers (Godot)

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

## Primary modals checklist (Phase 4 acceptance)

| Modal family | Explorer reference | Dungeoneers |
|--------------|---------------------|-------------|
| **Doors** | Unlock `gray`; open door `green`; trap flows red/yellow/green via state | `_ensure_door_prompt_window` / `_apply_door_window_chrome` |
| **Combat** | `color_scheme="red"`, `max_width={false}`, `scrollable={false}` | `_ensure_combat_window` / `_apply_combat_window_chrome` |
| **Treasure** (resolution) | Treasure dialog `green` | `_on_encounter_resolution_dialog` title `"Treasure found"` → `apply_accept_dialog_scheme` |
| **Rumors** | Rumor dialog `gray`; list overlay gray border | List: `_apply_rumors_list_window_chrome`; detail: `AcceptDialog` via encounter resolution |
| **Special items** | Special item `blue`; list like rumors | `_apply_special_items_list_window_chrome`; detail title `"Special item"` |
| **Traps / disarm** (treasure/room) | Trap detection red/green; disarm UI primary/secondary | `_apply_trapped_treasure_window_chrome` / `_apply_room_trap_window_chrome` (`yellow` caution panel) |

**Manual spot-check:** open each window in a net session and confirm border tint, body text readability, and primary vs secondary buttons match Explorer tone.

## CI

[`check_parse.gd`](../tools/check_parse.gd) calls `ExplorerModalChrome.assert_distinct_schemes_and_variants()` so scheme borders and button variants stay distinct.
