extends RefCounted
class_name ActionEntry

# ---------------------------------------------------------------------------
# ActionEntry — reusable for actions, reactions, legendary actions,
# special abilities, and class features.
# ---------------------------------------------------------------------------

var name: String = ""
var desc: String = ""
## Source tag for grouping: "race", "class:Fighter", "feat:Alert", "background", etc.
var source: String = ""
var attack_bonus: int = 0
## Array of {damage_dice: String, damage_type: String}
var damage: Array = []
## {dc_type: String, dc_value: int, success_type: String}
var dc: Dictionary = {}
## {type: String, times: int, rest_types: Array}
var usage: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"name": name,
		"desc": desc,
		"source": source,
		"attack_bonus": attack_bonus,
		"damage": damage,
		"dc": dc,
		"usage": usage,
	}


static func from_dict(d: Dictionary) -> ActionEntry:
	var a := ActionEntry.new()
	a.name = str(d.get("name", ""))
	a.desc = str(d.get("desc", ""))
	a.source = str(d.get("source", ""))
	a.attack_bonus = int(d.get("attack_bonus", 0))
	var raw_dmg: Variant = d.get("damage", [])
	if raw_dmg is Array:
		a.damage = raw_dmg as Array
	var raw_dc: Variant = d.get("dc", {})
	if raw_dc is Dictionary:
		a.dc = raw_dc as Dictionary
	var raw_usage: Variant = d.get("usage", {})
	if raw_usage is Dictionary:
		a.usage = raw_usage as Dictionary
	return a


## Parse an action entry from SRD JSON format.
static func from_srd(d: Dictionary) -> ActionEntry:
	var a := ActionEntry.new()
	a.name = str(d.get("name", ""))
	a.desc = str(d.get("desc", ""))
	a.attack_bonus = int(d.get("attack_bonus", 0))

	# SRD damage format: array of {damage_dice, damage_type: {index, name}}
	var raw_dmg: Variant = d.get("damage", [])
	if raw_dmg is Array:
		for entry: Variant in raw_dmg as Array:
			if entry is Dictionary:
				var ed := entry as Dictionary
				var dmg_dice: String = str(ed.get("damage_dice", ""))
				var dmg_type_raw: Variant = ed.get("damage_type", {})
				var dmg_type: String = ""
				if dmg_type_raw is Dictionary:
					dmg_type = str((dmg_type_raw as Dictionary).get("name", ""))
				elif dmg_type_raw is String:
					dmg_type = dmg_type_raw as String
				a.damage.append({"damage_dice": dmg_dice, "damage_type": dmg_type})

	# SRD DC format: {dc_type: {index, name}, dc_value: int, success_type: String}
	var raw_dc: Variant = d.get("dc", {})
	if raw_dc is Dictionary:
		var dcd := raw_dc as Dictionary
		var dc_type_raw: Variant = dcd.get("dc_type", {})
		var dc_type_str: String = ""
		if dc_type_raw is Dictionary:
			dc_type_str = str((dc_type_raw as Dictionary).get("name", ""))
		elif dc_type_raw is String:
			dc_type_str = dc_type_raw as String
		a.dc = {
			"dc_type": dc_type_str,
			"dc_value": int(dcd.get("dc_value", 0)),
			"success_type": str(dcd.get("success_type", "")),
		}

	# SRD usage format: {type: String, times: int, rest_types: Array}
	var raw_usage: Variant = d.get("usage", {})
	if raw_usage is Dictionary:
		a.usage = raw_usage as Dictionary

	return a
