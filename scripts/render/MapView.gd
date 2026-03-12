extends Node2D

# ---------------------------------------------------------------------------
# MapView — shared map viewport used by both the DM window and the Player
# display process.
#
# Scene structure (MapView.tscn):
#   MapView (Node2D)
#   └── Camera2D
#   └── MapImage     (TextureRect)
#   └── GridOverlay  (Node2D, GridOverlay.gd)
#   └── WallLayer    (Node2D — LightOccluder2D children, Phase 6)
#   └── TokenLayer   (Node2D — PlayerSprite children, Phase 4)
#
# Tool modes (set by DMWindow toolbar):
#   SELECT — default; left-click is reserved for future token interaction
#   PAN    — left-click-drag pans the camera
#
# Camera: position = world point shown at screen centre.
#   To show world (0,0) at screen top-left, init to viewport_size * 0.5.
#   call _reset_camera() or load saved state from MapData.
#
# Input summary:
#   Left-drag (Pan tool)   — pan
#   Middle-drag            — pan (always, regardless of tool)
#   Scroll wheel           — zoom toward cursor
#   Trackpad two-finger    — pan (InputEventPanGesture)
#   Trackpad pinch         — zoom (InputEventMagnifyGesture)
#   Arrow keys             — smooth pan via _process / Input.is_key_pressed()
#                            (buttons must have FOCUS_NONE to avoid UI nav)
# ---------------------------------------------------------------------------

enum Tool {SELECT, PAN}

const ZOOM_MIN: float = 0.1
const ZOOM_MAX: float = 8.0
const ZOOM_STEP: float = 0.12 ## per scroll click
const PAN_SPEED: float = 500.0 ## px/sec for arrow-key pan

@onready var camera: Camera2D = $Camera2D
@onready var map_image: TextureRect = $MapImage
@onready var grid_overlay: Node2D = $GridOverlay

var _map: MapData = null
var active_tool: Tool = Tool.SELECT

var _panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_cam: Vector2 = Vector2.ZERO

signal viewport_indicator_moved(new_center: Vector2)

## World-space rect — kept in sync with _indicator_overlay for hit-testing.
var _viewport_indicator: Rect2 = Rect2()
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

	# Restore saved view, or default to showing the map top-left at the
	# top-left corner of the viewport (camera_position == ZERO means new map).
	if map.camera_zoom != 1.0 or map.camera_position != Vector2.ZERO:
		camera.zoom = Vector2.ONE * map.camera_zoom
		camera.position = map.camera_position
	else:
		_reset_camera()

	print("MapView: loaded map '%s'" % map.map_name)


func get_map() -> MapData:
	return _map


func get_camera_state() -> Dictionary:
	## Returns the current camera position and zoom as a dict for broadcasting.
	## Returns a zero-state if called before _ready() has resolved @onready vars.
	if camera == null:
		return {"position": {"x": 0.0, "y": 0.0}, "zoom": 1.0}
	return {"position": {"x": camera.position.x, "y": camera.position.y}, "zoom": camera.zoom.x}


func set_camera_state(pos: Vector2, zoom: float) -> void:
	## Apply a camera state received from an external source (e.g. DM mini-view broadcast).
	camera.position = pos
	camera.zoom = Vector2.ONE * clampf(zoom, ZOOM_MIN, ZOOM_MAX)


func _ready() -> void:
	# Add the indicator overlay as the last child so it renders on top of
	# MapImage, GridOverlay, and all other siblings.
	_indicator_overlay = load("res://scripts/render/IndicatorOverlay.gd").new()
	_indicator_overlay.name = "IndicatorOverlay"
	_indicator_overlay.camera = camera
	add_child(_indicator_overlay)


func set_viewport_indicator(world_rect: Rect2) -> void:
	## Set the player-viewport indicator rect in world space. Pass Rect2() to hide.
	_viewport_indicator = world_rect
	_indicator_overlay.set_rect(world_rect)


func save_camera_to_map() -> void:
	if _map:
		_map.camera_position = camera.position
		_map.camera_zoom = camera.zoom.x


func _reset_camera() -> void:
	## Position camera so the map top-left aligns with the viewport top-left.
	camera.zoom = Vector2.ONE
	# Camera.position = world point at screen centre.
	# To get world (0,0) at screen top-left: centre = viewport_size / 2.
	camera.position = get_viewport().get_visible_rect().size * 0.5


func zoom_in() -> void:
	_zoom_camera(ZOOM_STEP, get_viewport().get_visible_rect().size * 0.5)


func zoom_out() -> void:
	_zoom_camera(-ZOOM_STEP, get_viewport().get_visible_rect().size * 0.5)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
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
					if _viewport_indicator != Rect2() and _viewport_indicator.has_point(get_global_mouse_position()):
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
			_indicator_overlay.set_rect(_viewport_indicator)
			viewport_indicator_moved.emit(_viewport_indicator.get_center())
			get_viewport().set_input_as_handled()
		elif _panning:
			var motion := event as InputEventMouseMotion
			camera.position = _pan_start_cam - (motion.position - _pan_start_mouse) / camera.zoom.x
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Smooth arrow-key pan (bypasses UI focus).
	var kdir := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT): kdir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT): kdir.x += 1.0
	if Input.is_key_pressed(KEY_UP): kdir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN): kdir.y += 1.0
	if kdir != Vector2.ZERO:
		camera.position += kdir.normalized() * PAN_SPEED * delta / camera.zoom.x

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
