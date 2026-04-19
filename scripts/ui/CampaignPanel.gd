extends Window
class_name CampaignPanel

const _CARD_MIN_W: float = 220.0
const _CARD_THUMB_H: float = 160.0
const _SUPPORTED_IMG_EXT: Array = ["png", "jpg", "jpeg", "webp", "bmp", "tga"]

## CampaignPanel — tabbed campaign management hub.
##
## Opens as a floating Window.  Accessed via:
##   File → Campaign Settings…   (TAB_OVERVIEW)
##   Edit → Characters…          (TAB_CHARACTERS, or global manager if no campaign)
##
## Signals delegate specialised operations back to DMWindow.

signal map_open_requested(path: String)
signal save_load_requested(path: String)
signal new_character_requested()
signal edit_character_requested(statblock_id: String)
## Fired when the user wants to create a new map from an image.
signal new_map_requested()
## Fired when the user wants to create a new save.
signal new_save_requested()
## Fired when the user wants to browse existing bundles to link to this campaign.
signal add_map_browse_requested()
signal add_save_browse_requested()
## Fired when the user wants to open a .map or .sav file from the file system.
signal open_map_file_requested()
signal open_save_file_requested()

const TAB_OVERVIEW := 0
const TAB_MAPS := 1
const TAB_SAVES := 2
const TAB_CHARACTERS := 3
const TAB_BESTIARY := 4
const TAB_ITEMS := 5
const TAB_NOTES := 6
const TAB_IMAGES := 7

# ── UI references ─────────────────────────────────────────────────────────────
var _tabs: TabContainer = null

## Overview
var _ov_title_lbl: Label = null
var _ov_name_edit: LineEdit = null
var _ov_desc_edit: TextEdit = null
var _ov_ruleset_opt: OptionButton = null
var _ov_tie_opt: OptionButton = null
var _ov_crit_opt: OptionButton = null
var _ov_exhaustion_opt: OptionButton = null
## Stat count labels [maps, saves, chars, notes, images]
var _ov_stat_labels: Array = []

## Card styles (shared by maps, saves, characters grids)
var _card_normal: StyleBoxFlat = null
var _card_hover: StyleBoxFlat = null
var _card_selected: StyleBoxFlat = null

## Maps
var _maps_grid: GridContainer = null
var _maps_scroll: ScrollContainer = null
var _maps_search_edit: LineEdit = null
var _maps_empty_lbl: Label = null
var _maps_selected_path: String = ""
var _maps_open_btn: Button = null
var _maps_add_btn: Button = null
var _maps_link_btn: Button = null

## Saves
var _saves_grid: GridContainer = null
var _saves_scroll: ScrollContainer = null
var _saves_search_edit: LineEdit = null
var _saves_empty_lbl: Label = null
var _saves_selected_path: String = ""
var _saves_open_btn: Button = null
var _saves_add_btn: Button = null
var _saves_link_btn: Button = null

## Characters
var _chars_grid: GridContainer = null
var _chars_empty_lbl: Label = null
var _chars_selected_id: String = ""
var _chars_show_all_chk: CheckBox = null
var _chars_sheet_btn: Button = null
var _chars_assign_btn: Button = null
var _chars_remove_btn: Button = null
var _chars_delete_btn: Button = null
var _chars_override_btn: Button = null

## Bestiary
var _bestiary_list: ItemList = null
var _bestiary_card: StatblockCardView = null
var _bestiary_library: StatblockLibrary = null

## Items
var _items_list: ItemList = null
var _items_card: ItemCardView = null
var _items_library: ItemLibrary = null
var _bestiary_dlg: Window = null
var _bestiary_editing_id: String = ""
## If non-empty, the old bestiary key to remove on save (handles SRD→custom promotion).
var _bestiary_editing_old_key: String = ""
## Bestiary dialog field controls (keyed by field name)
var _bst: Dictionary = {}

## Notes
var _notes_tree: Tree = null
var _notes_ctx_menu: PopupMenu = null
var _notes_title_edit: LineEdit = null
var _notes_folder_opt: OptionButton = null
var _notes_body_edit: TextEdit = null
var _notes_current_id: String = ""

## Images
var _images_tree: Tree = null
var _images_ctx_menu: PopupMenu = null
var _images_preview: TextureRect = null
var _images_path_label: Label = null
var _images_copy_chk: CheckBox = null
var _images_file_dialog: FileDialog = null
var _images_current_id: String = ""

## Clipboard state (shared across notes & images)
var _clipboard_tree: Tree = null ## which tree the copied items belong to
var _clipboard_items: Array = [] ## Array of {type:String, id:String, folder:String}
var _clipboard_mode: String = "" ## "cut" or "copy"

## Single-level undo state
var _undo_action: String = "" ## "move_note" | "move_image" | "move_folder"
var _undo_data: Dictionary = {} ## action-specific payload

## Shared inline-edit overlay state (only one edit at a time)
var _tree_edit_line: LineEdit = null
var _tree_edit_owner: Tree = null
var _tree_edit_item: TreeItem = null
var _tree_edit_action: String = "" ## "new_folder" | "rename"


func _ready() -> void:
	title = "Campaign"
	min_size = Vector2i(920, 640)
	# Disable wrap_controls so we own the window size entirely via
	# _show_window_centered().  wrap_controls computes content minimums only
	# after a real draw pass, which on Windows causes a very large initial
	# layout for the Maps tab (GridContainer height leaks through
	# ScrollContainer before the first render pass settles).
	wrap_controls = false
	popup_window = false
	exclusive = false
	transient = true
	close_requested.connect(func() -> void: hide())
	_build_ui()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and key.ctrl_pressed and key.keycode == KEY_Z:
		_undo_last_move()
		get_viewport().set_input_as_handled()


## Open to a specific tab.  Call before popup_centered().
func open_to_tab(tab_index: int = TAB_OVERVIEW) -> void:
	_refresh_all()
	if _tabs != null:
		_tabs.current_tab = tab_index
	var reg := _registry()
	var c: CampaignData = reg.campaign.get_active_campaign() if reg != null and reg.campaign != null else null
	title = ("Campaign \u2014 %s" % c.name) if c != null else "Campaign (no active campaign)"


## Called by DMWindow after linking a bundle via BundleBrowser pick mode.
func refresh_maps() -> void:
	_refresh_maps_list()
	_refresh_overview()


## Called by DMWindow after linking a bundle via BundleBrowser pick mode.
func refresh_saves() -> void:
	_refresh_saves_list()
	_refresh_overview()


## Called by DMWindow after character creation or update.
func refresh_chars() -> void:
	_refresh_chars_list()
	_refresh_overview()


func _registry() -> ServiceRegistry:
	return get_node_or_null("/root/ServiceRegistry") as ServiceRegistry


func _scale() -> float:
	var reg := _registry()
	if reg != null and reg.ui_scale != null:
		return reg.ui_scale.get_scale()
	return 1.0


# ─── Build UI ─────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var s: float = _scale()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", roundi(10.0 * s))
	margin.add_theme_constant_override("margin_right", roundi(10.0 * s))
	margin.add_theme_constant_override("margin_top", roundi(8.0 * s))
	margin.add_theme_constant_override("margin_bottom", roundi(8.0 * s))
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", roundi(8.0 * s))
	margin.add_child(root_vbox)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", roundi(14.0 * s))
	root_vbox.add_child(_tabs)

	_build_overview_tab(s)
	_build_maps_tab(s)
	_build_saves_tab(s)
	_build_characters_tab(s)
	_build_bestiary_tab(s)
	_build_items_tab(s)
	_build_notes_tab(s)
	_build_images_tab(s)

	var btn_row := HBoxContainer.new()
	root_vbox.add_child(btn_row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(roundi(100.0 * s), roundi(32.0 * s))
	close_btn.add_theme_font_size_override("font_size", roundi(13.0 * s))
	close_btn.pressed.connect(func() -> void: hide())
	btn_row.add_child(close_btn)

	var reg := _registry()
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(self , s)
	# ── Tab bar styles (matches BundleBrowser palette) ────────────────────────
	var accent: Dictionary = {}
	if reg != null and reg.ui_theme != null:
		accent = reg.ui_theme.get_accent_palette()
	var tab_normal_bg: Color = accent.get("normal_bg", Color(0.22, 0.22, 0.24)) as Color
	var tab_hover_bg: Color = accent.get("hover_bg", Color(0.28, 0.28, 0.30)) as Color
	var tab_selected_bg: Color = accent.get("panel_bg", Color(0.18, 0.18, 0.20)) as Color
	var tab_border: Color = accent.get("panel_border", Color(0.35, 0.35, 0.38)) as Color
	var tab_selected_border: Color = accent.get("selected_border", Color(0.4, 0.6, 1.0)) as Color
	var tab_font: Color = accent.get("label_tint", Color(0.75, 0.75, 0.75)) as Color
	var tab_corner: int = roundi(4.0 * s)
	var tab_pad_v: int = roundi(8.0 * s)
	var tab_pad_h: int = roundi(14.0 * s)
	var ts_unselected := StyleBoxFlat.new()
	ts_unselected.bg_color = tab_normal_bg
	ts_unselected.set_corner_radius_all(tab_corner)
	ts_unselected.corner_radius_bottom_left = 0
	ts_unselected.corner_radius_bottom_right = 0
	ts_unselected.set_content_margin(SIDE_TOP, tab_pad_v)
	ts_unselected.set_content_margin(SIDE_BOTTOM, tab_pad_v)
	ts_unselected.set_content_margin(SIDE_LEFT, tab_pad_h)
	ts_unselected.set_content_margin(SIDE_RIGHT, tab_pad_h)
	ts_unselected.set_border_width_all(1)
	ts_unselected.border_color = tab_border
	var ts_hovered := ts_unselected.duplicate() as StyleBoxFlat
	ts_hovered.bg_color = tab_hover_bg
	ts_hovered.border_color = tab_border.lightened(0.2)
	var ts_selected := ts_unselected.duplicate() as StyleBoxFlat
	ts_selected.bg_color = tab_selected_bg
	ts_selected.border_color = tab_selected_border
	ts_selected.border_width_top = roundi(2.0 * s)
	ts_selected.border_width_bottom = 0
	_tabs.add_theme_stylebox_override("tab_unselected", ts_unselected)
	_tabs.add_theme_stylebox_override("tab_hovered", ts_hovered)
	_tabs.add_theme_stylebox_override("tab_selected", ts_selected)
	_tabs.add_theme_color_override("font_unselected_color", tab_font.darkened(0.2))
	_tabs.add_theme_color_override("font_hovered_color", tab_font)
	_tabs.add_theme_color_override("font_selected_color", tab_font.lightened(0.2))
	size_changed.connect(_on_size_changed)


# ─── Tab builders ─────────────────────────────────────────────────────────────

func _build_overview_tab(s: float) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Overview"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)

	var tab := VBoxContainer.new()
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", roundi(10.0 * s))
	scroll.add_child(tab)

	# ── Campaign name header ─────────────────────────────────────────────
	_ov_title_lbl = Label.new()
	_ov_title_lbl.text = "(no campaign)"
	_ov_title_lbl.add_theme_font_size_override("font_size", roundi(20.0 * s))
	_ov_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tab.add_child(_ov_title_lbl)

	# ── Stats row — clickable tiles that jump to the relevant tab ────────
	var stats_data: Array = [
		["Maps", TAB_MAPS], ["Saves", TAB_SAVES],
		["Characters", TAB_CHARACTERS], ["Notes", TAB_NOTES], ["Images", TAB_IMAGES],
	]
	_ov_stat_labels.clear()

	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", roundi(8.0 * s))
	tab.add_child(stats_row)

	for entry: Array in stats_data:
		var label_text: String = str(entry[0])
		var tab_idx: int = int(entry[1])

		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0.0, roundi(56.0 * s))
		btn.text = "0\n%s" % label_text
		btn.add_theme_font_size_override("font_size", roundi(13.0 * s))
		btn.tooltip_text = "Go to %s tab" % label_text
		btn.pressed.connect(func() -> void:
			if _tabs != null:
				_tabs.current_tab = tab_idx
		)
		stats_row.add_child(btn)
		_ov_stat_labels.append(btn)

	tab.add_child(HSeparator.new())

	# ── Campaign settings section ────────────────────────────────────────
	var settings_lbl := Label.new()
	settings_lbl.text = "Campaign Settings"
	settings_lbl.add_theme_font_size_override("font_size", roundi(14.0 * s))
	tab.add_child(settings_lbl)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", roundi(8.0 * s))
	grid.add_theme_constant_override("v_separation", roundi(8.0 * s))
	tab.add_child(grid)

	_add_lbl(grid, "Campaign Name", s)
	_ov_name_edit = LineEdit.new()
	_ov_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ov_name_edit.add_theme_font_size_override("font_size", roundi(13.0 * s))
	grid.add_child(_ov_name_edit)

	_add_lbl(grid, "Ruleset", s)
	_ov_ruleset_opt = OptionButton.new()
	_ov_ruleset_opt.add_item("2014 (SRD 5e)")
	_ov_ruleset_opt.add_item("2024 (SRD 5e Revised)")
	_ov_ruleset_opt.add_theme_font_size_override("font_size", roundi(13.0 * s))
	grid.add_child(_ov_ruleset_opt)

	_add_lbl(grid, "Tie Goes To", s)
	_ov_tie_opt = OptionButton.new()
	_ov_tie_opt.add_item("Player")
	_ov_tie_opt.add_item("Monster / DM")
	_ov_tie_opt.add_theme_font_size_override("font_size", roundi(13.0 * s))
	grid.add_child(_ov_tie_opt)

	_add_lbl(grid, "Critical Hit Rule", s)
	_ov_crit_opt = OptionButton.new()
	_ov_crit_opt.add_item("Double Dice")
	_ov_crit_opt.add_item("Max + Roll")
	_ov_crit_opt.add_theme_font_size_override("font_size", roundi(13.0 * s))
	grid.add_child(_ov_crit_opt)

	_add_lbl(grid, "Exhaustion Rule", s)
	_ov_exhaustion_opt = OptionButton.new()
	_ov_exhaustion_opt.add_item("2014 (6 Levels)")
	_ov_exhaustion_opt.add_item("2024 (-2 per Level)")
	_ov_exhaustion_opt.add_theme_font_size_override("font_size", roundi(13.0 * s))
	grid.add_child(_ov_exhaustion_opt)

	var desc_lbl := Label.new()
	desc_lbl.text = "Description"
	desc_lbl.add_theme_font_size_override("font_size", roundi(13.0 * s))
	tab.add_child(desc_lbl)

	_ov_desc_edit = TextEdit.new()
	_ov_desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ov_desc_edit.custom_minimum_size.y = roundi(80.0 * s)
	_ov_desc_edit.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_ov_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	tab.add_child(_ov_desc_edit)

	var save_btn := Button.new()
	save_btn.text = "Save Changes"
	save_btn.custom_minimum_size = Vector2(roundi(130.0 * s), roundi(30.0 * s))
	save_btn.add_theme_font_size_override("font_size", roundi(13.0 * s))
	save_btn.pressed.connect(_on_overview_save)
	tab.add_child(save_btn)


func _build_maps_tab(s: float) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Maps"
	tab.add_theme_constant_override("separation", roundi(6.0 * s))
	_tabs.add_child(tab)

	_maps_search_edit = LineEdit.new()
	_maps_search_edit.placeholder_text = "Search maps\u2026"
	_maps_search_edit.clear_button_enabled = true
	_maps_search_edit.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_maps_search_edit.text_changed.connect(func(_t: String) -> void: _refresh_maps_list())
	tab.add_child(_maps_search_edit)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)

	_maps_scroll = scroll

	_maps_grid = GridContainer.new()
	_maps_grid.columns = _calc_columns()
	_maps_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_maps_grid.add_theme_constant_override("h_separation", roundi(10.0 * s))
	_maps_grid.add_theme_constant_override("v_separation", roundi(10.0 * s))
	scroll.add_child(_maps_grid)

	_maps_empty_lbl = Label.new()
	_maps_empty_lbl.text = "No maps yet.  Use \u201cNew\u201d to create one or \u201cBrowse\u2026\u201d to link a map from your library."
	_maps_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_maps_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_maps_empty_lbl.add_theme_font_size_override("font_size", roundi(14.0 * s))
	_maps_empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_maps_empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_maps_empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_maps_empty_lbl.hide()
	tab.add_child(_maps_empty_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(8.0 * s))
	tab.add_child(row)

	_make_btn(row, "New", s, _on_maps_new)
	var _maps_folder_btn := _make_btn(row, "📁", s, _on_maps_open_file)
	_maps_folder_btn.custom_minimum_size = Vector2(roundi(36.0 * s), roundi(32.0 * s))
	_maps_folder_btn.add_theme_font_size_override("font_size", roundi(15.0 * s))
	_maps_folder_btn.tooltip_text = "Open .map file\u2026"
	var _maps_spacer := Control.new()
	_maps_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_maps_spacer)
	_maps_add_btn = _make_btn(row, "Browse\u2026", s, _on_maps_add)
	_maps_link_btn = _make_btn(row, "Unlink", s, _on_maps_remove)
	_maps_link_btn.disabled = true
	_maps_open_btn = _make_btn(row, "Open", s, _on_maps_open)
	_maps_open_btn.disabled = true


func _build_saves_tab(s: float) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Saves"
	tab.add_theme_constant_override("separation", roundi(6.0 * s))
	_tabs.add_child(tab)

	_saves_search_edit = LineEdit.new()
	_saves_search_edit.placeholder_text = "Search saves\u2026"
	_saves_search_edit.clear_button_enabled = true
	_saves_search_edit.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_saves_search_edit.text_changed.connect(func(_t: String) -> void: _refresh_saves_list())
	tab.add_child(_saves_search_edit)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)

	_saves_scroll = scroll

	_saves_grid = GridContainer.new()
	_saves_grid.columns = _calc_columns()
	_saves_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saves_grid.add_theme_constant_override("h_separation", roundi(10.0 * s))
	_saves_grid.add_theme_constant_override("v_separation", roundi(10.0 * s))
	scroll.add_child(_saves_grid)

	_saves_empty_lbl = Label.new()
	_saves_empty_lbl.text = "No saves yet.  Use \u201cBrowse\u2026\u201d to link a save from your library."
	_saves_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_saves_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_saves_empty_lbl.add_theme_font_size_override("font_size", roundi(14.0 * s))
	_saves_empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_saves_empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_saves_empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_saves_empty_lbl.hide()
	tab.add_child(_saves_empty_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(8.0 * s))
	tab.add_child(row)

	_make_btn(row, "New", s, _on_saves_new)
	var _saves_folder_btn := _make_btn(row, "📁", s, _on_saves_open_file)
	_saves_folder_btn.custom_minimum_size = Vector2(roundi(36.0 * s), roundi(32.0 * s))
	_saves_folder_btn.add_theme_font_size_override("font_size", roundi(15.0 * s))
	_saves_folder_btn.tooltip_text = "Open .sav file\u2026"
	var _saves_spacer := Control.new()
	_saves_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_saves_spacer)
	_saves_add_btn = _make_btn(row, "Browse\u2026", s, _on_saves_add)
	_saves_link_btn = _make_btn(row, "Unlink", s, _on_saves_remove)
	_saves_link_btn.disabled = true
	_saves_open_btn = _make_btn(row, "Open", s, _on_saves_open)
	_saves_open_btn.disabled = true


func _build_characters_tab(s: float) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Characters"
	tab.add_theme_constant_override("separation", roundi(6.0 * s))
	_tabs.add_child(tab)

	_chars_show_all_chk = CheckBox.new()
	_chars_show_all_chk.text = "Show all characters (not just those assigned to this campaign)"
	_chars_show_all_chk.add_theme_font_size_override("font_size", roundi(12.0 * s))
	_chars_show_all_chk.toggled.connect(func(_v: bool) -> void: _refresh_chars_list())
	tab.add_child(_chars_show_all_chk)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab.add_child(scroll)

	_chars_grid = GridContainer.new()
	_chars_grid.columns = 4
	_chars_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chars_grid.add_theme_constant_override("h_separation", roundi(8.0 * s))
	_chars_grid.add_theme_constant_override("v_separation", roundi(8.0 * s))
	scroll.add_child(_chars_grid)

	_chars_empty_lbl = Label.new()
	_chars_empty_lbl.text = "No characters found."
	_chars_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_chars_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_chars_empty_lbl.add_theme_font_size_override("font_size", roundi(14.0 * s))
	_chars_empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_chars_empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chars_empty_lbl.hide()
	tab.add_child(_chars_empty_lbl)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(6.0 * s))
	tab.add_child(row)

	_make_btn(row, "New Character\u2026", s, func() -> void: new_character_requested.emit())
	_chars_sheet_btn = _make_btn(row, "Open Sheet", s, _on_chars_open_sheet)
	_chars_sheet_btn.disabled = true
	_chars_assign_btn = _make_btn(row, "Assign to Campaign", s, _on_chars_assign)
	_chars_assign_btn.disabled = true
	_chars_remove_btn = _make_btn(row, "Remove from Campaign", s, _on_chars_remove_from_campaign)
	_chars_remove_btn.disabled = true
	_chars_override_btn = _make_btn(row, "Customize\u2026", s, _on_chars_edit_override)
	_chars_override_btn.disabled = true
	_chars_delete_btn = _make_btn(row, "Delete", s, _on_chars_delete)
	_chars_delete_btn.disabled = true


func _build_bestiary_tab(s: float) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Bestiary"
	tab.add_theme_constant_override("separation", roundi(6.0 * s))
	_tabs.add_child(tab)

	var lbl := Label.new()
	lbl.text = "Campaign bestiary \u2014 monsters and NPCs for this campaign:"
	lbl.add_theme_font_size_override("font_size", roundi(13.0 * s))
	tab.add_child(lbl)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = roundi(220.0 * s)
	tab.add_child(split)

	_bestiary_list = ItemList.new()
	_bestiary_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bestiary_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bestiary_list.custom_minimum_size = Vector2(roundi(180.0 * s), 0)
	_bestiary_list.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_bestiary_list.item_selected.connect(_on_bestiary_item_selected)
	split.add_child(_bestiary_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	var card_scroll := ScrollContainer.new()
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(card_scroll)

	_bestiary_card = StatblockCardView.new()
	_bestiary_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(_bestiary_card)
	_bestiary_card.apply_font_scale(roundi(14.0 * s))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(6.0 * s))
	tab.add_child(row)

	_make_btn(row, "Add from Library\u2026", s, _on_bestiary_add)
	_make_btn(row, "Edit\u2026", s, _on_bestiary_edit)
	_make_btn(row, "Remove", s, _on_bestiary_remove)


func _build_items_tab(s: float) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Items"
	tab.add_theme_constant_override("separation", roundi(6.0 * s))
	_tabs.add_child(tab)

	var lbl := Label.new()
	lbl.text = "Campaign item library \u2014 equipment and treasure for this campaign:"
	lbl.add_theme_font_size_override("font_size", roundi(13.0 * s))
	tab.add_child(lbl)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = roundi(220.0 * s)
	tab.add_child(split)

	_items_list = ItemList.new()
	_items_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_items_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_list.custom_minimum_size = Vector2(roundi(180.0 * s), 0)
	_items_list.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_items_list.item_selected.connect(_on_items_item_selected)
	split.add_child(_items_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	var card_scroll := ScrollContainer.new()
	card_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(card_scroll)

	_items_card = ItemCardView.new()
	_items_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(_items_card)
	_items_card.apply_font_scale(roundi(14.0 * s))

	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", roundi(6.0 * s))
	tab.add_child(item_row)

	_make_btn(item_row, "Add from Library\u2026", s, _on_items_add)
	_make_btn(item_row, "Remove", s, _on_items_remove)


func _build_notes_tab(s: float) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Notes"
	tab.add_theme_constant_override("separation", roundi(6.0 * s))
	_tabs.add_child(tab)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = roundi(180.0 * s)
	tab.add_child(split)

	## Left pane — folder / note tree
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = roundi(120.0 * s)
	left.add_theme_constant_override("separation", roundi(4.0 * s))
	split.add_child(left)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", roundi(2.0 * s))
	left.add_child(toolbar)
	var new_note_btn := Button.new()
	new_note_btn.text = "📄"
	new_note_btn.tooltip_text = "New note"
	new_note_btn.custom_minimum_size = Vector2(roundi(28.0 * s), roundi(28.0 * s))
	new_note_btn.add_theme_font_size_override("font_size", roundi(14.0 * s))
	new_note_btn.pressed.connect(_on_note_new)
	toolbar.add_child(new_note_btn)
	var new_folder_btn := Button.new()
	new_folder_btn.text = "📁"
	new_folder_btn.tooltip_text = "New folder"
	new_folder_btn.custom_minimum_size = Vector2(roundi(28.0 * s), roundi(28.0 * s))
	new_folder_btn.add_theme_font_size_override("font_size", roundi(14.0 * s))
	new_folder_btn.pressed.connect(_on_note_new_folder)
	toolbar.add_child(new_folder_btn)

	_notes_tree = Tree.new()
	_notes_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_tree.hide_root = true
	_notes_tree.allow_reselect = true
	_notes_tree.allow_rmb_select = true
	_notes_tree.item_selected.connect(_on_note_tree_selected)
	_notes_tree.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_notes_tree.clip_contents = true
	_notes_tree.set_drag_forwarding(_notes_get_drag_data, _notes_can_drop_data, _notes_drop_data)
	left.add_child(_notes_tree)

	_notes_ctx_menu = PopupMenu.new()
	_notes_ctx_menu.add_item("Cut", 10)
	_notes_ctx_menu.add_item("Copy", 11)
	_notes_ctx_menu.add_item("Paste", 12)
	_notes_ctx_menu.add_separator()
	_notes_ctx_menu.add_item("Rename", 0)
	_notes_ctx_menu.add_item("Delete", 1)
	_notes_ctx_menu.add_separator()
	_notes_ctx_menu.add_item("New Note", 2)
	_notes_ctx_menu.add_item("New Folder", 3)
	_notes_ctx_menu.id_pressed.connect(_on_notes_ctx_action)
	add_child(_notes_ctx_menu)
	_notes_tree.item_mouse_selected.connect(_on_notes_tree_rmb)

	## Right pane — note editor
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", roundi(6.0 * s))
	split.add_child(right)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", roundi(8.0 * s))
	right.add_child(header_row)

	_notes_title_edit = LineEdit.new()
	_notes_title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_title_edit.placeholder_text = "Note title…"
	_notes_title_edit.add_theme_font_size_override("font_size", roundi(16.0 * s))
	_notes_title_edit.text_changed.connect(_on_note_title_changed)
	header_row.add_child(_notes_title_edit)

	_notes_folder_opt = OptionButton.new()
	_notes_folder_opt.custom_minimum_size.x = roundi(140.0 * s)
	_notes_folder_opt.add_theme_font_size_override("font_size", roundi(12.0 * s))
	_notes_folder_opt.tooltip_text = "Move to folder"
	_notes_folder_opt.item_selected.connect(_on_note_folder_changed)
	header_row.add_child(_notes_folder_opt)

	_notes_body_edit = TextEdit.new()
	_notes_body_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_body_edit.placeholder_text = "Write your note here…"
	_notes_body_edit.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_notes_body_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_notes_body_edit.text_changed.connect(_on_note_body_changed)
	right.add_child(_notes_body_edit)

	_notes_set_editor_enabled(false)


func _build_images_tab(s: float) -> void:
	var tab := VBoxContainer.new()
	tab.name = "Images"
	tab.add_theme_constant_override("separation", roundi(6.0 * s))
	_tabs.add_child(tab)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = roundi(180.0 * s)
	tab.add_child(split)

	## Left pane: image tree
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = roundi(120.0 * s)
	left.add_theme_constant_override("separation", roundi(4.0 * s))
	split.add_child(left)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", roundi(2.0 * s))
	left.add_child(toolbar)
	var add_img_btn := Button.new()
	add_img_btn.text = "➕"
	add_img_btn.tooltip_text = "Add image…"
	add_img_btn.custom_minimum_size = Vector2(roundi(28.0 * s), roundi(28.0 * s))
	add_img_btn.add_theme_font_size_override("font_size", roundi(14.0 * s))
	add_img_btn.pressed.connect(_on_image_add)
	toolbar.add_child(add_img_btn)
	var new_folder_btn := Button.new()
	new_folder_btn.text = "📁"
	new_folder_btn.tooltip_text = "New folder"
	new_folder_btn.custom_minimum_size = Vector2(roundi(28.0 * s), roundi(28.0 * s))
	new_folder_btn.add_theme_font_size_override("font_size", roundi(14.0 * s))
	new_folder_btn.pressed.connect(_on_image_new_folder)
	toolbar.add_child(new_folder_btn)

	_images_copy_chk = CheckBox.new()
	_images_copy_chk.text = "Copy into campaign"
	_images_copy_chk.button_pressed = true
	_images_copy_chk.add_theme_font_size_override("font_size", roundi(11.0 * s))
	toolbar.add_child(_images_copy_chk)

	_images_tree = Tree.new()
	_images_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_images_tree.hide_root = true
	_images_tree.allow_reselect = true
	_images_tree.allow_rmb_select = true
	_images_tree.item_selected.connect(_on_image_tree_selected)
	_images_tree.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_images_tree.clip_contents = true
	_images_tree.set_drag_forwarding(_images_get_drag_data, _images_can_drop_data, _images_drop_data)
	left.add_child(_images_tree)

	_images_ctx_menu = PopupMenu.new()
	_images_ctx_menu.add_item("Cut", 10)
	_images_ctx_menu.add_item("Copy", 11)
	_images_ctx_menu.add_item("Paste", 12)
	_images_ctx_menu.add_separator()
	_images_ctx_menu.add_item("Rename", 0)
	_images_ctx_menu.add_item("Delete", 1)
	_images_ctx_menu.add_separator()
	_images_ctx_menu.add_item("Add Image…", 5)
	_images_ctx_menu.add_item("Move to Folder…", 2)
	_images_ctx_menu.add_item("New Folder", 3)
	_images_ctx_menu.add_item("Open in System Viewer", 4)
	_images_ctx_menu.id_pressed.connect(_on_images_ctx_action)
	add_child(_images_ctx_menu)
	_images_tree.item_mouse_selected.connect(_on_images_tree_rmb)

	## Persistent native file dialog for adding images
	_images_file_dialog = FileDialog.new()
	_images_file_dialog.use_native_dialog = true
	_images_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_images_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_images_file_dialog.filters = ["*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.tga ; Image Files"]
	_images_file_dialog.title = "Select an Image"
	_images_file_dialog.file_selected.connect(_on_image_file_selected)
	add_child(_images_file_dialog)

	## Right pane: preview
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", roundi(4.0 * s))
	split.add_child(right)

	_images_preview = TextureRect.new()
	_images_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_images_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_images_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_images_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(_images_preview)

	_images_path_label = Label.new()
	_images_path_label.add_theme_font_size_override("font_size", roundi(11.0 * s))
	_images_path_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_images_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_images_path_label)


# ─── Refresh / Populate ───────────────────────────────────────────────────────

func _refresh_all() -> void:
	_refresh_overview()
	_refresh_maps_list()
	_refresh_saves_list()
	_refresh_chars_list()
	_refresh_bestiary_list()
	_refresh_items_list()
	_refresh_notes_list()
	_refresh_images_list()


func _refresh_overview() -> void:
	var reg := _registry()
	var c: CampaignData = reg.campaign.get_active_campaign() if reg != null and reg.campaign != null else null
	if c == null:
		if _ov_title_lbl != null:
			_ov_title_lbl.text = "(no active campaign)"
		return
	if _ov_title_lbl != null:
		_ov_title_lbl.text = c.name
	if _ov_name_edit != null:
		_ov_name_edit.text = c.name
	if _ov_desc_edit != null:
		_ov_desc_edit.text = c.description
	if _ov_ruleset_opt != null:
		_ov_ruleset_opt.selected = 1 if c.default_ruleset == "2024" else 0
	if _ov_tie_opt != null:
		_ov_tie_opt.selected = 1 if str(c.settings.get("tie_goes_to", "player")) == "monster" else 0
	if _ov_crit_opt != null:
		_ov_crit_opt.selected = 1 if str(c.settings.get("critical_hit_rule", "double_dice")) == "max_plus_roll" else 0
	if _ov_exhaustion_opt != null:
		_ov_exhaustion_opt.selected = 1 if str(c.settings.get("exhaustion_rule", "2014")) == "2024" else 0
	# Update stat tiles
	var counts: Array = [
		reg.campaign.get_map_paths().size() if reg.campaign != null else 0,
		reg.campaign.get_save_paths().size() if reg.campaign != null else 0,
		c.character_ids.size(),
		c.notes.size(),
		c.images.size(),
	]
	var tab_labels: Array = ["Maps", "Saves", "Characters", "Notes", "Images"]
	for i: int in _ov_stat_labels.size():
		var btn := _ov_stat_labels[i] as Button
		if btn != null:
			btn.text = "%d\n%s" % [counts[i], tab_labels[i]]


func _refresh_maps_list() -> void:
	if _maps_grid == null:
		return
	_maps_selected_path = ""
	for child: Node in _maps_grid.get_children():
		_maps_grid.remove_child(child)
		child.queue_free()
	_update_maps_btns()
	var reg := _registry()
	if reg == null or reg.campaign == null or reg.campaign.get_active_campaign() == null:
		if _maps_empty_lbl != null:
			_maps_empty_lbl.show()
		return
	var s: float = _scale()
	var filter: String = _maps_search_edit.text.strip_edges().to_lower() if _maps_search_edit != null else ""
	var pm: PersistenceManager = reg.persistence
	var count: int = 0
	for raw: Variant in reg.campaign.get_map_paths():
		var abs_p: String = ProjectSettings.globalize_path(str(raw))
		if not filter.is_empty() and abs_p.get_file().to_lower().find(filter) == -1:
			continue
		var meta: Dictionary = pm.load_bundle_metadata(abs_p) if pm != null else {}
		var data := {
			"bundle_path": abs_p,
			"name": meta.get("name", abs_p.get_file().get_basename()) as String,
			"thumbnail_path": meta.get("thumbnail_path", "") as String,
			"modified_time": int(meta.get("modified_time", 0)),
		}
		var card_node: PanelContainer = _build_bundle_card(data, s, true)
		_maps_grid.add_child(card_node)
		_load_thumbnail_deferred.call_deferred(data, card_node, true)
		count += 1
	if _maps_empty_lbl != null:
		_maps_empty_lbl.visible = count == 0
	if _maps_scroll != null:
		_maps_scroll.visible = count > 0


func _refresh_saves_list() -> void:
	if _saves_grid == null:
		return
	_saves_selected_path = ""
	for child: Node in _saves_grid.get_children():
		_saves_grid.remove_child(child)
		child.queue_free()
	_update_saves_btns()
	var reg := _registry()
	if reg == null or reg.campaign == null or reg.campaign.get_active_campaign() == null:
		if _saves_empty_lbl != null:
			_saves_empty_lbl.show()
		return
	var s: float = _scale()
	var filter: String = _saves_search_edit.text.strip_edges().to_lower() if _saves_search_edit != null else ""
	var pm: PersistenceManager = reg.persistence
	var count: int = 0
	for raw: Variant in reg.campaign.get_save_paths():
		var abs_p: String = ProjectSettings.globalize_path(str(raw))
		if not filter.is_empty() and abs_p.get_file().to_lower().find(filter) == -1:
			continue
		var meta: Dictionary = pm.load_bundle_metadata(abs_p) if pm != null else {}
		var data := {
			"bundle_path": abs_p,
			"name": meta.get("name", abs_p.get_file().get_basename()) as String,
			"thumbnail_path": meta.get("thumbnail_path", "") as String,
			"modified_time": int(meta.get("modified_time", 0)),
		}
		var card_node: PanelContainer = _build_bundle_card(data, s, false)
		_saves_grid.add_child(card_node)
		_load_thumbnail_deferred.call_deferred(data, card_node, false)
		count += 1
	if _saves_empty_lbl != null:
		_saves_empty_lbl.visible = count == 0
	if _saves_scroll != null:
		_saves_scroll.visible = count > 0


func _refresh_chars_list() -> void:
	if _chars_grid == null:
		return
	_chars_selected_id = ""
	for child: Node in _chars_grid.get_children():
		_chars_grid.remove_child(child)
		child.queue_free()
	_update_chars_btns()
	var reg := _registry()
	if reg == null or reg.character == null:
		if _chars_empty_lbl != null:
			_chars_empty_lbl.show()
		return
	var campaign_active: bool = reg.campaign != null and reg.campaign.get_active_campaign() != null
	var show_all: bool = _chars_show_all_chk != null and _chars_show_all_chk.button_pressed
	var s: float = _scale()
	var count: int = 0
	for ch: Variant in reg.character.get_characters():
		if not ch is StatblockData:
			continue
		var sb := ch as StatblockData
		var in_campaign: bool = campaign_active and reg.campaign.has_character(sb.id)
		if not show_all and not in_campaign:
			continue
		_chars_grid.add_child(_build_character_card(sb, s, in_campaign))
		count += 1
	if _chars_empty_lbl != null:
		_chars_empty_lbl.visible = count == 0


func _refresh_bestiary_list() -> void:
	if _bestiary_list == null:
		return
	_bestiary_list.clear()
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	for entry: Variant in reg.campaign.get_bestiary():
		if entry is StatblockData:
			var sb := entry as StatblockData
			var display_text: String = sb.name
			if not sb.creature_type.is_empty():
				display_text += " (%s)" % sb.creature_type
			elif not sb.class_name_str.is_empty():
				display_text += " (%s %d)" % [sb.class_name_str, sb.level]
			var is_srd: bool = not sb.srd_index.is_empty() and sb.source.begins_with("SRD")
			if is_srd:
				display_text += " [SRD]"
			_bestiary_list.add_item(display_text)
			## Key matches the bestiary dict key: srd_index for SRD, id for custom.
			var bst_key: String = sb.srd_index if is_srd else sb.id
			_bestiary_list.set_item_metadata(_bestiary_list.get_item_count() - 1, bst_key)


func _refresh_items_list() -> void:
	if _items_list == null:
		return
	_items_list.clear()
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	for entry: Variant in reg.campaign.get_item_library():
		if entry is ItemEntry:
			var ie := entry as ItemEntry
			var display_text: String = ie.name
			if not ie.category.is_empty():
				display_text += " (%s)" % ie.category
			if ie.source.begins_with("srd"):
				display_text += " [SRD]"
			_items_list.add_item(display_text)
			_items_list.set_item_metadata(_items_list.get_item_count() - 1, ie.id)


func _refresh_notes_list() -> void:
	if _notes_tree == null:
		return
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var notes: Array = reg.campaign.get_notes()

	## Collect folders and group notes by full path
	var folder_notes: Dictionary = {} # full_path -> Array[Dictionary]
	var root_notes: Array = []
	for note: Variant in notes:
		if not note is Dictionary:
			continue
		var d := note as Dictionary
		var f: String = str(d.get("folder", ""))
		if f.is_empty():
			root_notes.append(d)
		else:
			if not folder_notes.has(f):
				folder_notes[f] = []
			(folder_notes[f] as Array).append(d)

	## Merge persisted empty folders
	for pf: Variant in reg.campaign.get_note_folders():
		var fname: String = str(pf)
		if not fname.is_empty() and not folder_notes.has(fname):
			folder_notes[fname] = []

	_notes_tree.clear()
	var tree_root: TreeItem = _notes_tree.create_item()
	var folder_items: Dictionary = _build_nested_folder_tree(_notes_tree, tree_root, folder_notes)

	## Add items into their respective folders
	for folder_path: Variant in folder_notes.keys():
		var fp: String = str(folder_path)
		if not folder_items.has(fp):
			continue
		var parent_item: TreeItem = folder_items[fp] as TreeItem
		var children: Array = folder_notes[fp] as Array
		for child: Variant in children:
			var cd := child as Dictionary
			var note_item: TreeItem = _notes_tree.create_item(parent_item)
			note_item.set_text(0, str(cd.get("title", "Untitled")))
			note_item.set_meta("type", "note")
			note_item.set_meta("id", str(cd.get("id", "")))

	## Add root-level notes (no folder)
	for d: Variant in root_notes:
		var rd := d as Dictionary
		var note_item: TreeItem = _notes_tree.create_item(tree_root)
		note_item.set_text(0, str(rd.get("title", "Untitled")))
		note_item.set_meta("type", "note")
		note_item.set_meta("id", str(rd.get("id", "")))

	## Re-select current note if still exists
	if not _notes_current_id.is_empty():
		_notes_select_by_id(_notes_current_id)

	## Update folder OptionButton for the editor
	_refresh_notes_folder_options()


func _refresh_images_list() -> void:
	if _images_tree == null:
		return
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var images: Array = reg.campaign.get_images()

	## Collect folders and group images by full path
	var folder_images: Dictionary = {} # full_path -> Array[Dictionary]
	var root_images: Array = []
	for img: Variant in images:
		if not img is Dictionary:
			continue
		var d := img as Dictionary
		var f: String = str(d.get("folder", ""))
		if f.is_empty():
			root_images.append(d)
		else:
			if not folder_images.has(f):
				folder_images[f] = []
			(folder_images[f] as Array).append(d)

	## Merge persisted empty folders
	for pf: Variant in reg.campaign.get_image_folders():
		var fname: String = str(pf)
		if not fname.is_empty() and not folder_images.has(fname):
			folder_images[fname] = []

	_images_tree.clear()
	var tree_root: TreeItem = _images_tree.create_item()
	var folder_items: Dictionary = _build_nested_folder_tree(_images_tree, tree_root, folder_images)

	## Add items into their respective folders
	for folder_path: Variant in folder_images.keys():
		var fp: String = str(folder_path)
		if not folder_items.has(fp):
			continue
		var parent_item: TreeItem = folder_items[fp] as TreeItem
		var children: Array = folder_images[fp] as Array
		for child: Variant in children:
			var cd := child as Dictionary
			var img_item: TreeItem = _images_tree.create_item(parent_item)
			img_item.set_text(0, str(cd.get("name", "Unknown")))
			img_item.set_meta("type", "image")
			img_item.set_meta("id", str(cd.get("id", "")))

	## Add root-level images (no folder)
	for d: Variant in root_images:
		var rd := d as Dictionary
		var img_item: TreeItem = _images_tree.create_item(tree_root)
		img_item.set_text(0, str(rd.get("name", "Unknown")))
		img_item.set_meta("type", "image")
		img_item.set_meta("id", str(rd.get("id", "")))

	## Re-select current image if still exists
	if not _images_current_id.is_empty():
		_images_select_by_id(_images_current_id)


# ─── Button state updaters ────────────────────────────────────────────────────

func _update_maps_btns() -> void:
	var has: bool = not _maps_selected_path.is_empty()
	if _maps_open_btn != null:
		_maps_open_btn.disabled = not has
	if _maps_link_btn != null:
		_maps_link_btn.disabled = not has


func _update_saves_btns() -> void:
	var has: bool = not _saves_selected_path.is_empty()
	if _saves_open_btn != null:
		_saves_open_btn.disabled = not has
	if _saves_link_btn != null:
		_saves_link_btn.disabled = not has


func _update_chars_btns() -> void:
	var reg := _registry()
	var campaign_active: bool = reg != null and reg.campaign != null and reg.campaign.get_active_campaign() != null
	var has: bool = not _chars_selected_id.is_empty()
	var in_campaign: bool = campaign_active and has and reg.campaign.has_character(_chars_selected_id)
	if _chars_sheet_btn != null:
		_chars_sheet_btn.disabled = not has
	if _chars_assign_btn != null:
		_chars_assign_btn.disabled = not (has and campaign_active and not in_campaign)
	if _chars_remove_btn != null:
		_chars_remove_btn.disabled = not (has and in_campaign)
	if _chars_override_btn != null:
		_chars_override_btn.disabled = not (has and in_campaign)
	if _chars_delete_btn != null:
		_chars_delete_btn.disabled = not has


# ─── Overview handlers ────────────────────────────────────────────────────────

func _on_overview_save() -> void:
	var reg := _registry()
	if reg == null or reg.campaign == null or reg.campaign.get_active_campaign() == null:
		return
	var c: CampaignData = reg.campaign.get_active_campaign()
	if _ov_name_edit != null:
		c.name = _ov_name_edit.text.strip_edges()
	if _ov_desc_edit != null:
		c.description = _ov_desc_edit.text
	if _ov_ruleset_opt != null:
		c.default_ruleset = "2024" if _ov_ruleset_opt.selected == 1 else "2014"
	var new_settings: Dictionary = {}
	if _ov_tie_opt != null:
		new_settings["tie_goes_to"] = "monster" if _ov_tie_opt.selected == 1 else "player"
	if _ov_crit_opt != null:
		new_settings["critical_hit_rule"] = "max_plus_roll" if _ov_crit_opt.selected == 1 else "double_dice"
	if _ov_exhaustion_opt != null:
		new_settings["exhaustion_rule"] = "2024" if _ov_exhaustion_opt.selected == 1 else "2014"
	reg.campaign.update_settings(new_settings)
	reg.campaign.save_campaign()
	title = "Campaign \u2014 %s" % c.name


# ─── Maps handlers ────────────────────────────────────────────────────────────

func _on_maps_new() -> void:
	new_map_requested.emit()


func _on_maps_add() -> void:
	add_map_browse_requested.emit()


func _on_maps_open(_item_index: int = -1) -> void:
	if _maps_selected_path.is_empty():
		return
	var path: String = _maps_selected_path
	hide()
	map_open_requested.emit(path)


func _on_maps_remove() -> void:
	if _maps_selected_path.is_empty():
		return
	var reg := _registry()
	if reg != null and reg.campaign != null:
		reg.campaign.remove_map_path(_maps_selected_path)
		reg.campaign.save_campaign()
	_maps_selected_path = ""
	_refresh_maps_list()


func _on_maps_open_file() -> void:
	open_map_file_requested.emit()


func _on_saves_open_file() -> void:
	open_save_file_requested.emit()


func _on_maps_show_in_explorer() -> void:
	if _maps_selected_path.is_empty():
		return
	OS.shell_open(_maps_selected_path.get_base_dir())


# ─── Saves handlers ───────────────────────────────────────────────────────────

func _on_saves_new() -> void:
	new_save_requested.emit()


func _on_saves_add() -> void:
	add_save_browse_requested.emit()


func _on_saves_open(_item_index: int = -1) -> void:
	if _saves_selected_path.is_empty():
		return
	var path: String = _saves_selected_path
	hide()
	save_load_requested.emit(path)


func _on_saves_remove() -> void:
	if _saves_selected_path.is_empty():
		return
	var reg := _registry()
	if reg != null and reg.campaign != null:
		reg.campaign.remove_save_path(_saves_selected_path)
		reg.campaign.save_campaign()
	_saves_selected_path = ""
	_refresh_saves_list()


func _on_saves_show_in_explorer() -> void:
	if _saves_selected_path.is_empty():
		return
	OS.shell_open(_saves_selected_path.get_base_dir())


# ─── Characters handlers ──────────────────────────────────────────────────────

func _on_chars_open_sheet() -> void:
	if _chars_selected_id.is_empty():
		return
	edit_character_requested.emit(_chars_selected_id)


func _on_chars_assign() -> void:
	if _chars_selected_id.is_empty():
		return
	var reg := _registry()
	if reg == null or reg.campaign == null or reg.campaign.get_active_campaign() == null:
		return
	reg.campaign.add_character(_chars_selected_id)
	reg.campaign.save_campaign()
	_refresh_chars_list()


func _on_chars_remove_from_campaign() -> void:
	if _chars_selected_id.is_empty():
		return
	var reg := _registry()
	if reg == null or reg.campaign == null or reg.campaign.get_active_campaign() == null:
		return
	reg.campaign.remove_character(_chars_selected_id)
	reg.campaign.save_campaign()
	_refresh_chars_list()


func _on_chars_edit_override() -> void:
	if _chars_selected_id.is_empty():
		return
	var reg := _registry()
	if reg == null or reg.campaign == null or reg.campaign.get_active_campaign() == null:
		return
	if not reg.campaign.has_character(_chars_selected_id):
		return
	var ch_id: String = _chars_selected_id
	var co: CharacterOverride = reg.campaign.get_character_override(ch_id)
	if co == null:
		co = CharacterOverride.new()
		co.character_id = ch_id

	var s: float = _scale()
	# Resolve a display label for the dialog title.
	var sb: StatblockData = reg.character.get_character_by_id(ch_id) if reg.character != null else null
	var ch_name: String = sb.name if sb != null else ch_id

	var dlg := AcceptDialog.new()
	dlg.title = "Campaign Customization \u2014 %s" % ch_name
	dlg.ok_button_text = "Save"

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", roundi(8.0 * s))
	dlg.add_child(root)

	# ── Description ──
	var desc_lbl := Label.new()
	desc_lbl.text = "Customize how this character appears in this campaign.\nChanges here only affect this campaign \u2014 the original character is unchanged."
	desc_lbl.add_theme_font_size_override("font_size", roundi(12.0 * s))
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(desc_lbl)

	# ── Display Name ──
	var name_lbl := Label.new()
	name_lbl.text = "Campaign Display Name"
	name_lbl.add_theme_font_size_override("font_size", roundi(13.0 * s))
	root.add_child(name_lbl)
	var name_edit := LineEdit.new()
	name_edit.text = co.display_name
	name_edit.placeholder_text = ch_name + " (from character sheet)"
	name_edit.custom_minimum_size = Vector2(roundi(360.0 * s), 0)
	name_edit.add_theme_font_size_override("font_size", roundi(13.0 * s))
	root.add_child(name_edit)

	# ── Portrait ──
	var port_lbl := Label.new()
	port_lbl.text = "Campaign Portrait"
	port_lbl.add_theme_font_size_override("font_size", roundi(13.0 * s))
	root.add_child(port_lbl)

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", roundi(4.0 * s))
	root.add_child(port_row)
	var port_edit := LineEdit.new()
	port_edit.text = co.portrait_path
	port_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_edit.add_theme_font_size_override("font_size", roundi(13.0 * s))
	port_row.add_child(port_edit)

	var browse_btn := Button.new()
	browse_btn.text = "Browse\u2026"
	browse_btn.custom_minimum_size = Vector2(roundi(80.0 * s), 0)
	browse_btn.add_theme_font_size_override("font_size", roundi(12.0 * s))
	port_row.add_child(browse_btn)

	var campaign_btn := Button.new()
	campaign_btn.text = "Campaign\u2026"
	campaign_btn.custom_minimum_size = Vector2(roundi(100.0 * s), 0)
	campaign_btn.add_theme_font_size_override("font_size", roundi(12.0 * s))
	port_row.add_child(campaign_btn)

	# Track the campaign_image_id for back-reference.
	var cimg_id: Array = [co.campaign_image_id] # mutable wrapper for closures

	browse_btn.pressed.connect(func() -> void:
		var fd := FileDialog.new()
		fd.use_native_dialog = true
		fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.title = "Select Portrait Image"
		for f: String in TokenIconUtils.FILE_DIALOG_FILTERS:
			fd.add_filter(f)
		fd.file_selected.connect(func(path: String) -> void:
			port_edit.text = path
			cimg_id[0] = ""
			fd.queue_free()
		)
		add_child(fd)
		fd.popup_centered(Vector2i(800, 500))
	)

	campaign_btn.pressed.connect(func() -> void:
		var picker := CampaignImagePicker.new()
		picker.image_selected.connect(func(path: String, img_id: String) -> void:
			port_edit.text = path
			cimg_id[0] = img_id
			picker.queue_free()
		)
		add_child(picker)
		if reg.ui_theme != null:
			reg.ui_theme.theme_control_tree(picker, s)
		picker.show_picker()
	)

	# ── Notes ──
	var notes_lbl := Label.new()
	notes_lbl.text = "Campaign Notes"
	notes_lbl.add_theme_font_size_override("font_size", roundi(13.0 * s))
	root.add_child(notes_lbl)
	var notes_edit := TextEdit.new()
	notes_edit.text = co.notes
	notes_edit.custom_minimum_size = Vector2(roundi(360.0 * s), roundi(120.0 * s))
	notes_edit.add_theme_font_size_override("font_size", roundi(13.0 * s))
	root.add_child(notes_edit)

	# ── Clear button ──
	var clear_btn := Button.new()
	clear_btn.text = "Reset to Defaults"
	clear_btn.custom_minimum_size = Vector2(roundi(140.0 * s), roundi(28.0 * s))
	clear_btn.add_theme_font_size_override("font_size", roundi(12.0 * s))
	root.add_child(clear_btn)
	clear_btn.pressed.connect(func() -> void:
		name_edit.text = ""
		port_edit.text = ""
		notes_edit.text = ""
		cimg_id[0] = ""
	)

	add_child(dlg)
	if reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(dlg, s)
	if reg.ui_scale != null:
		reg.ui_scale.scale_button(dlg.get_ok_button())
	dlg.reset_size()
	dlg.popup_centered()

	dlg.confirmed.connect(func() -> void:
		var r := _registry()
		if r == null or r.campaign == null:
			dlg.queue_free()
			return
		var new_name: String = name_edit.text.strip_edges()
		var new_portrait: String = port_edit.text.strip_edges()
		var new_notes: String = notes_edit.text
		var new_cimg: String = cimg_id[0]
		# If all fields are empty, remove the override entirely.
		if new_name.is_empty() and new_portrait.is_empty() and new_notes.is_empty():
			r.campaign.remove_character_override(ch_id)
		else:
			var new_co := CharacterOverride.new()
			new_co.character_id = ch_id
			new_co.display_name = new_name
			new_co.portrait_path = new_portrait
			new_co.campaign_image_id = new_cimg
			new_co.notes = new_notes
			r.campaign.set_character_override(ch_id, new_co)
		r.campaign.save_campaign()
		_refresh_chars_list()
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())


func _on_chars_delete() -> void:
	if _chars_selected_id.is_empty():
		return
	var reg := _registry()
	var ch_id: String = _chars_selected_id
	var sb2: StatblockData = reg.character.get_character_by_id(ch_id) if reg != null and reg.character != null else null
	var ch_name: String = sb2.name if sb2 != null else ch_id
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Delete '%s'? This cannot be undone." % ch_name
	add_child(dlg)
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func() -> void:
		var r := _registry()
		if r != null and r.character != null:
			r.character.remove_character(ch_id)
		if r != null and r.campaign != null and r.campaign.has_character(ch_id):
			r.campaign.remove_character(ch_id)
			r.campaign.save_campaign()
		_refresh_chars_list()
		dlg.queue_free()
	)
	dlg.canceled.connect(func() -> void: dlg.queue_free())


# ─── Bestiary handlers ────────────────────────────────────────────────────────

func _on_bestiary_add() -> void:
	## Open the StatblockLibrary — it already has "Add to Bestiary".
	if _bestiary_library != null and is_instance_valid(_bestiary_library):
		_bestiary_library.show()
		_bestiary_library.grab_focus()
		return
	_bestiary_library = StatblockLibrary.new()
	add_child(_bestiary_library)
	var reg := _registry()
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(_bestiary_library, _scale())
	## Refresh our list when the library is closed so newly-added entries appear.
	_bestiary_library.close_requested.connect(func() -> void:
		_bestiary_library.hide()
		_refresh_bestiary_list())
	_bestiary_library.popup_centered()


func _on_bestiary_item_selected(idx: int) -> void:
	if _bestiary_list == null or _bestiary_card == null:
		return
	var bst_key: String = str(_bestiary_list.get_item_metadata(idx))
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var s: float = _scale()
	for entry: Variant in reg.campaign.get_bestiary():
		if not entry is StatblockData:
			continue
		var sb := entry as StatblockData
		var key: String = sb.srd_index if (not sb.srd_index.is_empty() and sb.source.begins_with("SRD")) else sb.id
		if key == bst_key:
			_bestiary_card.display(sb)
			_bestiary_card.apply_font_scale(roundi(14.0 * s))
			return


func _on_bestiary_edit() -> void:
	if _bestiary_list == null:
		return
	var sel: PackedInt32Array = _bestiary_list.get_selected_items()
	if sel.is_empty():
		return
	var bst_key: String = str(_bestiary_list.get_item_metadata(sel[0]))
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var sb: StatblockData = null
	for entry: Variant in reg.campaign.get_bestiary():
		if not entry is StatblockData:
			continue
		var candidate := entry as StatblockData
		var key: String = candidate.srd_index if (not candidate.srd_index.is_empty() and candidate.source.begins_with("SRD")) else candidate.id
		if key == bst_key:
			sb = candidate
			break
	if sb == null:
		return
	## Track the old key so save can remove it (handles SRD→custom promotion).
	_bestiary_editing_old_key = bst_key
	## For SRD entries, generate a new id for the to-be-custom copy; keep editing id blank
	## until save so cancel leaves the SRD ref intact.
	if not sb.srd_index.is_empty() and sb.source.begins_with("SRD"):
		_bestiary_editing_id = StatblockData.generate_id()
	else:
		_bestiary_editing_id = sb.id
	_open_bestiary_dialog(sb)


func _open_bestiary_dialog(sb: StatblockData) -> void:
	if _bestiary_dlg != null:
		_bestiary_dlg.queue_free()
		_bestiary_dlg = null
	_bst.clear()

	var s: float = _scale()
	var si := func(base_val: float) -> int:
		return roundi(base_val * s)

	_bestiary_dlg = Window.new()
	_bestiary_dlg.title = "Edit Statblock" if sb != null else "New Statblock"
	_bestiary_dlg.transient = true
	_bestiary_dlg.size = Vector2i(si.call(520.0), si.call(700.0))
	_bestiary_dlg.min_size = Vector2i(si.call(400.0), si.call(500.0))
	_bestiary_dlg.wrap_controls = false
	_bestiary_dlg.close_requested.connect(_on_bestiary_dlg_cancel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m_pad: int = si.call(10.0)
	margin.add_theme_constant_override("margin_left", m_pad)
	margin.add_theme_constant_override("margin_right", m_pad)
	margin.add_theme_constant_override("margin_top", m_pad)
	margin.add_theme_constant_override("margin_bottom", m_pad)
	_bestiary_dlg.add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", si.call(6.0))
	margin.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", si.call(4.0))
	scroll.add_child(form)

	var font_sz: int = si.call(13.0)
	var sec_sz: int = si.call(15.0)

	## ── Identity section ──
	_bst_section(form, "Identity", sec_sz)
	_bst["name"] = _bst_line(form, "Name", sb.name if sb != null else "", font_sz, si)
	_bst["creature_type"] = _bst_line(form, "Creature Type", sb.creature_type if sb != null else "", font_sz, si)
	_bst["subtype"] = _bst_line(form, "Subtype", sb.subtype if sb != null else "", font_sz, si)
	_bst["size"] = _bst_option(form, "Size", StatblockData.SIZE_LABELS, sb.size if sb != null else "Medium", font_sz, si)
	_bst["alignment"] = _bst_line(form, "Alignment", sb.alignment if sb != null else "", font_sz, si)

	## ── PC / Class section ──
	_bst_section(form, "Class / Race (optional)", sec_sz)
	_bst["class_name_str"] = _bst_line(form, "Class", sb.class_name_str if sb != null else "", font_sz, si)
	_bst["level"] = _bst_spin(form, "Level", sb.level if sb != null else 0, 0, 30, font_sz, si)
	_bst["race"] = _bst_line(form, "Race", sb.race if sb != null else "", font_sz, si)

	## ── Combat section ──
	_bst_section(form, "Combat", sec_sz)
	var ac_val: int = 10
	if sb != null and not sb.armor_class.is_empty():
		var first_ac: Variant = sb.armor_class[0]
		if first_ac is Dictionary:
			ac_val = int((first_ac as Dictionary).get("value", 10))
	_bst["ac"] = _bst_spin(form, "Armor Class", ac_val, 0, 30, font_sz, si)
	_bst["hp"] = _bst_spin(form, "Hit Points", sb.hit_points if sb != null else 0, 0, 9999, font_sz, si)
	_bst["hit_dice"] = _bst_line(form, "Hit Dice", sb.hit_dice if sb != null else "", font_sz, si)
	_bst["speed_walk"] = _bst_line(form, "Speed (walk)", str(sb.speed.get("walk", "")) if sb != null else "30 ft.", font_sz, si)
	_bst["speed_fly"] = _bst_line(form, "Speed (fly)", str(sb.speed.get("fly", "")) if sb != null else "", font_sz, si)
	_bst["speed_swim"] = _bst_line(form, "Speed (swim)", str(sb.speed.get("swim", "")) if sb != null else "", font_sz, si)

	## ── Ability Scores ──
	_bst_section(form, "Ability Scores", sec_sz)
	var abilities_row := GridContainer.new()
	abilities_row.columns = 6
	abilities_row.add_theme_constant_override("h_separation", si.call(6.0))
	abilities_row.add_theme_constant_override("v_separation", si.call(2.0))
	form.add_child(abilities_row)
	for ab: String in ["STR", "DEX", "CON", "INT", "WIS", "CHA"]:
		var ab_lbl := Label.new()
		ab_lbl.text = ab
		ab_lbl.add_theme_font_size_override("font_size", font_sz)
		ab_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		abilities_row.add_child(ab_lbl)
	var ab_map: Dictionary = {
		"str": sb.strength if sb != null else 10,
		"dex": sb.dexterity if sb != null else 10,
		"con": sb.constitution if sb != null else 10,
		"int": sb.intelligence if sb != null else 10,
		"wis": sb.wisdom if sb != null else 10,
		"cha": sb.charisma if sb != null else 10,
	}
	for key: String in ["str", "dex", "con", "int", "wis", "cha"]:
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = 30
		spin.value = ab_map[key]
		spin.custom_minimum_size = Vector2(si.call(60.0), 0)
		spin.add_theme_font_size_override("font_size", font_sz)
		spin.get_line_edit().add_theme_font_size_override("font_size", font_sz)
		abilities_row.add_child(spin)
		_bst[key] = spin

	## ── Rating ──
	_bst_section(form, "Challenge Rating", sec_sz)
	_bst["cr"] = _bst_line(form, "CR", str(sb.challenge_rating) if sb != null else "0", font_sz, si)
	_bst["xp"] = _bst_spin(form, "XP", sb.xp if sb != null else 0, 0, 999999, font_sz, si)
	_bst["proficiency_bonus"] = _bst_spin(form, "Proficiency Bonus", sb.proficiency_bonus if sb != null else 2, 0, 10, font_sz, si)

	## ── Senses / Languages ──
	_bst_section(form, "Senses & Languages", sec_sz)
	_bst["languages"] = _bst_line(form, "Languages", sb.languages if sb != null else "", font_sz, si)
	_bst["senses_text"] = _bst_line(form, "Senses", _senses_to_text(sb.senses) if sb != null else "", font_sz, si)

	## ── Defenses (comma-separated) ──
	_bst_section(form, "Defenses (comma-separated)", sec_sz)
	_bst["dmg_vuln"] = _bst_line(form, "Vulnerabilities", ", ".join(sb.damage_vulnerabilities) if sb != null else "", font_sz, si)
	_bst["dmg_res"] = _bst_line(form, "Resistances", ", ".join(sb.damage_resistances) if sb != null else "", font_sz, si)
	_bst["dmg_imm"] = _bst_line(form, "Immunities", ", ".join(sb.damage_immunities) if sb != null else "", font_sz, si)

	## ── Actions (name + desc pairs) ──
	_bst_section(form, "Actions (one per line: Name | Description)", sec_sz)
	_bst["actions_text"] = _bst_text(form, _actions_to_text(sb.actions) if sb != null else "", font_sz, si)

	## ── Special Abilities ──
	_bst_section(form, "Special Abilities (Name | Description)", sec_sz)
	_bst["specials_text"] = _bst_text(form, _actions_to_text(sb.special_abilities) if sb != null else "", font_sz, si)

	## ── Reactions ──
	_bst_section(form, "Reactions (Name | Description)", sec_sz)
	_bst["reactions_text"] = _bst_text(form, _actions_to_text(sb.reactions) if sb != null else "", font_sz, si)

	## ── Legendary Actions ──
	_bst_section(form, "Legendary Actions (Name | Description)", sec_sz)
	_bst["legendary_text"] = _bst_text(form, _actions_to_text(sb.legendary_actions) if sb != null else "", font_sz, si)

	## ── Notes ──
	_bst_section(form, "Notes", sec_sz)
	_bst["notes"] = _bst_text(form, sb.notes if sb != null else "", font_sz, si)

	## ── Button row ──
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", si.call(8.0))
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(si.call(90.0), si.call(32.0))
	cancel_btn.add_theme_font_size_override("font_size", font_sz)
	cancel_btn.pressed.connect(_on_bestiary_dlg_cancel)
	btn_row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(si.call(90.0), si.call(32.0))
	save_btn.add_theme_font_size_override("font_size", font_sz)
	save_btn.pressed.connect(_on_bestiary_dlg_save)
	btn_row.add_child(save_btn)

	add_child(_bestiary_dlg)
	var reg := _registry()
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(_bestiary_dlg, s)
	_bestiary_dlg.popup_centered()


func _on_bestiary_dlg_cancel() -> void:
	if _bestiary_dlg != null:
		_bestiary_dlg.queue_free()
		_bestiary_dlg = null
	_bestiary_editing_id = ""
	_bestiary_editing_old_key = ""


func _on_bestiary_dlg_save() -> void:
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return

	var sb := StatblockData.new()
	sb.id = _bestiary_editing_id if not _bestiary_editing_id.is_empty() else StatblockData.generate_id()
	sb.source = "campaign"
	sb.ruleset = "custom"
	sb.name = (_bst["name"] as LineEdit).text.strip_edges()
	if sb.name.is_empty():
		sb.name = "Unnamed"
	sb.creature_type = (_bst["creature_type"] as LineEdit).text.strip_edges()
	sb.subtype = (_bst["subtype"] as LineEdit).text.strip_edges()
	sb.size = (_bst["size"] as OptionButton).get_item_text((_bst["size"] as OptionButton).selected)
	sb.alignment = (_bst["alignment"] as LineEdit).text.strip_edges()

	sb.class_name_str = (_bst["class_name_str"] as LineEdit).text.strip_edges()
	sb.level = int((_bst["level"] as SpinBox).value)
	sb.race = (_bst["race"] as LineEdit).text.strip_edges()

	sb.armor_class = [ {"type": "natural", "value": int((_bst["ac"] as SpinBox).value)}]
	sb.hit_points = int((_bst["hp"] as SpinBox).value)
	sb.hit_dice = (_bst["hit_dice"] as LineEdit).text.strip_edges()

	var walk: String = (_bst["speed_walk"] as LineEdit).text.strip_edges()
	var fly: String = (_bst["speed_fly"] as LineEdit).text.strip_edges()
	var swim: String = (_bst["speed_swim"] as LineEdit).text.strip_edges()
	if not walk.is_empty():
		sb.speed["walk"] = walk
	if not fly.is_empty():
		sb.speed["fly"] = fly
	if not swim.is_empty():
		sb.speed["swim"] = swim

	sb.strength = int((_bst["str"] as SpinBox).value)
	sb.dexterity = int((_bst["dex"] as SpinBox).value)
	sb.constitution = int((_bst["con"] as SpinBox).value)
	sb.intelligence = int((_bst["int"] as SpinBox).value)
	sb.wisdom = int((_bst["wis"] as SpinBox).value)
	sb.charisma = int((_bst["cha"] as SpinBox).value)

	var cr_text: String = (_bst["cr"] as LineEdit).text.strip_edges()
	sb.challenge_rating = float(cr_text) if cr_text.is_valid_float() else 0.0
	sb.xp = int((_bst["xp"] as SpinBox).value)
	sb.proficiency_bonus = int((_bst["proficiency_bonus"] as SpinBox).value)

	sb.languages = (_bst["languages"] as LineEdit).text.strip_edges()
	sb.senses = _text_to_senses((_bst["senses_text"] as LineEdit).text.strip_edges())

	sb.damage_vulnerabilities = _csv_to_array((_bst["dmg_vuln"] as LineEdit).text)
	sb.damage_resistances = _csv_to_array((_bst["dmg_res"] as LineEdit).text)
	sb.damage_immunities = _csv_to_array((_bst["dmg_imm"] as LineEdit).text)

	sb.actions = _text_to_actions((_bst["actions_text"] as TextEdit).text)
	sb.special_abilities = _text_to_actions((_bst["specials_text"] as TextEdit).text)
	sb.reactions = _text_to_actions((_bst["reactions_text"] as TextEdit).text)
	sb.legendary_actions = _text_to_actions((_bst["legendary_text"] as TextEdit).text)
	sb.notes = (_bst["notes"] as TextEdit).text

	## Remove old entry when editing (handles SRD→custom promotion too).
	if not _bestiary_editing_old_key.is_empty():
		reg.campaign.remove_from_bestiary(_bestiary_editing_old_key)
	reg.campaign.add_to_bestiary(sb)
	reg.campaign.save_campaign()
	_refresh_bestiary_list()
	_on_bestiary_dlg_cancel()


func _on_bestiary_remove() -> void:
	if _bestiary_list == null:
		return
	var sel: PackedInt32Array = _bestiary_list.get_selected_items()
	if sel.is_empty():
		return
	var sb_id: String = str(_bestiary_list.get_item_metadata(sel[0]))
	var reg := _registry()
	if reg != null and reg.campaign != null:
		reg.campaign.remove_from_bestiary(sb_id)
		reg.campaign.save_campaign()
	_refresh_bestiary_list()


# ─── Items handlers ───────────────────────────────────────────────────────────

func _on_items_item_selected(idx: int) -> void:
	if _items_list == null or _items_card == null:
		return
	var item_id: String = str(_items_list.get_item_metadata(idx))
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	for entry: Variant in reg.campaign.get_item_library():
		if not entry is ItemEntry:
			continue
		var ie := entry as ItemEntry
		if ie.id == item_id:
			_items_card.display(ie)
			_items_card.apply_font_scale(roundi(14.0 * _scale()))
			return


func _on_items_add() -> void:
	if _items_library != null and is_instance_valid(_items_library):
		_items_library.show()
		_items_library.grab_focus()
		return
	_items_library = ItemLibrary.new()
	add_child(_items_library)
	var reg := _registry()
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(_items_library, _scale())
	_items_library.close_requested.connect(func() -> void:
		_items_library.hide()
		_refresh_items_list())
	_items_library.popup_centered()


func _on_items_remove() -> void:
	if _items_list == null:
		return
	var sel: PackedInt32Array = _items_list.get_selected_items()
	if sel.is_empty():
		return
	var item_id: String = str(_items_list.get_item_metadata(sel[0]))
	var reg := _registry()
	if reg != null and reg.campaign != null:
		reg.campaign.remove_from_item_library(item_id)
		reg.campaign.save_campaign()
	_refresh_items_list()


# ─── Notes handlers ───────────────────────────────────────────────────────────

func _notes_set_editor_enabled(enabled: bool) -> void:
	if _notes_title_edit != null:
		_notes_title_edit.editable = enabled
		if not enabled:
			_notes_title_edit.text = ""
	if _notes_folder_opt != null:
		_notes_folder_opt.disabled = not enabled
	if _notes_body_edit != null:
		_notes_body_edit.editable = enabled
		if not enabled:
			_notes_body_edit.text = ""


func _notes_select_by_id(note_id: String) -> void:
	if _notes_tree == null:
		return
	var root: TreeItem = _notes_tree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if item.get_meta("type") == "note" and str(item.get_meta("id")) == note_id:
			item.select(0)
			return
		var child: TreeItem = item.get_first_child()
		while child != null:
			if child.get_meta("type") == "note" and str(child.get_meta("id")) == note_id:
				child.select(0)
				return
			child = child.get_next()
		item = item.get_next()


func _refresh_notes_folder_options() -> void:
	if _notes_folder_opt == null:
		return
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return

	var folders: Array[String] = []
	for note: Variant in reg.campaign.get_notes():
		if not note is Dictionary:
			continue
		var f: String = str((note as Dictionary).get("folder", ""))
		if not f.is_empty() and not folders.has(f):
			folders.append(f)
	## Include persisted empty folders
	for pf: Variant in reg.campaign.get_note_folders():
		var fname: String = str(pf)
		if not fname.is_empty() and not folders.has(fname):
			folders.append(fname)
	folders.sort()

	var prev_text: String = ""
	if _notes_folder_opt.selected >= 0:
		prev_text = _notes_folder_opt.get_item_text(_notes_folder_opt.selected)

	_notes_folder_opt.clear()
	_notes_folder_opt.add_item("No Folder")
	for f: String in folders:
		_notes_folder_opt.add_item(f)
	_notes_folder_opt.add_separator()
	_notes_folder_opt.add_item("New Folder…")

	if not prev_text.is_empty():
		for i: int in _notes_folder_opt.item_count:
			if _notes_folder_opt.get_item_text(i) == prev_text:
				_notes_folder_opt.select(i)
				break


func _notes_auto_save() -> void:
	if _notes_current_id.is_empty():
		return
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var t: String = _notes_title_edit.text.strip_edges() if _notes_title_edit != null else "Untitled"
	if t.is_empty():
		t = "Untitled"
	var f: String = ""
	if _notes_folder_opt != null and _notes_folder_opt.selected > 0:
		var sel_text: String = _notes_folder_opt.get_item_text(_notes_folder_opt.selected)
		if sel_text != "New Folder…":
			f = sel_text
	var b: String = _notes_body_edit.text if _notes_body_edit != null else ""
	reg.campaign.update_note(_notes_current_id, t, b, f)
	reg.campaign.save_campaign()


func _on_note_tree_selected() -> void:
	var sel: TreeItem = _notes_tree.get_selected() if _notes_tree != null else null
	if sel == null:
		return
	var item_type: String = str(sel.get_meta("type"))
	if item_type == "note":
		_notes_auto_save()
		var note_id: String = str(sel.get_meta("id"))
		_notes_current_id = note_id
		var reg := _registry()
		if reg == null or reg.campaign == null:
			return
		for note: Variant in reg.campaign.get_notes():
			if not note is Dictionary:
				continue
			var d := note as Dictionary
			if str(d.get("id", "")) != note_id:
				continue
			_notes_set_editor_enabled(true)
			if _notes_title_edit != null:
				_notes_title_edit.text = str(d.get("title", ""))
			if _notes_body_edit != null:
				_notes_body_edit.text = str(d.get("body", ""))
			var folder_name: String = str(d.get("folder", ""))
			if _notes_folder_opt != null:
				if folder_name.is_empty():
					_notes_folder_opt.select(0)
				else:
					for i: int in _notes_folder_opt.item_count:
						if _notes_folder_opt.get_item_text(i) == folder_name:
							_notes_folder_opt.select(i)
							break
			break


func _on_notes_tree_rmb(_pos: Vector2, _mouse_btn: int) -> void:
	if _mouse_btn != 2:
		return
	if _notes_ctx_menu == null or _notes_tree == null:
		return
	var sel: TreeItem = _notes_tree.get_selected()
	if sel == null:
		return
	var has_paste: bool = not _clipboard_items.is_empty() and _clipboard_tree == _notes_tree
	_notes_ctx_menu.set_item_disabled(_notes_ctx_menu.get_item_index(10), false) # Cut
	_notes_ctx_menu.set_item_disabled(_notes_ctx_menu.get_item_index(11), false) # Copy
	_notes_ctx_menu.set_item_disabled(_notes_ctx_menu.get_item_index(12), not has_paste) # Paste
	_notes_ctx_menu.set_item_disabled(_notes_ctx_menu.get_item_index(0), false) # Rename
	_notes_ctx_menu.set_item_disabled(_notes_ctx_menu.get_item_index(1), false) # Delete
	_notes_ctx_menu.position = Vector2i(DisplayServer.mouse_get_position())
	_notes_ctx_menu.popup()


func _on_notes_ctx_action(id: int) -> void:
	match id:
		0: _on_note_ctx_rename()
		1: _on_note_delete()
		2: _on_note_new()
		3: _on_note_new_folder()
		10: _clipboard_cut(_notes_tree)
		11: _clipboard_copy(_notes_tree)
		12: _clipboard_paste(_notes_tree)


func _on_note_ctx_rename() -> void:
	var sel: TreeItem = _notes_tree.get_selected() if _notes_tree != null else null
	if sel == null:
		return
	var item_type: String = str(sel.get_meta("type"))
	if item_type == "note":
		if _notes_title_edit != null:
			_notes_title_edit.grab_focus()
			_notes_title_edit.select_all()
	elif item_type == "folder":
		_begin_tree_edit(_notes_tree, sel, "rename")


func _on_note_new() -> void:
	_notes_auto_save()
	var reg := _registry()
	if reg == null or reg.campaign == null or reg.campaign.get_active_campaign() == null:
		return
	var folder: String = ""
	var sel: TreeItem = _notes_tree.get_selected() if _notes_tree != null else null
	if sel != null:
		var item_type: String = str(sel.get_meta("type"))
		if item_type == "folder":
			folder = str(sel.get_meta("folder"))
		elif item_type == "note":
			var parent: TreeItem = sel.get_parent()
			if parent != null and parent.has_meta("type") and str(parent.get_meta("type")) == "folder":
				folder = str(parent.get_meta("folder"))
	var note_id: String = reg.campaign.add_note("New Note", "", folder)
	reg.campaign.save_campaign()
	_refresh_notes_list()
	_notes_select_by_id(note_id)
	_on_note_tree_selected()
	if _notes_title_edit != null:
		_notes_title_edit.grab_focus()
		_notes_title_edit.select_all()


func _on_note_new_folder() -> void:
	_create_folder_in_tree(_notes_tree, true)


func _notes_rename_folder(old_name: String, new_name: String) -> void:
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	reg.campaign.rename_note_folder(old_name, new_name)
	reg.campaign.save_campaign()
	_refresh_notes_list()


func _on_note_delete() -> void:
	var sel: TreeItem = _notes_tree.get_selected() if _notes_tree != null else null
	if sel == null:
		return
	var item_type: String = str(sel.get_meta("type"))
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return

	if item_type == "note":
		var note_id: String = str(sel.get_meta("id"))
		reg.campaign.delete_note(note_id)
		if note_id == _notes_current_id:
			_notes_current_id = ""
			_notes_set_editor_enabled(false)
	elif item_type == "folder":
		var folder_name: String = str(sel.get_meta("folder"))
		reg.campaign.remove_note_folder(folder_name)
		var prefix: String = folder_name + "/"
		var to_delete: Array[String] = []
		for note: Variant in reg.campaign.get_notes():
			if not note is Dictionary:
				continue
			var d := note as Dictionary
			var nf: String = str(d.get("folder", ""))
			if nf == folder_name or nf.begins_with(prefix):
				to_delete.append(str(d.get("id", "")))
		for nid: String in to_delete:
			reg.campaign.delete_note(nid)
			if nid == _notes_current_id:
				_notes_current_id = ""
				_notes_set_editor_enabled(false)

	reg.campaign.save_campaign()
	_refresh_notes_list()


func _on_note_title_changed(_new_text: String) -> void:
	if _notes_current_id.is_empty() or _notes_tree == null:
		return
	var sel: TreeItem = _notes_tree.get_selected()
	if sel != null and str(sel.get_meta("type")) == "note":
		var display: String = _notes_title_edit.text if _notes_title_edit != null else "Untitled"
		if display.strip_edges().is_empty():
			display = "Untitled"
		sel.set_text(0, display)
	_notes_auto_save()


func _on_note_folder_changed(index: int) -> void:
	if _notes_folder_opt == null or _notes_current_id.is_empty():
		return
	var selected_text: String = _notes_folder_opt.get_item_text(index)
	if selected_text == "New Folder…":
		_show_name_dialog("New Folder", "Folder name…", func(fname: String) -> void:
			var reg2 := _registry()
			if reg2 != null and reg2.campaign != null:
				reg2.campaign.add_note_folder(fname)
			_notes_auto_save_with_folder(fname)
			_refresh_notes_list())
	else:
		_notes_auto_save()
		_refresh_notes_list()


func _notes_auto_save_with_folder(folder: String) -> void:
	if _notes_current_id.is_empty():
		return
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var t: String = _notes_title_edit.text.strip_edges() if _notes_title_edit != null else "Untitled"
	if t.is_empty():
		t = "Untitled"
	var b: String = _notes_body_edit.text if _notes_body_edit != null else ""
	reg.campaign.update_note(_notes_current_id, t, b, folder)
	reg.campaign.save_campaign()


func _on_note_body_changed() -> void:
	_notes_auto_save()


# ─── Images handlers ──────────────────────────────────────────────────────────

func _images_select_by_id(image_id: String) -> void:
	if _images_tree == null:
		return
	var root: TreeItem = _images_tree.get_root()
	if root == null:
		return
	var item: TreeItem = root.get_first_child()
	while item != null:
		if item.get_meta("type") == "image" and str(item.get_meta("id")) == image_id:
			item.select(0)
			return
		var child: TreeItem = item.get_first_child()
		while child != null:
			if child.get_meta("type") == "image" and str(child.get_meta("id")) == image_id:
				child.select(0)
				return
			child = child.get_next()
		item = item.get_next()


func _on_image_tree_selected() -> void:
	var sel: TreeItem = _images_tree.get_selected() if _images_tree != null else null
	if sel == null:
		return
	if str(sel.get_meta("type")) != "image":
		return
	var img_id: String = str(sel.get_meta("id"))
	_images_current_id = img_id
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	for img: Variant in reg.campaign.get_images():
		if not img is Dictionary:
			continue
		var d := img as Dictionary
		if str(d.get("id", "")) != img_id:
			continue
		var path: String = str(d.get("path", ""))
		if _images_path_label != null:
			_images_path_label.text = path
		if _images_preview != null:
			_images_preview.texture = null
			if not path.is_empty() and FileAccess.file_exists(path):
				var image := Image.new()
				if image.load(path) == OK:
					_images_preview.texture = ImageTexture.create_from_image(image)
		return


func _on_images_tree_rmb(_pos: Vector2, _mouse_btn: int) -> void:
	if _mouse_btn != 2:
		return
	if _images_ctx_menu == null or _images_tree == null:
		return
	var sel: TreeItem = _images_tree.get_selected()
	if sel == null:
		return
	var is_image: bool = str(sel.get_meta("type")) == "image"
	var is_folder: bool = str(sel.get_meta("type")) == "folder"
	var has_paste: bool = not _clipboard_items.is_empty() and _clipboard_tree == _images_tree
	_images_ctx_menu.set_item_disabled(_images_ctx_menu.get_item_index(10), false) # Cut
	_images_ctx_menu.set_item_disabled(_images_ctx_menu.get_item_index(11), false) # Copy
	_images_ctx_menu.set_item_disabled(_images_ctx_menu.get_item_index(12), not has_paste) # Paste
	_images_ctx_menu.set_item_disabled(_images_ctx_menu.get_item_index(0), false) # Rename
	_images_ctx_menu.set_item_disabled(_images_ctx_menu.get_item_index(1), false) # Delete
	_images_ctx_menu.set_item_disabled(_images_ctx_menu.get_item_index(5), not is_folder) # Add Image Here
	_images_ctx_menu.set_item_disabled(_images_ctx_menu.get_item_index(2), not is_image) # Move to Folder
	_images_ctx_menu.set_item_disabled(_images_ctx_menu.get_item_index(4), not is_image) # Open in System Viewer
	_images_ctx_menu.position = Vector2i(DisplayServer.mouse_get_position())
	_images_ctx_menu.popup()


func _on_images_ctx_action(id: int) -> void:
	match id:
		0: _on_image_ctx_rename()
		1: _on_image_remove()
		2: _on_image_move_to_folder()
		3: _on_image_new_folder()
		4: _on_image_open_external()
		5: _on_image_add_here()
		10: _clipboard_cut(_images_tree)
		11: _clipboard_copy(_images_tree)
		12: _clipboard_paste(_images_tree)


func _on_image_ctx_rename() -> void:
	var sel: TreeItem = _images_tree.get_selected() if _images_tree != null else null
	if sel == null:
		return
	var item_type: String = str(sel.get_meta("type"))
	if item_type == "image" or item_type == "folder":
		_begin_tree_edit(_images_tree, sel, "rename")


func _images_rename_folder(old_name: String, new_name: String) -> void:
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	reg.campaign.rename_image_folder(old_name, new_name)
	reg.campaign.save_campaign()
	_refresh_images_list()


func _on_image_add() -> void:
	if _images_file_dialog == null:
		return
	_images_file_dialog.popup_centered(Vector2i(720, 500))


func _on_image_file_selected(path: String) -> void:
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var copy: bool = _images_copy_chk != null and _images_copy_chk.button_pressed
	var folder: String = ""
	var sel: TreeItem = _images_tree.get_selected() if _images_tree != null else null
	if sel != null:
		var sel_type: String = str(sel.get_meta("type"))
		if sel_type == "folder":
			folder = str(sel.get_meta("folder"))
		elif sel_type == "image":
			var parent: TreeItem = sel.get_parent()
			if parent != null and parent.has_meta("type") and str(parent.get_meta("type")) == "folder":
				folder = str(parent.get_meta("folder"))
	var result: Dictionary = reg.campaign.add_image(path, copy)
	if not folder.is_empty() and result.has("id"):
		reg.campaign.update_image(str(result["id"]), str(result.get("name", "")), folder)
	reg.campaign.save_campaign()
	_refresh_images_list()


func _on_image_new_folder() -> void:
	_create_folder_in_tree(_images_tree, false)


func _on_image_add_here() -> void:
	## Opens the file dialog with the target folder remembered from the selected folder item.
	var sel: TreeItem = _images_tree.get_selected() if _images_tree != null else null
	if sel == null or str(sel.get_meta("type")) != "folder":
		return
	## Store target folder in file dialog meta so _on_image_file_selected_here can use it.
	var target_folder: String = str(sel.get_meta("folder"))
	if _images_file_dialog == null:
		return
	_images_file_dialog.set_meta("add_here_folder", target_folder)
	_images_file_dialog.file_selected.disconnect(_on_image_file_selected)
	_images_file_dialog.file_selected.connect(_on_image_file_selected_here.bind(target_folder), CONNECT_ONE_SHOT)
	_images_file_dialog.popup_centered(Vector2i(720, 500))


func _on_image_file_selected_here(path: String, target_folder: String) -> void:
	## Reconnect the normal handler for future use.
	if not _images_file_dialog.file_selected.is_connected(_on_image_file_selected):
		_images_file_dialog.file_selected.connect(_on_image_file_selected)
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var copy: bool = _images_copy_chk != null and _images_copy_chk.button_pressed
	var result: Dictionary = reg.campaign.add_image(path, copy)
	if result.has("id") and not target_folder.is_empty():
		reg.campaign.update_image(str(result["id"]), str(result.get("name", "")), target_folder)
	reg.campaign.save_campaign()
	_refresh_images_list()


func _on_image_move_to_folder() -> void:
	var sel: TreeItem = _images_tree.get_selected() if _images_tree != null else null
	if sel == null or str(sel.get_meta("type")) != "image":
		return
	var img_id: String = str(sel.get_meta("id"))
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return

	## Build folder list for selection
	var folders: Array[String] = ["No Folder"]
	for img: Variant in reg.campaign.get_images():
		if not img is Dictionary:
			continue
		var f: String = str((img as Dictionary).get("folder", ""))
		if not f.is_empty() and not folders.has(f):
			folders.append(f)
	for pf: Variant in reg.campaign.get_image_folders():
		var fname: String = str(pf)
		if not fname.is_empty() and not folders.has(fname):
			folders.append(fname)
	folders.sort()

	var dlg := AcceptDialog.new()
	dlg.title = "Move to Folder"
	dlg.dialog_text = "Select folder or type a new name:"
	var line_edit := LineEdit.new()
	line_edit.placeholder_text = "Folder name…"
	dlg.add_child(line_edit)
	dlg.confirmed.connect(func() -> void:
		var fname: String = line_edit.text.strip_edges()
		for img: Variant in reg.campaign.get_images():
			if not img is Dictionary:
				continue
			var d := img as Dictionary
			if str(d.get("id", "")) == img_id:
				reg.campaign.update_image(img_id, str(d.get("name", "")), fname)
				break
		reg.campaign.save_campaign()
		_refresh_images_list()
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.close_requested.connect(func() -> void: dlg.queue_free())
	add_child(dlg)
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg)
	dlg.popup_centered(Vector2i(300, 120))
	line_edit.grab_focus()


func _on_image_remove() -> void:
	var sel: TreeItem = _images_tree.get_selected() if _images_tree != null else null
	if sel == null:
		return
	var item_type: String = str(sel.get_meta("type"))
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return

	if item_type == "image":
		var img_id: String = str(sel.get_meta("id"))
		reg.campaign.remove_image(img_id)
		if img_id == _images_current_id:
			_images_current_id = ""
			if _images_preview != null:
				_images_preview.texture = null
			if _images_path_label != null:
				_images_path_label.text = ""
	elif item_type == "folder":
		var folder_name: String = str(sel.get_meta("folder"))
		reg.campaign.remove_image_folder(folder_name)
		var prefix: String = folder_name + "/"
		var to_delete: Array[String] = []
		for img: Variant in reg.campaign.get_images():
			if not img is Dictionary:
				continue
			var d := img as Dictionary
			var imf: String = str(d.get("folder", ""))
			if imf == folder_name or imf.begins_with(prefix):
				to_delete.append(str(d.get("id", "")))
		for iid: String in to_delete:
			reg.campaign.remove_image(iid)
			if iid == _images_current_id:
				_images_current_id = ""
				if _images_preview != null:
					_images_preview.texture = null
				if _images_path_label != null:
					_images_path_label.text = ""

	reg.campaign.save_campaign()
	_refresh_images_list()


func _on_image_open_external() -> void:
	var sel: TreeItem = _images_tree.get_selected() if _images_tree != null else null
	if sel == null or str(sel.get_meta("type")) != "image":
		return
	var img_id: String = str(sel.get_meta("id"))
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	for img: Variant in reg.campaign.get_images():
		if not img is Dictionary:
			continue
		var d := img as Dictionary
		if str(d.get("id", "")) == img_id:
			var path: String = str(d.get("path", ""))
			if not path.is_empty():
				OS.shell_open(path)
			return


# ─── Card system ──────────────────────────────────────────────────────────────

func _calc_columns() -> int:
	var s := _scale()
	var card_w: float = _CARD_MIN_W * s
	var pad: float = 10.0 * s
	var available: float = size.x - (24.0 * s)
	if available <= 0.0:
		available = 900.0 * s
	return maxi(1, floori((available + pad) / (card_w + pad)))


func _on_size_changed() -> void:
	var cols: int = _calc_columns()
	if _maps_grid != null:
		_maps_grid.columns = cols
	if _saves_grid != null:
		_saves_grid.columns = cols


func _find_bundle_image(bundle_path: String) -> String:
	for ext: String in _SUPPORTED_IMG_EXT:
		var candidate := bundle_path.path_join("image." + ext)
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _load_thumbnail_deferred(data: Dictionary, card: PanelContainer, is_map: bool) -> void:
	if not is_instance_valid(card):
		return
	var thumb_path: String = str(data.get("thumbnail_path", ""))
	var bundle_path: String = str(data.get("bundle_path", ""))
	if thumb_path.is_empty() or not FileAccess.file_exists(thumb_path):
		var img_path := _find_bundle_image(bundle_path)
		if img_path.is_empty() and not is_map:
			img_path = _find_bundle_image(bundle_path.path_join("map.map"))
		if not img_path.is_empty():
			var dest := bundle_path.path_join("thumbnail.png")
			var reg := _registry()
			if reg != null and reg.persistence != null:
				var ok: bool = reg.persistence.generate_thumbnail(img_path, dest)
				if ok:
					thumb_path = dest
	if thumb_path.is_empty() or not FileAccess.file_exists(thumb_path):
		return
	var img := Image.new()
	if img.load(thumb_path) != OK:
		return
	var tex := ImageTexture.create_from_image(img)
	if not is_instance_valid(card):
		return
	var vbox_node: VBoxContainer = card.get_child(0) as VBoxContainer
	if vbox_node == null:
		return
	for child: Node in vbox_node.get_children():
		if child is TextureRect and child.has_meta("is_thumbnail"):
			(child as TextureRect).texture = tex
			break


func _init_card_styles(s: float) -> void:
	var reg := _registry()
	var accent: Dictionary = {}
	if reg != null and reg.ui_theme != null:
		accent = reg.ui_theme.get_accent_palette()
	_card_normal = StyleBoxFlat.new()
	_card_normal.bg_color = accent.get("normal_bg", Color(0.18, 0.18, 0.20, 1.0)) as Color
	_card_normal.set_corner_radius_all(roundi(6.0 * s))
	_card_normal.set_content_margin_all(roundi(6.0 * s))
	_card_hover = StyleBoxFlat.new()
	_card_hover.bg_color = (_card_normal.bg_color).lightened(0.15)
	_card_hover.set_corner_radius_all(roundi(6.0 * s))
	_card_hover.set_content_margin_all(roundi(6.0 * s))
	_card_hover.border_color = accent.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	_card_hover.set_border_width_all(1)
	_card_selected = StyleBoxFlat.new()
	_card_selected.bg_color = accent.get("selected_bg", Color(0.25, 0.35, 0.55, 1.0)) as Color
	_card_selected.set_corner_radius_all(roundi(6.0 * s))
	_card_selected.set_content_margin_all(roundi(6.0 * s))
	_card_selected.border_color = accent.get("selected_border", Color(0.4, 0.6, 1.0)) as Color
	_card_selected.set_border_width_all(roundi(2.0 * s))


func _build_bundle_card(data: Dictionary, s: float, is_map: bool) -> PanelContainer:
	if _card_normal == null:
		_init_card_styles(s)
	var card_w: float = _CARD_MIN_W * s
	var thumb_h: float = _CARD_THUMB_H * s
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, 0.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_normal)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("bundle_path", str(data.get("bundle_path", "")))
	card.set_meta("is_map", is_map)
	card.set_meta(UIThemeManager.SKIP_AUTO_THEME, true)
	card.gui_input.connect(_on_bundle_card_input.bind(card))
	card.mouse_entered.connect(func() -> void: _on_bundle_card_hover(card, true))
	card.mouse_exited.connect(func() -> void: _on_bundle_card_hover(card, false))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", roundi(4.0 * s))
	card.add_child(vbox)
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(0.0, thumb_h)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.set_meta("is_thumbnail", true)
	vbox.add_child(thumb)
	var name_lbl := Label.new()
	name_lbl.text = str(data.get("name", ""))
	name_lbl.add_theme_font_size_override("font_size", roundi(14.0 * s))
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)
	var mod_t: int = int(data.get("modified_time", 0))
	var time_str: String = ""
	if mod_t > 0:
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(mod_t)
		time_str = "%04d-%02d-%02d %02d:%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"]]
	else:
		time_str = "Unknown date"
	var time_lbl := Label.new()
	time_lbl.text = time_str
	time_lbl.add_theme_font_size_override("font_size", roundi(11.0 * s))
	time_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	time_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(time_lbl)
	return card


func _build_character_card(sb: StatblockData, s: float, in_campaign: bool) -> PanelContainer:
	if _card_normal == null:
		_init_card_styles(s)
	var card_w: float = 180.0 * s
	var thumb_h: float = 160.0 * s
	var color_hue: float = fmod(float(sb.name.hash() & 0xFFFF) / 65535.0, 1.0)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, 0.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _card_normal)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("char_id", sb.id)
	card.set_meta(UIThemeManager.SKIP_AUTO_THEME, true)
	card.gui_input.connect(_on_char_card_input.bind(card))
	card.mouse_entered.connect(func() -> void: _on_char_card_hover(card, true))
	card.mouse_exited.connect(func() -> void: _on_char_card_hover(card, false))
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", roundi(3.0 * s))
	card.add_child(vbox)
	## ── Portrait frame ──────────────────────────────────────────────────
	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(0.0, thumb_h)
	portrait_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.set_meta(UIThemeManager.SKIP_AUTO_THEME, true)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color.from_hsv(color_hue, 0.42, 0.30)
	frame_style.set_content_margin_all(0)
	portrait_frame.add_theme_stylebox_override("panel", frame_style)
	vbox.add_child(portrait_frame)
	## Resolve portrait: campaign override → statblock path → linked profile icon.
	var portrait_path: String = ""
	var reg2 := _registry()
	if reg2 != null and reg2.campaign != null:
		portrait_path = reg2.campaign.resolve_character_portrait(sb.id)
	if portrait_path.is_empty():
		portrait_path = sb.portrait_path
	if portrait_path.is_empty():
		if reg2 != null and reg2.profile != null:
			for p_var: Variant in reg2.profile.get_profiles():
				if not p_var is PlayerProfile:
					continue
				var pp := p_var as PlayerProfile
				if pp.statblock_id == sb.id and not pp.icon_image_path.is_empty():
					var full: String = ProjectSettings.globalize_path("user://data/".path_join(pp.icon_image_path))
					if FileAccess.file_exists(full):
						portrait_path = full
					break
	if not portrait_path.is_empty() and FileAccess.file_exists(portrait_path):
		var img_rect := TextureRect.new()
		img_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		img_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_frame.add_child(img_rect)
		_load_card_image.call_deferred(portrait_path, img_rect)
	else:
		var name_overlay := Label.new()
		name_overlay.text = sb.name
		name_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
		name_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_overlay.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_overlay.autowrap_mode = TextServer.AUTOWRAP_WORD
		name_overlay.add_theme_font_size_override("font_size", roundi(18.0 * s))
		name_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_frame.add_child(name_overlay)
	## ── Name ────────────────────────────────────────────────────────────
	var display_name: String = sb.name
	if in_campaign and reg2 != null and reg2.campaign != null:
		var resolved: String = reg2.campaign.resolve_character_name(sb.id)
		if not resolved.is_empty():
			display_name = resolved
	var name_lbl2 := Label.new()
	name_lbl2.text = display_name
	name_lbl2.add_theme_font_size_override("font_size", roundi(13.0 * s))
	name_lbl2.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl2)
	## ── Class · Race ─────────────────────────────────────────────────────
	var info_parts: Array = []
	if not sb.class_name_str.is_empty() or sb.level > 0:
		info_parts.append("%s %d" % [sb.class_name_str, sb.level])
	if not sb.race.is_empty():
		info_parts.append(sb.race)
	var info_lbl := Label.new()
	info_lbl.text = " \u00b7 ".join(info_parts)
	info_lbl.add_theme_font_size_override("font_size", roundi(10.0 * s))
	info_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	info_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(info_lbl)
	if in_campaign:
		var check_lbl := Label.new()
		check_lbl.text = "\u2713 In Campaign"
		check_lbl.add_theme_font_size_override("font_size", roundi(10.0 * s))
		check_lbl.add_theme_color_override("font_color", Color(0.35, 0.75, 0.35))
		check_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(check_lbl)
	return card


func _load_card_image(path: String, target: TextureRect) -> void:
	if not is_instance_valid(target):
		return
	var img := Image.new()
	if img.load(path) != OK:
		return
	if is_instance_valid(target):
		target.texture = ImageTexture.create_from_image(img)


func _on_bundle_card_input(event: InputEvent, card: PanelContainer) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var is_map: bool = bool(card.get_meta("is_map", true))
	var path: String = str(card.get_meta("bundle_path", ""))
	## Deselect all siblings in the same grid.
	var grid: GridContainer = _maps_grid if is_map else _saves_grid
	if grid != null:
		for sibling: Node in grid.get_children():
			if sibling is PanelContainer and sibling != card:
				(sibling as PanelContainer).add_theme_stylebox_override("panel", _card_normal)
	card.add_theme_stylebox_override("panel", _card_selected)
	if is_map:
		_maps_selected_path = path
		_update_maps_btns()
	else:
		_saves_selected_path = path
		_update_saves_btns()
	if mb.double_click:
		if is_map:
			_on_maps_open()
		else:
			_on_saves_open()


func _on_bundle_card_hover(card: PanelContainer, entered: bool) -> void:
	var is_map: bool = bool(card.get_meta("is_map", true))
	var cur: String = _maps_selected_path if is_map else _saves_selected_path
	if str(card.get_meta("bundle_path", "")) == cur:
		return
	card.add_theme_stylebox_override("panel", _card_hover if entered else _card_normal)


func _on_char_card_input(event: InputEvent, card: PanelContainer) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var char_id: String = str(card.get_meta("char_id", ""))
	if _chars_grid != null:
		for sibling: Node in _chars_grid.get_children():
			if sibling is PanelContainer and sibling != card:
				(sibling as PanelContainer).add_theme_stylebox_override("panel", _card_normal)
	card.add_theme_stylebox_override("panel", _card_selected)
	_chars_selected_id = char_id
	_update_chars_btns()
	if mb.double_click:
		_on_chars_open_sheet()


func _on_char_card_hover(card: PanelContainer, entered: bool) -> void:
	if str(card.get_meta("char_id", "")) == _chars_selected_id:
		return
	card.add_theme_stylebox_override("panel", _card_hover if entered else _card_normal)


# ─── Helpers ──────────────────────────────────────────────────────────────────

func _add_lbl(parent: Control, text: String, s: float) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", roundi(13.0 * s))
	parent.add_child(lbl)


@warning_ignore("shadowed_variable_base_class")
func _make_btn(parent: Control, text: String, s: float, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(roundi(90.0 * s), roundi(32.0 * s))
	btn.add_theme_font_size_override("font_size", roundi(13.0 * s))
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn


## Shared dialog helpers for rename / name-input prompts.

## ── Inline tree editing (shared overlay LineEdit) ────────────────────────────

## Builds a nested folder hierarchy in the tree from "/" separated paths.
## Returns a Dictionary mapping full_path -> TreeItem for each folder node.
func _build_nested_folder_tree(tree: Tree, tree_root: TreeItem, folder_dict: Dictionary) -> Dictionary:
	## Collect all required paths (including intermediate segments)
	var all_paths: Dictionary = {}
	for key: Variant in folder_dict.keys():
		var p: String = str(key)
		var segments: PackedStringArray = p.split("/")
		var current: String = ""
		for seg: String in segments:
			current = (current + "/" + seg) if not current.is_empty() else seg
			all_paths[current] = true

	var sorted_paths: Array = all_paths.keys()
	sorted_paths.sort()

	var folder_items: Dictionary = {} # full_path -> TreeItem
	for path_v: Variant in sorted_paths:
		var p: String = str(path_v)
		var slash_idx: int = p.rfind("/")
		var parent_item: TreeItem = tree_root
		if slash_idx >= 0:
			var parent_path: String = p.left(slash_idx)
			if folder_items.has(parent_path):
				parent_item = folder_items[parent_path] as TreeItem
		var segment: String = p.substr(slash_idx + 1) if slash_idx >= 0 else p
		var folder_item: TreeItem = tree.create_item(parent_item)
		folder_item.set_text(0, segment)
		folder_item.set_meta("type", "folder")
		folder_item.set_meta("folder", p)
		folder_item.collapsed = false
		folder_items[p] = folder_item
	return folder_items


## Recursively search a tree for a folder item matching the given full path.
func _find_tree_item_by_folder(root: TreeItem, folder_path: String) -> TreeItem:
	var child: TreeItem = root.get_first_child()
	while child != null:
		if child.has_meta("type") and str(child.get_meta("type")) == "folder":
			if str(child.get_meta("folder")) == folder_path:
				return child
		var found: TreeItem = _find_tree_item_by_folder(child, folder_path)
		if found != null:
			return found
		child = child.get_next()
	return null


## Returns the parent portion of a "/" separated folder path, or "" if root-level.
func _folder_parent_path(full_path: String) -> String:
	var slash_idx: int = full_path.rfind("/")
	if slash_idx >= 0:
		return full_path.left(slash_idx)
	return ""


func _unique_folder_path(existing: Array, parent_path: String) -> String:
	var base: String = "Untitled Folder"
	var candidate: String = (parent_path + "/" + base) if not parent_path.is_empty() else base
	if not existing.has(candidate):
		return candidate
	var n: int = 2
	var numbered: String = base + " " + str(n)
	candidate = (parent_path + "/" + numbered) if not parent_path.is_empty() else numbered
	while existing.has(candidate):
		n += 1
		numbered = base + " " + str(n)
		candidate = (parent_path + "/" + numbered) if not parent_path.is_empty() else numbered
	return candidate


func _create_folder_in_tree(tree: Tree, is_notes: bool) -> void:
	var reg := _registry()
	if reg == null or reg.campaign == null or tree == null:
		return
	## Determine parent path from the currently selected item
	var parent_path: String = ""
	var sel: TreeItem = tree.get_selected()
	if sel != null:
		var sel_type: String = str(sel.get_meta("type")) if sel.has_meta("type") else ""
		if sel_type == "folder":
			parent_path = str(sel.get_meta("folder"))
		else:
			var par: TreeItem = sel.get_parent()
			if par != null and par.has_meta("type") and str(par.get_meta("type")) == "folder":
				parent_path = str(par.get_meta("folder"))
	var folders: Array = reg.campaign.get_note_folders() if is_notes else reg.campaign.get_image_folders()
	var folder_path: String = _unique_folder_path(folders, parent_path)
	if is_notes:
		reg.campaign.add_note_folder(folder_path)
	else:
		reg.campaign.add_image_folder(folder_path)
	reg.campaign.save_campaign()
	if is_notes:
		_refresh_notes_list()
	else:
		_refresh_images_list()
	## Find the newly created folder item (may be nested) and begin editing
	var tree_root: TreeItem = tree.get_root()
	if tree_root == null:
		return
	var target: TreeItem = _find_tree_item_by_folder(tree_root, folder_path)
	if target != null:
		target.select(0)
		## Ensure all ancestors are expanded
		var ancestor: TreeItem = target.get_parent()
		while ancestor != null:
			ancestor.collapsed = false
			ancestor = ancestor.get_parent()
		## Defer to next frame so the tree layout recalculates indentation
		await get_tree().process_frame
		_begin_tree_edit(tree, target, "new_folder")


func _ensure_tree_edit_line(tree: Tree) -> LineEdit:
	if _tree_edit_line != null and _tree_edit_line.get_parent() == tree:
		return _tree_edit_line
	## Remove from old parent if needed
	if _tree_edit_line != null and _tree_edit_line.get_parent() != null:
		_tree_edit_line.get_parent().remove_child(_tree_edit_line)
	if _tree_edit_line == null:
		_tree_edit_line = LineEdit.new()
		_tree_edit_line.visible = false
		## Theme: borderless flat style to blend with the tree
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.22, 0.22, 0.25, 1.0)
		sb.border_color = Color(0.5, 0.7, 1.0, 0.6)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(2)
		sb.set_content_margin_all(2)
		_tree_edit_line.add_theme_stylebox_override("normal", sb)
		var sb_focus := sb.duplicate() as StyleBoxFlat
		sb_focus.border_color = Color(0.5, 0.7, 1.0, 0.9)
		_tree_edit_line.add_theme_stylebox_override("focus", sb_focus)
		_tree_edit_line.add_theme_font_size_override("font_size", tree.get_theme_font_size("font_size"))
		_tree_edit_line.text_submitted.connect(_on_tree_edit_submitted)
		_tree_edit_line.focus_exited.connect(_on_tree_edit_focus_lost)
	tree.add_child(_tree_edit_line)
	return _tree_edit_line


func _begin_tree_edit(tree: Tree, item: TreeItem, action: String) -> void:
	if tree == null or item == null:
		return
	_tree_edit_owner = tree
	_tree_edit_item = item
	_tree_edit_action = action
	var edit_line: LineEdit = _ensure_tree_edit_line(tree)
	## Position the LineEdit over the tree item text area
	var rect: Rect2 = tree.get_item_area_rect(item, 0)
	## get_item_area_rect returns the full column-0 rect; offset by the item's
	## depth-based indent so the LineEdit aligns with the visible text.
	var depth: int = 0
	var ancestor: TreeItem = item.get_parent()
	while ancestor != null:
		depth += 1
		ancestor = ancestor.get_parent()
	## Subtract 1 because the hidden root counts as depth but has no indent
	if tree.hide_root:
		depth -= 1
	var indent_px: float = float(depth) * float(tree.get_theme_constant("item_margin"))
	## Also account for the fold arrow / button width for folder items
	var button_w: float = float(tree.get_theme_icon("arrow").get_width()) if depth > 0 or item.get_first_child() != null else 0.0
	var offset: float = indent_px + button_w
	edit_line.position = Vector2(rect.position.x + offset, rect.position.y)
	edit_line.size = Vector2(rect.size.x - offset, rect.size.y)
	edit_line.text = item.get_text(0)
	edit_line.visible = true
	edit_line.grab_focus()
	edit_line.select_all()


func _commit_tree_edit(new_text: String) -> void:
	if _tree_edit_line == null:
		return
	_tree_edit_line.visible = false
	var tree: Tree = _tree_edit_owner
	var item: TreeItem = _tree_edit_item
	var action: String = _tree_edit_action
	_tree_edit_owner = null
	_tree_edit_item = null
	_tree_edit_action = ""
	if item == null or tree == null:
		return
	var segment: String = new_text.strip_edges()
	if segment.is_empty():
		segment = "Untitled Folder"
	## Strip any "/" the user may have typed — segment names must not contain slashes
	segment = segment.replace("/", "")
	if segment.is_empty():
		segment = "Untitled Folder"
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var is_notes: bool = tree == _notes_tree
	var item_type: String = str(item.get_meta("type")) if item.has_meta("type") else ""
	if (action == "new_folder" or action == "rename") and item_type == "folder":
		var old_full_path: String = str(item.get_meta("folder"))
		var parent_path: String = _folder_parent_path(old_full_path)
		var new_full_path: String = (parent_path + "/" + segment) if not parent_path.is_empty() else segment
		if old_full_path != new_full_path:
			if is_notes:
				reg.campaign.rename_note_folder(old_full_path, new_full_path)
			else:
				reg.campaign.rename_image_folder(old_full_path, new_full_path)
			reg.campaign.save_campaign()
			if is_notes:
				_refresh_notes_list()
			else:
				_refresh_images_list()
	elif action == "rename" and item_type == "image" and not is_notes:
		var img_id: String = str(item.get_meta("id"))
		for img: Variant in reg.campaign.get_images():
			if not img is Dictionary:
				continue
			var d := img as Dictionary
			if str(d.get("id", "")) == img_id:
				reg.campaign.update_image(img_id, segment, str(d.get("folder", "")))
				break
		reg.campaign.save_campaign()
		_refresh_images_list()


func _on_tree_edit_submitted(new_text: String) -> void:
	_commit_tree_edit(new_text)


func _on_tree_edit_focus_lost() -> void:
	if _tree_edit_line != null and _tree_edit_line.visible:
		_commit_tree_edit(_tree_edit_line.text)


func _show_rename_dialog(title_text: String, current_name: String, on_confirm: Callable) -> void:
	var reg := _registry()
	var dlg := AcceptDialog.new()
	dlg.title = title_text
	dlg.dialog_text = "Enter new name:"
	var line_edit := LineEdit.new()
	line_edit.text = current_name
	dlg.add_child(line_edit)
	dlg.confirmed.connect(func() -> void:
		var new_name: String = line_edit.text.strip_edges()
		if new_name.is_empty() or new_name == current_name:
			dlg.queue_free()
			return
		on_confirm.call(new_name)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.close_requested.connect(func() -> void: dlg.queue_free())
	add_child(dlg)
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg)
	dlg.popup_centered(Vector2i(300, 120))
	line_edit.grab_focus()
	line_edit.select_all()


func _show_name_dialog(title_text: String, placeholder: String, on_confirm: Callable) -> void:
	var reg := _registry()
	var dlg := AcceptDialog.new()
	dlg.title = title_text
	dlg.dialog_text = "Enter name:"
	var line_edit := LineEdit.new()
	line_edit.placeholder_text = placeholder
	dlg.add_child(line_edit)
	dlg.confirmed.connect(func() -> void:
		var fname: String = line_edit.text.strip_edges()
		if fname.is_empty():
			dlg.queue_free()
			return
		on_confirm.call(fname)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.close_requested.connect(func() -> void: dlg.queue_free())
	add_child(dlg)
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg)
	dlg.popup_centered(Vector2i(300, 120))
	line_edit.grab_focus()


# ─── Drag-and-drop ────────────────────────────────────────────────────────────

func _notes_get_drag_data(at_position: Vector2) -> Variant:
	if _notes_tree == null:
		return null
	var item: TreeItem = _notes_tree.get_item_at_position(at_position)
	if item == null:
		return null
	var label := Label.new()
	label.text = item.get_text(0)
	_notes_tree.set_drag_preview(label)
	return {"tree": "notes", "item": item}


func _notes_can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var d := data as Dictionary
	if str(d.get("tree", "")) != "notes":
		return false
	var dragged: TreeItem = d.get("item") as TreeItem
	if dragged == null:
		return false
	var target: TreeItem = _notes_tree.get_item_at_position(at_position)
	if target == dragged:
		return false
	if target == null:
		return true # drop at root level
	var target_type: String = str(target.get_meta("type"))
	if target_type == "folder":
		if str(dragged.get_meta("type")) == "folder":
			var dragged_path: String = str(dragged.get_meta("folder"))
			var target_path: String = str(target.get_meta("folder"))
			if target_path == dragged_path or target_path.begins_with(dragged_path + "/"):
				return false
		return true
	return false


func _notes_drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	var d := data as Dictionary
	var dragged: TreeItem = d.get("item") as TreeItem
	if dragged == null:
		return
	var target: TreeItem = _notes_tree.get_item_at_position(at_position)
	var target_folder: String = ""
	if target != null and str(target.get_meta("type")) == "folder":
		target_folder = str(target.get_meta("folder"))
	_move_tree_item_to_folder(_notes_tree, dragged, target_folder)


func _images_get_drag_data(at_position: Vector2) -> Variant:
	if _images_tree == null:
		return null
	var item: TreeItem = _images_tree.get_item_at_position(at_position)
	if item == null:
		return null
	var label := Label.new()
	label.text = item.get_text(0)
	_images_tree.set_drag_preview(label)
	return {"tree": "images", "item": item}


func _images_can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var d := data as Dictionary
	if str(d.get("tree", "")) != "images":
		return false
	var dragged: TreeItem = d.get("item") as TreeItem
	if dragged == null:
		return false
	var target: TreeItem = _images_tree.get_item_at_position(at_position)
	if target == dragged:
		return false
	if target == null:
		return true
	var target_type: String = str(target.get_meta("type"))
	if target_type == "folder":
		if str(dragged.get_meta("type")) == "folder":
			var dragged_path: String = str(dragged.get_meta("folder"))
			var target_path: String = str(target.get_meta("folder"))
			if target_path == dragged_path or target_path.begins_with(dragged_path + "/"):
				return false
		return true
	return false


func _images_drop_data(at_position: Vector2, data: Variant) -> void:
	if not data is Dictionary:
		return
	var d := data as Dictionary
	var dragged: TreeItem = d.get("item") as TreeItem
	if dragged == null:
		return
	var target: TreeItem = _images_tree.get_item_at_position(at_position)
	var target_folder: String = ""
	if target != null and str(target.get_meta("type")) == "folder":
		target_folder = str(target.get_meta("folder"))
	_move_tree_item_to_folder(_images_tree, dragged, target_folder)


func _move_tree_item_to_folder(tree: Tree, item: TreeItem, target_folder: String) -> void:
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	var item_type: String = str(item.get_meta("type"))
	var is_notes: bool = tree == _notes_tree

	if item_type == "note":
		var note_id: String = str(item.get_meta("id"))
		var old_folder: String = ""
		var note_title: String = ""
		var body: String = ""
		for n: Variant in reg.campaign.get_notes():
			if not n is Dictionary:
				continue
			var nd := n as Dictionary
			if str(nd.get("id", "")) == note_id:
				old_folder = str(nd.get("folder", ""))
				note_title = str(nd.get("title", ""))
				body = str(nd.get("body", ""))
				break
		if old_folder == target_folder:
			return
		_undo_action = "move_note"
		_undo_data = {"id": note_id, "title": note_title, "body": body, "old_folder": old_folder}
		reg.campaign.update_note(note_id, note_title, body, target_folder)

	elif item_type == "image":
		var img_id: String = str(item.get_meta("id"))
		var old_folder: String = ""
		var img_name: String = ""
		for img: Variant in reg.campaign.get_images():
			if not img is Dictionary:
				continue
			var d := img as Dictionary
			if str(d.get("id", "")) == img_id:
				old_folder = str(d.get("folder", ""))
				img_name = str(d.get("name", ""))
				break
		if old_folder == target_folder:
			return
		_undo_action = "move_image"
		_undo_data = {"id": img_id, "name": img_name, "old_folder": old_folder}
		reg.campaign.update_image(img_id, img_name, target_folder)

	elif item_type == "folder":
		var old_path: String = str(item.get_meta("folder"))
		if target_folder == old_path or target_folder.begins_with(old_path + "/"):
			return
		var segment: String = old_path.get_slice("/", old_path.get_slice_count("/") - 1)
		var new_path: String = (target_folder + "/" + segment) if not target_folder.is_empty() else segment
		_undo_action = "move_folder"
		_undo_data = {"old_path": old_path, "new_path": new_path, "is_notes": is_notes}
		if is_notes:
			reg.campaign.rename_note_folder(old_path, new_path)
		else:
			reg.campaign.rename_image_folder(old_path, new_path)

	reg.campaign.save_campaign()
	if is_notes:
		_refresh_notes_list()
	else:
		_refresh_images_list()


# ─── Clipboard (cut / copy / paste) ──────────────────────────────────────────

func _clipboard_cut(tree: Tree) -> void:
	var sel: TreeItem = tree.get_selected() if tree != null else null
	if sel == null:
		return
	_clipboard_tree = tree
	_clipboard_mode = "cut"
	_clipboard_items = [_tree_item_to_clipboard(sel)]


func _clipboard_copy(tree: Tree) -> void:
	var sel: TreeItem = tree.get_selected() if tree != null else null
	if sel == null:
		return
	_clipboard_tree = tree
	_clipboard_mode = "copy"
	_clipboard_items = [_tree_item_to_clipboard(sel)]


func _tree_item_to_clipboard(item: TreeItem) -> Dictionary:
	var item_type: String = str(item.get_meta("type"))
	var result: Dictionary = {"type": item_type}
	if item_type == "note" or item_type == "image":
		result["id"] = str(item.get_meta("id"))
	elif item_type == "folder":
		result["folder"] = str(item.get_meta("folder"))
	return result


func _clipboard_paste(tree: Tree) -> void:
	if _clipboard_items.is_empty() or _clipboard_tree != tree:
		return
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return

	var sel: TreeItem = tree.get_selected()
	var target_folder: String = ""
	if sel != null:
		var sel_type: String = str(sel.get_meta("type"))
		if sel_type == "folder":
			target_folder = str(sel.get_meta("folder"))
		else:
			var parent: TreeItem = sel.get_parent()
			if parent != null and parent.has_meta("type") and str(parent.get_meta("type")) == "folder":
				target_folder = str(parent.get_meta("folder"))

	var is_notes: bool = tree == _notes_tree
	for entry: Variant in _clipboard_items:
		if not entry is Dictionary:
			continue
		var e := entry as Dictionary
		var item_type: String = str(e.get("type", ""))
		if _clipboard_mode == "cut":
			_paste_move(reg, is_notes, item_type, e, target_folder)
		else:
			_paste_copy(reg, is_notes, item_type, e, target_folder)

	if _clipboard_mode == "cut":
		_clipboard_items.clear()

	reg.campaign.save_campaign()
	if is_notes:
		_refresh_notes_list()
	else:
		_refresh_images_list()


func _paste_move(reg: ServiceRegistry, is_notes: bool, item_type: String, entry: Dictionary, target_folder: String) -> void:
	if item_type == "note":
		var note_id: String = str(entry.get("id", ""))
		for n: Variant in reg.campaign.get_notes():
			if not n is Dictionary:
				continue
			var nd := n as Dictionary
			if str(nd.get("id", "")) == note_id:
				_undo_action = "move_note"
				_undo_data = {"id": note_id, "title": str(nd.get("title", "")), "body": str(nd.get("body", "")), "old_folder": str(nd.get("folder", ""))}
				reg.campaign.update_note(note_id, str(nd.get("title", "")), str(nd.get("body", "")), target_folder)
				break
	elif item_type == "image":
		var img_id: String = str(entry.get("id", ""))
		for img: Variant in reg.campaign.get_images():
			if not img is Dictionary:
				continue
			var d := img as Dictionary
			if str(d.get("id", "")) == img_id:
				_undo_action = "move_image"
				_undo_data = {"id": img_id, "name": str(d.get("name", "")), "old_folder": str(d.get("folder", ""))}
				reg.campaign.update_image(img_id, str(d.get("name", "")), target_folder)
				break
	elif item_type == "folder":
		var old_path: String = str(entry.get("folder", ""))
		var segment: String = old_path.get_slice("/", old_path.get_slice_count("/") - 1)
		var new_path: String = (target_folder + "/" + segment) if not target_folder.is_empty() else segment
		_undo_action = "move_folder"
		_undo_data = {"old_path": old_path, "new_path": new_path, "is_notes": is_notes}
		if is_notes:
			reg.campaign.rename_note_folder(old_path, new_path)
		else:
			reg.campaign.rename_image_folder(old_path, new_path)


func _paste_copy(reg: ServiceRegistry, is_notes: bool, item_type: String, entry: Dictionary, target_folder: String) -> void:
	## Copy duplicates notes; images and folders only support cut (move).
	if item_type == "note" and is_notes:
		var note_id: String = str(entry.get("id", ""))
		for n: Variant in reg.campaign.get_notes():
			if not n is Dictionary:
				continue
			var nd := n as Dictionary
			if str(nd.get("id", "")) == note_id:
				reg.campaign.add_note(
					str(nd.get("title", "")) + " (copy)",
					str(nd.get("body", "")),
					target_folder
				)
				break


# ─── Undo ─────────────────────────────────────────────────────────────────────

func _undo_last_move() -> void:
	if _undo_action.is_empty():
		return
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return

	match _undo_action:
		"move_note":
			var note_id: String = str(_undo_data.get("id", ""))
			var note_title: String = str(_undo_data.get("title", ""))
			var body: String = str(_undo_data.get("body", ""))
			var old_folder: String = str(_undo_data.get("old_folder", ""))
			reg.campaign.update_note(note_id, note_title, body, old_folder)
		"move_image":
			var img_id: String = str(_undo_data.get("id", ""))
			var img_name: String = str(_undo_data.get("name", ""))
			var old_folder: String = str(_undo_data.get("old_folder", ""))
			reg.campaign.update_image(img_id, img_name, old_folder)
		"move_folder":
			var old_path: String = str(_undo_data.get("old_path", ""))
			var new_path: String = str(_undo_data.get("new_path", ""))
			var is_notes: bool = bool(_undo_data.get("is_notes", true))
			if is_notes:
				reg.campaign.rename_note_folder(new_path, old_path)
			else:
				reg.campaign.rename_image_folder(new_path, old_path)

	_undo_action = ""
	_undo_data = {}
	reg.campaign.save_campaign()
	_refresh_notes_list()
	_refresh_images_list()


# ─── Bestiary dialog field builders ───────────────────────────────────────────

func _bst_section(parent: Control, text: String, font_sz: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_sz)
	parent.add_child(lbl)


func _bst_line(parent: Control, label_text: String, value: String, font_sz: int, si: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", si.call(6.0))
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(si.call(110.0), 0)
	lbl.add_theme_font_size_override("font_size", font_sz)
	row.add_child(lbl)
	var le := LineEdit.new()
	le.text = value
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_size_override("font_size", font_sz)
	row.add_child(le)
	return le


func _bst_spin(parent: Control, label_text: String, value: int, min_val: int, max_val: int, font_sz: int, si: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", si.call(6.0))
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(si.call(110.0), 0)
	lbl.add_theme_font_size_override("font_size", font_sz)
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = value
	spin.custom_minimum_size = Vector2(si.call(100.0), 0)
	spin.add_theme_font_size_override("font_size", font_sz)
	spin.get_line_edit().add_theme_font_size_override("font_size", font_sz)
	row.add_child(spin)
	return spin


func _bst_option(parent: Control, label_text: String, items: Array, current: String, font_sz: int, si: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", si.call(6.0))
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(si.call(110.0), 0)
	lbl.add_theme_font_size_override("font_size", font_sz)
	row.add_child(lbl)
	var opt := OptionButton.new()
	opt.add_theme_font_size_override("font_size", font_sz)
	var sel_idx: int = 0
	for i: int in items.size():
		opt.add_item(str(items[i]))
		if str(items[i]) == current:
			sel_idx = i
	opt.selected = sel_idx
	row.add_child(opt)
	return opt


func _bst_text(parent: Control, value: String, font_sz: int, si: Callable) -> TextEdit:
	var te := TextEdit.new()
	te.text = value
	te.custom_minimum_size = Vector2(0, si.call(80.0))
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.add_theme_font_size_override("font_size", font_sz)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(te)
	return te


# ─── Bestiary action/senses text conversion ──────────────────────────────────

func _actions_to_text(arr: Array) -> String:
	var lines: PackedStringArray = PackedStringArray()
	for entry: Variant in arr:
		if entry is ActionEntry:
			var ae := entry as ActionEntry
			lines.append("%s | %s" % [ae.name, ae.desc])
		elif entry is Dictionary:
			var d := entry as Dictionary
			lines.append("%s | %s" % [str(d.get("name", "")), str(d.get("desc", ""))])
	return "\n".join(lines)


func _text_to_actions(text: String) -> Array:
	var result: Array = []
	for line: String in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty():
			continue
		var parts: PackedStringArray = trimmed.split("|", true, 1)
		var ae := ActionEntry.new()
		ae.name = parts[0].strip_edges() if parts.size() > 0 else trimmed
		ae.desc = parts[1].strip_edges() if parts.size() > 1 else ""
		result.append(ae)
	return result


func _senses_to_text(senses_dict: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: Variant in senses_dict:
		parts.append("%s %s" % [str(key), str(senses_dict[key])])
	return ", ".join(parts)


func _text_to_senses(text: String) -> Dictionary:
	var result: Dictionary = {}
	if text.is_empty():
		return result
	for part: String in text.split(","):
		var trimmed: String = part.strip_edges()
		if trimmed.is_empty():
			continue
		var space_idx: int = trimmed.find(" ")
		if space_idx > 0:
			result[trimmed.left(space_idx)] = trimmed.substr(space_idx + 1).strip_edges()
		else:
			result[trimmed] = ""
	return result


func _csv_to_array(text: String) -> Array:
	var result: Array = []
	for part: String in text.split(","):
		var trimmed: String = part.strip_edges()
		if not trimmed.is_empty():
			result.append(trimmed)
	return result
