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

# Stores the latest movement vector per player_id
# { player_id (Variant): Vector2 }
var _vectors: Dictionary = {}

# Maps gamepad device_id → player_id (populated when profiles are bound)
# { device_id (int): player_id (Variant) }
var gamepad_bindings: Dictionary = {}

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
		set_vector(player_id, raw)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns the current movement vector for player_id.
## Returns Vector2.ZERO if the player is locked or has no input source.
func get_vector(player_id) -> Vector2:
	if GameState.is_locked(player_id):
		return Vector2.ZERO
	return _vectors.get(player_id, Vector2.ZERO)

## Called by NetworkManager when a WebSocket packet arrives.
func set_vector(player_id, vec: Vector2) -> void:
	# Clamp to valid range (security: also enforced in NetworkManager)
	_vectors[player_id] = vec.clamp(Vector2(-1, -1), Vector2(1, 1))

## Called when a player disconnects or is removed.
func clear_vector(player_id) -> void:
	_vectors.erase(player_id)

## Bind a gamepad device_id to a player profile id.
func bind_gamepad(device_id: int, player_id) -> void:
	gamepad_bindings[device_id] = player_id

## Unbind a gamepad.
func unbind_gamepad(device_id: int) -> void:
	gamepad_bindings.erase(device_id)


func clear_all_bindings() -> void:
	gamepad_bindings.clear()
