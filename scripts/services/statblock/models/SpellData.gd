extends RefCounted
class_name SpellData

# ---------------------------------------------------------------------------
# SpellData — full spell definition matching the SRD JSON schema.
# ---------------------------------------------------------------------------

var index: String = ""
var name: String = ""
var desc: String = ""
var higher_level: String = ""
var spell_range: String = ""
var components: Array = [] # ["V", "S", "M"]
var material: String = ""
var ritual: bool = false
var duration: String = ""
var concentration: bool = false
var casting_time: String = ""
var level: int = 0
var school: String = ""
var classes: Array = [] # Array of class name strings
var subclasses: Array = []
## {damage_type: String, damage_at_slot_level: Dictionary, damage_at_character_level: Dictionary}
var damage: Dictionary = {}
## {dc_type: String, dc_success: String}
var dc: Dictionary = {}
## {heal_at_slot_level: Dictionary}
var heal_at_slot_level: Dictionary = {}
## {type: String, size: int} — e.g. {type: "sphere", size: 20}
var area_of_effect: Dictionary = {}
var attack_type: String = ""
var source: String = "" # "SRD-2014" / "SRD-2024"
var ruleset: String = "" # "2014" / "2024"


func to_dict() -> Dictionary:
	return {
		"index": index,
		"name": name,
		"desc": desc,
		"higher_level": higher_level,
		"range": spell_range,
		"components": components,
		"material": material,
		"ritual": ritual,
		"duration": duration,
		"concentration": concentration,
		"casting_time": casting_time,
		"level": level,
		"school": school,
		"classes": classes,
		"subclasses": subclasses,
		"damage": damage,
		"dc": dc,
		"heal_at_slot_level": heal_at_slot_level,
		"area_of_effect": area_of_effect,
		"attack_type": attack_type,
		"source": source,
		"ruleset": ruleset,
	}


static func from_dict(d: Dictionary) -> SpellData:
	var s := SpellData.new()
	s.index = str(d.get("index", ""))
	s.name = str(d.get("name", ""))
	s.desc = str(d.get("desc", ""))
	s.higher_level = str(d.get("higher_level", ""))
	s.spell_range = str(d.get("range", ""))
	var raw_comp: Variant = d.get("components", [])
	if raw_comp is Array:
		s.components = raw_comp as Array
	s.material = str(d.get("material", ""))
	s.ritual = bool(d.get("ritual", false))
	s.duration = str(d.get("duration", ""))
	s.concentration = bool(d.get("concentration", false))
	s.casting_time = str(d.get("casting_time", ""))
	s.level = int(d.get("level", 0))
	s.school = str(d.get("school", ""))
	var raw_classes: Variant = d.get("classes", [])
	if raw_classes is Array:
		s.classes = raw_classes as Array
	var raw_sub: Variant = d.get("subclasses", [])
	if raw_sub is Array:
		s.subclasses = raw_sub as Array
	var raw_dmg: Variant = d.get("damage", {})
	if raw_dmg is Dictionary:
		s.damage = raw_dmg as Dictionary
	var raw_dc: Variant = d.get("dc", {})
	if raw_dc is Dictionary:
		s.dc = raw_dc as Dictionary
	var raw_heal: Variant = d.get("heal_at_slot_level", {})
	if raw_heal is Dictionary:
		s.heal_at_slot_level = raw_heal as Dictionary
	var raw_aoe: Variant = d.get("area_of_effect", {})
	if raw_aoe is Dictionary:
		s.area_of_effect = raw_aoe as Dictionary
	s.attack_type = str(d.get("attack_type", ""))
	s.source = str(d.get("source", ""))
	s.ruleset = str(d.get("ruleset", ""))
	return s


## Parse from SRD JSON format.
static func from_srd(d: Dictionary, p_ruleset: String) -> SpellData:
	var s := SpellData.new()
	s.index = str(d.get("index", ""))
	s.name = str(d.get("name", ""))

	# desc can be a string or array of strings
	var raw_desc: Variant = d.get("desc", "")
	if raw_desc is Array:
		var parts: PackedStringArray = PackedStringArray()
		for part: Variant in raw_desc as Array:
			parts.append(str(part))
		s.desc = "\n".join(parts)
	else:
		s.desc = str(raw_desc)

	var raw_hl: Variant = d.get("higher_level", "")
	if raw_hl is Array:
		var parts: PackedStringArray = PackedStringArray()
		for part: Variant in raw_hl as Array:
			parts.append(str(part))
		s.higher_level = "\n".join(parts)
	else:
		s.higher_level = str(raw_hl)

	s.spell_range = str(d.get("range", ""))

	var raw_comp: Variant = d.get("components", [])
	if raw_comp is Array:
		for c: Variant in raw_comp as Array:
			s.components.append(str(c))

	s.material = str(d.get("material", ""))
	s.ritual = bool(d.get("ritual", false))
	s.duration = str(d.get("duration", ""))
	s.concentration = bool(d.get("concentration", false))
	s.casting_time = str(d.get("casting_time", ""))
	s.level = int(d.get("level", 0))

	# school: {index, name} or String
	var raw_school: Variant = d.get("school", "")
	if raw_school is Dictionary:
		s.school = str((raw_school as Dictionary).get("name", ""))
	else:
		s.school = str(raw_school)

	# classes: array of {index, name}
	var raw_classes: Variant = d.get("classes", [])
	if raw_classes is Array:
		for cls: Variant in raw_classes as Array:
			if cls is Dictionary:
				s.classes.append(str((cls as Dictionary).get("name", "")))
			elif cls is String:
				s.classes.append(cls as String)

	var raw_sub: Variant = d.get("subclasses", [])
	if raw_sub is Array:
		for sub: Variant in raw_sub as Array:
			if sub is Dictionary:
				s.subclasses.append(str((sub as Dictionary).get("name", "")))
			elif sub is String:
				s.subclasses.append(sub as String)

	# damage
	var raw_dmg: Variant = d.get("damage", {})
	if raw_dmg is Dictionary:
		var dmg_dict := raw_dmg as Dictionary
		var parsed_damage: Dictionary = {}
		var dt_raw: Variant = dmg_dict.get("damage_type", {})
		if dt_raw is Dictionary:
			parsed_damage["damage_type"] = str((dt_raw as Dictionary).get("name", ""))
		var slot_lvl: Variant = dmg_dict.get("damage_at_slot_level", {})
		if slot_lvl is Dictionary:
			parsed_damage["damage_at_slot_level"] = slot_lvl as Dictionary
		var char_lvl: Variant = dmg_dict.get("damage_at_character_level", {})
		if char_lvl is Dictionary:
			parsed_damage["damage_at_character_level"] = char_lvl as Dictionary
		s.damage = parsed_damage

	# dc
	var raw_dc: Variant = d.get("dc", {})
	if raw_dc is Dictionary:
		var dcd := raw_dc as Dictionary
		var dc_type_raw: Variant = dcd.get("dc_type", {})
		var dc_type_str: String = ""
		if dc_type_raw is Dictionary:
			dc_type_str = str((dc_type_raw as Dictionary).get("name", ""))
		elif dc_type_raw is String:
			dc_type_str = dc_type_raw as String
		s.dc = {
			"dc_type": dc_type_str,
			"dc_success": str(dcd.get("dc_success", "")),
		}

	# heal
	var raw_heal: Variant = d.get("heal_at_slot_level", {})
	if raw_heal is Dictionary:
		s.heal_at_slot_level = raw_heal as Dictionary

	# area_of_effect
	var raw_aoe: Variant = d.get("area_of_effect", {})
	if raw_aoe is Dictionary:
		var aoe_d := raw_aoe as Dictionary
		s.area_of_effect = {
			"type": str(aoe_d.get("type", "")),
			"size": int(aoe_d.get("size", 0)),
		}

	s.attack_type = str(d.get("attack_type", ""))
	s.ruleset = p_ruleset
	s.source = "SRD-%s" % p_ruleset
	return s
