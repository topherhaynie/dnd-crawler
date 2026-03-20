extends IGameStateService
class_name GameStateService

## Set by ServiceBootstrap before _ready() runs.
var _model: GameStateModel = null


func _ready() -> void:
	## Wait for ProfileService to enter the tree, then sync player state.
	call_deferred("_connect_profile_service")


func _connect_profile_service() -> void:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.profile == null or reg.profile.service == null:
		call_deferred("_connect_profile_service")
		return
	if not reg.profile.service.is_connected("profiles_changed", _on_profiles_changed):
		reg.profile.service.profiles_changed.connect(_on_profiles_changed)
	_rebuild_player_state()


func _on_profiles_changed() -> void:
	_rebuild_player_state()
	emit_signal("profiles_changed")


func _rebuild_player_state() -> void:
	if _model == null:
		return
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.profile == null or reg.profile.service == null:
		return
	var profiles := reg.profile.service.get_profiles()
	var next_locked: Dictionary = {}
	var next_positions: Dictionary = {}
	for p in profiles:
		if not p is PlayerProfile:
			continue
		var prof := p as PlayerProfile
		prof.ensure_id()
		next_locked[prof.id] = _model.player_locked.get(prof.id, false)
		next_positions[prof.id] = _model.player_positions.get(prof.id, Vector2.ZERO)
	_model.player_locked = next_locked
	_model.player_positions = next_positions


func list_profiles() -> Array:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.profile != null and reg.profile.service != null:
		return reg.profile.service.get_profiles()
	return []


func get_profile_by_id(id: String) -> Variant:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg != null and reg.profile != null and reg.profile.service != null:
		return reg.profile.service.get_profile_by_id(id)
	return null


func register_player(player_id: String) -> void:
	if _model == null:
		return
	if not player_id in _model.player_locked:
		_model.player_locked[player_id] = false
		_model.player_positions[player_id] = Vector2.ZERO


func lock_player(player_id: Variant) -> void:
	if _model == null:
		return
	_model.player_locked[player_id] = true
	emit_signal("player_lock_changed", player_id, true)


func unlock_player(player_id: Variant) -> void:
	if _model == null:
		return
	_model.player_locked[player_id] = false
	emit_signal("player_lock_changed", player_id, false)


func lock_all_players() -> void:
	if _model == null:
		return
	for pid in _model.player_locked.keys():
		lock_player(pid)


func unlock_all_players() -> void:
	if _model == null:
		return
	for pid in _model.player_locked.keys():
		unlock_player(pid)


func is_locked(player_id: Variant) -> bool:
	if _model == null:
		return false
	return bool(_model.player_locked.get(player_id, false))
