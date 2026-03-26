extends Window
class_name BundleBrowser

## BundleBrowser — scrollable grid browser for .map and .sav bundles.
##
## Usage:
##   var browser := BundleBrowser.new()
##   browser.mode = "map"          # or "save"
##   add_child(browser)
##   browser.bundle_selected.connect(_on_bundle_selected)
##   browser.populate()
##   browser.popup_centered_ratio(0.85)

signal bundle_selected(path: String)

const _SUPPORTED_IMG_EXT: Array = ["png", "jpg", "jpeg", "webp", "bmp", "tga"]

## "map" or "save" — determines which directory to scan and labels to show.
var browse_mode: String = "map"

# ── Internal state ───────────────────────────────────────────────────────────
var _cards: Array = [] ## Array of {bundle_path, name, modified_time, thumbnail_path, node}
var _selected_index: int = -1
var _grid: GridContainer = null
var _scroll: ScrollContainer = null
var _search_edit: LineEdit = null
var _open_btn: Button = null
var _empty_label: Label = null

## Card sizing constants (base, before UI scale)
const _CARD_MIN_W: float = 220.0
const _CARD_THUMB_H: float = 160.0
const _CARD_PAD: float = 8.0

## Style
var _normal_style: StyleBoxFlat = null
var _selected_style: StyleBoxFlat = null


func _ready() -> void:
	title = "Browse Maps" if browse_mode == "map" else "Browse Saves"
	min_size = Vector2i(700, 500)
	close_requested.connect(_on_cancel)
	_build_ui()


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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", roundi(8.0 * scale))
	margin.add_child(vbox)

	# ── Search bar ───────────────────────────────────────────────────────
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search…"
	_search_edit.clear_button_enabled = true
	_search_edit.add_theme_font_size_override("font_size", roundi(14.0 * scale))
	_search_edit.text_changed.connect(_on_search_changed)
	vbox.add_child(_search_edit)

	# ── Scroll + Grid ────────────────────────────────────────────────────
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = _calc_columns()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", roundi(10.0 * scale))
	_grid.add_theme_constant_override("v_separation", roundi(10.0 * scale))
	_scroll.add_child(_grid)

	# ── Empty label (hidden by default) ──────────────────────────────────
	_empty_label = Label.new()
	_empty_label.text = "No maps found." if browse_mode == "map" else "No saves found."
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.add_theme_font_size_override("font_size", roundi(16.0 * scale))
	_empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_label.hide()
	vbox.add_child(_empty_label)

	# ── Bottom button bar ────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", roundi(8.0 * scale))
	vbox.add_child(btn_row)

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

	# ── Card styles ──────────────────────────────────────────────────────
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = Color(0.18, 0.18, 0.20, 1.0)
	_normal_style.set_corner_radius_all(roundi(6.0 * scale))
	_normal_style.set_content_margin_all(roundi(6.0 * scale))

	_selected_style = StyleBoxFlat.new()
	_selected_style.bg_color = Color(0.25, 0.35, 0.55, 1.0)
	_selected_style.set_corner_radius_all(roundi(6.0 * scale))
	_selected_style.set_content_margin_all(roundi(6.0 * scale))
	_selected_style.border_color = Color(0.4, 0.6, 1.0)
	_selected_style.set_border_width_all(roundi(2.0 * scale))

	# Recalculate columns on resize
	size_changed.connect(_on_window_resized)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func populate() -> void:
	## Scan the appropriate directory and rebuild the card grid.
	_cards.clear()
	_selected_index = -1
	if _open_btn != null:
		_open_btn.disabled = true

	var registry := _get_registry()
	if registry == null or registry.persistence == null:
		_show_empty(true)
		return

	var pm: PersistenceManager = registry.persistence
	var names: Array = []
	var base_dir: String = ""
	var suffix: String = ""

	if browse_mode == "map":
		names = pm.list_map_bundles()
		base_dir = ProjectSettings.globalize_path("user://data/maps")
		suffix = ".map"
	else:
		names = pm.list_save_bundles()
		base_dir = ProjectSettings.globalize_path("user://data/saves")
		suffix = ".sav"

	for bundle_name in names:
		var bundle_path: String = base_dir.path_join(str(bundle_name) + suffix)
		var meta: Dictionary = pm.load_bundle_metadata(bundle_path)
		_cards.append({
			"bundle_path": meta.get("bundle_path", bundle_path) as String,
			"name": meta.get("name", str(bundle_name)) as String,
			"modified_time": meta.get("modified_time", 0),
			"thumbnail_path": meta.get("thumbnail_path", "") as String,
		})

	# Sort by modified time descending (most recent first)
	_cards.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["modified_time"]) > int(b["modified_time"])
	)

	_rebuild_grid()


# ---------------------------------------------------------------------------
# Grid building
# ---------------------------------------------------------------------------

func _rebuild_grid() -> void:
	# Clear existing children
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	_grid.columns = _calc_columns()
	var scale: float = _ui_scale()
	var card_w: float = _CARD_MIN_W * scale
	var thumb_h: float = _CARD_THUMB_H * scale
	var visible_cards: int = 0

	for i: int in range(_cards.size()):
		var card_data: Dictionary = _cards[i]
		var card_name: String = card_data["name"] as String
		var filter_text: String = _search_edit.text.strip_edges().to_lower() if _search_edit != null else ""

		if not filter_text.is_empty() and card_name.to_lower().find(filter_text) == -1:
			continue

		var card := _build_card(i, card_data, card_w, thumb_h, scale)
		_grid.add_child(card)
		visible_cards += 1

		# Lazy-load thumbnail
		_load_thumbnail_deferred.call_deferred(i, card_data, card)

	_show_empty(visible_cards == 0)


func _build_card(index: int, data: Dictionary, card_w: float, thumb_h: float, scale: float) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(card_w, 0.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _normal_style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("card_index", index)

	# Click handling
	card.gui_input.connect(_on_card_gui_input.bind(index, card))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", roundi(4.0 * scale))
	card.add_child(vbox)

	# Thumbnail
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(0.0, thumb_h)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.set_meta("is_thumbnail", true)
	vbox.add_child(thumb)

	# Name label
	var name_label := Label.new()
	name_label.text = data["name"] as String
	name_label.add_theme_font_size_override("font_size", roundi(14.0 * scale))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	# Timestamp label
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


func _load_thumbnail_deferred(index: int, data: Dictionary, card: PanelContainer) -> void:
	if not is_instance_valid(card):
		return

	var thumb_path: String = data["thumbnail_path"] as String
	var bundle_path: String = data["bundle_path"] as String

	# If no thumbnail exists, try to generate one (legacy backfill)
	if thumb_path.is_empty() or not FileAccess.file_exists(thumb_path):
		var img_path := _find_bundle_image(bundle_path)
		if img_path.is_empty() and bundle_path.ends_with(".sav"):
			# For saves, look inside the embedded map.map/
			img_path = _find_bundle_image(bundle_path.path_join("map.map"))
		if not img_path.is_empty():
			var dest := bundle_path.path_join("thumbnail.png")
			var registry := _get_registry()
			if registry != null and registry.persistence != null:
				var ok: bool = registry.persistence.generate_thumbnail(img_path, dest)
				if ok:
					thumb_path = dest
					_cards[index]["thumbnail_path"] = dest

	if thumb_path.is_empty() or not FileAccess.file_exists(thumb_path):
		return

	var img := Image.new()
	var err := img.load(thumb_path)
	if err != OK:
		return
	var tex := ImageTexture.create_from_image(img)

	# Find the TextureRect in the card
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

func _on_card_gui_input(event: InputEvent, index: int, card: PanelContainer) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.double_click:
				_select_card(index, card)
				_on_open_pressed()
			else:
				_select_card(index, card)


func _select_card(index: int, card: PanelContainer) -> void:
	# Deselect previous
	if _selected_index >= 0:
		for child: Node in _grid.get_children():
			if child is PanelContainer and child.has_meta("card_index"):
				if int(child.get_meta("card_index")) == _selected_index:
					(child as PanelContainer).add_theme_stylebox_override("panel", _normal_style)
	_selected_index = index
	card.add_theme_stylebox_override("panel", _selected_style)
	if _open_btn != null:
		_open_btn.disabled = false


func _on_open_pressed() -> void:
	if _selected_index < 0 or _selected_index >= _cards.size():
		return
	var path: String = _cards[_selected_index]["bundle_path"] as String
	bundle_selected.emit(path)
	hide()


func _on_cancel() -> void:
	hide()


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

func _on_search_changed(_new_text: String) -> void:
	_rebuild_grid()


# ---------------------------------------------------------------------------
# Responsive columns
# ---------------------------------------------------------------------------

func _on_window_resized() -> void:
	if _grid != null:
		_grid.columns = _calc_columns()


func _calc_columns() -> int:
	var scale: float = _ui_scale()
	var card_w: float = _CARD_MIN_W * scale
	var pad: float = _CARD_PAD * scale
	# Estimate available width from window size minus margins
	var available: float = float(size.x) - (24.0 * scale) # 12px margin × 2
	if available <= 0.0:
		available = 700.0
	var cols: int = maxi(1, floori((available + pad) / (card_w + pad)))
	return cols


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _show_empty(is_empty: bool) -> void:
	if _empty_label != null:
		_empty_label.visible = is_empty
	if _scroll != null:
		_scroll.visible = not is_empty


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
