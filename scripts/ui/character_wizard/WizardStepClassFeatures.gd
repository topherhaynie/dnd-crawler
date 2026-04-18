extends VBoxContainer

# -----------------------------------------------------------------------------
# WizardStepClassFeatures — Step 2: Subclass, cantrips, spells, fighting style,
#   ranger/rogue/warlock features, ASI info, feats, and class feature summary.
# -----------------------------------------------------------------------------

var _wizard: CharacterWizard = null

var _cf_scroll: ScrollContainer = null
var _cf_container: VBoxContainer = null
var _cf_subclass_option: OptionButton = null
var _cantrip_counter_label: Label = null
var _spell_counter_label: Label = null


func _init(wizard: CharacterWizard) -> void:
	_wizard = wizard
	name = "StepClassFeatures"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_build()


func _build() -> void:
	_cf_scroll = ScrollContainer.new()
	_cf_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cf_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_cf_scroll)

	_cf_container = VBoxContainer.new()
	_cf_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cf_container.add_theme_constant_override("separation", 8)
	_cf_scroll.add_child(_cf_container)


## Rebuild the class features UI for the current class + level.
## Called each time CLASS_FEATURES becomes visible.
func refresh_ui() -> void:
	_cantrip_counter_label = null
	_spell_counter_label = null
	for child: Node in _cf_container.get_children():
		child.queue_free()
	_cf_subclass_option = null
	_wizard.selected_subclass = ""
	_wizard.chosen_cantrips.clear()
	_wizard.chosen_spells.clear()
	_wizard.chosen_fighting_style = ""
	_wizard.chosen_invocations.clear()
	_wizard.chosen_pact_boon = ""
	_wizard.ranger_favored_enemy = ""
	_wizard.ranger_terrain = ""
	_wizard.rogue_expertise_skills.clear()

	var class_nm: String = _wizard.get_selected_class_name()
	var class_key: String = class_nm.to_lower()
	var cls_data: Variant = WizardConstants.CLASS_DATA.get(class_key)

	if not (cls_data is Dictionary):
		var placeholder := Label.new()
		placeholder.text = "Select a class in the previous step."
		placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD
		_cf_container.add_child(placeholder)
		return

	var cd := cls_data as Dictionary

	# ── Subclass selection ────────────────────────────────────────────────
	var subclass_level: int = int(cd.get("subclass_level", 0))
	if subclass_level > 0:
		var sc_type: String = str(cd.get("subclass_type", "Subclass"))
		if _wizard.level >= subclass_level:
			var sc_lbl := Label.new()
			sc_lbl.text = "%s:" % sc_type
			_cf_container.add_child(sc_lbl)

			_cf_subclass_option = OptionButton.new()
			_cf_subclass_option.add_item("(choose)")
			var subclasses_var: Variant = cd.get("subclasses", [])
			if subclasses_var is Array:
				for sc: Variant in subclasses_var as Array:
					_cf_subclass_option.add_item(str(sc))
			_cf_subclass_option.item_selected.connect(
				func(i: int) -> void:
					_wizard.selected_subclass = "" if i == 0 else _cf_subclass_option.get_item_text(i)
			)
			_cf_container.add_child(_cf_subclass_option)
		else:
			var sc_note := Label.new()
			sc_note.text = "You will choose your %s at level %d." % [sc_type, subclass_level]
			sc_note.autowrap_mode = TextServer.AUTOWRAP_WORD
			sc_note.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
			sc_note.modulate = Color(0.7, 0.7, 0.7)
			_cf_container.add_child(sc_note)

	# ── Cantrip selection ─────────────────────────────────────────────────
	var cantrip_count: int = WizardConstants.cantrips_for_level(class_key, _wizard.level)
	if cantrip_count > 0:
		var ct_header := Label.new()
		ct_header.text = "Choose %d cantrip%s:" % [cantrip_count, "s" if cantrip_count != 1 else ""]
		_cf_container.add_child(ct_header)
		_cantrip_counter_label = Label.new()
		_cantrip_counter_label.text = "  Chosen: 0 of %d" % cantrip_count
		_cantrip_counter_label.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
		_cantrip_counter_label.modulate = Color(0.55, 0.85, 1.0)
		_cf_container.add_child(_cantrip_counter_label)
		_build_spell_checklist(_wizard.get_spells_for_class(class_nm, 0), cantrip_count, true)

	# ── Spell selection ───────────────────────────────────────────────────
	var spell_type: String = str(cd.get("spell_type", ""))
	var max_spl_lvl: int = WizardConstants.max_spell_level_for_class(class_key, _wizard.level)

	if spell_type == "known":
		var known_count: int = WizardConstants.spells_known_for_level(class_key, _wizard.level)
		if known_count > 0 and max_spl_lvl > 0:
			var sp_hdr := Label.new()
			sp_hdr.text = "Spells Known — choose %d total (any combination of levels 1–%d):" % [
					known_count, max_spl_lvl]
			_cf_container.add_child(sp_hdr)
			_spell_counter_label = Label.new()
			_spell_counter_label.text = "  Chosen: 0 of %d" % known_count
			_spell_counter_label.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
			_spell_counter_label.modulate = Color(0.55, 0.85, 1.0)
			_cf_container.add_child(_spell_counter_label)
			for spl_lvl: int in range(1, max_spl_lvl + 1):
				var spl_hdr := Label.new()
				spl_hdr.text = WizardConstants.spell_level_ordinal(spl_lvl) + "-Level Spells:"
				spl_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
				spl_hdr.modulate = Color(0.8, 0.8, 0.8)
				_cf_container.add_child(spl_hdr)
				_build_spell_checklist(_wizard.get_spells_for_class(class_nm, spl_lvl), known_count, false)

	elif spell_type == "spellbook":
		var sb_size: int = WizardConstants.spellbook_size_for_level(_wizard.level)
		if max_spl_lvl > 0:
			var sp_hdr := Label.new()
			sp_hdr.text = "Spellbook — choose %d entries (any combination of levels 1–%d):" % [
					sb_size, max_spl_lvl]
			_cf_container.add_child(sp_hdr)
			var sb_note := Label.new()
			sb_note.text = "(You can copy additional spells into your spellbook as you adventure.)"
			sb_note.autowrap_mode = TextServer.AUTOWRAP_WORD
			sb_note.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
			sb_note.modulate = Color(0.7, 0.7, 0.7)
			_cf_container.add_child(sb_note)
			_spell_counter_label = Label.new()
			_spell_counter_label.text = "  Chosen: 0 of %d" % sb_size
			_spell_counter_label.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
			_spell_counter_label.modulate = Color(0.55, 0.85, 1.0)
			_cf_container.add_child(_spell_counter_label)
			for spl_lvl: int in range(1, max_spl_lvl + 1):
				var spl_hdr := Label.new()
				spl_hdr.text = WizardConstants.spell_level_ordinal(spl_lvl) + "-Level Spells:"
				spl_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
				spl_hdr.modulate = Color(0.8, 0.8, 0.8)
				_cf_container.add_child(spl_hdr)
				_build_spell_checklist(_wizard.get_spells_for_class(class_nm, spl_lvl), sb_size, false)

	elif spell_type == "prepared":
		var prep_note := Label.new()
		prep_note.text = (
			"You prepare your spell list each long rest from the full %s spell list.\n" % class_nm
			+"Number of prepared spells = your spellcasting modifier + %s level." % class_nm
		)
		prep_note.autowrap_mode = TextServer.AUTOWRAP_WORD
		prep_note.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
		prep_note.modulate = Color(0.7, 0.7, 0.7)
		_cf_container.add_child(prep_note)

	# ── Fighting Style ────────────────────────────────────────────────────
	var fs_level: int = int(cd.get("fighting_style_level", 0))
	if fs_level > 0 and _wizard.level >= fs_level:
		var fs_styles_var: Variant = cd.get("fighting_styles", [])
		if fs_styles_var is Array and not (fs_styles_var as Array).is_empty():
			var fs_lbl := Label.new()
			fs_lbl.text = "Fighting Style:"
			_cf_container.add_child(fs_lbl)
			var fs_opt := OptionButton.new()
			fs_opt.add_item("(choose)")
			for style: Variant in fs_styles_var as Array:
				fs_opt.add_item(str(style))
			if not _wizard.chosen_fighting_style.is_empty():
				var fs_arr: Array = fs_styles_var as Array
				var fi: int = fs_arr.find(_wizard.chosen_fighting_style)
				if fi >= 0:
					fs_opt.select(fi + 1)
			fs_opt.item_selected.connect(
				func(sel_i: int) -> void:
					_wizard.chosen_fighting_style = "" if sel_i == 0 else str((fs_styles_var as Array)[sel_i - 1])
			)
			_cf_container.add_child(fs_opt)

	# ── Ranger: Favored Enemy + Natural Explorer ──────────────────────────
	var fe_level: int = int(cd.get("favored_enemy_level", 0))
	if fe_level > 0 and _wizard.level >= fe_level:
		var enemy_types: Array = [
			"Aberrations", "Beasts", "Celestials", "Constructs", "Dragons",
			"Elementals", "Fey", "Fiends", "Giants", "Humanoids (two types)",
			"Monstrosities", "Oozes", "Plants", "Undead",
		]
		var terrain_types: Array = [
			"Arctic", "Coast", "Desert", "Forest", "Grassland",
			"Mountain", "Swamp", "Underdark",
		]
		var fe_lbl := Label.new()
		fe_lbl.text = "Favored Enemy (choose type):"
		_cf_container.add_child(fe_lbl)
		var fe_opt := OptionButton.new()
		fe_opt.add_item("(choose)")
		for et: String in enemy_types:
			fe_opt.add_item(et)
		if not _wizard.ranger_favored_enemy.is_empty():
			var fei: int = enemy_types.find(_wizard.ranger_favored_enemy)
			if fei >= 0:
				fe_opt.select(fei + 1)
		fe_opt.item_selected.connect(
			func(sel_i: int) -> void:
				_wizard.ranger_favored_enemy = "" if sel_i == 0 else enemy_types[sel_i - 1]
		)
		_cf_container.add_child(fe_opt)

		var ne_lbl := Label.new()
		ne_lbl.text = "Natural Explorer (favored terrain):"
		_cf_container.add_child(ne_lbl)
		var ne_opt := OptionButton.new()
		ne_opt.add_item("(choose)")
		for tt: String in terrain_types:
			ne_opt.add_item(tt)
		if not _wizard.ranger_terrain.is_empty():
			var nti: int = terrain_types.find(_wizard.ranger_terrain)
			if nti >= 0:
				ne_opt.select(nti + 1)
		ne_opt.item_selected.connect(
			func(sel_i: int) -> void:
				_wizard.ranger_terrain = "" if sel_i == 0 else terrain_types[sel_i - 1]
		)
		_cf_container.add_child(ne_opt)

	# ── Rogue: Expertise ──────────────────────────────────────────────────
	var exp_level: int = int(cd.get("expertise_level", 0))
	if exp_level > 0 and _wizard.level >= exp_level:
		var exp_count: int = int(cd.get("expertise_count", 2))
		var skills_var: Variant = cd.get("skills_list", [])
		if skills_var is Array and not (skills_var as Array).is_empty():
			var exp_lbl := Label.new()
			exp_lbl.text = "Expertise — choose %d skills to double proficiency:" % exp_count
			_cf_container.add_child(exp_lbl)
			var exp_grid := GridContainer.new()
			exp_grid.columns = 2
			exp_grid.add_theme_constant_override("h_separation", 8)
			exp_grid.add_theme_constant_override("v_separation", 4)
			_cf_container.add_child(exp_grid)
			for skill_raw: Variant in skills_var as Array:
				var skill_nm: String = str(skill_raw)
				var cb := CheckBox.new()
				cb.text = skill_nm
				cb.button_pressed = _wizard.rogue_expertise_skills.has(skill_nm)
				cb.toggled.connect(
					func(on: bool) -> void:
						if on:
							if _wizard.rogue_expertise_skills.size() < exp_count and \
									not _wizard.rogue_expertise_skills.has(skill_nm):
								_wizard.rogue_expertise_skills.append(skill_nm)
							else:
								cb.set_pressed_no_signal(false)
						else:
							_wizard.rogue_expertise_skills.erase(skill_nm)
				)
				exp_grid.add_child(cb)

	# ── Warlock: Eldritch Invocations ─────────────────────────────────────
	var inv_level: int = int(cd.get("invocations_level", 0))
	if inv_level > 0 and _wizard.level >= inv_level:
		var inv_list_var: Variant = cd.get("invocations", [])
		if inv_list_var is Array and not (inv_list_var as Array).is_empty():
			var max_inv: int = int(cd.get("invocation_count_2", 2)) + maxi(0, int((_wizard.level - 2) / 2.0))
			var inv_hdr := Label.new()
			inv_hdr.text = "Eldritch Invocations — choose %d:" % max_inv
			_cf_container.add_child(inv_hdr)
			var inv_grid := GridContainer.new()
			inv_grid.columns = 2
			inv_grid.add_theme_constant_override("h_separation", 8)
			inv_grid.add_theme_constant_override("v_separation", 4)
			_cf_container.add_child(inv_grid)
			for inv_raw: Variant in inv_list_var as Array:
				var inv_nm: String = str(inv_raw)
				var inv_row := HBoxContainer.new()
				inv_row.add_theme_constant_override("separation", 4)
				inv_grid.add_child(inv_row)
				var cb := CheckBox.new()
				cb.text = inv_nm
				cb.button_pressed = _wizard.chosen_invocations.has(inv_nm)
				cb.toggled.connect(
					func(on: bool) -> void:
						if on:
							if _wizard.chosen_invocations.size() < max_inv and \
									not _wizard.chosen_invocations.has(inv_nm):
								_wizard.chosen_invocations.append(inv_nm)
							else:
								cb.set_pressed_no_signal(false)
						else:
							_wizard.chosen_invocations.erase(inv_nm)
				)
				inv_row.add_child(cb)

	# ── Warlock: Pact Boon ────────────────────────────────────────────────
	var pb_level: int = int(cd.get("pact_boon_level", 0))
	if pb_level > 0 and _wizard.level >= pb_level:
		var pb_lbl := Label.new()
		pb_lbl.text = "Pact Boon:"
		_cf_container.add_child(pb_lbl)
		var pb_opt := OptionButton.new()
		pb_opt.add_item("(choose)")
		var pact_boons: Array = ["Pact of the Blade", "Pact of the Chain", "Pact of the Tome"]
		for boon: String in pact_boons:
			pb_opt.add_item(boon)
		if not _wizard.chosen_pact_boon.is_empty():
			var pbi: int = pact_boons.find(_wizard.chosen_pact_boon)
			if pbi >= 0:
				pb_opt.select(pbi + 1)
		pb_opt.item_selected.connect(
			func(sel_i: int) -> void:
				_wizard.chosen_pact_boon = "" if sel_i == 0 else pact_boons[sel_i - 1]
		)
		_cf_container.add_child(pb_opt)

	# ── Class features summary ────────────────────────────────────────────
	_cf_container.add_child(HSeparator.new())

	var feat_header := Label.new()
	feat_header.text = "Level %d %s — Key Features:" % [_wizard.level, class_nm]
	feat_header.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	_cf_container.add_child(feat_header)

	var feat_lbl := RichTextLabel.new()
	feat_lbl.bbcode_enabled = true
	feat_lbl.fit_content = true
	feat_lbl.scroll_active = false
	feat_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feat_lbl.text = _class_features_text(class_key, _wizard.level)
	_cf_container.add_child(feat_lbl)

	# ── ASI / Feat choices ────────────────────────────────────────────────
	var asi_total: int = WizardConstants.asi_count_for(class_key, _wizard.level)
	if asi_total > 0:
		_cf_container.add_child(HSeparator.new())
		var asi_hdr := Label.new()
		asi_hdr.text = "Ability Score Improvements / Feats  (%d slot%s)" % [
				asi_total, "s" if asi_total != 1 else ""]
		asi_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
		_cf_container.add_child(asi_hdr)

		var asi_desc := Label.new()
		asi_desc.text = "For each ASI slot, choose: +2 to one ability, +1 to two abilities, or take a feat."
		asi_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		asi_desc.modulate = Color(0.7, 0.7, 0.7)
		asi_desc.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
		_cf_container.add_child(asi_desc)

		# Ensure asi_choices has the right number of slots
		while _wizard.asi_choices.size() < asi_total:
			_wizard.asi_choices.append({"type": "none"})
		if _wizard.asi_choices.size() > asi_total:
			_wizard.asi_choices.resize(asi_total)

		for slot_i: int in asi_total:
			_build_asi_slot(slot_i)

	# ── Bonus feats (DM discretion, outside ASI budget) ───────────────────
	_cf_container.add_child(HSeparator.new())
	var bf_hdr := Label.new()
	bf_hdr.text = "Bonus Feats  (DM approved, optional)"
	bf_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	_cf_container.add_child(bf_hdr)

	var bf_desc := Label.new()
	bf_desc.text = "Additional feats granted by your DM outside the ASI budget."
	bf_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	bf_desc.modulate = Color(0.7, 0.7, 0.7)
	bf_desc.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
	_cf_container.add_child(bf_desc)

	var bf_vbox := VBoxContainer.new()
	bf_vbox.add_theme_constant_override("separation", 4)
	_cf_container.add_child(bf_vbox)

	for feat_dict: Variant in _wizard.feats_raw:
		if not feat_dict is Dictionary:
			continue
		var fd: Dictionary = feat_dict as Dictionary
		var feat_nm: String = str(fd.get("name", ""))
		if feat_nm.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		bf_vbox.add_child(row)

		var fcb := CheckBox.new()
		fcb.text = feat_nm
		fcb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var prereq_fail: String = _wizard.check_feat_prerequisite(fd)
		if not prereq_fail.is_empty():
			fcb.disabled = true
			fcb.tooltip_text = prereq_fail
			fcb.modulate = Color(0.5, 0.5, 0.5)
		else:
			fcb.button_pressed = _wizard.bonus_feats.has(feat_nm)
			fcb.toggled.connect(func(on: bool) -> void:
				if on:
					if not _wizard.bonus_feats.has(feat_nm):
						_wizard.bonus_feats.append(feat_nm)
				else:
					_wizard.bonus_feats.erase(feat_nm)
			)
		row.add_child(fcb)

		var feat_info_btn := Button.new()
		feat_info_btn.text = "ℹ"
		feat_info_btn.custom_minimum_size = Vector2(28, 0)
		feat_info_btn.pressed.connect(func() -> void: _wizard.show_feat_detail(fd))
		row.add_child(feat_info_btn)

		var desc_raw: String = str(fd.get("desc", ""))
		if not desc_raw.is_empty():
			var brief: String = desc_raw.get_slice(".", 0).strip_edges() + "."
			if brief.length() > 120:
				brief = brief.left(117) + "..."
			var desc_lbl := Label.new()
			desc_lbl.text = brief
			desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			desc_lbl.modulate = Color(0.6, 0.6, 0.6)
			desc_lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(10.0))
			row.add_child(desc_lbl)

	# ── Custom feats (user-defined) ───────────────────────────────────────
	_cf_container.add_child(HSeparator.new())
	var cf_hdr := Label.new()
	cf_hdr.text = "Custom Feats"
	cf_hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(12.0))
	_cf_container.add_child(cf_hdr)

	var cf_desc := Label.new()
	cf_desc.text = "Add custom or homebrew feats. Each may include an ability score increase."
	cf_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	cf_desc.modulate = Color(0.7, 0.7, 0.7)
	cf_desc.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
	_cf_container.add_child(cf_desc)

	var cf_list_box := VBoxContainer.new()
	cf_list_box.add_theme_constant_override("separation", 8)
	_cf_container.add_child(cf_list_box)
	_rebuild_custom_feats_list(cf_list_box)

	_wizard.reapply_theme()


func validate() -> bool:
	return true


## Rebuild the custom feats list UI inside the given container.
func _rebuild_custom_feats_list(list_box: VBoxContainer) -> void:
	for ch: Node in list_box.get_children():
		ch.queue_free()

	# Render each existing custom feat
	for i: int in _wizard.custom_feats.size():
		var cf: Dictionary = _wizard.custom_feats[i] as Dictionary
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 4)
		list_box.add_child(card)

		# ── Header row: name + remove button ──
		var hdr_row := HBoxContainer.new()
		hdr_row.add_theme_constant_override("separation", 8)
		card.add_child(hdr_row)

		var name_edit := LineEdit.new()
		name_edit.placeholder_text = "Feat name"
		name_edit.text = str(cf.get("name", ""))
		name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_edit.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
		var cf_idx: int = i
		name_edit.text_changed.connect(func(new_text: String) -> void:
			if cf_idx < _wizard.custom_feats.size():
				(_wizard.custom_feats[cf_idx] as Dictionary)["name"] = new_text
		)
		hdr_row.add_child(name_edit)

		var remove_btn := Button.new()
		remove_btn.text = "✕"
		remove_btn.custom_minimum_size = Vector2(28, 0)
		remove_btn.tooltip_text = "Remove this custom feat"
		remove_btn.pressed.connect(func() -> void:
			if cf_idx < _wizard.custom_feats.size():
				_wizard.custom_feats.remove_at(cf_idx)
			_rebuild_custom_feats_list(list_box)
		)
		hdr_row.add_child(remove_btn)

		# ── Description ──
		var desc_edit := TextEdit.new()
		desc_edit.placeholder_text = "Description (optional)"
		desc_edit.text = str(cf.get("desc", ""))
		desc_edit.custom_minimum_size = Vector2(0, 52)
		desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_edit.add_theme_font_size_override("font_size", _wizard.scaled_fs(10.0))
		desc_edit.text_changed.connect(func() -> void:
			if cf_idx < _wizard.custom_feats.size():
				(_wizard.custom_feats[cf_idx] as Dictionary)["desc"] = desc_edit.text
		)
		card.add_child(desc_edit)

		# ── Stat boosts ──
		var asi_arr: Array = []
		var asi_var: Variant = cf.get("asi", [])
		if asi_var is Array:
			asi_arr = asi_var as Array

		var boosts_box := VBoxContainer.new()
		boosts_box.add_theme_constant_override("separation", 4)
		card.add_child(boosts_box)
		_rebuild_custom_feat_boosts(boosts_box, cf_idx, asi_arr)

		card.add_child(HSeparator.new())

	# ── "Add Custom Feat" button ──
	var add_btn := Button.new()
	add_btn.text = "+ Add Custom Feat"
	add_btn.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
	add_btn.pressed.connect(func() -> void:
		_wizard.custom_feats.append({"name": "", "desc": "", "asi": []})
		_rebuild_custom_feats_list(list_box)
	)
	list_box.add_child(add_btn)
	_wizard.reapply_theme()


## Rebuild the stat-boost rows for a single custom feat.
func _rebuild_custom_feat_boosts(box: VBoxContainer, cf_idx: int, asi_arr: Array) -> void:
	for ch: Node in box.get_children():
		ch.queue_free()

	var boost_lbl := Label.new()
	boost_lbl.text = "Stat Boosts (optional)"
	boost_lbl.modulate = Color(0.7, 0.7, 0.7)
	boost_lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(10.0))
	box.add_child(boost_lbl)

	for bi: int in asi_arr.size():
		var entry: Dictionary = asi_arr[bi] as Dictionary
		var boost_row := HBoxContainer.new()
		boost_row.add_theme_constant_override("separation", 6)
		box.add_child(boost_row)

		var ab_opt := OptionButton.new()
		ab_opt.add_item("(ability)")
		for ab_nm: String in WizardConstants.ABILITY_NAMES:
			ab_opt.add_item(ab_nm)
		var saved_ab: String = str(entry.get("ability", ""))
		if not saved_ab.is_empty():
			var ab_i: int = WizardConstants.ABILITY_KEYS.find(saved_ab)
			if ab_i >= 0:
				ab_opt.select(ab_i + 1)
		var boost_idx: int = bi
		ab_opt.item_selected.connect(func(sel_i: int) -> void:
			if cf_idx >= _wizard.custom_feats.size():
				return
			var arr: Variant = (_wizard.custom_feats[cf_idx] as Dictionary).get("asi", [])
			if not (arr is Array) or boost_idx >= (arr as Array).size():
				return
			if sel_i == 0:
				((arr as Array)[boost_idx] as Dictionary)["ability"] = ""
			else:
				((arr as Array)[boost_idx] as Dictionary)["ability"] = WizardConstants.ABILITY_KEYS[sel_i - 1]
		)
		boost_row.add_child(ab_opt)

		var amt_spin := SpinBox.new()
		amt_spin.min_value = -5
		amt_spin.max_value = 5
		amt_spin.step = 1
		amt_spin.value = int(entry.get("amount", 1))
		amt_spin.prefix = "+"
		amt_spin.custom_minimum_size = Vector2(80, 0)
		amt_spin.value_changed.connect(func(val: float) -> void:
			if cf_idx >= _wizard.custom_feats.size():
				return
			var arr: Variant = (_wizard.custom_feats[cf_idx] as Dictionary).get("asi", [])
			if not (arr is Array) or boost_idx >= (arr as Array).size():
				return
			((arr as Array)[boost_idx] as Dictionary)["amount"] = int(val)
		)
		boost_row.add_child(amt_spin)

		var rm_boost_btn := Button.new()
		rm_boost_btn.text = "✕"
		rm_boost_btn.custom_minimum_size = Vector2(24, 0)
		rm_boost_btn.tooltip_text = "Remove this boost"
		rm_boost_btn.pressed.connect(func() -> void:
			if cf_idx >= _wizard.custom_feats.size():
				return
			var arr: Variant = (_wizard.custom_feats[cf_idx] as Dictionary).get("asi", [])
			if arr is Array and boost_idx < (arr as Array).size():
				(arr as Array).remove_at(boost_idx)
			_rebuild_custom_feat_boosts(box, cf_idx, (_wizard.custom_feats[cf_idx] as Dictionary).get("asi", []) as Array)
		)
		boost_row.add_child(rm_boost_btn)

	var add_boost_btn := Button.new()
	add_boost_btn.text = "+ Add Stat Boost"
	add_boost_btn.add_theme_font_size_override("font_size", _wizard.scaled_fs(10.0))
	add_boost_btn.pressed.connect(func() -> void:
		if cf_idx >= _wizard.custom_feats.size():
			return
		var cf: Dictionary = _wizard.custom_feats[cf_idx] as Dictionary
		var arr: Variant = cf.get("asi", [])
		if not (arr is Array):
			arr = []
			cf["asi"] = arr
		(arr as Array).append({"ability": "", "amount": 1})
		_rebuild_custom_feat_boosts(box, cf_idx, arr as Array)
	)
	box.add_child(add_boost_btn)
	_wizard.reapply_theme()


## Build a single ASI-or-Feat slot UI (radio buttons + conditional sub-UI).
func _build_asi_slot(slot_i: int) -> void:
	var slot_box := VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 4)
	_cf_container.add_child(slot_box)

	var hdr := Label.new()
	hdr.text = "ASI Slot %d:" % (slot_i + 1)
	hdr.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
	hdr.modulate = Color(0.9, 0.8, 0.4)
	slot_box.add_child(hdr)

	var choice: Dictionary = _wizard.asi_choices[slot_i] as Dictionary
	var choice_type: String = str(choice.get("type", "none"))

	var bg := ButtonGroup.new()

	var radio_row := HBoxContainer.new()
	radio_row.add_theme_constant_override("separation", 12)
	slot_box.add_child(radio_row)

	var sub_container := VBoxContainer.new()
	sub_container.add_theme_constant_override("separation", 4)
	slot_box.add_child(sub_container)

	var btn_plus2 := Button.new()
	btn_plus2.text = "+2 to one"
	btn_plus2.toggle_mode = true
	btn_plus2.button_group = bg
	btn_plus2.button_pressed = (choice_type == "asi_plus2")
	radio_row.add_child(btn_plus2)

	var btn_plus1x2 := Button.new()
	btn_plus1x2.text = "+1 / +1"
	btn_plus1x2.toggle_mode = true
	btn_plus1x2.button_group = bg
	btn_plus1x2.button_pressed = (choice_type == "asi_plus1x2")
	radio_row.add_child(btn_plus1x2)

	var btn_feat := Button.new()
	btn_feat.text = "Take a Feat"
	btn_feat.toggle_mode = true
	btn_feat.button_group = bg
	btn_feat.button_pressed = (choice_type == "feat")
	radio_row.add_child(btn_feat)

	# Connect radio buttons — each rebuilds sub_container
	btn_plus2.pressed.connect(func() -> void:
		_wizard.asi_choices[slot_i] = {"type": "asi_plus2", "ability": ""}
		_rebuild_asi_sub(sub_container, slot_i)
	)
	btn_plus1x2.pressed.connect(func() -> void:
		_wizard.asi_choices[slot_i] = {"type": "asi_plus1x2", "ability1": "", "ability2": ""}
		_rebuild_asi_sub(sub_container, slot_i)
	)
	btn_feat.pressed.connect(func() -> void:
		_wizard.asi_choices[slot_i] = {"type": "feat", "feat_name": ""}
		_rebuild_asi_sub(sub_container, slot_i)
	)

	# Build initial sub-UI if a choice was already set
	if choice_type != "none":
		_rebuild_asi_sub(sub_container, slot_i)


## Rebuild the conditional sub-UI for a single ASI slot.
func _rebuild_asi_sub(container: VBoxContainer, slot_i: int) -> void:
	for ch: Node in container.get_children():
		ch.queue_free()

	var choice: Dictionary = _wizard.asi_choices[slot_i] as Dictionary
	var choice_type: String = str(choice.get("type", "none"))

	if choice_type == "asi_plus2":
		var opt := OptionButton.new()
		opt.add_item("(choose ability)")
		for ab_nm: String in WizardConstants.ABILITY_NAMES:
			opt.add_item(ab_nm)
		var saved_ab: String = str(choice.get("ability", ""))
		if not saved_ab.is_empty():
			var idx: int = WizardConstants.ABILITY_KEYS.find(saved_ab)
			if idx >= 0:
				opt.select(idx + 1)
		opt.item_selected.connect(func(sel_i: int) -> void:
			if sel_i == 0:
				choice["ability"] = ""
			else:
				choice["ability"] = WizardConstants.ABILITY_KEYS[sel_i - 1]
		)
		container.add_child(opt)

	elif choice_type == "asi_plus1x2":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		container.add_child(row)

		var opt1 := OptionButton.new()
		opt1.add_item("(first ability)")
		for ab_nm: String in WizardConstants.ABILITY_NAMES:
			opt1.add_item(ab_nm)
		var saved_ab1: String = str(choice.get("ability1", ""))
		if not saved_ab1.is_empty():
			var idx1: int = WizardConstants.ABILITY_KEYS.find(saved_ab1)
			if idx1 >= 0:
				opt1.select(idx1 + 1)
		opt1.item_selected.connect(func(sel_i: int) -> void:
			if sel_i == 0:
				choice["ability1"] = ""
			else:
				choice["ability1"] = WizardConstants.ABILITY_KEYS[sel_i - 1]
		)
		row.add_child(opt1)

		var opt2 := OptionButton.new()
		opt2.add_item("(second ability)")
		for ab_nm: String in WizardConstants.ABILITY_NAMES:
			opt2.add_item(ab_nm)
		var saved_ab2: String = str(choice.get("ability2", ""))
		if not saved_ab2.is_empty():
			var idx2: int = WizardConstants.ABILITY_KEYS.find(saved_ab2)
			if idx2 >= 0:
				opt2.select(idx2 + 1)
		opt2.item_selected.connect(func(sel_i: int) -> void:
			if sel_i == 0:
				choice["ability2"] = ""
			else:
				choice["ability2"] = WizardConstants.ABILITY_KEYS[sel_i - 1]
		)
		row.add_child(opt2)

	elif choice_type == "feat":
		var opt := OptionButton.new()
		opt.add_item("(choose feat)")
		var feat_names: Array = []
		var disabled_indices: Array[int] = []
		for fd_var: Variant in _wizard.feats_raw:
			if fd_var is Dictionary:
				var fd: Dictionary = fd_var as Dictionary
				var nm: String = str(fd.get("name", ""))
				if not nm.is_empty():
					feat_names.append(nm)
					var prereq_fail: String = _wizard.check_feat_prerequisite(fd)
					if not prereq_fail.is_empty():
						opt.add_item(nm + "  (" + prereq_fail + ")")
						disabled_indices.append(opt.item_count - 1)
					else:
						opt.add_item(nm)
		for di: int in disabled_indices:
			opt.set_item_disabled(di, true)
		var saved_feat: String = str(choice.get("feat_name", ""))
		if not saved_feat.is_empty():
			var fi: int = feat_names.find(saved_feat)
			if fi >= 0:
				opt.select(fi + 1)

		var feat_choices_box := VBoxContainer.new()
		feat_choices_box.add_theme_constant_override("separation", 4)

		opt.item_selected.connect(func(sel_i: int) -> void:
			if sel_i == 0:
				choice["feat_name"] = ""
				choice["feat_choices"] = []
			else:
				choice["feat_name"] = feat_names[sel_i - 1]
				choice["feat_choices"] = []
			_rebuild_feat_choices(feat_choices_box, choice)
		)
		container.add_child(opt)
		container.add_child(feat_choices_box)

		# Restore saved feat choices sub-UI
		if not saved_feat.is_empty():
			_rebuild_feat_choices(feat_choices_box, choice)
	_wizard.reapply_theme()


## Build sub-pickers for a feat's choices (ability, element, class, etc.).
func _rebuild_feat_choices(box: VBoxContainer, choice: Dictionary) -> void:
	for ch: Node in box.get_children():
		ch.queue_free()

	var feat_nm: String = str(choice.get("feat_name", ""))
	if feat_nm.is_empty():
		return

	# Look up feat data
	var feat_dict: Dictionary = {}
	for fd_var: Variant in _wizard.feats_raw:
		if fd_var is Dictionary:
			var fd: Dictionary = fd_var as Dictionary
			if str(fd.get("name", "")) == feat_nm:
				feat_dict = fd
				break
	if feat_dict.is_empty():
		return

	var choices_raw: Variant = feat_dict.get("choices", [])
	if not (choices_raw is Array) or (choices_raw as Array).is_empty():
		return

	# Ensure feat_choices array exists with right length
	if not choice.has("feat_choices"):
		choice["feat_choices"] = []
	var fc_arr: Array = choice["feat_choices"] as Array
	var choices_arr: Array = choices_raw as Array
	while fc_arr.size() < choices_arr.size():
		fc_arr.append({"selection": ""})

	for ci: int in choices_arr.size():
		var cdef_var: Variant = choices_arr[ci]
		if not (cdef_var is Dictionary):
			continue
		var cdef: Dictionary = cdef_var as Dictionary
		var ctype: String = str(cdef.get("type", ""))
		var clabel: String = str(cdef.get("label", ctype.capitalize()))
		var options_var: Variant = cdef.get("options", [])
		var options: Array = options_var as Array if options_var is Array else []

		if ctype == "ability":
			var lbl := Label.new()
			lbl.text = clabel + ":"
			box.add_child(lbl)
			var ab_opt := OptionButton.new()
			ab_opt.add_item("(choose)")
			for ab_key: Variant in options:
				var ab_idx: int = WizardConstants.ABILITY_KEYS.find(str(ab_key))
				if ab_idx >= 0:
					ab_opt.add_item(WizardConstants.ABILITY_NAMES[ab_idx])
				else:
					ab_opt.add_item(str(ab_key))
			var saved_sel: String = str((fc_arr[ci] as Dictionary).get("selection", ""))
			if not saved_sel.is_empty():
				var si: int = options.find(saved_sel)
				if si >= 0:
					ab_opt.select(si + 1)
			var fc_entry: Dictionary = fc_arr[ci] as Dictionary
			ab_opt.item_selected.connect(func(sel_i: int) -> void:
				if sel_i == 0:
					fc_entry["selection"] = ""
				else:
					fc_entry["selection"] = str(options[sel_i - 1])
			)
			box.add_child(ab_opt)

		elif ctype == "element" or ctype == "language" or ctype == "weapon":
			# Single or multi-select from fixed options
			var count: int = int(cdef.get("count", 1))
			var lbl := Label.new()
			lbl.text = clabel + ":"
			box.add_child(lbl)
			if count <= 1:
				var el_opt := OptionButton.new()
				el_opt.add_item("(choose)")
				for o: Variant in options:
					el_opt.add_item(str(o).capitalize())
				var saved_sel: String = str((fc_arr[ci] as Dictionary).get("selection", ""))
				if not saved_sel.is_empty():
					var si: int = options.find(saved_sel)
					if si >= 0:
						el_opt.select(si + 1)
				var fc_entry: Dictionary = fc_arr[ci] as Dictionary
				el_opt.item_selected.connect(func(sel_i: int) -> void:
					if sel_i == 0:
						fc_entry["selection"] = ""
					else:
						fc_entry["selection"] = str(options[sel_i - 1])
				)
				box.add_child(el_opt)
			else:
				_build_feat_multi_select(box, options, count, fc_arr[ci] as Dictionary)

		elif ctype == "class":
			var lbl := Label.new()
			lbl.text = clabel + ":"
			box.add_child(lbl)
			var cl_opt := OptionButton.new()
			cl_opt.add_item("(choose)")
			for o: Variant in options:
				cl_opt.add_item(str(o).capitalize())
			var saved_sel: String = str((fc_arr[ci] as Dictionary).get("selection", ""))
			if not saved_sel.is_empty():
				var si: int = options.find(saved_sel)
				if si >= 0:
					cl_opt.select(si + 1)
			var fc_entry: Dictionary = fc_arr[ci] as Dictionary
			cl_opt.item_selected.connect(func(sel_i: int) -> void:
				if sel_i == 0:
					fc_entry["selection"] = ""
				else:
					fc_entry["selection"] = str(options[sel_i - 1])
			)
			box.add_child(cl_opt)

		elif ctype == "spell":
			# Spell choices are complex (class-filtered); placeholder for session assignment
			var lbl := Label.new()
			lbl.text = clabel + " — assign spells during your session."
			lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
			lbl.modulate = Color(0.7, 0.7, 0.7)
			box.add_child(lbl)

		elif ctype == "skill_or_tool":
			var count: int = int(cdef.get("count", 1))
			var lbl := Label.new()
			lbl.text = clabel + ":"
			box.add_child(lbl)
			_build_feat_multi_select(box, options, count, fc_arr[ci] as Dictionary)

	_wizard.reapply_theme()


## Multi-select checklist for feat choices (skills, weapons, languages, etc.).
func _build_feat_multi_select(parent: Control, options: Array, max_count: int,
		fc_entry: Dictionary) -> void:
	if not fc_entry.has("selections"):
		fc_entry["selections"] = []
	var selections: Array = fc_entry["selections"] as Array

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 2)
	parent.add_child(grid)

	for o_var: Variant in options:
		var o_str: String = str(o_var)
		var display: String = o_str.replace("-", " ").capitalize()
		var cb := CheckBox.new()
		cb.text = display
		cb.button_pressed = selections.has(o_str)
		cb.toggled.connect(func(on: bool) -> void:
			if on:
				if selections.size() < max_count and not selections.has(o_str):
					selections.append(o_str)
				else:
					cb.set_pressed_no_signal(false)
			else:
				selections.erase(o_str)
		)
		grid.add_child(cb)


## Build a two-column CheckBox grid limited to max_count selections.
func _build_spell_checklist(spells: Array, max_count: int, use_cantrips: bool) -> void:
	if spells.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(Spell list not yet loaded — assign during your session.)"
		none_lbl.add_theme_font_size_override("font_size", _wizard.scaled_fs(11.0))
		none_lbl.modulate = Color(0.7, 0.7, 0.7)
		_cf_container.add_child(none_lbl)
		return

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	_cf_container.add_child(grid)

	for sp: Variant in spells:
		if not (sp is SpellData):
			continue
		var sd := sp as SpellData
		var sp_idx := sd.index

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		grid.add_child(row)

		var cb := CheckBox.new()
		cb.text = sd.name
		cb.button_pressed = (
			_wizard.chosen_cantrips.has(sp_idx) if use_cantrips else _wizard.chosen_spells.has(sp_idx)
		)
		cb.toggled.connect(
			func(on: bool) -> void:
				var target: Array = _wizard.chosen_cantrips if use_cantrips else _wizard.chosen_spells
				if on:
					if target.size() < max_count:
						target.append(sp_idx)
						if use_cantrips:
							if _cantrip_counter_label != null:
								_cantrip_counter_label.text = "  Chosen: %d of %d" % [_wizard.chosen_cantrips.size(), max_count]
						else:
							if _spell_counter_label != null:
								_spell_counter_label.text = "  Chosen: %d of %d" % [_wizard.chosen_spells.size(), max_count]
					else:
						cb.set_pressed_no_signal(false)
				else:
					target.erase(sp_idx)
					if use_cantrips:
						if _cantrip_counter_label != null:
							_cantrip_counter_label.text = "  Chosen: %d of %d" % [_wizard.chosen_cantrips.size(), max_count]
					else:
						if _spell_counter_label != null:
							_spell_counter_label.text = "  Chosen: %d of %d" % [_wizard.chosen_spells.size(), max_count]
		)
		row.add_child(cb)

		var info_btn := Button.new()
		info_btn.text = "ℹ"
		info_btn.custom_minimum_size = Vector2(28, 0)
		info_btn.pressed.connect(func() -> void: _wizard.show_spell_detail(sd))
		row.add_child(info_btn)


func _class_features_text(class_key: String, lvl: int) -> String:
	var lines: Array = []
	match class_key:
		"barbarian":
			var rage_uses: int = 2 + maxi(0, lvl - 2)
			lines = [
				"[b]Hit Die:[/b] d12  |  [b]Saves:[/b] STR, CON",
				"[b]Armor:[/b] Light, Medium, Shields  |  [b]Weapons:[/b] Simple, Martial",
				"[b]Rage:[/b] Bonus action. Advantage on STR checks/saves, resistance to B/P/S. %d uses/long rest." % rage_uses,
				"[b]Unarmored Defense:[/b] AC = 10 + DEX mod + CON mod (no armor).",
			]
			if lvl >= 2:
				lines.append("[b]Reckless Attack:[/b] Advantage on first STR attack; foes gain advantage vs. you.")
				lines.append("[b]Danger Sense:[/b] Advantage on DEX saves vs. visible threats.")
		"bard":
			lines = [
				"[b]Hit Die:[/b] d8  |  [b]Saves:[/b] DEX, CHA",
				"[b]Armor:[/b] Light  |  [b]Weapons:[/b] Simple + hand crossbow / longsword / rapier / shortsword",
				"[b]Bardic Inspiration:[/b] Bonus action. Grant a d6 die (CHA mod uses / long rest).",
				"[b]Spellcasting:[/b] Known cast (CHA). Freely cast any cantrip or known spell.",
			]
			if lvl >= 2:
				lines.append("[b]Jack of All Trades:[/b] Add half proficiency bonus to non-proficient checks.")
				lines.append("[b]Song of Rest:[/b] Allies regain extra 1d6 HP during short rests.")
		"cleric":
			lines = [
				"[b]Hit Die:[/b] d8  |  [b]Saves:[/b] WIS, CHA",
				"[b]Armor:[/b] Light, Medium, Shields  |  [b]Weapons:[/b] Simple",
				"[b]Spellcasting:[/b] Prepared cast (WIS). Prepares WIS mod + level spells each long rest.",
				"[b]Channel Divinity:[/b] 1/rest. Turn Undead + one domain-specific option.",
			]
		"druid":
			lines = [
				"[b]Hit Die:[/b] d8  |  [b]Saves:[/b] INT, WIS",
				"[b]Armor:[/b] Light, Medium, Shields (no metal)  |  [b]Weapons:[/b] Clubs/Daggers/Spears/etc.",
				"[b]Spellcasting:[/b] Prepared cast (WIS). Prepares WIS mod + level spells each long rest.",
			]
			if lvl >= 2:
				lines.append("[b]Wild Shape:[/b] 2/short rest. Transform into a beast (CR \u2264 1/4 at level 2).")
		"fighter":
			lines = [
				"[b]Hit Die:[/b] d10  |  [b]Saves:[/b] STR, CON",
				"[b]Armor:[/b] All armor, Shields  |  [b]Weapons:[/b] Simple, Martial",
				"[b]Fighting Style:[/b] Archery / Defense / Dueling / Great Weapon / Protection / Two-Weapon.",
				"[b]Second Wind:[/b] Bonus action. Regain 1d10 + Fighter level HP (1/short rest).",
			]
			if lvl >= 2:
				lines.append("[b]Action Surge:[/b] Take one extra action on your turn (1/short rest).")
		"monk":
			lines = [
				"[b]Hit Die:[/b] d8  |  [b]Saves:[/b] STR, DEX",
				"[b]Armor:[/b] None  |  [b]Weapons:[/b] Simple, Shortswords",
				"[b]Martial Arts:[/b] Use DEX for unarmed strikes; unarmed die = 1d4 (grows at levels 5/11/17).",
				"[b]Unarmored Defense:[/b] AC = 10 + DEX mod + WIS mod (no armor).",
			]
			if lvl >= 2:
				lines.append("[b]Ki:[/b] %d points. Flurry of Blows / Patient Defense / Step of the Wind." % lvl)
				lines.append("[b]Unarmored Movement:[/b] +10 ft. speed (grows at higher levels).")
		"paladin":
			lines = [
				"[b]Hit Die:[/b] d10  |  [b]Saves:[/b] WIS, CHA",
				"[b]Armor:[/b] All armor, Shields  |  [b]Weapons:[/b] Simple, Martial",
				"[b]Divine Sense:[/b] Detect celestials/fiends/undead within 60 ft. (1 + CHA mod uses / long rest).",
				"[b]Lay on Hands:[/b] Pool of %d HP. Touch to restore HP as an action." % (5 * lvl),
			]
			if lvl >= 2:
				lines.append("[b]Fighting Style:[/b] Choose one combat style.")
				lines.append("[b]Divine Smite:[/b] Expend slot on a hit: 2d8 radiant (+1d8 per slot level above 1st).")
				lines.append("[b]Spellcasting:[/b] Prepared cast (CHA). CHA mod + half Paladin level spells.")
		"ranger":
			lines = [
				"[b]Hit Die:[/b] d10  |  [b]Saves:[/b] STR, DEX",
				"[b]Armor:[/b] Light, Medium, Shields  |  [b]Weapons:[/b] Simple, Martial",
				"[b]Favored Enemy:[/b] Advantage on Survival (track); recall lore about chosen enemy type.",
				"[b]Natural Explorer:[/b] Double proficiency on INT/WIS checks in chosen terrain.",
			]
			if lvl >= 2:
				lines.append("[b]Fighting Style:[/b] Archery / Defense / Dueling / Two-Weapon Fighting.")
				lines.append("[b]Spellcasting:[/b] Known cast (WIS). See chosen spells.")
		"rogue":
			var sneak_dice: int = int(ceil(float(lvl) / 2.0))
			lines = [
				"[b]Hit Die:[/b] d8  |  [b]Saves:[/b] DEX, INT",
				"[b]Armor:[/b] Light  |  [b]Weapons:[/b] Simple + hand crossbow / longsword / rapier / shortsword",
				"[b]Expertise:[/b] Double proficiency on 2 chosen skills (4 at level 6).",
				"[b]Sneak Attack:[/b] Extra %dd6 on one attack/turn when you have advantage or adjacent ally." % sneak_dice,
				"[b]Thieves' Cant:[/b] Secret language of the criminal underworld.",
			]
			if lvl >= 2:
				lines.append("[b]Cunning Action:[/b] Bonus action: Dash, Disengage, or Hide.")
		"sorcerer":
			lines = [
				"[b]Hit Die:[/b] d6  |  [b]Saves:[/b] CON, CHA",
				"[b]Armor:[/b] None  |  [b]Weapons:[/b] Daggers/Darts/Slings/Quarterstaffs/Light crossbows",
				"[b]Spellcasting:[/b] Known cast (CHA). Freely cast any cantrip or known spell.",
			]
			if lvl >= 2:
				lines.append("[b]Font of Magic:[/b] %d sorcery points. Convert spell slots \u2194 sorcery points." % lvl)
		"warlock":
			lines = [
				"[b]Hit Die:[/b] d8  |  [b]Saves:[/b] WIS, CHA",
				"[b]Armor:[/b] Light  |  [b]Weapons:[/b] Simple",
				"[b]Pact Magic:[/b] Slots recharge on SHORT or long rest. Always highest available slot level.",
				"[b]Spellcasting:[/b] Known cast (CHA). Fixed known spells + patron expanded list.",
			]
			if lvl >= 2:
				lines.append("[b]Eldritch Invocations:[/b] Choose 2 invocations that enhance your magic.")
		"wizard":
			lines = [
				"[b]Hit Die:[/b] d6  |  [b]Saves:[/b] INT, WIS",
				"[b]Armor:[/b] None  |  [b]Weapons:[/b] Daggers/Darts/Slings/Quarterstaffs/Light crossbows",
				"[b]Spellbook:[/b] Contains spells you have learned. Grows as you adventure.",
				"[b]Spell Preparation:[/b] Memorise INT mod + Wizard level spells from spellbook each long rest.",
				"[b]Arcane Recovery:[/b] 1/day on short rest: regain slots totalling \u2264 half Wizard level (min 1).",
			]
		_:
			lines = ["(No feature summary available for this class.)"]
	return "\n".join(lines)
