extends RefCounted
class_name StatblockOverride

# ---------------------------------------------------------------------------
# StatblockOverride — per-token override container.
#
# Stores only fields that differ from the base statblock plus runtime
# combat state (current HP, conditions, etc.).
# ---------------------------------------------------------------------------

## ID of the base statblock this overrides.
var base_statblock_id: String = ""

## field_name → value.  Only changed fields are stored.
var overrides: Dictionary = {}

# --- Runtime combat state ---
var current_hp: int = 0
var max_hp: int = 0
var temp_hp: int = 0
var conditions: Array = [] # Array of condition name strings
## {level_number: slots_used_count}
var spell_slots_used: Dictionary = {}
## {successes: int, failures: int}
var death_saves: Dictionary = {"successes": 0, "failures": 0}
var concentration_spell: String = ""
var notes: String = ""


## Return the override value for a field, or the base value if not overridden.
func get_effective(field: String, base: Variant) -> Variant:
	if overrides.has(field):
		return overrides[field]
	return base


## Return a merged StatblockData with overrides applied.
func apply_to(base: StatblockData) -> StatblockData:
	if base == null:
		return null
	# Serialize the base, apply overrides, deserialize
	var d: Dictionary = base.to_dict()
	for key: String in overrides:
		d[key] = overrides[key]
	var merged: StatblockData = StatblockData.from_dict(d)
	merged.id = base.id
	return merged


## Roll HP from the base statblock's hit_points_roll, store as override.
func roll_hit_points(base: StatblockData) -> int:
	if base == null:
		return 0
	var rolled: int = base.roll_hit_points()
	overrides["hit_points"] = rolled
	current_hp = rolled
	max_hp = rolled
	return rolled


func to_dict() -> Dictionary:
	return {
		"base_statblock_id": base_statblock_id,
		"overrides": overrides,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"temp_hp": temp_hp,
		"conditions": conditions,
		"spell_slots_used": spell_slots_used,
		"death_saves": death_saves,
		"concentration_spell": concentration_spell,
		"notes": notes,
	}


static func from_dict(d: Dictionary) -> StatblockOverride:
	var so := StatblockOverride.new()
	so.base_statblock_id = str(d.get("base_statblock_id", ""))
	var raw_overrides: Variant = d.get("overrides", {})
	if raw_overrides is Dictionary:
		so.overrides = raw_overrides as Dictionary
	so.current_hp = int(d.get("current_hp", 0))
	so.max_hp = int(d.get("max_hp", 0))
	so.temp_hp = int(d.get("temp_hp", 0))
	var raw_cond: Variant = d.get("conditions", [])
	if raw_cond is Array:
		so.conditions = raw_cond as Array
	var raw_slots: Variant = d.get("spell_slots_used", {})
	if raw_slots is Dictionary:
		so.spell_slots_used = raw_slots as Dictionary
	var raw_ds: Variant = d.get("death_saves", {"successes": 0, "failures": 0})
	if raw_ds is Dictionary:
		so.death_saves = raw_ds as Dictionary
	so.concentration_spell = str(d.get("concentration_spell", ""))
	so.notes = str(d.get("notes", ""))
	return so
