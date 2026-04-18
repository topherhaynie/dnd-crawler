extends Node
class_name IDiceService

# ---------------------------------------------------------------------------
# IDiceService — protocol for the dice rolling subsystem.
#
# Provides both fast (instant numeric) and animated roll modes, plus
# convenience helpers for ability checks, saving throws, attacks, and damage.
# ---------------------------------------------------------------------------

@warning_ignore("unused_signal")
signal roll_completed(result: DiceResult)
@warning_ignore("unused_signal")
signal roll_started(expression: String, context: Dictionary)


func roll(_expression: String, _context: Dictionary = {}) -> DiceResult:
	push_error("IDiceService.roll: not implemented")
	return DiceResult.new()


func roll_animated(_expression: String, _context: Dictionary = {}) -> void:
	push_error("IDiceService.roll_animated: not implemented")


func roll_fast(_expression: String, _context: Dictionary = {}) -> DiceResult:
	push_error("IDiceService.roll_fast: not implemented")
	return DiceResult.new()


func roll_with_advantage(_expression: String, _context: Dictionary = {}) -> DiceResult:
	push_error("IDiceService.roll_with_advantage: not implemented")
	return DiceResult.new()


func roll_with_disadvantage(_expression: String, _context: Dictionary = {}) -> DiceResult:
	push_error("IDiceService.roll_with_disadvantage: not implemented")
	return DiceResult.new()


func set_roll_mode(_animated: bool) -> void:
	push_error("IDiceService.set_roll_mode: not implemented")


func get_roll_mode() -> bool:
	push_error("IDiceService.get_roll_mode: not implemented")
	return false


func roll_ability_check(_modifier: int, _advantage: bool, _disadvantage: bool) -> DiceResult:
	push_error("IDiceService.roll_ability_check: not implemented")
	return DiceResult.new()


func roll_saving_throw(_modifier: int, _dc: int, _advantage: bool, _disadvantage: bool) -> Dictionary:
	push_error("IDiceService.roll_saving_throw: not implemented")
	return {}


func roll_attack(_attack_bonus: int, _target_ac: int, _advantage: bool, _disadvantage: bool) -> Dictionary:
	push_error("IDiceService.roll_attack: not implemented")
	return {}


func roll_damage(_expression: String, _critical: bool, _crit_rule: String) -> DiceResult:
	push_error("IDiceService.roll_damage: not implemented")
	return DiceResult.new()


func get_roll_history() -> Array:
	push_error("IDiceService.get_roll_history: not implemented")
	return []


func clear_roll_history() -> void:
	push_error("IDiceService.clear_roll_history: not implemented")


func set_renderer(_renderer: DiceRenderer3D) -> void:
	push_error("IDiceService.set_renderer: not implemented")
