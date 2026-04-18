extends VBoxContainer

# -----------------------------------------------------------------------------
# WizardStepAbilities — Step 3: Ability score entry (manual / standard / point buy).
# -----------------------------------------------------------------------------

var _wizard: CharacterWizard = null

var _mode_group: ButtonGroup = null
var _pb_budget_label: Label = null
var _score_spins: Array = []


func _init(wizard: CharacterWizard) -> void:
	_wizard = wizard
	name = "StepAbilities"
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	add_child(mode_row)

	_mode_group = ButtonGroup.new()

	var btn_manual := Button.new()
	btn_manual.text = "Manual"
	btn_manual.toggle_mode = true
	btn_manual.button_pressed = true
	btn_manual.button_group = _mode_group
	btn_manual.pressed.connect(func() -> void: _set_ability_mode(0))
	mode_row.add_child(btn_manual)

	var btn_std := Button.new()
	btn_std.text = "Standard Array"
	btn_std.toggle_mode = true
	btn_std.button_group = _mode_group
	btn_std.pressed.connect(func() -> void: _set_ability_mode(1))
	mode_row.add_child(btn_std)

	var btn_pb := Button.new()
	btn_pb.text = "Point Buy"
	btn_pb.toggle_mode = true
	btn_pb.button_group = _mode_group
	btn_pb.pressed.connect(func() -> void: _set_ability_mode(2))
	mode_row.add_child(btn_pb)

	_pb_budget_label = Label.new()
	_pb_budget_label.text = "Points remaining: %d" % WizardConstants.POINT_BUY_BUDGET
	_pb_budget_label.visible = false
	add_child(_pb_budget_label)

	var grid := GridContainer.new()
	grid.name = "AbilityGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	add_child(grid)

	_score_spins.clear()
	for i: int in 6:
		var lbl := Label.new()
		lbl.text = WizardConstants.ABILITY_NAMES[i]
		grid.add_child(lbl)

		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = 30
		sp.value = _wizard.scores[i]
		sp.value_changed.connect(_on_score_changed.bind(i))
		_score_spins.append(sp)
		grid.add_child(sp)

		var bonus_lbl := Label.new()
		bonus_lbl.name = "RacialBonus%d" % i
		bonus_lbl.text = ""
		bonus_lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
		bonus_lbl.modulate = Color(0.4, 0.9, 0.4)
		grid.add_child(bonus_lbl)

		var total_lbl := Label.new()
		total_lbl.name = "RacialTotal%d" % i
		total_lbl.text = "= 10"
		total_lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
		grid.add_child(total_lbl)

	var asi_note_lbl := Label.new()
	asi_note_lbl.name = "ASINote"
	asi_note_lbl.text = ""
	asi_note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	asi_note_lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
	asi_note_lbl.modulate = Color(0.9, 0.8, 0.4)
	add_child(asi_note_lbl)


func refresh_display() -> void:
	_refresh_racial_display()


func validate() -> bool:
	if _wizard.ability_mode == 2 and _point_buy_remaining() < 0:
		_wizard.show_error("You have spent more points than the %d-point budget allows." % WizardConstants.POINT_BUY_BUDGET)
		return false
	return true


# ── Ability mode handlers ─────────────────────────────────────────────
func _set_ability_mode(score_mode: int) -> void:
	_wizard.ability_mode = score_mode
	_pb_budget_label.visible = (score_mode == 2)
	match score_mode:
		1:
			for i: int in 6:
				_wizard.scores[i] = WizardConstants.STANDARD_ARRAY[i]
				(_score_spins[i] as SpinBox).min_value = 1
				(_score_spins[i] as SpinBox).max_value = 30
				(_score_spins[i] as SpinBox).value = _wizard.scores[i]
				(_score_spins[i] as SpinBox).editable = true
		2:
			for i: int in 6:
				_wizard.scores[i] = 8
				(_score_spins[i] as SpinBox).min_value = 8
				(_score_spins[i] as SpinBox).max_value = 15
				(_score_spins[i] as SpinBox).value = 8
				(_score_spins[i] as SpinBox).editable = true
			_update_pb_label()
		_:
			for i: int in 6:
				(_score_spins[i] as SpinBox).min_value = 1
				(_score_spins[i] as SpinBox).max_value = 30
				(_score_spins[i] as SpinBox).editable = true


func _on_score_changed(value: float, idx: int) -> void:
	_wizard.scores[idx] = int(value)
	if _wizard.ability_mode == 2:
		_update_pb_label()
	_refresh_racial_display()


func _update_pb_label() -> void:
	if _pb_budget_label == null:
		return
	_pb_budget_label.text = "Points remaining: %d" % _point_buy_remaining()


func _point_buy_remaining() -> int:
	var spent: int = 0
	for score: int in _wizard.scores:
		var clamped: int = clampi(score, 8, 15)
		var cost_val: Variant = WizardConstants.POINT_BUY_TABLE.get(clamped, 0)
		spent += int(cost_val)
	return WizardConstants.POINT_BUY_BUDGET - spent


func _refresh_racial_display() -> void:
	var grid: Node = get_node_or_null("AbilityGrid")
	if grid == null:
		return
	var asi: Dictionary = _wizard.get_total_race_asi()
	var class_asi: Dictionary = _wizard.get_asi_choice_bonuses()
	for i: int in 6:
		var key: String = WizardConstants.ABILITY_KEYS[i]
		var racial_bonus: int = int(asi.get(key, 0))
		var cls_bonus: int = int(class_asi.get(key, 0))
		var bonus: int = racial_bonus + cls_bonus
		var base: int = _wizard.scores[i]
		var total: int = base + bonus
		var mod: int = int(floor((float(total) - 10.0) / 2.0))
		var mod_str: String = "+%d" % mod if mod >= 0 else str(mod)
		var bonus_node: Node = grid.get_node_or_null("RacialBonus%d" % i)
		if bonus_node != null:
			var bonus_lbl := bonus_node as Label
			if bonus_lbl != null:
				if bonus > 0:
					bonus_lbl.text = "+%d" % bonus
				elif bonus < 0:
					bonus_lbl.text = str(bonus)
				else:
					bonus_lbl.text = ""
		var total_node: Node = grid.get_node_or_null("RacialTotal%d" % i)
		if total_node != null:
			var total_lbl := total_node as Label
			if total_lbl != null:
				if bonus != 0:
					total_lbl.text = "= %d (%s)" % [total, mod_str]
					total_lbl.modulate = Color(1.0, 1.0, 0.6)
				else:
					total_lbl.text = "(%s)" % mod_str
					total_lbl.modulate = Color(0.7, 0.7, 0.7)
	var asi_note_node: Node = get_node_or_null("ASINote")
	if asi_note_node != null:
		var class_key_note: String = _wizard.get_selected_class_name().to_lower()
		var asi_cnt: int = WizardConstants.asi_count_for(class_key_note, _wizard.level)
		var note_lbl := asi_note_node as Label
		if note_lbl != null:
			if asi_cnt > 0:
				note_lbl.text = "Your class has earned %d ASI(s) at level %d. Configure them in the Class Features step — bonuses from ASI and feat choices are shown above." % [asi_cnt, _wizard.level]
			else:
				note_lbl.text = ""
