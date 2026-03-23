extends Node2D
class_name MeasurementOverlay

# ---------------------------------------------------------------------------
# MeasurementOverlay — draws all active measurement shapes on the map.
#
# Placed as a child of MapView at z_index 10 (above fog at 7, above token
# layer at 8).  All shapes are drawn in world-space coordinates.
#
# Drawing styles (all fixed white, 4px stroke):
#   LINE      — thick line with endpoint dots + midpoint ft label
#   CIRCLE    — arc outline + label at top of circle
#   CONE      — D&D 5e RAW: half-angle = atan(0.5) ≈ 26.6°
#                 filled semi-transparent interior + outline + label along axis
#   SQUARE    — rotated square (drag angle = rotation) + label at centre
#   RECTANGLE — rotated rectangle; extra_value = perpendicular half-width
#
# ft calculation: pixel_distance / _px_per_foot, rounded to nearest integer.
# ---------------------------------------------------------------------------

const STROKE_WIDTH: float = 4.0
const ENDPOINT_RADIUS: float = 6.0
const LABEL_FONT_SIZE: int = 18
const SELECTION_GLOW_COLOR: Color = Color(1.0, 0.85, 0.15, 0.9)
## D&D 5e cone half-angle: width = length → tan(half) = 0.5
const CONE_HALF_ANGLE: float = 0.4636476090008172 ## atan(0.5) radians
const FILL_ALPHA: float = 0.12

## id (String) → MeasurementData
var _measurements: Dictionary = {}
## px for one 5-foot cell (set from MapData.cell_px on map load)
var _px_per_5ft: float = 64.0
## Highlighted shape id for selection cue
var _selected_id: String = ""
## Inverse camera zoom — used only for pick-distance scaling.
## Recomputed at the start of every _draw().
var _inv_zoom: float = 1.0
## Cached zoom for change detection in _process.
var _last_zoom: float = -1.0


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	var ct: Transform2D = get_viewport_transform() * get_canvas_transform()
	var z: float = ct.get_scale().x
	if not is_equal_approx(z, _last_zoom):
		_last_zoom = z
		_inv_zoom = 1.0 / maxf(z, 0.01)

func set_scale_px(px_per_5ft: float) -> void:
	_px_per_5ft = maxf(1.0, px_per_5ft)
	queue_redraw()


func load_measurements(dicts: Array) -> void:
	_measurements.clear()
	for raw in dicts:
		if raw is Dictionary:
			var m: MeasurementData = MeasurementData.from_dict(raw as Dictionary)
			_measurements[m.id] = m
	queue_redraw()


func add_or_update(data: MeasurementData) -> void:
	if data == null or data.id.is_empty():
		return
	_measurements[data.id] = data
	queue_redraw()


func remove_shape(id: String) -> void:
	_measurements.erase(id)
	if _selected_id == id:
		_selected_id = ""
	queue_redraw()


func clear() -> void:
	_measurements.clear()
	_selected_id = ""
	queue_redraw()


func set_selected(id: String) -> void:
	_selected_id = id
	queue_redraw()


## Returns the id of the measurement nearest to world_pos within snap_px
## screen-pixels, or empty string if none found.
func pick_nearest(world_pos: Vector2, snap_px: float) -> String:
	var best_id: String = ""
	var snap_world: float = snap_px * _inv_zoom
	var best_dist: float = snap_world
	for raw in _measurements.values():
		var m: MeasurementData = raw as MeasurementData
		if m == null:
			continue
		var d: float = _pick_distance(m, world_pos)
		if d < best_dist:
			best_dist = d
			best_id = m.id
	return best_id


## Returns ["start"|"end", id] if world_pos is within snap_px of an endpoint,
## or ["", ""] if no endpoint is close enough.
func pick_endpoint(world_pos: Vector2, snap_px: float) -> Array:
	var snap_world: float = snap_px * _inv_zoom
	var best_which: String = ""
	var best_id: String = ""
	var best_dist: float = snap_world
	for raw in _measurements.values():
		var m: MeasurementData = raw as MeasurementData
		if m == null:
			continue
		var ds: float = world_pos.distance_to(m.world_start)
		var de: float = world_pos.distance_to(m.world_end)
		if ds < best_dist:
			best_dist = ds
			best_which = "start"
			best_id = m.id
		if de < best_dist:
			best_dist = de
			best_which = "end"
			best_id = m.id
	return [best_which, best_id]


# ---------------------------------------------------------------------------
# Draw dispatch
# ---------------------------------------------------------------------------

func _draw() -> void:
	for raw in _measurements.values():
		var m: MeasurementData = raw as MeasurementData
		if m == null:
			continue
		var selected: bool = (m.id == _selected_id)
		match m.shape_type:
			MeasurementData.ShapeType.LINE:
				_draw_line_shape(m, selected)
			MeasurementData.ShapeType.CIRCLE:
				_draw_circle_shape(m, selected)
			MeasurementData.ShapeType.CONE:
				_draw_cone_shape(m, selected)
			MeasurementData.ShapeType.SQUARE:
				_draw_square_shape(m, selected)
			MeasurementData.ShapeType.RECTANGLE:
				_draw_rectangle_shape(m, selected)


# ---------------------------------------------------------------------------
# ft helpers
# ---------------------------------------------------------------------------

func _px_to_ft(px: float) -> int:
	var px_per_foot: float = _px_per_5ft / 5.0
	return roundi(px / px_per_foot)


func _ft_label(px: float) -> String:
	return "%d ft" % _px_to_ft(px)


func _draw_label(pos: Vector2, text: String, stroke_col: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, pos + Vector2(2, 2), text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_FONT_SIZE, Color(0, 0, 0, 0.7))
	draw_string(font, pos, text,
		HORIZONTAL_ALIGNMENT_CENTER, -1, LABEL_FONT_SIZE, stroke_col)


# ---------------------------------------------------------------------------
# LINE
# ---------------------------------------------------------------------------

func _draw_line_shape(m: MeasurementData, selected: bool) -> void:
	var s: Vector2 = to_local(m.world_start)
	var e: Vector2 = to_local(m.world_end)
	var col: Color = SELECTION_GLOW_COLOR if selected else m.color
	draw_line(s, e, col, STROKE_WIDTH, true)
	draw_circle(s, ENDPOINT_RADIUS, col)
	draw_circle(e, ENDPOINT_RADIUS, col)
	var dist_px: float = m.world_start.distance_to(m.world_end)
	var mid: Vector2 = (s + e) * 0.5
	var perp: Vector2 = (e - s).normalized().rotated(PI * 0.5) * 18.0
	_draw_label(mid + perp, _ft_label(dist_px), col)


# ---------------------------------------------------------------------------
# CIRCLE
# ---------------------------------------------------------------------------

func _draw_circle_shape(m: MeasurementData, selected: bool) -> void:
	var center: Vector2 = to_local(m.world_start)
	var edge: Vector2 = to_local(m.world_end)
	var radius: float = center.distance_to(edge)
	if radius < 4.0:
		return
	var col: Color = SELECTION_GLOW_COLOR if selected else m.color
	# Filled semi-transparent interior
	var fill_col: Color = Color(col.r, col.g, col.b, FILL_ALPHA)
	_draw_filled_circle(center, radius, fill_col, 64)
	draw_arc(center, radius, 0.0, TAU, 64, col, STROKE_WIDTH, true)
	# Radius line for reference
	draw_line(center, edge, Color(col.r, col.g, col.b, 0.5), STROKE_WIDTH * 0.5, true)
	draw_circle(center, ENDPOINT_RADIUS * 0.6, col)
	draw_circle(edge, ENDPOINT_RADIUS, col)
	# Label at top of circle
	var label_pos: Vector2 = center + Vector2(0.0, - (radius + 24.0))
	_draw_label(label_pos, _ft_label(m.world_start.distance_to(m.world_end)), col)


func _draw_filled_circle(center: Vector2, radius: float, col: Color, segments: int) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	points.append(center)
	for i in range(segments):
		var angle: float = float(i) / float(segments) * TAU
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_polygon(points, PackedColorArray([col]))


# ---------------------------------------------------------------------------
# CONE (D&D 5e RAW — half-angle = atan(0.5))
# ---------------------------------------------------------------------------

func _draw_cone_shape(m: MeasurementData, selected: bool) -> void:
	var apex: Vector2 = to_local(m.world_start)
	var tip: Vector2 = to_local(m.world_end)
	var length: float = apex.distance_to(tip)
	if length < 4.0:
		return
	var col: Color = SELECTION_GLOW_COLOR if selected else m.color
	var dir: Vector2 = (tip - apex).normalized()
	var edge_dist: float = length / cos(CONE_HALF_ANGLE)
	var left_pt: Vector2 = apex + dir.rotated(-CONE_HALF_ANGLE) * edge_dist
	var right_pt: Vector2 = apex + dir.rotated(CONE_HALF_ANGLE) * edge_dist
	# Fill with simple triangle (skip when degenerate to avoid triangulation error)
	var tri_pts: PackedVector2Array = PackedVector2Array([apex, left_pt, right_pt])
	var cross: float = (left_pt - apex).cross(right_pt - apex)
	if absf(cross) > 1.0:
		var fill_col: Color = Color(col.r, col.g, col.b, FILL_ALPHA)
		draw_polygon(tri_pts, PackedColorArray([fill_col]))
	# Outline edges
	draw_line(apex, left_pt, col, STROKE_WIDTH, true)
	draw_line(apex, right_pt, col, STROKE_WIDTH, true)
	# Arc at open end — use angle_to to get the correct sweep direction
	var left_angle: float = (left_pt - apex).angle()
	var right_angle: float = (right_pt - apex).angle()
	var sweep: float = wrapf(right_angle - left_angle, -PI, PI)
	var arc_steps: int = 32
	var arc_pts: PackedVector2Array = PackedVector2Array()
	for i in range(arc_steps + 1):
		var t: float = float(i) / float(arc_steps)
		var a: float = left_angle + t * sweep
		arc_pts.append(apex + Vector2(cos(a), sin(a)) * edge_dist)
	draw_polyline(arc_pts, col, STROKE_WIDTH, true)
	draw_circle(apex, ENDPOINT_RADIUS, col)
	# Label along axis
	var label_pos: Vector2 = apex + dir * (length * 0.55)
	_draw_label(label_pos, _ft_label(m.world_start.distance_to(m.world_end)), col)


# ---------------------------------------------------------------------------
# SQUARE (rotated square, side = distance start→end, center = midpoint)
# ---------------------------------------------------------------------------

func _draw_square_shape(m: MeasurementData, selected: bool) -> void:
	var s: Vector2 = to_local(m.world_start)
	var e: Vector2 = to_local(m.world_end)
	var side: float = s.distance_to(e)
	if side < 4.0:
		return
	var col: Color = SELECTION_GLOW_COLOR if selected else m.color
	var dir: Vector2 = (e - s).normalized()
	var perp: Vector2 = dir.rotated(PI * 0.5)
	var half: float = side * 0.5
	# Square centred on midpoint, side = distance, aligned to drag direction
	var center: Vector2 = (s + e) * 0.5
	var c0: Vector2 = center + dir * half + perp * half
	var c1: Vector2 = center + dir * half - perp * half
	var c2: Vector2 = center - dir * half - perp * half
	var c3: Vector2 = center - dir * half + perp * half
	var corners: PackedVector2Array = PackedVector2Array([c0, c1, c2, c3])
	# Fill
	var fill_col: Color = Color(col.r, col.g, col.b, FILL_ALPHA)
	draw_polygon(corners, PackedColorArray([fill_col]))
	# Outline (closed loop)
	var outline: PackedVector2Array = PackedVector2Array([c0, c1, c2, c3, c0])
	draw_polyline(outline, col, STROKE_WIDTH, true)
	draw_circle(s, ENDPOINT_RADIUS, col)
	_draw_label(center, _ft_label(m.world_start.distance_to(m.world_end)), col)


# ---------------------------------------------------------------------------
# RECTANGLE (rotated; extra_value = perpendicular half-width in world-space px)
# ---------------------------------------------------------------------------

func _draw_rectangle_shape(m: MeasurementData, selected: bool) -> void:
	var s: Vector2 = to_local(m.world_start)
	var e: Vector2 = to_local(m.world_end)
	var along: Vector2 = e - s
	var length: float = along.length()
	if length < 4.0:
		return
	var col: Color = SELECTION_GLOW_COLOR if selected else m.color
	var dir: Vector2 = along.normalized()
	var perp: Vector2 = dir.rotated(PI * 0.5)
	# extra_value is the full perpendicular width in world-space
	var half_width_local: float = m.extra_value
	if half_width_local < 1.0:
		# Fallback: half of length so rect reads as a proportional shape
		half_width_local = length * 0.5
	var c0: Vector2 = s + perp * half_width_local
	var c1: Vector2 = e + perp * half_width_local
	var c2: Vector2 = e - perp * half_width_local
	var c3: Vector2 = s - perp * half_width_local
	var corners: PackedVector2Array = PackedVector2Array([c0, c1, c2, c3])
	var fill_col: Color = Color(col.r, col.g, col.b, FILL_ALPHA)
	draw_polygon(corners, PackedColorArray([fill_col]))
	var outline: PackedVector2Array = PackedVector2Array([c0, c1, c2, c3, c0])
	draw_polyline(outline, col, STROKE_WIDTH, true)
	draw_circle(s, ENDPOINT_RADIUS, col)
	draw_circle(e, ENDPOINT_RADIUS, col)
	var center: Vector2 = (s + e) * 0.5
	_draw_label(center, _ft_label(m.world_start.distance_to(m.world_end)), col)


# ---------------------------------------------------------------------------
# Pick distance — approximate distance from world_pos to nearest edge
# ---------------------------------------------------------------------------

func _pick_distance(m: MeasurementData, world_pos: Vector2) -> float:
	match m.shape_type:
		MeasurementData.ShapeType.LINE:
			return _point_to_segment_dist(world_pos, m.world_start, m.world_end)
		MeasurementData.ShapeType.CIRCLE:
			var r: float = m.world_start.distance_to(m.world_end)
			# Hit if near the rim OR inside the circle
			var d_from_center: float = world_pos.distance_to(m.world_start)
			if d_from_center <= r:
				return 0.0
			return d_from_center - r
		MeasurementData.ShapeType.CONE:
			# Hit if near either edge segment or the apex
			var edge_dist: float = m.world_start.distance_to(m.world_end) / cos(CONE_HALF_ANGLE)
			var dir: Vector2 = (m.world_end - m.world_start).normalized()
			var left_pt: Vector2 = m.world_start + dir.rotated(-CONE_HALF_ANGLE) * edge_dist
			var right_pt: Vector2 = m.world_start + dir.rotated(CONE_HALF_ANGLE) * edge_dist
			var d1: float = _point_to_segment_dist(world_pos, m.world_start, left_pt)
			var d2: float = _point_to_segment_dist(world_pos, m.world_start, right_pt)
			var d3: float = _point_to_segment_dist(world_pos, left_pt, right_pt)
			return minf(d1, minf(d2, d3))
		MeasurementData.ShapeType.SQUARE:
			var center: Vector2 = (m.world_start + m.world_end) * 0.5
			var half_side: float = m.world_start.distance_to(m.world_end) * 0.5
			# Inside the bounding-circle of the square → hit
			if world_pos.distance_to(center) <= half_side:
				return 0.0
			return world_pos.distance_to(center) - half_side
		MeasurementData.ShapeType.RECTANGLE:
			# Distance to either long edge or the center line
			var d_seg: float = _point_to_segment_dist(world_pos, m.world_start, m.world_end)
			var half_w: float = m.extra_value if m.extra_value > 1.0 \
				else m.world_start.distance_to(m.world_end) * 0.5
			if d_seg <= half_w:
				return 0.0
			return d_seg - half_w
	return INF


func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)
