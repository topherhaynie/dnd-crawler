extends RefCounted
class_name EffectManager

# ---------------------------------------------------------------------------
# EffectManager — typed coordinator for the magic effect domain.
#
# Owned by ServiceRegistry.effect.  All callers access effect operations
# through manager methods — never via registry.effect.service.
# ---------------------------------------------------------------------------

var service: IEffectService = null


func spawn(data: EffectData) -> void:
	if service == null:
		return
	service.spawn_effect(data)


func remove(id: String) -> void:
	if service == null:
		return
	service.remove_effect(id)


func load_from_dicts(dicts: Array) -> void:
	if service == null:
		return
	service.load_effects(dicts)


func clear() -> void:
	if service == null:
		return
	service.clear_effects()


func get_all() -> Array:
	if service == null:
		return []
	return service.get_all_effects()


func get_by_id(id: String) -> EffectData:
	if service == null:
		return null
	return service.get_effect_by_id(id)


# ---------------------------------------------------------------------------
# Manifest (EffectDefinition library)
# ---------------------------------------------------------------------------

func load_manifest(path: String) -> void:
	if service == null:
		return
	service.load_manifest(path)


func get_definitions() -> Array:
	if service == null:
		return []
	return service.get_definitions()


func get_definition(effect_id: String) -> EffectDefinition:
	if service == null:
		return null
	return service.get_definition(effect_id)


func is_manifest_loaded() -> bool:
	if service == null:
		return false
	return service.is_manifest_loaded()
