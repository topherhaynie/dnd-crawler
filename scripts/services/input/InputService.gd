extends IInputService
class_name InputService

# InputService — moves responsibilities from legacy InputManager autoload

# Dead-zone threshold for analog sticks
const DEAD_ZONE: float = 0.15

enum InputSource {NETWORK, GAMEPAD, DM}

const _SOURCE_ORDER: Array[int] = [InputSource.DM, InputSource.GAMEPAD, InputSource.NETWORK]

var _source_vectors: Dictionary = {}
var gamepad_bindings: Dictionary = {}
var _prev_gamepad_buttons: Dictionary = {} ## {device_id: {button: bool}}
var _dash_states: Dictionary = {} ## {player_id: bool}

func _game_state() -> GameStateManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.game_state == null:
		return null
	return registry.game_state

func _map_rotation_deg() -> int:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.map == null:
		return 0
	if registry.map.model != null:
		return registry.map.model.camera_rotation
	if registry.map.service != null:
		return registry.map.service.get_map_rotation()
	return 0

func _process(_delta: float) -> void:
	for device_id in gamepad_bindings.keys():
		var player_id = gamepad_bindings[device_id]
		var raw := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		)
		if raw.length() < DEAD_ZONE:
			raw = Vector2.ZERO
		else:
			raw = raw.normalized() * ((raw.length() - DEAD_ZONE) / (1.0 - DEAD_ZONE))
			raw = raw.clampf(-1.0, 1.0)
		set_gamepad_vector(player_id, raw)
		# --- Button edge detection for action dispatch ---
		var prev: Dictionary = _prev_gamepad_buttons.get(device_id, {}) as Dictionary
		var btn_a_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_A)
		var btn_b_now: bool = Input.is_joy_button_pressed(device_id, JOY_BUTTON_B)
		if btn_a_now and not bool(prev.get(JOY_BUTTON_A, false)):
			dispatch_action(player_id, "interact")
		if btn_b_now and not bool(prev.get(JOY_BUTTON_B, false)):
			set_dash_state(player_id, true)
		if not btn_b_now and bool(prev.get(JOY_BUTTON_B, false)):
			set_dash_state(player_id, false)
		_prev_gamepad_buttons[device_id] = {JOY_BUTTON_A: btn_a_now, JOY_BUTTON_B: btn_b_now}

func get_vector(player_id) -> Vector2:
	var gs := _game_state()
	if gs != null and gs.is_locked(player_id):
		return Vector2.ZERO
	var source_map: Dictionary = _source_vectors.get(player_id, {}) as Dictionary
	var vec := Vector2.ZERO
	for source_id in _SOURCE_ORDER:
		if source_map.has(source_id):
			vec = source_map[source_id] as Vector2
			break
	if vec == Vector2.ZERO:
		return vec
	var profile: Variant = gs.get_profile_by_id(player_id) if gs != null else null
	var table_orient: int = 0
	if profile and profile is PlayerProfile:
		table_orient = (profile as PlayerProfile).table_orientation
	# map_rotation compensates for viewport/camera rotation (positive), while
	# table_orient compensates for the player's seat position (negative).
	var net_angle := deg_to_rad(float(_map_rotation_deg() - table_orient))
	if not is_zero_approx(net_angle):
		vec = vec.rotated(net_angle)
	return vec

func set_vector(player_id, vec: Vector2, source: int = InputSource.NETWORK) -> void:
	if not _source_vectors.has(player_id):
		_source_vectors[player_id] = {}
	var source_map: Dictionary = _source_vectors[player_id] as Dictionary
	source_map[source] = vec.clamp(Vector2(-1, -1), Vector2(1, 1))
	_source_vectors[player_id] = source_map
	emit_signal("input_vector_changed", player_id, source_map[source])

func set_network_vector(player_id, vec: Vector2) -> void:
	set_vector(player_id, vec, InputSource.NETWORK)

func set_gamepad_vector(player_id, vec: Vector2) -> void:
	set_vector(player_id, vec, InputSource.GAMEPAD)

func set_dm_vector(player_id, vec: Vector2) -> void:
	set_vector(player_id, vec, InputSource.DM)

func clear_vector(player_id, source: int = -1) -> void:
	if source < 0:
		_source_vectors.erase(player_id)
		return
	if not _source_vectors.has(player_id):
		return
	var source_map: Dictionary = _source_vectors[player_id] as Dictionary
	source_map.erase(source)
	if source_map.is_empty():
		_source_vectors.erase(player_id)
	else:
		_source_vectors[player_id] = source_map

func clear_dm_vector(player_id) -> void:
	clear_vector(player_id, InputSource.DM)

func bind_gamepad(device_id: int, player_id) -> void:
	gamepad_bindings[device_id] = player_id
	emit_signal("input_binding_changed", player_id)

func unbind_gamepad(device_id: int) -> void:
	var player_id = gamepad_bindings.get(device_id, null)
	if player_id != null:
		clear_vector(player_id, InputSource.GAMEPAD)
	gamepad_bindings.erase(device_id)
	if player_id != null:
		emit_signal("input_binding_changed", player_id)

func bind_peer(_peer_id: int, _player_id: Variant) -> void:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry != null and registry.network != null and registry.network.service != null:
		registry.network.service.bind_peer(_peer_id, _player_id)

func clear_all_bindings() -> void:
	gamepad_bindings.clear()
	_source_vectors.clear()
	emit_signal("input_binding_changed", null)

func get_gamepad_bindings() -> Dictionary:
	return gamepad_bindings

func has_gamepad_binding(device_id: int) -> bool:
	return gamepad_bindings.has(device_id)


func dispatch_action(player_id: Variant, action: String) -> void:
	if action == "dash_start":
		set_dash_state(player_id, true)
		return
	if action == "dash_end":
		set_dash_state(player_id, false)
		return
	input_action_pressed.emit(player_id, action)


func set_dash_state(player_id: Variant, dashing: bool) -> void:
	var was: bool = bool(_dash_states.get(player_id, false))
	if was == dashing:
		return
	_dash_states[player_id] = dashing
	input_action_pressed.emit(player_id, "dash")


func is_dashing(player_id: Variant) -> bool:
	return bool(_dash_states.get(player_id, false))
