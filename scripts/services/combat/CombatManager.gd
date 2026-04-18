extends RefCounted
class_name CombatManager

## Combat domain coordinator.
##
## Access via: get_node("/root/ServiceRegistry").combat

var service: ICombatService = null


func start_combat(token_ids: Array[String]) -> void:
	if service != null:
		service.start_combat(token_ids)


func end_combat() -> void:
	if service != null:
		service.end_combat()


func reset_combat_labels() -> void:
	if service != null:
		service.reset_combat_labels()


func is_in_combat() -> bool:
	if service == null:
		return false
	return service.is_in_combat()


func add_combatant(token_id: String) -> void:
	if service != null:
		service.add_combatant(token_id)


func remove_combatant(token_id: String) -> void:
	if service != null:
		service.remove_combatant(token_id)


func roll_initiative_all() -> void:
	if service != null:
		service.roll_initiative_all()


func set_initiative(token_id: String, value: int) -> void:
	if service != null:
		service.set_initiative(token_id, value)


func get_initiative_order() -> Array:
	if service == null:
		return []
	return service.get_initiative_order()


func is_combatant(token_id: String) -> bool:
	if service == null:
		return false
	return service.is_combatant(token_id)


func next_turn() -> void:
	if service != null:
		service.next_turn()


func previous_turn() -> void:
	if service != null:
		service.previous_turn()


func delay_turn(token_id: String) -> void:
	if service != null:
		service.delay_turn(token_id)


func ready_action(token_id: String) -> void:
	if service != null:
		service.ready_action(token_id)


func get_current_turn_token_id() -> String:
	if service == null:
		return ""
	return service.get_current_turn_token_id()


func get_round_number() -> int:
	if service == null:
		return 0
	return service.get_round_number()


func apply_damage(token_id: String, amount: int, damage_type: String) -> Dictionary:
	if service == null:
		return {}
	return service.apply_damage(token_id, amount, damage_type)


func apply_healing(token_id: String, amount: int) -> Dictionary:
	if service == null:
		return {}
	return service.apply_healing(token_id, amount)


func apply_temp_hp(token_id: String, amount: int) -> void:
	if service != null:
		service.apply_temp_hp(token_id, amount)


func roll_death_save(token_id: String) -> Dictionary:
	if service == null:
		return {}
	return service.roll_death_save(token_id)


func get_hp_status(token_id: String) -> Dictionary:
	if service == null:
		return {}
	return service.get_hp_status(token_id)


func serialize_state() -> Dictionary:
	if service == null:
		return {}
	return service.serialize_state()


func deserialize_state(data: Dictionary) -> void:
	if service != null:
		service.deserialize_state(data)


func call_for_save(ability: String, dc: int, token_ids: Array[String]) -> Array:
	if service == null:
		return []
	return service.call_for_save(ability, dc, token_ids)


func get_save_modifier(token_id: String, ability: String) -> int:
	if service == null:
		return 0
	return service.get_save_modifier(token_id, ability)


func create_aoe(aoe: AoEData) -> void:
	if service != null:
		service.create_aoe(aoe)


func remove_aoe(aoe_id: String) -> void:
	if service != null:
		service.remove_aoe(aoe_id)


func get_aoes() -> Array:
	if service == null:
		return []
	return service.get_aoes()


func get_aoe(aoe_id: String) -> AoEData:
	if service == null:
		return null
	return service.get_aoe(aoe_id)


func apply_condition(token_id: String, condition_name: String,
		source: String, duration_rounds: int) -> void:
	if service != null:
		service.apply_condition(token_id, condition_name, source, duration_rounds)


func remove_condition(token_id: String, condition_name: String) -> void:
	if service != null:
		service.remove_condition(token_id, condition_name)


func get_conditions(token_id: String) -> Array:
	if service == null:
		return []
	return service.get_conditions(token_id)


func check_condition_modifiers(token_id: String, roll_type: String,
		ability: String) -> Dictionary:
	if service == null:
		return {"advantage": false, "disadvantage": false, "auto_fail": false}
	return service.check_condition_modifiers(token_id, roll_type, ability)


func get_combat_log() -> Array:
	if service == null:
		return []
	return service.get_combat_log()


func clear_combat_log() -> void:
	if service != null:
		service.clear_combat_log()


func add_log_entry(entry: Dictionary) -> void:
	if service != null:
		service.add_log_entry(entry)
