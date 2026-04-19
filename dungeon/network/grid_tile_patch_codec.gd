extends RefCounted

## Binary pack/unpack for **authority tile patches** (P7-14). Used for late-join replay as one `PackedByteArray` RPC
## instead of N per-cell `rpc_authority_tile_patch` calls. Format is little-endian.

const MAGIC := 0x4754  ## "GT"
const VERSION := 1
const MAX_TILE_UTF8 := 4096


static func _sorted_patch_cells(patches: Dictionary) -> Array:
	var keys: Array = patches.keys()
	keys.sort_custom(
		func(a: Variant, b: Variant) -> bool:
			var va := a as Vector2i
			var vb := b as Vector2i
			if va.y != vb.y:
				return va.y < vb.y
			return va.x < vb.x
	)
	return keys


## [code]patches[/code]: [code]Vector2i[/code] -> [code]String[/code] tile.
static func pack_sorted_patches(patches: Dictionary) -> PackedByteArray:
	var sp := StreamPeerBuffer.new()
	sp.put_u16(MAGIC)
	sp.put_u8(VERSION)
	var keys := _sorted_patch_cells(patches)
	sp.put_u32(keys.size())
	for k in keys:
		var cell := k as Vector2i
		var tile: String = str(patches[cell])
		var raw: PackedByteArray = tile.to_utf8_buffer()
		if raw.size() > MAX_TILE_UTF8:
			push_error("[Dungeoneers] grid_tile_patch_codec: tile UTF-8 too long at cell ", cell)
			return PackedByteArray()
		sp.put_u16(clampi(cell.x, 0, 65535))
		sp.put_u16(clampi(cell.y, 0, 65535))
		sp.put_u16(raw.size())
		sp.put_data(raw)
	return sp.get_data_array()


static func unpack_patches(data: PackedByteArray) -> Array:
	var out: Array = []
	if data.is_empty():
		return out
	var sp := StreamPeerBuffer.new()
	sp.data_array = data
	if sp.get_u16() != MAGIC:
		push_error("[Dungeoneers] grid_tile_patch_codec: bad magic")
		return out
	if sp.get_u8() != VERSION:
		push_error("[Dungeoneers] grid_tile_patch_codec: unsupported version")
		return out
	var n := int(sp.get_u32())
	if n < 0 or n > 1_000_000:
		push_error("[Dungeoneers] grid_tile_patch_codec: absurd patch count")
		return out
	for _i in range(n):
		if sp.get_position() + 6 > data.size():
			push_error("[Dungeoneers] grid_tile_patch_codec: truncated header")
			return out
		var cx := int(sp.get_u16())
		var cy := int(sp.get_u16())
		var slen := int(sp.get_u16())
		if slen < 0 or slen > MAX_TILE_UTF8:
			push_error("[Dungeoneers] grid_tile_patch_codec: bad string length")
			return out
		var raw_start := sp.get_position()
		if raw_start + slen > data.size():
			push_error("[Dungeoneers] grid_tile_patch_codec: truncated tile bytes")
			return out
		var raw2: PackedByteArray = data.slice(raw_start, raw_start + slen)
		if raw2.size() != slen:
			push_error("[Dungeoneers] grid_tile_patch_codec: short read")
			return out
		sp.seek(raw_start + slen)
		var tile_s: String = raw2.get_string_from_utf8()
		if tile_s.is_empty() and slen > 0:
			push_error("[Dungeoneers] grid_tile_patch_codec: invalid UTF-8")
			return out
		out.append({"cell": Vector2i(cx, cy), "tile": tile_s})
	return out


static func apply_patch_list_to_grid(patch_list: Array, base_grid: Dictionary) -> Dictionary:
	var g := base_grid.duplicate(true)
	for e in patch_list:
		if not e is Dictionary:
			continue
		var d := e as Dictionary
		var c: Variant = d.get("cell", Vector2i(-1, -1))
		if c is Vector2i:
			g[c] = str(d.get("tile", ""))
	return g
