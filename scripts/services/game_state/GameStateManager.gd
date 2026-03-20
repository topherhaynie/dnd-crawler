extends RefCounted
class_name GameStateManager

## GameState domain coordinator.
##
## Owns GameStateModel and exposes high-level operations for player lock,
## position, and window tracking. All mutations go through the manager so
## domain signals fire consistently.
##
## Access via: get_node("/root/ServiceRegistry").game_state

signal player_lock_changed(player_id: Variant, is_locked: bool)
signal player_positions_changed()
@warning_ignore("unused_signal")
signal profiles_changed()

var service: IGameStateService = null
var model: GameStateModel = null

## Convenience read-only views over the model for call sites that use
## _game_state().xxx directly (Player/DM lock checks, position reads, etc.).
var player_locked: Dictionary:
	get: return model.player_locked if model != null else {}
var player_positions: Dictionary:
	get: return model.player_positions if model != null else {}
var windows: Array:
	get: return model.windows if model != null else []


func configure() -> void:
	## Initialise model if ServiceBootstrap did not pre-create it.
	if model == null:
		model = GameStateModel.new()


func add_window(window_id: int) -> void:
	if model != null:
		model.windows.append(window_id)


func register_player(player_id: Variant) -> void:
	if model == null:
		return
	if not model.player_locked.has(player_id):
		model.player_locked[player_id] = false
		model.player_positions[player_id] = Vector2.ZERO
	if service != null:
		service.register_player(str(player_id))


func lock_player(player_id: Variant) -> void:
	if model == null:
		return
	model.player_locked[player_id] = true
	player_lock_changed.emit(player_id, true)
	if service != null:
		service.emit_signal("player_lock_changed", player_id, true)


func unlock_player(player_id: Variant) -> void:
	if model == null:
		return
	model.player_locked[player_id] = false
	player_lock_changed.emit(player_id, false)
	if service != null:
		service.emit_signal("player_lock_changed", player_id, false)


func lock_all_players() -> void:
	if model == null:
		return
	for pid in model.player_locked.keys():
		lock_player(pid)


func unlock_all_players() -> void:
	if model == null:
		return
	for pid in model.player_locked.keys():
		unlock_player(pid)


func is_locked(player_id: Variant) -> bool:
	if model == null:
		return false
	return bool(model.player_locked.get(player_id, false))


func get_position(player_id: Variant) -> Vector2:
	if model == null:
		return Vector2.ZERO
	return model.player_positions.get(player_id, Vector2.ZERO) as Vector2


func set_position(player_id: Variant, pos: Vector2) -> void:
	if model == null:
		return
	model.player_positions[player_id] = pos
	player_positions_changed.emit()


func list_profiles() -> Array:
	if service != null:
		return service.list_profiles()
	return []


func get_profile_by_id(id: String) -> Variant:
	if service != null:
		return service.get_profile_by_id(id)
	return null
