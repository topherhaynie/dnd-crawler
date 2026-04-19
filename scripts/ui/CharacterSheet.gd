extends Window
class_name CharacterSheet

# -----------------------------------------------------------------------------
# CharacterSheet — non-modal editable character sheet for a StatblockData PC.
#
# Displays and edits the base StatblockData.  Current combat HP/conditions are
# read from the linked StatblockOverride when provided (set_override()).
#
# Phase 4 redesign: grouped features by source, proficiency/save toggles,
# structured inventory, spell slots, senses, damage resistance editor,
# multiclass header.
# -----------------------------------------------------------------------------

signal character_saved(statblock: StatblockData)
signal level_up_requested(statblock: StatblockData)

const ABILITY_NAMES: Array = ["Strength", "Dexterity", "Constitution",
		"Intelligence", "Wisdom", "Charisma"]
const ABILITY_KEYS: Array = ["str", "dex", "con", "int", "wis", "cha"]

const SKILLS: Array = [
	{"name": "Acrobatics", "ability": "dex"},
	{"name": "Animal Handling", "ability": "wis"},
	{"name": "Arcana", "ability": "int"},
	{"name": "Athletics", "ability": "str"},
	{"name": "Deception", "ability": "cha"},
	{"name": "History", "ability": "int"},
	{"name": "Insight", "ability": "wis"},
	{"name": "Intimidation", "ability": "cha"},
	{"name": "Investigation", "ability": "int"},
	{"name": "Medicine", "ability": "wis"},
	{"name": "Nature", "ability": "int"},
	{"name": "Perception", "ability": "wis"},
	{"name": "Performance", "ability": "cha"},
	{"name": "Persuasion", "ability": "cha"},
	{"name": "Religion", "ability": "int"},
	{"name": "Sleight of Hand", "ability": "dex"},
	{"name": "Stealth", "ability": "dex"},
	{"name": "Survival", "ability": "wis"},
]

const FEATURE_SOURCES: Array = [
	{"key": "race", "label": "Racial Traits"},
	{"key": "class", "label": "Class Features"},
	{"key": "subclass", "label": "Subclass Features"},
	{"key": "feat", "label": "Feats"},
	{"key": "background", "label": "Background"},
	{"key": "", "label": "Custom"},
]

const DAMAGE_TYPES: Array = [
	"acid", "bludgeoning", "cold", "fire", "force",
	"lightning", "necrotic", "piercing", "poison",
	"psychic", "radiant", "slashing", "thunder",
]

const CONDITIONS: Array = [
	"blinded", "charmed", "deafened", "frightened", "grappled",
	"incapacitated", "invisible", "paralyzed", "petrified",
	"poisoned", "prone", "restrained", "stunned", "unconscious",
]

var _statblock: StatblockData = null
var _override: StatblockOverride = null
var _dirty: bool = false

# ── Widget refs ───────────────────────────────────────────────────────────────

## Header
var _name_edit: LineEdit = null
var _race_edit: LineEdit = null
var _race_label: Label = null
var _class_header_label: Label = null
var _classes_container: VBoxContainer = null
var _add_class_btn: Button = null
var _bg_edit: LineEdit = null

## Ability scores
var _score_spins: Array = []

## Combat stats
var _ac_spin: SpinBox = null
var _hp_spin: SpinBox = null
var _hp_max_spin: SpinBox = null
var _temp_hp_spin: SpinBox = null
var _speed_edit: LineEdit = null
var _init_label: Label = null
var _prof_bonus_label: Label = null

## Saving throws — ability_key -> {check: CheckBox, label: Label}
var _save_widgets: Dictionary = {}

## Skills — skill_name -> {prof: CheckBox, expert: CheckBox, label: Label}
var _skill_widgets: Dictionary = {}

## Features tab — source_key -> {container: VBoxContainer, rows: Array}
var _feature_sections: Dictionary = {}

## Spells tab
var _spells_text: TextEdit = null

## Spell slots — level (int) -> {max_spin: SpinBox, used_spin: SpinBox}
var _slot_widgets: Dictionary = {}
var _slot_container: VBoxContainer = null

## Inventory tab — Array of {row: HBoxContainer, name_edit: LineEdit,
##   qty_spin: SpinBox, weight_edit: LineEdit, equipped_check: CheckBox}
var _inventory_rows: Array = []
var _inventory_container: VBoxContainer = null
var _inventory_weight_lbl: Label = null
var _inventory_attune_lbl: Label = null
var _inventory_library: ItemLibrary = null
var _right_tabs: TabContainer = null
const _TAB_INVENTORY := 2

## Senses tab
var _darkvision_spin: SpinBox = null
var _passive_perc_spin: SpinBox = null

## Damage / condition lists — {container: VBoxContainer, items: Array}
var _resist_list: Dictionary = {}
var _immune_list: Dictionary = {}
var _vuln_list: Dictionary = {}
var _cond_immune_list: Dictionary = {}

## Proficiencies section — {container: VBoxContainer, edit: TextEdit}
var _armor_prof_edit: TextEdit = null
var _weapon_prof_edit: TextEdit = null
var _tool_prof_edit: TextEdit = null
var _language_edit: LineEdit = null

## Notes tab
var _notes_text: TextEdit = null

## Buttons
var _level_up_btn: Button = null
var _save_btn: Button = null
var _close_btn: Button = null


func _ready() -> void:
	title = "Character Sheet"
	var s: float = _get_ui_scale()
	size = Vector2i(roundi(900.0 * s), roundi(750.0 * s))
	min_size = Vector2i(roundi(700.0 * s), roundi(550.0 * s))
	wrap_controls = true
	popup_window = false
	exclusive = false
	transient = true
	close_requested.connect(_on_close_requested)
	_build_ui()


# ── Public API ────────────────────────────────────────────────────────────────

func is_dirty() -> bool:
	return _dirty


func get_character_name() -> String:
	if _statblock != null and _statblock.name != "":
		return _statblock.name
	return "character"


func save_now() -> void:
	## Programmatic save — identical to clicking the Save button.
	_on_save()


func prompt_save_or_discard() -> void:
	## Show save/discard dialog if dirty, then await completion.
	## When the user chooses Save or Discard the sheet is no longer dirty.
	## Returns immediately if not dirty.
	if not _dirty:
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "Unsaved Changes"
	dlg.dialog_text = "Save changes to '%s' before continuing?" % (
			_statblock.name if _statblock != null and _statblock.name != "" else "character")
	dlg.ok_button_text = "Save"
	dlg.cancel_button_text = "Discard"
	dlg.exclusive = true
	add_child(dlg)
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var s: float = _get_ui_scale()
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg, 15.0)
	dlg.min_size = Vector2i(roundi(300.0 * s), roundi(120.0 * s))
	dlg.reset_size()
	dlg.popup_centered()
	# Block until user picks an option.
	var chosen: StringName = await _await_dialog_choice(dlg)
	if chosen == &"confirmed":
		_on_save()
	else:
		_dirty = false
	dlg.queue_free()


func _await_dialog_choice(dlg: ConfirmationDialog) -> StringName:
	## Helper — returns "confirmed" or "canceled" when the dialog closes.
	var result: Array = []
	dlg.confirmed.connect(func() -> void: result.append(&"confirmed"))
	dlg.canceled.connect(func() -> void: result.append(&"canceled"))
	await dlg.visibility_changed # fires when dialog hides
	return result[0] if result.size() > 0 else &"canceled"


func load_character(sb: StatblockData) -> void:
	_statblock = sb
	_override = null
	_dirty = false
	if sb != null:
		_populate_from_statblock()


func set_override(so: StatblockOverride) -> void:
	_override = so
	_refresh_hp_from_override()


func select_inventory_tab() -> void:
	if _right_tabs != null:
		_right_tabs.current_tab = _TAB_INVENTORY


func _active_ruleset() -> String:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.campaign != null:
		var camp: CampaignData = reg.campaign.get_active_campaign()
		if camp != null:
			return camp.default_ruleset
	return "2014"


func _race_or_species_label() -> String:
	return "Species" if _active_ruleset() == "2024" else "Race"


func _feature_source_label(src_key: String) -> String:
	if src_key == "race":
		if _active_ruleset() == "2024":
			return "Species Traits"
		return "Racial Traits"
	for src: Variant in FEATURE_SOURCES:
		if src is Dictionary and str((src as Dictionary).get("key", "")) == src_key:
			return str((src as Dictionary).get("label", ""))
	return ""


# ── UI construction ───────────────────────────────────────────────────────────
func _build_ui() -> void:
	var s: float = _get_ui_scale()
	var margin: int = roundi(10.0 * s)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", roundi(6.0 * s))
	root.offset_left = margin
	root.offset_top = margin
	root.offset_right = - margin
	root.offset_bottom = - margin
	add_child(root)

	_build_header(root)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = roundi(240.0 * s)
	root.add_child(split)

	_build_left_panel(split)
	_build_right_panel(split)

	var sep := HSeparator.new()
	root.add_child(sep)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", roundi(6.0 * s))
	root.add_child(btn_row)

	_level_up_btn = Button.new()
	_level_up_btn.text = "Level Up"
	_level_up_btn.custom_minimum_size = Vector2(roundi(90.0 * s), roundi(30.0 * s))
	_level_up_btn.pressed.connect(_on_level_up)
	btn_row.add_child(_level_up_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.custom_minimum_size = Vector2(roundi(80.0 * s), roundi(30.0 * s))
	_save_btn.pressed.connect(_on_save)
	btn_row.add_child(_save_btn)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.custom_minimum_size = Vector2(roundi(80.0 * s), roundi(30.0 * s))
	_close_btn.pressed.connect(_on_close_requested)
	btn_row.add_child(_close_btn)


## ── Header (4.9: multiclass display) ────────────────────────────────────────
func _build_header(parent: Control) -> void:
	var s: float = _get_ui_scale()
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", roundi(10.0 * s))
	grid.add_theme_constant_override("v_separation", roundi(4.0 * s))
	parent.add_child(grid)

	_name_edit = _labeled_line_edit(grid, "Name", "Character name")
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.custom_minimum_size.x = roundi(140.0 * s)

	_race_label = Label.new()
	_race_label.text = _race_or_species_label()
	_apply_font_base(_race_label, 18.0)
	grid.add_child(_race_label)
	_race_edit = LineEdit.new()
	_race_edit.placeholder_text = _race_or_species_label()
	_race_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_race_edit.text_changed.connect(_on_text_changed)
	_apply_font_base(_race_edit, 18.0)
	grid.add_child(_race_edit)

	_bg_edit = _labeled_line_edit(grid, "Background", "Background")

	## Classes section — multiclass-aware (Step 4.9)
	var classes_section := VBoxContainer.new()
	classes_section.add_theme_constant_override("separation", roundi(2.0 * s))
	parent.add_child(classes_section)

	_class_header_label = Label.new()
	_class_header_label.text = "Classes"
	_apply_font_base(_class_header_label, 18.0)
	classes_section.add_child(_class_header_label)

	_classes_container = VBoxContainer.new()
	_classes_container.add_theme_constant_override("separation", roundi(2.0 * s))
	classes_section.add_child(_classes_container)

	_add_class_btn = Button.new()
	_add_class_btn.text = "+ Add Class"
	_add_class_btn.pressed.connect(_on_add_class_row.bind("", 1, ""))
	classes_section.add_child(_add_class_btn)

	var sep := HSeparator.new()
	parent.add_child(sep)


## ── Left panel: abilities, saves, combat ─────────────────────────────────────
func _build_left_panel(parent: Control) -> void:
	var s: float = _get_ui_scale()
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(left_scroll)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", roundi(8.0 * s))
	left_scroll.add_child(left)

	## Ability scores
	var ab_lbl := Label.new()
	ab_lbl.text = "Ability Scores"
	_apply_font_base(ab_lbl, 18.0)
	left.add_child(ab_lbl)

	var ab_grid := GridContainer.new()
	ab_grid.columns = 3
	ab_grid.add_theme_constant_override("h_separation", roundi(8.0 * s))
	ab_grid.add_theme_constant_override("v_separation", roundi(2.0 * s))
	left.add_child(ab_grid)

	_score_spins.clear()
	for i: int in 6:
		var lbl := Label.new()
		lbl.text = ABILITY_NAMES[i].left(3).to_upper()
		ab_grid.add_child(lbl)

		var sp := SpinBox.new()
		sp.min_value = 1
		sp.max_value = 30
		sp.value = 10
		sp.custom_minimum_size.x = roundi(70.0 * s)
		sp.value_changed.connect(_on_ability_changed.bind(i))
		_score_spins.append(sp)
		ab_grid.add_child(sp)

		var mod_lbl := Label.new()
		mod_lbl.text = "+0"
		mod_lbl.name = "ModLabel_%d" % i
		ab_grid.add_child(mod_lbl)

	left.add_child(HSeparator.new())

	## Saving throws (4.3: toggle proficiency)
	var st_lbl := Label.new()
	st_lbl.text = "Saving Throws"
	_apply_font_base(st_lbl, 18.0)
	left.add_child(st_lbl)

	var st_grid := GridContainer.new()
	st_grid.columns = 3
	st_grid.add_theme_constant_override("h_separation", roundi(4.0 * s))
	st_grid.add_theme_constant_override("v_separation", roundi(2.0 * s))
	left.add_child(st_grid)

	for i: int in 6:
		var key: String = ABILITY_KEYS[i]
		var cb := CheckBox.new()
		cb.tooltip_text = "Proficient in %s saves" % ABILITY_NAMES[i]
		cb.toggled.connect(func(_on: bool) -> void: _mark_dirty_and_refresh())
		st_grid.add_child(cb)

		var st_name_lbl := Label.new()
		st_name_lbl.text = ABILITY_NAMES[i].left(3).to_upper()
		st_grid.add_child(st_name_lbl)

		var val_lbl := Label.new()
		val_lbl.text = "+0"
		st_grid.add_child(val_lbl)

		_save_widgets[key] = {"check": cb, "label": val_lbl}

	left.add_child(HSeparator.new())

	## Combat stats
	var combat_lbl := Label.new()
	combat_lbl.text = "Combat"
	_apply_font_base(combat_lbl, 18.0)
	left.add_child(combat_lbl)

	var cg := GridContainer.new()
	cg.columns = 2
	cg.add_theme_constant_override("h_separation", roundi(8.0 * s))
	cg.add_theme_constant_override("v_separation", roundi(4.0 * s))
	left.add_child(cg)

	cg.add_child(_make_label("AC"))
	_ac_spin = SpinBox.new()
	_ac_spin.min_value = 0
	_ac_spin.max_value = 30
	_ac_spin.custom_minimum_size.x = roundi(70.0 * s)
	_ac_spin.value_changed.connect(_on_value_changed)
	cg.add_child(_ac_spin)

	cg.add_child(_make_label("Max HP"))
	_hp_max_spin = SpinBox.new()
	_hp_max_spin.min_value = 1
	_hp_max_spin.max_value = 9999
	_hp_max_spin.custom_minimum_size.x = roundi(70.0 * s)
	_hp_max_spin.value_changed.connect(_on_value_changed)
	cg.add_child(_hp_max_spin)

	cg.add_child(_make_label("Current HP"))
	_hp_spin = SpinBox.new()
	_hp_spin.min_value = -99
	_hp_spin.max_value = 9999
	_hp_spin.custom_minimum_size.x = roundi(70.0 * s)
	_hp_spin.value_changed.connect(_on_value_changed)
	cg.add_child(_hp_spin)

	cg.add_child(_make_label("Temp HP"))
	_temp_hp_spin = SpinBox.new()
	_temp_hp_spin.min_value = 0
	_temp_hp_spin.max_value = 9999
	_temp_hp_spin.custom_minimum_size.x = roundi(70.0 * s)
	_temp_hp_spin.value_changed.connect(_on_value_changed)
	cg.add_child(_temp_hp_spin)

	cg.add_child(_make_label("Speed"))
	_speed_edit = LineEdit.new()
	_speed_edit.placeholder_text = "30 ft."
	_speed_edit.custom_minimum_size.x = roundi(80.0 * s)
	_speed_edit.text_changed.connect(_on_text_changed)
	cg.add_child(_speed_edit)

	cg.add_child(_make_label("Initiative"))
	_init_label = Label.new()
	_init_label.text = "+0"
	cg.add_child(_init_label)

	cg.add_child(_make_label("Prof Bonus"))
	_prof_bonus_label = Label.new()
	_prof_bonus_label.text = "+2"
	cg.add_child(_prof_bonus_label)

	left.add_child(HSeparator.new())

	## Senses (4.7)
	var senses_lbl := Label.new()
	senses_lbl.text = "Senses"
	_apply_font_base(senses_lbl, 18.0)
	left.add_child(senses_lbl)

	var sg := GridContainer.new()
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", roundi(8.0 * s))
	sg.add_theme_constant_override("v_separation", roundi(4.0 * s))
	left.add_child(sg)

	sg.add_child(_make_label("Darkvision (ft)"))
	_darkvision_spin = SpinBox.new()
	_darkvision_spin.min_value = 0
	_darkvision_spin.max_value = 300
	_darkvision_spin.step = 30
	_darkvision_spin.custom_minimum_size.x = roundi(70.0 * s)
	_darkvision_spin.value_changed.connect(_on_value_changed)
	sg.add_child(_darkvision_spin)

	sg.add_child(_make_label("Passive Perc."))
	_passive_perc_spin = SpinBox.new()
	_passive_perc_spin.min_value = 1
	_passive_perc_spin.max_value = 30
	_passive_perc_spin.value = 10
	_passive_perc_spin.custom_minimum_size.x = roundi(70.0 * s)
	_passive_perc_spin.value_changed.connect(_on_value_changed)
	sg.add_child(_passive_perc_spin)


## ── Right panel: skills, tabs ────────────────────────────────────────────────
func _build_right_panel(parent: Control) -> void:
	var s: float = _get_ui_scale()
	var right := VSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.split_offset = roundi(100.0 * s)
	parent.add_child(right)

	## ── Top half: Skills ─────────────────────────────────────────────────
	var sk_panel := VBoxContainer.new()
	sk_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sk_panel.add_theme_constant_override("separation", roundi(4.0 * s))
	right.add_child(sk_panel)

	## Skills (4.2: proficiency + expertise toggles, grouped by ability)
	var sk_lbl := Label.new()
	sk_lbl.text = "Skills"
	_apply_font_base(sk_lbl, 18.0)
	sk_panel.add_child(sk_lbl)

	var sk_scroll := ScrollContainer.new()
	sk_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sk_scroll.custom_minimum_size = Vector2i(0, 0)
	sk_panel.add_child(sk_scroll)

	var sk_vbox := VBoxContainer.new()
	sk_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sk_vbox.add_theme_constant_override("separation", roundi(2.0 * s))
	sk_scroll.add_child(sk_vbox)

	## Group skills by ability
	var ability_order: Array = [
		{"key": "str", "label": "STR"},
		{"key": "dex", "label": "DEX"},
		{"key": "con", "label": "CON"},
		{"key": "int", "label": "INT"},
		{"key": "wis", "label": "WIS"},
		{"key": "cha", "label": "CHA"},
	]
	for ab_info: Variant in ability_order:
		if not (ab_info is Dictionary):
			continue
		var ab_key: String = str((ab_info as Dictionary).get("key", ""))
		var ab_label: String = str((ab_info as Dictionary).get("label", ""))
		## Collect skills for this ability
		var group_skills: Array = []
		for sk: Variant in SKILLS:
			if sk is Dictionary and str((sk as Dictionary).get("ability", "")) == ab_key:
				group_skills.append(sk)
		if group_skills.is_empty():
			continue
		var group_lbl := Label.new()
		group_lbl.text = ab_label
		_apply_font_base(group_lbl, 13.0)
		sk_vbox.add_child(group_lbl)

		var sk_grid := GridContainer.new()
		sk_grid.columns = 4
		sk_grid.add_theme_constant_override("h_separation", roundi(4.0 * s))
		sk_grid.add_theme_constant_override("v_separation", roundi(1.0 * s))
		sk_vbox.add_child(sk_grid)

		for sk2: Variant in group_skills:
			if not (sk2 is Dictionary):
				continue
			var sk_name: String = str((sk2 as Dictionary).get("name", ""))

			var prof_cb := CheckBox.new()
			prof_cb.tooltip_text = "Proficient"
			prof_cb.toggled.connect(func(_on: bool) -> void: _mark_dirty_and_refresh())
			sk_grid.add_child(prof_cb)

			var exp_cb := CheckBox.new()
			exp_cb.tooltip_text = "Expertise"
			exp_cb.toggled.connect(func(_on: bool) -> void: _mark_dirty_and_refresh())
			sk_grid.add_child(exp_cb)

			var sk_name_lbl := Label.new()
			sk_name_lbl.text = sk_name
			_apply_font_base(sk_name_lbl, 14.0)
			sk_grid.add_child(sk_name_lbl)

			var sk_val_lbl := Label.new()
			sk_val_lbl.text = "+0"
			_apply_font_base(sk_val_lbl, 14.0)
			sk_grid.add_child(sk_val_lbl)

			_skill_widgets[sk_name] = {"prof": prof_cb, "expert": exp_cb, "label": sk_val_lbl}

	## ── Bottom half: Tabs ────────────────────────────────────────────────
	_right_tabs = TabContainer.new()
	_right_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_right_tabs)

	_build_features_tab(_right_tabs)
	_build_spells_tab(_right_tabs)
	_build_inventory_tab(_right_tabs)
	_build_proficiencies_tab(_right_tabs)
	_build_defenses_tab(_right_tabs)
	_build_notes_tab(_right_tabs)


## ── Features tab (4.1: grouped by source) ────────────────────────────────────
func _build_features_tab(tabs: TabContainer) -> void:
	var s: float = _get_ui_scale()
	var pane := ScrollContainer.new()
	pane.name = "Features"
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(pane)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", roundi(4.0 * s))
	pane.add_child(vb)

	for src: Variant in FEATURE_SOURCES:
		if not (src is Dictionary):
			continue
		var src_key: String = str((src as Dictionary).get("key", ""))
		var src_label: String = _feature_source_label(src_key)

		var section := VBoxContainer.new()
		section.add_theme_constant_override("separation", roundi(2.0 * s))
		vb.add_child(section)

		var header_row := HBoxContainer.new()
		header_row.add_theme_constant_override("separation", roundi(4.0 * s))
		section.add_child(header_row)

		var section_lbl := Label.new()
		section_lbl.text = "▶ " + src_label
		_apply_font_base(section_lbl, 15.0)
		section_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		header_row.add_child(section_lbl)

		var add_btn := Button.new()
		add_btn.text = "+"
		add_btn.tooltip_text = "Add %s feature" % src_label.to_lower()
		add_btn.pressed.connect(_on_add_feature.bind(src_key))
		header_row.add_child(add_btn)

		var rows_container := VBoxContainer.new()
		rows_container.add_theme_constant_override("separation", roundi(2.0 * s))
		rows_container.visible = false
		section.add_child(rows_container)

		# Toggle collapse on label click
		section_lbl.gui_input.connect(
			_make_collapse_handler(section_lbl, rows_container))

		_feature_sections[src_key] = {"container": rows_container, "rows": []}

		section.add_child(HSeparator.new())


## ── Spells tab (with spell slot editor — 4.6) ───────────────────────────────
func _build_spells_tab(tabs: TabContainer) -> void:
	var s: float = _get_ui_scale()
	var split := VSplitContainer.new()
	split.name = "Spells"
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(split)

	## ── Top: Spell slots (in scroll so splitter can shrink it) ───────────
	var top_scroll := ScrollContainer.new()
	top_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(top_scroll)

	var top := VBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_scroll.add_child(top)

	## Spell slots grid
	var slot_lbl := Label.new()
	slot_lbl.text = "Spell Slots"
	_apply_font_base(slot_lbl, 18.0)
	top.add_child(slot_lbl)

	_slot_container = VBoxContainer.new()
	_slot_container.add_theme_constant_override("separation", roundi(2.0 * s))
	top.add_child(_slot_container)

	var slot_grid := GridContainer.new()
	slot_grid.columns = 4
	slot_grid.add_theme_constant_override("h_separation", roundi(6.0 * s))
	slot_grid.add_theme_constant_override("v_separation", roundi(2.0 * s))
	_slot_container.add_child(slot_grid)

	## Headers
	slot_grid.add_child(_make_label("Level"))
	slot_grid.add_child(_make_label("Max"))
	slot_grid.add_child(_make_label("Used"))
	slot_grid.add_child(_make_label("Avail"))

	for lvl: int in range(1, 10):
		var lvl_lbl := Label.new()
		lvl_lbl.text = _ordinal(lvl)
		slot_grid.add_child(lvl_lbl)

		var max_sp := SpinBox.new()
		max_sp.min_value = 0
		max_sp.max_value = 9
		max_sp.custom_minimum_size.x = roundi(60.0 * s)
		max_sp.value_changed.connect(_on_value_changed)
		slot_grid.add_child(max_sp)

		var used_sp := SpinBox.new()
		used_sp.min_value = 0
		used_sp.max_value = 9
		used_sp.custom_minimum_size.x = roundi(60.0 * s)
		used_sp.value_changed.connect(_on_value_changed)
		slot_grid.add_child(used_sp)

		var avail_lbl := Label.new()
		avail_lbl.text = "0"
		slot_grid.add_child(avail_lbl)

		_slot_widgets[lvl] = {"max_spin": max_sp, "used_spin": used_sp, "avail_label": avail_lbl}

	## ── Bottom: Spell list ───────────────────────────────────────────────
	var bottom := VBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(bottom)

	var spell_header := HBoxContainer.new()
	spell_header.add_theme_constant_override("separation", roundi(4.0 * s))
	bottom.add_child(spell_header)

	var spell_list_lbl := Label.new()
	spell_list_lbl.text = "Spell List"
	spell_list_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font_base(spell_list_lbl, 18.0)
	spell_header.add_child(spell_list_lbl)

	var add_spell_btn := Button.new()
	add_spell_btn.text = "+ Add Spell"
	add_spell_btn.pressed.connect(_on_add_spell_pressed)
	spell_header.add_child(add_spell_btn)

	_spells_text = TextEdit.new()
	_spells_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spells_text.custom_minimum_size.y = roundi(60.0 * s)
	_spells_text.placeholder_text = "Known spells (one per line)…"
	_spells_text.text_changed.connect(_on_text_edit_changed)
	_spells_text.gui_input.connect(_on_spells_text_gui_input)
	bottom.add_child(_spells_text)


## ── Inventory tab (4.8: structured rows) ─────────────────────────────────────
func _build_inventory_tab(tabs: TabContainer) -> void:
	var s: float = _get_ui_scale()
	var pane := VBoxContainer.new()
	pane.name = "Inventory"
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(pane)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", roundi(4.0 * s))
	pane.add_child(header)

	var inv_lbl := Label.new()
	inv_lbl.text = "Items"
	inv_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_apply_font_base(inv_lbl, 18.0)
	header.add_child(inv_lbl)

	var add_lib_btn := Button.new()
	add_lib_btn.text = "Add from Library\u2026"
	add_lib_btn.tooltip_text = "Browse and add items from the SRD or campaign library"
	add_lib_btn.pressed.connect(_on_add_from_item_library)
	header.add_child(add_lib_btn)

	var add_item_btn := Button.new()
	add_item_btn.text = "+ Custom Item"
	add_item_btn.tooltip_text = "Add a blank row for manual item entry"
	add_item_btn.pressed.connect(_on_add_inventory_item.bind("", 1, "", false, ""))
	header.add_child(add_item_btn)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pane.add_child(inv_scroll)

	_inventory_container = VBoxContainer.new()
	_inventory_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_container.add_theme_constant_override("separation", roundi(2.0 * s))
	inv_scroll.add_child(_inventory_container)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", roundi(8.0 * s))
	pane.add_child(footer)

	_inventory_weight_lbl = Label.new()
	_inventory_weight_lbl.text = "Total weight: 0 lb"
	_apply_font_base(_inventory_weight_lbl, 12.0)
	_inventory_weight_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_inventory_weight_lbl)

	_inventory_attune_lbl = Label.new()
	_inventory_attune_lbl.text = "Attuned: 0/3"
	_apply_font_base(_inventory_attune_lbl, 12.0)
	footer.add_child(_inventory_attune_lbl)


## ── Proficiencies tab (4.4: armor, weapon, tool, language) ───────────────────
func _build_proficiencies_tab(tabs: TabContainer) -> void:
	var s: float = _get_ui_scale()
	var pane := ScrollContainer.new()
	pane.name = "Proficiencies"
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(pane)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", roundi(6.0 * s))
	pane.add_child(vb)

	vb.add_child(_make_section_label("Armor Proficiencies"))
	_armor_prof_edit = _make_mini_text_edit("Light Armor, Medium Armor…")
	vb.add_child(_armor_prof_edit)

	vb.add_child(_make_section_label("Weapon Proficiencies"))
	_weapon_prof_edit = _make_mini_text_edit("Simple Weapons, Martial Weapons…")
	vb.add_child(_weapon_prof_edit)

	vb.add_child(_make_section_label("Tool Proficiencies"))
	_tool_prof_edit = _make_mini_text_edit("Thieves' Tools, Smith's Tools…")
	vb.add_child(_tool_prof_edit)

	vb.add_child(_make_section_label("Languages"))
	_language_edit = LineEdit.new()
	_language_edit.placeholder_text = "Common, Elvish…"
	_language_edit.text_changed.connect(_on_text_changed)
	vb.add_child(_language_edit)


## ── Defenses tab (4.5: damage resistances, immunities, conditions) ───────────
func _build_defenses_tab(tabs: TabContainer) -> void:
	var s: float = _get_ui_scale()
	var pane := ScrollContainer.new()
	pane.name = "Defenses"
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(pane)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", roundi(6.0 * s))
	pane.add_child(vb)

	_resist_list = _build_tag_list(vb, "Damage Resistances", DAMAGE_TYPES)
	_immune_list = _build_tag_list(vb, "Damage Immunities", DAMAGE_TYPES)
	_vuln_list = _build_tag_list(vb, "Damage Vulnerabilities", DAMAGE_TYPES)
	_cond_immune_list = _build_tag_list(vb, "Condition Immunities", CONDITIONS)


## ── Notes tab ────────────────────────────────────────────────────────────────
func _build_notes_tab(tabs: TabContainer) -> void:
	var s: float = _get_ui_scale()
	var pane := VBoxContainer.new()
	pane.name = "Notes"
	pane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(pane)

	_notes_text = TextEdit.new()
	_notes_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_text.custom_minimum_size.y = roundi(100.0 * s)
	_notes_text.placeholder_text = "DM and player notes…"
	_notes_text.text_changed.connect(_on_text_edit_changed)
	pane.add_child(_notes_text)


# ── Tag list builder (for defenses tab) ──────────────────────────────────────
func _build_tag_list(parent: Control, heading: String,
		options: Array) -> Dictionary:
	var s: float = _get_ui_scale()
	parent.add_child(_make_section_label(heading))

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", roundi(2.0 * s))
	parent.add_child(container)

	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", roundi(4.0 * s))
	container.add_child(tag_row)

	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", roundi(4.0 * s))
	flow.add_theme_constant_override("v_separation", roundi(2.0 * s))
	container.add_child(flow)

	var opt := OptionButton.new()
	for o: String in options:
		opt.add_item(o)
	tag_row.add_child(opt)

	var add_btn := Button.new()
	add_btn.text = "+"
	var result: Dictionary = {"flow": flow, "items": [], "option": opt}
	add_btn.pressed.connect(_make_tag_add_callback(result, opt))
	tag_row.add_child(add_btn)

	parent.add_child(HSeparator.new())
	return result


# ── Population from StatblockData ─────────────────────────────────────────────
func _populate_from_statblock() -> void:
	if _statblock == null:
		return
	var sb := _statblock

	_name_edit.text = sb.name
	_race_edit.text = sb.race
	_bg_edit.text = sb.background

	## Multiclass header (4.9)
	_populate_class_rows(sb)

	## Ability scores
	for i: int in 6:
		(_score_spins[i] as SpinBox).value = _score_for_index(sb, i)

	## Saving throw proficiency toggles (4.3)
	for key: String in ABILITY_KEYS:
		var w: Variant = _save_widgets.get(key)
		if w is Dictionary:
			((w as Dictionary).get("check") as CheckBox).button_pressed = \
				_has_save_proficiency(key)

	## AC
	var ac_val: int = 10
	if not sb.armor_class.is_empty():
		var first_ac: Variant = sb.armor_class[0]
		if first_ac is Dictionary:
			ac_val = int((first_ac as Dictionary).get("value", 10))
	_ac_spin.value = ac_val

	## HP
	_hp_max_spin.value = sb.hit_points if sb.hit_points > 0 else 1
	_hp_spin.value = sb.hit_points if sb.hit_points > 0 else 1

	## Speed
	var walk_speed: Variant = sb.speed.get("walk", "30 ft.")
	_speed_edit.text = str(walk_speed)

	## Senses (4.7)
	var dv_str: Variant = sb.senses.get("darkvision", "")
	_darkvision_spin.value = _parse_feet(str(dv_str))
	var pp_val: Variant = sb.senses.get("passive_perception", 10)
	_passive_perc_spin.value = int(pp_val)

	## Skill proficiency toggles (4.2)
	_populate_skill_proficiencies(sb)

	## Features grouped by source (4.1)
	_populate_features(sb)

	## Spells — resolve SRD indices to display names where possible
	_spells_text.text = _resolve_spell_names(sb.spell_list)

	## Spell slots (4.6)
	_populate_spell_slots(sb)

	## Inventory (4.8)
	_populate_inventory(sb)

	## Proficiencies (4.4)
	_populate_proficiency_texts(sb)

	## Defenses (4.5)
	_populate_tag_list(_resist_list, sb.damage_resistances)
	_populate_tag_list(_immune_list, sb.damage_immunities)
	_populate_tag_list(_vuln_list, sb.damage_vulnerabilities)
	_populate_condition_immunities(sb)

	## Languages
	_language_edit.text = sb.languages

	## Notes
	_notes_text.text = sb.notes

	_refresh_derived()
	_refresh_hp_from_override()
	_dirty = false


func _populate_class_rows(sb: StatblockData) -> void:
	## Clear existing rows
	for child: Node in _classes_container.get_children():
		child.queue_free()

	if sb.classes.is_empty():
		## Fallback: single class from legacy fields
		_on_add_class_row(sb.class_name_str, sb.level if sb.level > 0 else 1,
				"")
	else:
		for entry: Variant in sb.classes:
			if entry is Dictionary:
				var ed: Dictionary = entry as Dictionary
				_on_add_class_row(
					str(ed.get("name", "")),
					int(ed.get("level", 1)),
					str(ed.get("subclass", "")))


func _populate_skill_proficiencies(sb: StatblockData) -> void:
	## Reset all
	for sk_name: String in _skill_widgets.keys():
		var w: Dictionary = _skill_widgets[sk_name] as Dictionary
		(w.get("prof") as CheckBox).button_pressed = false
		(w.get("expert") as CheckBox).button_pressed = false

	for entry: Variant in sb.proficiencies:
		if not (entry is Dictionary):
			continue
		var ed: Dictionary = entry as Dictionary
		var prof_d: Variant = ed.get("proficiency", {})
		if not (prof_d is Dictionary):
			continue
		var prof_name: String = str((prof_d as Dictionary).get("name", ""))
		var prof_value: int = int(ed.get("value", 0))
		var w: Variant = _skill_widgets.get(prof_name)
		if w is Dictionary:
			if prof_value >= 2:
				((w as Dictionary).get("prof") as CheckBox).button_pressed = true
			if prof_value >= 4:
				((w as Dictionary).get("expert") as CheckBox).button_pressed = true


func _populate_features(sb: StatblockData) -> void:
	## Clear all sections — free container children directly, then reset rows.
	for src_key: String in _feature_sections.keys():
		var sec: Dictionary = _feature_sections[src_key] as Dictionary
		var container: VBoxContainer = sec.get("container") as VBoxContainer
		if container != null:
			for child: Node in container.get_children():
				child.queue_free()
		(sec.get("rows") as Array).clear()

	for f: Variant in sb.features:
		var src: String = ""
		var fname: String = ""
		var fdesc: String = ""
		if f is ActionEntry:
			var ae := f as ActionEntry
			src = ae.source
			fname = ae.name
			fdesc = ae.desc
		elif f is Dictionary:
			var fd: Dictionary = f as Dictionary
			src = str(fd.get("source", ""))
			fname = str(fd.get("name", ""))
			fdesc = str(fd.get("desc", ""))
		else:
			continue
		## Migrate legacy data that has no source tag
		if src.is_empty() and not fname.is_empty():
			src = _infer_feature_source(fname, sb)
		_add_feature_row(src, fname, fdesc)


func _populate_spell_slots(sb: StatblockData) -> void:
	for lvl: int in range(1, 10):
		var w: Variant = _slot_widgets.get(lvl)
		if not (w is Dictionary):
			continue
		var wd: Dictionary = w as Dictionary
		var max_sp: SpinBox = wd.get("max_spin") as SpinBox
		var used_sp: SpinBox = wd.get("used_spin") as SpinBox
		var avail_lbl: Label = wd.get("avail_label") as Label
		var slot_max: int = int(sb.spell_slots.get(lvl, 0))
		max_sp.value = slot_max
		var used_val: int = 0
		if _override != null:
			used_val = int(_override.spell_slots_used.get(str(lvl), 0))
		used_sp.value = used_val
		used_sp.max_value = slot_max
		avail_lbl.text = str(slot_max - used_val)


func _populate_inventory(sb: StatblockData) -> void:
	## Clear
	for row_data: Variant in _inventory_rows:
		if row_data is Dictionary:
			var r: Node = (row_data as Dictionary).get("row") as Node
			if r != null:
				r.queue_free()
	_inventory_rows.clear()

	for item: Variant in sb.inventory:
		if item is ItemEntry:
			var ie: ItemEntry = item as ItemEntry
			_on_add_inventory_item(
				ie.name, ie.quantity,
				str(ie.weight) if ie.weight > 0.0 else "",
				ie.equipped, ie.id)
		elif item is Dictionary:
			var id: Dictionary = item as Dictionary
			_on_add_inventory_item(
				str(id.get("name", "")),
				int(id.get("quantity", 1)),
				str(id.get("weight", "")),
				bool(id.get("equipped", false)),
				str(id.get("item_id", "")))


func _populate_proficiency_texts(sb: StatblockData) -> void:
	var armor_profs: PackedStringArray = PackedStringArray()
	var weapon_profs: PackedStringArray = PackedStringArray()
	var tool_profs: PackedStringArray = PackedStringArray()
	for entry: Variant in sb.proficiencies:
		if not (entry is Dictionary):
			continue
		var ed: Dictionary = entry as Dictionary
		var prof_d: Variant = ed.get("proficiency", {})
		if not (prof_d is Dictionary):
			continue
		var pname: String = str((prof_d as Dictionary).get("name", ""))
		if pname.is_empty():
			continue
		## Skip skill proficiencies (handled by toggles)
		if _skill_widgets.has(pname):
			continue
		## Skip saving throw proficiencies (handled by toggles)
		var pindex: String = str((prof_d as Dictionary).get("index", ""))
		if pindex in ABILITY_KEYS or pname.to_lower().begins_with("saving throw"):
			continue
		var pname_lower: String = pname.to_lower()
		if pname_lower.contains("armor") or pname_lower.contains("shield"):
			armor_profs.append(pname)
		elif pname_lower.contains("weapon") or pname_lower.contains("sword") \
				or pname_lower.contains("bow") or pname_lower.contains("crossbow") \
				or pname_lower.contains("axe") or pname_lower.contains("dagger") \
				or pname_lower.contains("mace") or pname_lower.contains("hammer") \
				or pname_lower.contains("rapier") or pname_lower.contains("pike") \
				or pname_lower.contains("halberd") or pname_lower.contains("flail") \
				or pname_lower.contains("spear") or pname_lower.contains("javelin") \
				or pname_lower.contains("trident") or pname_lower.contains("whip") \
				or pname_lower.contains("maul") or pname_lower.contains("morningstar") \
				or pname_lower.contains("scimitar") or pname_lower.contains("sling") \
				or pname_lower.contains("dart") or pname_lower.contains("club") \
				or pname_lower.contains("staff"):
			weapon_profs.append(pname)
		else:
			tool_profs.append(pname)
	_armor_prof_edit.text = ", ".join(armor_profs)
	_weapon_prof_edit.text = ", ".join(weapon_profs)
	_tool_prof_edit.text = ", ".join(tool_profs)


func _populate_tag_list(tag_list: Dictionary, values: Array) -> void:
	var flow: HFlowContainer = tag_list.get("flow") as HFlowContainer
	if flow == null:
		return
	## Clear
	for item: Variant in tag_list.get("items", []):
		if item is Node:
			(item as Node).queue_free()
	(tag_list["items"] as Array).clear()
	## Add tags
	for v: Variant in values:
		_add_tag_to_list(tag_list, str(v))


func _populate_condition_immunities(sb: StatblockData) -> void:
	var names: Array = []
	for ci: Variant in sb.condition_immunities:
		if ci is Dictionary:
			names.append(str((ci as Dictionary).get("name", "")))
		else:
			names.append(str(ci))
	_populate_tag_list(_cond_immune_list, names)


func _refresh_hp_from_override() -> void:
	if _override == null:
		return
	if _override.max_hp > 0:
		_hp_max_spin.value = _override.max_hp
		_hp_spin.value = _override.current_hp
		_temp_hp_spin.value = _override.temp_hp


func _refresh_derived() -> void:
	if _statblock == null:
		return
	var total_level: int = _get_total_level_from_rows()
	var prof: int = _proficiency_bonus(total_level)
	_prof_bonus_label.text = "+%d" % prof

	## Modifier labels
	for i: int in 6:
		var score: int = int((_score_spins[i] as SpinBox).value)
		var mod: int = int(floor((float(score) - 10.0) / 2.0))
		var mod_str: String = "+%d" % mod if mod >= 0 else str(mod)
		if _score_spins[i] is SpinBox:
			var parent_grid: Node = (_score_spins[i] as SpinBox).get_parent()
			if parent_grid != null:
				var lbl_node: Node = parent_grid.get_node_or_null("ModLabel_%d" % i)
				if lbl_node is Label:
					(lbl_node as Label).text = mod_str

	## Saving throws (4.3)
	for i: int in 6:
		var key: String = ABILITY_KEYS[i]
		var score: int = int((_score_spins[i] as SpinBox).value)
		var mod: int = int(floor((float(score) - 10.0) / 2.0))
		var w: Variant = _save_widgets.get(key)
		if not (w is Dictionary):
			continue
		var wd: Dictionary = w as Dictionary
		var is_proficient: bool = (wd.get("check") as CheckBox).button_pressed
		var total: int = mod + (prof if is_proficient else 0)
		var lbl: Label = wd.get("label") as Label
		var prefix: String = "● " if is_proficient else "○ "
		var total_str: String = "+%d" % total if total >= 0 else str(total)
		lbl.text = prefix + total_str

	## Skills (4.2)
	for sk: Variant in SKILLS:
		if not (sk is Dictionary):
			continue
		var sk_name: String = str((sk as Dictionary).get("name", ""))
		var sk_ability: String = str((sk as Dictionary).get("ability", "str"))
		var ab_idx: int = ABILITY_KEYS.find(sk_ability)
		var score: int = int((_score_spins[ab_idx] as SpinBox).value) if ab_idx >= 0 else 10
		var mod: int = int(floor((float(score) - 10.0) / 2.0))
		var w: Variant = _skill_widgets.get(sk_name)
		if not (w is Dictionary):
			continue
		var wd: Dictionary = w as Dictionary
		var is_prof: bool = (wd.get("prof") as CheckBox).button_pressed
		var is_expert: bool = (wd.get("expert") as CheckBox).button_pressed
		var bonus: int = mod
		if is_expert:
			bonus += prof * 2
		elif is_prof:
			bonus += prof
		var lbl: Label = wd.get("label") as Label
		var total_str: String = "+%d" % bonus if bonus >= 0 else str(bonus)
		lbl.text = total_str

	## Initiative (DEX mod)
	var dex_score: int = int((_score_spins[1] as SpinBox).value)
	var dex_mod: int = int(floor((float(dex_score) - 10.0) / 2.0))
	_init_label.text = "+%d" % dex_mod if dex_mod >= 0 else str(dex_mod)

	## Spell slot available labels
	for lvl: int in range(1, 10):
		var w: Variant = _slot_widgets.get(lvl)
		if w is Dictionary:
			var wd: Dictionary = w as Dictionary
			var mx: int = int((wd.get("max_spin") as SpinBox).value)
			var used: int = int((wd.get("used_spin") as SpinBox).value)
			(wd.get("avail_label") as Label).text = str(maxi(0, mx - used))


func _has_save_proficiency(ability_key: String) -> bool:
	if _statblock == null:
		return false
	for entry: Variant in _statblock.saving_throws:
		if entry is Dictionary:
			var prof_raw: Variant = (entry as Dictionary).get("proficiency", {})
			if prof_raw is Dictionary:
				if str((prof_raw as Dictionary).get("index", "")) == ability_key:
					return true
	return false


func _score_for_index(sb: StatblockData, idx: int) -> int:
	match idx:
		0: return sb.strength
		1: return sb.dexterity
		2: return sb.constitution
		3: return sb.intelligence
		4: return sb.wisdom
		5: return sb.charisma
	return 10


# ── Level Up ──────────────────────────────────────────────────────────────────
func _on_level_up() -> void:
	if _statblock == null:
		return
	_write_to_statblock()
	level_up_requested.emit(_statblock)


# ── Save ──────────────────────────────────────────────────────────────────────
func _on_save() -> void:
	if _statblock == null:
		return
	_write_to_statblock()
	_dirty = false
	character_saved.emit(_statblock)


func _write_to_statblock() -> void:
	var sb := _statblock
	sb.name = _name_edit.text.strip_edges()
	sb.race = _race_edit.text.strip_edges()
	sb.background = _bg_edit.text.strip_edges()

	## Classes (4.9)
	_write_classes(sb)

	sb.strength = int((_score_spins[0] as SpinBox).value)
	sb.dexterity = int((_score_spins[1] as SpinBox).value)
	sb.constitution = int((_score_spins[2] as SpinBox).value)
	sb.intelligence = int((_score_spins[3] as SpinBox).value)
	sb.wisdom = int((_score_spins[4] as SpinBox).value)
	sb.charisma = int((_score_spins[5] as SpinBox).value)

	sb.hit_points = int(_hp_max_spin.value)

	var speed_str: String = _speed_edit.text.strip_edges()
	if speed_str.is_empty():
		speed_str = "30 ft."
	sb.speed = {"walk": speed_str}

	var ac_val: int = int(_ac_spin.value)
	if sb.armor_class.is_empty():
		sb.armor_class = [ {"type": "natural", "value": ac_val}]
	else:
		var first: Variant = sb.armor_class[0]
		if first is Dictionary:
			(first as Dictionary)["value"] = ac_val

	## Saving throws (4.3)
	sb.saving_throws.clear()
	for i: int in 6:
		var key: String = ABILITY_KEYS[i]
		var w: Variant = _save_widgets.get(key)
		if w is Dictionary:
			if ((w as Dictionary).get("check") as CheckBox).button_pressed:
				sb.saving_throws.append({
					"proficiency": {"index": key, "name": ABILITY_NAMES[i]},
					"value": 0,
				})

	## Skill proficiencies (4.2)
	_write_proficiencies(sb)

	## Features (4.1)
	_write_features(sb)

	## Spell list — convert display names back to SRD indices for storage.
	if not _spells_text.text.strip_edges().is_empty():
		var spell_lines: PackedStringArray = _spells_text.text.split("\n", false)
		var lookup: Dictionary = _build_spell_lookup()
		var reg2 := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		sb.spell_list.clear()
		for sp_line: String in spell_lines:
			var trimmed: String = sp_line.strip_edges()
			## Skip level-header lines inserted by _resolve_spell_names.
			if trimmed.is_empty() or trimmed.begins_with("\u2014"):
				continue
			var info: Dictionary = _resolve_spell_entry(trimmed, lookup, reg2)
			sb.spell_list.append(str(info.get("index", trimmed)))
	else:
		sb.spell_list.clear()

	## Spell slots (4.6)
	sb.spell_slots.clear()
	for lvl: int in range(1, 10):
		var w: Variant = _slot_widgets.get(lvl)
		if w is Dictionary:
			var mx: int = int(((w as Dictionary).get("max_spin") as SpinBox).value)
			if mx > 0:
				sb.spell_slots[lvl] = mx
	## Sync slot usage to override
	if _override != null:
		_override.spell_slots_used.clear()
		for lvl: int in range(1, 10):
			var w: Variant = _slot_widgets.get(lvl)
			if w is Dictionary:
				var used: int = int(((w as Dictionary).get("used_spin") as SpinBox).value)
				if used > 0:
					_override.spell_slots_used[str(lvl)] = used

	## Inventory (4.8)
	_write_inventory(sb)

	## Defenses (4.5)
	sb.damage_resistances = _collect_tag_names(_resist_list)
	sb.damage_immunities = _collect_tag_names(_immune_list)
	sb.damage_vulnerabilities = _collect_tag_names(_vuln_list)
	sb.condition_immunities.clear()
	for cn: String in _collect_tag_names(_cond_immune_list):
		sb.condition_immunities.append({"index": cn.to_lower().replace(" ", "-"), "name": cn})

	## Senses (4.7)
	sb.senses = {"passive_perception": int(_passive_perc_spin.value)}
	if int(_darkvision_spin.value) > 0:
		sb.senses["darkvision"] = "%d ft." % int(_darkvision_spin.value)

	## Languages
	sb.languages = _language_edit.text.strip_edges()

	sb.notes = _notes_text.text

	## If override exists, sync current HP changes back
	if _override != null:
		_override.current_hp = int(_hp_spin.value)
		_override.max_hp = int(_hp_max_spin.value)
		_override.temp_hp = int(_temp_hp_spin.value)

	sb.proficiency_bonus = _proficiency_bonus(sb.level)


func _write_classes(sb: StatblockData) -> void:
	sb.classes.clear()
	var total_lvl: int = 0
	for child: Node in _classes_container.get_children():
		if not child.is_queued_for_deletion() and child is HBoxContainer:
			var class_edit: LineEdit = child.get_node_or_null("ClassEdit") as LineEdit
			var level_sp: SpinBox = child.get_node_or_null("LevelSpin") as SpinBox
			var sub_edit: LineEdit = child.get_node_or_null("SubEdit") as LineEdit
			if class_edit != null and level_sp != null:
				var cn: String = class_edit.text.strip_edges()
				var lv: int = int(level_sp.value)
				var sc: String = ""
				if sub_edit != null:
					sc = sub_edit.text.strip_edges()
				if not cn.is_empty():
					sb.classes.append({"name": cn, "level": lv, "subclass": sc})
					total_lvl += lv
	## Keep legacy fields in sync
	if not sb.classes.is_empty():
		var primary: Dictionary = sb.classes[0] as Dictionary
		sb.class_name_str = str(primary.get("name", ""))
		sb.level = total_lvl
	else:
		sb.class_name_str = ""
		sb.level = 0


func _write_proficiencies(sb: StatblockData) -> void:
	## Start from skill proficiencies
	sb.proficiencies.clear()
	for sk: Variant in SKILLS:
		if not (sk is Dictionary):
			continue
		var sk_name: String = str((sk as Dictionary).get("name", ""))
		var w: Variant = _skill_widgets.get(sk_name)
		if not (w is Dictionary):
			continue
		var wd: Dictionary = w as Dictionary
		var is_prof: bool = (wd.get("prof") as CheckBox).button_pressed
		var is_expert: bool = (wd.get("expert") as CheckBox).button_pressed
		if is_prof or is_expert:
			var val: int = 4 if is_expert else 2
			sb.proficiencies.append({
				"proficiency": {"index": sk_name.to_lower().replace(" ", "-"), "name": sk_name},
				"value": val,
			})

	## Armor, Weapon, Tool proficiencies from text edits (4.4)
	_append_text_profs(sb, _armor_prof_edit)
	_append_text_profs(sb, _weapon_prof_edit)
	_append_text_profs(sb, _tool_prof_edit)


func _append_text_profs(sb: StatblockData, edit: TextEdit) -> void:
	if edit == null:
		return
	var entries: PackedStringArray = edit.text.split(",", false)
	for entry: String in entries:
		var trimmed: String = entry.strip_edges()
		if not trimmed.is_empty():
			sb.proficiencies.append({
				"proficiency": {"index": trimmed.to_lower().replace(" ", "-"), "name": trimmed},
				"value": 1,
			})


func _write_features(sb: StatblockData) -> void:
	sb.features.clear()
	for src_entry: Variant in FEATURE_SOURCES:
		if not (src_entry is Dictionary):
			continue
		var src_key: String = str((src_entry as Dictionary).get("key", ""))
		var sec: Variant = _feature_sections.get(src_key)
		if not (sec is Dictionary):
			continue
		var container: VBoxContainer = (sec as Dictionary).get("container") as VBoxContainer
		if container == null:
			continue
		for child: Node in container.get_children():
			if child.is_queued_for_deletion():
				continue
			var name_edit: LineEdit = child.find_child("FeatureName", true, false) as LineEdit
			var desc_node: RichTextLabel = child.get_node_or_null("FeatureDesc") as RichTextLabel
			if name_edit != null and desc_node != null:
				var fn: String = name_edit.text.strip_edges()
				var fd: String = desc_node.text.strip_edges()
				if not fn.is_empty() or not fd.is_empty():
					sb.features.append({"name": fn, "desc": fd, "source": src_key})


func _write_inventory(sb: StatblockData) -> void:
	sb.inventory.clear()
	for row_data: Variant in _inventory_rows:
		if not (row_data is Dictionary):
			continue
		var rd: Dictionary = row_data as Dictionary
		var row_node: Node = rd.get("row") as Node
		if row_node == null or row_node.is_queued_for_deletion():
			continue
		var item_name: String = (rd.get("name_edit") as LineEdit).text.strip_edges()
		if item_name.is_empty():
			continue
		var entry: Dictionary = {
			"name": item_name,
			"quantity": int((rd.get("qty_spin") as SpinBox).value),
			"weight": (rd.get("weight_edit") as LineEdit).text.strip_edges(),
			"equipped": (rd.get("equipped_check") as CheckBox).button_pressed,
		}
		var stored_id: String = str(rd.get("item_id", ""))
		if not stored_id.is_empty():
			entry["item_id"] = stored_id
		sb.inventory.append(entry)


# ── Widget change handlers ────────────────────────────────────────────────────
func _on_ability_changed(_value: float, _idx: int) -> void:
	_dirty = true
	_refresh_derived()


func _on_value_changed(_value: float) -> void:
	_dirty = true
	_refresh_derived()


func _on_text_changed(_text: String) -> void:
	_dirty = true


func _on_text_edit_changed() -> void:
	_dirty = true


func _mark_dirty_and_refresh() -> void:
	_dirty = true
	_refresh_derived()


func _on_close_requested() -> void:
	if _dirty:
		var dlg := ConfirmationDialog.new()
		dlg.dialog_text = "Save changes before closing?"
		dlg.ok_button_text = "Save & Close"
		dlg.cancel_button_text = "Discard"
		dlg.exclusive = false
		add_child(dlg)
		var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
		var s: float = _get_ui_scale()
		if reg != null and reg.ui_theme != null:
			reg.ui_theme.prepare_window(dlg, 15.0)
		dlg.min_size = Vector2i(roundi(300.0 * s), roundi(120.0 * s))
		dlg.reset_size()
		dlg.popup_centered()
		dlg.confirmed.connect(func() -> void:
			_on_save()
			hide()
			dlg.queue_free())
		dlg.canceled.connect(func() -> void:
			_dirty = false
			hide()
			dlg.queue_free())
	else:
		hide()


# ── Dynamic row builders ─────────────────────────────────────────────────────

## Add a class row to the multiclass header (4.9)
func _on_add_class_row(class_name_str: String, lvl: int,
		subclass_str: String) -> void:
	var s: float = _get_ui_scale()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(4.0 * s))

	var class_edit := LineEdit.new()
	class_edit.name = "ClassEdit"
	class_edit.placeholder_text = "Class"
	class_edit.text = class_name_str
	class_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	class_edit.custom_minimum_size.x = roundi(100.0 * s)
	class_edit.text_changed.connect(_on_text_changed)
	row.add_child(class_edit)

	var lbl := Label.new()
	lbl.text = "Lv:"
	row.add_child(lbl)

	var level_sp := SpinBox.new()
	level_sp.name = "LevelSpin"
	level_sp.min_value = 1
	level_sp.max_value = 20
	level_sp.value = lvl
	level_sp.custom_minimum_size.x = roundi(60.0 * s)
	level_sp.value_changed.connect(_on_value_changed)
	row.add_child(level_sp)

	var sub_edit := LineEdit.new()
	sub_edit.name = "SubEdit"
	sub_edit.placeholder_text = "Subclass"
	sub_edit.text = subclass_str
	sub_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_edit.custom_minimum_size.x = roundi(80.0 * s)
	sub_edit.text_changed.connect(_on_text_changed)
	row.add_child(sub_edit)

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.pressed.connect(func() -> void:
		row.queue_free()
		_dirty = true
		_refresh_derived())
	row.add_child(remove_btn)

	_classes_container.add_child(row)
	_scale_new_row(row)
	_dirty = true


## Add a feature row (4.1)
func _on_add_feature(src_key: String) -> void:
	if src_key == "feat":
		_show_feat_picker()
		return
	_add_feature_row(src_key, "", "")
	_dirty = true


func _show_feat_picker() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.srd == null:
		_add_feature_row("feat", "", "")
		_dirty = true
		return
	var ruleset: String = _active_ruleset()
	var feats: Array = reg.srd.get_feats(ruleset)
	if feats.is_empty():
		_add_feature_row("feat", "", "")
		_dirty = true
		return
	var s: float = _get_ui_scale()
	var dialog := ConfirmationDialog.new()
	dialog.title = "Add Feat"
	dialog.ok_button_text = "Select"
	dialog.cancel_button_text = "Cancel"
	dialog.exclusive = false
	dialog.min_size = Vector2i(roundi(420.0 * s), roundi(380.0 * s))
	dialog.get_ok_button().disabled = true
	add_child(dialog)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", roundi(6.0 * s))
	dialog.add_child(vb)
	var hint_lbl := Label.new()
	hint_lbl.text = "Select a feat, then click Select (or double-click)."
	hint_lbl.add_theme_font_size_override("font_size", roundi(13.0 * s))
	vb.add_child(hint_lbl)
	var search_edit := LineEdit.new()
	search_edit.placeholder_text = "Search feats…"
	vb.add_child(search_edit)
	var item_list := ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.add_theme_font_size_override("font_size", roundi(16.0 * s))
	vb.add_child(item_list)
	for fd: Variant in feats:
		if not fd is Dictionary:
			continue
		var d: Dictionary = fd as Dictionary
		var idx: int = item_list.add_item(str(d.get("name", "")))
		item_list.set_item_metadata(idx, d)
	search_edit.text_changed.connect(func(query: String) -> void:
		item_list.clear()
		dialog.get_ok_button().disabled = true
		var q: String = query.strip_edges().to_lower()
		for fd2: Variant in feats:
			if not fd2 is Dictionary:
				continue
			var d2: Dictionary = fd2 as Dictionary
			var nm: String = str(d2.get("name", ""))
			if q.is_empty() or nm.to_lower().contains(q):
				var idx2: int = item_list.add_item(nm)
				item_list.set_item_metadata(idx2, d2))
	## Enable "Select" when an item is clicked
	item_list.item_selected.connect(func(_idx: int) -> void:
		dialog.get_ok_button().disabled = false)
	## Helper to finalize feat application after all choice dialogs.
	var finalize_feat: Callable = func(d3: Dictionary, choices: Dictionary) -> void:
		var nm3: String = str(d3.get("name", ""))
		var desc3: String = str(d3.get("desc", nm3))
		## Build choice summary to append to description
		var parts: PackedStringArray = PackedStringArray()
		var chosen_ability: String = str(choices.get("ability", ""))
		if not chosen_ability.is_empty():
			var ab_i: int = ABILITY_KEYS.find(chosen_ability)
			var ab_nm: String = ABILITY_NAMES[ab_i] if ab_i >= 0 and ab_i < ABILITY_NAMES.size() else chosen_ability.to_upper()
			parts.append("Ability: " + ab_nm)
		for ck: String in ["element", "class"]:
			var cv: String = str(choices.get(ck, ""))
			if not cv.is_empty():
				parts.append(ck.capitalize() + ": " + _format_choice_option(ck, cv))
		for ck2: String in ["language", "skill_or_tool", "weapon"]:
			var arr: Variant = choices.get(ck2, null)
			if arr is Array and not (arr as Array).is_empty():
				var dnms: PackedStringArray = PackedStringArray()
				for v: Variant in arr as Array:
					dnms.append(_format_choice_option(ck2, str(v)))
				parts.append(ck2.replace("_", " ").capitalize() + ": " + ", ".join(dnms))
		if not parts.is_empty():
			desc3 += "\n[Chosen: " + "; ".join(parts) + "]"
		_add_feature_row("feat", "Feat: " + nm3, desc3)
		_apply_feat_asi(d3)
		## Apply ability choice if one was made
		if not chosen_ability.is_empty():
			var ab_idx4: int = ABILITY_KEYS.find(chosen_ability)
			if ab_idx4 >= 0 and ab_idx4 < _score_spins.size():
				var sp: SpinBox = _score_spins[ab_idx4] as SpinBox
				sp.value = sp.value + 1.0
		## Apply save proficiency from ability choice if flagged
		var save_prof_flag: bool = choices.get("grants_save_proficiency", false)
		if save_prof_flag and not chosen_ability.is_empty():
			var sw: Variant = _save_widgets.get(chosen_ability)
			if sw is Dictionary and (sw as Dictionary).has("check"):
				var cb_save: CheckBox = (sw as Dictionary)["check"] as CheckBox
				if cb_save != null:
					cb_save.button_pressed = true
		## Apply passive perception bonus
		var pp_bonus: int = int(d3.get("passive_perception_bonus", 0))
		if pp_bonus != 0 and _passive_perc_spin != null:
			_passive_perc_spin.value = _passive_perc_spin.value + float(pp_bonus)
		_dirty = true
	## Helper to apply selected feat — starts the choice chain if needed.
	var apply_selected: Callable = func() -> void:
		var sel: PackedInt32Array = item_list.get_selected_items()
		if sel.is_empty():
			return
		var md: Variant = item_list.get_item_metadata(sel[0])
		if not (md is Dictionary):
			dialog.queue_free()
			return
		var d3: Dictionary = md as Dictionary
		dialog.queue_free()
		## Collect choices array from feat data
		var choices_var: Variant = d3.get("choices", [])
		if not (choices_var is Array) or (choices_var as Array).is_empty():
			finalize_feat.call(d3, {})
			return
		## Filter to supported types (skip spell for now)
		var supported: Array = []
		for ch_var: Variant in choices_var as Array:
			if not (ch_var is Dictionary):
				continue
			var ch_type: String = str((ch_var as Dictionary).get("type", ""))
			if ch_type != "spell":
				supported.append(ch_var as Dictionary)
		if supported.is_empty():
			finalize_feat.call(d3, {})
			return
		_show_feat_choice_chain(d3, supported, {}, finalize_feat)
	## Double-click selects and confirms immediately
	item_list.item_activated.connect(func(_idx3: int) -> void: apply_selected.call())
	## OK button confirms current selection
	dialog.confirmed.connect(func() -> void: apply_selected.call())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	dialog.close_requested.connect(func() -> void: dialog.queue_free())
	## Apply theme/scaling to the dialog tree
	if reg.ui_theme != null:
		reg.ui_theme.prepare_window(dialog, 16.0)
	dialog.reset_size()
	dialog.popup_centered()


func _show_feat_choice_chain(feat_dict: Dictionary, remaining: Array,
		accumulated: Dictionary, final_callback: Callable) -> void:
	## Process feat choices one at a time, chaining dialogs.
	if remaining.is_empty():
		final_callback.call(feat_dict, accumulated)
		return
	var choice: Dictionary = remaining[0] as Dictionary
	var rest: Array = remaining.slice(1)
	var ctype: String = str(choice.get("type", ""))
	var options_var: Variant = choice.get("options", [])
	var options: Array = options_var as Array if options_var is Array else []
	var count: int = int(choice.get("count", 1))
	var label: String = str(choice.get("label", ctype.replace("_", " ").capitalize()))
	var grants_save: bool = choice.get("grants_save_proficiency", false) == true

	match ctype:
		"ability":
			_show_feat_single_choice(feat_dict, label, ctype, options,
				func(val: String) -> void:
					accumulated["ability"] = val
					if grants_save:
						accumulated["grants_save_proficiency"] = true
					_show_feat_choice_chain(feat_dict, rest, accumulated, final_callback))
		"element", "class":
			_show_feat_single_choice(feat_dict, label, ctype, options,
				func(val: String) -> void:
					accumulated[ctype] = val
					_show_feat_choice_chain(feat_dict, rest, accumulated, final_callback))
		"language", "skill_or_tool", "weapon":
			_show_feat_multi_choice(feat_dict, label, ctype, options, count,
				func(vals: Array) -> void:
					accumulated[ctype] = vals
					_show_feat_choice_chain(feat_dict, rest, accumulated, final_callback))
		_:
			## Unknown type — skip
			_show_feat_choice_chain(feat_dict, rest, accumulated, final_callback)


func _show_feat_single_choice(feat_dict: Dictionary, label: String,
		choice_type: String, options: Array, callback: Callable) -> void:
	## Single-select choice dialog with an OptionButton.
	var s: float = _get_ui_scale()
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var dlg := ConfirmationDialog.new()
	dlg.title = "Choose %s — %s" % [label, str(feat_dict.get("name", "Feat"))]
	dlg.ok_button_text = "Apply"
	dlg.cancel_button_text = "Cancel"
	dlg.exclusive = false
	dlg.min_size = Vector2i(roundi(320.0 * s), roundi(160.0 * s))
	dlg.get_ok_button().disabled = true
	add_child(dlg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", roundi(8.0 * s))
	dlg.add_child(vb)
	var hint := Label.new()
	hint.text = label + ":"
	hint.add_theme_font_size_override("font_size", roundi(14.0 * s))
	vb.add_child(hint)
	var option_btn := OptionButton.new()
	option_btn.add_theme_font_size_override("font_size", roundi(14.0 * s))
	option_btn.add_item("— choose —")
	for opt: Variant in options:
		var key: String = str(opt)
		var display: String = _format_choice_option(choice_type, key)
		option_btn.add_item(display)
		option_btn.set_item_metadata(option_btn.item_count - 1, key)
	option_btn.item_selected.connect(func(idx: int) -> void:
		dlg.get_ok_button().disabled = (idx == 0))
	vb.add_child(option_btn)
	dlg.confirmed.connect(func() -> void:
		var sel_idx: int = option_btn.selected
		var chosen: String = ""
		if sel_idx > 0:
			chosen = str(option_btn.get_item_metadata(sel_idx))
		callback.call(chosen)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.close_requested.connect(func() -> void: dlg.queue_free())
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg, 14.0)
	dlg.reset_size()
	dlg.popup_centered()


func _show_feat_multi_choice(feat_dict: Dictionary, label: String,
		choice_type: String, options: Array, count: int,
		callback: Callable) -> void:
	## Multi-select choice dialog with an ItemList.
	var s: float = _get_ui_scale()
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var dlg := ConfirmationDialog.new()
	dlg.title = "Choose %s — %s" % [label, str(feat_dict.get("name", "Feat"))]
	dlg.ok_button_text = "Apply"
	dlg.cancel_button_text = "Cancel"
	dlg.exclusive = false
	dlg.min_size = Vector2i(roundi(380.0 * s), roundi(350.0 * s))
	dlg.get_ok_button().disabled = true
	add_child(dlg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", roundi(6.0 * s))
	dlg.add_child(vb)
	var hint := Label.new()
	hint.text = "Select %d (click to toggle):" % count
	hint.add_theme_font_size_override("font_size", roundi(13.0 * s))
	vb.add_child(hint)
	var il := ItemList.new()
	il.select_mode = ItemList.SELECT_MULTI
	il.size_flags_vertical = Control.SIZE_EXPAND_FILL
	il.add_theme_font_size_override("font_size", roundi(14.0 * s))
	for opt: Variant in options:
		var key: String = str(opt)
		var display: String = _format_choice_option(choice_type, key)
		var idx: int = il.add_item(display)
		il.set_item_metadata(idx, key)
	vb.add_child(il)
	var count_lbl := Label.new()
	count_lbl.text = "0 / %d selected" % count
	count_lbl.add_theme_font_size_override("font_size", roundi(12.0 * s))
	vb.add_child(count_lbl)
	## Track selection count via multi_selected signal
	il.multi_selected.connect(func(_idx: int, _selected: bool) -> void:
		var n: int = il.get_selected_items().size()
		count_lbl.text = "%d / %d selected" % [n, count]
		dlg.get_ok_button().disabled = (n != count))
	dlg.confirmed.connect(func() -> void:
		var chosen: Array = []
		for si: int in il.get_selected_items():
			chosen.append(str(il.get_item_metadata(si)))
		callback.call(chosen)
		dlg.queue_free())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.close_requested.connect(func() -> void: dlg.queue_free())
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg, 14.0)
	dlg.reset_size()
	dlg.popup_centered()


func _format_choice_option(choice_type: String, value: String) -> String:
	## Format a raw choice option key for display.
	match choice_type:
		"ability":
			var idx: int = ABILITY_KEYS.find(value)
			if idx >= 0 and idx < ABILITY_NAMES.size():
				return ABILITY_NAMES[idx]
			return value.to_upper()
		"skill_or_tool":
			if value.begins_with("skill-"):
				return value.substr(6).replace("-", " ").capitalize()
			return value.replace("-", " ").capitalize()
		_:
			return value.replace("-", " ").capitalize()


func _add_feature_row(src_key: String, fname: String, fdesc: String) -> void:
	var s: float = _get_ui_scale()
	## Map empty/custom source to ""
	var resolved_key: String = src_key
	if resolved_key == "custom":
		resolved_key = ""
	var sec: Variant = _feature_sections.get(resolved_key)
	if not (sec is Dictionary):
		push_warning("CharacterSheet: feature source '%s' not found in _feature_sections (keys: %s). Falling back to Custom." % [resolved_key, str(_feature_sections.keys())])
		sec = _feature_sections.get("")
	if not (sec is Dictionary):
		return
	var container: VBoxContainer = (sec as Dictionary).get("container") as VBoxContainer
	if container == null:
		return

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(2.0 * s))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", roundi(4.0 * s))
	row.add_child(top_row)

	var name_edit := LineEdit.new()
	name_edit.name = "FeatureName"
	name_edit.placeholder_text = "Feature name"
	name_edit.text = fname
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(_on_text_changed)
	top_row.add_child(name_edit)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.pressed.connect(func() -> void:
		row.queue_free()
		_dirty = true)
	top_row.add_child(del_btn)

	var desc_edit := RichTextLabel.new()
	desc_edit.name = "FeatureDesc"
	desc_edit.bbcode_enabled = false
	desc_edit.fit_content = true
	desc_edit.scroll_active = false
	desc_edit.text = fdesc
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_edit.mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_font_base(desc_edit, 13.0)
	row.add_child(desc_edit)

	container.add_child(row)
	((sec as Dictionary)["rows"] as Array).append({"row": row})
	_scale_new_row(row)


## Add an inventory item row (4.8)
func _on_add_inventory_item(item_name: String, qty: int, weight: String,
		equipped: bool, item_id: String = "") -> void:
	var s: float = _get_ui_scale()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(4.0 * s))

	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Item name"
	name_edit.text = item_name
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(_on_text_changed)
	name_edit.tooltip_text = "Double-click to view details" if not item_id.is_empty() else ""
	name_edit.gui_input.connect(_on_inventory_name_gui_input.bind(name_edit))
	row.add_child(name_edit)

	var qty_spin := SpinBox.new()
	qty_spin.min_value = 1
	qty_spin.max_value = 999
	qty_spin.value = qty
	qty_spin.tooltip_text = "Quantity"
	qty_spin.custom_minimum_size.x = roundi(60.0 * s)
	qty_spin.value_changed.connect(_on_value_changed)
	row.add_child(qty_spin)

	var weight_edit := LineEdit.new()
	weight_edit.placeholder_text = "Wt."
	weight_edit.text = weight
	weight_edit.custom_minimum_size.x = roundi(50.0 * s)
	weight_edit.text_changed.connect(_on_text_changed)
	row.add_child(weight_edit)

	var equipped_check := CheckBox.new()
	equipped_check.text = "Eq"
	equipped_check.tooltip_text = "Equipped"
	equipped_check.button_pressed = equipped
	equipped_check.toggled.connect(func(_on: bool) -> void: _dirty = true)
	row.add_child(equipped_check)

	var del_btn := Button.new()
	del_btn.text = "✕"
	del_btn.pressed.connect(_make_inventory_remove_callback(row))
	row.add_child(del_btn)

	_inventory_container.add_child(row)
	_inventory_rows.append({
		"row": row, "name_edit": name_edit, "qty_spin": qty_spin,
		"weight_edit": weight_edit, "equipped_check": equipped_check,
		"item_id": item_id,
	})
	_scale_new_row(row)
	_dirty = true
	_refresh_inventory_totals()


func _make_inventory_remove_callback(row: HBoxContainer) -> Callable:
	return func() -> void:
		var idx: int = -1
		for i: int in range(_inventory_rows.size()):
			var rd: Variant = _inventory_rows[i]
			if rd is Dictionary and (rd as Dictionary).get("row") == row:
				idx = i
				break
		if idx >= 0:
			_inventory_rows.remove_at(idx)
		row.queue_free()
		_dirty = true
		_refresh_inventory_totals()


func _on_add_from_item_library() -> void:
	if _inventory_library != null and is_instance_valid(_inventory_library):
		_inventory_library.show()
		_inventory_library.grab_focus()
		return
	_inventory_library = ItemLibrary.new()
	_inventory_library.set_pick_mode(true)
	add_child(_inventory_library)
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(_inventory_library, _get_ui_scale())
	_inventory_library.item_picked.connect(_on_library_item_picked)
	_inventory_library.popup_centered()


func _on_library_item_picked(data: ItemEntry) -> void:
	if not data.id.is_empty():
		for rd_var: Variant in _inventory_rows:
			if not (rd_var is Dictionary):
				continue
			var rd: Dictionary = rd_var as Dictionary
			if str(rd.get("item_id", "")) == data.id:
				var spin: SpinBox = rd.get("qty_spin") as SpinBox
				if spin != null:
					spin.value += 1
					_dirty = true
					_refresh_inventory_totals()
				return
	var wt: String = str(data.weight) if data.weight > 0.0 else ""
	_on_add_inventory_item(data.name, 1, wt, false, data.id)
	_refresh_inventory_totals()


func _on_inventory_name_gui_input(event: InputEvent, name_edit: LineEdit) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.double_click:
		return
	## Find the row dict for this name_edit.
	var row_item_id: String = ""
	for rd_var: Variant in _inventory_rows:
		if not (rd_var is Dictionary):
			continue
		var rd: Dictionary = rd_var as Dictionary
		if rd.get("name_edit") == name_edit:
			row_item_id = str(rd.get("item_id", ""))
			break
	if row_item_id.is_empty():
		return
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.item == null:
		return
	var entry: ItemEntry = reg.item.get_item(row_item_id)
	if entry == null:
		return
	_show_item_detail(entry)


func _show_item_detail(entry: ItemEntry) -> void:
	var s: float = _get_ui_scale()
	var dlg := AcceptDialog.new()
	dlg.title = entry.name
	dlg.exclusive = false
	dlg.wrap_controls = true

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2i(roundi(420.0 * s), roundi(340.0 * s))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dlg.add_child(scroll)

	var card := ItemCardView.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(card)
	card.display(entry)
	card.apply_font_scale(roundi(14.0 * s))

	add_child(dlg)
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg, 14.0)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)


func _refresh_inventory_totals() -> void:
	var total_weight: float = 0.0
	var attuned: int = 0
	for row_data: Variant in _inventory_rows:
		if not (row_data is Dictionary):
			continue
		var rd: Dictionary = row_data as Dictionary
		var row_node: Node = rd.get("row") as Node
		if row_node == null or row_node.is_queued_for_deletion():
			continue
		var w_text: String = (rd.get("weight_edit") as LineEdit).text.strip_edges()
		if w_text.is_valid_float():
			var qty: float = (rd.get("qty_spin") as SpinBox).value
			total_weight += w_text.to_float() * qty
	if _inventory_weight_lbl != null:
		_inventory_weight_lbl.text = "Total weight: %s lb" % str(snappedi(roundi(total_weight * 100), 1) / 100.0)
	if _inventory_attune_lbl != null:
		_inventory_attune_lbl.text = "Attuned: %d/3" % attuned


# ── Tag list helpers ─────────────────────────────────────────────────────────

func _make_tag_add_callback(tag_list: Dictionary,
		opt: OptionButton) -> Callable:
	return func() -> void:
		if opt.selected < 0:
			return
		var tag_name: String = opt.get_item_text(opt.selected)
		## Prevent duplicates
		for existing: Variant in tag_list.get("items", []):
			if existing is Button and (existing as Button).text.begins_with(tag_name):
				return
		_add_tag_to_list(tag_list, tag_name)
		_dirty = true


func _add_tag_to_list(tag_list: Dictionary, tag_name: String) -> void:
	var flow: HFlowContainer = tag_list.get("flow") as HFlowContainer
	if flow == null:
		return
	var btn := Button.new()
	btn.text = tag_name + " ✕"
	btn.tooltip_text = "Click to remove"
	btn.pressed.connect(func() -> void:
		(tag_list["items"] as Array).erase(btn)
		btn.queue_free()
		_dirty = true)
	flow.add_child(btn)
	(tag_list["items"] as Array).append(btn)


func _collect_tag_names(tag_list: Dictionary) -> Array:
	var result: Array = []
	for item: Variant in tag_list.get("items", []):
		if item is Button:
			var txt: String = (item as Button).text
			## Strip " ✕" suffix
			if txt.ends_with(" ✕"):
				txt = txt.left(txt.length() - 2)
			result.append(txt)
	return result


# ── Collapse handler ─────────────────────────────────────────────────────────
func _make_collapse_handler(section_lbl: Label,
		rows_container: VBoxContainer) -> Callable:
	return func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			rows_container.visible = not rows_container.visible
			if rows_container.visible:
				section_lbl.text = "▼ " + section_lbl.text.substr(2)
			else:
				section_lbl.text = "▶ " + section_lbl.text.substr(2)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_ui_scale() -> float:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.ui_scale != null:
		return reg.ui_scale.get_scale()
	return 1.0


func reapply_theme() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null:
		return
	var s: float = _get_ui_scale()
	if reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(self , s)
	if reg.ui_scale != null:
		reg.ui_scale.scale_control_fonts(_first_control_child_of(self ), 16.0)


func _scale_new_row(row: Control) -> void:
	## Apply theme + font scaling to a dynamically added row so it matches
	## the rest of the sheet without re-walking the entire tree.
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null:
		return
	var s: float = _get_ui_scale()
	if reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(row, s)
	if reg.ui_scale != null:
		reg.ui_scale.scale_control_fonts(row, 16.0)


func _apply_font_base(ctrl: Control, base: float) -> void:
	## Tag a control with a per-node font base.  scale_control_fonts reads
	## the "_font_base" meta automatically — no separate hierarchy pass needed.
	UIScaleManager.set_font_base(ctrl, base)
	ctrl.add_theme_font_size_override("font_size", roundi(base * _get_ui_scale()))


func _first_control_child_of(win: Window) -> Control:
	for child: Node in win.get_children():
		if child is Control and child.name != &"_ThemeBG":
			return child as Control
	return null


func _labeled_line_edit(parent: GridContainer, label_text: String,
		placeholder: String) -> LineEdit:
	var lbl := Label.new()
	lbl.text = label_text
	_apply_font_base(lbl, 18.0)
	parent.add_child(lbl)
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.text_changed.connect(_on_text_changed)
	_apply_font_base(le, 18.0)
	parent.add_child(le)
	return le


static func _make_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	return lbl


func _make_section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	_apply_font_base(lbl, 18.0)
	return lbl


func _make_mini_text_edit(placeholder: String) -> TextEdit:
	var s: float = _get_ui_scale()
	var te := TextEdit.new()
	te.placeholder_text = placeholder
	te.custom_minimum_size.y = roundi(50.0 * s)
	te.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	te.text_changed.connect(_on_text_edit_changed)
	return te


static func _proficiency_bonus(lvl: int) -> int:
	if lvl < 1:
		return 2
	return int(ceil(float(lvl) / 4.0)) + 1


func _get_total_level_from_rows() -> int:
	var total: int = 0
	for child: Node in _classes_container.get_children():
		if child.is_queued_for_deletion() or not (child is HBoxContainer):
			continue
		var level_sp: SpinBox = child.get_node_or_null("LevelSpin") as SpinBox
		if level_sp != null:
			total += int(level_sp.value)
	return maxi(total, 1)


static func _parse_feet(text: String) -> int:
	var stripped: String = text.replace("ft.", "").replace("ft", "").strip_edges()
	if stripped.is_valid_int():
		return int(stripped)
	return 0


static func _infer_feature_source(fname: String, sb: StatblockData) -> String:
	## Heuristic migration for legacy features without a source tag.
	var lower: String = fname.to_lower()
	## Feats always have "Feat: " prefix from wizard
	if fname.begins_with("Feat: ") or lower == "initiative bonus":
		return "feat"
	## Known class features
	if lower in ["fighting style", "favored enemy", "natural explorer",
			"expertise", "eldritch invocations", "pact boon",
			"sneak attack", "rage", "wild shape", "channel divinity",
			"action surge", "second wind", "arcane recovery",
			"bardic inspiration", "lay on hands", "divine smite",
			"unarmored defense", "ki", "metamagic", "sorcery points"]:
		return "class"
	## Subclass marker
	if lower == "subclass":
		return "subclass"
	## Draconic ancestry is a racial feature
	if lower == "draconic ancestry":
		return "race"
	## If race name appears in the statblock, try matching known SRD racial trait style
	## (short plain names without "Feat: " prefix are likely racial traits)
	if not sb.race.is_empty() and not fname.begins_with("Feat: ") \
			and not lower.contains("style") and not lower.contains("invocation"):
		return "race"
	return ""


func _build_spell_lookup() -> Dictionary:
	## Build a case-insensitive display-name → index map for all SRD spells.
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var ruleset: String = _active_ruleset()
	var lookup: Dictionary = {} # String (lower-name) -> String (index)
	if reg != null and reg.srd != null:
		for sd_var: Variant in reg.srd.get_spells(ruleset):
			if sd_var is SpellData:
				var sd: SpellData = sd_var as SpellData
				lookup[sd.name.to_lower()] = sd.index
	return lookup


func _resolve_spell_entry(entry: String, lookup: Dictionary, reg: ServiceRegistry) -> Dictionary:
	## Given a spell_list entry (index or display name), resolve to
	## {"index": String, "name": String, "level": int}.
	var idx: String = entry
	var display: String = entry
	var lvl: int = -1
	var ruleset: String = _active_ruleset()
	if reg != null and reg.srd != null:
		## Try direct index lookup first.
		var sd: SpellData = reg.srd.get_spell(idx, ruleset)
		if sd == null:
			## Fall back to display-name → index.
			var mapped: Variant = lookup.get(entry.to_lower(), "")
			if str(mapped) != "":
				idx = str(mapped)
				sd = reg.srd.get_spell(idx, ruleset)
		if sd != null:
			if not sd.name.is_empty():
				display = sd.name
			idx = sd.index
			lvl = sd.level
	return {"index": idx, "name": display, "level": lvl}


func _resolve_spell_names(spell_list: Array) -> String:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var lookup: Dictionary = _build_spell_lookup()
	## Bucket spells by level for sorted display.
	var by_level: Dictionary = {} # int -> Array[String]
	for sp_var: Variant in spell_list:
		var sp_str: String = str(sp_var)
		if sp_str.is_empty():
			continue
		var info: Dictionary = _resolve_spell_entry(sp_str, lookup, reg)
		var lvl: int = int(info.get("level", -1))
		var display: String = str(info.get("name", sp_str))
		if not by_level.has(lvl):
			by_level[lvl] = [] as Array[String]
		(by_level[lvl] as Array[String]).append(display)
	## Sort level keys and build output with headers.
	var keys: Array = by_level.keys()
	keys.sort()
	var lines: PackedStringArray = PackedStringArray()
	for k_var: Variant in keys:
		var k: int = int(k_var)
		var header: String
		if k < 0:
			header = "\u2014 Unknown Level \u2014"
		elif k == 0:
			header = "\u2014 Cantrips \u2014"
		else:
			header = "\u2014 %s Level \u2014" % _ordinal(k)
		lines.append(header)
		var names: Array[String] = by_level[k] as Array[String]
		names.sort()
		for n: String in names:
			lines.append(n)
	return "\n".join(lines)


static func _ordinal(lvl: int) -> String:
	match lvl:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return "%dth" % lvl


func _on_add_spell_pressed() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.srd == null:
		return
	var s: float = _get_ui_scale()
	var ruleset: String = _active_ruleset()
	var all_spells: Array = reg.srd.get_spells(ruleset)
	if all_spells.is_empty():
		return

	var dlg := AcceptDialog.new()
	dlg.title = "Add Spell"
	dlg.ok_button_text = "Add"
	dlg.exclusive = false

	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2i(roundi(400.0 * s), roundi(400.0 * s))
	vb.add_theme_constant_override("separation", roundi(4.0 * s))
	dlg.add_child(vb)

	## Filters row
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", roundi(4.0 * s))
	vb.add_child(filter_row)

	var search_edit := LineEdit.new()
	search_edit.placeholder_text = "Search spells…"
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.clear_button_enabled = true
	filter_row.add_child(search_edit)

	var level_option := OptionButton.new()
	level_option.add_item("All Levels", 0)
	level_option.add_item("Cantrip", 1)
	for lv: int in range(1, 10):
		level_option.add_item("%s Level" % _ordinal(lv), lv + 1)
	level_option.selected = 0
	filter_row.add_child(level_option)

	## Collect unique class names from all spells for the class filter.
	var class_names: Array[String] = []
	for sd_var2: Variant in all_spells:
		if sd_var2 is SpellData:
			for cn: Variant in (sd_var2 as SpellData).classes:
				var cname: String = str(cn)
				if not cname.is_empty() and not class_names.has(cname):
					class_names.append(cname)
	class_names.sort()

	var class_option := OptionButton.new()
	class_option.add_item("All Classes", 0)
	for ci: int in range(class_names.size()):
		class_option.add_item(class_names[ci], ci + 1)
	class_option.selected = 0
	filter_row.add_child(class_option)

	## Spell list
	var item_list := ItemList.new()
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item_list.select_mode = ItemList.SELECT_SINGLE
	item_list.allow_search = false
	vb.add_child(item_list)

	## Populate helper
	var populate: Callable = func() -> void:
		item_list.clear()
		var query: String = search_edit.text.strip_edges().to_lower()
		var sel_level_id: int = level_option.get_selected_id()
		## sel_level_id: 0=all, 1=cantrip(level 0), 2=1st(level 1), etc.
		var filter_level: int = -1
		if sel_level_id > 0:
			filter_level = sel_level_id - 1
		## Class filter
		var sel_class_id: int = class_option.get_selected_id()
		var filter_class: String = ""
		if sel_class_id > 0 and (sel_class_id - 1) < class_names.size():
			filter_class = class_names[sel_class_id - 1]
		## Collect existing spell indices to mark duplicates.
		var existing: Dictionary = {}
		var lookup: Dictionary = _build_spell_lookup()
		if _spells_text != null:
			for line: String in _spells_text.text.split("\n", false):
				var trimmed: String = line.strip_edges()
				if trimmed.is_empty() or trimmed.begins_with("\u2014"):
					continue
				var info: Dictionary = _resolve_spell_entry(trimmed, lookup, reg)
				existing[str(info.get("index", ""))] = true
		for sd_var: Variant in all_spells:
			if not (sd_var is SpellData):
				continue
			var sd: SpellData = sd_var as SpellData
			if filter_level >= 0 and sd.level != filter_level:
				continue
			if not filter_class.is_empty() and not sd.classes.has(filter_class):
				continue
			if not query.is_empty() and sd.name.to_lower().find(query) < 0:
				continue
			var suffix: String = ""
			if existing.has(sd.index):
				suffix = "  \u2713"
			var label: String
			if sd.level == 0:
				label = "%s (cantrip)%s" % [sd.name, suffix]
			else:
				label = "%s (%s level)%s" % [sd.name, _ordinal(sd.level), suffix]
			var idx: int = item_list.add_item(label)
			item_list.set_item_metadata(idx, sd.index)

	populate.call()
	search_edit.text_changed.connect(func(_t: String) -> void: populate.call())
	level_option.item_selected.connect(func(_i: int) -> void: populate.call())
	class_option.item_selected.connect(func(_i: int) -> void: populate.call())

	## Add selected spell to the text
	var add_spell: Callable = func() -> void:
		var sel: PackedInt32Array = item_list.get_selected_items()
		if sel.is_empty():
			return
		var sp_index: String = str(item_list.get_item_metadata(sel[0]))
		if sp_index.is_empty():
			return
		## Append to the statblock spell list and re-render.
		if _statblock != null:
			if not _statblock.spell_list.has(sp_index):
				_statblock.spell_list.append(sp_index)
				_spells_text.text = _resolve_spell_names(_statblock.spell_list)
				_dirty = true
		dlg.queue_free()

	## Double-click opens spell detail popup.
	item_list.item_activated.connect(func(idx2: int) -> void:
		var sp_idx2: String = str(item_list.get_item_metadata(idx2))
		if sp_idx2.is_empty():
			return
		var sd2: SpellData = reg.srd.get_spell(sp_idx2, ruleset)
		if sd2 != null:
			_show_spell_detail(sd2))
	## OK button adds the selected spell.
	dlg.confirmed.connect(func() -> void: add_spell.call())
	dlg.canceled.connect(func() -> void: dlg.queue_free())
	dlg.close_requested.connect(func() -> void: dlg.queue_free())

	add_child(dlg)
	if reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg, 14.0)
	dlg.reset_size()
	dlg.popup_centered()


func _on_spells_text_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.double_click:
		return
	if _spells_text == null:
		return
	var line_idx: int = _spells_text.get_caret_line()
	var line_text: String = _spells_text.get_line(line_idx).strip_edges()
	## Skip empty and header lines.
	if line_text.is_empty() or line_text.begins_with("\u2014"):
		return
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	var lookup: Dictionary = _build_spell_lookup()
	var info: Dictionary = _resolve_spell_entry(line_text, lookup, reg)
	var idx: String = str(info.get("index", ""))
	if idx.is_empty() or reg == null or reg.srd == null:
		return
	var sd: SpellData = reg.srd.get_spell(idx, _active_ruleset())
	if sd == null:
		return
	_show_spell_detail(sd)


func _show_spell_detail(sd: SpellData) -> void:
	var s: float = _get_ui_scale()
	var dlg := AcceptDialog.new()
	dlg.title = sd.name
	dlg.exclusive = false
	dlg.wrap_controls = true

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2i(roundi(420.0 * s), roundi(340.0 * s))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dlg.add_child(scroll)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.text = _format_spell_bbcode(sd)
	scroll.add_child(rtl)

	add_child(dlg)
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.prepare_window(dlg, 14.0)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)


func _format_spell_bbcode(sd: SpellData) -> String:
	var parts: PackedStringArray = PackedStringArray()
	## Level & school line
	var level_str: String
	if sd.level == 0:
		level_str = "%s cantrip" % sd.school.capitalize()
	else:
		level_str = "%s-level %s" % [_ordinal(sd.level), sd.school.to_lower()]
	if sd.ritual:
		level_str += " (ritual)"
	parts.append("[i]%s[/i]" % level_str)
	parts.append("")
	## Casting time, range, components, duration
	parts.append("[b]Casting Time:[/b] %s" % sd.casting_time)
	parts.append("[b]Range:[/b] %s" % sd.spell_range)
	var comp_str: String = ", ".join(sd.components)
	if not sd.material.is_empty():
		comp_str += " (%s)" % sd.material
	parts.append("[b]Components:[/b] %s" % comp_str)
	var dur_str: String = sd.duration
	if sd.concentration:
		dur_str = "Concentration, %s" % dur_str.to_lower()
	parts.append("[b]Duration:[/b] %s" % dur_str)
	parts.append("")
	## Description
	if not sd.desc.is_empty():
		parts.append(sd.desc)
	## At higher levels
	if not sd.higher_level.is_empty():
		parts.append("")
		parts.append("[b]At Higher Levels.[/b] %s" % sd.higher_level)
	## Classes
	if not sd.classes.is_empty():
		parts.append("")
		parts.append("[i]Classes: %s[/i]" % ", ".join(sd.classes))
	return "\n".join(parts)


func _apply_feat_asi(feat_dict: Dictionary) -> void:
	## Apply fixed ability score bonuses from a feat's "asi" array.
	## "choice" entries are skipped — the user can adjust manually.
	var asi_var: Variant = feat_dict.get("asi", [])
	if not (asi_var is Array):
		return
	for entry_var: Variant in asi_var as Array:
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var as Dictionary
		var ab: String = str(entry.get("ability", ""))
		var amt: int = int(entry.get("amount", 0))
		if ab == "choice" or ab.is_empty() or amt == 0:
			continue
		var ab_idx: int = ABILITY_KEYS.find(ab)
		if ab_idx < 0 or ab_idx >= _score_spins.size():
			continue
		var sp: SpinBox = _score_spins[ab_idx] as SpinBox
		sp.value = sp.value + float(amt)
