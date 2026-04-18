extends Window
class_name StatblockOverrideEditor

# ---------------------------------------------------------------------------
# StatblockOverrideEditor — modal editor for per-token statblock overrides.
#
# Shows base statblock fields with inline editing. Changed fields are
# highlighted and stored in a StatblockOverride. Supports "Reset to Base"
# per-field and "Reset All".
# ---------------------------------------------------------------------------

signal overrides_confirmed(override_dict: Dictionary)

var _base: StatblockData = null
var _override: StatblockOverride = null

# Field editors: key → {spin: SpinBox, reset_btn: Button, base_val: Variant}
var _field_editors: Dictionary = {}
var _hp_spin: SpinBox = null
var _max_hp_spin: SpinBox = null
var _temp_hp_spin: SpinBox = null
var _conditions_edit: LineEdit = null
var _notes_edit: TextEdit = null
var _confirm_btn: Button = null
var _reset_all_btn: Button = null
var _content_root: MarginContainer = null

const ABILITY_FIELDS: Array = ["strength", "dexterity", "constitution", "intelligence", "wisdom", "charisma"]
const COMBAT_FIELDS: Array = ["hit_points", "armor_class_value", "proficiency_bonus"]


func setup(base: StatblockData, override_data: StatblockOverride) -> void:
	_base = base
	_override = override_data if override_data != null else StatblockOverride.new()
	if _override.base_statblock_id.is_empty() and base != null:
		_override.base_statblock_id = base.id


func _ready() -> void:
	title = "Override Editor"
	if _base != null:
		title = "Override — %s" % _base.name
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base: float) -> int:
		return mgr.scaled(base) if mgr != null else roundi(base)
	size = Vector2i(s.call(480.0), s.call(580.0))
	min_size = Vector2i(s.call(400.0), s.call(400.0))
	wrap_controls = false
	exclusive = false
	close_requested.connect(func() -> void: hide())

	_build_ui()


func _build_ui() -> void:
	if _base == null:
		return

	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base_val: float) -> int:
		return mgr.scaled(base_val) if mgr != null else roundi(base_val)

	var margin := MarginContainer.new()
	_content_root = margin
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", s.call(8.0))
	margin.add_theme_constant_override("margin_right", s.call(8.0))
	margin.add_theme_constant_override("margin_top", s.call(8.0))
	margin.add_theme_constant_override("margin_bottom", s.call(8.0))
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", s.call(4.0))
	scroll.add_child(vbox)

	# --- Runtime state section ---
	var runtime_lbl := Label.new()
	runtime_lbl.text = "Runtime State"
	runtime_lbl.add_theme_font_size_override("font_size", s.call(16.0))
	vbox.add_child(runtime_lbl)

	var base_hp: int = _base.hit_points
	_hp_spin = _add_int_row(vbox, "Current HP", _override.current_hp, 0, 9999, s)
	_max_hp_spin = _add_int_row(vbox, "Max HP", _override.max_hp if _override.max_hp > 0 else base_hp, 1, 9999, s)
	# Show base HP for reference
	var hp_hint := Label.new()
	hp_hint.text = "(base HP: %d, dice: %s)" % [base_hp, _base.hit_points_roll if not _base.hit_points_roll.is_empty() else "—"]
	hp_hint.add_theme_font_size_override("font_size", s.call(13.0))
	hp_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
	vbox.add_child(hp_hint)
	_temp_hp_spin = _add_int_row(vbox, "Temp HP", _override.temp_hp, 0, 9999, s)

	var cond_row := HBoxContainer.new()
	var cond_lbl := Label.new()
	cond_lbl.text = "Conditions:"
	cond_lbl.add_theme_font_size_override("font_size", s.call(14.0))
	cond_lbl.custom_minimum_size = Vector2(s.call(120.0), 0)
	cond_row.add_child(cond_lbl)
	_conditions_edit = LineEdit.new()
	_conditions_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_conditions_edit.placeholder_text = "e.g. poisoned, prone"
	_conditions_edit.add_theme_font_size_override("font_size", s.call(14.0))
	var cond_str: String = ""
	for c: Variant in _override.conditions:
		if not cond_str.is_empty():
			cond_str += ", "
		cond_str += str(c)
	_conditions_edit.text = cond_str
	cond_row.add_child(_conditions_edit)
	vbox.add_child(cond_row)

	vbox.add_child(HSeparator.new())

	# --- Ability Scores ---
	var abilities_lbl := Label.new()
	abilities_lbl.text = "Ability Scores"
	abilities_lbl.add_theme_font_size_override("font_size", s.call(16.0))
	vbox.add_child(abilities_lbl)

	for field: String in ABILITY_FIELDS:
		var base_val: int = _base.get(field) as int
		var effective: int = int(_override.get_effective(field, base_val))
		var spin: SpinBox = _add_override_row(vbox, field.capitalize(), field, base_val, effective, 1, 30, s)
		_field_editors[field] = spin
		# Show ability modifier that updates live
		var mod_lbl := Label.new()
		mod_lbl.add_theme_font_size_override("font_size", s.call(13.0))
		mod_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0, 0.9))
		var _update_mod := func() -> void:
			var score: int = int(spin.value)
			var mod: int = int(floor((float(score) - 10.0) / 2.0))
			var sign_str: String = "+" if mod >= 0 else ""
			mod_lbl.text = "(%s%d mod)" % [sign_str, mod]
		_update_mod.call()
		spin.value_changed.connect(func(_v: float) -> void: _update_mod.call())
		# Insert mod_lbl into the spin's parent row (the last HBoxContainer added)
		spin.get_parent().add_child(mod_lbl)

	vbox.add_child(HSeparator.new())

	# --- Combat ---
	var combat_lbl := Label.new()
	combat_lbl.text = "Combat"
	combat_lbl.add_theme_font_size_override("font_size", s.call(16.0))
	vbox.add_child(combat_lbl)

	# Show AC (read-only, from base statblock)
	var ac_str: String = ""
	for ac_entry: Variant in _base.armor_class:
		if ac_entry is Dictionary:
			var acd := ac_entry as Dictionary
			var ac_val: int = int(acd.get("value", 0))
			var ac_type: String = str(acd.get("type", ""))
			ac_str = "AC %d" % ac_val
			if not ac_type.is_empty():
				ac_str += " (%s)" % ac_type
	if not ac_str.is_empty():
		var ac_row := HBoxContainer.new()
		var ac_lbl := Label.new()
		ac_lbl.text = "Armor Class:"
		ac_lbl.add_theme_font_size_override("font_size", s.call(14.0))
		ac_lbl.custom_minimum_size = Vector2(s.call(120.0), 0)
		ac_row.add_child(ac_lbl)
		var ac_val_lbl := Label.new()
		ac_val_lbl.text = ac_str
		ac_val_lbl.add_theme_font_size_override("font_size", s.call(14.0))
		ac_row.add_child(ac_val_lbl)
		vbox.add_child(ac_row)

	var hp_base: int = _base.hit_points
	var hp_eff: int = int(_override.get_effective("hit_points", hp_base))
	_field_editors["hit_points"] = _add_override_row(vbox, "Max HP", "hit_points", hp_base, hp_eff, 1, 9999, s)

	var prof_base: int = _base.proficiency_bonus
	var prof_eff: int = int(_override.get_effective("proficiency_bonus", prof_base))
	_field_editors["proficiency_bonus"] = _add_override_row(vbox, "Prof. Bonus", "proficiency_bonus", prof_base, prof_eff, 0, 20, s)

	vbox.add_child(HSeparator.new())

	# --- Notes ---
	var notes_lbl := Label.new()
	notes_lbl.text = "Notes:"
	notes_lbl.add_theme_font_size_override("font_size", s.call(14.0))
	vbox.add_child(notes_lbl)
	_notes_edit = TextEdit.new()
	_notes_edit.custom_minimum_size = Vector2(0, s.call(60.0))
	_notes_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_edit.add_theme_font_size_override("font_size", s.call(14.0))
	_notes_edit.text = _override.notes
	vbox.add_child(_notes_edit)

	vbox.add_child(HSeparator.new())

	# --- Buttons ---
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", s.call(8.0))
	_reset_all_btn = Button.new()
	_reset_all_btn.text = "Reset All to Base"
	_reset_all_btn.add_theme_font_size_override("font_size", s.call(14.0))
	_reset_all_btn.pressed.connect(_on_reset_all)
	btn_row.add_child(_reset_all_btn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", s.call(14.0))
	cancel_btn.pressed.connect(func() -> void: hide())
	btn_row.add_child(cancel_btn)
	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm"
	_confirm_btn.add_theme_font_size_override("font_size", s.call(14.0))
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)
	vbox.add_child(btn_row)


func _add_int_row(parent: Control, label_text: String, initial: int, min_val: int, max_val: int, s: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(s.call(120.0), 0)
	lbl.add_theme_font_size_override("font_size", s.call(14.0))
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = 1
	spin.value = initial
	spin.custom_minimum_size = Vector2(s.call(120.0), 0)
	spin.get_line_edit().add_theme_font_size_override("font_size", s.call(14.0))
	row.add_child(spin)
	parent.add_child(row)
	return spin


func _add_override_row(parent: Control, label_text: String, _field: String,
		base_val: int, effective_val: int, min_val: int, max_val: int, s: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", s.call(4.0))
	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size = Vector2(s.call(120.0), 0)
	lbl.add_theme_font_size_override("font_size", s.call(14.0))
	row.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = 1
	spin.value = effective_val
	spin.custom_minimum_size = Vector2(s.call(100.0), 0)
	spin.get_line_edit().add_theme_font_size_override("font_size", s.call(14.0))
	row.add_child(spin)
	var base_lbl := Label.new()
	base_lbl.text = "(base: %d)" % base_val
	base_lbl.add_theme_font_size_override("font_size", s.call(13.0))
	base_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))
	row.add_child(base_lbl)
	var reset_btn := Button.new()
	reset_btn.text = "⟲"
	reset_btn.tooltip_text = "Reset to base value"
	reset_btn.add_theme_font_size_override("font_size", s.call(16.0))
	reset_btn.custom_minimum_size = Vector2(s.call(28.0), s.call(28.0))
	reset_btn.pressed.connect(func() -> void:
		spin.value = base_val
	)
	row.add_child(reset_btn)
	# Highlight if different from base
	if effective_val != base_val:
		lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2, 1.0))
	spin.value_changed.connect(func(new_val: float) -> void:
		if int(new_val) != base_val:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2, 1.0))
		else:
			lbl.remove_theme_color_override("font_color")
	)
	parent.add_child(row)
	return spin


func _on_reset_all() -> void:
	for field: String in _field_editors:
		var base_val: int = 0
		if _base != null:
			var raw: Variant = _base.get(field)
			base_val = int(raw) if raw != null else 0
		var spin: SpinBox = _field_editors[field] as SpinBox
		if spin != null:
			spin.value = base_val
	if _hp_spin != null and _base != null:
		_hp_spin.value = _base.hit_points
	if _max_hp_spin != null and _base != null:
		_max_hp_spin.value = _base.hit_points
	if _temp_hp_spin != null:
		_temp_hp_spin.value = 0
	if _conditions_edit != null:
		_conditions_edit.text = ""
	if _notes_edit != null:
		_notes_edit.text = ""


func _on_confirm() -> void:
	if _override == null:
		_override = StatblockOverride.new()
	# Runtime state
	_override.current_hp = int(_hp_spin.value) if _hp_spin != null else 0
	_override.max_hp = int(_max_hp_spin.value) if _max_hp_spin != null else 0
	_override.temp_hp = int(_temp_hp_spin.value) if _temp_hp_spin != null else 0
	# Parse conditions
	_override.conditions.clear()
	if _conditions_edit != null and not _conditions_edit.text.strip_edges().is_empty():
		for c: String in _conditions_edit.text.split(","):
			var trimmed: String = c.strip_edges()
			if not trimmed.is_empty():
				_override.conditions.append(trimmed)
	_override.notes = _notes_edit.text if _notes_edit != null else ""
	# Collect overrides (only changed fields)
	_override.overrides.clear()
	for field: String in _field_editors:
		var spin: SpinBox = _field_editors[field] as SpinBox
		if spin == null:
			continue
		var base_val: int = 0
		if _base != null:
			var raw: Variant = _base.get(field)
			base_val = int(raw) if raw != null else 0
		if int(spin.value) != base_val:
			_override.overrides[field] = int(spin.value)

	overrides_confirmed.emit(_override.to_dict())
	hide()


func _get_ui_scale_mgr() -> UIScaleManager:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.ui_scale != null:
		return reg.ui_scale
	return null
