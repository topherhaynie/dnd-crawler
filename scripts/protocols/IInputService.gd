extends Node
class_name IInputService

"""
Protocol: IInputService

Methods:
- func get_vector(player_id: String) -> Vector2
- func set_network_vector(player_id: String, v: Vector2) -> void
- func set_gamepad_vector(player_id: String, v: Vector2) -> void
- func set_dm_vector(player_id: String, v: Vector2) -> void
- func bind_gamepad(device_id: int, player_id: String) -> void
- func unbind_gamepad(device_id: int) -> void
- func bind_peer(peer_id: int, player_id: String) -> void
- func clear_all_bindings() -> void
- func get_gamepad_bindings() -> Dictionary
- func has_gamepad_binding(device_id: int) -> bool

Notes:
- Minimal signatures only; implementations provide backing state.
"""

func get_vector(_player_id: String) -> Vector2:
    return Vector2.ZERO

func set_network_vector(_player_id: String, _v: Vector2) -> void:
    pass

func set_gamepad_vector(_player_id: String, _v: Vector2) -> void:
    pass

func set_dm_vector(_player_id: String, _v: Vector2) -> void:
    pass

func bind_gamepad(_device_id: int, _player_id: String) -> void:
    pass

func unbind_gamepad(_device_id: int) -> void:
    pass

func bind_peer(_peer_id: int, _player_id: String) -> void:
    pass

func clear_all_bindings() -> void:
    pass

func get_gamepad_bindings() -> Dictionary:
    return {}

func has_gamepad_binding(_device_id: int) -> bool:
    return false
