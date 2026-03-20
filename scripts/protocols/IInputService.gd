extends Node
class_name IInputService

## Protocol: IInputService
##
## Base class for multi-source input arbitration (gamepad, network, DM override).
## Extend this class for a concrete implementation.

@warning_ignore("unused_signal")
signal input_vector_changed(player_id: Variant, vector: Vector2)
@warning_ignore("unused_signal")
signal input_binding_changed(player_id: Variant)

func get_vector(_player_id: Variant) -> Vector2:
	push_error("IInputService.get_vector: not implemented")
	return Vector2.ZERO

func set_network_vector(_player_id: Variant, _v: Vector2) -> void:
	push_error("IInputService.set_network_vector: not implemented")

func set_gamepad_vector(_player_id: Variant, _v: Vector2) -> void:
	push_error("IInputService.set_gamepad_vector: not implemented")

func set_dm_vector(_player_id: Variant, _v: Vector2) -> void:
	push_error("IInputService.set_dm_vector: not implemented")

func bind_gamepad(_device_id: int, _player_id: Variant) -> void:
	push_error("IInputService.bind_gamepad: not implemented")

func unbind_gamepad(_device_id: int) -> void:
	push_error("IInputService.unbind_gamepad: not implemented")

func bind_peer(_peer_id: int, _player_id: Variant) -> void:
	push_error("IInputService.bind_peer: not implemented")

func clear_all_bindings() -> void:
	push_error("IInputService.clear_all_bindings: not implemented")

func get_gamepad_bindings() -> Dictionary:
	push_error("IInputService.get_gamepad_bindings: not implemented")
	return {}

func has_gamepad_binding(_device_id: int) -> bool:
	push_error("IInputService.has_gamepad_binding: not implemented")
	return false
