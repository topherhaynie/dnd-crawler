extends VBoxContainer

# -----------------------------------------------------------------------------
# WizardStepProficiencies — Step 5: Skill proficiency choices.
# -----------------------------------------------------------------------------

var _wizard: CharacterWizard = null

var _prof_auto_label: RichTextLabel = null
var _prof_class_scroll: ScrollContainer = null
var _prof_class_vbox: VBoxContainer = null
var _prof_racial_vbox: VBoxContainer = null


func _init(wizard: CharacterWizard) -> void:
	_wizard = wizard
	name = "StepProficiencies"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build()


func _build() -> void:
	var intro := Label.new()
	intro.text = "Choose your skill proficiencies.  Automatic proficiencies from your background and race are shown below."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	add_child(intro)

	var auto_hdr := Label.new()
	auto_hdr.text = "Automatic Proficiencies:"
	auto_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(13.0))
	add_child(auto_hdr)

	_prof_auto_label = RichTextLabel.new()
	_prof_auto_label.bbcode_enabled = true
	_prof_auto_label.fit_content = true
	_prof_auto_label.scroll_active = false
	_prof_auto_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prof_auto_label.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	add_child(_prof_auto_label)

	add_child(HSeparator.new())

	var class_hdr := Label.new()
	class_hdr.text = "Class Skill Choices:"
	class_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(13.0))
	add_child(class_hdr)

	_prof_class_scroll = ScrollContainer.new()
	_prof_class_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prof_class_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_prof_class_scroll)

	_prof_class_vbox = VBoxContainer.new()
	_prof_class_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prof_class_vbox.add_theme_constant_override("separation", 4)
	_prof_class_scroll.add_child(_prof_class_vbox)

	_prof_racial_vbox = VBoxContainer.new()
	_prof_racial_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prof_racial_vbox.add_theme_constant_override("separation", 4)
	add_child(_prof_racial_vbox)


func refresh_ui() -> void:
	# ── Automatic proficiencies ───────────────────────────────────────
	var auto_skills: Array = []
	var bg_name: String = WizardConstants.BACKGROUNDS[_wizard.background] if _wizard.ruleset == "2014" else ""
	if not bg_name.is_empty():
		var bg_profs_var: Variant = WizardConstants.BACKGROUND_PROFS.get(bg_name, [])
		if bg_profs_var is Array:
			for sk: Variant in bg_profs_var as Array:
				var sk_str := str(sk)
				if not auto_skills.has(sk_str):
					auto_skills.append(sk_str)

	var race_profs_var: Variant = _wizard.get_race_dict().get("prof_skills", [])
	if race_profs_var is Array:
		for sk: Variant in race_profs_var as Array:
			var sk_str := str(sk)
			if not auto_skills.has(sk_str):
				auto_skills.append(sk_str)

	if _prof_auto_label != null:
		if auto_skills.is_empty():
			_prof_auto_label.text = "[color=gray](none)[/color]"
		else:
			_prof_auto_label.text = "\n".join(auto_skills.map(func(s: String) -> String: return "• " + s))

	# ── Class skill choices ───────────────────────────────────────────
	if _prof_class_vbox == null:
		return
	for ch: Node in _prof_class_vbox.get_children():
		ch.queue_free()

	var class_key: String = _wizard.get_selected_class_name().to_lower()
	var skill_data_var: Variant = WizardConstants.CLASS_SKILL_PROFS.get(class_key, {})
	var skill_data: Dictionary = skill_data_var as Dictionary if skill_data_var is Dictionary else {}
	var num_choices: int = int(skill_data.get("count", 0))
	var from_var: Variant = skill_data.get("from", [])
	var from_list: Array = from_var as Array if from_var is Array else []
	if from_list.is_empty():
		from_list = WizardConstants.ALL_SKILLS.duplicate()

	var available: Array = from_list.filter(func(s: Variant) -> bool: return not auto_skills.has(str(s)))

	var hint_lbl := Label.new()
	hint_lbl.text = "Choose %d skill%s from:" % [num_choices, "s" if num_choices != 1 else ""]
	hint_lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	_prof_class_vbox.add_child(hint_lbl)

	_wizard.chosen_skills = _wizard.chosen_skills.filter(func(s: Variant) -> bool: return available.has(str(s)))

	for skill_var: Variant in available:
		var skill: String = str(skill_var)
		var chk := CheckBox.new()
		chk.text = skill
		chk.button_pressed = _wizard.chosen_skills.has(skill)
		chk.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
		chk.toggled.connect(func(on: bool) -> void:
			if on:
				if _wizard.chosen_skills.size() < num_choices:
					_wizard.chosen_skills.append(skill)
				else:
					chk.set_pressed_no_signal(false)
			else:
				_wizard.chosen_skills.erase(skill)
		)
		_prof_class_vbox.add_child(chk)

	# ── Racial free skill choices ─────────────────────────────────────
	if _prof_racial_vbox == null:
		return
	for ch2: Node in _prof_racial_vbox.get_children():
		ch2.queue_free()

	var free_count: int = int(_wizard.get_race_dict().get("free_skill_choices", 0))
	if free_count > 0:
		_prof_racial_vbox.add_child(HSeparator.new())

		var racial_hdr := Label.new()
		racial_hdr.text = "Racial Free Skills (choose %d from any skill):" % free_count
		racial_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(13.0))
		_prof_racial_vbox.add_child(racial_hdr)

		_wizard.chosen_racial_skills = _wizard.chosen_racial_skills.filter(
			func(s: Variant) -> bool: return not auto_skills.has(str(s)) and not _wizard.chosen_skills.has(str(s))
		)

		var any_skills: Array = WizardConstants.ALL_SKILLS.filter(
			func(s: Variant) -> bool: return not auto_skills.has(str(s)) and not _wizard.chosen_skills.has(str(s))
		)
		for rsk_var: Variant in any_skills:
			var rsk: String = str(rsk_var)
			var rchk := CheckBox.new()
			rchk.text = rsk
			rchk.button_pressed = _wizard.chosen_racial_skills.has(rsk)
			rchk.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
			rchk.toggled.connect(func(on: bool) -> void:
				if on:
					if _wizard.chosen_racial_skills.size() < free_count:
						_wizard.chosen_racial_skills.append(rsk)
					else:
						rchk.set_pressed_no_signal(false)
				else:
					_wizard.chosen_racial_skills.erase(rsk)
			)
			_prof_racial_vbox.add_child(rchk)
