extends Node
class_name IProfileService

@warning_ignore("unused_signal")
signal profiles_changed()

# Protocol signal — declared for implementations to emit; no inline references here.

func get_profiles() -> Array:
	return []

func get_profile_by_id(_id: String):
	return null

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
