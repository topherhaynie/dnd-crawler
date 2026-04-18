extends RefCounted
class_name AoEData

## AoEData — describes an Area-of-Effect template placed on the map.
##
## References a MeasurementData for geometry and an optional EffectData for
## visual rendering. Used by CombatService for token hit-testing and batch
## saving throw resolution.

var id: String = ""
var measurement_id: String = "" ## References MeasurementData.id for geometry
var effect_id: String = "" ## Optional EffectData.id for visual
var spell_name: String = ""
var save_ability: String = "" ## "str", "dex", "con", "int", "wis", "cha"
var save_dc: int = 0
var damage_expression: String = "" ## e.g. "8d6"
var damage_type: String = "" ## e.g. "fire"
var caster_token_id: String = ""
var duration_rounds: int = -1 ## -1 = indefinite, 0 = instant
var rounds_remaining: int = -1
var half_on_save: bool = true ## Typical: half damage on successful save
var color: Color = Color(1.0, 0.3, 0.1, 0.6)


static func generate_id() -> String:
	return "aoe_%d_%d" % [Time.get_ticks_msec(), randi()]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"measurement_id": measurement_id,
		"effect_id": effect_id,
		"spell_name": spell_name,
		"save_ability": save_ability,
		"save_dc": save_dc,
		"damage_expression": damage_expression,
		"damage_type": damage_type,
		"caster_token_id": caster_token_id,
		"duration_rounds": duration_rounds,
		"rounds_remaining": rounds_remaining,
		"half_on_save": half_on_save,
		"color": [color.r, color.g, color.b, color.a],
	}


static func from_dict(d: Dictionary) -> AoEData:
	var a := AoEData.new()
	a.id = str(d.get("id", ""))
	a.measurement_id = str(d.get("measurement_id", ""))
	a.effect_id = str(d.get("effect_id", ""))
	a.spell_name = str(d.get("spell_name", ""))
	a.save_ability = str(d.get("save_ability", ""))
	a.save_dc = int(d.get("save_dc", 0))
	a.damage_expression = str(d.get("damage_expression", ""))
	a.damage_type = str(d.get("damage_type", ""))
	a.caster_token_id = str(d.get("caster_token_id", ""))
	a.duration_rounds = int(d.get("duration_rounds", -1))
	a.rounds_remaining = int(d.get("rounds_remaining", -1))
	a.half_on_save = bool(d.get("half_on_save", true))
	var raw_color: Variant = d.get("color", null)
	if raw_color is Array and (raw_color as Array).size() >= 4:
		var ca: Array = raw_color as Array
		a.color = Color(float(ca[0]), float(ca[1]), float(ca[2]), float(ca[3]))
	return a
