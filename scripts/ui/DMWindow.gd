extends Node

# ---------------------------------------------------------------------------
# DMWindow — top-level UI controller for the DM process.
#
# Provides:
#   • MenuBar with File / Edit / View menus
#   • Collapsible toolbar with Select / Pan tool toggle + Zoom controls +
#	 Grid-type selector + status label
#   • Map loading via native FileDialog
#   • Calibration workflow via Edit > Calibrate Grid...
#   • Manual scale entry via Edit > Set Scale Manually...
#   • Grid overlay visibility toggle via View menu
#   • Save / load JSON map data (user://data/maps/)
#   • Broadcasts map data to connected Player clients via NetworkManager
#
# Phase stubs (wired but not functional yet):
#   • FogOfWarLayer references (Phase 6)
#   • Token placement (Phase 4)
# ---------------------------------------------------------------------------

const MapViewScene: PackedScene = preload("res://scenes/MapView.tscn")
const BackendRuntimeScript: Script = preload("res://scripts/core/BackendRuntime.gd")
const JsonUtilsScript = preload("res://scripts/utils/JsonUtils.gd")
const GameSaveDataScript = preload("res://scripts/services/game_state/models/GameSaveData.gd")
const ToolPaletteScript = preload("res://scripts/ui/ToolPalette.gd")
const NetworkUtilsScript = preload("res://scripts/utils/NetworkUtils.gd")
const QRCodeScript = preload("res://scripts/utils/QRCode.gd")

const MAP_DIR := "user://data/maps/"
const SAVE_DIR := "user://data/saves/"
const SUPPORTED_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]

# ── UI node references ──────────────────────────────────────────────────────
var _map_view: MapView = null
var _cal_tool: Node = null ## CalibrationTool instance

var _file_dialog: FileDialog = null
var _cal_dialog: ConfirmationDialog = null
var _manual_scale_dialog: ConfirmationDialog = null
## Content-root VBoxContainers for each small dialog — scaled in _apply_ui_scale().
var _cal_dialog_root: Control = null
var _manual_scale_dialog_root: Control = null
var _offset_dialog_root: Control = null
var _token_editor_dialog_root: Control = null

var _feet_spin: SpinBox = null ## calibration: feet input
var _offset_x_spin: SpinBox = null ## calibration: grid offset X
var _offset_y_spin: SpinBox = null ## calibration: grid offset Y
var _scale_px_spin: SpinBox = null ## manual scale: pixels
var _scale_ft_spin: SpinBox = null ## manual scale: feet

## Standalone offset dialog (Edit > Set Grid Offset)
var _offset_dialog: ConfirmationDialog = null
var _solo_offset_x_spin: SpinBox = null
var _solo_offset_y_spin: SpinBox = null

## New Map / Open Map workflow
var _open_map_dialog: FileDialog = null
var _save_as_dialog: FileDialog = null ## native Save panel for naming/renaming maps
var _save_game_dialog: FileDialog = null ## Save Game As dialog
var _load_game_dialog: FileDialog = null ## Load Game dialog
var _pending_image_path: String = "" ## holds image path while native save dialog is open
var _map_name_mode: String = "new" ## "new" or "save_as"
var _active_map_bundle_path: String = "" ## absolute path to the current .map bundle directory
var _active_save_bundle_path: String = "" ## absolute path to the current .sav bundle

var _status_label: Label = null
var _ui_root: VBoxContainer = null

# Player profile form fields
var _profile_orientation_spin: SpinBox = null

var _palette: PanelContainer = null ## Photoshop-style tool palette (ToolPalette)
var _view_menu: PopupMenu = null ## kept for checkmark management
var _edit_menu: PopupMenu = null ## kept for undo/redo label updates
var _grid_submenu: PopupMenu = null ## Grid Type submenu in View menu
var _grid_type_selected: int = MapData.GridType.SQUARE ## tracks current grid type
var _palette_window: Window = null ## non-null when palette is undocked
var _palette_floating: bool = false

# Handler for wall tool dropdown selection
func _on_wall_tool_selected(index: int) -> void:
	# 0 = Rectangle, 1 = Polygon
	# print("[DEBUG] Wall tool dropdown selected: index=", index)
	if _map_view == null:
		# print("[DEBUG] _on_wall_tool_selected: _map_view is null")
		return
	if index == 0:
		# print("[DEBUG] Activating Wall Rect tool in MapView")
		# _map_view.active_tool = _map_view.Tool.WALL
		# _map_view.wall_subtool = "rect"
		_map_view.set_wall_rect_mode(true)
		# print("[DEBUG] MapView state after dropdown: active_tool=", _map_view.active_tool, "wall_subtool=", _map_view.wall_subtool)

		# _map_view.set_wall_polygon_mode(false)
		_set_status("Wall Rect: drag on map to place wall occluder rectangle")
	elif index == 1:
		# print("[DEBUG] Activating Wall Polygon tool in MapView")
		# _map_view.active_tool = _map_view.Tool.WALL
		# _map_view.wall_subtool = "polygon"
		# _map_view.set_wall_rect_mode(false)
		_map_view.set_wall_polygon_mode(true)
		# print("[DEBUG] MapView state after dropdown: active_tool=", _map_view.active_tool, "wall_subtool=", _map_view.wall_subtool)

		_set_status("Wall Polygon: click to add points, double-click/right-click/Escape to finish")

# ── Token placement & editing ───────────────────────────────────────────────
## Token editor popup fields
var _token_editor_dialog: ConfirmationDialog = null
var _token_editor_id: String = "" ## empty = new token
var _token_label_edit: LineEdit = null
var _token_category_option: OptionButton = null
var _token_visible_check: CheckBox = null
var _token_perception_spin: SpinBox = null
var _token_autopause_check: CheckBox = null
var _token_autopause_collision_check: CheckBox = null
var _token_pause_interact_check: CheckBox = null
var _token_auto_reveal_check: CheckBox = null
var _token_trigger_spin: SpinBox = null
var _token_autopause_max_spin: SpinBox = null
var _token_notes_edit: TextEdit = null
var _token_width_spin: SpinBox = null
var _token_height_spin: SpinBox = null
var _token_rotation_spin: SpinBox = null
var _token_shape_option: OptionButton = null
var _token_blocks_los_check: CheckBox = null
var _token_blocks_los_row: HBoxContainer = null
## Puzzle notes sub-section
var _puzzle_notes_container: VBoxContainer = null
var _puzzle_notes_scroll: ScrollContainer = null
var _puzzle_notes_add_btn: Button = null
## Right-click context menu for tokens
var _token_context_menu: PopupMenu = null
var _token_context_id: String = ""

# ── Passage paint panel ────────────────────────────────────────────────────
var _passage_panel: PanelContainer = null
var _passage_mode_option: OptionButton = null
var _passage_brush_slider: HSlider = null
var _passage_token_label: Label = null
var _passage_mode_label: Label = null
var _passage_brush_label: Label = null
var _passage_commit_btn: Button = null
var _passage_clear_btn: Button = null
var _selected_passage_token_id: String = ""

# ── Phase 3: player profiles ------------------------------------------------
var _profiles_dialog: AcceptDialog = null
var _profiles_list: ItemList = null
var _profile_name_edit: LineEdit = null
var _profile_speed_spin: SpinBox = null
var _profile_vision_option: OptionButton = null
var _profile_darkvision_spin: SpinBox = null
var _profile_perception_spin: SpinBox = null
var _profile_dash_check: CheckBox = null
var _profile_input_type_option: OptionButton = null
var _profile_input_id_edit: LineEdit = null
var _profile_gamepad_option: OptionButton = null
var _profile_ws_option: OptionButton = null
var _profile_extras_edit: TextEdit = null
var _profile_passive_label: Label = null
var _profile_id_label: Label = null
var _profile_add_btn: Button = null
var _profile_delete_btn: Button = null
var _profile_add_btn_alt: Button = null
var _profile_delete_btn_alt: Button = null
var _profile_save_btn: Button = null
var _profile_cancel_new_btn: Button = null
var _profile_selected_index: int = -1
var _profile_is_new_draft: bool = false
var _profiles_import_dialog: FileDialog = null
var _profiles_export_dialog: FileDialog = null
var _profiles_root: Control = null
var _profile_color_btn: ColorPickerButton = null
## Legacy autoload reference removed — use registry-first `_network()` helper

# ── Measurement panel ────────────────────────────────────────────────────────
## Standalone floating window for measurement tools.
var _measure_panel: Window = null
## ButtonGroup shared by all 5 measure-tool buttons.
var _measure_tool_group: ButtonGroup = null
## ItemList showing all active measurement shapes (label + × delete button).
var _measure_shape_list: ItemList = null

# ── Player freeze panel ─────────────────────────────────────────────────────
var _freeze_panel: Control = null
var _freeze_panel_window: Window = null
var _freeze_panel_floating: bool = false
var _freeze_undock_btn: Button = null
var _freeze_panel_title: Label = null ## shown when docked, hidden when floating
var _freeze_master_btn: Button = null ## "Freeze All" / "Free All" master toggle
var _fp_vbox: VBoxContainer = null ## inner scale root — scaled by _apply_ui_scale like _ui_root
var _freeze_rows: VBoxContainer = null
var _freeze_row_buttons: Dictionary = {} ## {player_id: CheckButton}
var _freeze_light_buttons: Dictionary = {} ## {player_id: Button}
var _autopause_locked_ids: Dictionary = {} ## {player_id: true} — tracks which locks came from autopause
var _detected_token_ids: Array = [] ## token IDs currently in detection state
var _ui_layer: CanvasLayer = null ## CanvasLayer that owns _ui_root; freeze panel anchors here directly

# ── Share player link dialog ────────────────────────────────────────────────
var _share_dialog: AcceptDialog = null
var _share_dialog_root: VBoxContainer = null
var _share_qr_rect: TextureRect = null
var _share_url_label: Label = null

# ── Player viewport control ─────────────────────────────────────────────────
# The green box on the DM map shows what players currently see.
# Drag the box to reposition the player camera; use the toolbar to zoom.
var _player_cam_pos: Vector2 = Vector2(960.0, 540.0)
var _player_cam_zoom: float = 1.0
var _player_cam_rotation: int = 0
var _player_window_size: Vector2 = Vector2(1920.0, 1080.0)
var _player_is_fullscreen: bool = false
var _play_mode: bool = false

const _BROADCAST_DEBOUNCE: float = 0.05 ## seconds — near-instant feel
const _PLAYER_STATE_BROADCAST_DEBOUNCE: float = 0.0
const _FOG_BROADCAST_DEBOUNCE: float = 1.5
const _FOG_AUTO_SYNC_DEBOUNCE: float = 0.0
const _FOG_DELTA_MAX_CELLS: int = 1200
const _ENABLE_CONTINUOUS_FOG_SYNC: bool = false
const DEBUG_FOG_SNAPSHOT: bool = false
const DEBUG_FOG_TELEMETRY: bool = false
const _PERCEPTION_CHECK_INTERVAL: float = 0.25
var _perception_timer: float = 0.0
var _broadcast_dirty: bool = false
var _broadcast_countdown: float = 0.0
var _player_state_dirty: bool = false
var _player_state_countdown: float = 0.0
var _fog_dirty: bool = false
var _fog_countdown: float = 0.0
var _fog_snapshot_in_flight: bool = false
var _fog_snapshot_queued: bool = false
var _backend: BackendRuntime = null
var _dm_override_player_id: String = ""
var _initial_sync_ack_pending: Dictionary = {}
var _initial_sync_attempt_by_peer: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	# Bind to the runtime Network service/adapter (deferred to handle autoload ordering).
	call_deferred("_init_network_binding")
	# Defer profile bindings to ensure GameStateService is registered by bootstrap.
	call_deferred("_ensure_profile_bindings")
	# Defer game-state bindings for lock/unlock signal + initial freeze panel populate.
	call_deferred("_ensure_game_state_bindings")
	# Defer input-action bindings so InputService is registered by bootstrap.
	call_deferred("_ensure_input_bindings")
	# Re-apply gamepad bindings whenever a controller connects or disconnects.
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Defer history bindings so HistoryService is registered by bootstrap.
	call_deferred("_ensure_history_bindings")
	# Release all undo/redo closures when this node is freed to avoid dangling refs.
	tree_exiting.connect(func():
		var _r := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if _r != null and _r.history != null:
			_r.history.clear())
	_apply_ui_scale()
	print("DMWindow: ready")


func _ensure_profile_bindings() -> void:
	var pm := _profile_service()
	if pm == null:
		call_deferred("_ensure_profile_bindings")
		return
	if not pm.is_connected("profiles_changed", Callable(self , "_on_profiles_changed")):
		pm.profiles_changed.connect(_on_profiles_changed)
	_apply_profile_bindings()


func _ensure_game_state_bindings() -> void:
	var gs := _game_state()
	if gs == null:
		call_deferred("_ensure_game_state_bindings")
		return
	if not gs.is_connected("player_lock_changed", Callable(self , "_on_player_lock_changed_external")):
		gs.player_lock_changed.connect(_on_player_lock_changed_external)
	_refresh_freeze_panel()


func _ensure_input_bindings() -> void:
	var input: InputManager = _input_service()
	if input == null or input.service == null:
		call_deferred("_ensure_input_bindings")
		return
	# Signal subscription: IInputService extends Node; signals live on the Node
	# instance. RefCounted manager cannot re-emit them — approved narrow exception.
	var svc: IInputService = input.service
	if not svc.is_connected("input_action_pressed", Callable(self , "_on_player_action")):
		svc.input_action_pressed.connect(_on_player_action)


func _ensure_history_bindings() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.history == null or registry.history.service == null:
		call_deferred("_ensure_history_bindings")
		return
	# Signal subscription: IHistoryService extends Node; signals live on the Node
	# instance. RefCounted manager cannot re-emit them — approved narrow exception.
	var svc: IHistoryService = registry.history.service
	if not svc.is_connected("history_changed", Callable(self , "_refresh_history_menu")):
		svc.history_changed.connect(_refresh_history_menu)
	_refresh_history_menu()


func _refresh_history_menu() -> void:
	if _edit_menu == null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.history == null:
		return
	var can_undo := registry.history.can_undo()
	var can_redo := registry.history.can_redo()
	var undo_idx := _edit_menu.get_item_index(14)
	var redo_idx := _edit_menu.get_item_index(15)
	if undo_idx >= 0:
		_edit_menu.set_item_disabled(undo_idx, not can_undo)
		var undo_desc := registry.history.get_undo_description()
		_edit_menu.set_item_text(undo_idx, "Undo" if undo_desc.is_empty() else "Undo: %s" % undo_desc)
	if redo_idx >= 0:
		_edit_menu.set_item_disabled(redo_idx, not can_redo)
		var redo_desc := registry.history.get_redo_description()
		_edit_menu.set_item_text(redo_idx, "Redo" if redo_desc.is_empty() else "Redo: %s" % redo_desc)


func _network() -> NetworkManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.network == null:
		return null
	return registry.network


func _input_service() -> InputManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.input == null:
		return null
	return registry.input


## Network helper wrappers (centralise registry fallback and null-guards)
func _nm_broadcast_to_displays(msg: Dictionary) -> void:
	var nm := _network()
	if nm != null:
		nm.broadcast_to_displays(msg)

func _nm_broadcast_map(map: MapData) -> void:
	var nm := _network()
	if nm != null:
		nm.broadcast_to_displays({"msg": "map_loaded", "map": map.to_dict()})

func _nm_broadcast_map_update(map: MapData) -> void:
	var nm := _network()
	if nm != null:
		nm.broadcast_to_displays({"msg": "map_updated", "map": map.to_dict()})

func _nm_send_map_to_display(peer_id: int, map: MapData, is_update: bool, fog_snapshot: Dictionary) -> void:
	var nm := _network()
	if nm == null:
		return
	nm.send_map_to_display(peer_id, map, is_update, fog_snapshot)

func _nm_bind_peer(peer_id: int, player_id: Variant) -> void:
	var nm := _network()
	if nm != null:
		nm.bind_peer(peer_id, player_id)

func _nm_get_connected_input_peers() -> Array:
	var nm := _network()
	if nm != null:
		return nm.get_connected_input_peers()
	return []

func _nm_get_peer_bound_player(peer_id: int) -> String:
	var nm := _network()
	if nm != null:
		return str(nm.get_peer_bound_player(peer_id))
	return ""

func _nm_displays_under_backpressure() -> bool:
	var nm := _network()
	if nm != null:
		return bool(nm.displays_under_backpressure())
	return false

func _nm_is_display_peer_connected(peer_id: int) -> bool:
	var nm := _network()
	if nm != null:
		return bool(nm.is_display_peer_connected(peer_id))
	return true


func _game_state() -> GameStateManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.game_state == null:
		return null
	return registry.game_state


func _token_manager() -> TokenManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return null
	return registry.token


func _map_service() -> MapManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.map == null:
		return null
	return registry.map


func _map() -> MapData:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.map != null and registry.map.model != null:
		return registry.map.model
	if _map_view != null:
		return _map_view.get_map()
	return null


func _pixels_per_5ft_current() -> float:
	var map: MapData = _map()
	if map == null:
		return 60.0
	return map.cell_px if map.grid_type == MapData.GridType.SQUARE else map.hex_size * 2.0


func _init_network_binding() -> void:
	var nm := _network()
	if nm == null:
		# Try again later if not yet registered
		call_deferred("_init_network_binding")
		return
	# Signals are declared on INetworkService (a Node), not on the RefCounted manager.
	# This is the one approved location where we access registry.network.service directly
	# for signal subscription only — all method calls elsewhere use nm (the manager).
	var svc: INetworkService = nm.service
	if svc == null:
		call_deferred("_init_network_binding")
		return
	var connected_any := false
	if not svc.is_connected("display_peer_registered", Callable(self , "_on_display_peer_registered")):
		svc.display_peer_registered.connect(_on_display_peer_registered)
		connected_any = true
	if not svc.is_connected("client_disconnected", Callable(self , "_on_client_disconnected")):
		svc.client_disconnected.connect(_on_client_disconnected)
		connected_any = true
	if not svc.is_connected("display_viewport_resized", Callable(self , "_on_display_viewport_resized")):
		svc.display_viewport_resized.connect(_on_display_viewport_resized)
		connected_any = true
	if not svc.is_connected("display_fullscreen_changed", Callable(self , "_on_display_fullscreen_changed")):
		svc.display_fullscreen_changed.connect(_on_display_fullscreen_changed)
		connected_any = true
	if not svc.is_connected("display_sync_applied", Callable(self , "_on_display_sync_applied")):
		svc.display_sync_applied.connect(_on_display_sync_applied)
		connected_any = true
	# If the service exists but hasn't yet exposed the expected signals, retry shortly.
	if not connected_any:
		call_deferred("_init_network_binding")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		# Defer so the viewport reports its final settled size, not
		# an intermediate size mid-transition (e.g. macOS fullscreen animation).
		var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry != null and registry.ui_scale != null:
			registry.ui_scale.refresh()
		call_deferred("_apply_ui_scale")


func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if not key_event.is_command_or_control_pressed():
		return
	if key_event.keycode == KEY_Z:
		var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry == null or registry.history == null:
			return
		if key_event.shift_pressed:
			# Redo
			var desc := registry.history.get_redo_description()
			if registry.history.redo():
				_set_status("Redo: %s" % desc)
		else:
			# Undo
			var desc := registry.history.get_undo_description()
			if registry.history.undo():
				_set_status("Undo: %s" % desc)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _player_state_countdown > 0.0:
		_player_state_countdown = maxf(0.0, _player_state_countdown - delta)
	if _fog_countdown > 0.0:
		_fog_countdown = maxf(0.0, _fog_countdown - delta)
	if _fog_dirty and _fog_countdown <= 0.0:
		_fog_dirty = false
		_broadcast_fog_state()
		_fog_countdown = _FOG_BROADCAST_DEBOUNCE

	_update_dm_override_input()
	if _simulate_player_movement(delta):
		_player_state_dirty = true
		if _player_state_countdown <= 0.0:
			_broadcast_player_state()
			_player_state_dirty = false
			_player_state_countdown = _PLAYER_STATE_BROADCAST_DEBOUNCE

	# Broadcast queued player-viewport updates after a short debounce.
	if not _broadcast_dirty:
		pass
	else:
		_broadcast_countdown -= delta
		if _broadcast_countdown <= 0.0:
			_broadcast_dirty = false
			_broadcast_player_viewport()

	if _player_state_dirty and _player_state_countdown <= 0.0:
		_player_state_dirty = false
		_broadcast_player_state()

	# Periodic perception-proximity check — auto-reveal tokens whose DC is
	# met by a nearby player's passive perception.
	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer = _PERCEPTION_CHECK_INTERVAL
		_run_perception_check()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# ── MapView ─────────────────────────────────────────────────────────────
	_map_view = MapViewScene.instantiate() as MapView
	_map_view.name = "MapView"
	add_child(_map_view)
	_map_view.allow_keyboard_pan = false
	_map_view.set_dm_view(true)
	_map_view.fog_changed.connect(_on_map_fog_changed)
	_map_view.fog_delta.connect(_on_map_fog_delta)
	_map_view.fog_brush_applied.connect(_on_map_fog_brush_applied)
	_map_view.walls_changed.connect(_on_map_walls_changed)
	_map_view.spawn_points_changed.connect(_on_map_spawn_points_changed)
	_map_view.spawn_point_selected.connect(_on_spawn_point_selected)
	_map_view.token_drag_started.connect(_on_token_drag_started)
	_map_view.token_drag_completed.connect(_on_token_drag_completed)
	_map_view.token_resize_completed.connect(_on_token_resize_completed)
	_map_view.token_rotation_completed.connect(_on_token_rotation_completed)
	_map_view.token_trigger_radius_changed.connect(_on_token_trigger_radius_changed)
	_map_view.token_place_requested.connect(_on_token_place_requested)
	_map_view.token_right_clicked.connect(_on_token_right_clicked)
	_map_view.token_selected.connect(_on_token_selected)
	_map_view.passage_paths_committed.connect(_on_passage_paths_committed)
	_wire_measure_signals()
	_backend = BackendRuntimeScript.new() as BackendRuntime
	_backend.name = "BackendRuntime"
	add_child(_backend)
	_backend.configure(_map_view)

	# CalibrationTool lives inside MapView's world-space so its drawn overlay
	# follows the camera correctly.
	_cal_tool = load("res://scripts/tools/CalibrationTool.gd").new()
	_cal_tool.name = "CalibrationTool"
	_map_view.add_child(_cal_tool)

	# ── CanvasLayer for UI (always on top) ───────────────────────────────────
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UILayer"
	_ui_layer.layer = 10
	add_child(_ui_layer)

	# Root VBox fills the entire viewport
	_ui_root = VBoxContainer.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_layer.add_child(_ui_root)

	# ── Menu bar ─────────────────────────────────────────────────────────────
	var menu_bar := MenuBar.new()
	menu_bar.prefer_global_menu = true ## merge into native OS menu bar
	_ui_root.add_child(menu_bar)

	# File menu
	var file_menu := PopupMenu.new()
	file_menu.name = "File"
	file_menu.add_item("New Map from Image…", 0)
	file_menu.add_item("Open Map…", 1)
	file_menu.add_separator()
	file_menu.add_item("Save Map", 2)
	file_menu.add_item("Save Map As…", 3)
	file_menu.add_separator()
	file_menu.add_item("Save Game", 4)
	file_menu.add_item("Save Game As…", 5)
	file_menu.add_item("Load Game…", 6)
	file_menu.add_separator()
	file_menu.add_item("Quit", 9)
	file_menu.id_pressed.connect(_on_file_menu_id)
	menu_bar.add_child(file_menu)

	# Edit menu
	var edit_menu := PopupMenu.new()
	edit_menu.name = "Edit"
	edit_menu.add_item("Undo", 14)
	edit_menu.add_item("Redo", 15)
	edit_menu.add_separator()
	edit_menu.add_item("Calibrate Grid…", 10)
	edit_menu.add_item("Set Scale Manually…", 11)
	edit_menu.add_item("Set Grid Offset…", 12)
	edit_menu.add_separator()
	edit_menu.add_item("Player Profiles…", 13)
	edit_menu.id_pressed.connect(_on_edit_menu_id)
	_edit_menu = edit_menu
	# Undo/Redo start disabled; enabled once commands are pushed.
	edit_menu.set_item_disabled(edit_menu.get_item_index(14), true)
	edit_menu.set_item_disabled(edit_menu.get_item_index(15), true)
	menu_bar.add_child(edit_menu)

	# View menu  (indices matter for set_item_checked)
	# idx 0 → id 20 Toolbar
	# idx 1 → id 25 Player Freeze Panel
	# idx 2 → id 21 Grid Overlay
	# idx 3 → separator
	# idx 4 → id 22 Reset View
	# idx 5 → separator
	# idx 6 → id 24 Sync Fog Now
	# idx 7 → separator
	# idx 8 → id 26 Measurement Tools…
	# idx 9 → separator
	# idx 10 → Grid Type submenu
	# idx 11 → separator
	# idx 12 → id 23 Launch Player Window
	_view_menu = PopupMenu.new()
	_view_menu.name = "View"
	_view_menu.add_check_item("Toolbar", 20)
	_view_menu.set_item_checked(0, true)
	_view_menu.add_check_item("Player Freeze Panel", 25)
	_view_menu.set_item_checked(1, true)
	_view_menu.add_check_item("Grid Overlay", 21)
	_view_menu.set_item_checked(2, true)
	_view_menu.add_separator()
	_view_menu.add_item("Reset View", 22)
	_view_menu.add_separator()
	_view_menu.add_item("Sync Fog Now", 24)
	_view_menu.add_item("Reset Fog…", 27)
	_view_menu.add_check_item("Fog Overlay Effect", 28)
	_view_menu.set_item_checked(_view_menu.get_item_index(28), false)
	_view_menu.add_separator()
	_view_menu.add_item("Measurement Tools…", 26)
	_view_menu.add_separator()

	# Grid Type submenu
	_grid_submenu = PopupMenu.new()
	_grid_submenu.name = "GridType"
	_grid_submenu.add_radio_check_item("□  Square", MapData.GridType.SQUARE)
	_grid_submenu.add_radio_check_item("⬢  Hex Flat-top", MapData.GridType.HEX_FLAT)
	_grid_submenu.add_radio_check_item("⬣  Hex Pointy-top", MapData.GridType.HEX_POINTY)
	_grid_submenu.set_item_checked(0, true)
	_grid_submenu.id_pressed.connect(_on_grid_submenu_id)
	_view_menu.add_child(_grid_submenu)
	_view_menu.add_submenu_node_item("Grid Type", _grid_submenu)

	_view_menu.add_separator()
	_view_menu.add_item("▶ Launch Player Window", 23)
	_view_menu.id_pressed.connect(_on_view_menu_id)
	menu_bar.add_child(_view_menu)

	# Session menu
	var session_menu := PopupMenu.new()
	session_menu.name = "Session"
	session_menu.add_item("Share Player Link…", 30)
	session_menu.id_pressed.connect(_on_session_menu_id)
	menu_bar.add_child(session_menu)

	# ── Content row: map spacer ─────────────────────────────────────────────
	var content_row := HBoxContainer.new()
	content_row.name = "ContentRow"
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_root.add_child(content_row)

	# ── Tool palette (on _ui_layer for crisp HiDPI rendering) ───────────────
	_palette = ToolPaletteScript.new()
	_palette.name = "ToolPalette"
	# Anchor to left edge, full height (mirrors freeze panel on right).
	_palette.anchor_left = 0.0
	_palette.anchor_right = 0.0
	_palette.anchor_top = 0.0
	_palette.anchor_bottom = 1.0
	_palette.grow_horizontal = Control.GROW_DIRECTION_END
	_palette.setup(_get_ui_scale_mgr())
	_ui_layer.add_child(_palette)
	_apply_palette_size()

	# Wire palette signals
	_palette.tool_activated.connect(_on_palette_tool_activated)
	_palette.action_fired.connect(_on_palette_action_fired)
	_palette.fog_mode_changed.connect(_on_palette_fog_mode_changed)
	_palette.wall_mode_changed.connect(_on_wall_tool_selected)
	_palette.spawn_profile_selected.connect(_on_spawn_profile_selected)
	_palette.spawn_auto_assign_requested.connect(_on_spawn_auto_assign)
	_palette.move_to_spawns_requested.connect(_on_move_to_spawns)
	_palette.play_mode_toggled.connect(_on_palette_play_mode_toggled)
	_palette.dm_fog_visible_toggled.connect(_on_dm_fog_visible_toggled)
	_palette.flashlights_only_toggled.connect(_on_flashlights_only_toggled)
	_palette.undock_btn.pressed.connect(_on_undock_btn_pressed)

	# Add flyout panel to ui layer (not ui_root) for HiDPI stability
	_ui_layer.add_child(_palette.get_flyout())

	# ── Map area spacer (passes mouse through to the map) ────────────────────
	var map_spacer := Control.new()
	map_spacer.name = "MapSpacer"
	map_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_row.add_child(map_spacer)

	# ── Player freeze panel (vertical side panel, right side) ─────────────────
	# Added directly to _ui_layer (not _ui_root) so _ui_root.scale does not
	# push it off-screen on HiDPI / Retina displays.
	_build_freeze_panel()
	_build_passage_panel()

	_status_label = Label.new()
	_status_label.text = "No map loaded"
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ui_root.add_child(_status_label)

	# ── FileDialog (image selection for New Map) ─────────────────────────────
	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "Select Map Image"
	for ext in SUPPORTED_EXTENSIONS:
		_file_dialog.add_filter("*.%s" % ext)
	_file_dialog.file_selected.connect(_on_image_selected)
	add_child(_file_dialog)

	# ── Calibration dialog ───────────────────────────────────────────────────
	_cal_dialog = ConfirmationDialog.new()
	_cal_dialog.title = "Calibrate Grid"
	_cal_dialog.min_size = Vector2i(320, 0)

	var cal_vbox := VBoxContainer.new()
	cal_vbox.add_theme_constant_override("separation", 8)
	_cal_dialog_root = cal_vbox

	var feet_label := Label.new()
	feet_label.text = "Distance spanned (feet):"
	cal_vbox.add_child(feet_label)

	_feet_spin = SpinBox.new()
	_feet_spin.min_value = 5.0
	_feet_spin.max_value = 500.0
	_feet_spin.step = 5.0
	_feet_spin.value = 5.0
	_feet_spin.suffix = " ft"
	_feet_spin.focus_mode = Control.FOCUS_CLICK
	cal_vbox.add_child(_feet_spin)

	var offset_sep := HSeparator.new()
	cal_vbox.add_child(offset_sep)

	var offset_label := Label.new()
	offset_label.text = "Grid offset (px) — nudge to align grid to tiles:"
	cal_vbox.add_child(offset_label)

	var offset_grid := GridContainer.new()
	offset_grid.columns = 2
	offset_grid.add_theme_constant_override("h_separation", 12)
	offset_grid.add_theme_constant_override("v_separation", 4)

	var ox_label := Label.new(); ox_label.text = "Offset X:"
	offset_grid.add_child(ox_label)
	_offset_x_spin = SpinBox.new()
	_offset_x_spin.min_value = -4096.0
	_offset_x_spin.max_value = 4096.0
	_offset_x_spin.step = 1.0
	_offset_x_spin.value = 0.0
	_offset_x_spin.suffix = " px"
	_offset_x_spin.focus_mode = Control.FOCUS_CLICK
	offset_grid.add_child(_offset_x_spin)

	var oy_label := Label.new(); oy_label.text = "Offset Y:"
	offset_grid.add_child(oy_label)
	_offset_y_spin = SpinBox.new()
	_offset_y_spin.min_value = -4096.0
	_offset_y_spin.max_value = 4096.0
	_offset_y_spin.step = 1.0
	_offset_y_spin.value = 0.0
	_offset_y_spin.suffix = " px"
	_offset_y_spin.focus_mode = Control.FOCUS_CLICK
	offset_grid.add_child(_offset_y_spin)

	cal_vbox.add_child(offset_grid)

	_cal_dialog.add_child(cal_vbox)
	_cal_dialog.confirmed.connect(_on_calibration_confirmed)
	add_child(_cal_dialog)

	_cal_tool.confirm_dialog = _cal_dialog
	_cal_tool.calibration_done.connect(_on_calibration_done)
	_cal_tool.calibration_cancelled.connect(_on_calibration_cancelled)

	# ── Manual scale dialog ──────────────────────────────────────────────────
	_manual_scale_dialog = ConfirmationDialog.new()
	_manual_scale_dialog.title = "Set Scale Manually"
	_manual_scale_dialog.min_size = Vector2i(320, 0)

	var ms_vbox := VBoxContainer.new()
	ms_vbox.add_theme_constant_override("separation", 8)
	_manual_scale_dialog_root = ms_vbox

	var ms_grid := GridContainer.new()
	ms_grid.columns = 2
	ms_grid.add_theme_constant_override("h_separation", 16)
	ms_grid.add_theme_constant_override("v_separation", 6)

	var px_lbl := Label.new(); px_lbl.text = "Pixels per cell:"; ms_grid.add_child(px_lbl)
	_scale_px_spin = SpinBox.new()
	_scale_px_spin.min_value = 1.0
	_scale_px_spin.max_value = 4096.0
	_scale_px_spin.step = 1.0
	_scale_px_spin.value = 64.0
	_scale_px_spin.suffix = " px"
	_scale_px_spin.focus_mode = Control.FOCUS_CLICK
	ms_grid.add_child(_scale_px_spin)

	var ft_lbl := Label.new(); ft_lbl.text = "Cell size in feet:"; ms_grid.add_child(ft_lbl)
	_scale_ft_spin = SpinBox.new()
	_scale_ft_spin.min_value = 5.0
	_scale_ft_spin.max_value = 200.0
	_scale_ft_spin.step = 5.0
	_scale_ft_spin.value = 5.0 ## default: 5 ft per cell
	_scale_ft_spin.suffix = " ft"
	_scale_ft_spin.focus_mode = Control.FOCUS_CLICK
	ms_grid.add_child(_scale_ft_spin)

	ms_vbox.add_child(ms_grid)
	_manual_scale_dialog.add_child(ms_vbox)
	_manual_scale_dialog.confirmed.connect(_on_manual_scale_confirmed)
	add_child(_manual_scale_dialog)

	# ── Open Map dialog — select a .map bundle (directory package) ──────────────
	# Production: OPEN_FILE + *.map filter.  Info.plist UTType declares
	# com.apple.package + public.data so .map dirs appear as opaque files.
	# Dev: OPEN_ANY + *.map filter so .map dirs are selectable as folders.
	_open_map_dialog = FileDialog.new()
	_open_map_dialog.use_native_dialog = true
	_open_map_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_map_dialog.title = "Open Map Bundle"
	if OS.has_feature("standalone"):
		_open_map_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	else:
		_open_map_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_open_map_dialog.add_filter("*.map ; The Vault Map")
	_open_map_dialog.file_selected.connect(_on_map_bundle_selected)
	_open_map_dialog.dir_selected.connect(_on_map_bundle_selected)
	add_child(_open_map_dialog)

	# ── Save As dialog — native Save panel; filename stem becomes the map name ─
	_save_as_dialog = FileDialog.new()
	_save_as_dialog.use_native_dialog = true
	_save_as_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_as_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_as_dialog.title = "Save Map As"
	_save_as_dialog.add_filter("*.map ; The Vault Map")
	_save_as_dialog.file_selected.connect(_on_save_as_path_selected)
	add_child(_save_as_dialog)

	# ── Save Game As dialog — native Save panel for .sav bundles ────────────────
	_save_game_dialog = FileDialog.new()
	_save_game_dialog.use_native_dialog = true
	_save_game_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_game_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_game_dialog.title = "Save Game As"
	_save_game_dialog.add_filter("*.sav ; The Vault Save")
	_save_game_dialog.file_selected.connect(_on_save_game_path_selected)
	add_child(_save_game_dialog)

	# ── Load Game dialog — select a .sav bundle ────────────────────────────────
	# Production: OPEN_FILE + *.sav filter → .sav packages appear as opaque files.
	# Dev: OPEN_ANY + *.sav filter → .sav dirs are selectable as folders.
	_load_game_dialog = FileDialog.new()
	_load_game_dialog.use_native_dialog = true
	_load_game_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_load_game_dialog.title = "Load Game"
	if OS.has_feature("standalone"):
		_load_game_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	else:
		_load_game_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_load_game_dialog.add_filter("*.sav ; The Vault Save")
	_load_game_dialog.file_selected.connect(_on_load_game_path_selected)
	_load_game_dialog.dir_selected.connect(_on_load_game_path_selected)
	add_child(_load_game_dialog)

	# ── Standalone Grid Offset dialog (Edit > Set Grid Offset…)
	_offset_dialog = ConfirmationDialog.new()
	_offset_dialog.title = "Set Grid Offset"
	_offset_dialog.min_size = Vector2i(280, 0)

	var solo_vbox := VBoxContainer.new()
	solo_vbox.add_theme_constant_override("separation", 8)
	_offset_dialog_root = solo_vbox

	var solo_hint := Label.new()
	solo_hint.text = "Nudge the grid origin to align it to map tiles:"
	solo_vbox.add_child(solo_hint)

	var solo_grid := GridContainer.new()
	solo_grid.columns = 2
	solo_grid.add_theme_constant_override("h_separation", 12)
	solo_grid.add_theme_constant_override("v_separation", 4)

	var sox_lbl := Label.new(); sox_lbl.text = "Offset X:"
	solo_grid.add_child(sox_lbl)
	_solo_offset_x_spin = SpinBox.new()
	_solo_offset_x_spin.min_value = -4096.0
	_solo_offset_x_spin.max_value = 4096.0
	_solo_offset_x_spin.step = 1.0
	_solo_offset_x_spin.value = 0.0
	_solo_offset_x_spin.suffix = " px"
	_solo_offset_x_spin.focus_mode = Control.FOCUS_CLICK
	solo_grid.add_child(_solo_offset_x_spin)

	var soy_lbl := Label.new(); soy_lbl.text = "Offset Y:"
	solo_grid.add_child(soy_lbl)
	_solo_offset_y_spin = SpinBox.new()
	_solo_offset_y_spin.min_value = -4096.0
	_solo_offset_y_spin.max_value = 4096.0
	_solo_offset_y_spin.step = 1.0
	_solo_offset_y_spin.value = 0.0
	_solo_offset_y_spin.suffix = " px"
	_solo_offset_y_spin.focus_mode = Control.FOCUS_CLICK
	solo_grid.add_child(_solo_offset_y_spin)

	solo_vbox.add_child(solo_grid)
	_offset_dialog.add_child(solo_vbox)
	_offset_dialog.confirmed.connect(_on_offset_confirmed)
	add_child(_offset_dialog)

	# Phase 3 profile management UI
	_build_profiles_dialog()

	# Player viewport indicator — DM drags the green box on the main map
	# to reposition what players see. Hidden until a map is loaded.
	_map_view.set_viewport_indicator(Rect2())
	_map_view.viewport_indicator_moved.connect(_on_viewport_indicator_moved)
	_map_view.viewport_indicator_resized.connect(_on_viewport_indicator_resized)


# ---------------------------------------------------------------------------
# Player viewport helpers
# ---------------------------------------------------------------------------

func _on_display_peer_registered(_peer_id: int, viewport_size: Vector2) -> void:
	## A new Player display process just completed its handshake.
	## Keep the existing world-space viewport footprint stable by adjusting zoom
	## when the real player window size differs from our current assumption.
	_update_player_window_size_preserve_world(viewport_size)
	_update_viewport_indicator()
	_initial_sync_ack_pending[_peer_id] = true
	_initial_sync_attempt_by_peer[_peer_id] = 0
	_queue_initial_display_sync(_peer_id, 0.20)
	_send_player_bind_to_display(_peer_id)


## Send a player_bind message to a display peer, matching its handshake role
## to a profile ID. If the role matches no profile, no message is sent.
func _send_player_bind_to_display(peer_id: int) -> void:
	var nm := _network()
	if nm == null:
		return
	var role: String = nm.get_peer_role(peer_id)
	if role.is_empty():
		return
	var pm := _profile_service()
	if pm == null:
		return
	var profiles_arr: Array = pm.get_profiles()
	for profile in profiles_arr:
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		p.ensure_id()
		if p.id == role or p.player_name == role:
			nm.send_to_display(peer_id, {"msg": "player_bind", "player_id": p.id})
			return


## Re-send player_bind to every connected display peer (called after profile
## re-bind so displays pick up updated player assignments).
func _send_player_bind_to_all_displays() -> void:
	var nm := _network()
	if nm == null:
		return
	var peers: Array = nm.get_display_peer_ids()
	for peer_id_v in peers:
		_send_player_bind_to_display(int(peer_id_v))


func _queue_initial_display_sync(peer_id: int, delay_sec: float) -> void:
	if delay_sec <= 0.0:
		_send_initial_display_sync(peer_id)
		return
	var timer := get_tree().create_timer(delay_sec)
	timer.timeout.connect(func() -> void:
		_send_initial_display_sync(peer_id)
	)


func _send_initial_display_sync(peer_id: int) -> void:
	var map: MapData = _map()
	if map == null:
		return
	_update_viewport_indicator()
	var fog_snapshot := await _build_fog_state_snapshot(map)
	var attempt := int(_initial_sync_attempt_by_peer.get(peer_id, 0)) + 1
	_initial_sync_attempt_by_peer[peer_id] = attempt
	print("DMWindow: initial sync send attempt %d to peer %d" % [attempt, peer_id])
	_nm_send_map_to_display(peer_id, map, false, fog_snapshot)
	_broadcast_player_viewport()
	_broadcast_player_state()
	_broadcast_token_state()
	_broadcast_puzzle_notes_state()
	_broadcast_measurement_state()
	# Send current fog overlay state so the player matches the DM.
	var overlay_idx := _view_menu.get_item_index(28)
	_nm_broadcast_to_displays({"msg": "fog_overlay_toggle", "enabled": _view_menu.is_item_checked(overlay_idx)})
	# Send current flashlights-only state.
	var fl_enabled: bool = _map_view.fog_overlay.is_flashlights_only() if _map_view != null and _map_view.fog_overlay != null else false
	_nm_broadcast_to_displays({"msg": "flashlights_only_toggle", "enabled": fl_enabled})

	# Retry if no ack and peer is still connected.
	var retry_timer := get_tree().create_timer(1.0)
	retry_timer.timeout.connect(func() -> void:
		if not bool(_initial_sync_ack_pending.get(peer_id, false)):
			return
		if not _nm_is_display_peer_connected(peer_id):
			return
		var retries := int(_initial_sync_attempt_by_peer.get(peer_id, 1))
		if retries >= 3:
			push_warning("DMWindow: initial sync ack missing after %d attempts for peer %d" % [retries, peer_id])
			return
		_send_initial_display_sync(peer_id)
	)


func _on_display_sync_applied(peer_id: int, payload: Dictionary) -> void:
	if not bool(_initial_sync_ack_pending.get(peer_id, false)):
		return
	_initial_sync_ack_pending.erase(peer_id)
	print("DMWindow: initial sync ack from peer %d (stamp_bytes=%d stamp_hash=%d)" % [
		peer_id,
		int(payload.get("snapshot_bytes", -1)),
		int(payload.get("snapshot_hash", -1)),
	])


func _on_client_disconnected(peer_id: int) -> void:
	_initial_sync_ack_pending.erase(peer_id)
	_initial_sync_attempt_by_peer.erase(peer_id)


func _build_fog_state_snapshot(_map_data: MapData) -> Dictionary:
	var fog_state_png: PackedByteArray = PackedByteArray()
	if _map_view != null:
		fog_state_png = await _map_view.get_fog_state()
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if not fog_state_png.is_empty() and registry != null and registry.fog != null:
		registry.fog.sync_model_from_gpu(fog_state_png)
	var snapshot_hash := hash(fog_state_png)
	if DEBUG_FOG_SNAPSHOT:
		print("DMWindow: fog snapshot built (stamp_bytes=%d stamp_hash=%d)" % [
			fog_state_png.size(),
			snapshot_hash,
		])

	var snapshot := {
		"msg": "fog_state_snapshot",
		"snapshot_bytes": fog_state_png.size(),
		"snapshot_hash": snapshot_hash,
	}
	if not fog_state_png.is_empty():
		snapshot["fog_state_png_b64"] = Marshalls.raw_to_base64(fog_state_png)
	return snapshot


func _on_display_viewport_resized(_peer_id: int, viewport_size: Vector2) -> void:
	## Keep world-space view size stable on player fullscreen/resize by adjusting
	## camera zoom rather than letting the viewport rect jump in world units.
	_update_player_window_size_preserve_world(viewport_size)
	_update_viewport_indicator()
	_broadcast_player_viewport()


func _on_display_fullscreen_changed(_peer_id: int, is_fullscreen: bool) -> void:
	_player_is_fullscreen = is_fullscreen


func _on_viewport_indicator_moved(new_center: Vector2) -> void:
	## Called when the DM drags the green box on the DM map.
	var old_pos := _player_cam_pos
	_player_cam_pos = new_center
	_broadcast_dirty = true
	_broadcast_countdown = _BROADCAST_DEBOUNCE
	if old_pos != new_center:
		var registry_im := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry_im != null and registry_im.history != null:
			registry_im.history.push_command(HistoryCommand.create("Player view moved",
				func():
					_player_cam_pos = old_pos
					_update_viewport_indicator()
					_broadcast_player_viewport(),
				func():
					_player_cam_pos = new_center
					_update_viewport_indicator()
					_broadcast_player_viewport()))


func _on_viewport_indicator_resized(new_rect: Rect2) -> void:
	## Called when the DM drags a corner handle to resize the indicator.
	## Both paths derive zoom from the new world-space size so the player always
	## sees the area the indicator shows.  For windowed players the pixel window
	## size is also updated and a window_resize message is sent.
	var old_pos := _player_cam_pos
	var old_zoom := _player_cam_zoom
	var old_win_size := _player_window_size
	var world_size := new_rect.size
	if _player_is_fullscreen:
		# Lock to player window aspect ratio — the OS window cannot resize.
		world_size = _lock_to_aspect(new_rect.size, _player_window_size)

	_player_cam_pos = new_rect.get_center()
	# Zoom = pixels wide / world units wide so the indicator area fills the window.
	_player_cam_zoom = clampf(_player_window_size.x / maxf(world_size.x, 1.0), 0.1, 8.0)

	if not _player_is_fullscreen:
		# Derive new pixel window size from world_size × new zoom so it is
		# self-consistent and _update_player_window_size_preserve_world will
		# be a no-op when the player echoes viewport_resize back to us.
		var new_pixel_size := (world_size * _player_cam_zoom).max(Vector2(200.0, 200.0))
		_player_window_size = new_pixel_size
		_nm_broadcast_to_displays({
			"msg": "window_resize",
			"width": int(new_pixel_size.x),
			"height": int(new_pixel_size.y),
		})

	_update_viewport_indicator()
	# Broadcast immediately so the player zooms/pans in real time during the drag,
	# then also keep the dirty flag so a final clean broadcast fires on release.
	_broadcast_player_viewport()
	_broadcast_dirty = true
	_broadcast_countdown = _BROADCAST_DEBOUNCE
	# Push undo command capturing before/after state.
	var new_pos := _player_cam_pos
	var new_zoom := _player_cam_zoom
	var new_win_size := _player_window_size
	var is_fs := _player_is_fullscreen
	var registry_ir := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry_ir != null and registry_ir.history != null:
		registry_ir.history.push_command(HistoryCommand.create("Player view resized",
			func():
				_player_cam_pos = old_pos
				_player_cam_zoom = old_zoom
				if not is_fs:
					_player_window_size = old_win_size
					_nm_broadcast_to_displays({
						"msg": "window_resize",
						"width": int(old_win_size.x),
						"height": int(old_win_size.y),
					})
				_update_viewport_indicator()
				_broadcast_player_viewport(),
			func():
				_player_cam_pos = new_pos
				_player_cam_zoom = new_zoom
				if not is_fs:
					_player_window_size = new_win_size
					_nm_broadcast_to_displays({
						"msg": "window_resize",
						"width": int(new_win_size.x),
						"height": int(new_win_size.y),
					})
				_update_viewport_indicator()
				_broadcast_player_viewport()))


func _lock_to_aspect(size: Vector2, reference: Vector2) -> Vector2:
	## Returns size rescaled to match reference's aspect ratio, using X as primary.
	if reference.x <= 0.0 or reference.y <= 0.0:
		return size
	var aspect := reference.x / reference.y
	return Vector2(size.x, size.x / aspect)


func _change_player_zoom(delta_zoom: float) -> void:
	_player_cam_zoom = clampf(_player_cam_zoom + delta_zoom, 0.1, 8.0)
	_update_viewport_indicator()
	_broadcast_dirty = true
	_broadcast_countdown = _BROADCAST_DEBOUNCE


func _sync_player_to_dm_view() -> void:
	## Snap the player cam pos and zoom to match the DM's current view.
	if _map_view == null:
		return
	var state: Dictionary = _map_view.get_camera_state()
	_player_cam_pos = Vector2(state["position"]["x"], state["position"]["y"])
	_player_cam_zoom = float(state["zoom"])
	_update_viewport_indicator()
	_broadcast_player_viewport()


func _update_viewport_indicator() -> void:
	if _map_view == null:
		return
	var world_size := _player_window_size / _player_cam_zoom
	_map_view.set_viewport_indicator(Rect2(_player_cam_pos - world_size * 0.5, world_size), float(_player_cam_rotation))


func _update_player_window_size_preserve_world(new_size: Vector2) -> void:
	if new_size.x <= 0.0 or new_size.y <= 0.0:
		return
	var safe_zoom := maxf(_player_cam_zoom, 0.001)
	var prev_world_size := _player_window_size / safe_zoom
	_player_window_size = new_size
	if prev_world_size.x <= 0.0 or prev_world_size.y <= 0.0:
		return
	var zoom_x := _player_window_size.x / prev_world_size.x
	var zoom_y := _player_window_size.y / prev_world_size.y
	# One zoom value controls both axes; average keeps the same overall footprint.
	_player_cam_zoom = clampf((zoom_x + zoom_y) * 0.5, 0.1, 8.0)


func _broadcast_player_viewport() -> void:
	_nm_broadcast_to_displays({
		"msg": "camera_update",
		"position": {"x": _player_cam_pos.x, "y": _player_cam_pos.y},
		"zoom": _player_cam_zoom,
		"rotation": _player_cam_rotation,
	})


func _on_play_mode_pressed() -> void:
	if not _play_mode:
		_play_mode = true
		_launch_player_process()
	else:
		_play_mode = false
		if _palette != null and _palette.play_mode_btn != null:
			_palette.play_mode_btn.button_pressed = false


func _launch_player_process() -> void:
	var exe := OS.get_executable_path()
	var args: Array[String] = []
	if OS.has_feature("editor"):
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	args.append_array(["--", "--player-window"])
	var pid := OS.create_process(exe, args)
	if pid > 0:
		_set_status("Player window launched (pid=%d)" % pid)
	else:
		push_error("DMWindow: failed to launch Player window process")
		_play_mode = false
		if _palette != null and _palette.play_mode_btn != null:
			_palette.play_mode_btn.button_pressed = false


# ---------------------------------------------------------------------------
# Palette tool activation — drives MapView tool + context panel swap
# ---------------------------------------------------------------------------

func _on_palette_tool_activated(tool_key: String) -> void:
	if _map_view == null:
		return
	match tool_key:
		"select":
			_map_view.set_fog_tool(0, 64.0)
			_map_view._set_active_tool(_map_view.Tool.SELECT)
			_set_status("Tool: Select")
		"pan":
			_map_view.set_fog_tool(0, 64.0)
			_map_view._set_active_tool(_map_view.Tool.PAN)
			_set_status("Tool: Pan  (left-drag to pan)")
		"fog":
			var fog_id := 1
			if _palette != null and _palette.fog_tool_option != null:
				fog_id = _palette.fog_tool_option.get_item_id(_palette.fog_tool_option.selected)
			var brush_size := 64.0
			if _palette != null and _palette.fog_brush_spin != null:
				brush_size = _palette.fog_brush_spin.value
			_map_view._set_active_tool(_map_view.Tool.SELECT)
			_map_view.set_fog_tool(fog_id, brush_size)
			if _palette != null and _palette.fog_tool_option != null:
				_set_status("Fog tool: %s" % _palette.fog_tool_option.get_item_text(_palette.fog_tool_option.selected))
			else:
				_set_status("Fog tool active")
		"wall":
			_map_view.set_fog_tool(0, 64.0)
			# Wall mode is set via the wall_mode_changed signal from the palette stack button
		"spawn_point":
			_map_view.set_fog_tool(0, 64.0)
			_map_view._set_active_tool(_map_view.Tool.SPAWN_POINT)
			_refresh_spawn_profile_option()
			_set_status("Spawn Point tool — click to place, drag to move, right-click to remove")
		"token":
			_map_view.set_fog_tool(0, 64.0)
			_map_view._set_active_tool(_map_view.Tool.PLACE_TOKEN)
			_set_status("Token tool — click to place, click existing to select, right-click to edit")


func _on_palette_action_fired(action_key: String) -> void:
	match action_key:
		"dm_zoom_in":
			if _map_view:
				_map_view.zoom_in()
		"dm_zoom_out":
			if _map_view:
				_map_view.zoom_out()
		"dm_reset_view":
			if _map_view:
				_map_view._reset_camera()
		"pv_zoom_in":
			_change_player_zoom(0.15)
		"pv_zoom_out":
			_change_player_zoom(-0.15)
		"pv_sync":
			_sync_player_to_dm_view()
		"pv_rotate_ccw":
			_player_cam_rotation = (_player_cam_rotation - 90 + 360) % 360
			var m := _map()
			if m != null:
				m.camera_rotation = _player_cam_rotation
			_update_viewport_indicator()
			_broadcast_player_viewport()
		"pv_rotate_cw":
			_player_cam_rotation = (_player_cam_rotation + 90) % 360
			var m2 := _map()
			if m2 != null:
				m2.camera_rotation = _player_cam_rotation
			_update_viewport_indicator()
			_broadcast_player_viewport()
		"fog_reset":
			_show_fog_reset_confirm()


func _on_palette_fog_mode_changed(fog_id: int, brush_size: float) -> void:
	if _map_view == null:
		return
	_map_view.set_fog_tool(fog_id, brush_size)


func _on_palette_play_mode_toggled(active: bool) -> void:
	if active and not _play_mode:
		_play_mode = true
		_launch_player_process()
	elif not active:
		_play_mode = false


func _on_grid_submenu_id(id: int) -> void:
	_grid_type_selected = id
	_update_grid_submenu_checks()
	_on_grid_type_selected_by_id(id)


func _update_grid_submenu_checks() -> void:
	if _grid_submenu == null:
		return
	for i in range(_grid_submenu.item_count):
		_grid_submenu.set_item_checked(i, _grid_submenu.get_item_id(i) == _grid_type_selected)


# ---------------------------------------------------------------------------
# Phase 2: Palette undock / redock
# ---------------------------------------------------------------------------

func _on_undock_btn_pressed() -> void:
	if _palette_floating:
		_dock_palette()
	else:
		_undock_palette()


func _undock_palette() -> void:
	if _palette_floating or _palette == null:
		return
	_palette_floating = true
	if _palette.undock_btn:
		_palette.undock_btn.text = "⇱"
		_palette.undock_btn.tooltip_text = "Re-dock palette"

	_palette_window = Window.new()
	_palette_window.title = "Tools"
	_palette_window.popup_window = false
	_palette_window.exclusive = false
	add_child(_palette_window)

	var old_parent: Node = _palette.get_parent()
	if old_parent:
		old_parent.remove_child(_palette)
	_palette.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_palette.grow_vertical = Control.GROW_DIRECTION_BOTH
	_palette_window.add_child(_palette)
	_palette.set_anchors_preset(Control.PRESET_FULL_RECT)

	_palette_window.close_requested.connect(_dock_palette)
	var _pm := _get_ui_scale_mgr()
	if _pm != null:
		_pm.popup_fitted(_palette_window, 80.0, 500.0)
	else:
		_palette_window.popup_centered()


func _dock_palette() -> void:
	if not _palette_floating or _palette == null:
		return
	_palette_floating = false
	if _palette.undock_btn:
		_palette.undock_btn.text = "⇲"
		_palette.undock_btn.tooltip_text = "Detach / re-dock palette"

	if _palette_window:
		_palette_window.remove_child(_palette)

	# Re-anchor to left edge of _ui_layer.
	_palette.anchor_left = 0.0
	_palette.anchor_right = 0.0
	_palette.anchor_top = 0.0
	_palette.anchor_bottom = 1.0
	_palette.grow_horizontal = Control.GROW_DIRECTION_END
	_ui_layer.add_child(_palette)
	_apply_palette_size()

	if _palette_window:
		_palette_window.queue_free()
		_palette_window = null


# ---------------------------------------------------------------------------
# Player freeze panel — build, undock/redock, refresh
# ---------------------------------------------------------------------------

func _build_freeze_panel() -> void:
	# The panel lives directly in _ui_layer (screen coordinates), NOT inside
	# _ui_root. This keeps it immune to _ui_root.scale on HiDPI displays.
	_freeze_panel = PanelContainer.new()
	_freeze_panel.name = "FreezePanel"
	# Anchor right edge to screen right, full height.
	_freeze_panel.anchor_left = 1.0
	_freeze_panel.anchor_right = 1.0
	_freeze_panel.anchor_top = 0.0
	_freeze_panel.anchor_bottom = 1.0
	_freeze_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# offset_left is set (negative panel width in screen px) by _apply_ui_scale()
	_freeze_panel.offset_left = -200.0
	_freeze_panel.offset_right = 0.0
	_ui_layer.add_child(_freeze_panel)

	var fp_margin := MarginContainer.new()
	fp_margin.add_theme_constant_override("margin_left", 4)
	fp_margin.add_theme_constant_override("margin_right", 4)
	fp_margin.add_theme_constant_override("margin_top", 4)
	fp_margin.add_theme_constant_override("margin_bottom", 4)
	_freeze_panel.add_child(fp_margin)

	# _fp_vbox is the scale root — _apply_ui_scale() sets _fp_vbox.scale = Vector2(scale, scale)
	# exactly as it does for _ui_root, so all child sizes are specified in base (1x) units.
	_fp_vbox = VBoxContainer.new()
	_fp_vbox.add_theme_constant_override("separation", 2)
	fp_margin.add_child(_fp_vbox)

	_freeze_undock_btn = Button.new()
	_freeze_undock_btn.text = "⇲"
	_freeze_undock_btn.focus_mode = Control.FOCUS_NONE
	_freeze_undock_btn.tooltip_text = "Detach / re-dock freeze panel"
	_freeze_undock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_freeze_undock_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_freeze_undock_btn.custom_minimum_size = Vector2(0, roundi(22.0 * _ui_scale()))
	_freeze_undock_btn.add_theme_font_size_override("font_size", roundi(14.0 * _ui_scale()))
	_freeze_undock_btn.pressed.connect(_on_freeze_undock_btn_pressed)
	_fp_vbox.add_child(_freeze_undock_btn)

	_fp_vbox.add_child(HSeparator.new())

	_freeze_panel_title = Label.new()
	_freeze_panel_title.text = "Players"
	_freeze_panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_freeze_panel_title.add_theme_font_size_override("font_size", roundi(15.0 * _ui_scale()))
	_fp_vbox.add_child(_freeze_panel_title)

	_fp_vbox.add_child(HSeparator.new())

	_freeze_master_btn = Button.new()
	_freeze_master_btn.text = "Freeze All"
	_freeze_master_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_freeze_master_btn.custom_minimum_size = Vector2(0, roundi(30.0 * _ui_scale()))
	_freeze_master_btn.add_theme_font_size_override("font_size", roundi(13.0 * _ui_scale()))
	_freeze_master_btn.pressed.connect(_on_master_freeze_pressed)
	_fp_vbox.add_child(_freeze_master_btn)

	_fp_vbox.add_child(HSeparator.new())

	var fp_scroll := ScrollContainer.new()
	fp_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fp_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_fp_vbox.add_child(fp_scroll)

	_freeze_rows = VBoxContainer.new()
	_freeze_rows.add_theme_constant_override("separation", 4)
	_freeze_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fp_scroll.add_child(_freeze_rows)


func _refresh_freeze_panel() -> void:
	if _freeze_rows == null:
		return
	# Clear existing rows
	for child in _freeze_rows.get_children():
		child.queue_free()
	_freeze_row_buttons.clear()
	_freeze_light_buttons.clear()

	var pm := _profile_service()
	if pm == null:
		return
	var profiles_arr: Array = pm.get_profiles()
	var gs := _game_state()

	for raw_profile in profiles_arr:
		if not raw_profile is PlayerProfile:
			continue
		var p := raw_profile as PlayerProfile
		var locked: bool = gs.is_locked(p.id) if gs != null else false

		var row := HBoxContainer.new()
		row.name = "FreezeRow_" + p.id
		row.add_theme_constant_override("separation", 6)

		# Swatch is NOT inside the status container so its color is never tinted.
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(roundi(16.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.color = p.indicator_color
		row.add_child(swatch)

		# Inner container receives the green/red tint — swatch is excluded.
		var status_box := HBoxContainer.new()
		status_box.name = "StatusBox"
		status_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_box.add_theme_constant_override("separation", 4)
		if not locked:
			status_box.modulate = Color(0.6, 1.0, 0.6)
		elif _autopause_locked_ids.has(p.id):
			status_box.modulate = Color(1.0, 0.85, 0.0)
		else:
			status_box.modulate = Color(1.0, 0.6, 0.6)
		row.add_child(status_box)

		var name_lbl := Label.new()
		name_lbl.text = p.player_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.add_theme_font_size_override("font_size", roundi(15.0 * _ui_scale()))
		status_box.add_child(name_lbl)

		var chk := CheckButton.new()
		chk.toggle_mode = true
		chk.button_pressed = not locked # pressed = can move (green)
		chk.focus_mode = Control.FOCUS_NONE
		var icon_px := roundi(32.0 * _ui_scale())
		chk.custom_minimum_size = Vector2(icon_px * 2.4, icon_px * 1.3)
		chk.tooltip_text = "Toggle: green = can move, red = paused"
		# Scale the toggle icons to match the desired display size once in scene tree.
		chk.ready.connect(func() -> void:
			for iname: String in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
				var orig: Texture2D = chk.get_theme_icon(iname, "CheckButton")
				if orig == null:
					continue
				var img: Image = orig.get_image()
				if img == null:
					continue
				var scaled: Image = img.duplicate() as Image
				if scaled == null:
					continue
				scaled.resize(icon_px, icon_px, Image.INTERPOLATE_LANCZOS)
				chk.add_theme_icon_override(iname, ImageTexture.create_from_image(scaled))
		)
		# Capture player id by value for the lambda
		var pid := p.id
		chk.toggled.connect(func(on: bool) -> void: _on_player_freeze_toggled(pid, on))
		status_box.add_child(chk)

		var light_off: bool = gs.is_light_off(p.id) if gs != null else false
		var light_btn := Button.new()
		light_btn.text = "🚫" if light_off else "🔦"
		light_btn.toggle_mode = true
		light_btn.button_pressed = light_off
		light_btn.focus_mode = Control.FOCUS_NONE
		light_btn.tooltip_text = "Toggle player vision light on/off"
		light_btn.custom_minimum_size = Vector2(roundi(28.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
		light_btn.add_theme_font_size_override("font_size", roundi(12.0 * _ui_scale()))
		var lpid := p.id
		light_btn.toggled.connect(func(off: bool) -> void: _on_player_light_toggled(lpid, off))
		status_box.add_child(light_btn)

		_freeze_rows.add_child(row)
		_freeze_row_buttons[p.id] = chk
		_freeze_light_buttons[p.id] = light_btn

	_update_master_toggle()


func _on_player_freeze_toggled(player_id: String, toggled_on: bool) -> void:
	var gs := _game_state()
	if gs == null:
		return
	if toggled_on:
		gs.unlock_player(player_id)
		_autopause_locked_ids.erase(player_id)
	else:
		gs.lock_player(player_id)
	_broadcast_player_state()

	var row := _freeze_rows.get_node_or_null("FreezeRow_" + player_id) as HBoxContainer
	if row != null:
		var sb := row.get_node_or_null("StatusBox") as HBoxContainer
		if sb != null:
			sb.modulate = Color(0.6, 1.0, 0.6) if toggled_on else Color(1.0, 0.6, 0.6)
	_update_master_toggle()


func _on_player_light_toggled(player_id: String, off: bool) -> void:
	var gs := _game_state()
	if gs == null:
		return
	gs.set_light_off(player_id, off)
	# Update button text
	var btn: Variant = _freeze_light_buttons.get(player_id, null)
	if btn is Button:
		(btn as Button).text = "🚫" if off else "🔦"
	# Suppress on DM-side token
	if _backend != null:
		var dm_tokens: Dictionary = _backend.get_dm_token_nodes()
		var token: Variant = dm_tokens.get(player_id, null)
		if token is PlayerSprite:
			(token as PlayerSprite).set_light_suppressed(off)
	_broadcast_player_state()


func _on_player_lock_changed_external(player_id: Variant, locked: bool) -> void:
	var pid := str(player_id)
	if not _freeze_row_buttons.has(pid):
		return
	var chk := _freeze_row_buttons[pid] as CheckButton
	if chk == null:
		return
	chk.set_block_signals(true)
	chk.button_pressed = not locked
	chk.set_block_signals(false)
	var row := _freeze_rows.get_node_or_null("FreezeRow_" + pid) as HBoxContainer
	if row != null:
		var sb := row.get_node_or_null("StatusBox") as HBoxContainer
		if sb != null:
			if not locked:
				sb.modulate = Color(0.6, 1.0, 0.6)
			elif _autopause_locked_ids.has(pid):
				sb.modulate = Color(1.0, 0.85, 0.0)
			else:
				sb.modulate = Color(1.0, 0.6, 0.6)
	_update_master_toggle()


func _on_master_freeze_pressed() -> void:
	var gs := _game_state()
	var pm := _profile_service()
	if gs == null or pm == null:
		return
	# If all are currently locked → free all; otherwise lock everyone
	var all_locked := true
	for raw in pm.get_profiles():
		if raw is PlayerProfile:
			var p := raw as PlayerProfile
			if not gs.is_locked(p.id):
				all_locked = false
				break
	for raw in pm.get_profiles():
		if raw is PlayerProfile:
			var p := raw as PlayerProfile
			if all_locked:
				gs.unlock_player(p.id)
			else:
				gs.lock_player(p.id)
	_broadcast_player_state()
	_refresh_freeze_panel()


func _update_master_toggle() -> void:
	if _freeze_master_btn == null:
		return
	var gs := _game_state()
	var pm := _profile_service()
	if gs == null or pm == null:
		_freeze_master_btn.text = "Freeze All"
		return
	var all_locked := true
	var any_profile := false
	for raw in pm.get_profiles():
		if raw is PlayerProfile:
			any_profile = true
			var p := raw as PlayerProfile
			if not gs.is_locked(p.id):
				all_locked = false
				break
	_freeze_master_btn.text = "Free All" if (any_profile and all_locked) else "Freeze All"


func _on_freeze_undock_btn_pressed() -> void:
	if _freeze_panel_floating:
		_dock_freeze_panel()
	else:
		_undock_freeze_panel()


func _undock_freeze_panel() -> void:
	if _freeze_panel_floating or _freeze_panel == null:
		return
	_freeze_panel_floating = true
	if _freeze_undock_btn:
		_freeze_undock_btn.text = "⇱"
		_freeze_undock_btn.tooltip_text = "Re-dock freeze panel"

	# Hide title — the Window titlebar already shows "Players"
	if _freeze_panel_title != null:
		_freeze_panel_title.hide()

	_freeze_panel_window = Window.new()
	_freeze_panel_window.title = "Players"
	_freeze_panel_window.popup_window = false
	_freeze_panel_window.exclusive = false
	add_child(_freeze_panel_window)

	var old_parent := _freeze_panel.get_parent()
	if old_parent:
		old_parent.remove_child(_freeze_panel)
	_freeze_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_freeze_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_freeze_panel_window.add_child(_freeze_panel)
	_freeze_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Clear docked-mode offsets so the panel fills the window correctly.
	_freeze_panel.offset_left = 0.0
	_freeze_panel.offset_right = 0.0
	_freeze_panel.offset_top = 0.0
	_freeze_panel.offset_bottom = 0.0

	_freeze_panel_window.close_requested.connect(_dock_freeze_panel)
	var _fm := _get_ui_scale_mgr()
	if _fm != null:
		_fm.popup_fitted(_freeze_panel_window, 220.0, 400.0)
	else:
		_freeze_panel_window.popup_centered()

	if _view_menu != null:
		_view_menu.set_item_checked(1, true)


func _dock_freeze_panel() -> void:
	if not _freeze_panel_floating or _freeze_panel == null:
		return
	_freeze_panel_floating = false
	if _freeze_undock_btn:
		_freeze_undock_btn.text = "⇲"
		_freeze_undock_btn.tooltip_text = "Detach / re-dock freeze panel"

	if _freeze_panel_window:
		_freeze_panel_window.remove_child(_freeze_panel)

	# Re-anchor to right edge of screen in the CanvasLayer
	_freeze_panel.anchor_left = 1.0
	_freeze_panel.anchor_right = 1.0
	_freeze_panel.anchor_top = 0.0
	_freeze_panel.anchor_bottom = 1.0
	_freeze_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	if _ui_layer != null:
		_ui_layer.add_child(_freeze_panel)
		_apply_freeze_panel_size()

	# Restore title visibility now we're docked again
	if _freeze_panel_title != null:
		_freeze_panel_title.show()

	if _freeze_panel_window:
		_freeze_panel_window.queue_free()
		_freeze_panel_window = null

	if _view_menu != null:
		_view_menu.set_item_checked(1, true)


# ---------------------------------------------------------------------------
# Menu handlers
# ---------------------------------------------------------------------------

func _on_file_menu_id(id: int) -> void:
	match id:
		0: _on_new_map_pressed()
		1: _on_open_map_pressed()
		2: _on_save_map_pressed()
		3: _on_save_map_as_pressed()
		4: _on_save_game_pressed()
		5: _on_save_game_as_pressed()
		6: _on_load_game_pressed()
		9: get_tree().quit()


func _on_edit_menu_id(id: int) -> void:
	match id:
		14: # Undo
			var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if registry != null and registry.history != null:
				var desc := registry.history.get_undo_description()
				if registry.history.undo():
					_set_status("Undo: %s" % desc)
		15: # Redo
			var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if registry != null and registry.history != null:
				var desc := registry.history.get_redo_description()
				if registry.history.redo():
					_set_status("Redo: %s" % desc)
		10: _on_calibrate_pressed()
		11: _on_manual_scale_pressed()
		12: _on_set_offset_pressed()
		13: _open_profiles_editor()


func _on_session_menu_id(id: int) -> void:
	match id:
		30: _show_share_player_link()


func _on_view_menu_id(id: int) -> void:
	match id:
		20: # Toggle toolbar
			if _palette != null:
				_palette.visible = !_palette.visible
				_view_menu.set_item_checked(0, _palette.visible)
		25: # Toggle player freeze panel
			if _freeze_panel != null:
				_freeze_panel.visible = !_freeze_panel.visible
				_view_menu.set_item_checked(1, _freeze_panel.visible)
		21: # Toggle grid overlay
			if _map_view:
				var go: Node2D = _map_view.grid_overlay
				go.visible = !go.visible
				_view_menu.set_item_checked(2, go.visible)
		22: # Reset DM view
			if _map_view:
				_map_view._reset_camera()
		24: # Manual fog resync
			_manual_fog_sync_now()
		27: # Reset fog to fully hidden
			_show_fog_reset_confirm()
		28: # Toggle fog overlay effect
			var idx := _view_menu.get_item_index(28)
			var on := not _view_menu.is_item_checked(idx)
			_view_menu.set_item_checked(idx, on)
			if _map_view:
				_map_view.set_fog_overlay_enabled(on)
			_nm_broadcast_to_displays({"msg": "fog_overlay_toggle", "enabled": on})
		26: # Open measurement tools panel
			_open_measure_panel()
		23: # Launch player display process
			_launch_player_process()


# ---------------------------------------------------------------------------
# Tool toggle (Select = 0, Pan = 1)
# ---------------------------------------------------------------------------

func _on_tool_changed(tool: int) -> void:
	if _map_view:
		match tool:
			0:
				_map_view._set_active_tool(_map_view.Tool.SELECT)
				_set_status("Tool: Select")
			1:
				_map_view._set_active_tool(_map_view.Tool.PAN)
				_set_status("Tool: Pan  (left-drag to pan)")


func _on_fog_tool_selected(_index: int) -> void:
	# Legacy handler — fog mode changes are now routed via _on_palette_fog_mode_changed.
	pass


func _on_fog_brush_size_changed(_value: float) -> void:
	# Legacy handler — fog brush changes are now routed via _on_palette_fog_mode_changed.
	pass


func _on_dm_fog_visible_toggled(enabled: bool) -> void:
	if _map_view == null:
		return
	_map_view.set_dm_fog_visible(enabled)


func _on_flashlights_only_toggled(enabled: bool) -> void:
	if _map_view == null:
		return
	_map_view.set_flashlights_only(enabled)
	_nm_broadcast_to_displays({"msg": "flashlights_only_toggle", "enabled": enabled})


func _on_wall_rect_toggled(enabled: bool) -> void:
	if _map_view == null:
		return
	_map_view.set_wall_rect_mode(enabled)
	if enabled:
		_set_status("Wall Rect: drag on map to place wall occluder rectangle")
	else:
		_set_status("Wall Rect: off")


func _on_delete_wall_pressed() -> void:
	if _map_view == null:
		return
	if _map_view.delete_selected_wall():
		_set_status("Wall deleted.")
	else:
		_set_status("No wall selected. Use Select tool and click a wall first.")


# ---------------------------------------------------------------------------
# Grid type handler
# ---------------------------------------------------------------------------

func _on_grid_type_selected(_index: int) -> void:
	# Legacy handler kept for compatibility — forwards to ID-based handler.
	pass


func _on_grid_type_selected_by_id(grid_id: int) -> void:
	var map: MapData = _map()
	if map == null:
		return
	map.grid_type = grid_id
	_grid_type_selected = grid_id
	_map_view.grid_overlay.apply_map_data(map)
	_nm_broadcast_map_update(map)
	_broadcast_player_state()
	var label := "Square"
	match grid_id:
		MapData.GridType.HEX_FLAT:
			label = "Hex Flat-top"
		MapData.GridType.HEX_POINTY:
			label = "Hex Pointy-top"
	_set_status("Grid: %s" % label)


# ---------------------------------------------------------------------------
# Calibration workflow
# ---------------------------------------------------------------------------

func _on_calibrate_pressed() -> void:
	var map: MapData = _map()
	if map == null:
		_set_status("Load a map first.")
		return
	# Ensure we're in Select mode during calibration (no accidental drag pan)
	_map_view._set_active_tool(_map_view.Tool.SELECT)
	if _palette != null and _palette.select_btn != null:
		_palette.select_btn.button_pressed = true
	# Pre-fill offset spinboxes from current map data
	_offset_x_spin.value = map.grid_offset.x
	_offset_y_spin.value = map.grid_offset.y
	_cal_tool.activate(map)
	_set_status("Calibrate: click-drag a line on the map, then release.")


func _on_calibration_confirmed() -> void:
	_cal_tool.apply_measurement(_feet_spin.value)


func _on_calibration_cancelled() -> void:
	_set_status("Calibration cancelled.")


func _on_calibration_done(map: MapData) -> void:
	# Apply offset from the dialog spinboxes (user-entered or retained from before).
	map.grid_offset = Vector2(_offset_x_spin.value, _offset_y_spin.value)
	_map_view.grid_overlay.apply_map_data(map)
	_nm_broadcast_map_update(map)
	_broadcast_player_state()
	var detail := ("cell_px=%.1f" % map.cell_px) if map.grid_type == MapData.GridType.SQUARE else ("hex_size=%.1f" % map.hex_size)
	_set_status("Calibrated: %s  offset=(%.0f, %.0f)" % [detail, map.grid_offset.x, map.grid_offset.y])


# ---------------------------------------------------------------------------
# Manual scale handlers
# ---------------------------------------------------------------------------

func _on_manual_scale_pressed() -> void:
	var map: MapData = _map()
	if map == null:
		_set_status("Load a map first.")
		return
	# Pre-populate spins from current map data
	match map.grid_type:
		MapData.GridType.SQUARE:
			_scale_px_spin.value = map.cell_px
		_:
			_scale_px_spin.value = map.hex_size * 2.0
	_scale_ft_spin.value = 5.0
	_manual_scale_dialog.popup_centered()


func _on_manual_scale_confirmed() -> void:
	var map: MapData = _map()
	if map == null:
		return
	var px_per_cell := _scale_px_spin.value
	var ft_per_cell := _scale_ft_spin.value
	# Normalise to pixels-per-5ft cell and keep both fields in sync so
	# switching grid type preserves the calibrated scale.
	var cell_px := px_per_cell * (5.0 / ft_per_cell)
	map.cell_px = cell_px
	map.hex_size = cell_px * 0.5
	_map_view.grid_overlay.apply_map_data(map)
	_nm_broadcast_map_update(map)
	_broadcast_player_state()
	_set_status("Scale set: %.1f px = %.0f ft" % [px_per_cell, ft_per_cell])


# ---------------------------------------------------------------------------
# Standalone Grid Offset handler (Edit > Set Grid Offset…)
# ---------------------------------------------------------------------------

func _on_set_offset_pressed() -> void:
	var map: MapData = _map()
	if map == null:
		_set_status("Load a map first.")
		return
	_solo_offset_x_spin.value = map.grid_offset.x
	_solo_offset_y_spin.value = map.grid_offset.y
	_offset_dialog.popup_centered()


func _on_offset_confirmed() -> void:
	var map: MapData = _map()
	if map == null:
		return
	map.grid_offset = Vector2(_solo_offset_x_spin.value, _solo_offset_y_spin.value)
	_map_view.grid_overlay.apply_map_data(map)
	_nm_broadcast_map_update(map)
	_broadcast_player_state()
	_set_status("Grid offset: (%.0f, %.0f)" % [map.grid_offset.x, map.grid_offset.y])


# ---------------------------------------------------------------------------
# Phase 3: Player profile editor
# ---------------------------------------------------------------------------

func _build_profiles_dialog() -> void:
	_profiles_dialog = AcceptDialog.new()
	_profiles_dialog.title = "Player Profiles"
	_profiles_dialog.ok_button_text = "Close"
	## min_size intentionally omitted — popup_centered_ratio handles sizing
	add_child(_profiles_dialog)

	var root := HSplitContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var _sm := _get_ui_scale_mgr()
	var _ps: float = _sm.get_scale() if _sm != null else 1.0
	root.split_offset = roundi(280.0 * _ps)
	_profiles_dialog.add_child(root)
	_profiles_root = root

	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(roundi(260.0 * _ps), 0)
	root.add_child(left_panel)

	var left_title := Label.new()
	left_title.text = "Profiles"
	if _sm != null:
		left_title.add_theme_font_size_override("font_size", _sm.scaled(15.0))
	left_panel.add_child(left_title)

	_profiles_list = ItemList.new()
	_profiles_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _sm != null:
		_profiles_list.add_theme_font_size_override("font_size", _sm.scaled(14.0))
	_profiles_list.item_selected.connect(_on_profile_selected)
	left_panel.add_child(_profiles_list)

	var list_btn_row := HBoxContainer.new()
	left_panel.add_child(list_btn_row)

	_profile_add_btn = Button.new()
	_profile_add_btn.text = "New"
	if _sm != null:
		_sm.scale_button(_profile_add_btn)
	_profile_add_btn.pressed.connect(_on_profile_add_pressed)
	list_btn_row.add_child(_profile_add_btn)

	_profile_delete_btn = Button.new()
	_profile_delete_btn.text = "Remove"
	_profile_delete_btn.disabled = true
	if _sm != null:
		_sm.scale_button(_profile_delete_btn)
	_profile_delete_btn.pressed.connect(_on_profile_delete_pressed)
	list_btn_row.add_child(_profile_delete_btn)

	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(right_scroll)

	var right_panel := VBoxContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_constant_override("separation", 10)
	right_scroll.add_child(right_panel)

	_profile_id_label = Label.new()
	_profile_id_label.text = "ID: —"
	right_panel.add_child(_profile_id_label)

	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 14)
	form.add_theme_constant_override("v_separation", 8)
	right_panel.add_child(form)

	var name_lbl := Label.new(); name_lbl.text = "Name:"; form.add_child(name_lbl)
	_profile_name_edit = LineEdit.new()
	form.add_child(_profile_name_edit)

	var speed_lbl := Label.new(); speed_lbl.text = "Base Speed (ft):"; form.add_child(speed_lbl)
	_profile_speed_spin = SpinBox.new()
	_profile_speed_spin.min_value = 5
	_profile_speed_spin.max_value = 120
	_profile_speed_spin.step = 5
	_profile_speed_spin.value = 30
	form.add_child(_profile_speed_spin)

	var vision_lbl := Label.new(); vision_lbl.text = "Vision Type:"; form.add_child(vision_lbl)
	_profile_vision_option = OptionButton.new()
	_profile_vision_option.add_item("Normal", PlayerProfile.VisionType.NORMAL)
	_profile_vision_option.add_item("Darkvision", PlayerProfile.VisionType.DARKVISION)
	_profile_vision_option.item_selected.connect(_on_profile_vision_selected)
	form.add_child(_profile_vision_option)

	var dv_lbl := Label.new(); dv_lbl.text = "Darkvision Range (ft):"; form.add_child(dv_lbl)
	_profile_darkvision_spin = SpinBox.new()
	_profile_darkvision_spin.min_value = 5
	_profile_darkvision_spin.max_value = 240
	_profile_darkvision_spin.step = 5
	_profile_darkvision_spin.value = 60
	form.add_child(_profile_darkvision_spin)

	var pm_lbl := Label.new(); pm_lbl.text = "Perception Mod:"; form.add_child(pm_lbl)
	_profile_perception_spin = SpinBox.new()
	_profile_perception_spin.min_value = -10
	_profile_perception_spin.max_value = 20
	_profile_perception_spin.step = 1
	_profile_perception_spin.value = 0
	_profile_perception_spin.value_changed.connect(_on_profile_perception_changed)
	form.add_child(_profile_perception_spin)

	var pp_lbl := Label.new(); pp_lbl.text = "Passive Perception:"; form.add_child(pp_lbl)
	_profile_passive_label = Label.new()
	_profile_passive_label.text = "10"
	form.add_child(_profile_passive_label)

	var dash_lbl := Label.new(); dash_lbl.text = "Dashing:"; form.add_child(dash_lbl)
	_profile_dash_check = CheckBox.new()
	_profile_dash_check.text = "Dashing (Speed ×2, Perception ÷2 while active)"
	_profile_dash_check.button_pressed = false
	form.add_child(_profile_dash_check)

	var it_lbl := Label.new(); it_lbl.text = "Input Type:"; form.add_child(it_lbl)
	_profile_input_type_option = OptionButton.new()
	_profile_input_type_option.add_item("None", PlayerProfile.InputType.NONE)
	_profile_input_type_option.add_item("Gamepad", PlayerProfile.InputType.GAMEPAD)
	_profile_input_type_option.add_item("WebSocket", PlayerProfile.InputType.WEBSOCKET)
	form.add_child(_profile_input_type_option)

	var iid_lbl := Label.new(); iid_lbl.text = "Input ID:"; form.add_child(iid_lbl)
	_profile_input_id_edit = LineEdit.new()
	_profile_input_id_edit.placeholder_text = "Gamepad device id or WS peer id"
	form.add_child(_profile_input_id_edit)

	# Table orientation field
	var orient_lbl := Label.new(); orient_lbl.text = "Table Orientation:"; form.add_child(orient_lbl)
	_profile_orientation_spin = SpinBox.new()
	_profile_orientation_spin.min_value = 0
	_profile_orientation_spin.max_value = 359
	_profile_orientation_spin.step = 1
	# ...existing code...
	_profile_orientation_spin.value = 0
	_profile_orientation_spin.suffix = "°"
	form.add_child(_profile_orientation_spin)

	var color_lbl := Label.new(); color_lbl.text = "Indicator Color:"; form.add_child(color_lbl)
	_profile_color_btn = ColorPickerButton.new()
	_profile_color_btn.color = Color.WHITE
	_profile_color_btn.custom_minimum_size = Vector2(roundi(80.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	# Configure the inner ColorPicker for a cleaner, system-like appearance:
	# disable alpha (not needed for token colors) and use the HSV colour wheel.
	_profile_color_btn.ready.connect(func() -> void:
		var cp := _profile_color_btn.get_picker() as ColorPicker
		if cp != null:
			cp.edit_alpha = false
			cp.picker_shape = ColorPicker.SHAPE_VHS_CIRCLE
	)
	form.add_child(_profile_color_btn)

	var bind_sep := HSeparator.new()
	right_panel.add_child(bind_sep)

	var bind_row := GridContainer.new()
	bind_row.columns = 3
	bind_row.add_theme_constant_override("h_separation", 10)
	bind_row.add_theme_constant_override("v_separation", 6)
	right_panel.add_child(bind_row)

	var gp_lbl := Label.new(); gp_lbl.text = "Connected gamepads:"; bind_row.add_child(gp_lbl)
	_profile_gamepad_option = OptionButton.new()
	bind_row.add_child(_profile_gamepad_option)
	var gp_btn := Button.new()
	gp_btn.text = "Use"
	gp_btn.pressed.connect(_on_bind_use_gamepad_pressed)
	bind_row.add_child(gp_btn)

	var ws_lbl := Label.new(); ws_lbl.text = "Connected WS peers:"; bind_row.add_child(ws_lbl)
	_profile_ws_option = OptionButton.new()
	bind_row.add_child(_profile_ws_option)
	var ws_btn := Button.new()
	ws_btn.text = "Use"
	ws_btn.pressed.connect(_on_bind_use_ws_pressed)
	bind_row.add_child(ws_btn)

	var extras_lbl := Label.new()
	extras_lbl.text = "Extras (JSON object):"
	right_panel.add_child(extras_lbl)

	_profile_extras_edit = TextEdit.new()
	_profile_extras_edit.custom_minimum_size = Vector2(0, 160)
	_profile_extras_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_profile_extras_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	right_panel.add_child(_profile_extras_edit)

	var action_row := HBoxContainer.new()
	right_panel.add_child(action_row)

	_profile_add_btn_alt = Button.new()
	_profile_add_btn_alt.text = "New"
	_profile_add_btn_alt.pressed.connect(_on_profile_add_pressed)
	action_row.add_child(_profile_add_btn_alt)

	_profile_delete_btn_alt = Button.new()
	_profile_delete_btn_alt.text = "Remove"
	_profile_delete_btn_alt.disabled = true
	_profile_delete_btn_alt.pressed.connect(_on_profile_delete_pressed)
	action_row.add_child(_profile_delete_btn_alt)

	_profile_cancel_new_btn = Button.new()
	_profile_cancel_new_btn.text = "Cancel New"
	_profile_cancel_new_btn.visible = false
	_profile_cancel_new_btn.pressed.connect(_on_profile_cancel_new_pressed)
	action_row.add_child(_profile_cancel_new_btn)

	_profile_save_btn = Button.new()
	_profile_save_btn.text = "Save Profile"
	_profile_save_btn.pressed.connect(_on_profile_save_pressed)
	action_row.add_child(_profile_save_btn)

	var import_btn := Button.new()
	import_btn.text = "Import JSON"
	import_btn.pressed.connect(_on_profile_import_pressed)
	action_row.add_child(import_btn)

	var export_btn := Button.new()
	export_btn.text = "Export JSON"
	export_btn.pressed.connect(_on_profile_export_pressed)
	action_row.add_child(export_btn)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh Inputs"
	refresh_btn.pressed.connect(_refresh_available_inputs)
	action_row.add_child(refresh_btn)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(fill)

	var hint := Label.new()
	hint.text = "Tip: Unknown keys in extras are preserved across save/load."
	action_row.add_child(hint)

	_profiles_import_dialog = FileDialog.new()
	_profiles_import_dialog.use_native_dialog = true
	_profiles_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_profiles_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_profiles_import_dialog.title = "Import Player Profiles JSON"
	_profiles_import_dialog.add_filter("*.json ; JSON")
	_profiles_import_dialog.file_selected.connect(_on_profiles_import_path_selected)
	add_child(_profiles_import_dialog)

	_profiles_export_dialog = FileDialog.new()
	_profiles_export_dialog.use_native_dialog = true
	_profiles_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_profiles_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_profiles_export_dialog.title = "Export Player Profiles JSON"
	_profiles_export_dialog.add_filter("*.json ; JSON")
	_profiles_export_dialog.file_selected.connect(_on_profiles_export_path_selected)
	add_child(_profiles_export_dialog)


func _open_profiles_editor() -> void:
	_refresh_available_inputs()
	_refresh_profiles_list()
	_update_profile_action_state()
	_apply_ui_scale()
	_profiles_dialog.popup_centered_ratio(0.9)


func _refresh_profiles_list() -> void:
	if _profiles_list == null:
		return
	_profiles_list.clear()
	var pm := _profile_service()
	var profiles_arr: Array = pm.get_profiles() if pm != null else []
	for profile in profiles_arr:
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		_profiles_list.add_item("%s (%s)" % [p.player_name, p.id.left(8)])
	if profiles_arr.is_empty():
		_profile_selected_index = -1
		_clear_profile_form()
		_profile_is_new_draft = false
		_update_profile_action_state()
		return

	if _profile_is_new_draft:
		_profiles_list.deselect_all()
		_update_profile_action_state()
		return

	if _profile_selected_index < 0 or _profile_selected_index >= _profiles_list.item_count:
		_profile_selected_index = 0
	_profiles_list.select(_profile_selected_index)
	_load_selected_profile_into_form(_profile_selected_index)
	_update_profile_action_state()


func _clear_profile_form() -> void:
	_profile_id_label.text = "ID: (new profile)" if _profile_is_new_draft else "ID: —"
	_profile_name_edit.text = ""
	_profile_speed_spin.value = 30
	_profile_vision_option.select(0)
	_profile_darkvision_spin.value = 60
	_profile_perception_spin.value = 0
	_profile_passive_label.text = "10"
	if _profile_dash_check:
		_profile_dash_check.button_pressed = false
	_profile_input_type_option.select(0)
	_profile_input_id_edit.text = ""
	if _profile_color_btn:
		_profile_color_btn.color = Color.WHITE
	if _profile_orientation_spin:
		_profile_orientation_spin.value = 0
	_profile_extras_edit.text = "{}"
	_on_profile_vision_selected(0)
	_update_profile_action_state()


func _on_profile_selected(index: int) -> void:
	_profile_is_new_draft = false
	_profile_selected_index = index
	_load_selected_profile_into_form(index)
	_update_profile_action_state()


func _load_selected_profile_into_form(index: int) -> void:
	var pm := _profile_service()
	var profiles_arr: Array = pm.get_profiles() if pm != null else []
	if profiles_arr.is_empty() or index < 0 or index >= profiles_arr.size():
		_clear_profile_form()
		return
	var profile = profiles_arr[index]
	if not profile is PlayerProfile:
		_clear_profile_form()
		return
	var p := profile as PlayerProfile
	_profile_id_label.text = "ID: %s" % p.id
	_profile_name_edit.text = p.player_name
	_profile_speed_spin.value = p.base_speed
	_profile_vision_option.select(_profile_vision_option.get_item_index(p.vision_type))
	_profile_darkvision_spin.value = p.darkvision_range
	_profile_perception_spin.value = p.perception_mod
	_profile_passive_label.text = str(p.get_passive_perception())
	if _profile_dash_check:
		var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		var dash_on: bool = false
		if registry != null and registry.input != null:
			dash_on = registry.input.is_dashing(p.id)
		_profile_dash_check.button_pressed = dash_on
	_profile_input_type_option.select(_profile_input_type_option.get_item_index(p.input_type))
	_profile_input_id_edit.text = p.input_id
	_profile_extras_edit.text = JSON.stringify(p.extras, "\t")
	if _profile_orientation_spin:
		_profile_orientation_spin.value = p.table_orientation
	if _profile_color_btn:
		_profile_color_btn.color = p.indicator_color
	_on_profile_vision_selected(_profile_vision_option.selected)
	_update_profile_action_state()


func _on_profile_add_pressed() -> void:
	_profile_is_new_draft = true
	_profile_selected_index = -1
	if _profiles_list:
		_profiles_list.deselect_all()
	_clear_profile_form()
	var pm := _profile_service()
	var next_idx: int = (pm.get_profiles().size() + 1) if pm != null else 1
	_profile_name_edit.text = "Player %d" % next_idx
	if _profile_name_edit:
		_profile_name_edit.grab_focus()
		_profile_name_edit.select_all()
	_set_status("Creating new profile. Fill fields, then click Create Profile.")


func _on_profile_delete_pressed() -> void:
	if _profile_is_new_draft:
		_on_profile_cancel_new_pressed()
		return
	var pm := _profile_service()
	if pm == null or _profile_selected_index < 0 or _profile_selected_index >= pm.get_profiles().size():
		_set_status("Select a profile to remove.")
		return
	var arr := pm.get_profiles()
	var item = arr[_profile_selected_index]
	var removed_name := "Profile"
	if item is PlayerProfile:
		removed_name = (item as PlayerProfile).player_name
	var remove_id := str((item as PlayerProfile).id) if item is PlayerProfile else str((item as Dictionary).get("id", ""))
	pm.remove_profile(remove_id)
	_profile_selected_index = clampi(_profile_selected_index, 0, max(0, pm.get_profiles().size() - 1))
	_profile_is_new_draft = false
	_refresh_profiles_list()
	_update_profile_action_state()
	_set_status("Deleted profile: %s" % removed_name)


func _profile_service() -> ProfileManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.profile == null:
		return null
	return registry.profile


func _on_profile_save_pressed() -> void:
	var pm := _profile_service()
	if _profile_is_new_draft:
		var created := PlayerProfile.new()
		if not _apply_form_to_profile(created):
			return
		if pm != null:
			pm.add_profile(created)
		_profile_is_new_draft = false
		_profile_selected_index = _find_profile_index_by_id(created.id)
		_refresh_profiles_list()
		_update_profile_action_state()
		_set_status("Created profile: %s (PP %d)" % [created.player_name, created.get_passive_perception()])
		return

	var profiles_arr: Array = pm.get_profiles() if pm != null else []
	if profiles_arr.size() == 0 or _profile_selected_index < 0 or _profile_selected_index >= profiles_arr.size():
		_set_status("Select a profile to edit or click New.")
		return
	var profile = profiles_arr[_profile_selected_index]
	if not profile is PlayerProfile:
		_set_status("Invalid profile selected.")
		return
	var p: PlayerProfile = profile as PlayerProfile
	if not _apply_form_to_profile(p):
		return
	if pm != null:
		pm.update_profile_at(_profile_selected_index, p)
	_apply_profile_bindings()
	_refresh_profiles_list()
	_update_profile_action_state()
	_set_status("Saved profile: %s (PP %d) to user://data/profiles.json" % [p.player_name, p.get_passive_perception()])


func _on_profile_cancel_new_pressed() -> void:
	if not _profile_is_new_draft:
		return
	_profile_is_new_draft = false
	var pm := _profile_service()
	var count := pm.get_profiles().size() if pm != null else 0
	if count == 0:
		_profile_selected_index = -1
		_clear_profile_form()
	else:
		_profile_selected_index = clampi(_profile_selected_index, 0, count - 1)
	_refresh_profiles_list()
	_update_profile_action_state()
	_set_status("New profile draft canceled.")


func _apply_form_to_profile(p: PlayerProfile) -> bool:
	p.player_name = _profile_name_edit.text.strip_edges()
	if p.player_name.is_empty():
		p.player_name = "Unnamed Player"
	p.base_speed = _profile_speed_spin.value
	p.vision_type = _profile_vision_option.get_item_id(_profile_vision_option.selected)
	p.darkvision_range = _profile_darkvision_spin.value
	p.perception_mod = int(_profile_perception_spin.value)
	p.input_type = _profile_input_type_option.get_item_id(_profile_input_type_option.selected)
	# Prefer saving a stable player token rather than a numeric ephemeral peer id.
	var raw_input_id := _profile_input_id_edit.text.strip_edges()
	if raw_input_id.is_valid_int():
		# If this numeric id corresponds to a live WS peer that has a seen
		# token, prefer storing that token so profiles remain stable across
		# reconnects. Falls back to numeric id if no token available.
		var peer_id := int(raw_input_id)
		var seen: String = ""
		var nm := _network()
		if nm != null:
			var seen_raw: Variant = nm.get_peer_bound_player(peer_id)
			if seen_raw != null and str(seen_raw) != "":
				seen = str(seen_raw)
		if seen != "":
			p.input_id = seen
		else:
			p.input_id = raw_input_id
	else:
		p.input_id = raw_input_id
	if _profile_orientation_spin:
		p.table_orientation = int(_profile_orientation_spin.value)
	if _profile_color_btn:
		p.indicator_color = _profile_color_btn.color

	var extras_raw := _profile_extras_edit.text.strip_edges()
	if extras_raw.is_empty():
		p.extras = {}
	else:
		var parsed: Variant = JsonUtilsScript.parse_json_text(extras_raw)
		if parsed == null or not parsed is Dictionary:
			_set_status("Extras must be valid JSON object; profile not saved.")
			return false
		p.extras = (parsed as Dictionary).duplicate(true)
	var dash_val: bool = _profile_dash_check.button_pressed if _profile_dash_check else false
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.input != null:
		registry.input.set_dash_state(p.id, dash_val)

	p.ensure_id()
	return true


func _find_profile_index_by_id(profile_id: String) -> int:
	var pm := _profile_service()
	var profiles_arr: Array = pm.get_profiles() if pm != null else []
	for i in range(profiles_arr.size()):
		var profile = profiles_arr[i]
		if profile is PlayerProfile and (profile as PlayerProfile).id == profile_id:
			return i
	return max(0, profiles_arr.size() - 1)


func _update_profile_action_state() -> void:
	var pm := _profile_service()
	var count := pm.get_profiles().size() if pm != null else 0
	var has_selected: bool = count > 0 and _profile_selected_index >= 0 and _profile_selected_index < count and not _profile_is_new_draft
	if _profile_delete_btn:
		_profile_delete_btn.disabled = not has_selected and not _profile_is_new_draft
	if _profile_delete_btn_alt:
		_profile_delete_btn_alt.disabled = not has_selected and not _profile_is_new_draft
	if _profile_save_btn:
		_profile_save_btn.text = "Create Profile" if _profile_is_new_draft else "Save Profile"
	if _profile_cancel_new_btn:
		_profile_cancel_new_btn.visible = _profile_is_new_draft
	if _profile_add_btn:
		_profile_add_btn.disabled = _profile_is_new_draft
	if _profile_add_btn_alt:
		_profile_add_btn_alt.disabled = _profile_is_new_draft


func _on_profile_vision_selected(index: int) -> void:
	if _profile_darkvision_spin == null or _profile_vision_option == null:
		return
	var vision_id := _profile_vision_option.get_item_id(index)
	_profile_darkvision_spin.editable = (vision_id == PlayerProfile.VisionType.DARKVISION)


func _on_profile_perception_changed(value: float) -> void:
	if _profile_passive_label:
		_profile_passive_label.text = str(10 + int(value))


func _refresh_available_inputs() -> void:
	if _profile_gamepad_option:
		_profile_gamepad_option.clear()
		for device_id in Input.get_connected_joypads():
			_profile_gamepad_option.add_item("%d — %s" % [device_id, Input.get_joy_name(device_id)], device_id)
		if _profile_gamepad_option.item_count == 0:
			_profile_gamepad_option.add_item("No gamepads connected", -1)

	if _profile_ws_option:
		_profile_ws_option.clear()
		var nm := _network()
		if nm != null:
			for peer_id in nm.get_connected_input_peers():
				_profile_ws_option.add_item("Peer %d" % peer_id, peer_id)
		if _profile_ws_option.item_count == 0:
			_profile_ws_option.add_item("No WS peers connected", -1)


func _on_bind_use_gamepad_pressed() -> void:
	if _profile_gamepad_option == null or _profile_gamepad_option.item_count == 0:
		return
	var device_id := _profile_gamepad_option.get_item_id(_profile_gamepad_option.selected)
	if device_id < 0:
		return
	_profile_input_type_option.select(_profile_input_type_option.get_item_index(PlayerProfile.InputType.GAMEPAD))
	_profile_input_id_edit.text = str(device_id)
	# Auto-save binding for existing profile edits so bindings persist immediately
	if not _profile_is_new_draft:
		_on_profile_save_pressed()


func _on_bind_use_ws_pressed() -> void:
	if _profile_ws_option == null or _profile_ws_option.item_count == 0:
		return
	var peer_id := _profile_ws_option.get_item_id(_profile_ws_option.selected)
	if peer_id < 0:
		return
	_profile_input_type_option.select(_profile_input_type_option.get_item_index(PlayerProfile.InputType.WEBSOCKET))
	_profile_input_id_edit.text = str(peer_id)
	# Auto-save binding for existing profile edits so bindings persist immediately
	if not _profile_is_new_draft:
		_on_profile_save_pressed()


func _apply_profile_bindings() -> void:
	var input := _input_service()
	input.clear_all_bindings()
	var nm := _network()
	if nm != null:
		nm.clear_all_peer_bindings()
	var pm := _profile_service()
	var gs := _game_state()
	var profiles_arr: Array = pm.get_profiles() if pm != null else []
	for profile in profiles_arr:
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		p.ensure_id()
		if gs != null:
			gs.register_player(p.id)
		match p.input_type:
			PlayerProfile.InputType.GAMEPAD:
				# Bind by numeric device id if present
				if p.input_id.is_valid_int() and input != null:
					input.bind_gamepad(int(p.input_id), p.id)
				# Otherwise try to match by device name substring, or auto-bind first free device
				elif p.input_id != "":
					if input != null:
						for device_id in Input.get_connected_joypads():
							var joy_name := Input.get_joy_name(device_id)
							if joy_name != null and joy_name.to_lower().find(p.input_id.to_lower()) >= 0:
								input.bind_gamepad(device_id, p.id)
								break
				else:
					# Auto-bind: first connected device not already bound
					if input != null:
						for device_id in Input.get_connected_joypads():
							if not input.has_gamepad_binding(device_id):
								input.bind_gamepad(device_id, p.id)
								break
			PlayerProfile.InputType.WEBSOCKET:
				if p.input_id.is_valid_int() and nm != null:
					nm.bind_peer(int(p.input_id), p.id)
	_player_state_dirty = true
	_player_state_countdown = 0.0
	# Send player_bind to all display peers after re-binding.
	_send_player_bind_to_all_displays()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_apply_profile_bindings()
	if _profiles_dialog and _profiles_dialog.visible:
		_refresh_available_inputs()


func _on_profiles_changed() -> void:
	_apply_profile_bindings()
	if _backend != null:
		_backend.sync_profiles()
	if _map_view != null and _backend != null:
		_map_view.set_draggable_tokens(_backend.get_dm_token_nodes())
	_broadcast_player_state()
	if _profiles_dialog and _profiles_dialog.visible:
		_refresh_profiles_list()
	_update_profile_action_state()
	_refresh_freeze_panel()


func _on_token_drag_started(token_id: Variant) -> void:
	if _backend != null:
		_backend.begin_token_drag(token_id)


func _on_token_drag_completed(token_id: Variant, new_world_pos: Vector2) -> void:
	var id: String = str(token_id)
	var registry_drag := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	# Capture old player-character position before end_token_drag updates it.
	var old_char_pos: Vector2 = Vector2.ZERO
	var is_player_char: bool = false
	if registry_drag != null and registry_drag.game_state != null:
		is_player_char = registry_drag.game_state.player_positions.has(token_id)
		if is_player_char:
			old_char_pos = registry_drag.game_state.get_position(token_id)
	if _backend != null:
		_backend.end_token_drag(token_id, new_world_pos)
	_player_state_dirty = true
	# Persist the new position and refresh door/passthrough state.
	var data: TokenData = null
	if registry_drag != null and registry_drag.token != null:
		data = registry_drag.token.get_token_by_id(id)
		if data != null:
			var old_pos := data.world_pos
			data.world_pos = new_world_pos
			registry_drag.token.update_token(data)
			if _map_view != null:
				_map_view.apply_token_passthrough_state(data)
			# Push undo command capturing before/after world positions.
			if registry_drag.history != null and old_pos != new_world_pos:
				var mv := _map_view
				registry_drag.history.push_command(HistoryCommand.create("Token moved",
					func():
						var td: TokenData = registry_drag.token.get_token_by_id(id)
						if td == null: return
						td.world_pos = old_pos
						registry_drag.token.update_token(td)
						if mv != null:
							mv.update_token_sprite(td)
							mv.apply_token_passthrough_state(td)
						_broadcast_token_change(td, false),
					func():
						var td: TokenData = registry_drag.token.get_token_by_id(id)
						if td == null: return
						td.world_pos = new_world_pos
						registry_drag.token.update_token(td)
						if mv != null:
							mv.update_token_sprite(td)
							mv.apply_token_passthrough_state(td)
						_broadcast_token_change(td, false)))
		elif is_player_char and registry_drag.history != null and old_char_pos.distance_to(new_world_pos) > 1.0:
			# Player character drag — not in TokenService, undo via BackendRuntime.
			var backend_ref := _backend
			registry_drag.history.push_command(HistoryCommand.create("Character moved",
				func():
					if backend_ref != null:
						backend_ref.end_token_drag(token_id, old_char_pos)
					_nm_broadcast_to_displays({"msg": "token_moved", "token_id": id,
						"world_pos": {"x": old_char_pos.x, "y": old_char_pos.y}}),
				func():
					if backend_ref != null:
						backend_ref.end_token_drag(token_id, new_world_pos)
					_nm_broadcast_to_displays({"msg": "token_moved", "token_id": id,
						"world_pos": {"x": new_world_pos.x, "y": new_world_pos.y}})))
	# Broadcast updated token position to player displays.
	_nm_broadcast_to_displays({
		"msg": "token_moved",
		"token_id": id,
		"world_pos": {"x": new_world_pos.x, "y": new_world_pos.y},
	})
	# For DOOR and SECRET_PASSAGE tokens, also broadcast the full token_updated
	# so the player display can rebuild passthrough geometry with shifted paths.
	if data != null and (data.category == TokenData.TokenCategory.DOOR
			or data.category == TokenData.TokenCategory.SECRET_PASSAGE):
		_broadcast_token_change(data, false)


func _on_token_resize_completed(token_id: String, new_width_px: float, new_height_px: float) -> void:
	_player_state_dirty = true
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var data: TokenData = registry.token.get_token_by_id(token_id)
	if data == null:
		return
	var old_w := data.width_px
	var old_h := data.height_px
	data.width_px = new_width_px
	data.height_px = new_height_px
	registry.token.update_token(data)
	if _map_view != null:
		_map_view.apply_token_passthrough_state(data)
	if registry.history != null and (old_w != new_width_px or old_h != new_height_px):
		var mv := _map_view
		registry.history.push_command(HistoryCommand.create("Token resized",
			func():
				var td: TokenData = registry.token.get_token_by_id(token_id)
				if td == null: return
				td.width_px = old_w; td.height_px = old_h
				registry.token.update_token(td)
				if mv != null: mv.update_token_sprite(td); mv.apply_token_passthrough_state(td)
				_broadcast_token_change(td, false),
			func():
				var td: TokenData = registry.token.get_token_by_id(token_id)
				if td == null: return
				td.width_px = new_width_px; td.height_px = new_height_px
				registry.token.update_token(td)
				if mv != null: mv.update_token_sprite(td); mv.apply_token_passthrough_state(td)
				_broadcast_token_change(td, false)))
	_broadcast_token_change(data, false)


func _on_token_rotation_completed(token_id: String, rotation_deg: float) -> void:
	_player_state_dirty = true
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var data: TokenData = registry.token.get_token_by_id(token_id)
	if data == null:
		return
	var old_rot := data.rotation_deg
	data.rotation_deg = rotation_deg
	registry.token.update_token(data)
	if registry.history != null and old_rot != rotation_deg:
		var mv := _map_view
		registry.history.push_command(HistoryCommand.create("Token rotated",
			func():
				var td: TokenData = registry.token.get_token_by_id(token_id)
				if td == null: return
				td.rotation_deg = old_rot
				registry.token.update_token(td)
				if mv != null: mv.update_token_sprite(td)
				_broadcast_token_change(td, false),
			func():
				var td: TokenData = registry.token.get_token_by_id(token_id)
				if td == null: return
				td.rotation_deg = rotation_deg
				registry.token.update_token(td)
				if mv != null: mv.update_token_sprite(td)
				_broadcast_token_change(td, false)))
	_broadcast_token_change(data, false)


func _on_token_trigger_radius_changed(token_id: String, new_radius_px: float) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var data: TokenData = registry.token.get_token_by_id(token_id)
	if data == null:
		return
	var old_radius := data.trigger_radius_px
	data.trigger_radius_px = new_radius_px
	registry.token.update_token(data)
	if registry.history != null and not is_equal_approx(old_radius, new_radius_px):
		registry.history.push_command(HistoryCommand.create("Token trigger radius",
			func():
				var td: TokenData = registry.token.get_token_by_id(token_id)
				if td == null: return
				td.trigger_radius_px = old_radius
				registry.token.update_token(td)
				_broadcast_token_change(td, false),
			func():
				var td: TokenData = registry.token.get_token_by_id(token_id)
				if td == null: return
				td.trigger_radius_px = new_radius_px
				registry.token.update_token(td)
				_broadcast_token_change(td, false)))
	_broadcast_token_change(data, false)


# ---------------------------------------------------------------------------
# Passage paint panel — build, signals, handlers
# ---------------------------------------------------------------------------

func _build_passage_panel() -> void:
	# Anchored directly in _ui_layer (same as _freeze_panel) so _ui_root.scale
	# does not push it off-screen on HiDPI / Retina displays.
	_passage_panel = PanelContainer.new()
	_passage_panel.name = "PassagePanel"
	_passage_panel.visible = false
	# Bottom bar: anchors to bottom edge, full width, grows upward.
	_passage_panel.anchor_left = 0.0
	_passage_panel.anchor_right = 1.0
	_passage_panel.anchor_top = 1.0
	_passage_panel.anchor_bottom = 1.0
	_passage_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_passage_panel.offset_left = 0.0
	_passage_panel.offset_right = 0.0
	_passage_panel.offset_top = -44.0
	_passage_panel.offset_bottom = 0.0
	_ui_layer.add_child(_passage_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.add_child(hbox)
	_passage_panel.add_child(margin)

	var icon_label := Label.new()
	icon_label.text = "🌀"
	hbox.add_child(icon_label)

	_passage_token_label = Label.new()
	_passage_token_label.text = "Secret Passage"
	_passage_token_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_passage_token_label)

	_passage_mode_label = Label.new()
	_passage_mode_label.text = "Mode:"
	hbox.add_child(_passage_mode_label)

	_passage_mode_option = OptionButton.new()
	_passage_mode_option.add_item("Off", 0) # PassageTool.NONE
	_passage_mode_option.add_item("Freehand", 1) # PassageTool.FREEHAND
	_passage_mode_option.add_item("Polyline", 2) # PassageTool.POLYLINE
	_passage_mode_option.add_item("Erase", 3) # PassageTool.ERASE
	_passage_mode_option.selected = 0
	_passage_mode_option.focus_mode = Control.FOCUS_NONE
	_passage_mode_option.item_selected.connect(_on_passage_mode_selected)
	hbox.add_child(_passage_mode_option)

	_passage_brush_label = Label.new()
	_passage_brush_label.text = "Width:"
	hbox.add_child(_passage_brush_label)

	_passage_brush_slider = HSlider.new()
	_passage_brush_slider.min_value = 12.0
	_passage_brush_slider.max_value = 192.0
	_passage_brush_slider.step = 4.0
	_passage_brush_slider.value = 48.0
	_passage_brush_slider.custom_minimum_size = Vector2(120.0, 0.0)
	_passage_brush_slider.focus_mode = Control.FOCUS_NONE
	_passage_brush_slider.value_changed.connect(_on_passage_brush_changed)
	hbox.add_child(_passage_brush_slider)

	_passage_commit_btn = Button.new()
	_passage_commit_btn.text = "Commit"
	_passage_commit_btn.focus_mode = Control.FOCUS_NONE
	_passage_commit_btn.tooltip_text = "Save passage geometry to this token"
	_passage_commit_btn.pressed.connect(_on_passage_commit_pressed)
	hbox.add_child(_passage_commit_btn)

	_passage_clear_btn = Button.new()
	_passage_clear_btn.text = "Clear"
	_passage_clear_btn.focus_mode = Control.FOCUS_NONE
	_passage_clear_btn.tooltip_text = "Erase all WIP passage paths"
	_passage_clear_btn.pressed.connect(_on_passage_clear_pressed)
	hbox.add_child(_passage_clear_btn)


func _on_token_selected(token_id: String) -> void:
	## Show the passage paint panel when a SECRET_PASSAGE token is selected.
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(token_id)
	if data == null or data.category != TokenData.TokenCategory.SECRET_PASSAGE:
		_hide_passage_panel()
		return
	_selected_passage_token_id = token_id
	if _passage_panel != null:
		_passage_panel.visible = true
		_passage_token_label.text = "Passage: %s" % data.label if not data.label.is_empty() else "Secret Passage"
	if _passage_mode_option != null:
		_passage_mode_option.selected = 0


func _hide_passage_panel() -> void:
	if _map_view != null and _map_view._passage_tool != MapView.PassageTool.NONE:
		_map_view.deactivate_passage_tool()
	_selected_passage_token_id = ""
	if _passage_panel != null:
		_passage_panel.visible = false
	if _passage_mode_option != null:
		_passage_mode_option.selected = 0


func _on_passage_mode_selected(index: int) -> void:
	if _map_view == null or _selected_passage_token_id.is_empty():
		return
	var mode: int = _passage_mode_option.get_item_id(index)
	if mode == 0: # Off / NONE
		if _map_view._passage_tool != MapView.PassageTool.NONE:
			_map_view.deactivate_passage_tool()
		return
	# Activate / switch mode.
	var tm := _token_manager()
	if tm == null:
		return
	var brush_size: float = _passage_brush_slider.value if _passage_brush_slider != null else 48.0
	if _map_view._active_passage_token_id != _selected_passage_token_id:
		var data: TokenData = tm.get_token_by_id(_selected_passage_token_id)
		var initial_paths: Array = data.passage_paths if data != null else []
		_map_view.activate_passage_tool(_selected_passage_token_id, initial_paths, brush_size)
	_map_view.set_passage_tool(mode)


func _on_passage_brush_changed(value: float) -> void:
	if _map_view != null and _map_view._active_passage_token_id != "":
		_map_view._wip_brush_size = value
		_map_view._rebuild_passage_wip_lines()


func _on_passage_commit_pressed() -> void:
	if _map_view != null:
		_map_view.deactivate_passage_tool()
	if _passage_mode_option != null:
		_passage_mode_option.selected = 0


func _on_passage_clear_pressed() -> void:
	if _map_view != null:
		_map_view.clear_passage_wip()
	# Immediately commit empty passage data so the token sprite and LOS
	# geometry update right away rather than waiting for a separate Commit.
	if _selected_passage_token_id.is_empty():
		return
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(_selected_passage_token_id)
	if data == null:
		return
	data.passage_paths = []
	data.passage_width_px = 0.0
	tm.update_token(data)
	_player_state_dirty = true
	if _map_view != null:
		_map_view.update_token_sprite(data)
		_map_view.apply_token_passthrough_state(data)
	_broadcast_token_change(data, false)


func _on_passage_paths_committed(token_id: String, paths: Array, width_px: float) -> void:
	## Mirrors _on_token_resize_completed: update token data and broadcast.
	_player_state_dirty = true
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(token_id)
	if data == null:
		return
	var old_paths := data.passage_paths.duplicate(true)
	var old_width := data.passage_width_px
	var old_blocks_los := data.blocks_los
	data.passage_paths = paths
	data.passage_width_px = width_px
	# Auto-open the passage when corridors are painted.  The DM can always
	# re-close it via right-click → "Close (restore LOS)".
	if paths.size() > 0:
		data.blocks_los = false
	tm.update_token(data)
	if _map_view != null:
		_map_view.update_token_sprite(data)
		_map_view.apply_token_passthrough_state(data)
	var registry_p := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry_p != null and registry_p.history != null:
		var new_paths := paths.duplicate(true)
		var new_blos := data.blocks_los
		var mv := _map_view
		registry_p.history.push_command(HistoryCommand.create("Passage edited",
			func():
				var td: TokenData = tm.get_token_by_id(token_id)
				if td == null: return
				td.passage_paths = old_paths.duplicate(true)
				td.passage_width_px = old_width
				td.blocks_los = old_blocks_los
				tm.update_token(td)
				if mv != null: mv.update_token_sprite(td); mv.apply_token_passthrough_state(td)
				_broadcast_token_change(td, false),
			func():
				var td: TokenData = tm.get_token_by_id(token_id)
				if td == null: return
				td.passage_paths = new_paths.duplicate(true)
				td.passage_width_px = width_px
				td.blocks_los = new_blos
				tm.update_token(td)
				if mv != null: mv.update_token_sprite(td); mv.apply_token_passthrough_state(td)
				_broadcast_token_change(td, false)))
	_broadcast_token_change(data, false)
	_hide_passage_panel()
	_set_status("Passage paths saved")


# ---------------------------------------------------------------------------
# Token placement / editing
# ---------------------------------------------------------------------------

func _on_token_place_requested(world_pos: Vector2) -> void:
	## Left-click in PLACE_TOKEN tool mode — open editor for a brand-new token.
	_token_editor_id = ""
	_open_token_editor(TokenData.create(TokenData.TokenCategory.GENERIC, world_pos))


func _on_token_right_clicked(id: String, screen_pos: Vector2) -> void:
	## Right-click on a token in SELECT mode — show context menu.
	_token_context_id = id
	if _token_context_menu == null:
		_token_context_menu = PopupMenu.new()
		_token_context_menu.id_pressed.connect(_on_token_context_menu_id)
		add_child(_token_context_menu)
	_apply_token_context_menu_theme()
	_token_context_menu.clear()
	_token_context_menu.add_item("Edit Token…", 0)
	_token_context_menu.add_separator()
	_token_context_menu.add_item("Toggle Visibility", 1)
	# Show door open/close toggle for DOOR and SECRET_PASSAGE categories.
	var registry_cm := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var td: TokenData = registry_cm.token.get_token_by_id(id) if (registry_cm != null and registry_cm.token != null) else null
	if td != null and (td.category == TokenData.TokenCategory.DOOR or td.category == TokenData.TokenCategory.SECRET_PASSAGE):
		_token_context_menu.add_separator()
		var toggle_label: String
		if td.category == TokenData.TokenCategory.DOOR:
			toggle_label = "Open Door" if td.blocks_los else "Close Door"
		else:
			toggle_label = "Close (restore LOS)" if not td.blocks_los else "Open (allow LOS)"
		_token_context_menu.add_item(toggle_label, 3)
	_token_context_menu.add_separator()
	_token_context_menu.add_item("Delete Token", 2)
	_token_context_menu.popup(Rect2i(int(screen_pos.x), int(screen_pos.y), 0, 0))


func _on_token_context_menu_id(id: int) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var tm: TokenManager = registry.token
	match id:
		0: # Edit
			var data: TokenData = tm.get_token_by_id(_token_context_id)
			if data != null:
				_open_token_editor(data)
		1: # Toggle visibility
			var data: TokenData = tm.get_token_by_id(_token_context_id)
			if data != null:
				tm.set_token_visibility(_token_context_id, not data.is_visible_to_players)
				_on_token_visibility_changed(_token_context_id, data.is_visible_to_players)
		2: # Delete
			var del_data: TokenData = tm.get_token_by_id(_token_context_id)
			var del_snapshot: TokenData = null
			if del_data != null:
				del_snapshot = TokenData.from_dict(del_data.to_dict())
			tm.remove_token(_token_context_id)
			if _map_view != null:
				_map_view.remove_token_sprite(_token_context_id)
			_nm_broadcast_to_displays({"msg": "token_removed", "token_id": _token_context_id,
				"puzzle_notes": _collect_revealed_puzzle_notes()})
			_broadcast_puzzle_notes_state()
			if del_snapshot != null:
				var cid := _token_context_id
				var mv := _map_view
				var reg_del := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
				if reg_del != null and reg_del.history != null:
					reg_del.history.push_command(HistoryCommand.create("Token deleted",
						func():
							var restored := TokenData.from_dict(del_snapshot.to_dict())
							reg_del.token.add_token(restored)
							if mv != null: mv.add_token_sprite(restored, true); mv.apply_token_passthrough_state(restored)
							_broadcast_token_change(restored, true)
							_broadcast_puzzle_notes_state(),
						func():
							reg_del.token.remove_token(cid)
							if mv != null: mv.remove_token_sprite(cid)
							_nm_broadcast_to_displays({"msg": "token_removed", "token_id": cid,
								"puzzle_notes": _collect_revealed_puzzle_notes()})
							_broadcast_puzzle_notes_state()))
		3: # Toggle open/closed (DOOR / SECRET_PASSAGE)
			var data: TokenData = tm.get_token_by_id(_token_context_id)
			if data != null:
				data.blocks_los = not data.blocks_los
				tm.update_token(data)
				if _map_view != null:
					_map_view.apply_token_passthrough_state(data)
				_broadcast_token_change(data, false)


func _open_token_editor(data: TokenData) -> void:
	_token_editor_id = data.id
	if _token_editor_dialog == null:
		_build_token_editor_dialog()
		_apply_ui_scale()
	# Populate fields from data.
	if _token_label_edit != null:
		_token_label_edit.text = data.label
	if _token_category_option != null:
		_token_category_option.selected = data.category
	if _token_visible_check != null:
		_token_visible_check.button_pressed = data.is_visible_to_players
	if _token_perception_spin != null:
		_token_perception_spin.value = float(data.perception_dc)
	if _token_auto_reveal_check != null:
		_token_auto_reveal_check.button_pressed = data.auto_reveal
	if _token_width_spin != null:
		_token_width_spin.value = data.width_px
	if _token_height_spin != null:
		_token_height_spin.value = data.height_px
	if _token_rotation_spin != null:
		_token_rotation_spin.value = data.rotation_deg
	if _token_trigger_spin != null:
		var px_per_5ft: float = _pixels_per_5ft_current()
		_token_trigger_spin.value = data.trigger_radius_px / px_per_5ft * 5.0
	if _token_autopause_check != null:
		_token_autopause_check.button_pressed = data.autopause
	if _token_autopause_max_spin != null:
		_token_autopause_max_spin.value = float(data.autopause_max_triggers)
	if _token_autopause_collision_check != null:
		_token_autopause_collision_check.button_pressed = data.autopause_on_collision
	if _token_pause_interact_check != null:
		_token_pause_interact_check.button_pressed = data.pause_on_interact
	if _token_shape_option != null:
		_token_shape_option.select(_token_shape_option.get_item_index(data.token_shape))
	if _token_blocks_los_check != null:
		_token_blocks_los_check.button_pressed = data.blocks_los
	if _token_blocks_los_row != null:
		var is_door_type: bool = data.category == TokenData.TokenCategory.DOOR or data.category == TokenData.TokenCategory.SECRET_PASSAGE
		_token_blocks_los_row.visible = is_door_type
	if _token_notes_edit != null:
		_token_notes_edit.text = data.notes
	# Populate puzzle notes rows.
	_populate_puzzle_note_rows(data.puzzle_notes)
	# Store temporary placement position in editor id if brand new.
	if _token_editor_dialog != null:
		var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		var is_new := (registry == null
				or registry.token == null
				or registry.token.get_token_by_id(data.id) == null)
		_token_editor_dialog.title = "New Token" if is_new else "Edit Token"
		## Store the new-token world_pos in meta so confirm can read it.
		_token_editor_dialog.set_meta("pending_world_pos", data.world_pos)
		_token_editor_dialog.popup_centered()


func _build_token_editor_dialog() -> void:
	_token_editor_dialog = ConfirmationDialog.new()
	_token_editor_dialog.title = "Token"
	_token_editor_dialog.min_size = Vector2i(520, 620)
	_token_editor_dialog.confirmed.connect(_on_token_editor_confirmed)
	add_child(_token_editor_dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_token_editor_dialog_root = vbox
	_token_editor_dialog.add_child(vbox)

	# Label
	var lbl_row := HBoxContainer.new()
	var lbl_label := Label.new()
	lbl_label.text = "Label:"
	lbl_label.custom_minimum_size = Vector2(120, 0)
	lbl_row.add_child(lbl_label)
	_token_label_edit = LineEdit.new()
	_token_label_edit.custom_minimum_size = Vector2(200, 0)
	_token_label_edit.placeholder_text = "e.g. Iron Door"
	lbl_row.add_child(_token_label_edit)
	vbox.add_child(lbl_row)

	# Category
	var cat_row := HBoxContainer.new()
	var cat_label := Label.new()
	cat_label.text = "Category:"
	cat_label.custom_minimum_size = Vector2(120, 0)
	cat_row.add_child(cat_label)
	_token_category_option = OptionButton.new()
	_token_category_option.custom_minimum_size = Vector2(200, 0)
	for cat_val in range(8):
		_token_category_option.add_item(TokenData.category_name(cat_val), cat_val)
	cat_row.add_child(_token_category_option)
	vbox.add_child(cat_row)

	# Width
	var width_row := HBoxContainer.new()
	var width_label := Label.new()
	width_label.text = "Width (px):"
	width_label.custom_minimum_size = Vector2(120, 0)
	width_row.add_child(width_label)
	_token_width_spin = SpinBox.new()
	_token_width_spin.min_value = 24.0
	_token_width_spin.max_value = 1024.0
	_token_width_spin.step = 8.0
	_token_width_spin.value = 48.0
	_token_width_spin.suffix = "px"
	_token_width_spin.custom_minimum_size = Vector2(130, 0)
	width_row.add_child(_token_width_spin)
	vbox.add_child(width_row)

	# Height
	var height_row := HBoxContainer.new()
	var height_label := Label.new()
	height_label.text = "Height (px):"
	height_label.custom_minimum_size = Vector2(120, 0)
	height_row.add_child(height_label)
	_token_height_spin = SpinBox.new()
	_token_height_spin.min_value = 24.0
	_token_height_spin.max_value = 1024.0
	_token_height_spin.step = 8.0
	_token_height_spin.value = 48.0
	_token_height_spin.suffix = "px"
	_token_height_spin.custom_minimum_size = Vector2(130, 0)
	height_row.add_child(_token_height_spin)
	vbox.add_child(height_row)

	# Rotation
	var rot_row := HBoxContainer.new()
	var rot_label := Label.new()
	rot_label.text = "Rotation (°):"
	rot_label.custom_minimum_size = Vector2(120, 0)
	rot_row.add_child(rot_label)
	_token_rotation_spin = SpinBox.new()
	_token_rotation_spin.min_value = -360.0
	_token_rotation_spin.max_value = 360.0
	_token_rotation_spin.step = 15.0
	_token_rotation_spin.value = 0.0
	_token_rotation_spin.suffix = "°"
	_token_rotation_spin.custom_minimum_size = Vector2(130, 0)
	rot_row.add_child(_token_rotation_spin)
	vbox.add_child(rot_row)

	# Visible to players
	var vis_row := HBoxContainer.new()
	var vis_label := Label.new()
	vis_label.text = "Visible to players:"
	vis_label.custom_minimum_size = Vector2(120, 0)
	vis_row.add_child(vis_label)
	_token_visible_check = CheckBox.new()
	vis_row.add_child(_token_visible_check)
	vbox.add_child(vis_row)

	# Perception DC
	var perc_row := HBoxContainer.new()
	var perc_label := Label.new()
	perc_label.text = "Perception DC:"
	perc_label.custom_minimum_size = Vector2(120, 0)
	perc_row.add_child(perc_label)
	_token_perception_spin = SpinBox.new()
	_token_perception_spin.min_value = -1.0
	_token_perception_spin.max_value = 30.0
	_token_perception_spin.step = 1.0
	_token_perception_spin.value = -1.0
	_token_perception_spin.tooltip_text = "-1 = manual only"
	_token_perception_spin.custom_minimum_size = Vector2(170, 0)
	perc_row.add_child(_token_perception_spin)
	vbox.add_child(perc_row)

	# Auto Reveal (when perception DC is met)
	var ar_row := HBoxContainer.new()
	var ar_label := Label.new()
	ar_label.text = "Auto-reveal on perception:"
	ar_label.custom_minimum_size = Vector2(120, 0)
	ar_row.add_child(ar_label)
	_token_auto_reveal_check = CheckBox.new()
	_token_auto_reveal_check.tooltip_text = "Reveal token to players when perception DC is met (otherwise just shows ! indicator)"
	ar_row.add_child(_token_auto_reveal_check)
	vbox.add_child(ar_row)

	# Trigger Radius (displayed in feet, stored in pixels)
	var tr_row := HBoxContainer.new()
	var tr_label := Label.new()
	tr_label.text = "Trigger Radius:"
	tr_label.custom_minimum_size = Vector2(120, 0)
	tr_row.add_child(tr_label)
	_token_trigger_spin = SpinBox.new()
	_token_trigger_spin.min_value = 5.0
	_token_trigger_spin.max_value = 300.0
	_token_trigger_spin.step = 5.0
	_token_trigger_spin.value = 30.0
	_token_trigger_spin.suffix = "ft"
	_token_trigger_spin.custom_minimum_size = Vector2(130, 0)
	tr_row.add_child(_token_trigger_spin)
	vbox.add_child(tr_row)

	# Autopause
	var ap_row := HBoxContainer.new()
	var ap_label := Label.new()
	ap_label.text = "Autopause on proximity:"
	ap_label.custom_minimum_size = Vector2(120, 0)
	ap_row.add_child(ap_label)
	_token_autopause_check = CheckBox.new()
	ap_row.add_child(_token_autopause_check)
	vbox.add_child(ap_row)

	# Autopause on collision only (e.g. traps)
	var ac_row := HBoxContainer.new()
	var ac_label := Label.new()
	ac_label.text = "Collision only:"
	ac_label.custom_minimum_size = Vector2(120, 0)
	ac_row.add_child(ac_label)
	_token_autopause_collision_check = CheckBox.new()
	_token_autopause_collision_check.tooltip_text = "Only trigger autopause when a player walks onto the token (not at trigger radius)"
	ac_row.add_child(_token_autopause_collision_check)
	vbox.add_child(ac_row)

	# Max Autopause Triggers
	var mt_row := HBoxContainer.new()
	var mt_label := Label.new()
	mt_label.text = "Max Triggers:"
	mt_label.custom_minimum_size = Vector2(120, 0)
	mt_row.add_child(mt_label)
	_token_autopause_max_spin = SpinBox.new()
	_token_autopause_max_spin.min_value = 0.0
	_token_autopause_max_spin.max_value = 100.0
	_token_autopause_max_spin.step = 1.0
	_token_autopause_max_spin.value = 0.0
	_token_autopause_max_spin.tooltip_text = "0 = unlimited"
	_token_autopause_max_spin.custom_minimum_size = Vector2(170, 0)
	mt_row.add_child(_token_autopause_max_spin)
	vbox.add_child(mt_row)

	# Pause on interact
	var pi_row := HBoxContainer.new()
	var pi_label := Label.new()
	pi_label.text = "Pause on interact:"
	pi_label.custom_minimum_size = Vector2(120, 0)
	pi_row.add_child(pi_label)
	_token_pause_interact_check = CheckBox.new()
	pi_row.add_child(_token_pause_interact_check)
	vbox.add_child(pi_row)

	# Shape
	var shape_row := HBoxContainer.new()
	var shape_label := Label.new()
	shape_label.text = "Shape:"
	shape_label.custom_minimum_size = Vector2(120, 0)
	shape_row.add_child(shape_label)
	_token_shape_option = OptionButton.new()
	_token_shape_option.custom_minimum_size = Vector2(200, 0)
	_token_shape_option.add_item("Ellipse", TokenData.TokenShape.ELLIPSE)
	_token_shape_option.add_item("Rectangle", TokenData.TokenShape.RECTANGLE)
	shape_row.add_child(_token_shape_option)
	vbox.add_child(shape_row)

	# Blocks LOS (DOOR / SECRET_PASSAGE only)
	_token_blocks_los_row = HBoxContainer.new()
	var blos_label := Label.new()
	blos_label.text = "Blocks LOS:"
	blos_label.custom_minimum_size = Vector2(120, 0)
	_token_blocks_los_row.add_child(blos_label)
	_token_blocks_los_check = CheckBox.new()
	_token_blocks_los_check.button_pressed = true
	_token_blocks_los_row.add_child(_token_blocks_los_check)
	vbox.add_child(_token_blocks_los_row)

	# Connect category change to show/hide blocks_los row.
	if _token_category_option != null:
		_token_category_option.item_selected.connect(_on_token_category_changed)

	# Notes
	var notes_label := Label.new()
	notes_label.text = "Notes:"
	vbox.add_child(notes_label)
	_token_notes_edit = TextEdit.new()
	_token_notes_edit.custom_minimum_size = Vector2(0, 80)
	_token_notes_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_token_notes_edit.placeholder_text = "DM notes (not shown to players)"
	vbox.add_child(_token_notes_edit)

	# Puzzle Notes
	var pn_header := Label.new()
	pn_header.text = "Puzzle Notes (shown to players when revealed):"
	vbox.add_child(pn_header)
	_puzzle_notes_scroll = ScrollContainer.new()
	_puzzle_notes_scroll.custom_minimum_size = Vector2(0, 160)
	_puzzle_notes_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_puzzle_notes_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_puzzle_notes_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_puzzle_notes_scroll)
	_puzzle_notes_container = VBoxContainer.new()
	_puzzle_notes_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_puzzle_notes_container.add_theme_constant_override("separation", 4)
	_puzzle_notes_scroll.add_child(_puzzle_notes_container)
	_puzzle_notes_add_btn = Button.new()
	_puzzle_notes_add_btn.text = "+ Add Note"
	_puzzle_notes_add_btn.pressed.connect(_on_puzzle_note_add_pressed)
	vbox.add_child(_puzzle_notes_add_btn)


func _apply_token_context_menu_theme() -> void:
	if _token_context_menu == null:
		return
	var scale := _ui_scale()
	_token_context_menu.add_theme_font_size_override("font_size", roundi(16.0 * scale))
	_token_context_menu.add_theme_constant_override("v_separation", roundi(6 * scale))
	_token_context_menu.add_theme_constant_override("h_separation", roundi(12 * scale))


func _on_token_category_changed(idx: int) -> void:
	var cat: int = _token_category_option.get_item_id(idx) if _token_category_option != null else -1
	var is_door_type: bool = cat == TokenData.TokenCategory.DOOR or cat == TokenData.TokenCategory.SECRET_PASSAGE
	if _token_blocks_los_row != null:
		_token_blocks_los_row.visible = is_door_type
	# Default collision-only autopause for traps.
	if _token_autopause_collision_check != null and cat == TokenData.TokenCategory.TRAP:
		_token_autopause_collision_check.button_pressed = true


# ── Puzzle notes helpers ────────────────────────────────────────────────────

func _populate_puzzle_note_rows(notes: Array) -> void:
	if _puzzle_notes_container == null:
		return
	for child in _puzzle_notes_container.get_children():
		child.queue_free()
	for raw: Variant in notes:
		if raw is Dictionary:
			var d := raw as Dictionary
			_add_puzzle_note_row(str(d.get("text", "")), bool(d.get("revealed", false)))


func _add_puzzle_note_row(text: String, revealed: bool) -> void:
	if _puzzle_notes_container == null:
		return
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var up_btn := Button.new()
	up_btn.text = "▲"
	up_btn.custom_minimum_size = Vector2(28, 0)
	up_btn.pressed.connect(_move_puzzle_note_row.bind(row, -1))
	row.add_child(up_btn)

	var down_btn := Button.new()
	down_btn.text = "▼"
	down_btn.custom_minimum_size = Vector2(28, 0)
	down_btn.pressed.connect(_move_puzzle_note_row.bind(row, 1))
	row.add_child(down_btn)

	var line_edit := LineEdit.new()
	line_edit.text = text
	line_edit.placeholder_text = "Puzzle hint…"
	line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line_edit)

	var reveal_check := CheckBox.new()
	reveal_check.text = "Reveal"
	reveal_check.button_pressed = revealed
	row.add_child(reveal_check)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.custom_minimum_size = Vector2(28, 0)
	del_btn.pressed.connect(_remove_puzzle_note_row.bind(row))
	row.add_child(del_btn)

	_puzzle_notes_container.add_child(row)
	# Scale fonts to match the rest of the dialog (rows are added after initial
	# scale_control_fonts pass, so they miss the recursive walk).
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	if mgr != null:
		mgr.scale_control_fonts(row)


func _remove_puzzle_note_row(row: HBoxContainer) -> void:
	if row != null and row.get_parent() == _puzzle_notes_container:
		_puzzle_notes_container.remove_child(row)
		row.queue_free()


func _move_puzzle_note_row(row: HBoxContainer, delta: int) -> void:
	if _puzzle_notes_container == null or row == null:
		return
	var idx: int = row.get_index()
	var new_idx: int = clampi(idx + delta, 0, _puzzle_notes_container.get_child_count() - 1)
	if new_idx != idx:
		_puzzle_notes_container.move_child(row, new_idx)


func _read_puzzle_note_rows() -> Array:
	var result: Array = []
	if _puzzle_notes_container == null:
		return result
	for child in _puzzle_notes_container.get_children():
		var row: HBoxContainer = child as HBoxContainer
		if row == null:
			continue
		var line_edit: LineEdit = row.get_child(2) as LineEdit
		var reveal_check: CheckBox = row.get_child(3) as CheckBox
		if line_edit == null or reveal_check == null:
			continue
		var note_text: String = line_edit.text.strip_edges()
		if note_text.is_empty():
			continue
		result.append({"text": note_text, "revealed": reveal_check.button_pressed})
	return result


func _on_puzzle_note_add_pressed() -> void:
	_add_puzzle_note_row("", false)


func _on_token_editor_confirmed() -> void:
	var label_text: String = _token_label_edit.text.strip_edges() if _token_label_edit != null else ""
	var category: int = _token_category_option.get_selected_id() if _token_category_option != null else 0
	var is_vis: bool = _token_visible_check.button_pressed if _token_visible_check != null else false
	var perc_dc: int = int(_token_perception_spin.value) if _token_perception_spin != null else -1
	var do_auto_reveal: bool = _token_auto_reveal_check.button_pressed if _token_auto_reveal_check != null else false
	var do_ap: bool = _token_autopause_check.button_pressed if _token_autopause_check != null else false
	var do_ap_collision: bool = _token_autopause_collision_check.button_pressed if _token_autopause_collision_check != null else false
	var max_triggers: int = int(_token_autopause_max_spin.value) if _token_autopause_max_spin != null else 0
	var trigger_feet: float = _token_trigger_spin.value if _token_trigger_spin != null else 30.0
	var trigger_px: float = trigger_feet / 5.0 * _pixels_per_5ft_current()
	var do_pi: bool = _token_pause_interact_check.button_pressed if _token_pause_interact_check != null else false
	var notes_text: String = _token_notes_edit.text if _token_notes_edit != null else ""
	var p_notes: Array = _read_puzzle_note_rows()
	var w_px: float = _token_width_spin.value if _token_width_spin != null else 48.0
	var h_px: float = _token_height_spin.value if _token_height_spin != null else 48.0
	var rot_deg: float = _token_rotation_spin.value if _token_rotation_spin != null else 0.0
	var shape_val: int = _token_shape_option.get_selected_id() if _token_shape_option != null else 0
	var blos_val: bool = _token_blocks_los_check.button_pressed if _token_blocks_los_check != null else true

	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var tm: TokenManager = registry.token

	var existing: TokenData = tm.get_token_by_id(_token_editor_id)
	# Capture before-state for edit undo (null when creating a new token).
	var old_snapshot: TokenData = TokenData.from_dict(existing.to_dict()) if existing != null else null

	var data: TokenData
	if existing != null:
		data = existing
	else:
		data = TokenData.new()
		data.id = _token_editor_id if not _token_editor_id.is_empty() else TokenData.generate_id()
		if _token_editor_dialog != null and _token_editor_dialog.has_meta("pending_world_pos"):
			data.world_pos = _token_editor_dialog.get_meta("pending_world_pos") as Vector2

	data.label = label_text
	data.category = category
	data.is_visible_to_players = is_vis
	data.perception_dc = perc_dc
	data.auto_reveal = do_auto_reveal
	data.autopause = do_ap
	data.autopause_max_triggers = max_triggers
	data.autopause_on_collision = do_ap_collision
	data.trigger_radius_px = trigger_px
	data.pause_on_interact = do_pi
	data.notes = notes_text
	data.puzzle_notes = p_notes
	data.width_px = w_px
	data.height_px = h_px
	data.rotation_deg = rot_deg
	data.token_shape = shape_val
	data.blocks_los = blos_val

	if existing != null:
		tm.update_token(data)
		if _map_view != null:
			_map_view.update_token_sprite(data)
	else:
		tm.add_token(data)
		if _map_view != null:
			_map_view.add_token_sprite(data, true)

	if _map_view != null:
		_map_view.apply_token_passthrough_state(data)

	# Push undo command.
	if registry.history != null:
		var new_snapshot: TokenData = TokenData.from_dict(data.to_dict())
		var mv := _map_view
		if old_snapshot != null:
			# Edit existing token.
			registry.history.push_command(HistoryCommand.create("Token edited",
				func():
					var td: TokenData = tm.get_token_by_id(old_snapshot.id)
					if td == null: return
					var restored := TokenData.from_dict(old_snapshot.to_dict())
					tm.update_token(restored)
					if mv != null: mv.update_token_sprite(restored); mv.apply_token_passthrough_state(restored)
					_broadcast_token_change(restored, false)
					_broadcast_puzzle_notes_state(),
				func():
					var td: TokenData = tm.get_token_by_id(new_snapshot.id)
					if td == null: return
					var reapplied := TokenData.from_dict(new_snapshot.to_dict())
					tm.update_token(reapplied)
					if mv != null: mv.update_token_sprite(reapplied); mv.apply_token_passthrough_state(reapplied)
					_broadcast_token_change(reapplied, false)
					_broadcast_puzzle_notes_state()))
		else:
			# New token creation.
			var new_id := new_snapshot.id
			registry.history.push_command(HistoryCommand.create("Token added",
				func():
					tm.remove_token(new_id)
					if mv != null: mv.remove_token_sprite(new_id)
					_nm_broadcast_to_displays({"msg": "token_removed", "token_id": new_id,
						"puzzle_notes": _collect_revealed_puzzle_notes()})
					_broadcast_puzzle_notes_state(),
				func():
					var readd := TokenData.from_dict(new_snapshot.to_dict())
					tm.add_token(readd)
					if mv != null: mv.add_token_sprite(readd, true); mv.apply_token_passthrough_state(readd)
					_broadcast_token_change(readd, true)
					_broadcast_puzzle_notes_state()))

	# Broadcast to player displays.
	_broadcast_token_change(data, existing == null)
	_broadcast_puzzle_notes_state()


func _on_token_visibility_changed(id: String, is_visible: bool) -> void:
	## Refresh sprite and broadcast.
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var data: TokenData = registry.token.get_token_by_id(id)
	if data == null:
		return
	if _map_view != null:
		_map_view.update_token_sprite(data)
	if is_visible:
		_nm_broadcast_to_displays({
			"msg": "token_added",
			"token": data.to_dict(),
		})
	else:
		_nm_broadcast_to_displays({"msg": "token_removed", "token_id": id})


## Broadcast a single-token change to all connected display clients.
func _broadcast_token_change(data: TokenData, is_new: bool) -> void:
	# DOOR and SECRET_PASSAGE tokens affect wall/passthrough geometry on the
	# player display, so they must always be broadcast regardless of token
	# visibility.  Other token categories are only sent when visible.
	var is_passthrough_category: bool = (
		data.category == TokenData.TokenCategory.DOOR
		or data.category == TokenData.TokenCategory.SECRET_PASSAGE
	)
	if not data.is_visible_to_players and not is_passthrough_category:
		return
	var msg_type: String = "token_added" if is_new else "token_updated"
	_nm_broadcast_to_displays({"msg": msg_type, "token": data.to_dict(),
		"puzzle_notes": _collect_revealed_puzzle_notes()})


## Collect all revealed puzzle notes from every token (regardless of visibility).
func _collect_revealed_puzzle_notes() -> Array:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return []
	var notes: Array = []
	for raw in registry.token.get_all_tokens():
		var td: TokenData = raw as TokenData
		if td == null:
			continue
		for note_raw: Variant in td.puzzle_notes:
			if not note_raw is Dictionary:
				continue
			var d := note_raw as Dictionary
			if not bool(d.get("revealed", false)):
				continue
			var text: String = str(d.get("text", ""))
			if text.is_empty():
				continue
			notes.append({"label": td.label, "text": text})
	return notes


## Broadcast all revealed puzzle notes to player displays.
## Notes are independent of token visibility — hidden tokens can still have
## revealed notes that should appear on the player screen.
func _broadcast_puzzle_notes_state() -> void:
	_nm_broadcast_to_displays({"msg": "puzzle_notes_state",
		"puzzle_notes": _collect_revealed_puzzle_notes()})


## Broadcast the full visible-token snapshot (called on initial client connect
## or after a map load that includes pre-existing tokens).
func _broadcast_measurement_state() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	var all_m: Array = registry.measurement.get_all()
	var dicts: Array = []
	for raw in all_m:
		var md: MeasurementData = raw as MeasurementData
		if md != null:
			dicts.append(md.to_dict())
	_nm_broadcast_to_displays({"msg": "measurement_state", "measurements": dicts})


func _on_measurement_draw_completed(data: MeasurementData) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	var snapshot: Dictionary = data.to_dict()
	var id: String = data.id
	_meas_apply_add(data)
	if registry.history != null:
		var cmd := HistoryCommand.create("Add measurement",
			func() -> void: _meas_apply_remove(id),
			func() -> void: _meas_apply_add(MeasurementData.from_dict(snapshot)))
		registry.history.push_command(cmd)


func _on_measurement_delete_requested(id: String) -> void:
	if id.is_empty():
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	var existing: MeasurementData = registry.measurement.get_by_id(id)
	if existing == null:
		return
	var snapshot: Dictionary = existing.to_dict()
	_meas_apply_remove(id)
	if registry.history != null:
		var cmd := HistoryCommand.create("Delete measurement",
			func() -> void: _meas_apply_add(MeasurementData.from_dict(snapshot)),
			func() -> void: _meas_apply_remove(id))
		registry.history.push_command(cmd)


func _on_measurement_move_completed(id: String, new_start: Vector2, new_end: Vector2) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	var existing: MeasurementData = registry.measurement.get_by_id(id)
	if existing == null:
		return
	var old_start: Vector2 = existing.world_start
	var old_end: Vector2 = existing.world_end
	_meas_apply_move(id, new_start, new_end)
	if registry.history != null:
		var cmd := HistoryCommand.create("Move measurement",
			func() -> void: _meas_apply_move(id, old_start, old_end),
			func() -> void: _meas_apply_move(id, new_start, new_end))
		registry.history.push_command(cmd)


func _on_measurement_edit_completed(data: MeasurementData, old_start: Vector2, old_end: Vector2) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	var new_snapshot: Dictionary = data.to_dict()
	_meas_apply_update(data)
	if registry.history != null:
		var old_data: MeasurementData = MeasurementData.from_dict(new_snapshot)
		old_data.world_start = old_start
		old_data.world_end = old_end
		var old_snapshot: Dictionary = old_data.to_dict()
		var cmd := HistoryCommand.create("Edit measurement",
			func() -> void: _meas_apply_update(MeasurementData.from_dict(old_snapshot)),
			func() -> void: _meas_apply_update(MeasurementData.from_dict(new_snapshot)))
		registry.history.push_command(cmd)


func _mark_map_dirty() -> void:
	## Flush measurements back into MapData so the next save includes them.
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.map == null:
		return
	var map: MapData = registry.map.get_map() as MapData
	if map == null:
		return
	var all_m: Array = []
	if registry.measurement != null:
		for raw in registry.measurement.get_all():
			var md: MeasurementData = raw as MeasurementData
			if md != null:
				all_m.append(md.to_dict())
	map.measurements = all_m


# ---------------------------------------------------------------------------
# Measurement undo/redo apply helpers
# ---------------------------------------------------------------------------

func _meas_apply_add(data: MeasurementData) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	registry.measurement.add(data)
	if _map_view != null and _map_view.measurement_overlay != null:
		_map_view.measurement_overlay.add_or_update(data)
	_nm_broadcast_to_displays({"msg": "measurement_added", "measurement": data.to_dict()})
	_refresh_measure_shape_list()
	_mark_map_dirty()


func _meas_apply_remove(id: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	registry.measurement.remove(id)
	if _map_view != null and _map_view.measurement_overlay != null:
		_map_view.measurement_overlay.remove_shape(id)
	_nm_broadcast_to_displays({"msg": "measurement_removed", "measurement_id": id})
	_refresh_measure_shape_list()
	_mark_map_dirty()


func _meas_apply_move(id: String, new_start: Vector2, new_end: Vector2) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	registry.measurement.move(id, new_start, new_end)
	if _map_view != null and _map_view.measurement_overlay != null:
		var md: MeasurementData = registry.measurement.get_by_id(id)
		if md != null:
			_map_view.measurement_overlay.add_or_update(md)
	_nm_broadcast_to_displays({
		"msg": "measurement_moved",
		"measurement_id": id,
		"world_start": {"x": new_start.x, "y": new_start.y},
		"world_end": {"x": new_end.x, "y": new_end.y},
	})
	_refresh_measure_shape_list()
	_mark_map_dirty()


func _meas_apply_update(data: MeasurementData) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	registry.measurement.update(data)
	if _map_view != null and _map_view.measurement_overlay != null:
		_map_view.measurement_overlay.add_or_update(data)
	_nm_broadcast_to_displays({"msg": "measurement_updated", "measurement": data.to_dict()})
	_refresh_measure_shape_list()
	_mark_map_dirty()


func _meas_apply_clear() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	registry.measurement.clear()
	if _map_view != null and _map_view.measurement_overlay != null:
		_map_view.measurement_overlay.clear()
	_nm_broadcast_to_displays({"msg": "measurement_state", "measurements": []})
	_refresh_measure_shape_list()
	_mark_map_dirty()


func _meas_apply_restore(snapshots: Array) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	for raw in snapshots:
		var d: Dictionary = raw as Dictionary
		if d.is_empty():
			continue
		var md: MeasurementData = MeasurementData.from_dict(d)
		registry.measurement.add(md)
		if _map_view != null and _map_view.measurement_overlay != null:
			_map_view.measurement_overlay.add_or_update(md)
	_broadcast_measurement_state()
	_refresh_measure_shape_list()
	_mark_map_dirty()


# ---------------------------------------------------------------------------
# Measurement panel
# ---------------------------------------------------------------------------

func _open_measure_panel() -> void:
	if _measure_panel != null and is_instance_valid(_measure_panel):
		_measure_panel.grab_focus()
		return
	_measure_panel = Window.new()
	_measure_panel.title = "Measurement Tools"
	_measure_panel.close_requested.connect(func() -> void:
		if _measure_panel != null: _measure_panel.hide())
	add_child(_measure_panel)
	_build_measure_panel_contents()
	var mgr := _get_ui_scale_mgr()
	if mgr != null:
		mgr.popup_fitted(_measure_panel, 260.0, 420.0)
	else:
		_measure_panel.popup_centered()


func _build_measure_panel_contents() -> void:
	if _measure_panel == null:
		return
	var mgr := _get_ui_scale_mgr()
	var root := VBoxContainer.new()
	var margin := MarginContainer.new()
	var m: int = mgr.scaled(8.0) if mgr != null else 8
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, m)
	margin.add_child(root)
	_measure_panel.add_child(margin)

	# Tool buttons
	var title_lbl := Label.new()
	title_lbl.text = "Draw Tool"
	if mgr != null:
		title_lbl.add_theme_font_size_override("font_size", mgr.scaled(13.0))
	root.add_child(title_lbl)

	_measure_tool_group = ButtonGroup.new()
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	root.add_child(btn_row)

	const TOOL_DEFS: Array = [
		["╌", "Line", "measure_line"],
		["◯", "Circle (radius)", "measure_circle"],
		["◁", "Cone (D&D 5e)", "measure_cone"],
		["□", "Square (rotatable)", "measure_square"],
		["▭", "Rectangle", "measure_rect"],
	]
	for def in TOOL_DEFS:
		var lbl: String = str(def[0])
		var tt: String = str(def[1])
		var key: String = str(def[2])
		var btn := Button.new()
		btn.text = lbl
		btn.tooltip_text = tt
		btn.toggle_mode = true
		btn.button_group = _measure_tool_group
		btn.focus_mode = Control.FOCUS_NONE
		if mgr != null:
			btn.custom_minimum_size = Vector2(mgr.scaled(34.0), mgr.scaled(34.0))
			btn.add_theme_font_size_override("font_size", mgr.scaled(18.0))
		var k := key # capture
		btn.pressed.connect(func(): _on_measure_tool_btn_pressed(k))
		btn_row.add_child(btn)

	root.add_child(HSeparator.new())

	# Active shapes list
	var shapes_lbl := Label.new()
	shapes_lbl.text = "Active shapes"
	if mgr != null:
		shapes_lbl.add_theme_font_size_override("font_size", mgr.scaled(13.0))
	root.add_child(shapes_lbl)

	_measure_shape_list = ItemList.new()
	var list_h: int = mgr.scaled(140.0) if mgr != null else 140
	_measure_shape_list.custom_minimum_size = Vector2(0, list_h)
	_measure_shape_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_measure_shape_list.focus_mode = Control.FOCUS_NONE
	_measure_shape_list.item_selected.connect(_on_measure_shape_selected)
	root.add_child(_measure_shape_list)
	_refresh_measure_shape_list()

	# Action buttons row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	root.add_child(action_row)

	var del_btn := Button.new()
	del_btn.text = "Delete Selected"
	del_btn.focus_mode = Control.FOCUS_NONE
	if mgr != null:
		mgr.scale_button(del_btn)
	del_btn.pressed.connect(_on_measure_delete_selected_pressed)
	action_row.add_child(del_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear All"
	clear_btn.focus_mode = Control.FOCUS_NONE
	if mgr != null:
		mgr.scale_button(clear_btn, 80.0)
	clear_btn.pressed.connect(_on_measure_clear_all_pressed)
	action_row.add_child(clear_btn)


## Wire measure signals from MapView (called after MapView is ready).
func _wire_measure_signals() -> void:
	if _map_view == null:
		return
	if not _map_view.is_connected("measurement_draw_completed",
			Callable(self , "_on_measurement_draw_completed")):
		_map_view.measurement_draw_completed.connect(_on_measurement_draw_completed)
	if not _map_view.is_connected("measurement_delete_requested",
			Callable(self , "_on_measurement_delete_requested")):
		_map_view.measurement_delete_requested.connect(_on_measurement_delete_requested)
	if not _map_view.is_connected("measurement_move_completed",
			Callable(self , "_on_measurement_move_completed")):
		_map_view.measurement_move_completed.connect(_on_measurement_move_completed)
	if not _map_view.is_connected("measurement_edit_completed",
			Callable(self , "_on_measurement_edit_completed")):
		_map_view.measurement_edit_completed.connect(_on_measurement_edit_completed)


func _on_measure_tool_btn_pressed(key: String) -> void:
	if _map_view == null:
		return
	_map_view.set_fog_tool(0, 64.0)
	match key:
		"measure_line":
			_map_view._set_active_tool(_map_view.Tool.MEASURE_LINE)
			_set_status("Measure: Line — click and drag to draw")
		"measure_circle":
			_map_view._set_active_tool(_map_view.Tool.MEASURE_CIRCLE)
			_set_status("Measure: Circle — drag from centre to edge")
		"measure_cone":
			_map_view._set_active_tool(_map_view.Tool.MEASURE_CONE)
			_set_status("Measure: Cone (D&D 5e RAW) — drag apex to length")
		"measure_square":
			_map_view._set_active_tool(_map_view.Tool.MEASURE_SQUARE)
			_set_status("Measure: Square — drag to set size and rotation")
		"measure_rect":
			_map_view._set_active_tool(_map_view.Tool.MEASURE_RECT)
			_set_status("Measure: Rectangle — drag to set length, width = half length")


func _on_measure_clear_all_pressed() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	var all_m: Array = registry.measurement.get_all()
	if all_m.is_empty():
		return
	var snapshots: Array = []
	for raw in all_m:
		var md: MeasurementData = raw as MeasurementData
		if md != null:
			snapshots.append(md.to_dict())
	_meas_apply_clear()
	if registry.history != null:
		var cmd := HistoryCommand.create("Clear all measurements",
			func() -> void: _meas_apply_restore(snapshots),
			func() -> void: _meas_apply_clear())
		registry.history.push_command(cmd)


func _on_measure_shape_selected(idx: int) -> void:
	if _measure_shape_list == null:
		return
	var shape_id: String = str(_measure_shape_list.get_item_metadata(idx))
	if _map_view != null and _map_view.measurement_overlay != null:
		_map_view.measurement_overlay.set_selected(shape_id)


func _on_measure_delete_selected_pressed() -> void:
	if _measure_shape_list == null:
		return
	var selected_items: PackedInt32Array = _measure_shape_list.get_selected_items()
	if selected_items.is_empty():
		return
	var shape_id: String = str(_measure_shape_list.get_item_metadata(selected_items[0]))
	if shape_id.is_empty():
		return
	_on_measurement_delete_requested(shape_id)


func _refresh_measure_shape_list() -> void:
	if _measure_shape_list == null or not is_instance_valid(_measure_shape_list):
		return
	_measure_shape_list.clear()
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	const SHAPE_NAMES: Array = ["Line", "Circle", "Cone", "Square", "Rect"]
	for raw in registry.measurement.get_all():
		var md: MeasurementData = raw as MeasurementData
		if md == null:
			continue
		var dist_px: float = md.world_start.distance_to(md.world_end)
		var px_per_5ft: float = _pixels_per_5ft_current()
		var ft: int = roundi(dist_px / (px_per_5ft / 5.0))
		var shape_name: String = SHAPE_NAMES[clamp(md.shape_type, 0, SHAPE_NAMES.size() - 1)]
		var item_text: String = "%s: %d ft" % [shape_name, ft]
		var idx: int = _measure_shape_list.add_item(item_text)
		_measure_shape_list.set_item_metadata(idx, md.id)


func _broadcast_token_state() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var visible: Array = registry.token.get_visible_tokens()
	var dicts: Array = []
	for raw in visible:
		var td: TokenData = raw as TokenData
		if td != null:
			dicts.append(td.to_dict())
	# Include non-visible DOOR and SECRET_PASSAGE tokens so the player display
	# can rebuild wall/passthrough geometry even for tokens the player can't see.
	for raw in registry.token.get_all_tokens():
		var td: TokenData = raw as TokenData
		if td == null or td.is_visible_to_players:
			continue
		if td.category == TokenData.TokenCategory.DOOR \
				or td.category == TokenData.TokenCategory.SECRET_PASSAGE:
			dicts.append(td.to_dict())
	_nm_broadcast_to_displays({"msg": "token_state", "tokens": dicts,
		"puzzle_notes": _collect_revealed_puzzle_notes()})


# ---------------------------------------------------------------------------
# Player action handler (Phase 4)
# ---------------------------------------------------------------------------

func _on_player_action(player_id: Variant, action: String) -> void:
	var pid: String = str(player_id)
	if action == "dash":
		_apply_profile_bindings()
		_broadcast_player_state()
	elif action == "interact":
		_handle_interact_action(pid)


func _handle_interact_action(player_id: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	if _backend == null:
		return
	var token_nodes: Dictionary = _backend.get_dm_token_nodes()
	var node: Node2D = token_nodes.get(player_id, null) as Node2D
	if node == null or not is_instance_valid(node):
		return
	var nearby: Array = registry.token.check_interact_proximity(node.global_position)
	if nearby.is_empty():
		return
	var gs: GameStateManager = _game_state()
	if gs != null:
		gs.lock_player(player_id)
		_set_status("Interact — %s paused near token" % player_id)
		_broadcast_player_state()


## Collect player world positions and passive perceptions, then ask TokenService
## to auto-reveal any tokens whose perception DC is met.  Called every
## _PERCEPTION_CHECK_INTERVAL seconds from _process.
func _run_perception_check() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	# Gather player positions from live DM token nodes (same source MapView uses).
	var positions: Array = []
	var perceptions: Array = []
	var player_ids: Array = []
	if _backend != null:
		var token_nodes: Dictionary = _backend.get_dm_token_nodes()
		for pid in token_nodes.keys():
			var node: Node2D = token_nodes[pid] as Node2D
			if node == null or not is_instance_valid(node):
				continue
			positions.append(node.global_position)
			player_ids.append(str(pid))
			# Look up passive perception from the profile service.
			var pp: int = 10 ## default if profile not found
			if registry.profile != null:
				var prof: Variant = registry.profile.get_profile_by_id(str(pid))
				if prof is PlayerProfile:
					var p_prof := prof as PlayerProfile
					pp = p_prof.get_passive_perception()
					var im: InputManager = registry.input if registry.input != null else null
					if im != null and im.is_dashing(str(pid)):
						pp = floori(float(pp) / 2.0)
			perceptions.append(pp)
	if positions.is_empty():
		return
	var newly_revealed: Array = registry.token.check_perception_proximity(positions, perceptions)
	for id in newly_revealed:
		_on_token_visibility_changed(str(id), true)

	# --- Autopause proximity (Phase 3) ---
	var gs: GameStateManager = _game_state()
	if gs != null:
		var paused_ids: Array = registry.token.check_autopause_proximity(positions, player_ids)
		for pid in paused_ids:
			var pid_s: String = str(pid)
			if _autopause_locked_ids.has(pid_s):
				continue
			_autopause_locked_ids[pid_s] = true
			gs.lock_player(pid_s)
			_set_status("Autopause — %s paused by proximity trigger" % pid_s)
		_broadcast_player_state()

	# --- Detection exclamation (Phase 6) ---
	var new_detected: Array = registry.token.check_detection_proximity(positions, player_ids, perceptions)
	# Diff against previous detection set and broadcast changes.
	for tid in new_detected:
		var tid_s: String = str(tid)
		if not _detected_token_ids.has(tid_s):
			_nm_broadcast_to_displays({"msg": "token_detected", "token_id": tid_s})
	for tid_s in _detected_token_ids:
		if not new_detected.has(tid_s):
			_nm_broadcast_to_displays({"msg": "token_undetected", "token_id": tid_s})
	_detected_token_ids = new_detected


func _on_profile_import_pressed() -> void:
	if _profiles_import_dialog == null:
		return
	_profiles_import_dialog.current_file = "profiles.json"
	_profiles_import_dialog.popup_centered(Vector2i(900, 600))


func _on_profile_export_pressed() -> void:
	if _profiles_export_dialog == null:
		return
	_profiles_export_dialog.current_file = "profiles-export.json"
	_profiles_export_dialog.popup_centered(Vector2i(900, 600))


func _on_profiles_export_path_selected(path: String) -> void:
	var target_path := path
	if not target_path.to_lower().ends_with(".json"):
		target_path += ".json"
	var parent_dir := target_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_dir):
		var mk_err := DirAccess.make_dir_recursive_absolute(parent_dir)
		if mk_err != OK:
			_set_status("Export failed: could not create directory.")
			return
	# Use Persistence service for direct export when available.
	var export_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if export_reg != null and export_reg.persistence != null:
		var payload := {"profiles": _profiles_to_array()}
		if export_reg.persistence.save_game("profiles_export", payload) and export_reg.persistence.export_to_path("profiles_export", target_path):
			export_reg.persistence.delete_save("profiles_export")
			_set_status("Exported %d profiles." % payload["profiles"].size())
			return
	# Fallback: write directly to the chosen path
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_set_status("Export failed: could not write file.")
		return
	file.store_string(JSON.stringify(_profiles_to_array(), "\t"))
	file.close()
	var pm := _profile_service()
	var count := pm.get_profiles().size() if pm != null else 0
	_set_status("Exported %d profiles." % count)


func _on_profiles_import_path_selected(path: String) -> void:
	var parsed: Variant = null
	# If the selected path is under user:// and Persistence is available prefer it
	var import_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if path.begins_with("user://") and import_reg != null and import_reg.persistence != null:
		var save_name := path.get_file().get_basename()
		var loaded: Dictionary = import_reg.persistence.load_game(save_name)
		if loaded.has("profiles"):
			parsed = loaded["profiles"]
		elif not loaded.is_empty():
			parsed = loaded
	if parsed == null:
		if not FileAccess.file_exists(path):
			_set_status("Import failed: file not found.")
			return
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_set_status("Import failed: could not read file.")
			return
		var text := file.get_as_text()
		file.close()
		parsed = JsonUtilsScript.parse_json_text(text)
	if parsed == null or not parsed is Array:
		_set_status("Import failed: JSON must be an array of profiles.")
		return
	var imported_profiles: Array = []
	for item in parsed:
		if not item is Dictionary:
			continue
		imported_profiles.append(PlayerProfile.from_dict(item as Dictionary))
	if imported_profiles.is_empty():
		_set_status("Import skipped: no valid profiles found.")
		return
	var pm := _profile_service()
	if pm != null:
		pm.set_all_profiles(imported_profiles)
	_profile_selected_index = 0
	_refresh_profiles_list()
	_set_status("Imported %d profiles." % imported_profiles.size())


func _profiles_to_array() -> Array:
	var out: Array = []
	var pm := _profile_service()
	var profiles_arr: Array = pm.get_profiles() if pm != null else []
	for profile in profiles_arr:
		if profile is PlayerProfile:
			(profile as PlayerProfile).ensure_id()
			out.append((profile as PlayerProfile).to_dict())
	return out


# ---------------------------------------------------------------------------
# File — New Map / Open Map / Save / Save As
# ---------------------------------------------------------------------------

func _on_new_map_pressed() -> void:
	## Step 1: DM picks a source image.
	_file_dialog.title = "Select Map Image to Import"
	_file_dialog.popup_centered(Vector2i(900, 600))


func _on_image_selected(path: String) -> void:
	## Step 2: Store the image path, then open the native Save panel so the DM
	## chooses the .map bundle path.
	_pending_image_path = path
	_map_name_mode = "new"
	_save_as_dialog.current_file = path.get_file().get_basename() + ".map"
	_save_as_dialog.current_dir = _maps_dir_abs()
	_save_as_dialog.popup_centered(Vector2i(900, 600))


func _on_save_as_path_selected(path: String) -> void:
	## Normalise the chosen path to a .map bundle path and proceed.
	var bundle_path := _normalise_bundle_path(path)
	var map_name: String = bundle_path.get_file().get_basename().strip_edges()
	if map_name.is_empty():
		_set_status("Invalid map name — please try again.")
		return
	map_name = map_name.replace("/", "_").replace("\\", "_")

	match _map_name_mode:
		"new":
			_create_map_from_image(_pending_image_path, bundle_path)
		"save_as":
			_save_map_as_path(bundle_path)


func _create_map_from_image(src_path: String, bundle_path: String) -> void:
	_ensure_bundle_dir(bundle_path)
	var ext: String = src_path.get_extension().to_lower()
	var img_dest_abs: String = _image_dest_path_abs(bundle_path, ext)

	var copy_err := _copy_file(src_path, img_dest_abs)
	var new_map_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if new_map_reg != null and new_map_reg.persistence != null:
		copy_err = new_map_reg.persistence.copy_file(src_path, img_dest_abs) as Error
	if copy_err != OK:
		push_error("DMWindow: failed to copy image to '%s' (err %d)" % [img_dest_abs, copy_err])
		_set_status("Error: could not copy image.")
		return

	var map := MapData.new()
	map.map_name = bundle_path.get_file().get_basename()
	map.image_path = img_dest_abs
	_active_map_bundle_path = bundle_path
	_save_map_data(map)
	_apply_map(map)
	# Keep map manager model in sync if available
	var ms := _map_service()
	if ms != null:
		ms.update(map)
	_nm_broadcast_map(map)
	_set_status("New map: %s" % map.map_name)


func _on_open_map_pressed() -> void:
	## Open a previously saved .map file.
	_ensure_maps_dir()
	_open_map_dialog.current_dir = _maps_dir_abs()
	_open_map_dialog.popup_centered(Vector2i(900, 600))


func _on_map_bundle_selected(path: String) -> void:
	## Load the map stored inside the selected .map bundle.
	## Accepts direct bundle selection, map.json selection, or a child file inside
	## a bundle by walking up to the nearest parent ending in ".map".
	var bundle_path := _resolve_bundle_path(path)
	if bundle_path.is_empty():
		_set_status("Failed to load map: selected path is not a valid .map bundle.")
		return
	var map: MapData = null
	var ms := _map_service()
	# load_from_bundle calls MapService.load_map → _sync_tokens_from_map, so
	# TokenService is populated before _apply_map reads it for sprite creation.
	if ms != null and ms.service != null:
		map = ms.load_from_bundle(bundle_path)
	else:
		map = _load_map_from_bundle(bundle_path)
		if map != null and ms != null:
			ms.load(map)
	if map == null:
		_set_status("Failed to load map from: %s" % bundle_path.get_file())
		return
	_active_map_bundle_path = bundle_path
	_apply_map(map)
	_nm_broadcast_map(map)
	_set_status("Opened: %s" % map.map_name)


func _on_save_map_pressed() -> void:
	var map: MapData = _map()
	if map == null:
		_set_status("Nothing to save.")
		return
	if _active_map_bundle_path.is_empty():
		_on_save_map_as_pressed()
		return
	_map_view.save_camera_to_map()
	_save_map_data(map)
	var ms := _map_service()
	if ms != null:
		ms.update(map)
	_nm_broadcast_map_update(map)
	_set_status("Saved: %s" % map.map_name)


func _on_save_map_as_pressed() -> void:
	var map: MapData = _map()
	if map == null:
		_set_status("Nothing to save.")
		return
	_map_name_mode = "save_as"
	_save_as_dialog.current_file = map.map_name + ".map"
	_save_as_dialog.current_dir = _active_map_bundle_path.get_base_dir() if not _active_map_bundle_path.is_empty() else _maps_dir_abs()
	_save_as_dialog.popup_centered(Vector2i(900, 600))


# ---------------------------------------------------------------------------
# Save / Load Game
# ---------------------------------------------------------------------------

func _on_save_game_pressed() -> void:
	## Quick-save: overwrite the current .sav bundle, or fall through to Save As.
	if _active_save_bundle_path.is_empty():
		_on_save_game_as_pressed()
		return
	var save_name := _active_save_bundle_path.get_file().get_basename()
	await _save_game_to_bundle(save_name)


func _on_save_game_as_pressed() -> void:
	if _map() == null:
		_set_status("No map loaded — nothing to save.")
		return
	var dir := _saves_dir_abs()
	DirAccess.make_dir_recursive_absolute(dir)
	_save_game_dialog.current_dir = dir
	var map := _map()
	_save_game_dialog.current_file = (map.map_name if map != null else "game") + ".sav"
	_save_game_dialog.popup_centered(Vector2i(900, 600))


func _on_save_game_path_selected(path: String) -> void:
	## Called after the Save Game As dialog confirms a path.
	var save_name := path.get_file().get_basename()
	await _save_game_to_bundle(save_name)


func _save_game_to_bundle(save_name: String) -> void:
	var map := _map()
	if map == null:
		_set_status("No map loaded — nothing to save.")
		return
	if _active_map_bundle_path.is_empty():
		_set_status("Save the map first before saving a game session.")
		return

	# Ensure latest fog is flushed
	if _map_view != null:
		_map_view.force_fog_sync()
	_map_view.save_camera_to_map()

	# Collect fog as Image for the .sav bundle
	var fog_image: Image = null
	if _map_view != null:
		var fog_png: PackedByteArray = await _map_view.get_fog_state()
		if not fog_png.is_empty():
			fog_image = Image.new()
			fog_image.load_png_from_buffer(fog_png)

	# Sync player camera into model before saving
	var gs := _game_state()
	if gs != null:
		gs.player_camera_position = _player_cam_pos
		gs.player_camera_zoom = _player_cam_zoom
		gs.player_camera_rotation = _player_cam_rotation

	# Persist the session.  save_game_bundle copies the original .map bundle
	# into the .sav, then we overwrite the embedded map.json with the latest
	# token state.  This keeps the original .map untouched — only Save Map
	# should write there.
	var ms := _map_service()
	if gs != null:
		var ok := gs.save_session(save_name, fog_image, _active_map_bundle_path)
		if ok:
			_active_save_bundle_path = _saves_dir_abs().path_join(save_name + ".sav")
			# Flush current token state into the EMBEDDED map.json inside the
			# .sav bundle (not the original .map).
			if ms != null:
				var embedded_map_path: String = _active_save_bundle_path.path_join("map.map")
				ms.save_to_bundle(embedded_map_path)
			_set_status("Game saved: %s" % save_name)
		else:
			_set_status("Error: failed to save game.")
	else:
		_set_status("Error: game state service unavailable.")


func _on_load_game_pressed() -> void:
	if _game_state() == null:
		_set_status("Error: game state service unavailable.")
		return
	var dir := _saves_dir_abs()
	DirAccess.make_dir_recursive_absolute(dir)
	_load_game_dialog.current_dir = dir
	_load_game_dialog.popup_centered(Vector2i(900, 600))


func _on_load_game_path_selected(path: String) -> void:
	## Called when the user picks a .sav bundle from the Load Game dialog.
	var bundle_path := path
	# Walk up to the nearest .sav directory if needed.
	while not bundle_path.is_empty() and not bundle_path.ends_with(".sav"):
		var parent := bundle_path.get_base_dir()
		if parent == bundle_path:
			break
		bundle_path = parent
	if not bundle_path.ends_with(".sav"):
		_set_status("Invalid save bundle: %s" % path.get_file())
		return

	var gs := _game_state()
	if gs == null:
		_set_status("Error: game state service unavailable.")
		return

	var bundle: Dictionary = gs.load_session(bundle_path)
	if bundle.is_empty():
		_set_status("Failed to load game from: %s" % bundle_path.get_file())
		return

	# Extract loaded data
	var state_val: Variant = bundle.get("state", null)
	var fog_image: Variant = bundle.get("fog_image", null)
	var map_bundle: String = bundle.get("map_bundle_path", "") as String

	# Load the embedded map
	if not map_bundle.is_empty():
		var map: MapData = null
		var ms := _map_service()
		# load_from_bundle calls MapService.load_map → _sync_tokens_from_map, so
		# TokenService is populated before we apply session overrides below.
		if ms != null and ms.service != null:
			map = ms.load_from_bundle(map_bundle)
		else:
			map = _load_map_from_bundle(map_bundle)
			if map != null and ms != null:
				ms.load(map)
		if map != null:
			# ── Apply token visibility overrides BEFORE _apply_map so that the
			# sprites created there already reflect the saved session state.
			# token_states is the authoritative session record; map.json is a
			# best-effort copy that may lag if save_map_to_bundle failed.
			if state_val != null:
				var ts: Variant = state_val.token_states
				if ts is Dictionary and not (ts as Dictionary).is_empty():
					var tok_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
					if tok_reg != null and tok_reg.token != null:
						for tid_var in (ts as Dictionary).keys():
							var tstate: Variant = (ts as Dictionary)[tid_var]
							if tstate is Dictionary:
								tok_reg.token.set_token_visibility(
										str(tid_var),
										bool((tstate as Dictionary).get("is_visible_to_players", false)))
			# Resolve the active map bundle path for future Save Map writes.
			# Priority: 1) standard maps dir by name  2) recorded original
			# path if it is NOT inside the saves dir  3) embedded copy.
			var maps_candidate: String = _bundle_dir_abs(map.map_name) if not map.map_name.is_empty() else ""
			var saves_dir: String = _saves_dir_abs()
			if not maps_candidate.is_empty() and DirAccess.dir_exists_absolute(maps_candidate):
				_active_map_bundle_path = maps_candidate
			else:
				var recorded_path: String = "" if state_val == null else str(state_val.map_bundle_path)
				var resolved_path: String = ProjectSettings.globalize_path(recorded_path) if not recorded_path.is_empty() else ""
				if not resolved_path.is_empty() and DirAccess.dir_exists_absolute(resolved_path) and not resolved_path.begins_with(saves_dir):
					_active_map_bundle_path = recorded_path
				else:
					_active_map_bundle_path = map_bundle
			_apply_map(map, true)

	# Restore fog from the saved image
	if fog_image is Image and not (fog_image as Image).is_empty():
		var png_buf: PackedByteArray = (fog_image as Image).save_png_to_buffer()
		if not png_buf.is_empty() and _map_view != null:
			_map_view.apply_fog_snapshot(png_buf)

	# Restore player camera from save
	if state_val != null:
		_player_cam_pos = state_val.player_camera_position
		_player_cam_zoom = state_val.player_camera_zoom
		_player_cam_rotation = state_val.player_camera_rotation
		_update_viewport_indicator()

	# Sync restored player positions to backend tokens
	if _backend != null:
		_backend.sync_profiles()
	if _map_view != null and _backend != null:
		_map_view.set_draggable_tokens(_backend.get_dm_token_nodes())

	_active_save_bundle_path = bundle_path

	# Broadcast everything to connected displays.
	# _broadcast_token_state is called last so player displays receive the
	# fully-resolved visibility state (after all overrides are applied).
	_broadcast_player_viewport()
	_broadcast_fog_state()
	_broadcast_player_state()
	_broadcast_token_state()

	var save_label := bundle_path.get_file().get_basename()
	_set_status("Game loaded: %s" % save_label)


func _save_map_as_path(bundle_path: String) -> void:
	## Copy the current map into a new .map bundle and switch to it.
	var map: MapData = _map()
	if map == null:
		return
	_ensure_bundle_dir(bundle_path)
	var ext: String = map.image_path.get_extension().to_lower()
	var new_img_abs: String = _image_dest_path_abs(bundle_path, ext)

	# Only copy image if destination is different from source.
	if new_img_abs != map.image_path:
		var copy_err := _copy_file(map.image_path, new_img_abs)
		var save_as_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if save_as_reg != null and save_as_reg.persistence != null:
			copy_err = save_as_reg.persistence.copy_file(map.image_path, new_img_abs) as Error
		if copy_err != OK:
			push_error("DMWindow: failed to copy image for save-as (err %d)" % copy_err)
			_set_status("Error: could not duplicate image.")
			return

	_map_view.save_camera_to_map()
	map.map_name = bundle_path.get_file().get_basename()
	map.image_path = new_img_abs
	_active_map_bundle_path = bundle_path
	_save_map_data(map)
	var ms := _map_service()
	if ms != null:
		ms.update(map)
	_nm_broadcast_map_update(map)
	_set_status("Saved as: %s" % map.map_name)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _apply_map(map: MapData, from_save: bool = false) -> void:
	# ── Clear per-map transient state so nothing leaks between maps ──────
	_detected_token_ids.clear()
	_autopause_locked_ids.clear()
	_token_editor_id = ""
	_token_context_id = ""
	_selected_passage_token_id = ""
	_initial_sync_ack_pending.clear()
	_initial_sync_attempt_by_peer.clear()
	_broadcast_dirty = false
	_fog_dirty = false
	_fog_snapshot_in_flight = false
	_fog_snapshot_queued = false
	_player_state_dirty = false
	_dm_override_player_id = ""

	# Clear undo history whenever a new map is loaded — history must not span maps.
	var _hreg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _hreg != null and _hreg.history != null:
		_hreg.history.clear()
	if not from_save:
		# Reset game state when opening a map directly (not via Load Game).
		var gs := _game_state()
		if gs != null:
			gs.reset_session()
		_player_cam_rotation = 0
		_active_save_bundle_path = ""
	_map_view.load_map(map)
	if _map_view.map_image.texture == null:
		_set_status("Map image failed to load: %s" % map.image_path)
		return
	if not from_save:
		# Player cam is initialised to the DM's initial view once the camera settles.
		call_deferred("_init_player_cam_from_dm")
	else:
		# Restore the viewport indicator from the saved player camera state.
		_update_viewport_indicator()
	# Load DM-placed token sprites FIRST so that reset_for_new_map can add
	# player sprites into the same layer without being clobbered.
	if _map_view != null:
		var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg != null and reg.token != null:
			var all_tokens: Array = reg.token.get_all_tokens()
			var dicts: Array = []
			for raw in all_tokens:
				var td: TokenData = raw as TokenData
				if td != null:
					dicts.append(td.to_dict())
			_map_view.load_token_sprites(dicts, true)
	if _backend != null:
		_backend.reset_for_new_map()
	if _map_view != null and _backend != null:
		_map_view.set_draggable_tokens(_backend.get_dm_token_nodes())
	if not from_save:
		_broadcast_fog_state()
		_broadcast_player_state()
	# Broadcast visible token state after map load.
	_broadcast_token_state()
	_grid_type_selected = map.grid_type
	_update_grid_submenu_checks()


func _simulate_player_movement(delta: float) -> bool:
	if _backend == null:
		return false
	return bool(_backend.step(delta))


func _keyboard_temp_vector() -> Vector2:
	var vec := Vector2.ZERO
	if Input.is_key_pressed(KEY_LEFT):
		vec.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		vec.x += 1.0
	if Input.is_key_pressed(KEY_UP):
		vec.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		vec.y += 1.0
	if vec == Vector2.ZERO:
		return vec
	return vec.normalized()


func _broadcast_player_state() -> void:
	var players: Array = []
	if _backend != null:
		players = _backend.build_player_state_payload()
	_nm_broadcast_to_displays({"msg": "state", "players": players})


func _update_dm_override_input() -> void:
	var primary_player_id := ""
	var gs := _game_state()
	var profiles_arr: Array = gs.list_profiles() if gs != null else []
	for profile in profiles_arr:
		if profile is PlayerProfile:
			primary_player_id = (profile as PlayerProfile).id
			break

	var input := _input_service()
	if _dm_override_player_id != "" and _dm_override_player_id != primary_player_id:
		if input != null:
			input.clear_dm_vector(_dm_override_player_id)

	_dm_override_player_id = primary_player_id
	if _dm_override_player_id == "":
		return

	if input != null:
		input.set_dm_vector(_dm_override_player_id, _keyboard_temp_vector())


func _on_map_fog_changed(_map_data: MapData) -> void:
	if not _ENABLE_CONTINUOUS_FOG_SYNC:
		_queue_fog_snapshot_sync(_FOG_AUTO_SYNC_DEBOUNCE)
		return
	_fog_dirty = true
	if _fog_countdown <= 0.0:
		_fog_dirty = false
		_broadcast_fog_state()
		_fog_countdown = _FOG_BROADCAST_DEBOUNCE


func _on_map_fog_brush_applied(stroke: Dictionary) -> void:
	var stype: String = str(stroke.get("type", "brush"))
	if stype == "rect":
		var a := stroke.get("a", Vector2.ZERO) as Vector2
		var b := stroke.get("b", Vector2.ZERO) as Vector2
		_nm_broadcast_to_displays({
			"msg": "fog_brush_stroke",
			"type": "rect",
			"a_x": a.x,
			"a_y": a.y,
			"b_x": b.x,
			"b_y": b.y,
			"reveal": bool(stroke.get("reveal", true)),
		})
	else:
		var center := stroke.get("center", Vector2.ZERO) as Vector2
		_nm_broadcast_to_displays({
			"msg": "fog_brush_stroke",
			"type": stype,
			"center_x": center.x,
			"center_y": center.y,
			"radius": float(stroke.get("radius", 0.0)),
			"reveal": bool(stroke.get("reveal", true)),
		})


func _on_map_fog_delta(cell_px: int, revealed_cells: Array, hidden_cells: Array) -> void:
	if not _ENABLE_CONTINUOUS_FOG_SYNC:
		if revealed_cells.is_empty() and hidden_cells.is_empty():
			return
		if revealed_cells.size() + hidden_cells.size() > (_FOG_DELTA_MAX_CELLS * 4):
			_queue_fog_snapshot_sync(_FOG_AUTO_SYNC_DEBOUNCE)
			return
		_broadcast_fog_delta_chunked(cell_px, revealed_cells, hidden_cells)
		return
	if revealed_cells.is_empty() and hidden_cells.is_empty():
		return
	if revealed_cells.size() + hidden_cells.size() > (_FOG_DELTA_MAX_CELLS * 4):
		_fog_dirty = true
		if _fog_countdown <= 0.0:
			_fog_countdown = _FOG_AUTO_SYNC_DEBOUNCE
		return

	_broadcast_fog_delta_chunked(cell_px, revealed_cells, hidden_cells)


func _queue_fog_snapshot_sync(delay: float) -> void:
	_fog_dirty = true
	if _fog_countdown <= 0.0:
		_fog_countdown = delay
	else:
		_fog_countdown = minf(_fog_countdown, delay)


func _manual_fog_sync_now() -> void:
	_fog_dirty = false
	_fog_countdown = 0.0
	_broadcast_fog_state()
	_set_status("Fog sync queued to player displays.")


var _fog_reset_dialog: ConfirmationDialog = null

func _show_fog_reset_confirm() -> void:
	if _fog_reset_dialog == null:
		_fog_reset_dialog = ConfirmationDialog.new()
		_fog_reset_dialog.title = "Reset Fog"
		_fog_reset_dialog.dialog_text = "Reset all fog to fully hidden?\nThis will cover the entire map and cannot be undone."
		_fog_reset_dialog.ok_button_text = "Reset"
		_fog_reset_dialog.confirmed.connect(_on_fog_reset_confirmed)
		add_child(_fog_reset_dialog)
	_fog_reset_dialog.reset_size()
	_fog_reset_dialog.popup_centered()


func _on_fog_reset_confirmed() -> void:
	if _map_view == null:
		return
	_map_view.reset_fog()
	_broadcast_fog_state()
	_set_status("Fog reset — map fully hidden.")


func _broadcast_fog_delta_chunked(cell_px: int, revealed_cells: Array, hidden_cells: Array) -> void:
	var max_cells := maxi(1, _FOG_DELTA_MAX_CELLS)
	var revealed_index := 0
	var hidden_index := 0

	while revealed_index < revealed_cells.size() or hidden_index < hidden_cells.size():
		var budget := max_cells
		var revealed_chunk: Array = []
		var hidden_chunk: Array = []

		if revealed_index < revealed_cells.size():
			var take_revealed := mini(budget, revealed_cells.size() - revealed_index)
			if take_revealed > 0:
				revealed_chunk = revealed_cells.slice(revealed_index, revealed_index + take_revealed)
				revealed_index += take_revealed
				budget -= take_revealed

		if budget > 0 and hidden_index < hidden_cells.size():
			var take_hidden := mini(budget, hidden_cells.size() - hidden_index)
			if take_hidden > 0:
				hidden_chunk = hidden_cells.slice(hidden_index, hidden_index + take_hidden)
				hidden_index += take_hidden
				budget -= take_hidden

		if revealed_chunk.is_empty() and hidden_chunk.is_empty():
			break

		_nm_broadcast_to_displays({
			"msg": "fog_delta",
			"fog_cell_px": cell_px,
			"revealed_cells": _serialise_fog_cells(revealed_chunk),
			"hidden_cells": _serialise_fog_cells(hidden_chunk),
		})


func _on_map_walls_changed(map: MapData) -> void:
	_nm_broadcast_map_update(map)
	_set_status("Wall added. Save map to persist wall/fog edits.")


func _on_map_spawn_points_changed(_map_data: MapData) -> void:
	_set_status("Spawn points updated. Save map to persist.")
	_refresh_spawn_profile_option()


func _on_spawn_point_selected(_idx: int) -> void:
	_refresh_spawn_profile_option()


# ---------------------------------------------------------------------------
# Spawn context panel — profile assignment
# ---------------------------------------------------------------------------

func _build_spawn_context_widgets() -> void:
	# Spawn context widgets are now owned by ToolPalette.
	pass


func _refresh_spawn_profile_option() -> void:
	if _palette == null or _palette.spawn_profile_option == null:
		return
	var opt: OptionButton = _palette.spawn_profile_option
	opt.clear()
	opt.add_item("— None —", 0)
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.profile == null:
		opt.disabled = true
		return
	var profiles: Array = registry.profile.get_profiles()
	for i in range(profiles.size()):
		var p: Variant = profiles[i]
		if p is PlayerProfile:
			var pp := p as PlayerProfile
			opt.add_item(pp.player_name, i + 1)
			opt.set_item_metadata(opt.item_count - 1, pp.id)
	var sel_idx: int = _map_view._selected_spawn_index if _map_view != null else -1
	if sel_idx >= 0 and _map_view._map != null and sel_idx < _map_view._map.spawn_points.size():
		var sp: Dictionary = _map_view._map.spawn_points[sel_idx]
		var assigned_id: String = str(sp.get("profile_id", ""))
		if assigned_id.is_empty():
			opt.selected = 0
		else:
			for item_idx in range(opt.item_count):
				var meta: Variant = opt.get_item_metadata(item_idx)
				if meta is String and meta == assigned_id:
					opt.selected = item_idx
					break
	else:
		opt.selected = 0
	opt.disabled = sel_idx < 0


func _on_spawn_profile_selected(item_idx: int) -> void:
	if _map_view == null or _map_view._map == null:
		return
	var sel := _map_view._selected_spawn_index
	if sel < 0 or sel >= _map_view._map.spawn_points.size():
		return
	var profile_id: String = ""
	if item_idx > 0 and _palette != null and _palette.spawn_profile_option != null:
		var meta: Variant = _palette.spawn_profile_option.get_item_metadata(item_idx)
		if meta is String:
			profile_id = meta
	_map_view._map.spawn_points[sel]["profile_id"] = profile_id
	_map_view._rebuild_spawn_markers(_map_view._map)
	_map_view.spawn_points_changed.emit(_map_view._map)


func _on_spawn_auto_assign() -> void:
	if _map_view == null or _map_view._map == null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.profile == null:
		return
	var profiles: Array = registry.profile.get_profiles()
	var spawns: Array = _map_view._map.spawn_points
	if spawns.is_empty() or profiles.is_empty():
		return
	for i in range(spawns.size()):
		if i < profiles.size():
			var p: Variant = profiles[i]
			if p is PlayerProfile:
				(spawns[i] as Dictionary)["profile_id"] = (p as PlayerProfile).id
		else:
			(spawns[i] as Dictionary)["profile_id"] = ""
	_map_view._rebuild_spawn_markers(_map_view._map)
	_map_view.spawn_points_changed.emit(_map_view._map)
	_refresh_spawn_profile_option()
	_set_status("Profiles auto-assigned to spawn points.")


func _on_move_to_spawns() -> void:
	if _backend == null or _map_view == null or _map_view._map == null:
		return
	_backend.move_all_to_spawns()
	_broadcast_player_state()
	_set_status("All players moved to spawn points.")


func _broadcast_fog_state() -> void:
	if _map_view == null:
		return
	if _fog_snapshot_in_flight:
		_fog_snapshot_queued = true
		return
	if _nm_displays_under_backpressure():
		_queue_fog_snapshot_sync(0.5)
		return
	_map_view.force_fog_sync()
	_fog_snapshot_in_flight = true
	_broadcast_fog_state_after_frame()


func _broadcast_fog_state_after_frame() -> void:
	await get_tree().process_frame
	if _map_view == null:
		_fog_snapshot_in_flight = false
		return
	var map: MapData = _map()
	if map == null:
		_fog_snapshot_in_flight = false
		return
	if _nm_displays_under_backpressure():
		_fog_snapshot_in_flight = false
		_queue_fog_snapshot_sync(0.5)
		return
	_nm_broadcast_to_displays(await _build_fog_state_snapshot(map))
	_fog_snapshot_in_flight = false
	if _fog_snapshot_queued:
		_fog_snapshot_queued = false
		_queue_fog_snapshot_sync(0.1)


func _serialise_fog_cells(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		if c is Vector2i:
			out.append({"x": c.x, "y": c.y})
		elif c is Vector2:
			out.append({"x": int((c as Vector2).x), "y": int((c as Vector2).y)})
		elif c is Dictionary:
			out.append({"x": int(c.get("x", 0)), "y": int(c.get("y", 0))})
		elif c is Array and (c as Array).size() >= 2:
			var arr := c as Array
			out.append({"x": int(arr[0]), "y": int(arr[1])})
	return out


func _init_player_cam_from_dm() -> void:
	## Called deferred after map load so Camera2D has settled.
	## Note: _player_cam_rotation is already restored from MapData in _apply_map.
	if _map_view == null:
		return
	var state: Dictionary = _map_view.get_camera_state()
	_player_cam_pos = Vector2(state["position"]["x"], state["position"]["y"])
	_player_cam_zoom = float(state["zoom"])
	_update_viewport_indicator()
	_broadcast_player_viewport()


func _maps_dir_abs() -> String:
	return ProjectSettings.globalize_path(MAP_DIR)


func _saves_dir_abs() -> String:
	return ProjectSettings.globalize_path(SAVE_DIR)


func _bundle_dir_abs(map_name: String) -> String:
	## Default bundle location under the managed maps directory.
	return _maps_dir_abs().path_join(map_name + ".map")


func _bundle_json_path_abs(bundle_path: String) -> String:
	return bundle_path.path_join("map.json")


func _image_dest_path_abs(bundle_path: String, ext: String) -> String:
	return bundle_path.path_join("image." + ext.to_lower())


func _ensure_maps_dir() -> void:
	var abs_dir := _maps_dir_abs()
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)


func _ensure_bundle_dir(bundle_path: String) -> void:
	var abs_dir := bundle_path
	# Native save panels can leave behind a placeholder file at the selected path.
	# If that happened, remove it so the .map path can become a directory bundle.
	if FileAccess.file_exists(abs_dir) and not DirAccess.dir_exists_absolute(abs_dir):
		var remove_err := DirAccess.remove_absolute(abs_dir)
		if remove_err != OK:
			push_error("DMWindow: could not replace placeholder file '%s' with bundle dir (err %d)" % [abs_dir, remove_err])
			return
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)


func _normalise_bundle_path(path: String) -> String:
	if path.to_lower().ends_with(".map"):
		return path
	return path + ".map"


func _resolve_bundle_path(path: String) -> String:
	## Resolves a native-dialog return path to the nearest .map bundle.
	if path.is_empty():
		return ""

	var raw := path
	if raw.to_lower().ends_with(".map"):
		return raw

	var current := raw if DirAccess.dir_exists_absolute(raw) else raw.get_base_dir()
	while not current.is_empty():
		if current.to_lower().ends_with(".map"):
			return current
		var parent := current.get_base_dir()
		if parent == current:
			break
		current = parent

	return ""


func _save_map_data(map: MapData) -> void:
	## Serialise MapData to map.json inside the active .map bundle directory.
	## image_path is stored as a relative filename so the bundle is self-contained.
	if _active_map_bundle_path.is_empty():
		_active_map_bundle_path = _bundle_dir_abs(map.map_name)
	_ensure_bundle_dir(_active_map_bundle_path)
	var path := _bundle_json_path_abs(_active_map_bundle_path)
	var d := map.to_dict()
	d["image_path"] = map.image_path.get_file()
	var ms := _map_service()
	if ms != null:
		ms.update(map)
		ms.save_to_bundle(_active_map_bundle_path)
		return

	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		push_error("DMWindow: cannot write to '%s'" % path)
		return
	fa.store_string(JSON.stringify(d, "\t"))
	fa.close()


func _load_map_from_bundle(bundle_path: String) -> MapData:
	## Read map.json from a .map bundle directory and resolve image_path to absolute.
	var json_path := bundle_path.path_join("map.json")
	var fa := FileAccess.open(json_path, FileAccess.READ)
	if fa == null:
		push_error("DMWindow: cannot read '%s'" % json_path)
		return null
	var text := fa.get_as_text()
	fa.close()
	var parsed: Variant = JsonUtilsScript.parse_json_text(text)
	if not (parsed is Dictionary):
		push_error("DMWindow: invalid JSON in '%s'" % json_path)
		return null
	var d: Dictionary = parsed as Dictionary
	# Resolve relative image filename to an absolute path inside the bundle.
	if d.has("image_path"):
		var img_ref: String = d["image_path"]
		if not img_ref.is_absolute_path() and not img_ref.begins_with("user://"):
			d["image_path"] = bundle_path.path_join(img_ref)
	return MapData.from_dict(d)


func _set_status(msg: String) -> void:
	if _status_label:
		_status_label.text = msg
	print("DMWindow: %s" % msg)


func _copy_file(from_path: String, to_path: String) -> Error:
	## Copy any file by reading and writing raw bytes.
	## Works with OS absolute paths, user://, and res:// paths.
	var parent_dir := to_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_dir):
		var mkdir_err := DirAccess.make_dir_recursive_absolute(parent_dir)
		if mkdir_err != OK:
			return mkdir_err
	var src := FileAccess.open(from_path, FileAccess.READ)
	if src == null:
		return FileAccess.get_open_error()
	var data := src.get_buffer(src.get_length())
	src.close()
	var dst := FileAccess.open(to_path, FileAccess.WRITE)
	if dst == null:
		return FileAccess.get_open_error()
	dst.store_buffer(data)
	dst.close()
	return OK


func _apply_palette_size() -> void:
	## Set the palette's screen-space width. Called from _apply_ui_scale()
	## and _dock_palette(). The palette lives directly in the CanvasLayer
	## (not _ui_root), so it is NOT affected by _ui_root.scale.
	if _palette == null:
		return
	var scale := _ui_scale()
	var panel_w := roundi(34.0 * scale)
	_palette.offset_left = 0.0
	_palette.offset_right = float(panel_w)
	_palette.offset_top = 0.0
	_palette.offset_bottom = 0.0


func _apply_freeze_panel_size() -> void:
	## Set the freeze panel's screen-space width. Called from _apply_ui_scale()
	## and _dock_freeze_panel(). The panel lives directly in the CanvasLayer
	## (not _ui_root), so it is NOT affected by _ui_root.scale.
	if _freeze_panel == null:
		return
	var scale := _ui_scale()
	var panel_w := roundi(200.0 * scale)
	_freeze_panel.offset_left = float(-panel_w)
	_freeze_panel.offset_right = 0.0
	_freeze_panel.offset_top = 0.0
	_freeze_panel.offset_bottom = 0.0


func _apply_passage_panel_size() -> void:
	## Reposition and rescale the passage panel at the screen bottom.
	## The panel lives directly in _ui_layer, so it is NOT affected by _ui_root.scale.
	## Widget sizes/fonts are explicitly scaled here to match the rest of the UI.
	if _passage_panel == null:
		return
	var scale := _ui_scale()
	var panel_h := roundi(56.0 * scale)
	_passage_panel.offset_left = 0.0
	_passage_panel.offset_right = 0.0
	_passage_panel.offset_top = float(-panel_h)
	_passage_panel.offset_bottom = 0.0
	var font_size: int = roundi(15.0 * scale)
	var btn_h: int = roundi(34.0 * scale)
	if _passage_token_label:
		_passage_token_label.add_theme_font_size_override("font_size", font_size)
	if _passage_mode_label:
		_passage_mode_label.add_theme_font_size_override("font_size", font_size)
	if _passage_brush_label:
		_passage_brush_label.add_theme_font_size_override("font_size", font_size)
	if _passage_mode_option:
		_passage_mode_option.custom_minimum_size = Vector2(roundi(130.0 * scale), btn_h)
		_passage_mode_option.add_theme_font_size_override("font_size", font_size)
	if _passage_brush_slider:
		_passage_brush_slider.custom_minimum_size = Vector2(roundi(120.0 * scale), roundi(20.0 * scale))
	if _passage_commit_btn:
		_passage_commit_btn.custom_minimum_size = Vector2(roundi(80.0 * scale), btn_h)
		_passage_commit_btn.add_theme_font_size_override("font_size", font_size)
	if _passage_clear_btn:
		_passage_clear_btn.custom_minimum_size = Vector2(roundi(70.0 * scale), btn_h)
		_passage_clear_btn.add_theme_font_size_override("font_size", font_size)


func _apply_ui_scale() -> void:
	var mgr := _get_ui_scale_mgr()
	var scale := _ui_scale()
	if _palette:
		_palette.custom_minimum_size = Vector2(roundi(34.0 * scale), 0)
	if _palette and _palette.get_parent() == _ui_layer:
		_apply_palette_size()
	if _ui_root:
		_ui_root.scale = Vector2(scale, scale)
	if _freeze_panel and _freeze_panel.get_parent() == _ui_layer:
		_apply_freeze_panel_size()
	if _passage_panel and _passage_panel.get_parent() == _ui_layer:
		_apply_passage_panel_size()
	# Update freeze panel static widget sizes and rebuild rows at new scale.
	if _freeze_undock_btn:
		_freeze_undock_btn.custom_minimum_size = Vector2(0, roundi(22.0 * scale))
		_freeze_undock_btn.add_theme_font_size_override("font_size", roundi(14.0 * scale))
	if _freeze_panel_title:
		_freeze_panel_title.add_theme_font_size_override("font_size", roundi(15.0 * scale))
	if _freeze_master_btn:
		_freeze_master_btn.custom_minimum_size = Vector2(0, roundi(30.0 * scale))
		_freeze_master_btn.add_theme_font_size_override("font_size", roundi(13.0 * scale))
	_refresh_freeze_panel()
	# Only reposition freeze panel when docked — floating window manages its own layout.
	if _freeze_panel and _freeze_panel.get_parent() == _ui_layer:
		_apply_freeze_panel_size()

	if mgr == null:
		return

	# ── Profiles — crisp font scaling (no root.scale bitmap upscale) ────
	if _profiles_dialog:
		var vp := get_viewport().get_visible_rect().size
		_profiles_dialog.min_size = Vector2i(roundi(vp.x * 0.72), roundi(vp.y * 0.72))
		mgr.scale_button(_profiles_dialog.get_ok_button())
	if _profiles_root:
		mgr.scale_control_fonts(_profiles_root)

	# ── Small dialogs — scale content + buttons via manager ─────────────
	if _cal_dialog_root:
		_cal_dialog.min_size = Vector2i(mgr.scaled(320.0), 0)
		mgr.scale_control_fonts(_cal_dialog_root)
		mgr.scale_button(_cal_dialog.get_ok_button())
		mgr.scale_button(_cal_dialog.get_cancel_button())
	if _manual_scale_dialog_root:
		_manual_scale_dialog.min_size = Vector2i(mgr.scaled(320.0), 0)
		mgr.scale_control_fonts(_manual_scale_dialog_root)
		mgr.scale_button(_manual_scale_dialog.get_ok_button())
		mgr.scale_button(_manual_scale_dialog.get_cancel_button())
	if _offset_dialog_root:
		_offset_dialog.min_size = Vector2i(mgr.scaled(280.0), 0)
		mgr.scale_control_fonts(_offset_dialog_root)
		mgr.scale_button(_offset_dialog.get_ok_button())
		mgr.scale_button(_offset_dialog.get_cancel_button())
	if _token_editor_dialog_root:
		_token_editor_dialog.min_size = Vector2i(mgr.scaled(400.0), mgr.scaled(420.0))
		mgr.scale_control_fonts(_token_editor_dialog_root)
		mgr.scale_button(_token_editor_dialog.get_ok_button())
		mgr.scale_button(_token_editor_dialog.get_cancel_button())
	_apply_token_context_menu_theme()

	# ── Share player link dialog ──
	if _share_dialog_root:
		_share_qr_rect.custom_minimum_size = Vector2(mgr.scaled(280.0), mgr.scaled(280.0))
		_share_url_label.add_theme_font_size_override("font_size", mgr.scaled(13.0))
		_share_dialog_root.add_theme_constant_override("separation", mgr.scaled(12.0))
		mgr.scale_button(_share_dialog.get_ok_button())


func _ui_scale() -> float:
	## Delegates to UIScaleManager so scale logic lives in one place.
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	if mgr != null:
		return mgr.get_scale()
	return 1.0


func _get_ui_scale_mgr() -> UIScaleManager:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null:
		# Registry node not yet added (deferred). Fall back to bootstrap.
		var bootstrap := get_node_or_null("/root/ServiceBootstrap")
		if bootstrap != null and bootstrap.get("registry") != null:
			reg = bootstrap.registry as ServiceRegistry
	if reg != null and reg.ui_scale != null:
		return reg.ui_scale
	return null


# ---------------------------------------------------------------------------
# Share Player Link (Session menu)
# ---------------------------------------------------------------------------

const _SHARE_BASE_URL: String = "https://everstonekeep.com/the-vault/play/"
const _WS_PORT: int = 9090

func _build_share_url() -> String:
	var ip: String = NetworkUtilsScript.get_best_lan_ip()
	return "%s?host=%s&port=%d" % [_SHARE_BASE_URL, ip, _WS_PORT]


func _show_share_player_link() -> void:
	var url: String = _build_share_url()
	var mgr := _get_ui_scale_mgr()

	if _share_dialog != null:
		# Refresh QR and URL in case IP changed
		_share_url_label.text = url
		var refresh_img: Image = QRCodeScript.generate(url, 8)
		_share_qr_rect.texture = ImageTexture.create_from_image(refresh_img)
		_apply_ui_scale()
		_share_dialog.reset_size()
		_share_dialog.popup_centered()
		return

	_share_dialog = AcceptDialog.new()
	_share_dialog.title = "Share Player Link"
	_share_dialog.ok_button_text = "Close"

	# Content root — children sized explicitly via scale factor.
	# No root scale transform: dialogs need Godot’s layout engine to see the
	# real child sizes so the window auto-fits its content correctly.
	_share_dialog_root = VBoxContainer.new()
	if mgr != null:
		_share_dialog_root.add_theme_constant_override("separation", mgr.scaled(12.0))

	# Top padding
	var top_pad := Control.new()
	if mgr != null:
		top_pad.custom_minimum_size = Vector2(0, mgr.scaled(8.0))
	_share_dialog_root.add_child(top_pad)

	# QR code
	var qr_img: Image = QRCodeScript.generate(url, 8)
	var qr_tex: ImageTexture = ImageTexture.create_from_image(qr_img)
	_share_qr_rect = TextureRect.new()
	_share_qr_rect.texture = qr_tex
	_share_qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if mgr != null:
		_share_qr_rect.custom_minimum_size = Vector2(mgr.scaled(280.0), mgr.scaled(280.0))
	_share_qr_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_share_dialog_root.add_child(_share_qr_rect)

	# URL label
	_share_url_label = Label.new()
	_share_url_label.text = url
	_share_url_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_share_url_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if mgr != null:
		_share_url_label.add_theme_font_size_override("font_size", mgr.scaled(13.0))
	_share_dialog_root.add_child(_share_url_label)

	# Copy URL button
	var copy_btn := Button.new()
	copy_btn.text = "Copy URL"
	copy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if mgr != null:
		mgr.scale_button(copy_btn)
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(url)
		_set_status("Player link copied to clipboard"))
	_share_dialog_root.add_child(copy_btn)

	_share_dialog.add_child(_share_dialog_root)
	if mgr != null:
		mgr.scale_button(_share_dialog.get_ok_button())
	add_child(_share_dialog)
	_share_dialog.reset_size()
	_share_dialog.popup_centered()
