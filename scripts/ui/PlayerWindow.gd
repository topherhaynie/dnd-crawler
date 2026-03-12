extends Node

# ---------------------------------------------------------------------------
# PlayerWindow — root controller for the shared Player / TV display window.
#
# Phase 2 responsibilities:
#   • Host the MapView (same scene as DM uses, but without DM UI)
#   • React to "map_loaded" packets from the DM process via PlayerMain
#   • Phase 4 will add a FoW CanvasLayer and player token spawning
#
# This node is instantiated by PlayerMain.gd, which also owns PlayerClient.
# PlayerMain connects PlayerClient.state_received → PlayerWindow.on_state().
# ---------------------------------------------------------------------------

const MapViewScene: PackedScene = preload("res://scenes/MapView.tscn")

var _map_view: Node2D = null


func _ready() -> void:
	_map_view = MapViewScene.instantiate()
	_map_view.name = "MapView"
	add_child(_map_view)
	print("PlayerWindow: ready — awaiting map from DM")


# ---------------------------------------------------------------------------
# Called by PlayerMain when a state packet arrives from the DM
# ---------------------------------------------------------------------------

func on_state(data: Dictionary) -> void:
	var msg: String = data.get("msg", "")
	match msg:
		"map_loaded":
			_handle_map_loaded(data.get("map", {}))
		"map_updated":
			_handle_map_updated(data.get("map", {}))
		"camera_update":
			_handle_camera_update(data)
		"state", "delta":
			# Phase 4: token positions, FoW updates, etc.
			pass
		_:
			pass


# ---------------------------------------------------------------------------
# Map loading
# ---------------------------------------------------------------------------

func _handle_map_loaded(map_dict: Dictionary) -> void:
	if map_dict.is_empty():
		push_warning("PlayerWindow: received empty map dict")
		return
	var map: MapData = MapData.from_dict(map_dict)
	_map_view.load_map(map)
	print("PlayerWindow: map loaded — '%s'" % map.map_name)


func _handle_map_updated(map_dict: Dictionary) -> void:
	## Grid/scale change — update the overlay without touching the camera.
	if map_dict.is_empty() or _map_view == null:
		return
	var map: MapData = MapData.from_dict(map_dict)
	_map_view.grid_overlay.apply_map_data(map)
	print("PlayerWindow: map updated (grid/scale) — '%s'" % map.map_name)


func _handle_camera_update(data: Dictionary) -> void:
	if _map_view == null:
		return
	var pos_d: Dictionary = data.get("position", {"x": 0.0, "y": 0.0})
	var pos := Vector2(float(pos_d.get("x", 0.0)), float(pos_d.get("y", 0.0)))
	var zoom := float(data.get("zoom", 1.0))
	_map_view.set_camera_state(pos, zoom)
