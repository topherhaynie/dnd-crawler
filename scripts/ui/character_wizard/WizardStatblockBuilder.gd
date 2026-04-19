extends RefCounted

const _CFR := preload("res://scripts/ui/character_wizard/ClassFeatureResolver.gd")

# -----------------------------------------------------------------------------
# WizardStatblockBuilder — assembles a StatblockData from wizard state.
# Extracted from the monolithic CharacterWizard._build_statblock().
# -----------------------------------------------------------------------------


static func build(w: CharacterWizard) -> StatblockData:
	var sb := StatblockData.new()
	sb.id = StatblockData.generate_id()
	sb.name = w.char_name.strip_edges()
	sb.source = "campaign"
	sb.ruleset = w.ruleset

	sb.race = w.get_display_race_name()
	sb.class_name_str = w.get_selected_class_name()
	sb.level = w.level
	sb.classes = w.get_classes_array()
	if w.ruleset == "2014":
		sb.background = WizardConstants.BACKGROUNDS[w.background]
	else:
		sb.background = "(see table — 2024 rules)"

	## ── Ability scores (base + racial ASI) ───────────────────────────────
	sb.strength = w.scores[0]
	sb.dexterity = w.scores[1]
	sb.constitution = w.scores[2]
	sb.intelligence = w.scores[3]
	sb.wisdom = w.scores[4]
	sb.charisma = w.scores[5]
	var asi: Dictionary = w.get_total_race_asi()
	var ability_setter: Dictionary = {
		"str": func(v: int) -> void: sb.strength = v,
		"dex": func(v: int) -> void: sb.dexterity = v,
		"con": func(v: int) -> void: sb.constitution = v,
		"int": func(v: int) -> void: sb.intelligence = v,
		"wis": func(v: int) -> void: sb.wisdom = v,
		"cha": func(v: int) -> void: sb.charisma = v,
	}
	var ability_getter: Dictionary = {
		"str": func() -> int: return sb.strength,
		"dex": func() -> int: return sb.dexterity,
		"con": func() -> int: return sb.constitution,
		"int": func() -> int: return sb.intelligence,
		"wis": func() -> int: return sb.wisdom,
		"cha": func() -> int: return sb.charisma,
	}
	# Apply racial ASI
	for ab_key: String in asi.keys():
		if ability_getter.has(ab_key) and ability_setter.has(ab_key):
			var current: int = (ability_getter[ab_key] as Callable).call()
			(ability_setter[ab_key] as Callable).call(current + int(asi[ab_key]))
	# Apply ASI slot bonuses (from class ASI/feat choices)
	var asi_bonuses: Dictionary = w.get_asi_choice_bonuses()
	for ab_key: String in asi_bonuses.keys():
		if ability_getter.has(ab_key) and ability_setter.has(ab_key):
			var current: int = (ability_getter[ab_key] as Callable).call()
			(ability_setter[ab_key] as Callable).call(current + int(asi_bonuses[ab_key]))

	## ── Gather chosen feats' SRD data ────────────────────────────────────
	var chosen_feat_dicts: Array[Dictionary] = []
	for feat_nm: String in w.get_all_chosen_feat_names():
		for fd_var: Variant in w.feats_raw:
			if fd_var is Dictionary:
				var fd: Dictionary = fd_var as Dictionary
				if str(fd.get("name", "")) == feat_nm:
					chosen_feat_dicts.append(fd)
					break

	## ── Hit points (Hill Dwarf hp_bonus_per_level applies here) ──────────
	var hit_die: int = w.get_selected_hit_die()
	sb.hit_dice = "%dd%d" % [w.level, hit_die]
	var hp_bonus_per_lvl: int = int(w.get_subrace_dict().get("hp_bonus_per_level", 0))
	var feat_hp_per_lvl: int = 0
	for fd: Dictionary in chosen_feat_dicts:
		feat_hp_per_lvl += int(fd.get("hp_per_level", 0))
	var total_hp_per_lvl: int = hp_bonus_per_lvl + feat_hp_per_lvl
	sb.hit_points_roll = "%dd%d+%d" % [w.level, hit_die,
			w.level * sb.get_modifier("con")]
	var con_mod: int = sb.get_modifier("con")
	sb.hit_points = hit_die + con_mod + total_hp_per_lvl \
			+ (w.level - 1) * (int(ceil(hit_die / 2.0)) + 1 + con_mod + total_hp_per_lvl)
	if sb.hit_points < 1:
		sb.hit_points = 1

	## ── AC ───────────────────────────────────────────────────────────────
	var dex_mod: int = sb.get_modifier("dex")
	var feat_ac_bonus: int = 0
	for fd: Dictionary in chosen_feat_dicts:
		feat_ac_bonus += int(fd.get("ac_bonus", 0))
	sb.armor_class = [ {"type": "natural", "value": 10 + dex_mod + feat_ac_bonus}]

	## ── Speed (subrace may override base) ────────────────────────────────
	var feat_speed_bonus: int = 0
	for fd: Dictionary in chosen_feat_dicts:
		feat_speed_bonus += int(fd.get("speed_bonus", 0))
	sb.speed = {"walk": "%d ft." % (w.get_racial_speed() + feat_speed_bonus)}

	## ── Proficiency bonus ────────────────────────────────────────────────
	sb.proficiency_bonus = WizardConstants.proficiency_bonus_for_level(w.level)

	## ── Saving throws from class ─────────────────────────────────────────
	sb.saving_throws = w.get_selected_class_saves()

	# Feat-granted save proficiencies (e.g. Resilient)
	for fd: Dictionary in chosen_feat_dicts:
		var feat_nm: String = str(fd.get("name", ""))
		var fc_var: Variant = fd.get("choices", [])
		if not (fc_var is Array):
			continue
		for cdef_var: Variant in fc_var as Array:
			if not (cdef_var is Dictionary):
				continue
			var cdef: Dictionary = cdef_var as Dictionary
			if cdef.get("grants_save_proficiency", false):
				var resolved_ab: String = _resolve_feat_choice_ability(w, feat_nm)
				if not resolved_ab.is_empty():
					var ab_idx: int = WizardConstants.ABILITY_KEYS.find(resolved_ab)
					var save_name: String = WizardConstants.ABILITY_NAMES[ab_idx] \
							if ab_idx >= 0 else resolved_ab.capitalize()
					if not sb.saving_throws.has(save_name):
						sb.saving_throws.append(save_name)

	## ── Skill proficiencies (background + racial fixed + class choices + racial free)
	var skill_profs: Array = []
	if w.ruleset == "2014":
		var bg_nm2: String = WizardConstants.BACKGROUNDS[w.background]
		var bg_p_var: Variant = WizardConstants.BACKGROUND_PROFS.get(bg_nm2, [])
		if bg_p_var is Array:
			for sk: Variant in bg_p_var as Array:
				skill_profs.append({"proficiency": {"index": str(sk).to_lower().replace(" ", "-"), "name": str(sk)}, "value": 2})
	var race_p_var: Variant = w.get_race_dict().get("prof_skills", [])
	if race_p_var is Array:
		for sk: Variant in race_p_var as Array:
			var sk_str: String = str(sk)
			var already: bool = skill_profs.any(func(e: Dictionary) -> bool: return str(e.get("proficiency", {}).get("name", "")) == sk_str)
			if not already:
				skill_profs.append({"proficiency": {"index": sk_str.to_lower().replace(" ", "-"), "name": sk_str}, "value": 2})
	for sk: Variant in w.chosen_skills:
		skill_profs.append({"proficiency": {"index": str(sk).to_lower().replace(" ", "-"), "name": str(sk)}, "value": 2})
	for sk: Variant in w.chosen_racial_skills:
		var sk_str2: String = str(sk)
		var already2: bool = skill_profs.any(func(e: Dictionary) -> bool: return str(e.get("proficiency", {}).get("name", "")) == sk_str2)
		if not already2:
			skill_profs.append({"proficiency": {"index": sk_str2.to_lower().replace(" ", "-"), "name": sk_str2}, "value": 2})
	if not skill_profs.is_empty():
		sb.proficiencies = skill_profs

	## ── Class starting proficiencies (armor, weapon, tool) from SRD ──────
	if w.class_index >= 0 and w.class_index < w.classes_raw.size():
		var raw_c: Variant = w.classes_raw[w.class_index]
		if raw_c is Dictionary:
			var cls_profs_var: Variant = (raw_c as Dictionary).get("proficiencies", [])
			if cls_profs_var is Array:
				for cp_var: Variant in cls_profs_var as Array:
					if not (cp_var is Dictionary):
						continue
					var cp: Dictionary = cp_var as Dictionary
					var cp_idx: String = str(cp.get("index", ""))
					var cp_name: String = str(cp.get("name", ""))
					## Skip saving throw proficiencies (handled separately)
					if cp_idx.begins_with("saving-throw"):
						continue
					## Skip skill proficiencies (handled by skill toggles)
					if cp_idx.begins_with("skill-"):
						continue
					var cls_already: bool = sb.proficiencies.any(
						func(e: Dictionary) -> bool:
							return str(e.get("proficiency", {}).get("index", "")) == cp_idx
					)
					if not cls_already:
						sb.proficiencies.append({
							"proficiency": {"index": cp_idx, "name": cp_name},
							"value": 1,
						})

	## ── Racial weapon/tool proficiencies from RACE_DATA / SUBRACE_DATA ───
	var _race_wpns: Variant = w.get_race_dict().get("prof_weapons", [])
	if _race_wpns is Array:
		for rpw: Variant in _race_wpns as Array:
			var rpw_name: String = str(rpw)
			if rpw_name.is_empty():
				continue
			var rpw_idx: String = rpw_name.to_lower().replace(" ", "-")
			var rpw_already: bool = sb.proficiencies.any(
				func(e: Dictionary) -> bool:
					return str(e.get("proficiency", {}).get("index", "")) == rpw_idx
			)
			if not rpw_already:
				sb.proficiencies.append({
					"proficiency": {"index": rpw_idx, "name": rpw_name},
					"value": 1,
				})
	var _subrace_wpns: Variant = w.get_subrace_dict().get("prof_weapons", [])
	if _subrace_wpns is Array:
		for spw: Variant in _subrace_wpns as Array:
			var spw_name: String = str(spw)
			if spw_name.is_empty():
				continue
			var spw_idx: String = spw_name.to_lower().replace(" ", "-")
			var spw_already: bool = sb.proficiencies.any(
				func(e: Dictionary) -> bool:
					return str(e.get("proficiency", {}).get("index", "")) == spw_idx
			)
			if not spw_already:
				sb.proficiencies.append({
					"proficiency": {"index": spw_idx, "name": spw_name},
					"value": 1,
				})

	## ── Feat proficiencies (armor, weapon, tool) ─────────────────────────
	for fd: Dictionary in chosen_feat_dicts:
		var feat_profs_var: Variant = fd.get("proficiencies", [])
		if feat_profs_var is Array:
			for p_var: Variant in feat_profs_var as Array:
				if p_var is Dictionary:
					var p: Dictionary = p_var as Dictionary
					sb.proficiencies.append({
						"proficiency": {"index": str(p.get("index", "")), "name": str(p.get("name", ""))},
						"value": 1,
					})

	## ── Multiclass proficiency grants (from SRD multi_classing.proficiencies) ──
	for ec: Variant in w.extra_classes:
		if not (ec is Dictionary):
			continue
		var ci: int = int((ec as Dictionary).get("class_index", -1))
		if ci < 0 or ci >= w.classes_raw.size():
			continue
		var raw_c: Variant = w.classes_raw[ci]
		if not (raw_c is Dictionary):
			continue
		var mc_var: Variant = (raw_c as Dictionary).get("multi_classing", {})
		if not (mc_var is Dictionary):
			continue
		var mc_profs_var: Variant = (mc_var as Dictionary).get("proficiencies", [])
		if not (mc_profs_var is Array):
			continue
		for mp_var: Variant in mc_profs_var as Array:
			if mp_var is Dictionary:
				var mp: Dictionary = mp_var as Dictionary
				var mp_name: String = str(mp.get("name", ""))
				if not mp_name.is_empty():
					var mp_idx: String = mp_name.to_lower().replace(" ", "-")
					var mc_already: bool = sb.proficiencies.any(
						func(e: Dictionary) -> bool:
							return str(e.get("proficiency", {}).get("name", "")) == mp_name
					)
					if not mc_already:
						sb.proficiencies.append({
							"proficiency": {"index": mp_idx, "name": mp_name},
							"value": 1,
						})

	## ── Senses (darkvision from race/subrace) ────────────────────────────
	var dv: int = w.get_racial_darkvision()
	var passive_bonus: int = 0
	for fd: Dictionary in chosen_feat_dicts:
		passive_bonus += int(fd.get("passive_perception_bonus", 0))
	sb.senses = {"passive_perception": 10 + sb.get_modifier("wis") + passive_bonus}
	if dv > 0:
		sb.senses["darkvision"] = "%d ft." % dv

	sb.creature_type = "humanoid"
	sb.size = w.get_selected_race_size()

	## ── Languages ────────────────────────────────────────────────────────
	sb.languages = ", ".join(w.get_all_languages())

	## ── Damage resistances ───────────────────────────────────────────────
	sb.damage_resistances = w.get_racial_damage_resistances()

	## ── Spell list (class spells + racial cantrips + levelled racial spells)
	var all_spells: Array = []
	all_spells.append_array(w.get_racial_spell_indices())
	all_spells.append_array(w.get_racial_levelled_spells())
	all_spells.append_array(w.chosen_cantrips)
	all_spells.append_array(w.chosen_spells)
	for fd: Dictionary in chosen_feat_dicts:
		var feat_spells_var: Variant = fd.get("granted_spells", [])
		if feat_spells_var is Array:
			for sp_var: Variant in feat_spells_var as Array:
				var sp_idx: String = str(sp_var)
				if not sp_idx.is_empty() and not all_spells.has(sp_idx):
					all_spells.append(sp_idx)
	if not all_spells.is_empty():
		sb.spell_list = all_spells

	## ── Features (race + auto class + choices + feats) ───────────────────
	var all_features: Array = w.get_racial_features()

	# Auto-resolve level-appropriate class features from the progression table.
	var auto_class_features: Array = _CFR.resolve_multiclass(sb.classes)

	# Choice-based features override the generic auto-resolved version of the
	# same feature name (e.g. the wizard picks a specific Favored Enemy, which
	# replaces the generic Favored Enemy description from the table).
	var choice_overrides: Dictionary = {}
	if not w.chosen_fighting_style.is_empty():
		choice_overrides["Fighting Style"] = {"name": "Fighting Style", "desc": w.chosen_fighting_style, "source": "class"}
	if not w.ranger_favored_enemy.is_empty():
		choice_overrides["Favored Enemy"] = {"name": "Favored Enemy", "desc": w.ranger_favored_enemy, "source": "class"}
	if not w.ranger_terrain.is_empty():
		choice_overrides["Natural Explorer"] = {"name": "Natural Explorer", "desc": "Favored terrain: " + w.ranger_terrain, "source": "class"}
	if not w.rogue_expertise_skills.is_empty():
		choice_overrides["Expertise"] = {"name": "Expertise", "desc": "Double proficiency: " + ", ".join(w.rogue_expertise_skills), "source": "class"}
	if not w.chosen_invocations.is_empty():
		choice_overrides["Eldritch Invocations"] = {"name": "Eldritch Invocations", "desc": ", ".join(w.chosen_invocations), "source": "class"}
	if not w.chosen_pact_boon.is_empty():
		choice_overrides["Pact Boon"] = {"name": "Pact Boon", "desc": w.chosen_pact_boon, "source": "class"}

	# Merge auto features — substitute choice overrides where they exist.
	var applied_overrides: Dictionary = {}
	for af: Dictionary in auto_class_features:
		var af_name: String = str(af.get("name", ""))
		if choice_overrides.has(af_name):
			all_features.append(choice_overrides[af_name])
			applied_overrides[af_name] = true
		else:
			all_features.append(af)

	# Append any choice overrides that didn't match an auto feature (safety net).
	for co_key: String in choice_overrides.keys():
		if not applied_overrides.has(co_key):
			all_features.append(choice_overrides[co_key])

	# Subclass as its own entry.
	if not w.selected_subclass.is_empty():
		all_features.append({"name": "Subclass", "desc": w.selected_subclass, "source": "subclass"})
	if not w.dragonborn_ancestry.is_empty():
		var anc_resist: String = "fire"
		if w.dragonborn_ancestry.contains("Acid"):
			anc_resist = "acid"
		elif w.dragonborn_ancestry.contains("Lightning"):
			anc_resist = "lightning"
		elif w.dragonborn_ancestry.contains("Cold"):
			anc_resist = "cold"
		elif w.dragonborn_ancestry.contains("Poison"):
			anc_resist = "poison"
		all_features.append({"name": "Draconic Ancestry", "desc": w.dragonborn_ancestry, "source": "race"})
		if not sb.damage_resistances.has(anc_resist):
			sb.damage_resistances.append(anc_resist)
	for fd: Dictionary in chosen_feat_dicts:
		var feat_nm: String = str(fd.get("name", ""))
		# Overall feat entry with full description
		all_features.append({"name": "Feat: " + feat_nm, "desc": str(fd.get("desc", feat_nm)), "source": "feat"})
		# Feat sub-features (named mechanical abilities)
		var feat_features_var: Variant = fd.get("features", [])
		if feat_features_var is Array:
			for ff_var: Variant in feat_features_var as Array:
				if ff_var is Dictionary:
					var ff: Dictionary = ff_var as Dictionary
					all_features.append({
						"name": str(ff.get("name", "")),
						"desc": str(ff.get("desc", "")),
						"source": "feat",
					})
		# Initiative bonus — store on statblock and as a feature entry.
		var init_bonus: int = int(fd.get("initiative_bonus", 0))
		if init_bonus != 0:
			sb.initiative_bonus += init_bonus
			all_features.append({
				"name": "Initiative Bonus",
				"desc": "+%d to initiative (from %s)" % [init_bonus, feat_nm],
				"source": "feat",
			})
	# Custom feats — add as features (ASI already applied via get_asi_choice_bonuses)
	for cf_var: Variant in w.custom_feats:
		if not (cf_var is Dictionary):
			continue
		var cf: Dictionary = cf_var as Dictionary
		var cf_name: String = str(cf.get("name", "")).strip_edges()
		if cf_name.is_empty():
			continue
		var cf_desc: String = str(cf.get("desc", ""))
		var asi_parts: Array = []
		var cf_asi_var: Variant = cf.get("asi", [])
		if cf_asi_var is Array:
			for entry_var: Variant in cf_asi_var as Array:
				if entry_var is Dictionary:
					var entry: Dictionary = entry_var as Dictionary
					var ab: String = str(entry.get("ability", ""))
					var amt: int = int(entry.get("amount", 0))
					if not ab.is_empty() and amt != 0:
						var sign_str: String = "+" if amt > 0 else ""
						asi_parts.append("%s%d %s" % [sign_str, amt, ab.to_upper()])
		if not asi_parts.is_empty():
			var boost_note: String = "  [Stat boost: %s]" % ", ".join(asi_parts)
			cf_desc = cf_desc + boost_note if not cf_desc.is_empty() else boost_note.strip_edges()
		all_features.append({"name": "Feat: " + cf_name, "desc": cf_desc, "source": "feat"})
	if not all_features.is_empty():
		sb.features = all_features

	## ── Spell slots (supports multiclass computation) ────────────────────
	sb.spell_slots = WizardConstants.compute_spell_slots(sb.classes, w.ruleset)

	return sb


## Look up the resolved ability key for a feat's "choice" ASI from wizard state.
static func _resolve_feat_choice_ability(w: CharacterWizard, feat_nm: String) -> String:
	for choice_var: Variant in w.asi_choices:
		if not (choice_var is Dictionary):
			continue
		var c: Dictionary = choice_var as Dictionary
		if str(c.get("type", "")) != "feat":
			continue
		if str(c.get("feat_name", "")) != feat_nm:
			continue
		var fc_var: Variant = c.get("feat_choices", [])
		if not (fc_var is Array):
			return ""
		for fc_entry_var: Variant in fc_var as Array:
			if not (fc_entry_var is Dictionary):
				continue
			var sel: String = str((fc_entry_var as Dictionary).get("selection", ""))
			# Return the first ability-like selection (3-letter key)
			if sel.length() == 3 and WizardConstants.ABILITY_KEYS.has(sel):
				return sel
	return ""
