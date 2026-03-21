extends Node2D

# ---------------------------------------------------------------------------
# IndicatorOverlay — draws the green "Player View" indicator box on top of
# all other map children (MapImage, GridOverlay, etc.).
#
# Instantiated dynamically by MapView._ready() and add_child'd LAST so it
# renders after every sibling.  A reference to the scene Camera2D must be
# assigned so border width can be kept screen-constant at any zoom level.
# ---------------------------------------------------------------------------

var camera: Camera2D = null

var _rect: Rect2 = Rect2()
var _rotation_deg: float = 0.0

const _VI_FILL := Color(0.0, 0.85, 0.3, 0.08)
const _VI_BORDER := Color(0.0, 0.9, 0.3, 0.9)
const _VI_WIDTH := 3.0
const _HANDLE_SIZE := 8.0 ## Screen-space pixels; scaled by 1/cam_z like border width
const _HANDLE_COLOR := Color(1.0, 1.0, 1.0, 0.9)

var show_handles: bool = false


func set_rect(r: Rect2, rotation_deg: float = 0.0) -> void:
	_rect = r
	_rotation_deg = rotation_deg
	queue_redraw()


## Returns the corner index (0=TL, 1=TR, 2=BR, 3=BL) of the handle
## under world_pos, or -1 if none. Hit radius is 1.5× the visual size.
func get_handle_at(world_pos: Vector2) -> int:
	if _rect == Rect2() or not show_handles:
		return -1
	var cam_z := camera.zoom.x if camera else 1.0
	var hit_radius := _HANDLE_SIZE * 1.5 / cam_z
	var corners := _compute_corners()
	for i in range(4):
		if world_pos.distance_to(corners[i]) <= hit_radius:
			return i
	return -1


func _compute_corners() -> PackedVector2Array:
	var center := _rect.get_center()
	var half := _rect.size * 0.5
	var angle := deg_to_rad(_rotation_deg)
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y).rotated(angle),
		center + Vector2(half.x, -half.y).rotated(angle),
		center + Vector2(half.x, half.y).rotated(angle),
		center + Vector2(-half.x, half.y).rotated(angle),
	])


func _process(_delta: float) -> void:
	# Redraw every frame while visible so border width stays crisp during zoom.
	if _rect != Rect2():
		queue_redraw()


func _draw() -> void:
	if _rect == Rect2():
		return
	var cam_z := camera.zoom.x if camera else 1.0
	var w := _VI_WIDTH / cam_z
	var corners := _compute_corners()
	draw_polygon(corners, PackedColorArray([_VI_FILL, _VI_FILL, _VI_FILL, _VI_FILL]))
	var poly_line := PackedVector2Array(corners)
	poly_line.append(corners[0])
	draw_polyline(poly_line, _VI_BORDER, w)
	var fs := int(clampf(13.0 / cam_z, 8.0, 48.0))
	draw_string(ThemeDB.fallback_font,
		corners[0] + Vector2((w + 2.0) / cam_z, (fs + 4.0) / cam_z),
		"Player View",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _VI_BORDER)
	if show_handles:
		var hs := _HANDLE_SIZE / cam_z
		for corner in corners:
			draw_rect(Rect2(corner - Vector2(hs, hs) * 0.5, Vector2(hs, hs)), _HANDLE_COLOR)
