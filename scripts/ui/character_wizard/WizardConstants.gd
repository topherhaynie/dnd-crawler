extends RefCounted
class_name WizardConstants

# -----------------------------------------------------------------------------
# WizardConstants — shared constants for the character creation wizard.
# -----------------------------------------------------------------------------

const STEP_TITLES: Array = [
	"Step 1 of 8 — Name & Race",
	"Step 2 of 8 — Class & Level",
	"Step 3 of 8 — Ability Scores",
	"Step 4 of 8 — Class Features",
	"Step 5 of 8 — Background",
	"Step 6 of 8 — Proficiencies",
	"Step 7 of 8 — Review",
	"Step 8 of 8 — Finalize & Override",
]

const STANDARD_ARRAY: Array[int] = [15, 14, 13, 12, 10, 8]
const ABILITY_NAMES: Array = ["Strength", "Dexterity", "Constitution",
		"Intelligence", "Wisdom", "Charisma"]
const ABILITY_KEYS: Array = ["str", "dex", "con", "int", "wis", "cha"]
const POINT_BUY_TABLE: Dictionary = {
	8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9
}
const POINT_BUY_BUDGET: int = 27
const BACKGROUNDS: Array = [
	"Acolyte", "Charlatan", "Criminal", "Entertainer", "Folk Hero",
	"Guild Artisan", "Hermit", "Noble", "Outlander", "Sage",
	"Sailor", "Soldier", "Urchin",
]

## D&D 5e SRD skill list (used by BACKGROUND_PROFS and CLASS_SKILL_PROFS).
const ALL_SKILLS: Array = [
	"Acrobatics", "Animal Handling", "Arcana", "Athletics", "Deception",
	"History", "Insight", "Intimidation", "Investigation", "Medicine",
	"Nature", "Perception", "Performance", "Persuasion", "Religion",
	"Sleight of Hand", "Stealth", "Survival",
]

## Automatic skill proficiencies granted by each 2014 SRD background.
const BACKGROUND_PROFS: Dictionary = {
	"Acolyte": ["Insight", "Religion"],
	"Charlatan": ["Deception", "Sleight of Hand"],
	"Criminal": ["Deception", "Stealth"],
	"Entertainer": ["Acrobatics", "Performance"],
	"Folk Hero": ["Animal Handling", "Survival"],
	"Guild Artisan": ["Insight", "Persuasion"],
	"Hermit": ["Medicine", "Religion"],
	"Noble": ["History", "Persuasion"],
	"Outlander": ["Athletics", "Survival"],
	"Sage": ["Arcana", "History"],
	"Sailor": ["Athletics", "Perception"],
	"Soldier": ["Athletics", "Intimidation"],
	"Urchin": ["Sleight of Hand", "Stealth"],
}

## Class skill proficiency options: how many to choose and from which list.
## Empty "from" means the player may choose from any skill.
const CLASS_SKILL_PROFS: Dictionary = {
	"barbarian": {"count": 2, "from": ["Animal Handling", "Athletics", "Intimidation", "Nature", "Perception", "Survival"]},
	"bard": {"count": 3, "from": []},
	"cleric": {"count": 2, "from": ["History", "Insight", "Medicine", "Persuasion", "Religion"]},
	"druid": {"count": 2, "from": ["Arcana", "Animal Handling", "Insight", "Medicine", "Nature", "Perception", "Religion", "Survival"]},
	"fighter": {"count": 2, "from": ["Acrobatics", "Animal Handling", "Athletics", "History", "Insight", "Intimidation", "Perception", "Survival"]},
	"monk": {"count": 2, "from": ["Acrobatics", "Athletics", "History", "Insight", "Religion", "Stealth"]},
	"paladin": {"count": 2, "from": ["Athletics", "Insight", "Intimidation", "Medicine", "Persuasion", "Religion"]},
	"ranger": {"count": 3, "from": ["Animal Handling", "Athletics", "Insight", "Investigation", "Nature", "Perception", "Stealth", "Survival"]},
	"rogue": {"count": 4, "from": ["Acrobatics", "Athletics", "Deception", "Insight", "Intimidation", "Investigation", "Perception", "Performance", "Persuasion", "Sleight of Hand", "Stealth"]},
	"sorcerer": {"count": 2, "from": ["Arcana", "Deception", "Insight", "Intimidation", "Persuasion", "Religion"]},
	"warlock": {"count": 2, "from": ["Arcana", "Deception", "History", "Intimidation", "Investigation", "Nature", "Religion"]},
	"wizard": {"count": 2, "from": ["Arcana", "History", "Insight", "Investigation", "Medicine", "Religion"]},
}

## Per-class spellcasting and subclass data (SRD-only options).
const CLASS_DATA: Dictionary = {
	"barbarian": {
		"cantrips": 0, "spell_type": "",
		"subclass_level": 3, "subclass_type": "Primal Path",
		"subclasses": ["Path of the Berserker", "Path of the Totem Warrior"],
	},
	"bard": {
		"cantrips": 2, "spell_type": "known", "spells_known_at_1": 4,
		"subclass_level": 3, "subclass_type": "Bard College",
		"subclasses": ["College of Lore", "College of Valor"],
	},
	"cleric": {
		"cantrips": 3, "spell_type": "prepared",
		"subclass_level": 1, "subclass_type": "Divine Domain",
		"subclasses": [
			"Knowledge Domain", "Life Domain", "Light Domain",
			"Nature Domain", "Tempest Domain", "Trickery Domain", "War Domain",
		],
	},
	"druid": {
		"cantrips": 2, "spell_type": "prepared",
		"subclass_level": 2, "subclass_type": "Druid Circle",
		"subclasses": ["Circle of the Land", "Circle of the Moon"],
	},
	"fighter": {
		"cantrips": 0, "spell_type": "",
		"subclass_level": 3, "subclass_type": "Martial Archetype",
		"subclasses": ["Battle Master", "Champion", "Eldritch Knight"],
		"fighting_style_level": 1,
		"fighting_styles": ["Archery", "Defense", "Dueling", "Great Weapon Fighting", "Protection", "Two-Weapon Fighting"],
	},
	"monk": {
		"cantrips": 0, "spell_type": "",
		"subclass_level": 3, "subclass_type": "Monastic Tradition",
		"subclasses": ["Way of the Open Hand", "Way of Shadow", "Way of the Four Elements"],
	},
	"paladin": {
		"cantrips": 0, "spell_type": "prepared",
		"subclass_level": 3, "subclass_type": "Sacred Oath",
		"subclasses": ["Oath of Devotion", "Oath of the Ancients", "Oath of Vengeance"],
		"fighting_style_level": 2,
		"fighting_styles": ["Defense", "Dueling", "Great Weapon Fighting", "Protection"],
	},
	"ranger": {
		"cantrips": 0, "spell_type": "known", "spells_known_at_1": 2,
		"subclass_level": 3, "subclass_type": "Ranger Archetype",
		"subclasses": ["Beast Master", "Hunter"],
		"fighting_style_level": 2,
		"fighting_styles": ["Archery", "Defense", "Dueling", "Two-Weapon Fighting"],
		"favored_enemy_level": 1,
		"natural_explorer_level": 1,
	},
	"rogue": {
		"cantrips": 0, "spell_type": "",
		"subclass_level": 3, "subclass_type": "Roguish Archetype",
		"subclasses": ["Arcane Trickster", "Assassin", "Thief"],
		"expertise_level": 1,
		"expertise_count": 2,
		"skills_list": [
			"Acrobatics", "Athletics", "Deception", "Insight", "Intimidation",
			"Investigation", "Perception", "Performance", "Persuasion",
			"Sleight of Hand", "Stealth",
		],
	},
	"sorcerer": {
		"cantrips": 4, "spell_type": "known", "spells_known_at_1": 2,
		"subclass_level": 1, "subclass_type": "Sorcerous Origin",
		"subclasses": ["Draconic Bloodline", "Wild Magic"],
	},
	"warlock": {
		"cantrips": 2, "spell_type": "known", "spells_known_at_1": 2,
		"subclass_level": 1, "subclass_type": "Otherworldly Patron",
		"subclasses": ["The Archfey", "The Fiend", "The Great Old One"],
		"invocations_level": 2,
		"invocations": [
			"Agonizing Blast", "Armor of Shadows", "Beast Speech", "Beguiling Influence",
			"Devil's Sight", "Eldritch Sight", "Eldritch Spear", "Eyes of the Rune Keeper",
			"Fiendish Vigor", "Gaze of Two Minds", "Mask of Many Faces", "Misty Visions",
			"Repelling Blast", "Thief of Five Fates", "Thirsting Blade", "Voice of the Chain Master",
		],
		"invocation_count_2": 2,
		"pact_boon_level": 3,
	},
	"wizard": {
		"cantrips": 3, "spell_type": "spellbook", "spellbook_size": 6,
		"subclass_level": 2, "subclass_type": "Arcane Tradition",
		"subclasses": [
			"School of Abjuration", "School of Conjuration", "School of Divination",
			"School of Enchantment", "School of Evocation", "School of Illusion",
			"School of Necromancy", "School of Transmutation",
		],
	},
}

## Subrace options keyed by base race name.
const SUBRACE_DATA: Dictionary = {
	"Dwarf": [
		{
			"name": "Hill Dwarf",
			"asi": "Wisdom +1",
			"asi_keys": [ {"key": "wis", "bonus": 1}],
			"hp_bonus_per_level": 1,
			"traits": ["Dwarven Toughness: HP maximum +1, and +1 more per level gained."],
		},
	],
	"Elf": [
		{
			"name": "High Elf",
			"asi": "Intelligence +1",
			"asi_keys": [ {"key": "int", "bonus": 1}],
			"choose_cantrip": true,
			"choose_language": true,
			"prof_weapons": ["Longsword", "Shortsword", "Shortbow", "Longbow"],
			"traits": [
				"Cantrip: Know one Wizard cantrip of your choice.",
				"Extra Language: One additional language of your choice.",
			],
		},
		{
			"name": "Wood Elf",
			"asi": "Wisdom +1",
			"asi_keys": [ {"key": "wis", "bonus": 1}],
			"speed": 35,
			"prof_weapons": ["Longsword", "Shortsword", "Shortbow", "Longbow"],
			"traits": [
				"Fleet of Foot: Base walking speed becomes 35 ft.",
				"Mask of the Wild: Can attempt to Hide when only lightly obscured by natural phenomena.",
			],
		},
		{
			"name": "Dark Elf (Drow)",
			"asi": "Charisma +1",
			"asi_keys": [ {"key": "cha", "bonus": 1}],
			"darkvision": 120,
			"prof_weapons": ["Rapier", "Shortsword", "Hand Crossbow"],
			"racial_cantrips": ["dancing-lights"],
			"racial_spells": [
				{"index": "faerie-fire", "level": 1, "unlocked_at_level": 3},
				{"index": "darkness", "level": 2, "unlocked_at_level": 5},
			],
			"traits": [
				"Superior Darkvision: 120 ft. (replaces base 60 ft.)",
				"Sunlight Sensitivity: Disadvantage on attack rolls and Perception checks in sunlight.",
				"Drow Magic: Dancing Lights cantrip; Faerie Fire at level 3; Darkness at level 5 (CHA).",
			],
		},
	],
	"Halfling": [
		{
			"name": "Lightfoot",
			"asi": "Charisma +1",
			"asi_keys": [ {"key": "cha", "bonus": 1}],
			"traits": ["Naturally Stealthy: Can attempt to Hide when obscured by a Medium or larger creature."],
		},
		{
			"name": "Stout",
			"asi": "Constitution +1",
			"asi_keys": [ {"key": "con", "bonus": 1}],
			"damage_resist": ["poison"],
			"traits": ["Stout Resilience: Advantage on saves vs. poison; resistance to poison damage."],
		},
	],
	"Gnome": [
		{
			"name": "Rock Gnome",
			"asi": "Constitution +1",
			"asi_keys": [ {"key": "con", "bonus": 1}],
			"traits": [
				"Artificer's Lore: Double proficiency on History for magic items / tech.",
				"Tinker: Construct tiny clockwork devices using thieves' tools.",
			],
		},
		{
			"name": "Forest Gnome",
			"asi": "Dexterity +1",
			"asi_keys": [ {"key": "dex", "bonus": 1}],
			"racial_cantrips": ["minor-illusion"],
			"traits": [
				"Natural Illusionist: Know Minor Illusion cantrip (Intelligence).",
				"Speak with Small Beasts: Communicate simple ideas with Tiny or Small beasts.",
			],
		},
	],
}

## Full race mechanical data.
const RACE_DATA: Dictionary = {
	"Dwarf": {
		"asi_keys": [ {"key": "con", "bonus": 2}],
		"darkvision": 60,
		"languages": ["Common", "Dwarvish"],
		"prof_weapons": ["Battleaxe", "Handaxe", "Light Hammer", "Warhammer"],
		"features": [
			{"name": "Dwarven Resilience", "desc": "Advantage on saving throws vs. poison; resistance to poison damage."},
			{"name": "Stonecunning", "desc": "Double proficiency on History checks about stonework."},
			{"name": "Dwarven Combat Training", "desc": "Proficiency with battleaxe, handaxe, light hammer, and warhammer."},
			{"name": "Tool Proficiency", "desc": "Proficiency with one artisan's tool of your choice."},
		],
	},
	"Elf": {
		"asi_keys": [ {"key": "dex", "bonus": 2}],
		"darkvision": 60,
		"languages": ["Common", "Elvish"],
		"prof_skills": ["Perception"],
		"features": [
			{"name": "Fey Ancestry", "desc": "Advantage on saving throws vs. being charmed; can't be magically put to sleep."},
			{"name": "Trance", "desc": "Elves don't sleep; instead meditate 4 hours (equivalent to 8-hour rest)."},
			{"name": "Keen Senses", "desc": "Proficiency in the Perception skill."},
		],
	},
	"Halfling": {
		"asi_keys": [ {"key": "dex", "bonus": 2}],
		"darkvision": 0,
		"languages": ["Common", "Halfling"],
		"features": [
			{"name": "Lucky", "desc": "When you roll a 1 on a d20 for attack, ability check, or save, reroll and use the new roll."},
			{"name": "Brave", "desc": "Advantage on saving throws against being frightened."},
			{"name": "Halfling Nimbleness", "desc": "Can move through the space of any creature that is a size larger than yours."},
		],
	},
	"Human": {
		"asi_keys": [
			{"key": "str", "bonus": 1}, {"key": "dex", "bonus": 1}, {"key": "con", "bonus": 1},
			{"key": "int", "bonus": 1}, {"key": "wis", "bonus": 1}, {"key": "cha", "bonus": 1},
		],
		"darkvision": 0,
		"languages": ["Common"],
		"choose_languages": 1,
		"features": [],
	},
	"Dragonborn": {
		"asi_keys": [ {"key": "str", "bonus": 2}, {"key": "cha", "bonus": 1}],
		"darkvision": 0,
		"languages": ["Common", "Draconic"],
		"choose_draconic_ancestry": true,
		"features": [
			{"name": "Draconic Ancestry", "desc": "Choose a dragon type; determines breath weapon damage type and damage resistance."},
			{"name": "Breath Weapon", "desc": "Use action to exhale destructive energy (recharges on short or long rest). DC = 8 + CON mod + proficiency."},
			{"name": "Damage Resistance", "desc": "Resistance to the damage type of your Draconic Ancestry."},
		],
	},
	"Gnome": {
		"asi_keys": [ {"key": "int", "bonus": 2}],
		"darkvision": 60,
		"languages": ["Common", "Gnomish"],
		"features": [
			{"name": "Gnome Cunning", "desc": "Advantage on all INT, WIS, and CHA saving throws against magic."},
		],
	},
	"Half-Elf": {
		"asi_keys": [ {"key": "cha", "bonus": 2}],
		"asi_choose_two": true,
		"darkvision": 60,
		"languages": ["Common", "Elvish"],
		"choose_language": true,
		"free_skill_choices": 2,
		"features": [
			{"name": "Fey Ancestry", "desc": "Advantage on saving throws vs. being charmed; can't be magically put to sleep."},
			{"name": "Skill Versatility", "desc": "Proficiency in two skills of your choice."},
		],
	},
	"Half-Orc": {
		"asi_keys": [ {"key": "str", "bonus": 2}, {"key": "con", "bonus": 1}],
		"darkvision": 60,
		"languages": ["Common", "Orc"],
		"prof_skills": ["Intimidation"],
		"features": [
			{"name": "Menacing", "desc": "Proficiency in the Intimidation skill."},
			{"name": "Relentless Endurance", "desc": "When reduced to 0 HP (not killed outright), drop to 1 HP instead. 1/long rest."},
			{"name": "Savage Attacks", "desc": "On critical hit with melee weapon, roll one extra weapon damage die."},
		],
	},
	"Tiefling": {
		"asi_keys": [ {"key": "int", "bonus": 1}, {"key": "cha", "bonus": 2}],
		"darkvision": 60,
		"languages": ["Common", "Infernal"],
		"damage_resist": ["fire"],
		"racial_cantrips": ["thaumaturgy"],
		"racial_spells": [
			{"index": "hellish-rebuke", "level": 1, "unlocked_at_level": 3},
			{"index": "darkness", "level": 2, "unlocked_at_level": 5},
		],
		"features": [
			{"name": "Hellish Resistance", "desc": "Resistance to fire damage."},
			{"name": "Infernal Legacy", "desc": "Thaumaturgy cantrip; Hellish Rebuke (2nd level) at level 3; Darkness at level 5. CHA is the spellcasting ability."},
		],
	},
}

## Level-aware helpers ──────────────────────────────────────────────────────

## Total cantrips known for a class at a given character level.
static func cantrips_for_level(class_key: String, lvl: int) -> int:
	var i: int = clampi(lvl, 1, 20) - 1
	match class_key:
		"bard": return [2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4][i]
		"cleric": return [3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5][i]
		"druid": return [2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4][i]
		"sorcerer": return [4, 4, 4, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6][i]
		"warlock": return [2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4][i]
		"wizard": return [3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5][i]
		_:
			var cd_v: Variant = CLASS_DATA.get(class_key)
			if cd_v is Dictionary:
				return int((cd_v as Dictionary).get("cantrips", 0))
			return 0


## Highest spell level this class can cast at the given character level.
static func max_spell_level_for_class(class_key: String, lvl: int) -> int:
	var l: int = clampi(lvl, 0, 20)
	const FULL: Array[int] = [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 9, 9]
	const HALF: Array[int] = [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]
	const WRLK: Array[int] = [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]
	match class_key:
		"bard", "cleric", "druid", "sorcerer", "wizard": return FULL[l]
		"paladin", "ranger": return HALF[l]
		"warlock": return WRLK[l]
		_: return 0


## Total spells known for "known" caster classes at the given character level.
static func spells_known_for_level(class_key: String, lvl: int) -> int:
	var i: int = clampi(lvl, 1, 20) - 1
	match class_key:
		"bard": return [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 19, 19, 20, 22, 22, 22][i]
		"ranger": return [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 14][i]
		"sorcerer": return [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 12, 13, 13, 14, 14, 15, 15, 15, 15][i]
		"warlock": return [2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15][i]
		_:
			var cd_v: Variant = CLASS_DATA.get(class_key)
			if cd_v is Dictionary:
				return int((cd_v as Dictionary).get("spells_known_at_1", 0))
			return 0


## Wizard spellbook total entries available at character level.
static func spellbook_size_for_level(lvl: int) -> int:
	return 6 + (clampi(lvl, 1, 20) - 1) * 2


## ASI character levels for a given class, ascending order.
static func asi_levels_for_class(class_key: String) -> Array:
	match class_key:
		"fighter": return [4, 6, 8, 12, 14, 16, 19]
		"rogue": return [4, 8, 10, 12, 16, 19]
		_: return [4, 8, 12, 16, 19]


## Number of ASIs earned by this class at the given level.
static func asi_count_for(class_key: String, lvl: int) -> int:
	var count: int = 0
	for l: int in asi_levels_for_class(class_key):
		if lvl >= l:
			count += 1
	return count


## Ordinal string for a spell level (1 → "1st", 2 → "2nd", etc.).
static func spell_level_ordinal(lvl: int) -> String:
	match lvl:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return "%dth" % lvl


static func proficiency_bonus_for_level(lvl: int) -> int:
	return int(ceil(float(lvl) / 4.0)) + 1


## D&D 5e XP thresholds — minimum XP required for each character level.
## Index 0 = level 1, index 19 = level 20.
const XP_THRESHOLDS: Array = [
	0, # Level 1
	300, # Level 2
	900, # Level 3
	2700, # Level 4
	6500, # Level 5
	14000, # Level 6
	23000, # Level 7
	34000, # Level 8
	48000, # Level 9
	64000, # Level 10
	85000, # Level 11
	100000, # Level 12
	120000, # Level 13
	140000, # Level 14
	165000, # Level 15
	195000, # Level 16
	225000, # Level 17
	265000, # Level 18
	305000, # Level 19
	355000, # Level 20
]


## D&D 5e CR → XP reward table.
const CR_XP_TABLE: Dictionary = {
	0.0: 10, 0.125: 25, 0.25: 50, 0.5: 100,
	1.0: 200, 2.0: 450, 3.0: 700, 4.0: 1100,
	5.0: 1800, 6.0: 2300, 7.0: 2900, 8.0: 3900,
	9.0: 5000, 10.0: 5900, 11.0: 7200, 12.0: 8400,
	13.0: 10000, 14.0: 11500, 15.0: 13000, 16.0: 15000,
	17.0: 18000, 18.0: 20000, 19.0: 22000, 20.0: 25000,
	21.0: 33000, 22.0: 41000, 23.0: 50000, 24.0: 62000,
	25.0: 75000, 26.0: 90000, 27.0: 105000, 28.0: 120000,
	29.0: 135000, 30.0: 155000,
}


## Return the XP reward for a given challenge rating.
static func cr_to_xp(cr: float) -> int:
	var exact: Variant = CR_XP_TABLE.get(cr, null)
	if exact != null:
		return int(exact)
	# Nearest lower CR fallback.
	var best_cr: float = 0.0
	for key: Variant in CR_XP_TABLE.keys():
		var k: float = float(key)
		if k <= cr and k > best_cr:
			best_cr = k
	return int(CR_XP_TABLE.get(best_cr, 0))


## Return the level a character should be at given their current XP.
static func level_for_xp(xp_val: int) -> int:
	for i: int in range(XP_THRESHOLDS.size() - 1, -1, -1):
		if xp_val >= int(XP_THRESHOLDS[i]):
			return i + 1
	return 1


## Return the XP threshold for the given level.
static func xp_for_level(lvl: int) -> int:
	var idx: int = clampi(lvl - 1, 0, XP_THRESHOLDS.size() - 1)
	return int(XP_THRESHOLDS[idx])


## HP gained on level-up: hit_die average + CON modifier (minimum 1).
static func hp_increase_average(hit_die: int, con_modifier: int) -> int:
	return maxi(1, int(ceil(float(hit_die) / 2.0)) + 1 + con_modifier)


## ── Multiclass spell slot computation (5e PHB rules) ─────────────────────

## Caster-level weight for a class.  Returns 1.0 for full, 0.5 for half,
## 0.334 for third, 0.0 for non-casters, and -1.0 for warlock (pact magic).
static func caster_weight(class_key: String) -> float:
	match class_key:
		"bard", "cleric", "druid", "sorcerer", "wizard":
			return 1.0
		"paladin", "ranger":
			return 0.5
		"warlock":
			return -1.0 # separate pact magic
		_:
			# Eldritch Knight (fighter) and Arcane Trickster (rogue) are 1/3 casters,
			# but that requires subclass knowledge. For the wizard builder we treat
			# base fighter/rogue as non-casters; subclass spell selection is handled
			# in the class features step already.
			return 0.0


## Standard 5e full-caster spell slot table indexed by total caster level (0-20).
## Entry format: [1st, 2nd, 3rd, 4th, 5th, 6th, 7th, 8th, 9th].
const SPELL_SLOT_TABLE: Array = [
	[0, 0, 0, 0, 0, 0, 0, 0, 0], # caster level 0
	[2, 0, 0, 0, 0, 0, 0, 0, 0], # 1
	[3, 0, 0, 0, 0, 0, 0, 0, 0], # 2
	[4, 2, 0, 0, 0, 0, 0, 0, 0], # 3
	[4, 3, 0, 0, 0, 0, 0, 0, 0], # 4
	[4, 3, 2, 0, 0, 0, 0, 0, 0], # 5
	[4, 3, 3, 0, 0, 0, 0, 0, 0], # 6
	[4, 3, 3, 1, 0, 0, 0, 0, 0], # 7
	[4, 3, 3, 2, 0, 0, 0, 0, 0], # 8
	[4, 3, 3, 3, 1, 0, 0, 0, 0], # 9
	[4, 3, 3, 3, 2, 0, 0, 0, 0], # 10
	[4, 3, 3, 3, 2, 1, 0, 0, 0], # 11
	[4, 3, 3, 3, 2, 1, 0, 0, 0], # 12
	[4, 3, 3, 3, 2, 1, 1, 0, 0], # 13
	[4, 3, 3, 3, 2, 1, 1, 0, 0], # 14
	[4, 3, 3, 3, 2, 1, 1, 1, 0], # 15
	[4, 3, 3, 3, 2, 1, 1, 1, 0], # 16
	[4, 3, 3, 3, 2, 1, 1, 1, 1], # 17
	[4, 3, 3, 3, 3, 1, 1, 1, 1], # 18
	[4, 3, 3, 3, 3, 2, 1, 1, 1], # 19
	[4, 3, 3, 3, 3, 2, 2, 1, 1], # 20
]

## Warlock pact magic slots by warlock level.
## Entry format: [slot_count, slot_level].
const WARLOCK_PACT_SLOTS: Array = [
	[0, 0], # level 0
	[1, 1], # 1
	[2, 1], # 2
	[2, 2], # 3
	[2, 2], # 4
	[2, 3], # 5
	[2, 3], # 6
	[2, 4], # 7
	[2, 4], # 8
	[2, 5], # 9
	[2, 5], # 10
	[3, 5], # 11
	[3, 5], # 12
	[3, 5], # 13
	[3, 5], # 14
	[3, 5], # 15
	[3, 5], # 16
	[4, 5], # 17
	[4, 5], # 18
	[4, 5], # 19
	[4, 5], # 20
]


## Compute spell slots for a classes array [{name, level, subclass}].
## Returns a Dictionary: { 1: count, 2: count, ... 9: count } with
## only non-zero entries.  Warlock pact magic appears as "pact_slots"
## and "pact_slot_level" keys.
static func compute_spell_slots(classes: Array) -> Dictionary:
	var combined_caster_level: float = 0.0
	var warlock_level: int = 0
	for entry_var: Variant in classes:
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var as Dictionary
		var cn: String = str(entry.get("name", "")).to_lower()
		var lv: int = int(entry.get("level", 0))
		var w: float = caster_weight(cn)
		if w < 0.0:
			warlock_level = lv
		elif w > 0.0:
			combined_caster_level += lv * w
	var caster_level: int = int(combined_caster_level)
	caster_level = clampi(caster_level, 0, 20)
	var result: Dictionary = {}
	if caster_level > 0:
		var row: Variant = SPELL_SLOT_TABLE[caster_level]
		if row is Array:
			for i: int in range((row as Array).size()):
				var count: int = int((row as Array)[i])
				if count > 0:
					result[i + 1] = count
	if warlock_level > 0 and warlock_level <= 20:
		var pact: Variant = WARLOCK_PACT_SLOTS[warlock_level]
		if pact is Array and (pact as Array).size() >= 2:
			result["pact_slots"] = int((pact as Array)[0])
			result["pact_slot_level"] = int((pact as Array)[1])
	return result
