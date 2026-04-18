extends RefCounted
class_name DiceExpression

# ---------------------------------------------------------------------------
# DiceExpression — parses and evaluates dice notation strings.
#
# Supported syntax:
#   "2d8+2"      — roll 2 eight-sided dice and add 2
#   "4d6kh3"     — roll 4d6, keep highest 3
#   "4d6kl1"     — roll 4d6, keep lowest 1
#   "1d20+5"     — single d20 plus modifier
#   "2d6+1d4+3"  — multiple dice groups with a flat modifier
#
# Usage:
#   var expr := DiceExpression.parse("2d8+2")
#   var result: DiceResult = expr.roll()
# ---------------------------------------------------------------------------

## Parsed dice groups: Array of Dictionaries.
## Each: {count: int, sides: int, keep_highest: int, keep_lowest: int}
## keep_highest/keep_lowest of 0 means keep all.
var _groups: Array = []

## Flat modifier sum (can be negative).
var _modifier: int = 0

## Original expression string.
var _raw: String = ""


static func parse(expr: String) -> DiceExpression:
	var de := DiceExpression.new()
	de._raw = expr.strip_edges()
	if de._raw.is_empty():
		return de

	# Normalise: lowercase, convert minus to +-
	var normalised: String = de._raw.to_lower().replace("-", "+-")

	# Split into tokens on "+"
	var tokens: PackedStringArray = normalised.split("+", false)

	for token: String in tokens:
		token = token.strip_edges()
		if token.is_empty():
			continue

		var d_pos: int = token.find("d")
		if d_pos == -1:
			# Pure numeric modifier
			de._modifier += int(token)
			continue

		# Parse dice group: NdS[kh/kl N]
		var count_str: String = token.substr(0, d_pos)
		var count: int = int(count_str) if not count_str.is_empty() else 1

		var remainder: String = token.substr(d_pos + 1)
		var keep_highest: int = 0
		var keep_lowest: int = 0

		var kh_pos: int = remainder.find("kh")
		var kl_pos: int = remainder.find("kl")

		if kh_pos != -1:
			var sides_str: String = remainder.substr(0, kh_pos)
			var kh_val_str: String = remainder.substr(kh_pos + 2)
			var sides: int = int(sides_str)
			keep_highest = int(kh_val_str) if not kh_val_str.is_empty() else 1
			de._groups.append({
				"count": count,
				"sides": sides,
				"keep_highest": keep_highest,
				"keep_lowest": 0,
			})
		elif kl_pos != -1:
			var sides_str: String = remainder.substr(0, kl_pos)
			var kl_val_str: String = remainder.substr(kl_pos + 2)
			var sides: int = int(sides_str)
			keep_lowest = int(kl_val_str) if not kl_val_str.is_empty() else 1
			de._groups.append({
				"count": count,
				"sides": sides,
				"keep_highest": 0,
				"keep_lowest": keep_lowest,
			})
		else:
			var sides: int = int(remainder)
			de._groups.append({
				"count": count,
				"sides": sides,
				"keep_highest": 0,
				"keep_lowest": 0,
			})

	return de


func roll() -> DiceResult:
	var result := DiceResult.new()
	result.expression = _raw
	result.modifiers = _modifier
	var running_total: int = _modifier

	for group: Dictionary in _groups:
		var count: int = int(group.get("count", 1))
		var sides: int = int(group.get("sides", 6))
		var kh: int = int(group.get("keep_highest", 0))
		var kl: int = int(group.get("keep_lowest", 0))

		if sides <= 0 or count <= 0:
			result.individual_rolls.append([])
			continue

		# Roll all dice in this group
		var rolls: Array[int] = []
		for _i: int in range(count):
			rolls.append(randi_range(1, sides))

		# Determine which rolls to keep
		var kept: Array[int] = []
		if kh > 0:
			var sorted_rolls: Array[int] = rolls.duplicate()
			sorted_rolls.sort()
			sorted_rolls.reverse()
			for i: int in range(mini(kh, sorted_rolls.size())):
				kept.append(sorted_rolls[i])
		elif kl > 0:
			var sorted_rolls: Array[int] = rolls.duplicate()
			sorted_rolls.sort()
			for i: int in range(mini(kl, sorted_rolls.size())):
				kept.append(sorted_rolls[i])
		else:
			kept = rolls

		result.individual_rolls.append(rolls)

		var group_total: int = 0
		for val: int in kept:
			group_total += val
		running_total += group_total

	result.total = running_total

	# Check for critical/fumble on first d20 roll
	if _groups.size() > 0:
		var first_group: Dictionary = _groups[0]
		if int(first_group.get("sides", 0)) == 20 and result.individual_rolls.size() > 0:
			var first_rolls: Array = result.individual_rolls[0]
			if first_rolls.size() > 0:
				var first_val: int = int(first_rolls[0])
				result.is_critical = first_val == 20
				result.is_fumble = first_val == 1

	return result


func get_average() -> float:
	var avg: float = float(_modifier)
	for group: Dictionary in _groups:
		var count: int = int(group.get("count", 1))
		var sides: int = int(group.get("sides", 6))
		var kh: int = int(group.get("keep_highest", 0))
		var kl: int = int(group.get("keep_lowest", 0))
		if sides <= 0:
			continue
		if kh == 0 and kl == 0:
			# Keep all: average of NdS = N * (S + 1) / 2
			avg += float(count) * (float(sides) + 1.0) / 2.0
		else:
			# Approximate: use keep-all average scaled by kept/total ratio
			var keep_count: int = kh if kh > 0 else kl
			avg += float(count) * (float(sides) + 1.0) / 2.0 * float(keep_count) / float(count)
	return avg


func get_min() -> int:
	var mn: int = _modifier
	for group: Dictionary in _groups:
		var count: int = int(group.get("count", 1))
		var kh: int = int(group.get("keep_highest", 0))
		var kl: int = int(group.get("keep_lowest", 0))
		var sides: int = int(group.get("sides", 6))
		if sides <= 0:
			continue
		var keep_count: int = count
		if kh > 0:
			keep_count = mini(kh, count)
		elif kl > 0:
			keep_count = mini(kl, count)
		mn += keep_count # each kept die minimum is 1
	return mn


func get_max() -> int:
	var mx: int = _modifier
	for group: Dictionary in _groups:
		var count: int = int(group.get("count", 1))
		var sides: int = int(group.get("sides", 6))
		var kh: int = int(group.get("keep_highest", 0))
		var kl: int = int(group.get("keep_lowest", 0))
		if sides <= 0:
			continue
		var keep_count: int = count
		if kh > 0:
			keep_count = mini(kh, count)
		elif kl > 0:
			keep_count = mini(kl, count)
		mx += keep_count * sides
	return mx


func _to_string() -> String:
	return _raw
