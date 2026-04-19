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
const BundleIOScript = preload("res://scripts/utils/BundleIO.gd")
const GameSaveDataScript = preload("res://scripts/services/game_state/models/GameSaveData.gd")
const ToolPaletteScript = preload("res://scripts/ui/ToolPalette.gd")
const BundleBrowserScript = preload("res://scripts/ui/BundleBrowser.gd")
const CampaignBrowserScript = preload("res://scripts/ui/CampaignBrowser.gd")
const NetworkUtilsScript = preload("res://scripts/utils/NetworkUtils.gd")
const QRCodeScript = preload("res://scripts/utils/QRCode.gd")
const EffectPanelScript = preload("res://scripts/ui/EffectPanel.gd")
const OverrideEditorScript = preload("res://scripts/ui/StatblockOverrideEditor.gd")
const DiceTrayScript = preload("res://scripts/ui/DiceTray.gd")
const CombatLogPanelScript = preload("res://scripts/ui/CombatLogPanel.gd")
const CharacterWizardScript = preload("res://scripts/ui/character_wizard/CharacterWizard.gd")
const CharacterSheetScript = preload("res://scripts/ui/CharacterSheet.gd")
const LevelUpWizardScript = preload("res://scripts/ui/character_wizard/LevelUpWizard.gd")

const MAP_DIR := "user://data/maps/"
const SAVE_DIR := "user://data/saves/"
const SUPPORTED_IMAGE_EXTENSIONS := MapData.SUPPORTED_IMAGE_EXTENSIONS
const SUPPORTED_VIDEO_EXTENSIONS := MapData.SUPPORTED_VIDEO_EXTENSIONS
const SUPPORTED_EXTENSIONS := SUPPORTED_IMAGE_EXTENSIONS + SUPPORTED_VIDEO_EXTENSIONS

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
var _active_map_bundle_path: String = "" ## absolute path to the current .map working directory
var _active_save_bundle_path: String = "" ## absolute path to the current .sav working directory
var _active_map_zip_path: String = "" ## ZIP path when working from a ZIP bundle (empty for legacy dirs)
var _active_save_zip_path: String = "" ## ZIP path for .sav bundles

## Bundle browser window (lazy-created, shared for maps and saves)
var _bundle_browser: Node = null

## Video conversion progress dialog
var _progress_dialog: AcceptDialog = null
var _progress_label: Label = null
var _progress_bar: ProgressBar = null
var _convert_thread: Thread = null
var _convert_result: int = -1
var _convert_pending_bundle: String = ""
var _convert_pending_dest: String = ""
var _convert_pending_src: String = ""
var _convert_progress_file: String = ""
var _convert_duration_us: float = 0.0
var _convert_progress_timer: Timer = null

## Video conversion settings dialog
var _convert_settings_dialog: ConfirmationDialog = null
var _convert_res_option: OptionButton = null
var _convert_fps_option: OptionButton = null
var _convert_vq_option: OptionButton = null

## Background audio volume window (View menu)
var _volume_window: Window = null
var _volume_slider: HSlider = null
var _volume_mute_btn: CheckButton = null
var _volume_label: Label = null
var _volume_vbox: VBoxContainer = null

var _status_label: Label = null
var _status_bar: PanelContainer = null
var _ui_root: VBoxContainer = null
var _map_spacer: Control = null ## map-area catchall; forwards gui_input to MapView

# Player profile form fields
var _profile_orientation_spin: SpinBox = null

var _menu_bar: MenuBar = null ## in-window MenuBar (0-height on macOS native menu)
var _native_menu: Node = null ## NativeWin32MenuBar instance (Windows only)
var _palette: PanelContainer = null ## Photoshop-style tool palette (ToolPalette)
var _view_menu: PopupMenu = null ## kept for checkmark management
var _edit_menu: PopupMenu = null ## kept for undo/redo label updates
var _grid_submenu: PopupMenu = null ## Grid Type submenu in View menu
var _theme_submenu: PopupMenu = null ## UI Theme submenu in View menu
var _statblock_library: StatblockLibrary = null ## Statblock Library window
var _item_library: ItemLibrary = null ## Item Library window
var _campaign_panel: CampaignPanel = null ## Campaign management hub
var _campaign_browser: Node = null ## Campaign selection browser (startup + post-close)
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
var _token_size_ft_spin: SpinBox = null
var _token_size_ft_row: HBoxContainer = null
var _token_roam_info_row: HBoxContainer = null
var _token_roam_info_label: Label = null
var _token_rotation_spin: SpinBox = null
var _token_shape_option: OptionButton = null
var _token_blocks_los_check: CheckBox = null
var _token_blocks_los_row: HBoxContainer = null
## Token icon image picker
var _token_icon_preview: TextureRect = null
var _token_icon_choose_btn: Button = null
var _token_icon_clear_btn: Button = null
var _token_icon_path_edit: LineEdit = null
var _token_icon_load_btn: Button = null
var _token_icon_pending_source: String = "" ## source file picked by file dialog
var _token_icon_file_dialog: FileDialog = null
var _token_icon_crop_btn: Button = null
var _token_icon_crop_offset: Vector2 = Vector2.ZERO
var _token_icon_crop_zoom: float = 1.0
var _token_icon_facing_deg: float = 0.0
var _token_icon_campaign_image_id: String = ""
## Puzzle notes sub-section
var _puzzle_notes_container: VBoxContainer = null
var _puzzle_notes_scroll: ScrollContainer = null
var _puzzle_notes_add_btn: Button = null
## Statblocks sub-section (MONSTER / NPC tokens)
var _token_statblocks_section: VBoxContainer = null
var _token_statblocks_list: ItemList = null
var _token_statblock_attach_btn: Button = null
var _token_statblock_detach_btn: Button = null
var _token_statblock_view_btn: Button = null
var _token_statblock_rollhp_btn: Button = null
var _token_statblock_edit_overrides_btn: Button = null
var _token_statblock_hp_spin: SpinBox = null
var _token_statblock_temphp_spin: SpinBox = null
var _token_statblock_hp_label: Label = null
var _token_statblock_visibility_option: OptionButton = null
## Pending statblock data edited in the token editor.
var _token_pending_statblock_refs: Array = []
var _token_pending_statblock_overrides: Dictionary = {}
## Right-click context menu for tokens
var _token_context_menu: PopupMenu = null
var _token_context_id: String = ""
## In-app clipboard for token copy/cut/paste (serialised TokenData snapshot).
var _token_clipboard: Dictionary = {}
## World position captured from background right-click for paste.
var _background_right_click_pos: Vector2 = Vector2.ZERO
## Background context menu (right-click on empty map space).
var _background_context_menu: PopupMenu = null
var _background_right_click_effect_id: String = ""
## Measurement right-click context menu.
var _measurement_context_menu: PopupMenu = null
var _measurement_context_id: String = ""

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

# ── Roam path panel ────────────────────────────────────────────────────────
var _roam_panel: PanelContainer = null
var _roam_token_label: Label = null
var _roam_mode_option: OptionButton = null
var _roam_loop_check: CheckBox = null
var _roam_speed_slider: HSlider = null
var _roam_speed_value_label: Label = null
var _roam_smooth_btn: Button = null
var _roam_play_btn: Button = null
var _roam_reset_btn: Button = null
var _roam_commit_btn: Button = null
var _roam_clear_btn: Button = null
var _selected_roam_token_id: String = ""
# Roam animation state: token_id → { progress: float, direction: int, playing: bool }
var _roaming_tokens: Dictionary = {}
const _ROAM_BROADCAST_INTERVAL: float = 0.033 # seconds between position broadcasts
# Drag state for roam-path offset: token_id → pre-drag world_pos.
var _drag_start_positions: Dictionary = {}

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
var _profile_delete_confirm_dialog: ConfirmationDialog = null
var _profile_delete_pending_id: String = ""
var _profile_delete_pending_name: String = ""
var _profile_delete_pending_index: int = -1
var _profile_delete_pending_snapshot: PlayerProfile = null
var _profile_undo_btn: Button = null
var _profile_save_btn: Button = null
var _profile_cancel_new_btn: Button = null
var _profile_selected_index: int = -1
var _profile_is_new_draft: bool = false
var _profiles_import_dialog: FileDialog = null
var _profiles_export_dialog: FileDialog = null
var _statblocks_import_dialog: FileDialog = null
var _statblocks_export_dialog: FileDialog = null
var _campaign_import_dialog: FileDialog = null
var _campaign_export_dialog: FileDialog = null
var _profiles_root: Control = null
var _profile_color_btn: ColorPickerButton = null
var _profile_active_check: CheckBox = null
var _profile_search_edit: LineEdit = null
var _profile_display_indices: Array = []
## Profile icon picker.
var _profile_icon_preview: TextureRect = null
var _profile_icon_choose_btn: Button = null
var _profile_icon_clear_btn: Button = null
var _profile_icon_path_edit: LineEdit = null
var _profile_icon_load_btn: Button = null
var _profile_icon_pending_source: String = ""
var _profile_icon_file_dialog: FileDialog = null
var _profile_icon_crop_btn: Button = null
var _profile_icon_crop_offset: Vector2 = Vector2.ZERO
var _profile_icon_crop_zoom: float = 1.0
var _profile_icon_facing_deg: float = 0.0
var _profile_icon_campaign_image_id: String = ""
var _profile_size_option: OptionButton = null
## Shared campaign image picker dialog (used by token and profile editors).
var _campaign_image_picker: CampaignImagePicker = null
## Shared crop editor dialog (used by both token and profile editors).
var _crop_editor_dialog: Window = null
var _crop_editor_canvas: Control = null
var _crop_editor_source_img: Image = null
var _crop_editor_source_tex: ImageTexture = null
var _crop_editor_offset: Vector2 = Vector2.ZERO
var _crop_editor_zoom: float = 1.0
var _crop_editor_dragging: bool = false
var _crop_editor_drag_start: Vector2 = Vector2.ZERO
var _crop_editor_offset_start: Vector2 = Vector2.ZERO
var _crop_editor_callback: Callable = Callable()
var _crop_editor_facing_deg: float = 0.0
var _crop_editor_facing_dragging: bool = false
var _crop_editor_vbox: VBoxContainer = null
var _crop_editor_btn_row: HBoxContainer = null
var _crop_editor_hint: Label = null
var _crop_editor_reset_btn: Button = null
var _crop_editor_cancel_btn: Button = null
var _crop_editor_ok_btn: Button = null
## Legacy autoload reference removed — use registry-first `_network()` helper

# ── Phase 23: character management ------------------------------------------
var _char_wizard: CharacterWizardScript = null
var _char_sheet: CharacterSheetScript = null
var _level_up_wizard: LevelUpWizardScript = null
var _char_mgr_dialog: AcceptDialog = null
var _char_mgr_list: ItemList = null
var _chars_assign_btn: Button = null
var _chars_remove_btn: Button = null
var _profile_char_option: OptionButton = null

# ── Measurement panel ────────────────────────────────────────────────────────
## Dockable panel for measurement tools (right-side, left of effect panel).
var _measure_panel: PanelContainer = null
var _measure_panel_window: Window = null
var _measure_panel_floating: bool = false
var _measure_undock_btn: Button = null
var _measure_panel_title: Label = null
var _measure_vbox: VBoxContainer = null
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
var _prev_player_positions: Dictionary = {} ## {player_id: Vector2} — previous frame positions for swept-path
var _detected_token_ids: Array = [] ## token IDs currently in detection state
var _ui_layer: CanvasLayer = null ## CanvasLayer that owns the UI tree
var _ui_content_area: Control = null ## viewport-filling region above the status bar; all overlays live here
var _bg_chrome_layer: CanvasLayer = null ## background chrome behind MapView

# ── Effect panel ─────────────────────────────────────────────────────────────
var _effect_panel: PanelContainer = null
var _effect_panel_window: Window = null
var _effect_panel_floating: bool = false

# ── Dice tray panel ──────────────────────────────────────────────────────────
var _dice_tray: PanelContainer = null
var _dice_tray_window: Window = null
var _dice_tray_floating: bool = false
var _dice_renderer: DiceRenderer3D = null

# ── Initiative panel ─────────────────────────────────────────────────────────
var _initiative_panel: InitiativePanel = null
var _initiative_panel_window: Window = null
var _initiative_panel_floating: bool = false
var _quick_damage_dialog: QuickDamageDialog = null
var _combat_turn_token_id: String = "" ## Token ID currently showing the active-turn ring.

# ── Save / AoE panel ────────────────────────────────────────────────────────
var _save_results_panel: SaveResultsPanel = null
var _save_config_dialog: Window = null
## Temporarily stores measurement ID while save config dialog is open.
var _pending_save_measurement_id: String = ""

# ── Condition dialog ─────────────────────────────────────────────────────────
var _condition_dialog: ConditionDialog = null
var _combat_log_panel: PanelContainer = null
var _combat_log_panel_window: Window = null
var _combat_log_panel_floating: bool = false

# ── Share player link dialog ────────────────────────────────────────────────
var _share_dialog: AcceptDialog = null
var _share_dialog_root: VBoxContainer = null
var _share_qr_rect: TextureRect = null
var _share_url_label: Label = null

# ── Multi-selection action bar ──────────────────────────────────────────────
var _multi_select_bar: PanelContainer = null
var _multi_select_combat_btn: Button = null
var _multi_select_label: Label = null

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
	# Defer campaign bindings so CampaignService is registered by bootstrap.
	call_deferred("_ensure_campaign_bindings")
	# Release all undo/redo closures when this node is freed to avoid dangling refs.
	tree_exiting.connect(func():
		var _r := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if _r != null and _r.history != null:
			_r.history.clear())
	_apply_ui_scale()
	# On startup: try to resume the most-recently-used campaign, then show the
	# save browser so the DM can quickly pick up a session.
	# Wait one frame so the node tree finishes setting up children first.
	get_tree().process_frame.connect(_on_first_frame, CONNECT_ONE_SHOT)


func _on_first_frame() -> void:
	## On startup, resume the most recently used campaign and open its hub,
	## or show the campaign browser if no prior campaign exists.
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var resumed: bool = false
	if registry != null and registry.campaign != null:
		var last_path: String = registry.campaign.get_last_campaign_path()
		if not last_path.is_empty():
			var json_check: String = last_path.rstrip("/") + "/campaign.json"
			if FileAccess.file_exists(json_check):
				var campaign: CampaignData = registry.campaign.open_campaign(last_path)
				if campaign != null:
					_set_status("Resumed campaign: %s" % campaign.name)
					resumed = true
					_open_campaign_hub()
	if not resumed:
		_open_campaign_browser()


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
	if gs == null or gs.service == null:
		call_deferred("_ensure_game_state_bindings")
		return
	if not gs.is_connected("player_lock_changed", Callable(self , "_on_player_lock_changed_external")):
		gs.player_lock_changed.connect(_on_player_lock_changed_external)
	# Signal subscription: IGameStateService extends Node; signals live on the
	# Node instance. Approved narrow exception to the view-must-call-manager rule.
	var svc: IGameStateService = gs.service
	if not svc.is_connected("session_loaded", Callable(self , "_on_session_changed")):
		svc.session_loaded.connect(_on_session_changed)
	if not svc.is_connected("session_saved", Callable(self , "_on_session_changed")):
		svc.session_saved.connect(_on_session_changed)
	if not svc.is_connected("active_profiles_changed", Callable(self , "_on_profiles_changed")):
		svc.active_profiles_changed.connect(_on_profiles_changed)
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
	if not svc.is_connected("history_changed", Callable(self , "_update_profile_undo_btn")):
		svc.history_changed.connect(_update_profile_undo_btn)
	_refresh_history_menu()
	_update_profile_undo_btn()


func _ensure_campaign_bindings() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null or registry.campaign.service == null:
		call_deferred("_ensure_campaign_bindings")
		return
	# Signal subscription: ICampaignService extends Node; signals live on the
	# Node instance. RefCounted manager cannot re-emit — approved exception.
	var svc: ICampaignService = registry.campaign.service
	if not svc.is_connected("campaign_loaded", Callable(self , "_on_campaign_indicator_loaded")):
		svc.campaign_loaded.connect(_on_campaign_indicator_loaded)
	if not svc.is_connected("campaign_closed", Callable(self , "_on_campaign_indicator_closed")):
		svc.campaign_closed.connect(_on_campaign_indicator_closed)
	_update_campaign_indicator()


func _on_campaign_indicator_loaded(_campaign: CampaignData) -> void:
	_update_campaign_indicator()


func _on_campaign_indicator_closed() -> void:
	_update_campaign_indicator()


func _update_campaign_indicator() -> void:
	var base_title: String = "The Vault"
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.campaign != null:
		var campaign: CampaignData = registry.campaign.get_active_campaign()
		if campaign != null and not campaign.name.is_empty():
			get_window().title = "%s \u2014 %s" % [base_title, campaign.name]
			return
	get_window().title = base_title


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
		var undo_text := "Undo" if undo_desc.is_empty() else "Undo: %s" % undo_desc
		_edit_menu.set_item_text(undo_idx, undo_text)
		_nm_set_disabled("Edit", 14, not can_undo)
		_nm_set_text("Edit", 14, undo_text)
	if redo_idx >= 0:
		_edit_menu.set_item_disabled(redo_idx, not can_redo)
		var redo_desc := registry.history.get_redo_description()
		var redo_text := "Redo" if redo_desc.is_empty() else "Redo: %s" % redo_desc
		_edit_menu.set_item_text(redo_idx, redo_text)
		_nm_set_disabled("Edit", 15, not can_redo)
		_nm_set_text("Edit", 15, redo_text)
	# Copy/Cut are enabled when a token is hovered; paste when clipboard is non-empty.
	var has_hover: bool = _map_view != null and _map_view.get_hovered_token_id() != null
	var copy_idx := _edit_menu.get_item_index(16)
	var cut_idx := _edit_menu.get_item_index(17)
	var paste_idx := _edit_menu.get_item_index(18)
	if copy_idx >= 0:
		_edit_menu.set_item_disabled(copy_idx, not has_hover)
		_nm_set_disabled("Edit", 16, not has_hover)
	if cut_idx >= 0:
		_edit_menu.set_item_disabled(cut_idx, not has_hover)
		_nm_set_disabled("Edit", 17, not has_hover)
	if paste_idx >= 0:
		_edit_menu.set_item_disabled(paste_idx, _token_clipboard.is_empty())
		_nm_set_disabled("Edit", 18, _token_clipboard.is_empty())
	# Snap All Tokens to Grid — enabled when a map is loaded.
	var snap_idx := _edit_menu.get_item_index(19)
	if snap_idx >= 0:
		var has_map: bool = _map() != null
		_edit_menu.set_item_disabled(snap_idx, not has_map)


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
	if not svc.is_connected("dice_roll_received", Callable(self , "_on_dice_roll_received")):
		svc.dice_roll_received.connect(_on_dice_roll_received)
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


func _on_map_gui_input(event: InputEvent) -> void:
	## Forward map-area pointer events from the GUI system to MapView so that
	## tool interactions work without routing through _unhandled_input.
	if _map_view == null or _map_spacer == null:
		return
	var xf: Transform2D = _map_spacer.get_global_transform_with_canvas()
	_map_view._unhandled_input(event.xformed_by(xf))


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
	elif key_event.keycode == KEY_C:
		var hover_id: Variant = _map_view.get_hovered_token_id() if _map_view != null else null
		if hover_id != null:
			_copy_token(str(hover_id))
			get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_X:
		var hover_id: Variant = _map_view.get_hovered_token_id() if _map_view != null else null
		if hover_id != null:
			_cut_token(str(hover_id))
			get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_V:
		if not _token_clipboard.is_empty() and _map_view != null:
			var world_pos: Vector2 = _map_view.get_global_mouse_position()
			_paste_token(world_pos)
			get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_L:
		_open_statblock_library()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# Re-dock floating panels if the OS minimizes them (macOS yellow dot).
	# Minimized sub-windows can't be restored from within the DM window, so
	# we snap them back to docked state immediately.
	if _freeze_panel_window != null and is_instance_valid(_freeze_panel_window) \
			and _freeze_panel_window.mode == Window.MODE_MINIMIZED:
		call_deferred("_dock_freeze_panel")
	if _effect_panel_window != null and is_instance_valid(_effect_panel_window) \
			and _effect_panel_window.mode == Window.MODE_MINIMIZED:
		call_deferred("_dock_effect_panel")
	if _player_state_countdown > 0.0:
		_player_state_countdown = maxf(0.0, _player_state_countdown - delta)
	if _fog_countdown > 0.0:
		_fog_countdown = maxf(0.0, _fog_countdown - delta)
	if _fog_dirty and _fog_countdown <= 0.0:
		_fog_dirty = false
		_broadcast_fog_state()
		_fog_countdown = _FOG_BROADCAST_DEBOUNCE

	if Log.debug_mode:
		_update_dm_override_input()
	var _player_moved: bool = _simulate_player_movement(delta)
	if _player_moved:
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

	# Advance roam animations for any playing tokens.
	_tick_roam_animations(delta)

	# Periodic perception-proximity check — auto-reveal tokens whose DC is
	# met by a nearby player's passive perception.
	# Autopause collision only needs to run when players or roaming tokens moved.
	if _player_moved or not _roaming_tokens.is_empty():
		_run_autopause_check()

	_perception_timer -= delta
	if _perception_timer <= 0.0:
		_perception_timer = _PERCEPTION_CHECK_INTERVAL
		_run_perception_check()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# ── Background chrome layer (behind everything) ─────────────────────────
	var _bg_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _bg_reg == null:
		var _bg_boot := get_node_or_null("/root/ServiceBootstrap")
		if _bg_boot != null and _bg_boot.get("registry") != null:
			_bg_reg = _bg_boot.registry as ServiceRegistry
	if _bg_reg != null and _bg_reg.ui_theme != null:
		_bg_chrome_layer = CanvasLayer.new()
		_bg_chrome_layer.name = "BGChromeLayer"
		_bg_chrome_layer.layer = -1
		add_child(_bg_chrome_layer)
		var bg_rect: ColorRect = _bg_reg.ui_theme.create_background_chrome()
		_bg_chrome_layer.add_child(bg_rect)

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
	_map_view.measurement_right_clicked.connect(_on_measurement_right_clicked)
	_map_view.background_right_clicked.connect(_on_background_right_clicked)
	_map_view.token_selected.connect(_on_token_selected)
	# Connect selection_changed from the selection service for status updates.
	var sel_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if sel_reg == null:
		var _sel_boot := get_node_or_null("/root/ServiceBootstrap")
		if _sel_boot != null and _sel_boot.get("registry") != null:
			sel_reg = _sel_boot.registry as ServiceRegistry
	if sel_reg != null and sel_reg.selection != null and sel_reg.selection.service != null:
		sel_reg.selection.service.selection_changed.connect(_on_selection_changed)
	_map_view.passage_paths_committed.connect(_on_passage_paths_committed)
	_map_view.roam_path_committed.connect(_on_roam_path_committed)
	_map_view.effect_place_requested.connect(_on_effect_place_requested)
	_map_view.effect_shape_place_requested.connect(_on_effect_shape_place_requested)
	_map_view.effect_drag_completed.connect(_on_effect_drag_completed)
	_map_view.effect_resize_completed.connect(_on_effect_resize_completed)
	_map_view.effect_delete_requested.connect(_on_effect_delete_requested)
	_map_view.effect_burst_started.connect(_on_effect_burst_started)
	_map_view.effect_burst_moved.connect(_on_effect_burst_moved)
	_map_view.effect_burst_ended.connect(_on_effect_burst_ended)
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

	# Content area fills the viewport above the status bar. All overlays and
	# _ui_root live inside this node so their anchor_bottom = 1.0 resolves to
	# the top of the status bar rather than the viewport bottom.
	# Default STOP filter keeps the GUI event pipeline from spilling into
	# _unhandled_input, which would break embedded sub-window interaction.
	_ui_content_area = Control.new()
	_ui_content_area.name = "UIContentArea"
	_ui_content_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(_ui_content_area)

	# Root VBox fills the content area.
	_ui_root = VBoxContainer.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ui_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ui_content_area.add_child(_ui_root)

	# ── Menu bar ─────────────────────────────────────────────────────────────
	_menu_bar = MenuBar.new()
	_menu_bar.prefer_global_menu = true ## merge into native OS menu bar
	_menu_bar.resized.connect(_apply_palette_size)
	_menu_bar.resized.connect(_apply_freeze_panel_size)
	_menu_bar.resized.connect(_apply_effect_panel_size)
	_menu_bar.resized.connect(_apply_dice_tray_size)
	_menu_bar.resized.connect(_apply_initiative_panel_size)
	_ui_root.add_child(_menu_bar)

	var menu_bar: MenuBar = _menu_bar ## local alias for readability below

	# File menu  (IDs 0-9 = map/save/quit, 40-44 = campaign)
	var file_menu := PopupMenu.new()
	file_menu.name = "File"
	file_menu.add_item("New Map from Image…", 0)
	file_menu.add_item("Open Map…", 1)
	file_menu.add_item("Browse Maps…", 7)
	file_menu.add_separator()
	file_menu.add_item("Save Map", 2)
	file_menu.add_item("Save Map As…", 3)
	file_menu.add_separator()
	file_menu.add_item("Save Game", 4)
	file_menu.add_item("Save Game As…", 5)
	file_menu.add_item("Load Game…", 6)
	file_menu.add_item("Browse Saves…", 8)
	file_menu.add_separator()
	file_menu.add_item("New Campaign…", 40)
	file_menu.add_item("Open Campaign…", 41)
	file_menu.add_item("Save Campaign", 42)
	file_menu.add_item("Close Campaign", 44)
	file_menu.add_separator()
	file_menu.add_item("Export Statblocks as JSON\u2026", 47)
	file_menu.add_item("Import Statblocks from JSON\u2026", 48)
	file_menu.add_item("Export Campaign as JSON\u2026", 49)
	file_menu.add_item("Import Campaign from JSON\u2026", 50)
	file_menu.add_separator()
	file_menu.add_item("Check for SRD Updates\u2026", 51)
	file_menu.add_separator()
	file_menu.add_item("Close Map", 45)
	file_menu.add_item("Close Save", 46)
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
	edit_menu.add_item("Copy Token", 16)
	edit_menu.add_item("Cut Token", 17)
	edit_menu.add_item("Paste Token", 18)
	edit_menu.add_separator()
	edit_menu.add_item("Calibrate Grid…", 10)
	edit_menu.add_item("Set Scale Manually…", 11)
	edit_menu.add_item("Set Grid Offset…", 12)
	edit_menu.add_item("Snap All Tokens to Grid", 19)
	edit_menu.add_separator()
	edit_menu.add_item("Player Profiles…", 13)
	edit_menu.add_item("Characters…", 100)
	edit_menu.id_pressed.connect(_on_edit_menu_id)
	_edit_menu = edit_menu
	# Undo/Redo start disabled; enabled once commands are pushed.
	edit_menu.set_item_disabled(edit_menu.get_item_index(14), true)
	edit_menu.set_item_disabled(edit_menu.get_item_index(15), true)
	# Copy/Cut/Paste start disabled; enabled dynamically.
	edit_menu.set_item_disabled(edit_menu.get_item_index(16), true)
	edit_menu.set_item_disabled(edit_menu.get_item_index(17), true)
	edit_menu.set_item_disabled(edit_menu.get_item_index(18), true)
	# Snap All starts disabled; enabled when a map is loaded.
	edit_menu.set_item_disabled(edit_menu.get_item_index(19), true)
	menu_bar.add_child(edit_menu)

	# View menu  (all set_item_checked calls use get_item_index(id) — no hardcoded indices)
	# idx 0 → id 20 Toolbar
	# idx 1 → id 25 Player Freeze Panel
	# idx 2 → id 29 Effect Panel
	# idx 3 → id 21 Grid Overlay
	# idx 4 → separator
	# idx 5 → id 22 Reset View
	# idx 6 → separator
	# idx 7 → id 30 Fog of War
	# idx 8 → id 24 Sync Fog Now
	# idx 9 → id 27 Reset Fog…
	# idx 10 → id 28 Fog Overlay Effect
	# idx 11 → separator
	# idx 12 → id 26 Measurement Tools…
	# idx 13 → separator
	# idx 14 → Grid Type submenu
	# idx 15 → UI Theme submenu
	# idx 16 → separator
	# idx 17 → id 23 Launch Player Window
	_view_menu = PopupMenu.new()
	_view_menu.name = "View"
	_view_menu.add_check_item("Toolbar", 20)
	_view_menu.set_item_checked(_view_menu.get_item_index(20), true)
	_view_menu.add_check_item("Player Freeze Panel", 25)
	_view_menu.set_item_checked(_view_menu.get_item_index(25), true)
	_view_menu.add_check_item("Effect Panel", 29)
	_view_menu.set_item_checked(_view_menu.get_item_index(29), false)
	_view_menu.add_check_item("Grid Overlay", 21)
	_view_menu.set_item_checked(_view_menu.get_item_index(21), true)
	_view_menu.add_separator()
	_view_menu.add_item("Reset View", 22)
	_view_menu.add_separator()
	_view_menu.add_check_item("Fog of War", 30)
	_view_menu.set_item_checked(_view_menu.get_item_index(30), true)
	_view_menu.add_item("Sync Fog Now", 24)
	_view_menu.add_item("Reset Fog…", 27)
	_view_menu.add_check_item("Fog Overlay Effect", 28)
	_view_menu.set_item_checked(_view_menu.get_item_index(28), false)
	_view_menu.add_separator()
	_view_menu.add_check_item("Measurement Tools", 26)
	_view_menu.set_item_checked(_view_menu.get_item_index(26), false)
	_view_menu.add_item("Background Audio…", 31)
	_view_menu.add_item("Statblock Library…", 32)
	_view_menu.add_item("Item Library…", 36)
	_view_menu.add_item("Dice Tray", 33)
	_view_menu.add_check_item("Initiative Panel", 34)
	_view_menu.set_item_checked(_view_menu.get_item_index(34), false)
	_view_menu.add_check_item("Combat Log", 35)
	_view_menu.set_item_checked(_view_menu.get_item_index(35), false)
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

	# UI Theme submenu
	_theme_submenu = PopupMenu.new()
	_theme_submenu.name = "UITheme"
	for preset_id: int in UIThemeData.get_all_presets():
		_theme_submenu.add_radio_check_item(UIThemeData.get_display_name(preset_id), preset_id)
	_theme_submenu.set_item_checked(0, true) # default checked = FLAT_DARK
	_theme_submenu.id_pressed.connect(_on_theme_submenu_id)
	_view_menu.add_child(_theme_submenu)
	_view_menu.add_submenu_node_item("UI Theme", _theme_submenu)

	# Sync theme submenu checkmarks to persisted theme
	var _theme_reg2 := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _theme_reg2 == null:
		var _bootstrap2 := get_node_or_null("/root/ServiceBootstrap")
		if _bootstrap2 != null and _bootstrap2.get("registry") != null:
			_theme_reg2 = _bootstrap2.registry as ServiceRegistry
	if _theme_reg2 != null and _theme_reg2.ui_theme != null:
		var current_preset: int = _theme_reg2.ui_theme.get_theme()
		_sync_theme_submenu_checks(current_preset)

	_view_menu.add_separator()
	_view_menu.add_item("Campaign Hub…", 37)
	_view_menu.add_item("▶ Launch Player Window", 23)
	_view_menu.id_pressed.connect(_on_view_menu_id)
	menu_bar.add_child(_view_menu)

	# Campaign menu items are now under File (IDs 40-44); no separate menu.

	# Session menu
	var session_menu := PopupMenu.new()
	session_menu.name = "Session"
	session_menu.add_item("Share Player Link…", 30)
	session_menu.id_pressed.connect(_on_session_menu_id)
	menu_bar.add_child(session_menu)

	# ── Native Win32 menu bar (Windows only) ────────────────────────────────
	if OS.get_name() == "Windows":
		var nm_script: Variant = load("res://scripts/ui/NativeWin32MenuBar.cs")
		if nm_script:
			_native_menu = nm_script.new()
			add_child(_native_menu)
			_build_native_menus()
			_menu_bar.visible = false

	# ── Content row: map spacer ─────────────────────────────────────────────
	var content_row := HBoxContainer.new()
	content_row.name = "ContentRow"
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var _tm_ref: UIThemeManager = null
	var _sr: ServiceRegistry = get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _sr != null:
		_tm_ref = _sr.ui_theme
	_palette.setup(_get_ui_scale_mgr(), _tm_ref)
	_ui_content_area.add_child(_palette)
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
	_palette.darkvision_disabled_toggled.connect(_on_darkvision_disabled_toggled)
	_palette.effect_tool_activated.connect(_on_palette_effect_tool_activated)
	_palette.undock_btn.pressed.connect(_on_undock_btn_pressed)

	# Add flyout panel to content area (not ui_root) for HiDPI stability
	_ui_content_area.add_child(_palette.get_flyout())

	# ── Map area spacer (catches mouse events and forwards to MapView) ────────
	# STOP intercepts pointer events in the map region; the gui_input
	# callback transforms them back to viewport coordinates and calls
	# MapView._unhandled_input directly.  This avoids the normal
	# _unhandled_input pipeline which interferes with sub-window dragging.
	_map_spacer = Control.new()
	_map_spacer.name = "MapSpacer"
	_map_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_spacer.mouse_filter = Control.MOUSE_FILTER_STOP
	content_row.add_child(_map_spacer)
	_map_spacer.gui_input.connect(_on_map_gui_input)

	# ── Player freeze panel (vertical side panel, right side) ─────────────────
	# Added directly to _ui_content_area (not _ui_root) so _ui_root.scale does not
	# push it off-screen on HiDPI / Retina displays.
	_build_freeze_panel()
	_build_effect_panel()
	_build_measure_panel()
	_build_dice_tray()
	_build_initiative_panel()
	_build_combat_log_panel()
	_build_passage_panel()
	_build_roam_panel()
	_build_multi_select_bar()

	# ── Apply chrome theme backgrounds to all panels ────────────────────────
	var _theme_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _theme_reg == null:
		var _bootstrap := get_node_or_null("/root/ServiceBootstrap")
		if _bootstrap != null and _bootstrap.get("registry") != null:
			_theme_reg = _bootstrap.registry as ServiceRegistry
	if _theme_reg != null and _theme_reg.ui_theme != null:
		var tm: UIThemeManager = _theme_reg.ui_theme
		if _palette is PanelContainer:
			tm.apply_chrome(_palette as PanelContainer)
		if _freeze_panel is PanelContainer:
			tm.apply_chrome(_freeze_panel as PanelContainer)
		if _effect_panel is PanelContainer:
			tm.apply_chrome(_effect_panel as PanelContainer)
		if _passage_panel is PanelContainer:
			tm.apply_chrome(_passage_panel as PanelContainer)
		if _roam_panel is PanelContainer:
			tm.apply_chrome(_roam_panel as PanelContainer)
		if _measure_panel is PanelContainer:
			tm.apply_chrome(_measure_panel as PanelContainer)
		# Signal subscription: IUIThemeService extends Node; signals live on the
		# Node instance.  RefCounted manager cannot re-emit — approved exception.
		if tm.service != null:
			tm.service.theme_changed.connect(_on_ui_theme_changed)
		# Theme all existing buttons/panels in the UI tree in one pass
		tm.theme_control_tree(_ui_root, _ui_scale())
		# Overlay panels live on _ui_content_area (not _ui_root) — theme them too
		if _palette != null:
			tm.theme_control_tree(_palette, _ui_scale())
		# Flyout is on _ui_layer (not a child of palette) — theme it separately
		var _flyout: PanelContainer = _palette.get_flyout() if _palette != null else null
		if _flyout != null:
			tm.theme_control_tree(_flyout, _ui_scale())
		if _freeze_panel != null:
			tm.theme_control_tree(_freeze_panel, _ui_scale())
		if _effect_panel != null:
			tm.theme_control_tree(_effect_panel, _ui_scale())
		if _passage_panel != null:
			tm.theme_control_tree(_passage_panel, _ui_scale())
		if _roam_panel != null:
			tm.theme_control_tree(_roam_panel, _ui_scale())
		if _initiative_panel != null:
			tm.theme_control_tree(_initiative_panel, _ui_scale())
		if _measure_panel != null:
			tm.theme_control_tree(_measure_panel, _ui_scale())
		if _multi_select_bar != null:
			tm.theme_control_tree(_multi_select_bar, _ui_scale())

	# Status bar lives on _ui_layer (not _ui_root) so _ui_root.scale does not
	# push it off-screen. Anchored to the bottom edge, full width.
	_status_bar = PanelContainer.new()
	_status_bar.name = "StatusBar"
	_status_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_bar.anchor_left = 0.0
	_status_bar.anchor_right = 1.0
	_status_bar.anchor_top = 1.0
	_status_bar.anchor_bottom = 1.0
	_status_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var s: float = _ui_scale()
	_apply_status_bar_size()
	var status_bg := StyleBoxFlat.new()
	status_bg.bg_color = Color(0.12, 0.12, 0.14, 0.9)
	status_bg.content_margin_left = roundi(8.0 * s)
	status_bg.content_margin_right = roundi(8.0 * s)
	status_bg.content_margin_top = roundi(4.0 * s)
	status_bg.content_margin_bottom = roundi(4.0 * s)
	_status_bar.add_theme_stylebox_override("panel", status_bg)
	_status_label = Label.new()
	_status_label.text = "No map loaded"
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_status_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_status_bar.add_child(_status_label)
	_ui_layer.add_child(_status_bar)

	# ── FileDialog (image selection for New Map) ─────────────────────────────
	_file_dialog = FileDialog.new()
	_file_dialog.use_native_dialog = true
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.title = "Select Map Image or Video"
	var _img_filter := ",".join(SUPPORTED_IMAGE_EXTENSIONS.map(func(e: Variant) -> String: return "*.%s" % str(e)))
	var _vid_filter := ",".join(SUPPORTED_VIDEO_EXTENSIONS.map(func(e: Variant) -> String: return "*.%s" % str(e)))
	_file_dialog.add_filter("%s ; Image Files" % _img_filter)
	_file_dialog.add_filter("%s ; Video Files" % _vid_filter)
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

	# ── Open Map dialog — select a .map bundle (ZIP archive or legacy directory) ────
	# Bundles are stored as ZIP files so OPEN_FILE works on all platforms.
	# Legacy directory bundles are supported via OPEN_ANY in dev mode.
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

	# ── Load Game dialog — select a .sav bundle (ZIP archive or legacy directory) ──
	# Same approach as Open Map: OPEN_FILE for standalone, OPEN_ANY for dev.
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

	# Share player link dialog — built eagerly so the window is in the scene
	# tree and has a full layout pass before the user first opens it.
	_build_share_player_link_dialog()

	# Player viewport indicator — DM drags the green box on the main map
	# to reposition what players see. Hidden until a map is loaded.
	_map_view.set_viewport_indicator(Rect2())
	_map_view.viewport_indicator_moved.connect(_on_viewport_indicator_moved)
	_map_view.viewport_indicator_resized.connect(_on_viewport_indicator_resized)

	# ── Apply dialog theming ────────────────────────────────────────────────
	_apply_dialog_themes()


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
	# Restart video playback so DM and player roughly sync.
	if _map_view != null:
		_map_view.restart_video()


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
	Log.info("DMWindow", "initial sync send attempt %d to peer %d" % [attempt, peer_id])
	_nm_send_map_to_display(peer_id, map, false, fog_snapshot)
	_broadcast_player_viewport()
	_broadcast_player_state()
	_broadcast_token_state()
	_broadcast_puzzle_notes_state()
	_broadcast_measurement_state()
	_broadcast_effect_state()
	# Send current fog-of-war enabled state.
	var fog_enabled_val: bool = _view_menu.is_item_checked(_view_menu.get_item_index(30))
	_nm_broadcast_to_displays({"msg": "fog_enabled_toggle", "enabled": fog_enabled_val})
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
	Log.info("DMWindow", "initial sync ack from peer %d (stamp_bytes=%d stamp_hash=%d)" % [
		peer_id,
		int(payload.get("snapshot_bytes", -1)),
		int(payload.get("snapshot_hash", -1)),
	])
	# Send icon data now that the main sync payload has been delivered and the
	# outbound buffer has drained.
	_send_display_icon_sync()


func _on_dice_roll_received(player_id: String, result: DiceResult, _context: Dictionary) -> void:
	if _dice_tray == null:
		return
	var player_name: String = player_id
	var gs := _game_state()
	if gs != null:
		var profile: Variant = gs.get_profile_by_id(player_id)
		if profile is PlayerProfile:
			player_name = (profile as PlayerProfile).player_name
	(_dice_tray as DiceTray).append_remote_roll(player_name, result)


## Send each player/token icon as a separate small message so the WebSocket
## outbound buffer is not overwhelmed by a single giant payload.
func _send_display_icon_sync() -> void:
	var nm := _network()
	if nm == null:
		return
	# Player profile icons.
	var gs := _game_state()
	if gs != null:
		for raw in gs.list_profiles():
			if not raw is PlayerProfile:
				continue
			var p := raw as PlayerProfile
			if p.icon_image_path.is_empty():
				continue
			var b64: String = TokenIconUtils.encode_icon_to_b64(p.icon_image_path)
			if not b64.is_empty():
				nm.broadcast_to_displays({"msg": "player_icon", "id": p.id, "icon_image_b64": b64})
	# Token icons.
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.token != null:
		for raw in registry.token.get_all_tokens():
			var td: TokenData = raw as TokenData
			if td == null or td.icon_image_path.is_empty():
				continue
			var b64: String = TokenIconUtils.encode_icon_to_b64(td.icon_image_path)
			if not b64.is_empty():
				nm.broadcast_to_displays({"msg": "token_icon", "id": td.id, "icon_image_b64": b64})


func _broadcast_player_icon(p: PlayerProfile) -> void:
	var nm := _network()
	if nm == null:
		return
	var b64 := ""
	if not p.icon_image_path.is_empty():
		b64 = TokenIconUtils.encode_icon_to_b64(p.icon_image_path)
	nm.broadcast_to_displays({"msg": "player_icon", "id": p.id, "icon_image_b64": b64})


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
	Log.debug("DMWindow", "fog snapshot built (stamp_bytes=%d stamp_hash=%d)" % [
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
			_set_status("Token tool — click to place, drag to move, hold Shift to snap to grid")
		"effect":
			_map_view.set_fog_tool(0, 64.0)
			_map_view._set_active_tool(_map_view.Tool.PLACE_EFFECT)
			if _effect_panel != null:
				_effect_panel.visible = true
				_set_view_checked(29, true)
				_apply_effect_panel_size()
				_map_view.effect_place_type = _effect_panel.get_selected_effect_type()
				_map_view.effect_place_size = _effect_panel.get_effect_size()
				_map_view.effect_burst_mode = _effect_panel.is_burst_mode()
				_map_view.effect_place_shape = _effect_panel.get_selected_shape()
				_map_view.effect_place_palette = _effect_panel.get_selected_palette()
				_map_view.effect_place_definition_id = _effect_panel.get_selected_effect_definition_id()
			var eff_def_id: String = _effect_panel.get_selected_effect_definition_id() if _effect_panel != null else ""
			if not eff_def_id.is_empty():
				_set_status("Effect tool — %s — click to place" % eff_def_id)
			else:
				var eff_type: int = _effect_panel.get_selected_effect_type() if _effect_panel != null else 0
				var eff_label: String = EffectData.EFFECT_LABELS[eff_type] if eff_type < EffectData.EFFECT_LABELS.size() else "FX"
				_set_status("Effect tool — %s — click to place" % eff_label)


func _on_palette_effect_tool_activated(_effect_type: int) -> void:
	if _map_view == null:
		return
	_map_view.set_fog_tool(0, 64.0)
	_map_view._set_active_tool(_map_view.Tool.PLACE_EFFECT)

	# Auto-show the effect panel and sync state to MapView
	if _effect_panel != null:
		_effect_panel.visible = true
		_set_view_checked(29, true)
		_apply_effect_panel_size()
		_map_view.effect_place_type = _effect_panel.get_selected_effect_type()
		_map_view.effect_place_size = _effect_panel.get_effect_size()
		_map_view.effect_burst_mode = _effect_panel.is_burst_mode()
		_map_view.effect_place_shape = _effect_panel.get_selected_shape()
		_map_view.effect_place_palette = _effect_panel.get_selected_palette()
		_map_view.effect_place_definition_id = _effect_panel.get_selected_effect_definition_id()

	var eff_type: int = _effect_panel.get_selected_effect_type() if _effect_panel != null else _effect_type
	var eff_label: String = EffectData.EFFECT_LABELS[eff_type] if eff_type < EffectData.EFFECT_LABELS.size() else "FX"
	var burst: bool = _effect_panel.is_burst_mode() if _effect_panel != null else false
	var suffix: String = " (burst)" if burst else ""
	_set_status("Effect tool — %s%s — click to place" % [eff_label, suffix])


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
	if _native_menu:
		_native_menu.call(&"SetRadioChecked", "GridType", 0, 2, _grid_type_selected)


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
	_palette_window.transient = true
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

	_palette_window.close_requested.connect(_close_floating_palette)
	# Theme floating window chrome + buttons
	var _uw_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _uw_reg != null and _uw_reg.ui_theme != null:
		_uw_reg.ui_theme.theme_control_tree(_palette_window, _ui_scale())
	var _pm := _get_ui_scale_mgr()
	if _pm != null:
		_pm.popup_fitted(_palette_window, 56.0, 500.0)
	else:
		_palette_window.popup_centered()
		_palette_window.grab_focus()


func _dock_palette() -> void:
	if not _palette_floating or _palette == null:
		return
	_palette_floating = false
	if _palette.undock_btn:
		_palette.undock_btn.text = "⇲"
		_palette.undock_btn.tooltip_text = "Detach / re-dock palette"

	if _palette_window:
		_palette_window.remove_child(_palette)

	# Re-anchor to left edge of content area.
	_palette.anchor_left = 0.0
	_palette.anchor_right = 0.0
	_palette.anchor_top = 0.0
	_palette.anchor_bottom = 1.0
	_palette.grow_horizontal = Control.GROW_DIRECTION_END
	_ui_content_area.add_child(_palette)
	_apply_palette_size()

	if _palette_window:
		_palette_window.queue_free()
		_palette_window = null


func _close_floating_palette() -> void:
	_dock_palette()
	if _palette != null:
		_palette.visible = false
	_set_view_checked(20, false)


# ---------------------------------------------------------------------------
# Player freeze panel — build, undock/redock, refresh
# ---------------------------------------------------------------------------

func _build_freeze_panel() -> void:
	# The panel lives directly in _ui_content_area (screen coordinates), NOT inside
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
	_ui_content_area.add_child(_freeze_panel)

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

	_fp_vbox.add_child(HSeparator.new())

	var edit_profiles_btn := Button.new()
	edit_profiles_btn.text = "Edit Profiles…"
	edit_profiles_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_profiles_btn.custom_minimum_size = Vector2(0, roundi(28.0 * _ui_scale()))
	edit_profiles_btn.add_theme_font_size_override("font_size", roundi(12.0 * _ui_scale()))
	edit_profiles_btn.pressed.connect(_open_profiles_editor)
	_fp_vbox.add_child(edit_profiles_btn)


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
		# Skip profiles not active in the current session (or when no session is loaded).
		if gs != null and not gs.is_profile_active(p.id):
			continue
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
		chk.custom_minimum_size = Vector2(0, icon_px * 1.3)
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
		# Theme dynamically-created freeze row controls
		var _fr_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if _fr_reg != null and _fr_reg.ui_theme != null:
			_fr_reg.ui_theme.theme_control_tree(row, _ui_scale())

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
	_freeze_panel_window.transient = true
	_freeze_panel_window.popup_window = false
	_freeze_panel_window.exclusive = false
	add_child(_freeze_panel_window)

	var old_parent := _freeze_panel.get_parent()
	if old_parent:
		old_parent.remove_child(_freeze_panel)
	_apply_effect_panel_size()
	_freeze_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_freeze_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_freeze_panel_window.add_child(_freeze_panel)
	_freeze_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Clear docked-mode offsets so the panel fills the window correctly.
	_freeze_panel.offset_left = 0.0
	_freeze_panel.offset_right = 0.0
	_freeze_panel.offset_top = 0.0
	_freeze_panel.offset_bottom = 0.0

	_freeze_panel_window.close_requested.connect(_close_floating_freeze_panel)
	# Theme floating window chrome + buttons
	var _fw_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _fw_reg != null and _fw_reg.ui_theme != null:
		_fw_reg.ui_theme.theme_control_tree(_freeze_panel_window, _ui_scale())
	var _fm := _get_ui_scale_mgr()
	if _fm != null:
		_fm.popup_fitted(_freeze_panel_window, 220.0, 400.0)
	else:
		_freeze_panel_window.popup_centered()
		_freeze_panel_window.grab_focus()

	_set_view_checked(25, true)
	_apply_effect_panel_size()


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

	if _ui_content_area != null:
		_ui_content_area.add_child(_freeze_panel)
		_apply_freeze_panel_size()

	# Restore title visibility now we're docked again
	if _freeze_panel_title != null:
		_freeze_panel_title.show()

	if _freeze_panel_window:
		_freeze_panel_window.queue_free()
		_freeze_panel_window = null

	_set_view_checked(25, true)
	_apply_effect_panel_size()


func _close_floating_freeze_panel() -> void:
	_dock_freeze_panel()
	if _freeze_panel != null:
		_freeze_panel.visible = false
	_set_view_checked(25, false)
	_apply_effect_panel_size()


# ---------------------------------------------------------------------------
# Effect panel — build, undock/redock
# ---------------------------------------------------------------------------

func _build_effect_panel() -> void:
	_effect_panel = EffectPanelScript.new() as PanelContainer
	var _ep_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var _ep_tm: UIThemeManager = _ep_reg.ui_theme if _ep_reg != null else null
	_effect_panel.setup(_get_ui_scale_mgr(), _ep_tm)
	_effect_panel.visible = false

	# Anchor to right edge, offset to the left of the freeze panel.
	_effect_panel.anchor_left = 1.0
	_effect_panel.anchor_right = 1.0
	_effect_panel.anchor_top = 0.0
	_effect_panel.anchor_bottom = 1.0
	_effect_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ui_content_area.add_child(_effect_panel)
	_apply_effect_panel_size()

	# Wire signals
	_effect_panel.palette_changed.connect(_on_effect_panel_palette_changed)
	_effect_panel.effect_type_selected.connect(_on_effect_panel_type_selected)
	_effect_panel.shape_changed.connect(_on_effect_panel_shape_changed)
	_effect_panel.burst_mode_changed.connect(_on_effect_panel_burst_changed)
	_effect_panel.size_changed.connect(_on_effect_panel_size_changed)
	_effect_panel.effect_definition_id_selected.connect(_on_effect_panel_definition_id_selected)
	# Reposition measure panel whenever the effect panel resizes (e.g. palette row toggles).
	_effect_panel.resized.connect(_apply_measure_panel_size)
	_effect_panel._undock_btn.pressed.connect(_on_effect_undock_btn_pressed)
	# Load the effects manifest and switch the palette to manifest mode if found.
	_load_effect_manifest()


func _apply_effect_panel_size() -> void:
	if _effect_panel == null:
		return
	var scale := _ui_scale()
	# Use the panel's actual minimum content width so panels that show wider
	# controls (e.g. fire-effect palette row) don't overflow the hardcoded value.
	var natural_w: float = _effect_panel.get_combined_minimum_size().x
	var panel_w := roundi(maxf(170.0 * scale, natural_w))
	var freeze_w := roundi(200.0 * scale) if (_freeze_panel != null and _freeze_panel.visible and not _freeze_panel_floating) else 0
	_effect_panel.offset_left = float(- (panel_w + freeze_w))
	_effect_panel.offset_right = float(-freeze_w)
	_effect_panel.offset_top = _menu_bar_screen_height()
	_effect_panel.offset_bottom = 0.0
	# Measurement panel stacks left of effect — recalculate when effect moves.
	_apply_measure_panel_size()


## If the FX tool is not already active, switch to it so the user can
## immediately place effects after picking one in the EffectPanel.
func _ensure_effect_tool_active() -> void:
	if _palette == null or _map_view == null:
		return
	if (_palette as ToolPalette).get_active_tool() == "effect":
		return
	(_palette as ToolPalette).activate_effect_tool()


func _on_effect_panel_type_selected(effect_type: int) -> void:
	_ensure_effect_tool_active()
	if _map_view != null:
		_map_view.effect_place_type = effect_type
	var label: String = EffectData.EFFECT_LABELS[effect_type] if effect_type < EffectData.EFFECT_LABELS.size() else "FX"
	var burst: bool = _effect_panel.is_burst_mode() if _effect_panel != null else false
	var suffix: String = " (burst)" if burst else ""
	_set_status("Effect tool — %s%s — click to place" % [label, suffix])


func _on_effect_panel_shape_changed(shape: int) -> void:
	if _map_view != null:
		_map_view.effect_place_shape = shape


func _on_effect_panel_burst_changed(enabled: bool) -> void:
	if _map_view != null:
		_map_view.effect_burst_mode = enabled
	var label: String = EffectData.EFFECT_LABELS[_map_view.effect_place_type] if _map_view != null and _map_view.effect_place_type < EffectData.EFFECT_LABELS.size() else "FX"
	var suffix: String = " (burst)" if enabled else ""
	_set_status("Effect tool — %s%s — click to place" % [label, suffix])


func _on_effect_panel_size_changed(size_px: float) -> void:
	if _map_view != null:
		_map_view.effect_place_size = size_px


func _on_effect_panel_palette_changed(palette_idx: int) -> void:
	if _map_view != null:
		_map_view.effect_place_palette = palette_idx


## Load the effects manifest from disk and switch the panel to manifest mode.
## The manifest lives at res://data/effects_manifest.json (bundled with the app).
func _load_effect_manifest() -> void:
	if _effect_panel == null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	var manifest_path: String = "res://data/effects_manifest.json"
	registry.effect.load_manifest(manifest_path)
	if registry.effect.is_manifest_loaded():
		var defs: Array = registry.effect.get_definitions()
		(_effect_panel as EffectPanel).setup_manifest(defs)
		# Reconnect the undock button (rebuild cleared children).
		if _effect_panel._undock_btn != null:
			if not _effect_panel._undock_btn.pressed.is_connected(_on_effect_undock_btn_pressed):
				_effect_panel._undock_btn.pressed.connect(_on_effect_undock_btn_pressed)


func _on_effect_panel_definition_id_selected(effect_id: String) -> void:
	_ensure_effect_tool_active()
	if _map_view != null:
		_map_view.effect_place_definition_id = effect_id
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	var def: EffectDefinition = registry.effect.get_definition(effect_id)
	var label: String = def.display_name if def != null else effect_id
	_set_status("Effect tool — %s — click to place" % label)


func _update_effect_panel_calibration() -> void:
	if _effect_panel == null:
		return
	var px_per_5ft: float = _pixels_per_5ft_current()
	_effect_panel.set_px_per_foot(px_per_5ft / 5.0)


func _update_measurement_overlay_scale() -> void:
	if _map_view == null or _map_view.measurement_overlay == null:
		return
	_map_view.measurement_overlay.set_scale_px(_pixels_per_5ft_current())


func _on_effect_undock_btn_pressed() -> void:
	if _effect_panel_floating:
		_dock_effect_panel()
	else:
		_undock_effect_panel()


func _undock_effect_panel() -> void:
	if _effect_panel_floating or _effect_panel == null:
		return
	_effect_panel_floating = true
	if _effect_panel._undock_btn:
		_effect_panel._undock_btn.text = "⇱"
		_effect_panel._undock_btn.tooltip_text = "Re-dock effect panel"

	_effect_panel_window = Window.new()
	_effect_panel_window.title = "Effects"
	_effect_panel_window.transient = true
	_effect_panel_window.popup_window = false
	_effect_panel_window.exclusive = false
	add_child(_effect_panel_window)

	var old_parent: Node = _effect_panel.get_parent()
	if old_parent:
		old_parent.remove_child(_effect_panel)
	_effect_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_effect_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_effect_panel_window.add_child(_effect_panel)
	_effect_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effect_panel.offset_left = 0.0
	_effect_panel.offset_right = 0.0
	_effect_panel.offset_top = 0.0
	_effect_panel.offset_bottom = 0.0

	_effect_panel_window.close_requested.connect(_close_floating_effect_panel)
	# Theme floating window chrome + buttons
	var _ew_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _ew_reg != null and _ew_reg.ui_theme != null:
		_ew_reg.ui_theme.theme_control_tree(_effect_panel_window, _ui_scale())
	var _fm := _get_ui_scale_mgr()
	if _fm != null:
		_fm.popup_fitted(_effect_panel_window, 200.0, 550.0)
	else:
		_effect_panel_window.popup_centered()
		_effect_panel_window.grab_focus()

	_set_view_checked(29, true)


func _dock_effect_panel() -> void:
	if not _effect_panel_floating or _effect_panel == null:
		return
	_effect_panel_floating = false
	if _effect_panel._undock_btn:
		_effect_panel._undock_btn.text = "⇲"
		_effect_panel._undock_btn.tooltip_text = "Detach / re-dock effect panel"

	if _effect_panel_window:
		_effect_panel_window.remove_child(_effect_panel)

	_effect_panel.anchor_left = 1.0
	_effect_panel.anchor_right = 1.0
	_effect_panel.anchor_top = 0.0
	_effect_panel.anchor_bottom = 1.0
	_effect_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	if _ui_content_area != null:
		_ui_content_area.add_child(_effect_panel)
		_apply_effect_panel_size()

	if _effect_panel_window:
		_effect_panel_window.queue_free()
		_effect_panel_window = null


func _close_floating_effect_panel() -> void:
	_dock_effect_panel()
	if _effect_panel != null:
		_effect_panel.visible = false
	_set_view_checked(29, false)
	_apply_effect_panel_size()


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
		7: _open_bundle_browser("map")
		8: _open_bundle_browser("save")
		9: get_tree().quit()
		40: _on_new_campaign()
		41: _on_open_campaign()
		42: _on_save_campaign()
		44: _on_close_campaign()
		45: _on_close_map()
		46: _on_close_save()
		47: _on_export_statblocks()
		48: _on_import_statblocks()
		49: _on_export_campaign()
		50: _on_import_campaign()
		51: _on_check_srd_updates()


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
		16: # Copy Token
			var hover_id: Variant = _map_view.get_hovered_token_id() if _map_view != null else null
			if hover_id != null:
				_copy_token(str(hover_id))
		17: # Cut Token
			var hover_id: Variant = _map_view.get_hovered_token_id() if _map_view != null else null
			if hover_id != null:
				_cut_token(str(hover_id))
		18: # Paste Token
			if not _token_clipboard.is_empty() and _map_view != null:
				var world_pos: Vector2 = _map_view.get_global_mouse_position()
				_paste_token(world_pos)
		10: _on_calibrate_pressed()
		11: _on_manual_scale_pressed()
		12: _on_set_offset_pressed()
		13: _open_profiles_editor()
		19: _snap_all_tokens_to_grid()
		100: _open_campaign_panel_to_characters()


# ── Campaign menu items now dispatched from _on_file_menu_id ─────────────────


func _on_new_campaign() -> void:
	## Show a name-input dialog before creating the campaign, similar to how
	## map/save bundles prompt for a filename before writing to disk.
	var mgr := _get_ui_scale_mgr()
	var dlg := AcceptDialog.new()
	dlg.title = "New Campaign"
	dlg.ok_button_text = "Create"

	var vbox := VBoxContainer.new()
	if mgr != null:
		vbox.add_theme_constant_override("separation", mgr.scaled(6.0))
	else:
		vbox.add_theme_constant_override("separation", 6)

	var lbl := Label.new()
	lbl.text = "Campaign name:"
	vbox.add_child(lbl)

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "My Campaign"
	name_edit.text = "My Campaign"
	name_edit.select_all_on_focus = true
	vbox.add_child(name_edit)

	dlg.add_child(vbox)
	add_child(dlg)
	var _nc_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _nc_reg != null and _nc_reg.ui_theme != null:
		_nc_reg.ui_theme.theme_control_tree(dlg, _ui_scale())
	if mgr != null:
		mgr.scale_control_fonts(vbox)
		mgr.scale_button(dlg.get_ok_button())

	dlg.confirmed.connect(func() -> void:
		var registry2 := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry2 == null or registry2.campaign == null:
			dlg.queue_free()
			return
		if registry2.campaign.get_active_campaign() != null:
			registry2.campaign.save_campaign()
		var camp_name: String = name_edit.text.strip_edges()
		if camp_name.is_empty():
			camp_name = "Untitled Campaign"
		var campaign: CampaignData = registry2.campaign.new_campaign(camp_name, "2014")
		if campaign != null:
			_set_status("New campaign created: %s" % campaign.name)
			_open_campaign_panel(CampaignPanel.TAB_OVERVIEW)
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	if mgr != null:
		mgr.popup_fitted(dlg, 360.0, 130.0)
	else:
		dlg.popup_centered()


func _on_open_campaign() -> void:
	## Show the campaign browser (same UI as startup / post-close).
	_open_campaign_browser()


func _on_open_campaign_folder() -> void:
	## Use a native folder-picker to import a .campaign directory from a
	## non-standard location.  Campaigns are directory bundles, so
	## FILE_MODE_OPEN_DIR with use_native_dialog=true gives a native OS
	## folder picker on all platforms.
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	fd.title = "Open Campaign Folder"
	fd.use_native_dialog = true
	fd.access = FileDialog.ACCESS_FILESYSTEM
	var campaigns_abs: String = ProjectSettings.globalize_path("user://data/campaigns/")
	DirAccess.make_dir_recursive_absolute(campaigns_abs)
	fd.current_dir = campaigns_abs
	add_child(fd)
	fd.dir_selected.connect(func(path: String) -> void:
		var registry2 := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry2 == null or registry2.campaign == null:
			fd.queue_free()
			return
		var campaign: CampaignData = registry2.campaign.open_campaign(path)
		if campaign != null:
			_set_status("Opened campaign: %s" % campaign.name)
			_open_campaign_panel(CampaignPanel.TAB_OVERVIEW)
		else:
			_set_status("Failed to open campaign — select the .campaign folder")
		fd.queue_free()
	)
	fd.canceled.connect(func() -> void: fd.queue_free())
	fd.popup_centered(Vector2i(720, 500))


func _on_save_campaign() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null:
		return
	if registry.campaign.get_active_campaign() == null:
		_set_status("No campaign to save")
		return
	if registry.campaign.save_campaign():
		_set_status("Campaign saved")
	else:
		_set_status("Failed to save campaign")


func _on_close_campaign() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null:
		return
	if registry.campaign.get_active_campaign() != null:
		registry.campaign.save_campaign()
		registry.campaign.close_campaign()
		_set_status("Campaign closed")
	if _campaign_panel != null and is_instance_valid(_campaign_panel):
		_campaign_panel.hide()
	_open_campaign_browser()


func _on_close_map() -> void:
	## Unload the current map and return to the campaign hub (if a campaign is
	## active) or do nothing if no map is loaded.
	if _active_map_bundle_path.is_empty() and _map_view.map_image.texture == null:
		_set_status("No map is currently open")
		return
	# Save the map before closing.
	var map: MapData = _map()
	if map != null:
		_map_view.save_camera_to_map()
		_save_map_data(map)
	_active_map_bundle_path = ""
	_active_map_zip_path = ""
	_active_save_bundle_path = ""
	_active_save_zip_path = ""
	# Reset map state in services.
	var ms := _map_service()
	if ms != null:
		ms.load(MapData.new())
	_map_view.clear_map()
	_nm_broadcast_map(MapData.new())
	_set_status("Map closed")
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.campaign != null and registry.campaign.get_active_campaign() != null:
		_open_campaign_hub()


# ---------------------------------------------------------------------------
# Quit-time unsaved-changes prompt
# ---------------------------------------------------------------------------

func has_unsaved_changes() -> bool:
	## Returns true when any subsystem has data that would be lost on quit.
	if _char_sheet != null and _char_sheet.is_dirty():
		return true
	if not _active_save_bundle_path.is_empty():
		return true
	return false


func prompt_save_before_quit() -> void:
	## Show a themed quit-confirmation dialog when unsaved work exists.
	## Saves campaign, character sheet, and optionally the game save, then quits.
	## If the user cancels, the quit is aborted.
	var char_dirty: bool = _char_sheet != null and _char_sheet.is_dirty()
	var save_active: bool = not _active_save_bundle_path.is_empty()

	# Build description of what is unsaved.
	var parts: PackedStringArray = PackedStringArray()
	if char_dirty:
		var ch_name: String = _char_sheet.get_character_name() if _char_sheet != null else "character"
		parts.append("character sheet (%s)" % ch_name)
	if save_active:
		parts.append("game save")
	var detail: String = ", ".join(parts)

	var s: float = _ui_scale()
	var dlg := ConfirmationDialog.new()
	dlg.title = "Quit — Unsaved Changes"
	dlg.dialog_text = "You have unsaved changes: %s.\n\nSave before quitting?" % detail
	dlg.ok_button_text = "Save & Quit"
	dlg.cancel_button_text = "Cancel"
	dlg.add_button("Quit Without Saving", false, "nosave")
	dlg.exclusive = true
	add_child(dlg)
	var _q_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _q_reg != null and _q_reg.ui_theme != null:
		_q_reg.ui_theme.prepare_window(dlg, 15.0)
	dlg.min_size = Vector2i(roundi(380.0 * s), roundi(140.0 * s))
	dlg.reset_size()
	dlg.popup_centered()

	var result: Array = []
	dlg.confirmed.connect(func() -> void: result.append(&"save"))
	dlg.custom_action.connect(func(action: StringName) -> void:
		if action == &"nosave":
			result.append(&"nosave")
			dlg.hide())
	dlg.canceled.connect(func() -> void: result.append(&"cancel"))
	await dlg.visibility_changed
	dlg.queue_free()

	var choice: StringName = result[0] if result.size() > 0 else &"cancel"
	if choice == &"cancel":
		return # abort quit

	if choice == &"save":
		# Save dirty character sheet.
		if char_dirty and _char_sheet != null:
			_char_sheet.save_now()
		# Save the active game session.
		if save_active:
			await _on_save_game_pressed()
		# Save the campaign (always safe to call).
		_on_save_campaign()

	get_tree().quit()


func _on_close_save() -> void:
	## Prompt to save, then unload map + save and return to the campaign hub.
	if _active_save_bundle_path.is_empty():
		_set_status("No save is currently loaded")
		return
	var s: float = _ui_scale()
	var dlg := ConfirmationDialog.new()
	dlg.title = "Close Save"
	dlg.dialog_text = "Save game before closing?\n\nUnsaved progress will be lost."
	dlg.ok_button_text = "Save & Close"
	dlg.cancel_button_text = "Cancel"
	dlg.add_button("Close Without Saving", false, "nosave")
	add_child(dlg)
	var _cs_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _cs_reg != null and _cs_reg.ui_theme != null:
		_cs_reg.ui_theme.theme_control_tree(dlg, s)
	dlg.confirmed.connect(func() -> void:
		await _on_save_game_pressed()
		_do_close_save()
		dlg.queue_free()
	)
	dlg.custom_action.connect(func(action: StringName) -> void:
		if action == "nosave":
			_do_close_save()
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.popup_centered()


func _do_close_save() -> void:
	## Unload both the current save session and map, then return to the campaign hub.
	_active_save_bundle_path = ""
	_active_save_zip_path = ""
	var gs := _game_state()
	if gs != null:
		gs.reset_session()
	_active_map_bundle_path = ""
	_active_map_zip_path = ""
	var ms := _map_service()
	if ms != null:
		ms.load(MapData.new())
	if _map_view != null:
		_map_view.clear_map()
	_nm_broadcast_map(MapData.new())
	_set_status("Save closed")
	var reg2 := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg2 != null and reg2.campaign != null and reg2.campaign.get_active_campaign() != null:
		_open_campaign_hub()


func _on_campaign_settings() -> void:
	_open_campaign_hub()


func _open_campaign_hub(tab_index: int = CampaignPanel.TAB_OVERVIEW) -> void:
	## Show the CampaignPanel hub. This is the central screen when a campaign is
	## active but no map/save is loaded. The X button simply hides the hub —
	## only File → Close Campaign actually closes the campaign.
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null:
		return
	if registry.campaign.get_active_campaign() == null:
		_set_status("No active campaign — create or open one first")
		return
	# Hide the campaign browser (startup/post-close selection window) so it
	# doesn't linger behind the hub or reappear when the hub is later hidden.
	if _campaign_browser != null and _campaign_browser is Window and (_campaign_browser as Window).visible:
		(_campaign_browser as Window).hide()
	if _campaign_panel == null:
		_campaign_panel = CampaignPanel.new()
		add_child(_campaign_panel)
		_campaign_panel.new_character_requested.connect(_on_chars_new_pressed)
		_campaign_panel.edit_character_requested.connect(_on_campaign_panel_edit_character)
		_campaign_panel.map_open_requested.connect(_on_campaign_map_open_requested)
		_campaign_panel.save_load_requested.connect(_on_campaign_save_load_requested)
		_campaign_panel.new_map_requested.connect(_on_new_map_pressed)
		_campaign_panel.new_save_requested.connect(_on_save_game_pressed)
		_campaign_panel.add_map_browse_requested.connect(_on_campaign_panel_add_map_browse)
		_campaign_panel.add_save_browse_requested.connect(_on_campaign_panel_add_save_browse)
		_campaign_panel.open_map_file_requested.connect(_on_open_map_pressed)
		_campaign_panel.open_save_file_requested.connect(_on_load_game_pressed)
		_campaign_panel.visibility_changed.connect(_update_campaign_indicator)
		_apply_dialog_themes()
	_campaign_panel.open_to_tab(tab_index)
	_apply_ui_scale()
	_campaign_panel.reset_size()
	_show_window_centered(_campaign_panel, 0.85)


func _open_campaign_panel(tab_index: int = CampaignPanel.TAB_OVERVIEW) -> void:
	## Legacy alias — routes to _open_campaign_hub().
	_open_campaign_hub(tab_index)


func _open_campaign_browser() -> void:
	## Show the campaign selection browser (startup screen / post-close).
	if _campaign_browser == null:
		_campaign_browser = CampaignBrowserScript.new()
		add_child(_campaign_browser)
		_campaign_browser.campaign_selected.connect(_on_campaign_browser_selected)
		_campaign_browser.create_new_requested.connect(_on_new_campaign)
		_campaign_browser.open_folder_requested.connect(_on_open_campaign_folder)
	var _cb_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _cb_reg != null and _cb_reg.ui_theme != null:
		_cb_reg.ui_theme.theme_control_tree(_campaign_browser, _ui_scale())
	_campaign_browser.populate()
	_campaign_browser.reset_size()
	_show_window_centered(_campaign_browser, 0.85)


func _on_campaign_browser_selected(path: String) -> void:
	## Called when the DM selects a campaign card in the browser.
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null:
		return
	var campaign: CampaignData = registry.campaign.open_campaign(path)
	if campaign != null:
		_set_status("Opened campaign: %s" % campaign.name)
		_open_campaign_hub()
	else:
		_set_status("Failed to open campaign — select the .campaign folder")
		_open_campaign_browser()


func _on_campaign_map_open_requested(path: String) -> void:
	## Map open requested from campaign hub — hide hub then load map.
	if _campaign_panel != null and is_instance_valid(_campaign_panel):
		_campaign_panel.hide()
	_on_map_bundle_selected(path)


func _on_campaign_save_load_requested(path: String) -> void:
	## Save load requested from campaign hub — hide hub then load save.
	if _campaign_panel != null and is_instance_valid(_campaign_panel):
		_campaign_panel.hide()
	_on_load_game_path_selected(path)


func _on_campaign_panel_add_map_browse() -> void:
	## Open BundleBrowser in pick mode (maps tab only) so the DM can link
	## an existing .map bundle to the current campaign.
	_ensure_maps_dir()
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null or registry.campaign.get_active_campaign() == null:
		return
	if _bundle_browser == null:
		_bundle_browser = BundleBrowserScript.new()
		add_child(_bundle_browser)
		_bundle_browser.map_selected.connect(_on_map_bundle_selected)
		_bundle_browser.save_selected.connect(_on_load_game_path_selected)
		_bundle_browser.new_map_requested.connect(_on_new_map_pressed)
		_bundle_browser.open_map_file_requested.connect(_on_open_map_pressed)
		_bundle_browser.open_save_file_requested.connect(_on_load_game_pressed)
		var _bb_reg2 := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if _bb_reg2 != null and _bb_reg2.ui_theme != null:
			_bb_reg2.ui_theme.theme_control_tree(_bundle_browser, _ui_scale())
	## One-shot: disconnect any stale pick callback then attach the unified handler.
	if _bundle_browser.bundle_picked.is_connected(_on_campaign_bundle_picked):
		_bundle_browser.bundle_picked.disconnect(_on_campaign_bundle_picked)
	_bundle_browser.bundle_picked.connect(_on_campaign_bundle_picked, CONNECT_ONE_SHOT)
	_bundle_browser.open_as_picker("map")
	_bundle_browser.populate()
	_bundle_browser.call_deferred(&"popup_centered_ratio", 0.85)
	_bundle_browser.call_deferred(&"grab_focus")


func _on_campaign_bundle_picked(path: String, bundle_type: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null or registry.campaign.get_active_campaign() == null:
		return
	if bundle_type == "map":
		registry.campaign.add_map_path(path)
		registry.campaign.save_campaign()
		_set_status("Map linked to campaign: %s" % path.get_file())
		if _campaign_panel != null and is_instance_valid(_campaign_panel):
			_campaign_panel.refresh_maps()
	else:
		registry.campaign.add_save_path(path)
		registry.campaign.save_campaign()
		_set_status("Save linked to campaign: %s" % path.get_file())
		if _campaign_panel != null and is_instance_valid(_campaign_panel):
			_campaign_panel.refresh_saves()


func _on_campaign_panel_add_save_browse() -> void:
	## Open BundleBrowser in pick mode (saves tab only) so the DM can link
	## an existing .sav bundle to the current campaign.
	var dir := _saves_dir_abs()
	DirAccess.make_dir_recursive_absolute(dir)
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null or registry.campaign.get_active_campaign() == null:
		return
	if _bundle_browser == null:
		_bundle_browser = BundleBrowserScript.new()
		add_child(_bundle_browser)
		_bundle_browser.map_selected.connect(_on_map_bundle_selected)
		_bundle_browser.save_selected.connect(_on_load_game_path_selected)
		_bundle_browser.new_map_requested.connect(_on_new_map_pressed)
		_bundle_browser.open_map_file_requested.connect(_on_open_map_pressed)
		_bundle_browser.open_save_file_requested.connect(_on_load_game_pressed)
		var _bb_reg3 := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if _bb_reg3 != null and _bb_reg3.ui_theme != null:
			_bb_reg3.ui_theme.theme_control_tree(_bundle_browser, _ui_scale())
	## One-shot: disconnect any stale pick callback then attach the unified handler.
	if _bundle_browser.bundle_picked.is_connected(_on_campaign_bundle_picked):
		_bundle_browser.bundle_picked.disconnect(_on_campaign_bundle_picked)
	_bundle_browser.bundle_picked.connect(_on_campaign_bundle_picked, CONNECT_ONE_SHOT)
	_bundle_browser.open_as_picker("save")
	_bundle_browser.populate()
	_bundle_browser.call_deferred(&"popup_centered_ratio", 0.85)
	_bundle_browser.call_deferred(&"grab_focus")


func _on_campaign_save_bundle_picked(path: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.campaign != null and registry.campaign.get_active_campaign() != null:
		registry.campaign.add_save_path(path)
		registry.campaign.save_campaign()
		_set_status("Save linked to campaign: %s" % path.get_file())
	if _campaign_panel != null and is_instance_valid(_campaign_panel):
		_campaign_panel.refresh_saves()


func _open_campaign_panel_to_characters() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var campaign_active: bool = registry != null and registry.campaign != null and registry.campaign.get_active_campaign() != null
	if campaign_active:
		_open_campaign_panel(CampaignPanel.TAB_CHARACTERS)
	else:
		_open_characters_manager()


func _on_campaign_panel_edit_character(statblock_id: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.character == null:
		_set_status("Character service unavailable.")
		return
	var sb: StatblockData = registry.character.get_character_by_id(statblock_id)
	if sb != null:
		_open_char_sheet_for(sb)
	else:
		_set_status("Character not found — it may have been deleted.")


func _on_prefetch_monster_art() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.srd == null:
		return

	_set_status("Downloading monster art…")

	# Signal subscription: ISRDLibraryService extends Node; signals live on the
	# Node instance. Approved narrow exception per architecture instructions.
	var svc: ISRDLibraryService = registry.srd.service
	if svc == null:
		return

	svc.image_prefetch_progress.connect(func(current: int, total: int) -> void:
		_set_status("Downloading monster art: %d / %d" % [current, total])
	)
	svc.image_prefetch_completed.connect(func() -> void:
		_set_status("Monster art download complete")
	)
	registry.srd.prefetch_all_monster_images()


func _on_session_menu_id(id: int) -> void:
	match id:
		30: _show_share_player_link()


func _on_view_menu_id(id: int) -> void:
	match id:
		20: # Toggle toolbar
			if _palette != null:
				_palette.visible = !_palette.visible
				_set_view_checked(20, _palette.visible)
		25: # Toggle player freeze panel
			if _freeze_panel != null:
				_freeze_panel.visible = !_freeze_panel.visible
				_set_view_checked(25, _freeze_panel.visible)
				_apply_effect_panel_size()
		29: # Toggle effect panel
			if _effect_panel != null:
				_effect_panel.visible = !_effect_panel.visible
				_set_view_checked(29, _effect_panel.visible)
				_apply_effect_panel_size()
		21: # Toggle grid overlay
			if _map_view:
				var go: Node2D = _map_view.grid_overlay
				go.visible = !go.visible
				_set_view_checked(21, go.visible)
		22: # Reset DM view
			if _map_view:
				_map_view._reset_camera()
		24: # Manual fog resync
			_manual_fog_sync_now()
		27: # Reset fog to fully hidden
			_show_fog_reset_confirm()
		30: # Toggle fog of war (both views)
			var fog_idx := _view_menu.get_item_index(30)
			var fog_on := not _view_menu.is_item_checked(fog_idx)
			_set_view_checked(30, fog_on)
			if _map_view:
				_map_view.set_fog_enabled(fog_on)
			var map_for_fog: MapData = _map()
			if map_for_fog != null:
				map_for_fog.fog_enabled = fog_on
				_save_map_data(map_for_fog)
			_nm_broadcast_to_displays({"msg": "fog_enabled_toggle", "enabled": fog_on})
		28: # Toggle fog overlay effect
			var idx := _view_menu.get_item_index(28)
			var on := not _view_menu.is_item_checked(idx)
			_set_view_checked(28, on)
			if _map_view:
				_map_view.set_fog_overlay_enabled(on)
			_nm_broadcast_to_displays({"msg": "fog_overlay_toggle", "enabled": on})
		26: # Toggle measurement tools panel
			if _measure_panel != null:
				_measure_panel.visible = !_measure_panel.visible
				_set_view_checked(26, _measure_panel.visible)
				if _measure_panel.visible:
					_apply_measure_panel_size()
				if not _measure_panel.visible and _map_view != null:
					_map_view._set_active_tool(_map_view.Tool.SELECT)
		31: # Open background audio volume window
			_open_volume_window()
		32: # Open statblock library
			_open_statblock_library()
		36: # Open item library
			_open_item_library()
		33: # Toggle dice tray
			_toggle_dice_tray()
		34: # Toggle initiative panel
			_toggle_initiative_panel()
		35: # Toggle combat log panel
			_toggle_combat_log_panel()
		37: # Open campaign hub
			_on_campaign_settings()
		23: # Launch player display process
			_launch_player_process()


# ---------------------------------------------------------------------------
# UI Theme switching
# ---------------------------------------------------------------------------

func _apply_dialog_themes() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null:
		# ServiceRegistry is added deferred — fall back to bootstrap during _ready()
		var _bootstrap := get_node_or_null("/root/ServiceBootstrap")
		if _bootstrap != null and _bootstrap.get("registry") != null:
			reg = _bootstrap.registry as ServiceRegistry
	if reg == null or reg.ui_theme == null:
		return
	var tm: UIThemeManager = reg.ui_theme
	var s: float = _ui_scale()
	var dialogs: Array[Window] = []
	if _cal_dialog != null:
		dialogs.append(_cal_dialog)
	if _manual_scale_dialog != null:
		dialogs.append(_manual_scale_dialog)
	if _offset_dialog != null:
		dialogs.append(_offset_dialog)
	if _token_editor_dialog != null:
		dialogs.append(_token_editor_dialog)
	if _profiles_dialog != null:
		dialogs.append(_profiles_dialog)
	if _share_dialog != null:
		dialogs.append(_share_dialog)
	if _fog_reset_dialog != null:
		dialogs.append(_fog_reset_dialog)
	if _profile_delete_confirm_dialog != null:
		dialogs.append(_profile_delete_confirm_dialog)
	if _bundle_browser != null and _bundle_browser is Window:
		dialogs.append(_bundle_browser as Window)
	if _campaign_browser != null and _campaign_browser is Window:
		dialogs.append(_campaign_browser as Window)
	if _volume_window != null:
		dialogs.append(_volume_window)
	if _statblock_library != null:
		dialogs.append(_statblock_library)
		# StatblockEditor is child of StatblockLibrary — theme propagates
	if _item_library != null:
		dialogs.append(_item_library)
	if _progress_dialog != null:
		dialogs.append(_progress_dialog)
	if _convert_settings_dialog != null:
		dialogs.append(_convert_settings_dialog)
	for dlg: Window in dialogs:
		# Theme the window chrome + recursively style every child control
		tm.theme_control_tree(dlg, s)
	# Dice tray is a PanelContainer (not a Window) — theme it + its floating window
	if _dice_tray != null:
		var dt: DiceTray = _dice_tray as DiceTray
		if dt != null:
			dt.refresh_theme()
	if _dice_tray_window != null:
		tm.theme_control_tree(_dice_tray_window, s)
	# Initiative panel + floating window
	if _initiative_panel != null:
		tm.theme_control_tree(_initiative_panel, s)
	if _initiative_panel_window != null:
		tm.theme_control_tree(_initiative_panel_window, s)
	# Combat log panel + floating window
	if _combat_log_panel != null:
		tm.theme_control_tree(_combat_log_panel, s)
	if _combat_log_panel_window != null:
		tm.theme_control_tree(_combat_log_panel_window, s)
	if _quick_damage_dialog != null:
		tm.theme_control_tree(_quick_damage_dialog, s)
	if _save_results_panel != null:
		tm.theme_control_tree(_save_results_panel, s)
	if _save_config_dialog != null:
		tm.theme_control_tree(_save_config_dialog, s)
	if _crop_editor_dialog != null:
		tm.theme_control_tree(_crop_editor_dialog, s)
	if _char_mgr_dialog != null:
		tm.theme_control_tree(_char_mgr_dialog, s)
	if _char_wizard != null:
		tm.theme_control_tree(_char_wizard, s)
	if _char_sheet != null:
		_char_sheet.reapply_theme()
	if _level_up_wizard != null:
		_level_up_wizard.reapply_theme()
	if _campaign_panel != null:
		tm.theme_control_tree(_campaign_panel, s)
	if _statblocks_import_dialog != null:
		dialogs.append(_statblocks_import_dialog)
	if _statblocks_export_dialog != null:
		dialogs.append(_statblocks_export_dialog)
	if _campaign_import_dialog != null:
		dialogs.append(_campaign_import_dialog)
	if _campaign_export_dialog != null:
		dialogs.append(_campaign_export_dialog)


func _on_theme_submenu_id(id: int) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.ui_theme != null:
		registry.ui_theme.set_theme(id)


func _on_ui_theme_changed(preset: int) -> void:
	_sync_theme_submenu_checks(preset)
	_apply_dialog_themes()
	# Refresh panel button/label colours
	var tp: ToolPalette = _palette as ToolPalette
	if tp != null:
		tp.refresh_theme()
	var ep: EffectPanel = _effect_panel as EffectPanel
	if ep != null:
		ep.refresh_theme()
	# Refresh freeze panel label tint
	var _tc_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _tc_reg != null and _tc_reg.ui_theme != null:
		var tint: Color = _tc_reg.ui_theme.get_label_tint()
		if _freeze_panel_title != null:
			_freeze_panel_title.add_theme_color_override("font_color", tint)


func _sync_theme_submenu_checks(preset: int) -> void:
	if _theme_submenu == null:
		return
	for i: int in _theme_submenu.item_count:
		var item_id: int = _theme_submenu.get_item_id(i)
		_theme_submenu.set_item_checked(i, item_id == preset)
	if _native_menu:
		_native_menu.call(&"SetRadioChecked", "UITheme", 0, 4, preset)


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


func _on_dm_fog_visible_toggled(enabled: bool) -> void:
	if _map_view == null:
		return
	_map_view.set_dm_fog_visible(enabled)


func _on_flashlights_only_toggled(enabled: bool) -> void:
	if _map_view == null:
		return
	_map_view.set_flashlights_only(enabled)
	_nm_broadcast_to_displays({"msg": "flashlights_only_toggle", "enabled": enabled})


func _on_darkvision_disabled_toggled(disabled: bool) -> void:
	var gs := _game_state()
	if gs == null:
		return
	gs.set_darkvision_disabled(disabled)
	_broadcast_player_state()


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

func _on_grid_type_selected_by_id(grid_id: int) -> void:
	var map: MapData = _map()
	if map == null:
		return
	map.grid_type = grid_id
	_grid_type_selected = grid_id
	# Keep hex_size and cell_px in sync so switching grid type preserves
	# the calibrated scale.  CalibrationTool and manual-scale both enforce
	# hex_size = cell_px / 2.0; replicate that invariant here.
	map.hex_size = map.cell_px / 2.0
	_map_view.grid_overlay.apply_map_data(map)
	_resize_tokens_for_calibration(map)
	_nm_broadcast_map_update(map)
	_broadcast_player_state()
	_update_effect_panel_calibration()
	_update_measurement_overlay_scale()
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
	_resize_tokens_for_calibration(map)
	_nm_broadcast_map_update(map)
	_broadcast_player_state()
	_update_effect_panel_calibration()
	_update_measurement_overlay_scale()
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
	_resize_tokens_for_calibration(map)
	_nm_broadcast_map_update(map)
	_broadcast_player_state()
	_update_effect_panel_calibration()
	_update_measurement_overlay_scale()
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

	_profile_search_edit = LineEdit.new()
	_profile_search_edit.placeholder_text = "Filter profiles..."
	_profile_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_search_edit.clear_button_enabled = true
	if _sm != null:
		_profile_search_edit.add_theme_font_size_override("font_size", _sm.scaled(13.0))
	_profile_search_edit.text_changed.connect(_on_profile_search_changed)
	left_panel.add_child(_profile_search_edit)

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

	var size_lbl := Label.new(); size_lbl.text = "Token Size:"; form.add_child(size_lbl)
	_profile_size_option = OptionButton.new()
	for size_label: String in StatblockData.SIZE_LABELS:
		_profile_size_option.add_item(size_label)
	_profile_size_option.select(2) # default: Medium
	form.add_child(_profile_size_option)

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

	# Profile icon image row.
	var pi_lbl := Label.new(); pi_lbl.text = "Icon Image:"; form.add_child(pi_lbl)
	var pi_row := HBoxContainer.new()
	pi_row.add_theme_constant_override("separation", 6)
	_profile_icon_preview = TextureRect.new()
	_profile_icon_preview.custom_minimum_size = Vector2(48, 48)
	_profile_icon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_profile_icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pi_row.add_child(_profile_icon_preview)
	_profile_icon_choose_btn = Button.new()
	_profile_icon_choose_btn.text = "Choose..."
	_profile_icon_choose_btn.pressed.connect(_on_profile_icon_choose_pressed)
	pi_row.add_child(_profile_icon_choose_btn)
	_profile_icon_clear_btn = Button.new()
	_profile_icon_clear_btn.text = "Clear"
	_profile_icon_clear_btn.pressed.connect(_on_profile_icon_clear_pressed)
	pi_row.add_child(_profile_icon_clear_btn)
	_profile_icon_crop_btn = Button.new()
	_profile_icon_crop_btn.text = "Edit Crop"
	_profile_icon_crop_btn.disabled = true
	_profile_icon_crop_btn.pressed.connect(_on_profile_icon_crop_pressed)
	pi_row.add_child(_profile_icon_crop_btn)
	var profile_campaign_btn := Button.new()
	profile_campaign_btn.text = "Campaign..."
	profile_campaign_btn.tooltip_text = "Pick from campaign image library"
	profile_campaign_btn.pressed.connect(_on_profile_icon_campaign_pressed)
	pi_row.add_child(profile_campaign_btn)
	form.add_child(pi_row)
	var pi_path_row := HBoxContainer.new()
	pi_path_row.add_theme_constant_override("separation", 4)
	_profile_icon_path_edit = LineEdit.new()
	_profile_icon_path_edit.placeholder_text = "Or paste image path..."
	_profile_icon_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pi_path_row.add_child(_profile_icon_path_edit)
	_profile_icon_load_btn = Button.new()
	_profile_icon_load_btn.text = "Load"
	_profile_icon_load_btn.pressed.connect(_on_profile_icon_load_pressed)
	pi_path_row.add_child(_profile_icon_load_btn)
	form.add_child(pi_path_row)

	var char_link_lbl := Label.new()
	char_link_lbl.text = "Linked Character:"
	form.add_child(char_link_lbl)
	var char_link_row := HBoxContainer.new()
	char_link_row.add_theme_constant_override("separation", 6)
	_profile_char_option = OptionButton.new()
	_profile_char_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profile_char_option.add_item("— None —")
	_profile_char_option.set_item_metadata(0, "")
	_profile_char_option.item_selected.connect(_on_profile_char_link_changed)
	char_link_row.add_child(_profile_char_option)
	var char_open_btn := Button.new()
	char_open_btn.text = "Open Sheet"
	char_open_btn.pressed.connect(_on_profile_open_sheet_pressed)
	char_link_row.add_child(char_open_btn)
	form.add_child(char_link_row)

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

	var session_sep := HSeparator.new()
	right_panel.add_child(session_sep)

	_profile_active_check = CheckBox.new()
	_profile_active_check.text = "Active in current session"
	_profile_active_check.disabled = true
	_profile_active_check.toggled.connect(_on_profile_active_toggled)
	right_panel.add_child(_profile_active_check)

	var session_hint := Label.new()
	session_hint.text = "(no effect when no session is loaded)"
	session_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	right_panel.add_child(session_hint)

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

	_profile_undo_btn = Button.new()
	_profile_undo_btn.text = "Undo"
	_profile_undo_btn.disabled = true
	_profile_undo_btn.pressed.connect(_on_profile_undo_pressed)
	action_row.add_child(_profile_undo_btn)

	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(fill)

	var hint_margin := MarginContainer.new()
	hint_margin.add_theme_constant_override("margin_right", 12)
	var hint := Label.new()
	hint.text = "Tip: Unknown keys in extras are preserved across save/load."
	hint_margin.add_child(hint)
	action_row.add_child(hint_margin)

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

	# ── Statblock import / export dialogs ─────────────────────────────────
	_statblocks_export_dialog = FileDialog.new()
	_statblocks_export_dialog.use_native_dialog = true
	_statblocks_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_statblocks_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_statblocks_export_dialog.title = "Export Statblocks as JSON"
	_statblocks_export_dialog.add_filter("*.json ; JSON")
	_statblocks_export_dialog.file_selected.connect(_on_statblocks_export_path_selected)
	add_child(_statblocks_export_dialog)

	_statblocks_import_dialog = FileDialog.new()
	_statblocks_import_dialog.use_native_dialog = true
	_statblocks_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_statblocks_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_statblocks_import_dialog.title = "Import Statblocks from JSON"
	_statblocks_import_dialog.add_filter("*.json ; JSON")
	_statblocks_import_dialog.file_selected.connect(_on_statblocks_import_path_selected)
	add_child(_statblocks_import_dialog)

	# ── Campaign import / export dialogs ──────────────────────────────────
	_campaign_export_dialog = FileDialog.new()
	_campaign_export_dialog.use_native_dialog = true
	_campaign_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_campaign_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_campaign_export_dialog.title = "Export Campaign as JSON"
	_campaign_export_dialog.add_filter("*.campaign.json ; Campaign JSON")
	_campaign_export_dialog.file_selected.connect(_on_campaign_export_path_selected)
	add_child(_campaign_export_dialog)

	_campaign_import_dialog = FileDialog.new()
	_campaign_import_dialog.use_native_dialog = true
	_campaign_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_campaign_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_campaign_import_dialog.title = "Import Campaign from JSON"
	_campaign_import_dialog.add_filter("*.json ; JSON")
	_campaign_import_dialog.file_selected.connect(_on_campaign_import_path_selected)
	add_child(_campaign_import_dialog)


func _open_profiles_editor() -> void:
	_refresh_available_inputs()
	_refresh_profiles_list()
	_update_profile_action_state()
	_apply_ui_scale()
	_apply_dialog_themes()
	_profiles_dialog.popup_centered_ratio(0.9)


func _refresh_profiles_list() -> void:
	if _profiles_list == null:
		return
	_profiles_list.clear()
	_profile_display_indices.clear()
	var pm := _profile_service()
	var gs := _game_state()
	var profiles_arr: Array = pm.get_profiles() if pm != null else []
	var filter := _profile_search_edit.text.strip_edges().to_lower() if _profile_search_edit != null else ""
	for i in range(profiles_arr.size()):
		var profile = profiles_arr[i]
		if not profile is PlayerProfile:
			continue
		var p := profile as PlayerProfile
		if filter != "" and not p.player_name.to_lower().contains(filter):
			continue
		var label: String
		if gs != null and not gs.is_profile_active(p.id):
			label = "%s (%s) [not in session]" % [p.player_name, p.id.left(8)]
		else:
			label = "%s (%s)" % [p.player_name, p.id.left(8)]
		_profiles_list.add_item(label)
		_profile_display_indices.append(i)
		if gs != null and not gs.is_profile_active(p.id):
			var item_idx: int = _profiles_list.item_count - 1
			_profiles_list.set_item_custom_fg_color(item_idx, Color(0.6, 0.6, 0.6))
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

	# Find the list position for the currently selected real profile index.
	var list_pos: int = _profile_display_indices.find(_profile_selected_index)
	if list_pos < 0:
		# Selected profile not visible in current filter — pick first visible.
		if _profile_display_indices.size() > 0:
			list_pos = 0
			_profile_selected_index = _profile_display_indices[0]
		else:
			# Nothing visible (all filtered out) — clear form without losing the selection.
			_profiles_list.deselect_all()
			_clear_profile_form()
			_update_profile_action_state()
			return
	_profiles_list.select(list_pos)
	_load_selected_profile_into_form(_profile_selected_index)
	_update_profile_action_state()


func _clear_profile_form() -> void:
	_profile_id_label.text = "ID: (new profile)" if _profile_is_new_draft else "ID: —"
	_profile_name_edit.text = ""
	_profile_speed_spin.value = 30
	if _profile_size_option != null:
		_profile_size_option.select(2) # Medium
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
	if _profile_active_check:
		_profile_active_check.set_pressed_no_signal(false)
		_profile_active_check.disabled = true
	_on_profile_vision_selected(0)
	if _profile_char_option != null:
		_profile_char_option.clear()
		_profile_char_option.add_item("— None —")
		_profile_char_option.set_item_metadata(0, "")
		_profile_char_option.select(0)
	# Restore editability (no linked character on a cleared form).
	_profile_speed_spin.editable = true
	if _profile_size_option != null:
		_profile_size_option.disabled = false
	_profile_vision_option.disabled = false
	_profile_perception_spin.editable = true
	_update_profile_action_state()

func _on_profile_selected(list_idx: int) -> void:
	_profile_is_new_draft = false
	# Translate the displayed list position to the real profiles-array index.
	var real_idx: int = _profile_display_indices[list_idx] if list_idx < _profile_display_indices.size() else list_idx
	_profile_selected_index = real_idx
	_load_selected_profile_into_form(real_idx)
	_update_profile_action_state()


func _on_profile_search_changed(_new_text: String) -> void:
	_refresh_profiles_list()


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
	if _profile_size_option != null:
		var size_label: String = StatblockData.feet_to_size_label(p.size_ft)
		var idx: int = StatblockData.SIZE_LABELS.find(size_label)
		_profile_size_option.select(idx if idx >= 0 else 2)
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
	# Populate profile icon preview.
	_profile_icon_pending_source = ""
	_profile_icon_crop_offset = p.icon_crop_offset
	_profile_icon_crop_zoom = p.icon_crop_zoom
	_profile_icon_facing_deg = p.icon_facing_deg
	_profile_icon_campaign_image_id = p.icon_campaign_image_id
	if _profile_icon_preview != null:
		if not p.icon_image_path.is_empty():
			var tex: ImageTexture = TokenIconUtils.get_or_load_circular_texture(p.icon_image_path)
			_profile_icon_preview.texture = tex
			if _profile_icon_path_edit != null:
				_profile_icon_path_edit.text = p.icon_image_path
		else:
			_profile_icon_preview.texture = null
			if _profile_icon_path_edit != null:
				_profile_icon_path_edit.text = ""
	if _profile_icon_crop_btn != null:
		_profile_icon_crop_btn.disabled = p.icon_image_path.is_empty()
	if _profile_active_check:
		var gs := _game_state()
		var has_session: bool = gs != null and gs.has_active_session()
		_profile_active_check.disabled = _profile_is_new_draft or not has_session
		# Use set_pressed_no_signal to avoid triggering _on_profile_active_toggled
		# (and the binding rebuild cascade) when merely loading the form.
		if has_session:
			_profile_active_check.set_pressed_no_signal(gs.is_profile_active(p.id))
		else:
			_profile_active_check.set_pressed_no_signal(false)
	_on_profile_vision_selected(_profile_vision_option.selected)
	_refresh_profile_char_link_option(p.statblock_id)
	_update_profile_form_linked_state()
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
	_profile_delete_pending_id = remove_id
	_profile_delete_pending_name = removed_name
	_profile_delete_pending_index = _profile_selected_index
	_profile_delete_pending_snapshot = PlayerProfile.from_dict((item as PlayerProfile).to_dict()) if item is PlayerProfile else null
	_show_profile_delete_confirm(removed_name)


func _show_profile_delete_confirm(profile_name: String) -> void:
	if _profile_delete_confirm_dialog == null:
		_profile_delete_confirm_dialog = ConfirmationDialog.new()
		_profile_delete_confirm_dialog.title = "Remove Profile"
		_profile_delete_confirm_dialog.ok_button_text = "Remove"
		_profile_delete_confirm_dialog.confirmed.connect(_on_profile_delete_confirmed)
		# Add as child of the profiles AcceptDialog so it doesn't conflict with
		# DMWindow's exclusive popup constraint.
		_profiles_dialog.add_child(_profile_delete_confirm_dialog)
		_apply_dialog_themes()
		_apply_ui_scale()
	_profile_delete_confirm_dialog.dialog_text = (
		"Remove \"%s\"?\n\nThis permanently deletes the profile from disk. You can undo this action with Ctrl+Z." % profile_name
	)
	_profile_delete_confirm_dialog.reset_size()
	_profile_delete_confirm_dialog.popup_centered()


func _on_profile_delete_confirmed() -> void:
	var pm := _profile_service()
	if pm == null:
		return
	var remove_id := _profile_delete_pending_id
	var removed_name := _profile_delete_pending_name
	var original_index := _profile_delete_pending_index
	var snapshot: PlayerProfile = _profile_delete_pending_snapshot
	pm.remove_profile(remove_id)
	_profile_selected_index = clampi(_profile_selected_index, 0, max(0, pm.get_profiles().size() - 1))
	_profile_is_new_draft = false
	_refresh_profiles_list()
	_update_profile_action_state()
	_set_status("Deleted profile: %s" % removed_name)
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.history != null and snapshot != null:
		var snap := snapshot
		var rid := remove_id
		var rname := removed_name
		var ridx := original_index
		var undo_fn := func() -> void:
			var pm_u := _profile_service()
			if pm_u == null:
				return
			var arr := pm_u.get_profiles()
			arr.insert(mini(ridx, arr.size()), snap)
			pm_u.set_all_profiles(arr)
			_profile_selected_index = mini(ridx, pm_u.get_profiles().size() - 1)
			_refresh_profiles_list()
			_update_profile_action_state()
			_update_profile_undo_btn()
			_set_status("Restored profile: %s" % rname)
		var redo_fn := func() -> void:
			var pm_r := _profile_service()
			if pm_r == null:
				return
			pm_r.remove_profile(rid)
			_profile_selected_index = clampi(_profile_selected_index, 0, max(0, pm_r.get_profiles().size() - 1))
			_refresh_profiles_list()
			_update_profile_action_state()
			_update_profile_undo_btn()
			_set_status("Deleted profile: %s" % rname)
		registry.history.push_command(HistoryCommand.create(
			"Delete profile \"%s\"" % rname, undo_fn, redo_fn))
	_update_profile_undo_btn()


func _profile_service() -> ProfileManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.profile == null:
		return null
	return registry.profile


func _update_profile_undo_btn() -> void:
	if _profile_undo_btn == null:
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var can := registry != null and registry.history != null and registry.history.can_undo()
	_profile_undo_btn.disabled = not can
	if can and registry != null and registry.history != null:
		_profile_undo_btn.tooltip_text = "Undo: %s" % registry.history.get_undo_description()
	else:
		_profile_undo_btn.tooltip_text = ""


func _on_profile_undo_pressed() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.history == null:
		return
	var desc := registry.history.get_undo_description()
	if registry.history.undo():
		_set_status("Undo: %s" % desc)


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
	_broadcast_player_icon(p)
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
	# Only write manual stat fields when no character sheet is linked — the
	# form shows derived read-only values when linked and we must not overwrite
	# the stored fallbacks with statblock-derived numbers.
	var linked: bool = false
	if _profile_char_option != null and _profile_char_option.selected >= 0:
		linked = str(_profile_char_option.get_item_metadata(_profile_char_option.selected)) != ""
	if not linked:
		p.base_speed = _profile_speed_spin.value
		if _profile_size_option != null and _profile_size_option.selected >= 0:
			var size_label: String = _profile_size_option.get_item_text(_profile_size_option.selected)
			p.size_ft = StatblockData.size_to_feet(size_label)
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

	# Save profile icon image.
	if not _profile_icon_pending_source.is_empty():
		# Delete old icon if present.
		if not p.icon_image_path.is_empty():
			TokenIconUtils.delete_icon_file(p.icon_image_path)
			TokenIconUtils.evict(p.icon_image_path)
		var dest_dir: String = "user://data/profile_icons"
		p.ensure_id()
		var dest_path: String = dest_dir.path_join("%s.png" % p.id)
		var err: Error = TokenIconUtils.process_and_save_icon(
			_profile_icon_pending_source, dest_path,
			_profile_icon_crop_offset, _profile_icon_crop_zoom)
		if err == OK:
			p.icon_image_path = dest_path
			p.icon_crop_offset = _profile_icon_crop_offset
			p.icon_crop_zoom = _profile_icon_crop_zoom
			p.icon_facing_deg = _profile_icon_facing_deg
			p.icon_source_path = _profile_icon_pending_source
			p.icon_campaign_image_id = _profile_icon_campaign_image_id
		else:
			_set_status("Failed to save profile icon (error %d)" % err)
	elif _profile_icon_preview != null and _profile_icon_preview.texture == null:
		# DM cleared the icon.
		if not p.icon_image_path.is_empty():
			TokenIconUtils.delete_icon_file(p.icon_image_path)
			TokenIconUtils.evict(p.icon_image_path)
		p.icon_image_path = ""
		p.icon_source_path = ""
		p.icon_crop_offset = Vector2.ZERO
		p.icon_crop_zoom = 1.0
		p.icon_facing_deg = 0.0
		p.icon_campaign_image_id = ""

	# Always persist icon facing direction (can change via crop editor without new source).
	p.icon_facing_deg = _profile_icon_facing_deg

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
	if _profile_char_option != null and _profile_char_option.selected >= 0:
		p.statblock_id = str(_profile_char_option.get_item_metadata(_profile_char_option.selected))
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


func _on_profile_char_link_changed(_index: int) -> void:
	_update_profile_form_linked_state()


## When a statblock is linked, update stat fields to show derived values and
## make them read-only so the DM edits the character sheet instead.
func _update_profile_form_linked_state() -> void:
	if _profile_char_option == null:
		return
	var sb_id: String = ""
	if _profile_char_option.selected >= 0:
		sb_id = str(_profile_char_option.get_item_metadata(_profile_char_option.selected))
	var linked: bool = not sb_id.is_empty()
	var sb: StatblockData = null
	if linked:
		var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if registry != null and registry.character != null:
			sb = registry.character.get_character_by_id(sb_id)
		linked = sb != null
	# Speed — parse from speed dict the same way as PlayerProfile.get_speed()
	if _profile_speed_spin != null:
		_profile_speed_spin.editable = not linked
		if linked and sb != null:
			var walk: Variant = sb.speed.get("walk", "")
			var walk_str: String = str(walk).strip_edges()
			if not walk_str.is_empty():
				var num: String = walk_str.split(" ")[0]
				if num.is_valid_float():
					_profile_speed_spin.value = float(num)
	# Token size
	if _profile_size_option != null:
		_profile_size_option.disabled = linked
		if linked and sb != null and not sb.size.is_empty():
			var ft: float = StatblockData.size_to_feet(sb.size)
			var label: String = StatblockData.feet_to_size_label(ft)
			var idx: int = StatblockData.SIZE_LABELS.find(label)
			if idx >= 0:
				_profile_size_option.select(idx)
	# Vision type + darkvision range
	if _profile_vision_option != null:
		_profile_vision_option.disabled = linked
		if linked and sb != null:
			var dv_val: String = str(sb.senses.get("darkvision", ""))
			if not dv_val.is_empty():
				_profile_vision_option.select(_profile_vision_option.get_item_index(PlayerProfile.VisionType.DARKVISION))
			else:
				_profile_vision_option.select(_profile_vision_option.get_item_index(PlayerProfile.VisionType.NORMAL))
	if _profile_darkvision_spin != null:
		if linked and sb != null:
			var dv_str: String = str(sb.senses.get("darkvision", ""))
			if not dv_str.is_empty():
				var num: String = dv_str.split(" ")[0]
				if num.is_valid_float():
					_profile_darkvision_spin.value = float(num)
			_profile_darkvision_spin.editable = false
		elif not linked:
			_on_profile_vision_selected(_profile_vision_option.selected if _profile_vision_option else 0)
	# Perception mod — compute from wisdom + proficiency
	if _profile_perception_spin != null:
		_profile_perception_spin.editable = not linked
		if linked and sb != null:
			var wis_mod: int = floori((sb.wisdom - 10) / 2.0)
			var has_perc: bool = false
			for prof_entry: Variant in sb.proficiencies:
				if prof_entry is Dictionary:
					var p_info: Variant = (prof_entry as Dictionary).get("proficiency", {})
					if p_info is Dictionary:
						if str((p_info as Dictionary).get("index", "")) == "skill-perception":
							has_perc = true
							break
			var perc_mod: int = wis_mod + (sb.proficiency_bonus if has_perc else 0)
			_profile_perception_spin.value = perc_mod
	if _profile_passive_label != null:
		_profile_passive_label.text = str(10 + int(_profile_perception_spin.value)) if _profile_perception_spin else "10"


# ── Profile icon image helpers ──────────────────────────────────────────────

func _on_profile_icon_choose_pressed() -> void:
	if _profile_icon_file_dialog == null:
		_profile_icon_file_dialog = FileDialog.new()
		_profile_icon_file_dialog.use_native_dialog = true
		_profile_icon_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_profile_icon_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_profile_icon_file_dialog.title = "Select Profile Icon Image"
		for f: String in TokenIconUtils.FILE_DIALOG_FILTERS:
			_profile_icon_file_dialog.add_filter(f)
		_profile_icon_file_dialog.file_selected.connect(_on_profile_icon_file_selected)
		add_child(_profile_icon_file_dialog)
	_profile_icon_file_dialog.popup_centered(Vector2i(800, 500))


func _on_profile_icon_file_selected(path: String) -> void:
	_load_profile_icon_from_path(path)


func _on_profile_icon_load_pressed() -> void:
	if _profile_icon_path_edit == null:
		return
	var path: String = _profile_icon_path_edit.text.strip_edges()
	if path.is_empty():
		return
	_load_profile_icon_from_path(path)


func _load_profile_icon_from_path(path: String) -> void:
	var img: Image = TokenIconUtils.load_image_from_path(path)
	if img == null:
		_set_status("Failed to load icon image: %s" % path)
		return
	_profile_icon_pending_source = path
	_profile_icon_crop_offset = Vector2.ZERO
	_profile_icon_crop_zoom = 1.0
	_profile_icon_facing_deg = 0.0
	var tex: ImageTexture = TokenIconUtils.create_circular_texture(img)
	if _profile_icon_preview != null:
		_profile_icon_preview.texture = tex
	if _profile_icon_path_edit != null:
		_profile_icon_path_edit.text = path
	if _profile_icon_crop_btn != null:
		_profile_icon_crop_btn.disabled = false


func _on_profile_icon_clear_pressed() -> void:
	_profile_icon_pending_source = ""
	_profile_icon_crop_offset = Vector2.ZERO
	_profile_icon_crop_zoom = 1.0
	_profile_icon_facing_deg = 0.0
	_profile_icon_campaign_image_id = ""
	if _profile_icon_preview != null:
		_profile_icon_preview.texture = null
	if _profile_icon_path_edit != null:
		_profile_icon_path_edit.text = ""
	if _profile_icon_crop_btn != null:
		_profile_icon_crop_btn.disabled = true


func _on_profile_icon_campaign_pressed() -> void:
	_ensure_campaign_image_picker()
	if _campaign_image_picker == null:
		return
	if _campaign_image_picker.image_selected.is_connected(_on_profile_campaign_image_picked):
		_campaign_image_picker.image_selected.disconnect(_on_profile_campaign_image_picked)
	_campaign_image_picker.image_selected.connect(_on_profile_campaign_image_picked)
	_campaign_image_picker.show_picker()


func _on_profile_campaign_image_picked(path: String, campaign_image_id: String) -> void:
	_campaign_image_picker.image_selected.disconnect(_on_profile_campaign_image_picked)
	_profile_icon_campaign_image_id = campaign_image_id
	_load_profile_icon_from_path(path)


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
		# When a session is loaded, skip profiles not assigned to it.
		# When no session is loaded, skip all — no players active on a fresh map.
		if gs != null and not gs.is_profile_active(p.id):
			continue
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


func _on_profile_active_toggled(active: bool) -> void:
	if _profile_is_new_draft:
		return
	var pm := _profile_service()
	if pm == null or _profile_selected_index < 0:
		return
	var arr := pm.get_profiles()
	if _profile_selected_index >= arr.size():
		return
	var item = arr[_profile_selected_index]
	if not item is PlayerProfile:
		return
	var gs := _game_state()
	if gs == null or not gs.has_active_session():
		return
	gs.set_profile_active((item as PlayerProfile).id, active)
	# Rebuild bindings immediately so input follows the new assignment.
	_apply_profile_bindings()
	_refresh_profiles_list()


func _on_session_changed(_save_name: String) -> void:
	_on_profiles_changed()
	if _profiles_dialog != null and _profiles_dialog.visible and _profile_selected_index >= 0:
		_load_selected_profile_into_form(_profile_selected_index)


func _on_token_drag_started(token_id: Variant) -> void:
	if _backend != null:
		_backend.begin_token_drag(token_id)
	# Snapshot pre-drag position so drag-complete can compute a correct delta
	# even if a roam tick mutated world_pos in-between.
	var registry_ds := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry_ds != null and registry_ds.token != null:
		var data: TokenData = registry_ds.token.get_token_by_id(str(token_id))
		if data != null:
			_drag_start_positions[str(token_id)] = data.world_pos


func _on_token_drag_completed(token_id: Variant, new_world_pos: Vector2) -> void:
	var id: String = str(token_id)
	var registry_drag := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	# Capture pre-drag position for opportunity attack checking.
	var oa_old_pos: Vector2 = _drag_start_positions.get(id, new_world_pos) as Vector2
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
			# Use the pre-drag snapshot (immune to roam-tick mutations mid-drag).
			var old_pos: Vector2 = _drag_start_positions.get(id, data.world_pos) as Vector2
			_drag_start_positions.erase(id)
			data.world_pos = new_world_pos
			# Offset roam path by the drag delta so the path follows the token.
			var drag_delta: Vector2 = new_world_pos - old_pos
			var old_roam: PackedVector2Array = data.roam_path.duplicate()
			if drag_delta.length_squared() > 0.01 and data.roam_path.size() > 0:
				var shifted := PackedVector2Array()
				for pt: Vector2 in data.roam_path:
					shifted.append(pt + drag_delta)
				data.roam_path = shifted
			registry_drag.token.update_token(data)
			if _map_view != null:
				_map_view.update_token_sprite(data)
				_map_view.apply_token_passthrough_state(data)
			# Re-snap roam animation progress so a running roam resumes
			# from the drop position instead of the pre-drag progress.
			if _roaming_tokens.has(id) and data.roam_path.size() >= 2:
				var rs: Dictionary = _roaming_tokens[id] as Dictionary
				rs["progress"] = _roam_snap_progress(data.roam_path, new_world_pos, data.roam_loop)
			# Push undo command capturing before/after world positions + roam path.
			if registry_drag.history != null and old_pos != new_world_pos:
				var mv := _map_view
				var new_roam: PackedVector2Array = data.roam_path.duplicate()
				registry_drag.history.push_command(HistoryCommand.create("Token moved",
					func():
						var td: TokenData = registry_drag.token.get_token_by_id(id)
						if td == null: return
						td.world_pos = old_pos
						td.roam_path = old_roam
						registry_drag.token.update_token(td)
						if mv != null:
							mv.update_token_sprite(td)
							mv.apply_token_passthrough_state(td)
						_broadcast_token_change(td, false),
					func():
						var td: TokenData = registry_drag.token.get_token_by_id(id)
						if td == null: return
						td.world_pos = new_world_pos
						td.roam_path = new_roam
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
	# Opportunity attack check — only during active combat.
	if data != null and registry_drag != null and registry_drag.combat != null \
			and registry_drag.combat.is_in_combat():
		if oa_old_pos.distance_to(new_world_pos) > 1.0:
			_check_opportunity_attacks(id, oa_old_pos, new_world_pos, registry_drag)


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
# Dice Tray — build, toggle, sizing
# ---------------------------------------------------------------------------

func _build_dice_tray() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null:
		var _bootstrap := get_node_or_null("/root/ServiceBootstrap")
		if _bootstrap != null and _bootstrap.get("registry") != null:
			reg = _bootstrap.registry as ServiceRegistry
	var tm: UIThemeManager = reg.ui_theme if reg != null else null
	var dm: DiceManager = reg.dice if reg != null else null
	_dice_tray = DiceTrayScript.new() as PanelContainer
	(_dice_tray as DiceTray).setup(_get_ui_scale_mgr(), tm, dm)
	_dice_tray.visible = false

	# Anchor to bottom-left
	_dice_tray.anchor_left = 0.0
	_dice_tray.anchor_right = 0.0
	_dice_tray.anchor_top = 1.0
	_dice_tray.anchor_bottom = 1.0
	_dice_tray.grow_horizontal = Control.GROW_DIRECTION_END
	_dice_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ui_content_area.add_child(_dice_tray)
	_apply_dice_tray_size()

	# Undock wire
	var dt: DiceTray = _dice_tray as DiceTray
	if dt != null and dt._undock_btn != null:
		dt._undock_btn.pressed.connect(_on_dice_tray_undock)

	# 3D Dice Renderer — overlay centered in viewport
	_dice_renderer = DiceRenderer3D.new()
	_dice_renderer.anchor_left = 0.5
	_dice_renderer.anchor_right = 0.5
	_dice_renderer.anchor_top = 0.5
	_dice_renderer.anchor_bottom = 0.5
	_dice_renderer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dice_renderer.grow_vertical = Control.GROW_DIRECTION_BOTH
	_dice_renderer.visible = false
	_dice_renderer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_content_area.add_child(_dice_renderer)
	_apply_dice_renderer_size()
	# Wire renderer to dice service
	if dm != null:
		dm.set_renderer(_dice_renderer)


func _apply_status_bar_size() -> void:
	if _status_bar == null:
		return
	var s: float = _ui_scale()
	var bar_h: int = roundi(26.0 * s)
	_status_bar.offset_left = 0.0
	_status_bar.offset_right = 0.0
	_status_bar.offset_top = float(-bar_h)
	_status_bar.offset_bottom = 0.0
	# Shrink content area so overlays never extend behind the status bar.
	if _ui_content_area != null:
		_ui_content_area.offset_bottom = float(-bar_h)


func _apply_dice_tray_size() -> void:
	if _dice_tray == null or _dice_tray_floating:
		return
	var s: float = _ui_scale()
	var panel_w: int = roundi(220.0 * s)
	var panel_h: int = roundi(380.0 * s)
	var palette_w: int = roundi(52.0 * s) if (_palette != null and _palette.visible and not _palette_floating) else 0
	_dice_tray.offset_left = float(palette_w)
	_dice_tray.offset_right = float(palette_w + panel_w)
	_dice_tray.offset_bottom = 0.0
	_dice_tray.offset_top = float(-panel_h)


func _apply_dice_renderer_size() -> void:
	if _dice_renderer == null:
		return
	var s: float = _ui_scale()
	var rw: int = roundi(480.0 * s)
	var rh: int = roundi(360.0 * s)
	var half_w: float = float(rw) * 0.5
	var half_h: float = float(rh) * 0.5
	_dice_renderer.offset_left = - half_w
	_dice_renderer.offset_right = half_w
	_dice_renderer.offset_top = - half_h
	_dice_renderer.offset_bottom = half_h
	_dice_renderer.set_render_size(Vector2i(rw, rh))


func _toggle_dice_tray() -> void:
	if _dice_tray == null:
		return
	if _dice_tray_floating and _dice_tray_window != null:
		_dice_tray_window.visible = not _dice_tray_window.visible
		if _dice_tray_window.visible:
			_dice_tray_window.grab_focus()
	else:
		_dice_tray.visible = not _dice_tray.visible


func _on_dice_tray_undock() -> void:
	if _dice_tray == null:
		return
	if _dice_tray_floating:
		# Re-dock
		if _dice_tray_window != null:
			_dice_tray_window.remove_child(_dice_tray)
			_dice_tray_window.queue_free()
			_dice_tray_window = null
		_dice_tray_floating = false
		# Restore docked anchors (bottom-left, grow right + upward)
		_dice_tray.anchor_left = 0.0
		_dice_tray.anchor_right = 0.0
		_dice_tray.anchor_top = 1.0
		_dice_tray.anchor_bottom = 1.0
		_dice_tray.grow_horizontal = Control.GROW_DIRECTION_END
		_dice_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_ui_content_area.add_child(_dice_tray)
		_dice_tray.visible = true
		_apply_dice_tray_size()
	else:
		# Undock into floating window
		_ui_content_area.remove_child(_dice_tray)
		_dice_tray_floating = true
		var s: float = _ui_scale()
		_dice_tray_window = Window.new()
		_dice_tray_window.title = "Dice Tray"
		_dice_tray_window.size = Vector2i(roundi(240.0 * s), roundi(420.0 * s))
		_dice_tray_window.min_size = Vector2i(roundi(200.0 * s), roundi(300.0 * s))
		_dice_tray_window.transient = true
		_dice_tray_window.wrap_controls = false
		_dice_tray_window.close_requested.connect(func() -> void:
			_dice_tray_window.visible = false
		)
		_dice_tray.set_anchors_preset(Control.PRESET_FULL_RECT)
		_dice_tray.offset_left = 0.0
		_dice_tray.offset_right = 0.0
		_dice_tray.offset_top = 0.0
		_dice_tray.offset_bottom = 0.0
		_dice_tray_window.add_child(_dice_tray)
		add_child(_dice_tray_window)
		_dice_tray.visible = true
		var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg != null and reg.ui_theme != null:
			reg.ui_theme.theme_control_tree(_dice_tray_window, _ui_scale())
		_dice_tray_window.popup_centered()
		_dice_tray_window.grab_focus()


# ---------------------------------------------------------------------------
# Initiative panel — build, toggle, combat signal handlers
# ---------------------------------------------------------------------------

func _build_initiative_panel() -> void:
	_initiative_panel = InitiativePanel.new()
	_initiative_panel.anchor_left = 1.0
	_initiative_panel.anchor_right = 1.0
	_initiative_panel.anchor_top = 0.0
	_initiative_panel.anchor_bottom = 1.0
	_initiative_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_initiative_panel.grow_vertical = Control.GROW_DIRECTION_END
	_initiative_panel.visible = false
	_ui_content_area.add_child(_initiative_panel)
	_apply_initiative_panel_size()
	_initiative_panel.apply_scale(_ui_scale())
	_initiative_panel.damage_requested.connect(_on_initiative_damage_requested)
	_initiative_panel.heal_requested.connect(_on_initiative_heal_requested)
	_initiative_panel.combat_start_requested.connect(_ensure_initiative_panel_visible)
	if _initiative_panel._undock_btn != null:
		_initiative_panel._undock_btn.pressed.connect(_on_initiative_panel_undock)
	# Connect combat service signals for live refresh.
	# ServiceRegistry is added deferred, so fall back to the bootstrap instance
	# when the direct path isn't in the tree yet (same pattern as theming block).
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null:
		var bootstrap := get_node_or_null("/root/ServiceBootstrap")
		if bootstrap != null and bootstrap.get("registry") != null:
			reg = bootstrap.registry as ServiceRegistry
	if reg != null and reg.combat != null:
		# Signal subscription: ICombatService extends Node; signals live on the
		# Node instance. RefCounted manager cannot re-emit — approved exception.
		var csvc: ICombatService = reg.combat.service
		if csvc != null:
			csvc.initiative_changed.connect(_on_combat_initiative_changed)
			csvc.turn_changed.connect(_on_combat_turn_changed)
			csvc.hp_changed.connect(_on_combat_hp_changed)
			csvc.combat_started.connect(_on_combat_started)
			csvc.combat_ended.connect(_on_combat_ended)
			csvc.token_killed.connect(_on_combat_token_killed)
			csvc.condition_applied.connect(_on_condition_applied)
			csvc.condition_removed.connect(_on_condition_removed)
			csvc.log_entry_added.connect(_on_combat_log_entry_added)
			csvc.combatant_added.connect(func(_tid: String) -> void: _refresh_initiative_panel())
			csvc.combatant_removed.connect(func(_tid: String) -> void: _refresh_initiative_panel())


func _apply_initiative_panel_size() -> void:
	if _initiative_panel == null or _initiative_panel_floating:
		return
	var s: float = _ui_scale()
	var panel_w: int = roundi(320.0 * s)
	var menu_h: float = _menu_bar.size.y if _menu_bar != null else 0.0
	# Offset from right edge — stack left of freeze panel if visible.
	var right_offset: int = 0
	if _freeze_panel != null and _freeze_panel.visible and not _freeze_panel_floating:
		right_offset = roundi((_freeze_panel.offset_right - _freeze_panel.offset_left))
	_initiative_panel.offset_left = float(-panel_w - right_offset)
	_initiative_panel.offset_right = float(-right_offset)
	_initiative_panel.offset_top = menu_h
	_initiative_panel.offset_bottom = 0.0


func _toggle_initiative_panel() -> void:
	if _initiative_panel == null:
		return
	if _initiative_panel_floating and _initiative_panel_window != null:
		_initiative_panel_window.visible = not _initiative_panel_window.visible
		if _initiative_panel_window.visible:
			_initiative_panel_window.grab_focus()
	else:
		_initiative_panel.visible = not _initiative_panel.visible
		_set_view_checked(34, _initiative_panel.visible)
	if _initiative_panel.visible or (_initiative_panel_floating and _initiative_panel_window != null and _initiative_panel_window.visible):
		_refresh_initiative_panel()


func _on_initiative_panel_undock() -> void:
	if _initiative_panel == null:
		return
	if _initiative_panel_floating:
		# Re-dock.
		if _initiative_panel_window != null:
			_initiative_panel_window.remove_child(_initiative_panel)
			_initiative_panel_window.queue_free()
			_initiative_panel_window = null
		_initiative_panel_floating = false
		_initiative_panel.anchor_left = 1.0
		_initiative_panel.anchor_right = 1.0
		_initiative_panel.anchor_top = 0.0
		_initiative_panel.anchor_bottom = 1.0
		_initiative_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_initiative_panel.grow_vertical = Control.GROW_DIRECTION_END
		_ui_content_area.add_child(_initiative_panel)
		_initiative_panel.visible = true
		_apply_initiative_panel_size()
		if _initiative_panel._undock_btn != null:
			_initiative_panel._undock_btn.text = "\u21f2"
	else:
		# Undock into floating window.
		_ui_content_area.remove_child(_initiative_panel)
		_initiative_panel_floating = true
		var s: float = _ui_scale()
		_initiative_panel_window = Window.new()
		_initiative_panel_window.title = "Initiative Tracker"
		_initiative_panel_window.size = Vector2i(roundi(340.0 * s), roundi(500.0 * s))
		_initiative_panel_window.min_size = Vector2i(roundi(280.0 * s), roundi(300.0 * s))
		_initiative_panel_window.transient = true
		_initiative_panel_window.wrap_controls = false
		_initiative_panel_window.close_requested.connect(func() -> void:
			_initiative_panel_window.visible = false
		)
		_initiative_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_initiative_panel.offset_left = 0.0
		_initiative_panel.offset_right = 0.0
		_initiative_panel.offset_top = 0.0
		_initiative_panel.offset_bottom = 0.0
		_initiative_panel_window.add_child(_initiative_panel)
		add_child(_initiative_panel_window)
		_initiative_panel.visible = true
		if _initiative_panel._undock_btn != null:
			_initiative_panel._undock_btn.text = "\u21f1"
		var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg != null and reg.ui_theme != null:
			reg.ui_theme.theme_control_tree(_initiative_panel_window, _ui_scale())
		_initiative_panel_window.popup_centered()
		_initiative_panel_window.grab_focus()


# ---------------------------------------------------------------------------
# Combat log panel — build, toggle, undock
# ---------------------------------------------------------------------------

func _build_combat_log_panel() -> void:
	_combat_log_panel = CombatLogPanelScript.new() as PanelContainer
	_combat_log_panel.visible = false
	# Anchor to left edge, full height.
	_combat_log_panel.anchor_left = 0.0
	_combat_log_panel.anchor_right = 0.0
	_combat_log_panel.anchor_top = 0.0
	_combat_log_panel.anchor_bottom = 1.0
	_combat_log_panel.grow_horizontal = Control.GROW_DIRECTION_END
	_combat_log_panel.grow_vertical = Control.GROW_DIRECTION_END
	_ui_content_area.add_child(_combat_log_panel)
	_apply_combat_log_panel_size()
	_combat_log_panel.apply_scale(_ui_scale())
	_combat_log_panel.undock_requested.connect(_on_combat_log_panel_undock)


func _apply_combat_log_panel_size() -> void:
	if _combat_log_panel == null or _combat_log_panel_floating:
		return
	var s: float = _ui_scale()
	var panel_w: int = roundi(340.0 * s)
	var palette_w: int = roundi(52.0 * s) if (_palette != null and _palette.visible and not _palette_floating) else 0
	var menu_h: float = _menu_bar.size.y if _menu_bar != null else 0.0
	_combat_log_panel.offset_left = float(palette_w)
	_combat_log_panel.offset_right = float(palette_w + panel_w)
	_combat_log_panel.offset_top = menu_h
	_combat_log_panel.offset_bottom = 0.0


func _toggle_combat_log_panel() -> void:
	if _combat_log_panel == null:
		return
	if _combat_log_panel_floating and _combat_log_panel_window != null:
		_combat_log_panel_window.visible = not _combat_log_panel_window.visible
		if _combat_log_panel_window.visible:
			_combat_log_panel_window.grab_focus()
	else:
		_combat_log_panel.visible = not _combat_log_panel.visible
		_set_view_checked(35, _combat_log_panel.visible)
	if _combat_log_panel.visible or (_combat_log_panel_floating and \
			_combat_log_panel_window != null and _combat_log_panel_window.visible):
		_refresh_combat_log_panel()


func _refresh_combat_log_panel() -> void:
	if _combat_log_panel == null:
		return
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.combat == null:
		return
	_combat_log_panel.refresh_from_log(reg.combat.get_combat_log())
	_combat_log_panel.apply_scale(_ui_scale())
	if reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(_combat_log_panel, _ui_scale())


func _on_combat_log_panel_undock() -> void:
	if _combat_log_panel == null:
		return
	if _combat_log_panel_floating:
		# Re-dock.
		if _combat_log_panel_window != null:
			_combat_log_panel_window.remove_child(_combat_log_panel)
			_combat_log_panel_window.queue_free()
			_combat_log_panel_window = null
		_combat_log_panel_floating = false
		_combat_log_panel.anchor_left = 0.0
		_combat_log_panel.anchor_right = 0.0
		_combat_log_panel.anchor_top = 0.0
		_combat_log_panel.anchor_bottom = 1.0
		_combat_log_panel.grow_horizontal = Control.GROW_DIRECTION_END
		_combat_log_panel.grow_vertical = Control.GROW_DIRECTION_END
		_ui_content_area.add_child(_combat_log_panel)
		_combat_log_panel.visible = true
		_apply_combat_log_panel_size()
		if _combat_log_panel._undock_btn != null:
			_combat_log_panel._undock_btn.text = "\u21f2"
	else:
		# Undock into floating window.
		_ui_content_area.remove_child(_combat_log_panel)
		_combat_log_panel_floating = true
		var s: float = _ui_scale()
		_combat_log_panel_window = Window.new()
		_combat_log_panel_window.title = "Combat Log"
		_combat_log_panel_window.size = Vector2i(roundi(380.0 * s), roundi(500.0 * s))
		_combat_log_panel_window.min_size = Vector2i(roundi(300.0 * s), roundi(280.0 * s))
		_combat_log_panel_window.transient = true
		_combat_log_panel_window.wrap_controls = false
		_combat_log_panel_window.close_requested.connect(func() -> void:
			_combat_log_panel_window.visible = false
		)
		_combat_log_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		_combat_log_panel.offset_left = 0.0
		_combat_log_panel.offset_right = 0.0
		_combat_log_panel.offset_top = 0.0
		_combat_log_panel.offset_bottom = 0.0
		_combat_log_panel_window.add_child(_combat_log_panel)
		add_child(_combat_log_panel_window)
		_combat_log_panel.visible = true
		if _combat_log_panel._undock_btn != null:
			_combat_log_panel._undock_btn.text = "\u21f1"
		var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg != null and reg.ui_theme != null:
			reg.ui_theme.theme_control_tree(_combat_log_panel_window, _ui_scale())
		_combat_log_panel_window.popup_centered()
		_combat_log_panel_window.grab_focus()


func _refresh_initiative_panel() -> void:
	if _initiative_panel == null:
		return
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.combat == null:
		return
	_initiative_panel.refresh(reg.combat, reg.token, reg.statblock)
	_initiative_panel.apply_scale(_ui_scale())
	# Re-apply theme to all newly created InitiativeEntry children.
	if reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(_initiative_panel, _ui_scale())


func _ensure_initiative_panel_visible() -> void:
	## Make the initiative panel visible when combat starts, regardless of
	## whether it was triggered from the panel itself or the multi-select bar.
	## Also refreshes data so entries are populated at first show.
	if _initiative_panel == null:
		return
	var did_show: bool = false
	if _initiative_panel_floating:
		if _initiative_panel_window != null and not _initiative_panel_window.visible:
			_initiative_panel_window.visible = true
			did_show = true
	elif not _initiative_panel.visible:
		_initiative_panel.visible = true
		_set_view_checked(34, true)
		did_show = true
	if did_show:
		# Recalculate the docked position now that the freeze panel is fully
		# laid out (deferred so scrollbars/content have settled first).
		call_deferred("_apply_initiative_panel_size")
		_refresh_initiative_panel()


## Check whether moving a token out of melee reach triggers opportunity attacks.
## Compares old and new positions against all other combatants.
func _check_opportunity_attacks(moved_id: String, old_pos: Vector2,
		new_pos: Vector2, registry: ServiceRegistry) -> void:
	if registry.token == null or registry.combat == null:
		return
	if not registry.combat.is_in_combat() or not registry.combat.is_combatant(moved_id):
		return
	var px5: float = _pixels_per_5ft_current()
	# Standard melee reach = 5 ft = 1 cell.
	var reach_px: float = px5
	var order: Array = registry.combat.get_initiative_order()
	var threats: PackedStringArray = PackedStringArray()
	for entry: Dictionary in order:
		var tid: String = str(entry.get("token_id", ""))
		if tid.is_empty() or tid == moved_id:
			continue
		var td: TokenData = registry.token.get_token_by_id(tid)
		if td == null:
			continue
		var other_pos: Vector2 = td.world_pos
		var was_adjacent: bool = old_pos.distance_to(other_pos) <= reach_px * 1.5
		var still_adjacent: bool = new_pos.distance_to(other_pos) <= reach_px * 1.5
		if was_adjacent and not still_adjacent:
			var threat_name: String = td.label if not td.label.is_empty() else tid
			threats.append(threat_name)
	if threats.is_empty():
		return
	# Resolve name of the moving token.
	var moved_td: TokenData = registry.token.get_token_by_id(moved_id)
	var moved_name: String = moved_td.label if moved_td != null and not moved_td.label.is_empty() else moved_id
	# Show opportunity attack prompt.
	var msg: String = "%s moved out of melee reach of:\n• %s\n\nOpportunity attack?" % [
		moved_name, "\n• ".join(threats)]
	var dlg := AcceptDialog.new()
	dlg.dialog_text = msg
	dlg.title = "Opportunity Attack"
	dlg.ok_button_text = "Dismiss"
	dlg.add_button("Log OA", true, "log_oa")
	dlg.custom_action.connect(func(action: StringName) -> void:
		if action == &"log_oa" and registry.combat != null:
			for t_name: String in threats:
				registry.combat.add_log_entry({
					"type": "opportunity_attack",
					"text": "%s provoked an opportunity attack from %s" % [moved_name, t_name],
				})
		dlg.hide())
	dlg.canceled.connect(dlg.queue_free)
	dlg.confirmed.connect(dlg.queue_free)
	add_child(dlg)
	if registry.ui_theme != null:
		registry.ui_theme.prepare_window(dlg)
	dlg.popup_centered()


func _on_combat_started() -> void:
	_refresh_initiative_panel()
	_ensure_initiative_panel_visible()


func _on_combat_ended() -> void:
	_refresh_initiative_panel()
	if _map_view != null and not _combat_turn_token_id.is_empty():
		var prev: Node2D = _map_view.get_token_sprite(_combat_turn_token_id)
		if prev != null:
			prev.set_active_turn(false)
	_combat_turn_token_id = ""
	_set_status("Combat ended")


func _on_combat_initiative_changed(_order: Array) -> void:
	_refresh_initiative_panel()


func _on_combat_turn_changed(token_id: String, round_number: int) -> void:
	_refresh_initiative_panel()
	# Restart the turn timer on the initiative panel.
	if _initiative_panel != null:
		_initiative_panel.on_turn_changed()
	# Update active-turn ring on the map.
	if _map_view != null:
		if not _combat_turn_token_id.is_empty():
			var prev: Node2D = _map_view.get_token_sprite(_combat_turn_token_id)
			if prev != null:
				prev.set_active_turn(false)
		var curr: Node2D = _map_view.get_token_sprite(token_id)
		if curr != null:
			curr.set_active_turn(true)
	_combat_turn_token_id = token_id
	# Resolve a human-readable name for status bar and network broadcast.
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var name_str: String = token_id
	var td: TokenData = null
	if reg != null:
		if reg.token != null:
			td = reg.token.get_token_by_id(token_id)
			if td != null and not td.label.is_empty():
				name_str = td.label
		if name_str == token_id and reg.profile != null:
			var prof: Variant = reg.profile.get_profile_by_id(token_id)
			if prof is PlayerProfile and not (prof as PlayerProfile).player_name.is_empty():
				name_str = (prof as PlayerProfile).player_name
		if name_str == token_id and td != null and not td.statblock_refs.is_empty() and reg.statblock != null:
			var sb: StatblockData = reg.statblock.get_statblock(str(td.statblock_refs[0]))
			if sb != null and not sb.name.is_empty():
				name_str = sb.name
	_set_status("Round %d — %s's turn" % [round_number, name_str])
	# Broadcast to player displays (with resolved name so PlayerWindow can display it).
	_nm_broadcast_to_displays({"msg": "combat_turn_update",
		"current_token_id": token_id, "round_number": round_number,
		"token_name": name_str})


func _on_combat_hp_changed(token_id: String, current_hp: int, max_hp: int, _delta: int) -> void:
	_refresh_initiative_panel()
	# Update the token sprite HP bar.
	if _map_view != null:
		var sprite: Node = _map_view.get_token_sprite(token_id)
		if sprite != null and sprite.has_method("set_hp_bar"):
			var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			var temp_hp: int = 0
			if reg != null and reg.combat != null:
				var status: Dictionary = reg.combat.get_hp_status(token_id)
				temp_hp = int(status.get("temp", 0))
			sprite.set_hp_bar(current_hp, max_hp, temp_hp)
	# Broadcast HP update to player displays.
	_nm_broadcast_to_displays({"msg": "combat_hp_update",
		"token_id": token_id, "current_hp": current_hp, "max_hp": max_hp})


func _on_combat_token_killed(token_id: String) -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var name_str: String = token_id
	var monster_cr: float = 0.0
	var monster_xp: int = 0
	if reg != null and reg.token != null:
		var td: TokenData = reg.token.get_token_by_id(token_id)
		if td != null and not td.label.is_empty():
			name_str = td.label
		# Look up monster CR for XP awarding.
		if td != null and td.category == TokenData.TokenCategory.MONSTER and not td.statblock_refs.is_empty():
			var sb_id: String = str(td.statblock_refs[0])
			if reg.statblock != null and not sb_id.is_empty():
				var sb: StatblockData = reg.statblock.get_statblock(sb_id)
				if sb != null:
					monster_cr = sb.challenge_rating
					monster_xp = sb.xp if sb.xp > 0 else WizardConstants.cr_to_xp(monster_cr)
	_set_status("%s killed!" % name_str)
	_refresh_initiative_panel()

	# Award XP if campaign is in XP mode.
	if monster_xp > 0 and reg != null and reg.campaign != null:
		var mode: String = str(reg.campaign.get_setting("advancement_mode"))
		if mode == "xp":
			_award_xp_to_party(monster_xp, name_str)


func _on_combat_log_entry_added(entry: Dictionary) -> void:
	if _combat_log_panel == null or not _combat_log_panel.visible:
		return
	_combat_log_panel.append_entry(entry)


func _award_xp_to_party(total_xp: int, source_name: String) -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.campaign == null or reg.character == null:
		return
	var char_ids: Array = reg.campaign.get_character_ids()
	if char_ids.is_empty():
		return
	var pc_count: int = char_ids.size()
	var xp_each: int = maxi(1, int(float(total_xp) / float(pc_count)))
	var leveled: Array = []
	for cid: Variant in char_ids:
		var sb: StatblockData = reg.character.get_character_by_id(str(cid))
		if sb == null:
			continue
		var old_level: int = sb.get_total_level()
		sb.current_xp += xp_each
		var new_level: int = WizardConstants.level_for_xp(sb.current_xp)
		reg.character.add_character(sb)
		if reg.statblock != null:
			reg.statblock.update_statblock(sb)
		if new_level > old_level:
			leveled.append(sb.name)
	var msg: String = "XP: %d from %s (%d each to %d PCs)." % [
		total_xp, source_name, xp_each, pc_count]
	if not leveled.is_empty():
		msg += " Ready to level up: %s" % ", ".join(leveled)
	_set_status(msg)


func _on_condition_applied(token_id: String, _condition: Dictionary) -> void:
	_refresh_initiative_panel()
	_refresh_token_sprite_conditions(token_id)


func _on_condition_removed(token_id: String, _condition: Dictionary) -> void:
	_refresh_initiative_panel()
	_refresh_token_sprite_conditions(token_id)
	# If the condition dialog is open for this token, refresh its list.
	if _condition_dialog != null and _condition_dialog.visible and \
			_condition_dialog._token_id == token_id:
		_open_condition_dialog(token_id)


## Update the condition badges on the map sprite for a token.
func _refresh_token_sprite_conditions(token_id: String) -> void:
	if _map_view == null:
		return
	var sprite: Node = _map_view.get_token_sprite(token_id)
	if sprite == null or not sprite.has_method("set_conditions"):
		return
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.combat == null:
		return
	# Pass condition name strings so TokenSprite can look up abbrev/colour.
	var names: Array = []
	for cond: Variant in reg.combat.get_conditions(token_id):
		if cond is Dictionary:
			var n: String = str((cond as Dictionary).get("name", ""))
			if not n.is_empty():
				names.append(n)
		elif cond is String:
			names.append(cond as String)
	sprite.set_conditions(names)


## Open (or reopen) the condition dialog for a token.
func _open_condition_dialog(token_id: String) -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.combat == null:
		return
	if _condition_dialog == null:
		_condition_dialog = ConditionDialog.new()
		add_child(_condition_dialog)
		_condition_dialog.condition_confirmed.connect(_on_condition_confirmed)
		_condition_dialog.condition_removed_requested.connect(
			_on_condition_remove_requested)
		var reg_tm := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg_tm != null and reg_tm.ui_theme != null:
			reg_tm.ui_theme.theme_control_tree(_condition_dialog, _ui_scale())
		_condition_dialog.apply_scale(_ui_scale())
	var token_name: String = token_id
	if reg.token != null:
		var td: TokenData = reg.token.get_token_by_id(token_id)
		if td != null and not td.label.is_empty():
			token_name = td.label
	var current_conds: Array = reg.combat.get_conditions(token_id)
	_condition_dialog.open_for_token(token_id, token_name, current_conds)


func _on_condition_confirmed(token_id: String, condition_name: String,
		source: String, duration_rounds: int, exhaustion_level: int) -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.combat == null:
		return
	if condition_name == "exhaustion" and exhaustion_level > 0:
		reg.combat.set_exhaustion_level(token_id, exhaustion_level)
	else:
		reg.combat.apply_condition(token_id, condition_name, source, duration_rounds)
	# Refresh the dialog's active list immediately.
	_open_condition_dialog(token_id)


func _on_condition_remove_requested(token_id: String, condition_name: String) -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.combat == null:
		return
	reg.combat.remove_condition(token_id, condition_name)


func _on_initiative_damage_requested(token_id: String) -> void:
	_open_quick_damage_dialog(token_id, false)


func _on_initiative_heal_requested(token_id: String) -> void:
	_open_quick_damage_dialog(token_id, true)


func _open_quick_damage_dialog(token_id: String, is_healing: bool) -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _quick_damage_dialog == null:
		_quick_damage_dialog = QuickDamageDialog.new()
		add_child(_quick_damage_dialog)
		_quick_damage_dialog.applied.connect(_on_quick_damage_applied)
		if reg != null and reg.ui_theme != null:
			reg.ui_theme.theme_control_tree(_quick_damage_dialog, _ui_scale())
		_quick_damage_dialog.apply_scale(_ui_scale())
	var token_name: String = token_id
	if reg != null and reg.token != null:
		var td: TokenData = reg.token.get_token_by_id(token_id)
		if td != null and not td.label.is_empty():
			token_name = td.label
	if is_healing:
		_quick_damage_dialog.open_healing(token_id, token_name)
	else:
		_quick_damage_dialog.open_damage(token_id, token_name)


func _on_quick_damage_applied(token_id: String, amount: int, damage_type: String,
		mode: QuickDamageDialog.HpMode) -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.combat == null:
		return
	match mode:
		QuickDamageDialog.HpMode.HEAL:
			var result: Dictionary = reg.combat.apply_healing(token_id, amount)
			var actual: int = int(result.get("actual_healing", 0))
			_set_status("Healed %d HP" % actual)
		QuickDamageDialog.HpMode.TEMP_HP:
			reg.combat.apply_temp_hp(token_id, amount)
			_set_status("Set %d temp HP" % amount)
		_: # DAMAGE
			var result: Dictionary = reg.combat.apply_damage(token_id, amount, damage_type)
			var actual: int = int(result.get("actual_damage", 0))
			var detail: String = str(result.get("detail", ""))
			var killed: bool = bool(result.get("killed", false))
			var msg: String = "Dealt %d damage" % actual
			if not detail.is_empty():
				msg += " (%s)" % detail
			if killed:
				msg += " \u2014 KILLED"
			_set_status(msg)


# ---------------------------------------------------------------------------
# Passage paint panel — build, signals, handlers
# ---------------------------------------------------------------------------

func _build_passage_panel() -> void:
	# Anchored directly in _ui_content_area (same as _freeze_panel) so _ui_root.scale
	# does not push it off-screen on HiDPI / Retina displays.
	var s := _ui_scale()
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
	_passage_panel.offset_top = roundi(-44.0 * s)
	_passage_panel.offset_bottom = 0.0
	_ui_content_area.add_child(_passage_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", roundi(8.0 * s))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", roundi(6.0 * s))
	margin.add_theme_constant_override("margin_right", roundi(6.0 * s))
	margin.add_theme_constant_override("margin_top", roundi(4.0 * s))
	margin.add_theme_constant_override("margin_bottom", roundi(4.0 * s))
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
	_passage_brush_slider.custom_minimum_size = Vector2(roundi(120.0 * s), 0.0)
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


func _build_roam_panel() -> void:
	# Bottom-bar panel for roam-path editing, parallel to `_build_passage_panel`.
	var s := _ui_scale()
	_roam_panel = PanelContainer.new()
	_roam_panel.name = "RoamPanel"
	_roam_panel.visible = false
	_roam_panel.anchor_left = 0.0
	_roam_panel.anchor_right = 1.0
	_roam_panel.anchor_top = 1.0
	_roam_panel.anchor_bottom = 1.0
	_roam_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_roam_panel.offset_left = 0.0
	_roam_panel.offset_right = 0.0
	_roam_panel.offset_top = roundi(-44.0 * s)
	_roam_panel.offset_bottom = 0.0
	_ui_content_area.add_child(_roam_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", roundi(8.0 * s))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", roundi(6.0 * s))
	margin.add_theme_constant_override("margin_right", roundi(6.0 * s))
	margin.add_theme_constant_override("margin_top", roundi(4.0 * s))
	margin.add_theme_constant_override("margin_bottom", roundi(4.0 * s))
	margin.add_child(hbox)
	_roam_panel.add_child(margin)

	var icon_label := Label.new()
	icon_label.text = "🐾"
	hbox.add_child(icon_label)

	_roam_token_label = Label.new()
	_roam_token_label.text = "Roam Path"
	hbox.add_child(_roam_token_label)

	var mode_label := Label.new()
	mode_label.text = "Mode:"
	hbox.add_child(mode_label)

	_roam_mode_option = OptionButton.new()
	_roam_mode_option.add_item("Off", 0)
	_roam_mode_option.add_item("Freehand", 1)
	_roam_mode_option.add_item("Polyline", 2)
	_roam_mode_option.add_item("Erase", 3)
	_roam_mode_option.selected = 0
	_roam_mode_option.focus_mode = Control.FOCUS_NONE
	_roam_mode_option.item_selected.connect(_on_roam_mode_selected)
	hbox.add_child(_roam_mode_option)

	_roam_loop_check = CheckBox.new()
	_roam_loop_check.text = "Loop"
	_roam_loop_check.button_pressed = true
	_roam_loop_check.focus_mode = Control.FOCUS_NONE
	_roam_loop_check.tooltip_text = "Loop: return to start.  Uncheck for ping-pong."
	_roam_loop_check.toggled.connect(_on_roam_loop_toggled)
	hbox.add_child(_roam_loop_check)

	var speed_label := Label.new()
	speed_label.text = "Speed:"
	hbox.add_child(speed_label)

	_roam_speed_slider = HSlider.new()
	_roam_speed_slider.min_value = 5.0
	_roam_speed_slider.max_value = 120.0
	_roam_speed_slider.step = 5.0
	_roam_speed_slider.value = 30.0
	_roam_speed_slider.custom_minimum_size = Vector2(roundi(100.0 * s), 0.0)
	_roam_speed_slider.focus_mode = Control.FOCUS_NONE
	_roam_speed_slider.value_changed.connect(_on_roam_speed_changed)
	hbox.add_child(_roam_speed_slider)

	_roam_speed_value_label = Label.new()
	_roam_speed_value_label.text = "30 ft/rd"
	_roam_speed_value_label.custom_minimum_size = Vector2(roundi(60.0 * s), 0.0)
	hbox.add_child(_roam_speed_value_label)

	_roam_smooth_btn = Button.new()
	_roam_smooth_btn.text = "⌇"
	_roam_smooth_btn.focus_mode = Control.FOCUS_NONE
	_roam_smooth_btn.tooltip_text = "Smooth path (Chaikin corner-cutting)"
	_roam_smooth_btn.pressed.connect(_on_roam_smooth_pressed)
	hbox.add_child(_roam_smooth_btn)

	_roam_play_btn = Button.new()
	_roam_play_btn.text = "▶"
	_roam_play_btn.focus_mode = Control.FOCUS_NONE
	_roam_play_btn.tooltip_text = "Play / pause roam animation"
	_roam_play_btn.pressed.connect(_on_roam_play_pressed)
	hbox.add_child(_roam_play_btn)

	_roam_reset_btn = Button.new()
	_roam_reset_btn.text = "↺"
	_roam_reset_btn.focus_mode = Control.FOCUS_NONE
	_roam_reset_btn.tooltip_text = "Reset token to path start"
	_roam_reset_btn.pressed.connect(_on_roam_reset_pressed)
	hbox.add_child(_roam_reset_btn)

	_roam_commit_btn = Button.new()
	_roam_commit_btn.text = "Commit"
	_roam_commit_btn.focus_mode = Control.FOCUS_NONE
	_roam_commit_btn.tooltip_text = "Save roam path to this token"
	_roam_commit_btn.pressed.connect(_on_roam_commit_pressed)
	hbox.add_child(_roam_commit_btn)

	_roam_clear_btn = Button.new()
	_roam_clear_btn.text = "Clear"
	_roam_clear_btn.focus_mode = Control.FOCUS_NONE
	_roam_clear_btn.tooltip_text = "Erase the WIP roam path"
	_roam_clear_btn.pressed.connect(_on_roam_clear_pressed)
	hbox.add_child(_roam_clear_btn)


func _build_multi_select_bar() -> void:
	var s := _ui_scale()
	_multi_select_bar = PanelContainer.new()
	_multi_select_bar.name = "MultiSelectBar"
	_multi_select_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	# Anchor bottom-center.
	_multi_select_bar.anchor_left = 0.5
	_multi_select_bar.anchor_right = 0.5
	_multi_select_bar.anchor_top = 1.0
	_multi_select_bar.anchor_bottom = 1.0
	_multi_select_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_multi_select_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_multi_select_bar.offset_top = roundi(-50.0 * s)
	_multi_select_bar.offset_bottom = roundi(-8.0 * s)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.14, 0.92)
	bg.set_corner_radius_all(roundi(8.0 * s))
	bg.content_margin_left = roundi(12.0 * s)
	bg.content_margin_right = roundi(12.0 * s)
	bg.content_margin_top = roundi(6.0 * s)
	bg.content_margin_bottom = roundi(6.0 * s)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.35, 0.55, 1.0, 0.5)
	_multi_select_bar.add_theme_stylebox_override("panel", bg)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(10.0 * s))
	_multi_select_bar.add_child(row)

	_multi_select_label = Label.new()
	row.add_child(_multi_select_label)

	var combat_btn := Button.new()
	combat_btn.text = "Start Combat"
	combat_btn.focus_mode = Control.FOCUS_NONE
	combat_btn.pressed.connect(_on_multi_select_start_combat)
	row.add_child(combat_btn)
	_multi_select_combat_btn = combat_btn

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_on_multi_select_clear)
	row.add_child(clear_btn)

	_multi_select_bar.visible = false
	_ui_content_area.add_child(_multi_select_bar)


func _update_multi_select_bar(selected_ids: Array) -> void:
	if _multi_select_bar == null:
		return
	var count: int = selected_ids.size()
	if count < 2:
		_multi_select_bar.visible = false
		return
	_multi_select_label.text = "%d tokens selected" % count
	# Update combat button label based on whether combat is already active.
	if _multi_select_combat_btn != null:
		var reg_msb := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		var in_combat: bool = reg_msb != null and reg_msb.combat != null and reg_msb.combat.is_in_combat()
		_multi_select_combat_btn.text = "Add to Combat" if in_combat else "Start Combat"
	_multi_select_bar.visible = true


func _on_multi_select_start_combat() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.selection == null or reg.combat == null:
		return
	var ids: Array[String] = reg.selection.get_selected_ids()
	if reg.combat.is_in_combat():
		# Add selected tokens to an existing combat.
		for tid: String in ids:
			reg.combat.add_combatant(tid)
	else:
		if ids.is_empty():
			return
		reg.combat.start_combat(ids)
		# _on_combat_started fires via signal, but call directly in case the
		# panel was deferred-hidden and the signal fires before layout settles.
		_ensure_initiative_panel_visible()


func _on_multi_select_clear() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.selection == null:
		return
	reg.selection.clear_selection()


func _on_token_selected(token_id: String) -> void:
	## Show the passage paint panel when a SECRET_PASSAGE token is selected,
	## or the roam panel when a MONSTER / NPC token is selected.
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(token_id)
	if data == null:
		_hide_passage_panel()
		_hide_roam_panel()
		return
	# Mutually exclusive panels: passage vs roam.
	if data.category == TokenData.TokenCategory.SECRET_PASSAGE:
		_hide_roam_panel()
		_selected_passage_token_id = token_id
		if _passage_panel != null:
			_passage_panel.visible = true
			_passage_token_label.text = "Passage: %s" % data.label if not data.label.is_empty() else "Secret Passage"
		if _passage_mode_option != null:
			_passage_mode_option.selected = 0
	elif data.category == TokenData.TokenCategory.MONSTER or data.category == TokenData.TokenCategory.NPC:
		_hide_passage_panel()
		_show_roam_panel(token_id, data)
	else:
		_hide_passage_panel()
		_hide_roam_panel()
	# Mirror selection to the initiative panel so the matching row highlights.
	if _initiative_panel != null:
		_initiative_panel.set_selected_token(token_id)


func _on_selection_changed(selected_ids: Array) -> void:
	var count: int = selected_ids.size()
	if count == 0:
		_set_status("Selection cleared")
		# Clear map-selection highlight in the initiative panel.
		if _initiative_panel != null:
			_initiative_panel.set_selected_token("")
		# Hide context-sensitive panels that were open for the deselected token.
		_hide_passage_panel()
		_hide_roam_panel()
	elif count == 1:
		var tid: String = str(selected_ids[0])
		# Mirror single-token selection to initiative panel highlight.
		if _initiative_panel != null:
			_initiative_panel.set_selected_token(tid)
		var tm := _token_manager()
		if tm != null:
			var data: TokenData = tm.get_token_by_id(tid)
			if data != null:
				_set_status("Selected: %s" % (data.label if not data.label.is_empty() else tid))
				_update_multi_select_bar(selected_ids)
				return
		_set_status("Selected: %s" % tid)
	else:
		# Multi-select: clear the single-token initiative highlight.
		if _initiative_panel != null:
			_initiative_panel.set_selected_token("")
		_set_status("Selected: %d tokens" % count)
	_update_multi_select_bar(selected_ids)


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
# Roam path panel — show / hide / handlers
# ---------------------------------------------------------------------------

func _show_roam_panel(token_id: String, data: TokenData) -> void:
	_selected_roam_token_id = token_id
	if _roam_panel == null:
		return
	_roam_panel.visible = true
	var lbl: String = data.label if not data.label.is_empty() else "Token"
	_roam_token_label.text = "Roam: %s" % lbl
	if _roam_loop_check != null:
		_roam_loop_check.set_pressed_no_signal(data.roam_loop)
	if _roam_speed_slider != null:
		_roam_speed_slider.set_value_no_signal(data.roam_speed)
	if _roam_speed_value_label != null:
		_roam_speed_value_label.text = "%d ft/rd" % int(data.roam_speed)
	if _roam_mode_option != null:
		_roam_mode_option.selected = 0
	if _roam_play_btn != null:
		_roam_play_btn.text = "⏸" if _is_roam_playing(token_id) else "▶"


func _hide_roam_panel() -> void:
	if _map_view != null and _map_view._roam_tool != MapView.RoamTool.NONE:
		_map_view.deactivate_roam_tool()
	_selected_roam_token_id = ""
	if _roam_panel != null:
		_roam_panel.visible = false
	if _roam_mode_option != null:
		_roam_mode_option.selected = 0


func _on_roam_mode_selected(index: int) -> void:
	if _map_view == null or _selected_roam_token_id.is_empty():
		return
	var mode: int = _roam_mode_option.get_item_id(index)
	if mode == 0: # Off
		if _map_view._roam_tool != MapView.RoamTool.NONE:
			_map_view.deactivate_roam_tool()
		return
	var tm := _token_manager()
	if tm == null:
		return
	var loop_val: bool = _roam_loop_check.button_pressed if _roam_loop_check != null else true
	if _map_view._active_roam_token_id != _selected_roam_token_id:
		var data: TokenData = tm.get_token_by_id(_selected_roam_token_id)
		var initial_path: PackedVector2Array = data.roam_path if data != null else PackedVector2Array()
		_map_view.activate_roam_tool(_selected_roam_token_id, initial_path, loop_val)
	_map_view.set_roam_tool(mode)


func _on_roam_loop_toggled(pressed: bool) -> void:
	if _map_view != null and _map_view._active_roam_token_id != "":
		_map_view.set_roam_loop(pressed)


func _on_roam_speed_changed(value: float) -> void:
	if _roam_speed_value_label != null:
		_roam_speed_value_label.text = "%d ft/rd" % int(value)
	# Apply immediately so a running animation picks up the new speed.
	if _selected_roam_token_id.is_empty():
		return
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(_selected_roam_token_id)
	if data != null:
		data.roam_speed = value


func _on_roam_smooth_pressed() -> void:
	if _map_view != null and _map_view._active_roam_token_id != "":
		_map_view.smooth_roam_path()


func _on_roam_play_pressed() -> void:
	if _selected_roam_token_id.is_empty():
		return
	if _is_roam_playing(_selected_roam_token_id):
		_pause_roam(_selected_roam_token_id)
	else:
		_start_roam(_selected_roam_token_id)


func _on_roam_reset_pressed() -> void:
	if _selected_roam_token_id.is_empty():
		return
	_reset_roam(_selected_roam_token_id)


func _on_roam_commit_pressed() -> void:
	if _map_view != null:
		_map_view.deactivate_roam_tool()
	if _roam_mode_option != null:
		_roam_mode_option.selected = 0


func _on_roam_clear_pressed() -> void:
	if _map_view != null:
		_map_view.clear_roam_wip()
	if _selected_roam_token_id.is_empty():
		return
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(_selected_roam_token_id)
	if data == null:
		return
	data.roam_path = PackedVector2Array()
	data.roam_speed = _roam_speed_slider.value if _roam_speed_slider != null else 30.0
	data.roam_loop = _roam_loop_check.button_pressed if _roam_loop_check != null else true
	tm.update_token(data)
	_player_state_dirty = true
	if _map_view != null:
		_map_view.update_token_sprite(data)
	_broadcast_token_change(data, false)
	_set_status("Roam path cleared")


func _on_roam_path_committed(token_id: String, path: PackedVector2Array, loop: bool) -> void:
	_player_state_dirty = true
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(token_id)
	if data == null:
		return
	var old_path := data.roam_path.duplicate()
	var old_speed := data.roam_speed
	var old_loop := data.roam_loop
	var speed_val: float = _roam_speed_slider.value if _roam_speed_slider != null else 30.0
	data.roam_path = path
	data.roam_speed = speed_val
	data.roam_loop = loop
	tm.update_token(data)
	if _map_view != null:
		_map_view.update_token_sprite(data)
	var registry_r := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry_r != null and registry_r.history != null:
		var new_path := path.duplicate()
		var new_speed := speed_val
		var new_loop := loop
		var mv := _map_view
		registry_r.history.push_command(HistoryCommand.create("Roam path edited",
			func():
				var td: TokenData = tm.get_token_by_id(token_id)
				if td == null: return
				td.roam_path = old_path.duplicate()
				td.roam_speed = old_speed
				td.roam_loop = old_loop
				tm.update_token(td)
				if mv != null: mv.update_token_sprite(td)
				_broadcast_token_change(td, false),
			func():
				var td: TokenData = tm.get_token_by_id(token_id)
				if td == null: return
				td.roam_path = new_path.duplicate()
				td.roam_speed = new_speed
				td.roam_loop = new_loop
				tm.update_token(td)
				if mv != null: mv.update_token_sprite(td)
				_broadcast_token_change(td, false)))
	_broadcast_token_change(data, false)
	_hide_roam_panel()
	_set_status("Roam path saved")


# ---------------------------------------------------------------------------
# Roam animation engine
# ---------------------------------------------------------------------------

func _tick_roam_animations(delta: float) -> void:
	if _roaming_tokens.is_empty():
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null or registry.movement == null:
		return
	var map: MapData = _map()
	if map == null:
		return
	var ids_to_remove: Array = []
	for tid in _roaming_tokens.keys():
		var state: Dictionary = _roaming_tokens[tid] as Dictionary
		var playing: bool = state.get("playing", false) as bool
		if not playing:
			continue
		# Skip tokens currently being dragged.
		if _drag_start_positions.has(str(tid)):
			continue
		var data: TokenData = registry.token.get_token_by_id(str(tid))
		if data == null or data.roam_path.size() < 2:
			ids_to_remove.append(tid)
			continue
		var speed_px: float = registry.movement.get_roam_speed_px_per_sec(data, map)
		if speed_px <= 0.0:
			continue
		var total_len: float = _roam_path_total_length(data.roam_path, data.roam_loop)
		if total_len <= 0.0:
			continue
		var progress: float = state.get("progress", 0.0) as float
		var direction: int = state.get("direction", 1) as int
		progress += speed_px * delta * direction
		# Boundary handling
		if data.roam_loop:
			progress = fmod(progress, total_len)
			if progress < 0.0:
				progress += total_len
		else:
			# Ping-pong
			if progress >= total_len:
				progress = total_len
				direction = -1
			elif progress <= 0.0:
				progress = 0.0
				direction = 1
		state["progress"] = progress
		state["direction"] = direction
		var new_pos: Vector2 = _roam_position_at_progress(data.roam_path, progress, data.roam_loop)
		# Compute facing angle from movement direction, offset by icon's natural facing.
		var prev_pos: Vector2 = data.world_pos
		var move_dir: Vector2 = new_pos - prev_pos
		if move_dir.length_squared() > 0.01:
			data.rotation_deg = rad_to_deg(move_dir.angle()) - data.icon_facing_deg
		registry.token.move_token(str(tid), new_pos)
		if _map_view != null:
			_map_view.update_token_sprite(data)
		# Throttled broadcast to player displays
		var last_broadcast: float = state.get("last_broadcast", 0.0) as float
		last_broadcast += delta
		if last_broadcast >= _ROAM_BROADCAST_INTERVAL:
			last_broadcast = 0.0
			_nm_broadcast_to_displays({
				"msg": "token_moved",
				"token_id": str(tid),
				"world_pos": {"x": new_pos.x, "y": new_pos.y},
				"rotation_deg": data.rotation_deg,
			})
		state["last_broadcast"] = last_broadcast
	for tid in ids_to_remove:
		_roaming_tokens.erase(tid)


func _roam_path_total_length(path: PackedVector2Array, loop: bool) -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	if loop and path.size() >= 2:
		total += path[path.size() - 1].distance_to(path[0])
	return total


func _roam_position_at_progress(path: PackedVector2Array, progress: float, loop: bool) -> Vector2:
	if path.size() == 0:
		return Vector2.ZERO
	if path.size() == 1:
		return path[0]
	var remaining: float = progress
	var seg_count: int = path.size() - 1
	if loop:
		seg_count = path.size()
	for i: int in range(seg_count):
		var a: Vector2 = path[i]
		var b: Vector2 = path[(i + 1) % path.size()]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.0:
			continue
		if remaining <= seg_len:
			return a.lerp(b, remaining / seg_len)
		remaining -= seg_len
	# Clamp to end
	if loop:
		return path[0]
	return path[path.size() - 1]


func _roam_snap_progress(path: PackedVector2Array, pos: Vector2, loop: bool) -> float:
	## Find the progress value closest to the given world position.
	var best_progress: float = 0.0
	var best_dist_sq: float = INF
	var cumulative: float = 0.0
	var seg_count: int = path.size() - 1
	if loop:
		seg_count = path.size()
	for i: int in range(seg_count):
		var a: Vector2 = path[i]
		var b: Vector2 = path[(i + 1) % path.size()]
		var seg_len: float = a.distance_to(b)
		if seg_len <= 0.0:
			continue
		var ab: Vector2 = b - a
		var t: float = clampf(ab.dot(pos - a) / ab.dot(ab), 0.0, 1.0)
		var proj: Vector2 = a + ab * t
		var d_sq: float = pos.distance_squared_to(proj)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_progress = cumulative + seg_len * t
		cumulative += seg_len
	return best_progress


func _start_roam(token_id: String) -> void:
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(token_id)
	if data == null or data.roam_path.size() < 2:
		return
	var state: Dictionary = _roaming_tokens.get(token_id, {}) as Dictionary
	if state.is_empty():
		# Fresh start — snap progress to current token position.
		var p: float = _roam_snap_progress(data.roam_path, data.world_pos, data.roam_loop)
		state = {"progress": p, "direction": 1, "playing": true, "last_broadcast": 0.0}
	else:
		state["playing"] = true
	_roaming_tokens[token_id] = state
	if _roam_play_btn != null:
		_roam_play_btn.text = "⏸"


func _pause_roam(token_id: String) -> void:
	if _roaming_tokens.has(token_id):
		var state: Dictionary = _roaming_tokens[token_id] as Dictionary
		state["playing"] = false
	if _roam_play_btn != null:
		_roam_play_btn.text = "▶"


func _reset_roam(token_id: String) -> void:
	_pause_roam(token_id)
	_roaming_tokens.erase(token_id)
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(token_id)
	if data == null or data.roam_path.is_empty():
		return
	var start_pos: Vector2 = data.roam_path[0]
	tm.move_token(token_id, start_pos)
	if _map_view != null:
		_map_view.update_token_sprite(data)
	_nm_broadcast_to_displays({
		"msg": "token_moved",
		"token_id": token_id,
		"world_pos": {"x": start_pos.x, "y": start_pos.y},
	})


func _is_roam_playing(token_id: String) -> bool:
	if not _roaming_tokens.has(token_id):
		return false
	var state: Dictionary = _roaming_tokens[token_id] as Dictionary
	return state.get("playing", false) as bool


func _snap_token_to_roam_path(token_id: String) -> void:
	## Move the token to the nearest point on its roam path.
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(token_id)
	if data == null or data.roam_path.size() < 2:
		return
	var old_pos: Vector2 = data.world_pos
	var snap_progress: float = _roam_snap_progress(data.roam_path, old_pos, data.roam_loop)
	var snap_pos: Vector2 = _roam_position_at_progress(data.roam_path, snap_progress, data.roam_loop)
	if old_pos.distance_squared_to(snap_pos) < 0.5:
		return
	tm.move_token(token_id, snap_pos)
	if _map_view != null:
		_map_view.update_token_sprite(data)
	# Update roam animation progress to match the snapped position.
	if _roaming_tokens.has(token_id):
		var rs: Dictionary = _roaming_tokens[token_id] as Dictionary
		rs["progress"] = snap_progress
	# Undo support.
	var registry_snap := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry_snap != null and registry_snap.history != null:
		var mv := _map_view
		registry_snap.history.push_command(HistoryCommand.create("Snap to path",
			func() -> void:
				var td: TokenData = tm.get_token_by_id(token_id)
				if td == null: return
				tm.move_token(token_id, old_pos)
				if mv != null: mv.update_token_sprite(td),
			func() -> void:
				var td: TokenData = tm.get_token_by_id(token_id)
				if td == null: return
				tm.move_token(token_id, snap_pos)
				if mv != null: mv.update_token_sprite(td)))
	_nm_broadcast_to_displays({
		"msg": "token_moved",
		"token_id": token_id,
		"world_pos": {"x": snap_pos.x, "y": snap_pos.y},
	})
	_player_state_dirty = true


# ---------------------------------------------------------------------------
# Token clipboard — copy / cut / paste
# ---------------------------------------------------------------------------

func _copy_token(token_id: String) -> void:
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(token_id)
	if data == null:
		return
	_token_clipboard = data.to_dict()
	_set_status("Copied: %s" % data.label if not data.label.is_empty() else "Copied token")


func _cut_token(token_id: String) -> void:
	var tm := _token_manager()
	if tm == null:
		return
	var data: TokenData = tm.get_token_by_id(token_id)
	if data == null:
		return
	_copy_token(token_id)
	_delete_token(token_id)
	_set_status("Cut: %s" % data.label if not data.label.is_empty() else "Cut token")


func _paste_token(world_pos: Vector2) -> void:
	if _token_clipboard.is_empty():
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var tm: TokenManager = registry.token
	var data: TokenData = TokenData.from_dict(_token_clipboard)
	var old_world_pos: Vector2 = data.world_pos
	data.id = TokenData.generate_id()
	data.world_pos = world_pos
	# Strip any trailing " N" suffix from the clipboard label so that
	# _ensure_unique_combatant_names can renumber cleanly when added to combat.
	var paste_label: String = data.label
	var _pi: int = paste_label.rfind(" ")
	if _pi != -1 and paste_label.substr(_pi + 1).is_valid_int():
		paste_label = paste_label.left(_pi)
	data.label = paste_label
	# Offset passage paths relative to the position delta.
	if not data.passage_paths.is_empty():
		var delta: Vector2 = world_pos - old_world_pos
		var shifted: Array = []
		for raw: Variant in data.passage_paths:
			if raw is PackedVector2Array:
				var chain := raw as PackedVector2Array
				var new_chain := PackedVector2Array()
				for pt: Vector2 in chain:
					new_chain.append(pt + delta)
				shifted.append(new_chain)
		data.passage_paths = shifted
	# Offset roam path relative to the position delta.
	if not data.roam_path.is_empty():
		var roam_delta: Vector2 = world_pos - old_world_pos
		var shifted_roam := PackedVector2Array()
		for pt: Vector2 in data.roam_path:
			shifted_roam.append(pt + roam_delta)
		data.roam_path = shifted_roam
	tm.add_token(data)
	var mv := _map_view
	if mv != null:
		mv.add_token_sprite(data, true)
		mv.apply_token_passthrough_state(data)
	_broadcast_token_change(data, true)
	_broadcast_puzzle_notes_state()
	# Push undo command.
	if registry.history != null:
		var new_snapshot: TokenData = TokenData.from_dict(data.to_dict())
		var new_id: String = new_snapshot.id
		registry.history.push_command(HistoryCommand.create("Token pasted",
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
	_set_status("Pasted: %s" % data.label if not data.label.is_empty() else "Pasted token")


## Returns a label that does not collide with any existing token on the current map.
## Strips any trailing " N" suffix from base_label, then appends " 1", " 2" etc.
## as needed.  If base_label is empty the original is returned unchanged.
func _make_unique_token_label(base_label: String, tm: TokenManager) -> String:
	if base_label.is_empty():
		return base_label
	# Strip a trailing " <integer>" suffix (e.g. "Goblin 2" → "Goblin").
	var stripped: String = base_label
	var space_idx: int = base_label.rfind(" ")
	if space_idx != -1:
		var suffix: String = base_label.substr(space_idx + 1)
		if suffix.is_valid_int():
			stripped = base_label.left(space_idx)
	# Collect all existing token labels that share the same base name.
	var all_tokens: Array = tm.get_all_tokens()
	var existing_labels: Array = []
	for tok: Variant in all_tokens:
		if tok is TokenData:
			var lbl: String = (tok as TokenData).label
			if lbl == stripped or lbl.begins_with(stripped + " "):
				existing_labels.append(lbl)
	if existing_labels.is_empty():
		return base_label # No conflict — keep original (no number needed yet).
	# Find the lowest positive integer not already in use.
	var n: int = 1
	while existing_labels.has("%s %d" % [stripped, n]):
		n += 1
	return "%s %d" % [stripped, n]


func _delete_token(token_id: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var tm: TokenManager = registry.token
	var del_data: TokenData = tm.get_token_by_id(token_id)
	var del_snapshot: TokenData = null
	if del_data != null:
		del_snapshot = TokenData.from_dict(del_data.to_dict())
	# Capture combat state before removal so undo can restore it.
	var was_combatant: bool = false
	var saved_initiative: int = 0
	if registry.combat != null and registry.combat.is_in_combat():
		was_combatant = registry.combat.is_combatant(token_id)
		if was_combatant:
			for entry: Dictionary in registry.combat.get_initiative_order():
				if str(entry.get("token_id", "")) == token_id:
					saved_initiative = int(entry.get("initiative", 0))
					break
			registry.combat.remove_combatant(token_id)
	# Clean up the token icon file from the map bundle.
	if del_data != null and not del_data.icon_image_path.is_empty():
		_delete_token_icon(token_id)
	tm.remove_token(token_id)
	if _map_view != null:
		_map_view.remove_token_sprite(token_id)
	_nm_broadcast_to_displays({"msg": "token_removed", "token_id": token_id,
		"puzzle_notes": _collect_revealed_puzzle_notes()})
	_broadcast_puzzle_notes_state()
	if del_snapshot != null and registry.history != null:
		var cid: String = token_id
		var mv := _map_view
		registry.history.push_command(HistoryCommand.create("Token deleted",
			func():
				var restored := TokenData.from_dict(del_snapshot.to_dict())
				registry.token.add_token(restored)
				if mv != null: mv.add_token_sprite(restored, true); mv.apply_token_passthrough_state(restored)
				_broadcast_token_change(restored, true)
				_broadcast_puzzle_notes_state()
				if was_combatant and registry.combat != null and registry.combat.is_in_combat():
					registry.combat.add_combatant(cid)
					registry.combat.set_initiative(cid, saved_initiative),
			func():
				if registry.combat != null and registry.combat.is_combatant(cid):
					registry.combat.remove_combatant(cid)
				registry.token.remove_token(cid)
				if mv != null: mv.remove_token_sprite(cid)
				_nm_broadcast_to_displays({"msg": "token_removed", "token_id": cid,
					"puzzle_notes": _collect_revealed_puzzle_notes()})
				_broadcast_puzzle_notes_state()))


# ---------------------------------------------------------------------------
# Token placement / editing
# ---------------------------------------------------------------------------

func _on_token_place_requested(world_pos: Vector2) -> void:
	## Left-click in PLACE_TOKEN tool mode — open editor for a brand-new token.
	_token_editor_id = ""
	_open_token_editor(TokenData.create(TokenData.TokenCategory.GENERIC, world_pos))


func _on_background_right_clicked(world_pos: Vector2, screen_pos: Vector2) -> void:
	## Right-click on empty map space — show background context menu.
	_background_right_click_pos = world_pos
	if _background_context_menu == null or not is_instance_valid(_background_context_menu):
		_background_context_menu = PopupMenu.new()
		_background_context_menu.id_pressed.connect(_on_background_context_menu_id)
		add_child(_background_context_menu)
	_apply_token_context_menu_theme_to(_background_context_menu)
	_background_context_menu.clear()
	# Check if right-click is on an active effect.
	var eff_id: String = _map_view.hit_test_effect(world_pos) if _map_view != null else ""
	if not eff_id.is_empty():
		_background_right_click_effect_id = eff_id
		_background_context_menu.add_item("Remove Effect", 1)
	if not _token_clipboard.is_empty():
		_background_context_menu.add_item("Paste Token", 0)
	# Selection quick-filters.
	var sel_registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if sel_registry != null and sel_registry.token != null:
		var has_monsters: bool = false
		var has_npcs: bool = false
		for td_raw: Variant in sel_registry.token.get_all_tokens():
			var td_item: TokenData = td_raw as TokenData
			if td_item == null:
				continue
			if td_item.category == TokenData.TokenCategory.MONSTER:
				has_monsters = true
			elif td_item.category == TokenData.TokenCategory.NPC:
				has_npcs = true
			if has_monsters and has_npcs:
				break
		if has_monsters or has_npcs:
			_background_context_menu.add_separator()
			if has_monsters:
				_background_context_menu.add_item("Select All Monsters", 10)
			if has_npcs:
				_background_context_menu.add_item("Select All NPCs", 11)
	if _background_context_menu.item_count == 0:
		return
	_background_context_menu.popup(Rect2i(int(screen_pos.x), int(screen_pos.y), 0, 0))


func _on_background_context_menu_id(id: int) -> void:
	match id:
		0: # Paste Token
			_paste_token(_background_right_click_pos)
		1: # Remove Effect
			if not _background_right_click_effect_id.is_empty():
				_delete_effect(_background_right_click_effect_id)
				_background_right_click_effect_id = ""
		10: # Select All Monsters
			_select_all_tokens_by_category(TokenData.TokenCategory.MONSTER)
		11: # Select All NPCs
			_select_all_tokens_by_category(TokenData.TokenCategory.NPC)


func _select_all_tokens_by_category(cat: int) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null or registry.selection == null:
		return
	var cat_name: String = TokenData.category_name(cat).to_lower()
	var ids: Array[String] = []
	for raw: Variant in registry.token.get_all_tokens():
		var td: TokenData = raw as TokenData
		if td != null and td.category == cat:
			ids.append(td.id)
	if ids.is_empty():
		_set_status("No %s tokens on the map" % cat_name)
		return
	registry.selection.select_many(ids, ISelectionService.SelectionLayer.TOKEN)
	_set_status("Selected %d %s token(s)" % [ids.size(), cat_name])


func _delete_effect(id: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	var existing: EffectData = registry.effect.get_by_id(id)
	if existing == null:
		return
	var snapshot: Dictionary = existing.to_dict()
	_effect_apply_remove(id)
	if registry.history != null:
		var cmd := HistoryCommand.create("Remove effect",
			func() -> void: _effect_apply_add(EffectData.from_dict(snapshot)),
			func() -> void: _effect_apply_remove(id))
		registry.history.push_command(cmd)


func _on_effect_delete_requested(id: String) -> void:
	_delete_effect(id)


func _on_effect_drag_completed(id: String, new_world_pos: Vector2) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	var existing: EffectData = registry.effect.get_by_id(id)
	if existing == null:
		return
	var old_pos: Vector2 = existing.world_pos
	existing.world_pos = new_world_pos
	_nm_broadcast_to_displays({"msg": "effect_spawn", "effect": existing.to_dict()})
	_mark_map_dirty_effects()
	if registry.history != null:
		var cmd := HistoryCommand.create("Move effect",
			func() -> void:
				var e: EffectData = registry.effect.get_by_id(id)
				if e != null:
					e.world_pos = old_pos
					if _map_view != null:
						_map_view.remove_effect_node(id)
						_map_view.add_effect_node(e)
					_nm_broadcast_to_displays({"msg": "effect_spawn", "effect": e.to_dict()})
					_mark_map_dirty_effects(),
			func() -> void:
				var e: EffectData = registry.effect.get_by_id(id)
				if e != null:
					e.world_pos = new_world_pos
					if _map_view != null:
						_map_view.remove_effect_node(id)
						_map_view.add_effect_node(e)
					_nm_broadcast_to_displays({"msg": "effect_spawn", "effect": e.to_dict()})
					_mark_map_dirty_effects())
		registry.history.push_command(cmd)


func _on_effect_resize_completed(id: String, new_size_px: float) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	var existing: EffectData = registry.effect.get_by_id(id)
	if existing == null:
		return
	var old_size: float = existing.size_px
	existing.size_px = new_size_px
	_nm_broadcast_to_displays({"msg": "effect_spawn", "effect": existing.to_dict()})
	_mark_map_dirty_effects()
	if registry.history != null:
		var cmd := HistoryCommand.create("Resize effect",
			func() -> void:
				var e: EffectData = registry.effect.get_by_id(id)
				if e != null:
					e.size_px = old_size
					if _map_view != null:
						_map_view.remove_effect_node(id)
						_map_view.add_effect_node(e)
					_nm_broadcast_to_displays({"msg": "effect_spawn", "effect": e.to_dict()})
					_mark_map_dirty_effects(),
			func() -> void:
				var e: EffectData = registry.effect.get_by_id(id)
				if e != null:
					e.size_px = new_size_px
					if _map_view != null:
						_map_view.remove_effect_node(id)
						_map_view.add_effect_node(e)
					_nm_broadcast_to_displays({"msg": "effect_spawn", "effect": e.to_dict()})
					_mark_map_dirty_effects())
		registry.history.push_command(cmd)


func _on_effect_burst_started(effect_type: int, world_pos: Vector2, size_px: float) -> void:
	var data: EffectData = EffectData.create(effect_type, world_pos, size_px, -1.0)
	data.id = "__burst__"
	data.shape = _effect_panel.get_selected_shape() if _effect_panel != null else 0
	data.palette = _effect_panel.get_selected_palette() if _effect_panel != null else 0
	_nm_broadcast_to_displays({"msg": "effect_spawn", "effect": data.to_dict()})


func _on_effect_burst_moved(world_pos: Vector2) -> void:
	_nm_broadcast_to_displays({"msg": "effect_burst_move", "x": world_pos.x, "y": world_pos.y})


func _on_effect_burst_ended() -> void:
	_nm_broadcast_to_displays({"msg": "effect_remove", "effect_id": "__burst__"})


func _on_measurement_right_clicked(meas_id: String, screen_pos: Vector2) -> void:
	_measurement_context_id = meas_id
	if _measurement_context_menu == null or not is_instance_valid(_measurement_context_menu):
		_measurement_context_menu = PopupMenu.new()
		_measurement_context_menu.id_pressed.connect(_on_measurement_context_menu_id)
		add_child(_measurement_context_menu)
	_apply_token_context_menu_theme_to(_measurement_context_menu)
	_measurement_context_menu.clear()
	_measurement_context_menu.add_item("Call for Saving Throw…", 0)
	_measurement_context_menu.popup(Rect2i(int(screen_pos.x), int(screen_pos.y), 0, 0))


func _on_measurement_context_menu_id(id: int) -> void:
	match id:
		0: # Call for Saving Throw
			var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if registry == null or registry.measurement == null:
				return
			var md: MeasurementData = registry.measurement.get_by_id(_measurement_context_id)
			if md == null:
				_set_status("Measurement shape not found.")
				return
			if _map_view == null:
				return
			var token_ids: Array[String] = _map_view.get_tokens_in_measurement(md)
			# Filter to creature tokens only.
			var tm := _token_manager()
			if tm != null:
				var filtered: Array[String] = []
				for tid: String in token_ids:
					var td: TokenData = tm.get_token_by_id(tid)
					if td != null and (td.category == TokenData.TokenCategory.MONSTER or td.category == TokenData.TokenCategory.NPC or td.category == TokenData.TokenCategory.GENERIC):
						filtered.append(tid)
				token_ids = filtered
			if token_ids.is_empty():
				_set_status("No creature tokens inside the measurement shape.")
				return
			_pending_save_measurement_id = md.id
			_open_save_config_dialog(token_ids)


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
	_token_context_menu.add_item("Copy Token", 4)
	_token_context_menu.add_item("Cut Token", 5)
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
	# Show roam play/pause/reset for MONSTER and NPC with a roam path.
	if td != null and (td.category == TokenData.TokenCategory.MONSTER or td.category == TokenData.TokenCategory.NPC) and td.roam_path.size() >= 2:
		_token_context_menu.add_separator()
		if _is_roam_playing(id):
			_token_context_menu.add_item("Pause Roam", 10)
		else:
			_token_context_menu.add_item("Play Roam", 10)
		_token_context_menu.add_item("Reset Roam", 11)
		_token_context_menu.add_item("Snap to Path", 12)
	# Show statblock shortcuts for MONSTER/NPC with attached statblocks.
	if td != null and td.statblock_refs.size() > 0:
		_token_context_menu.add_separator()
		_token_context_menu.add_item("View Statblock", 20)
		_token_context_menu.add_item("Quick HP…", 21)
		_token_context_menu.add_item("Edit Token Statblocks…", 22)
		_token_context_menu.add_item("Manage Inventory…", 23)
	# Show combat options when a map is loaded.
	var registry_cbt := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry_cbt != null and registry_cbt.combat != null and registry_cbt.combat.is_in_combat():
		_token_context_menu.add_separator()
		if registry_cbt.combat.is_combatant(id):
			_token_context_menu.add_item("Remove from Combat", 31)
		else:
			_token_context_menu.add_item("Add to Combat", 30)
		# Conditions option — only for combatants with statblocks.
		if registry_cbt.combat.is_combatant(id) and td != null and td.statblock_refs.size() > 0:
			_token_context_menu.add_item("Conditions…", 40)
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
			_delete_token(_token_context_id)
		3: # Toggle open/closed (DOOR / SECRET_PASSAGE)
			var data: TokenData = tm.get_token_by_id(_token_context_id)
			if data != null:
				data.blocks_los = not data.blocks_los
				tm.update_token(data)
				if _map_view != null:
					_map_view.apply_token_passthrough_state(data)
				_broadcast_token_change(data, false)
		4: # Copy Token
			_copy_token(_token_context_id)
		5: # Cut Token
			_cut_token(_token_context_id)
		10: # Play / Pause Roam
			if _is_roam_playing(_token_context_id):
				_pause_roam(_token_context_id)
			else:
				_start_roam(_token_context_id)
		11: # Reset Roam
			_reset_roam(_token_context_id)
		12: # Snap to Path
			_snap_token_to_roam_path(_token_context_id)
		20: # View Statblock (primary)
			var data: TokenData = tm.get_token_by_id(_token_context_id)
			if data != null and data.statblock_refs.size() > 0:
				_show_token_statblock_card(data, str(data.statblock_refs[0]))
		21: # Quick HP adjustment
			var data: TokenData = tm.get_token_by_id(_token_context_id)
			if data != null and data.statblock_refs.size() > 0:
				_show_quick_hp_dialog(data)
		22: # Edit Overrides (primary statblock)
			var data: TokenData = tm.get_token_by_id(_token_context_id)
			if data != null and data.statblock_refs.size() > 0:
				_show_override_editor_for_token(data, str(data.statblock_refs[0]))
		23: # Manage Inventory
			var data: TokenData = tm.get_token_by_id(_token_context_id)
			if data != null and data.statblock_refs.size() > 0:
				var sb_id: String = str(data.statblock_refs[0])
				var registry_inv := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
				var sb: StatblockData = registry_inv.statblock.get_statblock(sb_id) if (registry_inv != null and registry_inv.statblock != null) else null
				if sb != null:
					_open_char_sheet_for(sb)
					if _char_sheet != null:
						_char_sheet.select_inventory_tab()
		30: # Add to Combat
			var reg_cbt := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if reg_cbt != null and reg_cbt.combat != null:
				reg_cbt.combat.add_combatant(_token_context_id)
		31: # Remove from Combat
			var reg_cbt2 := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
			if reg_cbt2 != null and reg_cbt2.combat != null:
				reg_cbt2.combat.remove_combatant(_token_context_id)
		40: # Conditions…
			_open_condition_dialog(_token_context_id)


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
	if _token_size_ft_spin != null:
		_token_size_ft_spin.value = data.size_ft
	if _token_size_ft_row != null:
		var is_creature: bool = data.category == TokenData.TokenCategory.MONSTER or data.category == TokenData.TokenCategory.NPC
		_token_size_ft_row.visible = is_creature
	if _token_roam_info_row != null:
		var is_creature_r: bool = data.category == TokenData.TokenCategory.MONSTER or data.category == TokenData.TokenCategory.NPC
		_token_roam_info_row.visible = is_creature_r
	if _token_roam_info_label != null:
		if data.roam_path.size() >= 2:
			var mode_str: String = "loop" if data.roam_loop else "ping-pong"
			_token_roam_info_label.text = "%d pts, %d ft/rd (%s)" % [data.roam_path.size(), int(data.roam_speed), mode_str]
		else:
			_token_roam_info_label.text = "None"
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
	# Populate icon preview.
	_token_icon_pending_source = ""
	_token_icon_crop_offset = data.icon_crop_offset
	_token_icon_crop_zoom = data.icon_crop_zoom
	_token_icon_facing_deg = data.icon_facing_deg
	_token_icon_campaign_image_id = data.icon_campaign_image_id
	if _token_icon_preview != null:
		if not data.icon_image_path.is_empty():
			var tex: ImageTexture = TokenIconUtils.get_or_load_circular_texture(data.icon_image_path)
			_token_icon_preview.texture = tex
			if _token_icon_path_edit != null:
				_token_icon_path_edit.text = data.icon_image_path
		else:
			_token_icon_preview.texture = null
			if _token_icon_path_edit != null:
				_token_icon_path_edit.text = ""
	if _token_icon_crop_btn != null:
		_token_icon_crop_btn.disabled = data.icon_image_path.is_empty()
	# Populate puzzle notes rows.
	_populate_puzzle_note_rows(data.puzzle_notes)
	# Populate statblock references.
	_token_pending_statblock_refs = data.statblock_refs.duplicate()
	_token_pending_statblock_overrides = data.statblock_overrides.duplicate(true)
	_refresh_token_statblock_list()
	var is_creature_sb: bool = data.category == TokenData.TokenCategory.MONSTER or data.category == TokenData.TokenCategory.NPC
	if _token_statblocks_section != null:
		_token_statblocks_section.visible = is_creature_sb
	# Populate statblock visibility dropdown
	if _token_statblock_visibility_option != null:
		var vis_idx: int = 0
		match data.statblock_visibility:
			"name": vis_idx = 1
			"partial": vis_idx = 2
			"full": vis_idx = 3
		_token_statblock_visibility_option.selected = vis_idx
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

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_token_editor_dialog.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_token_editor_dialog_root = vbox
	scroll.add_child(vbox)

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

	# Icon Image
	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 6)
	var icon_label := Label.new()
	icon_label.text = "Icon Image:"
	icon_label.custom_minimum_size = Vector2(120, 0)
	icon_row.add_child(icon_label)
	_token_icon_preview = TextureRect.new()
	_token_icon_preview.custom_minimum_size = Vector2(48, 48)
	_token_icon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_token_icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_row.add_child(_token_icon_preview)
	_token_icon_choose_btn = Button.new()
	_token_icon_choose_btn.text = "Choose..."
	_token_icon_choose_btn.pressed.connect(_on_token_icon_choose_pressed)
	icon_row.add_child(_token_icon_choose_btn)
	_token_icon_clear_btn = Button.new()
	_token_icon_clear_btn.text = "Clear"
	_token_icon_clear_btn.pressed.connect(_on_token_icon_clear_pressed)
	icon_row.add_child(_token_icon_clear_btn)
	_token_icon_crop_btn = Button.new()
	_token_icon_crop_btn.text = "Edit Crop"
	_token_icon_crop_btn.disabled = true
	_token_icon_crop_btn.pressed.connect(_on_token_icon_crop_pressed)
	icon_row.add_child(_token_icon_crop_btn)
	var token_campaign_btn := Button.new()
	token_campaign_btn.text = "Campaign..."
	token_campaign_btn.tooltip_text = "Pick from campaign image library"
	token_campaign_btn.pressed.connect(_on_token_icon_campaign_pressed)
	icon_row.add_child(token_campaign_btn)
	vbox.add_child(icon_row)
	# Optional path / URL input row.
	var icon_path_row := HBoxContainer.new()
	icon_path_row.add_theme_constant_override("separation", 4)
	var ipr_spacer := Control.new()
	ipr_spacer.custom_minimum_size = Vector2(120, 0)
	icon_path_row.add_child(ipr_spacer)
	_token_icon_path_edit = LineEdit.new()
	_token_icon_path_edit.placeholder_text = "Or paste image path..."
	_token_icon_path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_path_row.add_child(_token_icon_path_edit)
	_token_icon_load_btn = Button.new()
	_token_icon_load_btn.text = "Load"
	_token_icon_load_btn.pressed.connect(_on_token_icon_load_pressed)
	icon_path_row.add_child(_token_icon_load_btn)
	vbox.add_child(icon_path_row)

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

	# Size (ft) — creature tokens (MONSTER / NPC)
	_token_size_ft_row = HBoxContainer.new()
	var sft_label := Label.new()
	sft_label.text = "Space (ft):"
	sft_label.custom_minimum_size = Vector2(120, 0)
	_token_size_ft_row.add_child(sft_label)
	_token_size_ft_spin = SpinBox.new()
	_token_size_ft_spin.min_value = 0.0
	_token_size_ft_spin.max_value = 40.0
	_token_size_ft_spin.step = 2.5
	_token_size_ft_spin.value = 5.0
	_token_size_ft_spin.suffix = "ft"
	_token_size_ft_spin.tooltip_text = "Creature space in feet (5 = Medium, 10 = Large, etc.). Auto-sizes the token from calibration."
	_token_size_ft_spin.custom_minimum_size = Vector2(130, 0)
	_token_size_ft_row.add_child(_token_size_ft_spin)
	_token_size_ft_row.visible = false
	vbox.add_child(_token_size_ft_row)

	# Roam path info (read-only, MONSTER/NPC only)
	_token_roam_info_row = HBoxContainer.new()
	var roam_info_lbl := Label.new()
	roam_info_lbl.text = "Roam Path:"
	roam_info_lbl.custom_minimum_size = Vector2(120, 0)
	_token_roam_info_row.add_child(roam_info_lbl)
	_token_roam_info_label = Label.new()
	_token_roam_info_label.text = "None"
	_token_roam_info_row.add_child(_token_roam_info_label)
	_token_roam_info_row.visible = false
	vbox.add_child(_token_roam_info_row)

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

	# Statblocks section (MONSTER / NPC only)
	_token_statblocks_section = VBoxContainer.new()
	_token_statblocks_section.add_theme_constant_override("separation", 4)
	_token_statblocks_section.visible = false

	var sb_sep := HSeparator.new()
	_token_statblocks_section.add_child(sb_sep)

	var sb_header := Label.new()
	sb_header.text = "Statblocks"
	sb_header.add_theme_font_size_override("font_size", 14)
	_token_statblocks_section.add_child(sb_header)

	_token_statblocks_list = ItemList.new()
	_token_statblocks_list.custom_minimum_size = Vector2(0, 80)
	_token_statblocks_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_token_statblocks_list.item_selected.connect(_on_token_statblock_selected)
	_token_statblocks_section.add_child(_token_statblocks_list)

	var sb_btns := HBoxContainer.new()
	sb_btns.add_theme_constant_override("separation", 4)
	_token_statblock_attach_btn = Button.new()
	_token_statblock_attach_btn.text = "Attach…"
	_token_statblock_attach_btn.pressed.connect(_on_token_statblock_attach)
	sb_btns.add_child(_token_statblock_attach_btn)
	_token_statblock_detach_btn = Button.new()
	_token_statblock_detach_btn.text = "Detach"
	_token_statblock_detach_btn.disabled = true
	_token_statblock_detach_btn.pressed.connect(_on_token_statblock_detach)
	sb_btns.add_child(_token_statblock_detach_btn)
	_token_statblock_view_btn = Button.new()
	_token_statblock_view_btn.text = "View"
	_token_statblock_view_btn.disabled = true
	_token_statblock_view_btn.pressed.connect(_on_token_statblock_view)
	sb_btns.add_child(_token_statblock_view_btn)
	_token_statblock_rollhp_btn = Button.new()
	_token_statblock_rollhp_btn.text = "Roll HP"
	_token_statblock_rollhp_btn.disabled = true
	_token_statblock_rollhp_btn.pressed.connect(_on_token_statblock_roll_hp)
	sb_btns.add_child(_token_statblock_rollhp_btn)
	_token_statblock_edit_overrides_btn = Button.new()
	_token_statblock_edit_overrides_btn.text = "Edit Overrides…"
	_token_statblock_edit_overrides_btn.disabled = true
	_token_statblock_edit_overrides_btn.pressed.connect(_on_token_statblock_edit_overrides)
	sb_btns.add_child(_token_statblock_edit_overrides_btn)
	_token_statblocks_section.add_child(sb_btns)

	# HP editors
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	_token_statblock_hp_label = Label.new()
	_token_statblock_hp_label.text = "Current HP:"
	hp_row.add_child(_token_statblock_hp_label)
	_token_statblock_hp_spin = SpinBox.new()
	_token_statblock_hp_spin.min_value = 0
	_token_statblock_hp_spin.max_value = 9999
	_token_statblock_hp_spin.step = 1
	_token_statblock_hp_spin.value = 0
	_token_statblock_hp_spin.custom_minimum_size = Vector2(90, 0)
	_token_statblock_hp_spin.value_changed.connect(_on_token_statblock_hp_changed)
	hp_row.add_child(_token_statblock_hp_spin)
	var temp_label := Label.new()
	temp_label.text = "Temp HP:"
	hp_row.add_child(temp_label)
	_token_statblock_temphp_spin = SpinBox.new()
	_token_statblock_temphp_spin.min_value = 0
	_token_statblock_temphp_spin.max_value = 9999
	_token_statblock_temphp_spin.step = 1
	_token_statblock_temphp_spin.value = 0
	_token_statblock_temphp_spin.custom_minimum_size = Vector2(80, 0)
	_token_statblock_temphp_spin.value_changed.connect(_on_token_statblock_temphp_changed)
	hp_row.add_child(_token_statblock_temphp_spin)
	_token_statblocks_section.add_child(hp_row)

	# Statblock visibility level for player display
	var sv_row := HBoxContainer.new()
	sv_row.add_theme_constant_override("separation", 6)
	var sv_label := Label.new()
	sv_label.text = "Player Visibility:"
	sv_label.custom_minimum_size = Vector2(120, 0)
	sv_row.add_child(sv_label)
	_token_statblock_visibility_option = OptionButton.new()
	_token_statblock_visibility_option.custom_minimum_size = Vector2(180, 0)
	_token_statblock_visibility_option.add_item("Hidden", 0)
	_token_statblock_visibility_option.add_item("Name Only", 1)
	_token_statblock_visibility_option.add_item("Partial (name/AC/HP)", 2)
	_token_statblock_visibility_option.add_item("Full", 3)
	sv_row.add_child(_token_statblock_visibility_option)
	_token_statblocks_section.add_child(sv_row)

	vbox.add_child(_token_statblocks_section)

	# Theme the token editor dialog
	var _te_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _te_reg != null and _te_reg.ui_theme != null:
		_te_reg.ui_theme.theme_control_tree(_token_editor_dialog, _ui_scale())


func _apply_token_context_menu_theme() -> void:
	_apply_token_context_menu_theme_to(_token_context_menu)


func _apply_token_context_menu_theme_to(menu: PopupMenu) -> void:
	if menu == null:
		return
	var _cm_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _cm_reg != null and _cm_reg.ui_theme != null:
		_cm_reg.ui_theme.apply_popup_style(menu, _ui_scale())
	else:
		var scale := _ui_scale()
		menu.add_theme_font_size_override("font_size", roundi(16.0 * scale))
		menu.add_theme_constant_override("v_separation", roundi(6 * scale))
		menu.add_theme_constant_override("h_separation", roundi(12 * scale))


func _on_token_category_changed(idx: int) -> void:
	var cat: int = _token_category_option.get_item_id(idx) if _token_category_option != null else -1
	var is_door_type: bool = cat == TokenData.TokenCategory.DOOR or cat == TokenData.TokenCategory.SECRET_PASSAGE
	if _token_blocks_los_row != null:
		_token_blocks_los_row.visible = is_door_type
	var is_creature: bool = cat == TokenData.TokenCategory.MONSTER or cat == TokenData.TokenCategory.NPC
	if _token_size_ft_row != null:
		_token_size_ft_row.visible = is_creature
	if _token_roam_info_row != null:
		_token_roam_info_row.visible = is_creature
	if is_creature and _token_size_ft_spin != null and _token_size_ft_spin.value <= 0.0:
		_token_size_ft_spin.value = 5.0
	if _token_statblocks_section != null:
		_token_statblocks_section.visible = is_creature
	# Default trap flags: autopause (collision-only), pause-on-interact, auto-reveal.
	if cat == TokenData.TokenCategory.TRAP:
		if _token_autopause_check != null:
			_token_autopause_check.button_pressed = true
		if _token_autopause_collision_check != null:
			_token_autopause_collision_check.button_pressed = true
		if _token_pause_interact_check != null:
			_token_pause_interact_check.button_pressed = true
		if _token_auto_reveal_check != null:
			_token_auto_reveal_check.button_pressed = true


# ── Token statblock helpers ─────────────────────────────────────────────────

func _refresh_token_statblock_list() -> void:
	if _token_statblocks_list == null:
		return
	_token_statblocks_list.clear()
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	for ref_id: Variant in _token_pending_statblock_refs:
		var sb_id: String = str(ref_id)
		var sb: StatblockData = _resolve_statblock(sb_id, registry)
		var override_dict: Variant = _token_pending_statblock_overrides.get(sb_id, null)
		var display_name: String = sb.name if sb != null else sb_id
		var hp_str: String = ""
		if override_dict is Dictionary:
			var so: StatblockOverride = StatblockOverride.from_dict(override_dict as Dictionary)
			var max_hp: int = so.max_hp if so.max_hp > 0 else (sb.hit_points if sb != null else 0)
			hp_str = " [HP: %d/%d]" % [so.current_hp, max_hp]
		elif sb != null:
			hp_str = " [HP: %d]" % sb.hit_points
		_token_statblocks_list.add_item(display_name + hp_str)
	_update_token_statblock_buttons()


func _resolve_statblock(sb_id: String, registry: ServiceRegistry) -> StatblockData:
	if registry == null:
		return null
	# Try statblock service first (global + campaign + map), then SRD
	if registry.statblock != null:
		var s: StatblockData = registry.statblock.get_statblock(sb_id)
		if s != null:
			return s
	if registry.srd != null:
		var ruleset: String = "2014"
		if registry.campaign != null:
			var camp: CampaignData = registry.campaign.get_active_campaign()
			if camp != null:
				ruleset = camp.default_ruleset
		var s2: StatblockData = registry.srd.get_monster(sb_id, ruleset)
		if s2 != null:
			return s2
	return null


func _update_token_statblock_buttons() -> void:
	var sel: PackedInt32Array = _token_statblocks_list.get_selected_items() if _token_statblocks_list != null else PackedInt32Array()
	var has_sel: bool = sel.size() > 0
	if _token_statblock_detach_btn != null:
		_token_statblock_detach_btn.disabled = not has_sel
	if _token_statblock_view_btn != null:
		_token_statblock_view_btn.disabled = not has_sel
	if _token_statblock_rollhp_btn != null:
		_token_statblock_rollhp_btn.disabled = not has_sel
	if _token_statblock_edit_overrides_btn != null:
		_token_statblock_edit_overrides_btn.disabled = not has_sel
	# Update HP spinboxes
	if has_sel:
		var idx: int = sel[0]
		var sb_id: String = str(_token_pending_statblock_refs[idx]) if idx < _token_pending_statblock_refs.size() else ""
		var override_dict: Variant = _token_pending_statblock_overrides.get(sb_id, null)
		if override_dict is Dictionary:
			var so: StatblockOverride = StatblockOverride.from_dict(override_dict as Dictionary)
			if _token_statblock_hp_spin != null:
				_token_statblock_hp_spin.value = so.current_hp
			if _token_statblock_temphp_spin != null:
				_token_statblock_temphp_spin.value = so.temp_hp


func _on_token_statblock_selected(_index: int) -> void:
	_update_token_statblock_buttons()


func _on_token_statblock_attach() -> void:
	# Open library in attach mode.
	if _statblock_library == null or not is_instance_valid(_statblock_library):
		_statblock_library = StatblockLibrary.new()
		add_child(_statblock_library)
		_apply_dialog_themes()
	_statblock_library.set_attach_mode(true)
	if not _statblock_library.statblock_picked.is_connected(_on_library_statblock_picked):
		_statblock_library.statblock_picked.connect(_on_library_statblock_picked)
	_statblock_library.popup_centered()
	_statblock_library.grab_focus()


func _on_library_statblock_picked(data: StatblockData) -> void:
	if data == null:
		return
	# For SRD entries, store the srd_index (stable key for SRD lookups).
	# For custom/campaign/global entries, store the generated id.
	var sb_id: String = data.srd_index if not data.srd_index.is_empty() else data.id
	if sb_id.is_empty():
		return
	# Avoid duplicates
	for existing: Variant in _token_pending_statblock_refs:
		if str(existing) == sb_id:
			return
	_token_pending_statblock_refs.append(sb_id)
	# Create initial override with base HP
	var so := StatblockOverride.new()
	so.base_statblock_id = sb_id
	so.current_hp = data.hit_points
	so.max_hp = data.hit_points
	_token_pending_statblock_overrides[sb_id] = so.to_dict()
	_refresh_token_statblock_list()
	# Auto-suggest a label from the statblock name when the label field is empty.
	if _token_label_edit != null and _token_label_edit.text.strip_edges().is_empty():
		_token_label_edit.text = data.name
	# Auto-apply SRD icon if token has no custom icon
	_maybe_apply_srd_icon(data)
	# Auto-set size from statblock creature size
	if _token_size_ft_spin != null and not data.size.is_empty():
		var size_ft: float = StatblockData.size_to_feet(data.size)
		if size_ft > 0.0:
			_token_size_ft_spin.value = size_ft


func _on_token_statblock_detach() -> void:
	if _token_statblocks_list == null:
		return
	var sel: PackedInt32Array = _token_statblocks_list.get_selected_items()
	if sel.size() == 0:
		return
	var idx: int = sel[0]
	if idx < 0 or idx >= _token_pending_statblock_refs.size():
		return
	var sb_id: String = str(_token_pending_statblock_refs[idx])
	_token_pending_statblock_refs.remove_at(idx)
	_token_pending_statblock_overrides.erase(sb_id)
	_refresh_token_statblock_list()


func _on_token_statblock_view() -> void:
	if _token_statblocks_list == null:
		return
	var sel: PackedInt32Array = _token_statblocks_list.get_selected_items()
	if sel.size() == 0:
		return
	var idx: int = sel[0]
	if idx < 0 or idx >= _token_pending_statblock_refs.size():
		return
	var sb_id: String = str(_token_pending_statblock_refs[idx])
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var sb: StatblockData = _resolve_statblock(sb_id, registry)
	if sb == null:
		return
	# Apply overrides for display
	var override_dict: Variant = _token_pending_statblock_overrides.get(sb_id, null)
	if override_dict is Dictionary:
		var so: StatblockOverride = StatblockOverride.from_dict(override_dict as Dictionary)
		sb = so.apply_to(sb)
	# Show in a popup card
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var popup := Window.new()
	popup.title = sb.name
	popup.transient = true
	popup.size = Vector2i(mgr.scaled(420.0) if mgr != null else 420, mgr.scaled(650.0) if mgr != null else 650)
	popup.min_size = Vector2i(mgr.scaled(350.0) if mgr != null else 350, mgr.scaled(400.0) if mgr != null else 400)
	popup.wrap_controls = false
	popup.close_requested.connect(func() -> void: popup.queue_free())
	var m_pad: int = mgr.scaled(8.0) if mgr != null else 8
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", m_pad)
	margin.add_theme_constant_override("margin_right", m_pad)
	margin.add_theme_constant_override("margin_top", m_pad)
	margin.add_theme_constant_override("margin_bottom", m_pad)
	popup.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var card := StatblockCardView.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)
	add_child(popup)
	card.display(sb)
	if mgr != null:
		card.apply_font_scale(mgr.scaled(14.0))
	var _sv_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _sv_reg != null and _sv_reg.ui_theme != null:
		_sv_reg.ui_theme.theme_control_tree(popup, _ui_scale())
	popup.popup_centered()
	popup.grab_focus()


func _on_token_statblock_edit_overrides() -> void:
	if _token_statblocks_list == null:
		return
	var sel: PackedInt32Array = _token_statblocks_list.get_selected_items()
	if sel.size() == 0:
		return
	var idx: int = sel[0]
	if idx < 0 or idx >= _token_pending_statblock_refs.size():
		return
	var sb_id: String = str(_token_pending_statblock_refs[idx])
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var sb: StatblockData = _resolve_statblock(sb_id, registry)
	if sb == null:
		return
	var override_dict: Variant = _token_pending_statblock_overrides.get(sb_id, null)
	var so: StatblockOverride = null
	if override_dict is Dictionary:
		so = StatblockOverride.from_dict(override_dict as Dictionary)
	else:
		so = StatblockOverride.new()
		so.base_statblock_id = sb_id
	var editor: Window = OverrideEditorScript.new()
	editor.transient = true
	editor.setup(sb, so)
	editor.overrides_confirmed.connect(func(new_dict: Dictionary) -> void:
		_token_pending_statblock_overrides[sb_id] = new_dict
		_refresh_token_statblock_list()
		editor.queue_free()
	)
	add_child(editor)
	var _oe_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _oe_reg != null and _oe_reg.ui_theme != null:
		_oe_reg.ui_theme.theme_control_tree(editor, _ui_scale())
	editor.popup_centered()


## Open override editor for a token from the context menu. Saves directly to
## the token on confirm (unlike the token-editor version which uses pending edits).
func _show_override_editor_for_token(td: TokenData, sb_id: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var sb: StatblockData = _resolve_statblock(sb_id, registry)
	if sb == null:
		return
	var override_dict: Variant = td.statblock_overrides.get(sb_id, null)
	var so: StatblockOverride = null
	if override_dict is Dictionary:
		so = StatblockOverride.from_dict(override_dict as Dictionary)
	else:
		so = StatblockOverride.new()
		so.base_statblock_id = sb_id
		so.current_hp = sb.hit_points
		so.max_hp = sb.hit_points
	var editor: Window = OverrideEditorScript.new()
	editor.transient = true
	editor.setup(sb, so)
	var token_id: String = td.id
	editor.overrides_confirmed.connect(func(new_dict: Dictionary) -> void:
		td.statblock_overrides[sb_id] = new_dict
		if registry != null and registry.token != null:
			registry.token.update_token(td)
			if _map_view != null:
				_map_view.update_token_sprite(td)
			_broadcast_token_change(td, false)
			_nm_broadcast_to_displays({"msg": "token_statblock_override_updated",
				"token_id": token_id, "statblock_id": sb_id,
				"overrides": new_dict})
		editor.queue_free()
	)
	add_child(editor)
	if registry != null and registry.ui_theme != null:
		registry.ui_theme.theme_control_tree(editor, _ui_scale())
	editor.popup_centered()


func _on_token_statblock_roll_hp() -> void:
	if _token_statblocks_list == null:
		return
	var sel: PackedInt32Array = _token_statblocks_list.get_selected_items()
	if sel.size() == 0:
		return
	var idx: int = sel[0]
	if idx < 0 or idx >= _token_pending_statblock_refs.size():
		return
	var sb_id: String = str(_token_pending_statblock_refs[idx])
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var sb: StatblockData = _resolve_statblock(sb_id, registry)
	if sb == null:
		return
	# Get or create override
	var override_dict: Variant = _token_pending_statblock_overrides.get(sb_id, null)
	var so: StatblockOverride
	if override_dict is Dictionary:
		so = StatblockOverride.from_dict(override_dict as Dictionary)
	else:
		so = StatblockOverride.new()
		so.base_statblock_id = sb_id
	var rolled: int = so.roll_hit_points(sb)
	_token_pending_statblock_overrides[sb_id] = so.to_dict()
	if _token_statblock_hp_spin != null:
		_token_statblock_hp_spin.value = rolled
	_refresh_token_statblock_list()


func _on_token_statblock_hp_changed(new_val: float) -> void:
	if _token_statblocks_list == null:
		return
	var sel: PackedInt32Array = _token_statblocks_list.get_selected_items()
	if sel.size() == 0:
		return
	var idx: int = sel[0]
	if idx < 0 or idx >= _token_pending_statblock_refs.size():
		return
	var sb_id: String = str(_token_pending_statblock_refs[idx])
	var so_dict: Variant = _token_pending_statblock_overrides.get(sb_id, {})
	if not so_dict is Dictionary:
		so_dict = {}
	var d := so_dict as Dictionary
	d["current_hp"] = int(new_val)
	d["base_statblock_id"] = sb_id
	_token_pending_statblock_overrides[sb_id] = d


func _on_token_statblock_temphp_changed(new_val: float) -> void:
	if _token_statblocks_list == null:
		return
	var sel: PackedInt32Array = _token_statblocks_list.get_selected_items()
	if sel.size() == 0:
		return
	var idx: int = sel[0]
	if idx < 0 or idx >= _token_pending_statblock_refs.size():
		return
	var sb_id: String = str(_token_pending_statblock_refs[idx])
	var so_dict: Variant = _token_pending_statblock_overrides.get(sb_id, {})
	if not so_dict is Dictionary:
		so_dict = {}
	var d := so_dict as Dictionary
	d["temp_hp"] = int(new_val)
	d["base_statblock_id"] = sb_id
	_token_pending_statblock_overrides[sb_id] = d


## Auto-apply SRD monster icon when statblock is attached and no custom icon set.
func _maybe_apply_srd_icon(data: StatblockData) -> void:
	# Only applies when the token editor icon preview is blank
	if _token_icon_preview != null and _token_icon_preview.texture != null:
		return
	if not _token_icon_pending_source.is_empty():
		return
	if data.srd_image_url.is_empty():
		return
	# Determine cache path
	var slug: String = data.srd_index if not data.srd_index.is_empty() else data.name.to_lower().replace(" ", "-")
	var cache_dir: String = "user://data/srd_cache/images/monsters/"
	var cache_path: String = cache_dir + slug + ".png"
	if FileAccess.file_exists(cache_path):
		_token_icon_pending_source = cache_path
		var img: Image = TokenIconUtils.load_image_from_path(cache_path)
		if img != null and _token_icon_preview != null:
			_token_icon_preview.texture = TokenIconUtils.create_circular_texture(img)
			if _token_icon_crop_btn != null:
				_token_icon_crop_btn.disabled = false
	else:
		# Download asynchronously
		DirAccess.make_dir_recursive_absolute(cache_dir)
		var http := HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
			http.queue_free()
			if code != 200 or body.size() == 0:
				return
			var img := Image.new()
			if img.load_png_from_buffer(body) != OK:
				if img.load_jpg_from_buffer(body) != OK:
					if img.load_webp_from_buffer(body) != OK:
						return
			img.save_png(cache_path)
			_token_icon_pending_source = cache_path
			if _token_icon_preview != null:
				_token_icon_preview.texture = TokenIconUtils.create_circular_texture(img)
				if _token_icon_crop_btn != null:
					_token_icon_crop_btn.disabled = false
		)
		http.request(data.srd_image_url)


## Show a stat card popup for a specific statblock attached to a token.
func _show_token_statblock_card(td: TokenData, sb_id: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var sb: StatblockData = _resolve_statblock(sb_id, registry)
	if sb == null:
		push_warning("Cannot resolve statblock '%s' — detach and re-attach from the library." % sb_id)
		return
	# Apply overrides
	var override_dict: Variant = td.statblock_overrides.get(sb_id, null)
	if override_dict is Dictionary:
		var so: StatblockOverride = StatblockOverride.from_dict(override_dict as Dictionary)
		sb = so.apply_to(sb)
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var popup := Window.new()
	popup.title = sb.name
	popup.transient = true
	popup.size = Vector2i(mgr.scaled(420.0) if mgr != null else 420, mgr.scaled(650.0) if mgr != null else 650)
	popup.min_size = Vector2i(mgr.scaled(350.0) if mgr != null else 350, mgr.scaled(400.0) if mgr != null else 400)
	popup.wrap_controls = false
	popup.close_requested.connect(func() -> void: popup.queue_free())
	var m_pad2: int = mgr.scaled(8.0) if mgr != null else 8
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", m_pad2)
	margin.add_theme_constant_override("margin_right", m_pad2)
	margin.add_theme_constant_override("margin_top", m_pad2)
	margin.add_theme_constant_override("margin_bottom", m_pad2)
	popup.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var card := StatblockCardView.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)
	add_child(popup)
	card.display(sb)
	if mgr != null:
		card.apply_font_scale(mgr.scaled(14.0))
	var _sc_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _sc_reg != null and _sc_reg.ui_theme != null:
		_sc_reg.ui_theme.theme_control_tree(popup, _ui_scale())
	popup.popup_centered()
	popup.grab_focus()


## Show a quick HP adjustment dialog for the primary statblock on a token.
func _show_quick_hp_dialog(td: TokenData) -> void:
	if td.statblock_refs.size() == 0:
		return
	var sb_id: String = str(td.statblock_refs[0])
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var sb: StatblockData = _resolve_statblock(sb_id, registry)
	# Get or create override
	var override_dict: Variant = td.statblock_overrides.get(sb_id, null)
	var so: StatblockOverride
	if override_dict is Dictionary:
		so = StatblockOverride.from_dict(override_dict as Dictionary)
	else:
		so = StatblockOverride.new()
		so.base_statblock_id = sb_id
		so.current_hp = sb.hit_points if sb != null else 0
		so.max_hp = sb.hit_points if sb != null else 0
	var max_hp: int = so.max_hp if so.max_hp > 0 else int(so.get_effective("hit_points", sb.hit_points if sb != null else 0))
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base: float) -> int:
		return mgr.scaled(base) if mgr != null else roundi(base)
	var popup := AcceptDialog.new()
	popup.title = "Quick HP — %s" % (sb.name if sb != null else sb_id)
	popup.ok_button_text = "Close"

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", s.call(10.0))
	popup.add_child(root)

	# HP display header
	var hp_label := Label.new()
	hp_label.add_theme_font_size_override("font_size", s.call(18.0))
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.text = "%d / %d HP" % [so.current_hp, max_hp]
	root.add_child(hp_label)

	# Temp HP display
	var temp_label := Label.new()
	temp_label.add_theme_font_size_override("font_size", s.call(13.0))
	temp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	temp_label.modulate = Color(0.5, 0.7, 1.0)
	temp_label.text = "Temp HP: %d" % so.temp_hp if so.temp_hp > 0 else ""
	root.add_child(temp_label)

	root.add_child(HSeparator.new())

	# Amount entry
	var amount_label := Label.new()
	amount_label.text = "Amount:"
	amount_label.add_theme_font_size_override("font_size", s.call(14.0))
	root.add_child(amount_label)

	var amount_spin := SpinBox.new()
	amount_spin.min_value = 1
	amount_spin.max_value = 9999
	amount_spin.step = 1
	amount_spin.value = 1
	amount_spin.custom_minimum_size = Vector2(s.call(200.0), 0)
	amount_spin.get_line_edit().add_theme_font_size_override("font_size", s.call(14.0))
	root.add_child(amount_spin)

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", s.call(8.0))
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var damage_btn := Button.new()
	damage_btn.text = "Deal Damage"
	damage_btn.custom_minimum_size = Vector2(s.call(120.0), s.call(32.0))
	damage_btn.add_theme_font_size_override("font_size", s.call(14.0))
	btn_row.add_child(damage_btn)
	var heal_btn := Button.new()
	heal_btn.text = "Heal"
	heal_btn.custom_minimum_size = Vector2(s.call(120.0), s.call(32.0))
	heal_btn.add_theme_font_size_override("font_size", s.call(14.0))
	btn_row.add_child(heal_btn)
	root.add_child(btn_row)

	if mgr != null:
		mgr.scale_button(popup.get_ok_button(), 80.0, 28.0, 13.0)
	add_child(popup)

	var token_id: String = td.id
	var update_display := func() -> void:
		hp_label.text = "%d / %d HP" % [so.current_hp, max_hp]
		temp_label.text = "Temp HP: %d" % so.temp_hp if so.temp_hp > 0 else ""

	var apply_hp := func(delta: int) -> void:
		var new_hp: int = clampi(so.current_hp + delta, 0, max_hp)
		so.current_hp = new_hp
		td.statblock_overrides[sb_id] = so.to_dict()
		update_display.call()
		# Update the token and sprite
		if registry != null and registry.token != null:
			registry.token.update_token(td)
			if _map_view != null:
				_map_view.update_token_sprite(td)
			_broadcast_token_change(td, false)
			_nm_broadcast_to_displays({"msg": "token_statblock_override_updated",
				"token_id": token_id, "statblock_id": sb_id,
				"overrides": so.to_dict()})

	damage_btn.pressed.connect(func() -> void:
		var amt: int = absi(int(amount_spin.value))
		if amt <= 0:
			return
		# Damage absorbs temp HP first
		var temp_absorbed: int = mini(so.temp_hp, amt)
		so.temp_hp -= temp_absorbed
		amt -= temp_absorbed
		apply_hp.call(-amt)
	)
	heal_btn.pressed.connect(func() -> void:
		var amt: int = absi(int(amount_spin.value))
		if amt <= 0:
			return
		apply_hp.call(amt)
	)
	popup.confirmed.connect(func() -> void: popup.queue_free())
	var _hp_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _hp_reg != null and _hp_reg.ui_theme != null:
		_hp_reg.ui_theme.theme_control_tree(popup, _ui_scale())
	if mgr != null:
		mgr.popup_fitted(popup, 340.0, 0.0)
	else:
		popup.reset_size()
		popup.popup_centered()
		popup.grab_focus()


# ── Token icon image helpers ────────────────────────────────────────────────

func _on_token_icon_choose_pressed() -> void:
	if _token_icon_file_dialog == null:
		_token_icon_file_dialog = FileDialog.new()
		_token_icon_file_dialog.use_native_dialog = true
		_token_icon_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_token_icon_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_token_icon_file_dialog.title = "Select Token Icon Image"
		for f: String in TokenIconUtils.FILE_DIALOG_FILTERS:
			_token_icon_file_dialog.add_filter(f)
		_token_icon_file_dialog.file_selected.connect(_on_token_icon_file_selected)
		add_child(_token_icon_file_dialog)
	_token_icon_file_dialog.popup_centered(Vector2i(800, 500))


func _on_token_icon_file_selected(path: String) -> void:
	_load_token_icon_from_path(path)


func _on_token_icon_load_pressed() -> void:
	if _token_icon_path_edit == null:
		return
	var path: String = _token_icon_path_edit.text.strip_edges()
	if path.is_empty():
		return
	_load_token_icon_from_path(path)


func _load_token_icon_from_path(path: String) -> void:
	var img: Image = TokenIconUtils.load_image_from_path(path)
	if img == null:
		_set_status("Failed to load icon image: %s" % path)
		return
	_token_icon_pending_source = path
	_token_icon_crop_offset = Vector2.ZERO
	_token_icon_crop_zoom = 1.0
	_token_icon_facing_deg = 0.0
	# Show circular preview.
	var tex: ImageTexture = TokenIconUtils.create_circular_texture(img)
	if _token_icon_preview != null:
		_token_icon_preview.texture = tex
	if _token_icon_path_edit != null:
		_token_icon_path_edit.text = path
	if _token_icon_crop_btn != null:
		_token_icon_crop_btn.disabled = false


func _on_token_icon_clear_pressed() -> void:
	_token_icon_pending_source = ""
	_token_icon_crop_offset = Vector2.ZERO
	_token_icon_crop_zoom = 1.0
	_token_icon_facing_deg = 0.0
	_token_icon_campaign_image_id = ""
	if _token_icon_preview != null:
		_token_icon_preview.texture = null
	if _token_icon_path_edit != null:
		_token_icon_path_edit.text = ""
	if _token_icon_crop_btn != null:
		_token_icon_crop_btn.disabled = true


func _on_token_icon_campaign_pressed() -> void:
	_ensure_campaign_image_picker()
	if _campaign_image_picker == null:
		return
	# Disconnect any previous one-shot connection.
	if _campaign_image_picker.image_selected.is_connected(_on_token_campaign_image_picked):
		_campaign_image_picker.image_selected.disconnect(_on_token_campaign_image_picked)
	_campaign_image_picker.image_selected.connect(_on_token_campaign_image_picked)
	_campaign_image_picker.show_picker()


func _on_token_campaign_image_picked(path: String, campaign_image_id: String) -> void:
	_campaign_image_picker.image_selected.disconnect(_on_token_campaign_image_picked)
	_token_icon_campaign_image_id = campaign_image_id
	_load_token_icon_from_path(path)


func _ensure_campaign_image_picker() -> void:
	if _campaign_image_picker != null:
		return
	_campaign_image_picker = CampaignImagePicker.new()
	add_child(_campaign_image_picker)
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(_campaign_image_picker, _ui_scale())


## Persist the pending token icon into the .map bundle and return the relative path.
## Returns empty string if no pending icon or the bundle path is unavailable.
func _save_pending_token_icon(token_id: String) -> String:
	if _token_icon_pending_source.is_empty() or _active_map_bundle_path.is_empty():
		return ""
	var dest_dir: String = _active_map_bundle_path.path_join("token_icons")
	var dest_path: String = dest_dir.path_join("%s.png" % token_id)
	var err: Error = TokenIconUtils.process_and_save_icon(
		_token_icon_pending_source, dest_path,
		_token_icon_crop_offset, _token_icon_crop_zoom)
	if err != OK:
		_set_status("Failed to save token icon (error %d)" % err)
		return ""
	return dest_path


## Delete a token's icon file from the .map bundle directory.
func _delete_token_icon(token_id: String) -> void:
	if _active_map_bundle_path.is_empty():
		return
	var icon_path: String = _active_map_bundle_path.path_join("token_icons/%s.png" % token_id)
	TokenIconUtils.delete_icon_file(icon_path)
	TokenIconUtils.evict(icon_path)


# ── Crop editor ─────────────────────────────────────────────────────────────

## Open the crop editor with the given source image path, starting offset/zoom,
## facing direction, and a callback `fn(offset: Vector2, zoom: float, facing_deg: float)` invoked on confirm.
func _open_crop_editor(source_path: String, offset: Vector2, zoom: float, facing_deg: float, on_confirm: Callable) -> void:
	var img: Image = TokenIconUtils.load_image_from_path(source_path)
	if img == null:
		_set_status("Cannot open crop editor — failed to load image.")
		return
	_crop_editor_source_img = img
	_crop_editor_source_tex = ImageTexture.create_from_image(img)
	_crop_editor_offset = offset
	_crop_editor_zoom = maxf(zoom, 1.0)
	_crop_editor_dragging = false
	_crop_editor_facing_deg = facing_deg
	_crop_editor_facing_dragging = false
	_crop_editor_callback = on_confirm
	if _crop_editor_dialog == null:
		_build_crop_editor_dialog()
	_crop_editor_canvas.queue_redraw()
	var _ce_mgr := _get_ui_scale_mgr()
	if _ce_mgr != null:
		_crop_editor_dialog.min_size = Vector2i(_ce_mgr.scaled(460.0), _ce_mgr.scaled(520.0))
	_crop_editor_dialog.reset_size()
	_crop_editor_dialog.popup_centered()


func _build_crop_editor_dialog() -> void:
	var mgr := _get_ui_scale_mgr()
	_crop_editor_dialog = Window.new()
	_crop_editor_dialog.title = "Crop Icon Image"
	_crop_editor_dialog.wrap_controls = true
	_crop_editor_dialog.transient = true
	_crop_editor_dialog.close_requested.connect(_on_crop_editor_cancel)
	add_child(_crop_editor_dialog)

	_crop_editor_vbox = VBoxContainer.new()
	_crop_editor_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	if mgr != null:
		_crop_editor_vbox.add_theme_constant_override("separation", mgr.scaled(8.0))
	else:
		_crop_editor_vbox.add_theme_constant_override("separation", 8)
	_crop_editor_dialog.add_child(_crop_editor_vbox)

	_crop_editor_hint = Label.new()
	_crop_editor_hint.text = "Drag to pan · Scroll to zoom · Right-drag circle edge to set facing"
	_crop_editor_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if mgr != null:
		_crop_editor_hint.add_theme_font_size_override("font_size", mgr.scaled(14.0))
	_crop_editor_vbox.add_child(_crop_editor_hint)

	var panel := Panel.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_crop_editor_vbox.add_child(panel)

	_crop_editor_canvas = Control.new()
	_crop_editor_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crop_editor_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_crop_editor_canvas.draw.connect(_on_crop_editor_draw)
	_crop_editor_canvas.gui_input.connect(_on_crop_editor_input)
	panel.add_child(_crop_editor_canvas)

	_crop_editor_btn_row = HBoxContainer.new()
	_crop_editor_btn_row.alignment = BoxContainer.ALIGNMENT_END
	if mgr != null:
		_crop_editor_btn_row.add_theme_constant_override("separation", mgr.scaled(8.0))
	else:
		_crop_editor_btn_row.add_theme_constant_override("separation", 8)
	_crop_editor_vbox.add_child(_crop_editor_btn_row)

	_crop_editor_reset_btn = Button.new()
	_crop_editor_reset_btn.text = "Reset"
	_crop_editor_reset_btn.pressed.connect(_on_crop_editor_reset)
	if mgr != null:
		mgr.scale_button(_crop_editor_reset_btn)
	_crop_editor_btn_row.add_child(_crop_editor_reset_btn)

	_crop_editor_cancel_btn = Button.new()
	_crop_editor_cancel_btn.text = "Cancel"
	_crop_editor_cancel_btn.pressed.connect(_on_crop_editor_cancel)
	if mgr != null:
		mgr.scale_button(_crop_editor_cancel_btn)
	_crop_editor_btn_row.add_child(_crop_editor_cancel_btn)

	_crop_editor_ok_btn = Button.new()
	_crop_editor_ok_btn.text = "OK"
	_crop_editor_ok_btn.pressed.connect(_on_crop_editor_confirm)
	if mgr != null:
		mgr.scale_button(_crop_editor_ok_btn)
	_crop_editor_btn_row.add_child(_crop_editor_ok_btn)

	# Theme the crop editor dialog.
	var _ce_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _ce_reg != null and _ce_reg.ui_theme != null:
		_ce_reg.ui_theme.theme_control_tree(_crop_editor_dialog, _ui_scale())


func _on_crop_editor_draw() -> void:
	if _crop_editor_canvas == null or _crop_editor_source_tex == null:
		return
	var canvas: Control = _crop_editor_canvas
	var cw: float = canvas.size.x
	var ch: float = canvas.size.y
	var preview_side: float = minf(cw, ch) - 16.0
	if preview_side <= 0.0:
		return
	var cx: float = cw * 0.5
	var cy: float = ch * 0.5

	var src_w: float = float(_crop_editor_source_img.get_width())
	var src_h: float = float(_crop_editor_source_img.get_height())
	var base_side: float = minf(src_w, src_h)
	# Effective crop region size in source pixels.
	var crop_px: float = base_side / maxf(_crop_editor_zoom, 1.0)
	# Scale factor: preview pixels per source pixel.
	var scale: float = preview_side / crop_px

	# Centre of the crop region in source-pixel space.
	var src_cx: float = src_w * 0.5 + _crop_editor_offset.x
	var src_cy: float = src_h * 0.5 + _crop_editor_offset.y

	# Draw the source image scaled and positioned so the crop centre maps to
	# the canvas centre.
	var draw_w: float = src_w * scale
	var draw_h: float = src_h * scale
	var draw_x: float = cx - src_cx * scale
	var draw_y: float = cy - src_cy * scale
	canvas.draw_texture_rect(_crop_editor_source_tex,
		Rect2(draw_x, draw_y, draw_w, draw_h), false)

	# Semi-transparent overlay outside the circular crop region.
	var mask_color := Color(0, 0, 0, 0.55)
	var radius: float = preview_side * 0.5
	# Draw four rects covering the area outside the circle's bounding square.
	var sq_x: float = cx - radius
	var sq_y: float = cy - radius
	var sq_side: float = radius * 2.0
	# Top bar.
	canvas.draw_rect(Rect2(0, 0, cw, sq_y), mask_color)
	# Bottom bar.
	canvas.draw_rect(Rect2(0, sq_y + sq_side, cw, ch - sq_y - sq_side), mask_color)
	# Left bar (between top/bottom).
	canvas.draw_rect(Rect2(0, sq_y, sq_x, sq_side), mask_color)
	# Right bar (between top/bottom).
	canvas.draw_rect(Rect2(sq_x + sq_side, sq_y, cw - sq_x - sq_side, sq_side), mask_color)
	# Draw circle-corner masks using arcs for the four corners of the bounding square.
	# A cheap approach: draw a large ring using canvas_item primitives.
	# Instead, draw a series of thin horizontal scanline rects to mask corners.
	var steps: int = ceili(radius)
	for i: int in range(steps):
		var y_off: float = float(i)
		var x_inset: float = radius - sqrt(maxf(radius * radius - (radius - y_off) * (radius - y_off), 0.0))
		if x_inset < 1.0:
			continue
		# Top half: two rects on left + right of circle at this scanline.
		canvas.draw_rect(Rect2(sq_x, sq_y + y_off, x_inset, 1.0), mask_color)
		canvas.draw_rect(Rect2(sq_x + sq_side - x_inset, sq_y + y_off, x_inset, 1.0), mask_color)
		# Bottom half (mirror).
		canvas.draw_rect(Rect2(sq_x, sq_y + sq_side - y_off - 1.0, x_inset, 1.0), mask_color)
		canvas.draw_rect(Rect2(sq_x + sq_side - x_inset, sq_y + sq_side - y_off - 1.0, x_inset, 1.0), mask_color)

	# Circle outline.
	canvas.draw_arc(Vector2(cx, cy), radius, 0.0, TAU, 64, Color.WHITE, 2.0)

	# ── Facing direction handle ─────────────────────────────────────────────
	var facing_rad: float = deg_to_rad(_crop_editor_facing_deg)
	var handle_pos := Vector2(cx + cos(facing_rad) * radius, cy + sin(facing_rad) * radius)
	var handle_radius: float = 8.0
	# Draw a small direction line from centre outward toward the handle.
	var dir_start := Vector2(cx + cos(facing_rad) * (radius - 30.0), cy + sin(facing_rad) * (radius - 30.0))
	canvas.draw_line(dir_start, handle_pos, Color(1.0, 0.85, 0.0, 0.7), 2.0)
	# Handle circle (filled yellow dot).
	canvas.draw_circle(handle_pos, handle_radius, Color(1.0, 0.85, 0.0, 0.9))
	canvas.draw_arc(handle_pos, handle_radius, 0.0, TAU, 16, Color.WHITE, 1.5)


func _on_crop_editor_input(event: InputEvent) -> void:
	if _crop_editor_canvas == null or _crop_editor_source_img == null:
		return
	var cw: float = _crop_editor_canvas.size.x
	var ch: float = _crop_editor_canvas.size.y
	var cx: float = cw * 0.5
	var cy: float = ch * 0.5
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				# Start facing drag if click is near the circle edge.
				var preview_side: float = minf(cw, ch) - 16.0
				var radius: float = preview_side * 0.5
				var dist: float = mb.position.distance_to(Vector2(cx, cy))
				if absf(dist - radius) < 24.0:
					_crop_editor_facing_dragging = true
					_crop_editor_facing_deg = rad_to_deg(atan2(mb.position.y - cy, mb.position.x - cx))
					if _crop_editor_facing_deg < 0.0:
						_crop_editor_facing_deg += 360.0
					_crop_editor_canvas.queue_redraw()
			else:
				_crop_editor_facing_dragging = false
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Check if clicking on the facing handle first.
				var preview_side: float = minf(cw, ch) - 16.0
				var radius: float = preview_side * 0.5
				var facing_rad: float = deg_to_rad(_crop_editor_facing_deg)
				var handle_pos := Vector2(cx + cos(facing_rad) * radius, cy + sin(facing_rad) * radius)
				if mb.position.distance_to(handle_pos) < 16.0:
					_crop_editor_facing_dragging = true
				else:
					_crop_editor_dragging = true
					_crop_editor_drag_start = mb.position
					_crop_editor_offset_start = _crop_editor_offset
			else:
				_crop_editor_dragging = false
				_crop_editor_facing_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_crop_editor_zoom = minf(_crop_editor_zoom + 0.1, 10.0)
			_crop_editor_canvas.queue_redraw()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_crop_editor_zoom = maxf(_crop_editor_zoom - 0.1, 1.0)
			_crop_editor_canvas.queue_redraw()
	elif event is InputEventMagnifyGesture:
		# Trackpad pinch-to-zoom (macOS).
		var step: float = (event.factor - 1.0) * 2.0
		_crop_editor_zoom = clampf(_crop_editor_zoom + step, 1.0, 10.0)
		_crop_editor_canvas.queue_redraw()
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if _crop_editor_facing_dragging:
			_crop_editor_facing_deg = rad_to_deg(atan2(mm.position.y - cy, mm.position.x - cx))
			if _crop_editor_facing_deg < 0.0:
				_crop_editor_facing_deg += 360.0
			_crop_editor_canvas.queue_redraw()
		elif _crop_editor_dragging:
			var preview_side: float = minf(cw, ch) - 16.0
			if preview_side <= 0.0:
				return
			var src_w: float = float(_crop_editor_source_img.get_width())
			var src_h: float = float(_crop_editor_source_img.get_height())
			var base_side: float = minf(src_w, src_h)
			var crop_px: float = base_side / maxf(_crop_editor_zoom, 1.0)
			var scale: float = preview_side / crop_px
			# Convert pixel drag delta to source-pixel offset.
			var delta: Vector2 = mm.position - _crop_editor_drag_start
			_crop_editor_offset = _crop_editor_offset_start - delta / scale
			_crop_editor_canvas.queue_redraw()


func _on_crop_editor_reset() -> void:
	_crop_editor_offset = Vector2.ZERO
	_crop_editor_zoom = 1.0
	_crop_editor_facing_deg = 0.0
	if _crop_editor_canvas != null:
		_crop_editor_canvas.queue_redraw()


func _on_crop_editor_cancel() -> void:
	if _crop_editor_dialog != null:
		_crop_editor_dialog.hide()


func _on_crop_editor_confirm() -> void:
	if _crop_editor_dialog != null:
		_crop_editor_dialog.hide()
	if _crop_editor_callback.is_valid():
		_crop_editor_callback.call(_crop_editor_offset, _crop_editor_zoom, _crop_editor_facing_deg)


func _on_token_icon_crop_pressed() -> void:
	# Determine source: pending (freshly picked), original source, or saved crop.
	var source: String = _token_icon_pending_source
	if source.is_empty():
		# Try original source path from existing token data.
		var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg != null and reg.token != null and not _token_editor_id.is_empty():
			var td: TokenData = reg.token.get_token_by_id(_token_editor_id)
			if td != null and not td.icon_source_path.is_empty() and FileAccess.file_exists(td.icon_source_path):
				source = td.icon_source_path
	if source.is_empty() and _token_icon_path_edit != null:
		source = _token_icon_path_edit.text.strip_edges()
	if source.is_empty():
		return
	_open_crop_editor(source, _token_icon_crop_offset, _token_icon_crop_zoom, _token_icon_facing_deg,
		func(offset: Vector2, zoom: float, facing_deg: float) -> void:
			_token_icon_crop_offset = offset
			_token_icon_crop_zoom = zoom
			_token_icon_facing_deg = facing_deg
			# Re-generate preview with new crop.
			var img: Image = TokenIconUtils.load_image_from_path(source)
			if img == null:
				return
			img = TokenIconUtils.crop_with_params(img, offset, zoom)
			img = TokenIconUtils.resize_to_max(img, TokenIconUtils.MAX_ICON_SIZE)
			img = TokenIconUtils.apply_circular_alpha_mask(img)
			var tex: ImageTexture = ImageTexture.create_from_image(img)
			if _token_icon_preview != null:
				_token_icon_preview.texture = tex
			# Ensure pending source is set so confirm handler re-saves.
			if _token_icon_pending_source.is_empty():
				_token_icon_pending_source = source)


func _on_profile_icon_crop_pressed() -> void:
	var source: String = _profile_icon_pending_source
	if source.is_empty():
		# Try original source path from existing profile data.
		var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg != null and reg.profile != null and _profile_selected_index >= 0:
			var profiles: Array = reg.profile.get_profiles()
			if _profile_selected_index < profiles.size():
				var prof: PlayerProfile = profiles[_profile_selected_index] as PlayerProfile
				if prof != null and not prof.icon_source_path.is_empty() and FileAccess.file_exists(prof.icon_source_path):
					source = prof.icon_source_path
	if source.is_empty() and _profile_icon_path_edit != null:
		source = _profile_icon_path_edit.text.strip_edges()
	if source.is_empty():
		return
	_open_crop_editor(source, _profile_icon_crop_offset, _profile_icon_crop_zoom, _profile_icon_facing_deg,
		func(offset: Vector2, zoom: float, facing_deg: float) -> void:
			_profile_icon_crop_offset = offset
			_profile_icon_crop_zoom = zoom
			_profile_icon_facing_deg = facing_deg
			var img: Image = TokenIconUtils.load_image_from_path(source)
			if img == null:
				return
			img = TokenIconUtils.crop_with_params(img, offset, zoom)
			img = TokenIconUtils.resize_to_max(img, TokenIconUtils.MAX_ICON_SIZE)
			img = TokenIconUtils.apply_circular_alpha_mask(img)
			var tex: ImageTexture = ImageTexture.create_from_image(img)
			if _profile_icon_preview != null:
				_profile_icon_preview.texture = tex
			if _profile_icon_pending_source.is_empty():
				_profile_icon_pending_source = source)


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
	# Theme dynamically-added puzzle note row controls
	var _pnr_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _pnr_reg != null and _pnr_reg.ui_theme != null:
		_pnr_reg.ui_theme.theme_control_tree(row, _ui_scale())


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
	var s_ft: float = _token_size_ft_spin.value if _token_size_ft_spin != null else 0.0
	var is_creature: bool = category == TokenData.TokenCategory.MONSTER or category == TokenData.TokenCategory.NPC
	if not is_creature:
		s_ft = 0.0
	# Auto-compute pixel size from calibration when size_ft is set.
	if s_ft > 0.0:
		var px_per_5ft: float = _pixels_per_5ft_current()
		var px_size: float = s_ft / 5.0 * px_per_5ft
		w_px = px_size
		h_px = px_size
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
		# Auto-number the label to keep multiple tokens of the same type distinct.
		label_text = _make_unique_token_label(label_text, tm)

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
	data.size_ft = s_ft
	data.rotation_deg = rot_deg
	data.token_shape = shape_val
	data.blocks_los = blos_val

	# Statblock references and overrides.
	data.statblock_refs = _token_pending_statblock_refs.duplicate()
	data.statblock_overrides = _token_pending_statblock_overrides.duplicate(true)

	# Statblock visibility for player display.
	if _token_statblock_visibility_option != null:
		var vis_id: int = _token_statblock_visibility_option.get_selected_id()
		match vis_id:
			1: data.statblock_visibility = "name"
			2: data.statblock_visibility = "partial"
			3: data.statblock_visibility = "full"
			_: data.statblock_visibility = "none"

	# Icon facing direction.
	data.icon_facing_deg = _token_icon_facing_deg

	# Persist custom icon image.
	if not _token_icon_pending_source.is_empty():
		# Delete the previous icon file if it differs.
		if not data.icon_image_path.is_empty():
			TokenIconUtils.delete_icon_file(data.icon_image_path)
			TokenIconUtils.evict(data.icon_image_path)
		var abs_path: String = _save_pending_token_icon(data.id)
		data.icon_image_path = abs_path
		data.icon_crop_offset = _token_icon_crop_offset
		data.icon_crop_zoom = _token_icon_crop_zoom
		# Preserve original source so re-cropping operates on the full image.
		data.icon_source_path = _token_icon_pending_source
		data.icon_campaign_image_id = _token_icon_campaign_image_id
	elif _token_icon_preview != null and _token_icon_preview.texture == null:
		# DM cleared the icon — remove existing file.
		if not data.icon_image_path.is_empty():
			TokenIconUtils.delete_icon_file(data.icon_image_path)
			TokenIconUtils.evict(data.icon_image_path)
		data.icon_image_path = ""
		data.icon_source_path = ""
		data.icon_crop_offset = Vector2.ZERO
		data.icon_crop_zoom = 1.0
		data.icon_campaign_image_id = ""

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
					_broadcast_puzzle_notes_state()
					_refresh_initiative_panel(),
				func():
					var td: TokenData = tm.get_token_by_id(new_snapshot.id)
					if td == null: return
					var reapplied := TokenData.from_dict(new_snapshot.to_dict())
					tm.update_token(reapplied)
					if mv != null: mv.update_token_sprite(reapplied); mv.apply_token_passthrough_state(reapplied)
					_broadcast_token_change(reapplied, false)
					_broadcast_puzzle_notes_state()
					_refresh_initiative_panel()))
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
	# Refresh initiative panel in case the label or statblock changed for a combatant.
	_refresh_initiative_panel()


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


## Recalculate pixel size for every token whose size_ft > 0 based on the
## current map calibration.  Called after calibration, manual scale, or
## grid-type changes so creature tokens stay at the correct foot-based size.
func _resize_tokens_for_calibration(map: MapData) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var px_per_5ft: float = map.cell_px if map.grid_type == MapData.GridType.SQUARE else map.hex_size * 2.0
	var all_tokens: Array = registry.token.get_all_tokens()
	for raw: Variant in all_tokens:
		var td: TokenData = raw as TokenData
		if td == null or td.size_ft <= 0.0:
			continue
		var desired_px: float = td.size_ft / 5.0 * px_per_5ft
		if absf(td.width_px - desired_px) < 0.5 and absf(td.height_px - desired_px) < 0.5:
			continue
		td.width_px = desired_px
		td.height_px = desired_px
		registry.token.update_token(td)
		if _map_view != null:
			_map_view.update_token_sprite(td)
		_broadcast_token_change(td, false)

	# Resize player sprites to match their profile size_ft.
	if _backend != null:
		_backend.resize_player_tokens_for_calibration()


## Snap every token on the current map to its nearest grid cell centre.
## Pushes a single compound undo command and broadcasts changes to displays.
func _snap_all_tokens_to_grid() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var map_data: MapData = _map()
	if map_data == null:
		return
	var all_tokens: Array = registry.token.get_all_tokens()
	var moved_entries: Array = [] # [{id, old_pos, new_pos, old_paths}]
	for raw: Variant in all_tokens:
		var td: TokenData = raw as TokenData
		if td == null:
			continue
		var snap_pos: Vector2 = GridSnap.snap_to_grid(td.world_pos, map_data)
		if snap_pos.distance_to(td.world_pos) < 0.5:
			continue
		var entry: Dictionary = {
			"id": td.id,
			"old_pos": td.world_pos,
			"new_pos": snap_pos,
			"old_paths": td.passage_paths.duplicate(true),
		}
		# Shift SECRET_PASSAGE corridor coordinates by the same delta.
		var delta: Vector2 = snap_pos - td.world_pos
		if td.category == TokenData.TokenCategory.SECRET_PASSAGE and td.passage_paths.size() > 0:
			var shifted: Array = []
			for path_raw: Variant in td.passage_paths:
				if path_raw is PackedVector2Array:
					var shifted_chain := PackedVector2Array()
					for pt: Vector2 in (path_raw as PackedVector2Array):
						shifted_chain.append(pt + delta)
					shifted.append(shifted_chain)
				else:
					shifted.append(path_raw)
			td.passage_paths = shifted
		td.world_pos = snap_pos
		registry.token.update_token(td)
		if _map_view != null:
			_map_view.update_token_sprite(td)
			_map_view.apply_token_passthrough_state(td)
		_broadcast_token_change(td, false)
		moved_entries.append(entry)
	# Push a single compound undo command for DM tokens.
	if not moved_entries.is_empty() and registry.history != null:
		var mv := _map_view
		var entries_copy: Array = moved_entries.duplicate(true)
		registry.history.push_command(HistoryCommand.create(
			"Snap %d tokens to grid" % entries_copy.size(),
			func():
				for e: Variant in entries_copy:
					var d: Dictionary = e as Dictionary
					var td: TokenData = registry.token.get_token_by_id(d["id"] as String)
					if td == null:
						continue
					td.world_pos = d["old_pos"] as Vector2
					td.passage_paths = (d["old_paths"] as Array).duplicate(true)
					registry.token.update_token(td)
					if mv != null:
						mv.update_token_sprite(td)
						mv.apply_token_passthrough_state(td)
					_broadcast_token_change(td, false),
			func():
				for e: Variant in entries_copy:
					var d: Dictionary = e as Dictionary
					var td: TokenData = registry.token.get_token_by_id(d["id"] as String)
					if td == null:
						continue
					var redo_delta: Vector2 = (d["new_pos"] as Vector2) - (d["old_pos"] as Vector2)
					if td.category == TokenData.TokenCategory.SECRET_PASSAGE and td.passage_paths.size() > 0:
						var shifted_redo: Array = []
						for pr: Variant in td.passage_paths:
							if pr is PackedVector2Array:
								var sc := PackedVector2Array()
								for pt: Vector2 in (pr as PackedVector2Array):
									sc.append(pt + redo_delta)
								shifted_redo.append(sc)
							else:
								shifted_redo.append(pr)
						td.passage_paths = shifted_redo
					td.world_pos = d["new_pos"] as Vector2
					registry.token.update_token(td)
					if mv != null:
						mv.update_token_sprite(td)
						mv.apply_token_passthrough_state(td)
					_broadcast_token_change(td, false)))

	# ── Snap player tokens (PlayerSprite characters) ───────────────────────
	var player_moved: int = 0
	var old_player_positions: Dictionary = {}
	var dm_tokens: Dictionary = _backend.get_dm_token_nodes() if _backend != null else {}
	if registry.game_state != null:
		var gs: GameStateManager = registry.game_state
		for pid: Variant in gs.player_positions.keys():
			var old_pos: Vector2 = gs.player_positions[pid] as Vector2
			var snapped_pos: Vector2 = GridSnap.snap_to_grid(old_pos, map_data)
			if snapped_pos.distance_to(old_pos) < 0.5:
				continue
			old_player_positions[pid] = old_pos
			gs.set_position(pid, snapped_pos)
			# Move the actual PlayerSprite node so BackendRuntime doesn't
			# overwrite the position on the next step() frame.
			var sprite: Node2D = dm_tokens.get(pid, null) as Node2D
			if sprite != null and is_instance_valid(sprite):
				sprite.global_position = snapped_pos
			player_moved += 1
		if player_moved > 0:
			_broadcast_player_state()

	# ── Snap spawn points ─────────────────────────────────────────────────
	var spawn_moved: int = 0
	var old_spawn_points: Array = map_data.spawn_points.duplicate(true)
	for sp: Variant in map_data.spawn_points:
		if not sp is Dictionary:
			continue
		var spd := sp as Dictionary
		var sp_pos := Vector2(float(spd.get("x", 0.0)), float(spd.get("y", 0.0)))
		var snapped_sp: Vector2 = GridSnap.snap_to_grid(sp_pos, map_data)
		if snapped_sp.distance_to(sp_pos) < 0.5:
			continue
		spd["x"] = snapped_sp.x
		spd["y"] = snapped_sp.y
		spawn_moved += 1
	if spawn_moved > 0 and _map_view != null:
		_map_view._rebuild_spawn_markers(map_data)

	var total_moved: int = moved_entries.size() + player_moved + spawn_moved
	if total_moved == 0:
		_set_status("All tokens already on grid")
		return

	# Extend the compound undo command with player + spawn state.
	if registry.history != null:
		var old_pp: Dictionary = old_player_positions.duplicate()
		var old_sp: Array = old_spawn_points.duplicate(true)
		var new_sp: Array = map_data.spawn_points.duplicate(true)
		var gs_ref: GameStateManager = registry.game_state
		var mv2 := _map_view
		var map_ref: MapData = map_data
		var backend_ref: BackendRuntime = _backend
		if player_moved > 0 or spawn_moved > 0:
			registry.history.push_command(HistoryCommand.create(
				"Snap players/spawns to grid",
				func():
					if gs_ref != null:
						var dtoks: Dictionary = backend_ref.get_dm_token_nodes() if backend_ref != null else {}
						for pid2: Variant in old_pp.keys():
							var restore_pos: Vector2 = old_pp[pid2] as Vector2
							gs_ref.set_position(pid2, restore_pos)
							var spr: Node2D = dtoks.get(pid2, null) as Node2D
							if spr != null and is_instance_valid(spr):
								spr.global_position = restore_pos
						_broadcast_player_state()
					if map_ref != null:
						map_ref.spawn_points = old_sp.duplicate(true)
						if mv2 != null:
							mv2._rebuild_spawn_markers(map_ref),
				func():
					if gs_ref != null:
						var dtoks: Dictionary = backend_ref.get_dm_token_nodes() if backend_ref != null else {}
						for pid2: Variant in old_pp.keys():
							var new_pos: Vector2 = GridSnap.snap_to_grid(old_pp[pid2] as Vector2, map_ref)
							gs_ref.set_position(pid2, new_pos)
							var spr: Node2D = dtoks.get(pid2, null) as Node2D
							if spr != null and is_instance_valid(spr):
								spr.global_position = new_pos
						_broadcast_player_state()
					if map_ref != null:
						map_ref.spawn_points = new_sp.duplicate(true)
						if mv2 != null:
							mv2._rebuild_spawn_markers(map_ref)))

	var parts: PackedStringArray = PackedStringArray()
	if moved_entries.size() > 0:
		parts.append("%d token(s)" % moved_entries.size())
	if player_moved > 0:
		parts.append("%d player(s)" % player_moved)
	if spawn_moved > 0:
		parts.append("%d spawn(s)" % spawn_moved)
	_set_status("Snapped %s to grid" % ", ".join(parts))


## Populate the transient statblock_display dict on a TokenData based on its
## visibility level and attached statblock references.  The dict travels in the
## network message so the player display can render name / AC / HP / full info.
func _inject_statblock_display(data: TokenData, registry: ServiceRegistry) -> void:
	data.statblock_display = {}
	if data.statblock_visibility == "none" or data.statblock_refs.is_empty():
		return
	if registry == null:
		return
	var sb_id: String = str(data.statblock_refs[0])
	var sb: StatblockData = _resolve_statblock(sb_id, registry)
	if sb == null:
		return
	# Apply overrides for runtime HP, etc.
	var ovr_raw: Variant = data.statblock_overrides.get(sb_id, null)
	var so: StatblockOverride = null
	if ovr_raw is Dictionary:
		so = StatblockOverride.from_dict(ovr_raw as Dictionary)
	# Name level — just creature name and type.
	var display: Dictionary = {
		"name": sb.name,
		"creature_type": sb.creature_type,
		"size": sb.size,
	}
	if data.statblock_visibility == "name":
		data.statblock_display = display
		return
	# Partial — add AC, HP, CR.
	var ac_val: int = 0
	if sb.armor_class.size() > 0:
		var ac_entry: Variant = sb.armor_class[0]
		if ac_entry is Dictionary:
			ac_val = int((ac_entry as Dictionary).get("value", 0))
		elif ac_entry is float or ac_entry is int:
			ac_val = int(ac_entry)
	display["ac"] = ac_val
	display["cr"] = sb.challenge_rating
	if so != null and so.max_hp > 0:
		display["hp_current"] = so.current_hp
		display["hp_max"] = so.max_hp
		display["temp_hp"] = so.temp_hp
	else:
		display["hp_current"] = sb.hit_points
		display["hp_max"] = sb.hit_points
		display["temp_hp"] = 0
	if data.statblock_visibility == "partial":
		data.statblock_display = display
		return
	# Full — include everything the player might want.
	display["alignment"] = sb.alignment
	display["speed"] = sb.speed
	display["str"] = sb.strength
	display["dex"] = sb.dexterity
	display["con"] = sb.constitution
	display["int"] = sb.intelligence
	display["wis"] = sb.wisdom
	display["cha"] = sb.charisma
	display["damage_resistances"] = sb.damage_resistances
	display["damage_immunities"] = sb.damage_immunities
	display["condition_immunities"] = sb.condition_immunities
	display["senses"] = sb.senses
	display["languages"] = sb.languages
	if so != null:
		display["conditions"] = so.conditions
	data.statblock_display = display


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
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	_inject_statblock_display(data, reg)
	var msg_type: String = "token_added" if is_new else "token_updated"
	var token_dict: Dictionary = data.to_dict()
	# Attach inline base64 icon for the player display.
	if not data.icon_image_path.is_empty():
		token_dict["icon_image_b64"] = TokenIconUtils.encode_icon_to_b64(data.icon_image_path)
	_nm_broadcast_to_displays({"msg": msg_type, "token": token_dict,
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
	# Capture old extra_value from the service store before applying the update.
	var old_md: MeasurementData = registry.measurement.get_by_id(data.id)
	var old_extra: float = old_md.extra_value if old_md != null else data.extra_value
	var new_snapshot: Dictionary = data.to_dict()
	_meas_apply_update(data)
	if registry.history != null:
		var old_data: MeasurementData = MeasurementData.from_dict(new_snapshot)
		old_data.world_start = old_start
		old_data.world_end = old_end
		old_data.extra_value = old_extra
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
	_select_measure_shape_by_id(data.id)
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
# Magic effect helpers
# ---------------------------------------------------------------------------

## Broadcast full effect state snapshot to all connected displays.
func _broadcast_effect_state() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	var all_e: Array = registry.effect.get_all()
	var dicts: Array = []
	for raw in all_e:
		var ed: EffectData = raw as EffectData
		if ed != null:
			dicts.append(ed.to_dict())
	_nm_broadcast_to_displays({"msg": "effect_state", "effects": dicts})


## Called when the DM clicks on the map with the PLACE_EFFECT tool active.
func _on_effect_place_requested(world_pos: Vector2) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	var size_px: float = _effect_panel.get_effect_size() if _effect_panel != null else 128.0
	var def_id: String = _effect_panel.get_selected_effect_definition_id() if _effect_panel != null else ""
	var data: EffectData
	if not def_id.is_empty() and registry.effect.is_manifest_loaded():
		# Manifest-driven (Phase 11): instantiate a scene effect.
		var def: EffectDefinition = registry.effect.get_definition(def_id)
		data = EffectData.create(0, world_pos, size_px, -1.0)
		data.scene_effect_id = def_id
		if def != null:
			data.scene_path = def.scene_path
			if def.mode == EffectDefinition.Mode.ONE_SHOT:
				data.duration_sec = 3.0 ## Scene handles its own timing; this marks it as transient.
	else:
		# Legacy shader path.
		var eff_type: int = _effect_panel.get_selected_effect_type() if _effect_panel != null else 0
		var shape: int = _effect_panel.get_selected_shape() if _effect_panel != null else 0
		data = EffectData.create(eff_type, world_pos, size_px, -1.0)
		data.shape = shape
		data.palette = _effect_panel.get_selected_palette() if _effect_panel != null else 0
	var snapshot: Dictionary = data.to_dict()
	var id: String = data.id
	_effect_apply_add(data)
	if registry.history != null:
		var cmd := HistoryCommand.create("Spawn effect",
			func() -> void: _effect_apply_remove(id),
			func() -> void: _effect_apply_add(EffectData.from_dict(snapshot)))
		registry.history.push_command(cmd)


## Called when the DM click-drags on the map to define a shaped effect.
func _on_effect_shape_place_requested(world_pos: Vector2, world_end: Vector2, shape: int) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	var eff_type: int = _effect_panel.get_selected_effect_type() if _effect_panel != null else 0
	var size_px: float = _effect_panel.get_effect_size() if _effect_panel != null else 128.0
	var data: EffectData = EffectData.create(eff_type, world_pos, size_px, -1.0)
	data.shape = shape
	data.world_end = world_end
	data.palette = _effect_panel.get_selected_palette() if _effect_panel != null else 0
	# For CIRCLE, size_px = diameter from drag distance; rotation = drag direction
	if shape == EffectData.EffectShape.CIRCLE:
		data.size_px = world_pos.distance_to(world_end) * 2.0
		var drag_dir: Vector2 = world_end - world_pos
		if drag_dir.length() > 1.0:
			data.rotation_deg = rad_to_deg(drag_dir.angle() + PI * 0.5)
	var snapshot: Dictionary = data.to_dict()
	var id: String = data.id
	_effect_apply_add(data)
	if registry.history != null:
		var cmd := HistoryCommand.create("Spawn effect",
			func() -> void: _effect_apply_remove(id),
			func() -> void: _effect_apply_add(EffectData.from_dict(snapshot)))
		registry.history.push_command(cmd)


func _effect_apply_add(data: EffectData) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	registry.effect.spawn(data)
	if _map_view != null:
		_map_view.add_effect_node(data)
	_nm_broadcast_to_displays({"msg": "effect_spawn", "effect": data.to_dict()})
	_mark_map_dirty_effects()


func _effect_apply_remove(id: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.effect == null:
		return
	registry.effect.remove(id)
	if _map_view != null:
		_map_view.remove_effect_node(id)
	_nm_broadcast_to_displays({"msg": "effect_remove", "effect_id": id})
	_mark_map_dirty_effects()


func _mark_map_dirty_effects() -> void:
	## Flush effects into MapData so the next save includes them.
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.map == null:
		return
	var map: MapData = registry.map.get_map() as MapData
	if map == null:
		return
	var all_e: Array = []
	if registry.effect != null:
		for raw in registry.effect.get_all():
			var ed: EffectData = raw as EffectData
			if ed != null:
				all_e.append(ed.to_dict())
	map.effects = all_e


# ---------------------------------------------------------------------------
# Background audio volume window
# ---------------------------------------------------------------------------

func _open_statblock_library() -> void:
	if _statblock_library != null and is_instance_valid(_statblock_library):
		_statblock_library.show()
		_statblock_library.grab_focus()
		return
	_statblock_library = StatblockLibrary.new()
	add_child(_statblock_library)
	_apply_dialog_themes()
	_statblock_library.popup_centered()
	_statblock_library.grab_focus()


func _open_item_library() -> void:
	if _item_library != null and is_instance_valid(_item_library):
		_item_library.show()
		_item_library.grab_focus()
		return
	_item_library = ItemLibrary.new()
	add_child(_item_library)
	_apply_dialog_themes()
	_item_library.popup_centered()
	_item_library.grab_focus()


# ---------------------------------------------------------------------------

func _open_volume_window() -> void:
	if _volume_window != null and is_instance_valid(_volume_window):
		_volume_window.show()
		_volume_window.grab_focus()
		return
	_volume_window = Window.new()
	_volume_window.title = "Background Audio"
	_volume_window.transient = true
	_volume_window.popup_window = false
	_volume_window.exclusive = false
	_volume_window.close_requested.connect(func() -> void:
		if _volume_window != null: _volume_window.hide())
	add_child(_volume_window)

	var mgr := _get_ui_scale_mgr()
	var margin := MarginContainer.new()
	var m: int = mgr.scaled(10.0) if mgr != null else 10
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, m)

	_volume_vbox = VBoxContainer.new()
	_volume_vbox.add_theme_constant_override("separation", 8)

	_volume_label = Label.new()
	_volume_label.text = "Volume"
	_volume_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_volume_vbox.add_child(_volume_label)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 100.0
	_volume_slider.value = 100.0
	_volume_slider.step = 1.0
	_volume_slider.custom_minimum_size = Vector2(180, 20)
	_volume_slider.value_changed.connect(_on_volume_slider_changed)
	_volume_vbox.add_child(_volume_slider)

	_volume_mute_btn = CheckButton.new()
	_volume_mute_btn.text = "Mute"
	_volume_mute_btn.toggled.connect(_on_volume_mute_toggled)
	_volume_vbox.add_child(_volume_mute_btn)

	margin.add_child(_volume_vbox)
	_volume_window.add_child(margin)

	# Sync slider to current map volume.
	var map: MapData = _map()
	if map != null:
		_volume_slider.value = _db_to_linear_pct(map.audio_volume_db)

	# Theme + size
	var _vw_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _vw_reg != null and _vw_reg.ui_theme != null:
		_vw_reg.ui_theme.theme_control_tree(_volume_window, _ui_scale())
	if mgr != null:
		mgr.popup_fitted(_volume_window, 220.0, 160.0)
	else:
		_volume_window.popup_centered()
		_volume_window.grab_focus()


func _on_volume_slider_changed(value: float) -> void:
	var db: float = _linear_pct_to_db(value)
	if _map_view != null:
		_map_view.set_audio_volume_db(db)
	var map: MapData = _map()
	if map != null:
		map.audio_volume_db = db
	_nm_broadcast_to_displays({"msg": "audio_volume", "volume_db": db})
	_update_volume_label()


func _on_volume_mute_toggled(muted: bool) -> void:
	if _volume_slider != null:
		_volume_slider.editable = not muted
	var db: float = -80.0 if muted else _linear_pct_to_db(_volume_slider.value if _volume_slider != null else 100.0)
	if _map_view != null:
		_map_view.set_audio_volume_db(db)
	var map: MapData = _map()
	if map != null and not muted:
		map.audio_volume_db = db
	_nm_broadcast_to_displays({"msg": "audio_volume", "volume_db": db})
	_update_volume_label()


func _update_volume_label() -> void:
	if _volume_label == null:
		return
	if _volume_mute_btn != null and _volume_mute_btn.button_pressed:
		_volume_label.text = "Volume: Muted"
	elif _volume_slider != null:
		_volume_label.text = "Volume: %d%%" % int(_volume_slider.value)
	else:
		_volume_label.text = "Volume"


static func _linear_pct_to_db(pct: float) -> float:
	## Convert a 0-100 linear percentage to decibels.
	if pct <= 0.0:
		return -80.0
	return 20.0 * log(pct / 100.0) / log(10.0)


static func _db_to_linear_pct(db: float) -> float:
	## Convert decibels to a 0-100 linear percentage.
	if db <= -80.0:
		return 0.0
	return 100.0 * pow(10.0, db / 20.0)


# ---------------------------------------------------------------------------
# Measurement panel
# ---------------------------------------------------------------------------

func _close_measure_panel() -> void:
	if _map_view != null:
		_map_view._set_active_tool(_map_view.Tool.SELECT)
	if _measure_panel != null:
		_measure_panel.hide()
	_set_view_checked(26, false)


func _open_measure_panel() -> void:
	if _measure_panel != null:
		_measure_panel.show()
		_apply_measure_panel_size()
		_set_view_checked(26, true)


func _build_measure_panel() -> void:
	var scale := _ui_scale()

	_measure_panel = PanelContainer.new()
	_measure_panel.name = "MeasurePanel"
	_measure_panel.visible = false
	_measure_panel.anchor_left = 1.0
	_measure_panel.anchor_right = 1.0
	_measure_panel.anchor_top = 0.0
	_measure_panel.anchor_bottom = 1.0
	_measure_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_ui_content_area.add_child(_measure_panel)

	var mp_margin := MarginContainer.new()
	mp_margin.add_theme_constant_override("margin_left", 4)
	mp_margin.add_theme_constant_override("margin_right", 4)
	mp_margin.add_theme_constant_override("margin_top", 4)
	mp_margin.add_theme_constant_override("margin_bottom", 4)
	_measure_panel.add_child(mp_margin)

	_measure_vbox = VBoxContainer.new()
	_measure_vbox.add_theme_constant_override("separation", 2)
	mp_margin.add_child(_measure_vbox)

	_measure_undock_btn = Button.new()
	_measure_undock_btn.text = "⇲"
	_measure_undock_btn.focus_mode = Control.FOCUS_NONE
	_measure_undock_btn.tooltip_text = "Detach / re-dock measurement panel"
	_measure_undock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_measure_undock_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_measure_undock_btn.custom_minimum_size = Vector2(0, roundi(22.0 * scale))
	_measure_undock_btn.add_theme_font_size_override("font_size", roundi(14.0 * scale))
	_measure_undock_btn.pressed.connect(_on_measure_undock_btn_pressed)
	_measure_vbox.add_child(_measure_undock_btn)

	_measure_vbox.add_child(HSeparator.new())

	_measure_panel_title = Label.new()
	_measure_panel_title.text = "Measurement Tools"
	_measure_panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_measure_panel_title.add_theme_font_size_override("font_size", roundi(15.0 * scale))
	_measure_vbox.add_child(_measure_panel_title)

	_measure_vbox.add_child(HSeparator.new())

	# Tool buttons
	var title_lbl := Label.new()
	title_lbl.text = "Draw Tool"
	_measure_vbox.add_child(title_lbl)

	_measure_tool_group = ButtonGroup.new()
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", roundi(4.0 * scale))
	_measure_vbox.add_child(btn_row)

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
		btn.custom_minimum_size = Vector2(roundi(34.0 * scale), roundi(34.0 * scale))
		btn.add_theme_font_size_override("font_size", roundi(18.0 * scale))
		var k := key # capture
		btn.pressed.connect(func(): _on_measure_tool_btn_pressed(k))
		btn_row.add_child(btn)

	_measure_vbox.add_child(HSeparator.new())

	# Active shapes list
	var shapes_lbl := Label.new()
	shapes_lbl.text = "Active shapes"
	_measure_vbox.add_child(shapes_lbl)

	_measure_shape_list = ItemList.new()
	_measure_shape_list.custom_minimum_size = Vector2(0, roundi(140.0 * scale))
	_measure_shape_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_measure_shape_list.focus_mode = Control.FOCUS_NONE
	_measure_shape_list.item_selected.connect(_on_measure_shape_selected)
	_measure_vbox.add_child(_measure_shape_list)
	_refresh_measure_shape_list()

	# Action buttons row
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", roundi(6.0 * scale))
	_measure_vbox.add_child(action_row)

	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.focus_mode = Control.FOCUS_NONE
	del_btn.custom_minimum_size = Vector2(0, roundi(28.0 * scale))
	del_btn.pressed.connect(_on_measure_delete_selected_pressed)
	action_row.add_child(del_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear All"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.custom_minimum_size = Vector2(0, roundi(28.0 * scale))
	clear_btn.pressed.connect(_on_measure_clear_all_pressed)
	action_row.add_child(clear_btn)

	# AoE / Save section
	_measure_vbox.add_child(HSeparator.new())

	var save_btn := Button.new()
	save_btn.text = "Call for Save"
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.custom_minimum_size = Vector2(0, roundi(28.0 * scale))
	save_btn.pressed.connect(_on_measure_call_for_save_pressed)
	_measure_vbox.add_child(save_btn)

	_apply_measure_panel_size()


func _apply_measure_panel_size() -> void:
	if _measure_panel == null:
		return
	var scale := _ui_scale()
	var panel_w := roundi(200.0 * scale)
	var freeze_w := roundi(200.0 * scale) if (_freeze_panel != null and _freeze_panel.visible and not _freeze_panel_floating) else 0
	# Derive effect width from the offsets already set by _apply_effect_panel_size
	# so we always match the effect panel's actual rendered width regardless of content.
	var effect_w: int = 0
	if _effect_panel != null and _effect_panel.visible and not _effect_panel_floating:
		effect_w = roundi(_effect_panel.offset_right - _effect_panel.offset_left)
	var right_offset: int = freeze_w + effect_w
	_measure_panel.offset_left = float(- (panel_w + right_offset))
	_measure_panel.offset_right = float(-right_offset)
	_measure_panel.offset_top = _menu_bar_screen_height()
	_measure_panel.offset_bottom = 0.0


func _on_measure_undock_btn_pressed() -> void:
	if _measure_panel_floating:
		_dock_measure_panel()
	else:
		_undock_measure_panel()


func _undock_measure_panel() -> void:
	if _measure_panel_floating or _measure_panel == null:
		return
	_measure_panel_floating = true
	if _measure_undock_btn:
		_measure_undock_btn.text = "⇱"
		_measure_undock_btn.tooltip_text = "Re-dock measurement panel"
	if _measure_panel_title != null:
		_measure_panel_title.hide()

	_measure_panel_window = Window.new()
	_measure_panel_window.title = "Measurement Tools"
	_measure_panel_window.transient = true
	_measure_panel_window.popup_window = false
	_measure_panel_window.exclusive = false
	add_child(_measure_panel_window)

	var old_parent := _measure_panel.get_parent()
	if old_parent:
		old_parent.remove_child(_measure_panel)
	_measure_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_measure_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_measure_panel_window.add_child(_measure_panel)
	_measure_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_measure_panel.offset_left = 0.0
	_measure_panel.offset_right = 0.0
	_measure_panel.offset_top = 0.0
	_measure_panel.offset_bottom = 0.0

	_measure_panel_window.close_requested.connect(_close_floating_measure_panel)
	var _mw_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _mw_reg != null and _mw_reg.ui_theme != null:
		_mw_reg.ui_theme.theme_control_tree(_measure_panel_window, _ui_scale())
	var _mm := _get_ui_scale_mgr()
	if _mm != null:
		_mm.popup_fitted(_measure_panel_window, 220.0, 420.0)
	else:
		_measure_panel_window.popup_centered()
		_measure_panel_window.grab_focus()

	_set_view_checked(26, true)


func _dock_measure_panel() -> void:
	if not _measure_panel_floating or _measure_panel == null:
		return
	_measure_panel_floating = false
	if _measure_undock_btn:
		_measure_undock_btn.text = "⇲"
		_measure_undock_btn.tooltip_text = "Detach / re-dock measurement panel"

	if _measure_panel_window:
		_measure_panel_window.remove_child(_measure_panel)

	_measure_panel.anchor_left = 1.0
	_measure_panel.anchor_right = 1.0
	_measure_panel.anchor_top = 0.0
	_measure_panel.anchor_bottom = 1.0
	_measure_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	if _ui_content_area != null:
		_ui_content_area.add_child(_measure_panel)
		_apply_measure_panel_size()

	if _measure_panel_title != null:
		_measure_panel_title.show()

	if _measure_panel_window:
		_measure_panel_window.queue_free()
		_measure_panel_window = null

	_set_view_checked(26, true)


func _close_floating_measure_panel() -> void:
	_dock_measure_panel()
	if _measure_panel != null:
		_measure_panel.visible = false
	_set_view_checked(26, false)


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
	if not _map_view.is_connected("measurement_selected",
			Callable(self , "_on_measurement_selected_on_map")):
		_map_view.measurement_selected.connect(_on_measurement_selected_on_map)


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


func _on_measurement_selected_on_map(meas_id: String) -> void:
	_select_measure_shape_by_id(meas_id)


func _select_measure_shape_by_id(meas_id: String) -> void:
	if _measure_shape_list == null:
		return
	for i: int in _measure_shape_list.item_count:
		if str(_measure_shape_list.get_item_metadata(i)) == meas_id:
			_measure_shape_list.select(i)
			_measure_shape_list.ensure_current_is_visible()
			return


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
	# Preserve the currently selected ID across rebuild.
	var prev_selected_id: String = ""
	var prev_sel: PackedInt32Array = _measure_shape_list.get_selected_items()
	if not prev_sel.is_empty():
		prev_selected_id = str(_measure_shape_list.get_item_metadata(prev_sel[0]))
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
	# Restore selection if the previously selected item still exists.
	if not prev_selected_id.is_empty():
		_select_measure_shape_by_id(prev_selected_id)


# ---------------------------------------------------------------------------
# AoE / Saving throw workflow
# ---------------------------------------------------------------------------

## "Call for Save" button on the measurement panel — uses the selected shape.
func _on_measure_call_for_save_pressed() -> void:
	if _measure_shape_list == null:
		return
	var selected_items: PackedInt32Array = _measure_shape_list.get_selected_items()
	if selected_items.is_empty():
		_set_status("Select a measurement shape first.")
		return
	var shape_id: String = str(_measure_shape_list.get_item_metadata(selected_items[0]))
	if shape_id.is_empty():
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.measurement == null:
		return
	var md: MeasurementData = registry.measurement.get_by_id(shape_id)
	if md == null:
		return
	# Find tokens inside the shape.
	if _map_view == null:
		return
	var token_ids: Array[String] = _map_view.get_tokens_in_measurement(md)
	# Filter to creature tokens only (monsters, NPCs, and player tokens).
	var tm := _token_manager()
	if tm != null:
		var filtered: Array[String] = []
		for tid: String in token_ids:
			var td: TokenData = tm.get_token_by_id(tid)
			if td != null and (td.category == TokenData.TokenCategory.MONSTER or td.category == TokenData.TokenCategory.NPC or td.category == TokenData.TokenCategory.GENERIC):
				filtered.append(tid)
		token_ids = filtered
	if token_ids.is_empty():
		_set_status("No creature tokens inside the selected shape.")
		return
	# Store the measurement id and open the save config dialog.
	_pending_save_measurement_id = md.id
	_open_save_config_dialog(token_ids)


## Opens a small popup to choose save ability + DC before rolling.
func _open_save_config_dialog(token_ids: Array[String]) -> void:
	if _save_config_dialog != null and is_instance_valid(_save_config_dialog):
		_save_config_dialog.queue_free()
	_save_config_dialog = Window.new()
	_save_config_dialog.title = "Configure Saving Throw"
	_save_config_dialog.transient = true
	_save_config_dialog.exclusive = true
	_save_config_dialog.close_requested.connect(func() -> void:
		_save_config_dialog.hide())
	add_child(_save_config_dialog)

	var mgr := _get_ui_scale_mgr()
	var margin := MarginContainer.new()
	var m: int = mgr.scaled(12.0) if mgr != null else 12
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, m)
	_save_config_dialog.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", mgr.scaled(8.0) if mgr != null else 8)
	margin.add_child(vbox)

	# Token count info
	var info_lbl := Label.new()
	info_lbl.text = "%d token(s) in area" % token_ids.size()
	vbox.add_child(info_lbl)

	# Ability selector
	var ab_row := HBoxContainer.new()
	ab_row.add_theme_constant_override("separation", mgr.scaled(6.0) if mgr != null else 6)
	vbox.add_child(ab_row)
	var ab_lbl := Label.new()
	ab_lbl.text = "Ability:"
	ab_row.add_child(ab_lbl)
	var ability_option := OptionButton.new()
	for ab: String in ["STR", "DEX", "CON", "INT", "WIS", "CHA"]:
		ability_option.add_item(ab)
	ability_option.selected = 1 # Default to DEX (most common AoE save)
	ability_option.custom_minimum_size.x = float(mgr.scaled(100.0)) if mgr != null else 100.0
	ab_row.add_child(ability_option)

	# DC spinner
	var dc_row := HBoxContainer.new()
	dc_row.add_theme_constant_override("separation", mgr.scaled(6.0) if mgr != null else 6)
	vbox.add_child(dc_row)
	var dc_lbl := Label.new()
	dc_lbl.text = "DC:"
	dc_row.add_child(dc_lbl)
	var dc_spin := SpinBox.new()
	dc_spin.min_value = 1
	dc_spin.max_value = 30
	dc_spin.value = 15
	dc_spin.custom_minimum_size.x = float(mgr.scaled(80.0)) if mgr != null else 80.0
	dc_row.add_child(dc_spin)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", mgr.scaled(8.0) if mgr != null else 8)
	vbox.add_child(btn_row)
	var roll_btn := Button.new()
	roll_btn.text = "Roll Saves"
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	if mgr != null:
		mgr.scale_button(roll_btn)
		mgr.scale_button(cancel_btn)

	# Capture references for the lambda.
	var tids: Array[String] = token_ids
	var ab_opt := ability_option
	var dc_sp := dc_spin
	roll_btn.pressed.connect(func() -> void:
		var abilities: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]
		var idx: int = ab_opt.selected
		var ability: String = abilities[idx] if idx >= 0 and idx < abilities.size() else "dex"
		var dc: int = int(dc_sp.value)
		_save_config_dialog.hide()
		_execute_save_for_tokens(ability, dc, tids))
	cancel_btn.pressed.connect(func() -> void:
		_save_config_dialog.hide()
		_pending_save_measurement_id = "")
	btn_row.add_child(roll_btn)
	btn_row.add_child(cancel_btn)

	# Theme, font scaling, and show.
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(_save_config_dialog, _ui_scale())
	if mgr != null:
		mgr.scale_control_fonts(margin)
		mgr.popup_fitted(_save_config_dialog, 260.0, 200.0)
	else:
		_save_config_dialog.popup_centered()
		_save_config_dialog.grab_focus()


## Rolls saves for the given tokens and opens the results panel.
func _execute_save_for_tokens(ability: String, dc: int,
		token_ids: Array[String]) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.combat == null:
		return
	var results: Array = registry.combat.call_for_save(ability, dc, token_ids)
	if results.is_empty():
		_set_status("No save results (tokens may lack statblocks).")
		return
	_open_save_results_panel(ability, dc, results)


## Creates / shows the save results panel.
func _open_save_results_panel(ability: String, dc: int, results: Array) -> void:
	if _save_results_panel == null:
		_save_results_panel = SaveResultsPanel.new()
		add_child(_save_results_panel)
		_save_results_panel.apply_damage_to_results.connect(
			_on_save_results_apply_damage)
		var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg != null and reg.ui_theme != null:
			reg.ui_theme.theme_control_tree(_save_results_panel, _ui_scale())
		_save_results_panel.apply_scale(_ui_scale())
	_save_results_panel.show_results(ability, dc, results)
	# Broadcast save event to player displays for optional notification.
	_nm_broadcast_to_displays({"msg": "save_called",
		"ability": ability.to_upper(), "dc": dc,
		"token_count": results.size()})


## Applies damage from the save results panel to affected tokens.
func _on_save_results_apply_damage(results: Array, damage_amount: int,
		damage_type: String, half_on_pass: bool) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.combat == null:
		return
	var total_applied: int = 0
	var count: int = 0
	for r: Dictionary in results:
		var tid: String = str(r.get("token_id", ""))
		if tid.is_empty():
			continue
		var passed: bool = bool(r.get("passed", false))
		var amount: int = 0
		if passed and half_on_pass:
			amount = int(floor(damage_amount / 2.0))
		elif not passed:
			amount = damage_amount
		else:
			continue # passed and not half_on_pass — no damage
		if amount <= 0:
			continue
		var result: Dictionary = registry.combat.apply_damage(tid, amount, damage_type)
		total_applied += int(result.get("actual_damage", 0))
		count += 1
	_set_status("Applied damage to %d token(s), total: %d HP" % [count, total_applied])
	# Optionally create an AoE record linking to the measurement.
	if not _pending_save_measurement_id.is_empty():
		_pending_save_measurement_id = ""


func _broadcast_token_state() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var visible: Array = registry.token.get_visible_tokens()
	var dicts: Array = []
	for raw in visible:
		var td: TokenData = raw as TokenData
		if td != null:
			_inject_statblock_display(td, registry)
			var d: Dictionary = td.to_dict()
			dicts.append(d)
	# Include non-visible DOOR and SECRET_PASSAGE tokens so the player display
	# can rebuild wall/passthrough geometry even for tokens the player can't see.
	for raw in registry.token.get_all_tokens():
		var td: TokenData = raw as TokenData
		if td == null or td.is_visible_to_players:
			continue
		if td.category == TokenData.TokenCategory.DOOR \
				or td.category == TokenData.TokenCategory.SECRET_PASSAGE:
			var d: Dictionary = td.to_dict()
			dicts.append(d)
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


# ---------------------------------------------------------------------------
# Autopause — runs every frame for reliable swept-path collision detection.
# ---------------------------------------------------------------------------

func _run_autopause_check() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null:
		return
	var gs: GameStateManager = _game_state()
	if gs == null or _backend == null:
		return

	var prev_positions: Array = []
	var curr_positions: Array = []
	var player_ids: Array = []
	var token_nodes: Dictionary = _backend.get_dm_token_nodes()
	for pid in token_nodes.keys():
		var node: Node2D = token_nodes[pid] as Node2D
		if node == null or not is_instance_valid(node):
			continue
		var pid_s: String = str(pid)
		var curr: Vector2 = node.global_position
		var prev: Vector2 = _prev_player_positions.get(pid_s, curr) as Vector2
		prev_positions.append(prev)
		curr_positions.append(curr)
		player_ids.append(pid_s)
		_prev_player_positions[pid_s] = curr

	if curr_positions.is_empty():
		return

	var player_radius: float = _pixels_per_5ft_current() * 0.5
	var result: Dictionary = registry.token.check_autopause_collision(
			prev_positions, curr_positions, player_ids, player_radius)
	var paused_ids: Array = result.get("player_ids", []) as Array
	var revealed_ids: Array = result.get("revealed_token_ids", []) as Array
	# Broadcast trap reveals triggered by collision (trap sprung).
	for tid in revealed_ids:
		_on_token_visibility_changed(str(tid), true)
	if paused_ids.is_empty() and revealed_ids.is_empty():
		return
	for pid in paused_ids:
		var pid_s: String = str(pid)
		if _autopause_locked_ids.has(pid_s):
			continue
		_autopause_locked_ids[pid_s] = true
		gs.lock_player(pid_s)
		_set_status("Autopause — %s paused by proximity trigger" % pid_s)
	_broadcast_player_state()


# ---------------------------------------------------------------------------
# Perception / detection — runs on a timer (_PERCEPTION_CHECK_INTERVAL).
# ---------------------------------------------------------------------------

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
# File — Statblock Import / Export
# ---------------------------------------------------------------------------

func _on_export_statblocks() -> void:
	if _statblocks_export_dialog != null:
		_statblocks_export_dialog.popup_centered(Vector2i(900, 600))


func _on_import_statblocks() -> void:
	if _statblocks_import_dialog != null:
		_statblocks_import_dialog.popup_centered(Vector2i(900, 600))


func _on_statblocks_export_path_selected(path: String) -> void:
	var target_path := path
	if not target_path.to_lower().ends_with(".json"):
		target_path += ".json"
	var parent_dir := target_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_dir):
		var mk_err := DirAccess.make_dir_recursive_absolute(parent_dir)
		if mk_err != OK:
			_set_status("Export failed: could not create directory.")
			return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.statblock == null:
		_set_status("Export failed: statblock service unavailable.")
		return
	var all_sb: Array = registry.statblock.get_all_by_scope("global")
	var out: Array = []
	for entry: Variant in all_sb:
		if entry is StatblockData:
			out.append((entry as StatblockData).to_dict())
	if out.is_empty():
		_set_status("Export skipped: no custom statblocks to export.")
		return
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_set_status("Export failed: could not write file.")
		return
	file.store_string(JSON.stringify(out, "\t"))
	file.close()
	_set_status("Exported %d statblocks." % out.size())


func _on_statblocks_import_path_selected(path: String) -> void:
	if not FileAccess.file_exists(path):
		_set_status("Import failed: file not found.")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("Import failed: could not read file.")
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JsonUtilsScript.parse_json_text(text)
	if parsed == null or not parsed is Array:
		_set_status("Import failed: JSON must be an array of statblocks.")
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.statblock == null:
		_set_status("Import failed: statblock service unavailable.")
		return
	var count: int = 0
	for item: Variant in parsed:
		if not item is Dictionary:
			continue
		var sb := StatblockData.from_dict(item as Dictionary)
		if sb.id.is_empty():
			sb.id = StatblockData.generate_id()
		sb.source = "custom"
		registry.statblock.add_statblock(sb, "global")
		count += 1
	if count == 0:
		_set_status("Import skipped: no valid statblocks found.")
		return
	_set_status("Imported %d statblocks." % count)


# ---------------------------------------------------------------------------
# File — Campaign Import / Export
# ---------------------------------------------------------------------------

func _on_export_campaign() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null:
		_set_status("No campaign service available.")
		return
	var camp: CampaignData = registry.campaign.get_active_campaign()
	if camp == null:
		_set_status("No active campaign to export.")
		return
	if _campaign_export_dialog != null:
		_campaign_export_dialog.popup_centered(Vector2i(900, 600))


func _on_import_campaign() -> void:
	if _campaign_import_dialog != null:
		_campaign_import_dialog.popup_centered(Vector2i(900, 600))


func _on_campaign_export_path_selected(path: String) -> void:
	var target_path := path
	if not target_path.to_lower().ends_with(".json"):
		target_path += ".json"
	var parent_dir := target_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent_dir):
		var mk_err := DirAccess.make_dir_recursive_absolute(parent_dir)
		if mk_err != OK:
			_set_status("Export failed: could not create directory.")
			return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null:
		_set_status("Export failed: campaign service unavailable.")
		return
	var camp: CampaignData = registry.campaign.get_active_campaign()
	if camp == null:
		_set_status("Export failed: no active campaign.")
		return
	registry.campaign.save_campaign()
	var file := FileAccess.open(target_path, FileAccess.WRITE)
	if file == null:
		_set_status("Export failed: could not write file.")
		return
	file.store_string(JSON.stringify(camp.to_dict(), "\t"))
	file.close()
	_set_status("Exported campaign \"%s\"." % camp.name)


func _on_campaign_import_path_selected(path: String) -> void:
	if not FileAccess.file_exists(path):
		_set_status("Import failed: file not found.")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("Import failed: could not read file.")
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JsonUtilsScript.parse_json_text(text)
	if parsed == null or not parsed is Dictionary:
		_set_status("Import failed: JSON must be a campaign object.")
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null:
		_set_status("Import failed: campaign service unavailable.")
		return
	# Save current campaign before replacing
	if registry.campaign.get_active_campaign() != null:
		registry.campaign.save_campaign()
	var camp := CampaignData.from_dict(parsed as Dictionary)
	# Give it a fresh ID to avoid collision with existing campaigns
	if camp.id.is_empty():
		camp.generate_id()
	var new_camp: CampaignData = registry.campaign.new_campaign(camp.name, camp.default_ruleset)
	# Merge imported data into newly created campaign
	new_camp.description = camp.description
	new_camp.bestiary = camp.bestiary
	new_camp.character_ids = camp.character_ids
	new_camp.spell_library = camp.spell_library
	new_camp.item_library = camp.item_library
	new_camp.notes = camp.notes
	new_camp.note_folders = camp.note_folders
	new_camp.images = camp.images
	new_camp.image_folders = camp.image_folders
	new_camp.settings = camp.settings
	registry.campaign.save_campaign()
	_set_status("Imported campaign \"%s\"." % new_camp.name)


# ---------------------------------------------------------------------------
# File — SRD Update Check
# ---------------------------------------------------------------------------

const SRD_VERSION_URL: String = "https://raw.githubusercontent.com/5e-bits/5e-database/main/package.json"

func _on_check_srd_updates() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.srd == null:
		_set_status("SRD service unavailable.")
		return
	_set_status("Checking for SRD updates…")
	# Signal subscription: ISRDLibraryService extends Node; signals live on the
	# Node instance. RefCounted manager cannot re-emit them — approved narrow exception.
	var svc: ISRDLibraryService = registry.srd.service
	if not svc.update_check_completed.is_connected(_on_srd_update_check_result):
		svc.update_check_completed.connect(_on_srd_update_check_result)
	registry.srd.check_for_updates(SRD_VERSION_URL)


func _on_srd_update_check_result(has_update: bool, remote_version: String, message: String) -> void:
	_set_status(message)
	if has_update:
		var s: float = _ui_scale()
		var dlg := AcceptDialog.new()
		dlg.title = "SRD Update Available"
		dlg.ok_button_text = "OK"
		dlg.min_size = Vector2i(roundi(400.0 * s), roundi(120.0 * s))
		var lbl := Label.new()
		lbl.text = "A newer SRD version is available: v%s\nCurrent version: v%s\n\nA future update will include the new SRD data." % [remote_version, _get_srd_version()]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", roundi(14.0 * s))
		dlg.add_child(lbl)
		add_child(dlg)
		var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg != null and reg.ui_theme != null:
			reg.ui_theme.theme_control_tree(dlg, s)
		dlg.confirmed.connect(dlg.queue_free)
		dlg.canceled.connect(dlg.queue_free)
		dlg.popup_centered()


func _get_srd_version() -> String:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.srd != null:
		return registry.srd.get_version()
	return "unknown"


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
	## New bundles are always ZIP-backed: the working directory is a cache folder
	## and the canonical .map path is a ZIP file.
	var bundle_path := _normalise_bundle_path(path)
	var map_name: String = bundle_path.get_file().get_basename().strip_edges()
	if map_name.is_empty():
		_set_status("Invalid map name — please try again.")
		return
	map_name = map_name.replace("/", "_").replace("\\", "_")

	# Prepare a working directory in the cache for the new bundle.
	var work_dir: String = BundleIOScript._cache_dir_for(bundle_path)
	DirAccess.make_dir_recursive_absolute(work_dir)
	_active_map_zip_path = bundle_path
	_active_map_bundle_path = work_dir

	match _map_name_mode:
		"new":
			_create_map_from_image(_pending_image_path, bundle_path)
		"save_as":
			_save_map_as_path(bundle_path)


func _create_map_from_image(src_path: String, bundle_path: String) -> void:
	# bundle_path is the canonical ZIP path. Use the working directory for file ops.
	var work_dir: String = _active_map_bundle_path if not _active_map_bundle_path.is_empty() else bundle_path
	_ensure_bundle_dir(work_dir)
	var ext: String = src_path.get_extension().to_lower()
	var is_video: bool = ext in SUPPORTED_VIDEO_EXTENSIONS

	if is_video:
		_create_map_from_video(src_path, bundle_path, ext)
		return

	# ── Static image path (unchanged) ──────────────────────────────────────
	var img_dest_abs: String = _image_dest_path_abs(work_dir, ext)

	var copy_err := _copy_file(src_path, img_dest_abs)
	var new_map_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if new_map_reg != null and new_map_reg.persistence != null:
		copy_err = new_map_reg.persistence.copy_file(src_path, img_dest_abs) as Error
	if copy_err != OK:
		push_error("DMWindow: failed to copy image to '%s' (err %d)" % [img_dest_abs, copy_err])
		_set_status("Error: could not copy image.")
		return

	_finish_map_creation(bundle_path, img_dest_abs)


func _create_map_from_video(src_path: String, bundle_path: String, ext: String) -> void:
	## Handle video-format map imports. OGV files are copied directly; all
	## other formats are converted to OGV via the system ``ffmpeg`` CLI.
	# bundle_path is the canonical ZIP path; use the work directory for file ops.
	var work_dir: String = _active_map_bundle_path if not _active_map_bundle_path.is_empty() else bundle_path
	var dest_ogv: String = work_dir.path_join("video.ogv")

	if ext == "ogv":
		# OGV — copy directly, no conversion needed.
		var copy_err := _copy_file(src_path, dest_ogv)
		var _vreg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if _vreg != null and _vreg.persistence != null:
			copy_err = _vreg.persistence.copy_file(src_path, dest_ogv) as Error
		if copy_err != OK:
			push_error("DMWindow: failed to copy video to '%s' (err %d)" % [dest_ogv, copy_err])
			_set_status("Error: could not copy video.")
			return
		_finish_map_creation(bundle_path, dest_ogv)
		return

	# Non-OGV video — need ffmpeg to convert.
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.persistence == null or not reg.persistence.is_ffmpeg_available():
		_show_ffmpeg_missing_dialog()
		return

	# Stash paths for after the user confirms settings.
	_convert_pending_bundle = bundle_path
	_convert_pending_dest = dest_ogv
	_convert_pending_src = src_path
	_show_convert_settings_dialog()


func _show_convert_settings_dialog() -> void:
	## Show a dialog letting the user choose resolution, fps, and quality
	## before starting the (potentially slow) Theora conversion.
	if _convert_settings_dialog == null:
		_convert_settings_dialog = ConfirmationDialog.new()
		_convert_settings_dialog.title = "Video Conversion Settings"
		_convert_settings_dialog.min_size = Vector2i(380, 0)
		_convert_settings_dialog.ok_button_text = "Convert"

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 10)

		var info_label := Label.new()
		info_label.text = "Godot requires OGV (Theora) format for video playback.\nChoose settings for the conversion:"
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(info_label)

		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 6)

		# --- Max Resolution ---
		var res_label := Label.new()
		res_label.text = "Max Resolution:"
		grid.add_child(res_label)
		_convert_res_option = OptionButton.new()
		_convert_res_option.add_item("1280p (Fast)", 1280)
		_convert_res_option.add_item("1920p (Recommended)", 1920)
		_convert_res_option.add_item("2560p", 2560)
		_convert_res_option.add_item("3840p (4K)", 3840)
		_convert_res_option.add_item("Original", 0)
		_convert_res_option.select(1) # default: 1920
		grid.add_child(_convert_res_option)

		# --- Framerate ---
		var fps_label := Label.new()
		fps_label.text = "Max Framerate:"
		grid.add_child(fps_label)
		_convert_fps_option = OptionButton.new()
		_convert_fps_option.add_item("24 fps", 24)
		_convert_fps_option.add_item("30 fps (Recommended)", 30)
		_convert_fps_option.add_item("60 fps (Slow)", 60)
		_convert_fps_option.add_item("Original", 0)
		_convert_fps_option.select(1) # default: 30
		grid.add_child(_convert_fps_option)

		# --- Quality ---
		var vq_label := Label.new()
		vq_label.text = "Quality:"
		grid.add_child(vq_label)
		_convert_vq_option = OptionButton.new()
		_convert_vq_option.add_item("Low (Fastest)", 4)
		_convert_vq_option.add_item("Medium (Recommended)", 6)
		_convert_vq_option.add_item("High", 8)
		_convert_vq_option.add_item("Maximum (Slowest)", 10)
		_convert_vq_option.select(1) # default: Medium
		grid.add_child(_convert_vq_option)

		vbox.add_child(grid)
		_convert_settings_dialog.add_child(vbox)
		add_child(_convert_settings_dialog)
		_convert_settings_dialog.confirmed.connect(_on_convert_settings_confirmed)
		_convert_settings_dialog.canceled.connect(_on_convert_settings_canceled)
		_apply_dialog_themes()
	_convert_settings_dialog.popup_centered()


func _on_convert_settings_confirmed() -> void:
	## User clicked Convert — read the chosen settings and start encoding.
	var max_w: int = _convert_res_option.get_selected_id()
	var fps: int = _convert_fps_option.get_selected_id()
	var vq: int = _convert_vq_option.get_selected_id()
	# Audio quality tracks video quality roughly: low=2, medium=4, high=6, max=8
	var aq: int = clampi(vq - 2, 0, 10)
	_begin_video_conversion(max_w, fps, vq, aq)


func _on_convert_settings_canceled() -> void:
	_convert_pending_bundle = ""
	_convert_pending_dest = ""
	_convert_pending_src = ""


func _begin_video_conversion(max_width: int, fps: int, vq: int, aq: int) -> void:
	## Probe duration, show progress, and launch threaded ffmpeg conversion.
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.persistence == null:
		return

	# Probe duration so we can show a real progress bar.
	var persistence := reg.persistence
	var duration_s: float = persistence.probe_video_duration(_convert_pending_src)
	_convert_duration_us = duration_s * 1_000_000.0

	# Temp file for ffmpeg to write machine-readable progress into.
	_convert_progress_file = OS.get_cache_dir().path_join("thevault_ffmpeg_progress.txt")
	if FileAccess.file_exists(_convert_progress_file):
		DirAccess.remove_absolute(_convert_progress_file)

	_show_progress_dialog("Converting video…", "Encoding to Theora/Vorbis…")
	_start_progress_timer()

	_convert_thread = Thread.new()
	_convert_thread.start(
		_thread_convert_video.bind(
			_convert_pending_src, _convert_pending_dest, persistence,
			_convert_progress_file, max_width, fps, vq, aq
		)
	)


func _thread_convert_video(
	src_path: String, dest_path: String, persistence: PersistenceManager,
	progress_file: String, max_width: int, fps: int, vq: int, aq: int,
) -> void:
	## Runs on a background thread — converts video to OGV via ffmpeg.
	if persistence != null:
		_convert_result = persistence.convert_video_to_ogv(
			src_path, dest_path, progress_file, max_width, fps, vq, aq
		)
	else:
		_convert_result = -1
	call_deferred("_on_video_conversion_finished")


func _start_progress_timer() -> void:
	if _convert_progress_timer != null:
		_convert_progress_timer.stop()
		_convert_progress_timer.queue_free()
	_convert_progress_timer = Timer.new()
	_convert_progress_timer.wait_time = 0.35
	_convert_progress_timer.timeout.connect(_poll_convert_progress)
	add_child(_convert_progress_timer)
	_convert_progress_timer.start()


func _stop_progress_timer() -> void:
	if _convert_progress_timer != null:
		_convert_progress_timer.stop()
		_convert_progress_timer.queue_free()
		_convert_progress_timer = null


func _poll_convert_progress() -> void:
	## Read ffmpeg's -progress file and update the bar.
	if _convert_progress_file.is_empty() or not FileAccess.file_exists(_convert_progress_file):
		return
	var f := FileAccess.open(_convert_progress_file, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	# Parse the last out_time_us value in the file.
	var out_us: float = 0.0
	for line: String in text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("out_time_us="):
			out_us = stripped.substr(12).to_float()
	if _convert_duration_us > 0.0 and out_us > 0.0:
		var pct: float = clampf(out_us / _convert_duration_us * 100.0, 0.0, 100.0)
		if _progress_bar != null:
			if _progress_bar.indeterminate:
				_progress_bar.indeterminate = false
				_progress_bar.show_percentage = true
			_progress_bar.value = pct
		if _progress_label != null:
			_progress_label.text = "Encoding to Theora/Vorbis… %d%%" % int(pct)


func _on_video_conversion_finished() -> void:
	## Called on the main thread after the background conversion completes.
	_stop_progress_timer()
	if _convert_thread != null:
		_convert_thread.wait_to_finish()
		_convert_thread = null
	_hide_progress_dialog()
	# Clean up temp progress file.
	if not _convert_progress_file.is_empty() and FileAccess.file_exists(_convert_progress_file):
		DirAccess.remove_absolute(_convert_progress_file)
	_convert_progress_file = ""
	_convert_duration_us = 0.0

	if _convert_result != 0:
		push_error("DMWindow: ffmpeg conversion failed (exit %d)" % _convert_result)
		_set_status("Error: video conversion failed (exit %d). Check ffmpeg installation." % _convert_result)
		return

	_finish_map_creation(_convert_pending_bundle, _convert_pending_dest)
	_convert_pending_bundle = ""
	_convert_pending_dest = ""
	_convert_pending_src = ""


func _finish_map_creation(bundle_path: String, media_path: String) -> void:
	## Shared tail for both image and video map creation: build MapData, save,
	## load via service, broadcast, and generate thumbnail.
	## _active_map_bundle_path (work dir) and _active_map_zip_path are already set
	## by _on_save_as_path_selected before we reach here.
	var map := MapData.new()
	map.map_name = bundle_path.get_file().get_basename()
	map.image_path = media_path
	# _active_map_bundle_path is the work directory (set by caller).
	# Clear all tokens from any previous session BEFORE saving the new bundle.
	# _save_map_data calls save_to_bundle → _flush_tokens_to_map, which would
	# otherwise write stale TokenService state into the brand-new map.json.
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.token != null:
		reg.token.clear_tokens()
	_save_map_data(map)
	# Load via the service to emit map_loaded and run _sync_tokens_from_map.
	# map.tokens is [] here (saved clean above), so TokenService stays empty.
	var ms := _map_service()
	if ms != null:
		ms.load(map)
	_apply_map(map)
	_nm_broadcast_map(map)
	_generate_thumbnail(_active_map_bundle_path, media_path)
	_set_status("New map: %s" % map.map_name)


func _on_open_map_pressed() -> void:
	## Open a previously saved .map file.
	_ensure_maps_dir()
	_open_map_dialog.current_dir = _maps_dir_abs()
	_open_map_dialog.popup_centered(Vector2i(900, 600))


func _open_bundle_browser(mode: String) -> void:
	## Open the unified map/save browser window on the given tab ("map" or "save").
	_ensure_maps_dir()
	var dir := _saves_dir_abs()
	DirAccess.make_dir_recursive_absolute(dir)
	if _bundle_browser == null:
		_bundle_browser = BundleBrowserScript.new()
		add_child(_bundle_browser)
		_bundle_browser.map_selected.connect(_on_map_bundle_selected)
		_bundle_browser.save_selected.connect(_on_load_game_path_selected)
		_bundle_browser.new_map_requested.connect(_on_new_map_pressed)
		_bundle_browser.open_map_file_requested.connect(_on_open_map_pressed)
		_bundle_browser.open_save_file_requested.connect(_on_load_game_pressed)
		var _bb_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if _bb_reg != null and _bb_reg.ui_theme != null:
			_bb_reg.ui_theme.theme_control_tree(_bundle_browser, _ui_scale())
	_bundle_browser.open_to_mode(mode)
	_bundle_browser.populate()
	# Defer the popup so the Window node has fully entered the scene tree before
	# being shown — fixes a Windows-specific race where a just-created Window
	# doesn't appear because it hasn't received its HWND yet.
	_bundle_browser.call_deferred(&"popup_centered_ratio", 0.85)
	_bundle_browser.call_deferred(&"grab_focus")


func _on_map_bundle_selected(path: String) -> void:
	## Load the map stored inside the selected .map bundle.
	## Accepts direct bundle selection, map.json selection, or a child file inside
	## a bundle by walking up to the nearest parent ending in ".map".
	var bundle_path := _resolve_bundle_path(path)
	if bundle_path.is_empty():
		_set_status("Failed to load map: selected path is not a valid .map bundle.")
		return
	# Transparently handle ZIP or directory bundles.
	var work_dir: String = BundleIOScript.open_bundle(bundle_path)
	if work_dir.is_empty():
		_set_status("Failed to open map bundle: %s" % bundle_path.get_file())
		return
	var is_zip: bool = (work_dir != bundle_path)
	var map: MapData = null
	var ms := _map_service()
	# load_from_bundle calls MapService.load_map → _sync_tokens_from_map, so
	# TokenService is populated before _apply_map reads it for sprite creation.
	# Pass the work directory so MapService resolves relative paths correctly.
	if ms != null and ms.service != null:
		map = ms.load_from_bundle(work_dir)
	else:
		map = _load_map_from_bundle(work_dir)
		if map != null and ms != null:
			ms.load(map)
	if map == null:
		_set_status("Failed to load map from: %s" % bundle_path.get_file())
		return
	_active_map_bundle_path = work_dir
	_active_map_zip_path = bundle_path if is_zip else ""
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
	_save_as_dialog.current_dir = _active_map_zip_path.get_base_dir() if not _active_map_zip_path.is_empty() else _maps_dir_abs()
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
	var sav_zip_path: String = _saves_dir_abs().path_join(save_name + ".sav")
	if gs != null:
		var ok := gs.save_session(save_name, fog_image, _active_map_bundle_path)
		if ok:
			# The .sav ZIP is the canonical path; get its work dir for embedded ops.
			var sav_work_dir: String = BundleIOScript.open_bundle(sav_zip_path)
			if sav_work_dir.is_empty():
				sav_work_dir = BundleIOScript._cache_dir_for(sav_zip_path)
			_active_save_bundle_path = sav_work_dir
			_active_save_zip_path = sav_zip_path
			# Flush current token state into the EMBEDDED map.json inside the
			# .sav bundle (not the original .map).
			if ms != null:
				var embedded_map_path: String = sav_work_dir.path_join("map.map")
				ms.save_to_bundle(embedded_map_path)
			# Generate thumbnail for the .sav bundle from the embedded map image
			var sav_img := _find_bundle_media(sav_work_dir.path_join("map.map"))
			if not sav_img.is_empty():
				_generate_thumbnail(sav_work_dir, sav_img)
			# Re-pack the .sav ZIP with updated embedded map.json + thumbnail.
			var pack_err: Error = BundleIOScript.save_bundle(sav_work_dir, sav_zip_path)
			if pack_err != OK:
				push_error("DMWindow: failed to re-pack .sav ZIP '%s' (err %d)" % [sav_zip_path, pack_err])
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
	## Handles both ZIP archives and legacy directory bundles.
	var bundle_path := path
	# For legacy directory bundles, walk up to the nearest .sav if needed.
	if not bundle_path.ends_with(".sav"):
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

	# Track ZIP path for re-packing on future saves.
	var is_zip: bool = BundleIOScript.is_zip(bundle_path)
	_active_save_zip_path = bundle_path if is_zip else ""

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
			if not maps_candidate.is_empty() and BundleIOScript.bundle_exists(maps_candidate):
				# Open the ZIP-backed map for working
				var work_dir: String = BundleIOScript.open_bundle(maps_candidate)
				if not work_dir.is_empty():
					_active_map_bundle_path = work_dir
					_active_map_zip_path = maps_candidate if (work_dir != maps_candidate) else ""
				else:
					_active_map_bundle_path = maps_candidate
					_active_map_zip_path = ""
			else:
				var recorded_path: String = "" if state_val == null else str(state_val.map_bundle_path)
				var resolved_path: String = ProjectSettings.globalize_path(recorded_path) if not recorded_path.is_empty() else ""
				if not resolved_path.is_empty() and BundleIOScript.bundle_exists(resolved_path) and not resolved_path.begins_with(saves_dir):
					var work_dir2: String = BundleIOScript.open_bundle(resolved_path)
					if not work_dir2.is_empty():
						_active_map_bundle_path = work_dir2
						_active_map_zip_path = resolved_path if (work_dir2 != resolved_path) else ""
					else:
						_active_map_bundle_path = recorded_path
						_active_map_zip_path = ""
				else:
					_active_map_bundle_path = map_bundle
					_active_map_zip_path = ""
			_active_save_bundle_path = BundleIOScript.open_bundle(bundle_path) if is_zip else bundle_path
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

	# Ensure the save work dir is tracked (may already have been set inside the
	# map-loading block above; this covers the case where map_bundle was empty).
	if _active_save_bundle_path.is_empty():
		if is_zip:
			var sav_wdir: String = BundleIOScript.open_bundle(bundle_path)
			_active_save_bundle_path = sav_wdir if not sav_wdir.is_empty() else bundle_path
		else:
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
	## _active_map_bundle_path (work dir) and _active_map_zip_path are already
	## set by _on_save_as_path_selected.
	var map: MapData = _map()
	if map == null:
		return
	var work_dir: String = _active_map_bundle_path
	_ensure_bundle_dir(work_dir)
	var ext: String = map.image_path.get_extension().to_lower()
	var new_img_abs: String = _image_dest_path_abs(work_dir, ext)

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
	_save_map_data(map)
	var ms := _map_service()
	if ms != null:
		ms.update(map)
	_nm_broadcast_map_update(map)
	_generate_thumbnail(work_dir, new_img_abs)
	_set_status("Saved as: %s" % map.map_name)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _apply_map(map: MapData, from_save: bool = false) -> void:
	# Hide the campaign hub whenever a map is loaded — the map view becomes primary.
	if _campaign_panel != null and is_instance_valid(_campaign_panel) and _campaign_panel.visible:
		_campaign_panel.hide()
	# ── Clear per-map transient state so nothing leaks between maps ──────
	_detected_token_ids.clear()
	_autopause_locked_ids.clear()
	_prev_player_positions.clear()
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
			# Create an ephemeral session so profile active toggles work
			# immediately without requiring a Save Game first.
			gs.init_ephemeral_session()
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
	_update_effect_panel_calibration()
	_refresh_freeze_panel()
	# Restore per-map fog-of-war toggle.
	_set_view_checked(30, map.fog_enabled)
	if _map_view != null:
		_map_view.set_fog_enabled(map.fog_enabled)


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
		_apply_dialog_themes()
		_apply_ui_scale()
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
	if _backend != null:
		_backend.mark_walls_dirty()
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
	var gs_spawn := _game_state()
	for i in range(profiles.size()):
		var p: Variant = profiles[i]
		if p is PlayerProfile:
			var pp := p as PlayerProfile
			if gs_spawn != null and not gs_spawn.is_profile_active(pp.id):
				continue
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
	var spawns: Array = _map_view._map.spawn_points
	if spawns.is_empty():
		return
	# Build a list of profiles that are active in the current session (or all if no session).
	var gs_auto := _game_state()
	var active_profiles: Array = []
	for raw in registry.profile.get_profiles():
		if not raw is PlayerProfile:
			continue
		var pp := raw as PlayerProfile
		if gs_auto != null and not gs_auto.is_profile_active(pp.id):
			continue
		active_profiles.append(pp)
	if active_profiles.is_empty():
		return
	for i in range(spawns.size()):
		if i < active_profiles.size():
			(spawns[i] as Dictionary)["profile_id"] = (active_profiles[i] as PlayerProfile).id
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
	# Native save panels may leave behind a placeholder file at the selected path.
	# ZIP bundles are real files — only remove 0-byte placeholders.
	if FileAccess.file_exists(abs_dir) and not DirAccess.dir_exists_absolute(abs_dir):
		# Check if this is a real ZIP bundle (non-zero size) vs placeholder.
		var fa := FileAccess.open(abs_dir, FileAccess.READ)
		var is_placeholder: bool = (fa == null or fa.get_length() == 0)
		if fa != null:
			fa.close()
		if is_placeholder:
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
	## Handles both ZIP files and legacy directory bundles.
	if path.is_empty():
		return ""

	var raw := path
	# Direct match: path ends in .map and is a file (ZIP) or directory.
	if raw.to_lower().ends_with(".map"):
		if BundleIOScript.bundle_exists(raw):
			return raw
		return raw # might be a Save As target that doesn't exist yet

	# Walk up to find the nearest .map parent (legacy directory bundles).
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
	## Serialise MapData to map.json inside the active .map bundle working directory.
	## image_path is stored as a relative filename so the bundle is self-contained.
	## If the map is backed by a ZIP, the working dir is packed back to ZIP after writing.
	if _active_map_bundle_path.is_empty():
		var default_dir: String = _bundle_dir_abs(map.map_name)
		_active_map_bundle_path = default_dir
		_active_map_zip_path = default_dir # new bundles are always ZIP
	_ensure_bundle_dir(_active_map_bundle_path)
	var path := _bundle_json_path_abs(_active_map_bundle_path)
	var d := map.to_dict()
	d["image_path"] = map.image_path.get_file()
	var ms := _map_service()
	if ms != null:
		ms.update(map)
		ms.save_to_bundle(_active_map_bundle_path)
		# Regenerate thumbnail on every map save
		var thumb_img_ms := _find_bundle_media(_active_map_bundle_path)
		if not thumb_img_ms.is_empty():
			_generate_thumbnail(_active_map_bundle_path, thumb_img_ms)
		_pack_active_map_zip()
		return

	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		push_error("DMWindow: cannot write to '%s'" % path)
		return
	fa.store_string(JSON.stringify(d, "\t"))
	fa.close()
	# Regenerate thumbnail on every map save
	var thumb_img := _find_bundle_media(_active_map_bundle_path)
	if not thumb_img.is_empty():
		_generate_thumbnail(_active_map_bundle_path, thumb_img)
	_pack_active_map_zip()


func _pack_active_map_zip() -> void:
	## Pack the working directory back to the ZIP archive if this map is ZIP-backed.
	if _active_map_zip_path.is_empty():
		return
	if _active_map_bundle_path.is_empty():
		return
	var err: Error = BundleIOScript.save_bundle(_active_map_bundle_path, _active_map_zip_path)
	if err != OK:
		push_error("DMWindow: failed to pack map ZIP '%s' (err %d)" % [_active_map_zip_path, err])


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
	Log.debug("DMWindow", msg)


func _generate_thumbnail(bundle_path: String, media_path: String) -> void:
	## Generate thumbnail.png inside the bundle from the map image or video.
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.persistence == null:
		return
	var thumb_dest := bundle_path.path_join("thumbnail.png")
	var ext: String = media_path.get_extension().to_lower()
	if ext in SUPPORTED_VIDEO_EXTENSIONS:
		registry.persistence.generate_video_thumbnail(media_path, thumb_dest)
	else:
		registry.persistence.generate_thumbnail(media_path, thumb_dest)


func _find_bundle_media(bundle_path: String) -> String:
	## Locate the image or video file inside a bundle by trying known extensions.
	for ext in SUPPORTED_IMAGE_EXTENSIONS:
		var candidate := bundle_path.path_join("image." + ext)
		if FileAccess.file_exists(candidate):
			return candidate
	var video_candidate := bundle_path.path_join("video.ogv")
	if FileAccess.file_exists(video_candidate):
		return video_candidate
	return ""


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


# ---------------------------------------------------------------------------
# Video conversion progress dialog
# ---------------------------------------------------------------------------

func _show_progress_dialog(title: String, message: String) -> void:
	if _progress_dialog == null:
		_progress_dialog = AcceptDialog.new()
		_progress_dialog.title = "Working…"
		_progress_dialog.exclusive = true
		_progress_dialog.min_size = Vector2i(360, 0)
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 8)
		_progress_label = Label.new()
		_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(_progress_label)
		_progress_bar = ProgressBar.new()
		_progress_bar.custom_minimum_size = Vector2(300, 20)
		_progress_bar.min_value = 0.0
		_progress_bar.max_value = 100.0
		_progress_bar.value = 0.0
		_progress_bar.indeterminate = true
		_progress_bar.show_percentage = false
		vbox.add_child(_progress_bar)
		_progress_dialog.add_child(vbox)
		add_child(_progress_dialog)
		_apply_dialog_themes()
	_progress_dialog.title = title
	_progress_label.text = message
	# Reset to indeterminate until first poll arrives.
	_progress_bar.value = 0.0
	_progress_bar.indeterminate = true
	_progress_bar.show_percentage = false
	# Hide the OK button during conversion.
	_progress_dialog.get_ok_button().visible = false
	_progress_dialog.popup_centered()


func _hide_progress_dialog() -> void:
	if _progress_dialog != null:
		_progress_dialog.hide()


func _show_ffmpeg_missing_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "ffmpeg Not Found"
	var hint: String
	match OS.get_name():
		"macOS":
			hint = "ffmpeg should be bundled inside the app.\n\nIf you are running from the editor, run this in the project root:\n    ./setup_ffmpeg_dev.sh\n\nThis downloads a static ffmpeg with the required Theora encoder."
		"Windows":
			hint = "ffmpeg.exe should be next to The Vault.exe.\n\nIf you are running from the editor, install ffmpeg and add it to PATH."
		_:
			hint = "Install ffmpeg via your system's package manager."
	dlg.dialog_text = "Video import requires ffmpeg, which was not found.\n\n%s" % hint
	dlg.min_size = Vector2i(420, 0)
	add_child(dlg)
	var _ff_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _ff_reg != null and _ff_reg.ui_theme != null:
		_ff_reg.ui_theme.theme_control_tree(dlg, _ui_scale())
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)


func _menu_bar_screen_height() -> float:
	## Returns the in-window MenuBar height in screen pixels.  On macOS the
	## native global menu is used so size.y == 0; on Windows the native menu
	## bar is used and _menu_bar is hidden, so return 0 in that case too.
	if _menu_bar == null or not _menu_bar.visible:
		return 0.0
	return _menu_bar.size.y * _ui_scale()


func _apply_palette_size() -> void:
	## Set the palette's screen-space width. Called from _apply_ui_scale()
	## and _dock_palette(). The palette lives directly in the CanvasLayer
	## (not _ui_root), so it is NOT affected by _ui_root.scale.
	if _palette == null:
		return
	var scale := _ui_scale()
	var panel_w := roundi(40.0 * scale)
	_palette.offset_left = 0.0
	_palette.offset_right = float(panel_w)
	_palette.offset_top = _menu_bar_screen_height()
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
	_freeze_panel.offset_top = _menu_bar_screen_height()
	_freeze_panel.offset_bottom = 0.0
	# Initiative panel stacks left of the freeze panel — reposition now that
	# freeze width is finalised.
	_apply_initiative_panel_size()


func _apply_passage_panel_size() -> void:
	## Reposition and rescale the passage panel at the screen bottom.
	## The panel lives directly in _ui_content_area, so it is NOT affected by _ui_root.scale.
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


func _apply_roam_panel_size() -> void:
	## Reposition and rescale the roam panel at the screen bottom.
	## Same pattern as _apply_passage_panel_size — explicit scaling because
	## the panel lives in _ui_content_area, outside _ui_root.scale.
	if _roam_panel == null:
		return
	var scale := _ui_scale()
	var panel_h := roundi(56.0 * scale)
	_roam_panel.offset_left = 0.0
	_roam_panel.offset_right = 0.0
	_roam_panel.offset_top = float(-panel_h)
	_roam_panel.offset_bottom = 0.0
	var font_size: int = roundi(15.0 * scale)
	var btn_h: int = roundi(34.0 * scale)
	var icon_font: int = roundi(18.0 * scale)
	# Icon label (🐾)
	for child in _roam_panel.get_children():
		var margin: MarginContainer = child as MarginContainer
		if margin == null:
			continue
		margin.add_theme_constant_override("margin_left", roundi(6.0 * scale))
		margin.add_theme_constant_override("margin_right", roundi(6.0 * scale))
		margin.add_theme_constant_override("margin_top", roundi(4.0 * scale))
		margin.add_theme_constant_override("margin_bottom", roundi(4.0 * scale))
		for mc_child in margin.get_children():
			var hbox: HBoxContainer = mc_child as HBoxContainer
			if hbox != null:
				hbox.add_theme_constant_override("separation", roundi(8.0 * scale))
				# Scale all child Labels that are not tracked by a specific var
				for hc in hbox.get_children():
					if hc is Label:
						(hc as Label).add_theme_font_size_override("font_size", font_size)
	if _roam_token_label:
		_roam_token_label.add_theme_font_size_override("font_size", font_size)
	if _roam_mode_option:
		_roam_mode_option.custom_minimum_size = Vector2(roundi(130.0 * scale), btn_h)
		_roam_mode_option.add_theme_font_size_override("font_size", font_size)
	if _roam_loop_check:
		_roam_loop_check.custom_minimum_size = Vector2(0, btn_h)
		_roam_loop_check.add_theme_font_size_override("font_size", font_size)
	if _roam_speed_slider:
		_roam_speed_slider.custom_minimum_size = Vector2(roundi(100.0 * scale), roundi(20.0 * scale))
	if _roam_speed_value_label:
		_roam_speed_value_label.custom_minimum_size = Vector2(roundi(60.0 * scale), 0)
		_roam_speed_value_label.add_theme_font_size_override("font_size", font_size)
	if _roam_smooth_btn:
		_roam_smooth_btn.custom_minimum_size = Vector2(btn_h, btn_h)
		_roam_smooth_btn.add_theme_font_size_override("font_size", icon_font)
	if _roam_play_btn:
		_roam_play_btn.custom_minimum_size = Vector2(btn_h, btn_h)
		_roam_play_btn.add_theme_font_size_override("font_size", icon_font)
	if _roam_reset_btn:
		_roam_reset_btn.custom_minimum_size = Vector2(btn_h, btn_h)
		_roam_reset_btn.add_theme_font_size_override("font_size", icon_font)
	if _roam_commit_btn:
		_roam_commit_btn.custom_minimum_size = Vector2(roundi(80.0 * scale), btn_h)
		_roam_commit_btn.add_theme_font_size_override("font_size", font_size)
	if _roam_clear_btn:
		_roam_clear_btn.custom_minimum_size = Vector2(roundi(70.0 * scale), btn_h)
		_roam_clear_btn.add_theme_font_size_override("font_size", font_size)


func _apply_ui_scale() -> void:
	var mgr := _get_ui_scale_mgr()
	var scale := _ui_scale()
	if _palette:
		_palette.custom_minimum_size = Vector2(roundi(34.0 * scale), 0)
	if _palette and _palette.get_parent() == _ui_content_area:
		_apply_palette_size()
	if _ui_root:
		_ui_root.scale = Vector2(scale, scale)
	if _freeze_panel and _freeze_panel.get_parent() == _ui_content_area:
		_apply_freeze_panel_size()
	if _effect_panel and _effect_panel.get_parent() == _ui_content_area:
		_apply_effect_panel_size()
	if _measure_panel and _measure_panel.get_parent() == _ui_content_area:
		_apply_measure_panel_size()
	if _passage_panel and _passage_panel.get_parent() == _ui_content_area:
		_apply_passage_panel_size()
	if _roam_panel and _roam_panel.get_parent() == _ui_content_area:
		_apply_roam_panel_size()
	if _dice_tray and _dice_tray.get_parent() == _ui_content_area:
		_apply_dice_tray_size()
	if _initiative_panel and _initiative_panel.get_parent() == _ui_content_area:
		_apply_initiative_panel_size()
	# Scale initiative panel child content (works both docked and floating).
	if _initiative_panel:
		_initiative_panel.apply_scale(scale)
	if _combat_log_panel and _combat_log_panel.get_parent() == _ui_content_area:
		_apply_combat_log_panel_size()
	if _combat_log_panel:
		_combat_log_panel.apply_scale(scale)
	if _dice_renderer != null:
		_apply_dice_renderer_size()
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
	# Update measure panel static widget sizes at new scale.
	if _measure_undock_btn:
		_measure_undock_btn.custom_minimum_size = Vector2(0, roundi(22.0 * scale))
		_measure_undock_btn.add_theme_font_size_override("font_size", roundi(14.0 * scale))
	if _measure_panel_title:
		_measure_panel_title.add_theme_font_size_override("font_size", roundi(15.0 * scale))
	# Only reposition freeze panel when docked — floating window manages its own layout.
	if _freeze_panel and _freeze_panel.get_parent() == _ui_content_area:
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
	if _fog_reset_dialog:
		mgr.scale_button(_fog_reset_dialog.get_ok_button())
		mgr.scale_button(_fog_reset_dialog.get_cancel_button())
		_fog_reset_dialog.get_label().add_theme_font_size_override("font_size", mgr.scaled(14.0))
	if _profile_delete_confirm_dialog:
		mgr.scale_button(_profile_delete_confirm_dialog.get_ok_button())
		mgr.scale_button(_profile_delete_confirm_dialog.get_cancel_button())
		_profile_delete_confirm_dialog.get_label().add_theme_font_size_override("font_size", mgr.scaled(14.0))
	_apply_token_context_menu_theme()

	# ── Share player link dialog ──
	if _share_dialog_root:
		var qr_px: int = mgr.scaled(280.0)
		_share_qr_rect.custom_minimum_size = Vector2(qr_px, qr_px)
		_share_url_label.add_theme_font_size_override("font_size", mgr.scaled(13.0))
		var sep_px: int = mgr.scaled(12.0)
		_share_dialog_root.add_theme_constant_override("separation", sep_px)
		mgr.scale_button(_share_dialog.get_ok_button())
		# Set min_size derived from the same scaled measurements as the content so
		# reset_size() has the correct floor on the first open, before wrap_controls
		# has had a chance to propagate child minimums through a layout pass.
		# Width:  QR width + left/right content margins (~30 px total scaled)
		# Height: title_bar(30) + content_top_margin(8) + top_pad(8)
		#         + 3 seps(12*3=36) + QR(280) + label(~20) + copy_btn(~28)
		#         + content_bottom_margin(8) + ok_btn_row(~40)
		#       = 30+8+8+36+20+28+8+40 = 178 chrome; use 200 for safe headroom
		var margin_x: int = mgr.scaled(30.0)
		var chrome_y: int = mgr.scaled(200.0)
		_share_dialog.min_size = Vector2i(qr_px + margin_x, qr_px + chrome_y)

	# ── Volume window ──
	if _volume_vbox != null:
		mgr.scale_control_fonts(_volume_vbox)
	if _progress_dialog != null and _progress_label != null:
		_progress_dialog.min_size = Vector2i(mgr.scaled(360.0), 0)
		_progress_label.add_theme_font_size_override("font_size", mgr.scaled(14.0))
		mgr.scale_button(_progress_dialog.get_ok_button())

	# ── Crop editor dialog ──
	if _crop_editor_dialog != null:
		_crop_editor_dialog.min_size = Vector2i(mgr.scaled(460.0), mgr.scaled(520.0))
	if _crop_editor_vbox != null:
		_crop_editor_vbox.add_theme_constant_override("separation", mgr.scaled(8.0))
	if _crop_editor_btn_row != null:
		_crop_editor_btn_row.add_theme_constant_override("separation", mgr.scaled(8.0))
	if _crop_editor_hint != null:
		_crop_editor_hint.add_theme_font_size_override("font_size", mgr.scaled(14.0))
	if _crop_editor_reset_btn != null:
		mgr.scale_button(_crop_editor_reset_btn)
	if _crop_editor_cancel_btn != null:
		mgr.scale_button(_crop_editor_cancel_btn)
	if _crop_editor_ok_btn != null:
		mgr.scale_button(_crop_editor_ok_btn)

	# ── Quick damage dialog ──
	if _quick_damage_dialog != null:
		_quick_damage_dialog.apply_scale(scale)
		var qd_root: Control = _first_control_child(_quick_damage_dialog)
		if qd_root != null:
			mgr.scale_control_fonts(qd_root)

	# ── Save results panel ──
	if _save_results_panel != null:
		_save_results_panel.apply_scale(scale)
		var sr_root: Control = _first_control_child(_save_results_panel)
		if sr_root != null:
			mgr.scale_control_fonts(sr_root)

	# ── Save config dialog ──
	if _save_config_dialog != null:
		_save_config_dialog.min_size = Vector2i(mgr.scaled(260.0), mgr.scaled(200.0))
		var sc_root: Control = _first_control_child(_save_config_dialog)
		if sc_root != null:
			mgr.scale_control_fonts(sc_root)
			# Re-scale separations and min sizes for child containers.
			for child: Node in sc_root.get_children():
				if child is VBoxContainer:
					(child as VBoxContainer).add_theme_constant_override("separation", mgr.scaled(8.0))
					for row: Node in child.get_children():
						if row is HBoxContainer:
							(row as HBoxContainer).add_theme_constant_override("separation", mgr.scaled(6.0))
							for btn: Node in row.get_children():
								if btn is Button:
									mgr.scale_button(btn as Button)

	# ── Character manager / wizard / sheet ──
	if _char_mgr_dialog != null:
		_char_mgr_dialog.min_size = Vector2i(mgr.scaled(540.0), mgr.scaled(380.0))
		mgr.scale_button(_char_mgr_dialog.get_ok_button())
		var cm_root: Control = _first_control_child(_char_mgr_dialog)
		if cm_root != null:
			mgr.scale_control_fonts(cm_root)
	if _char_wizard != null:
		_char_wizard.min_size = Vector2i(mgr.scaled(480.0), mgr.scaled(420.0))
		var cw_root: Control = _first_control_child(_char_wizard)
		if cw_root != null:
			mgr.scale_control_fonts(cw_root)
	if _char_sheet != null:
		_char_sheet.min_size = Vector2i(mgr.scaled(700.0), mgr.scaled(550.0))
		var cs_root: Control = _first_control_child(_char_sheet)
		if cs_root != null:
			mgr.scale_control_fonts(cs_root)
	if _level_up_wizard != null:
		_level_up_wizard.min_size = Vector2i(mgr.scaled(500.0), mgr.scaled(400.0))
		var lu_root: Control = _first_control_child(_level_up_wizard)
		if lu_root != null:
			mgr.scale_control_fonts(lu_root)

	# ── Status bar ──
	if _status_bar != null:
		_apply_status_bar_size()
		_status_label.add_theme_font_size_override("font_size", roundi(13.0 * scale))
		var sb_bg: StyleBoxFlat = _status_bar.get_theme_stylebox("panel") as StyleBoxFlat
		if sb_bg != null:
			sb_bg.content_margin_left = roundi(8.0 * scale)
			sb_bg.content_margin_right = roundi(8.0 * scale)
			sb_bg.content_margin_top = roundi(4.0 * scale)
			sb_bg.content_margin_bottom = roundi(4.0 * scale)

	# ── Multi-selection bar ──
	if _multi_select_bar != null:
		mgr.scale_control_fonts(_multi_select_bar)
		var ms_bg: StyleBoxFlat = _multi_select_bar.get_theme_stylebox("panel") as StyleBoxFlat
		if ms_bg != null:
			var pad_x: float = 12.0 * scale
			var pad_y: float = 6.0 * scale
			ms_bg.content_margin_left = pad_x
			ms_bg.content_margin_right = pad_x
			ms_bg.content_margin_top = pad_y
			ms_bg.content_margin_bottom = pad_y
		_multi_select_bar.offset_top = - roundi(50.0 * scale)
		_multi_select_bar.offset_bottom = - roundi(8.0 * scale)


func _first_control_child(win: Window) -> Control:
	for child: Node in win.get_children():
		if child is Control:
			return child as Control
	return null


func _ui_scale() -> float:
	## Delegates to UIScaleManager so scale logic lives in one place.
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	if mgr != null:
		return mgr.get_scale()
	return 1.0


func _show_window_centered(win: Window, ratio: float = 0.0) -> void:
	## Show a Window centered on the current screen without setting
	## popup_window = true (which prevents title-bar dragging on macOS).
	var parent_wid: int = get_window().get_window_id()
	var scr: int = DisplayServer.window_get_current_screen(parent_wid)
	var rect: Rect2i = DisplayServer.screen_get_usable_rect(scr)
	if ratio > 0.0:
		win.size = Vector2i(roundi(rect.size.x * ratio), roundi(rect.size.y * ratio))
	win.position = rect.position + (rect.size - win.size) / 2
	win.show()
	win.grab_focus()


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


func _build_share_player_link_dialog() -> void:
	## Constructs the share-player-link AcceptDialog and adds it to the
	## scene tree at startup, so the layout engine has a full frame to
	## process the node before the user first opens it (fixes wrong size
	## on first open).
	var mgr := _get_ui_scale_mgr()

	_share_dialog = AcceptDialog.new()
	_share_dialog.title = "Share Player Link"
	_share_dialog.ok_button_text = "Close"
	# Disable wrap_controls so we own the window size entirely via min_size.
	# wrap_controls only computes content minimums after a real draw pass, which
	# causes the wrong size on first open. With it off, reset_size() always snaps
	# to our explicitly-computed min_size.
	_share_dialog.wrap_controls = false

	# Content root -- children sized explicitly via scale factor.
	_share_dialog_root = VBoxContainer.new()
	if mgr != null:
		_share_dialog_root.add_theme_constant_override("separation", mgr.scaled(12.0))

	# Top padding
	var top_pad := Control.new()
	if mgr != null:
		top_pad.custom_minimum_size = Vector2(0, mgr.scaled(8.0))
	_share_dialog_root.add_child(top_pad)

	# QR code -- content filled in _show_share_player_link().
	_share_qr_rect = TextureRect.new()
	_share_qr_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if mgr != null:
		_share_qr_rect.custom_minimum_size = Vector2(mgr.scaled(280.0), mgr.scaled(280.0))
	_share_qr_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_share_dialog_root.add_child(_share_qr_rect)

	# URL label -- text filled in _show_share_player_link().
	_share_url_label = Label.new()
	_share_url_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_share_url_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if mgr != null:
		_share_url_label.add_theme_font_size_override("font_size", mgr.scaled(13.0))
	_share_dialog_root.add_child(_share_url_label)

	# Copy URL button -- reads _share_url_label.text so it always copies
	# the current URL regardless of when it was last refreshed.
	var copy_btn := Button.new()
	copy_btn.text = "Copy URL"
	copy_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if mgr != null:
		mgr.scale_button(copy_btn)
	copy_btn.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_share_url_label.text)
		_set_status("Player link copied to clipboard"))
	_share_dialog_root.add_child(copy_btn)

	_share_dialog.add_child(_share_dialog_root)
	if mgr != null:
		mgr.scale_button(_share_dialog.get_ok_button())
	add_child(_share_dialog)
	var _sd_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _sd_reg != null and _sd_reg.ui_theme != null:
		_sd_reg.ui_theme.theme_control_tree(_share_dialog, _ui_scale())


func _show_share_player_link() -> void:
	# Refresh QR and URL in case IP changed, then show.
	# The dialog is always in the scene tree (built at startup via
	# _build_share_player_link_dialog) so reset_size() measures the
	# correct layout on every call including the first.
	var url: String = _build_share_url()
	_share_url_label.text = url
	var refresh_img: Image = QRCodeScript.generate(url, 8)
	_share_qr_rect.texture = ImageTexture.create_from_image(refresh_img)
	# Apply theme at interaction time — services are guaranteed ready here.
	var _show_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _show_reg != null and _show_reg.ui_theme != null:
		_show_reg.ui_theme.theme_control_tree(_share_dialog, _ui_scale())
	_apply_ui_scale()
	_share_dialog.reset_size()
	_share_dialog.popup_centered()

# ---------------------------------------------------------------------------

func _build_native_menus() -> void:
	## Populate the NativeWin32MenuBar with the same structure as the Godot
	## MenuBar / PopupMenu tree.  Called once from _build_ui() on Windows.
	if _native_menu == null:
		return
	var nm := _native_menu

	# File
	nm.call(&"AddMenu", "File")
	nm.call(&"AddItem", "File", "New Map from Image…", 0)
	nm.call(&"AddItem", "File", "Open Map…", 1)
	nm.call(&"AddItem", "File", "Browse Maps…", 7)
	nm.call(&"AddSeparator", "File")
	nm.call(&"AddItem", "File", "Save Map", 2)
	nm.call(&"AddItem", "File", "Save Map As…", 3)
	nm.call(&"AddSeparator", "File")
	nm.call(&"AddItem", "File", "Save Game", 4)
	nm.call(&"AddItem", "File", "Save Game As…", 5)
	nm.call(&"AddItem", "File", "Load Game…", 6)
	nm.call(&"AddItem", "File", "Browse Saves…", 8)
	nm.call(&"AddSeparator", "File")
	nm.call(&"AddItem", "File", "New Campaign…", 40)
	nm.call(&"AddItem", "File", "Open Campaign…", 41)
	nm.call(&"AddItem", "File", "Save Campaign", 42)
	nm.call(&"AddItem", "File", "Close Campaign", 44)
	nm.call(&"AddSeparator", "File")
	nm.call(&"AddItem", "File", "Close Map", 45)
	nm.call(&"AddItem", "File", "Close Save", 46)
	nm.call(&"AddSeparator", "File")
	nm.call(&"AddItem", "File", "Quit", 9)

	# Edit
	nm.call(&"AddMenu", "Edit")
	nm.call(&"AddItem", "Edit", "Undo", 14)
	nm.call(&"AddItem", "Edit", "Redo", 15)
	nm.call(&"AddSeparator", "Edit")
	nm.call(&"AddItem", "Edit", "Copy Token", 16)
	nm.call(&"AddItem", "Edit", "Cut Token", 17)
	nm.call(&"AddItem", "Edit", "Paste Token", 18)
	nm.call(&"AddSeparator", "Edit")
	nm.call(&"AddItem", "Edit", "Calibrate Grid…", 10)
	nm.call(&"AddItem", "Edit", "Set Scale Manually…", 11)
	nm.call(&"AddItem", "Edit", "Set Grid Offset…", 12)
	nm.call(&"AddSeparator", "Edit")
	nm.call(&"AddItem", "Edit", "Player Profiles…", 13)
	# Initial disabled state
	nm.call(&"SetItemDisabled", "Edit", 14, true)
	nm.call(&"SetItemDisabled", "Edit", 15, true)
	nm.call(&"SetItemDisabled", "Edit", 16, true)
	nm.call(&"SetItemDisabled", "Edit", 17, true)
	nm.call(&"SetItemDisabled", "Edit", 18, true)

	# View
	nm.call(&"AddMenu", "View")
	nm.call(&"AddCheckItem", "View", "Toolbar", 20, true)
	nm.call(&"AddCheckItem", "View", "Player Freeze Panel", 25, true)
	nm.call(&"AddCheckItem", "View", "Effect Panel", 29, false)
	nm.call(&"AddCheckItem", "View", "Grid Overlay", 21, true)
	nm.call(&"AddSeparator", "View")
	nm.call(&"AddItem", "View", "Reset View", 22)
	nm.call(&"AddSeparator", "View")
	nm.call(&"AddItem", "View", "Sync Fog Now", 24)
	nm.call(&"AddItem", "View", "Reset Fog…", 27)
	nm.call(&"AddCheckItem", "View", "Fog Overlay Effect", 28, false)
	nm.call(&"AddSeparator", "View")
	nm.call(&"AddItem", "View", "Measurement Tools…", 26)
	nm.call(&"AddItem", "View", "Background Audio…", 31)
	nm.call(&"AddSeparator", "View")

	# Grid Type submenu
	nm.call(&"AddMenu", "GridType")
	nm.call(&"AddRadioCheckItem", "GridType", "□  Square", 0, true)
	nm.call(&"AddRadioCheckItem", "GridType", "⬢  Hex Flat-top", 1, false)
	nm.call(&"AddRadioCheckItem", "GridType", "⬣  Hex Pointy-top", 2, false)
	nm.call(&"AddSubmenu", "View", "GridType", "Grid Type")

	# UI Theme submenu
	nm.call(&"AddMenu", "UITheme")
	nm.call(&"AddRadioCheckItem", "UITheme", "Flat Dark", 0, true)
	nm.call(&"AddRadioCheckItem", "UITheme", "Steel Vault", 1, false)
	nm.call(&"AddRadioCheckItem", "UITheme", "Silver Chrome", 2, false)
	nm.call(&"AddRadioCheckItem", "UITheme", "Forged Iron", 3, false)
	nm.call(&"AddRadioCheckItem", "UITheme", "Arcane", 4, false)
	nm.call(&"AddSubmenu", "View", "UITheme", "UI Theme")

	nm.call(&"AddSeparator", "View")
	nm.call(&"AddItem", "View", "Campaign Hub…", 37)
	nm.call(&"AddItem", "View", "▶ Launch Player Window", 23)

	# Session
	nm.call(&"AddMenu", "Session")
	nm.call(&"AddItem", "Session", "Share Player Link…", 30)

	nm.call(&"Build")

	# Sync initial theme checkmark to persisted setting
	var _nm_theme_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _nm_theme_reg != null and _nm_theme_reg.ui_theme != null:
		var _initial_preset: int = _nm_theme_reg.ui_theme.get_theme()
		nm.call(&"SetRadioChecked", "UITheme", 0, 4, _initial_preset)

	# Route native menu signals to the existing handlers
	nm.connect(&"MenuItemPressed", _on_native_menu_pressed)


func _on_native_menu_pressed(menu_name: String, item_id: int) -> void:
	match menu_name:
		"File": _on_file_menu_id(item_id)
		"Edit": _on_edit_menu_id(item_id)
		"View": _on_view_menu_id(item_id)
		"GridType": _on_grid_submenu_id(item_id)
		"UITheme": _on_theme_submenu_id(item_id)
		"Session": _on_session_menu_id(item_id)


func _nm_set_checked(menu: String, id: int, checked: bool) -> void:
	if _native_menu:
		_native_menu.call(&"SetItemChecked", menu, id, checked)


func _nm_set_disabled(menu: String, id: int, disabled: bool) -> void:
	if _native_menu:
		_native_menu.call(&"SetItemDisabled", menu, id, disabled)


func _nm_set_text(menu: String, id: int, text: String) -> void:
	if _native_menu:
		_native_menu.call(&"SetItemText", menu, id, text)


func _set_view_checked(id: int, on: bool) -> void:
	## Update both the Godot view PopupMenu checkmark and the native Win32 menu bar in one call.
	if _view_menu != null:
		_view_menu.set_item_checked(_view_menu.get_item_index(id), on)
	_nm_set_checked("View", id, on)


# ── Phase 23: character management ───────────────────────────────────────────

func _open_characters_manager() -> void:
	if _char_mgr_dialog == null:
		_build_characters_manager()
	_refresh_chars_list()
	_apply_ui_scale()
	_apply_dialog_themes()
	_char_mgr_dialog.reset_size()
	_char_mgr_dialog.popup_centered(Vector2i(roundi(540.0 * _ui_scale()), roundi(380.0 * _ui_scale())))


func _build_characters_manager() -> void:
	_char_mgr_dialog = AcceptDialog.new()
	_char_mgr_dialog.title = "Characters"
	_char_mgr_dialog.ok_button_text = "Close"
	var s: float = _ui_scale()
	_char_mgr_dialog.min_size = Vector2i(roundi(540.0 * s), roundi(380.0 * s))
	add_child(_char_mgr_dialog)
	_char_mgr_dialog.confirmed.connect(func() -> void: _char_mgr_dialog.hide())
	_char_mgr_dialog.close_requested.connect(func() -> void: _char_mgr_dialog.hide())

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", roundi(6.0 * s))
	_char_mgr_dialog.add_child(root)

	var lbl := Label.new()
	lbl.text = "All Characters (campaign-independent)"
	lbl.add_theme_font_size_override("font_size", roundi(15.0 * s))
	root.add_child(lbl)

	_char_mgr_list = ItemList.new()
	_char_mgr_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_char_mgr_list.add_theme_font_size_override("font_size", roundi(14.0 * s))
	_char_mgr_list.auto_height = true
	_char_mgr_list.item_selected.connect(_on_chars_list_selection_changed)
	root.add_child(_char_mgr_list)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", roundi(6.0 * s))
	root.add_child(btn_row)

	var new_btn := Button.new()
	new_btn.text = "New Character…"
	new_btn.custom_minimum_size = Vector2(roundi(120.0 * s), roundi(30.0 * s))
	new_btn.pressed.connect(_on_chars_new_pressed)
	btn_row.add_child(new_btn)

	var open_btn := Button.new()
	open_btn.text = "Open Sheet"
	open_btn.custom_minimum_size = Vector2(roundi(100.0 * s), roundi(30.0 * s))
	open_btn.pressed.connect(_on_chars_open_sheet_pressed)
	btn_row.add_child(open_btn)

	var level_up_btn := Button.new()
	level_up_btn.text = "Grant Level"
	level_up_btn.custom_minimum_size = Vector2(roundi(100.0 * s), roundi(30.0 * s))
	level_up_btn.pressed.connect(_on_chars_grant_level_pressed)
	btn_row.add_child(level_up_btn)

	_chars_assign_btn = Button.new()
	_chars_assign_btn.text = "Assign to Campaign"
	_chars_assign_btn.custom_minimum_size = Vector2(roundi(140.0 * s), roundi(30.0 * s))
	_chars_assign_btn.disabled = true
	_chars_assign_btn.pressed.connect(_on_chars_assign_pressed)
	btn_row.add_child(_chars_assign_btn)

	_chars_remove_btn = Button.new()
	_chars_remove_btn.text = "Remove from Campaign"
	_chars_remove_btn.custom_minimum_size = Vector2(roundi(160.0 * s), roundi(30.0 * s))
	_chars_remove_btn.disabled = true
	_chars_remove_btn.pressed.connect(_on_chars_remove_from_campaign_pressed)
	btn_row.add_child(_chars_remove_btn)

	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.custom_minimum_size = Vector2(roundi(80.0 * s), roundi(30.0 * s))
	del_btn.pressed.connect(_on_chars_delete_pressed)
	btn_row.add_child(del_btn)


func _refresh_chars_list() -> void:
	if _char_mgr_list == null:
		return
	_char_mgr_list.clear()
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.character == null:
		_char_mgr_list.add_item("(character service unavailable)")
		return
	var chars: Array = registry.character.get_characters()
	if chars.is_empty():
		_char_mgr_list.add_item("(no characters — click New Character…)")
		return
	var campaign_active: bool = registry.campaign != null and registry.campaign.get_active_campaign() != null
	for ch: Variant in chars:
		if not ch is StatblockData:
			continue
		var sb := ch as StatblockData
		var label: String = "%s — %s %d (%s)" % [sb.name, sb.class_name_str, sb.level, sb.race]
		if campaign_active:
			if registry.campaign.has_character(sb.id):
				var cname: String = registry.campaign.get_active_campaign().name
				label += "  [Campaign: %s]" % cname
		_char_mgr_list.add_item(label)
		_char_mgr_list.set_item_metadata(_char_mgr_list.get_item_count() - 1, sb.id)
	_on_chars_list_selection_changed(-1)


func _on_chars_list_selection_changed(_idx: int) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var campaign_active: bool = registry != null and registry.campaign != null and registry.campaign.get_active_campaign() != null
	var selected: PackedInt32Array = _char_mgr_list.get_selected_items() if _char_mgr_list != null else PackedInt32Array()
	var has_sel: bool = not selected.is_empty()
	var ch_id: String = ""
	if has_sel:
		ch_id = str(_char_mgr_list.get_item_metadata(selected[0]))
	var assigned: bool = campaign_active and not ch_id.is_empty() and registry.campaign.has_character(ch_id)
	if _chars_assign_btn != null:
		_chars_assign_btn.disabled = not (has_sel and campaign_active and not assigned)
	if _chars_remove_btn != null:
		_chars_remove_btn.disabled = not (has_sel and assigned)


func _on_chars_new_pressed() -> void:
	if _char_wizard == null:
		_char_wizard = CharacterWizardScript.new()
		add_child(_char_wizard)
		_char_wizard.character_created.connect(_on_char_wizard_character_created)
	_apply_ui_scale()
	_apply_dialog_themes()
	_char_wizard.open_wizard()


func _on_char_wizard_character_created(statblock: StatblockData, profile_id: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.character == null:
		_set_status("Cannot save character: character service unavailable.")
		return
	registry.character.add_character(statblock)
	## Also assign to current campaign if one is active.
	if registry.campaign != null and registry.campaign.get_active_campaign() != null:
		registry.campaign.add_character(statblock.id)
		registry.campaign.save_campaign()
	if not profile_id.is_empty():
		var pm := _profile_service()
		if pm != null:
			var profiles_arr: Array = pm.get_profiles()
			for i: int in profiles_arr.size():
				var item: Variant = profiles_arr[i]
				if item is PlayerProfile:
					var p := item as PlayerProfile
					if p.id == profile_id:
						p.statblock_id = statblock.id
						pm.update_profile_at(i, p)
						break
	_set_status("Character '%s' created." % statblock.name)
	_refresh_chars_list()
	if _campaign_panel != null:
		_campaign_panel.refresh_chars()
	## Auto-open the character sheet so the user can review immediately.
	_open_char_sheet_for(statblock)


func _on_chars_open_sheet_pressed() -> void:
	if _char_mgr_list == null:
		return
	var selected: PackedInt32Array = _char_mgr_list.get_selected_items()
	if selected.is_empty():
		_set_status("Select a character first.")
		return
	var idx: int = selected[0]
	var sb_id: String = str(_char_mgr_list.get_item_metadata(idx))
	if sb_id.is_empty():
		_set_status("No character selected.")
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.character == null:
		_set_status("Character service unavailable.")
		return
	var sb: StatblockData = registry.character.get_character_by_id(sb_id)
	if sb == null:
		_set_status("Character not found.")
		return
	_open_char_sheet_for(sb)


func _on_chars_grant_level_pressed() -> void:
	if _char_mgr_list == null:
		return
	var selected: PackedInt32Array = _char_mgr_list.get_selected_items()
	if selected.is_empty():
		_set_status("Select a character first.")
		return
	var idx: int = selected[0]
	var sb_id: String = str(_char_mgr_list.get_item_metadata(idx))
	if sb_id.is_empty():
		_set_status("No character selected.")
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.character == null:
		_set_status("Character service unavailable.")
		return
	var sb: StatblockData = registry.character.get_character_by_id(sb_id)
	if sb == null:
		_set_status("Character not found.")
		return
	_open_level_up_wizard(sb)


func _on_chars_assign_pressed() -> void:
	if _char_mgr_list == null:
		return
	var selected: PackedInt32Array = _char_mgr_list.get_selected_items()
	if selected.is_empty():
		return
	var ch_id: String = str(_char_mgr_list.get_item_metadata(selected[0]))
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null or registry.campaign.get_active_campaign() == null:
		_set_status("No active campaign loaded.")
		return
	registry.campaign.add_character(ch_id)
	registry.campaign.save_campaign()
	_refresh_chars_list()
	var sb: StatblockData = registry.character.get_character_by_id(ch_id)
	var char_name: String = sb.name if sb != null else ch_id
	_set_status("Assigned '%s' to campaign." % char_name)


func _on_chars_remove_from_campaign_pressed() -> void:
	if _char_mgr_list == null:
		return
	var selected: PackedInt32Array = _char_mgr_list.get_selected_items()
	if selected.is_empty():
		return
	var ch_id: String = str(_char_mgr_list.get_item_metadata(selected[0]))
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.campaign == null or registry.campaign.get_active_campaign() == null:
		return
	registry.campaign.remove_character(ch_id)
	registry.campaign.save_campaign()
	_refresh_chars_list()
	var sb: StatblockData = registry.character.get_character_by_id(ch_id) if registry.character != null else null
	var char_name: String = sb.name if sb != null else ch_id
	_set_status("Removed '%s' from campaign." % char_name)


func _open_char_sheet_for(sb: StatblockData) -> void:
	if _char_sheet == null:
		_char_sheet = CharacterSheetScript.new()
		add_child(_char_sheet)
		_char_sheet.character_saved.connect(_on_char_sheet_saved)
		_char_sheet.level_up_requested.connect(_on_char_sheet_level_up)
		_char_sheet.visibility_changed.connect(_on_char_sheet_visibility_changed)
	# Prompt to save/discard if the sheet already has unsaved edits for a
	# different character.
	if _char_sheet.is_dirty():
		await _char_sheet.prompt_save_or_discard()
	_char_sheet.load_character(sb)
	_char_sheet.reapply_theme()
	if not _char_sheet.is_visible():
		var target_size := Vector2i(roundi(900.0 * _ui_scale()), roundi(750.0 * _ui_scale()))
		_char_sheet.size = target_size
		_show_window_centered(_char_sheet)
	_char_sheet.grab_focus()


func _on_char_sheet_saved(statblock: StatblockData) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.character != null:
		registry.character.add_character(statblock)
	# Sync to StatblockService so tokens see updated data.
	if registry != null and registry.statblock != null:
		registry.statblock.update_statblock(statblock)
	_set_status("Character '%s' saved." % statblock.name)
	_refresh_chars_list()
	if _campaign_panel != null:
		_campaign_panel.refresh_chars()


func _on_char_sheet_visibility_changed() -> void:
	if _char_sheet != null and not _char_sheet.visible:
		# When the character sheet closes on Windows, the OS gives focus to
		# the main window instead of the still-visible campaign hub.  Refocus
		# it so it stays in front.
		if _campaign_panel != null and _campaign_panel.visible:
			_campaign_panel.grab_focus()


func _on_char_sheet_level_up(statblock: StatblockData) -> void:
	_open_level_up_wizard(statblock)


func _open_level_up_wizard(statblock: StatblockData) -> void:
	if _level_up_wizard == null:
		_level_up_wizard = LevelUpWizardScript.new()
		add_child(_level_up_wizard)
		_level_up_wizard.character_leveled_up.connect(_on_character_leveled_up)
	_apply_ui_scale()
	_apply_dialog_themes()
	_level_up_wizard.open(statblock)


func _on_character_leveled_up(statblock: StatblockData) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.character != null:
		registry.character.add_character(statblock)
	if registry != null and registry.statblock != null:
		registry.statblock.update_statblock(statblock)
	_set_status("Character '%s' leveled up to %d." % [statblock.name, statblock.level])
	_refresh_chars_list()
	if _campaign_panel != null:
		_campaign_panel.refresh_chars()
	## Refresh the character sheet if it was open.
	if _char_sheet != null and _char_sheet.is_visible():
		_char_sheet.load_character(statblock)


func _on_chars_delete_pressed() -> void:
	if _char_mgr_list == null:
		return
	var selected: PackedInt32Array = _char_mgr_list.get_selected_items()
	if selected.is_empty():
		_set_status("Select a character to delete.")
		return
	var idx: int = selected[0]
	var ch_id: String = str(_char_mgr_list.get_item_metadata(idx))
	if ch_id.is_empty():
		return
	var ch_name: String = _char_mgr_list.get_item_text(idx)
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete character '%s'? This cannot be undone." % ch_name
	add_child(dlg)
	var _cd_reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if _cd_reg != null and _cd_reg.ui_theme != null:
		_cd_reg.ui_theme.prepare_window(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func() -> void:
		var reg2 := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		if reg2 != null and reg2.character != null:
			## Remove from global roster (also implicitly removes from any campaign reference).
			reg2.character.remove_character(ch_id)
		if reg2 != null and reg2.campaign != null and reg2.campaign.get_active_campaign() != null:
			if reg2.campaign.has_character(ch_id):
				reg2.campaign.remove_character(ch_id)
				reg2.campaign.save_campaign()
		_refresh_chars_list()
		_set_status("Deleted character '%s'." % ch_name)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())


func _on_profile_open_sheet_pressed() -> void:
	if _profile_char_option == null or _profile_char_option.selected < 0:
		return
	var sb_id: String = str(_profile_char_option.get_item_metadata(_profile_char_option.selected))
	if sb_id.is_empty():
		_set_status("No character linked to this profile.")
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.character == null:
		return
	var sb: StatblockData = registry.character.get_character_by_id(sb_id)
	if sb == null:
		_set_status("Linked character not found.")
		return
	_open_char_sheet_for(sb)


func _refresh_profile_char_link_option(current_statblock_id: String) -> void:
	if _profile_char_option == null:
		return
	_profile_char_option.clear()
	_profile_char_option.add_item("— None —")
	_profile_char_option.set_item_metadata(0, "")
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.character == null:
		_profile_char_option.select(0)
		return
	var chars: Array = registry.character.get_characters()
	for i: int in chars.size():
		var ch: Variant = chars[i]
		if not ch is StatblockData:
			continue
		var sb := ch as StatblockData
		_profile_char_option.add_item("%s (%s %d)" % [sb.name, sb.class_name_str, sb.level])
		_profile_char_option.set_item_metadata(i + 1, sb.id)
		if sb.id == current_statblock_id:
			_profile_char_option.select(i + 1)
