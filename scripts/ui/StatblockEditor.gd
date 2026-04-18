extends Window
class_name StatblockEditor

# ---------------------------------------------------------------------------
# StatblockEditor — rich form for creating / editing creatures from scratch.
#
# Covers identity, ability scores, combat stats, actions, reactions,
# legendary actions, special abilities, spells, and metadata.
# ---------------------------------------------------------------------------

signal statblock_saved(data: StatblockData)

var _registry: ServiceRegistry = null
var _data: StatblockData = null

# ── Identity tab ──────────────────────────────────────────────────────────
var _name_edit: LineEdit = null
var _size_option: OptionButton = null
var _type_edit: LineEdit = null
var _subtype_edit: LineEdit = null
var _alignment_edit: LineEdit = null
var _cr_spin: SpinBox = null
var _xp_spin: SpinBox = null
var _prof_spin: SpinBox = null
var _notes_edit: TextEdit = null

# ── Combat tab ────────────────────────────────────────────────────────────
var _ac_spin: SpinBox = null
var _ac_type_edit: LineEdit = null
var _hp_spin: SpinBox = null
var _hit_dice_edit: LineEdit = null
var _speed_walk_edit: LineEdit = null
var _speed_fly_edit: LineEdit = null
var _speed_swim_edit: LineEdit = null
var _speed_burrow_edit: LineEdit = null
var _speed_climb_edit: LineEdit = null

# ── Ability scores ────────────────────────────────────────────────────────
var _str_spin: SpinBox = null
var _dex_spin: SpinBox = null
var _con_spin: SpinBox = null
var _int_spin: SpinBox = null
var _wis_spin: SpinBox = null
var _cha_spin: SpinBox = null

# ── Defenses tab ──────────────────────────────────────────────────────────
var _resistances_edit: LineEdit = null
var _immunities_edit: LineEdit = null
var _vulnerabilities_edit: LineEdit = null
var _condition_immunities_edit: LineEdit = null
var _senses_edit: LineEdit = null
var _languages_edit: LineEdit = null

# ── Actions / Abilities tabs ──────────────────────────────────────────────
var _actions_container: VBoxContainer = null
var _reactions_container: VBoxContainer = null
var _legendary_container: VBoxContainer = null
var _abilities_container: VBoxContainer = null
var _actions_rows: Array = []
var _reactions_rows: Array = []
var _legendary_rows: Array = []
var _abilities_rows: Array = []

# ── Spells tab ────────────────────────────────────────────────────────────
var _spells_text: TextEdit = null
var _slot_spins: Dictionary = {}  # {level_int: SpinBox}

# ── Layout ────────────────────────────────────────────────────────────────
var _tabs: TabContainer = null
var _save_btn: Button = null
var _cancel_btn: Button = null


func _ready() -> void:
	_registry = get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	title = "Statblock Editor"
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base: float) -> int:
		return mgr.scaled(base) if mgr != null else roundi(base)
	size = Vector2i(s.call(700.0), s.call(650.0))
	min_size = Vector2i(s.call(500.0), s.call(400.0))
	wrap_controls = false
	exclusive = true
	transient = true
	close_requested.connect(func() -> void: hide())
	_build_ui()


func edit(data: StatblockData) -> void:
	_data = data
	_populate_from_data()
	popup_centered()
	reapply_theme()


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base: float) -> int:
		return mgr.scaled(base) if mgr != null else roundi(base)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", s.call(4.0))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", s.call(8.0))
	margin.add_theme_constant_override("margin_right", s.call(8.0))
	margin.add_theme_constant_override("margin_top", s.call(8.0))
	margin.add_theme_constant_override("margin_bottom", s.call(8.0))
	margin.add_child(root)
	add_child(margin)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_build_identity_tab(s)
	_build_combat_tab(s)
	_build_abilities_tab(s)
	_build_defenses_tab(s)
	_build_actions_tab(s, "Actions", "_actions")
	_build_actions_tab(s, "Reactions", "_reactions")
	_build_actions_tab(s, "Legendary", "_legendary")
	_build_actions_tab(s, "Special Abilities", "_abilities")
	_build_spells_tab(s)

	# ── Bottom buttons ────────────────────────────────────────────────────
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", s.call(8.0))
	btn_row.alignment = BoxContainer.ALIGNMENT_END

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.add_theme_font_size_override("font_size", s.call(14.0))
	_cancel_btn.custom_minimum_size = Vector2(s.call(100.0), 0)
	_cancel_btn.pressed.connect(func() -> void: hide())
	btn_row.add_child(_cancel_btn)

	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.add_theme_font_size_override("font_size", s.call(14.0))
	_save_btn.custom_minimum_size = Vector2(s.call(100.0), 0)
	_save_btn.pressed.connect(_on_save)
	btn_row.add_child(_save_btn)

	root.add_child(btn_row)


func _build_identity_tab(s: Callable) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Identity"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", s.call(8.0))
	grid.add_theme_constant_override("v_separation", s.call(6.0))

	_name_edit = _add_field(grid, "Name", s)
	_size_option = OptionButton.new()
	for lbl: String in StatblockData.SIZE_LABELS:
		_size_option.add_item(lbl)
	_size_option.add_theme_font_size_override("font_size", s.call(14.0))
	_add_label_widget(grid, "Size", _size_option, s)
	_type_edit = _add_field(grid, "Type", s)
	_subtype_edit = _add_field(grid, "Subtype", s)
	_alignment_edit = _add_field(grid, "Alignment", s)
	_cr_spin = _add_spin(grid, "Challenge Rating", 0.0, 30.0, 0.25, s)
	_xp_spin = _add_spin(grid, "XP", 0.0, 999999.0, 1.0, s)
	_prof_spin = _add_spin(grid, "Proficiency Bonus", 0.0, 10.0, 1.0, s)

	var notes_lbl := Label.new()
	notes_lbl.text = "Notes"
	notes_lbl.add_theme_font_size_override("font_size", s.call(14.0))
	grid.add_child(notes_lbl)
	_notes_edit = TextEdit.new()
	_notes_edit.custom_minimum_size = Vector2(0, s.call(60.0))
	_notes_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_notes_edit.add_theme_font_size_override("font_size", s.call(14.0))
	_notes_edit.placeholder_text = "DM notes…"
	grid.add_child(_notes_edit)

	scroll.add_child(grid)
	_tabs.add_child(scroll)


func _build_combat_tab(s: Callable) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Combat"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", s.call(8.0))
	grid.add_theme_constant_override("v_separation", s.call(6.0))

	_ac_spin = _add_spin(grid, "Armor Class", 0.0, 30.0, 1.0, s)
	_ac_type_edit = _add_field(grid, "AC Type", s)
	_hp_spin = _add_spin(grid, "Hit Points", 0.0, 9999.0, 1.0, s)
	_hit_dice_edit = _add_field(grid, "Hit Dice", s)
	_speed_walk_edit = _add_field(grid, "Speed (Walk)", s)
	_speed_fly_edit = _add_field(grid, "Speed (Fly)", s)
	_speed_swim_edit = _add_field(grid, "Speed (Swim)", s)
	_speed_burrow_edit = _add_field(grid, "Speed (Burrow)", s)
	_speed_climb_edit = _add_field(grid, "Speed (Climb)", s)

	scroll.add_child(grid)
	_tabs.add_child(scroll)


func _build_abilities_tab(s: Callable) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Ability Scores"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", s.call(8.0))
	grid.add_theme_constant_override("v_separation", s.call(6.0))

	_str_spin = _add_spin(grid, "Strength", 1.0, 30.0, 1.0, s)
	_dex_spin = _add_spin(grid, "Dexterity", 1.0, 30.0, 1.0, s)
	_con_spin = _add_spin(grid, "Constitution", 1.0, 30.0, 1.0, s)
	_int_spin = _add_spin(grid, "Intelligence", 1.0, 30.0, 1.0, s)
	_wis_spin = _add_spin(grid, "Wisdom", 1.0, 30.0, 1.0, s)
	_cha_spin = _add_spin(grid, "Charisma", 1.0, 30.0, 1.0, s)

	scroll.add_child(grid)
	_tabs.add_child(scroll)


func _build_defenses_tab(s: Callable) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Defenses"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", s.call(8.0))
	grid.add_theme_constant_override("v_separation", s.call(6.0))

	_resistances_edit = _add_field(grid, "Damage Resistances", s)
	_immunities_edit = _add_field(grid, "Damage Immunities", s)
	_vulnerabilities_edit = _add_field(grid, "Damage Vulnerabilities", s)
	_condition_immunities_edit = _add_field(grid, "Condition Immunities", s)
	_senses_edit = _add_field(grid, "Senses", s)
	_languages_edit = _add_field(grid, "Languages", s)

	scroll.add_child(grid)
	_tabs.add_child(scroll)


func _build_actions_tab(s: Callable, tab_label: String, field_prefix: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_label
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", s.call(6.0))

	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", s.call(4.0))
	vbox.add_child(container)

	var add_btn := Button.new()
	add_btn.text = "+ Add %s" % tab_label.trim_suffix("s")
	add_btn.add_theme_font_size_override("font_size", s.call(13.0))
	add_btn.pressed.connect(_on_add_action.bind(container, field_prefix))
	vbox.add_child(add_btn)

	# Store references based on prefix
	match field_prefix:
		"_actions":
			_actions_container = container
		"_reactions":
			_reactions_container = container
		"_legendary":
			_legendary_container = container
		"_abilities":
			_abilities_container = container

	scroll.add_child(vbox)
	_tabs.add_child(scroll)


func _build_spells_tab(s: Callable) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "Spells"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", s.call(6.0))

	# Spell slots grid
	var slots_label := Label.new()
	slots_label.text = "Spell Slots"
	slots_label.add_theme_font_size_override("font_size", s.call(14.0))
	vbox.add_child(slots_label)

	var slot_grid := GridContainer.new()
	slot_grid.columns = 10
	slot_grid.add_theme_constant_override("h_separation", s.call(4.0))
	for lvl: int in range(1, 10):
		var col_lbl := Label.new()
		col_lbl.text = str(lvl)
		col_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_lbl.add_theme_font_size_override("font_size", s.call(12.0))
		slot_grid.add_child(col_lbl)
	# "Cantrips" header placeholder
	var cant_lbl := Label.new()
	cant_lbl.text = ""
	slot_grid.add_child(cant_lbl)

	for lvl: int in range(1, 10):
		var sp := SpinBox.new()
		sp.min_value = 0
		sp.max_value = 9
		sp.value = 0
		sp.custom_minimum_size = Vector2(s.call(50.0), 0)
		sp.get_line_edit().add_theme_font_size_override("font_size", s.call(12.0))
		slot_grid.add_child(sp)
		_slot_spins[lvl] = sp
	# Empty cell for alignment
	slot_grid.add_child(Control.new())

	vbox.add_child(slot_grid)

	var spells_lbl := Label.new()
	spells_lbl.text = "Spell List (one per line)"
	spells_lbl.add_theme_font_size_override("font_size", s.call(14.0))
	vbox.add_child(spells_lbl)

	_spells_text = TextEdit.new()
	_spells_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spells_text.custom_minimum_size = Vector2(0, s.call(120.0))
	_spells_text.add_theme_font_size_override("font_size", s.call(14.0))
	_spells_text.placeholder_text = "fireball\nshield\ncure-wounds\n…"
	vbox.add_child(_spells_text)

	scroll.add_child(vbox)
	_tabs.add_child(scroll)


# ---------------------------------------------------------------------------
# Action Row Builder
# ---------------------------------------------------------------------------

func _on_add_action(container: VBoxContainer, field_prefix: String) -> void:
	var row: Dictionary = _create_action_row(container)
	match field_prefix:
		"_actions": _actions_rows.append(row)
		"_reactions": _reactions_rows.append(row)
		"_legendary": _legendary_rows.append(row)
		"_abilities": _abilities_rows.append(row)


func _create_action_row(container: VBoxContainer) -> Dictionary:
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	var s := func(base: float) -> int:
		return mgr.scaled(base) if mgr != null else roundi(base)

	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", s.call(2.0))

	# Row 1: name + attack bonus + remove
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", s.call(4.0))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Name"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.add_theme_font_size_override("font_size", s.call(13.0))
	row1.add_child(name_edit)

	var atk_lbl := Label.new()
	atk_lbl.text = "Atk+"
	atk_lbl.add_theme_font_size_override("font_size", s.call(12.0))
	row1.add_child(atk_lbl)
	var atk_spin := SpinBox.new()
	atk_spin.min_value = -10
	atk_spin.max_value = 30
	atk_spin.value = 0
	atk_spin.custom_minimum_size = Vector2(s.call(60.0), 0)
	atk_spin.get_line_edit().add_theme_font_size_override("font_size", s.call(12.0))
	row1.add_child(atk_spin)

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.custom_minimum_size = Vector2(s.call(28.0), s.call(28.0))
	remove_btn.add_theme_font_size_override("font_size", s.call(14.0))
	row1.add_child(remove_btn)
	frame.add_child(row1)

	# Row 2: dice expression + damage type
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", s.call(4.0))
	var dice_edit := LineEdit.new()
	dice_edit.placeholder_text = "Damage (e.g. 2d6+3)"
	dice_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dice_edit.add_theme_font_size_override("font_size", s.call(13.0))
	row2.add_child(dice_edit)
	var dmg_type_edit := LineEdit.new()
	dmg_type_edit.placeholder_text = "Type (slashing)"
	dmg_type_edit.custom_minimum_size = Vector2(s.call(130.0), 0)
	dmg_type_edit.add_theme_font_size_override("font_size", s.call(13.0))
	row2.add_child(dmg_type_edit)
	frame.add_child(row2)

	# Row 3: description
	var desc_edit := TextEdit.new()
	desc_edit.placeholder_text = "Description…"
	desc_edit.custom_minimum_size = Vector2(0, s.call(48.0))
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.add_theme_font_size_override("font_size", s.call(13.0))
	frame.add_child(desc_edit)

	# Separator
	var sep := HSeparator.new()
	frame.add_child(sep)

	container.add_child(frame)

	var row_dict: Dictionary = {
		"frame": frame,
		"name_edit": name_edit,
		"atk_spin": atk_spin,
		"dice_edit": dice_edit,
		"dmg_type_edit": dmg_type_edit,
		"desc_edit": desc_edit,
	}

	remove_btn.pressed.connect(func() -> void:
		frame.queue_free()
		_actions_rows.erase(row_dict)
		_reactions_rows.erase(row_dict)
		_legendary_rows.erase(row_dict)
		_abilities_rows.erase(row_dict)
	)

	reapply_theme()
	return row_dict


# ---------------------------------------------------------------------------
# Populate from StatblockData
# ---------------------------------------------------------------------------

func _populate_from_data() -> void:
	if _data == null:
		return

	_name_edit.text = _data.name
	_size_option.selected = maxi(0, StatblockData.SIZE_LABELS.find(_data.size))
	_type_edit.text = _data.creature_type
	_subtype_edit.text = _data.subtype
	_alignment_edit.text = _data.alignment
	_cr_spin.value = _data.challenge_rating
	_xp_spin.value = _data.xp
	_prof_spin.value = _data.proficiency_bonus
	_notes_edit.text = _data.notes

	# Combat
	if _data.armor_class.size() > 0:
		var ac_entry: Variant = _data.armor_class[0]
		if ac_entry is Dictionary:
			_ac_spin.value = int((ac_entry as Dictionary).get("value", 0))
			_ac_type_edit.text = str((ac_entry as Dictionary).get("type", ""))
	_hp_spin.value = _data.hit_points
	_hit_dice_edit.text = _data.hit_points_roll if not _data.hit_points_roll.is_empty() else _data.hit_dice
	_speed_walk_edit.text = str(_data.speed.get("walk", ""))
	_speed_fly_edit.text = str(_data.speed.get("fly", ""))
	_speed_swim_edit.text = str(_data.speed.get("swim", ""))
	_speed_burrow_edit.text = str(_data.speed.get("burrow", ""))
	_speed_climb_edit.text = str(_data.speed.get("climb", ""))

	# Abilities
	_str_spin.value = _data.strength
	_dex_spin.value = _data.dexterity
	_con_spin.value = _data.constitution
	_int_spin.value = _data.intelligence
	_wis_spin.value = _data.wisdom
	_cha_spin.value = _data.charisma

	# Defenses
	_resistances_edit.text = ", ".join(_data.damage_resistances.map(func(v: Variant) -> String: return str(v)))
	_immunities_edit.text = ", ".join(_data.damage_immunities.map(func(v: Variant) -> String: return str(v)))
	_vulnerabilities_edit.text = ", ".join(_data.damage_vulnerabilities.map(func(v: Variant) -> String: return str(v)))
	var imm_strs: Array = []
	for ci: Variant in _data.condition_immunities:
		if ci is Dictionary:
			imm_strs.append(str((ci as Dictionary).get("name", "")))
		else:
			imm_strs.append(str(ci))
	_condition_immunities_edit.text = ", ".join(imm_strs)

	var senses_parts: Array = []
	for key: Variant in _data.senses:
		senses_parts.append("%s: %s" % [str(key), str(_data.senses[key])])
	_senses_edit.text = ", ".join(senses_parts)
	_languages_edit.text = _data.languages

	# Actions / Reactions / Legendary / Abilities
	_populate_action_rows(_data.actions, _actions_container, "_actions")
	_populate_action_rows(_data.reactions, _reactions_container, "_reactions")
	_populate_action_rows(_data.legendary_actions, _legendary_container, "_legendary")
	_populate_action_rows(_data.special_abilities, _abilities_container, "_abilities")

	# Spells
	_spells_text.text = "\n".join(_data.spell_list)
	for lvl: int in _slot_spins:
		var sp: SpinBox = _slot_spins[lvl] as SpinBox
		sp.value = int(_data.spell_slots.get(lvl, _data.spell_slots.get(str(lvl), 0)))


func _populate_action_rows(entries: Array, container: VBoxContainer, field_prefix: String) -> void:
	for entry: Variant in entries:
		var d: Dictionary = {}
		if entry is ActionEntry:
			d = (entry as ActionEntry).to_dict()
		elif entry is Dictionary:
			d = entry as Dictionary
		else:
			continue
		var row: Dictionary = _create_action_row(container)
		match field_prefix:
			"_actions": _actions_rows.append(row)
			"_reactions": _reactions_rows.append(row)
			"_legendary": _legendary_rows.append(row)
			"_abilities": _abilities_rows.append(row)
		(row["name_edit"] as LineEdit).text = str(d.get("name", ""))
		(row["atk_spin"] as SpinBox).value = int(d.get("attack_bonus", 0))
		(row["desc_edit"] as TextEdit).text = str(d.get("desc", ""))
		var dmg_arr: Variant = d.get("damage", [])
		if dmg_arr is Array and (dmg_arr as Array).size() > 0:
			var first: Variant = (dmg_arr as Array)[0]
			if first is Dictionary:
				(row["dice_edit"] as LineEdit).text = str((first as Dictionary).get("damage_dice", ""))
				(row["dmg_type_edit"] as LineEdit).text = str((first as Dictionary).get("damage_type", ""))


# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------

func _on_save() -> void:
	if _data == null:
		_data = StatblockData.new()
		_data.id = StatblockData.generate_id()
		_data.source = "custom"

	_data.name = _name_edit.text.strip_edges()
	if _data.name.is_empty():
		_data.name = "Unnamed Creature"
	_data.size = StatblockData.SIZE_LABELS[_size_option.selected] if _size_option.selected >= 0 else "Medium"
	_data.creature_type = _type_edit.text.strip_edges()
	_data.subtype = _subtype_edit.text.strip_edges()
	_data.alignment = _alignment_edit.text.strip_edges()
	_data.challenge_rating = _cr_spin.value
	_data.xp = int(_xp_spin.value)
	_data.proficiency_bonus = int(_prof_spin.value)
	_data.notes = _notes_edit.text

	# Combat
	_data.armor_class = [{"type": _ac_type_edit.text.strip_edges(), "value": int(_ac_spin.value)}]
	_data.hit_points = int(_hp_spin.value)
	_data.hit_points_roll = _hit_dice_edit.text.strip_edges()
	_data.hit_dice = _data.hit_points_roll

	var spd: Dictionary = {}
	if not _speed_walk_edit.text.strip_edges().is_empty():
		spd["walk"] = _speed_walk_edit.text.strip_edges()
	if not _speed_fly_edit.text.strip_edges().is_empty():
		spd["fly"] = _speed_fly_edit.text.strip_edges()
	if not _speed_swim_edit.text.strip_edges().is_empty():
		spd["swim"] = _speed_swim_edit.text.strip_edges()
	if not _speed_burrow_edit.text.strip_edges().is_empty():
		spd["burrow"] = _speed_burrow_edit.text.strip_edges()
	if not _speed_climb_edit.text.strip_edges().is_empty():
		spd["climb"] = _speed_climb_edit.text.strip_edges()
	_data.speed = spd

	# Abilities
	_data.strength = int(_str_spin.value)
	_data.dexterity = int(_dex_spin.value)
	_data.constitution = int(_con_spin.value)
	_data.intelligence = int(_int_spin.value)
	_data.wisdom = int(_wis_spin.value)
	_data.charisma = int(_cha_spin.value)

	# Defenses
	_data.damage_resistances = _parse_comma_list(_resistances_edit.text)
	_data.damage_immunities = _parse_comma_list(_immunities_edit.text)
	_data.damage_vulnerabilities = _parse_comma_list(_vulnerabilities_edit.text)
	_data.condition_immunities = _parse_comma_list(_condition_immunities_edit.text)
	_data.languages = _languages_edit.text.strip_edges()

	# Senses
	var senses_dict: Dictionary = {}
	for part: String in _senses_edit.text.split(","):
		var trimmed: String = part.strip_edges()
		if trimmed.is_empty():
			continue
		var colon_idx: int = trimmed.find(":")
		if colon_idx > 0:
			senses_dict[trimmed.substr(0, colon_idx).strip_edges()] = trimmed.substr(colon_idx + 1).strip_edges()
		else:
			senses_dict[trimmed] = ""
	_data.senses = senses_dict

	# Actions
	_data.actions = _read_action_rows(_actions_rows)
	_data.reactions = _read_action_rows(_reactions_rows)
	_data.legendary_actions = _read_action_rows(_legendary_rows)
	_data.special_abilities = _read_action_rows(_abilities_rows)

	# Spells
	var spell_lines: PackedStringArray = _spells_text.text.split("\n")
	_data.spell_list = []
	for line: String in spell_lines:
		var t: String = line.strip_edges()
		if not t.is_empty():
			_data.spell_list.append(t)
	_data.spell_slots = {}
	for lvl: int in _slot_spins:
		var sp: SpinBox = _slot_spins[lvl] as SpinBox
		if int(sp.value) > 0:
			_data.spell_slots[lvl] = int(sp.value)

	statblock_saved.emit(_data)
	hide()


func _read_action_rows(rows: Array) -> Array:
	var out: Array = []
	for row: Variant in rows:
		if not row is Dictionary:
			continue
		var rd := row as Dictionary
		var name_ctrl: Variant = rd.get("name_edit")
		var atk_ctrl: Variant = rd.get("atk_spin")
		var dice_ctrl: Variant = rd.get("dice_edit")
		var type_ctrl: Variant = rd.get("dmg_type_edit")
		var desc_ctrl: Variant = rd.get("desc_edit")
		# Skip if the frame has been removed
		if name_ctrl is LineEdit and not (name_ctrl as LineEdit).is_inside_tree():
			continue
		var entry := ActionEntry.new()
		entry.name = (name_ctrl as LineEdit).text.strip_edges() if name_ctrl is LineEdit else ""
		entry.attack_bonus = int((atk_ctrl as SpinBox).value) if atk_ctrl is SpinBox else 0
		entry.desc = (desc_ctrl as TextEdit).text.strip_edges() if desc_ctrl is TextEdit else ""
		var dice_str: String = (dice_ctrl as LineEdit).text.strip_edges() if dice_ctrl is LineEdit else ""
		var type_str: String = (type_ctrl as LineEdit).text.strip_edges() if type_ctrl is LineEdit else ""
		if not dice_str.is_empty():
			entry.damage = [{"damage_dice": dice_str, "damage_type": type_str}]
		if entry.name.is_empty() and entry.desc.is_empty():
			continue
		out.append(entry)
	return out


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _add_field(grid: GridContainer, label_text: String, s: Callable) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", s.call(14.0))
	grid.add_child(lbl)
	var field := LineEdit.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_theme_font_size_override("font_size", s.call(14.0))
	grid.add_child(field)
	return field


func _add_spin(grid: GridContainer, label_text: String, min_val: float, max_val: float, step: float, s: Callable) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", s.call(14.0))
	grid.add_child(lbl)
	var sp := SpinBox.new()
	sp.min_value = min_val
	sp.max_value = max_val
	sp.step = step
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.get_line_edit().add_theme_font_size_override("font_size", s.call(14.0))
	grid.add_child(sp)
	return sp


func _add_label_widget(grid: GridContainer, label_text: String, widget: Control, s: Callable) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", s.call(14.0))
	grid.add_child(lbl)
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(widget)


func _parse_comma_list(text: String) -> Array:
	var out: Array = []
	for part: String in text.split(","):
		var trimmed: String = part.strip_edges()
		if not trimmed.is_empty():
			out.append(trimmed)
	return out


func _get_ui_scale_mgr() -> UIScaleManager:
	if _registry != null and _registry.ui_scale != null:
		return _registry.ui_scale
	return null


func reapply_theme() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.ui_theme == null:
		return
	var s_val: float = reg.ui_scale.get_scale() if reg.ui_scale != null else 1.0
	reg.ui_theme.theme_control_tree(self, s_val)
	if reg.ui_scale != null:
		for child: Node in get_children():
			if child is Control:
				reg.ui_scale.scale_control_fonts(child as Control, 14.0)
