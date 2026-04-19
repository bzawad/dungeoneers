extends RefCounted

## Explorer `DungeonWeb.DungeonLive.MonsterTurnSystem` (first Godot slice): after a player move, **hunting**
## encounter monsters may hear the player (DC 10), path up to **4** orthogonal steps (doors blocked), move
## onto the player’s ring, then **start interactive combat** when king-adjacent.
## **Guards / NPCs:** Explorer `hostile_monster?` — **Guard** hunts if `guards_hostile` **or** lawful/chaotic clash with player; **NPC** hunts only on alignment clash; normal monsters use **`hunts_player`** (CSV).
##
## **CMB-02:** Explorer applies `Enum.reduce(monsters_in_viewport, socket, …)` — one ordered pass over a
## **snapshot** of hunters; each step mutates the grid. Dungeoneers matches that via
## `process_monster_reduce_pass` (combat is **immediate** here; Explorer uses `Process.send_after` for combat UI).

const GridWalk := preload("res://dungeon/movement/grid_walkability.gd")
const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const DungeonFeatures := preload("res://dungeon/generator/features_dungeon.gd")
const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")
const PlayerAlignment := preload("res://dungeon/progression/player_alignment.gd")
const MonsterTable := preload("res://dungeon/combat/monster_table.gd")

const MAX_MONSTER_MOVE_EDGES := 4
## Explorer `MonsterTurnSystem`: hear player on d20 ≥ 10.
const HEARING_DC := 10
## Explorer `dungeon_live.ex` desktop viewport (`get_viewport_size` → 16×16 cells), centered on mover.
const VIEWPORT_CELLS_W := 16
const VIEWPORT_CELLS_H := 16


static func encounter_monster_name_from_tile(tile: String) -> String:
	var parts := tile.split("|")
	return parts[2].strip_edges() if parts.size() > 2 else "monster"


## Explorer `MonsterTurnSystem.hostile_monster?/3` — `player_alignment` is numeric Explorer value.
static func effective_hunts(def: Dictionary, guards_hostile: bool, player_alignment: int) -> bool:
	if def.is_empty():
		return false
	var role := str(def.get("role", "")).strip_edges().to_lower()
	var m_align := str(def.get("alignment", "neutral")).strip_edges().to_lower()
	if role == "quest_npc":
		return false
	if role == "quest_monster":
		return true
	var clash := PlayerAlignment.npc_hostile_to_player(m_align, player_alignment)
	if role == "npc":
		return clash
	if role == "guard":
		return guards_hostile or clash
	return bool(def.get("hunts_player", false))


static func monster_tile_walkable_for_pathfinding(tile: String) -> bool:
	if DungeonFeatures.is_door_tile(tile):
		return false
	if GridWalk.is_locked_door_tile(tile):
		return false
	## Encounter cells host monsters; `GridWalk.is_walkable_tile` excludes them (player rules).
	if tile.begins_with("encounter|"):
		return true
	return GridWalk.is_walkable_tile(tile)


## Orthogonal BFS; returns **full** path from `from` to `to` inclusive, or empty.
static func bfs_path_orthogonal(
	grid: Dictionary,
	from: Vector2i,
	to: Vector2i,
	trap_defused: Dictionary,
	max_edges: int,
	fog_enabled: bool,
	revealed: Dictionary
) -> Array[Vector2i]:
	if fog_enabled and not DungeonFog.square_revealed(from, revealed, true):
		return []
	if from == to:
		return [from]
	var prev: Dictionary = {}
	var depth: Dictionary = {}
	var q: Array[Vector2i] = [from]
	prev[from] = from
	depth[from] = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var qi := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		if cur == to:
			break
		if int(depth[cur]) >= max_edges:
			continue
		for d: Vector2i in dirs:
			var nxt: Vector2i = cur + d
			if (
				nxt.x < 0
				or nxt.y < 0
				or nxt.x >= DungeonGrid.MAP_WIDTH
				or nxt.y >= DungeonGrid.MAP_HEIGHT
			):
				continue
			if prev.has(nxt):
				continue
			if fog_enabled and not DungeonFog.square_revealed(nxt, revealed, true):
				continue
			var t: String = GridWalk.tile_effective(grid, nxt, trap_defused)
			if not monster_tile_walkable_for_pathfinding(t):
				continue
			prev[nxt] = cur
			depth[nxt] = int(depth[cur]) + 1
			q.append(nxt)

	if not prev.has(to):
		return []

	var chain: Array[Vector2i] = []
	var p := to
	while p != from:
		chain.append(p)
		p = prev[p]
	chain.reverse()
	var out: Array[Vector2i] = [from]
	for c: Vector2i in chain:
		out.append(c)
	return out


static func _player_adjacent_targets(player: Vector2i) -> Array[Vector2i]:
	return [
		player + Vector2i(1, 0),
		player + Vector2i(-1, 0),
		player + Vector2i(0, 1),
		player + Vector2i(0, -1),
	]


static func best_path_to_adjacent_ring(
	grid: Dictionary,
	monster_cell: Vector2i,
	player: Vector2i,
	trap_defused: Dictionary,
	fog_enabled: bool,
	revealed: Dictionary
) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_len := 999
	for tgt in _player_adjacent_targets(player):
		var pth := bfs_path_orthogonal(
			grid, monster_cell, tgt, trap_defused, MAX_MONSTER_MOVE_EDGES, fog_enabled, revealed
		)
		if pth.is_empty():
			continue
		var edges := pth.size() - 1
		if edges > MAX_MONSTER_MOVE_EDGES:
			continue
		if edges < best_len:
			best_len = edges
			best = pth
	return best


## Explorer `MonsterTurnSystem.get_monsters_in_viewport`: nested **x then y** over a player-centered window.
static func collect_encounter_cells_viewport(
	grid: Dictionary, center: Vector2i, viewport_w: int, viewport_h: int
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var vw := clampi(viewport_w, 1, DungeonGrid.MAP_WIDTH)
	var vh := clampi(viewport_h, 1, DungeonGrid.MAP_HEIGHT)
	var half_x := vw >> 1
	var half_y := vh >> 1
	var vx := clampi(center.x - half_x, 0, maxi(0, DungeonGrid.MAP_WIDTH - vw))
	var vy := clampi(center.y - half_y, 0, maxi(0, DungeonGrid.MAP_HEIGHT - vh))
	for x in range(vx, vx + vw):
		for y in range(vy, vy + vh):
			var c := Vector2i(x, y)
			var t: String = str(grid.get(c, ""))
			if t.begins_with("encounter|"):
				out.append(c)
	return out


## Deterministic d20 used for hearing (`randi_range(1, 20)` vs `HEARING_DC`). Exposed for CI ordering tests.
static func monster_hearing_roll_value(authority_seed: int, mover_peer: int, cell: Vector2i) -> int:
	var h := rng_for_monster(authority_seed, mover_peer, cell, 41)
	return h.randi_range(1, 20)


static func rng_for_monster(
	authority_seed: int, peer_id: int, cell: Vector2i, salt: int
) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(authority_seed)
		^ int(peer_id) * 1_000_003
		^ cell.x * 9176
		^ cell.y * 131_071
		^ int(salt) * 265_443_5761
	)
	return rng


static func underlying_after_encounter_leaves(cell: Vector2i, rooms: Array) -> String:
	return "floor" if DungeonGrid.point_in_any_room(cell, rooms) else "corridor"


## After earlier monsters in the same reduce pass moved, the encounter `raw_tile` may no longer sit on
## `snap_cell`. Scan **viewport iteration order** and return the first cell whose tile equals `raw_tile`.
## Returns `Vector2i(-1, -1)` if absent (monster left viewport or tile was destroyed).
static func resolve_live_encounter_cell(
	grid: Dictionary, viewport_cells: Array[Vector2i], snap_cell: Vector2i, raw_tile: String
) -> Vector2i:
	if str(grid.get(snap_cell, "")) == raw_tile:
		return snap_cell
	for c: Vector2i in viewport_cells:
		if str(grid.get(c, "")) == raw_tile:
			return c
	return Vector2i(-1, -1)


## Explorer `process_monster_turns` → snapshot + `Enum.reduce`: one ordered pass, **current** grid for
## pathfinding and hearing. Calls `notify_tile_patch(cell, new_tile)` after each logical cell write when
## the callable is valid. Returns encounter **destination** cell if king-adjacent combat should start,
## else `Vector2i(-1, -1)`.
static func process_monster_reduce_pass(
	grid: Dictionary,
	rooms: Array,
	trap_defused: Dictionary,
	fog_enabled: bool,
	revealed: Dictionary,
	authority_seed: int,
	mover_peer: int,
	player_cell: Vector2i,
	guards_hostile: bool,
	player_alignment: int,
	notify_tile_patch: Callable
) -> Vector2i:
	var viewport_cells: Array[Vector2i] = collect_encounter_cells_viewport(
		grid, player_cell, VIEWPORT_CELLS_W, VIEWPORT_CELLS_H
	)
	var snapshot: Array[Dictionary] = []
	for mcell in viewport_cells:
		if fog_enabled and not DungeonFog.square_revealed(mcell, revealed, true):
			continue
		var raw_t: String = str(grid.get(mcell, ""))
		if not raw_t.begins_with("encounter|"):
			continue
		var mname: String = encounter_monster_name_from_tile(raw_t)
		var def: Dictionary = MonsterTable.lookup_monster(mname)
		if not effective_hunts(def, guards_hostile, player_alignment):
			continue
		snapshot.append({"snap_cell": mcell, "raw": raw_t})

	for entry in snapshot:
		var e: Dictionary = entry
		var raw_tile: String = str(e.get("raw", ""))
		var snap_cell: Vector2i = e.get("snap_cell", Vector2i(-1, -1)) as Vector2i
		var live: Vector2i = resolve_live_encounter_cell(grid, viewport_cells, snap_cell, raw_tile)
		if live.x < 0:
			continue
		var hear := rng_for_monster(authority_seed, mover_peer, live, 41)
		if hear.randi_range(1, 20) < HEARING_DC:
			continue
		var path: Array[Vector2i] = best_path_to_adjacent_ring(
			grid, live, player_cell, trap_defused, fog_enabled, revealed
		)
		if path.size() < 2:
			continue
		var dst: Vector2i = path[path.size() - 1]
		if dst == live:
			continue
		var under: String = underlying_after_encounter_leaves(live, rooms)
		grid[live] = under
		if notify_tile_patch.is_valid():
			notify_tile_patch.call(live, under)
		grid[dst] = raw_tile
		if notify_tile_patch.is_valid():
			notify_tile_patch.call(dst, raw_tile)
		print(
			"[Dungeoneers] monster_turn moved ",
			encounter_monster_name_from_tile(raw_tile),
			" ",
			live,
			"->",
			dst,
			" peer_id=",
			mover_peer
		)
		if GridWalk.is_king_adjacent(dst, player_cell):
			return dst
	return Vector2i(-1, -1)
