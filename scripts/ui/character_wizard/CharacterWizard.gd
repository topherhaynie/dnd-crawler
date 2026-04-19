extends Window
class_name CharacterWizard

const _StepNameRace = preload("res://scripts/ui/character_wizard/WizardStepNameRace.gd")
const _StepClass = preload("res://scripts/ui/character_wizard/WizardStepClass.gd")
const _StepClassFeatures = preload("res://scripts/ui/character_wizard/WizardStepClassFeatures.gd")
const _StepAbilities = preload("res://scripts/ui/character_wizard/WizardStepAbilities.gd")
const _StepBackground = preload("res://scripts/ui/character_wizard/WizardStepBackground.gd")
const _StepProficiencies = preload("res://scripts/ui/character_wizard/WizardStepProficiencies.gd")
const _StepReview = preload("res://scripts/ui/character_wizard/WizardStepReview.gd")
const _StepOverride = preload("res://scripts/ui/character_wizard/WizardStepOverride.gd")
const _StatblockBuilder = preload("res://scripts/ui/character_wizard/WizardStatblockBuilder.gd")
const _DetailPanel = preload("res://scripts/ui/character_wizard/WizardDetailPanel.gd")

# -----------------------------------------------------------------------------
# CharacterWizard — step-by-step D&D 5e character creation (shell).
#
# Steps:
#   0  Name & Race        — name input + race OptionButton (SRD)
#   1  Class              — class + level (SRD)
#   2  Class Features     — subclass / cantrip / spell selection per class
#   3  Ability Scores     — manual / standard array / point buy
#   4  Background         — 2014: OptionButton;  2024: informational note
#   5  Proficiencies      — skill proficiency choices
#   6  Review             — summary + optional profile link dropdown
#   7  Override           — free-form editing of all fields
#
# On confirm: emits character_created(statblock: StatblockData, profile_id: String)
# -----------------------------------------------------------------------------

signal character_created(statblock: StatblockData, profile_id: String)

enum Step {NAME_RACE, CLASS, ABILITIES, CLASS_FEATURES, BACKGROUND, PROFICIENCIES, REVIEW, OVERRIDE}

# ── Shared wizard state (public — read/written by step scripts) ──────────────
var char_name: String = ""
var race_index: int = 0
var class_index: int = 0
var level: int = 1
## Multiclass entries: [{class_index: int, level: int}]. Empty = single class.
var extra_classes: Array = []
var ability_mode: int = 0 ## 0=manual 1=standard_array 2=point_buy
var scores: Array[int]
var background: int = 0
var link_profile_id: String = ""
var ruleset: String = "2014"

var races_raw: Array = []
var classes_raw: Array = []
var spells_raw: Array = []
var feats_raw: Array = []


func _campaign_default_ruleset() -> String:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.campaign != null:
		var camp: CampaignData = registry.campaign.get_active_campaign()
		if camp != null:
			return camp.default_ruleset
	return "2014"

## Class features step state
var selected_subclass: String = ""
var chosen_cantrips: Array = []
var chosen_spells: Array = []

## Race subrace selection
var subrace_name: String = ""
var racial_cantrip: String = ""
var racial_extra_languages: Array = []
var half_elf_asi_choices: Array = []

## Class feature extra choices
var chosen_fighting_style: String = ""
var chosen_invocations: Array = []
var chosen_pact_boon: String = ""
var ranger_favored_enemy: String = ""
var ranger_terrain: String = ""
var rogue_expertise_skills: Array = []
var dragonborn_ancestry: String = ""

## ASI-or-feat choices — one entry per earned ASI slot.
## Each is a Dictionary: {type: "asi_plus2"|"asi_plus1x2"|"feat"|"none", ...}
var asi_choices: Array = []
## Extra feats granted by DM outside the ASI budget.
var bonus_feats: Array = []
## Custom feats added by the user.  Each entry is a Dictionary:
## {name: String, desc: String, asi: [{ability: String, amount: int}]}
var custom_feats: Array = []

## Proficiency choices
var chosen_skills: Array = []
var chosen_racial_skills: Array = []

## Override step state
var ov_chosen_spells: Array = []
var ov_custom_spells: Array = []

# ── Private UI references ────────────────────────────────────────────
var _step: int = Step.NAME_RACE
var _step_label: Label = null
var _page_container: BoxContainer = null
var _back_btn: Button = null
var _next_btn: Button = null
var _cancel_btn: Button = null

## Step instances
var _step_name_race: _StepNameRace = null
var _step_class: _StepClass = null
var _step_class_features: _StepClassFeatures = null
var _step_abilities: _StepAbilities = null
var _step_background: _StepBackground = null
var _step_proficiencies: _StepProficiencies = null
var _step_review: _StepReview = null
var _step_override: _StepOverride = null
var _detail_panel: _DetailPanel = null


func _ready() -> void:
	title = "Create Character"
	size = Vector2i(760, 700)
	min_size = Vector2i(640, 560)
	wrap_controls = false
	close_requested.connect(_on_cancel)

	scores.resize(6)
	for i: int in 6:
		scores[i] = 10

	_build_ui()
	_load_srd_data()
	_go_to_step(Step.NAME_RACE)


## Re-initialise and show the wizard from step 1.
func open_wizard() -> void:
	for i: int in 6:
		scores[i] = 10
	char_name = ""
	race_index = 0
	subrace_name = ""
	racial_cantrip = ""
	racial_extra_languages.clear()
	half_elf_asi_choices.clear()
	class_index = 0
	level = 1
	extra_classes.clear()
	ability_mode = 0
	background = 0
	link_profile_id = ""
	ruleset = _campaign_default_ruleset()
	selected_subclass = ""
	chosen_cantrips.clear()
	chosen_spells.clear()
	chosen_fighting_style = ""
	chosen_invocations.clear()
	chosen_pact_boon = ""
	ranger_favored_enemy = ""
	ranger_terrain = ""
	rogue_expertise_skills.clear()
	dragonborn_ancestry = ""
	asi_choices.clear()
	bonus_feats.clear()
	custom_feats.clear()
	chosen_skills.clear()
	chosen_racial_skills.clear()
	ov_chosen_spells.clear()
	ov_custom_spells.clear()
	if _step_name_race != null:
		_step_name_race.reset_ruleset()
	_load_srd_data()
	_go_to_step(Step.NAME_RACE)
	var sm: UIScaleManager = get_ui_scale_mgr()
	if sm != null:
		size = Vector2i(sm.scaled(760.0), sm.scaled(700.0))
		min_size = Vector2i(sm.scaled(640.0), sm.scaled(560.0))
	else:
		size = Vector2i(760, 700)
		min_size = Vector2i(640, 560)
	reapply_theme()
	popup_centered()


## Stub for future level-up mode. TODO(Phase 25): implement incremental
## level-up that pre-populates from an existing statblock, shows only the
## new level's choices (ASI/feat, new spells, subclass if applicable), and
## patches the statblock in place rather than rebuilding from scratch.
func open_level_up(_statblock: StatblockData) -> void:
	push_error("Level-up wizard not implemented — deferred to Phase 25")
	open_wizard()


# ── SRD data loading ──────────────────────────────────────────────────
func _load_srd_data() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.srd != null:
		var races := registry.srd.get_races(ruleset)
		var classes := registry.srd.get_classes(ruleset)
		races_raw = races if not races.is_empty() else registry.srd.get_races("2014")
		classes_raw = classes if not classes.is_empty() else registry.srd.get_classes("2014")
		var spells := registry.srd.get_spells(ruleset)
		spells_raw = spells if not spells.is_empty() else registry.srd.get_spells("2014")
		var feats := registry.srd.get_feats(ruleset)
		feats_raw = feats if not feats.is_empty() else registry.srd.get_feats("2014")
	if _step_name_race != null:
		_step_name_race.populate_race_option()
	if _step_class != null:
		_step_class.populate_class_option()


# ── UI construction ───────────────────────────────────────────────
func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	add_child(root)

	_step_label = Label.new()
	_step_label.add_theme_font_size_override("font_size", scaled_fs(13.0))
	root.add_child(_step_label)

	root.add_child(HSeparator.new())

	_page_container = VBoxContainer.new()
	_page_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_detail_panel = _DetailPanel.new(self )

	var body_row := HBoxContainer.new()
	body_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_row.add_theme_constant_override("separation", 8)
	body_row.add_child(_page_container)
	body_row.add_child(_detail_panel)
	root.add_child(body_row)

	root.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 6)
	root.add_child(btn_row)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_btn)

	_back_btn = Button.new()
	_back_btn.text = "← Back"
	_back_btn.pressed.connect(_on_back)
	btn_row.add_child(_back_btn)

	_next_btn = Button.new()
	_next_btn.text = "Next →"
	_next_btn.pressed.connect(_on_next)
	btn_row.add_child(_next_btn)

	## Create step containers
	_step_name_race = _StepNameRace.new(self )
	_page_container.add_child(_step_name_race)

	_step_class = _StepClass.new(self )
	_page_container.add_child(_step_class)

	_step_abilities = _StepAbilities.new(self )
	_page_container.add_child(_step_abilities)

	_step_class_features = _StepClassFeatures.new(self )
	_page_container.add_child(_step_class_features)

	_step_background = _StepBackground.new(self )
	_page_container.add_child(_step_background)

	_step_proficiencies = _StepProficiencies.new(self )
	_page_container.add_child(_step_proficiencies)

	_step_review = _StepReview.new(self )
	_page_container.add_child(_step_review)

	_step_override = _StepOverride.new(self )
	_page_container.add_child(_step_override)

	var srd_notice := Label.new()
	srd_notice.text = "Content is based on the D&D 5e SRD (CC BY 4.0). For the complete rules and all classes we encourage you to support the creators — pick up the official books at your local game store or DnDBeyond.com."
	srd_notice.autowrap_mode = TextServer.AUTOWRAP_WORD
	srd_notice.add_theme_font_size_override("font_size", scaled_fs(10.0))
	srd_notice.modulate = Color(0.45, 0.45, 0.45)
	root.add_child(srd_notice)


# ── Step navigation ───────────────────────────────────────────────
func _go_to_step(step: int) -> void:
	_step = step
	_step_label.text = WizardConstants.STEP_TITLES[step]

	for child: Node in _page_container.get_children():
		child.visible = false

	match step:
		Step.NAME_RACE:
			_step_name_race.visible = true
			_back_btn.disabled = true
			_next_btn.text = "Next →"
		Step.CLASS:
			_step_class.visible = true
			_back_btn.disabled = false
			_next_btn.text = "Next →"
		Step.ABILITIES:
			_step_abilities.refresh_display()
			_step_abilities.visible = true
			_back_btn.disabled = false
			_next_btn.text = "Next →"
		Step.CLASS_FEATURES:
			_step_class_features.refresh_ui()
			_step_class_features.visible = true
			_back_btn.disabled = false
			_next_btn.text = "Next →"
		Step.BACKGROUND:
			_step_background.refresh_ui()
			_step_background.visible = true
			_back_btn.disabled = false
			_next_btn.text = "Next →"
		Step.PROFICIENCIES:
			_step_proficiencies.refresh_ui()
			_step_proficiencies.visible = true
			_back_btn.disabled = false
			_next_btn.text = "Next →"
		Step.REVIEW:
			_step_review.populate_review()
			_step_review.visible = true
			_back_btn.disabled = false
			_next_btn.text = "Next →"
		Step.OVERRIDE:
			_step_override.refresh_ui()
			_step_override.visible = true
			_back_btn.disabled = false
			_next_btn.text = "Create Character"


func _on_back() -> void:
	if _step > 0:
		_go_to_step(_step - 1)


func _on_next() -> void:
	if not _validate_step(_step):
		return
	if _step < Step.OVERRIDE:
		_go_to_step(_step + 1)
	else:
		_confirm_create()


func _validate_step(step: int) -> bool:
	match step:
		Step.NAME_RACE:
			return _step_name_race.validate()
		Step.CLASS_FEATURES:
			return _step_class_features.validate()
		Step.ABILITIES:
			return _step_abilities.validate()
	return true


func _on_cancel() -> void:
	hide()


func _on_ruleset_changed(new_ruleset: String) -> void:
	ruleset = new_ruleset
	race_index = 0
	subrace_name = ""
	class_index = 0
	extra_classes.clear()
	_load_srd_data()


# ── Confirmation ──────────────────────────────────────────────────────────────
func _confirm_create() -> void:
	link_profile_id = ""
	var sel: int = _step_review.get_selected_profile_index()
	var ids: Array = _step_review.get_profile_ids()
	if sel >= 0 and sel < ids.size():
		link_profile_id = ids[sel]

	var sb: StatblockData = _StatblockBuilder.build(self )
	_step_override.apply_overrides(sb)

	hide()
	character_created.emit(sb, link_profile_id)


# ── Race / subrace mechanic helpers (shared across steps) ────────────────────

func get_subrace_dict() -> Dictionary:
	if subrace_name.is_empty():
		return {}
	var race_nm: String = get_selected_race_name()
	var subs_var: Variant = WizardConstants.SUBRACE_DATA.get(race_nm, [])
	if subs_var is Array:
		for s: Variant in subs_var as Array:
			if s is Dictionary and str((s as Dictionary).get("name", "")) == subrace_name:
				return s as Dictionary
	return {}


func get_race_dict() -> Dictionary:
	var race_nm: String = get_selected_race_name()
	var d_var: Variant = WizardConstants.RACE_DATA.get(race_nm, {})
	return d_var as Dictionary if d_var is Dictionary else {}


func get_total_race_asi() -> Dictionary:
	var totals: Dictionary = {}
	var rd: Dictionary = get_race_dict()
	var asi_var: Variant = rd.get("asi_keys", [])
	if asi_var is Array:
		for entry: Variant in asi_var as Array:
			if entry is Dictionary:
				var ed := entry as Dictionary
				var k: String = str(ed.get("key", ""))
				var b: int = int(ed.get("bonus", 0))
				totals[k] = int(totals.get(k, 0)) + b
	for k: String in half_elf_asi_choices:
		totals[k] = int(totals.get(k, 0)) + 1
	var sd: Dictionary = get_subrace_dict()
	var sub_asi_var: Variant = sd.get("asi_keys", [])
	if sub_asi_var is Array:
		for entry: Variant in sub_asi_var as Array:
			if entry is Dictionary:
				var ed := entry as Dictionary
				var k: String = str(ed.get("key", ""))
				var b: int = int(ed.get("bonus", 0))
				totals[k] = int(totals.get(k, 0)) + b
	return totals


## Collect ability score bonuses from ASI slot choices and custom feats (not racial).
func get_asi_choice_bonuses() -> Dictionary:
	var totals: Dictionary = {}
	for choice: Variant in asi_choices:
		if not choice is Dictionary:
			continue
		var c: Dictionary = choice as Dictionary
		var t: String = str(c.get("type", "none"))
		match t:
			"asi_plus2":
				var ab: String = str(c.get("ability", ""))
				if not ab.is_empty():
					totals[ab] = int(totals.get(ab, 0)) + 2
			"asi_plus1x2":
				var ab1: String = str(c.get("ability1", ""))
				var ab2: String = str(c.get("ability2", ""))
				if not ab1.is_empty():
					totals[ab1] = int(totals.get(ab1, 0)) + 1
				if not ab2.is_empty():
					totals[ab2] = int(totals.get(ab2, 0)) + 1
			"feat":
				var feat_nm: String = str(c.get("feat_name", ""))
				if feat_nm.is_empty():
					continue
				var fd: Dictionary = _find_feat_dict(feat_nm)
				if fd.is_empty():
					continue
				var feat_asi_var: Variant = fd.get("asi", [])
				if not (feat_asi_var is Array):
					continue
				for entry_var: Variant in feat_asi_var as Array:
					if not (entry_var is Dictionary):
						continue
					var entry: Dictionary = entry_var as Dictionary
					var ab: String = str(entry.get("ability", ""))
					var amt: int = int(entry.get("amount", 0))
					if ab == "choice":
						ab = _resolve_feat_choice_ab(c)
					if not ab.is_empty() and amt != 0:
						totals[ab] = int(totals.get(ab, 0)) + amt
	# Custom feat ASI bonuses
	for cf_var: Variant in custom_feats:
		if not (cf_var is Dictionary):
			continue
		var cf: Dictionary = cf_var as Dictionary
		var cf_asi_var: Variant = cf.get("asi", [])
		if not (cf_asi_var is Array):
			continue
		for entry_var: Variant in cf_asi_var as Array:
			if not (entry_var is Dictionary):
				continue
			var entry: Dictionary = entry_var as Dictionary
			var ab: String = str(entry.get("ability", ""))
			var amt: int = int(entry.get("amount", 0))
			if not ab.is_empty() and amt != 0:
				totals[ab] = int(totals.get(ab, 0)) + amt
	return totals


## Find a feat dict from feats_raw by name.
func _find_feat_dict(feat_nm: String) -> Dictionary:
	for fd_var: Variant in feats_raw:
		if fd_var is Dictionary:
			var fd: Dictionary = fd_var as Dictionary
			if str(fd.get("name", "")) == feat_nm:
				return fd
	return {}


## Resolve the ability key from a feat ASI choice stored in choice["feat_choices"].
func _resolve_feat_choice_ab(choice: Dictionary) -> String:
	var fc_var: Variant = choice.get("feat_choices", [])
	if not (fc_var is Array):
		return ""
	for fc_entry_var: Variant in fc_var as Array:
		if not (fc_entry_var is Dictionary):
			continue
		var sel: String = str((fc_entry_var as Dictionary).get("selection", ""))
		if sel.length() == 3 and WizardConstants.ABILITY_KEYS.has(sel):
			return sel
	return ""


## All feat names chosen via ASI slots, bonus feats, or custom feats.
func get_all_chosen_feat_names() -> Array:
	var names: Array = []
	for choice: Variant in asi_choices:
		if not choice is Dictionary:
			continue
		var c: Dictionary = choice as Dictionary
		if str(c.get("type", "")) == "feat":
			var nm: String = str(c.get("feat_name", ""))
			if not nm.is_empty() and not names.has(nm):
				names.append(nm)
	for nm: String in bonus_feats:
		if not names.has(nm):
			names.append(nm)
	for cf: Variant in custom_feats:
		if cf is Dictionary:
			var nm: String = str((cf as Dictionary).get("name", ""))
			if not nm.is_empty() and not names.has(nm):
				names.append(nm)
	return names


## Build the classes array for StatblockData from primary + extra classes.
func get_classes_array() -> Array:
	var result: Array = []
	var primary_name: String = get_selected_class_name()
	var primary_level: int = level
	# If multiclassing, primary level = level minus sum of extra levels
	var extra_level_sum: int = 0
	for ec: Variant in extra_classes:
		if ec is Dictionary:
			extra_level_sum += int((ec as Dictionary).get("level", 0))
	primary_level = maxi(1, level - extra_level_sum)
	result.append({"name": primary_name, "level": primary_level, "subclass": selected_subclass})
	for ec: Variant in extra_classes:
		if not (ec is Dictionary):
			continue
		var ecd: Dictionary = ec as Dictionary
		var ci: int = int(ecd.get("class_index", 0))
		var el: int = int(ecd.get("level", 1))
		var ec_name: String = ""
		if ci >= 0 and ci < classes_raw.size():
			var raw: Variant = classes_raw[ci]
			if raw is Dictionary:
				ec_name = str((raw as Dictionary).get("name", ""))
		if not ec_name.is_empty():
			result.append({"name": ec_name, "level": el, "subclass": ""})
	return result


## Check multiclass prerequisites for a given class index against current scores.
## Returns "" if met, or a reason string if not met.
func check_multiclass_prereq(ci: int) -> String:
	if ci < 0 or ci >= classes_raw.size():
		return "Invalid class"
	var raw: Variant = classes_raw[ci]
	if not (raw is Dictionary):
		return "Invalid class data"
	var cd: Dictionary = raw as Dictionary
	var mc_var: Variant = cd.get("multi_classing", {})
	if not (mc_var is Dictionary):
		return ""
	var mc: Dictionary = mc_var as Dictionary
	var prereqs_var: Variant = mc.get("prerequisites", [])
	if not (prereqs_var is Array):
		return ""
	for p_var: Variant in prereqs_var as Array:
		if not (p_var is Dictionary):
			continue
		var p: Dictionary = p_var as Dictionary
		var min_score: int = int(p.get("minimum_score", 0))
		var ab_dict_var: Variant = p.get("ability_score", {})
		if ab_dict_var is Dictionary:
			var ab_key: String = str((ab_dict_var as Dictionary).get("index", ""))
			var idx: int = WizardConstants.ABILITY_KEYS.find(ab_key)
			if idx >= 0 and scores[idx] < min_score:
				return "Requires %s %d+" % [WizardConstants.ABILITY_NAMES[idx], min_score]
	return ""


func get_racial_speed() -> int:
	var sub_speed: int = int(get_subrace_dict().get("speed", 0))
	if sub_speed > 0:
		return sub_speed
	return get_selected_race_speed()


func get_racial_darkvision() -> int:
	var sd: Dictionary = get_subrace_dict()
	var sub_dv: int = int(sd.get("darkvision", -1))
	if sub_dv >= 0:
		return sub_dv
	return int(get_race_dict().get("darkvision", 0))


func get_racial_spell_indices() -> Array:
	var result: Array = []
	var rc_var: Variant = get_race_dict().get("racial_cantrips", [])
	if rc_var is Array:
		for s: Variant in rc_var as Array:
			result.append(str(s))
	var src_var: Variant = get_subrace_dict().get("racial_cantrips", [])
	if src_var is Array:
		for s: Variant in src_var as Array:
			result.append(str(s))
	if not racial_cantrip.is_empty() and not result.has(racial_cantrip):
		result.append(racial_cantrip)
	return result


func get_racial_levelled_spells() -> Array:
	var result: Array = []
	var rs_var: Variant = get_race_dict().get("racial_spells", [])
	if rs_var is Array:
		for entry: Variant in rs_var as Array:
			if entry is Dictionary:
				var ed := entry as Dictionary
				if level >= int(ed.get("unlocked_at_level", 99)):
					result.append(str(ed.get("index", "")))
	var ss_var: Variant = get_subrace_dict().get("racial_spells", [])
	if ss_var is Array:
		for entry: Variant in ss_var as Array:
			if entry is Dictionary:
				var ed := entry as Dictionary
				if level >= int(ed.get("unlocked_at_level", 99)):
					result.append(str(ed.get("index", "")))
	return result


func get_racial_damage_resistances() -> Array:
	var result: Array = []
	var rd_var: Variant = get_race_dict().get("damage_resist", [])
	if rd_var is Array:
		for s: Variant in rd_var as Array:
			result.append(str(s))
	var sd_var: Variant = get_subrace_dict().get("damage_resist", [])
	if sd_var is Array:
		for s: Variant in sd_var as Array:
			if not result.has(str(s)):
				result.append(str(s))
	return result


func get_all_languages() -> Array:
	var result: Array = []
	var rd: Dictionary = get_race_dict()
	var lang_var: Variant = rd.get("languages", [])
	if lang_var is Array:
		for l: Variant in lang_var as Array:
			result.append(str(l))
	for l: String in racial_extra_languages:
		if not l.is_empty() and not result.has(l):
			result.append(l)
	return result


func expected_extra_language_count() -> int:
	var rd: Dictionary = get_race_dict()
	var count: int = int(rd.get("choose_languages", 0))
	if bool(rd.get("choose_language", false)):
		count = maxi(count, 1)
	if bool(get_subrace_dict().get("choose_language", false)):
		count = maxi(count, 1)
	return count


func get_racial_features() -> Array:
	var result: Array = []
	var rd: Dictionary = get_race_dict()
	## SRD race data uses "traits" (name/index references), not "features".
	var traits_var: Variant = rd.get("traits", [])
	if traits_var is Array:
		for t: Variant in traits_var as Array:
			if t is Dictionary:
				var td: Dictionary = t as Dictionary
				var trait_name: String = str(td.get("name", ""))
				if not trait_name.is_empty():
					result.append({
						"name": trait_name,
						"desc": str(td.get("desc", trait_name)),
						"source": "race",
					})
	## Also include any explicit "features" if present.
	var rf_var: Variant = rd.get("features", [])
	if rf_var is Array:
		for f: Variant in rf_var as Array:
			if f is Dictionary:
				var fd: Dictionary = (f as Dictionary).duplicate()
				fd["source"] = "race"
				result.append(fd)
	var sd: Dictionary = get_subrace_dict()
	var sub_traits_var: Variant = sd.get("traits", [])
	if sub_traits_var is Array:
		for t: Variant in sub_traits_var as Array:
			if t is Dictionary:
				var td: Dictionary = t as Dictionary
				var st_name: String = str(td.get("name", subrace_name))
				result.append({"name": st_name, "desc": str(td.get("desc", st_name)), "source": "race"})
			else:
				result.append({"name": subrace_name, "desc": str(t), "source": "race"})
	return result


# ── SRD data accessors ────────────────────────────────────────────────
func get_selected_race_name() -> String:
	if races_raw.is_empty() or race_index >= races_raw.size():
		return ""
	var raw: Variant = races_raw[race_index]
	if raw is Dictionary:
		return str((raw as Dictionary).get("name", ""))
	return ""


## Returns a display-friendly race string that includes the subrace when
## selected, avoiding duplication (e.g. "High Elf" not "High Elf Elf").
func get_display_race_name() -> String:
	var base: String = get_selected_race_name()
	if subrace_name.is_empty():
		return base
	# If the subrace already contains the base race name, use it as-is.
	if subrace_name.to_lower().contains(base.to_lower()):
		return subrace_name
	return subrace_name + " " + base


func get_selected_race_speed() -> int:
	if races_raw.is_empty() or race_index >= races_raw.size():
		return 30
	var raw: Variant = races_raw[race_index]
	if raw is Dictionary:
		return int((raw as Dictionary).get("speed", 30))
	return 30


func get_selected_race_size() -> String:
	if races_raw.is_empty() or race_index >= races_raw.size():
		return "Medium"
	var raw: Variant = races_raw[race_index]
	if raw is Dictionary:
		return str((raw as Dictionary).get("size", "Medium"))
	return "Medium"


func get_selected_class_name() -> String:
	if classes_raw.is_empty() or class_index >= classes_raw.size():
		return ""
	var raw: Variant = classes_raw[class_index]
	if raw is Dictionary:
		return str((raw as Dictionary).get("name", ""))
	return ""


func get_selected_hit_die() -> int:
	if classes_raw.is_empty() or class_index >= classes_raw.size():
		return 8
	var raw: Variant = classes_raw[class_index]
	if raw is Dictionary:
		return int((raw as Dictionary).get("hit_die", 8))
	return 8


func get_selected_class_saves() -> Array:
	if classes_raw.is_empty() or class_index >= classes_raw.size():
		return []
	var raw: Variant = classes_raw[class_index]
	if not (raw is Dictionary):
		return []
	var saves_raw: Variant = (raw as Dictionary).get("saving_throws", [])
	if not (saves_raw is Array):
		return []
	var result: Array = []
	for s: Variant in saves_raw as Array:
		if s is Dictionary:
			var sd := s as Dictionary
			result.append({"proficiency": {"index": str(sd.get("index", "")),
					"name": str(sd.get("name", ""))}, "value": 0})
	return result


func get_spells_for_class(class_nm: String, spell_level: int) -> Array:
	var result: Array = []
	for sp: Variant in spells_raw:
		if not (sp is SpellData):
			continue
		var sd := sp as SpellData
		if sd.level != spell_level:
			continue
		for cls_name: Variant in sd.classes:
			if str(cls_name).nocasecmp_to(class_nm) == 0:
				result.append(sd)
				break
	return result


func get_class_data_value(key: String) -> String:
	var cd: Variant = WizardConstants.CLASS_DATA.get(get_selected_class_name().to_lower())
	if cd is Dictionary:
		return str((cd as Dictionary).get(key, ""))
	return ""


## Check whether a feat's prerequisites are met by the current wizard state.
## Returns "" if met, or a human-readable reason string if not.
func check_feat_prerequisite(feat_dict: Dictionary) -> String:
	var prereq: String = str(feat_dict.get("prerequisite", ""))
	if prereq.is_empty():
		return ""
	var p_lower: String = prereq.to_lower()
	# Ability score prerequisites (e.g. "Dexterity 13 or higher")
	for i: int in WizardConstants.ABILITY_NAMES.size():
		var ab_name: String = WizardConstants.ABILITY_NAMES[i].to_lower()
		if p_lower.contains(ab_name):
			var parts: PackedStringArray = p_lower.split(ab_name)
			if parts.size() > 1:
				var after: String = parts[1].strip_edges()
				# Handle "or Wisdom 13" pattern
				var threshold: int = 0
				for word: String in after.split(" "):
					if word.is_valid_int():
						threshold = int(word)
						break
				if threshold > 0 and scores[i] < threshold:
					return "Requires %s %d+" % [WizardConstants.ABILITY_NAMES[i], threshold]
	# "Intelligence or Wisdom 13 or higher" (Ritual Caster)
	if p_lower.contains(" or ") and p_lower.contains("13"):
		var meets_any: bool = false
		for i: int in WizardConstants.ABILITY_NAMES.size():
			if p_lower.contains(WizardConstants.ABILITY_NAMES[i].to_lower()) and scores[i] >= 13:
				meets_any = true
				break
		if not meets_any:
			return prereq
	# Spellcasting prerequisites
	if p_lower.contains("ability to cast at least one spell"):
		var class_key: String = get_selected_class_name().to_lower()
		var spell_type: String = str(WizardConstants.CLASS_DATA.get(class_key, {}).get("spell_type", ""))
		if spell_type.is_empty():
			return "Requires spellcasting ability"
	# Armor proficiency prerequisites
	if p_lower.contains("proficiency with heavy armor"):
		var class_key: String = get_selected_class_name().to_lower()
		if class_key not in ["fighter", "paladin"]:
			return "Requires heavy armor proficiency"
	if p_lower.contains("proficiency with medium armor"):
		var class_key: String = get_selected_class_name().to_lower()
		if class_key not in ["barbarian", "cleric", "druid", "fighter", "paladin", "ranger"]:
			return "Requires medium armor proficiency"
	if p_lower.contains("proficiency with light armor"):
		var class_key: String = get_selected_class_name().to_lower()
		if class_key not in ["barbarian", "bard", "cleric", "druid", "fighter", "monk", "paladin", "ranger", "rogue", "warlock"]:
			return "Requires light armor proficiency"
	return ""


## Show spell details in the side panel.
func show_spell_detail(sd: SpellData) -> void:
	if _detail_panel != null:
		_detail_panel.show_spell(sd)


## Show feat details in the side panel.
func show_feat_detail(feat_dict: Dictionary) -> void:
	if _detail_panel != null:
		_detail_panel.show_feat(feat_dict)


## Show a generic text detail in the side panel.
func show_text_detail(heading: String, description: String) -> void:
	if _detail_panel != null:
		_detail_panel.show_text(heading, description)


# ── UI scale + theme helpers ───────────────────────────────────────
func get_ui_scale_mgr() -> UIScaleManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.ui_scale != null:
		return registry.ui_scale
	return null


func get_ui_scale() -> float:
	var mgr: UIScaleManager = get_ui_scale_mgr()
	return mgr.get_scale() if mgr != null else 1.0


func scaled_fs(base: float) -> int:
	var mgr: UIScaleManager = get_ui_scale_mgr()
	return mgr.scaled(base) if mgr != null else roundi(base)


func reapply_theme() -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null:
		return
	var scale: float = get_ui_scale()
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


func show_error(msg: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.dialog_text = msg
	dlg.title = "Validation"
	add_child(dlg)
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.ui_theme != null:
		reg.ui_theme.theme_control_tree(dlg, get_ui_scale())
	dlg.reset_size()
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
