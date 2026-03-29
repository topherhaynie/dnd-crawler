extends Window
class_name BundleBrowser

## BundleBrowser — tabbed grid browser for .map and .sav bundles.
##
## Usage:
##   var browser := BundleBrowser.new()
##   add_child(browser)
##   browser.map_selected.connect(_on_map_selected)
##   browser.save_selected.connect(_on_save_selected)
##   browser.new_map_requested.connect(_on_new_map)
##   browser.open_map_file_requested.connect(_on_open_map_file)
##   browser.open_save_file_requested.connect(_on_open_save_file)
##   browser.populate()
##   browser.open_to_mode("map")  # or "save"
##   browser.popup_centered_ratio(0.85)

signal map_selected(path: String)
signal save_selected(path: String)
signal new_map_requested()
signal open_map_file_requested()
signal open_save_file_requested()

const _SUPPORTED_IMG_EXT: Array = ["png", "jpg", "jpeg", "webp", "bmp", "tga"]

## Card sizing constants (base, before UI scale)
const _CARD_MIN_W: float = 220.0
const _CARD_THUMB_H: float = 160.0
const _CARD_PAD: float = 8.0

# ── Per-tab state ────────────────────────────────────────────────────────────
var _map_cards: Array = []
var _save_cards: Array = []
var _map_selected_index: int = -1
var _save_selected_index: int = -1
var _map_grid: GridContainer = null
var _save_grid: GridContainer = null
var _map_scroll: ScrollContainer = null
var _save_scroll: ScrollContainer = null
var _map_search_edit: LineEdit = null
var _save_search_edit: LineEdit = null
var _map_empty_label: Label = null
var _save_empty_label: Label = null

# ── Shared UI references ─────────────────────────────────────────────────────
var _tabs: TabContainer = null
var _open_btn: Button = null

## Style
var _normal_style: StyleBoxFlat = null
var _hover_style: StyleBoxFlat = null
var _selected_style: StyleBoxFlat = null


func _ready() -> void:
	title = "Maps & Saves"
	min_size = Vector2i(700, 500)
	close_requested.connect(_on_cancel)
	_build_ui()


## Switch to the given tab before showing. Call before popup_centered_ratio().
func open_to_mode(browse_mode: String) -> void:
	if _tabs == null:
		return
	_tabs.current_tab = 0 if browse_mode == "map" else 1


func _build_ui() -> void:
	var scale: float = _ui_scale()

	# ── Root margin ──────────────────────────────────────────────────────
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", roundi(12.0 * scale))
	margin.add_theme_constant_override("margin_right", roundi(12.0 * scale))
	margin.add_theme_constant_override("margin_top", roundi(12.0 * scale))
	margin.add_theme_constant_override("margin_bottom", roundi(12.0 * scale))
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", roundi(8.0 * scale))
	margin.add_child(root_vbox)

	# ── Tab container ────────────────────────────────────────────────────
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", roundi(15.0 * scale))
	_tabs.tab_changed.connect(_on_tab_changed)
	root_vbox.add_child(_tabs)

	_build_tab(_tabs, "Maps", scale, true)
	_build_tab(_tabs, "Saves", scale, false)

	# ── Bottom button bar ────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", roundi(8.0 * scale))
	root_vbox.add_child(btn_row)

	var new_btn := Button.new()
	new_btn.text = "New"
	new_btn.custom_minimum_size = Vector2(roundi(90.0 * scale), roundi(32.0 * scale))
	new_btn.add_theme_font_size_override("font_size", roundi(13.0 * scale))
	new_btn.tooltip_text = "New Map from Image…"
	new_btn.pressed.connect(_on_new_pressed)
	btn_row.add_child(new_btn)

	var folder_btn := Button.new()
	folder_btn.text = "📁"
	folder_btn.custom_minimum_size = Vector2(roundi(36.0 * scale), roundi(32.0 * scale))
	folder_btn.add_theme_font_size_override("font_size", roundi(15.0 * scale))
	folder_btn.tooltip_text = "Open file…"
	folder_btn.pressed.connect(_on_folder_pressed)
	btn_row.add_child(folder_btn)

	# Flexible spacer pushes Cancel/Open to the right
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(roundi(90.0 * scale), roundi(32.0 * scale))
	cancel_btn.add_theme_font_size_override("font_size", roundi(13.0 * scale))
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	_open_btn = Button.new()
	_open_btn.text = "Open"
	_open_btn.custom_minimum_size = Vector2(roundi(90.0 * scale), roundi(32.0 * scale))
	_open_btn.add_theme_font_size_override("font_size", roundi(13.0 * scale))
	_open_btn.disabled = true
	_open_btn.pressed.connect(_on_open_pressed)
	btn_row.add_child(_open_btn)

	# ── Theme self (window chrome + all child buttons) ───────────────────
	var _bt_reg := _get_registry()
	if _bt_reg != null and _bt_reg.ui_theme != null:
		_bt_reg.ui_theme.theme_control_tree(self , scale)

	# ── Card styles ──────────────────────────────────────────────────────
	var accent: Dictionary = {}
	if _bt_reg != null and _bt_reg.ui_theme != null:
		accent = _bt_reg.ui_theme.get_accent_palette()
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = accent.get("normal_bg", Color(0.18, 0.18, 0.20, 1.0)) as Color
	_normal_style.set_corner_radius_all(roundi(6.0 * scale))
	_normal_style.set_content_margin_all(roundi(6.0 * scale))

	_hover_style = StyleBoxFlat.new()
	_hover_style.bg_color = (_normal_style.bg_color).lightened(0.15)
	_hover_style.set_corner_radius_all(roundi(6.0 * scale))
	_hover_style.set_content_margin_all(roundi(6.0 * scale))
	_hover_style.border_color = accent.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	_hover_style.set_border_width_all(1)

	_selected_style = StyleBoxFlat.new()
	_selected_style.bg_color = accent.get("selected_bg", Color(0.25, 0.35, 0.55, 1.0)) as Color
	_selected_style.set_corner_radius_all(roundi(6.0 * scale))
	_selected_style.set_content_margin_all(roundi(6.0 * scale))
	_selected_style.border_color = accent.get("selected_border", Color(0.4, 0.6, 1.0)) as Color
	_selected_style.set_border_width_all(roundi(2.0 * scale))

	# ── Tab bar styles (palette-driven, scaled) ───────────────────────────
	var tab_normal_bg: Color = accent.get("normal_bg", Color(0.22, 0.22, 0.24)) as Color
	var tab_hover_bg: Color = accent.get("hover_bg", Color(0.28, 0.28, 0.30)) as Color
	var tab_selected_bg: Color = accent.get("panel_bg", Color(0.18, 0.18, 0.20)) as Color
	var tab_border: Color = accent.get("panel_border", Color(0.35, 0.35, 0.38)) as Color
	var tab_selected_border: Color = accent.get("selected_border", Color(0.4, 0.6, 1.0)) as Color
	var tab_font: Color = accent.get("label_tint", Color(0.75, 0.75, 0.75)) as Color
	var tab_corner: int = roundi(4.0 * scale)
	var tab_pad_v: int = roundi(8.0 * scale)
	var tab_pad_h: int = roundi(14.0 * scale)

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
	ts_selected.border_width_top = roundi(2.0 * scale)
	ts_selected.border_width_bottom = 0

	_tabs.add_theme_stylebox_override("tab_unselected", ts_unselected)
	_tabs.add_theme_stylebox_override("tab_hovered", ts_hovered)
	_tabs.add_theme_stylebox_override("tab_selected", ts_selected)
	_tabs.add_theme_color_override("font_unselected_color", tab_font.darkened(0.2))
	_tabs.add_theme_color_override("font_hovered_color", tab_font)
	_tabs.add_theme_color_override("font_selected_color", tab_font.lightened(0.2))

	# Recalculate columns on resize
	size_changed.connect(_on_window_resized)


func _build_tab(tabs: TabContainer, tab_title: String, scale: float, is_maps: bool) -> void:
	var tab_root := VBoxContainer.new()
	tab_root.name = tab_title
	tab_root.add_theme_constant_override("separation", roundi(8.0 * scale))
	tabs.add_child(tab_root)

	var search := LineEdit.new()
	search.placeholder_text = "Search…"
	search.clear_button_enabled = true
	search.add_theme_font_size_override("font_size", roundi(14.0 * scale))
	tab_root.add_child(search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_root.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = _calc_columns()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", roundi(10.0 * scale))
	grid.add_theme_constant_override("v_separation", roundi(10.0 * scale))
	scroll.add_child(grid)

	var empty_lbl := Label.new()
	empty_lbl.text = "No maps found." if is_maps else "No saves found."
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_lbl.add_theme_font_size_override("font_size", roundi(16.0 * scale))
	empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_lbl.hide()
	tab_root.add_child(empty_lbl)

	if is_maps:
		_map_search_edit = search
		_map_scroll = scroll
		_map_grid = grid
		_map_empty_label = empty_lbl
		search.text_changed.connect(_on_map_search_changed)
	else:
		_save_search_edit = search
		_save_scroll = scroll
		_save_grid = grid
		_save_empty_label = empty_lbl
		search.text_changed.connect(_on_save_search_changed)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func populate() -> void:
	## Scan both directories and rebuild both grids.
	_map_selected_index = -1
	_save_selected_index = -1
	if _open_btn != null:
		_open_btn.disabled = true

	var registry := _get_registry()
	var pm: PersistenceManager = registry.persistence if registry != null else null

	# ── Maps ──────────────────────────────────────────────────────────────
	_map_cards.clear()
	if pm != null:
		var map_base_dir: String = ProjectSettings.globalize_path("user://data/maps")
		for bundle_name: Variant in pm.list_map_bundles():
			var bundle_path: String = map_base_dir.path_join(str(bundle_name) + ".map")
			var meta: Dictionary = pm.load_bundle_metadata(bundle_path)
			_map_cards.append({
				"bundle_path": meta.get("bundle_path", bundle_path) as String,
				"name": meta.get("name", str(bundle_name)) as String,
				"modified_time": meta.get("modified_time", 0),
				"thumbnail_path": meta.get("thumbnail_path", "") as String,
			})
		_map_cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["modified_time"]) > int(b["modified_time"])
		)
	_rebuild_grid(true)

	# ── Saves ─────────────────────────────────────────────────────────────
	_save_cards.clear()
	if pm != null:
		var save_base_dir: String = ProjectSettings.globalize_path("user://data/saves")
		for bundle_name: Variant in pm.list_save_bundles():
			var bundle_path: String = save_base_dir.path_join(str(bundle_name) + ".sav")
			var meta: Dictionary = pm.load_bundle_metadata(bundle_path)
			_save_cards.append({
				"bundle_path": meta.get("bundle_path", bundle_path) as String,
				"name": meta.get("name", str(bundle_name)) as String,
				"modified_time": meta.get("modified_time", 0),
				"thumbnail_path": meta.get("thumbnail_path", "") as String,
			})
		_save_cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["modified_time"]) > int(b["modified_time"])
		)
	_rebuild_grid(false)


# ---------------------------------------------------------------------------
# Grid building
# ---------------------------------------------------------------------------

func _rebuild_grid(is_maps: bool) -> void:
	var grid: GridContainer = _map_grid if is_maps else _save_grid
	var search_edit: LineEdit = _map_search_edit if is_maps else _save_search_edit
	var cards: Array = _map_cards if is_maps else _save_cards
	if grid == null:
		return

	for child: Node in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	grid.columns = _calc_columns()
	var scale: float = _ui_scale()
	var card_w: float = _CARD_MIN_W * scale
	var thumb_h: float = _CARD_THUMB_H * scale
	var visible_cards: int = 0
	var filter_text: String = search_edit.text.strip_edges().to_lower() if search_edit != null else ""

	for i: int in range(cards.size()):
		var card_data: Dictionary = cards[i]
		var card_name: String = card_data["name"] as String

		if not filter_text.is_empty() and card_name.to_lower().find(filter_text) == -1:
			continue

		var card := _build_card(i, card_data, card_w, thumb_h, scale, is_maps)
		grid.add_child(card)
		visible_cards += 1

		_load_thumbnail_deferred.call_deferred(i, card_data, card, is_maps)

	_show_empty(is_maps, visible_cards == 0)


func _build_card(index: int, data: Dictionary, card_w: float, thumb_h: float, scale: float, is_maps: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, 0.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _normal_style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("card_index", index)
	card.set_meta(UIThemeManager.SKIP_AUTO_THEME, true)

	card.gui_input.connect(_on_card_gui_input.bind(index, card, is_maps))
	card.mouse_entered.connect(_on_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_card_hover.bind(card, false))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", roundi(4.0 * scale))
	card.add_child(vbox)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(0.0, thumb_h)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.set_meta("is_thumbnail", true)
	vbox.add_child(thumb)

	var name_label := Label.new()
	name_label.text = data["name"] as String
	name_label.add_theme_font_size_override("font_size", roundi(14.0 * scale))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	var mod_time: int = int(data["modified_time"])
	var time_str: String = ""
	if mod_time > 0:
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(mod_time)
		time_str = "%04d-%02d-%02d %02d:%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"]]
	else:
		time_str = "Unknown date"
	var time_label := Label.new()
	time_label.text = time_str
	time_label.add_theme_font_size_override("font_size", roundi(11.0 * scale))
	time_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(time_label)

	return card


func _load_thumbnail_deferred(index: int, data: Dictionary, card: PanelContainer, is_maps: bool) -> void:
	if not is_instance_valid(card):
		return

	var thumb_path: String = data["thumbnail_path"] as String
	var bundle_path: String = data["bundle_path"] as String

	if thumb_path.is_empty() or not FileAccess.file_exists(thumb_path):
		var img_path := _find_bundle_image(bundle_path)
		if img_path.is_empty() and not is_maps:
			img_path = _find_bundle_image(bundle_path.path_join("map.map"))
		if not img_path.is_empty():
			var dest := bundle_path.path_join("thumbnail.png")
			var registry := _get_registry()
			if registry != null and registry.persistence != null:
				var ok: bool = registry.persistence.generate_thumbnail(img_path, dest)
				if ok:
					thumb_path = dest
					if is_maps:
						_map_cards[index]["thumbnail_path"] = dest
					else:
						_save_cards[index]["thumbnail_path"] = dest

	if thumb_path.is_empty() or not FileAccess.file_exists(thumb_path):
		return

	var img := Image.new()
	var err: Error = img.load(thumb_path)
	if err != OK:
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


# ---------------------------------------------------------------------------
# Card interaction
# ---------------------------------------------------------------------------

func _on_card_gui_input(event: InputEvent, index: int, card: PanelContainer, is_maps: bool) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.double_click:
				_select_card(index, card, is_maps)
				_on_open_pressed()
			else:
				_select_card(index, card, is_maps)


func _on_card_hover(card: PanelContainer, entered: bool) -> void:
	var active_index: int = _map_selected_index if _tabs != null and _tabs.current_tab == 0 else _save_selected_index
	if card.has_meta("card_index") and int(card.get_meta("card_index")) == active_index:
		return
	card.add_theme_stylebox_override("panel", _hover_style if entered else _normal_style)


func _select_card(index: int, card: PanelContainer, is_maps: bool) -> void:
	var grid: GridContainer = _map_grid if is_maps else _save_grid
	var prev_index: int = _map_selected_index if is_maps else _save_selected_index

	if prev_index >= 0 and grid != null:
		for child: Node in grid.get_children():
			if child is PanelContainer and child.has_meta("card_index"):
				if int(child.get_meta("card_index")) == prev_index:
					(child as PanelContainer).add_theme_stylebox_override("panel", _normal_style)

	if is_maps:
		_map_selected_index = index
	else:
		_save_selected_index = index
	card.add_theme_stylebox_override("panel", _selected_style)
	if _open_btn != null:
		_open_btn.disabled = false


func _on_tab_changed(_tab: int) -> void:
	# Update Open button state to reflect new tab's selection
	if _open_btn == null or _tabs == null:
		return
	var is_maps: bool = _tabs.current_tab == 0
	var sel: int = _map_selected_index if is_maps else _save_selected_index
	_open_btn.disabled = sel < 0


func _on_open_pressed() -> void:
	if _tabs == null:
		return
	var is_maps: bool = _tabs.current_tab == 0
	var cards: Array = _map_cards if is_maps else _save_cards
	var sel: int = _map_selected_index if is_maps else _save_selected_index
	if sel < 0 or sel >= cards.size():
		return
	var path: String = cards[sel]["bundle_path"] as String
	hide()
	if is_maps:
		map_selected.emit(path)
	else:
		save_selected.emit(path)


func _on_new_pressed() -> void:
	hide()
	new_map_requested.emit()


func _on_folder_pressed() -> void:
	hide()
	if _tabs != null and _tabs.current_tab == 0:
		open_map_file_requested.emit()
	else:
		open_save_file_requested.emit()


func _on_cancel() -> void:
	hide()


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

func _on_map_search_changed(_new_text: String) -> void:
	_rebuild_grid(true)


func _on_save_search_changed(_new_text: String) -> void:
	_rebuild_grid(false)


# ---------------------------------------------------------------------------
# Responsive columns
# ---------------------------------------------------------------------------

func _on_window_resized() -> void:
	if _map_grid != null:
		_map_grid.columns = _calc_columns()
	if _save_grid != null:
		_save_grid.columns = _calc_columns()


func _calc_columns() -> int:
	var scale: float = _ui_scale()
	var card_w: float = _CARD_MIN_W * scale
	var pad: float = _CARD_PAD * scale
	var available: float = float(size.x) - (24.0 * scale) # 12px margin × 2
	if available <= 0.0:
		available = 700.0
	var cols: int = maxi(1, floori((available + pad) / (card_w + pad)))
	return cols


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _show_empty(is_maps: bool, is_empty: bool) -> void:
	var empty_lbl: Label = _map_empty_label if is_maps else _save_empty_label
	var scroll: ScrollContainer = _map_scroll if is_maps else _save_scroll
	if empty_lbl != null:
		empty_lbl.visible = is_empty
	if scroll != null:
		scroll.visible = not is_empty


func _find_bundle_image(bundle_path: String) -> String:
	for ext: String in _SUPPORTED_IMG_EXT:
		var candidate := bundle_path.path_join("image." + ext)
		if FileAccess.file_exists(candidate):
			return candidate
	return ""


func _ui_scale() -> float:
	var registry := _get_registry()
	if registry != null and registry.ui_scale != null:
		return registry.ui_scale.get_scale()
	return 1.0


func _get_registry() -> ServiceRegistry:
	var reg := Engine.get_main_loop()
	if reg == null:
		return null
	var tree: SceneTree = reg as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
