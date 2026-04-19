# Explorer generator parity → Dungeoneers (Godot)

Authoritative Explorer sources: [`dungeon_explorer/lib/dungeon/generator.ex`](../../dungeon_explorer/lib/dungeon/generator.ex) (dispatch + pipeline order), [`dungeon_explorer/lib/dungeon/generator/features.ex`](../../dungeon_explorer/lib/dungeon/generator/features.ex) (dice rules, special-feature registry API, placement), supporting modules [`rooms.ex`](../../dungeon_explorer/lib/dungeon/generator/rooms.ex), [`corridors.ex`](../../dungeon_explorer/lib/dungeon/generator/corridors.ex), [`caverns.ex`](../../dungeon_explorer/lib/dungeon/generator/caverns.ex), [`cities.ex`](../../dungeon_explorer/lib/dungeon/generator/cities.ex), [`grid.ex`](../../dungeon_explorer/lib/dungeon/generator/grid.ex).

Godot implementation: [`dungeon_generator.gd`](../dungeon/generator/dungeon_generator.gd), [`generator_features.gd`](../dungeon/generator/generator_features.gd), [`features_dungeon.gd`](../dungeon/generator/features_dungeon.gd), [`organic_areas.gd`](../dungeon/generator/organic_areas.gd), [`cities_generator.gd`](../dungeon/generator/cities_generator.gd), [`map_link_system.gd`](../dungeon/generator/map_link_system.gd).

Map raster / overlays remain in [`explorer_map_to_godot.md`](explorer_map_to_godot.md). Modal chrome in [`explorer_dialog_to_godot.md`](explorer_dialog_to_godot.md).

## CI drift gates (GEN-02+)

- [`check_parse.gd`](../tools/check_parse.gd): empty-theme `pick_special_feature_name` must resolve via [`special_feature_registry.json`](../dungeon/data/special_feature_registry.json) (55 rows); city encounter + city feature rules (Phase 7) below.

## Pipeline order (high level)

| Generation type | Explorer `generator.ex` | Dungeoneers `dungeon_generator.gd` |
|-----------------|-------------------------|-------------------------------------|
| Traditional | Rooms → corridors → pillars/labels/doors/stairs → map links → room traps → encounters → treasures → food → healing → torches (level-aware) → special features | Same sequence in `_generate_traditional` + `GeneratorFeatures.*` |
| Cavern | Organic areas → labels → stairs → min exits → map links → encounters → treasures → food → healing → torches (level) → special features | `_generate_cavern` |
| Outdoor | Organic areas → waypoints → min exits → map links → … (cavern-style feature set on areas) | `_generate_outdoor` |
| City | `Cities.generate` → labels → `add_waypoints_to_city_areas` → min exits → map links → city encounters → treasures/food/healing/torches → city special features | `_generate_city` + `_add_city_starting_waypoint` / `_place_city_extra_waypoints` (same waypoint intent as Explorer) |

## Traditional dungeon — rule matrix

| Rule | Explorer (`features.ex`) | Dungeoneers |
|------|--------------------------|-------------|
| Room traps (skip R1) | 1 in 20 per other room | `add_room_traps` same |
| Room encounters | 2 in 3 other rooms; side floor not center 3×3 | `add_encounters_traditional` |
| Corridor encounters | 1 in 4; pure corridor not in room | Same |
| Room treasure | 1 in 2 other rooms; trapped 1 in 10 | `add_treasures_traditional` |
| Corridor treasure | 1 in 4; trapped 1 in 4 | Same |
| Food | 1 in 4 other rooms; `:bread`/`:cheese`/`:grapes` | `add_food_traditional` |
| Healing potions | d20 ≤ 5 rooms (skip R1) and corridors | `add_healing_potions_traditional` |
| Torches | 1 in 2 other rooms; R1 forced if `level >= 2` | `add_torches_traditional_with_level` |
| Special feature count by room area | `<30`: 70% 0 / 30% 1; `<80`: 20/50/30; else 10/20/40/30 for 0–3 | `_calc_feature_count` |
| Special feature pick (theme list) | `determine_feature_rarity` 60/25/12/3; tier walk down; empty list → global rarity | `pick_special_feature_name` + registry JSON |
| Staircases (rooms) | 1–4 extra after R1 start | `DungeonFeaturesDungeon.add_staircases` |

Placement helpers mirror Explorer “avoid room label center” and `Grid.position_available_for_treasure?` via [`grid.gd`](../dungeon/generator/grid.gd) `position_available_for_treasure`.

## Cavern / outdoor (organic areas)

| Rule | Explorer | Dungeoneers |
|------|----------|-------------|
| Skip first area for encounters / food / torches / special features | Yes | `range(1, caverns.size())` etc. |
| Cavern special feature count | `max(1, div(cells,20) + d20 bonus 0/1/2)` | `add_special_features_to_caverns` |
| Healing potions | All areas, d20 ≤ 5 each | All caverns in loop |
| Cavern treasure | 1 in 2 per area; trapped `random_treasure_type` 1 in 4 | `add_treasures_to_caverns` |
| `find_cavern_position` | `:floor` or `:corridor` in area | Same string tiles |

## City

| Rule | Explorer | Dungeoneers |
|------|----------|-------------|
| Encounters on blocks (skip first block) | 2 in 3 | `add_encounters_to_city_areas` |
| Monster on building vs road | `get_monster_for_city_block`: temporary `theme` with `monsters` set to `indoor_monsters` / `outdoor_monsters`, then `Monster.get_random_monster_for_theme_with_fog_type/3` | `pick_monster_for_city_encounter` → `pick_monster_for_theme_with_fog_type` on `theme.duplicate()` with `"monsters"` swapped |
| City special features | 30% building / 40% road roll; `Enum.random` on **only** `indoor_features` / `outdoor_features`; empty list → no placement | `add_city_special_features` skips when list empty; `pick_city_feature_name` uniform index (no global registry fallback) |
| City tile string | `{:special_feature, name, name}`; LiveView may unwrap `{name, rarity}` tuples | `special_feature\|name\|name` string |

## Exports (themes + registry)

- Themes: [`export_themes_from_explorer.sh`](../tools/export_themes_from_explorer.sh) → [`themes.json`](../dungeon/data/themes.json).
- Special feature registry: [`export_special_feature_registry_from_explorer.sh`](../tools/export_special_feature_registry_from_explorer.sh) → [`special_feature_registry.json`](../dungeon/data/special_feature_registry.json) (`Dungeon.Generator.Features.dungeoneers_special_feature_registry_rows/0` in Explorer).

## Intentional deltas

- Explorer grid cells use atoms/tuples; Dungeoneers uses string encodings (`encounter|E1|Rat`, `special_feature|F1|Barrel`, …) for replication — behavior parity is rule-level, not byte-identical grid maps.
- Godot city starting waypoint + extra waypoints are implemented locally in `dungeon_generator.gd` to match Explorer outcomes (`edge_margin` 8 / waypoint margin 12 toward map edge) — see `find_city_waypoint_position` in [`generator_features.gd`](../dungeon/generator/generator_features.gd).
