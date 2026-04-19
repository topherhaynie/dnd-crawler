extends Window
class_name LevelUpWizard

# -----------------------------------------------------------------------------
# LevelUpWizard — streamlined level-up flow for an existing PC.
#
# Steps:
#   0  Class Choice     — which class to level in (multiclass-aware)
#   1  HP Increase      — roll or take average
#   2  ASI / Feat       — if the new level grants one
#   3  New Spells       — if the class is a caster with learnable spells
#   4  Confirm          — summary and apply
#
# On confirm: patches the StatblockData in-place and emits character_leveled_up.
# -----------------------------------------------------------------------------

signal character_leveled_up(statblock: StatblockData)

const _CFR := preload("res://scripts/ui/character_wizard/ClassFeatureResolver.gd")

enum Step {CLASS_CHOICE, HP_INCREASE, ASI_FEAT, NEW_SPELLS, CONFIRM}

# ── Inputs ────────────────────────────────────────────────────────────────────
var _statblock: StatblockData = null

# ── Wizard state ──────────────────────────────────────────────────────────────
var _chosen_class_index: int = 0 ## Index into _statblock.classes
var _hp_mode: int = 0 ## 0 = average, 1 = roll
var _hp_rolled: int = 0
var _hp_average: int = 0
var _hit_die: int = 8
var _asi_choice: Dictionary = {} ## {type, ability/ability1/ability2/feat_name, feat_choices}
var _new_spells: Array = []
var _new_cantrips: Array = []
var _custom_spells: Array = [] ## [{"name": String, "level": int, "source": String}]
var _new_level: int = 0
var _chosen_class_name: String = ""
var _grants_asi: bool = false
var _grants_subclass: bool = false
var _chosen_subclass: String = ""
var _feats_raw: Array = []
var _spells_raw: Array = []
var _classes_raw: Array = []

# ── UI refs ───────────────────────────────────────────────────────────────────
var _step: int = Step.CLASS_CHOICE
var _step_label: Label = null
var _page_container: VBoxContainer = null
var _back_btn: Button = null
var _next_btn: Button = null
var _cancel_btn: Button = null

# Step 0: class choice
var _class_option: OptionButton = null

# Step 1: HP
var _hp_avg_radio: CheckBox = null
var _hp_roll_radio: CheckBox = null
var _hp_roll_btn: Button = null
var _hp_result_label: Label = null
var _hp_info_label: Label = null

# Step 2: ASI/Feat
var _asi_container: VBoxContainer = null
var _asi_type_option: OptionButton = null
var _asi_ability_option: OptionButton = null
var _asi_ability1_option: OptionButton = null
var _asi_ability2_option: OptionButton = null
var _feat_option: OptionButton = null
var _feat_desc_label: RichTextLabel = null
var _feat_choice_option: OptionButton = null ## For feats with "choice" ASI

# Step 3: Spells
var _spell_container: VBoxContainer = null
var _cantrip_checks: Array = []
var _spell_checks: Array = []
var _custom_spell_name: LineEdit = null
var _custom_spell_level: SpinBox = null
var _custom_spell_source: LineEdit = null
var _custom_spell_list_vbox: VBoxContainer = null

# Step 4: Confirm
var _confirm_label: RichTextLabel = null

# Step containers
var _step_class_choice: Control = null
var _step_hp: Control = null
var _step_asi: Control = null
var _step_spells: Control = null
var _step_confirm: Control = null


func _ready() -> void:
	title = "Level Up"
	size = Vector2i(600, 520)
	min_size = Vector2i(500, 400)
	wrap_controls = false
	close_requested.connect(_on_cancel)
	_build_ui()


func open(statblock: StatblockData) -> void:
	_statblock = statblock
	_reset_state()
	_load_srd_data()
	_populate_class_choice()
	_go_to_step(Step.CLASS_CHOICE)
	var sm: UIScaleManager = _get_ui_scale_mgr()
	if sm != null:
		size = Vector2i(sm.scaled(600.0), sm.scaled(520.0))
		min_size = Vector2i(sm.scaled(500.0), sm.scaled(400.0))
	else:
		size = Vector2i(600, 520)
		min_size = Vector2i(500, 400)
	reapply_theme()
	popup_centered()


func _reset_state() -> void:
	_chosen_class_index = 0
	_hp_mode = 0
	_hp_rolled = 0
	_hp_average = 0
	_asi_choice = {}
	_new_spells.clear()
	_new_cantrips.clear()
	_custom_spells.clear()
	_new_level = 0
	_chosen_class_name = ""
	_grants_asi = false
	_grants_subclass = false
	_chosen_subclass = ""


func _load_srd_data() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.srd == null:
		return
	var rs: String = _statblock.ruleset if not _statblock.ruleset.is_empty() else "2014"
	_classes_raw = registry.srd.get_classes(rs)
	if _classes_raw.is_empty():
		_classes_raw = registry.srd.get_classes("2014")
	_feats_raw = registry.srd.get_feats(rs)
	if _feats_raw.is_empty():
		_feats_raw = registry.srd.get_feats("2014")
	_spells_raw = []
	var raw_spells: Array = registry.srd.get_spells(rs)
	if raw_spells.is_empty():
		raw_spells = registry.srd.get_spells("2014")
	for sp: Variant in raw_spells:
		if sp is SpellData:
			_spells_raw.append(sp)


# ── UI construction ───────────────────────────────────────────────────────────
func _build_ui() -> void:
	var s: float = _get_ui_scale()
	var margin: int = roundi(12.0 * s)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", roundi(8.0 * s))
	root.offset_left = margin; root.offset_top = margin
	root.offset_right = - margin; root.offset_bottom = - margin
	add_child(root)

	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_step_label)

	var sep := HSeparator.new()
	root.add_child(sep)

	_page_container = VBoxContainer.new()
	_page_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_page_container)

	_build_step_class_choice()
	_build_step_hp()
	_build_step_asi()
	_build_step_spells()
	_build_step_confirm()

	var sep2 := HSeparator.new()
	root.add_child(sep2)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", roundi(8.0 * s))
	root.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.custom_minimum_size = Vector2(roundi(80.0 * s), roundi(30.0 * s))
	_cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_row.add_child(spacer)

	_back_btn = Button.new()
	_back_btn.text = "← Back"
	_back_btn.custom_minimum_size = Vector2(roundi(80.0 * s), roundi(30.0 * s))
	_back_btn.pressed.connect(_on_back)
	btn_row.add_child(_back_btn)

	_next_btn = Button.new()
	_next_btn.text = "Next →"
	_next_btn.custom_minimum_size = Vector2(roundi(80.0 * s), roundi(30.0 * s))
	_next_btn.pressed.connect(_on_next)
	btn_row.add_child(_next_btn)


func _build_step_class_choice() -> void:
	var s: float = _get_ui_scale()
	_step_class_choice = VBoxContainer.new()
	_step_class_choice.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_class_choice.add_theme_constant_override("separation", roundi(8.0 * s))
	_page_container.add_child(_step_class_choice)

	var info := Label.new()
	info.text = "Choose which class to gain a level in:"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_class_choice.add_child(info)

	_class_option = OptionButton.new()
	_step_class_choice.add_child(_class_option)


func _build_step_hp() -> void:
	var s: float = _get_ui_scale()
	_step_hp = VBoxContainer.new()
	_step_hp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_hp.add_theme_constant_override("separation", roundi(6.0 * s))
	_page_container.add_child(_step_hp)

	_hp_info_label = Label.new()
	_hp_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_step_hp.add_child(_hp_info_label)

	_hp_avg_radio = CheckBox.new()
	_hp_avg_radio.text = "Take average"
	_hp_avg_radio.button_pressed = true
	_hp_avg_radio.toggled.connect(func(on: bool) -> void:
		if on:
			_hp_mode = 0
			_hp_roll_radio.set_pressed_no_signal(false)
			_update_hp_display()
	)
	_step_hp.add_child(_hp_avg_radio)

	_hp_roll_radio = CheckBox.new()
	_hp_roll_radio.text = "Roll"
	_hp_roll_radio.toggled.connect(func(on: bool) -> void:
		if on:
			_hp_mode = 1
			_hp_avg_radio.set_pressed_no_signal(false)
			_update_hp_display()
	)
	_step_hp.add_child(_hp_roll_radio)

	var roll_row := HBoxContainer.new()
	roll_row.add_theme_constant_override("separation", roundi(8.0 * s))
	_step_hp.add_child(roll_row)

	_hp_roll_btn = Button.new()
	_hp_roll_btn.text = "Roll Hit Die"
	_hp_roll_btn.custom_minimum_size = Vector2(roundi(100.0 * s), roundi(30.0 * s))
	_hp_roll_btn.pressed.connect(_on_roll_hp)
	roll_row.add_child(_hp_roll_btn)

	_hp_result_label = Label.new()
	_hp_result_label.text = ""
	roll_row.add_child(_hp_result_label)


func _build_step_asi() -> void:
	var s: float = _get_ui_scale()
	_step_asi = VBoxContainer.new()
	_step_asi.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_asi.add_theme_constant_override("separation", roundi(6.0 * s))
	_page_container.add_child(_step_asi)

	_asi_container = VBoxContainer.new()
	_asi_container.add_theme_constant_override("separation", roundi(6.0 * s))
	_step_asi.add_child(_asi_container)


func _build_step_spells() -> void:
	var s: float = _get_ui_scale()
	_step_spells = VBoxContainer.new()
	_step_spells.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_spells.add_theme_constant_override("separation", roundi(4.0 * s))
	_page_container.add_child(_step_spells)

	_spell_container = VBoxContainer.new()
	_spell_container.add_theme_constant_override("separation", roundi(2.0 * s))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_spell_container)
	_step_spells.add_child(scroll)

	# Custom spell form
	var custom_sep := HSeparator.new()
	_step_spells.add_child(custom_sep)

	var custom_lbl := Label.new()
	custom_lbl.text = "Add Custom Spell (from sourcebooks you own):"
	_step_spells.add_child(custom_lbl)

	var custom_row := HBoxContainer.new()
	custom_row.add_theme_constant_override("separation", roundi(4.0 * s))
	_step_spells.add_child(custom_row)

	_custom_spell_name = LineEdit.new()
	_custom_spell_name.placeholder_text = "Spell name"
	_custom_spell_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_row.add_child(_custom_spell_name)

	var lvl_lbl := Label.new()
	lvl_lbl.text = "Lvl"
	custom_row.add_child(lvl_lbl)
	_custom_spell_level = SpinBox.new()
	_custom_spell_level.min_value = 0
	_custom_spell_level.max_value = 9
	_custom_spell_level.value = 1
	_custom_spell_level.custom_minimum_size = Vector2(roundi(60.0 * s), 0)
	custom_row.add_child(_custom_spell_level)

	_custom_spell_source = LineEdit.new()
	_custom_spell_source.placeholder_text = "Source (e.g. Tasha's p.12)"
	_custom_spell_source.custom_minimum_size = Vector2(roundi(140.0 * s), 0)
	custom_row.add_child(_custom_spell_source)

	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(_on_add_custom_spell)
	custom_row.add_child(add_btn)

	_custom_spell_name.text_submitted.connect(func(_t: String) -> void: _on_add_custom_spell())
	_custom_spell_source.text_submitted.connect(func(_t: String) -> void: _on_add_custom_spell())

	_custom_spell_list_vbox = VBoxContainer.new()
	_custom_spell_list_vbox.add_theme_constant_override("separation", roundi(2.0 * s))
	_step_spells.add_child(_custom_spell_list_vbox)


func _build_step_confirm() -> void:
	_step_confirm = VBoxContainer.new()
	_step_confirm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_container.add_child(_step_confirm)

	_confirm_label = RichTextLabel.new()
	_confirm_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_confirm_label.bbcode_enabled = true
	_confirm_label.fit_content = false
	var s: float = _get_ui_scale()
	_confirm_label.custom_minimum_size.y = roundi(200.0 * s)
	_step_confirm.add_child(_confirm_label)


# ── Step population ───────────────────────────────────────────────────────────
func _populate_class_choice() -> void:
	if _class_option == null or _statblock == null:
		return
	_class_option.clear()
	if _statblock.classes.is_empty():
		# Single-class: just show the class name
		_class_option.add_item("%s (Level %d → %d)" % [
			_statblock.class_name_str if not _statblock.class_name_str.is_empty() else "Unknown",
			_statblock.level, _statblock.level + 1])
		_class_option.set_item_metadata(0, 0)
	else:
		for i: int in _statblock.classes.size():
			var entry: Variant = _statblock.classes[i]
			if not (entry is Dictionary):
				continue
			var cls: Dictionary = entry as Dictionary
			var cn: String = str(cls.get("name", ""))
			var cl: int = int(cls.get("level", 0))
			_class_option.add_item("%s (Level %d → %d)" % [cn, cl, cl + 1])
			_class_option.set_item_metadata(i, i)
	# Add "+ New Class (Multiclass)" option
	_class_option.add_item("+ New Class (Multiclass)...")
	_class_option.set_item_metadata(_class_option.item_count - 1, -1)


func _resolve_chosen_class() -> void:
	var meta: int = -1
	if _class_option != null and _class_option.selected >= 0:
		meta = int(_class_option.get_item_metadata(_class_option.selected))
	_chosen_class_index = meta

	if meta >= 0:
		# Existing class
		if _statblock.classes.is_empty():
			_chosen_class_name = _statblock.class_name_str
			_new_level = _statblock.level + 1
		else:
			var entry: Dictionary = _statblock.classes[meta] as Dictionary
			_chosen_class_name = str(entry.get("name", ""))
			_new_level = int(entry.get("level", 0)) + 1
	else:
		# Multiclass — will be handled via a dialog; for now use first SRD class
		_chosen_class_name = ""
		_new_level = 1

	# Look up hit die from SRD class data
	_hit_die = 8
	for cls_var: Variant in _classes_raw:
		if cls_var is Dictionary:
			var cd: Dictionary = cls_var as Dictionary
			if str(cd.get("name", "")).to_lower() == _chosen_class_name.to_lower():
				_hit_die = int(cd.get("hit_die", 8))
				break

	# Check if this level grants an ASI
	var cls_key: String = _chosen_class_name.to_lower()
	_grants_asi = WizardConstants.asi_levels_for_class(cls_key).has(_new_level)

	# Check if this level grants a subclass
	var subclass_level: int = int(WizardConstants.CLASS_DATA.get(cls_key, {}).get("subclass_level", 0))
	_grants_subclass = subclass_level == _new_level

	# Compute HP average
	var con_mod: int = _statblock.get_modifier("con")
	_hp_average = WizardConstants.hp_increase_average(_hit_die, con_mod)
	_hp_rolled = 0


func _populate_hp_step() -> void:
	var con_mod: int = _statblock.get_modifier("con")
	_hp_info_label.text = "Hit Die: d%d | CON modifier: %+d\nAverage: %d (%d/2 + 1 + %d)" % [
		_hit_die, con_mod, _hp_average,
		_hit_die, con_mod]
	_hp_avg_radio.set_pressed_no_signal(true)
	_hp_roll_radio.set_pressed_no_signal(false)
	_hp_mode = 0
	_hp_rolled = 0
	_hp_result_label.text = ""
	_update_hp_display()


func _update_hp_display() -> void:
	if _hp_mode == 0:
		_hp_result_label.text = "HP increase: +%d" % _hp_average
		_hp_roll_btn.disabled = true
	else:
		_hp_roll_btn.disabled = false
		if _hp_rolled > 0:
			_hp_result_label.text = "Rolled: %d → HP increase: +%d" % [
				_hp_rolled, maxi(1, _hp_rolled + _statblock.get_modifier("con"))]
		else:
			_hp_result_label.text = "Click Roll to determine HP increase"


func _on_roll_hp() -> void:
	_hp_rolled = randi_range(1, _hit_die)
	_update_hp_display()


func _populate_asi_step() -> void:
	# Clear old content
	for child: Node in _asi_container.get_children():
		child.queue_free()

	if not _grants_asi:
		var lbl := Label.new()
		lbl.text = "No ASI/Feat at this level."
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_asi_container.add_child(lbl)
		return

	var header := Label.new()
	header.text = "Ability Score Improvement at Level %d" % _new_level
	_asi_container.add_child(header)

	_asi_type_option = OptionButton.new()
	_asi_type_option.add_item("+2 to one ability", 0)
	_asi_type_option.add_item("+1 to two abilities", 1)
	_asi_type_option.add_item("Choose a feat", 2)
	_asi_type_option.item_selected.connect(_on_asi_type_changed)
	_asi_container.add_child(_asi_type_option)

	# +2 single ability
	_asi_ability_option = OptionButton.new()
	for i: int in 6:
		var score: int = _get_ability_score_by_key(WizardConstants.ABILITY_KEYS[i])
		_asi_ability_option.add_item("%s (%d → %d)" % [WizardConstants.ABILITY_NAMES[i], score, score + 2])
	_asi_container.add_child(_asi_ability_option)

	# +1/+1 two abilities
	_asi_ability1_option = OptionButton.new()
	_asi_ability2_option = OptionButton.new()
	for i: int in 6:
		var score: int = _get_ability_score_by_key(WizardConstants.ABILITY_KEYS[i])
		_asi_ability1_option.add_item("%s (%d → %d)" % [WizardConstants.ABILITY_NAMES[i], score, score + 1])
		_asi_ability2_option.add_item("%s (%d → %d)" % [WizardConstants.ABILITY_NAMES[i], score, score + 1])
	_asi_ability1_option.select(0)
	_asi_ability2_option.select(1)
	_asi_container.add_child(_asi_ability1_option)
	_asi_container.add_child(_asi_ability2_option)

	# Feat selection
	_feat_option = OptionButton.new()
	for fd_var: Variant in _feats_raw:
		if fd_var is Dictionary:
			_feat_option.add_item(str((fd_var as Dictionary).get("name", "")))
	_asi_container.add_child(_feat_option)

	_feat_desc_label = RichTextLabel.new()
	_feat_desc_label.bbcode_enabled = true
	_feat_desc_label.fit_content = true
	_feat_desc_label.custom_minimum_size.y = roundi(80.0 * _get_ui_scale())
	_asi_container.add_child(_feat_desc_label)

	# Ability choice dropdown for feats with "choice" ASI
	_feat_choice_option = OptionButton.new()
	for i: int in 6:
		var score: int = _get_ability_score_by_key(WizardConstants.ABILITY_KEYS[i])
		_feat_choice_option.add_item("%s (%d → %d)" % [WizardConstants.ABILITY_NAMES[i], score, score + 1])
	_feat_choice_option.visible = false
	_asi_container.add_child(_feat_choice_option)

	_feat_option.item_selected.connect(_on_feat_selected)

	_on_asi_type_changed(0)


func _on_asi_type_changed(idx: int) -> void:
	if _asi_ability_option:
		_asi_ability_option.visible = (idx == 0)
	if _asi_ability1_option:
		_asi_ability1_option.visible = (idx == 1)
	if _asi_ability2_option:
		_asi_ability2_option.visible = (idx == 1)
	if _feat_option:
		_feat_option.visible = (idx == 2)
	if _feat_desc_label:
		_feat_desc_label.visible = (idx == 2)
	if _feat_choice_option:
		_feat_choice_option.visible = false
	if idx == 2:
		_on_feat_selected(_feat_option.selected if _feat_option else 0)


func _on_feat_selected(idx: int) -> void:
	# Update feat description
	if idx >= 0 and idx < _feats_raw.size():
		var fd: Dictionary = _feats_raw[idx] as Dictionary
		if _feat_desc_label:
			_feat_desc_label.text = str(fd.get("desc", ""))
	# Show/hide the ability choice dropdown based on whether feat has "choice" ASI
	var has_choice: bool = _feat_has_choice_asi(idx)
	if _feat_choice_option:
		_feat_choice_option.visible = has_choice


func _feat_has_choice_asi(feat_idx: int) -> bool:
	if feat_idx < 0 or feat_idx >= _feats_raw.size():
		return false
	var fd: Dictionary = _feats_raw[feat_idx] as Dictionary
	var asi_var: Variant = fd.get("asi", [])
	if asi_var is Array:
		for entry_var: Variant in asi_var as Array:
			if entry_var is Dictionary:
				if str((entry_var as Dictionary).get("ability", "")) == "choice":
					return true
	return false


func _populate_spells_step() -> void:
	# Clear old
	_cantrip_checks.clear()
	_spell_checks.clear()
	for child: Node in _spell_container.get_children():
		child.queue_free()

	var cls_key: String = _chosen_class_name.to_lower()
	var cd_var: Variant = WizardConstants.CLASS_DATA.get(cls_key, {})
	var cd: Dictionary = cd_var as Dictionary if cd_var is Dictionary else {}
	var spell_type: String = str(cd.get("spell_type", "none"))

	if spell_type == "none":
		var lbl := Label.new()
		lbl.text = "This class does not have spellcasting."
		_spell_container.add_child(lbl)
		return

	# Filter spells for this class
	var class_spells: Array = []
	for sp: Variant in _spells_raw:
		if sp is SpellData:
			var sd: SpellData = sp as SpellData
			for cls_entry: Variant in sd.classes:
				if str(cls_entry).to_lower() == cls_key:
					class_spells.append(sd)
					break

	# Get current known spell indices for deduplication
	var known: Dictionary = {}
	for idx: Variant in _statblock.spell_list:
		known[str(idx)] = true

	# Cantrips section (if class gains cantrips at this level)
	var cantrip_count: int = _cantrips_gained_at_level(cls_key, _new_level)
	if cantrip_count > 0:
		var cantrip_header := Label.new()
		cantrip_header.text = "New Cantrips (select up to %d):" % cantrip_count
		cantrip_header.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
		_spell_container.add_child(cantrip_header)
		# Sort cantrips alphabetically within level 0
		var cantrip_list: Array[SpellData] = []
		for sp: SpellData in class_spells:
			if sp.level == 0 and not known.has(sp.index):
				cantrip_list.append(sp)
		cantrip_list.sort_custom(func(a: SpellData, b: SpellData) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
		for sp: SpellData in cantrip_list:
			var cb := CheckBox.new()
			cb.text = sp.name
			cb.set_meta("spell_index", sp.index)
			cb.set_meta("is_cantrip", true)
			_spell_container.add_child(cb)
			_cantrip_checks.append(cb)

	# Levelled spells section — grouped by spell level
	var max_spell_level: int = _max_spell_level_for_class(cls_key, _new_level)
	if max_spell_level > 0:
		var learn_count: int = _spells_learned_on_level_up(cls_key, spell_type)
		var spell_header := Label.new()
		spell_header.text = "New Spells (select up to %d, max level %d):" % [
			learn_count, max_spell_level]
		spell_header.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
		_spell_container.add_child(spell_header)
		for sl: int in range(1, max_spell_level + 1):
			var level_spells: Array[SpellData] = []
			for sp: SpellData in class_spells:
				if sp.level == sl and not known.has(sp.index):
					level_spells.append(sp)
			if level_spells.is_empty():
				continue
			level_spells.sort_custom(func(a: SpellData, b: SpellData) -> bool: return a.name.naturalnocasecmp_to(b.name) < 0)
			var lv_header := Label.new()
			lv_header.text = "— %s Level —" % WizardConstants.spell_level_ordinal(sl)
			lv_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lv_header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			_spell_container.add_child(lv_header)
			for sp: SpellData in level_spells:
				var cb := CheckBox.new()
				cb.text = sp.name
				cb.set_meta("spell_index", sp.index)
				cb.set_meta("is_cantrip", false)
				_spell_container.add_child(cb)
				_spell_checks.append(cb)

	if _cantrip_checks.is_empty() and _spell_checks.is_empty():
		var lbl := Label.new()
		lbl.text = "No new spells available at this level."
		_spell_container.add_child(lbl)

	# Rebuild the custom spell list display
	_rebuild_custom_spell_list()


func _populate_confirm_step() -> void:
	if _confirm_label == null:
		return

	var lines: Array = []
	lines.append("[b]Level Up Summary[/b]")
	lines.append("")
	lines.append("[b]Class:[/b] %s → Level %d" % [_chosen_class_name, _new_level])
	lines.append("[b]Total Level:[/b] %d → %d" % [
		_statblock.get_total_level(), _statblock.get_total_level() + 1])

	# HP
	var hp_gain: int = _get_hp_gain()
	lines.append("[b]HP:[/b] %d → %d (+%d)" % [
		_statblock.hit_points, _statblock.hit_points + hp_gain, hp_gain])

	# Proficiency bonus
	var old_prof: int = WizardConstants.proficiency_bonus_for_level(_statblock.get_total_level())
	var new_prof: int = WizardConstants.proficiency_bonus_for_level(_statblock.get_total_level() + 1)
	if new_prof != old_prof:
		lines.append("[b]Proficiency Bonus:[/b] +%d → +%d" % [old_prof, new_prof])

	# ASI
	if _grants_asi:
		_read_asi_choice()
		var t: String = str(_asi_choice.get("type", "none"))
		match t:
			"asi_plus2":
				var ab: String = str(_asi_choice.get("ability", ""))
				var idx: int = WizardConstants.ABILITY_KEYS.find(ab)
				var name_str: String = WizardConstants.ABILITY_NAMES[idx] if idx >= 0 else ab
				lines.append("[b]ASI:[/b] %s +2" % name_str)
			"asi_plus1x2":
				var ab1: String = str(_asi_choice.get("ability1", ""))
				var ab2: String = str(_asi_choice.get("ability2", ""))
				var i1: int = WizardConstants.ABILITY_KEYS.find(ab1)
				var i2: int = WizardConstants.ABILITY_KEYS.find(ab2)
				var n1: String = WizardConstants.ABILITY_NAMES[i1] if i1 >= 0 else ab1
				var n2: String = WizardConstants.ABILITY_NAMES[i2] if i2 >= 0 else ab2
				lines.append("[b]ASI:[/b] %s +1, %s +1" % [n1, n2])
			"feat":
				var feat_line: String = "[b]Feat:[/b] %s" % str(_asi_choice.get("feat_name", ""))
				var ca: String = str(_asi_choice.get("choice_ability", ""))
				if not ca.is_empty():
					var ci: int = WizardConstants.ABILITY_KEYS.find(ca)
					var cn: String = WizardConstants.ABILITY_NAMES[ci] if ci >= 0 else ca
					feat_line += " (%s +1)" % cn
				lines.append(feat_line)

	# New features
	var new_features: Array = _CFR.resolve(_chosen_class_name.to_lower(), _new_level)
	var old_features: Array = _CFR.resolve(_chosen_class_name.to_lower(), _new_level - 1)
	var old_names: Dictionary = {}
	for f: Dictionary in old_features:
		old_names[str(f.get("name", ""))] = true
	var added: Array = []
	for f: Dictionary in new_features:
		if not old_names.has(str(f.get("name", ""))):
			added.append(str(f.get("name", "")))
	if not added.is_empty():
		lines.append("[b]New Features:[/b] %s" % ", ".join(added))

	# Spells
	_read_spell_choices()
	if not _new_cantrips.is_empty():
		var cantrip_names: Array = []
		for ci: String in _new_cantrips:
			cantrip_names.append(_spell_name_for_index(ci))
		lines.append("[b]New Cantrips:[/b] %s" % ", ".join(cantrip_names))
	if not _new_spells.is_empty():
		var spell_names: Array = []
		for si: String in _new_spells:
			spell_names.append(_spell_name_for_index(si))
		lines.append("[b]New Spells:[/b] %s" % ", ".join(spell_names))
	if not _custom_spells.is_empty():
		var custom_names: Array = []
		for cs: Dictionary in _custom_spells:
			custom_names.append(str(cs.get("name", "")))
		lines.append("[b]Custom Spells:[/b] %s" % ", ".join(custom_names))

	# Spell slots
	var old_classes: Array = _statblock.classes.duplicate(true)
	var new_classes: Array = _build_new_classes_array()
	var rs: String = _statblock.ruleset if not _statblock.ruleset.is_empty() else "2014"
	var old_slots: Dictionary = WizardConstants.compute_spell_slots(old_classes, rs)
	var new_slots: Dictionary = WizardConstants.compute_spell_slots(new_classes, rs)
	if new_slots != old_slots:
		var slot_parts: Array = []
		for lv: int in range(1, 10):
			var ns: int = int(new_slots.get(lv, 0))
			var os: int = int(old_slots.get(lv, 0))
			if ns > 0 and ns != os:
				slot_parts.append("Level %d: %d" % [lv, ns])
		if not slot_parts.is_empty():
			lines.append("[b]Spell Slots:[/b] %s" % ", ".join(slot_parts))

	_confirm_label.text = "\n".join(lines)


# ── Step navigation ───────────────────────────────────────────────────────────
const _STEP_TITLES: Array = [
	"Step 1 — Choose Class",
	"Step 2 — Hit Points",
	"Step 3 — Ability Score Improvement",
	"Step 4 — New Spells",
	"Step 5 — Confirm Level Up",
]

func _go_to_step(step: int) -> void:
	_step = step
	_step_label.text = _STEP_TITLES[step] if step < _STEP_TITLES.size() else ""

	if _step_class_choice: _step_class_choice.visible = (step == Step.CLASS_CHOICE)
	if _step_hp: _step_hp.visible = (step == Step.HP_INCREASE)
	if _step_asi: _step_asi.visible = (step == Step.ASI_FEAT)
	if _step_spells: _step_spells.visible = (step == Step.NEW_SPELLS)
	if _step_confirm: _step_confirm.visible = (step == Step.CONFIRM)

	_back_btn.disabled = (step == Step.CLASS_CHOICE)
	_next_btn.text = "Level Up" if step == Step.CONFIRM else "Next →"

	match step:
		Step.CLASS_CHOICE:
			pass
		Step.HP_INCREASE:
			_resolve_chosen_class()
			_populate_hp_step()
		Step.ASI_FEAT:
			_populate_asi_step()
		Step.NEW_SPELLS:
			_populate_spells_step()
		Step.CONFIRM:
			_populate_confirm_step()
	reapply_theme()


func _on_back() -> void:
	if _step > Step.CLASS_CHOICE:
		# Skip ASI step if no ASI at this level
		var prev: int = _step - 1
		if prev == Step.ASI_FEAT and not _grants_asi:
			prev = Step.HP_INCREASE
		_go_to_step(prev)


func _on_next() -> void:
	if _step == Step.CONFIRM:
		_apply_level_up()
		return
	# Skip ASI step if no ASI at this level
	var nxt: int = _step + 1
	if nxt == Step.ASI_FEAT and not _grants_asi:
		nxt = Step.NEW_SPELLS
	_go_to_step(nxt)


func _on_cancel() -> void:
	hide()


# ── State readers ─────────────────────────────────────────────────────────────
func _get_hp_gain() -> int:
	if _hp_mode == 0:
		return _hp_average
	if _hp_rolled > 0:
		return maxi(1, _hp_rolled + _statblock.get_modifier("con"))
	return _hp_average


func _read_asi_choice() -> void:
	_asi_choice = {}
	if not _grants_asi or _asi_type_option == null:
		return
	var t: int = _asi_type_option.selected
	match t:
		0: # +2 single
			var idx: int = _asi_ability_option.selected if _asi_ability_option else 0
			_asi_choice = {"type": "asi_plus2", "ability": WizardConstants.ABILITY_KEYS[idx]}
		1: # +1/+1
			var i1: int = _asi_ability1_option.selected if _asi_ability1_option else 0
			var i2: int = _asi_ability2_option.selected if _asi_ability2_option else 1
			_asi_choice = {"type": "asi_plus1x2",
				"ability1": WizardConstants.ABILITY_KEYS[i1],
				"ability2": WizardConstants.ABILITY_KEYS[i2]}
		2: # Feat
			var fi: int = _feat_option.selected if _feat_option else 0
			var feat_name: String = ""
			if fi >= 0 and fi < _feats_raw.size():
				feat_name = str((_feats_raw[fi] as Dictionary).get("name", ""))
			var choice_ability: String = ""
			if _feat_choice_option and _feat_choice_option.visible and _feat_choice_option.selected >= 0:
				choice_ability = WizardConstants.ABILITY_KEYS[_feat_choice_option.selected]
			_asi_choice = {"type": "feat", "feat_name": feat_name, "choice_ability": choice_ability}


func _read_spell_choices() -> void:
	_new_cantrips.clear()
	_new_spells.clear()
	for cb: Variant in _cantrip_checks:
		if cb is CheckBox and (cb as CheckBox).button_pressed:
			_new_cantrips.append(str((cb as CheckBox).get_meta("spell_index")))
	for cb: Variant in _spell_checks:
		if cb is CheckBox and (cb as CheckBox).button_pressed:
			_new_spells.append(str((cb as CheckBox).get_meta("spell_index")))


func _build_new_classes_array() -> Array:
	var new_classes: Array = _statblock.classes.duplicate(true)
	if new_classes.is_empty() and not _statblock.class_name_str.is_empty():
		new_classes = [ {"name": _statblock.class_name_str, "level": _statblock.level, "subclass": ""}]

	if _chosen_class_index >= 0 and _chosen_class_index < new_classes.size():
		var entry: Dictionary = (new_classes[_chosen_class_index] as Dictionary).duplicate()
		entry["level"] = int(entry.get("level", 0)) + 1
		new_classes[_chosen_class_index] = entry
	elif _chosen_class_index < 0 and not _chosen_class_name.is_empty():
		new_classes.append({"name": _chosen_class_name, "level": 1, "subclass": ""})

	return new_classes


# ── Apply level up to statblock ──────────────────────────────────────────────
func _apply_level_up() -> void:
	var sb := _statblock
	if sb == null:
		return

	# 1. Bump class level
	sb.classes = _build_new_classes_array()
	sb.level = sb.get_total_level()
	sb.class_name_str = sb.get_primary_class()

	# 2. HP
	var hp_gain: int = _get_hp_gain()
	sb.hit_points += hp_gain
	sb.hit_dice = "%dd%d" % [sb.level, _hit_die]
	sb.hit_points_roll = "%dd%d+%d" % [sb.level, _hit_die, sb.level * sb.get_modifier("con")]

	# 3. Proficiency bonus
	sb.proficiency_bonus = WizardConstants.proficiency_bonus_for_level(sb.level)

	# 4. ASI
	_read_asi_choice()
	if _grants_asi and not _asi_choice.is_empty():
		var t: String = str(_asi_choice.get("type", ""))
		match t:
			"asi_plus2":
				_add_ability_score(sb, str(_asi_choice.get("ability", "")), 2)
			"asi_plus1x2":
				_add_ability_score(sb, str(_asi_choice.get("ability1", "")), 1)
				_add_ability_score(sb, str(_asi_choice.get("ability2", "")), 1)
			"feat":
				var feat_name: String = str(_asi_choice.get("feat_name", ""))
				if not feat_name.is_empty():
					sb.features.append({"name": "Feat: " + feat_name,
						"desc": _get_feat_desc(feat_name), "source": "feat"})
					var chosen_ability: String = str(_asi_choice.get("choice_ability", ""))
					_apply_feat_bonuses(sb, feat_name, chosen_ability)

	# 5. New class features
	var new_features: Array = _CFR.resolve(_chosen_class_name.to_lower(), _new_level)
	var old_features: Array = _CFR.resolve(_chosen_class_name.to_lower(), _new_level - 1)
	var old_names: Dictionary = {}
	for f: Dictionary in old_features:
		old_names[str(f.get("name", ""))] = true
	for f: Dictionary in new_features:
		var fn: String = str(f.get("name", ""))
		if not old_names.has(fn):
			# Check if this feature replaces an existing one (scaling features)
			var replaced: bool = false
			for i: int in sb.features.size():
				var existing: Variant = sb.features[i]
				var existing_name: String = ""
				if existing is Dictionary:
					existing_name = str((existing as Dictionary).get("name", ""))
				elif existing is ActionEntry:
					existing_name = (existing as ActionEntry).name
				if existing_name == fn:
					sb.features[i] = f
					replaced = true
					break
			if not replaced:
				sb.features.append(f)

	# 6. New spells
	_read_spell_choices()
	for idx: String in _new_cantrips:
		if not sb.spell_list.has(idx):
			sb.spell_list.append(idx)
	for idx: String in _new_spells:
		if not sb.spell_list.has(idx):
			sb.spell_list.append(idx)

	# 6b. Custom spells — stored as feature entries (no SRD index)
	for cs: Dictionary in _custom_spells:
		var level_str: String = "Cantrip" if int(cs.get("level", 1)) == 0 else "Level %d" % int(cs.get("level", 1))
		var desc: String = "%s (%s)" % [str(cs.get("name", "")), level_str]
		if not str(cs.get("source", "")).is_empty():
			desc += " — %s" % str(cs.get("source", ""))
		sb.features.append({"name": "Custom Spell", "desc": desc})

	# 7. Spell slots
	var lvl_rs: String = sb.ruleset if not sb.ruleset.is_empty() else "2014"
	sb.spell_slots = WizardConstants.compute_spell_slots(sb.classes, lvl_rs)

	# 8. Recalculate passive perception in senses
	var wis_mod: int = sb.get_modifier("wis")
	var perc_bonus: int = 0
	for prof_entry: Variant in sb.proficiencies:
		if prof_entry is Dictionary:
			var pi: Variant = (prof_entry as Dictionary).get("proficiency", {})
			if pi is Dictionary and str((pi as Dictionary).get("index", "")) == "skill-perception":
				perc_bonus = sb.proficiency_bonus
				break
	sb.senses["passive_perception"] = 10 + wis_mod + perc_bonus

	hide()
	character_leveled_up.emit(sb)


func _add_ability_score(sb: StatblockData, ability: String, amount: int) -> void:
	match ability:
		"str": sb.strength = mini(sb.strength + amount, 20)
		"dex": sb.dexterity = mini(sb.dexterity + amount, 20)
		"con": sb.constitution = mini(sb.constitution + amount, 20)
		"int": sb.intelligence = mini(sb.intelligence + amount, 20)
		"wis": sb.wisdom = mini(sb.wisdom + amount, 20)
		"cha": sb.charisma = mini(sb.charisma + amount, 20)


func _get_feat_desc(feat_name: String) -> String:
	for fd_var: Variant in _feats_raw:
		if fd_var is Dictionary:
			var fd: Dictionary = fd_var as Dictionary
			if str(fd.get("name", "")) == feat_name:
				return str(fd.get("desc", feat_name))
	return feat_name


func _apply_feat_bonuses(sb: StatblockData, feat_name: String, chosen_ability: String = "") -> void:
	for fd_var: Variant in _feats_raw:
		if not (fd_var is Dictionary):
			continue
		var fd: Dictionary = fd_var as Dictionary
		if str(fd.get("name", "")) != feat_name:
			continue
		# ASI from feat
		var asi_var: Variant = fd.get("asi", [])
		if asi_var is Array:
			for entry_var: Variant in asi_var as Array:
				if entry_var is Dictionary:
					var entry: Dictionary = entry_var as Dictionary
					var ab: String = str(entry.get("ability", ""))
					var amt: int = int(entry.get("amount", 0))
					if ab == "choice" and not chosen_ability.is_empty():
						_add_ability_score(sb, chosen_ability, amt)
					elif not ab.is_empty() and ab != "choice" and amt != 0:
						_add_ability_score(sb, ab, amt)
		# HP per level (e.g. Tough)
		var hp_per_lvl: int = int(fd.get("hp_per_level", 0))
		if hp_per_lvl > 0:
			sb.hit_points += hp_per_lvl * sb.level
		# Speed bonus (e.g. Mobile)
		var speed_bonus: int = int(fd.get("speed_bonus", 0))
		if speed_bonus > 0:
			var walk_str: String = str(sb.speed.get("walk", "30 ft."))
			var walk_val: int = int(walk_str.replace(" ft.", "").strip_edges())
			sb.speed["walk"] = "%d ft." % (walk_val + speed_bonus)
		# Proficiencies from feat
		var profs_var: Variant = fd.get("proficiencies", [])
		if profs_var is Array:
			for p_var: Variant in profs_var as Array:
				if p_var is Dictionary:
					var p: Dictionary = p_var as Dictionary
					sb.proficiencies.append({
						"proficiency": {"index": str(p.get("index", "")), "name": str(p.get("name", ""))},
						"value": 1,
					})
		# Granted spells
		var sp_var: Variant = fd.get("granted_spells", [])
		if sp_var is Array:
			for sp_idx_var: Variant in sp_var as Array:
				var sp_idx: String = str(sp_idx_var)
				if not sp_idx.is_empty() and not sb.spell_list.has(sp_idx):
					sb.spell_list.append(sp_idx)
		break


# ── Spell helpers ─────────────────────────────────────────────────────────────

## Number of new cantrips gained at this class level (0 for most levels).
func _cantrips_gained_at_level(cls_key: String, lvl: int) -> int:
	if lvl <= 1:
		return WizardConstants.cantrips_for_level(cls_key, 1)
	var curr: int = WizardConstants.cantrips_for_level(cls_key, lvl)
	var prev: int = WizardConstants.cantrips_for_level(cls_key, lvl - 1)
	return maxi(0, curr - prev)


## Maximum spell level this class can cast at the given class level.
func _max_spell_level_for_class(cls_key: String, cls_level: int) -> int:
	var w: float = WizardConstants.caster_weight(cls_key)
	if w <= 0.0 and cls_key != "warlock":
		return 0
	if cls_key == "warlock":
		if cls_level <= 0 or cls_level > 20:
			return 0
		return int(WizardConstants.WARLOCK_PACT_SLOTS[cls_level][1])
	var effective_caster_level: int = int(float(cls_level) * w)
	effective_caster_level = clampi(effective_caster_level, 0, 20)
	if effective_caster_level <= 0:
		return 0
	var row: Variant = WizardConstants.SPELL_SLOT_TABLE[effective_caster_level]
	if not (row is Array):
		return 0
	for i: int in range((row as Array).size() - 1, -1, -1):
		if int((row as Array)[i]) > 0:
			return i + 1
	return 0


## Number of new levelled spells learned on level-up for this class.
func _spells_learned_on_level_up(_cls_key: String, spell_type: String) -> int:
	match spell_type:
		"known":
			# Known-casters (Bard, Ranger, Sorcerer, Warlock) learn 1 per level
			return 1
		"prepared":
			# Prepared casters (Cleric, Druid, Paladin) don't have a fixed
			# "spells learned" — they prepare from the full list daily.
			# Show all available for selection.
			return 99
		"spellbook":
			# Wizards learn 2 spells per level
			return 2
	return 0


## Read an ability score from the statblock by abbreviated key.
func _get_ability_score_by_key(key: String) -> int:
	if _statblock == null:
		return 10
	match key:
		"str": return _statblock.strength
		"dex": return _statblock.dexterity
		"con": return _statblock.constitution
		"int": return _statblock.intelligence
		"wis": return _statblock.wisdom
		"cha": return _statblock.charisma
	return 10


## Resolve a spell index to its display name.
func _spell_name_for_index(idx: String) -> String:
	for sp: Variant in _spells_raw:
		if sp is SpellData and (sp as SpellData).index == idx:
			return (sp as SpellData).name
	return idx


## Add a custom spell from the inline form.
func _on_add_custom_spell() -> void:
	if _custom_spell_name == null:
		return
	var nm: String = _custom_spell_name.text.strip_edges()
	if nm.is_empty():
		return
	var lvl: int = int(_custom_spell_level.value) if _custom_spell_level != null else 1
	var src: String = _custom_spell_source.text.strip_edges() if _custom_spell_source != null else ""
	_custom_spells.append({"name": nm, "level": lvl, "source": src})
	_custom_spell_name.text = ""
	if _custom_spell_source != null:
		_custom_spell_source.text = ""
	_rebuild_custom_spell_list()


## Rebuild the custom spell list display below the form.
func _rebuild_custom_spell_list() -> void:
	if _custom_spell_list_vbox == null:
		return
	for child: Node in _custom_spell_list_vbox.get_children():
		child.queue_free()
	if _custom_spells.is_empty():
		return
	for idx: int in range(_custom_spells.size()):
		var cs: Dictionary = _custom_spells[idx]
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var level_str: String = "Cantrip" if int(cs.get("level", 1)) == 0 else "Level %d" % int(cs.get("level", 1))
		lbl.text = "%s  (%s)" % [str(cs.get("name", "")), level_str]
		if not str(cs.get("source", "")).is_empty():
			lbl.text += "  —  %s" % str(cs.get("source", ""))
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		var rm_btn := Button.new()
		rm_btn.text = "×"
		rm_btn.flat = true
		rm_btn.modulate = Color(1.0, 0.4, 0.4)
		var capture_idx: int = idx
		rm_btn.pressed.connect(func() -> void:
			_custom_spells.remove_at(capture_idx)
			_rebuild_custom_spell_list()
		)
		row.add_child(rm_btn)
		_custom_spell_list_vbox.add_child(row)
	reapply_theme()


# ── UI scale + theme helpers ─────────────────────────────────────────────────
func _get_ui_scale_mgr() -> UIScaleManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.ui_scale != null:
		return registry.ui_scale
	return null


func _get_ui_scale() -> float:
	var mgr: UIScaleManager = _get_ui_scale_mgr()
	return mgr.get_scale() if mgr != null else 1.0


func reapply_theme() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null:
		return
	var scale: float = _get_ui_scale()
	if registry.ui_theme != null:
		registry.ui_theme.theme_control_tree(self , scale)
	_scale_rich_text_recursive(self , scale)


func _scale_rich_text_recursive(node: Node, scale: float) -> void:
	if node is RichTextLabel:
		var fsz: int = roundi(13.0 * scale)
		(node as RichTextLabel).add_theme_font_size_override("normal_font_size", fsz)
		(node as RichTextLabel).add_theme_font_size_override("bold_font_size", fsz)
	for child: Node in node.get_children():
		_scale_rich_text_recursive(child, scale)
