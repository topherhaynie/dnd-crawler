extends VBoxContainer
class_name StatblockCardView

# ---------------------------------------------------------------------------
# StatblockCardView — formatted D&D-style statblock card (reusable widget).
#
# Call display(statblock) to populate all fields. Suitable for embedding
# inside a ScrollContainer in the library browser or a popup.
# ---------------------------------------------------------------------------

@warning_ignore("UNUSED_SIGNAL")
signal roll_hp_requested(statblock: StatblockData)

var _current: StatblockData = null

## Cached label references for fast updates
var _name_label: Label = null
var _type_label: Label = null
var _ac_label: RichTextLabel = null
var _hp_label: RichTextLabel = null
var _speed_label: RichTextLabel = null
var _abilities_grid: GridContainer = null
var _saves_label: RichTextLabel = null
var _skills_label: RichTextLabel = null
var _vuln_label: RichTextLabel = null
var _resist_label: RichTextLabel = null
var _immune_label: RichTextLabel = null
var _condition_immune_label: RichTextLabel = null
var _senses_label: RichTextLabel = null
var _languages_label: RichTextLabel = null
var _cr_label: RichTextLabel = null
var _traits_box: VBoxContainer = null
var _actions_box: VBoxContainer = null
var _reactions_box: VBoxContainer = null
var _legendary_box: VBoxContainer = null
var _portrait_rect: TextureRect = null


func _ready() -> void:
	_build_layout()


func display(statblock: StatblockData) -> void:
	_current = statblock
	if statblock == null:
		_clear()
		return
	_populate(statblock)


func get_current() -> StatblockData:
	return _current


## Apply scaled font sizes across all card elements. Call after display().
## `base` is the body-text font size in logical pixels (e.g. 14.0); headings
## and sub-text sizes are derived proportionally.
func apply_font_scale(base: float) -> void:
	var title_sz: int = roundi(base * 1.6) # ~22 at base 14
	var section_sz: int = roundi(base * 1.15) # ~16 at base 14
	var body_sz: int = roundi(base) # 14
	var small_sz: int = roundi(base * 0.9) # ~12-13 at base 14

	if _name_label != null:
		_name_label.add_theme_font_size_override("font_size", title_sz)
	if _type_label != null:
		_type_label.add_theme_font_size_override("font_size", small_sz)

	# Rich text labels (body size)
	for rtl: RichTextLabel in [_ac_label, _hp_label, _speed_label, _saves_label,
			_skills_label, _vuln_label, _resist_label, _immune_label,
			_condition_immune_label, _senses_label, _languages_label, _cr_label]:
		if rtl != null:
			rtl.add_theme_font_size_override("normal_font_size", body_sz)
			rtl.add_theme_font_size_override("bold_font_size", body_sz)

	# Ability grid: headers = small, values = small
	if _abilities_grid != null:
		for child: Node in _abilities_grid.get_children():
			if child is Label:
				(child as Label).add_theme_font_size_override("font_size", small_sz)

	# Action section boxes — scale headers and RichTextLabels
	for box: VBoxContainer in [_traits_box, _actions_box, _reactions_box, _legendary_box]:
		if box == null:
			continue
		for child: Node in box.get_children():
			if child is Label:
				(child as Label).add_theme_font_size_override("font_size", section_sz)
			elif child is RichTextLabel:
				(child as RichTextLabel).add_theme_font_size_override("normal_font_size", body_sz)
				(child as RichTextLabel).add_theme_font_size_override("bold_font_size", body_sz)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _build_layout() -> void:
	add_theme_constant_override("separation", 2)

	# Portrait
	_portrait_rect = TextureRect.new()
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_rect.custom_minimum_size = Vector2(0, 180)
	_portrait_rect.visible = false
	_portrait_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	add_child(_portrait_rect)

	# Name
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	add_child(_name_label)

	# Type line
	_type_label = Label.new()
	_type_label.add_theme_font_size_override("font_size", 12)
	_type_label.modulate = Color(0.7, 0.7, 0.7)
	add_child(_type_label)

	add_child(_make_separator())

	# AC / HP / Speed
	_ac_label = _make_rich_label()
	add_child(_ac_label)
	_hp_label = _make_rich_label()
	add_child(_hp_label)
	_speed_label = _make_rich_label()
	add_child(_speed_label)

	add_child(_make_separator())

	# Ability scores (6-column grid)
	_abilities_grid = GridContainer.new()
	_abilities_grid.columns = 6
	for col_name: String in ["STR", "DEX", "CON", "INT", "WIS", "CHA"]:
		var header := Label.new()
		header.text = col_name
		header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_theme_font_size_override("font_size", 12)
		header.size_flags_horizontal = SIZE_EXPAND_FILL
		_abilities_grid.add_child(header)
	# Value rows get added dynamically
	add_child(_abilities_grid)

	add_child(_make_separator())

	# Properties section (saves, skills, defenses, senses, etc.)
	_saves_label = _make_rich_label()
	add_child(_saves_label)
	_skills_label = _make_rich_label()
	add_child(_skills_label)
	_vuln_label = _make_rich_label()
	add_child(_vuln_label)
	_resist_label = _make_rich_label()
	add_child(_resist_label)
	_immune_label = _make_rich_label()
	add_child(_immune_label)
	_condition_immune_label = _make_rich_label()
	add_child(_condition_immune_label)
	_senses_label = _make_rich_label()
	add_child(_senses_label)
	_languages_label = _make_rich_label()
	add_child(_languages_label)
	_cr_label = _make_rich_label()
	add_child(_cr_label)

	add_child(_make_separator())

	# Action sections
	_traits_box = VBoxContainer.new()
	add_child(_traits_box)
	_actions_box = VBoxContainer.new()
	add_child(_actions_box)
	_reactions_box = VBoxContainer.new()
	add_child(_reactions_box)
	_legendary_box = VBoxContainer.new()
	add_child(_legendary_box)


# ---------------------------------------------------------------------------
# Populate
# ---------------------------------------------------------------------------

func _populate(s: StatblockData) -> void:
	_name_label.text = s.name

	# Type line
	var type_parts: PackedStringArray = PackedStringArray()
	if not s.size.is_empty():
		type_parts.append(s.size)
	if not s.creature_type.is_empty():
		type_parts.append(s.creature_type)
	if not s.subtype.is_empty():
		type_parts.append("(%s)" % s.subtype)
	if not s.alignment.is_empty():
		type_parts.append(", %s" % s.alignment)
	_type_label.text = " ".join(type_parts)

	# AC
	var ac_str: String = ""
	for ac_entry: Variant in s.armor_class:
		if ac_entry is Dictionary:
			var d := ac_entry as Dictionary
			var val: String = str(d.get("value", ""))
			var ac_type: String = str(d.get("type", ""))
			ac_str += val
			if not ac_type.is_empty() and ac_type != "dex":
				ac_str += " (%s)" % ac_type
	_set_prop(_ac_label, "Armor Class", ac_str)

	# HP
	var hp_str: String = "%d" % s.hit_points
	if not s.hit_points_roll.is_empty():
		hp_str += " (%s)" % s.hit_points_roll
	_set_prop(_hp_label, "Hit Points", hp_str)

	# Speed
	var speed_parts: PackedStringArray = PackedStringArray()
	for key: Variant in s.speed:
		speed_parts.append("%s %s" % [str(key), str(s.speed[key])])
	_set_prop(_speed_label, "Speed", ", ".join(speed_parts))

	# Ability scores — remove old value cells, rebuild
	var child_count: int = _abilities_grid.get_child_count()
	while child_count > 6:
		child_count -= 1
		var old_child: Node = _abilities_grid.get_child(child_count)
		_abilities_grid.remove_child(old_child)
		old_child.queue_free()
	for score: int in [s.strength, s.dexterity, s.constitution, s.intelligence, s.wisdom, s.charisma]:
		var mod: int = int(floor((score - 10) / 2.0))
		var sign_str: String = "+" if mod >= 0 else ""
		var cell := Label.new()
		cell.text = "%d (%s%d)" % [score, sign_str, mod]
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_theme_font_size_override("font_size", 13)
		cell.size_flags_horizontal = SIZE_EXPAND_FILL
		_abilities_grid.add_child(cell)

	# Saving throws
	var save_strs: PackedStringArray = PackedStringArray()
	for entry: Variant in s.saving_throws:
		if entry is Dictionary:
			var d := entry as Dictionary
			var sv_name: String = str(d.get("name", ""))
			var sv_val: int = int(d.get("value", 0))
			save_strs.append("%s +%d" % [sv_name, sv_val])
	_set_prop_visible(_saves_label, "Saving Throws", ", ".join(save_strs))

	# Skills (from proficiencies that start with "Skill: ")
	var skill_strs: PackedStringArray = PackedStringArray()
	for entry: Variant in s.proficiencies:
		if entry is Dictionary:
			var d := entry as Dictionary
			var prof: Variant = d.get("proficiency", {})
			var pname: String = ""
			if prof is Dictionary:
				pname = str((prof as Dictionary).get("name", ""))
			else:
				pname = str(prof)
			if pname.begins_with("Skill: "):
				var skill_name: String = pname.substr(7)
				var val: int = int(d.get("value", 0))
				skill_strs.append("%s +%d" % [skill_name, val])
	_set_prop_visible(_skills_label, "Skills", ", ".join(skill_strs))

	# Defenses
	_set_prop_visible(_vuln_label, "Damage Vulnerabilities", ", ".join(PackedStringArray(s.damage_vulnerabilities)))
	_set_prop_visible(_resist_label, "Damage Resistances", ", ".join(PackedStringArray(s.damage_resistances)))
	_set_prop_visible(_immune_label, "Damage Immunities", ", ".join(PackedStringArray(s.damage_immunities)))

	var cond_names: PackedStringArray = PackedStringArray()
	for ci: Variant in s.condition_immunities:
		if ci is Dictionary:
			cond_names.append(str((ci as Dictionary).get("name", "")))
		elif ci is String:
			cond_names.append(ci as String)
	_set_prop_visible(_condition_immune_label, "Condition Immunities", ", ".join(cond_names))

	# Senses
	var sense_strs: PackedStringArray = PackedStringArray()
	for key: Variant in s.senses:
		sense_strs.append("%s %s" % [str(key), str(s.senses[key])])
	_set_prop_visible(_senses_label, "Senses", ", ".join(sense_strs))

	# Languages
	_set_prop_visible(_languages_label, "Languages", s.languages)

	# CR
	var cr_str: String = _format_cr(s.challenge_rating)
	if s.xp > 0:
		cr_str += " (%d XP)" % s.xp
	_set_prop(_cr_label, "Challenge", cr_str)

	# Action sections
	_populate_actions(_traits_box, "Traits", s.special_abilities)
	_populate_actions(_actions_box, "Actions", s.actions)
	_populate_actions(_reactions_box, "Reactions", s.reactions)
	_populate_actions(_legendary_box, "Legendary Actions", s.legendary_actions)

	# Portrait
	_portrait_rect.visible = false
	if not s.srd_image_url.is_empty():
		_load_portrait_async(s.srd_index)


func _clear() -> void:
	_name_label.text = ""
	_type_label.text = ""
	_ac_label.text = ""
	_hp_label.text = ""
	_speed_label.text = ""
	_saves_label.text = ""
	_saves_label.visible = false
	_skills_label.text = ""
	_skills_label.visible = false
	_vuln_label.visible = false
	_resist_label.visible = false
	_immune_label.visible = false
	_condition_immune_label.visible = false
	_senses_label.visible = false
	_languages_label.visible = false
	_cr_label.text = ""
	_portrait_rect.visible = false
	_clear_box(_traits_box)
	_clear_box(_actions_box)
	_clear_box(_reactions_box)
	_clear_box(_legendary_box)


# ---------------------------------------------------------------------------
# Action section helpers
# ---------------------------------------------------------------------------

func _populate_actions(box: VBoxContainer, header_text: String, entries: Array) -> void:
	_clear_box(box)
	if entries.is_empty():
		box.visible = false
		return
	box.visible = true

	# Section header
	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 16)
	box.add_child(header)
	box.add_child(_make_separator())

	for entry: Variant in entries:
		if not entry is ActionEntry:
			continue
		var action := entry as ActionEntry
		var rtl := RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.selection_enabled = true

		var text: String = "[b]%s.[/b] %s" % [action.name, action.desc]
		rtl.text = text
		box.add_child(rtl)


func _clear_box(box: VBoxContainer) -> void:
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------------------
# Portrait loading
# ---------------------------------------------------------------------------

func _load_portrait_async(srd_index: String) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.srd == null:
		return

	# Try cached first
	var cached: Image = registry.srd.get_cached_monster_image(srd_index)
	if cached != null:
		_apply_portrait(cached)
		return

	# Fetch URL and download
	var url: String = registry.srd.get_monster_image_url(srd_index)
	if url.is_empty():
		return

	var http := HTTPRequest.new()
	add_child(http)
	var err: Error = http.request(url)
	if err != OK:
		http.queue_free()
		return

	http.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		http.queue_free()
		if response_code != 200 or body.is_empty():
			return
		var img := Image.new()
		var load_err: Error = img.load_png_from_buffer(body)
		if load_err != OK:
			return
		_apply_portrait(img)
	)


func _apply_portrait(img: Image) -> void:
	var tex := ImageTexture.create_from_image(img)
	_portrait_rect.texture = tex
	_portrait_rect.visible = true


# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

func _make_rich_label() -> RichTextLabel:
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.selection_enabled = true
	return rtl


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	return sep


func _set_prop(label: RichTextLabel, prop_name: String, value: String) -> void:
	label.text = "[b]%s[/b] %s" % [prop_name, value]
	label.visible = true


func _set_prop_visible(label: RichTextLabel, prop_name: String, value: String) -> void:
	if value.is_empty():
		label.visible = false
		return
	label.text = "[b]%s[/b] %s" % [prop_name, value]
	label.visible = true


func _format_cr(cr: float) -> String:
	if cr == 0.125:
		return "1/8"
	elif cr == 0.25:
		return "1/4"
	elif cr == 0.5:
		return "1/2"
	elif cr == int(cr):
		return str(int(cr))
	return str(cr)
