extends RefCounted
class_name ClassFeatureTable

# -----------------------------------------------------------------------------
# ClassFeatureTable — Complete 5e SRD class feature progression tables.
#
# Each class maps to an Array of feature entries. Every entry is a Dictionary:
#   level   : int    — character level the feature is gained
#   name    : String — feature name
#   desc    : String — rules description (may contain {placeholders} for scaling)
#   scaling : Dictionary (optional) — keyed by placeholder name, each value is
#             an Array[20] indexed by (level - 1) giving the value at that level.
#             The resolver substitutes these before writing to the statblock.
#   replace : bool (optional) — if true, this entry *replaces* the previous
#             version of the same-named feature instead of stacking. Useful for
#             features that upgrade (e.g. Brutal Critical gaining more dice).
#
# Choice-based features (subclass, fighting style, expertise, invocations, etc.)
# are NOT listed here — they are handled by the wizard's interactive UI and
# assembled in WizardStatblockBuilder separately.
# -----------------------------------------------------------------------------


## Barbarian Rage uses by level (index 0 = level 1).
const _RAGE_USES: Array = [2, 2, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 6, 6, 6, 999]
## Barbarian Rage damage bonus by level.
const _RAGE_DAMAGE: Array = [2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4]

## Monk Martial Arts die by level.
const _MARTIAL_ARTS_DIE: Array = [
	"1d4", "1d4", "1d4", "1d4", "1d6", "1d6", "1d6", "1d6", "1d6", "1d6",
	"1d8", "1d8", "1d8", "1d8", "1d8", "1d8", "1d10", "1d10", "1d10", "1d10",
]

## Monk Unarmored Movement bonus (ft.) by level.
const _UNARMORED_MOVEMENT: Array = [
	0, 10, 10, 10, 10, 15, 15, 15, 20, 20,
	20, 20, 20, 25, 25, 25, 25, 30, 30, 30,
]

## Rogue Sneak Attack dice by level.
const _SNEAK_ATTACK_DICE: Array = [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10]

## Sorcerer Sorcery Points by level.
const _SORCERY_POINTS: Array = [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]

## Wild Shape max CR by level.
const _WILD_SHAPE_CR: Array = [
	"0", "1/4", "1/4", "1/2", "1/2", "1/2", "1/2", "1", "1", "1",
	"1", "1", "1", "1", "1", "1", "1", "1", "1", "1",
]

## Channel Divinity uses by level.
const _CHANNEL_DIVINITY_USES: Array = [
	1, 1, 1, 1, 1, 2, 2, 2, 2, 2,
	2, 2, 2, 2, 2, 2, 2, 3, 3, 3,
]

## Fighter Indomitable uses by level (0 until level 9).
const _INDOMITABLE_USES: Array = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3]

## Fighter extra attacks: 0 until 5, then 1, then 2 at 11, then 3 at 20.
const _FIGHTER_EXTRA_ATTACKS: Array = [0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3]

## Action Surge uses by level.
const _ACTION_SURGE_USES: Array = [0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2]

## Warlock invocation count by level.
const _INVOCATION_COUNT: Array = [0, 2, 2, 2, 3, 3, 3, 4, 4, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7, 8]

## Paladin Lay on Hands pool = 5 * paladin level (computed, not a table).
## Aura range: 10 ft. at 6, 30 ft. at 18.
const _PALADIN_AURA_RANGE: Array = [0, 0, 0, 0, 0, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 30, 30, 30]

## Bardic Inspiration die by level.
const _BARDIC_INSPIRATION_DIE: Array = [
	"d6", "d6", "d6", "d6", "d8", "d8", "d8", "d8", "d8", "d10",
	"d10", "d10", "d10", "d10", "d12", "d12", "d12", "d12", "d12", "d12",
]


# =============================================================================
#  Feature tables per class
# =============================================================================

const BARBARIAN: Array = [
	{
		"level": 1, "name": "Rage",
		"desc": "Bonus action to rage. {uses}/long rest. +{dmg} melee damage. Advantage on STR checks/saves. Resistance to bludgeoning, piercing, and slashing damage. Lasts 1 minute.",
		"scaling": {"uses": _RAGE_USES, "dmg": _RAGE_DAMAGE},
		"replace": true,
	},
	{
		"level": 1, "name": "Unarmored Defense",
		"desc": "While not wearing armor, AC = 10 + DEX modifier + CON modifier. You can use a shield and still gain this benefit.",
	},
	{
		"level": 2, "name": "Reckless Attack",
		"desc": "When you make your first attack on your turn, you can choose to gain advantage on melee weapon attack rolls using STR during this turn, but attack rolls against you have advantage until your next turn.",
	},
	{
		"level": 2, "name": "Danger Sense",
		"desc": "Advantage on DEX saving throws against effects you can see, such as traps and spells. You can't be blinded, deafened, or incapacitated to use this.",
	},
	{
		"level": 5, "name": "Extra Attack",
		"desc": "You can attack twice, instead of once, whenever you take the Attack action on your turn.",
	},
	{
		"level": 5, "name": "Fast Movement",
		"desc": "+10 ft. to speed while not wearing heavy armor.",
	},
	{
		"level": 7, "name": "Feral Instinct",
		"desc": "Advantage on initiative rolls. If surprised, you can still act normally on your first turn if you enter your rage before doing anything else.",
	},
	{
		"level": 9, "name": "Brutal Critical",
		"desc": "Roll 1 additional weapon damage die when determining the extra damage for a critical hit with a melee attack.",
		"replace": true,
	},
	{
		"level": 11, "name": "Relentless Rage",
		"desc": "If you drop to 0 HP while raging and don't die outright, make a DC 10 CON save to drop to 1 HP instead. DC increases by 5 each time until you finish a rest.",
	},
	{
		"level": 13, "name": "Brutal Critical",
		"desc": "Roll 2 additional weapon damage dice when determining the extra damage for a critical hit with a melee attack.",
		"replace": true,
	},
	{
		"level": 15, "name": "Persistent Rage",
		"desc": "Your rage only ends early if you fall unconscious or choose to end it.",
	},
	{
		"level": 17, "name": "Brutal Critical",
		"desc": "Roll 3 additional weapon damage dice when determining the extra damage for a critical hit with a melee attack.",
		"replace": true,
	},
	{
		"level": 18, "name": "Indomitable Might",
		"desc": "If your total for a STR check is less than your STR score, you can use your STR score in place of the total.",
	},
	{
		"level": 20, "name": "Primal Champion",
		"desc": "STR and CON scores increase by 4. Maximum for those scores is now 24.",
	},
]

const BARD: Array = [
	{
		"level": 1, "name": "Bardic Inspiration",
		"desc": "Bonus action, grant one creature within 60 ft. a {die} Bardic Inspiration die (CHA modifier uses per long rest). The creature can add the die to one ability check, attack roll, or saving throw within 10 minutes.",
		"scaling": {"die": _BARDIC_INSPIRATION_DIE},
		"replace": true,
	},
	{
		"level": 2, "name": "Jack of All Trades",
		"desc": "Add half your proficiency bonus (rounded down) to any ability check that doesn't already include your proficiency bonus.",
	},
	{
		"level": 2, "name": "Song of Rest",
		"desc": "During a short rest, you and friendly creatures who can hear your performance regain an extra 1d6 hit points if they spend any Hit Dice.",
	},
	{
		"level": 3, "name": "Expertise",
		"desc": "Choose two skill proficiencies. Your proficiency bonus is doubled for any ability check you make that uses either of the chosen proficiencies. At 10th level, choose two more.",
	},
	{
		"level": 5, "name": "Font of Inspiration",
		"desc": "You regain all expended uses of Bardic Inspiration on a short or long rest (instead of only long rest).",
	},
	{
		"level": 6, "name": "Countercharm",
		"desc": "As an action, start a performance lasting until end of your next turn. During that time, you and friendly creatures within 30 ft. have advantage on saves against being frightened or charmed.",
	},
	{
		"level": 10, "name": "Magical Secrets",
		"desc": "Choose two spells from any class's spell list. These count as bard spells for you and are included in your spells known.",
	},
	{
		"level": 14, "name": "Magical Secrets",
		"desc": "Choose two additional spells from any class's spell list. These count as bard spells for you.",
		"replace": true,
	},
	{
		"level": 18, "name": "Magical Secrets",
		"desc": "Choose two additional spells from any class's spell list. These count as bard spells for you.",
		"replace": true,
	},
	{
		"level": 20, "name": "Superior Inspiration",
		"desc": "When you roll initiative and have no uses of Bardic Inspiration left, you regain one use.",
	},
]

const CLERIC: Array = [
	{
		"level": 1, "name": "Spellcasting",
		"desc": "Prepared caster (WIS). Prepare WIS modifier + cleric level spells each long rest from the cleric spell list.",
	},
	{
		"level": 2, "name": "Channel Divinity",
		"desc": "{uses}/rest. Turn Undead: each undead within 30 ft. must make a WIS save or be turned for 1 minute.",
		"scaling": {"uses": _CHANNEL_DIVINITY_USES},
		"replace": true,
	},
	{
		"level": 5, "name": "Destroy Undead",
		"desc": "When an undead fails its save against Turn Undead, it is instantly destroyed if its CR is 1/2 or lower. Threshold increases at levels 8 (CR 1), 11 (CR 2), 14 (CR 3), 17 (CR 4).",
	},
	{
		"level": 10, "name": "Divine Intervention",
		"desc": "As an action, implore your deity's aid. Roll percentile dice; if you roll equal to or below your cleric level, your deity intervenes. If successful, can't use again for 7 days. At 20th level, it succeeds automatically.",
	},
]

const DRUID: Array = [
	{
		"level": 1, "name": "Druidic",
		"desc": "You know Druidic, the secret language of druids. You can speak it and use it to leave hidden messages.",
	},
	{
		"level": 1, "name": "Spellcasting",
		"desc": "Prepared caster (WIS). Prepare WIS modifier + druid level spells each long rest from the druid spell list.",
	},
	{
		"level": 2, "name": "Wild Shape",
		"desc": "2 uses/short rest. Transform into a beast you have seen with CR {cr} or lower. Lasts hours = half druid level (rounded down). At level 4 you can swim; at level 8 you can fly.",
		"scaling": {"cr": _WILD_SHAPE_CR},
		"replace": true,
	},
	{
		"level": 18, "name": "Timeless Body",
		"desc": "You age more slowly. For every 10 years that pass, your body ages only 1 year.",
	},
	{
		"level": 18, "name": "Beast Spells",
		"desc": "You can perform the somatic and verbal components of druid spells while in Wild Shape form.",
	},
	{
		"level": 20, "name": "Archdruid",
		"desc": "You can use Wild Shape an unlimited number of times. You can ignore the verbal and somatic components of druid spells, as well as any material components that lack a cost and aren't consumed.",
	},
]

const FIGHTER: Array = [
	{
		"level": 1, "name": "Second Wind",
		"desc": "Bonus action: regain 1d10 + fighter level HP. 1 use per short rest.",
	},
	{
		"level": 2, "name": "Action Surge",
		"desc": "Take one additional action on your turn. {uses} use(s) per short rest.",
		"scaling": {"uses": _ACTION_SURGE_USES},
		"replace": true,
	},
	{
		"level": 5, "name": "Extra Attack",
		"desc": "You can attack {attacks} time(s) instead of once whenever you take the Attack action on your turn.",
		"scaling": {"attacks": _FIGHTER_EXTRA_ATTACKS},
		"replace": true,
	},
	{
		"level": 9, "name": "Indomitable",
		"desc": "Reroll a failed saving throw. {uses} use(s) per long rest.",
		"scaling": {"uses": _INDOMITABLE_USES},
		"replace": true,
	},
]

const MONK: Array = [
	{
		"level": 1, "name": "Unarmored Defense",
		"desc": "While wearing no armor and not wielding a shield, AC = 10 + DEX modifier + WIS modifier.",
	},
	{
		"level": 1, "name": "Martial Arts",
		"desc": "While unarmed or wielding monk weapons (and not wearing armor or a shield): use DEX instead of STR for attack/damage rolls; unarmed strike damage is {die}; when you take the Attack action with an unarmed strike or monk weapon, you can make one unarmed strike as a bonus action.",
		"scaling": {"die": _MARTIAL_ARTS_DIE},
		"replace": true,
	},
	{
		"level": 2, "name": "Ki",
		"desc": "{points} ki points per short rest. Flurry of Blows (2 unarmed strikes as bonus action for 1 ki), Patient Defense (Dodge as bonus action for 1 ki), Step of the Wind (Disengage or Dash as bonus action for 1 ki, jump distance doubled).",
		"scaling": {"points": [2, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]},
		"replace": true,
	},
	{
		"level": 2, "name": "Unarmored Movement",
		"desc": "+{bonus} ft. speed while not wearing armor or wielding a shield.",
		"scaling": {"bonus": _UNARMORED_MOVEMENT},
		"replace": true,
	},
	{
		"level": 3, "name": "Deflect Missiles",
		"desc": "Use your reaction to deflect a ranged weapon attack. Reduce damage by 1d10 + DEX modifier + monk level. If reduced to 0, you can catch the missile and spend 1 ki point to make a ranged attack with it.",
	},
	{
		"level": 4, "name": "Slow Fall",
		"desc": "Use your reaction to reduce falling damage by 5 × monk level.",
	},
	{
		"level": 5, "name": "Extra Attack",
		"desc": "You can attack twice, instead of once, whenever you take the Attack action on your turn.",
	},
	{
		"level": 5, "name": "Stunning Strike",
		"desc": "When you hit with a melee weapon attack, spend 1 ki point. The target must succeed on a CON save or be stunned until the end of your next turn.",
	},
	{
		"level": 6, "name": "Ki-Empowered Strikes",
		"desc": "Your unarmed strikes count as magical for the purpose of overcoming resistance and immunity to nonmagical attacks and damage.",
	},
	{
		"level": 7, "name": "Evasion",
		"desc": "When subjected to an effect that allows a DEX save for half damage, you take no damage on a success and half damage on a failure.",
	},
	{
		"level": 7, "name": "Stillness of Mind",
		"desc": "Use your action to end one effect on yourself that is causing you to be charmed or frightened.",
	},
	{
		"level": 10, "name": "Purity of Body",
		"desc": "You are immune to disease and poison.",
	},
	{
		"level": 13, "name": "Tongue of the Sun and Moon",
		"desc": "You learn to touch the ki of other minds so that you understand all spoken languages. Any creature that can understand a language can understand what you say.",
	},
	{
		"level": 14, "name": "Diamond Soul",
		"desc": "Proficiency in all saving throws. When you fail a save, you can spend 1 ki point to reroll it and take the second result.",
	},
	{
		"level": 15, "name": "Timeless Body",
		"desc": "You suffer none of the frailty of old age and can't be aged magically. You no longer need food or water.",
	},
	{
		"level": 18, "name": "Empty Body",
		"desc": "Spend 4 ki points to become invisible for 1 minute (also resistance to all damage except force). Spend 8 ki points to cast Astral Projection without material components.",
	},
	{
		"level": 20, "name": "Perfect Self",
		"desc": "When you roll initiative and have no ki points remaining, you regain 4 ki points.",
	},
]

const PALADIN: Array = [
	{
		"level": 1, "name": "Divine Sense",
		"desc": "As an action, detect celestials, fiends, and undead within 60 ft. that are not behind total cover. Also detect consecrated or desecrated ground. Uses: 1 + CHA modifier per long rest.",
	},
	{
		"level": 1, "name": "Lay on Hands",
		"desc": "Touch to restore HP from a pool of {pool} hit points per long rest. Alternatively, spend 5 pool points to cure one disease or neutralize one poison.",
		"scaling": {"pool": [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]},
		"replace": true,
	},
	{
		"level": 2, "name": "Divine Smite",
		"desc": "When you hit with a melee weapon attack, expend one spell slot to deal 2d8 radiant damage to the target, plus 1d8 for each slot level above 1st (max 5d8). +1d8 extra against undead and fiends.",
	},
	{
		"level": 2, "name": "Spellcasting",
		"desc": "Prepared caster (CHA). Prepare CHA modifier + half paladin level (rounded down) spells from the paladin spell list each long rest.",
	},
	{
		"level": 5, "name": "Extra Attack",
		"desc": "You can attack twice, instead of once, whenever you take the Attack action on your turn.",
	},
	{
		"level": 6, "name": "Aura of Protection",
		"desc": "You and friendly creatures within {range} ft. gain a bonus equal to your CHA modifier (minimum +1) to all saving throws while you are conscious.",
		"scaling": {"range": _PALADIN_AURA_RANGE},
		"replace": true,
	},
	{
		"level": 10, "name": "Aura of Courage",
		"desc": "You and friendly creatures within {range} ft. can't be frightened while you are conscious.",
		"scaling": {"range": _PALADIN_AURA_RANGE},
		"replace": true,
	},
	{
		"level": 11, "name": "Improved Divine Smite",
		"desc": "Whenever you hit a creature with a melee weapon, the creature takes an extra 1d8 radiant damage.",
	},
	{
		"level": 14, "name": "Cleansing Touch",
		"desc": "As an action, end one spell on yourself or one willing creature you touch. Uses: CHA modifier per long rest (minimum 1).",
	},
]

const RANGER: Array = [
	{
		"level": 1, "name": "Favored Enemy",
		"desc": "Advantage on WIS (Survival) checks to track your favored enemies, and INT checks to recall information about them. You also learn one language of your choice spoken by your favored enemies.",
	},
	{
		"level": 1, "name": "Natural Explorer",
		"desc": "In your favored terrain: difficult terrain doesn't slow your group's travel; you can't become lost except by magical means; you remain alert to danger even while foraging, navigating, or tracking; you move stealthily at normal pace (alone); find twice as much food when foraging; and learn exact numbers, sizes, and how long ago creatures passed through the area when tracking.",
	},
	{
		"level": 2, "name": "Spellcasting",
		"desc": "Known caster (WIS). You know a number of ranger spells chosen from the ranger spell list.",
	},
	{
		"level": 3, "name": "Primeval Awareness",
		"desc": "Expend one spell slot to sense whether aberrations, celestials, dragons, elementals, fey, fiends, or undead are within 1 mile (or 6 miles in favored terrain). Doesn't reveal location or number.",
	},
	{
		"level": 5, "name": "Extra Attack",
		"desc": "You can attack twice, instead of once, whenever you take the Attack action on your turn.",
	},
	{
		"level": 8, "name": "Land's Stride",
		"desc": "Moving through nonmagical difficult terrain costs no extra movement. You can also pass through nonmagical plants without being slowed or taking damage. Advantage on saves against magically created or manipulated plants.",
	},
	{
		"level": 10, "name": "Hide in Plain Sight",
		"desc": "Spend 1 minute creating camouflage. While remaining still, +10 to Stealth checks. Must reapply if you move or take an action/reaction.",
	},
	{
		"level": 14, "name": "Vanish",
		"desc": "You can use the Hide action as a bonus action. You can't be tracked by nonmagical means unless you choose to leave a trail.",
	},
	{
		"level": 18, "name": "Feral Senses",
		"desc": "No disadvantage on attack rolls against creatures you can't see. You are aware of the location of any invisible creature within 30 ft., provided it isn't hidden from you and you aren't blinded or deafened.",
	},
	{
		"level": 20, "name": "Foe Slayer",
		"desc": "Once per turn, add your WIS modifier to the attack roll or the damage roll of an attack you make against one of your favored enemies.",
	},
]

const ROGUE: Array = [
	{
		"level": 1, "name": "Sneak Attack",
		"desc": "{dice}d6 extra damage once per turn when you hit with a finesse or ranged weapon and have advantage on the attack roll, or another enemy of the target is within 5 ft. of it.",
		"scaling": {"dice": _SNEAK_ATTACK_DICE},
		"replace": true,
	},
	{
		"level": 1, "name": "Thieves' Cant",
		"desc": "You know thieves' cant, a secret mix of dialect, jargon, and code. It takes 4× longer to convey a message this way than speaking plainly. You can also understand hidden signs and symbols.",
	},
	{
		"level": 2, "name": "Cunning Action",
		"desc": "Bonus action: Dash, Disengage, or Hide.",
	},
	{
		"level": 5, "name": "Uncanny Dodge",
		"desc": "When an attacker you can see hits you with an attack, you can use your reaction to halve the attack's damage against you.",
	},
	{
		"level": 7, "name": "Evasion",
		"desc": "When subjected to an effect that allows a DEX save for half damage, you take no damage on a success and half damage on a failure.",
	},
	{
		"level": 11, "name": "Reliable Talent",
		"desc": "When you make an ability check that lets you add your proficiency bonus, treat any d20 roll of 9 or lower as a 10.",
	},
	{
		"level": 14, "name": "Blindsense",
		"desc": "If you can hear, you are aware of the location of any hidden or invisible creature within 10 ft. of you.",
	},
	{
		"level": 15, "name": "Slippery Mind",
		"desc": "You gain proficiency in WIS saving throws.",
	},
	{
		"level": 18, "name": "Elusive",
		"desc": "No attack roll has advantage against you while you aren't incapacitated.",
	},
	{
		"level": 20, "name": "Stroke of Luck",
		"desc": "If your attack misses, you can turn the miss into a hit. Alternatively, if you fail an ability check, treat the d20 roll as a 20. 1 use per short rest.",
	},
]

const SORCERER: Array = [
	{
		"level": 1, "name": "Spellcasting",
		"desc": "Known caster (CHA). You know a number of sorcerer spells chosen from the sorcerer spell list.",
	},
	{
		"level": 2, "name": "Font of Magic",
		"desc": "{points} sorcery points per long rest. You can create spell slots by spending sorcery points, or sacrifice spell slots to gain sorcery points.",
		"scaling": {"points": _SORCERY_POINTS},
		"replace": true,
	},
	{
		"level": 3, "name": "Metamagic",
		"desc": "Choose 2 Metamagic options (additional at levels 10 and 17). You can use only one Metamagic option on a spell unless otherwise noted. Options include: Careful, Distant, Empowered, Extended, Heightened, Quickened, Subtle, Twinned Spell.",
	},
	{
		"level": 20, "name": "Sorcerous Restoration",
		"desc": "You regain 4 sorcery points whenever you finish a short rest.",
	},
]

const WARLOCK: Array = [
	{
		"level": 1, "name": "Pact Magic",
		"desc": "Known caster (CHA). Spell slots recharge on a short or long rest. All slots are always the highest available level.",
	},
	{
		"level": 2, "name": "Eldritch Invocations",
		"desc": "You know {count} eldritch invocations of your choice. Some invocations have prerequisites.",
		"scaling": {"count": _INVOCATION_COUNT},
		"replace": true,
	},
	{
		"level": 11, "name": "Mystic Arcanum (6th level)",
		"desc": "Choose one 6th-level warlock spell as an arcanum. You can cast it once per long rest without expending a spell slot.",
	},
	{
		"level": 13, "name": "Mystic Arcanum (7th level)",
		"desc": "Choose one 7th-level warlock spell as an arcanum. You can cast it once per long rest without expending a spell slot.",
	},
	{
		"level": 15, "name": "Mystic Arcanum (8th level)",
		"desc": "Choose one 8th-level warlock spell as an arcanum. You can cast it once per long rest without expending a spell slot.",
	},
	{
		"level": 17, "name": "Mystic Arcanum (9th level)",
		"desc": "Choose one 9th-level warlock spell as an arcanum. You can cast it once per long rest without expending a spell slot.",
	},
	{
		"level": 20, "name": "Eldritch Master",
		"desc": "Spend 1 minute entreating your patron to regain all Pact Magic spell slots. 1 use per long rest.",
	},
]

const WIZARD: Array = [
	{
		"level": 1, "name": "Spellcasting",
		"desc": "Spellbook caster (INT). Prepare INT modifier + wizard level spells from your spellbook each long rest.",
	},
	{
		"level": 1, "name": "Arcane Recovery",
		"desc": "Once per day during a short rest, recover spell slots with a combined level equal to or less than half your wizard level (rounded up). None of the slots can be 6th level or higher.",
	},
	{
		"level": 18, "name": "Spell Mastery",
		"desc": "Choose a 1st-level and a 2nd-level wizard spell in your spellbook. You can cast them at their lowest level without expending a spell slot if you have them prepared.",
	},
	{
		"level": 20, "name": "Signature Spells",
		"desc": "Choose two 3rd-level wizard spells in your spellbook. You always have them prepared, they don't count against prepared spells, and you can cast each once at 3rd level without expending a slot. Regain uses on a short or long rest.",
	},
]


## Master lookup mapping class key (lowercase) to its feature progression table.
const CLASS_FEATURES: Dictionary = {
	"barbarian": BARBARIAN,
	"bard": BARD,
	"cleric": CLERIC,
	"druid": DRUID,
	"fighter": FIGHTER,
	"monk": MONK,
	"paladin": PALADIN,
	"ranger": RANGER,
	"rogue": ROGUE,
	"sorcerer": SORCERER,
	"warlock": WARLOCK,
	"wizard": WIZARD,
}
