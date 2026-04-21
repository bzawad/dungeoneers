extends RefCounted

## 4-neighbor (rook) **A\*** path on a walkable grid, optionally restricted to Explorer-style revealed cells.
## Matches Explorer web click pathfinding (orthogonal steps only — no corner-cutting diagonals).
## `plan_ignore_fog`: client click planning only — matches Explorer `PathfindingHook` (full walkability grid); server still validates fog per step.
## `h` = Manhattan distance to goal (admissible for unit-cost orthogonal steps). Open-set ties: lower `f`, then lower `h`, then lower `y`, then lower `x`.
## Neighbor expansion order: east, west, south, north (same as legacy BFS cardinals-first block).

const GridWalk := preload("res://dungeon/movement/grid_walkability.gd")
const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]


static func _manhattan_h(a: Vector2i, goal: Vector2i) -> int:
	return absi(a.x - goal.x) + absi(a.y - goal.y)


## Lexicographic tie-break: prefer smaller `(f, h, y, x)`.
static func _cell_better_open_than(
	f_a: int, h_a: int, c_a: Vector2i, f_b: int, h_b: int, c_b: Vector2i
) -> bool:
	if f_a != f_b:
		return f_a < f_b
	if h_a != h_b:
		return h_a < h_b
	if c_a.y != c_b.y:
		return c_a.y < c_b.y
	return c_a.x < c_b.x


## When `from` and `to` share a row or column, return the unique cardinal segment if every cell on that
## segment is pathfinding-walkable and (when fog is on) revealed. Otherwise empty — caller falls back to A\*.
## Avoids Manhattan-A\* tie-break zigzags in wide open or fog-bounded corridors for straight clicks.
static func _try_axis_aligned_line_path(
	grid: Dictionary,
	from: Vector2i,
	to: Vector2i,
	revealed: Dictionary,
	fog_enabled: bool,
	unlocked_doors: Dictionary,
	trap_defused: Dictionary,
	guards_hostile: bool,
	plan_ignore_fog: bool = false
) -> PackedVector2Array:
	if from.x != to.x and from.y != to.y:
		return PackedVector2Array()
	var packed := PackedVector2Array()
	var cur := from
	while cur != to:
		var nxt: Vector2i
		if cur.x != to.x:
			nxt = Vector2i(cur.x + (1 if to.x > cur.x else -1), cur.y)
		else:
			nxt = Vector2i(cur.x, cur.y + (1 if to.y > cur.y else -1))
		var n_tile: String = GridWalk.tile_effective(grid, nxt, trap_defused)
		if not GridWalk.is_walkable_for_pathfinding_at(n_tile, nxt, unlocked_doors, guards_hostile):
			return PackedVector2Array()
		if (
			(not plan_ignore_fog)
			and fog_enabled
			and not DungeonFog.square_revealed(nxt, revealed, true)
		):
			return PackedVector2Array()
		packed.append(Vector2(nxt))
		cur = nxt
	return packed


static func find_path_4dir(
	grid: Dictionary,
	from: Vector2i,
	to: Vector2i,
	revealed: Dictionary,
	fog_enabled: bool,
	unlocked_doors: Dictionary,
	trap_defused: Dictionary = {},
	guards_hostile: bool = false,
	plan_ignore_fog: bool = false
) -> PackedVector2Array:
	if from == to:
		return PackedVector2Array()
	var to_tile: String = GridWalk.tile_effective(grid, to, trap_defused)
	if not GridWalk.is_walkable_for_pathfinding_at(to_tile, to, unlocked_doors, guards_hostile):
		return PackedVector2Array()
	if (not plan_ignore_fog) and fog_enabled and not DungeonFog.square_revealed(to, revealed, true):
		return PackedVector2Array()

	var straight: PackedVector2Array = _try_axis_aligned_line_path(
		grid,
		from,
		to,
		revealed,
		fog_enabled,
		unlocked_doors,
		trap_defused,
		guards_hostile,
		plan_ignore_fog
	)
	if not straight.is_empty():
		return straight

	var g_score: Dictionary = {}
	var parent: Dictionary = {}
	var open_cells: Array[Vector2i] = []
	var in_open: Dictionary = {}
	var closed: Dictionary = {}

	g_score[from] = 0
	parent[from] = from
	open_cells.append(from)
	in_open[from] = true

	while not open_cells.is_empty():
		var best_i := 0
		var best_c: Vector2i = open_cells[0]
		var best_f: int = int(g_score[best_c]) + _manhattan_h(best_c, to)
		var best_h: int = _manhattan_h(best_c, to)
		for j in range(1, open_cells.size()):
			var cj: Vector2i = open_cells[j]
			var fj: int = int(g_score[cj]) + _manhattan_h(cj, to)
			var hj: int = _manhattan_h(cj, to)
			if _cell_better_open_than(fj, hj, cj, best_f, best_h, best_c):
				best_i = j
				best_c = cj
				best_f = fj
				best_h = hj

		open_cells.remove_at(best_i)
		in_open.erase(best_c)
		closed[best_c] = true

		if best_c == to:
			var chain: Array[Vector2i] = []
			var p := to
			while p != from:
				chain.append(p)
				p = parent[p]
			chain.reverse()
			var packed := PackedVector2Array()
			for c: Vector2i in chain:
				packed.append(Vector2(c))
			return packed

		for d: Vector2i in _DIRS:
			var nxt: Vector2i = best_c + d
			if (
				nxt.x < 0
				or nxt.y < 0
				or nxt.x >= DungeonGrid.MAP_WIDTH
				or nxt.y >= DungeonGrid.MAP_HEIGHT
			):
				continue
			if closed.has(nxt):
				continue
			var n_tile: String = GridWalk.tile_effective(grid, nxt, trap_defused)
			if not GridWalk.is_walkable_for_pathfinding_at(
				n_tile, nxt, unlocked_doors, guards_hostile
			):
				continue
			if (
				(not plan_ignore_fog)
				and fog_enabled
				and not DungeonFog.square_revealed(nxt, revealed, true)
			):
				continue

			var tentative_g: int = int(g_score[best_c]) + 1
			if not g_score.has(nxt) or tentative_g < int(g_score[nxt]):
				parent[nxt] = best_c
				g_score[nxt] = tentative_g
				if not in_open.get(nxt, false):
					open_cells.append(nxt)
					in_open[nxt] = true

	return PackedVector2Array()


## How many orthogonally adjacent edges from `path_start` along `path` (in order) are needed to reach `end`.
## Returns `-1` if `end` is not reachable as a prefix of `path` or if a step is not a single cardinal step.
static func orthogonal_step_count_along_path_prefix(
	path_start: Vector2i, path: PackedVector2Array, end: Vector2i
) -> int:
	if end == path_start:
		return 0
	var cur := path_start
	for i in range(path.size()):
		var nxt := Vector2i(int(path[i].x), int(path[i].y))
		if not GridWalk.is_orthogonal_adjacent(cur, nxt):
			return -1
		cur = nxt
		if cur == end:
			return i + 1
	return -1


## Legacy **BFS** oracle for tests: shortest 4-dir path; expansion order matches `find_path_4dir` neighbor order.
static func find_path_4dir_bfs_reference(
	grid: Dictionary,
	from: Vector2i,
	to: Vector2i,
	revealed: Dictionary,
	fog_enabled: bool,
	unlocked_doors: Dictionary,
	trap_defused: Dictionary = {},
	guards_hostile: bool = false
) -> PackedVector2Array:
	if from == to:
		return PackedVector2Array()
	var to_tile: String = GridWalk.tile_effective(grid, to, trap_defused)
	if not GridWalk.is_walkable_for_pathfinding_at(to_tile, to, unlocked_doors, guards_hostile):
		return PackedVector2Array()
	if fog_enabled and not DungeonFog.square_revealed(to, revealed, true):
		return PackedVector2Array()

	var prev: Dictionary = {}
	var q: Array[Vector2i] = [from]
	prev[from] = from
	var qi := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		if cur == to:
			break
		for d: Vector2i in _DIRS:
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
			var n_tile: String = GridWalk.tile_effective(grid, nxt, trap_defused)
			if not GridWalk.is_walkable_for_pathfinding_at(
				n_tile, nxt, unlocked_doors, guards_hostile
			):
				continue
			if fog_enabled and not DungeonFog.square_revealed(nxt, revealed, true):
				continue
			prev[nxt] = cur
			q.append(nxt)

	if not prev.has(to):
		return PackedVector2Array()

	var chain: Array[Vector2i] = []
	var p := to
	while p != from:
		chain.append(p)
		p = prev[p]
	chain.reverse()

	var packed := PackedVector2Array()
	for c: Vector2i in chain:
		packed.append(Vector2(c))
	return packed
