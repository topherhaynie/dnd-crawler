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

const _VI_FILL := Color(0.0, 0.85, 0.3, 0.08)
const _VI_BORDER := Color(0.0, 0.9, 0.3, 0.9)
const _VI_WIDTH := 3.0


func set_rect(r: Rect2) -> void:
	_rect = r
	queue_redraw()


func _process(_delta: float) -> void:
	# Redraw every frame while visible so border width stays crisp during zoom.
	if _rect != Rect2():
		queue_redraw()


func _draw() -> void:
	if _rect == Rect2():
		return
	var cam_z := camera.zoom.x if camera else 1.0
	var w := _VI_WIDTH / cam_z
	draw_rect(_rect, _VI_FILL)
	draw_rect(_rect, _VI_BORDER, false, w)
	var fs := int(clampf(13.0 / cam_z, 8.0, 48.0))
	draw_string(ThemeDB.fallback_font,
		_rect.position + Vector2(w + 2.0 / cam_z, (fs + 4.0) / cam_z),
		"Player View",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _VI_BORDER)
