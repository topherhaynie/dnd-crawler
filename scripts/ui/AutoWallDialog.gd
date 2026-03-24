extends ConfirmationDialog
class_name AutoWallDialog

## AutoWallDialog — DM dialog for configuring and previewing auto-detected
## wall polygons generated from the map image.

signal preview_requested(polygons: Array)
signal preview_cleared
signal walls_applied(polygons: Array, replace: bool)
signal eyedropper_requested

# ── Controls ─────────────────────────────────────────────────────────────────
var _mode_option: OptionButton = null
var _color_picker: ColorPickerButton = null
var _color_row: HBoxContainer = null
var _eyedropper_btn: Button = null
var _threshold_slider: HSlider = null
var _threshold_label: Label = null
var _detail_slider: HSlider = null
var _detail_label: Label = null
var _invert_check: CheckButton = null
var _replace_check: CheckButton = null
var _status_label: Label = null
var _preview_btn: Button = null

var _last_polygons: Array = []

func _init() -> void:
	title = "Auto-Detect Walls"
	min_size = Vector2i(360, 0)
	ok_button_text = "Apply"
	get_ok_button().disabled = true


func _ready() -> void:
	_build_ui()
	confirmed.connect(_on_apply)
	canceled.connect(_on_cancel)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)

	# ── Mode selector ────────────────────────────────────────────────────
	var mode_lbl := Label.new()
	mode_lbl.text = "Detection mode:"
	root.add_child(mode_lbl)

	_mode_option = OptionButton.new()
	_mode_option.add_item("Alpha (Transparent)", 0)
	_mode_option.add_item("Color (Solid Background)", 1)
	_mode_option.item_selected.connect(_on_mode_changed)
	root.add_child(_mode_option)

	# ── Color picker row (hidden by default) ─────────────────────────────
	_color_row = HBoxContainer.new()
	_color_row.add_theme_constant_override("separation", 8)
	_color_row.visible = false

	var color_lbl := Label.new()
	color_lbl.text = "Background color:"
	_color_row.add_child(color_lbl)

	_color_picker = ColorPickerButton.new()
	_color_picker.color = Color(0., 0.0, 0.0, 1.0)
	_color_picker.custom_minimum_size = Vector2(40, 28)
	_color_picker.edit_alpha = false
	_color_row.add_child(_color_picker)

	_eyedropper_btn = Button.new()
	_eyedropper_btn.text = "Sample from map"
	_eyedropper_btn.tooltip_text = "Click on the map to sample a background color"
	_eyedropper_btn.pressed.connect(_on_eyedropper_pressed)
	_color_row.add_child(_eyedropper_btn)

	root.add_child(_color_row)

	root.add_child(HSeparator.new())

	# ── Threshold slider ─────────────────────────────────────────────────
	var thresh_row := HBoxContainer.new()
	thresh_row.add_theme_constant_override("separation", 8)
	var thresh_lbl := Label.new()
	thresh_lbl.text = "Threshold:"
	thresh_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	thresh_row.add_child(thresh_lbl)

	_threshold_label = Label.new()
	_threshold_label.text = "0.50"
	_threshold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_threshold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thresh_row.add_child(_threshold_label)
	root.add_child(thresh_row)

	_threshold_slider = HSlider.new()
	_threshold_slider.min_value = 0.01
	_threshold_slider.max_value = 1.0
	_threshold_slider.step = 0.01
	_threshold_slider.value = 0.5
	_threshold_slider.custom_minimum_size = Vector2(200, 0)
	_threshold_slider.value_changed.connect(_on_threshold_changed)
	root.add_child(_threshold_slider)

	# ── Detail slider ────────────────────────────────────────────────────
	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 8)
	var detail_lbl := Label.new()
	detail_lbl.text = "Detail:"
	detail_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	detail_row.add_child(detail_lbl)

	_detail_label = Label.new()
	_detail_label.text = "85%"
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_detail_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_row.add_child(_detail_label)
	root.add_child(detail_row)

	_detail_slider = HSlider.new()
	_detail_slider.min_value = 0
	_detail_slider.max_value = 100
	_detail_slider.step = 1
	_detail_slider.value = 85
	_detail_slider.custom_minimum_size = Vector2(200, 0)
	_detail_slider.value_changed.connect(_on_detail_changed)
	root.add_child(_detail_slider)

	root.add_child(HSeparator.new())

	# ── Checkboxes ───────────────────────────────────────────────────────
	_invert_check = CheckButton.new()
	_invert_check.text = "Invert polygon (recommended)"
	_invert_check.tooltip_text = "Wrap contours with image corners so the filled polygon covers walls, not rooms.\nLeave checked for most maps."
	_invert_check.button_pressed = true
	root.add_child(_invert_check)

	_replace_check = CheckButton.new()
	_replace_check.text = "Replace all existing walls"
	_replace_check.tooltip_text = "Clear all current wall polygons before applying (unchecked = append)"
	_replace_check.button_pressed = false
	root.add_child(_replace_check)

	root.add_child(HSeparator.new())

	# ── Preview button + status ──────────────────────────────────────────
	_preview_btn = Button.new()
	_preview_btn.text = "Preview"
	_preview_btn.tooltip_text = "Run detection and show wall outlines on the map"
	_preview_btn.pressed.connect(_on_preview_pressed)
	root.add_child(_preview_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	add_child(root)

# ── Config builder ───────────────────────────────────────────────────────────

func get_trace_config() -> Dictionary:
	var detect_mode: int = _mode_option.get_item_id(_mode_option.selected)
	var detail_pct: float = _detail_slider.value
	# Map detail % to epsilon: 100% → 0.5 (near-raw), 0% → 20.0 (aggressive)
	var epsilon: float = lerpf(20.0, 0.5, detail_pct / 100.0)
	var config: Dictionary = {
		"mode": detect_mode,
		"threshold": _threshold_slider.value,
		"invert": _invert_check.button_pressed,
		"epsilon": epsilon,
		"trace_scale": 0.5,
		"min_points": 20,
	}
	if detect_mode == 1: # AutoWallTracer.DetectMode.COLOR
		config["sample_color"] = _color_picker.color
	return config


## Set the background color (e.g. from eyedropper sampling on the map).
func set_sampled_color(color: Color) -> void:
	if _color_picker != null:
		_color_picker.color = color
	# Switch to Color mode automatically
	if _mode_option != null:
		_mode_option.select(1)
		_on_mode_changed(1)

# ── Signal handlers ──────────────────────────────────────────────────────────

func _on_mode_changed(index: int) -> void:
	var id: int = _mode_option.get_item_id(index)
	_color_row.visible = (id == 1) # AutoWallTracer.DetectMode.COLOR


func _on_threshold_changed(value: float) -> void:
	_threshold_label.text = "%.2f" % value


func _on_detail_changed(value: float) -> void:
	_detail_label.text = "%d%%" % roundi(value)


func _on_eyedropper_pressed() -> void:
	eyedropper_requested.emit()


func _on_preview_pressed() -> void:
	_status_label.text = "Detecting..."
	# Defer to let label update render before blocking trace
	_run_trace.call_deferred()


func _run_trace() -> void:
	preview_requested.emit(get_trace_config())


func show_trace_result(polygons: Array) -> void:
	_last_polygons = polygons
	var total_points: int = 0
	for poly: Variant in polygons:
		var p: PackedVector2Array = poly as PackedVector2Array
		if p != null:
			total_points += p.size()
	_status_label.text = "Found %d wall segments (%d total points)" % [polygons.size(), total_points]
	get_ok_button().disabled = polygons.is_empty()


func _on_apply() -> void:
	if _last_polygons.is_empty():
		return
	walls_applied.emit(_last_polygons, _replace_check.button_pressed)
	preview_cleared.emit()


func _on_cancel() -> void:
	_last_polygons.clear()
	preview_cleared.emit()
