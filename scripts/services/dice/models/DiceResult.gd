extends RefCounted
class_name DiceResult

# ---------------------------------------------------------------------------
# DiceResult — outcome of evaluating a dice expression.
# ---------------------------------------------------------------------------

## The original expression string (e.g. "2d8+2").
var expression: String = ""

## Per-group individual die rolls.  Each element is an Array[int] for one
## dice group — e.g. "2d8+1d6" → [[5, 3], [4]].
var individual_rolls: Array = []

## Sum of all flat modifiers in the expression.
var modifiers: int = 0

## Final computed total (sum of kept dice + modifiers).
var total: int = 0

## True when a d20 roll yielded a natural 20 (first die in first group).
var is_critical: bool = false

## True when a d20 roll yielded a natural 1 (first die in first group).
var is_fumble: bool = false


func to_dict() -> Dictionary:
	return {
		"expression": expression,
		"individual_rolls": individual_rolls,
		"modifiers": modifiers,
		"total": total,
		"is_critical": is_critical,
		"is_fumble": is_fumble,
	}


static func from_dict(d: Dictionary) -> DiceResult:
	var r := DiceResult.new()
	r.expression = str(d.get("expression", ""))
	r.modifiers = int(d.get("modifiers", 0))
	r.total = int(d.get("total", 0))
	r.is_critical = bool(d.get("is_critical", false))
	r.is_fumble = bool(d.get("is_fumble", false))
	var raw_rolls: Variant = d.get("individual_rolls", [])
	if raw_rolls is Array:
		r.individual_rolls = raw_rolls as Array
	return r
