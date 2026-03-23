extends Node2D

# ---------------------------------------------------------------------------
# CalibrationTool — DM drags a ruler line on the map to set the grid scale.
#
# Workflow:
#   1. DM presses the Calibrate button in DMWindow → this node becomes active
#   2. DM clicks-and-drags on the map to draw a measurement line
#   3. A dialog asks "How many feet does this span?" (default 5 ft)
#   4. Tool computes cell_px (square) or hex_size (hex) and writes back to
#      the MapData, then emits calibration_done
#   5. DMWindow hides the tool and calls MapView.grid_overlay.queue_redraw()
#
# The ruler line and dot are drawn directly in _draw().
# ---------------------------------------------------------------------------

signal calibration_done(map: MapData) ## Emitted after the DM confirms the measurement

const LINE_COLOR: Color = Color(1.0, 0.85, 0.0, 0.9) ## bright yellow
const DOT_RADIUS: float = 6.0
const LINE_WIDTH: float = 2.5
const LABEL_OFFSET: Vector2 = Vector2(12, -16)
## Must be above all MapView render layers. MapView.RenderLayer.FOG+2 (=8) is the
## highest used (token_layer in DM mode), so we sit one step above everything.
const OVERLAY_Z_INDEX: int = 9

var _map: MapData = null
var _active: bool = false
var _dragging: bool = false
var _start: Vector2 = Vector2.ZERO
var _end: Vector2 = Vector2.ZERO

# Dialog reference set by DMWindow so it can be shown from this script
var confirm_dialog: ConfirmationDialog = null


func _ready() -> void:
	z_index = OVERLAY_Z_INDEX


func activate(map: MapData) -> void:
	_map = map
	_active = true
	_dragging = false
	_start = Vector2.ZERO
	_end = Vector2.ZERO
	set_process_unhandled_input(true)
	queue_redraw()


func deactivate() -> void:
	_active = false
	_dragging = false
	set_process_unhandled_input(false)
	queue_redraw()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_start = get_global_mouse_position()
			_end = _start
			queue_redraw()
		else:
			_dragging = false
			if _start.distance_to(_end) > 4.0:
				_show_confirm_dialog()
			queue_redraw()
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		_end = get_global_mouse_position()
		queue_redraw()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Draw
# ---------------------------------------------------------------------------

func _draw() -> void:
	if not _active or _start == Vector2.ZERO:
		return
	# Convert global positions to local drawing space
	var ls := to_local(_start)
	var le := to_local(_end)
	draw_line(ls, le, LINE_COLOR, LINE_WIDTH)
	draw_circle(ls, DOT_RADIUS, LINE_COLOR)
	draw_circle(le, DOT_RADIUS, LINE_COLOR)
	# Pixel-distance label
	var px_dist := _start.distance_to(_end)
	draw_string(ThemeDB.fallback_font, le + LABEL_OFFSET,
		"%.0f px" % px_dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, LINE_COLOR)


# ---------------------------------------------------------------------------
# Confirm dialog
# ---------------------------------------------------------------------------

func _show_confirm_dialog() -> void:
	if confirm_dialog == null:
		push_error("CalibrationTool: confirm_dialog not set")
		return
	var on_confirmed := Callable(self , "_on_confirmed")
	if confirm_dialog.confirmed.is_connected(on_confirmed):
		confirm_dialog.confirmed.disconnect(on_confirmed)
	var on_canceled := Callable(self , "_on_canceled")
	if confirm_dialog.canceled.is_connected(on_canceled):
		confirm_dialog.canceled.disconnect(on_canceled)
	confirm_dialog.confirmed.connect(_on_confirmed, CONNECT_ONE_SHOT)
	confirm_dialog.canceled.connect(_on_canceled, CONNECT_ONE_SHOT)
	confirm_dialog.popup_centered(Vector2i(340, 120))


func _on_confirmed() -> void:
	# DMWindow reads the SpinBox value, calls apply_measurement() with it
	pass


func _on_canceled() -> void:
	_start = Vector2.ZERO
	_end = Vector2.ZERO
	queue_redraw()


func apply_measurement(feet: float) -> void:
	## Called by DMWindow after the DM confirms the foot value.
	## Computes and writes the correct calibration field on _map.
	if _map == null or feet <= 0.0:
		return
	var px_dist := _start.distance_to(_end)
	if px_dist <= 0.0:
		return
	var px_per_foot := px_dist / feet
	match _map.grid_type:
		MapData.GridType.SQUARE:
			_map.cell_px = px_per_foot * 5.0 # one cell = 5 ft
			print("CalibrationTool: cell_px = %.2f" % _map.cell_px)
		MapData.GridType.HEX_FLAT, MapData.GridType.HEX_POINTY:
			# hex_size = outer radius; one hex width (flat-top) = 2 * hex_size
			# Treat the ruler span as the width of N hexes; one hex = 5 ft
			_map.hex_size = (px_per_foot * 5.0) / 2.0
			print("CalibrationTool: hex_size = %.2f" % _map.hex_size)
	calibration_done.emit(_map)
	deactivate()
