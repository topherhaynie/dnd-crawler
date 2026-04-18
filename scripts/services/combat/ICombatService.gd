extends Node
class_name ICombatService

## Protocol: ICombatService
##
## Manages combat encounters: initiative tracking, turn management,
## HP/damage pipeline, and death saves.

@warning_ignore("unused_signal")
signal combat_started
@warning_ignore("unused_signal")
signal combat_ended
@warning_ignore("unused_signal")
signal turn_changed(token_id: String, round_number: int)
@warning_ignore("unused_signal")
signal initiative_changed(order: Array)
@warning_ignore("unused_signal")
signal hp_changed(token_id: String, current_hp: int, max_hp: int, delta: int)
@warning_ignore("unused_signal")
signal token_killed(token_id: String)
@warning_ignore("unused_signal")
signal token_stabilized(token_id: String)
@warning_ignore("unused_signal")
signal combatant_added(token_id: String)
@warning_ignore("unused_signal")
signal combatant_removed(token_id: String)
@warning_ignore("unused_signal")
signal aoe_created(aoe: AoEData)
@warning_ignore("unused_signal")
signal aoe_removed(aoe_id: String)
@warning_ignore("unused_signal")
signal condition_applied(token_id: String, condition: Dictionary)
@warning_ignore("unused_signal")
signal condition_removed(token_id: String, condition: Dictionary)


## Start a combat encounter with the given token IDs.
func start_combat(_token_ids: Array[String]) -> void:
	push_error("ICombatService.start_combat: not implemented")


## End the current combat encounter.
func end_combat() -> void:
	push_error("ICombatService.end_combat: not implemented")


## Reset the number-suffix high-water marks so the next disambiguation pass
## renumbers all duplicate-name combatants from 1 again.
func reset_combat_labels() -> void:
	push_error("ICombatService.reset_combat_labels: not implemented")


## Return true when a combat encounter is active.
func is_in_combat() -> bool:
	push_error("ICombatService.is_in_combat: not implemented")
	return false


## Add a combatant to an active encounter.
func add_combatant(_token_id: String) -> void:
	push_error("ICombatService.add_combatant: not implemented")


## Remove a combatant from the active encounter.
func remove_combatant(_token_id: String) -> void:
	push_error("ICombatService.remove_combatant: not implemented")


## Auto-roll initiative for all combatants using DEX modifier.
func roll_initiative_all() -> void:
	push_error("ICombatService.roll_initiative_all: not implemented")


## Set a manual initiative value for one combatant.
func set_initiative(_token_id: String, _value: int) -> void:
	push_error("ICombatService.set_initiative: not implemented")


## Return the sorted initiative order as Array of Dictionaries.
## Each entry: {token_id: String, initiative: int, dex_mod: int}
func get_initiative_order() -> Array:
	push_error("ICombatService.get_initiative_order: not implemented")
	return []


## Advance to the next combatant's turn.
func next_turn() -> void:
	push_error("ICombatService.next_turn: not implemented")


## Return to the previous combatant's turn.
func previous_turn() -> void:
	push_error("ICombatService.previous_turn: not implemented")


## Delay the given combatant's turn (moves to end of current round).
func delay_turn(_token_id: String) -> void:
	push_error("ICombatService.delay_turn: not implemented")


## Ready an action for the given combatant.
func ready_action(_token_id: String) -> void:
	push_error("ICombatService.ready_action: not implemented")


## Return the token ID of the combatant whose turn it is.
func get_current_turn_token_id() -> String:
	push_error("ICombatService.get_current_turn_token_id: not implemented")
	return ""


## Return the current round number (1-based).
func get_round_number() -> int:
	push_error("ICombatService.get_round_number: not implemented")
	return 0


## Apply damage to a token. Respects resistances/immunities/vulnerabilities.
## Returns {actual_damage: int, new_hp: int, killed: bool, detail: String}.
func apply_damage(_token_id: String, _amount: int, _damage_type: String) -> Dictionary:
	push_error("ICombatService.apply_damage: not implemented")
	return {}


## Apply healing to a token.
## Returns {actual_healing: int, new_hp: int}.
func apply_healing(_token_id: String, _amount: int) -> Dictionary:
	push_error("ICombatService.apply_healing: not implemented")
	return {}


## Apply temporary hit points to a token (non-stacking, takes higher).
func apply_temp_hp(_token_id: String, _amount: int) -> void:
	push_error("ICombatService.apply_temp_hp: not implemented")


## Roll a death saving throw for a PC at 0 HP.
## Returns {roll: int, success: bool, stabilized: bool, dead: bool}.
func roll_death_save(_token_id: String) -> Dictionary:
	push_error("ICombatService.roll_death_save: not implemented")
	return {}


## Return HP status for a token.
## Returns {current: int, max: int, temp: int, bloodied: bool, dead: bool}.
func get_hp_status(_token_id: String) -> Dictionary:
	push_error("ICombatService.get_hp_status: not implemented")
	return {}


## Batch saving throws for a group of tokens.
## Returns Array of per-token results:
## {token_id, name, roll: int, modifier: int, total: int, passed: bool,
##  nat20: bool, nat1: bool, advantage: bool, disadvantage: bool}
func call_for_save(_ability: String, _dc: int, _token_ids: Array[String]) -> Array:
	push_error("ICombatService.call_for_save: not implemented")
	return []


## Return the saving throw modifier for a token and ability.
func get_save_modifier(_token_id: String, _ability: String) -> int:
	push_error("ICombatService.get_save_modifier: not implemented")
	return 0


## Register an AoE template. Emits aoe_created.
func create_aoe(_aoe: AoEData) -> void:
	push_error("ICombatService.create_aoe: not implemented")


## Remove an AoE template. Emits aoe_removed.
func remove_aoe(_aoe_id: String) -> void:
	push_error("ICombatService.remove_aoe: not implemented")


## Return true if the given token is currently in the initiative order.
func is_combatant(_token_id: String) -> bool:
	push_error("ICombatService.is_combatant: not implemented")
	return false


## Return all active AoE templates.
func get_aoes() -> Array:
	push_error("ICombatService.get_aoes: not implemented")
	return []


## Return the AoE with the given id, or null.
func get_aoe(_aoe_id: String) -> AoEData:
	push_error("ICombatService.get_aoe: not implemented")
	return null


## Serialize combat state for persistence.
func serialize_state() -> Dictionary:
	push_error("ICombatService.serialize_state: not implemented")
	return {}


## Restore combat state from serialized data.
func deserialize_state(_data: Dictionary) -> void:
	push_error("ICombatService.deserialize_state: not implemented")


## Apply a condition to a token.
## condition_name: key from ConditionRules (e.g. "blinded")
## source: free-text description of who applied it
## duration_rounds: rounds remaining; -1 = indefinite
func apply_condition(_token_id: String, _condition_name: String,
		_source: String, _duration_rounds: int) -> void:
	push_error("ICombatService.apply_condition: not implemented")


## Remove a condition from a token by condition name.
func remove_condition(_token_id: String, _condition_name: String) -> void:
	push_error("ICombatService.remove_condition: not implemented")


## Return all active conditions for a token.
## Each entry: {name: String, source: String, rounds_remaining: int}
func get_conditions(_token_id: String) -> Array:
	push_error("ICombatService.get_conditions: not implemented")
	return []


## Check condition modifiers for a token for a given roll.
## roll_type: "attack_made" | "attack_rcvd" | "save" | "check"
## ability: save/check ability key (e.g. "str", "dex") — ignored for attack rolls
## Returns {advantage: bool, disadvantage: bool, auto_fail: bool}
func check_condition_modifiers(_token_id: String, _roll_type: String,
		_ability: String) -> Dictionary:
	push_error("ICombatService.check_condition_modifiers: not implemented")
	return {"advantage": false, "disadvantage": false, "auto_fail": false}


# ---------------------------------------------------------------------------
# Combat Log
# ---------------------------------------------------------------------------

@warning_ignore("unused_signal")
signal log_entry_added(entry: Dictionary)


## Return all log entries for the current (or most recent) encounter.
func get_combat_log() -> Array:
	push_error("ICombatService.get_combat_log: not implemented")
	return []


## Clear all log entries.
func clear_combat_log() -> void:
	push_error("ICombatService.clear_combat_log: not implemented")


## Append a custom DM note to the log.
## entry must include at minimum {"type": "custom", "text": String}
func add_log_entry(_entry: Dictionary) -> void:
	push_error("ICombatService.add_log_entry: not implemented")
