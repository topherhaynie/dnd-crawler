extends ICombatService
class_name CombatService

## CombatService — initiative tracking, turn management, HP/damage pipeline.
##
## Relies on sibling services via ServiceRegistry:
##   registry.token  — token data queries and updates
##   registry.statblock — base statblock lookups
##   registry.dice   — dice rolling

var _state: CombatState = CombatState.new()
var _aoes: Dictionary = {} ## id -> AoEData
var _combat_log: Array = [] ## Array of entry Dictionaries
var _used_label_max: Dictionary = {} ## base_name -> highest number ever assigned this combat
var _player_overrides: Dictionary = {} ## profile_id -> StatblockOverride.to_dict()
var _exhaustion_levels: Dictionary = {} ## token_id -> int (exhaustion level)


# ---------------------------------------------------------------------------
# Combat lifecycle
# ---------------------------------------------------------------------------

func start_combat(token_ids: Array[String]) -> void:
	if _state.is_active:
		end_combat()
	_state = CombatState.new()
	_state.is_active = true
	_state.round_number = 1
	_state.current_turn_index = 0
	_state.initiative_order.clear()
	_player_overrides.clear()
	for tid: String in token_ids:
		_ensure_player_override(tid)
		_state.initiative_order.append({
			"token_id": tid,
			"initiative": 0,
			"dex_mod": _get_dex_mod(tid),
			"init_bonus": _get_initiative_bonus(tid),
		})
	_used_label_max.clear()
	_ensure_unique_combatant_names()
	combat_started.emit()
	initiative_changed.emit(_state.initiative_order.duplicate(true))
	_log({"type": "combat_start"})


func end_combat() -> void:
	if not _state.is_active:
		return
	_state.is_active = false
	_log({"type": "combat_end"})
	_state.initiative_order.clear()
	_state.readied_actions.clear()
	_state.delayed_tokens.clear()
	_state.conditions.clear()
	_used_label_max.clear()
	_player_overrides.clear()
	_exhaustion_levels.clear()
	combat_ended.emit()


func reset_combat_labels() -> void:
	# Strip all trailing " N" suffixes from active combatants so that
	# _ensure_unique_combatant_names can assign fresh sequential numbers.
	var reg: ServiceRegistry = _get_registry()
	if reg != null and reg.token != null:
		var tm: TokenManager = reg.token
		for entry: Dictionary in _state.initiative_order:
			var tid: String = str(entry.get("token_id", ""))
			if tid.is_empty():
				continue
			var td: TokenData = tm.get_token_by_id(tid)
			if td == null:
				continue
			var si: int = td.label.rfind(" ")
			if si != -1 and td.label.substr(si + 1).is_valid_int():
				td.label = td.label.left(si)
				tm.update_token(td)
	_used_label_max.clear()
	_ensure_unique_combatant_names()
	initiative_changed.emit(_state.initiative_order.duplicate(true))


func is_in_combat() -> bool:
	return _state.is_active


func add_combatant(token_id: String) -> void:
	if not _state.is_active:
		return
	for entry: Dictionary in _state.initiative_order:
		if str(entry.get("token_id", "")) == token_id:
			return # already present
	_ensure_player_override(token_id)
	_state.initiative_order.append({
		"token_id": token_id,
		"initiative": 0,
		"dex_mod": _get_dex_mod(token_id),
		"init_bonus": _get_initiative_bonus(token_id),
	})
	_ensure_unique_combatant_names()
	combatant_added.emit(token_id)
	initiative_changed.emit(_state.initiative_order.duplicate(true))


func remove_combatant(token_id: String) -> void:
	if not _state.is_active:
		return
	var current_tid: String = get_current_turn_token_id()
	for i: int in range(_state.initiative_order.size()):
		if str(_state.initiative_order[i].get("token_id", "")) == token_id:
			_state.initiative_order.remove_at(i)
			# Adjust turn index if needed.
			if _state.initiative_order.is_empty():
				_state.current_turn_index = 0
			elif i < _state.current_turn_index:
				_state.current_turn_index -= 1
			elif i == _state.current_turn_index:
				_state.current_turn_index = mini(_state.current_turn_index,
					_state.initiative_order.size() - 1)
			break
	_state.readied_actions.erase(token_id)
	_state.delayed_tokens.erase(token_id)
	combatant_removed.emit(token_id)
	initiative_changed.emit(_state.initiative_order.duplicate(true))
	# If the removed combatant was the active turn, emit turn_changed.
	if current_tid == token_id and not _state.initiative_order.is_empty():
		var new_tid: String = get_current_turn_token_id()
		turn_changed.emit(new_tid, _state.round_number)


# ---------------------------------------------------------------------------
# Initiative
# ---------------------------------------------------------------------------

func roll_initiative_all() -> void:
	if not _state.is_active:
		return
	var dice_svc: IDiceService = _get_dice_service()
	if dice_svc == null:
		return
	for entry: Dictionary in _state.initiative_order:
		var dex_mod: int = int(entry.get("dex_mod", 0))
		var init_bonus: int = int(entry.get("init_bonus", 0))
		var modifier: int = dex_mod + init_bonus
		var result: DiceResult = dice_svc.roll_fast("1d20", {"context": "initiative"})
		entry["initiative"] = result.total + modifier
		_log({"type": "initiative_rolled", "token_id": str(entry.get("token_id", "")),
			"token_name": _get_name(str(entry.get("token_id", ""))),
			"roll": result.total, "modifier": modifier, "total": result.total + modifier})
	_sort_initiative()
	_state.current_turn_index = 0
	initiative_changed.emit(_state.initiative_order.duplicate(true))
	if not _state.initiative_order.is_empty():
		turn_changed.emit(get_current_turn_token_id(), _state.round_number)


func set_initiative(token_id: String, value: int) -> void:
	for entry: Dictionary in _state.initiative_order:
		if str(entry.get("token_id", "")) == token_id:
			entry["initiative"] = value
			break
	_sort_initiative()
	initiative_changed.emit(_state.initiative_order.duplicate(true))
	_log({"type": "initiative_rolled", "token_id": token_id,
		"token_name": _get_name(token_id), "roll": value, "modifier": 0, "total": value})


func get_initiative_order() -> Array:
	return _state.initiative_order.duplicate(true)


func is_combatant(token_id: String) -> bool:
	if not _state.is_active:
		return false
	for entry: Dictionary in _state.initiative_order:
		if str(entry.get("token_id", "")) == token_id:
			return true
	return false


# ---------------------------------------------------------------------------
# Turn management
# ---------------------------------------------------------------------------

func next_turn() -> void:
	if not _state.is_active or _state.initiative_order.is_empty():
		return
	_state.current_turn_index += 1
	if _state.current_turn_index >= _state.initiative_order.size():
		_state.current_turn_index = 0
		_state.round_number += 1
		_state.delayed_tokens.clear()
	var new_tid: String = get_current_turn_token_id()
	_process_condition_expiry(new_tid)
	turn_changed.emit(new_tid, _state.round_number)
	_log({"type": "turn_start", "token_id": new_tid, "token_name": _get_name(new_tid), "round": _state.round_number})


func previous_turn() -> void:
	if not _state.is_active or _state.initiative_order.is_empty():
		return
	_state.current_turn_index -= 1
	if _state.current_turn_index < 0:
		_state.current_turn_index = _state.initiative_order.size() - 1
		_state.round_number = maxi(1, _state.round_number - 1)
	turn_changed.emit(get_current_turn_token_id(), _state.round_number)


func delay_turn(token_id: String) -> void:
	if not _state.is_active:
		return
	# Move the token to end of initiative order.
	var idx: int = _find_combatant_index(token_id)
	if idx < 0:
		return
	var entry: Dictionary = _state.initiative_order[idx]
	_state.initiative_order.remove_at(idx)
	_state.initiative_order.append(entry)
	_state.delayed_tokens.append(token_id)
	# Adjust turn index.
	if idx < _state.current_turn_index:
		_state.current_turn_index -= 1
	elif idx == _state.current_turn_index:
		# The active combatant delayed — move to next (same index, new entry).
		_state.current_turn_index = mini(_state.current_turn_index,
			_state.initiative_order.size() - 1)
		turn_changed.emit(get_current_turn_token_id(), _state.round_number)
	initiative_changed.emit(_state.initiative_order.duplicate(true))


func ready_action(token_id: String) -> void:
	if not _state.is_active:
		return
	if not _state.readied_actions.has(token_id):
		_state.readied_actions.append(token_id)


func get_current_turn_token_id() -> String:
	if _state.initiative_order.is_empty():
		return ""
	var idx: int = clampi(_state.current_turn_index, 0, _state.initiative_order.size() - 1)
	return str(_state.initiative_order[idx].get("token_id", ""))


func get_round_number() -> int:
	return _state.round_number


# ---------------------------------------------------------------------------
# HP / Damage pipeline
# ---------------------------------------------------------------------------

func apply_damage(token_id: String, amount: int, damage_type: String) -> Dictionary:
	var override: StatblockOverride = _get_override(token_id)
	if override == null:
		return {"actual_damage": 0, "new_hp": 0, "killed": false, "detail": "no statblock"}

	var base: StatblockData = _get_base_statblock(token_id)
	var effective_amount: int = amount
	var detail: String = ""

	if base != null and not damage_type.is_empty():
		# Immunity check
		if _has_damage_type(base.damage_immunities, damage_type):
			detail = "immune to %s" % damage_type
			return {"actual_damage": 0, "new_hp": override.current_hp, "killed": false, "detail": detail}
		# Resistance check (halve, round down)
		if _has_damage_type(base.damage_resistances, damage_type):
			effective_amount = int(floor(float(amount) / 2.0))
			detail = "halved from %d — %s resistance" % [amount, damage_type]
		# Vulnerability check (double)
		elif _has_damage_type(base.damage_vulnerabilities, damage_type):
			effective_amount = amount * 2
			detail = "doubled from %d — %s vulnerability" % [amount, damage_type]

	# Subtract temp HP first.
	var remaining: int = effective_amount
	if override.temp_hp > 0:
		var absorbed: int = mini(override.temp_hp, remaining)
		override.temp_hp -= absorbed
		remaining -= absorbed
		if not detail.is_empty():
			detail += "; %d absorbed by temp HP" % absorbed
		elif absorbed > 0:
			detail = "%d absorbed by temp HP" % absorbed

	# Subtract from current HP.
	override.current_hp = maxi(0, override.current_hp - remaining)
	_commit_override(token_id, override)

	var killed: bool = override.current_hp <= 0
	if killed:
		# Monsters die instantly at 0 HP.
		var td: TokenData = _get_token(token_id)
		if td != null and td.category == TokenData.TokenCategory.MONSTER:
			token_killed.emit(token_id)
		# PCs enter death saves — that's handled externally via roll_death_save.

	hp_changed.emit(token_id, override.current_hp, override.max_hp, -effective_amount)
	_log({"type": "damage_dealt", "source_id": "", "source_name": "",
		"target_id": token_id, "target_name": _get_name(token_id),
		"amount": amount, "actual": effective_amount, "type_detail": damage_type, "detail": detail})
	if killed:
		_log({"type": "token_killed", "token_id": token_id, "token_name": _get_name(token_id)})
	return {
		"actual_damage": effective_amount,
		"new_hp": override.current_hp,
		"killed": killed,
		"detail": detail,
	}


func apply_healing(token_id: String, amount: int) -> Dictionary:
	var override: StatblockOverride = _get_override(token_id)
	if override == null:
		return {"actual_healing": 0, "new_hp": 0}
	var old_hp: int = override.current_hp
	override.current_hp = mini(override.current_hp + amount, override.max_hp)
	var actual: int = override.current_hp - old_hp
	# Clear death saves on healing from 0.
	if old_hp == 0 and override.current_hp > 0:
		override.death_saves = {"successes": 0, "failures": 0}
	_commit_override(token_id, override)
	hp_changed.emit(token_id, override.current_hp, override.max_hp, actual)
	_log({"type": "healing_applied", "source_id": "", "source_name": "",
		"target_id": token_id, "target_name": _get_name(token_id), "amount": actual})
	return {"actual_healing": actual, "new_hp": override.current_hp}


func apply_temp_hp(token_id: String, amount: int) -> void:
	var override: StatblockOverride = _get_override(token_id)
	if override == null:
		return
	# Temp HP doesn't stack — take the higher value.
	override.temp_hp = maxi(override.temp_hp, amount)
	_commit_override(token_id, override)


func roll_death_save(token_id: String) -> Dictionary:
	var override: StatblockOverride = _get_override(token_id)
	if override == null:
		return {"roll": 0, "success": false, "stabilized": false, "dead": false}
	var dice_svc: IDiceService = _get_dice_service()
	if dice_svc == null:
		return {"roll": 0, "success": false, "stabilized": false, "dead": false}

	var result: DiceResult = dice_svc.roll_fast("1d20", {"context": "death_save"})
	var roll_val: int = result.total
	var successes: int = int(override.death_saves.get("successes", 0))
	var failures: int = int(override.death_saves.get("failures", 0))

	# Nat 20 → regain 1 HP.
	if result.is_critical:
		override.current_hp = 1
		override.death_saves = {"successes": 0, "failures": 0}
		_commit_override(token_id, override)
		token_stabilized.emit(token_id)
		hp_changed.emit(token_id, 1, override.max_hp, 1)
		_log({"type": "death_save", "token_id": token_id, "token_name": _get_name(token_id),
			"roll": roll_val, "success": true, "stabilized": true, "dead": false})
		return {"roll": roll_val, "success": true, "stabilized": true, "dead": false}

	# Nat 1 → 2 failures.
	if result.is_fumble:
		failures += 2
	elif roll_val >= 10:
		successes += 1
	else:
		failures += 1

	override.death_saves = {"successes": successes, "failures": failures}

	var stabilized: bool = successes >= 3
	var dead: bool = failures >= 3

	_commit_override(token_id, override)

	if stabilized:
		token_stabilized.emit(token_id)
		_log({"type": "token_stabilized", "token_id": token_id, "token_name": _get_name(token_id)})
	if dead:
		token_killed.emit(token_id)
		_log({"type": "token_killed", "token_id": token_id, "token_name": _get_name(token_id)})

	_log({"type": "death_save", "token_id": token_id, "token_name": _get_name(token_id),
		"roll": roll_val, "success": roll_val >= 10 or result.is_critical,
		"stabilized": stabilized, "dead": dead})
	return {"roll": roll_val, "success": roll_val >= 10 or result.is_critical,
		"stabilized": stabilized, "dead": dead}


func get_hp_status(token_id: String) -> Dictionary:
	var override: StatblockOverride = _get_override(token_id)
	if override == null:
		return {"current": 0, "max": 0, "temp": 0, "bloodied": false, "dead": false}
	var bloodied: bool = override.max_hp > 0 and override.current_hp <= int(
		floor(float(override.max_hp) / 2.0))
	var dead: bool = override.current_hp <= 0
	return {
		"current": override.current_hp,
		"max": override.max_hp,
		"temp": override.temp_hp,
		"bloodied": bloodied,
		"dead": dead,
	}


# ---------------------------------------------------------------------------
# Saving throws
# ---------------------------------------------------------------------------

func call_for_save(ability: String, dc: int, token_ids: Array[String]) -> Array:
	var dice_svc: IDiceService = _get_dice_service()
	if dice_svc == null:
		return []
	var results: Array = []
	for tid: String in token_ids:
		var modifier: int = get_save_modifier(tid, ability)
		# Check condition modifiers for this token.
		var mods: Dictionary = check_condition_modifiers(tid, "save", ability)
		var adv: bool = bool(mods.get("advantage", false))
		var disadv: bool = bool(mods.get("disadvantage", false))
		var auto_fail: bool = bool(mods.get("auto_fail", false))
		# Resolve token name.
		var token_name: String = tid
		var td: TokenData = _get_token(tid)
		if td != null and not td.label.is_empty():
			token_name = td.label
		# Auto-fail short-circuit (e.g. paralyzed, stunned auto-fail STR/DEX).
		if auto_fail:
			var af_entry: Dictionary = {
				"token_id": tid,
				"name": token_name,
				"roll": 1,
				"modifier": modifier,
				"total": 1 + modifier,
				"passed": false,
				"nat20": false,
				"nat1": true,
				"advantage": false,
				"disadvantage": false,
				"auto_fail": true,
			}
			results.append(af_entry)
			_log({"type": "saving_throw", "token_id": tid, "token_name": token_name,
				"ability": ability, "dc": dc, "roll": 1, "modifier": modifier,
				"total": 1 + modifier, "passed": false, "auto_fail": true})
			continue
		var save_result: Dictionary = dice_svc.roll_saving_throw(
			modifier, dc, adv, disadv)
		var dice_result: DiceResult = save_result.get("result", null) as DiceResult
		var roll_val: int = 0
		var total_val: int = 0
		var nat20: bool = false
		var nat1: bool = false
		if dice_result != null:
			total_val = dice_result.total
			roll_val = total_val - modifier
			nat20 = dice_result.is_critical
			nat1 = dice_result.is_fumble
		var passed: bool = bool(save_result.get("passed", false))
		var r: Dictionary = {
			"token_id": tid,
			"name": token_name,
			"roll": roll_val,
			"modifier": modifier,
			"total": total_val,
			"passed": passed,
			"nat20": nat20,
			"nat1": nat1,
			"advantage": adv,
			"disadvantage": disadv,
			"auto_fail": false,
		}
		results.append(r)
		_log({"type": "saving_throw", "token_id": tid, "token_name": token_name,
			"ability": ability, "dc": dc, "roll": roll_val, "modifier": modifier,
			"total": total_val, "passed": passed, "auto_fail": false})
	return results


func get_save_modifier(token_id: String, ability: String) -> int:
	var base: StatblockData = _get_base_statblock(token_id)
	if base == null:
		return 0
	# Check if creature is proficient in this save.
	var ability_lower: String = ability.to_lower()
	for entry: Dictionary in base.saving_throws:
		var prof: Variant = entry.get("proficiency", null)
		if prof is Dictionary:
			var idx: String = str((prof as Dictionary).get("index", ""))
			if idx == "saving-throw-%s" % ability_lower:
				return int(entry.get("value", 0))
	# Fallback: raw ability modifier (not proficient).
	return base.get_modifier(ability)


# ---------------------------------------------------------------------------
# AoE management
# ---------------------------------------------------------------------------

func create_aoe(aoe: AoEData) -> void:
	if aoe == null or aoe.id.is_empty():
		return
	_aoes[aoe.id] = aoe
	aoe_created.emit(aoe)


func remove_aoe(aoe_id: String) -> void:
	if _aoes.has(aoe_id):
		_aoes.erase(aoe_id)
		aoe_removed.emit(aoe_id)


func get_aoes() -> Array:
	return _aoes.values()


func get_aoe(aoe_id: String) -> AoEData:
	return _aoes.get(aoe_id, null) as AoEData


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

func serialize_state() -> Dictionary:
	var d: Dictionary = _state.to_dict()
	var aoe_arr: Array = []
	for aoe: AoEData in _aoes.values():
		aoe_arr.append(aoe.to_dict())
	d["aoes"] = aoe_arr
	d["exhaustion_levels"] = _exhaustion_levels.duplicate()
	return d


func deserialize_state(data: Dictionary) -> void:
	_state = CombatState.from_dict(data)
	_aoes.clear()
	var raw_aoes: Variant = data.get("aoes", [])
	if raw_aoes is Array:
		for raw: Variant in raw_aoes as Array:
			if raw is Dictionary:
				var a: AoEData = AoEData.from_dict(raw as Dictionary)
				if not a.id.is_empty():
					_aoes[a.id] = a
	_exhaustion_levels.clear()
	var raw_exh: Variant = data.get("exhaustion_levels", {})
	if raw_exh is Dictionary:
		for k: Variant in (raw_exh as Dictionary).keys():
			_exhaustion_levels[str(k)] = int((raw_exh as Dictionary)[k])
	if _state.is_active:
		combat_started.emit()
		initiative_changed.emit(_state.initiative_order.duplicate(true))
		if not _state.initiative_order.is_empty():
			turn_changed.emit(get_current_turn_token_id(), _state.round_number)
	# Re-emit condition signals so listeners can refresh their displays.
	for tid: String in _state.conditions:
		var arr: Array = _state.conditions[tid] as Array
		for cond: Variant in arr:
			if cond is Dictionary:
				condition_applied.emit(tid, cond as Dictionary)


# ---------------------------------------------------------------------------
# Condition management
# ---------------------------------------------------------------------------

func apply_condition(token_id: String, condition_name: String,
		source: String, duration_rounds: int) -> void:
	if not _state.conditions.has(token_id):
		_state.conditions[token_id] = []
	var conds: Array = _state.conditions[token_id] as Array
	# Remove any existing entry with the same name (re-applying resets duration/source).
	for i: int in range(conds.size() - 1, -1, -1):
		if str(conds[i].get("name", "")) == condition_name:
			conds.remove_at(i)
	var cond: Dictionary = {
		"name": condition_name,
		"source": source,
		"rounds_remaining": duration_rounds,
	}
	conds.append(cond)
	condition_applied.emit(token_id, cond)
	_log({"type": "condition_applied", "token_id": token_id, "token_name": _get_name(token_id),
		"condition_name": condition_name, "source": source})
	_sync_conditions_to_override(token_id)


func remove_condition(token_id: String, condition_name: String) -> void:
	if not _state.conditions.has(token_id):
		return
	var conds: Array = _state.conditions[token_id] as Array
	for i: int in range(conds.size() - 1, -1, -1):
		if str(conds[i].get("name", "")) == condition_name:
			var removed: Dictionary = (conds[i] as Dictionary).duplicate()
			conds.remove_at(i)
			condition_removed.emit(token_id, removed)
			_log({"type": "condition_removed", "token_id": token_id,
				"token_name": _get_name(token_id), "condition_name": condition_name})
	if conds.is_empty():
		_state.conditions.erase(token_id)
	_sync_conditions_to_override(token_id)


func get_conditions(token_id: String) -> Array:
	if not _state.conditions.has(token_id):
		return []
	return (_state.conditions[token_id] as Array).duplicate(true)


func check_condition_modifiers(token_id: String, roll_type: String,
		ability: String) -> Dictionary:
	var conds: Array = get_conditions(token_id)
	var base: Dictionary = ConditionRules.compute_modifiers(conds, roll_type, ability)
	# Layer exhaustion modifiers on top.
	var exh_level: int = get_exhaustion_level(token_id)
	if exh_level > 0:
		var ruleset: String = _get_exhaustion_ruleset()
		var exh: Dictionary = ConditionRules.compute_exhaustion_modifiers(exh_level, ruleset)
		if ruleset == "2024":
			# 2024: d20_penalty is applied externally by callers
			base["d20_penalty"] = int(exh.get("d20_penalty", 0))
		else:
			# 2014: level-based advantage/disadvantage
			if roll_type == "check" and bool(exh.get("check_disadv", false)):
				base["disadvantage"] = true
			if roll_type == "save" and bool(exh.get("save_disadv", false)):
				base["disadvantage"] = true
			if roll_type == "attack_made" and bool(exh.get("attack_disadv", false)):
				base["disadvantage"] = true
	return base


## Set the exhaustion level for a token. Level 0 removes exhaustion.
func set_exhaustion_level(token_id: String, level: int) -> void:
	var ruleset: String = _get_exhaustion_ruleset()
	var max_lv: int = ConditionRules.max_exhaustion_level(ruleset)
	var clamped: int = clampi(level, 0, max_lv)
	if clamped <= 0:
		_exhaustion_levels.erase(token_id)
		# Also remove the exhaustion condition entry.
		remove_condition(token_id, "exhaustion")
		_log({"type": "exhaustion_changed", "token_id": token_id,
			"token_name": _get_name(token_id), "level": 0})
		return
	_exhaustion_levels[token_id] = clamped
	# Ensure exhaustion condition entry exists for UI display.
	apply_condition(token_id, "exhaustion", "Exhaustion %d" % clamped, -1)
	_log({"type": "exhaustion_changed", "token_id": token_id,
		"token_name": _get_name(token_id), "level": clamped})


## Return the current exhaustion level for a token (0 = none).
func get_exhaustion_level(token_id: String) -> int:
	return int(_exhaustion_levels.get(token_id, 0))


## Return the exhaustion ruleset from the active campaign settings.
func _get_exhaustion_ruleset() -> String:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.campaign == null:
		return "2014"
	var c: CampaignData = reg.campaign.get_active_campaign()
	if c == null:
		return "2014"
	return str(c.settings.get("exhaustion_rule", "2014"))


## Sync condition name strings to the token's StatblockOverride for persistence and UI.
func _sync_conditions_to_override(token_id: String) -> void:
	var override: StatblockOverride = _get_override(token_id)
	if override == null:
		return
	var names: Array = []
	if _state.conditions.has(token_id):
		for cond: Variant in (_state.conditions[token_id] as Array):
			if cond is Dictionary:
				var n: String = str((cond as Dictionary).get("name", ""))
				if not n.is_empty():
					names.append(n)
	override.conditions = names
	_commit_override(token_id, override)


## Decrement round-tracked conditions at the start of a token's turn.
func _process_condition_expiry(token_id: String) -> void:
	if token_id.is_empty() or not _state.conditions.has(token_id):
		return
	var conds: Array = _state.conditions[token_id] as Array
	for i: int in range(conds.size() - 1, -1, -1):
		var rd: int = int(conds[i].get("rounds_remaining", -1))
		if rd < 0:
			continue # Indefinite — never expires.
		rd -= 1
		if rd <= 0:
			var expired: Dictionary = (conds[i] as Dictionary).duplicate()
			conds.remove_at(i)
			condition_removed.emit(token_id, expired)
		else:
			conds[i]["rounds_remaining"] = rd
	if conds.is_empty():
		_state.conditions.erase(token_id)
	_sync_conditions_to_override(token_id)


# ---------------------------------------------------------------------------
# Grapple / Shove
# ---------------------------------------------------------------------------

## Attempt to grapple a target.
## 2014: contested check — attacker Athletics vs target Athletics or Acrobatics (target's choice).
## 2024: target makes STR or DEX saving throw vs attacker's unarmed strike DC
##        (8 + proficiency + STR modifier).
## Returns {success: bool, attacker_roll: int, target_roll: int, detail: String}
func attempt_grapple(attacker_id: String, target_id: String) -> Dictionary:
	var ruleset: String = _get_grapple_ruleset()
	var dice_svc: IDiceService = _get_dice_service()
	if dice_svc == null:
		return {"success": false, "attacker_roll": 0, "target_roll": 0, "detail": "no dice service"}
	var atk_base: StatblockData = _get_base_statblock(attacker_id)
	var tgt_base: StatblockData = _get_base_statblock(target_id)
	if atk_base == null or tgt_base == null:
		return {"success": false, "attacker_roll": 0, "target_roll": 0, "detail": "missing statblock"}
	var result: Dictionary = {}
	if ruleset == "2024":
		result = _grapple_shove_2024(attacker_id, target_id, atk_base, tgt_base, dice_svc, "grapple")
	else:
		result = _grapple_shove_2014(attacker_id, target_id, atk_base, tgt_base, dice_svc, "grapple")
	if bool(result.get("success", false)):
		apply_condition(target_id, "grappled", _get_name(attacker_id), -1)
	_log({"type": "grapple_attempt", "attacker_id": attacker_id,
		"attacker_name": _get_name(attacker_id), "target_id": target_id,
		"target_name": _get_name(target_id), "success": bool(result.get("success", false)),
		"detail": str(result.get("detail", ""))})
	return result


## Attempt to shove a target (push 5 ft or knock prone).
## Same contest/save logic as grapple but on success applies push or prone.
func attempt_shove(attacker_id: String, target_id: String,
		knock_prone: bool) -> Dictionary:
	var ruleset: String = _get_grapple_ruleset()
	var dice_svc: IDiceService = _get_dice_service()
	if dice_svc == null:
		return {"success": false, "attacker_roll": 0, "target_roll": 0, "detail": "no dice service"}
	var atk_base: StatblockData = _get_base_statblock(attacker_id)
	var tgt_base: StatblockData = _get_base_statblock(target_id)
	if atk_base == null or tgt_base == null:
		return {"success": false, "attacker_roll": 0, "target_roll": 0, "detail": "missing statblock"}
	var result: Dictionary = {}
	if ruleset == "2024":
		result = _grapple_shove_2024(attacker_id, target_id, atk_base, tgt_base, dice_svc, "shove")
	else:
		result = _grapple_shove_2014(attacker_id, target_id, atk_base, tgt_base, dice_svc, "shove")
	if bool(result.get("success", false)) and knock_prone:
		apply_condition(target_id, "prone", _get_name(attacker_id), -1)
	_log({"type": "shove_attempt", "attacker_id": attacker_id,
		"attacker_name": _get_name(attacker_id), "target_id": target_id,
		"target_name": _get_name(target_id), "success": bool(result.get("success", false)),
		"knock_prone": knock_prone, "detail": str(result.get("detail", ""))})
	return result


## 2014 contested check: attacker Athletics vs target Athletics or Acrobatics (higher).
func _grapple_shove_2014(attacker_id: String, target_id: String,
		atk_base: StatblockData, tgt_base: StatblockData,
		dice_svc: IDiceService, _action: String) -> Dictionary:
	var atk_mod: int = atk_base.get_modifier("str")
	var tgt_str_mod: int = tgt_base.get_modifier("str")
	var tgt_dex_mod: int = tgt_base.get_modifier("dex")
	var tgt_mod: int = maxi(tgt_str_mod, tgt_dex_mod)
	# Check condition modifiers on attacker.
	var atk_mods: Dictionary = check_condition_modifiers(attacker_id, "check", "str")
	var atk_adv: bool = bool(atk_mods.get("advantage", false))
	var atk_disadv: bool = bool(atk_mods.get("disadvantage", false))
	var atk_result: DiceResult = dice_svc.roll_ability_check(atk_mod, atk_adv, atk_disadv)
	# Target uses best of STR or DEX for their check.
	var tgt_ability: String = "str" if tgt_str_mod >= tgt_dex_mod else "dex"
	var tgt_mods: Dictionary = check_condition_modifiers(target_id, "check", tgt_ability)
	var tgt_adv: bool = bool(tgt_mods.get("advantage", false))
	var tgt_disadv: bool = bool(tgt_mods.get("disadvantage", false))
	var tgt_result: DiceResult = dice_svc.roll_ability_check(tgt_mod, tgt_adv, tgt_disadv)
	var success: bool = atk_result.total >= tgt_result.total
	var detail: String = "Attacker %d vs Target %d (contested check)" % [atk_result.total, tgt_result.total]
	return {"success": success, "attacker_roll": atk_result.total,
		"target_roll": tgt_result.total, "detail": detail}


## 2024 save-based: target makes STR or DEX save vs attacker DC (8 + proficiency + STR mod).
func _grapple_shove_2024(_attacker_id: String, target_id: String,
		atk_base: StatblockData, _tgt_base: StatblockData,
		dice_svc: IDiceService, _action: String) -> Dictionary:
	var dc: int = 8 + atk_base.proficiency_bonus + atk_base.get_modifier("str")
	# Target chooses STR or DEX save (use whichever modifier is higher).
	var tgt_str_save: int = get_save_modifier(target_id, "str")
	var tgt_dex_save: int = get_save_modifier(target_id, "dex")
	var tgt_ability: String = "str" if tgt_str_save >= tgt_dex_save else "dex"
	var tgt_mod: int = maxi(tgt_str_save, tgt_dex_save)
	var tgt_mods: Dictionary = check_condition_modifiers(target_id, "save", tgt_ability)
	var tgt_adv: bool = bool(tgt_mods.get("advantage", false))
	var tgt_disadv: bool = bool(tgt_mods.get("disadvantage", false))
	var save_result: Dictionary = dice_svc.roll_saving_throw(tgt_mod, dc, tgt_adv, tgt_disadv)
	var passed: bool = bool(save_result.get("passed", false))
	var dice_r: DiceResult = save_result.get("result", null) as DiceResult
	var roll_total: int = dice_r.total if dice_r != null else 0
	var success: bool = not passed
	var detail: String = "Target save %d vs DC %d (%s)" % [roll_total, dc, "saved" if passed else "failed"]
	return {"success": success, "attacker_roll": dc,
		"target_roll": roll_total, "detail": detail}


## Get the grapple/shove ruleset from the active campaign.
func _get_grapple_ruleset() -> String:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.campaign == null:
		return "2014"
	var c: CampaignData = reg.campaign.get_active_campaign()
	if c == null:
		return "2014"
	return c.default_ruleset


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _get_registry() -> ServiceRegistry:
	return get_node_or_null("/root/ServiceRegistry") as ServiceRegistry


func _get_token(token_id: String) -> TokenData:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.token == null:
		return null
	return reg.token.get_token_by_id(token_id)


func _get_base_statblock(token_id: String) -> StatblockData:
	var td: TokenData = _get_token(token_id)
	if td != null and not td.statblock_refs.is_empty():
		var reg: ServiceRegistry = _get_registry()
		if reg != null and reg.statblock != null:
			var sb_id: String = str(td.statblock_refs[0])
			return reg.statblock.get_statblock(sb_id)
	# Fall back to player profile → character statblock.
	return _resolve_player_statblock(token_id)


func _get_override(token_id: String) -> StatblockOverride:
	var td: TokenData = _get_token(token_id)
	if td != null and not td.statblock_refs.is_empty():
		var sb_id: String = str(td.statblock_refs[0])
		var raw: Variant = td.statblock_overrides.get(sb_id, null)
		if raw is Dictionary:
			return StatblockOverride.from_dict(raw as Dictionary)
		if raw is StatblockOverride:
			return raw as StatblockOverride
		return null
	# Fall back to player override stored in combat service.
	var player_raw: Variant = _player_overrides.get(token_id, null)
	if player_raw is Dictionary:
		return StatblockOverride.from_dict(player_raw as Dictionary)
	return null


func _commit_override(token_id: String, override: StatblockOverride) -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg != null and reg.token != null:
		var td: TokenData = reg.token.get_token_by_id(token_id)
		if td != null and not td.statblock_refs.is_empty():
			var sb_id: String = str(td.statblock_refs[0])
			td.statblock_overrides[sb_id] = override.to_dict()
			reg.token.update_token(td)
			return
	# Fall back to player override stored in combat service.
	_player_overrides[token_id] = override.to_dict()


func _resolve_player_statblock(token_id: String) -> StatblockData:
	## Look up the character statblock linked to a player profile.
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.profile == null or reg.character == null:
		return null
	var prof: Variant = reg.profile.get_profile_by_id(token_id)
	if not prof is PlayerProfile:
		return null
	var sb_id: String = (prof as PlayerProfile).statblock_id
	if sb_id.is_empty():
		return null
	return reg.character.get_character_by_id(sb_id)


func _ensure_player_override(token_id: String) -> void:
	## If token_id is a player with a linked statblock and no existing override,
	## create a StatblockOverride seeded with the character's hit_points.
	if _get_token(token_id) != null:
		return # DM-placed token — handled via TokenData.statblock_overrides.
	if _player_overrides.has(token_id):
		return # Already initialised.
	var sb: StatblockData = _resolve_player_statblock(token_id)
	if sb == null:
		return
	var so := StatblockOverride.new()
	so.base_statblock_id = sb.id
	so.current_hp = sb.hit_points
	so.max_hp = sb.hit_points
	_player_overrides[token_id] = so.to_dict()


func _get_dex_mod(token_id: String) -> int:
	var base: StatblockData = _get_base_statblock(token_id)
	if base == null:
		return 0
	return base.get_modifier("dex")


func _get_initiative_bonus(token_id: String) -> int:
	var base: StatblockData = _get_base_statblock(token_id)
	if base == null:
		return 0
	return base.initiative_bonus


func _get_dice_service() -> IDiceService:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.dice == null:
		return null
	return reg.dice.service


func _find_combatant_index(token_id: String) -> int:
	for i: int in range(_state.initiative_order.size()):
		if str(_state.initiative_order[i].get("token_id", "")) == token_id:
			return i
	return -1


func _sort_initiative() -> void:
	## Sort descending by initiative, tie-break by DEX modifier (higher first).
	_state.initiative_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_init: int = int(a.get("initiative", 0))
		var b_init: int = int(b.get("initiative", 0))
		if a_init != b_init:
			return a_init > b_init
		var a_dex: int = int(a.get("dex_mod", 0))
		var b_dex: int = int(b.get("dex_mod", 0))
		return a_dex > b_dex
	)
	# After sorting, reset current_turn_index to top.


func _has_damage_type(type_list: Array, damage_type: String) -> bool:
	var dt_lower: String = damage_type.to_lower()
	for raw: Variant in type_list:
		if str(raw).to_lower() == dt_lower:
			return true
	return false


# ---------------------------------------------------------------------------
# Combat Log
# ---------------------------------------------------------------------------

func get_combat_log() -> Array:
	return _combat_log.duplicate(true)


func clear_combat_log() -> void:
	_combat_log.clear()


func add_log_entry(entry: Dictionary) -> void:
	_log(entry)


func _log(entry: Dictionary) -> void:
	entry["round"] = _state.round_number
	_combat_log.append(entry)
	log_entry_added.emit(entry)


func _get_name(token_id: String) -> String:
	var td: TokenData = _get_token(token_id)
	if td != null and not td.label.is_empty():
		return td.label
	var base: StatblockData = _get_base_statblock(token_id)
	if base != null and not base.name.is_empty():
		return base.name
	# Fall back to player profile name for PC tokens.
	var reg: ServiceRegistry = _get_registry()
	if reg != null and reg.profile != null:
		var prof: Variant = reg.profile.get_profile_by_id(token_id)
		if prof is PlayerProfile and not (prof as PlayerProfile).player_name.is_empty():
			return (prof as PlayerProfile).player_name
	return token_id


## Ensures every active combatant has a unique display name by permanently
## writing numbered labels back into TokenData for any group of combatants
## Assigns unique numbered labels to any combatants that share the same base
## display name. Numbers already in use are never re-assigned — only unlabelled
## (or un-numbered) tokens receive a new number.  The high-water mark per base
## name persists for the life of the combat so that killed/removed tokens keep
## their slot and new additions always get a fresh higher number.
func _ensure_unique_combatant_names() -> void:
	var reg: ServiceRegistry = _get_registry()
	if reg == null or reg.token == null:
		return
	var tm: TokenManager = reg.token
	# Build groups keyed by base name (strip trailing " N" suffix).
	var base_to_ids: Dictionary = {}
	for entry: Dictionary in _state.initiative_order:
		var tid: String = str(entry.get("token_id", ""))
		if tid.is_empty():
			continue
		var nm: String = _get_name(tid)
		var base: String = nm
		var si: int = nm.rfind(" ")
		if si != -1 and nm.substr(si + 1).is_valid_int():
			base = nm.left(si)
		if not base_to_ids.has(base):
			base_to_ids[base] = []
		(base_to_ids[base] as Array).append(tid)
	# Only process groups where 2+ tokens share the same base name.
	for base: String in base_to_ids.keys():
		var ids: Array = base_to_ids[base] as Array
		if ids.size() < 2:
			continue
		# First pass: update the high-water mark from already-numbered members
		# so we never accidentally reuse a number that was assigned in a prior run.
		for tid: String in ids:
			var nm: String = _get_name(tid)
			var si: int = nm.rfind(" ")
			if si != -1 and nm.substr(si + 1).is_valid_int():
				var seen: int = int(nm.substr(si + 1))
				if seen > int(_used_label_max.get(base, 0)):
					_used_label_max[base] = seen
		# Second pass: assign the next number only to tokens that don't have one.
		for tid: String in ids:
			var nm: String = _get_name(tid)
			var si: int = nm.rfind(" ")
			if si != -1 and nm.substr(si + 1).is_valid_int():
				continue # Already numbered — leave it alone.
			var next_n: int = int(_used_label_max.get(base, 0)) + 1
			_used_label_max[base] = next_n
			var td: TokenData = tm.get_token_by_id(tid)
			if td == null:
				continue
			td.label = "%s %d" % [base, next_n]
			tm.update_token(td)
