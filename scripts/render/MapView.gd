extends Node2D

# ---------------------------------------------------------------------------
# MapView — shared map viewport used by both the DM window and the Player
# display process.
#
# Scene structure (MapView.tscn):
#   MapView (Node2D)
#   └── Camera2D
#   └── MapImage		 (TextureRect)
#   └── GridOverlay  (Node2D, GridOverlay.gd)
#   └── WallLayer		(Node2D — LightOccluder2D children, Phase 6)
#   └── TokenLayer   (Node2D — PlayerSprite children, Phase 4)
#
# Tool modes (set by DMWindow toolbar):
#   SELECT — default; left-click is reserved for future token interaction
#   PAN		— left-click-drag pans the camera
#
# Camera: position = world point shown at screen centre.
#   To show world (0,0) at screen top-left, init to viewport_size * 0.5.
#   call _reset_camera() or load saved state from MapData.
#
# Input summary:
#   Left-drag (Pan tool)   — pan
#   Middle-drag						— pan (always, regardless of tool)
#   Scroll wheel				   — zoom toward cursor
#   Trackpad two-finger		— pan (InputEventPanGesture)
#   Trackpad pinch				 — zoom (InputEventMagnifyGesture)
#   Arrow keys						 — smooth pan via _process / Input.is_key_pressed()
#														(buttons must have FOCUS_NONE to avoid UI nav)
# ---------------------------------------------------------------------------

enum Tool {
	NONE,
	SELECT,
	PAN,
	ZOOM,
	PLAYER_ZOOM,
	WALL
}

const ZOOM_MIN: float = 0.1
const ZOOM_MAX: float = 8.0
const ZOOM_STEP: float = 0.12 ## per scroll click
const PAN_SPEED: float = 500.0 ## px/sec for arrow-key pan
const WALL_HANDLE_HIT_RADIUS_PX: float = 12.0
const WALL_HANDLE_SIZE_WORLD: float = 6.0
const ROTATION_STEP: int = 90 ## degrees per rotate click

@onready var camera: Camera2D = $Camera2D
@onready var map_image: TextureRect = $MapImage
@onready var grid_overlay: Node2D = $GridOverlay
@onready var wall_layer: Node2D = $WallLayer
@onready var wall_visual_layer: Node2D = $WallVisualLayer
@onready var object_layer: Node2D = get_node_or_null("ObjectLayer") as Node2D
@onready var fog_overlay: FogSystem = $FogSystem as FogSystem
@onready var token_layer: Node2D = $TokenLayer

enum RenderLayer {
	BACKGROUND,
	MAP,
	GRID,
	WALL,
	OBJECT,
	PLAYER,
	FOG,
	PLAYER_VIEWPORT,
}

enum RenderProfile {DM, PLAYER}

var _map: MapData = null
var active_tool: Tool = Tool.SELECT
var allow_keyboard_pan: bool = false

enum FogTool {NONE, REVEAL_BRUSH, HIDE_BRUSH, REVEAL_RECT, HIDE_RECT}
var fog_tool: int = FogTool.NONE
var fog_brush_radius_px: float = 64.0
var is_dm_view: bool = true
var dm_fog_visible: bool = true
var _render_profile: int = RenderProfile.DM

var _fog_hidden_cells: Dictionary = {}
var _fog_rect_dragging: bool = false
var _fog_rect_start: Vector2 = Vector2.ZERO
var _fog_brush_cursor_ring: Line2D = null
var _fog_brush_cursor_last_radius: float = -1.0
var _wall_rect_dragging: bool = false
var _wall_rect_start: Vector2 = Vector2.ZERO
var _wall_rect_preview: Line2D = null
var _wall_rect_preview_fill: Polygon2D = null
var _fog_rect_preview: Line2D = null
var _fog_rect_preview_fill: Polygon2D = null
var wall_polygon_points: Array = []
var wall_subtool: String = "rect" # "rect" or "polygon"
var _wall_polygon_preview: Line2D = null
var _wall_polygon_preview_fill: Polygon2D = null
func _clear_wall_polygon_preview() -> void:
	if _wall_polygon_preview and is_instance_valid(_wall_polygon_preview):
		_wall_polygon_preview.queue_free()
	_wall_polygon_preview = null
	if _wall_polygon_preview_fill and is_instance_valid(_wall_polygon_preview_fill):
		_wall_polygon_preview_fill.queue_free()
	_wall_polygon_preview_fill = null
	wall_polygon_points.clear()
var _selected_wall_index: int = -1
## var _wall_dragging_move: bool = false
var _wall_dragging_handle: int = -1
## var _wall_drag_start_mouse: Vector2 = Vector2.ZERO
var _wall_drag_start_points: Array = []
var _wall_selection_outline: Line2D = null
var _wall_handle_nodes: Array = []

var _panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_cam: Vector2 = Vector2.ZERO
var _map_rotation: int = 0 ## Current map rotation in degrees (0, 90, 180, 270)


func _set_active_tool(tool: Tool) -> void:
	# Clear transient input state when switching tools to avoid "stuck" drags
	active_tool = tool
	_panning = false
	_dragging_indicator = false
	_wall_rect_dragging = false
	_fog_rect_dragging = false
	_wall_dragging_handle = -1
	if typeof(_wall_drag_start_points) == TYPE_ARRAY:
		_wall_drag_start_points.clear()

signal viewport_indicator_moved(new_center: Vector2)
signal fog_changed(map: MapData)
@warning_ignore("unused_signal")
signal fog_delta(cell_px: int, revealed_cells: Array, hidden_cells: Array)
signal walls_changed(map: MapData)

## World-space rect — kept in sync with _indicator_overlay for hit-testing.
var _viewport_indicator: Rect2 = Rect2()
var _indicator_rotation_deg: float = 0.0
var _dragging_indicator: bool = false

## Dedicated child Node2D added LAST so it renders on top of MapImage etc.
var _indicator_overlay: Node2D = null


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func load_map(map: MapData) -> void:
	## Load a MapData and display it. Safe to call from DM or Player process.
	_map = map

	if map.image_path != "":
		var img := Image.load_from_file(map.image_path)
		if img and not img.is_empty():
			map_image.texture = ImageTexture.create_from_image(img)
		else:
			push_error("MapView: could not load image at '%s'" % map.image_path)
			map_image.texture = null
	else:
		map_image.texture = null

	map_image.size = map_image.texture.get_size() if map_image.texture else Vector2(1920, 1080)
	grid_overlay.apply_map_data(map)
	_load_fog_from_map(map)
	_refresh_fog_overlay()
	_rebuild_wall_occluders(map)
	var applied_cached_snapshot := _apply_cached_fog_snapshot_if_compatible()
	if not applied_cached_snapshot:
		var _reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if _reg != null and _reg.fog != null:
			_reg.fog.reset()
			_reg.fog.seed_from_hidden(maxi(1, map.fog_cell_px), _fog_hidden_cells)
	if fog_overlay and fog_overlay.has_method("set_dm_reveals"):
		fog_overlay.set_dm_reveals(_build_dm_reveal_sources(map))

	# Restore saved view, or default to showing the map top-left at the
	# top-left corner of the viewport (camera_position == ZERO means new map).
	if map.camera_zoom != 1.0 or map.camera_position != Vector2.ZERO:
		camera.zoom = Vector2.ONE * map.camera_zoom
		camera.position = map.camera_position
	else:
		_reset_camera()
	# Rotation is applied by set_camera_state() from the network broadcast;
	# do not rotate the camera here (DM view is never rotated).

	print("MapView: loaded map '%s'" % map.map_name)


func get_map() -> MapData:
	return _map


func get_token_layer() -> Node2D:
	return token_layer


func get_object_layer() -> Node2D:
	_ensure_object_layer()
	return object_layer


func set_dm_view(enabled: bool) -> void:
	is_dm_view = enabled
	if not enabled:
		dm_fog_visible = true
	apply_render_profile(RenderProfile.DM if enabled else RenderProfile.PLAYER)
	if _map != null:
		_rebuild_wall_occluders(_map)
	_refresh_fog_overlay()


func set_dm_fog_visible(enabled: bool) -> void:
	dm_fog_visible = enabled
	_refresh_fog_overlay()


func set_fog_tool(tool_id: int, brush_radius_px: float) -> void:
	fog_tool = tool_id
	fog_brush_radius_px = maxf(8.0, brush_radius_px)
	if fog_tool != FogTool.REVEAL_RECT and fog_tool != FogTool.HIDE_RECT:
		_fog_rect_dragging = false
		_clear_fog_rect_preview()
	if fog_tool == FogTool.NONE:
		_hide_fog_brush_cursor()
	elif fog_tool == FogTool.REVEAL_BRUSH or fog_tool == FogTool.HIDE_BRUSH:
		_build_fog_brush_cursor()
		_update_fog_brush_cursor_style()


func apply_fog_state(cell_px: int, hidden_cells: Array) -> void:
	if _map == null:
		return
	_map.fog_cell_px = maxi(1, cell_px)
	_set_fog_hidden_from_array(hidden_cells)
	_refresh_fog_overlay()


func apply_fog_delta(cell_px: int, revealed_cells: Array, hidden_cells: Array) -> void:
	if _map == null:
		return
	_map.fog_cell_px = maxi(1, cell_px)
	for cell in revealed_cells:
		if cell is Vector2i:
			_fog_hidden_cells.erase(cell)
		elif cell is Array and (cell as Array).size() >= 2:
			var arr := cell as Array
			_fog_hidden_cells.erase(Vector2i(int(arr[0]), int(arr[1])))
		elif cell is Dictionary:
			_fog_hidden_cells.erase(Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0))))
	for cell in hidden_cells:
		if cell is Vector2i:
			_fog_hidden_cells[cell] = true
		elif cell is Array and (cell as Array).size() >= 2:
			var arr := cell as Array
			_fog_hidden_cells[Vector2i(int(arr[0]), int(arr[1]))] = true
		elif cell is Dictionary:
			_fog_hidden_cells[Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0)))] = true
	_sync_fog_to_map(false)
	_apply_fog_overlay_delta(revealed_cells, hidden_cells)


func force_fog_sync() -> void:
	_sync_fog_to_map(false)


func set_wall_rect_mode(enabled: bool) -> void:
	if enabled:
		_set_active_tool(Tool.WALL)
		wall_subtool = "rect"
		_clear_wall_rect_preview()
		_clear_wall_polygon_preview()
		wall_polygon_points.clear() # Ensure polygon points are cleared
		_set_selected_wall(-1)
	else:
		if active_tool == Tool.WALL:
			_set_active_tool(Tool.SELECT)
		wall_subtool = "none"
		_clear_wall_rect_preview()
		_clear_wall_polygon_preview()
		wall_polygon_points.clear() # Also clear polygon points when disabling


func set_wall_polygon_mode(enabled: bool) -> void:
	if enabled:
		_set_active_tool(Tool.WALL)
		wall_subtool = "polygon"
		_clear_wall_polygon_preview()
		_clear_wall_rect_preview()
		wall_polygon_points.clear()
		_set_selected_wall(-1)
	else:
		if active_tool == Tool.WALL:
			_set_active_tool(Tool.SELECT)
		wall_subtool = "none"
		_clear_wall_polygon_preview()
		_clear_wall_rect_preview()
		wall_polygon_points.clear()


func has_selected_wall() -> bool:
	return _selected_wall_index >= 0 and _map != null and _selected_wall_index < _map.wall_polygons.size()


func delete_selected_wall() -> bool:
	if not has_selected_wall():
		return false
	_map.wall_polygons.remove_at(_selected_wall_index)
	_set_selected_wall(-1)
	_rebuild_wall_occluders(_map)
	walls_changed.emit(_map)
	return true


func get_camera_state() -> Dictionary:
	## Returns the current camera position, zoom, and rotation as a dict for broadcasting.
	## Returns a zero-state if called before _ready() has resolved @onready vars.
	if camera == null:
		return {"position": {"x": 0.0, "y": 0.0}, "zoom": 1.0, "rotation": 0}
	return {"position": {"x": camera.position.x, "y": camera.position.y}, "zoom": camera.zoom.x, "rotation": _map_rotation}


func set_camera_state(pos: Vector2, zoom: float, rotation_deg: int = 0) -> void:
	## Apply a camera state received from an external source (e.g. DM mini-view broadcast).
	camera.position = pos
	camera.zoom = Vector2.ONE * clampf(zoom, ZOOM_MIN, ZOOM_MAX)
	_map_rotation = rotation_deg
	camera.rotation_degrees = float(_map_rotation)


func _ready() -> void:
	_ensure_object_layer()
	# Allow Camera2D to honour rotation_degrees (disabled by default in Godot 4).
	camera.ignore_rotation = false
	# Add the indicator overlay as the last child so it renders on top of
	# MapImage, GridOverlay, and all other siblings.
	_indicator_overlay = load("res://scripts/render/IndicatorOverlay.gd").new()
	_indicator_overlay.name = "IndicatorOverlay"
	_indicator_overlay.camera = camera
	add_child(_indicator_overlay)
	_apply_layer_order()
	apply_render_profile(RenderProfile.DM if is_dm_view else RenderProfile.PLAYER)


func set_viewport_indicator(world_rect: Rect2, rotation_deg: float = 0.0) -> void:
	## Set the player-viewport indicator rect in world space. Pass Rect2() to hide.
	_viewport_indicator = world_rect
	_indicator_rotation_deg = rotation_deg
	_indicator_overlay.set_rect(world_rect, rotation_deg)


func save_camera_to_map() -> void:
	if _map:
		_map.camera_position = camera.position
		_map.camera_zoom = camera.zoom.x
		# camera_rotation is written by DMWindow directly (player rotation, not DM camera rotation)


func _reset_camera() -> void:
	## Position camera so the map top-left aligns with the viewport top-left.
	camera.zoom = Vector2.ONE
	_map_rotation = 0
	camera.rotation_degrees = 0.0
	# Camera.position = world point at screen centre.
	# To get world (0,0) at screen top-left: centre = viewport_size / 2.
	camera.position = get_viewport().get_visible_rect().size * 0.5


func zoom_in() -> void:
	_zoom_camera(ZOOM_STEP, get_viewport().get_visible_rect().size * 0.5)


func zoom_out() -> void:
	_zoom_camera(-ZOOM_STEP, get_viewport().get_visible_rect().size * 0.5)


func _indicator_has_point(world_pos: Vector2) -> bool:
	## Point-in-rotated-rect hit test for the indicator box.
	if _viewport_indicator == Rect2():
		return false
	if _indicator_rotation_deg == 0.0:
		return _viewport_indicator.has_point(world_pos)
	var center := _viewport_indicator.get_center()
	var local := (world_pos - center).rotated(deg_to_rad(-_indicator_rotation_deg))
	var half := _viewport_indicator.size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y


func rotate_cw() -> void:
	## Rotate the map camera 90° clockwise.
	_map_rotation = (_map_rotation + ROTATION_STEP) % 360
	camera.rotation_degrees = float(_map_rotation)


func rotate_ccw() -> void:
	## Rotate the map camera 90° counter-clockwise.
	_map_rotation = (_map_rotation - ROTATION_STEP + 360) % 360
	camera.rotation_degrees = float(_map_rotation)


func get_map_rotation() -> int:
	## Returns the current map rotation in degrees (0, 90, 180, 270).
	return _map_rotation


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# print("[DEBUG] _unhandled_input: event=", event, "active_tool=", active_tool, "wall_subtool=", wall_subtool)
	if _handle_fog_input(event):
		get_viewport().set_input_as_handled()
		return
	if _handle_fog_wall_input(event):
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_DELETE or key_event.keycode == KEY_BACKSPACE):
			if delete_selected_wall():
				get_viewport().set_input_as_handled()
				return

	# Fix: Deselect wall tools when SELECT or PAN is chosen
	if active_tool == Tool.SELECT or active_tool == Tool.PAN:
		set_wall_rect_mode(false)
		set_wall_polygon_mode(false)

	# --- Trackpad: two-finger pan -------------------------------------------
	if event is InputEventPanGesture:
		camera.position += event.delta / camera.zoom.x
		get_viewport().set_input_as_handled()
		return

	# --- Trackpad: pinch to zoom --------------------------------------------
	if event is InputEventMagnifyGesture:
		var step: float = (event.factor - 1.0) * 1.5
		_zoom_camera(step, event.position)
		get_viewport().set_input_as_handled()
		return

	# --- Mouse buttons ------------------------------------------------------
	if event is InputEventMouseButton:
		var btn_event := event as InputEventMouseButton
		match btn_event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(ZOOM_STEP, btn_event.position)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(-ZOOM_STEP, btn_event.position)
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_MIDDLE:
				# Middle-drag always pans regardless of active tool
				_panning = btn_event.pressed
				if _panning:
					_pan_start_mouse = btn_event.position
					_pan_start_cam = camera.position
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_LEFT:
				if btn_event.pressed:
					# Indicator drag takes priority over Pan tool
					if _viewport_indicator != Rect2() and _indicator_has_point(get_global_mouse_position()):
						_dragging_indicator = true
						get_viewport().set_input_as_handled()
					elif active_tool == Tool.PAN:
						_panning = true
						_pan_start_mouse = btn_event.position
						_pan_start_cam = camera.position
						get_viewport().set_input_as_handled()
					return
				else:
					if _dragging_indicator:
						_dragging_indicator = false
						get_viewport().set_input_as_handled()
					elif _panning:
						_panning = false
						get_viewport().set_input_as_handled()
		return

	# --- Mouse motion (panning + indicator drag) ----------------------------
	if event is InputEventMouseMotion:
		if _dragging_indicator:
			var motion := event as InputEventMouseMotion
			var world_delta := motion.relative / camera.zoom.x
			_viewport_indicator = Rect2(
				_viewport_indicator.position + world_delta,
				_viewport_indicator.size)
			_indicator_overlay.set_rect(_viewport_indicator, _indicator_rotation_deg)
			viewport_indicator_moved.emit(_viewport_indicator.get_center())
			get_viewport().set_input_as_handled()
		elif _panning:
			var motion := event as InputEventMouseMotion
			camera.position = _pan_start_cam - (motion.position - _pan_start_mouse) / camera.zoom.x
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if allow_keyboard_pan:
		# Smooth arrow-key pan (bypasses UI focus).
		var kdir := Vector2.ZERO
		if Input.is_key_pressed(KEY_LEFT): kdir.x -= 1.0
		if Input.is_key_pressed(KEY_RIGHT): kdir.x += 1.0
		if Input.is_key_pressed(KEY_UP): kdir.y -= 1.0
		if Input.is_key_pressed(KEY_DOWN): kdir.y += 1.0
		if kdir != Vector2.ZERO:
			camera.position += kdir.normalized() * PAN_SPEED * delta / camera.zoom.x

	if fog_overlay and fog_overlay.has_method("sync_player_revealers"):
		fog_overlay.sync_player_revealers(token_layer.get_children())


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _zoom_camera(step: float, pivot_screen: Vector2) -> void:
	var old_zoom := camera.zoom.x
	var new_zoom := clampf(old_zoom + step, ZOOM_MIN, ZOOM_MAX)
	if new_zoom == old_zoom:
		return
	var half_vp := get_viewport().get_visible_rect().size * 0.5
	var pivot_world := camera.position + (pivot_screen - half_vp) / old_zoom
	camera.zoom = Vector2.ONE * new_zoom
	camera.position = pivot_world - (pivot_screen - half_vp) / new_zoom


func _handle_fog_wall_input(event: InputEvent) -> bool:
	# print("[DEBUG] _handle_fog_wall_input: event=", event, "active_tool=", active_tool, "wall_subtool=", wall_subtool)
	if _map == null or not is_dm_view:
		return false

	# Wall tool input handling
	if active_tool == Tool.WALL:
		# print("[DEBUG] Wall Tool Active: wall_subtool=", wall_subtool)
		if wall_subtool == "rect":
			if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				var mb := event as InputEventMouseButton
				if mb.pressed:
					# print("[DEBUG] Wall Rect: Drag started at", get_global_mouse_position())
					_wall_rect_dragging = true
					_wall_rect_start = get_global_mouse_position()
					_update_wall_rect_preview(_wall_rect_start, _wall_rect_start)
				else:
					if _wall_rect_dragging:
						# print("[DEBUG] Wall Rect: Drag ended at", get_global_mouse_position())
						_wall_rect_dragging = false
						_clear_wall_rect_preview()
						_apply_wall_rect(_wall_rect_start, get_global_mouse_position())
				return true
			# print("[DEBUG] Wall Rect: Event not handled:", event)
			if _wall_rect_dragging and event is InputEventMouseMotion:
				_update_wall_rect_preview(_wall_rect_start, get_global_mouse_position())
				return true
		elif wall_subtool == "polygon":
			if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				var mb := event as InputEventMouseButton
				if mb.pressed:
					var pos := get_global_mouse_position()
					# print("[DEBUG] Wall Polygon: Point added", pos)
					wall_polygon_points.append(pos)
					_update_wall_polygon_preview()
				return true
			if event is InputEventMouseButton and ((event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT or (event as InputEventMouseButton).double_click):
				if wall_polygon_points.size() >= 3:
					# print("[DEBUG] Wall Polygon: Polygon created with points", wall_polygon_points)
					_apply_wall_polygon(wall_polygon_points)
				else:
					print("[DEBUG] Wall Polygon: Not enough points to create polygon")
					pass
				_clear_wall_polygon_preview()
				wall_polygon_points.clear()
				return true
			if event is InputEventKey:
				var key_event := event as InputEventKey
				if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_ESCAPE):
					# print("[DEBUG] Wall Polygon: ESC pressed, clearing preview and points")
					_clear_wall_polygon_preview()
					wall_polygon_points.clear()
					return true
			if event is InputEventMouseMotion:
				_update_wall_polygon_preview(get_global_mouse_position())
				return true
		else:
			print("[DEBUG] Wall Tool: Unknown wall_subtool value:", wall_subtool)
			# Optionally, return false or handle as needed
			return false

	# Restore SELECT tool wall selection, handle drag, and move drag logic
	if active_tool == Tool.SELECT and fog_tool == FogTool.NONE:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var sb := event as InputEventMouseButton
			if sb.pressed:
				var mouse_pos := get_global_mouse_position()
				var handle_idx := _hit_test_selected_wall_handle(mouse_pos)
				if handle_idx >= 0:
					_wall_dragging_handle = handle_idx
					_wall_drag_start_points = _get_wall_points(_selected_wall_index)
					return true
				var wall_idx := _find_wall_at_point(mouse_pos)
				if wall_idx >= 0:
					_set_selected_wall(wall_idx)
					_wall_drag_start_points = _get_wall_points(_selected_wall_index)
					return true
				_set_selected_wall(-1)
				return false
			# On mouse release: only consume the event if we actually performed a wall drag/move
			var prev_handle := _wall_dragging_handle
			_wall_dragging_handle = -1
			var handled_release: bool = false
			if prev_handle >= 0:
				handled_release = true
			if not _wall_drag_start_points.is_empty():
				walls_changed.emit(_map)
				_wall_drag_start_points.clear()
				handled_release = true
			if handled_release:
				return true
			# Not related to wall drag — allow outer handler to process (e.g., indicator/pan release)
			return false
		if event is InputEventMouseMotion:
			var mm := event as InputEventMouseMotion
			if _wall_dragging_handle >= 0:
				_apply_wall_handle_drag(get_global_mouse_position())
				return true
			elif has_selected_wall() and not _wall_drag_start_points.is_empty():
				_apply_wall_move_drag(mm)
				return true
	return false


func _update_wall_polygon_preview(mouse_pos: Variant = null) -> void:
	if wall_visual_layer == null or not is_dm_view:
		return
	var points := wall_polygon_points.duplicate()
	if typeof(mouse_pos) == TYPE_VECTOR2:
		points.append(mouse_pos)
	if _wall_polygon_preview == null or not is_instance_valid(_wall_polygon_preview):
		_wall_polygon_preview = Line2D.new()
		_wall_polygon_preview.width = 2.0
		_wall_polygon_preview.default_color = Color(1.0, 0.9, 0.2, 0.95)
		_wall_polygon_preview.closed = true
		wall_visual_layer.add_child(_wall_polygon_preview)
	if _wall_polygon_preview_fill == null or not is_instance_valid(_wall_polygon_preview_fill):
		_wall_polygon_preview_fill = Polygon2D.new()
		_wall_polygon_preview_fill.color = Color(1.0, 0.9, 0.2, 0.18)
		wall_visual_layer.add_child(_wall_polygon_preview_fill)
	var packed := PackedVector2Array()
	for p in points:
		packed.append(p)
	_wall_polygon_preview.points = packed
	_wall_polygon_preview_fill.polygon = packed


func _apply_wall_polygon(points: Array) -> void:
	if _map == null:
		return
	if points.size() < 3:
		return
	var poly := []
	for p in points:
		if p is Vector2:
			poly.append(p)
	_map.wall_polygons.append(poly)
	_rebuild_wall_occluders(_map)
	walls_changed.emit(_map)

	# Removed unreachable/incorrect event handling and return statements from void function


# ---------------------------------------------------------------------------
# Fog tool input dispatch
# ---------------------------------------------------------------------------

func _handle_fog_input(event: InputEvent) -> bool:
	if fog_tool == FogTool.NONE or not is_dm_view or _map == null:
		return false

	var is_reveal := fog_tool == FogTool.REVEAL_BRUSH or fog_tool == FogTool.REVEAL_RECT

	if fog_tool == FogTool.REVEAL_BRUSH or fog_tool == FogTool.HIDE_BRUSH:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_apply_fog_brush(get_global_mouse_position(), is_reveal)
				return true
		if event is InputEventMouseMotion:
			var world_pos := get_global_mouse_position()
			_update_fog_brush_cursor(world_pos)
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_apply_fog_brush(world_pos, is_reveal)
			return true
		return false

	if fog_tool == FogTool.REVEAL_RECT or fog_tool == FogTool.HIDE_RECT:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_fog_rect_start = get_global_mouse_position()
					_fog_rect_dragging = true
					_update_fog_rect_preview(_fog_rect_start, _fog_rect_start, is_reveal)
				else:
					if _fog_rect_dragging:
						_fog_rect_dragging = false
						_clear_fog_rect_preview()
						_apply_fog_rect(_fog_rect_start, get_global_mouse_position(), is_reveal)
				return true
		if _fog_rect_dragging and event is InputEventMouseMotion:
			_update_fog_rect_preview(_fog_rect_start, get_global_mouse_position(), is_reveal)
			return true
		return false

	return false


# ---------------------------------------------------------------------------
# Fog brush cursor ring
# ---------------------------------------------------------------------------

func _build_fog_brush_cursor() -> void:
	if _fog_brush_cursor_ring != null and is_instance_valid(_fog_brush_cursor_ring):
		return
	_fog_brush_cursor_ring = Line2D.new()
	_fog_brush_cursor_ring.name = "FogBrushCursor"
	_fog_brush_cursor_ring.width = 2.0
	_fog_brush_cursor_ring.closed = true
	_fog_brush_cursor_ring.z_index = RenderLayer.FOG + 1
	_rebuild_fog_brush_cursor_points()
	add_child(_fog_brush_cursor_ring)


func _rebuild_fog_brush_cursor_points() -> void:
	if _fog_brush_cursor_ring == null or not is_instance_valid(_fog_brush_cursor_ring):
		return
	const RING_POINTS: int = 32
	var pts := PackedVector2Array()
	pts.resize(RING_POINTS)
	for i in RING_POINTS:
		var angle := (float(i) / float(RING_POINTS)) * TAU
		pts[i] = Vector2(cos(angle) * fog_brush_radius_px, sin(angle) * fog_brush_radius_px)
	_fog_brush_cursor_ring.points = pts
	_fog_brush_cursor_last_radius = fog_brush_radius_px


func _update_fog_brush_cursor(world_pos: Vector2) -> void:
	_build_fog_brush_cursor()
	if _fog_brush_cursor_ring == null or not is_instance_valid(_fog_brush_cursor_ring):
		return
	_fog_brush_cursor_ring.position = world_pos
	_fog_brush_cursor_ring.visible = true
	if absf(_fog_brush_cursor_last_radius - fog_brush_radius_px) > 0.5:
		_rebuild_fog_brush_cursor_points()
	_update_fog_brush_cursor_style()


func _update_fog_brush_cursor_style() -> void:
	if _fog_brush_cursor_ring == null or not is_instance_valid(_fog_brush_cursor_ring):
		return
	if fog_tool == FogTool.REVEAL_BRUSH:
		_fog_brush_cursor_ring.default_color = Color(0.2, 1.0, 0.35, 0.9)
	else:
		_fog_brush_cursor_ring.default_color = Color(1.0, 0.35, 0.3, 0.9)


func _hide_fog_brush_cursor() -> void:
	if _fog_brush_cursor_ring != null and is_instance_valid(_fog_brush_cursor_ring):
		_fog_brush_cursor_ring.visible = false


func _apply_fog_brush(world_pos: Vector2, reveal: bool) -> void:
	if _map == null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.fog == null:
		return
	if reveal:
		registry.fog.reveal_brush(world_pos, fog_brush_radius_px)
	else:
		registry.fog.hide_brush(world_pos, fog_brush_radius_px)
	fog_changed.emit(_map)


func _apply_fog_rect(a: Vector2, b: Vector2, reveal: bool) -> void:
	if _map == null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.fog == null:
		return
	if reveal:
		registry.fog.reveal_rect(a, b)
	else:
		registry.fog.hide_rect(a, b)
	fog_changed.emit(_map)


func _apply_wall_rect(a: Vector2, b: Vector2) -> void:
	# print("[DEBUG] _apply_wall_rect called: a=%s, b=%s" % [str(a), str(b)])
	if _map == null:
		return
	var min_x := minf(a.x, b.x)
	var min_y := minf(a.y, b.y)
	var max_x := maxf(a.x, b.x)
	var max_y := maxf(a.y, b.y)
	if absf(max_x - min_x) < 4.0 or absf(max_y - min_y) < 4.0:
		# print("[DEBUG] Wall Rect: Ignored, too small. a=", a, "b=", b)
		return
	var poly := [
		Vector2(min_x, min_y),
		Vector2(max_x, min_y),
		Vector2(max_x, max_y),
		Vector2(min_x, max_y),
	]
	# print("[DEBUG] Wall Rect: Created polygon=", poly)
	_map.wall_polygons.append(poly)
	_rebuild_wall_occluders(_map)
	walls_changed.emit(_map)


func _load_fog_from_map(map: MapData) -> void:
	_fog_hidden_cells.clear()
	if is_dm_view:
		# Authoritative DM side: new maps start fully hidden.
		var cell_px: int = maxi(1, map.fog_cell_px)
		var size := map_image.texture.get_size() if map_image.texture else Vector2(1920, 1080)
		for y in range(0, int(ceil(size.y / cell_px))):
			for x in range(0, int(ceil(size.x / cell_px))):
				_fog_hidden_cells[Vector2i(x, y)] = true
		_sync_fog_to_map()
	else:
		# Player side: wait for fog_updated snapshot from DM.
		_sync_fog_to_map(false)


func _set_fog_hidden_from_array(raw_cells: Array) -> void:
	_fog_hidden_cells.clear()
	for cell in raw_cells:
		if cell is Vector2i:
			_fog_hidden_cells[cell] = true
		elif cell is Array and (cell as Array).size() >= 2:
			var arr := cell as Array
			_fog_hidden_cells[Vector2i(int(arr[0]), int(arr[1]))] = true
		elif cell is Dictionary:
			_fog_hidden_cells[Vector2i(int(cell.get("x", 0)), int(cell.get("y", 0)))] = true


func _sync_fog_to_map(emit_change_signal: bool = true) -> void:
	if _map == null:
		return
	if emit_change_signal:
		fog_changed.emit(_map)


func get_fog_state() -> PackedByteArray:
	if fog_overlay == null:
		return PackedByteArray()
	return await fog_overlay.get_fog_state()


func apply_fog_snapshot(buffer: PackedByteArray) -> bool:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.fog == null:
		return false
	return registry.fog.apply_snapshot(buffer)


func set_fog_state(data: PackedByteArray) -> bool:
	return apply_fog_snapshot(data)


func _apply_cached_fog_snapshot_if_compatible() -> bool:
	if _map == null:
		return false
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.fog == null or registry.fog.service == null:
		return false
	var stamp_size := registry.fog.service.get_fog_state_size()
	if stamp_size == Vector2i.ZERO:
		return false
	var map_size := map_image.texture.get_size() if map_image and map_image.texture else Vector2(1920, 1080)
	return stamp_size == Vector2i(roundi(map_size.x), roundi(map_size.y))


func _refresh_fog_overlay() -> void:
	if fog_overlay == null or _map == null:
		return
	var size := map_image.texture.get_size() if map_image.texture else Vector2(1920, 1080)
	var fog_is_visible := dm_fog_visible if is_dm_view else true
	fog_overlay.configure(size, is_dm_view, fog_is_visible)


func apply_render_profile(profile: int) -> void:
	_render_profile = profile
	is_dm_view = (profile == RenderProfile.DM)
	_apply_layer_visibility()
	# Ensure wall layers are visible and z-index is correct
	if wall_visual_layer:
		wall_visual_layer.visible = is_dm_view
		wall_visual_layer.z_index = RenderLayer.WALL
	if wall_layer:
		wall_layer.visible = is_dm_view
		wall_layer.z_index = RenderLayer.WALL
	_refresh_fog_overlay()


func _ensure_object_layer() -> void:
	if object_layer and is_instance_valid(object_layer):
		return
	object_layer = Node2D.new()
	object_layer.name = "ObjectLayer"
	add_child(object_layer)


func _apply_layer_order() -> void:
	map_image.z_index = RenderLayer.MAP
	grid_overlay.z_index = RenderLayer.GRID
	wall_layer.z_index = RenderLayer.WALL
	if wall_visual_layer:
		wall_visual_layer.z_index = RenderLayer.WALL
	_ensure_object_layer()
	if object_layer:
		object_layer.z_index = RenderLayer.OBJECT
	token_layer.z_index = RenderLayer.PLAYER
	fog_overlay.z_index = RenderLayer.FOG
	if _indicator_overlay:
		_indicator_overlay.z_index = RenderLayer.PLAYER_VIEWPORT


func _apply_layer_visibility() -> void:
	var is_dm := _render_profile == RenderProfile.DM
	if wall_visual_layer:
		wall_visual_layer.visible = is_dm
	if _indicator_overlay:
		_indicator_overlay.visible = is_dm


func _apply_fog_overlay_delta(revealed_cells: Array, hidden_cells: Array) -> void:
	if revealed_cells.is_empty() and hidden_cells.is_empty():
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.fog == null:
		return
	var cell_px := maxi(1, _map.fog_cell_px) if _map else 1
	registry.fog.apply_seed_delta(revealed_cells, hidden_cells, cell_px)


func _rebuild_wall_occluders(map: MapData) -> void:
	if wall_layer == null:
		return
	for c in wall_layer.get_children():
		c.queue_free()
	if wall_visual_layer:
		for c in wall_visual_layer.get_children():
			c.queue_free()
	for poly in map.wall_polygons:
		if not poly is Array or (poly as Array).size() < 3:
			continue
		var points := PackedVector2Array()
		for p in poly:
			if p is Vector2:
				points.append(p)
		if points.size() < 3:
			continue
		var occ_poly := OccluderPolygon2D.new()
		occ_poly.polygon = points
		var occ := LightOccluder2D.new()
		occ.occluder = occ_poly
		occ.visibility_layer = 2
		occ.occluder_light_mask = 2
		wall_layer.add_child(occ)

		if wall_visual_layer and is_dm_view:
			var line := Line2D.new()
			line.width = 3.0
			line.default_color = Color(1.0, 0.25, 0.2, 0.9)
			line.closed = true
			line.points = points
			wall_visual_layer.add_child(line)

	_refresh_selected_wall_visuals()
	if fog_overlay and fog_overlay.has_method("set_wall_polygons"):
		fog_overlay.set_wall_polygons(map.wall_polygons)


func _build_dm_reveal_sources(map: MapData) -> Array:
		if map == null:
			return []
		var reveals: Array = []
		# This function should build DM reveal sources from map data
		# Example: iterate map.dm_reveal_objects or similar
		# Placeholder logic (update as needed for your map data structure):
		if "dm_reveal_objects" in map and map.dm_reveal_objects != null:
			for obj in map.dm_reveal_objects:
				var pos_raw = obj.get("position", {})
				var pos = Vector2(float(pos_raw.get("x", 0.0)), float(pos_raw.get("y", 0.0)))
				reveals.append({
					"position": pos,
					"radius": maxf(float(obj.get("dm_reveal_radius", 56.0)), 12.0),
				})
		return reveals


func _update_wall_rect_preview(a: Vector2, b: Vector2) -> void:
	# print("[DEBUG] _update_wall_rect_preview called: a=%s, b=%s" % [str(a), str(b)])
	if wall_visual_layer == null or not is_dm_view:
		return
	if _wall_rect_preview == null or not is_instance_valid(_wall_rect_preview):
		_wall_rect_preview_fill = Polygon2D.new()
		_wall_rect_preview_fill.color = Color(1.0, 0.9, 0.2, 0.18)
		wall_visual_layer.add_child(_wall_rect_preview_fill)

		_wall_rect_preview = Line2D.new()
		_wall_rect_preview.width = 2.0
		_wall_rect_preview.default_color = Color(1.0, 0.9, 0.2, 0.95)
		_wall_rect_preview.closed = true
		wall_visual_layer.add_child(_wall_rect_preview)
	var min_x := minf(a.x, b.x)
	var min_y := minf(a.y, b.y)
	var max_x := maxf(a.x, b.x)
	var max_y := maxf(a.y, b.y)
	_wall_rect_preview.points = PackedVector2Array([
		Vector2(min_x, min_y),
		Vector2(max_x, min_y),
		Vector2(max_x, max_y),
		Vector2(min_x, max_y),
	])
	if _wall_rect_preview_fill and is_instance_valid(_wall_rect_preview_fill):
		_wall_rect_preview_fill.polygon = PackedVector2Array([
			Vector2(min_x, min_y),
			Vector2(max_x, min_y),
			Vector2(max_x, max_y),
			Vector2(min_x, max_y),
		])


func _clear_wall_rect_preview() -> void:
	if _wall_rect_preview_fill and is_instance_valid(_wall_rect_preview_fill):
		_wall_rect_preview_fill.queue_free()
	_wall_rect_preview_fill = null
	if _wall_rect_preview and is_instance_valid(_wall_rect_preview):
		_wall_rect_preview.queue_free()
	_wall_rect_preview = null


func _update_fog_rect_preview(a: Vector2, b: Vector2, reveal: bool) -> void:
	if not is_dm_view:
		return
	if _fog_rect_preview == null or not is_instance_valid(_fog_rect_preview):
		_fog_rect_preview_fill = Polygon2D.new()
		_fog_rect_preview_fill.z_index = RenderLayer.FOG + 1
		add_child(_fog_rect_preview_fill)

		_fog_rect_preview = Line2D.new()
		_fog_rect_preview.width = 2.0
		_fog_rect_preview.closed = true
		_fog_rect_preview.z_index = RenderLayer.FOG + 1
		add_child(_fog_rect_preview)

	var edge_color := Color(0.2, 1.0, 0.35, 0.95) if reveal else Color(1.0, 0.35, 0.3, 0.95)
	var fill_color := Color(0.2, 1.0, 0.35, 0.20) if reveal else Color(1.0, 0.35, 0.3, 0.20)
	_fog_rect_preview.default_color = edge_color
	_fog_rect_preview_fill.color = fill_color

	var min_x := minf(a.x, b.x)
	var min_y := minf(a.y, b.y)
	var max_x := maxf(a.x, b.x)
	var max_y := maxf(a.y, b.y)
	_fog_rect_preview.points = PackedVector2Array([
		Vector2(min_x, min_y),
		Vector2(max_x, min_y),
		Vector2(max_x, max_y),
		Vector2(min_x, max_y),
	])
	if _fog_rect_preview_fill and is_instance_valid(_fog_rect_preview_fill):
		_fog_rect_preview_fill.polygon = PackedVector2Array([
			Vector2(min_x, min_y),
			Vector2(max_x, min_y),
			Vector2(max_x, max_y),
			Vector2(min_x, max_y),
		])


func _clear_fog_rect_preview() -> void:
	if _fog_rect_preview_fill and is_instance_valid(_fog_rect_preview_fill):
		_fog_rect_preview_fill.queue_free()
	_fog_rect_preview_fill = null
	if _fog_rect_preview and is_instance_valid(_fog_rect_preview):
		_fog_rect_preview.queue_free()
	_fog_rect_preview = null


func _set_selected_wall(index: int) -> void:
	if _map == null:
		_selected_wall_index = -1
		_refresh_selected_wall_visuals()
		return
	if index < 0 or index >= _map.wall_polygons.size():
		_selected_wall_index = -1
	else:
		_selected_wall_index = index
	_refresh_selected_wall_visuals()


func _refresh_selected_wall_visuals() -> void:
	if _wall_selection_outline and is_instance_valid(_wall_selection_outline):
		_wall_selection_outline.queue_free()
	_wall_selection_outline = null
	for n in _wall_handle_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_wall_handle_nodes.clear()

	if not has_selected_wall() or wall_visual_layer == null or not is_dm_view:
		return

	var points := _get_wall_points(_selected_wall_index)
	if points.is_empty():
		return
	if _wall_selection_outline == null or not is_instance_valid(_wall_selection_outline):
		_wall_selection_outline = Line2D.new()
		_wall_selection_outline.width = 4.0
		_wall_selection_outline.default_color = Color(0.25, 0.95, 1.0, 0.95)
		_wall_selection_outline.closed = true
	var packed := PackedVector2Array()
	for p in points:
		packed.append(p)
	_wall_selection_outline.points = packed
	wall_visual_layer.add_child(_wall_selection_outline)

	# Always show handles for both rectangles and polygons
	if points.size() >= 3:
		for p in points:
			if not p is Vector2:
				continue
			var handle := Polygon2D.new()
			handle.position = p
			handle.polygon = PackedVector2Array([
				Vector2(-WALL_HANDLE_SIZE_WORLD, -WALL_HANDLE_SIZE_WORLD),
				Vector2(WALL_HANDLE_SIZE_WORLD, -WALL_HANDLE_SIZE_WORLD),
				Vector2(WALL_HANDLE_SIZE_WORLD, WALL_HANDLE_SIZE_WORLD),
				Vector2(-WALL_HANDLE_SIZE_WORLD, WALL_HANDLE_SIZE_WORLD),
			])
			wall_visual_layer.add_child(handle)
			_wall_handle_nodes.append(handle)


func _get_wall_points(index: int) -> Array:
	if _map == null or index < 0 or index >= _map.wall_polygons.size():
		return []
	var out: Array = []
	var raw = _map.wall_polygons[index]
	if not raw is Array:
		return out
	for p in raw:
		if p is Vector2:
			out.append(p)
	return out


func _set_wall_points(index: int, points: Array) -> void:
	if _map == null or index < 0 or index >= _map.wall_polygons.size():
		return
	_map.wall_polygons[index] = points.duplicate(true)
	_rebuild_wall_occluders(_map)


func _find_wall_at_point(world_pos: Vector2) -> int:
	if _map == null:
		return -1
	for i in range(_map.wall_polygons.size() - 1, -1, -1):
		var pts := _get_wall_points(i)
		if pts.size() < 3:
			continue
		var poly := PackedVector2Array()
		for p in pts:
			poly.append(p)
		if Geometry2D.is_point_in_polygon(world_pos, poly):
			return i
	return -1


func _hit_test_selected_wall_handle(world_pos: Vector2) -> int:
	if not has_selected_wall():
		return -1
	var points := _get_wall_points(_selected_wall_index)
	if points.size() < 3:
		return -1
	var hit_radius := WALL_HANDLE_HIT_RADIUS_PX / maxf(camera.zoom.x, 0.001)
	for i in range(points.size()):
		var p = points[i]
		if p is Vector2 and (p as Vector2).distance_to(world_pos) <= hit_radius:
			return i
	return -1


func _apply_wall_move_drag(mm: InputEventMouseMotion) -> void:
	if not has_selected_wall() or _wall_drag_start_points.is_empty():
		return
	var delta_world := mm.relative / maxf(camera.zoom.x, 0.001)
	var moved: Array = []
	for p in _get_wall_points(_selected_wall_index):
		if p is Vector2:
			moved.append((p as Vector2) + delta_world)
	_set_wall_points(_selected_wall_index, moved)


func _apply_wall_handle_drag(world_pos: Vector2) -> void:
	if not has_selected_wall() or _wall_dragging_handle < 0:
		return
	var points := _wall_drag_start_points.duplicate()
	if points.size() < 3:
		return
	# For rectangles, preserve opposite corner logic
	if points.size() == 4:
		var opposite_idx := (_wall_dragging_handle + 2) % 4
		var fixed_v: Variant = points[opposite_idx]
		if not fixed_v is Vector2:
			return
		var fixed := fixed_v as Vector2
		var min_x := minf(fixed.x, world_pos.x)
		var min_y := minf(fixed.y, world_pos.y)
		var max_x := maxf(fixed.x, world_pos.x)
		var max_y := maxf(fixed.y, world_pos.y)
		_set_wall_points(_selected_wall_index, [
			Vector2(min_x, min_y),
			Vector2(max_x, min_y),
			Vector2(max_x, max_y),
			Vector2(min_x, max_y),
		])
	else:
		# For polygons, move only the selected handle
		if _wall_dragging_handle >= 0 and _wall_dragging_handle < points.size():
			points[_wall_dragging_handle] = world_pos
			_set_wall_points(_selected_wall_index, points)
