extends Node

# ---------------------------------------------------------------------------
# DMWindow — top-level UI controller for the DM process.
#
# Provides:
#   • MenuBar with File / Edit / View menus
#   • Collapsible toolbar with Select / Pan tool toggle + Zoom controls +
#     Grid-type selector + status label
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

var _toolbar: Control = null ## HBoxContainer — shown/hidden by View menu
var _select_btn: Button = null
var _pan_btn: Button = null
var _view_menu: PopupMenu = null ## kept for checkmark management

# ── Player viewport control ─────────────────────────────────────────────────
# The green box on the DM map shows what players currently see.
# Drag the box to reposition the player camera; use the toolbar to zoom.
var _player_cam_pos: Vector2 = Vector2(960.0, 540.0)
var _player_cam_zoom: float = 1.0
var _player_window_size: Vector2 = Vector2(1920.0, 1080.0)
var _play_mode: bool = false
var _play_mode_btn: Button = null

const _BROADCAST_DEBOUNCE: float = 0.05 ## seconds — near-instant feel
var _broadcast_dirty: bool = false
var _broadcast_countdown: float = 0.0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_build_ui()
	NetworkManager.display_peer_registered.connect(_on_display_peer_registered)
	NetworkManager.display_viewport_resized.connect(_on_display_viewport_resized)
	print("DMWindow: ready (Phase 2 complete — map CRUD, calibration offset)")


func _process(delta: float) -> void:
	# Broadcast queued player-viewport updates after a short debounce.
	if not _broadcast_dirty:
		return
	_broadcast_countdown -= delta
	if _broadcast_countdown <= 0.0:
		_broadcast_dirty = false
		_broadcast_player_viewport()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# ── MapView ─────────────────────────────────────────────────────────────
	_map_view = MapViewScene.instantiate()
	_map_view.name = "MapView"
	add_child(_map_view)

	# CalibrationTool lives inside MapView's world-space so its drawn overlay
	# follows the camera correctly.
	_cal_tool = load("res://scripts/CalibrationTool.gd").new()
	_cal_tool.name = "CalibrationTool"
	_map_view.add_child(_cal_tool)

	# ── CanvasLayer for UI (always on top) ───────────────────────────────────
	var ui_layer := CanvasLayer.new()
	ui_layer.name = "UILayer"
	ui_layer.layer = 10
	add_child(ui_layer)

	# Root VBox pinned to the full top edge
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ui_layer.add_child(root_vbox)

	# ── Menu bar ─────────────────────────────────────────────────────────────
	var menu_bar := MenuBar.new()
	menu_bar.prefer_global_menu = true ## merge into native OS menu bar
	root_vbox.add_child(menu_bar)

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
	edit_menu.id_pressed.connect(_on_edit_menu_id)
	menu_bar.add_child(edit_menu)

	# View menu  (indices matter for set_item_checked)
	# idx 0 → id 20 Toolbar
	# idx 1 → id 21 Grid Overlay
	# idx 2 → separator
	# idx 3 → id 22 Reset View
	_view_menu = PopupMenu.new()
	_view_menu.name = "View"
	_view_menu.add_check_item("Toolbar", 20)
	_view_menu.set_item_checked(0, true)
	_view_menu.add_check_item("Grid Overlay", 21)
	_view_menu.set_item_checked(1, true)
	_view_menu.add_separator()
	_view_menu.add_item("Reset View", 22)
	_view_menu.add_separator()
	_view_menu.add_item("▶ Launch Player Window", 23)
	_view_menu.id_pressed.connect(_on_view_menu_id)
	menu_bar.add_child(_view_menu)

	# ── Toolbar ──────────────────────────────────────────────────────────────
	_toolbar = PanelContainer.new()
	_toolbar.name = "Toolbar"
	_toolbar.custom_minimum_size = Vector2(0, 44)
	root_vbox.add_child(_toolbar)

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
	_select_btn.text = "↖  Select"
	_select_btn.toggle_mode = true
	_select_btn.button_pressed = true
	_select_btn.button_group = tool_group
	_select_btn.focus_mode = Control.FOCUS_NONE
	_select_btn.tooltip_text = "Select tool"
	_select_btn.pressed.connect(func(): _on_tool_changed(0))
	toolbar_hbox.add_child(_select_btn)

	_pan_btn = Button.new()
	_pan_btn.text = "✋ Pan"
	_pan_btn.toggle_mode = true
	_pan_btn.button_group = tool_group
	_pan_btn.focus_mode = Control.FOCUS_NONE
	_pan_btn.tooltip_text = "Pan tool — left-drag to pan"
	_pan_btn.pressed.connect(func(): _on_tool_changed(1))
	toolbar_hbox.add_child(_pan_btn)

	var sep1 := VSeparator.new()
	toolbar_hbox.add_child(sep1)

	# Zoom controls
	var zoom_in_btn := _make_toolbar_btn("Zoom +", "Zoom in (scroll up)")
	zoom_in_btn.pressed.connect(func(): if _map_view: _map_view.zoom_in())
	toolbar_hbox.add_child(zoom_in_btn)

	var zoom_out_btn := _make_toolbar_btn("Zoom −", "Zoom out (scroll down)")
	zoom_out_btn.pressed.connect(func(): if _map_view: _map_view.zoom_out())
	toolbar_hbox.add_child(zoom_out_btn)

	var reset_btn := _make_toolbar_btn("Reset View", "Fit map to window")
	reset_btn.pressed.connect(func(): if _map_view: _map_view._reset_camera())
	toolbar_hbox.add_child(reset_btn)

	var sep2 := VSeparator.new()
	toolbar_hbox.add_child(sep2)

	# Grid type selector
	var grid_label := Label.new()
	grid_label.text = "Grid:"
	grid_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar_hbox.add_child(grid_label)

	_grid_option = OptionButton.new()
	_grid_option.add_item("Square", MapData.GridType.SQUARE)
	_grid_option.add_item("Hex (flat)", MapData.GridType.HEX_FLAT)
	_grid_option.add_item("Hex (pointy)", MapData.GridType.HEX_POINTY)
	_grid_option.disabled = true
	_grid_option.focus_mode = Control.FOCUS_NONE
	_grid_option.item_selected.connect(_on_grid_type_selected)
	toolbar_hbox.add_child(_grid_option)

	var sep3 := VSeparator.new()
	toolbar_hbox.add_child(sep3)

	var pv_label := Label.new()
	pv_label.text = "Player View:"
	pv_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar_hbox.add_child(pv_label)

	var pv_zoom_in_btn := _make_toolbar_btn("Zoom +", "Zoom player viewport in")
	pv_zoom_in_btn.pressed.connect(func(): _change_player_zoom(0.15))
	toolbar_hbox.add_child(pv_zoom_in_btn)

	var pv_zoom_out_btn := _make_toolbar_btn("Zoom \u2212", "Zoom player viewport out")
	pv_zoom_out_btn.pressed.connect(func(): _change_player_zoom(-0.15))
	toolbar_hbox.add_child(pv_zoom_out_btn)

	var pv_sync_btn := _make_toolbar_btn("Sync to DM", "Snap player view to match your current view")
	pv_sync_btn.pressed.connect(_sync_player_to_dm_view)
	toolbar_hbox.add_child(pv_sync_btn)

	var sep4 := VSeparator.new()
	toolbar_hbox.add_child(sep4)

	_play_mode_btn = Button.new()
	_play_mode_btn.text = "\u25b6 Play Mode"
	_play_mode_btn.toggle_mode = true
	_play_mode_btn.focus_mode = Control.FOCUS_NONE
	_play_mode_btn.tooltip_text = "Launch the Player display window"
	_play_mode_btn.pressed.connect(_on_play_mode_pressed)
	toolbar_hbox.add_child(_play_mode_btn)

	# Spacer pushes status label to the right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar_hbox.add_child(spacer)

	_status_label = Label.new()
	_status_label.text = "No map loaded"
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar_hbox.add_child(_status_label)

	var pad_right := Control.new()
	pad_right.custom_minimum_size = Vector2(8, 0)
	toolbar_hbox.add_child(pad_right)

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

	# ── Open Map dialog ──────────────────────────────────────────────────────
	# ── Open Map dialog — user selects a .map bundle path ─────────────────────
	_open_map_dialog = FileDialog.new()
	_open_map_dialog.use_native_dialog = true
	_open_map_dialog.file_mode = FileDialog.FILE_MODE_OPEN_ANY
	_open_map_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_map_dialog.title = "Open Map"
	_open_map_dialog.add_filter("*.map ; OmniCrawl Map")
	_open_map_dialog.file_selected.connect(_on_map_bundle_selected)
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

	# ── Standalone Grid Offset dialog (Edit > Set Grid Offset) ───────────────
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

	# Player viewport indicator — DM drags the green box on the main map
	# to reposition what players see. Hidden until a map is loaded.
	_map_view.set_viewport_indicator(Rect2())
	_map_view.viewport_indicator_moved.connect(_on_viewport_indicator_moved)


# ---------------------------------------------------------------------------
# Player viewport helpers
# ---------------------------------------------------------------------------

func _on_display_peer_registered(_peer_id: int, viewport_size: Vector2) -> void:
	## A new Player display process just completed its handshake.
	## Update the assumed player window size from the real viewport dimensions,
	## then re-broadcast the current map and camera so the late-joining player
	## isn't stuck on a blank screen.
	_player_window_size = viewport_size
	var map: MapData = _map_view.get_map() if _map_view else null
	if map == null:
		return
	_update_viewport_indicator()
	NetworkManager.broadcast_map(map)
	_broadcast_player_viewport()


func _on_display_viewport_resized(_peer_id: int, viewport_size: Vector2) -> void:
	## Player window was resized — update the indicator box immediately.
	_player_window_size = viewport_size
	_update_viewport_indicator()


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


func _broadcast_player_viewport() -> void:
	NetworkManager.broadcast_to_displays({
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
		23: # Launch player display process
			_launch_player_process()


# ---------------------------------------------------------------------------
# Tool toggle (Select = 0, Pan = 1)
# ---------------------------------------------------------------------------

func _on_tool_changed(tool: int) -> void:
	if _map_view:
		# MapView.Tool enum values match 0 / 1
		_map_view.active_tool = tool
	match tool:
		0: _set_status("Tool: Select")
		1: _set_status("Tool: Pan  (left-drag to pan)")


# ---------------------------------------------------------------------------
# Grid type handler
# ---------------------------------------------------------------------------

func _on_grid_type_selected(index: int) -> void:
	var map: MapData = _map_view.get_map() if _map_view else null
	if map == null:
		return
	map.grid_type = _grid_option.get_item_id(index)
	_map_view.grid_overlay.apply_map_data(map)
	NetworkManager.broadcast_map_update(map)
	_set_status("Grid: %s" % _grid_option.get_item_text(index))


# ---------------------------------------------------------------------------
# Calibration workflow
# ---------------------------------------------------------------------------

func _on_calibrate_pressed() -> void:
	var map: MapData = _map_view.get_map() if _map_view else null
	if map == null:
		_set_status("Load a map first.")
		return
	# Ensure we're in Select mode during calibration (no accidental drag pan)
	_map_view.active_tool = 0 # Tool.SELECT
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
	NetworkManager.broadcast_map_update(map)
	var detail := ("cell_px=%.1f" % map.cell_px) if map.grid_type == MapData.GridType.SQUARE else ("hex_size=%.1f" % map.hex_size)
	_set_status("Calibrated: %s  offset=(%.0f, %.0f)" % [detail, map.grid_offset.x, map.grid_offset.y])


# ---------------------------------------------------------------------------
# Manual scale handlers
# ---------------------------------------------------------------------------

func _on_manual_scale_pressed() -> void:
	var map: MapData = _map_view.get_map() if _map_view else null
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
	var map: MapData = _map_view.get_map() if _map_view else null
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
	NetworkManager.broadcast_map_update(map)
	_set_status("Scale set: %.1f px = %.0f ft" % [px_per_cell, ft_per_cell])


# ---------------------------------------------------------------------------
# Standalone Grid Offset handler (Edit > Set Grid Offset…)
# ---------------------------------------------------------------------------

func _on_set_offset_pressed() -> void:
	var map: MapData = _map_view.get_map() if _map_view else null
	if map == null:
		_set_status("Load a map first.")
		return
	_solo_offset_x_spin.value = map.grid_offset.x
	_solo_offset_y_spin.value = map.grid_offset.y
	_offset_dialog.popup_centered(Vector2i(320, 160))


func _on_offset_confirmed() -> void:
	var map: MapData = _map_view.get_map() if _map_view else null
	if map == null:
		return
	map.grid_offset = Vector2(_solo_offset_x_spin.value, _solo_offset_y_spin.value)
	_map_view.grid_overlay.apply_map_data(map)
	NetworkManager.broadcast_map_update(map)
	_set_status("Grid offset: (%.0f, %.0f)" % [map.grid_offset.x, map.grid_offset.y])


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

	var err := _copy_file(src_path, img_dest_abs)
	if err != OK:
		push_error("DMWindow: failed to copy image to '%s' (err %d)" % [img_dest_abs, err])
		_set_status("Error: could not copy image.")
		return

	var map := MapData.new()
	map.map_name = bundle_path.get_file().get_basename()
	map.image_path = img_dest_abs
	_active_map_bundle_path = bundle_path
	_save_map_data(map)
	_apply_map(map)
	NetworkManager.broadcast_map(map)
	_set_status("New map: %s" % map.map_name)


func _on_open_map_pressed() -> void:
	## Open a previously saved .map file.
	_ensure_maps_dir()
	_open_map_dialog.current_dir = _maps_dir_abs()
	_open_map_dialog.popup_centered(Vector2i(900, 600))


func _on_map_bundle_selected(path: String) -> void:
	## Load the map stored inside the selected .map bundle.
	var bundle_path := _normalise_bundle_path(path)
	var map := _load_map_from_bundle(bundle_path)
	if map == null:
		_set_status("Failed to load map from: %s" % bundle_path.get_file())
		return
	_active_map_bundle_path = bundle_path
	_apply_map(map)
	NetworkManager.broadcast_map(map)
	_set_status("Opened: %s" % map.map_name)


func _on_save_map_pressed() -> void:
	var map: MapData = _map_view.get_map() if _map_view else null
	if map == null:
		_set_status("Nothing to save.")
		return
	if _active_map_bundle_path.is_empty():
		_on_save_map_as_pressed()
		return
	_map_view.save_camera_to_map()
	_save_map_data(map)
	NetworkManager.broadcast_map_update(map)
	_set_status("Saved: %s" % map.map_name)


func _on_save_map_as_pressed() -> void:
	var map: MapData = _map_view.get_map() if _map_view else null
	if map == null:
		_set_status("Nothing to save.")
		return
	_map_name_mode = "save_as"
	_save_as_dialog.current_file = map.map_name + ".map"
	_save_as_dialog.current_dir = _active_map_bundle_path.get_base_dir() if not _active_map_bundle_path.is_empty() else _maps_dir_abs()
	_save_as_dialog.popup_centered(Vector2i(900, 600))


func _save_map_as_path(bundle_path: String) -> void:
	## Copy the current map into a new .map bundle and switch to it.
	var map: MapData = _map_view.get_map()
	if map == null:
		return
	_ensure_bundle_dir(bundle_path)
	var ext: String = map.image_path.get_extension().to_lower()
	var new_img_abs: String = _image_dest_path_abs(bundle_path, ext)

	# Only copy image if destination is different from source.
	if new_img_abs != map.image_path:
		var err := _copy_file(map.image_path, new_img_abs)
		if err != OK:
			push_error("DMWindow: failed to copy image for save-as (err %d)" % err)
			_set_status("Error: could not duplicate image.")
			return

	_map_view.save_camera_to_map()
	map.map_name = bundle_path.get_file().get_basename()
	map.image_path = new_img_abs
	_active_map_bundle_path = bundle_path
	_save_map_data(map)
	NetworkManager.broadcast_map_update(map)
	_set_status("Saved as: %s" % map.map_name)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _apply_map(map: MapData) -> void:
	_map_view.load_map(map)
	# Player cam is initialised to the DM's initial view once the camera settles.
	call_deferred("_init_player_cam_from_dm")
	_grid_option.disabled = false
	_grid_option.select(_grid_option.get_item_index(map.grid_type))


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


func _save_map_data(map: MapData) -> void:
	## Serialise MapData to map.json inside the active .map bundle directory.
	## image_path is stored as a relative filename so the bundle is self-contained.
	if _active_map_bundle_path.is_empty():
		_active_map_bundle_path = _bundle_dir_abs(map.map_name)
	_ensure_bundle_dir(_active_map_bundle_path)
	var path := _bundle_json_path_abs(_active_map_bundle_path)
	var d := map.to_dict()
	d["image_path"] = map.image_path.get_file()
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
	var parsed: Variant = JSON.parse_string(text)
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
