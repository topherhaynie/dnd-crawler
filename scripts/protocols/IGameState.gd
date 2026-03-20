extends Node
class_name IGameState

## Protocol: IGameState
##
## Base class for runtime game state. Tracks player locks, positions, and
## window registrations. Extend this class for a concrete implementation.
##
## Note: profiles, player_locked, player_positions, and windows are exposed as
## mutable properties intentionally — BackendRuntime writes to them directly.
## Phase 5 will introduce typed accessors to eliminate direct property writes.

@warning_ignore("unused_signal")
signal profiles_changed()
@warning_ignore("unused_signal")
signal player_lock_changed(player_id: Variant, is_locked: bool)

# Runtime state — directly accessible from BackendRuntime and DMWindow.
var profiles: Array = []
var player_locked: Dictionary = {}
var player_positions: Dictionary = {}
var windows: Array = []

func get_profile_by_id(_id: String) -> Variant:
	push_error("IGameState.get_profile_by_id: not implemented")
	return null

func list_profiles() -> Array:
	push_error("IGameState.list_profiles: not implemented")
	return []

func register_player(_player_id: String) -> void:
	push_error("IGameState.register_player: not implemented")

func lock_player(_player_id: Variant) -> void:
	push_error("IGameState.lock_player: not implemented")

func unlock_player(_player_id: Variant) -> void:
	push_error("IGameState.unlock_player: not implemented")

func lock_all_players() -> void:
	push_error("IGameState.lock_all_players: not implemented")

func unlock_all_players() -> void:
	push_error("IGameState.unlock_all_players: not implemented")

func is_locked(_player_id: Variant) -> bool:
	push_error("IGameState.is_locked: not implemented")
	return false
