extends Node2D

# ---------------------------------------------------------------------------
# GridOverlay — draws a square or hex grid over the map image.
#
# Usage:
#   - Add as a child of the map Node2D (above the TextureRect, below tokens)
#   - Call apply_map_data(map: MapData) whenever the active map changes
#   - The overlay redraws automatically; call queue_redraw() after calibration
#
# Coordinate convention:
#   grid_offset (from MapData) is applied so the grid origin aligns to the
#   top-left corner of the first full cell, not the image edge.
#
# Hex geometry reference:
#   HEX_FLAT  : col spacing = hex_size * 1.5,  row spacing = hex_size * sqrt(3)
#   HEX_POINTY: col spacing = hex_size * sqrt(3), row spacing = hex_size * 1.5
# ---------------------------------------------------------------------------

const GRID_COLOR: Color = Color(1.0, 1.0, 1.0, 0.25)
const GRID_LINE_WIDTH: float = 1.0

var _map: MapData = null


func apply_map_data(map: MapData) -> void:
	_map = map
	queue_redraw()


func _draw() -> void:
	if _map == null:
		return
	match _map.grid_type:
		MapData.GridType.SQUARE:
			_draw_square()
		MapData.GridType.HEX_FLAT:
			_draw_hex(false)
		MapData.GridType.HEX_POINTY:
			_draw_hex(true)


# ---------------------------------------------------------------------------
# Square grid
# ---------------------------------------------------------------------------

func _draw_square() -> void:
	var tex_size := _get_texture_size()
	var step: float = _map.cell_px
	var ox: float = fmod(_map.grid_offset.x, step)
	var oy: float = fmod(_map.grid_offset.y, step)

	# Vertical lines — draw up to and including the right edge
	var x: float = ox
	while x < tex_size.x:
		draw_line(Vector2(x, 0), Vector2(x, tex_size.y), GRID_COLOR, GRID_LINE_WIDTH)
		x += step
	# Final line at the right boundary
	draw_line(Vector2(tex_size.x, 0), Vector2(tex_size.x, tex_size.y), GRID_COLOR, GRID_LINE_WIDTH)

	# Horizontal lines — draw up to and including the bottom edge
	var y: float = oy
	while y < tex_size.y:
		draw_line(Vector2(0, y), Vector2(tex_size.x, y), GRID_COLOR, GRID_LINE_WIDTH)
		y += step
	# Final line at the bottom boundary
	draw_line(Vector2(0, tex_size.y), Vector2(tex_size.x, tex_size.y), GRID_COLOR, GRID_LINE_WIDTH)


# ---------------------------------------------------------------------------
# Hex grid
# ---------------------------------------------------------------------------

func _draw_hex(pointy_top: bool) -> void:
	var tex_size := _get_texture_size()
	var r: float = _map.hex_size
	var ox: float = _map.grid_offset.x
	var oy: float = _map.grid_offset.y

	if pointy_top:
		var col_step: float = r * sqrt(3.0)
		var row_step: float = r * 1.5
		# Calculate exact number of cells needed to cover texture, with buffer for partial cells
		var cols: int = int(ceil((tex_size.x - ox) / col_step)) + 1
		var rows: int = int(ceil((tex_size.y - oy) / row_step)) + 1
		for row in range(rows):
			for col in range(cols):
				var cx: float = ox + col * col_step + (0.5 * col_step if row % 2 != 0 else 0.0)
				var cy: float = oy + row * row_step
				# Only draw if cell center is within or touches the texture bounds
				if cx - r < tex_size.x and cy - r < tex_size.y:
					_draw_hex_cell(Vector2(cx, cy), r, true)
	else:
		# flat-top
		var col_step: float = r * 1.5
		var row_step: float = r * sqrt(3.0)
		# Calculate exact number of cells needed to cover texture, with buffer for partial cells
		var cols: int = int(ceil((tex_size.x - ox) / col_step)) + 1
		var rows: int = int(ceil((tex_size.y - oy) / row_step)) + 1
		for col in range(cols):
			for row in range(rows):
				var cx: float = ox + col * col_step
				var cy: float = oy + row * row_step + (0.5 * row_step if col % 2 != 0 else 0.0)
				# Only draw if cell center is within or touches the texture bounds
				if cx - r < tex_size.x and cy - r < tex_size.y:
					_draw_hex_cell(Vector2(cx, cy), r, false)


func _draw_hex_cell(center: Vector2, r: float, pointy_top: bool) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in range(6):
		var angle_deg: float = 60.0 * float(i) + (30.0 if pointy_top else 0.0)
		var angle_rad: float = deg_to_rad(angle_deg)
		pts.append(center + Vector2(r * cos(angle_rad), r * sin(angle_rad)))
	# draw_polyline expects the loop closed
	pts.append(pts[0])
	draw_polyline(pts, GRID_COLOR, GRID_LINE_WIDTH)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _get_texture_size() -> Vector2:
	# GridOverlay lives inside a Node2D that also contains a TextureRect
	# named "MapImage". Fall back to a large default if the node isn't ready.
	var parent := get_parent()
	if parent == null:
		return Vector2(4096, 4096)
	var img_node: Node = parent.get_node_or_null("MapImage")
	if img_node and img_node is TextureRect and img_node.texture:
		return img_node.texture.get_size()
	return Vector2(4096, 4096)
