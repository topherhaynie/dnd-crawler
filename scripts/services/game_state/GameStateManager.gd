extends RefCounted
class_name GameStateManager

const _GameSaveDataClass = preload("res://scripts/services/game_state/models/GameSaveData.gd")

## GameState domain coordinator.
##
## Owns GameStateModel and exposes high-level operations for player lock,
## position, and window tracking. All mutations go through the manager so
## domain signals fire consistently.
##
## Access via: get_node("/root/ServiceRegistry").game_state

signal player_lock_changed(player_id: Variant, is_locked: bool)
signal player_light_off_changed(player_id: Variant, is_off: bool)
signal player_positions_changed()
@warning_ignore("unused_signal")
signal profiles_changed()
@warning_ignore("unused_signal")
signal session_saved(save_name: String)
@warning_ignore("unused_signal")
signal session_loaded(save_name: String)

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


func set_light_off(player_id: Variant, off: bool) -> void:
	if model == null:
		return
	model.player_light_off[player_id] = off
	player_light_off_changed.emit(player_id, off)
	if service != null:
		service.emit_signal("player_light_off_changed", player_id, off)


func is_light_off(player_id: Variant) -> bool:
	if model == null:
		return false
	return bool(model.player_light_off.get(player_id, false))


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


# ---------------------------------------------------------------------------
# Player camera (DM-controlled viewport shown on player displays)
# ---------------------------------------------------------------------------

var player_camera_position: Vector2:
	get: return model.player_camera_position if model != null else Vector2(960.0, 540.0)
	set(v):
		if model != null:
			model.player_camera_position = v

var player_camera_zoom: float:
	get: return model.player_camera_zoom if model != null else 1.0
	set(v):
		if model != null:
			model.player_camera_zoom = v

var player_camera_rotation: int:
	get: return model.player_camera_rotation if model != null else 0
	set(v):
		if model != null:
			model.player_camera_rotation = v


# ---------------------------------------------------------------------------
# Session save / load
# ---------------------------------------------------------------------------

var active_save: RefCounted: ## GameSaveData or null
	get: return model.active_save if model != null else null


func save_session(save_name: String, fog_image: Image, map_bundle_path: String) -> bool:
	if service == null:
		return false
	var ok := service.save_session(save_name, fog_image, map_bundle_path)
	if ok:
		session_saved.emit(save_name)
	return ok


func load_session(save_path: String) -> Dictionary:
	if service == null:
		return {}
	var bundle := service.load_session(save_path)
	if not bundle.is_empty():
		var state: Variant = bundle.get("state", null)
		if state != null:
			session_loaded.emit(state.save_name)
	return bundle


func list_sessions() -> Array:
	if service == null:
		return []
	return service.list_sessions()


func reset_session() -> void:
	if service != null:
		service.reset_session()


# ---------------------------------------------------------------------------
# Per-save profile assignment
# ---------------------------------------------------------------------------

func get_active_profile_ids() -> Array:
	if service == null:
		return []
	return service.get_active_profile_ids()


func set_profile_active(id: String, active: bool) -> void:
	if service != null:
		service.set_profile_active(id, active)


func is_profile_active(id: String) -> bool:
	if service == null:
		return false
	return service.is_profile_active(id)


func has_active_session() -> bool:
	if service == null:
		return false
	return service.has_active_session()


func init_ephemeral_session() -> void:
	if service != null:
		service.init_ephemeral_session()
