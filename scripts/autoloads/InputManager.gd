extends Node

# ---------------------------------------------------------------------------
# InputManager — collects movement vectors from all input sources each frame
# and exposes them to PlayerSprite nodes via get_vector(player_id).
#
# Input sources (wired in Phase 5):
#   - Gamepad: polled here each frame via Input.get_joy_axis()
#   - WebSocket: vectors written here by NetworkManager on packet receipt
# ---------------------------------------------------------------------------

# Dead-zone threshold for analog sticks
const DEAD_ZONE: float = 0.15

enum InputSource {NETWORK, GAMEPAD, DM}

const _SOURCE_ORDER: Array[int] = [InputSource.DM, InputSource.GAMEPAD, InputSource.NETWORK]

# Stores vectors by source per player_id.
# { player_id (Variant): { source_id (int): Vector2 } }
var _source_vectors: Dictionary = {}

# Maps gamepad device_id → player_id (populated when profiles are bound)
# { device_id (int): player_id (Variant) }
var gamepad_bindings: Dictionary = {}


func _game_state() -> Node:
	var registry := get_node_or_null("/root/ServiceRegistry")
	if registry != null and registry.has_method("get_service"):
		var svc := registry.get_service("GameState") as Node
		if svc == null:
			svc = registry.get_service("GameStateAdapter") as Node
		return svc
	return null

# ---------------------------------------------------------------------------
# Frame update — poll all bound gamepads
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	for device_id in gamepad_bindings.keys():
		var player_id = gamepad_bindings[device_id]
		var raw := Vector2(
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
		)
		# Apply dead-zone and normalize
		if raw.length() < DEAD_ZONE:
			raw = Vector2.ZERO
		else:
			raw = raw.normalized() * ((raw.length() - DEAD_ZONE) / (1.0 - DEAD_ZONE))
			raw = raw.clampf(-1.0, 1.0)
		set_gamepad_vector(player_id, raw)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the current movement vector for player_id.
## Returns Vector2.ZERO if the player is locked or has no input source.
func get_vector(player_id) -> Vector2:
	if _game_state().is_locked(player_id):
		return Vector2.ZERO
	var source_map: Dictionary = _source_vectors.get(player_id, {}) as Dictionary
	var vec := Vector2.ZERO
	for source_id in _SOURCE_ORDER:
		if source_map.has(source_id):
			vec = source_map[source_id] as Vector2
			break
	if vec == Vector2.ZERO:
		return vec
	# Rotate input vector based on table_orientation
	var profile: Variant = _game_state().get_profile_by_id(player_id)
	if profile and profile is PlayerProfile:
		var angle_rad := deg_to_rad((profile as PlayerProfile).table_orientation)
		vec = vec.rotated(-angle_rad)
	return vec

## Called by NetworkManager when a WebSocket packet arrives.
func set_vector(player_id, vec: Vector2, source: int = InputSource.NETWORK) -> void:
	# Clamp to valid range (security: also enforced in NetworkManager)
	if not _source_vectors.has(player_id):
		_source_vectors[player_id] = {}
	var source_map: Dictionary = _source_vectors[player_id] as Dictionary
	source_map[source] = vec.clamp(Vector2(-1, -1), Vector2(1, 1))
	_source_vectors[player_id] = source_map


func set_network_vector(player_id, vec: Vector2) -> void:
	set_vector(player_id, vec, InputSource.NETWORK)


func set_gamepad_vector(player_id, vec: Vector2) -> void:
	set_vector(player_id, vec, InputSource.GAMEPAD)


func set_dm_vector(player_id, vec: Vector2) -> void:
	set_vector(player_id, vec, InputSource.DM)

## Called when a player disconnects or is removed.
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

## Bind a gamepad device_id to a player profile id.
func bind_gamepad(device_id: int, player_id) -> void:
	gamepad_bindings[device_id] = player_id

## Unbind a gamepad.
func unbind_gamepad(device_id: int) -> void:
	var player_id = gamepad_bindings.get(device_id, null)
	if player_id != null:
		clear_vector(player_id, InputSource.GAMEPAD)
	gamepad_bindings.erase(device_id)


func clear_all_bindings() -> void:
	gamepad_bindings.clear()
	_source_vectors.clear()
