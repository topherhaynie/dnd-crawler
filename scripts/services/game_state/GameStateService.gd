extends IGameStateService
class_name GameStateService

const _GameSaveDataClass = preload("res://scripts/services/game_state/models/GameSaveData.gd")

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


func set_light_off(player_id: Variant, off: bool) -> void:
	if _model == null:
		return
	_model.player_light_off[player_id] = off
	emit_signal("player_light_off_changed", player_id, off)


func is_light_off(player_id: Variant) -> bool:
	if _model == null:
		return false
	return bool(_model.player_light_off.get(player_id, false))


# ---------------------------------------------------------------------------
# Session save / load
# ---------------------------------------------------------------------------

func save_session(save_name: String, fog_image: Image, map_bundle_path: String) -> bool:
	if _model == null:
		return false
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.persistence == null or reg.persistence.service == null:
		push_error("GameStateService.save_session: persistence service unavailable")
		return false

	var now := Time.get_datetime_string_from_system(true)
	var state := _GameSaveDataClass.new()
	state.save_name = save_name
	state.map_bundle_path = map_bundle_path

	# Carry over which profiles are active in this session
	if _model.active_save != null:
		state.active_profile_ids = (_model.active_save as GameSaveData).active_profile_ids.duplicate()

	# Snapshot player positions as serialisable dicts
	for pid in _model.player_positions.keys():
		var pos: Variant = _model.player_positions[pid]
		if pos is Vector2:
			state.player_positions[pid] = pos
		else:
			state.player_positions[pid] = Vector2.ZERO
	for pid in _model.player_locked.keys():
		state.player_locked[pid] = bool(_model.player_locked[pid])

	# Player camera
	state.player_camera_position = _model.player_camera_position
	state.player_camera_zoom = _model.player_camera_zoom
	state.player_camera_rotation = _model.player_camera_rotation

	# Token runtime state (is_visible_to_players etc.)
	if reg.token != null and reg.token.service != null:
		var all_tokens: Array = reg.token.service.get_all_tokens()
		for raw in all_tokens:
			var td: TokenData = raw as TokenData
			if td == null:
				continue
			state.token_states[td.id] = {"is_visible_to_players": td.is_visible_to_players}

	# Timestamps
	if _model.active_save != null and not _model.active_save.created_at.is_empty():
		state.created_at = _model.active_save.created_at
	else:
		state.created_at = now
	state.updated_at = now

	var bundle_path := "user://data/saves/%s.sav" % save_name
	var ok := reg.persistence.service.save_game_bundle(bundle_path, state, fog_image, map_bundle_path)
	if ok:
		_model.active_save = state
		emit_signal("session_saved", save_name)
	return ok


func load_session(save_path: String) -> Dictionary:
	## Returns the raw bundle dict from PersistenceService on success
	## ({"state": GameSaveData, "fog_image": Image, "map_bundle_path": String})
	## or empty dict on failure. Also restores model state.
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.persistence == null or reg.persistence.service == null:
		push_error("GameStateService.load_session: persistence service unavailable")
		return {}

	var bundle := reg.persistence.service.load_game_bundle(save_path)
	if bundle.is_empty():
		return {}

	var state: Variant = bundle.get("state", null)
	if state == null:
		return {}

	if _model == null:
		return {}

	# Restore positions
	_model.player_positions.clear()
	for pid in state.player_positions.keys():
		_model.player_positions[pid] = state.player_positions[pid]

	# Restore locks
	_model.player_locked.clear()
	for pid in state.player_locked.keys():
		_model.player_locked[pid] = state.player_locked[pid]

	# Restore player camera
	_model.player_camera_position = state.player_camera_position
	_model.player_camera_zoom = state.player_camera_zoom
	_model.player_camera_rotation = state.player_camera_rotation

	_model.active_save = state
	emit_signal("session_loaded", state.save_name)
	return bundle


func list_sessions() -> Array:
	var reg := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if reg == null or reg.persistence == null or reg.persistence.service == null:
		return []
	return reg.persistence.service.list_save_bundles()


func reset_session() -> void:
	if _model == null:
		return
	_model.player_positions.clear()
	_model.player_locked.clear()
	_model.player_camera_position = Vector2(960.0, 540.0)
	_model.player_camera_zoom = 1.0
	_model.player_camera_rotation = 0
	_model.active_save = null


# ---------------------------------------------------------------------------
# Per-save profile assignment
# ---------------------------------------------------------------------------

func get_active_profile_ids() -> Array:
	if _model == null or _model.active_save == null:
		return []
	return (_model.active_save as GameSaveData).active_profile_ids.duplicate()


func set_profile_active(id: String, active: bool) -> void:
	if _model == null or _model.active_save == null:
		return
	var save := _model.active_save as GameSaveData
	var idx: int = save.active_profile_ids.find(id)
	if active and idx == -1:
		save.active_profile_ids.append(id)
	elif not active and idx != -1:
		save.active_profile_ids.remove_at(idx)
	else:
		return # no change
	emit_signal("active_profiles_changed")
	_save_session_state_only()


func is_profile_active(id: String) -> bool:
	if _model == null or _model.active_save == null:
		return false # no session loaded → no profiles active
	return id in (_model.active_save as GameSaveData).active_profile_ids


func has_active_session() -> bool:
	return _model != null and _model.active_save != null


func init_ephemeral_session() -> void:
	if _model == null:
		return
	var state := _GameSaveDataClass.new()
	# No save_name — ephemeral session that hasn't been saved to disk yet.
	# Starts with no active profiles; the DM activates them individually.
	_model.active_save = state


func _save_session_state_only() -> void:
	if _model == null or _model.active_save == null:
		return
	var save := _model.active_save as GameSaveData
	if save.save_name.is_empty():
		return  # Ephemeral session — no disk location yet.
	save.updated_at = Time.get_datetime_string_from_system(true)
	var bundle_path := "user://data/saves/%s.sav" % save.save_name
	var abs_bundle := ProjectSettings.globalize_path(bundle_path)
	var state_path := abs_bundle.path_join("state.json")
	var fa := FileAccess.open(state_path, FileAccess.WRITE)
	if fa == null:
		push_error("GameStateService._save_session_state_only: cannot write state.json at '%s'" % state_path)
		return
	fa.store_string(JSON.stringify(save.to_dict(), "\t"))
	fa.close()
