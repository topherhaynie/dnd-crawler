extends IEffectService
class_name EffectService

# ---------------------------------------------------------------------------
# EffectService — concrete magic effect domain service.
#
# Owns the canonical in-memory effect collection (_effects: Dictionary).
# All state mutations go through this service; callers receive change
# notifications via the signals declared in IEffectService.
# ---------------------------------------------------------------------------

## id (String) → EffectData
var _effects: Dictionary = {}


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
