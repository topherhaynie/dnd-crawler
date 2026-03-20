extends IInputService
class_name InputService

# InputService — moves responsibilities from legacy InputManager autoload

# Dead-zone threshold for analog sticks
const DEAD_ZONE: float = 0.15

enum InputSource {NETWORK, GAMEPAD, DM}

const _SOURCE_ORDER: Array[int] = [InputSource.DM, InputSource.GAMEPAD, InputSource.NETWORK]

var _source_vectors: Dictionary = {}
var gamepad_bindings: Dictionary = {}

func _game_state() -> GameStateManager:
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.game_state == null:
		return null
	return registry.game_state

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
	if profile and profile is PlayerProfile:
		var angle_rad := deg_to_rad((profile as PlayerProfile).table_orientation)
		vec = vec.rotated(-angle_rad)
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
