extends RefCounted
class_name StatblockData

# ---------------------------------------------------------------------------
# StatblockData — unified creature/character statblock.
#
# Covers both monsters (SRD) and player characters. PC-specific fields
# remain empty for monsters. SRD-specific fields remain empty for custom
# characters.
# ---------------------------------------------------------------------------

# --- Identity --------------------------------------------------------------
var id: String = ""
var name: String = ""
## SRD index slug (e.g. "goblin"). Empty for custom statblocks.
var srd_index: String = ""
## "SRD-2014" / "SRD-2024" / "campaign" / "token-override" / "global"
var source: String = ""
## "2014" / "2024" / "custom"
var ruleset: String = ""

# --- Type ------------------------------------------------------------------
var size: String = ""
var creature_type: String = ""
var subtype: String = ""
var alignment: String = ""

# --- Combat ----------------------------------------------------------------
## Array of {type: String, value: int}
var armor_class: Array = []
var hit_points: int = 0
var hit_dice: String = ""
var hit_points_roll: String = ""
## Flat bonus to initiative rolls (e.g. +5 from Alert feat).
var initiative_bonus: int = 0

# --- Speed -----------------------------------------------------------------
## {"walk": "30 ft.", "fly": "60 ft.", ...}
var speed: Dictionary = {}

# --- Ability Scores --------------------------------------------------------
var strength: int = 10
var dexterity: int = 10
var constitution: int = 10
var intelligence: int = 10
var wisdom: int = 10
var charisma: int = 10

# --- Defenses --------------------------------------------------------------
## Array of {proficiency: {index, name}, value: int}
var saving_throws: Array = []
var damage_vulnerabilities: Array = []
var damage_resistances: Array = []
var damage_immunities: Array = []
## Array of {index: String, name: String} or plain strings
var condition_immunities: Array = []

# --- Proficiencies ---------------------------------------------------------
## Array of {value: int, proficiency: {index: String, name: String}}
var proficiencies: Array = []
var proficiency_bonus: int = 0

# --- Senses & Languages ----------------------------------------------------
## {passive_perception: int, darkvision: String, ...}
var senses: Dictionary = {}
var languages: String = ""

# --- Rating ----------------------------------------------------------------
var challenge_rating: float = 0.0
var xp: int = 0 ## Monster XP reward value (from SRD).
var current_xp: int = 0 ## PC accumulated experience points.

# --- Abilities --------------------------------------------------------------
var special_abilities: Array = [] # Array of ActionEntry.to_dict()
var actions: Array = []
var reactions: Array = []
var legendary_actions: Array = []

# --- Spellcasting -----------------------------------------------------------
var spell_list: Array = [] # Array of spell index strings
## {level_number: slot_count}
var spell_slots: Dictionary = {}

# --- PC Extensions ----------------------------------------------------------
var class_name_str: String = ""
var level: int = 0
var race: String = ""
var background: String = ""
var inventory: Array = [] # Array of ItemEntry.to_dict()
var features: Array = [] # Array of ActionEntry.to_dict()
## Multiclass entries: [{"name": "Fighter", "level": 5, "subclass": "Champion"}, ...]
var classes: Array = []

# --- Image ------------------------------------------------------------------
var portrait_path: String = ""
var srd_image_url: String = ""
## Optional back-reference to a campaign image ID this portrait was sourced
## from.  Metadata only — rendering uses portrait_path directly.
var portrait_campaign_image_id: String = ""

# --- Meta -------------------------------------------------------------------
var notes: String = ""
var tags: Array = []


# ---------------------------------------------------------------------------
# D\u0026D Size Category Mapping
# ---------------------------------------------------------------------------

## Standard D&D 5e size categories and their space in feet.
const _SIZE_TO_FEET: Dictionary = {
	"Tiny": 2.5,
	"Small": 5.0,
	"Medium": 5.0,
	"Large": 10.0,
	"Huge": 15.0,
	"Gargantuan": 20.0,
}

## Ordered labels for UI dropdowns (index-stable).
const SIZE_LABELS: Array = ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]


## Convert a D&D size string (e.g. "Large") to feet. Returns 5.0 for unknown.
static func size_to_feet(size_str: String) -> float:
	var val: Variant = _SIZE_TO_FEET.get(size_str, null)
	if val != null:
		return float(val)
	# Try case-insensitive match.
	for key: String in _SIZE_TO_FEET:
		if key.to_lower() == size_str.strip_edges().to_lower():
			return float(_SIZE_TO_FEET[key])
	return 5.0


## Convert a feet value to the best matching D&D size label.
static func feet_to_size_label(ft: float) -> String:
	if ft <= 2.5:
		return "Tiny"
	if ft <= 5.0:
		return "Medium" # Both Small and Medium are 5 ft; default to Medium.
	if ft <= 10.0:
		return "Large"
	if ft <= 15.0:
		return "Huge"
	return "Gargantuan"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

static func generate_id() -> String:
	return "%d_%d" % [Time.get_ticks_msec(), randi()]


## Sum of all class levels from the classes array, falling back to `level`.
func get_total_level() -> int:
	if classes.is_empty():
		return level
	var total: int = 0
	for entry: Variant in classes:
		if entry is Dictionary:
			total += int((entry as Dictionary).get("level", 0))
	return total if total > 0 else level


## Primary class name (first entry in `classes`, or `class_name_str`).
func get_primary_class() -> String:
	if not classes.is_empty():
		var first: Variant = classes[0]
		if first is Dictionary:
			return str((first as Dictionary).get("name", class_name_str))
	return class_name_str


func get_modifier(ability: String) -> int:
	var score: int = _get_ability_score(ability)
	return int(floor((float(score) - 10.0) / 2.0))


func _get_ability_score(ability: String) -> int:
	match ability.to_lower():
		"str", "strength": return strength
		"dex", "dexterity": return dexterity
		"con", "constitution": return constitution
		"int", "intelligence": return intelligence
		"wis", "wisdom": return wisdom
		"cha", "charisma": return charisma
	return 10


func roll_hit_points() -> int:
	if hit_points_roll.is_empty():
		return hit_points
	var expr := DiceExpression.parse(hit_points_roll)
	var result: DiceResult = expr.roll()
	return maxi(1, result.total)


# ---------------------------------------------------------------------------
# Serialisation
# ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var sa: Array = []
	for entry: Variant in special_abilities:
		if entry is ActionEntry:
			sa.append((entry as ActionEntry).to_dict())
		elif entry is Dictionary:
			sa.append(entry)

	var act: Array = []
	for entry: Variant in actions:
		if entry is ActionEntry:
			act.append((entry as ActionEntry).to_dict())
		elif entry is Dictionary:
			act.append(entry)

	var react: Array = []
	for entry: Variant in reactions:
		if entry is ActionEntry:
			react.append((entry as ActionEntry).to_dict())
		elif entry is Dictionary:
			react.append(entry)

	var legend: Array = []
	for entry: Variant in legendary_actions:
		if entry is ActionEntry:
			legend.append((entry as ActionEntry).to_dict())
		elif entry is Dictionary:
			legend.append(entry)

	var inv: Array = []
	for entry: Variant in inventory:
		if entry is ItemEntry:
			inv.append((entry as ItemEntry).to_dict())
		elif entry is Dictionary:
			inv.append(entry)

	var feat: Array = []
	for entry: Variant in features:
		if entry is ActionEntry:
			feat.append((entry as ActionEntry).to_dict())
		elif entry is Dictionary:
			feat.append(entry)

	return {
		"id": id,
		"name": name,
		"srd_index": srd_index,
		"source": source,
		"ruleset": ruleset,
		"size": size,
		"creature_type": creature_type,
		"subtype": subtype,
		"alignment": alignment,
		"armor_class": armor_class,
		"hit_points": hit_points,
		"hit_dice": hit_dice,
		"hit_points_roll": hit_points_roll,
		"initiative_bonus": initiative_bonus,
		"speed": speed,
		"strength": strength,
		"dexterity": dexterity,
		"constitution": constitution,
		"intelligence": intelligence,
		"wisdom": wisdom,
		"charisma": charisma,
		"saving_throws": saving_throws,
		"damage_vulnerabilities": damage_vulnerabilities,
		"damage_resistances": damage_resistances,
		"damage_immunities": damage_immunities,
		"condition_immunities": condition_immunities,
		"proficiencies": proficiencies,
		"proficiency_bonus": proficiency_bonus,
		"senses": senses,
		"languages": languages,
		"challenge_rating": challenge_rating,
		"xp": xp,
		"current_xp": current_xp,
		"special_abilities": sa,
		"actions": act,
		"reactions": react,
		"legendary_actions": legend,
		"spell_list": spell_list,
		"spell_slots": spell_slots,
		"class_name_str": class_name_str,
		"level": level,
		"race": race,
		"background": background,
		"inventory": inv,
		"features": feat,
		"classes": classes,
		"portrait_path": portrait_path,
		"srd_image_url": srd_image_url,
		"portrait_campaign_image_id": portrait_campaign_image_id,
		"notes": notes,
		"tags": tags,
	}


static func from_dict(d: Dictionary) -> StatblockData:
	var s := StatblockData.new()
	s.id = str(d.get("id", ""))
	s.name = str(d.get("name", ""))
	s.srd_index = str(d.get("srd_index", ""))
	s.source = str(d.get("source", ""))
	s.ruleset = str(d.get("ruleset", ""))
	s.size = str(d.get("size", ""))
	s.creature_type = str(d.get("creature_type", ""))
	s.subtype = str(d.get("subtype", ""))
	s.alignment = str(d.get("alignment", ""))

	var raw_ac: Variant = d.get("armor_class", [])
	if raw_ac is Array:
		s.armor_class = raw_ac as Array

	s.hit_points = int(d.get("hit_points", 0))
	s.hit_dice = str(d.get("hit_dice", ""))
	s.hit_points_roll = str(d.get("hit_points_roll", ""))
	s.initiative_bonus = int(d.get("initiative_bonus", 0))

	var raw_speed: Variant = d.get("speed", {})
	if raw_speed is Dictionary:
		s.speed = raw_speed as Dictionary

	s.strength = int(d.get("strength", 10))
	s.dexterity = int(d.get("dexterity", 10))
	s.constitution = int(d.get("constitution", 10))
	s.intelligence = int(d.get("intelligence", 10))
	s.wisdom = int(d.get("wisdom", 10))
	s.charisma = int(d.get("charisma", 10))

	var raw_st: Variant = d.get("saving_throws", [])
	if raw_st is Array:
		s.saving_throws = raw_st as Array

	var raw_dv: Variant = d.get("damage_vulnerabilities", [])
	if raw_dv is Array:
		s.damage_vulnerabilities = raw_dv as Array

	var raw_dr: Variant = d.get("damage_resistances", [])
	if raw_dr is Array:
		s.damage_resistances = raw_dr as Array

	var raw_di: Variant = d.get("damage_immunities", [])
	if raw_di is Array:
		s.damage_immunities = raw_di as Array

	var raw_ci: Variant = d.get("condition_immunities", [])
	if raw_ci is Array:
		s.condition_immunities = raw_ci as Array

	var raw_prof: Variant = d.get("proficiencies", [])
	if raw_prof is Array:
		s.proficiencies = raw_prof as Array

	s.proficiency_bonus = int(d.get("proficiency_bonus", 0))

	var raw_senses: Variant = d.get("senses", {})
	if raw_senses is Dictionary:
		s.senses = raw_senses as Dictionary

	s.languages = str(d.get("languages", ""))
	s.challenge_rating = float(d.get("challenge_rating", 0.0))
	s.xp = int(d.get("xp", 0))

	s.special_abilities = _deserialize_actions(d.get("special_abilities", []))
	s.actions = _deserialize_actions(d.get("actions", []))
	s.reactions = _deserialize_actions(d.get("reactions", []))
	s.legendary_actions = _deserialize_actions(d.get("legendary_actions", []))

	var raw_spells: Variant = d.get("spell_list", [])
	if raw_spells is Array:
		s.spell_list = raw_spells as Array

	var raw_slots: Variant = d.get("spell_slots", {})
	if raw_slots is Dictionary:
		## JSON round-trip converts int keys to strings — normalise back to int.
		s.spell_slots = {}
		for k: Variant in (raw_slots as Dictionary).keys():
			var v: Variant = (raw_slots as Dictionary).get(k, 0)
			if str(k).is_valid_int():
				s.spell_slots[int(str(k))] = int(v)
			else:
				s.spell_slots[k] = v

	s.class_name_str = str(d.get("class_name_str", ""))
	s.level = int(d.get("level", 0))
	s.race = str(d.get("race", ""))
	s.background = str(d.get("background", ""))

	s.inventory = _deserialize_items(d.get("inventory", []))
	s.features = _deserialize_actions(d.get("features", []))

	# Multiclass array — migrate from single class_name_str/level if absent.
	var raw_classes: Variant = d.get("classes", [])
	if raw_classes is Array:
		s.classes = raw_classes as Array
	if s.classes.is_empty() and not s.class_name_str.is_empty() and s.level > 0:
		s.classes = [ {"name": s.class_name_str, "level": s.level, "subclass": ""}]

	s.portrait_path = str(d.get("portrait_path", ""))
	s.srd_image_url = str(d.get("srd_image_url", ""))
	s.portrait_campaign_image_id = str(d.get("portrait_campaign_image_id", ""))
	s.notes = str(d.get("notes", ""))

	var raw_tags: Variant = d.get("tags", [])
	if raw_tags is Array:
		s.tags = raw_tags as Array

	return s


static func _deserialize_actions(raw: Variant) -> Array:
	var result: Array = []
	if not raw is Array:
		return result
	for entry: Variant in raw as Array:
		if entry is Dictionary:
			result.append(ActionEntry.from_dict(entry as Dictionary))
	return result


static func _deserialize_items(raw: Variant) -> Array:
	var result: Array = []
	if not raw is Array:
		return result
	for entry: Variant in raw as Array:
		if entry is Dictionary:
			result.append(ItemEntry.from_dict(entry as Dictionary))
	return result


# ---------------------------------------------------------------------------
# SRD JSON parsing
# ---------------------------------------------------------------------------

## Parse a monster entry from SRD JSON.
static func from_srd_monster(d: Dictionary, p_ruleset: String) -> StatblockData:
	var s := StatblockData.new()
	s.id = StatblockData.generate_id()
	s.srd_index = str(d.get("index", ""))
	s.name = str(d.get("name", ""))
	s.source = "SRD-%s" % p_ruleset
	s.ruleset = p_ruleset

	s.size = str(d.get("size", ""))
	s.creature_type = str(d.get("type", ""))
	s.subtype = str(d.get("subtype", ""))
	s.alignment = str(d.get("alignment", ""))

	# armor_class — SRD format: array of {type, value} dicts
	var raw_ac: Variant = d.get("armor_class", [])
	if raw_ac is Array:
		for ac_raw: Variant in raw_ac as Array:
			if ac_raw is Dictionary:
				var acd := ac_raw as Dictionary
				s.armor_class.append({
					"type": str(acd.get("type", "")),
					"value": int(acd.get("value", 0)),
				})

	s.hit_points = int(d.get("hit_points", 0))
	s.hit_dice = str(d.get("hit_dice", ""))
	s.hit_points_roll = str(d.get("hit_points_roll", ""))

	# speed — SRD format: {walk: "30 ft.", fly: "60 ft.", ...}
	var raw_speed: Variant = d.get("speed", {})
	if raw_speed is Dictionary:
		s.speed = raw_speed as Dictionary

	s.strength = int(d.get("strength", 10))
	s.dexterity = int(d.get("dexterity", 10))
	s.constitution = int(d.get("constitution", 10))
	s.intelligence = int(d.get("intelligence", 10))
	s.wisdom = int(d.get("wisdom", 10))
	s.charisma = int(d.get("charisma", 10))

	# proficiencies — SRD format: [{proficiency: {index, name, url}, value: int}]
	# Split saving throws out from skill proficiencies
	var raw_prof: Variant = d.get("proficiencies", [])
	if raw_prof is Array:
		for prof_raw: Variant in raw_prof as Array:
			if not prof_raw is Dictionary:
				continue
			var pd := prof_raw as Dictionary
			var prof_info: Variant = pd.get("proficiency", {})
			if not prof_info is Dictionary:
				continue
			var prof_dict := prof_info as Dictionary
			var prof_index: String = str(prof_dict.get("index", ""))
			var entry: Dictionary = {
				"value": int(pd.get("value", 0)),
				"proficiency": {
					"index": prof_index,
					"name": str(prof_dict.get("name", "")),
				},
			}
			if prof_index.begins_with("saving-throw-"):
				s.saving_throws.append(entry)
			else:
				s.proficiencies.append(entry)

	# proficiency bonus — derive from CR
	s.proficiency_bonus = _cr_to_proficiency_bonus(s.challenge_rating)

	# Damage arrays
	var raw_dv: Variant = d.get("damage_vulnerabilities", [])
	if raw_dv is Array:
		for v: Variant in raw_dv as Array:
			s.damage_vulnerabilities.append(str(v))

	var raw_dr: Variant = d.get("damage_resistances", [])
	if raw_dr is Array:
		for v: Variant in raw_dr as Array:
			s.damage_resistances.append(str(v))

	var raw_di: Variant = d.get("damage_immunities", [])
	if raw_di is Array:
		for v: Variant in raw_di as Array:
			s.damage_immunities.append(str(v))

	# Condition immunities — SRD: array of {index, name}
	var raw_ci: Variant = d.get("condition_immunities", [])
	if raw_ci is Array:
		for ci_raw: Variant in raw_ci as Array:
			if ci_raw is Dictionary:
				var cid := ci_raw as Dictionary
				s.condition_immunities.append({
					"index": str(cid.get("index", "")),
					"name": str(cid.get("name", "")),
				})
			elif ci_raw is String:
				s.condition_immunities.append(ci_raw)

	# Senses
	var raw_senses: Variant = d.get("senses", {})
	if raw_senses is Dictionary:
		s.senses = raw_senses as Dictionary

	s.languages = str(d.get("languages", ""))
	s.challenge_rating = float(d.get("challenge_rating", 0.0))
	s.xp = int(d.get("xp", 0))

	# Actions, abilities, reactions, legendary actions
	var raw_sa: Variant = d.get("special_abilities", [])
	if raw_sa is Array:
		for entry: Variant in raw_sa as Array:
			if entry is Dictionary:
				s.special_abilities.append(ActionEntry.from_srd(entry as Dictionary))

	var raw_act: Variant = d.get("actions", [])
	if raw_act is Array:
		for entry: Variant in raw_act as Array:
			if entry is Dictionary:
				s.actions.append(ActionEntry.from_srd(entry as Dictionary))

	var raw_react: Variant = d.get("reactions", [])
	if raw_react is Array:
		for entry: Variant in raw_react as Array:
			if entry is Dictionary:
				s.reactions.append(ActionEntry.from_srd(entry as Dictionary))

	var raw_legend: Variant = d.get("legendary_actions", [])
	if raw_legend is Array:
		for entry: Variant in raw_legend as Array:
			if entry is Dictionary:
				s.legendary_actions.append(ActionEntry.from_srd(entry as Dictionary))

	# Image URL
	var raw_image: Variant = d.get("image", "")
	if raw_image is String and not (raw_image as String).is_empty():
		s.srd_image_url = "https://www.dnd5eapi.co%s" % raw_image

	return s


## Derive proficiency bonus from challenge rating per 5e rules.
static func _cr_to_proficiency_bonus(cr: float) -> int:
	if cr < 5.0:
		return 2
	elif cr < 9.0:
		return 3
	elif cr < 13.0:
		return 4
	elif cr < 17.0:
		return 5
	elif cr < 21.0:
		return 6
	elif cr < 25.0:
		return 7
	elif cr < 29.0:
		return 8
	return 9
