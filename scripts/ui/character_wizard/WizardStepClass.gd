extends VBoxContainer

# -----------------------------------------------------------------------------
# WizardStepClass — Step 1: Class, level, and optional multiclass selection.
# -----------------------------------------------------------------------------

var _wizard: CharacterWizard = null
var _class_option: OptionButton = null
var _level_spin: SpinBox = null
var _budget_label: Label = null
var _add_class_btn: Button = null
var _extra_rows_container: VBoxContainer = null
## Each entry: { "row": HBoxContainer, "option": OptionButton, "spin": SpinBox, "warn": Label }
var _extra_rows: Array = []


func _init(wizard: CharacterWizard) -> void:
	_wizard = wizard
	name = "StepClass"
	add_theme_constant_override("separation", 8)
	_build()


func _build() -> void:
	var class_lbl := Label.new()
	class_lbl.text = "Primary Class:"
	add_child(class_lbl)

	_class_option = OptionButton.new()
	_class_option.item_selected.connect(_on_class_selected)
	add_child(_class_option)

	var level_lbl := Label.new()
	level_lbl.text = "Total Character Level:"
	add_child(level_lbl)

	_level_spin = SpinBox.new()
	_level_spin.min_value = 1
	_level_spin.max_value = 20
	_level_spin.value = 1
	_level_spin.value_changed.connect(_on_level_changed)
	add_child(_level_spin)

	_budget_label = Label.new()
	_budget_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	add_child(_budget_label)

	var sep := HSeparator.new()
	add_child(sep)

	var mc_header := Label.new()
	mc_header.text = "Multiclass (optional):"
	add_child(mc_header)

	_extra_rows_container = VBoxContainer.new()
	_extra_rows_container.add_theme_constant_override("separation", 4)
	add_child(_extra_rows_container)

	_add_class_btn = Button.new()
	_add_class_btn.text = "+ Add Class"
	_add_class_btn.pressed.connect(_on_add_class)
	add_child(_add_class_btn)

	_update_budget_label()


func populate_class_option() -> void:
	if _class_option == null:
		return
	_class_option.clear()
	if _wizard.classes_raw.is_empty():
		_class_option.add_item("(SRD not loaded)")
		return
	for raw: Variant in _wizard.classes_raw:
		if raw is Dictionary:
			_class_option.add_item(str((raw as Dictionary).get("name", "?")))
	# Refresh existing extra rows' OptionButtons
	for entry: Variant in _extra_rows:
		if entry is Dictionary:
			var opt: OptionButton = (entry as Dictionary).get("option") as OptionButton
			if opt != null:
				var prev_idx: int = opt.selected
				opt.clear()
				for raw: Variant in _wizard.classes_raw:
					if raw is Dictionary:
						opt.add_item(str((raw as Dictionary).get("name", "?")))
				if prev_idx >= 0 and prev_idx < opt.item_count:
					opt.select(prev_idx)


func _on_class_selected(idx: int) -> void:
	_wizard.class_index = idx


func _on_level_changed(value: float) -> void:
	_wizard.level = int(value)
	_clamp_extra_levels()
	_update_budget_label()


func _on_add_class() -> void:
	var remaining: int = _get_remaining_levels()
	if remaining < 1:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for raw: Variant in _wizard.classes_raw:
		if raw is Dictionary:
			opt.add_item(str((raw as Dictionary).get("name", "?")))
	row.add_child(opt)

	var lbl := Label.new()
	lbl.text = "Lv:"
	row.add_child(lbl)

	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = remaining
	spin.value = 1
	row.add_child(spin)

	var warn := Label.new()
	warn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	warn.add_theme_font_size_override("font_size", 11)
	row.add_child(warn)

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.pressed.connect(_make_remove_callback(row))
	row.add_child(remove_btn)

	_extra_rows_container.add_child(row)
	var entry: Dictionary = {"row": row, "option": opt, "spin": spin, "warn": warn}
	_extra_rows.append(entry)

	opt.item_selected.connect(func(_idx: int) -> void: _sync_extra_classes())
	spin.value_changed.connect(func(_v: float) -> void:
		_clamp_extra_levels()
		_sync_extra_classes()
	)

	_sync_extra_classes()
	_update_budget_label()


func _make_remove_callback(row: HBoxContainer) -> Callable:
	return func() -> void: _remove_extra_row(row)


func _remove_extra_row(row: HBoxContainer) -> void:
	var idx: int = -1
	for i: int in range(_extra_rows.size()):
		var ev: Variant = _extra_rows[i]
		if ev is Dictionary and (ev as Dictionary).get("row") == row:
			idx = i
			break
	if idx >= 0:
		_extra_rows.remove_at(idx)
	row.queue_free()
	_sync_extra_classes()
	_update_budget_label()


func _get_extra_level_sum() -> int:
	var total: int = 0
	for entry: Variant in _extra_rows:
		if entry is Dictionary:
			var spin: SpinBox = (entry as Dictionary).get("spin") as SpinBox
			if spin != null:
				total += int(spin.value)
	return total


func _get_remaining_levels() -> int:
	return maxi(0, _wizard.level - 1 - _get_extra_level_sum())


func _clamp_extra_levels() -> void:
	# Ensure extra class levels don't exceed total level - 1 (primary must have >= 1)
	var budget: int = _wizard.level - 1
	var running: int = 0
	for entry: Variant in _extra_rows:
		if not (entry is Dictionary):
			continue
		var spin: SpinBox = (entry as Dictionary).get("spin") as SpinBox
		if spin == null:
			continue
		var allowed: int = maxi(1, budget - running)
		spin.max_value = allowed
		if int(spin.value) > allowed:
			spin.value = allowed
		running += int(spin.value)


func _sync_extra_classes() -> void:
	_wizard.extra_classes.clear()
	for entry: Variant in _extra_rows:
		if not (entry is Dictionary):
			continue
		var ed: Dictionary = entry as Dictionary
		var opt: OptionButton = ed.get("option") as OptionButton
		var spin: SpinBox = ed.get("spin") as SpinBox
		var warn: Label = ed.get("warn") as Label
		if opt == null or spin == null:
			continue
		var ci: int = opt.selected
		var lv: int = int(spin.value)
		# Check prerequisites
		var prereq_fail: String = _wizard.check_multiclass_prereq(ci)
		if warn != null:
			warn.text = prereq_fail
		_wizard.extra_classes.append({"class_index": ci, "level": lv})
	_update_budget_label()


func _update_budget_label() -> void:
	if _budget_label == null:
		return
	var extra_sum: int = _get_extra_level_sum()
	var primary_lv: int = maxi(1, _wizard.level - extra_sum)
	if extra_sum > 0:
		_budget_label.text = "Primary class level: %d  |  Multiclass levels: %d  |  Total: %d" % [
			primary_lv, extra_sum, _wizard.level]
	else:
		_budget_label.text = ""
	# Disable add button when no remaining budget
	if _add_class_btn != null:
		_add_class_btn.disabled = _get_remaining_levels() < 1
