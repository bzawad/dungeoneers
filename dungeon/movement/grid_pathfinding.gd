extends RefCounted

## 8-neighbor (king) **A\*** path on a walkable grid, optionally restricted to Explorer-style revealed cells.
## `h` = Chebyshev distance to goal (admissible for unit-cost king steps). Open-set ties: lower `f`, then lower `h`, then lower `y`, then lower `x`.
## Neighbor relaxation order matches historical BFS expansion (cardinals, then diagonals).

const GridWalk := preload("res://dungeon/movement/grid_walkability.gd")
const DungeonGrid := preload("res://dungeon/generator/grid.gd")
const DungeonFog := preload("res://dungeon/fog/fog_of_war.gd")

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1),
]


static func _cheb_h(a: Vector2i, goal: Vector2i) -> int:
	return maxi(absi(a.x - goal.x), absi(a.y - goal.y))


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


static func find_path_8dir(
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
		var best_f: int = int(g_score[best_c]) + _cheb_h(best_c, to)
		var best_h: int = _cheb_h(best_c, to)
		for j in range(1, open_cells.size()):
			var cj: Vector2i = open_cells[j]
			var fj: int = int(g_score[cj]) + _cheb_h(cj, to)
			var hj: int = _cheb_h(cj, to)
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
			if fog_enabled and not DungeonFog.square_revealed(nxt, revealed, true):
				continue

			var tentative_g: int = int(g_score[best_c]) + 1
			if not g_score.has(nxt) or tentative_g < int(g_score[nxt]):
				parent[nxt] = best_c
				g_score[nxt] = tentative_g
				if not in_open.get(nxt, false):
					open_cells.append(nxt)
					in_open[nxt] = true

	return PackedVector2Array()


## How many king-adjacent edges from `path_start` along `path` (in order) are needed to reach `end`.
## Returns `-1` if `end` is not reachable as a prefix of `path` or if a step is not king-adjacent.
static func king_step_count_along_path_prefix(
	path_start: Vector2i, path: PackedVector2Array, end: Vector2i
) -> int:
	if end == path_start:
		return 0
	var cur := path_start
	for i in range(path.size()):
		var nxt := Vector2i(int(path[i].x), int(path[i].y))
		if not GridWalk.is_king_adjacent(cur, nxt):
			return -1
		cur = nxt
		if cur == end:
			return i + 1
	return -1


## Legacy **BFS** oracle for tests: shortest king path; expansion order matches pre–CMB-01 `find_path_8dir`.
static func find_path_8dir_bfs_reference(
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
