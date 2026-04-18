extends RefCounted
class_name CombatState

## Serializable combat encounter state for save/load persistence.
##
## Each entry in `initiative_order` is:
##   {token_id: String, initiative: int, dex_mod: int, init_bonus: int}

var is_active: bool = false
var round_number: int = 1
var current_turn_index: int = 0
var initiative_order: Array = [] ## Array of {token_id, initiative, dex_mod, init_bonus}
var readied_actions: Array = [] ## token_ids with readied actions
var delayed_tokens: Array = [] ## token_ids that delayed this round
## token_id → Array of {name: String, source: String, rounds_remaining: int}
var conditions: Dictionary = {}


func to_dict() -> Dictionary:
	# Serialise conditions: each token's array is duplicated independently.
	var conds_out: Dictionary = {}
	for tid: String in conditions:
		var arr: Array = conditions[tid] as Array
		conds_out[tid] = arr.duplicate(true)
	return {
		"is_active": is_active,
		"round_number": round_number,
		"current_turn_index": current_turn_index,
		"initiative_order": initiative_order.duplicate(true),
		"readied_actions": readied_actions.duplicate(),
		"delayed_tokens": delayed_tokens.duplicate(),
		"conditions": conds_out,
	}


static func from_dict(d: Dictionary) -> CombatState:
	var cs := CombatState.new()
	cs.is_active = bool(d.get("is_active", false))
	cs.round_number = int(d.get("round_number", 1))
	cs.current_turn_index = int(d.get("current_turn_index", 0))
	var raw_order: Variant = d.get("initiative_order", [])
	if raw_order is Array:
		cs.initiative_order = (raw_order as Array).duplicate(true)
	var raw_readied: Variant = d.get("readied_actions", [])
	if raw_readied is Array:
		cs.readied_actions = (raw_readied as Array).duplicate()
	var raw_delayed: Variant = d.get("delayed_tokens", [])
	if raw_delayed is Array:
		cs.delayed_tokens = (raw_delayed as Array).duplicate()
	var raw_conds: Variant = d.get("conditions", {})
	if raw_conds is Dictionary:
		for tid: String in (raw_conds as Dictionary):
			var raw_arr: Variant = (raw_conds as Dictionary)[tid]
			if raw_arr is Array:
				cs.conditions[tid] = (raw_arr as Array).duplicate(true)
	return cs
