extends RefCounted
class_name ClassFeatureResolver

const _CFT := preload("res://scripts/ui/character_wizard/ClassFeatureTable.gd")

# -----------------------------------------------------------------------------
# ClassFeatureResolver — resolves class features for a given class + level.
#
# Reads from ClassFeatureTable, substitutes scaling placeholders, and returns
# an Array of feature dictionaries ready to write into StatblockData.features.
#
# Supports multiclass: call resolve() once per class entry and merge results.
# -----------------------------------------------------------------------------


## Resolve all automatic class features for a single class at the given level.
## Returns Array of {name: String, desc: String, source: String}.
## Choice-based features (subclass, fighting style, expertise, invocations, etc.)
## are NOT included — those are assembled by WizardStatblockBuilder from wizard state.
static func resolve(class_key: String, level: int) -> Array:
	var table_var: Variant = _CFT.CLASS_FEATURES.get(class_key.to_lower())
	if not (table_var is Array):
		return []
	var table: Array = table_var as Array
	var lvl: int = clampi(level, 1, 20)

	# Collect features the character has earned (level <= current level).
	# When a feature has replace=true, keep only the highest-level version.
	var seen: Dictionary = {} # name -> resolved feature dict
	var order: Array = [] # names in insertion order

	for entry_var: Variant in table:
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var as Dictionary
		var feat_level: int = int(entry.get("level", 99))
		if feat_level > lvl:
			continue

		var feat_name: String = str(entry.get("name", ""))
		var feat_desc: String = str(entry.get("desc", ""))
		var should_replace: bool = bool(entry.get("replace", false))

		# Substitute scaling placeholders.
		var scaling_var: Variant = entry.get("scaling")
		if scaling_var is Dictionary:
			var scaling: Dictionary = scaling_var as Dictionary
			for placeholder: String in scaling.keys():
				var values_var: Variant = scaling[placeholder]
				if values_var is Array:
					var values: Array = values_var as Array
					var idx: int = clampi(lvl - 1, 0, values.size() - 1)
					feat_desc = feat_desc.replace("{%s}" % placeholder, str(values[idx]))

		var resolved: Dictionary = {
			"name": feat_name,
			"desc": feat_desc,
			"source": "class",
		}

		if should_replace:
			if seen.has(feat_name):
				# Overwrite the previous version.
				seen[feat_name] = resolved
			else:
				seen[feat_name] = resolved
				order.append(feat_name)
		else:
			# Non-replacing features with the same name stack (e.g. Magical Secrets).
			# Give them a unique key to avoid collisions.
			var unique_key: String = feat_name + "_%d" % feat_level
			seen[unique_key] = resolved
			order.append(unique_key)

	# Build ordered result array.
	var result: Array = []
	for key: String in order:
		if seen.has(key):
			result.append(seen[key])
	return result


## Resolve features for a multiclass character.
## classes_array: [{name: String, level: int, subclass: String}, ...]
## Returns merged Array of feature dicts, each tagged with source "class".
static func resolve_multiclass(classes_array: Array) -> Array:
	var all_features: Array = []
	for entry_var: Variant in classes_array:
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var as Dictionary
		var cls_name: String = str(entry.get("name", "")).to_lower()
		var cls_level: int = int(entry.get("level", 0))
		if cls_name.is_empty() or cls_level < 1:
			continue
		all_features.append_array(resolve(cls_name, cls_level))
	return all_features
