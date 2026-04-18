extends RefCounted
class_name ConditionRules

## ConditionRules — static data for all 15 SRD 5e conditions.
##
## Each condition entry contains:
##   label              : String  — display name
##   abbrev             : String  — 3-letter badge abbreviation
##   color              : Color   — badge background colour
##   attack_made_adv    : bool    — this token has advantage on attacks it makes
##   attack_made_disadv : bool    — this token has disadvantage on attacks it makes
##   attack_rcvd_adv    : bool    — attackers have advantage when targeting this token
##   attack_rcvd_disadv : bool    — attackers have disadvantage when targeting this token
##   save_auto_fail     : Array   — ability keys (e.g. "str","dex") auto-failed on saves
##   save_disadv        : Array   — ability keys with disadvantage on saves
##   check_disadv       : bool    — disadvantage on ability checks
##   speed_mult         : float   — movement speed multiplier (0.0 = can't move)
##   incapacitated      : bool    — can't take actions or reactions
##   description        : String  — brief plain-English summary

const CONDITIONS: Dictionary = {
	"blinded": {
		"label": "Blinded",
		"abbrev": "BLD",
		"color": Color(0.20, 0.08, 0.28, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": true,
		"attack_rcvd_adv": true,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 1.0,
		"incapacitated": false,
		"description": "Disadvantage on attack rolls; attacks against have advantage.",
	},
	"charmed": {
		"label": "Charmed",
		"abbrev": "CHR",
		"color": Color(0.90, 0.30, 0.55, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": false,
		"attack_rcvd_adv": false,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 1.0,
		"incapacitated": false,
		"description": "Can't attack the charmer; charmer has advantage on social checks.",
	},
	"deafened": {
		"label": "Deafened",
		"abbrev": "DEF",
		"color": Color(0.35, 0.35, 0.55, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": false,
		"attack_rcvd_adv": false,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 1.0,
		"incapacitated": false,
		"description": "Can't hear; automatically fails checks requiring hearing.",
	},
	"exhaustion": {
		"label": "Exhaustion",
		"abbrev": "EXH",
		"color": Color(0.55, 0.40, 0.12, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": true,
		"attack_rcvd_adv": false,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": ["str", "dex", "con", "int", "wis", "cha"],
		"check_disadv": true,
		"speed_mult": 0.5,
		"incapacitated": false,
		"description": "Disadvantage on ability checks/saves; speed halved (simplified level 1-3).",
	},
	"frightened": {
		"label": "Frightened",
		"abbrev": "FRT",
		"color": Color(0.85, 0.40, 0.05, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": true,
		"attack_rcvd_adv": false,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": [],
		"check_disadv": true,
		"speed_mult": 1.0,
		"incapacitated": false,
		"description": "Disadvantage on attacks/checks while source visible; can't move closer.",
	},
	"grappled": {
		"label": "Grappled",
		"abbrev": "GRP",
		"color": Color(0.12, 0.55, 0.50, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": false,
		"attack_rcvd_adv": false,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 0.0,
		"incapacitated": false,
		"description": "Speed becomes 0; ends if grappler is incapacitated.",
	},
	"incapacitated": {
		"label": "Incapacitated",
		"abbrev": "INC",
		"color": Color(0.70, 0.08, 0.08, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": false,
		"attack_rcvd_adv": false,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 1.0,
		"incapacitated": true,
		"description": "Can't take actions or reactions.",
	},
	"invisible": {
		"label": "Invisible",
		"abbrev": "INV",
		"color": Color(0.18, 0.60, 0.80, 1.0),
		"attack_made_adv": true,
		"attack_made_disadv": false,
		"attack_rcvd_adv": false,
		"attack_rcvd_disadv": true,
		"save_auto_fail": [],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 1.0,
		"incapacitated": false,
		"description": "Advantage on attacks; attacks against have disadvantage.",
	},
	"paralyzed": {
		"label": "Paralyzed",
		"abbrev": "PAR",
		"color": Color(0.15, 0.30, 0.85, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": false,
		"attack_rcvd_adv": true,
		"attack_rcvd_disadv": false,
		"save_auto_fail": ["str", "dex"],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 0.0,
		"incapacitated": true,
		"description": "Incapacitated, can't move; auto-fails STR/DEX saves; attacks have advantage.",
	},
	"petrified": {
		"label": "Petrified",
		"abbrev": "PET",
		"color": Color(0.52, 0.52, 0.52, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": false,
		"attack_rcvd_adv": true,
		"attack_rcvd_disadv": false,
		"save_auto_fail": ["str", "dex"],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 0.0,
		"incapacitated": true,
		"description": "Incapacitated, can't move; auto-fails STR/DEX saves; attacks have advantage.",
	},
	"poisoned": {
		"label": "Poisoned",
		"abbrev": "POI",
		"color": Color(0.20, 0.65, 0.12, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": true,
		"attack_rcvd_adv": false,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": [],
		"check_disadv": true,
		"speed_mult": 1.0,
		"incapacitated": false,
		"description": "Disadvantage on attack rolls and ability checks.",
	},
	"prone": {
		"label": "Prone",
		"abbrev": "PRN",
		"color": Color(0.50, 0.32, 0.10, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": true,
		"attack_rcvd_adv": true,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 0.5,
		"incapacitated": false,
		"description": "Disadvantage on attacks; melee attacks have advantage; half speed to stand.",
	},
	"restrained": {
		"label": "Restrained",
		"abbrev": "RST",
		"color": Color(0.75, 0.28, 0.08, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": true,
		"attack_rcvd_adv": true,
		"attack_rcvd_disadv": false,
		"save_auto_fail": [],
		"save_disadv": ["dex"],
		"check_disadv": false,
		"speed_mult": 0.0,
		"incapacitated": false,
		"description": "Speed 0; disadvantage on attacks and DEX saves; attacks against have advantage.",
	},
	"stunned": {
		"label": "Stunned",
		"abbrev": "STN",
		"color": Color(0.92, 0.82, 0.05, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": false,
		"attack_rcvd_adv": true,
		"attack_rcvd_disadv": false,
		"save_auto_fail": ["str", "dex"],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 1.0,
		"incapacitated": true,
		"description": "Incapacitated; auto-fails STR/DEX saves; attacks have advantage.",
	},
	"unconscious": {
		"label": "Unconscious",
		"abbrev": "UNC",
		"color": Color(0.10, 0.12, 0.35, 1.0),
		"attack_made_adv": false,
		"attack_made_disadv": false,
		"attack_rcvd_adv": true,
		"attack_rcvd_disadv": false,
		"save_auto_fail": ["str", "dex"],
		"save_disadv": [],
		"check_disadv": false,
		"speed_mult": 0.0,
		"incapacitated": true,
		"description": "Incapacitated, can't move; auto-fails STR/DEX saves; attacks have advantage.",
	},
}


## Return an Array of all condition key strings.
static func get_all_keys() -> Array[String]:
	var keys: Array[String] = []
	for k: String in CONDITIONS.keys():
		keys.append(k)
	return keys


## Return the human-readable label for a condition key.
static func get_label(key: String) -> String:
	var raw: Variant = CONDITIONS.get(key, null)
	if raw == null:
		return key.capitalize()
	return str((raw as Dictionary).get("label", key))


## Return the 3-letter badge abbreviation for a condition key.
static func get_abbrev(key: String) -> String:
	var raw: Variant = CONDITIONS.get(key, null)
	if raw == null:
		return key.left(3).to_upper()
	return str((raw as Dictionary).get("abbrev", key.left(3).to_upper()))


## Return the badge background colour for a condition key.
static func get_color(key: String) -> Color:
	var raw: Variant = CONDITIONS.get(key, null)
	if raw == null:
		return Color(0.4, 0.4, 0.4, 1.0)
	var col: Variant = (raw as Dictionary).get("color", Color(0.4, 0.4, 0.4, 1.0))
	if col is Color:
		return col as Color
	return Color(0.4, 0.4, 0.4, 1.0)


## Compute combined advantage/disadvantage/auto_fail for a set of conditions.
##
## conditions  : Array of condition name strings (from StatblockOverride.conditions)
## roll_type   : "attack_made" | "attack_rcvd" | "save" | "check"
## ability     : save/check ability key (e.g. "str","dex") — unused for attack rolls
##
## Returns {advantage: bool, disadvantage: bool, auto_fail: bool}
static func compute_modifiers(conditions: Array, roll_type: String, ability: String) -> Dictionary:
	var adv: bool = false
	var disadv: bool = false
	var auto_fail: bool = false
	var ab_lower: String = ability.to_lower()

	for raw_entry: Variant in conditions:
		var cname: String = ""
		if raw_entry is String:
			cname = raw_entry as String
		elif raw_entry is Dictionary:
			cname = str((raw_entry as Dictionary).get("name", ""))
		if cname.is_empty():
			continue
		var rules_raw: Variant = CONDITIONS.get(cname, null)
		if rules_raw == null:
			continue
		var r: Dictionary = rules_raw as Dictionary
		match roll_type:
			"attack_made":
				if bool(r.get("attack_made_adv", false)):
					adv = true
				if bool(r.get("attack_made_disadv", false)):
					disadv = true
			"attack_rcvd":
				if bool(r.get("attack_rcvd_adv", false)):
					adv = true
				if bool(r.get("attack_rcvd_disadv", false)):
					disadv = true
			"save":
				var auto_fails: Array = r.get("save_auto_fail", []) as Array
				if ab_lower in auto_fails:
					auto_fail = true
				var save_disadvs: Array = r.get("save_disadv", []) as Array
				if ab_lower in save_disadvs:
					disadv = true
			"check":
				if bool(r.get("check_disadv", false)):
					disadv = true

	return {"advantage": adv, "disadvantage": disadv, "auto_fail": auto_fail}
