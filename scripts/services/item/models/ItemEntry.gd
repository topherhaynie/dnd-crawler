extends RefCounted
class_name ItemEntry

# ---------------------------------------------------------------------------
# ItemEntry — equipment/item definition matching SRD JSON + inventory fields.
# ---------------------------------------------------------------------------

var id: String = ""
var index: String = ""
var name: String = ""
var category: String = ""
var desc: String = ""
var weight: float = 0.0
var source: String = "" # "srd_2014", "srd_2024", "custom", "campaign"
var ruleset: String = "" # "2014", "2024", "custom"
## {quantity: int, unit: String}
var cost: Dictionary = {}
var properties: Array = []
## {damage_dice: String, damage_type: String}
var damage: Dictionary = {}
## {base: int, dex_bonus: bool, max_bonus: int}
var armor_class: Dictionary = {}
## {normal: int, long: int}
var item_range: Dictionary = {}

# --- Inventory fields (per-instance) ---
var quantity: int = 1
var equipped: bool = false
var attuned: bool = false


func to_dict() -> Dictionary:
	return {
		"id": id,
		"index": index,
		"name": name,
		"category": category,
		"desc": desc,
		"weight": weight,
		"source": source,
		"ruleset": ruleset,
		"cost": cost,
		"properties": properties,
		"damage": damage,
		"armor_class": armor_class,
		"item_range": item_range,
		"quantity": quantity,
		"equipped": equipped,
		"attuned": attuned,
	}


static func from_dict(d: Dictionary) -> ItemEntry:
	var it := ItemEntry.new()
	it.id = str(d.get("id", ""))
	it.index = str(d.get("index", ""))
	it.name = str(d.get("name", ""))
	it.category = str(d.get("category", ""))
	it.desc = str(d.get("desc", ""))
	it.weight = float(d.get("weight", 0.0))
	it.source = str(d.get("source", ""))
	it.ruleset = str(d.get("ruleset", ""))
	var raw_cost: Variant = d.get("cost", {})
	if raw_cost is Dictionary:
		it.cost = raw_cost as Dictionary
	var raw_props: Variant = d.get("properties", [])
	if raw_props is Array:
		it.properties = raw_props as Array
	var raw_dmg: Variant = d.get("damage", {})
	if raw_dmg is Dictionary:
		it.damage = raw_dmg as Dictionary
	var raw_ac: Variant = d.get("armor_class", {})
	if raw_ac is Dictionary:
		it.armor_class = raw_ac as Dictionary
	var raw_range: Variant = d.get("item_range", d.get("range", {}))
	if raw_range is Dictionary:
		it.item_range = raw_range as Dictionary
	it.quantity = int(d.get("quantity", 1))
	it.equipped = bool(d.get("equipped", false))
	it.attuned = bool(d.get("attuned", false))
	return it


## Parse from SRD JSON format.
static func from_srd(d: Dictionary, p_ruleset: String = "2014") -> ItemEntry:
	var it := ItemEntry.new()
	it.index = str(d.get("index", ""))
	it.id = it.index
	it.name = str(d.get("name", ""))
	it.source = "srd_%s" % p_ruleset
	it.ruleset = p_ruleset

	# category: {index, name} or String
	var raw_cat: Variant = d.get("equipment_category", "")
	if raw_cat is Dictionary:
		it.category = str((raw_cat as Dictionary).get("name", ""))
	else:
		it.category = str(raw_cat)

	# desc can be array or string
	var raw_desc: Variant = d.get("desc", "")
	if raw_desc is Array:
		var parts: PackedStringArray = PackedStringArray()
		for part: Variant in raw_desc as Array:
			parts.append(str(part))
		it.desc = "\n".join(parts)
	else:
		it.desc = str(raw_desc)

	it.weight = float(d.get("weight", 0.0))

	var raw_cost: Variant = d.get("cost", {})
	if raw_cost is Dictionary:
		var cd := raw_cost as Dictionary
		it.cost = {"quantity": int(cd.get("quantity", 0)), "unit": str(cd.get("unit", "gp"))}

	# properties: array of {index, name}
	var raw_props: Variant = d.get("properties", [])
	if raw_props is Array:
		for prop: Variant in raw_props as Array:
			if prop is Dictionary:
				it.properties.append(str((prop as Dictionary).get("name", "")))
			elif prop is String:
				it.properties.append(prop as String)

	# damage
	var raw_dmg: Variant = d.get("damage", {})
	if raw_dmg is Dictionary:
		var dd := raw_dmg as Dictionary
		var dmg_dice: String = str(dd.get("damage_dice", ""))
		var dmg_type_raw: Variant = dd.get("damage_type", {})
		var dmg_type: String = ""
		if dmg_type_raw is Dictionary:
			dmg_type = str((dmg_type_raw as Dictionary).get("name", ""))
		it.damage = {"damage_dice": dmg_dice, "damage_type": dmg_type}

	# armor_class
	var raw_ac: Variant = d.get("armor_class", {})
	if raw_ac is Dictionary:
		var acd := raw_ac as Dictionary
		it.armor_class = {
			"base": int(acd.get("base", 0)),
			"dex_bonus": bool(acd.get("dex_bonus", false)),
			"max_bonus": int(acd.get("max_bonus", 0)),
		}

	# range
	var raw_range: Variant = d.get("range", {})
	if raw_range is Dictionary:
		var rd := raw_range as Dictionary
		it.item_range = {"normal": int(rd.get("normal", 0)), "long": int(rd.get("long", 0))}

	return it


static func generate_id() -> String:
	return "item_%d_%d" % [Time.get_ticks_msec(), randi()]
