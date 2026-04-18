extends Window
class_name ConditionDialog

## ConditionDialog — modal dialog for applying and removing conditions on a token.
##
## Opened by DMWindow when the DM right-clicks a token and selects "Conditions…".
## Shows currently-active conditions with remove buttons, plus a form to add new ones.
##
## Usage:
##   dialog.open_for_token(token_id, token_name, current_conditions)
##
## current_conditions: Array of condition name strings (from StatblockOverride.conditions)

signal condition_confirmed(token_id: String, condition_name: String,
	source: String, duration_rounds: int)
signal condition_removed_requested(token_id: String, condition_name: String)

var _token_id: String = ""

# UI nodes
var _scale: float = 1.0
var _root: VBoxContainer = null
var _active_vbox: VBoxContainer = null
var _active_section: VBoxContainer = null
var _condition_option: OptionButton = null
var _source_edit: LineEdit = null
var _duration_spin: SpinBox = null
var _apply_btn: Button = null


func _init() -> void:
	title = "Conditions"
	transient = true
	exclusive = true
	wrap_controls = true
	close_requested.connect(_on_close)


func _ready() -> void:
	_build_ui()


## Call after creation and on every ui-scale change.
func apply_scale(s: float) -> void:
	_scale = s
	if _root == null:
		return
	var si := func(base: float) -> int: return roundi(base * s)
	_root.offset_left = si.call(12.0)
	_root.offset_right = - si.call(12.0)
	_root.offset_top = si.call(12.0)
	_root.offset_bottom = - si.call(12.0)
	_root.add_theme_constant_override("separation", si.call(8.0))


## Open the dialog for a specific token.
## current_conditions: Array of condition name strings.
func open_for_token(token_id: String, token_name: String, current_conditions: Array) -> void:
	_token_id = token_id
	title = "Conditions — %s" % token_name
	_rebuild_active_conditions(current_conditions)
	if _condition_option != null:
		_condition_option.selected = 0
	if _source_edit != null:
		_source_edit.text = ""
	if _duration_spin != null:
		_duration_spin.value = -1.0
	reset_size()
	popup_centered(Vector2i(360, 280))


func _build_ui() -> void:
	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.offset_left = 12.0
	_root.offset_right = -12.0
	_root.offset_top = 12.0
	_root.offset_bottom = -12.0
	_root.add_theme_constant_override("separation", 8)
	add_child(_root)

	# ── Active conditions section ────────────────────────────────────────────
	_active_section = VBoxContainer.new()
	_active_section.add_theme_constant_override("separation", 4)
	_root.add_child(_active_section)

	var active_lbl := Label.new()
	active_lbl.text = "Active Conditions"
	active_lbl.add_theme_font_size_override("font_size", 12)
	_active_section.add_child(active_lbl)

	_active_vbox = VBoxContainer.new()
	_active_vbox.add_theme_constant_override("separation", 3)
	_active_section.add_child(_active_vbox)

	_root.add_child(HSeparator.new())

	# ── Add condition form ───────────────────────────────────────────────────
	var add_lbl := Label.new()
	add_lbl.text = "Add Condition"
	add_lbl.add_theme_font_size_override("font_size", 12)
	_root.add_child(add_lbl)

	# Condition picker.
	var cond_row := HBoxContainer.new()
	cond_row.add_theme_constant_override("separation", 6)
	_root.add_child(cond_row)

	var cond_lbl := Label.new()
	cond_lbl.text = "Condition:"
	cond_row.add_child(cond_lbl)

	_condition_option = OptionButton.new()
	_condition_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key: String in ConditionRules.get_all_keys():
		_condition_option.add_item(ConditionRules.get_label(key))
		_condition_option.set_item_metadata(
			_condition_option.item_count - 1, key)
	cond_row.add_child(_condition_option)

	# Source field.
	var src_row := HBoxContainer.new()
	src_row.add_theme_constant_override("separation", 6)
	_root.add_child(src_row)

	var src_lbl := Label.new()
	src_lbl.text = "Source:"
	src_row.add_child(src_lbl)

	_source_edit = LineEdit.new()
	_source_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_edit.placeholder_text = "optional (e.g. Stinking Cloud)"
	src_row.add_child(_source_edit)

	# Duration spinner.
	var dur_row := HBoxContainer.new()
	dur_row.add_theme_constant_override("separation", 6)
	_root.add_child(dur_row)

	var dur_lbl := Label.new()
	dur_lbl.text = "Duration:"
	dur_row.add_child(dur_lbl)

	_duration_spin = SpinBox.new()
	_duration_spin.min_value = -1.0
	_duration_spin.max_value = 100.0
	_duration_spin.step = 1.0
	_duration_spin.value = -1.0
	_duration_spin.suffix = "rounds  (-1 = indefinite)"
	_duration_spin.allow_lesser = false
	_duration_spin.allow_greater = false
	_duration_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dur_row.add_child(_duration_spin)

	# Buttons.
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Close"
	cancel_btn.pressed.connect(_on_close)
	btn_row.add_child(cancel_btn)

	_apply_btn = Button.new()
	_apply_btn.text = "Apply"
	_apply_btn.pressed.connect(_on_apply_pressed)
	btn_row.add_child(_apply_btn)


func _rebuild_active_conditions(conditions: Array) -> void:
	if _active_vbox == null:
		return
	for child: Node in _active_vbox.get_children():
		child.queue_free()

	if conditions.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "  (none)"
		none_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55, 1.0))
		none_lbl.add_theme_font_size_override("font_size", 11)
		_active_vbox.add_child(none_lbl)
		return

	for raw_entry: Variant in conditions:
		var cname: String = ""
		var csource: String = ""
		var crd: int = -1
		if raw_entry is String:
			cname = raw_entry as String
		elif raw_entry is Dictionary:
			var d: Dictionary = raw_entry as Dictionary
			cname = str(d.get("name", ""))
			csource = str(d.get("source", ""))
			crd = int(d.get("rounds_remaining", -1))
		if cname.is_empty():
			continue

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		_active_vbox.add_child(row)

		# Coloured abbreviation badge.
		var badge := PanelContainer.new()
		var badge_sb := StyleBoxFlat.new()
		badge_sb.bg_color = ConditionRules.get_color(cname)
		badge_sb.corner_radius_top_left = 3
		badge_sb.corner_radius_top_right = 3
		badge_sb.corner_radius_bottom_left = 3
		badge_sb.corner_radius_bottom_right = 3
		badge_sb.content_margin_left = 4.0
		badge_sb.content_margin_right = 4.0
		badge_sb.content_margin_top = 1.0
		badge_sb.content_margin_bottom = 1.0
		badge.add_theme_stylebox_override("panel", badge_sb)
		var badge_lbl := Label.new()
		badge_lbl.text = ConditionRules.get_abbrev(cname)
		badge_lbl.add_theme_font_size_override("font_size", 10)
		badge_lbl.add_theme_color_override("font_color", Color.WHITE)
		badge.add_child(badge_lbl)
		row.add_child(badge)

		# Condition label text.
		var name_lbl := Label.new()
		name_lbl.text = ConditionRules.get_label(cname)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.add_theme_font_size_override("font_size", 11)
		if not csource.is_empty():
			name_lbl.text += " (%s)" % csource
		if crd >= 0:
			name_lbl.text += " [%d rd]" % crd
		row.add_child(name_lbl)

		# Remove button.
		var rm_btn := Button.new()
		rm_btn.text = "✕"
		rm_btn.custom_minimum_size = Vector2(22.0, 22.0)
		rm_btn.tooltip_text = "Remove %s" % ConditionRules.get_label(cname)
		var captured_name: String = cname
		rm_btn.pressed.connect(func() -> void:
			condition_removed_requested.emit(_token_id, captured_name)
		)
		row.add_child(rm_btn)


func _on_apply_pressed() -> void:
	if _condition_option == null:
		return
	var idx: int = _condition_option.selected
	if idx < 0:
		return
	var cname: String = str(_condition_option.get_item_metadata(idx))
	var source: String = _source_edit.text.strip_edges() if _source_edit != null else ""
	var duration: int = int(_duration_spin.value) if _duration_spin != null else -1
	condition_confirmed.emit(_token_id, cname, source, duration)
	# Clear form for next entry.
	if _source_edit != null:
		_source_edit.text = ""
	if _duration_spin != null:
		_duration_spin.value = -1.0


func _on_close() -> void:
	hide()
