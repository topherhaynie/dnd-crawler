extends Node
class_name IGameStateService

## Protocol: IGameStateService
##
## Base contract for runtime game state. All runtime state (player locks,
## positions, windows) is owned by GameStateModel via GameStateManager.
## Concrete services receive the model via _model before _ready() runs.

@warning_ignore("unused_signal")
signal profiles_changed()
@warning_ignore("unused_signal")
signal player_lock_changed(player_id: Variant, is_locked: bool)
@warning_ignore("unused_signal")
signal session_saved(save_name: String)
@warning_ignore("unused_signal")
signal session_loaded(save_name: String)

func get_profile_by_id(_id: String) -> Variant:
	push_error("IGameStateService.get_profile_by_id: not implemented")
	return null

func list_profiles() -> Array:
	push_error("IGameStateService.list_profiles: not implemented")
	return []

func register_player(_player_id: String) -> void:
	push_error("IGameStateService.register_player: not implemented")

func lock_player(_player_id: Variant) -> void:
	push_error("IGameStateService.lock_player: not implemented")

func unlock_player(_player_id: Variant) -> void:
	push_error("IGameStateService.unlock_player: not implemented")

func lock_all_players() -> void:
	push_error("IGameStateService.lock_all_players: not implemented")

func unlock_all_players() -> void:
	push_error("IGameStateService.unlock_all_players: not implemented")

func is_locked(_player_id: Variant) -> bool:
	push_error("IGameStateService.is_locked: not implemented")
	return false

# --- Session save/load ------------------------------------------------------

func save_session(_save_name: String, _fog_image: Image, _map_bundle_path: String) -> bool:
	push_error("IGameStateService.save_session: not implemented")
	return false

func load_session(_save_path: String) -> Dictionary:
	push_error("IGameStateService.load_session: not implemented")
	return {}

func list_sessions() -> Array:
	push_error("IGameStateService.list_sessions: not implemented")
	return []

func reset_session() -> void:
	push_error("IGameStateService.reset_session: not implemented")
