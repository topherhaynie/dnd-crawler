extends IDiceService
class_name DiceService

# ---------------------------------------------------------------------------
# DiceService — concrete dice rolling implementation.
#
# Provides instant ("fast") rolls via DiceExpression, advantage/disadvantage,
# and D&D 5e helpers (ability checks, saving throws, attacks, damage).
# When a DiceRenderer3D is attached and animated mode is on, roll_animated()
# delegates to the 3D physics renderer.  Otherwise falls back to fast roll.
# ---------------------------------------------------------------------------

const MAX_HISTORY: int = 50

var _animated_mode: bool = false
var _roll_history: Array = []
var _renderer: DiceRenderer3D = null
var _pending_expression: String = ""
var _pending_context: Dictionary = {}


func set_renderer(renderer: DiceRenderer3D) -> void:
	if _renderer != null and _renderer.roll_finished.is_connected(_on_renderer_finished):
		_renderer.roll_finished.disconnect(_on_renderer_finished)
	_renderer = renderer
	if _renderer != null:
		_renderer.roll_finished.connect(_on_renderer_finished)


func roll(expression: String, context: Dictionary = {}) -> DiceResult:
	if _animated_mode and _renderer != null:
		roll_animated(expression, context)
		# In animated mode we return an empty result; the real one comes via signal.
		return DiceResult.new()
	return roll_fast(expression, context)


func roll_animated(expression: String, context: Dictionary = {}) -> void:
	roll_started.emit(expression, context)
	if _renderer != null:
		_pending_expression = expression
		_pending_context = context
		var parsed: DiceExpression = DiceExpression.parse(expression)
		var groups: Array = _expression_to_groups(parsed)
		_renderer.start_roll(groups)
	else:
		# Fallback: fast roll
		var result: DiceResult = _evaluate(expression)
		_record(result, context)
		roll_completed.emit(result)


func roll_fast(expression: String, context: Dictionary = {}) -> DiceResult:
	var result: DiceResult = _evaluate(expression)
	_record(result, context)
	roll_started.emit(expression, context)
	roll_completed.emit(result)
	return result


func roll_with_advantage(expression: String, context: Dictionary = {}) -> DiceResult:
	var r1: DiceResult = _evaluate(expression)
	var r2: DiceResult = _evaluate(expression)
	var best: DiceResult = r1 if r1.total >= r2.total else r2
	best.individual_rolls = r1.individual_rolls + r2.individual_rolls
	_record(best, context)
	roll_started.emit(expression, context)
	roll_completed.emit(best)
	return best


func roll_with_disadvantage(expression: String, context: Dictionary = {}) -> DiceResult:
	var r1: DiceResult = _evaluate(expression)
	var r2: DiceResult = _evaluate(expression)
	var worst: DiceResult = r1 if r1.total <= r2.total else r2
	worst.individual_rolls = r1.individual_rolls + r2.individual_rolls
	_record(worst, context)
	roll_started.emit(expression, context)
	roll_completed.emit(worst)
	return worst


func set_roll_mode(animated: bool) -> void:
	_animated_mode = animated


func get_roll_mode() -> bool:
	return _animated_mode


func roll_ability_check(modifier: int, advantage: bool, disadvantage: bool) -> DiceResult:
	var expr_str: String = "1d20%+d" % modifier if modifier != 0 else "1d20"
	if modifier > 0:
		expr_str = "1d20+%d" % modifier
	elif modifier < 0:
		expr_str = "1d20%d" % modifier
	else:
		expr_str = "1d20"
	if advantage and not disadvantage:
		return roll_with_advantage(expr_str)
	elif disadvantage and not advantage:
		return roll_with_disadvantage(expr_str)
	return roll_fast(expr_str)


func roll_saving_throw(modifier: int, dc: int, advantage: bool, disadvantage: bool) -> Dictionary:
	var result: DiceResult = roll_ability_check(modifier, advantage, disadvantage)
	var passed: bool = result.total >= dc
	return {"result": result, "passed": passed}


func roll_attack(attack_bonus: int, target_ac: int, advantage: bool, disadvantage: bool) -> Dictionary:
	var result: DiceResult = roll_ability_check(attack_bonus, advantage, disadvantage)
	var critical: bool = result.is_critical
	var hit: bool = critical or (not result.is_fumble and result.total >= target_ac)
	return {"result": result, "hit": hit, "critical": critical}


func roll_damage(expression: String, critical: bool, crit_rule: String) -> DiceResult:
	if not critical:
		return roll_fast(expression)
	# Apply critical hit rule
	match crit_rule:
		"max_plus_roll":
			# Max the base dice, then roll normally and add
			var base: DiceExpression = DiceExpression.parse(expression)
			var max_val: int = base.get_max()
			var roll_result: DiceResult = _evaluate(expression)
			roll_result.total = max_val + roll_result.total - roll_result.modifiers
			roll_result.modifiers = roll_result.modifiers
			_record(roll_result, {"critical": true, "crit_rule": crit_rule})
			roll_completed.emit(roll_result)
			return roll_result
		_:
			# "double_dice" (default) — roll the dice expression twice
			var r1: DiceResult = _evaluate(expression)
			var r2: DiceResult = _evaluate(expression)
			var combined := DiceResult.new()
			combined.expression = expression + " (crit)"
			combined.individual_rolls = r1.individual_rolls + r2.individual_rolls
			combined.modifiers = r1.modifiers
			combined.total = r1.total + r2.total - r1.modifiers
			combined.is_critical = true
			_record(combined, {"critical": true, "crit_rule": crit_rule})
			roll_completed.emit(combined)
			return combined


func get_roll_history() -> Array:
	return _roll_history.duplicate()


func clear_roll_history() -> void:
	_roll_history.clear()


# --- Internal helpers ---

func _evaluate(expression: String) -> DiceResult:
	var parsed: DiceExpression = DiceExpression.parse(expression)
	return parsed.roll()


func _record(result: DiceResult, context: Dictionary) -> void:
	_roll_history.push_front({
		"result": result.to_dict(),
		"context": context,
		"timestamp": Time.get_unix_time_from_system(),
	})
	if _roll_history.size() > MAX_HISTORY:
		_roll_history.resize(MAX_HISTORY)


## Convert a DiceExpression's internal groups into the format DiceRenderer3D expects.
## Re-parses the pending expression string to extract count and sides per group.
func _expression_to_groups(_parsed: DiceExpression) -> Array:
	var groups: Array = []
	var normalised: String = _pending_expression.to_lower().replace("-", "+-")
	var tokens: PackedStringArray = normalised.split("+", false)
	for token: String in tokens:
		token = token.strip_edges()
		if token.is_empty():
			continue
		var d_pos: int = token.find("d")
		if d_pos == -1:
			continue # modifier, not dice
		var count_str: String = token.substr(0, d_pos)
		var count: int = int(count_str) if not count_str.is_empty() else 1
		var remainder: String = token.substr(d_pos + 1)
		# Strip keep notation for the renderer (it rolls all, we pick afterwards)
		var kh_pos: int = remainder.find("kh")
		var kl_pos: int = remainder.find("kl")
		if kh_pos != -1:
			remainder = remainder.substr(0, kh_pos)
		elif kl_pos != -1:
			remainder = remainder.substr(0, kl_pos)
		var sides: int = int(remainder)
		if sides > 0 and count > 0:
			groups.append({"count": count, "sides": sides})
	return groups


## Called when the 3D renderer finishes rolling.
func _on_renderer_finished(results: Array) -> void:
	# Build a DiceResult from the 3D physics results
	var result := DiceResult.new()
	result.expression = _pending_expression

	# Re-parse expression to get modifier and keep info
	var parsed: DiceExpression = DiceExpression.parse(_pending_expression)
	var fast_result: DiceResult = parsed.roll()
	result.modifiers = fast_result.modifiers

	var total: int = result.modifiers
	for group_data: Dictionary in results:
		var values: Array = group_data.get("values", []) as Array
		var int_values: Array[int] = []
		for v: Variant in values:
			int_values.append(int(v))
		result.individual_rolls.append(int_values)
		for val: int in int_values:
			total += val

	result.total = total

	# Check for critical/fumble on first d20
	if results.size() > 0:
		var first_group: Dictionary = results[0] as Dictionary
		if int(first_group.get("sides", 0)) == 20:
			var vals: Array = first_group.get("values", []) as Array
			if vals.size() > 0:
				var first_val: int = int(vals[0])
				result.is_critical = first_val == 20
				result.is_fumble = first_val == 1

	_record(result, _pending_context)
	roll_completed.emit(result)
	_pending_expression = ""
	_pending_context = {}
