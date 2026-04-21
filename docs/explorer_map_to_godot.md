# Explorer map raster parity → Dungeoneers (Godot)

Authoritative Explorer sources: [`map_template.ex`](../../dungeon_explorer/lib/dungeon_web/live/dungeon_live/map_template.ex) (per-tile overlays, label chrome), [`renderer.ex`](../../dungeon_explorer/lib/dungeon_web/live/dungeon_live/renderer.ex) (terrain / fog), [`features.ex`](../../dungeon_explorer/lib/dungeon/generator/features.ex) (`get_special_feature_image_path/1`).

Godot implementation: [`map_cell_overlay_art.gd`](../dungeon/ui/map_cell_overlay_art.gd), [`dungeon_grid_view.gd`](../dungeon/ui/dungeon_grid_view.gd) (`MapCellOverlays` + `_sync_map_cell_overlays`), [`dungeon_tile_assets.gd`](../dungeon/ui/dungeon_tile_assets.gd) (terrain / decor / fog), [`dungeon_door_overlays.gd`](../dungeon/ui/dungeon_door_overlays.gd).

Modal / dialog chrome remains documented in [`explorer_dialog_to_godot.md`](explorer_dialog_to_godot.md) (Phase 4 / P7-11).

## Map tile → Godot mapping

| Explorer surface | Dungeoneers |
|------------------|-------------|
| Floor / wall / corridor / shrub / road tilesets + opacity bands | `DungeonTileAssets` `TileMapLayer` + `_apply_generation_layer_modulate` |
| Fog pattern + `fog_opacity_class` | Three fog atlas sources on `_tile_layer` |
| Door half-barrier + lock / trap / secret | `DungeonDoorOverlays` |
| Stairs + pillar decor | `Decor` `TileMapLayer` + `decor_source_atlas` |
| `encounter` monster portrait | `EncounterMapToken` + `_sync_encounter_monster_tokens` |
| Treasure / trapped treasure / room trap / torch / consumables / quest item | `MapCellOverlayArt` → `MapCellOverlays` `TextureRect` children |
| Special feature raster (`get_feature_image_path`) | Registry JSON `image` + `size` (from Explorer export) → scaled `TextureRect`; **Pillar** stays decor-only (no second icon) |
| Waypoints / starting waypoint / map link entrances & exits | `map_links/*.png` overlays; large links centered with negative inset (Explorer `overflow-visible` spirit) |
| Room / corridor / area / building labels (`text-[14px]` + dark pill) | `Label` + `StyleBoxFlat` on `normal`; font scaled from 48px reference cell |
| Stair arrows + waypoint / stair labels (`text-[20px]` `text-green-600`) | `↑` `↓` glyphs + Tailwind **green-600** (`#16a34a`) + outline |

## Party marker & movement semantics

Authoritative Explorer sources: [`movement.ex`](../../dungeon_explorer/lib/dungeon_web/live/dungeon_live/movement.ex) (walkability, pathfinding flags, facing on keyboard step), [`map_template.ex`](../../dungeon_explorer/lib/dungeon_web/live/dungeon_live/map_template.ex) (`get_player_sprite_path/3` — sprite index per facing + torch/daylight).

Godot: [`party_marker_art.gd`](../dungeon/ui/party_marker_art.gd), [`dungeon_grid_view.gd`](../dungeon/ui/dungeon_grid_view.gd) `sync_peer_marker`, 4-dir A\* in [`grid_pathfinding.gd`](../dungeon/movement/grid_pathfinding.gd), authoritative **stepped** path execution in [`dungeon_replication.gd`](../dungeon/network/dungeon_replication.gd) `_server_handle_path_move` (timer between cells, same cadence as historical `PATH_VISUAL_STEP_SEC` / Explorer queued `move_player`).

| Topic | Explorer | Dungeoneers |
|-------|----------|-------------|
| Map token sprite index `N` in `rogue2_N.png` | `0` = south (`:forward`), `1` = north (`:back`), `2` = west (`:left`), `3` = east (`:right`) | Same `0..3` as `PartyMarkerArt.FACING_*` / **gama**-style down, up, left, right |
| Facing from a grid step | [`update_facing_direction/2`](../../dungeon_explorer/lib/dungeon_web/live/dungeon_live/movement.ex): non-zero `dx` picks left/right before `dy` | `PartyMarkerArt.facing_from_grid_step`: horizontal preferred when abs(dx) ≥ abs(dy) (matches Explorer on orthogonal steps; same formula if a diagonal step were ever shown) |
| Click / path shape | Web client **4-dir** A\* between cells | **4-dir** (Manhattan) A\* — aligned with Explorer; no diagonal corner cuts |
| Click planning + wall remap | `PathfindingHook`: full `walkability` grid (no fog); unwalkable tile → first cardinal walkable neighbor (+x, −x, +y, −y) | `path_click_goal_cell` + `find_path_4dir(..., plan_ignore_fog true)` in `dungeon_session.gd`; **server** still enforces `square_revealed` per step like Explorer `valid_movement?` |
| Path onto locked door | Stop before tile; door flow | Same: stop at last walkable cell, `_server_handle_door_click` |
| Pathfinding vs dialogs | `is_pathfinding: true` suppresses some NPC / stair / waypoint dialogs mid-path | Server applies `_apply_authorized_move` once per path cell (with step delay); client path preview + move SFX follow each `player_position_updated` |

**Optional walk-cycle art:** with only `rogue*_0..3.png` synced, the marker shows a static facing frame. Extra in-betweens use optional files next to the base PNG, e.g. `rogue2_0_w1.png`, `rogue2_0_w2.png` for facing `0` (and the same `fighter*` / `rogue1` / `rogue2` basename order as facing art). When two or more frames exist for a facing, `sync_peer_marker` uses an `AnimatedTexture` for the move tween, then restores the static facing texture.

## Data & export

- [`special_feature_registry.json`](../dungeon/data/special_feature_registry.json) includes **`image`** and **`size`** per feature, regenerated from Explorer via [`export_special_feature_registry_from_explorer.sh`](../tools/export_special_feature_registry_from_explorer.sh) → [`tools/export_dungeoneers_data.exs`](../../dungeon_explorer/tools/export_dungeoneers_data.exs) (`registry` command).

## Intentional static substitutes

| Explorer | Dungeoneers |
|----------|-------------|
| CSS `torch-flicker` / quest glow keyframe animations | Static textures only (no flicker / glow animation) |
| `room_trap` bounce when sprung | Static trap icon (no bounce) |
| Some features sized >1 cell in LiveView | Same PNG scaled from Explorer `size` field into the 64px cell (may feel tighter than web overflow) |

## Manual spot-check

With [`sync_explorer_assets.sh`](../tools/sync_explorer_assets.sh) run against a full Explorer `priv/static/images/` tree: compare torch, treasure, trapped treasure (after fog click reveals the door-trap warning glyph per Explorer `show_trap_warning?`), a special feature, waypoint, and a map link entrance on the same seed/theme as Explorer.
