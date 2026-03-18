extends RefCounted
class_name IGameState

"""
Protocol: IGameState

Methods:
- func get_profile_by_id(id: String) -> Dictionary
- func list_profiles() -> Array

Signals:
- signal profiles_changed()

Notes:
- Minimal protocol signatures for game-state access.
"""

signal profiles_changed()

func get_profile_by_id(_id: String) -> Variant:
	return null

func list_profiles() -> Array:
	return []


func _protocol_signal_marker() -> void:
	# Intentionally never-run code path to reference protocol signals so the
	# static analyzer does not flag them as unused.
	if false:
		emit_signal("profiles_changed")
