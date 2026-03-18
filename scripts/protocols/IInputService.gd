extends Node
class_name IInputService

# Protocol for Input service

func get_vector(_player_id: String) -> Vector2:
    return Vector2.ZERO

func set_network_vector(_player_id: String, _v: Vector2) -> void:
    return

func set_gamepad_vector(_player_id: String, _v: Vector2) -> void:
    return

func set_dm_vector(_player_id: String, _v: Vector2) -> void:
    return

func bind_gamepad(_device_id: int, _player_id) -> void:
    return

func unbind_gamepad(_device_id: int) -> void:
    return

func bind_peer(_peer_id: int, _player_id) -> void:
    return

func clear_all_bindings() -> void:
    return
