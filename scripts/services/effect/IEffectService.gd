extends Node
class_name IEffectService

# ---------------------------------------------------------------------------
# IEffectService — protocol (interface) for the magic effect domain.
#
# All public methods are declared here with push_error stubs.
# Concrete implementations must override them.
# Signals are declared here; concrete services must NOT redeclare them.
# ---------------------------------------------------------------------------

# --- Signals ---------------------------------------------------------------
@warning_ignore("unused_signal")
signal effect_spawned(data: EffectData)
@warning_ignore("unused_signal")
signal effect_removed(id: String)
@warning_ignore("unused_signal")
signal effects_reloaded


# --- Mutation --------------------------------------------------------------

func spawn_effect(_data: EffectData) -> void:
	push_error("IEffectService.spawn_effect: not implemented")


func remove_effect(_id: String) -> void:
	push_error("IEffectService.remove_effect: not implemented")


# --- Bulk ------------------------------------------------------------------

func load_effects(_dicts: Array) -> void:
	push_error("IEffectService.load_effects: not implemented")


func clear_effects() -> void:
	push_error("IEffectService.clear_effects: not implemented")


# --- Query -----------------------------------------------------------------

func get_all_effects() -> Array:
	push_error("IEffectService.get_all_effects: not implemented")
	return []


func get_effect_by_id(_id: String) -> EffectData:
	push_error("IEffectService.get_effect_by_id: not implemented")
	return null


# --- Manifest (EffectDefinition library) -----------------------------------

func load_manifest(_path: String) -> void:
	push_error("IEffectService.load_manifest: not implemented")


func get_definitions() -> Array:
	push_error("IEffectService.get_definitions: not implemented")
	return []


func get_definition(_effect_id: String) -> EffectDefinition:
	push_error("IEffectService.get_definition: not implemented")
	return null


func is_manifest_loaded() -> bool:
	push_error("IEffectService.is_manifest_loaded: not implemented")
	return false
