extends VBoxContainer

# -----------------------------------------------------------------------------
# WizardStepNameRace — Step 0: Character name, ruleset, race, and subrace.
# -----------------------------------------------------------------------------

var _wizard: CharacterWizard = null

var _name_edit: LineEdit = null
var _ruleset_option: OptionButton = null
var _race_option: OptionButton = null
var _subrace_container: VBoxContainer = null
var _subrace_option: OptionButton = null
var _race_traits_panel: ScrollContainer = null
var _race_traits_label: RichTextLabel = null
var _racial_choices_container: VBoxContainer = null


func _init(wizard: CharacterWizard) -> void:
	_wizard = wizard
	name = "StepNameRace"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build()


func _build() -> void:
	var ruleset_lbl := Label.new()
	ruleset_lbl.text = "Ruleset:"
	add_child(ruleset_lbl)

	_ruleset_option = OptionButton.new()
	_ruleset_option.add_item("D&D 5e 2014 (SRD)", 0)
	_ruleset_option.add_item("D&D 5e 2024 (SRD)", 1)
	_ruleset_option.select(0)
	_ruleset_option.item_selected.connect(_on_ruleset_selected)
	add_child(_ruleset_option)

	var name_lbl := Label.new()
	name_lbl.text = "Character name:"
	add_child(name_lbl)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Enter a name…"
	_name_edit.text_changed.connect(func(text: String) -> void: _wizard.char_name = text)
	add_child(_name_edit)

	var race_lbl := Label.new()
	race_lbl.text = "Race / Species:"
	add_child(race_lbl)

	_race_option = OptionButton.new()
	_race_option.item_selected.connect(_on_race_selected)
	add_child(_race_option)

	_subrace_container = VBoxContainer.new()
	_subrace_container.add_theme_constant_override("separation", 4)
	_subrace_container.visible = false
	add_child(_subrace_container)

	var subrace_lbl := Label.new()
	subrace_lbl.text = "Subrace:"
	_subrace_container.add_child(subrace_lbl)

	_subrace_option = OptionButton.new()
	_subrace_option.item_selected.connect(_on_subrace_selected)
	_subrace_container.add_child(_subrace_option)

	var traits_header := Label.new()
	traits_header.text = "Race traits:"
	add_child(traits_header)

	_race_traits_panel = ScrollContainer.new()
	_race_traits_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_race_traits_panel.custom_minimum_size = Vector2(0, 100)
	_race_traits_panel.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_race_traits_panel)

	_race_traits_label = RichTextLabel.new()
	_race_traits_label.bbcode_enabled = true
	_race_traits_label.fit_content = true
	_race_traits_label.scroll_active = false
	_race_traits_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_race_traits_label.text = "(Select a race to see traits.)"
	_race_traits_panel.add_child(_race_traits_label)

	_racial_choices_container = VBoxContainer.new()
	_racial_choices_container.add_theme_constant_override("separation", 6)
	add_child(_racial_choices_container)


func populate_race_option() -> void:
	if _race_option == null:
		return
	_race_option.clear()
	if _wizard.races_raw.is_empty():
		_race_option.add_item("(SRD not loaded)")
		_refresh_race_traits_ui()
		return
	for raw: Variant in _wizard.races_raw:
		if raw is Dictionary:
			_race_option.add_item(str((raw as Dictionary).get("name", "?")))
	_refresh_race_traits_ui()


func reset_ruleset() -> void:
	if _ruleset_option != null:
		_ruleset_option.select(0)


func validate() -> bool:
	if _wizard.char_name.strip_edges().is_empty():
		_wizard.show_error("Please enter a character name.")
		return false
	var race_nm: String = _wizard.get_selected_race_name()
	var race_d_var: Variant = WizardConstants.RACE_DATA.get(race_nm, {})
	if race_d_var is Dictionary and bool((race_d_var as Dictionary).get("asi_choose_two", false)):
		if _wizard.half_elf_asi_choices.size() < 2:
			_wizard.show_error("Half-Elves gain +1 to two ability scores of your choice. Please select two.")
			return false
	if not _wizard.subrace_name.is_empty():
		var sub_d: Dictionary = _wizard.get_subrace_dict()
		if bool(sub_d.get("choose_cantrip", false)) and _wizard.racial_cantrip.is_empty():
			_wizard.show_error("Please choose a %s cantrip." % _wizard.subrace_name)
			return false
	var expected_langs: int = _wizard.expected_extra_language_count()
	for li: int in expected_langs:
		var chosen: String = _wizard.racial_extra_languages[li] if li < _wizard.racial_extra_languages.size() else ""
		if chosen.is_empty():
			_wizard.show_error("Please choose all extra languages before continuing.")
			return false
	if race_d_var is Dictionary and \
			bool((race_d_var as Dictionary).get("choose_draconic_ancestry", false)):
		if _wizard.dragonborn_ancestry.is_empty():
			_wizard.show_error("Please choose a Draconic Ancestry before continuing.")
			return false
	return true


# ── Event handlers ────────────────────────────────────────────────────
func _on_ruleset_selected(idx: int) -> void:
	var new_ruleset: String = "2024" if idx == 1 else "2014"
	_wizard._on_ruleset_changed(new_ruleset)


func _on_race_selected(idx: int) -> void:
	_wizard.race_index = idx
	_wizard.subrace_name = ""
	_wizard.racial_cantrip = ""
	_wizard.racial_extra_languages.clear()
	_wizard.half_elf_asi_choices.clear()
	_refresh_race_traits_ui()
	_refresh_racial_choices_ui()


func _on_subrace_selected(idx: int) -> void:
	if _subrace_option == null:
		return
	_wizard.subrace_name = "" if idx == 0 else _subrace_option.get_item_text(idx)
	_wizard.racial_cantrip = ""
	_wizard.racial_extra_languages.clear()
	if _race_traits_label != null:
		_race_traits_label.text = _race_traits_text(_wizard.get_selected_race_name())
	_refresh_racial_choices_ui()


func _refresh_race_traits_ui() -> void:
	if _race_traits_label == null:
		return
	var race_nm: String = _wizard.get_selected_race_name()
	var subs_var: Variant = WizardConstants.SUBRACE_DATA.get(race_nm, [])
	var subs: Array = subs_var as Array if subs_var is Array else []
	if _subrace_container != null:
		_subrace_container.visible = not subs.is_empty()
	if _subrace_option != null:
		_subrace_option.clear()
		if not subs.is_empty():
			_subrace_option.add_item("None (base race)")
			for sub: Variant in subs:
				if sub is Dictionary:
					_subrace_option.add_item(str((sub as Dictionary).get("name", "")))
	_race_traits_label.text = _race_traits_text(race_nm)


func _race_traits_text(race_nm: String) -> String:
	if race_nm.is_empty():
		return "(Select a race to see traits.)"
	var lines: Array = []

	if not _wizard.races_raw.is_empty() and _wizard.race_index < _wizard.races_raw.size():
		var raw: Variant = _wizard.races_raw[_wizard.race_index]
		if raw is Dictionary:
			var rd := raw as Dictionary
			var spd: int = int(rd.get("speed", 30))
			var sz: String = str(rd.get("size", "Medium"))
			lines.append("[b]Speed:[/b] %d ft.  |  [b]Size:[/b] %s" % [spd, sz])
			var ab_var: Variant = rd.get("ability_bonuses", [])
			if ab_var is Array:
				var parts: Array = []
				for ab: Variant in ab_var as Array:
					if ab is Dictionary:
						var abd := ab as Dictionary
						var score_var: Variant = abd.get("ability_score", {})
						var score_nm: String = ""
						if score_var is Dictionary:
							score_nm = str((score_var as Dictionary).get("name", ""))
						var bonus: int = int(abd.get("bonus", 0))
						if not score_nm.is_empty():
							parts.append("%s +%d" % [score_nm, bonus])
				if not parts.is_empty():
					lines.append("[b]ASI:[/b] " + ", ".join(parts))
			var lang_var: Variant = rd.get("languages", [])
			if lang_var is Array:
				var lang_parts: Array = []
				for lang: Variant in lang_var as Array:
					if lang is Dictionary:
						lang_parts.append(str((lang as Dictionary).get("name", "")))
				if not lang_parts.is_empty():
					lines.append("[b]Languages:[/b] " + ", ".join(lang_parts))
			var traits_var: Variant = rd.get("traits", [])
			if traits_var is Array and not (traits_var as Array).is_empty():
				var trait_names: Array = []
				for t: Variant in traits_var as Array:
					if t is Dictionary:
						var tn: String = str((t as Dictionary).get("name", ""))
						if not tn.is_empty():
							trait_names.append(tn)
				if not trait_names.is_empty():
					lines.append("[b]Racial Traits:[/b] " + ", ".join(trait_names))

	if not _wizard.subrace_name.is_empty():
		var subs_var: Variant = WizardConstants.SUBRACE_DATA.get(race_nm, [])
		if subs_var is Array:
			for sub: Variant in subs_var as Array:
				if not (sub is Dictionary):
					continue
				var sd := sub as Dictionary
				if str(sd.get("name", "")) != _wizard.subrace_name:
					continue
				lines.append("")
				lines.append("[b]── %s ──[/b]" % _wizard.subrace_name)
				var asi: String = str(sd.get("asi", ""))
				if not asi.is_empty():
					lines.append("[b]Subrace ASI:[/b] " + asi)
				var st_var: Variant = sd.get("traits", [])
				if st_var is Array:
					for st: Variant in st_var as Array:
						lines.append("• " + str(st))
				break

	if lines.is_empty():
		return "(No trait data available.)"
	return "\n".join(lines)


func _refresh_racial_choices_ui() -> void:
	if _racial_choices_container == null:
		return
	for child: Node in _racial_choices_container.get_children():
		child.queue_free()

	var race_nm: String = _wizard.get_selected_race_name()
	var race_d_var: Variant = WizardConstants.RACE_DATA.get(race_nm, {})
	var race_d: Dictionary = race_d_var as Dictionary if race_d_var is Dictionary else {}

	var sub_d: Dictionary = {}
	if not _wizard.subrace_name.is_empty():
		var subs_var: Variant = WizardConstants.SUBRACE_DATA.get(race_nm, [])
		if subs_var is Array:
			for s: Variant in subs_var as Array:
				if s is Dictionary and str((s as Dictionary).get("name", "")) == _wizard.subrace_name:
					sub_d = s as Dictionary
					break

	# ── Half-Elf: choose two ability scores for +1 each ──────────────────
	var asi_choose_two: bool = bool(race_d.get("asi_choose_two", false))
	if asi_choose_two:
		var hdr := Label.new()
		hdr.text = "Bonus +1 to two ability scores of your choice (not Charisma):"
		_racial_choices_container.add_child(hdr)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 4)
		_racial_choices_container.add_child(grid)
		var fixed_keys: Array = []
		var fixed_var: Variant = race_d.get("asi_keys", [])
		if fixed_var is Array:
			for fe: Variant in fixed_var as Array:
				if fe is Dictionary:
					fixed_keys.append(str((fe as Dictionary).get("key", "")))
		for i: int in WizardConstants.ABILITY_NAMES.size():
			var ab_key: String = WizardConstants.ABILITY_KEYS[i]
			if fixed_keys.has(ab_key):
				continue
			var cb := CheckBox.new()
			cb.text = WizardConstants.ABILITY_NAMES[i]
			cb.button_pressed = _wizard.half_elf_asi_choices.has(ab_key)
			cb.toggled.connect(
				func(on: bool) -> void:
					if on:
						if _wizard.half_elf_asi_choices.size() < 2 and not _wizard.half_elf_asi_choices.has(ab_key):
							_wizard.half_elf_asi_choices.append(ab_key)
						else:
							cb.set_pressed_no_signal(false)
					else:
						_wizard.half_elf_asi_choices.erase(ab_key)
			)
			grid.add_child(cb)

	# ── Wizard cantrip choice (High Elf) ─────────────────────────────────
	var choose_cantrip: bool = bool(sub_d.get("choose_cantrip", false))
	if choose_cantrip:
		var hdr := Label.new()
		hdr.text = "Choose one Wizard cantrip:"
		_racial_choices_container.add_child(hdr)
		var ct_opt := OptionButton.new()
		ct_opt.add_item("(choose)")
		var wizard_cantrips: Array = [
			"Acid Splash", "Chill Touch", "Dancing Lights", "Fire Bolt",
			"Light", "Mage Hand", "Mending", "Message", "Minor Illusion",
			"Poison Spray", "Prestidigitation", "Ray of Frost",
			"Shocking Grasp", "True Strike",
		]
		var wizard_indices: Array = [
			"acid-splash", "chill-touch", "dancing-lights", "fire-bolt",
			"light", "mage-hand", "mending", "message", "minor-illusion",
			"poison-spray", "prestidigitation", "ray-of-frost",
			"shocking-grasp", "true-strike",
		]
		for nm: String in wizard_cantrips:
			ct_opt.add_item(nm)
		ct_opt.item_selected.connect(
			func(sel_idx: int) -> void:
				_wizard.racial_cantrip = "" if sel_idx == 0 else wizard_indices[sel_idx - 1]
		)
		if not _wizard.racial_cantrip.is_empty():
			var wci: int = wizard_indices.find(_wizard.racial_cantrip)
			if wci >= 0:
				ct_opt.select(wci + 1)
		_racial_choices_container.add_child(ct_opt)

	# ── Extra language choice ─────────────────────────────────────────────
	var choose_lang_base: bool = bool(race_d.get("choose_language", false))
	var choose_lang_sub: bool = bool(sub_d.get("choose_language", false))
	var extra_langs_needed: int = int(race_d.get("choose_languages", 0))
	if choose_lang_base or choose_lang_sub:
		extra_langs_needed = maxi(extra_langs_needed, 1)

	var common_languages: Array = [
		"Abyssal", "Celestial", "Common", "Deep Speech", "Draconic",
		"Dwarvish", "Elvish", "Giant", "Gnomish", "Goblin", "Halfling",
		"Infernal", "Orc", "Primordial", "Sylvan", "Undercommon",
	]

	for li: int in extra_langs_needed:
		var lang_hdr := Label.new()
		lang_hdr.text = "Choose an extra language:" if extra_langs_needed == 1 else "Choose extra language %d:" % (li + 1)
		_racial_choices_container.add_child(lang_hdr)
		var lang_opt := OptionButton.new()
		lang_opt.add_item("(choose)")
		for lnm: String in common_languages:
			lang_opt.add_item(lnm)
		var slot_index: int = li
		if slot_index < _wizard.racial_extra_languages.size():
			var prev: String = _wizard.racial_extra_languages[slot_index]
			var prev_i: int = common_languages.find(prev)
			if prev_i >= 0:
				lang_opt.select(prev_i + 1)
		lang_opt.item_selected.connect(
			func(sel_idx: int) -> void:
				var chosen: String = "" if sel_idx == 0 else common_languages[sel_idx - 1]
				while _wizard.racial_extra_languages.size() <= slot_index:
					_wizard.racial_extra_languages.append("")
				_wizard.racial_extra_languages[slot_index] = chosen
		)
		_racial_choices_container.add_child(lang_opt)

	# ── Dragonborn: Draconic Ancestry ────────────────────────────────────────
	var choose_ancestry: bool = bool(race_d.get("choose_draconic_ancestry", false))
	if choose_ancestry:
		var anc_hdr := Label.new()
		anc_hdr.text = "Draconic Ancestry (determines breath weapon & resistance):"
		_racial_choices_container.add_child(anc_hdr)
		var anc_opt := OptionButton.new()
		anc_opt.add_item("(choose)")
		var ancestry_types: Array = [
			"Black (Acid)", "Blue (Lightning)", "Brass (Fire)", "Bronze (Lightning)",
			"Copper (Acid)", "Gold (Fire)", "Green (Poison)", "Red (Fire)",
			"Silver (Cold)", "White (Cold)",
		]
		for at: String in ancestry_types:
			anc_opt.add_item(at)
		if not _wizard.dragonborn_ancestry.is_empty():
			var ai: int = ancestry_types.find(_wizard.dragonborn_ancestry)
			if ai >= 0:
				anc_opt.select(ai + 1)
		anc_opt.item_selected.connect(
			func(sel_i: int) -> void:
				_wizard.dragonborn_ancestry = "" if sel_i == 0 else ancestry_types[sel_i - 1]
		)
		_racial_choices_container.add_child(anc_opt)
	_wizard.reapply_theme()
