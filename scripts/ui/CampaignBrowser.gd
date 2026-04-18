extends Window
class_name CampaignBrowser

## CampaignBrowser — startup campaign selection window.
##
## Shown on app launch when no recent campaign exists, and after "Close Campaign".
## Presents all discovered .campaign bundles as selection cards.
## All campaign mutations are delegated back to DMWindow via signals.

signal campaign_selected(path: String)
signal create_new_requested()
signal open_folder_requested()

## Card style references (built in populate()).
var _normal_style: StyleBoxFlat = null
var _hover_style: StyleBoxFlat = null
var _selected_style: StyleBoxFlat = null

var _grid: GridContainer = null
var _scroll: ScrollContainer = null
var _empty_lbl: Label = null
var _open_btn: Button = null
var _selected_path: String = ""


func _ready() -> void:
	title = "Choose a Campaign"
	min_size = Vector2i(780, 560)
	wrap_controls = true
	popup_window = false
	exclusive = false
	transient = true

	close_requested.connect(func() -> void: hide())
	_build_ui()


func populate() -> void:
	## Scan the campaigns directory and rebuild the card grid.
	var reg := _registry()
	if reg == null or reg.campaign == null:
		return
	_init_card_styles()
	_populate_grid(reg.campaign.list_campaigns())
	var tm: UIThemeManager = reg.ui_theme if reg != null else null
	if tm != null:
		tm.theme_control_tree(self , _scale())


func _registry() -> ServiceRegistry:
	return get_node_or_null("/root/ServiceRegistry") as ServiceRegistry


func _scale() -> float:
	var reg := _registry()
	if reg != null and reg.ui_scale != null:
		return reg.ui_scale.get_scale()
	return 1.0


# ── Card styles ───────────────────────────────────────────────────────────────

func _init_card_styles() -> void:
	var s := _scale()
	var reg := _registry()
	var accent: Dictionary = {}
	if reg != null and reg.ui_theme != null:
		accent = reg.ui_theme.get_accent_palette()

	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = accent.get("normal_bg", Color(0.18, 0.18, 0.20, 1.0)) as Color
	_normal_style.set_corner_radius_all(roundi(6.0 * s))
	_normal_style.set_content_margin_all(roundi(10.0 * s))

	_hover_style = StyleBoxFlat.new()
	_hover_style.bg_color = (_normal_style.bg_color).lightened(0.12)
	_hover_style.set_corner_radius_all(roundi(6.0 * s))
	_hover_style.set_content_margin_all(roundi(10.0 * s))
	_hover_style.border_color = accent.get("panel_border", Color(0.35, 0.35, 0.38)) as Color
	_hover_style.set_border_width_all(1)

	_selected_style = StyleBoxFlat.new()
	_selected_style.bg_color = accent.get("selected_bg", Color(0.25, 0.35, 0.55, 1.0)) as Color
	_selected_style.set_corner_radius_all(roundi(6.0 * s))
	_selected_style.set_content_margin_all(roundi(10.0 * s))
	_selected_style.border_color = accent.get("selected_border", Color(0.4, 0.6, 1.0)) as Color
	_selected_style.set_border_width_all(roundi(2.0 * s))


# ── Grid population ───────────────────────────────────────────────────────────

func _populate_grid(campaigns: Array) -> void:
	for child in _grid.get_children():
		child.queue_free()
	_selected_path = ""
	_update_open_btn()

	var has_campaigns: bool = not campaigns.is_empty()
	_scroll.visible = has_campaigns
	_empty_lbl.visible = not has_campaigns

	for entry: Variant in campaigns:
		if entry is Dictionary:
			_grid.add_child(_build_card(entry as Dictionary))


func _build_card(data: Dictionary) -> PanelContainer:
	var s := _scale()
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220.0 * s, 110.0 * s)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _normal_style.duplicate())
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.set_meta("path", str(data.get("path", "")))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", roundi(4.0 * s))
	card.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = str(data.get("name", "Unnamed Campaign"))
	name_lbl.add_theme_font_size_override("font_size", roundi(15.0 * s))
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var ruleset_lbl := Label.new()
	ruleset_lbl.text = "Ruleset: %s" % str(data.get("default_ruleset", "2014"))
	ruleset_lbl.add_theme_font_size_override("font_size", roundi(11.0 * s))
	ruleset_lbl.modulate.a = 0.65
	ruleset_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(ruleset_lbl)

	var map_count: int = (data.get("map_paths") as Array).size() if data.get("map_paths") is Array else 0
	var save_count: int = (data.get("save_paths") as Array).size() if data.get("save_paths") is Array else 0
	var stats_lbl := Label.new()
	stats_lbl.text = "%d map(s)  \u2022  %d save(s)" % [map_count, save_count]
	stats_lbl.add_theme_font_size_override("font_size", roundi(11.0 * s))
	stats_lbl.modulate.a = 0.65
	stats_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(stats_lbl)

	card.gui_input.connect(_on_card_input.bind(card))
	card.mouse_entered.connect(_on_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_card_hover.bind(card, false))
	return card


func _on_card_hover(card: PanelContainer, entered: bool) -> void:
	var path: String = str(card.get_meta("path", ""))
	if path == _selected_path:
		return
	card.add_theme_stylebox_override("panel", _hover_style.duplicate() if entered else _normal_style.duplicate())


func _on_card_input(event: InputEvent, card: PanelContainer) -> void:
	if not (event is InputEventMouseButton):
		return
	var mbe := event as InputEventMouseButton
	if mbe.button_index != MOUSE_BUTTON_LEFT or not mbe.pressed:
		return
	# Deselect all siblings.
	for sibling in _grid.get_children():
		if sibling != card:
			sibling.add_theme_stylebox_override("panel", _normal_style.duplicate())
	card.add_theme_stylebox_override("panel", _selected_style.duplicate())
	_selected_path = str(card.get_meta("path", ""))
	_update_open_btn()
	if mbe.double_click:
		_do_open()


func _do_open() -> void:
	if _selected_path.is_empty():
		return
	hide()
	campaign_selected.emit(_selected_path)


func _update_open_btn() -> void:
	if _open_btn != null:
		_open_btn.disabled = _selected_path.is_empty()


# ── Build UI ──────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var s := _scale()

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", roundi(14.0 * s))
	margin.add_theme_constant_override("margin_right", roundi(14.0 * s))
	margin.add_theme_constant_override("margin_top", roundi(12.0 * s))
	margin.add_theme_constant_override("margin_bottom", roundi(12.0 * s))
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", roundi(10.0 * s))
	margin.add_child(root)

	# Subtitle
	var hint_lbl := Label.new()
	hint_lbl.text = "Select a campaign to open, or create a new one."
	hint_lbl.add_theme_font_size_override("font_size", roundi(13.0 * s))
	hint_lbl.modulate.a = 0.7
	root.add_child(hint_lbl)

	# Top action row
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", roundi(8.0 * s))
	root.add_child(top_row)

	var new_btn := Button.new()
	new_btn.text = "New Campaign\u2026"
	new_btn.pressed.connect(func() -> void:
		create_new_requested.emit())
	top_row.add_child(new_btn)

	var folder_btn := Button.new()
	folder_btn.text = "📁"
	folder_btn.custom_minimum_size = Vector2(roundi(36.0 * s), roundi(32.0 * s))
	folder_btn.add_theme_font_size_override("font_size", roundi(15.0 * s))
	folder_btn.tooltip_text = "Open campaigns folder…"
	folder_btn.pressed.connect(func() -> void:
		open_folder_requested.emit())
	top_row.add_child(folder_btn)

	# Campaign card grid (scroll area)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", roundi(10.0 * s))
	_grid.add_theme_constant_override("v_separation", roundi(10.0 * s))
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)

	# Empty state label (shown when no campaigns exist)
	_empty_lbl = Label.new()
	_empty_lbl.text = "No campaigns found.\nClick \"New Campaign\u2026\" to create your first campaign."
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_lbl.add_theme_font_size_override("font_size", roundi(14.0 * s))
	_empty_lbl.modulate.a = 0.55
	_empty_lbl.hide()
	root.add_child(_empty_lbl)

	# Bottom button row
	var sep := HSeparator.new()
	root.add_child(sep)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", roundi(8.0 * s))
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(btn_row)

	_open_btn = Button.new()
	_open_btn.text = "Open"
	_open_btn.disabled = true
	_open_btn.pressed.connect(_do_open)
	btn_row.add_child(_open_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func() -> void: hide())
	btn_row.add_child(cancel_btn)
