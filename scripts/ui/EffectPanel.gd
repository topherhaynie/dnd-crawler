extends PanelContainer
class_name EffectPanel

# ---------------------------------------------------------------------------
# EffectPanel — dedicated side-panel for magic effect configuration.
#
# Contains effect type selection, a size slider, and a burst-mode toggle.
# Docked to the right side of the DM window (to the left of the freeze
# panel) or detached into a floating window.
# ---------------------------------------------------------------------------

signal effect_type_selected(effect_type: int)
signal shape_changed(shape: int)
signal palette_changed(palette: int)
signal burst_mode_changed(enabled: bool)
signal size_changed(size_px: float)
## Emitted when a manifest-driven effect is selected (Phase 11).
signal effect_definition_id_selected(effect_id: String)

var _selected_effect_type: int = 0
var _selected_shape: int = EffectData.EffectShape.CIRCLE
var _selected_palette: int = 0
var _burst_mode: bool = false
var _effect_size_ft: float = 20.0 ## Size in feet (slider unit)
var _px_per_foot: float = 0.0 ## 0 = uncalibrated

## Phase 11: manifest mode — populated by setup_manifest().
var _definitions: Array = []
var _selected_effect_definition_id: String = ""
var _manifest_mode: bool = false

var _vbox: VBoxContainer = null
var _type_buttons: Array[Button] = []
var _type_group: ButtonGroup = null
var _shape_buttons: Array[Button] = []
var _shape_group: ButtonGroup = null
var _shape_container: HBoxContainer = null
var _palette_header: Label = null
var _palette_container: HBoxContainer = null
var _palette_buttons: Array[Button] = []
var _palette_group: ButtonGroup = null
var _burst_check: CheckBox = null
var _size_slider: HSlider = null
var _size_label: Label = null
var _undock_btn: Button = null
var _title_label: Label = null
var _ui_scale_mgr: UIScaleManager = null
var _ui_theme_mgr: UIThemeManager = null


func setup(mgr: UIScaleManager, theme_mgr: UIThemeManager = null) -> void:
	_ui_scale_mgr = mgr
	_ui_theme_mgr = theme_mgr
	_build()


func refresh_theme() -> void:
	## Update all button/panel/header styles when the active theme changes.
	if _ui_theme_mgr == null:
		return
	var palette: Dictionary = _ui_theme_mgr.get_accent_palette()
	var panel_bg: Color = palette.get("panel_bg", Color(0.15, 0.15, 0.15, 0.95)) as Color
	var panel_border: Color = palette.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	var hdr_tint: Color = _ui_theme_mgr.get_header_tint()
	# Panel background
	var bg_sb: Variant = get_theme_stylebox("panel")
	if bg_sb is StyleBoxFlat:
		(bg_sb as StyleBoxFlat).bg_color = panel_bg
		(bg_sb as StyleBoxFlat).border_color = panel_border
	# Re-theme all child controls via the manager's tree walk
	_ui_theme_mgr.theme_control_tree(self , _s())
	# Header label tints
	for child: Node in _vbox.get_children():
		if child is Label and (child as Label).text in ["SHAPE", "PALETTE", "SIZE"]:
			(child as Label).add_theme_color_override("font_color", hdr_tint)


func _s() -> float:
	if _ui_scale_mgr != null:
		return _ui_scale_mgr.get_scale()
	return 1.0


func _build() -> void:
	var s: float = _s()
	name = "EffectPanel"

	# Dark background
	var _ep_accent: Dictionary = UIThemeData.get_accent_palette(
		_ui_theme_mgr.get_theme() if _ui_theme_mgr != null else 0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = _ep_accent.get("panel_bg", Color(0.15, 0.15, 0.15, 0.95)) as Color
	bg.border_width_left = 1
	bg.border_color = _ep_accent.get("panel_border", Color(0.3, 0.3, 0.3)) as Color
	add_theme_stylebox_override("panel", bg)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", roundi(4.0 * s))
	margin.add_theme_constant_override("margin_right", roundi(4.0 * s))
	margin.add_theme_constant_override("margin_top", roundi(4.0 * s))
	margin.add_theme_constant_override("margin_bottom", roundi(4.0 * s))
	add_child(margin)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", roundi(4.0 * s))
	margin.add_child(_vbox)

	# Undock button
	_undock_btn = Button.new()
	_undock_btn.text = "⇲"
	_undock_btn.focus_mode = Control.FOCUS_NONE
	_undock_btn.tooltip_text = "Detach / re-dock effect panel"
	_undock_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_undock_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_undock_btn.custom_minimum_size = Vector2(0, roundi(22.0 * s))
	_undock_btn.add_theme_font_size_override("font_size", roundi(14.0 * s))
	if _ui_theme_mgr != null:
		_ui_theme_mgr.apply_button_style(_undock_btn, s)
	_vbox.add_child(_undock_btn)

	_vbox.add_child(HSeparator.new())

	# Title
	_title_label = Label.new()
	_title_label.text = "Effects"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", roundi(15.0 * s))
	_vbox.add_child(_title_label)

	_vbox.add_child(HSeparator.new())

	# Effect type buttons — manifest-grouped or legacy hardcoded
	_type_group = ButtonGroup.new()

	if _manifest_mode:
		_build_manifest_buttons(s)
	else:
		_build_legacy_buttons(s)

	_vbox.add_child(HSeparator.new())

	# Shape selector row — hidden in manifest mode (scenes are self-contained)
	var shape_header := Label.new()
	shape_header.text = "SHAPE"
	shape_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shape_header.add_theme_font_size_override("font_size", roundi(9.0 * s))
	var _hdr_tint: Color = _ui_theme_mgr.get_header_tint() if _ui_theme_mgr != null else Color(0.6, 0.6, 0.6)
	shape_header.add_theme_color_override("font_color", _hdr_tint)
	shape_header.visible = not _manifest_mode
	_vbox.add_child(shape_header)

	_shape_group = ButtonGroup.new()
	_shape_container = HBoxContainer.new()
	_shape_container.add_theme_constant_override("separation", roundi(4.0 * s))
	_shape_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_shape_container.visible = not _manifest_mode
	var shape_icons: Array[String] = ["\u25cf", "\u2500", "\u25e5"] # Circle, Line, Cone
	for sidx in EffectData.SHAPE_LABELS.size():
		var sbtn := Button.new()
		sbtn.toggle_mode = true
		sbtn.text = "%s %s" % [shape_icons[sidx], EffectData.SHAPE_LABELS[sidx]]
		sbtn.button_group = _shape_group
		sbtn.focus_mode = Control.FOCUS_NONE
		sbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sbtn.custom_minimum_size = Vector2(0, roundi(24.0 * s))
		sbtn.add_theme_font_size_override("font_size", roundi(11.0 * s))
		if _ui_theme_mgr != null:
			_ui_theme_mgr.apply_button_style(sbtn, s)
		var shape_idx: int = sidx
		sbtn.pressed.connect(func() -> void: _on_shape_pressed(shape_idx))
		_shape_container.add_child(sbtn)
		_shape_buttons.append(sbtn)
	_shape_buttons[0].button_pressed = true
	_vbox.add_child(_shape_container)
	_refresh_shape_buttons()

	_vbox.add_child(HSeparator.new())

	# Palette selector row (only visible for palette-enabled legacy effects)
	_palette_header = Label.new()
	_palette_header.text = "PALETTE"
	_palette_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_palette_header.add_theme_font_size_override("font_size", roundi(9.0 * s))
	var _pal_tint: Color = _ui_theme_mgr.get_header_tint() if _ui_theme_mgr != null else Color(0.6, 0.6, 0.6)
	_palette_header.add_theme_color_override("font_color", _pal_tint)
	_palette_header.visible = not _manifest_mode
	_vbox.add_child(_palette_header)

	_palette_group = ButtonGroup.new()
	_palette_container = HBoxContainer.new()
	_palette_container.add_theme_constant_override("separation", roundi(2.0 * s))
	_palette_container.alignment = BoxContainer.ALIGNMENT_CENTER
	var palette_colors: Array[Color] = [
		Color(1.0, 0.5, 0.0), # Orange
		Color(0.9, 0.1, 0.1), # Red
		Color(0.2, 0.8, 0.1), # Green
		Color(0.2, 0.4, 1.0), # Blue
		Color(0.7, 0.15, 0.85), # Violet
		Color(1.0, 0.9, 0.0), # Yellow
		Color(0.08, 0.08, 0.09), # Black
	]
	for pidx in EffectData.PALETTE_LABELS.size():
		var pbtn := Button.new()
		pbtn.toggle_mode = true
		pbtn.text = " "
		pbtn.tooltip_text = EffectData.PALETTE_LABELS[pidx]
		pbtn.button_group = _palette_group
		pbtn.focus_mode = Control.FOCUS_NONE
		pbtn.custom_minimum_size = Vector2(roundi(28.0 * s), roundi(24.0 * s))
		pbtn.add_theme_font_size_override("font_size", roundi(10.0 * s))
		pbtn.set_meta(UIThemeManager.SKIP_AUTO_THEME, true)
		var p_normal := StyleBoxFlat.new()
		p_normal.bg_color = palette_colors[pidx]
		p_normal.corner_radius_top_left = 3
		p_normal.corner_radius_top_right = 3
		p_normal.corner_radius_bottom_left = 3
		p_normal.corner_radius_bottom_right = 3
		pbtn.add_theme_stylebox_override("normal", p_normal)
		var p_hover := StyleBoxFlat.new()
		p_hover.bg_color = palette_colors[pidx].lightened(0.2)
		p_hover.corner_radius_top_left = 3
		p_hover.corner_radius_top_right = 3
		p_hover.corner_radius_bottom_left = 3
		p_hover.corner_radius_bottom_right = 3
		pbtn.add_theme_stylebox_override("hover", p_hover)
		var p_pressed := StyleBoxFlat.new()
		p_pressed.bg_color = palette_colors[pidx].lightened(0.15)
		p_pressed.border_width_bottom = 3
		p_pressed.border_width_top = 3
		p_pressed.border_width_left = 3
		p_pressed.border_width_right = 3
		p_pressed.border_color = Color.WHITE
		p_pressed.corner_radius_top_left = 3
		p_pressed.corner_radius_top_right = 3
		p_pressed.corner_radius_bottom_left = 3
		p_pressed.corner_radius_bottom_right = 3
		pbtn.add_theme_stylebox_override("pressed", p_pressed)
		var pal_idx: int = pidx
		pbtn.pressed.connect(func() -> void: _on_palette_pressed(pal_idx))
		_palette_container.add_child(pbtn)
		_palette_buttons.append(pbtn)
	_palette_buttons[0].button_pressed = true
	_palette_container.visible = not _manifest_mode
	_vbox.add_child(_palette_container)
	_refresh_palette_visibility()

	_vbox.add_child(HSeparator.new())

	# Size section
	var size_header := Label.new()
	size_header.text = "SIZE"
	size_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size_header.add_theme_font_size_override("font_size", roundi(9.0 * s))
	var _sz_tint: Color = _ui_theme_mgr.get_header_tint() if _ui_theme_mgr != null else Color(0.6, 0.6, 0.6)
	size_header.add_theme_color_override("font_color", _sz_tint)
	_vbox.add_child(size_header)

	_size_slider = HSlider.new()
	_size_slider.min_value = 5.0
	_size_slider.max_value = 200.0
	_size_slider.step = 5.0
	_size_slider.value = _effect_size_ft
	_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_slider.custom_minimum_size = Vector2(0, roundi(20.0 * s))
	_size_slider.value_changed.connect(_on_size_changed)
	_vbox.add_child(_size_slider)

	_size_label = Label.new()
	_size_label.text = _format_size(_effect_size_ft)
	_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_size_label.add_theme_font_size_override("font_size", roundi(11.0 * s))
	_vbox.add_child(_size_label)

	_vbox.add_child(HSeparator.new())

	# Burst checkbox — hidden in manifest mode (scene effects use click-to-place)
	_burst_check = CheckBox.new()
	_burst_check.text = "Burst (hold to play)"
	_burst_check.add_theme_font_size_override("font_size", roundi(12.0 * s))
	_burst_check.toggled.connect(_on_burst_toggled)
	_burst_check.visible = not _manifest_mode
	_vbox.add_child(_burst_check)

	# Lock minimum width to the palette row (widest element) so toggling
	# palette visibility doesn't cause the panel to resize.
	if not _palette_buttons.is_empty():
		var pal_btn_w: int = roundi(28.0 * s)
		var pal_sep: int = roundi(2.0 * s)
		var margin_side: int = roundi(4.0 * s)
		custom_minimum_size.x = float(
			_palette_buttons.size() * pal_btn_w
			+ maxi(_palette_buttons.size() - 1, 0) * pal_sep
			+2 * margin_side) + 1.0


func _build_legacy_buttons(s: float) -> void:
	var icons: Array[String] = ["🔥", "🔥○", "🔥▬", "🔥│", "🔥↓", "⚡", "⚡⚡", "⚡●", "❄", "❄❄", "☁", "✦", "✧"]
	for idx in EffectData.EFFECT_LABELS.size():
		var btn := Button.new()
		btn.toggle_mode = true
		btn.text = "%s %s" % [icons[idx], EffectData.EFFECT_LABELS[idx]]
		btn.button_group = _type_group
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, roundi(26.0 * s))
		btn.add_theme_font_size_override("font_size", roundi(12.0 * s))
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if _ui_theme_mgr != null:
			_ui_theme_mgr.apply_button_style(btn, s)
		var type_idx: int = idx
		btn.pressed.connect(func() -> void: _on_type_pressed(type_idx))
		_vbox.add_child(btn)
		_type_buttons.append(btn)
	if not _type_buttons.is_empty():
		_type_buttons[0].button_pressed = true


func _build_manifest_buttons(s: float) -> void:
	## Group definitions by category and render a header + buttons for each group.
	var categories: Array[String] = []
	var by_category: Dictionary = {}
	for raw in _definitions:
		var def: EffectDefinition = raw as EffectDefinition
		if def == null:
			continue
		if not by_category.has(def.category):
			categories.append(def.category)
			by_category[def.category] = []
		(by_category[def.category] as Array).append(def)

	var first_btn: Button = null
	var first_def_id: String = ""
	var first_def_size: float = 100.0

	for cat in categories:
		# Category header
		var hdr := Label.new()
		hdr.text = cat.to_upper()
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		hdr.add_theme_font_size_override("font_size", roundi(9.0 * s))
		var hdr_tint: Color = _ui_theme_mgr.get_header_tint() if _ui_theme_mgr != null else Color(0.6, 0.6, 0.6)
		hdr.add_theme_color_override("font_color", hdr_tint)
		hdr.add_theme_constant_override("margin_top", roundi(4.0 * s))
		_vbox.add_child(hdr)

		for raw2 in (by_category[cat] as Array):
			var def: EffectDefinition = raw2 as EffectDefinition
			if def == null:
				continue
			var btn := Button.new()
			btn.toggle_mode = true
			var mode_tag: String = " ♾" if def.mode == EffectDefinition.Mode.PERSISTENT else " ▶"
			btn.text = "%s %s%s" % [def.icon, def.display_name, mode_tag]
			btn.tooltip_text = "%s\nSize: %.0f px default  |  %s" % [
				def.display_name,
				def.default_size,
				"Persistent" if def.mode == EffectDefinition.Mode.PERSISTENT else "One-shot"
			]
			btn.button_group = _type_group
			btn.focus_mode = Control.FOCUS_NONE
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.custom_minimum_size = Vector2(0, roundi(26.0 * s))
			btn.add_theme_font_size_override("font_size", roundi(12.0 * s))
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if _ui_theme_mgr != null:
				_ui_theme_mgr.apply_button_style(btn, s)
			var def_id: String = def.effect_id
			var def_size: float = def.default_size
			btn.pressed.connect(func() -> void: _on_manifest_btn_pressed(def_id, def_size))
			_vbox.add_child(btn)
			_type_buttons.append(btn)
			if first_btn == null:
				first_btn = btn
				first_def_id = def.effect_id
				first_def_size = def.default_size

	if first_btn != null:
		first_btn.button_pressed = true
		_selected_effect_definition_id = first_def_id
		var default_ft: float = first_def_size / maxf(_px_per_foot, 1.0)
		_effect_size_ft = clampf(default_ft, 5.0, 200.0)


func _on_type_pressed(idx: int) -> void:
	_selected_effect_type = idx
	_selected_effect_definition_id = ""
	_refresh_shape_buttons()
	_refresh_palette_visibility()
	effect_type_selected.emit(idx)


func _on_manifest_btn_pressed(effect_id: String, size_default_ft: float) -> void:
	_selected_effect_definition_id = effect_id
	_selected_effect_type = 0 ## Legacy type irrelevant in manifest mode
	## Update size slider to the effect's default size (converted from px to ft).
	var default_ft: float = size_default_ft / maxf(_px_per_foot, 1.0)
	set_effect_size(clampf(default_ft, 5.0, 200.0))
	effect_definition_id_selected.emit(effect_id)


func _on_shape_pressed(idx: int) -> void:
	_selected_shape = idx
	shape_changed.emit(idx)


func _on_size_changed(val: float) -> void:
	_effect_size_ft = val
	_size_label.text = _format_size(val)
	size_changed.emit(_get_size_px())


func _on_burst_toggled(enabled: bool) -> void:
	_burst_mode = enabled
	burst_mode_changed.emit(enabled)


func _on_palette_pressed(idx: int) -> void:
	_selected_palette = idx
	palette_changed.emit(idx)


func _format_size(size_ft: float) -> String:
	return "%d ft" % int(size_ft)


func _refresh_shape_buttons() -> void:
	## Show/hide shape buttons based on the available shapes for the current
	## effect type. If the currently selected shape is not available, auto-select
	## the first available one.
	if _manifest_mode or _shape_buttons.is_empty():
		return
	var available: Variant = EffectData.AVAILABLE_SHAPES.get(_selected_effect_type, null)
	if available == null:
		available = [EffectData.EffectShape.CIRCLE]
	var avail_arr: Array = available as Array
	var current_valid: bool = avail_arr.has(_selected_shape)
	for i in _shape_buttons.size():
		var btn: Button = _shape_buttons[i]
		btn.visible = avail_arr.has(i)
	if not current_valid and not avail_arr.is_empty():
		_selected_shape = int(avail_arr[0])
		_shape_buttons[_selected_shape].button_pressed = true
		shape_changed.emit(_selected_shape)


func _refresh_palette_visibility() -> void:
	if _manifest_mode:
		return ## Palette is hidden in manifest mode (scenes handle their own appearance)
	var show_palette: bool = EffectData.PALETTE_ENABLED.has(_selected_effect_type)
	if _palette_header != null:
		_palette_header.visible = show_palette
	if _palette_container != null:
		_palette_container.visible = show_palette


func set_px_per_foot(val: float) -> void:
	_px_per_foot = val


func get_selected_shape() -> int:
	return _selected_shape


func get_selected_effect_type() -> int:
	return _selected_effect_type


func is_burst_mode() -> bool:
	return _burst_mode


func get_effect_size() -> float:
	return _get_size_px()


func _get_size_px() -> float:
	if _px_per_foot > 0.0:
		return _effect_size_ft * _px_per_foot
	# Fallback: assume 1 px per foot when uncalibrated
	return _effect_size_ft


func get_selected_palette() -> int:
	return _selected_palette


func set_effect_size(val: float) -> void:
	## Accepts a value in feet.
	_effect_size_ft = val
	if _size_slider != null:
		_size_slider.value = val
	if _size_label != null:
		_size_label.text = _format_size(val)


# ---------------------------------------------------------------------------
# Phase 11: Manifest-driven palette
# ---------------------------------------------------------------------------

## Replace the effect type buttons with category-grouped manifest entries.
## Call after the manifest is loaded.  Passing an empty array resets to
## the legacy hard-coded list.
func setup_manifest(definitions: Array) -> void:
	_definitions = definitions
	_manifest_mode = not _definitions.is_empty()
	_selected_effect_definition_id = ""
	_rebuild()


func get_selected_effect_definition_id() -> String:
	return _selected_effect_definition_id


## Rebuild the full panel UI.  Called once at setup and again after
## setup_manifest() to switch between legacy and manifest layouts.
func _rebuild() -> void:
	if _vbox == null:
		return
	# Free all children immediately so _build() starts with a clean node.
	var old_children: Array[Node] = []
	old_children.assign(get_children())
	for child in old_children:
		child.free()
	_type_buttons.clear()
	_type_group = null
	_shape_buttons.clear()
	_shape_group = null
	_shape_container = null
	_palette_header = null
	_palette_container = null
	_palette_buttons.clear()
	_palette_group = null
	_burst_check = null
	_size_slider = null
	_size_label = null
	# _vbox and _undock_btn are also freed — recreate via _build()
	_vbox = null
	_undock_btn = null
	_title_label = null
	_build()
	# Re-wire the undock button — caller (DMWindow) must reconnect it.
	# We emit a signal so DMWindow knows to reconnect.
	# (No direct notification needed; DMWindow reconnects when it builds the panel.)
