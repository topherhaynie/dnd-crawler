extends Window
class_name CampaignImagePicker

# ---------------------------------------------------------------------------
# CampaignImagePicker — modal popup for selecting an image from the active
# campaign's image library.
#
# Usage:
#   var picker := CampaignImagePicker.new()
#   picker.image_selected.connect(_on_campaign_image_picked)
#   add_child(picker)
#   picker.show_picker()
#
# The selected signal carries (path, campaign_image_id) so the caller can
# set both the concrete file path and the back-reference in one step.
# ---------------------------------------------------------------------------

## Emitted when the user confirms a selection.
## path: absolute filesystem path to the image file.
## campaign_image_id: the campaign image entry ID for traceability.
signal image_selected(path: String, campaign_image_id: String)

var _grid: GridContainer = null
var _scroll: ScrollContainer = null
var _preview: TextureRect = null
var _name_label: Label = null
var _path_label: Label = null
var _ok_btn: Button = null
var _cancel_btn: Button = null
var _search_edit: LineEdit = null

var _selected_id: String = ""
var _selected_path: String = ""
var _card_map: Dictionary = {} ## campaign_image_id → PanelContainer

var _normal_style: StyleBoxFlat = null
var _hover_style: StyleBoxFlat = null
var _selected_style: StyleBoxFlat = null


func _ready() -> void:
	title = "Pick from Campaign Images"
	min_size = Vector2i(640, 480)
	wrap_controls = false
	transient = true
	exclusive = false

	close_requested.connect(func() -> void: hide())
	_build_ui()


func show_picker() -> void:
	_selected_id = ""
	_selected_path = ""
	_update_ok_state()
	_populate_grid()
	var reg := _registry()
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(self , _scale())
	var s: float = _scale()
	size = Vector2i(roundi(680.0 * s), roundi(520.0 * s))
	min_size = Vector2i(roundi(480.0 * s), roundi(380.0 * s))
	popup_centered()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var s: float = _scale()
	_init_card_styles()

	var m_pad: int = roundi(10.0 * s)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.set_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", m_pad)
	margin.add_theme_constant_override("margin_right", m_pad)
	margin.add_theme_constant_override("margin_top", m_pad)
	margin.add_theme_constant_override("margin_bottom", m_pad)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", roundi(8.0 * s))
	margin.add_child(outer)

	## Search bar
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Filter images..."
	_search_edit.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_changed)
	outer.add_child(_search_edit)

	## Split: grid on left, preview on right
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = roundi(380.0 * s)
	outer.add_child(split)

	## Left — scrollable grid of image thumbnails
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(roundi(280.0 * s), 0)
	split.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", roundi(6.0 * s))
	_grid.add_theme_constant_override("v_separation", roundi(6.0 * s))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)

	## Right — preview pane
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", roundi(6.0 * s))
	right.custom_minimum_size = Vector2(roundi(180.0 * s), 0)
	split.add_child(right)

	_preview = TextureRect.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	right.add_child(_preview)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	right.add_child(_name_label)

	_path_label = Label.new()
	_path_label.add_theme_font_size_override("font_size", roundi(11.0 * s))
	_path_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_path_label)

	## Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", roundi(8.0 * s))
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.custom_minimum_size = Vector2(roundi(80.0 * s), roundi(28.0 * s))
	_cancel_btn.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_cancel_btn.pressed.connect(func() -> void: hide())
	btn_row.add_child(_cancel_btn)

	_ok_btn = Button.new()
	_ok_btn.text = "Select"
	_ok_btn.custom_minimum_size = Vector2(roundi(80.0 * s), roundi(28.0 * s))
	_ok_btn.add_theme_font_size_override("font_size", roundi(13.0 * s))
	_ok_btn.disabled = true
	_ok_btn.pressed.connect(_on_ok_pressed)
	btn_row.add_child(_ok_btn)


# ---------------------------------------------------------------------------
# Grid population
# ---------------------------------------------------------------------------

func _populate_grid(filter_text: String = "") -> void:
	if _grid == null:
		return
	for child: Node in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_card_map.clear()

	var reg := _registry()
	if reg == null or reg.campaign == null:
		var empty_lbl := Label.new()
		empty_lbl.text = "No campaign loaded."
		empty_lbl.add_theme_font_size_override("font_size", roundi(13.0 * _scale()))
		_grid.add_child(empty_lbl)
		return

	var images: Array = reg.campaign.get_images()
	if images.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No images in this campaign.\nAdd images via the Campaign Panel."
		empty_lbl.add_theme_font_size_override("font_size", roundi(13.0 * _scale()))
		_grid.add_child(empty_lbl)
		return

	var s: float = _scale()
	var thumb_size: int = roundi(100.0 * s)
	var query: String = filter_text.strip_edges().to_lower()

	for img: Variant in images:
		if not img is Dictionary:
			continue
		var d := img as Dictionary
		var img_name: String = str(d.get("name", ""))
		var img_id: String = str(d.get("id", ""))
		var img_path: String = str(d.get("path", ""))

		if not query.is_empty() and img_name.to_lower().find(query) == -1:
			continue

		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(thumb_size, thumb_size + roundi(24.0 * s))
		card.add_theme_stylebox_override("panel", _normal_style.duplicate())
		card.mouse_entered.connect(_on_card_hover.bind(card, true))
		card.mouse_exited.connect(_on_card_hover.bind(card, false))
		card.gui_input.connect(_on_card_input.bind(img_id, img_path, img_name))

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", roundi(2.0 * s))
		card.add_child(vbox)

		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(thumb_size, thumb_size)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(tex_rect)

		if not img_path.is_empty() and FileAccess.file_exists(img_path):
			_load_thumbnail.call_deferred(img_path, tex_rect)

		var lbl := Label.new()
		lbl.text = img_name
		lbl.add_theme_font_size_override("font_size", roundi(11.0 * s))
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lbl)

		_grid.add_child(card)
		_card_map[img_id] = card


# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_card_input(event: InputEvent, img_id: String, img_path: String, img_name: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_select_image(img_id, img_path, img_name)
			if mb.double_click:
				_on_ok_pressed()


func _on_card_hover(card: PanelContainer, entered: bool) -> void:
	if card == null:
		return
	var card_id: String = ""
	for key: String in _card_map:
		if _card_map[key] == card:
			card_id = key
			break
	if card_id == _selected_id:
		return
	card.add_theme_stylebox_override("panel", (_hover_style if entered else _normal_style).duplicate())


func _select_image(img_id: String, img_path: String, img_name: String) -> void:
	# Deselect previous
	if not _selected_id.is_empty() and _card_map.has(_selected_id):
		var old_card: PanelContainer = _card_map[_selected_id] as PanelContainer
		if old_card != null:
			old_card.add_theme_stylebox_override("panel", _normal_style.duplicate())

	_selected_id = img_id
	_selected_path = img_path

	# Highlight new
	if _card_map.has(img_id):
		var new_card: PanelContainer = _card_map[img_id] as PanelContainer
		if new_card != null:
			new_card.add_theme_stylebox_override("panel", _selected_style.duplicate())

	# Update preview
	if _name_label != null:
		_name_label.text = img_name
	if _path_label != null:
		_path_label.text = img_path
	if _preview != null:
		_preview.texture = null
		if not img_path.is_empty() and FileAccess.file_exists(img_path):
			var image := Image.new()
			if image.load(img_path) == OK:
				_preview.texture = ImageTexture.create_from_image(image)

	_update_ok_state()


func _on_ok_pressed() -> void:
	if _selected_path.is_empty():
		return
	image_selected.emit(_selected_path, _selected_id)
	hide()


func _on_search_changed(new_text: String) -> void:
	_populate_grid(new_text)
	# Re-select if still visible
	if not _selected_id.is_empty() and _card_map.has(_selected_id):
		var card: PanelContainer = _card_map[_selected_id] as PanelContainer
		if card != null:
			card.add_theme_stylebox_override("panel", _selected_style.duplicate())


func _update_ok_state() -> void:
	if _ok_btn != null:
		_ok_btn.disabled = _selected_path.is_empty()


# ---------------------------------------------------------------------------
# Card styles
# ---------------------------------------------------------------------------

func _init_card_styles() -> void:
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = Color(0.18, 0.18, 0.22, 1.0)
	_normal_style.set_corner_radius_all(4)
	_normal_style.set_content_margin_all(4)

	_hover_style = StyleBoxFlat.new()
	_hover_style.bg_color = Color(0.26, 0.26, 0.32, 1.0)
	_hover_style.set_corner_radius_all(4)
	_hover_style.set_content_margin_all(4)

	_selected_style = StyleBoxFlat.new()
	_selected_style.bg_color = Color(0.2, 0.35, 0.55, 1.0)
	_selected_style.border_color = Color(0.4, 0.6, 0.9, 1.0)
	_selected_style.set_border_width_all(2)
	_selected_style.set_corner_radius_all(4)
	_selected_style.set_content_margin_all(4)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _load_thumbnail(path: String, target: TextureRect) -> void:
	if not is_instance_valid(target):
		return
	if not FileAccess.file_exists(path):
		return
	var image := Image.new()
	if image.load(path) != OK:
		return
	## Downscale for thumbnail performance.
	var max_dim: int = 256
	if image.get_width() > max_dim or image.get_height() > max_dim:
		image.resize(max_dim, max_dim, Image.INTERPOLATE_LANCZOS)
	target.texture = ImageTexture.create_from_image(image)


func _registry() -> ServiceRegistry:
	return get_node_or_null("/root/ServiceRegistry") as ServiceRegistry


func _scale() -> float:
	var reg := _registry()
	if reg != null and reg.ui_scale != null:
		return reg.ui_scale.get_scale()
	return 1.0
