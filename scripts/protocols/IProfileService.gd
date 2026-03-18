extends Node
class_name IProfileService

"""
Protocol: IProfileService

Methods:
- func get_profiles() -> Array
- func get_profile_by_id(id: String) -> Dictionary
- func add_profile(profile: Dictionary) -> void
- func remove_profile(id: String) -> void
- func save_profiles() -> void
- func load_profiles() -> void
- func register_player(player_id: String) -> void

Signals:
- signal profiles_changed()

Notes:
- Protocol remains minimal; implementations provide concrete storage and behavior.
"""

signal profiles_changed()

func get_profiles() -> Array:
	return []

func get_profile_by_id(_id: String) -> Dictionary:
	return {}

func add_profile(_profile: Dictionary) -> void:
	pass

func remove_profile(_id: String) -> void:
	pass

func save_profiles() -> void:
	pass

func load_profiles() -> void:
	pass

func register_player(_player_id: String) -> void:
	pass
