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
const JsonUtils = preload("res://scripts/utils/JsonUtils.gd")

const MAP_DIR := "user://data/maps/"
const SUPPORTED_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]

# ── UI node references ──────────────────────────────────────────────────────
var _map_view: Node2D = null
var _cal_tool: Node = null ## CalibrationTool instance

var _file_dialog: FileDialog = null
var _cal_dialog: ConfirmationDialog = null
var _manual_scale_dialog: ConfirmationDialog = null

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
var _pending_image_path: String = "" ## holds image path while native save dialog is open
var _map_name_mode: String = "new" ## "new" or "save_as"
var _active_map_bundle_path: String = "" ## absolute path to the current .map bundle directory

var _status_label: Label = null
var _grid_option: OptionButton = null
var _ui_root: VBoxContainer = null

# Player profile form fields
var _profile_orientation_spin: SpinBox = null

var _toolbar: Control = null ## HBoxContainer — shown/hidden by View menu
var _select_btn: Button = null
var _pan_btn: Button = null
var _view_menu: PopupMenu = null ## kept for checkmark management
var _fog_tool_option: OptionButton = null
var _fog_brush_spin: SpinBox = null
var _fog_visible_check: CheckBox = null
## Removed unused _wall_tool_dropdown variable
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
var _wall_delete_btn: Button = null

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
## Legacy autoload reference removed — use registry-first `_network()` helper

# ── Player viewport control ─────────────────────────────────────────────────
# The green box on the DM map shows what players currently see.
# Drag the box to reposition the player camera; use the toolbar to zoom.
var _player_cam_pos: Vector2 = Vector2(960.0, 540.0)
var _player_cam_zoom: float = 1.0
var _player_window_size: Vector2 = Vector2(1920.0, 1080.0)
var _play_mode: bool = false
var _play_mode_btn: Button = null

const _BROADCAST_DEBOUNCE: float = 0.05 ## seconds — near-instant feel
const _PLAYER_STATE_BROADCAST_DEBOUNCE: float = 0.0
const _FOG_BROADCAST_DEBOUNCE: float = 1.5
const _FOG_AUTO_SYNC_DEBOUNCE: float = 0.0
const _FOG_DELTA_MAX_CELLS: int = 1200
const _FOG_TRUTH_MAX_CELLS_PER_CHUNK: int = 400
const _FOG_TRUTH_CHUNKS_PER_FRAME: int = 100000
const _ENABLE_CONTINUOUS_FOG_SYNC: bool = false
const DEBUG_FOG_SNAPSHOT: bool = false
const DEBUG_FOG_TELEMETRY: bool = false
var _broadcast_dirty: bool = false
var _broadcast_countdown: float = 0.0
var _player_state_dirty: bool = false
var _player_state_countdown: float = 0.0
var _fog_dirty: bool = false
var _fog_countdown: float = 0.0
var _fog_snapshot_in_flight: bool = false
var _fog_snapshot_queued: bool = false
var _fog_truth_send_queue: Array = []
var _fog_truth_send_index: int = 0
var _backend: Node = null
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
	_apply_ui_scale()
	print("DMWindow: ready")


func _ensure_profile_bindings() -> void:
	var ps_node: Node = _profile_service()
	var gs_node: Node = _game_state()
	if ps_node == null and gs_node == null:
		call_deferred("_ensure_profile_bindings")
		return
	var target := ps_node if ps_node != null else gs_node
	if target.has_signal("profiles_changed") and not target.is_connected("profiles_changed", Callable(self , "_on_profiles_changed")):
		target.profiles_changed.connect(_on_profiles_changed)
	_apply_profile_bindings()


func _network() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var svc: Object = registry.get_service("Network")
		if svc == null:
			var adapter: Object = registry.get_service("NetworkAdapter")
			if adapter != null:
				push_warning("DMWindow: 'Network' service missing — falling back to 'NetworkAdapter'")
				svc = adapter
		if svc != null:
			return svc as Node
	return null


func _input_service() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var svc: Object = registry.get_service("Input")
		if svc == null:
			var adapter: Object = registry.get_service("InputAdapter")
			if adapter != null:
				push_warning("DMWindow: 'Input' service missing — falling back to 'InputAdapter'")
				svc = adapter
		if svc != null:
			return svc as Node
	# Final fallback to legacy autoload
	return get_node_or_null("/root/InputManager")


## Network helper wrappers (centralise registry fallback and null-guards)
func _nm_broadcast_to_displays(msg: Dictionary) -> void:
	var nm := _network()
	if nm != null and nm.has_method("broadcast_to_displays"):
		nm.broadcast_to_displays(msg)

func _nm_broadcast_map(map: MapData) -> void:
	var nm := _network()
	if nm == null:
		return
	if nm.has_method("broadcast_map"):
		nm.broadcast_map(map)
	elif nm.has_method("broadcast_to_displays"):
		nm.broadcast_to_displays({"msg": "map_loaded", "map": map})

func _nm_broadcast_map_update(map: MapData) -> void:
	var nm := _network()
	if nm == null:
		return
	if nm.has_method("broadcast_map_update"):
		nm.broadcast_map_update(map)
	elif nm.has_method("broadcast_to_displays"):
		nm.broadcast_to_displays({"msg": "map_updated", "map": map})

func _nm_send_map_to_display(peer_id: int, map: MapData, is_update: bool, fog_snapshot: Dictionary) -> void:
	var nm := _network()
	if nm == null:
		return
	if nm.has_method("send_map_to_display"):
		nm.send_map_to_display(peer_id, map, is_update, fog_snapshot)
	elif nm.has_method("broadcast_map"):
		nm.broadcast_map(map)

func _nm_bind_peer(peer_id: int, player_id: Variant) -> void:
	var nm := _network()
	if nm != null and nm.has_method("bind_peer"):
		nm.bind_peer(peer_id, player_id)

func _nm_get_connected_input_peers() -> Array:
	var nm := _network()
	if nm != null and nm.has_method("get_connected_input_peers"):
		return nm.get_connected_input_peers()
	return []

func _nm_get_peer_bound_player(peer_id: int) -> String:
	var nm := _network()
	if nm != null and nm.has_method("get_peer_bound_player"):
		return str(nm.get_peer_bound_player(peer_id))
	return ""

func _nm_displays_under_backpressure() -> bool:
	var nm := _network()
	if nm != null and nm.has_method("displays_under_backpressure"):
		return bool(nm.displays_under_backpressure())
	return false

func _nm_is_display_peer_connected(peer_id: int) -> bool:
	var nm := _network()
	if nm != null and nm.has_method("is_display_peer_connected"):
		return bool(nm.is_display_peer_connected(peer_id))
	return true


func _game_state() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var svc: Object = registry.get_service("GameState")
		if svc == null:
			var adapter: Object = registry.get_service("GameStateAdapter")
			if adapter != null:
				push_warning("DMWindow: 'GameState' service missing — falling back to 'GameStateAdapter'")
				svc = adapter
		return svc as Node
	return null


func _map_service() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var svc: Object = registry.get_service("Map")
		if svc == null:
			var adapter: Object = registry.get_service("MapAdapter")
			if adapter != null:
				push_warning("DMWindow: 'Map' service missing — falling back to 'MapAdapter'")
				svc = adapter
		return svc as Node
	return null


func _map() -> MapData:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var ms: Object = registry.get_service("Map")
		if ms == null:
			ms = registry.get_service("MapAdapter")
		if ms != null and ms.has_method("get_map"):
			var m: MapData = ms.get_map() as MapData
			if m != null:
				return m
	if _map_view != null and _map_view.has_method("get_map"):
		return _map_view.get_map() as MapData
	return null


func _init_network_binding() -> void:
	var nm := _network()
	if nm == null:
		# Try again later if not yet registered
		call_deferred("_init_network_binding")
		return
	# keep local nm reference only; avoid storing legacy global
	var connected_any := false
	if nm.has_signal("display_peer_registered") and not nm.is_connected("display_peer_registered", Callable(self , "_on_display_peer_registered")):
		nm.display_peer_registered.connect(_on_display_peer_registered)
		connected_any = true
	if nm.has_signal("client_disconnected") and not nm.is_connected("client_disconnected", Callable(self , "_on_client_disconnected")):
		nm.client_disconnected.connect(_on_client_disconnected)
		connected_any = true
	if nm.has_signal("display_viewport_resized") and not nm.is_connected("display_viewport_resized", Callable(self , "_on_display_viewport_resized")):
		nm.display_viewport_resized.connect(_on_display_viewport_resized)
		connected_any = true
	if nm.has_signal("display_sync_applied") and not nm.is_connected("display_sync_applied", Callable(self , "_on_display_sync_applied")):
		nm.display_sync_applied.connect(_on_display_sync_applied)
		connected_any = true
	# If the service exists but hasn't yet exposed the expected signals, retry shortly.
	if not connected_any:
		call_deferred("_init_network_binding")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_apply_ui_scale()


func _process(delta: float) -> void:
	if _player_state_countdown > 0.0:
		_player_state_countdown = maxf(0.0, _player_state_countdown - delta)
	if _fog_countdown > 0.0:
		_fog_countdown = maxf(0.0, _fog_countdown - delta)
	if _fog_dirty and _fog_countdown <= 0.0:
		_fog_dirty = false
		_broadcast_fog_truth_state()
		_fog_countdown = _FOG_BROADCAST_DEBOUNCE

	_pump_fog_truth_send_queue()

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


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# ── MapView ─────────────────────────────────────────────────────────────
	_map_view = MapViewScene.instantiate()
	_map_view.name = "MapView"
	add_child(_map_view)
	_map_view.allow_keyboard_pan = false
	_map_view.set_dm_view(true)
	_map_view.fog_changed.connect(_on_map_fog_changed)
	_map_view.fog_delta.connect(_on_map_fog_delta)
	_map_view.walls_changed.connect(_on_map_walls_changed)
	_backend = BackendRuntimeScript.new()
	_backend.name = "BackendRuntime"
	add_child(_backend)
	if _backend.has_method("configure"):
		_backend.configure(_map_view)

	# CalibrationTool lives inside MapView's world-space so its drawn overlay
	# follows the camera correctly.
	_cal_tool = load("res://scripts/tools/CalibrationTool.gd").new()
	_cal_tool.name = "CalibrationTool"
	_map_view.add_child(_cal_tool)

	# ── CanvasLayer for UI (always on top) ───────────────────────────────────
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)

	# Root VBox pinned to the full top edge
	_ui_root = VBoxContainer.new()
	_ui_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_ui_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_layer.add_child(_ui_root)

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
	file_menu.add_item("Quit", 9)
	file_menu.id_pressed.connect(_on_file_menu_id)
	menu_bar.add_child(file_menu)

	# Edit menu
	var edit_menu := PopupMenu.new()
	edit_menu.name = "Edit"
	edit_menu.add_item("Calibrate Grid…", 10)
	edit_menu.add_item("Set Scale Manually…", 11)
	edit_menu.add_item("Set Grid Offset…", 12)
	edit_menu.add_separator()
	edit_menu.add_item("Player Profiles…", 13)
	edit_menu.id_pressed.connect(_on_edit_menu_id)
	menu_bar.add_child(edit_menu)

	# View menu  (indices matter for set_item_checked)
	# idx 0 → id 20 Toolbar
	# idx 1 → id 21 Grid Overlay
	# idx 2 → separator
	# idx 3 → id 22 Reset View
	# idx 4 → separator
	# idx 5 → id 24 Sync Fog Now
	# idx 6 → separator
	# idx 7 → id 23 Launch Player Window
	_view_menu = PopupMenu.new()
	_view_menu.name = "View"
	_view_menu.add_check_item("Toolbar", 20)
	_view_menu.set_item_checked(0, true)
	_view_menu.add_check_item("Grid Overlay", 21)
	_view_menu.set_item_checked(1, true)
	_view_menu.add_separator()
	_view_menu.add_item("Reset View", 22)
	_view_menu.add_separator()
	_view_menu.add_item("Sync Fog Now", 24)
	_view_menu.add_separator()
	_view_menu.add_item("▶ Launch Player Window", 23)
	_view_menu.id_pressed.connect(_on_view_menu_id)
	menu_bar.add_child(_view_menu)

	# ── Toolbar ──────────────────────────────────────────────────────────────
	_toolbar = PanelContainer.new()
	_toolbar.name = "Toolbar"
	_toolbar.custom_minimum_size = Vector2(0, roundi(44.0 * _ui_scale()))
	_ui_root.add_child(_toolbar)

	var toolbar_hbox := HBoxContainer.new()
	toolbar_hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	toolbar_hbox.add_theme_constant_override("separation", 6)
	var toolbar_margin := MarginContainer.new()
	toolbar_margin.add_theme_constant_override("margin_left", 6)
	toolbar_margin.add_theme_constant_override("margin_right", 6)
	toolbar_margin.add_theme_constant_override("margin_top", 4)
	toolbar_margin.add_theme_constant_override("margin_bottom", 4)
	toolbar_margin.add_child(toolbar_hbox)
	_toolbar.add_child(toolbar_margin)

	# Tool toggle group (Select / Pan)
	var tool_group := ButtonGroup.new()

	_select_btn = Button.new()
	_select_btn.text = "↖"
	_select_btn.toggle_mode = true
	_select_btn.button_pressed = true
	_select_btn.button_group = tool_group
	_select_btn.focus_mode = Control.FOCUS_NONE
	_select_btn.tooltip_text = "Select tool"
	_select_btn.custom_minimum_size = Vector2(roundi(34.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	_select_btn.add_theme_font_size_override("font_size", roundi(20.0 * _ui_scale()))
	_select_btn.pressed.connect(func(): _on_tool_changed(0))
	toolbar_hbox.add_child(_select_btn)

	_pan_btn = Button.new()
	_pan_btn.text = "✋"
	_pan_btn.toggle_mode = true
	_pan_btn.button_group = tool_group
	_pan_btn.focus_mode = Control.FOCUS_NONE
	_pan_btn.tooltip_text = "Pan tool — left-drag to pan"
	_pan_btn.custom_minimum_size = Vector2(roundi(34.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	_pan_btn.add_theme_font_size_override("font_size", roundi(20.0 * _ui_scale()))
	_pan_btn.pressed.connect(func(): _on_tool_changed(1))
	toolbar_hbox.add_child(_pan_btn)

	var sep1 := VSeparator.new()
	toolbar_hbox.add_child(sep1)

	# Zoom controls
	var zoom_in_btn := _make_toolbar_btn("+", "Zoom in (scroll up)")
	zoom_in_btn.pressed.connect(func(): if _map_view: _map_view.zoom_in())
	toolbar_hbox.add_child(zoom_in_btn)

	var zoom_out_btn := _make_toolbar_btn("-", "Zoom out (scroll down)")
	zoom_out_btn.pressed.connect(func(): if _map_view: _map_view.zoom_out())
	toolbar_hbox.add_child(zoom_out_btn)

	var reset_btn := _make_toolbar_btn("⌂", "Reset view")
	reset_btn.pressed.connect(func(): if _map_view: _map_view._reset_camera())
	toolbar_hbox.add_child(reset_btn)

	var sep2 := VSeparator.new()
	toolbar_hbox.add_child(sep2)

	# Grid type selector
	_grid_option = OptionButton.new()
	_grid_option.add_item("□", MapData.GridType.SQUARE)
	_grid_option.add_item("⬢", MapData.GridType.HEX_FLAT)
	_grid_option.add_item("⬣", MapData.GridType.HEX_POINTY)
	_grid_option.disabled = true
	_grid_option.focus_mode = Control.FOCUS_NONE
	_grid_option.custom_minimum_size = Vector2(roundi(44.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	_grid_option.add_theme_font_size_override("font_size", roundi(22.0 * _ui_scale()))
	_grid_option.tooltip_text = "Grid type: square, hex flat-top, hex pointy-top"
	_grid_option.item_selected.connect(_on_grid_type_selected)
	toolbar_hbox.add_child(_grid_option)

	var sep3 := VSeparator.new()
	toolbar_hbox.add_child(sep3)

	var pv_zoom_in_btn := _make_toolbar_btn("▣+", "Zoom player viewport in")
	pv_zoom_in_btn.pressed.connect(func(): _change_player_zoom(0.15))
	toolbar_hbox.add_child(pv_zoom_in_btn)

	var pv_zoom_out_btn := _make_toolbar_btn("▣-", "Zoom player viewport out")
	pv_zoom_out_btn.pressed.connect(func(): _change_player_zoom(-0.15))
	toolbar_hbox.add_child(pv_zoom_out_btn)

	var pv_sync_btn := _make_toolbar_btn("◎", "Sync player view to DM")
	pv_sync_btn.pressed.connect(_sync_player_to_dm_view)
	toolbar_hbox.add_child(pv_sync_btn)

	var sep4 := VSeparator.new()
	toolbar_hbox.add_child(sep4)

	_fog_tool_option = OptionButton.new()
	_fog_tool_option.focus_mode = Control.FOCUS_NONE
	_fog_tool_option.add_item("☁ Off", 0)
	_fog_tool_option.add_item("☁ R◯", 1)
	_fog_tool_option.add_item("☁ H◯", 2)
	_fog_tool_option.add_item("☁ R▭", 3)
	_fog_tool_option.add_item("☁ H▭", 4)
	_fog_tool_option.custom_minimum_size = Vector2(roundi(70.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	_fog_tool_option.add_theme_font_size_override("font_size", roundi(12.0 * _ui_scale()))
	_fog_tool_option.tooltip_text = "Fog tools: Reveal/Hide brush and rectangle"
	_fog_tool_option.item_selected.connect(_on_fog_tool_selected)
	toolbar_hbox.add_child(_fog_tool_option)

	_fog_brush_spin = SpinBox.new()
	_fog_brush_spin.min_value = 8
	_fog_brush_spin.max_value = 512
	_fog_brush_spin.step = 8
	_fog_brush_spin.value = 64
	_fog_brush_spin.suffix = " px"
	_fog_brush_spin.custom_minimum_size = Vector2(roundi(74.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	_fog_brush_spin.add_theme_font_size_override("font_size", roundi(15.0 * _ui_scale()))
	_fog_brush_spin.value_changed.connect(_on_fog_brush_size_changed)
	toolbar_hbox.add_child(_fog_brush_spin)

	_fog_visible_check = CheckBox.new()
	_fog_visible_check.text = "🔦"
	_fog_visible_check.button_pressed = true
	_fog_visible_check.focus_mode = Control.FOCUS_NONE
	_fog_visible_check.tooltip_text = "Show/hide DM fog overlay"
	_fog_visible_check.custom_minimum_size = Vector2(roundi(38.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	_fog_visible_check.add_theme_font_size_override("font_size", roundi(14.0 * _ui_scale()))
	_fog_visible_check.toggled.connect(_on_dm_fog_visible_toggled)
	toolbar_hbox.add_child(_fog_visible_check)

	# Wall tool dropdown
	var wall_tool_dropdown := OptionButton.new()
	wall_tool_dropdown.name = "WallToolDropdown"
	wall_tool_dropdown.focus_mode = Control.FOCUS_NONE
	wall_tool_dropdown.custom_minimum_size = Vector2(roundi(70.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	wall_tool_dropdown.add_theme_font_size_override("font_size", roundi(16.0 * _ui_scale()))
	wall_tool_dropdown.tooltip_text = "Wall tools: Rectangle or Polygon"
	wall_tool_dropdown.add_item("▭ Rectangle", 0)
	wall_tool_dropdown.add_item("▲ Polygon", 1)
	wall_tool_dropdown.select(0)
	wall_tool_dropdown.item_selected.connect(_on_wall_tool_selected)
	wall_tool_dropdown.pressed.connect(func():
		var idx := wall_tool_dropdown.selected
		_on_wall_tool_selected(idx)
	)
	toolbar_hbox.add_child(wall_tool_dropdown)

	_wall_delete_btn = _make_toolbar_btn("⌫", "Delete selected wall (or press Delete)")
	_wall_delete_btn.pressed.connect(_on_delete_wall_pressed)
	toolbar_hbox.add_child(_wall_delete_btn)

	var sep5 := VSeparator.new()
	toolbar_hbox.add_child(sep5)

	_play_mode_btn = Button.new()
	_play_mode_btn.text = "▶"
	_play_mode_btn.toggle_mode = true
	_play_mode_btn.focus_mode = Control.FOCUS_NONE
	_play_mode_btn.tooltip_text = "Launch the Player display window"
	_play_mode_btn.custom_minimum_size = Vector2(roundi(34.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	_play_mode_btn.add_theme_font_size_override("font_size", roundi(20.0 * _ui_scale()))
	_play_mode_btn.pressed.connect(_on_play_mode_pressed)
	toolbar_hbox.add_child(_play_mode_btn)

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

	# ── Manual scale dialog ──────────────────────────────────────────────────
	_manual_scale_dialog = ConfirmationDialog.new()
	_manual_scale_dialog.title = "Set Scale Manually"
	_manual_scale_dialog.min_size = Vector2i(320, 0)

	var ms_vbox := VBoxContainer.new()
	ms_vbox.add_theme_constant_override("separation", 8)

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
	_open_map_dialog = FileDialog.new()
	_open_map_dialog.use_native_dialog = true
	_open_map_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_open_map_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_map_dialog.title = "Open Map Bundle"
	_open_map_dialog.add_filter("*.map ; OmniCrawl Map Bundle")
	_open_map_dialog.file_selected.connect(_on_map_bundle_selected)
	_open_map_dialog.dir_selected.connect(_on_map_bundle_selected)
	add_child(_open_map_dialog)

	# ── Save As dialog — native Save panel; filename stem becomes the map name ─
	_save_as_dialog = FileDialog.new()
	_save_as_dialog.use_native_dialog = true
	_save_as_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_as_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_save_as_dialog.title = "Save Map As"
	_save_as_dialog.add_filter("*.map ; OmniCrawl Map")
	_save_as_dialog.file_selected.connect(_on_save_as_path_selected)
	add_child(_save_as_dialog)

	# ── Standalone Grid Offset dialog (Edit > Set Grid Offset…)
	_offset_dialog = ConfirmationDialog.new()
	_offset_dialog.title = "Set Grid Offset"
	_offset_dialog.min_size = Vector2i(280, 0)

	var solo_vbox := VBoxContainer.new()
	solo_vbox.add_theme_constant_override("separation", 8)

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


# ---------------------------------------------------------------------------
# Player viewport helpers
# ---------------------------------------------------------------------------

func _on_display_peer_registered(_peer_id: int, viewport_size: Vector2) -> void:
	## A new Player display process just completed its handshake.
	## Keep the existing world-space viewport footprint stable by adjusting zoom
	## when the real player window size differs from our current assumption.
	_update_player_window_size_preserve_world(viewport_size)
	_initial_sync_ack_pending[_peer_id] = true
	_initial_sync_attempt_by_peer[_peer_id] = 0
	_queue_initial_display_sync(_peer_id, 0.20)


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
	if _map_view and _map_view.has_method("get_fog_state"):
		fog_state_png = await _map_view.get_fog_state()
	var fog_manager: Object = null
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		fog_manager = registry.get_service("Fog")
		if fog_manager == null:
			var fog_adapter: Object = registry.get_service("FogAdapter")
			if fog_adapter != null:
				push_warning("DMWindow: 'Fog' service missing — falling back to 'FogAdapter'")
				fog_manager = fog_adapter
	if not fog_state_png.is_empty() and fog_manager and fog_manager.has_method("set_fog_state"):
		fog_manager.set_fog_state(fog_state_png)
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


func _on_viewport_indicator_moved(new_center: Vector2) -> void:
	## Called when the DM drags the green box on the DM map.
	_player_cam_pos = new_center
	_broadcast_dirty = true
	_broadcast_countdown = _BROADCAST_DEBOUNCE


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
	_map_view.set_viewport_indicator(Rect2(_player_cam_pos - world_size * 0.5, world_size))


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
	})


func _on_play_mode_pressed() -> void:
	if not _play_mode:
		_play_mode = true
		_launch_player_process()
	else:
		# Cannot kill the external process; just toggle the button visual back.
		_play_mode = false
		if _play_mode_btn:
			_play_mode_btn.button_pressed = false


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
		if _play_mode_btn:
			_play_mode_btn.button_pressed = false


# ---------------------------------------------------------------------------
# Helper: FOCUS_NONE button for toolbar
# ---------------------------------------------------------------------------

func _make_toolbar_btn(label: String, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(roundi(34.0 * _ui_scale()), roundi(28.0 * _ui_scale()))
	b.add_theme_font_size_override("font_size", roundi(18.0 * _ui_scale()))
	return b


# ---------------------------------------------------------------------------
# Menu handlers
# ---------------------------------------------------------------------------

func _on_file_menu_id(id: int) -> void:
	match id:
		0: _on_new_map_pressed()
		1: _on_open_map_pressed()
		2: _on_save_map_pressed()
		3: _on_save_map_as_pressed()
		9: get_tree().quit()


func _on_edit_menu_id(id: int) -> void:
	match id:
		10: _on_calibrate_pressed()
		11: _on_manual_scale_pressed()
		12: _on_set_offset_pressed()
		13: _open_profiles_editor()


func _on_view_menu_id(id: int) -> void:
	match id:
		20: # Toggle toolbar
			_toolbar.visible = !_toolbar.visible
			_view_menu.set_item_checked(0, _toolbar.visible)
		21: # Toggle grid overlay
			if _map_view:
				var go: Node2D = _map_view.grid_overlay
				go.visible = !go.visible
				_view_menu.set_item_checked(1, go.visible)
		22: # Reset DM view
			if _map_view:
				_map_view._reset_camera()
		24: # Manual fog resync
			_manual_fog_sync_now()
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


func _on_fog_tool_selected(index: int) -> void:
	if _map_view == null or _fog_tool_option == null:
		return
	var tool_id := _fog_tool_option.get_item_id(index)
	_map_view.set_fog_tool(tool_id, _fog_brush_spin.value if _fog_brush_spin else 64.0)
	# Tool enum assignment handled in set_fog_tool
	_set_status("Fog tool: %s" % _fog_tool_option.get_item_text(index))


func _on_fog_brush_size_changed(value: float) -> void:
	if _map_view == null or _fog_tool_option == null:
		return
	_map_view.set_fog_tool(_fog_tool_option.get_item_id(_fog_tool_option.selected), value)


func _on_dm_fog_visible_toggled(enabled: bool) -> void:
	if _map_view == null:
		return
	_map_view.set_dm_fog_visible(enabled)


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

func _on_grid_type_selected(index: int) -> void:
	var map: MapData = _map()
	if map == null:
		return
	map.grid_type = _grid_option.get_item_id(index)
	_map_view.grid_overlay.apply_map_data(map)
	_nm_broadcast_map_update(map)
	_broadcast_player_state()
	_set_status("Grid: %s" % _grid_option.get_item_text(index))


# ---------------------------------------------------------------------------
# Calibration workflow
# ---------------------------------------------------------------------------

func _on_calibrate_pressed() -> void:
	var map: MapData = _map()
	if map == null:
		_set_status("Load a map first.")
		return
	# Ensure we're in Select mode during calibration (no accidental drag pan)
	_map_view._set_active_tool(0) # Tool.SELECT
	_select_btn.button_pressed = true
	# Pre-fill offset spinboxes from current map data
	_offset_x_spin.value = map.grid_offset.x
	_offset_y_spin.value = map.grid_offset.y
	_cal_tool.activate(map)
	_set_status("Calibrate: click-drag a line on the map, then release.")


func _on_calibration_confirmed() -> void:
	_cal_tool.apply_measurement(_feet_spin.value)


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
	_manual_scale_dialog.popup_centered(Vector2i(360, 160))


func _on_manual_scale_confirmed() -> void:
	var map: MapData = _map()
	if map == null:
		return
	var px_per_cell := _scale_px_spin.value
	var ft_per_cell := _scale_ft_spin.value
	# Normalise to pixels-per-5ft cell
	var cell_px := px_per_cell * (5.0 / ft_per_cell)
	match map.grid_type:
		MapData.GridType.SQUARE:
			map.cell_px = cell_px
		_:
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
	_offset_dialog.popup_centered(Vector2i(320, 160))


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
	root.split_offset = 280
	_profiles_dialog.add_child(root)
	_profiles_root = root

	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(260, 0)
	root.add_child(left_panel)

	var left_title := Label.new()
	left_title.text = "Profiles"
	left_panel.add_child(left_title)

	_profiles_list = ItemList.new()
	_profiles_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_profiles_list.item_selected.connect(_on_profile_selected)
	left_panel.add_child(_profiles_list)

	var list_btn_row := HBoxContainer.new()
	left_panel.add_child(list_btn_row)

	_profile_add_btn = Button.new()
	_profile_add_btn.text = "New"
	_profile_add_btn.pressed.connect(_on_profile_add_pressed)
	list_btn_row.add_child(_profile_add_btn)

	_profile_delete_btn = Button.new()
	_profile_delete_btn.text = "Remove"
	_profile_delete_btn.disabled = true
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
	_profile_dash_check.text = "Speed +50%, Vision -50%"
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
	var gs_node: Node = _game_state()
	var profiles_arr: Array = Array()
	if gs_node != null:
		profiles_arr = gs_node.profiles
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
	_profile_extras_edit.text = "{}"
	_on_profile_vision_selected(0)
	_update_profile_action_state()


func _on_profile_selected(index: int) -> void:
	_profile_is_new_draft = false
	_profile_selected_index = index
	_load_selected_profile_into_form(index)
	_update_profile_action_state()


func _load_selected_profile_into_form(index: int) -> void:
	var ps_node: Node = _profile_service()
	var gs_node: Node = _game_state()
	var profiles_arr: Array = []
	if ps_node != null and ps_node.has_method("get_profiles"):
		profiles_arr = ps_node.get_profiles()
	elif gs_node != null:
		profiles_arr = gs_node.profiles
	else:
		_clear_profile_form()
		return
	if index < 0 or index >= profiles_arr.size():
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
		_profile_dash_check.button_pressed = bool(p.extras.get("is_dashing", false))
	_profile_input_type_option.select(_profile_input_type_option.get_item_index(p.input_type))
	_profile_input_id_edit.text = p.input_id
	_profile_extras_edit.text = JSON.stringify(p.extras, "\t")
	if _profile_orientation_spin:
		_profile_orientation_spin.value = p.table_orientation
	_on_profile_vision_selected(_profile_vision_option.selected)
	_update_profile_action_state()


func _on_profile_add_pressed() -> void:
	_profile_is_new_draft = true
	_profile_selected_index = -1
	if _profiles_list:
		_profiles_list.deselect_all()
	_clear_profile_form()
	var ps_node: Node = _profile_service()
	var gs_node: Node = _game_state()
	var next_idx: int = 1
	if ps_node != null and ps_node.has_method("get_profiles"):
		next_idx = ps_node.get_profiles().size() + 1
	elif gs_node != null:
		next_idx = gs_node.profiles.size() + 1
	_profile_name_edit.text = "Player %d" % next_idx
	if _profile_name_edit:
		_profile_name_edit.grab_focus()
		_profile_name_edit.select_all()
	_set_status("Creating new profile. Fill fields, then click Create Profile.")


func _on_profile_delete_pressed() -> void:
	if _profile_is_new_draft:
		_on_profile_cancel_new_pressed()
		return
	var ps_node: Node = _profile_service()
	var gs_node: Node = _game_state()
	if ps_node != null:
		if _profile_selected_index < 0 or _profile_selected_index >= (ps_node.get_profiles() if ps_node.has_method("get_profiles") else []).size():
			_set_status("Select a profile to remove.")
			return
	else:
		if gs_node == null or _profile_selected_index < 0 or _profile_selected_index >= gs_node.profiles.size():
			_set_status("Select a profile to remove.")
			return
	var removed_name := "Profile"
	if ps_node != null:
		var arr: Array = ps_node.get_profiles() if ps_node.has_method("get_profiles") else []
		var item = arr[_profile_selected_index]
		if item is PlayerProfile:
			removed_name = (item as PlayerProfile).player_name
		if ps_node.has_method("remove_profile"):
			ps_node.remove_profile(item.id if item is PlayerProfile else str(item.get("id", "")))
		if ps_node.has_method("save_profiles"):
			ps_node.save_profiles()
		if ps_node.has_method("load_profiles"):
			ps_node.load_profiles()
	else:
		if gs_node.profiles[_profile_selected_index] is PlayerProfile:
			removed_name = (gs_node.profiles[_profile_selected_index] as PlayerProfile).player_name
		gs_node.profiles.remove_at(_profile_selected_index)
		if gs_node.has_method("save_profiles"):
			gs_node.save_profiles()
		if gs_node.has_method("load_profiles"):
			gs_node.load_profiles()
	_profile_selected_index = clampi(_profile_selected_index, 0, max(0, gs_node.profiles.size() - 1))
	_profile_is_new_draft = false
	_refresh_profiles_list()
	_update_profile_action_state()
	_set_status("Deleted profile: %s" % removed_name)


func _profile_service() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var svc: Object = registry.get_service("Profile")
		if svc == null:
			var adapter: Object = registry.get_service("ProfileAdapter")
			if adapter != null:
				push_warning("DMWindow: 'Profile' service missing — falling back to 'ProfileAdapter'")
				svc = adapter
		if svc != null:
			return svc as Node
	return null


func _on_profile_save_pressed() -> void:
	var ps_node: Node = _profile_service()
	var gs_node: Node = _game_state()
	if _profile_is_new_draft:
		var created := PlayerProfile.new()
		if not _apply_form_to_profile(created):
			return
		if ps_node != null and ps_node.has_method("add_profile"):
			ps_node.add_profile(created)
			if ps_node.has_method("save_profiles"):
				ps_node.save_profiles()
		elif gs_node != null:
			gs_node.profiles.append(created)
			if gs_node.has_method("save_profiles"):
				gs_node.save_profiles()
		_profile_is_new_draft = false
		_profile_selected_index = _find_profile_index_by_id(created.id)
		_refresh_profiles_list()
		_update_profile_action_state()
		_set_status("Created profile: %s (PP %d)" % [created.player_name, created.get_passive_perception()])
		return

	# Determine the profiles array from service or GameState
	var profiles_arr: Array = []
	if ps_node != null and ps_node.has_method("get_profiles"):
		profiles_arr = ps_node.get_profiles()
	elif gs_node != null:
		profiles_arr = gs_node.profiles
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

	# Persist changes via service when available, otherwise GameState
	if ps_node != null and ps_node.has_method("save_profiles"):
		# service owns the profiles array; save the service-managed profiles
		ps_node.save_profiles()
	elif gs_node != null and gs_node.has_method("save_profiles"):
		gs_node.profiles[_profile_selected_index] = p
		gs_node.save_profiles()

	_apply_profile_bindings()
	_refresh_profiles_list()
	_update_profile_action_state()
	_set_status("Saved profile: %s (PP %d) to user://data/profiles.json" % [p.player_name, p.get_passive_perception()])


func _on_profile_cancel_new_pressed() -> void:
	if not _profile_is_new_draft:
		return
	_profile_is_new_draft = false
	var gs_node: Node = _game_state()
	if gs_node == null or gs_node.profiles.is_empty():
		_profile_selected_index = -1
		_clear_profile_form()
	else:
		_profile_selected_index = clampi(_profile_selected_index, 0, gs_node.profiles.size() - 1)
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
		if nm != null and nm.has_method("get_peer_bound_player"):
			var seen_raw = nm.get_peer_bound_player(peer_id)
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

	var extras_raw := _profile_extras_edit.text.strip_edges()
	if extras_raw.is_empty():
		p.extras = {}
	else:
		var parsed: Variant = JsonUtils.parse_json_text(extras_raw)
		if parsed == null or not parsed is Dictionary:
			_set_status("Extras must be valid JSON object; profile not saved.")
			return false
		p.extras = (parsed as Dictionary).duplicate(true)
	p.extras["is_dashing"] = _profile_dash_check.button_pressed if _profile_dash_check else false

	p.ensure_id()
	return true


func _find_profile_index_by_id(profile_id: String) -> int:
	var ps_node: Node = _profile_service()
	var gs_node: Node = _game_state()
	var profiles_arr: Array = []
	if ps_node != null and ps_node.has_method("get_profiles"):
		profiles_arr = ps_node.get_profiles()
	elif gs_node != null:
		profiles_arr = gs_node.profiles
	for i in range(profiles_arr.size()):
		var profile = profiles_arr[i]
		if profile is PlayerProfile and (profile as PlayerProfile).id == profile_id:
			return i
	return max(0, profiles_arr.size() - 1)


func _update_profile_action_state() -> void:
	var gs_node: Node = _game_state()
	var has_selected: bool = gs_node != null and _profile_selected_index >= 0 and _profile_selected_index < gs_node.profiles.size() and not _profile_is_new_draft
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
		if nm != null and nm.has_method("get_connected_input_peers"):
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
	if input != null and input.has_method("clear_all_bindings"):
		input.clear_all_bindings()
	elif InputManager and InputManager.has_method("clear_all_bindings"):
		InputManager.clear_all_bindings()
	var nm := _network()
	if nm != null and nm.has_method("clear_all_peer_bindings"):
		nm.clear_all_peer_bindings()
	var ps_node: Node = _profile_service()
	var gs_node: Node = _game_state()
	var profiles_arr: Array = Array()
	if ps_node != null and ps_node.has_method("get_profiles"):
		profiles_arr = ps_node.get_profiles()
	elif gs_node != null:
		profiles_arr = gs_node.profiles
	for profile in profiles_arr:
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		p.ensure_id()
		if gs_node != null and gs_node.has_method("register_player"):
			gs_node.register_player(p.id)
		match p.input_type:
			PlayerProfile.InputType.GAMEPAD:
				# Bind by numeric device id if present
				if p.input_id.is_valid_int() and input != null and input.has_method("bind_gamepad"):
					input.bind_gamepad(int(p.input_id), p.id)
				elif p.input_id.is_valid_int() and InputManager and InputManager.has_method("bind_gamepad"):
					InputManager.bind_gamepad(int(p.input_id), p.id)
				# Otherwise try to match by device name substring, or auto-bind first free device
				elif p.input_id != "" and input != null and input.has_method("bind_gamepad"):
					for device_id in Input.get_connected_joypads():
						var joy_name := Input.get_joy_name(device_id)
						if joy_name != null and joy_name.to_lower().find(p.input_id.to_lower()) >= 0:
							input.bind_gamepad(device_id, p.id)
							break
				elif p.input_id != "" and InputManager and InputManager.has_method("bind_gamepad"):
					for device_id in Input.get_connected_joypads():
						var joy_name := Input.get_joy_name(device_id)
						if joy_name != null and joy_name.to_lower().find(p.input_id.to_lower()) >= 0:
							InputManager.bind_gamepad(device_id, p.id)
							break
				else:
					# Auto-bind: first connected device not already bound
					if input != null and input.has_method("bind_gamepad"):
						var connected := Input.get_connected_joypads()
						for device_id in connected:
							var already := false
							if input.has_method("has_gamepad_binding"):
								already = input.has_gamepad_binding(device_id)
							elif InputManager and InputManager.gamepad_bindings != null:
								already = InputManager.gamepad_bindings.has(device_id)
							if not already:
								input.bind_gamepad(device_id, p.id)
								break
					elif InputManager and InputManager.has_method("bind_gamepad"):
						var connected := Input.get_connected_joypads()
						for device_id in connected:
							if not InputManager.gamepad_bindings.has(device_id):
								InputManager.bind_gamepad(device_id, p.id)
								break
			PlayerProfile.InputType.WEBSOCKET:
				if p.input_id.is_valid_int() and nm != null and nm.has_method("bind_peer"):
					nm.bind_peer(int(p.input_id), p.id)
	_player_state_dirty = true
	_player_state_countdown = 0.0


func _on_profiles_changed() -> void:
	_apply_profile_bindings()
	if _backend and _backend.has_method("sync_profiles"):
		_backend.sync_profiles()
	_broadcast_player_state()
	if _profiles_dialog and _profiles_dialog.visible:
		_refresh_profiles_list()
	_update_profile_action_state()


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
	# Prefer using the Persistence service to generate export content when available.
	# If Persistence supports `export_to_path` we can avoid writing a temp file.
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var persistence: Node = registry.get_service("Persistence") as Node
		if persistence == null:
			persistence = registry.get_service("PersistenceAdapter") as Node
		if persistence != null:
			var payload := {"profiles": _profiles_to_array()}
			# If adapter/service offers direct export, use it.
			if persistence.has_method("save_game") and persistence.has_method("export_to_path"):
				if persistence.save_game("profiles_export", payload) and persistence.export_to_path("profiles_export", target_path):
					if persistence.has_method("delete_save"):
						persistence.delete_save("profiles_export")
					_set_status("Exported %d profiles." % payload["profiles"].size())
					return
			# Otherwise fallback to writing directly to the chosen path
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_set_status("Export failed: could not write file.")
		return
	file.store_string(JSON.stringify(_profiles_to_array(), "\t"))
	file.close()
	var ps_node: Node = _profile_service()
	var count := 0
	if ps_node != null and ps_node.has_method("get_profiles"):
		count = ps_node.get_profiles().size()
	else:
		var gs_node: Node = _game_state()
		count = gs_node.profiles.size() if gs_node != null else 0
	_set_status("Exported %d profiles." % count)


func _on_profiles_import_path_selected(path: String) -> void:
	var parsed: Variant = null
	# If the selected path is under user:// and Persistence is available prefer it
	var registry := get_node_or_null("/root/ServiceRegistry")
	if path.begins_with("user://") and registry != null and registry.has_method("get_service"):
		var persistence: Node = registry.get_service("Persistence") as Node
		if persistence == null:
			persistence = registry.get_service("PersistenceAdapter") as Node
		if persistence != null and persistence.has_method("load_game"):
			var save_name := path.get_file().get_basename()
			var loaded: Variant = persistence.load_game(save_name)
			if loaded is Array:
				parsed = loaded
			elif loaded is Dictionary and loaded.has("profiles"):
				parsed = loaded["profiles"]
			else:
				parsed = null
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
		parsed = JsonUtils.parse_json_text(text)
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
	var ps_node: Node = _profile_service()
	var gs_node: Node = _game_state()
	if ps_node != null:
		ps_node.profiles = imported_profiles
		if ps_node.has_method("save_profiles"):
			ps_node.save_profiles()
		if ps_node.has_method("load_profiles"):
			ps_node.load_profiles()
	elif gs_node != null:
		gs_node.profiles = imported_profiles
		if gs_node.has_method("save_profiles"):
			gs_node.save_profiles()
		if gs_node.has_method("load_profiles"):
			gs_node.load_profiles()
	_profile_selected_index = 0
	_refresh_profiles_list()
	_set_status("Imported %d profiles." % imported_profiles.size())


func _profiles_to_array() -> Array:
	var out: Array = []
	var ps_node: Node = _profile_service()
	var gs_node: Node = _game_state()
	var profiles_arr: Array = Array()
	if ps_node != null and ps_node.has_method("get_profiles"):
		profiles_arr = ps_node.get_profiles()
	elif gs_node != null:
		profiles_arr = gs_node.profiles
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

	# Prefer using Persistence copy API when available
	var registry := get_node_or_null("/root/ServiceRegistry")
	var copy_err := _copy_file(src_path, img_dest_abs)
	if registry != null and registry.has_method("get_service"):
		var persistence: Node = registry.get_service("Persistence") as Node
		if persistence == null:
			persistence = registry.get_service("PersistenceAdapter") as Node
		if persistence != null and persistence.has_method("copy_file"):
			copy_err = persistence.copy_file(src_path, img_dest_abs)
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
	# Keep registered Map service in sync if available
	var ms := _map_service()
	if ms != null:
		if ms.has_method("update_map"):
			ms.update_map(map)
		elif ms.has_method("load_map"):
			ms.load_map(map)
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
	if ms != null and ms.has_method("load_map_from_bundle"):
		map = ms.load_map_from_bundle(bundle_path)
	else:
		map = _load_map_from_bundle(bundle_path)
	if map == null:
		_set_status("Failed to load map from: %s" % bundle_path.get_file())
		return
	_active_map_bundle_path = bundle_path
	_apply_map(map)
	# Ensure map service knows about this map
	if ms != null:
		if ms.has_method("load_map"):
			ms.load_map(map)
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
	if _map_view and _map_view.has_method("force_fog_sync"):
		_map_view.force_fog_sync()
	_map_view.save_camera_to_map()
	_save_map_data(map)
	var ms := _map_service()
	if ms != null:
		if ms.has_method("update_map"):
			ms.update_map(map)
		elif ms.has_method("load_map"):
			ms.load_map(map)
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
		# Prefer using Persistence copy API when available
		var registry := get_node_or_null("/root/ServiceRegistry")
		var copy_err := _copy_file(map.image_path, new_img_abs)
		if registry != null and registry.has_method("get_service"):
			var persistence: Node = registry.get_service("Persistence") as Node
			if persistence == null:
				persistence = registry.get_service("PersistenceAdapter") as Node
			if persistence != null and persistence.has_method("copy_file"):
				copy_err = persistence.copy_file(map.image_path, new_img_abs)
		if copy_err != OK:
			push_error("DMWindow: failed to copy image for save-as (err %d)" % copy_err)
			_set_status("Error: could not duplicate image.")
			return

	if _map_view and _map_view.has_method("force_fog_sync"):
		_map_view.force_fog_sync()
	_map_view.save_camera_to_map()
	map.map_name = bundle_path.get_file().get_basename()
	map.image_path = new_img_abs
	_active_map_bundle_path = bundle_path
	_save_map_data(map)
	var ms := _map_service()
	if ms != null:
		if ms.has_method("update_map"):
			ms.update_map(map)
		elif ms.has_method("load_map"):
			ms.load_map(map)
	_nm_broadcast_map_update(map)
	_set_status("Saved as: %s" % map.map_name)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _apply_map(map: MapData) -> void:
	_map_view.load_map(map)
	if _map_view.map_image.texture == null:
		_set_status("Map image failed to load: %s" % map.image_path)
		return
	# Player cam is initialised to the DM's initial view once the camera settles.
	call_deferred("_init_player_cam_from_dm")
	if _backend and _backend.has_method("reset_for_new_map"):
		_backend.reset_for_new_map()
	_broadcast_fog_state()
	_broadcast_player_state()
	_grid_option.disabled = false
	_grid_option.select(_grid_option.get_item_index(map.grid_type))


func _simulate_player_movement(delta: float) -> bool:
	if _backend == null:
		return false
	if not _backend.has_method("step"):
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
	if _backend and _backend.has_method("build_player_state_payload"):
		players = _backend.build_player_state_payload()
	_nm_broadcast_to_displays({"msg": "state", "players": players})


func _update_dm_override_input() -> void:
	var primary_player_id := ""
	var gs_node: Node = _game_state()
	var profiles_arr: Array = Array()
	if gs_node != null:
		profiles_arr = gs_node.profiles
	for profile in profiles_arr:
		if profile is PlayerProfile:
			primary_player_id = (profile as PlayerProfile).id
			break

	var input := _input_service()
	if _dm_override_player_id != "" and _dm_override_player_id != primary_player_id:
		if input != null and input.has_method("clear_dm_vector"):
			input.clear_dm_vector(_dm_override_player_id)
		elif InputManager and InputManager.has_method("clear_dm_vector"):
			InputManager.clear_dm_vector(_dm_override_player_id)

	_dm_override_player_id = primary_player_id
	if _dm_override_player_id == "":
		return

	if input != null and input.has_method("set_dm_vector"):
		input.set_dm_vector(_dm_override_player_id, _keyboard_temp_vector())
	elif InputManager and InputManager.has_method("set_dm_vector"):
		InputManager.set_dm_vector(_dm_override_player_id, _keyboard_temp_vector())


func _on_map_fog_changed(_map_data: MapData) -> void:
	if not _ENABLE_CONTINUOUS_FOG_SYNC:
		_queue_fog_snapshot_sync(_FOG_AUTO_SYNC_DEBOUNCE)
		return
	_fog_dirty = true
	if _fog_countdown <= 0.0:
		_fog_dirty = false
		_broadcast_fog_truth_state()
		_fog_countdown = _FOG_BROADCAST_DEBOUNCE


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
	_broadcast_fog_truth_state()
	_set_status("Fog sync queued to player displays.")


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


func _broadcast_fog_state() -> void:
	if _map_view == null:
		return
	if _fog_snapshot_in_flight:
		_fog_snapshot_queued = true
		return
	if _nm_displays_under_backpressure():
		_queue_fog_snapshot_sync(0.5)
		return
	if _map_view.has_method("force_fog_sync"):
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


func _broadcast_fog_truth_state() -> void:
	if _map_view == null:
		return
	if _nm_displays_under_backpressure():
		_queue_fog_snapshot_sync(0.5)
		return
	var map: MapData = _map()
	if map == null:
		return
	_queue_fog_truth_chunked(map)


func _queue_fog_truth_chunked(map: MapData) -> void:
	var queue: Array = []
	var serial_cells := _serialise_fog_cells(map.fog_hidden_cells)
	var total_cells := serial_cells.size()
	var chunk_size := maxi(1, _FOG_TRUTH_MAX_CELLS_PER_CHUNK)
	var chunks := int(ceil(float(total_cells) / float(chunk_size)))
	chunks = maxi(1, chunks)

	queue.append({
		"msg": "fog_truth_begin",
		"fog_cell_px": int(maxi(1, map.fog_cell_px)),
		"chunks": chunks,
	})

	if total_cells == 0:
		queue.append({
			"msg": "fog_truth_chunk",
			"index": 0,
			"chunks": 1,
			"hidden_cells": [],
		})
		queue.append({
			"msg": "fog_truth_end",
			"chunks": 1,
		})
		_fog_truth_send_queue = queue
		_fog_truth_send_index = 0
		return

	for i in range(chunks):
		var start := i * chunk_size
		var end := mini(total_cells, start + chunk_size)
		var chunk := serial_cells.slice(start, end)
		queue.append({
			"msg": "fog_truth_chunk",
			"index": i,
			"chunks": chunks,
			"hidden_cells": chunk,
		})

	queue.append({
		"msg": "fog_truth_end",
		"chunks": chunks,
	})
	_fog_truth_send_queue = queue
	_fog_truth_send_index = 0


func _pump_fog_truth_send_queue() -> void:
	if _fog_truth_send_index >= _fog_truth_send_queue.size():
		if _fog_truth_send_queue.size() > 0:
			_fog_truth_send_queue.clear()
			_fog_truth_send_index = 0
		return
	if _nm_displays_under_backpressure():
		return
	var sent := 0
	var per_frame := maxi(1, _FOG_TRUTH_CHUNKS_PER_FRAME)
	while sent < per_frame and _fog_truth_send_index < _fog_truth_send_queue.size():
		var msg: Variant = _fog_truth_send_queue[_fog_truth_send_index]
		if msg is Dictionary:
			_nm_broadcast_to_displays(msg as Dictionary)
		_fog_truth_send_index += 1
		sent += 1


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
	if _map_view == null:
		return
	var state: Dictionary = _map_view.get_camera_state()
	_player_cam_pos = Vector2(state["position"]["x"], state["position"]["y"])
	_player_cam_zoom = float(state["zoom"])
	_update_viewport_indicator()
	_broadcast_player_viewport()


func _maps_dir_abs() -> String:
	return ProjectSettings.globalize_path(MAP_DIR)


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
	## Handles all native-dialog return variants:
	## - direct ".map" directory/package
	## - "map.json" file inside bundle
	## - any file/folder nested under a bundle
	if path.is_empty():
		return ""

	var raw := path
	if raw.get_file().to_lower() == "map.json":
		raw = raw.get_base_dir()

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

	# Fallback: if user selected a plain folder containing map.json, allow it.
	if DirAccess.dir_exists_absolute(raw):
		var maybe_json := raw.path_join("map.json")
		if FileAccess.file_exists(maybe_json):
			return raw

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
	if ms != null and ms.has_method("save_map_to_bundle"):
		# Let MapService handle bundle serialization/consistency when available.
		if ms.has_method("update_map"):
			ms.update_map(map)
		ms.save_map_to_bundle(_active_map_bundle_path)
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
	var parsed: Variant = JsonUtils.parse_json_text(text)
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


func _apply_ui_scale() -> void:
	var scale := _ui_scale()
	if _toolbar:
		# Slightly shorter than before so the bar hugs its controls better.
		_toolbar.custom_minimum_size = Vector2(0, roundi(34.0 * scale))
	if _ui_root:
		_ui_root.scale = Vector2(scale, scale)
	if _profiles_dialog:
		var vp := get_viewport().get_visible_rect().size
		_profiles_dialog.min_size = Vector2i(roundi(vp.x * 0.72), roundi(vp.y * 0.72))
		var close_btn := _profiles_dialog.get_ok_button()
		if close_btn:
			close_btn.custom_minimum_size = Vector2(roundi(110.0 * scale), roundi(34.0 * scale))
			close_btn.add_theme_font_size_override("font_size", roundi(14.0 * scale))
	if _profiles_root:
		_profiles_root.scale = Vector2(scale, scale)


func _ui_scale() -> float:
	## Blend DPI scaling with viewport-relative scaling so fullscreen does not
	## make UI appear tiny on large displays.
	var dpi_scale := clampf(DisplayServer.screen_get_dpi() / 96.0, 1.0, 2.0)
	var vp := get_viewport().get_visible_rect().size
	var viewport_scale := clampf(minf(vp.x / 1920.0, vp.y / 1080.0), 1.0, 1.6)
	return maxf(dpi_scale, viewport_scale)
