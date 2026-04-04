extends RefCounted
class_name GridSnap

## Static utility for snapping world-space positions to the nearest grid cell
## centre.  Supports SQUARE, HEX_FLAT, and HEX_POINTY grids.  The hex math is
## ported directly from grid_overlay.gdshader (cube-coordinate rounding).

const SQRT3: float = 1.7320508
const SQRT3_2: float = 0.8660254 # sqrt(3) / 2


## Snap a world-space position to the centre of the nearest grid cell.
## Returns the position unchanged when map_data is null or cell_px / hex_size
## are too small to be meaningful.
static func snap_to_grid(world_pos: Vector2, map_data: MapData) -> Vector2:
	if map_data == null:
		return world_pos

	match map_data.grid_type:
		MapData.GridType.SQUARE:
			return _snap_square(world_pos, map_data.cell_px, map_data.grid_offset)
		MapData.GridType.HEX_FLAT:
			return _snap_hex_flat(world_pos, map_data.hex_size, map_data.grid_offset)
		MapData.GridType.HEX_POINTY:
			return _snap_hex_pointy(world_pos, map_data.hex_size, map_data.grid_offset)
		_:
			return world_pos


# ── Square grid ───────────────────────────────────────────────────────────

static func _snap_square(world_pos: Vector2, cell_px: float, offset: Vector2) -> Vector2:
	if cell_px < 1.0:
		return world_pos
	# Remove the grid offset, snap, then re-apply it.
	var local: Vector2 = world_pos - offset
	var cx: float = floorf(local.x / cell_px) * cell_px + cell_px * 0.5
	var cy: float = floorf(local.y / cell_px) * cell_px + cell_px * 0.5
	return Vector2(cx, cy) + offset


# ── Hex helpers ───────────────────────────────────────────────────────────

static func _cube_round(cube: Vector3) -> Vector3:
	var rx: float = roundf(cube.x)
	var ry: float = roundf(cube.y)
	var rz: float = roundf(cube.z)
	var dx: float = absf(rx - cube.x)
	var dy: float = absf(ry - cube.y)
	var dz: float = absf(rz - cube.z)
	if dx > dy and dx > dz:
		rx = - ry - rz
	elif dy > dz:
		ry = - rx - rz
	else:
		rz = - rx - ry
	return Vector3(rx, ry, rz)


# ── Hex flat-top ──────────────────────────────────────────────────────────

static func _snap_hex_flat(world_pos: Vector2, hex_size: float, offset: Vector2) -> Vector2:
	if hex_size < 1.0:
		return world_pos
	var pos: Vector2 = world_pos - offset
	var r: float = hex_size
	# pixel → fractional axial
	var q: float = (2.0 / 3.0) * pos.x / r
	var s: float = (-1.0 / 3.0 * pos.x + SQRT3 / 3.0 * pos.y) / r
	var cube: Vector3 = _cube_round(Vector3(q, s, -q - s))
	# axial → pixel
	var centre := Vector2(r * 1.5 * cube.x, r * (SQRT3_2 * cube.x + SQRT3 * cube.y))
	return centre + offset


# ── Hex pointy-top ────────────────────────────────────────────────────────

static func _snap_hex_pointy(world_pos: Vector2, hex_size: float, offset: Vector2) -> Vector2:
	if hex_size < 1.0:
		return world_pos
	var pos: Vector2 = world_pos - offset
	var r: float = hex_size
	# pixel → fractional axial
	var q: float = (SQRT3 / 3.0 * pos.x - 1.0 / 3.0 * pos.y) / r
	var s: float = (2.0 / 3.0) * pos.y / r
	var cube: Vector3 = _cube_round(Vector3(q, s, -q - s))
	# axial → pixel
	var centre := Vector2(r * (SQRT3 * cube.x + SQRT3_2 * cube.y), r * 1.5 * cube.y)
	return centre + offset
