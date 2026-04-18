extends VBoxContainer

# -----------------------------------------------------------------------------
# WizardStepReview — Step 6: Summary and optional profile link.
# -----------------------------------------------------------------------------

var _wizard: CharacterWizard = null

var _review_label: RichTextLabel = null
var _profile_option: OptionButton = null
var _profile_ids: Array = []


func _init(wizard: CharacterWizard) -> void:
	_wizard = wizard
	name = "StepReview"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	_build()


func _build() -> void:
	var review_scroll := ScrollContainer.new()
	review_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	review_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(review_scroll)

	_review_label = RichTextLabel.new()
	_review_label.bbcode_enabled = true
	_review_label.fit_content = true
	_review_label.scroll_active = false
	_review_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	review_scroll.add_child(_review_label)

	var link_lbl := Label.new()
	link_lbl.text = "Link to player profile (optional):"
	add_child(link_lbl)

	_profile_option = OptionButton.new()
	add_child(_profile_option)


func get_selected_profile_index() -> int:
	if _profile_option == null:
		return -1
	return _profile_option.selected


func get_profile_ids() -> Array:
	return _profile_ids


func populate_review() -> void:
	if _review_label == null:
		return

	var race_name: String = _wizard.get_display_race_name()
	var class_name_str: String = _wizard.get_selected_class_name()
	var bg_text: String = (
		WizardConstants.BACKGROUNDS[_wizard.background] if _wizard.ruleset == "2014"
		else "(see table — 2024 rules)"
	)

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[b]Ruleset:[/b] %s" % _wizard.ruleset)
	lines.append("[b]Name:[/b] %s" % _wizard.char_name)
	lines.append("[b]Race:[/b] %s" % race_name)
	lines.append("[b]Class:[/b] %s (Level %d)" % [class_name_str, _wizard.level])
	if not _wizard.selected_subclass.is_empty():
		lines.append("[b]Subclass:[/b] %s" % _wizard.selected_subclass)
	lines.append("[b]Background:[/b] %s" % bg_text)

	# Proficiency summary
	var all_prof_skills: Array = []
	if _wizard.ruleset == "2014":
		var bg_profs_var2: Variant = WizardConstants.BACKGROUND_PROFS.get(bg_text, [])
		if bg_profs_var2 is Array:
			all_prof_skills.append_array(bg_profs_var2 as Array)
	var race_profs_var2: Variant = _wizard.get_race_dict().get("prof_skills", [])
	if race_profs_var2 is Array:
		for rsk: Variant in race_profs_var2 as Array:
			if not all_prof_skills.has(str(rsk)):
				all_prof_skills.append(str(rsk))
	all_prof_skills.append_array(_wizard.chosen_skills)
	all_prof_skills.append_array(_wizard.chosen_racial_skills)
	if not all_prof_skills.is_empty():
		lines.append("[b]Skill Proficiencies:[/b] %s" % ", ".join(all_prof_skills))
	lines.append("")

	# Ability scores
	var race_asi: Dictionary = _wizard.get_total_race_asi()
	lines.append("[b]Ability Scores:[/b]  (base + ancestry → total)")
	for i: int in 6:
		var key: String = WizardConstants.ABILITY_KEYS[i]
		var race_bonus: int = int(race_asi.get(key, 0))
		var final_score: int = _wizard.scores[i] + race_bonus
		var mod: int = int(floor((float(final_score) - 10.0) / 2.0))
		var mod_str: String = "+%d" % mod if mod >= 0 else str(mod)
		if race_bonus != 0:
			lines.append("  %s: %d [color=lime](+%d)[/color] → [b]%d[/b] (%s)" % [WizardConstants.ABILITY_NAMES[i], _wizard.scores[i], race_bonus, final_score, mod_str])
		else:
			lines.append("  %s: [b]%d[/b] (%s)" % [WizardConstants.ABILITY_NAMES[i], final_score, mod_str])
	lines.append("")

	# Race mechanics
	var dv: int = _wizard.get_racial_darkvision()
	if dv > 0:
		lines.append("[b]Darkvision:[/b] %d ft." % dv)
	var langs: Array = _wizard.get_all_languages()
	if not langs.is_empty():
		lines.append("[b]Languages:[/b] %s" % ", ".join(langs))
	var resists: Array = _wizard.get_racial_damage_resistances()
	if not resists.is_empty():
		lines.append("[b]Damage Resistances:[/b] %s" % ", ".join(resists))
	var hp_bonus: int = int(_wizard.get_subrace_dict().get("hp_bonus_per_level", 0))
	if hp_bonus > 0:
		lines.append("[b]HP Bonus per Level:[/b] +%d (Dwarven Toughness)" % hp_bonus)
	lines.append("")

	# Class feature choices
	if not _wizard.chosen_fighting_style.is_empty():
		lines.append("[b]Fighting Style:[/b] %s" % _wizard.chosen_fighting_style)
	if not _wizard.ranger_favored_enemy.is_empty():
		lines.append("[b]Favored Enemy:[/b] %s" % _wizard.ranger_favored_enemy)
	if not _wizard.ranger_terrain.is_empty():
		lines.append("[b]Natural Explorer:[/b] %s" % _wizard.ranger_terrain)
	if not _wizard.rogue_expertise_skills.is_empty():
		lines.append("[b]Expertise:[/b] %s" % ", ".join(_wizard.rogue_expertise_skills))
	if not _wizard.chosen_invocations.is_empty():
		lines.append("[b]Eldritch Invocations:[/b] %s" % ", ".join(_wizard.chosen_invocations))
	if not _wizard.chosen_pact_boon.is_empty():
		lines.append("[b]Pact Boon:[/b] %s" % _wizard.chosen_pact_boon)
	if not _wizard.dragonborn_ancestry.is_empty():
		lines.append("[b]Draconic Ancestry:[/b] %s" % _wizard.dragonborn_ancestry)
	# ASI slot choices
	var asi_summary_parts: Array = []
	for choice: Variant in _wizard.asi_choices:
		if not choice is Dictionary:
			continue
		var c: Dictionary = choice as Dictionary
		var t: String = str(c.get("type", "none"))
		match t:
			"asi_plus2":
				var ab: String = str(c.get("ability", ""))
				if not ab.is_empty():
					asi_summary_parts.append("+2 %s" % ab.to_upper())
			"asi_plus1x2":
				var ab1: String = str(c.get("ability1", ""))
				var ab2: String = str(c.get("ability2", ""))
				if not ab1.is_empty() and not ab2.is_empty():
					asi_summary_parts.append("+1 %s, +1 %s" % [ab1.to_upper(), ab2.to_upper()])
			"feat":
				var fn: String = str(c.get("feat_name", ""))
				if not fn.is_empty():
					asi_summary_parts.append("Feat: %s" % fn)
	if not asi_summary_parts.is_empty():
		lines.append("[b]ASI Choices:[/b] %s" % " | ".join(asi_summary_parts))
	var all_feat_names: Array = _wizard.get_all_chosen_feat_names()
	if not all_feat_names.is_empty():
		lines.append("[b]Feats:[/b] %s" % ", ".join(all_feat_names))
	# Custom feat details (show stat boosts)
	for cf_var: Variant in _wizard.custom_feats:
		if not (cf_var is Dictionary):
			continue
		var cf: Dictionary = cf_var as Dictionary
		var cf_name: String = str(cf.get("name", "")).strip_edges()
		if cf_name.is_empty():
			continue
		var parts: Array = []
		var cf_asi_var: Variant = cf.get("asi", [])
		if cf_asi_var is Array:
			for entry_var: Variant in cf_asi_var as Array:
				if entry_var is Dictionary:
					var entry: Dictionary = entry_var as Dictionary
					var ab: String = str(entry.get("ability", ""))
					var amt: int = int(entry.get("amount", 0))
					if not ab.is_empty() and amt != 0:
						var sign_str: String = "+" if amt > 0 else ""
						parts.append("%s%d %s" % [sign_str, amt, ab.to_upper()])
		var boost_text: String = " (%s)" % ", ".join(parts) if not parts.is_empty() else ""
		lines.append("[b]  Custom Feat:[/b] %s%s" % [cf_name, boost_text])

	lines.append("[b]Hit Die:[/b] d%d" % _wizard.get_selected_hit_die())

	var all_cantrips: Array = []
	all_cantrips.append_array(_wizard.get_racial_spell_indices())
	all_cantrips.append_array(_wizard.chosen_cantrips)
	if not all_cantrips.is_empty():
		lines.append("[b]Cantrips:[/b] %s" % ", ".join(all_cantrips))

	var all_levelled: Array = []
	all_levelled.append_array(_wizard.get_racial_levelled_spells())
	all_levelled.append_array(_wizard.chosen_spells)
	if not all_levelled.is_empty():
		var spell_label: String = (
			"Spellbook" if _wizard.get_class_data_value("spell_type") == "spellbook"
			else "Spells"
		)
		lines.append("[b]%s:[/b] %s" % [spell_label, ", ".join(all_levelled)])

	_review_label.text = "\n".join(lines)
	_populate_profile_option()


func _populate_profile_option() -> void:
	if _profile_option == null:
		return
	_profile_option.clear()
	_profile_ids.clear()
	_profile_option.add_item("(none — create without linking)")
	_profile_ids.append("")

	var registry := _wizard.get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.profile == null:
		return
	for p: Variant in registry.profile.get_profiles():
		if p is PlayerProfile:
			var prof := p as PlayerProfile
			_profile_option.add_item(prof.player_name)
			_profile_ids.append(prof.id)

	var idx: int = _profile_ids.find(_wizard.link_profile_id)
	if idx >= 0:
		_profile_option.select(idx)
