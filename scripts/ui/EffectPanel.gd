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
signal burst_mode_changed(enabled: bool)
signal size_changed(size_px: float)

var _selected_effect_type: int = 0
var _selected_shape: int = EffectData.EffectShape.CIRCLE
var _burst_mode: bool = false
var _effect_size: float = 128.0
var _px_per_foot: float = 0.0 ## 0 = uncalibrated, display in px

var _vbox: VBoxContainer = null
var _type_buttons: Array[Button] = []
var _type_group: ButtonGroup = null
var _shape_buttons: Array[Button] = []
var _shape_group: ButtonGroup = null
var _shape_container: HBoxContainer = null
var _burst_check: CheckBox = null
var _size_slider: HSlider = null
var _size_label: Label = null
var _undock_btn: Button = null
var _title_label: Label = null
var _ui_scale_mgr: UIScaleManager = null


func setup(mgr: UIScaleManager) -> void:
	_ui_scale_mgr = mgr
	_build()


func _s() -> float:
	if _ui_scale_mgr != null:
		return _ui_scale_mgr.get_scale()
	return 1.0


func _build() -> void:
	var s: float = _s()
	name = "EffectPanel"

	# Dark background
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.15, 0.15, 0.15, 0.95)
	bg.border_width_left = 1
	bg.border_color = Color(0.3, 0.3, 0.3)
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
	_vbox.add_child(_undock_btn)

	_vbox.add_child(HSeparator.new())

	# Title
	_title_label = Label.new()
	_title_label.text = "Effects"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", roundi(15.0 * s))
	_vbox.add_child(_title_label)

	_vbox.add_child(HSeparator.new())

	# Effect type buttons
	_type_group = ButtonGroup.new()
	var icons: Array[String] = ["🔥", "⚡", "⚡⚡", "⚡●", "❄", "❄❄", "☁", "✦", "✧"]
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
		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.3, 0.5, 0.8, 0.6)
		btn.add_theme_stylebox_override("pressed", pressed_style)
		var type_idx: int = idx
		btn.pressed.connect(func() -> void: _on_type_pressed(type_idx))
		_vbox.add_child(btn)
		_type_buttons.append(btn)
	_type_buttons[0].button_pressed = true

	_vbox.add_child(HSeparator.new())

	# Shape selector row
	var shape_header := Label.new()
	shape_header.text = "SHAPE"
	shape_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shape_header.add_theme_font_size_override("font_size", roundi(9.0 * s))
	shape_header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_vbox.add_child(shape_header)

	_shape_group = ButtonGroup.new()
	_shape_container = HBoxContainer.new()
	_shape_container.add_theme_constant_override("separation", roundi(4.0 * s))
	_shape_container.alignment = BoxContainer.ALIGNMENT_CENTER
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
		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.3, 0.5, 0.8, 0.6)
		sbtn.add_theme_stylebox_override("pressed", pressed_style)
		var shape_idx: int = sidx
		sbtn.pressed.connect(func() -> void: _on_shape_pressed(shape_idx))
		_shape_container.add_child(sbtn)
		_shape_buttons.append(sbtn)
	_shape_buttons[0].button_pressed = true
	_vbox.add_child(_shape_container)
	_refresh_shape_buttons()

	_vbox.add_child(HSeparator.new())

	# Size section
	var size_header := Label.new()
	size_header.text = "SIZE"
	size_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	size_header.add_theme_font_size_override("font_size", roundi(9.0 * s))
	size_header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_vbox.add_child(size_header)

	_size_slider = HSlider.new()
	_size_slider.min_value = 32.0
	_size_slider.max_value = 512.0
	_size_slider.step = 8.0
	_size_slider.value = _effect_size
	_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_size_slider.custom_minimum_size = Vector2(0, roundi(20.0 * s))
	_size_slider.value_changed.connect(_on_size_changed)
	_vbox.add_child(_size_slider)

	_size_label = Label.new()
	_size_label.text = _format_size(_effect_size)
	_size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_size_label.add_theme_font_size_override("font_size", roundi(11.0 * s))
	_vbox.add_child(_size_label)

	_vbox.add_child(HSeparator.new())

	# Burst checkbox
	_burst_check = CheckBox.new()
	_burst_check.text = "Burst (hold to play)"
	_burst_check.add_theme_font_size_override("font_size", roundi(12.0 * s))
	_burst_check.toggled.connect(_on_burst_toggled)
	_vbox.add_child(_burst_check)


func _on_type_pressed(idx: int) -> void:
	_selected_effect_type = idx
	_refresh_shape_buttons()
	effect_type_selected.emit(idx)


func _on_shape_pressed(idx: int) -> void:
	_selected_shape = idx
	shape_changed.emit(idx)


func _on_size_changed(val: float) -> void:
	_effect_size = val
	_size_label.text = _format_size(val)
	size_changed.emit(val)


func _on_burst_toggled(enabled: bool) -> void:
	_burst_mode = enabled
	burst_mode_changed.emit(enabled)


func _format_size(size_px: float) -> String:
	if _px_per_foot > 0.0:
		return "%d ft" % int(size_px / _px_per_foot)
	return "%d px" % int(size_px)


func _refresh_shape_buttons() -> void:
	## Show/hide shape buttons based on the available shapes for the current
	## effect type. If the currently selected shape is not available, auto-select
	## the first available one.
	if _shape_buttons.is_empty():
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


func set_px_per_foot(val: float) -> void:
	_px_per_foot = val
	if _size_label != null:
		_size_label.text = _format_size(_effect_size)


func get_selected_shape() -> int:
	return _selected_shape


func get_selected_effect_type() -> int:
	return _selected_effect_type


func is_burst_mode() -> bool:
	return _burst_mode


func get_effect_size() -> float:
	return _effect_size


func set_effect_size(val: float) -> void:
	_effect_size = val
	if _size_slider != null:
		_size_slider.value = val
	if _size_label != null:
		_size_label.text = _format_size(val)
