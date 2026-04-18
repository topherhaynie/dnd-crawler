extends VBoxContainer

# -----------------------------------------------------------------------------
# WizardStepOverride — Step 7: Free-form editing / DM overrides.
# -----------------------------------------------------------------------------

const _StatblockBuilder = preload("res://scripts/ui/character_wizard/WizardStatblockBuilder.gd")

var _wizard: CharacterWizard = null

# Basic info
var _ov_name_edit: LineEdit = null
var _ov_race_edit: LineEdit = null
var _ov_class_edit: LineEdit = null
var _ov_bg_edit: LineEdit = null
var _ov_level_spin: SpinBox = null

# Ability scores
var _ov_score_spins: Array = []

# Combat stats
var _ov_hp_spin: SpinBox = null
var _ov_ac_spin: SpinBox = null
var _ov_speed_spin: SpinBox = null
var _ov_prof_spin: SpinBox = null

# Notes
var _ov_notes_edit: TextEdit = null

# Spell override
var _ov_spell_source_option: OptionButton = null
var _ov_spell_vbox: VBoxContainer = null

# Custom spells
var _ov_custom_name_edit: LineEdit = null
var _ov_custom_level_spin: SpinBox = null
var _ov_custom_source_edit: LineEdit = null
var _ov_custom_list_vbox: VBoxContainer = null


func _init(wizard: CharacterWizard) -> void:
	_wizard = wizard
	name = "StepOverride"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build()


func _build() -> void:
	var intro := Label.new()
	intro.text = "All fields are pre-filled from your wizard choices. Edit anything you need — useful for high-level imports, carrying over an existing character, or DM overrides."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
	intro.modulate = Color(0.7, 0.7, 0.7)
	add_child(intro)

	var ov_scroll := ScrollContainer.new()
	ov_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ov_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(ov_scroll)

	var ov_vbox := VBoxContainer.new()
	ov_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ov_vbox.add_theme_constant_override("separation", 6)
	ov_scroll.add_child(ov_vbox)

	# ── Basic Info ────────────────────────────────────────────────────────
	var basic_hdr := Label.new()
	basic_hdr.text = "Basic Info"
	basic_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	ov_vbox.add_child(basic_hdr)

	var grid_basic := GridContainer.new()
	grid_basic.columns = 2
	grid_basic.add_theme_constant_override("h_separation", 10)
	grid_basic.add_theme_constant_override("v_separation", 4)
	ov_vbox.add_child(grid_basic)

	var lbl_nm := Label.new()
	lbl_nm.text = "Name:"
	grid_basic.add_child(lbl_nm)
	_ov_name_edit = LineEdit.new()
	_ov_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_basic.add_child(_ov_name_edit)

	var lbl_rc := Label.new()
	lbl_rc.text = "Race:"
	grid_basic.add_child(lbl_rc)
	_ov_race_edit = LineEdit.new()
	_ov_race_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_basic.add_child(_ov_race_edit)

	var lbl_cl := Label.new()
	lbl_cl.text = "Class:"
	grid_basic.add_child(lbl_cl)
	_ov_class_edit = LineEdit.new()
	_ov_class_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_basic.add_child(_ov_class_edit)

	var lbl_bg_ov := Label.new()
	lbl_bg_ov.text = "Background:"
	grid_basic.add_child(lbl_bg_ov)
	_ov_bg_edit = LineEdit.new()
	_ov_bg_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_basic.add_child(_ov_bg_edit)

	var lbl_lv := Label.new()
	lbl_lv.text = "Level:"
	grid_basic.add_child(lbl_lv)
	_ov_level_spin = SpinBox.new()
	_ov_level_spin.min_value = 1
	_ov_level_spin.max_value = 30
	grid_basic.add_child(_ov_level_spin)

	ov_vbox.add_child(HSeparator.new())

	# ── Ability Scores ────────────────────────────────────────────────────
	var ab_hdr := Label.new()
	ab_hdr.text = "Ability Scores  (final values — edit to override anything)"
	ab_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	ov_vbox.add_child(ab_hdr)

	var grid_ab := GridContainer.new()
	grid_ab.columns = 2
	grid_ab.add_theme_constant_override("h_separation", 10)
	grid_ab.add_theme_constant_override("v_separation", 4)
	ov_vbox.add_child(grid_ab)

	_ov_score_spins.clear()
	for i: int in 6:
		var lbl_ab := Label.new()
		lbl_ab.text = WizardConstants.ABILITY_NAMES[i] + ":"
		grid_ab.add_child(lbl_ab)
		var sp_ab := SpinBox.new()
		sp_ab.min_value = 1
		sp_ab.max_value = 30
		grid_ab.add_child(sp_ab)
		_ov_score_spins.append(sp_ab)

	ov_vbox.add_child(HSeparator.new())

	# ── Combat Stats ──────────────────────────────────────────────────────
	var cbt_hdr := Label.new()
	cbt_hdr.text = "Combat Stats"
	cbt_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	ov_vbox.add_child(cbt_hdr)

	var grid_cbt := GridContainer.new()
	grid_cbt.columns = 2
	grid_cbt.add_theme_constant_override("h_separation", 10)
	grid_cbt.add_theme_constant_override("v_separation", 4)
	ov_vbox.add_child(grid_cbt)

	var lbl_hp := Label.new()
	lbl_hp.text = "Max HP:"
	grid_cbt.add_child(lbl_hp)
	_ov_hp_spin = SpinBox.new()
	_ov_hp_spin.min_value = 1
	_ov_hp_spin.max_value = 9999
	grid_cbt.add_child(_ov_hp_spin)

	var lbl_ac := Label.new()
	lbl_ac.text = "Armor Class:"
	grid_cbt.add_child(lbl_ac)
	_ov_ac_spin = SpinBox.new()
	_ov_ac_spin.min_value = 1
	_ov_ac_spin.max_value = 30
	grid_cbt.add_child(_ov_ac_spin)

	var lbl_spd := Label.new()
	lbl_spd.text = "Speed (ft.):"
	grid_cbt.add_child(lbl_spd)
	_ov_speed_spin = SpinBox.new()
	_ov_speed_spin.min_value = 5
	_ov_speed_spin.max_value = 120
	grid_cbt.add_child(_ov_speed_spin)

	var lbl_pb2 := Label.new()
	lbl_pb2.text = "Proficiency Bonus:"
	grid_cbt.add_child(lbl_pb2)
	_ov_prof_spin = SpinBox.new()
	_ov_prof_spin.min_value = 2
	_ov_prof_spin.max_value = 9
	grid_cbt.add_child(_ov_prof_spin)

	ov_vbox.add_child(HSeparator.new())

	# ── Extra Notes / Features ────────────────────────────────────────────
	var notes_hdr := Label.new()
	notes_hdr.text = "Extra Features / Notes  (appended to character):"
	notes_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	ov_vbox.add_child(notes_hdr)

	_ov_notes_edit = TextEdit.new()
	_ov_notes_edit.custom_minimum_size = Vector2(0, 80)
	_ov_notes_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ov_notes_edit.placeholder_text = "Additional traits, equipment, spells, campaign notes..."
	_ov_notes_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	ov_vbox.add_child(_ov_notes_edit)

	ov_vbox.add_child(HSeparator.new())

	# ── Spell Loadout ─────────────────────────────────────────────────────
	var spell_ov_hdr := Label.new()
	spell_ov_hdr.text = "Spell Loadout  (optional override)"
	spell_ov_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	ov_vbox.add_child(spell_ov_hdr)

	var spell_ov_note := Label.new()
	spell_ov_note.text = "Any spells ticked below replace the wizard-chosen list entirely. Leave all unticked to keep the Class Features spell selection. Useful for importing existing characters or non-standard magic access."
	spell_ov_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	spell_ov_note.modulate = Color(0.7, 0.7, 0.7)
	spell_ov_note.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
	ov_vbox.add_child(spell_ov_note)

	var spell_src_row := HBoxContainer.new()
	ov_vbox.add_child(spell_src_row)
	var spell_src_lbl := Label.new()
	spell_src_lbl.text = "Show list from:"
	spell_src_row.add_child(spell_src_lbl)
	_ov_spell_source_option = OptionButton.new()
	_ov_spell_source_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ov_spell_source_option.item_selected.connect(_rebuild_ov_spell_list)
	spell_src_row.add_child(_ov_spell_source_option)

	var spell_ov_scroll := ScrollContainer.new()
	spell_ov_scroll.custom_minimum_size = Vector2(0, 200)
	spell_ov_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ov_vbox.add_child(spell_ov_scroll)
	_ov_spell_vbox = VBoxContainer.new()
	_ov_spell_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spell_ov_scroll.add_child(_ov_spell_vbox)

	ov_vbox.add_child(HSeparator.new())

	# ── Custom Spells ─────────────────────────────────────────────────────
	var custom_hdr := Label.new()
	custom_hdr.text = "Custom Spells  (books you own)"
	custom_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	ov_vbox.add_child(custom_hdr)

	var custom_note := Label.new()
	custom_note.text = "Enter spells from sourcebooks you own. Only the name, level, and source are stored — no rules text is included."
	custom_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	custom_note.modulate = Color(0.7, 0.7, 0.7)
	custom_note.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
	ov_vbox.add_child(custom_note)

	var custom_form := HBoxContainer.new()
	custom_form.add_theme_constant_override("separation", 6)
	ov_vbox.add_child(custom_form)

	_ov_custom_name_edit = LineEdit.new()
	_ov_custom_name_edit.placeholder_text = "Spell name"
	_ov_custom_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_form.add_child(_ov_custom_name_edit)

	var lvl_lbl := Label.new()
	lvl_lbl.text = "Lvl"
	custom_form.add_child(lvl_lbl)
	_ov_custom_level_spin = SpinBox.new()
	_ov_custom_level_spin.min_value = 0
	_ov_custom_level_spin.max_value = 9
	_ov_custom_level_spin.value = 1
	_ov_custom_level_spin.custom_minimum_size = Vector2(60, 0)
	custom_form.add_child(_ov_custom_level_spin)

	_ov_custom_source_edit = LineEdit.new()
	_ov_custom_source_edit.placeholder_text = "Source (e.g. Tasha's p.12)"
	_ov_custom_source_edit.custom_minimum_size = Vector2(160, 0)
	custom_form.add_child(_ov_custom_source_edit)

	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(_add_custom_spell)
	custom_form.add_child(add_btn)

	_ov_custom_name_edit.text_submitted.connect(func(_t: String) -> void: _add_custom_spell())
	_ov_custom_source_edit.text_submitted.connect(func(_t: String) -> void: _add_custom_spell())

	var custom_list_scroll := ScrollContainer.new()
	custom_list_scroll.custom_minimum_size = Vector2(0, 100)
	custom_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ov_vbox.add_child(custom_list_scroll)
	_ov_custom_list_vbox = VBoxContainer.new()
	_ov_custom_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_list_scroll.add_child(_ov_custom_list_vbox)


func refresh_ui() -> void:
	var sb: StatblockData = _StatblockBuilder.build(_wizard)
	if _ov_name_edit != null:
		_ov_name_edit.text = sb.name
	if _ov_race_edit != null:
		_ov_race_edit.text = sb.race
	if _ov_class_edit != null:
		_ov_class_edit.text = sb.class_name_str
	if _ov_bg_edit != null:
		_ov_bg_edit.text = sb.background
	if _ov_level_spin != null:
		_ov_level_spin.value = sb.level
	var comp_scores: Array[int] = [sb.strength, sb.dexterity, sb.constitution,
			sb.intelligence, sb.wisdom, sb.charisma]
	for i: int in 6:
		if i < _ov_score_spins.size():
			(_ov_score_spins[i] as SpinBox).value = comp_scores[i]
	if _ov_hp_spin != null:
		_ov_hp_spin.value = sb.hit_points
	var ac_val: int = 10
	if not sb.armor_class.is_empty():
		var ac_entry: Variant = sb.armor_class[0]
		if ac_entry is Dictionary:
			ac_val = int((ac_entry as Dictionary).get("value", 10))
	if _ov_ac_spin != null:
		_ov_ac_spin.value = ac_val
	var speed_val: int = 30
	var speed_var: Variant = sb.speed.get("walk", "30 ft.")
	var speed_str: String = str(speed_var).replace(" ft.", "").strip_edges()
	if speed_str.is_valid_int():
		speed_val = speed_str.to_int()
	if _ov_speed_spin != null:
		_ov_speed_spin.value = speed_val
	if _ov_prof_spin != null:
		_ov_prof_spin.value = sb.proficiency_bonus
	if _ov_notes_edit != null:
		_ov_notes_edit.text = ""
	# Populate spell source dropdown
	if _ov_spell_source_option != null:
		_ov_spell_source_option.clear()
		var char_class: String = _wizard.get_selected_class_name()
		var source_names: Array = [char_class]
		for cn_v: Variant in _wizard.classes_raw:
			if cn_v is Dictionary:
				var cn_str: String = str((cn_v as Dictionary).get("name", ""))
				if not cn_str.is_empty() and cn_str != char_class:
					source_names.append(cn_str)
		source_names.append("All Spells")
		for sn: String in source_names:
			_ov_spell_source_option.add_item(sn)
		_wizard.ov_chosen_spells.clear()
		_rebuild_ov_spell_list(0)
	_wizard.reapply_theme()


## Apply all override widgets on top of a pre-built statblock.
func apply_overrides(sb: StatblockData) -> void:
	if _ov_name_edit != null:
		var ov_nm: String = _ov_name_edit.text.strip_edges()
		if not ov_nm.is_empty():
			sb.name = ov_nm
	if _ov_race_edit != null:
		var ov_rc: String = _ov_race_edit.text.strip_edges()
		if not ov_rc.is_empty():
			sb.race = ov_rc
	if _ov_class_edit != null:
		var ov_cl: String = _ov_class_edit.text.strip_edges()
		if not ov_cl.is_empty():
			sb.class_name_str = ov_cl
	if _ov_bg_edit != null:
		var ov_bg_val: String = _ov_bg_edit.text.strip_edges()
		if not ov_bg_val.is_empty():
			sb.background = ov_bg_val
	if _ov_level_spin != null:
		sb.level = int(_ov_level_spin.value)
	if _ov_score_spins.size() == 6:
		sb.strength = int((_ov_score_spins[0] as SpinBox).value)
		sb.dexterity = int((_ov_score_spins[1] as SpinBox).value)
		sb.constitution = int((_ov_score_spins[2] as SpinBox).value)
		sb.intelligence = int((_ov_score_spins[3] as SpinBox).value)
		sb.wisdom = int((_ov_score_spins[4] as SpinBox).value)
		sb.charisma = int((_ov_score_spins[5] as SpinBox).value)
	if _ov_hp_spin != null:
		sb.hit_points = int(_ov_hp_spin.value)
	if _ov_ac_spin != null:
		sb.armor_class = [ {"type": "natural", "value": int(_ov_ac_spin.value)}]
	if _ov_speed_spin != null:
		sb.speed = {"walk": "%d ft." % int(_ov_speed_spin.value)}
	if _ov_prof_spin != null:
		sb.proficiency_bonus = int(_ov_prof_spin.value)
	if _ov_notes_edit != null:
		var notes_txt: String = _ov_notes_edit.text.strip_edges()
		if not notes_txt.is_empty():
			if sb.features == null:
				sb.features = []
			sb.features.append({"name": "Notes", "desc": notes_txt})
	# Override spell list
	if not _wizard.ov_chosen_spells.is_empty():
		sb.spell_list = _wizard.ov_chosen_spells.duplicate()
	# Append custom spells as feature entries
	for cs: Dictionary in _wizard.ov_custom_spells:
		var level_str: String = "Cantrip" if int(cs["level"]) == 0 else "Level %d" % int(cs["level"])
		var desc: String = "%s (%s)" % [str(cs["name"]), level_str]
		if not str(cs.get("source", "")).is_empty():
			desc += " — %s" % str(cs["source"])
		if sb.features == null:
			sb.features = []
		sb.features.append({"name": "Custom Spell", "desc": desc})


func _add_custom_spell() -> void:
	if _ov_custom_name_edit == null:
		return
	var nm: String = _ov_custom_name_edit.text.strip_edges()
	if nm.is_empty():
		return
	var lvl: int = int(_ov_custom_level_spin.value) if _ov_custom_level_spin != null else 1
	var src: String = _ov_custom_source_edit.text.strip_edges() if _ov_custom_source_edit != null else ""
	_wizard.ov_custom_spells.append({"name": nm, "level": lvl, "source": src})
	_ov_custom_name_edit.text = ""
	if _ov_custom_source_edit != null:
		_ov_custom_source_edit.text = ""
	_rebuild_custom_spell_list()


func _rebuild_custom_spell_list() -> void:
	if _ov_custom_list_vbox == null:
		return
	for child: Node in _ov_custom_list_vbox.get_children():
		child.queue_free()
	if _wizard.ov_custom_spells.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No custom spells added yet."
		empty_lbl.modulate = Color(0.5, 0.5, 0.5)
		empty_lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
		_ov_custom_list_vbox.add_child(empty_lbl)
		return
	for idx: int in range(_wizard.ov_custom_spells.size()):
		var cs: Dictionary = _wizard.ov_custom_spells[idx]
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var level_str: String = "Cantrip" if int(cs["level"]) == 0 else "Level %d" % int(cs["level"])
		lbl.text = "%s  (%s)" % [str(cs["name"]), level_str]
		if not str(cs.get("source", "")).is_empty():
			lbl.text += "  —  %s" % str(cs["source"])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
		row.add_child(lbl)
		var rm_btn := Button.new()
		rm_btn.text = "×"
		rm_btn.flat = true
		rm_btn.modulate = Color(1.0, 0.4, 0.4)
		var capture_idx: int = idx
		rm_btn.pressed.connect(func() -> void:
			_wizard.ov_custom_spells.remove_at(capture_idx)
			_rebuild_custom_spell_list()
		)
		row.add_child(rm_btn)
		_ov_custom_list_vbox.add_child(row)


func _rebuild_ov_spell_list(source_idx: int) -> void:
	if _ov_spell_vbox == null or _ov_spell_source_option == null:
		return
	for child: Node in _ov_spell_vbox.get_children():
		child.queue_free()
	_wizard.ov_chosen_spells.clear()
	var source_nm: String = _ov_spell_source_option.get_item_text(source_idx)
	var is_all: bool = (source_nm == "All Spells")
	var by_level: Dictionary = {}
	for sp_v: Variant in _wizard.spells_raw:
		if not (sp_v is SpellData):
			continue
		var sd := sp_v as SpellData
		if not is_all:
			var found_class: bool = false
			for cls_nm: Variant in sd.classes:
				if str(cls_nm).nocasecmp_to(source_nm) == 0:
					found_class = true
					break
			if not found_class:
				continue
		var lvl_key: int = sd.level
		if not by_level.has(lvl_key):
			by_level[lvl_key] = []
		(by_level[lvl_key] as Array).append(sd)
	if by_level.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "(No spells found for this source.)"
		empty_lbl.modulate = Color(0.6, 0.6, 0.6)
		_ov_spell_vbox.add_child(empty_lbl)
		return
	var sorted_levels: Array = by_level.keys()
	sorted_levels.sort()
	for lv: Variant in sorted_levels:
		var level_int: int = int(lv)
		var hdr := Label.new()
		hdr.text = "Cantrips" if level_int == 0 else "%s-level Spells" % WizardConstants.spell_level_ordinal(level_int)
		hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
		hdr.modulate = Color(0.7, 0.85, 1.0)
		_ov_spell_vbox.add_child(hdr)
		var spell_grid := GridContainer.new()
		spell_grid.columns = 2
		spell_grid.add_theme_constant_override("h_separation", 10)
		spell_grid.add_theme_constant_override("v_separation", 2)
		_ov_spell_vbox.add_child(spell_grid)
		var spells_at_level: Array = by_level[lv] as Array
		spells_at_level.sort_custom(func(a: SpellData, b: SpellData) -> bool: return a.name < b.name)
		for sp2_v: Variant in spells_at_level:
			var sd2 := sp2_v as SpellData
			var cb := CheckBox.new()
			cb.text = sd2.name
			cb.button_pressed = _wizard.ov_chosen_spells.has(sd2.index)
			cb.toggled.connect(func(on: bool) -> void:
				if on:
					if not _wizard.ov_chosen_spells.has(sd2.index):
						_wizard.ov_chosen_spells.append(sd2.index)
				else:
					_wizard.ov_chosen_spells.erase(sd2.index)
			)
			spell_grid.add_child(cb)
	_wizard.reapply_theme()
