extends IEffectService
class_name EffectService

# ---------------------------------------------------------------------------
# EffectService — concrete magic effect domain service.
#
# Owns the canonical in-memory effect collection (_effects: Dictionary).
# Also loads and holds the EffectDefinition manifest for the expandable
# effect library (Phase 11).
# All state mutations go through this service; callers receive change
# notifications via the signals declared in IEffectService.
# ---------------------------------------------------------------------------

## id (String) → EffectData
var _effects: Dictionary = {}

## effect_id (String) → EffectDefinition
var _definitions: Dictionary = {}
var _manifest_loaded: bool = false


# ---------------------------------------------------------------------------
# Mutation
# ---------------------------------------------------------------------------

func spawn_effect(data: EffectData) -> void:
	if data == null or data.id.is_empty():
		push_error("EffectService.spawn_effect: data is null or has empty id")
		return
	_effects[data.id] = data
	effect_spawned.emit(data)


func remove_effect(id: String) -> void:
	if not _effects.has(id):
		return
	_effects.erase(id)
	effect_removed.emit(id)


# ---------------------------------------------------------------------------
# Bulk
# ---------------------------------------------------------------------------

func load_effects(dicts: Array) -> void:
	_effects.clear()
	for raw in dicts:
		if raw is Dictionary:
			var e: EffectData = EffectData.from_dict(raw as Dictionary)
			_effects[e.id] = e
	effects_reloaded.emit()


func clear_effects() -> void:
	_effects.clear()
	effects_reloaded.emit()


# ---------------------------------------------------------------------------
# Query
# ---------------------------------------------------------------------------

func get_all_effects() -> Array:
	return _effects.values()


func get_effect_by_id(id: String) -> EffectData:
	return _effects.get(id, null) as EffectData


# ---------------------------------------------------------------------------
# Manifest (EffectDefinition library)
# ---------------------------------------------------------------------------

func load_manifest(path: String) -> void:
	_definitions.clear()
	_manifest_loaded = false
	if not FileAccess.file_exists(path):
		push_warning("EffectService.load_manifest: manifest not found at '%s'" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("EffectService.load_manifest: cannot open '%s'" % path)
		return
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not raw is Array:
		push_error("EffectService.load_manifest: expected JSON array in '%s'" % path)
		return
	for entry in (raw as Array):
		if entry is Dictionary:
			var def: EffectDefinition = EffectDefinition.from_dict(entry as Dictionary)
			if not def.effect_id.is_empty():
				_definitions[def.effect_id] = def
	_manifest_loaded = true


func get_definitions() -> Array:
	return _definitions.values()


func get_definition(effect_id: String) -> EffectDefinition:
	return _definitions.get(effect_id, null) as EffectDefinition


func is_manifest_loaded() -> bool:
	return _manifest_loaded
