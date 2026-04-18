extends PanelContainer

# -----------------------------------------------------------------------------
# WizardDetailPanel — shared right-side detail preview for spells, feats,
# and invocations inside the character creation wizard.
# -----------------------------------------------------------------------------

var _wizard: CharacterWizard = null
var _title_label: Label = null
var _body: RichTextLabel = null
var _close_btn: Button = null


func _init(wizard: CharacterWizard) -> void:
	_wizard = wizard
	name = "DetailPanel"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(280, 0)
	visible = false
	_build()


func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	vbox.add_child(header)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.add_theme_font_size_override("font_size", _wizard.scaled_fs(13.0))
	header.add_child(_title_label)

	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.pressed.connect(func() -> void: hide())
	header.add_child(_close_btn)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)


## Show spell details in BBCode format.
func show_spell(sd: SpellData) -> void:
	_title_label.text = sd.name
	var lines: Array = []
	var level_str: String = "Cantrip" if sd.level == 0 else "%s-level" % WizardConstants.spell_level_ordinal(sd.level)
	lines.append("[b]%s[/b] %s" % [level_str, sd.school])
	if sd.ritual:
		lines.append("[i](Ritual)[/i]")
	lines.append("")
	lines.append("[b]Casting Time:[/b] %s" % sd.casting_time)
	lines.append("[b]Range:[/b] %s" % sd.spell_range)
	var comp_str: String = ", ".join(sd.components)
	if not sd.material.is_empty():
		comp_str += " (%s)" % sd.material
	lines.append("[b]Components:[/b] %s" % comp_str)
	var dur: String = sd.duration
	if sd.concentration:
		dur = "Concentration, " + dur
	lines.append("[b]Duration:[/b] %s" % dur)
	if not sd.area_of_effect.is_empty():
		var aoe_type: String = str(sd.area_of_effect.get("type", ""))
		var aoe_size: int = int(sd.area_of_effect.get("size", 0))
		if aoe_size > 0:
			lines.append("[b]Area:[/b] %d-ft %s" % [aoe_size, aoe_type])
	lines.append("")
	lines.append(sd.desc)
	if not sd.higher_level.is_empty():
		lines.append("")
		lines.append("[b]At Higher Levels.[/b] %s" % sd.higher_level)
	_body.text = "\n".join(lines)
	visible = true
	_wizard.reapply_theme()


## Show feat details in BBCode format.
func show_feat(feat_dict: Dictionary) -> void:
	var feat_nm: String = str(feat_dict.get("name", ""))
	_title_label.text = feat_nm
	var lines: Array = []
	var prereq: String = str(feat_dict.get("prerequisite", ""))
	if not prereq.is_empty():
		lines.append("[b]Prerequisite:[/b] %s" % prereq)
		lines.append("")
	lines.append(str(feat_dict.get("desc", "")))
	# Mechanical effects summary
	var effects: Array = []
	var asi_var: Variant = feat_dict.get("asi", [])
	if asi_var is Array:
		for entry: Variant in asi_var as Array:
			if entry is Dictionary:
				var ab: String = str((entry as Dictionary).get("ability", ""))
				var amt: int = int((entry as Dictionary).get("amount", 0))
				if amt != 0:
					effects.append("+%d %s" % [amt, ab.to_upper()])
	var ac_b: int = int(feat_dict.get("ac_bonus", 0))
	if ac_b != 0:
		effects.append("+%d AC" % ac_b)
	var hp_b: int = int(feat_dict.get("hp_per_level", 0))
	if hp_b != 0:
		effects.append("+%d HP per level" % hp_b)
	var spd_b: int = int(feat_dict.get("speed_bonus", 0))
	if spd_b != 0:
		effects.append("+%d ft. speed" % spd_b)
	var init_b: int = int(feat_dict.get("initiative_bonus", 0))
	if init_b != 0:
		effects.append("+%d initiative" % init_b)
	if not effects.is_empty():
		lines.append("")
		lines.append("[b]Effects:[/b] %s" % ", ".join(effects))
	var profs_var: Variant = feat_dict.get("proficiencies", [])
	if profs_var is Array and not (profs_var as Array).is_empty():
		var prof_names: Array = []
		for p: Variant in profs_var as Array:
			if p is Dictionary:
				prof_names.append(str((p as Dictionary).get("name", "")))
		if not prof_names.is_empty():
			lines.append("[b]Proficiencies:[/b] %s" % ", ".join(prof_names))
	var features_var: Variant = feat_dict.get("features", [])
	if features_var is Array:
		for ff: Variant in features_var as Array:
			if ff is Dictionary:
				var ff_d: Dictionary = ff as Dictionary
				lines.append("")
				lines.append("[b]%s.[/b] %s" % [str(ff_d.get("name", "")), str(ff_d.get("desc", ""))])
	_body.text = "\n".join(lines)
	visible = true
	_wizard.reapply_theme()


## Show a simple name + description (invocations, class features, etc.).
func show_text(title: String, description: String) -> void:
	_title_label.text = title
	_body.text = description
	visible = true
	_wizard.reapply_theme()
