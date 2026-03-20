extends Node
class_name IProfileService

## Protocol: IProfileService
##
## Base class for player profile storage. Owns the authoritative profile array
## and persistence. Runtime lock/position state belongs to IGameState.

@warning_ignore("unused_signal")
signal profiles_changed()

func get_profiles() -> Array:
	push_error("IProfileService.get_profiles: not implemented")
	return []

func get_profile_by_id(_id: String) -> Variant:
	push_error("IProfileService.get_profile_by_id: not implemented")
	return null

func add_profile(_profile: PlayerProfile) -> void:
	push_error("IProfileService.add_profile: not implemented")

func remove_profile(_id: String) -> void:
	push_error("IProfileService.remove_profile: not implemented")

func save_profiles() -> void:
	push_error("IProfileService.save_profiles: not implemented")

func load_profiles() -> void:
	push_error("IProfileService.load_profiles: not implemented")
