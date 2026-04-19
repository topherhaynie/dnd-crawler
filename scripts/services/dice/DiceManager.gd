extends RefCounted
class_name DiceManager

# ---------------------------------------------------------------------------
# DiceManager — typed coordinator for the dice rolling domain.
#
# Owned by ServiceRegistry.dice.  All callers access dice operations through
# manager methods — never via `registry.dice.service` directly.
# ---------------------------------------------------------------------------

var service: IDiceService = null


func roll(expression: String, context: Dictionary = {}) -> DiceResult:
	if service == null:
		return DiceResult.new()
	return service.roll(expression, context)


func roll_animated(expression: String, context: Dictionary = {}) -> void:
	if service == null:
		return
	service.roll_animated(expression, context)


func roll_fast(expression: String, context: Dictionary = {}) -> DiceResult:
	if service == null:
		return DiceResult.new()
	return service.roll_fast(expression, context)


func roll_with_advantage(expression: String, context: Dictionary = {}) -> DiceResult:
	if service == null:
		return DiceResult.new()
	return service.roll_with_advantage(expression, context)


func roll_with_disadvantage(expression: String, context: Dictionary = {}) -> DiceResult:
	if service == null:
		return DiceResult.new()
	return service.roll_with_disadvantage(expression, context)


func set_roll_mode(animated: bool) -> void:
	if service == null:
		return
	service.set_roll_mode(animated)


func get_roll_mode() -> bool:
	if service == null:
		return false
	return service.get_roll_mode()


func roll_ability_check(modifier: int, advantage: bool, disadvantage: bool) -> DiceResult:
	if service == null:
		return DiceResult.new()
	return service.roll_ability_check(modifier, advantage, disadvantage)


func roll_saving_throw(modifier: int, dc: int, advantage: bool, disadvantage: bool) -> Dictionary:
	if service == null:
		return {}
	return service.roll_saving_throw(modifier, dc, advantage, disadvantage)


func roll_attack(attack_bonus: int, target_ac: int, advantage: bool, disadvantage: bool) -> Dictionary:
	if service == null:
		return {}
	return service.roll_attack(attack_bonus, target_ac, advantage, disadvantage)


func roll_damage(expression: String, critical: bool, crit_rule: String,
		is_weapon_attack: bool = true) -> DiceResult:
	if service == null:
		return DiceResult.new()
	return service.roll_damage(expression, critical, crit_rule, is_weapon_attack)


func get_roll_history() -> Array:
	if service == null:
		return []
	return service.get_roll_history()


func clear_roll_history() -> void:
	if service == null:
		return
	service.clear_roll_history()


func set_renderer(renderer: DiceRenderer3D) -> void:
	if service == null:
		return
	service.set_renderer(renderer)
