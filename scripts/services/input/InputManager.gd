extends RefCounted
class_name InputManager

## Input domain coordinator.
##
## Owns InputModel (mirrors binding state) and exposes domain operations
## through IInputService. High-frequency vector-change signals are emitted
## by the service; discrete binding-change signals are emitted here.
##
## Access via: get_node("/root/ServiceRegistry").input

@warning_ignore("unused_signal")
signal input_vector_changed(player_id: Variant, vector: Vector2)
signal input_binding_changed(player_id: Variant)

var service: IInputService = null
var model: InputModel = null


func get_vector(player_id: Variant) -> Vector2:
	if service == null:
		return Vector2.ZERO
	return service.get_vector(player_id)


func set_network_vector(player_id: Variant, vec: Vector2) -> void:
	if service == null:
		return
	service.set_network_vector(player_id, vec)


func set_gamepad_vector(player_id: Variant, vec: Vector2) -> void:
	if service == null:
		return
	service.set_gamepad_vector(player_id, vec)


func set_dm_vector(player_id: Variant, vec: Vector2) -> void:
	if service == null:
		return
	service.set_dm_vector(player_id, vec)


func bind_gamepad(device_id: int, player_id: Variant) -> void:
	if service == null:
		return
	service.bind_gamepad(device_id, player_id)
	if model != null:
		model.gamepad_bindings[device_id] = player_id
	input_binding_changed.emit(player_id)


func unbind_gamepad(device_id: int) -> void:
	if service == null:
		return
	if model != null:
		model.gamepad_bindings.erase(device_id)
	service.unbind_gamepad(device_id)
	input_binding_changed.emit(null)


func bind_peer(peer_id: int, player_id: Variant) -> void:
	if service == null:
		return
	service.bind_peer(peer_id, player_id)


func clear_all_bindings() -> void:
	if model != null:
		model.gamepad_bindings.clear()
		model.source_vectors.clear()
	if service != null:
		service.clear_all_bindings()
	input_binding_changed.emit(null)


func get_gamepad_bindings() -> Dictionary:
	if model != null:
		return model.gamepad_bindings
	if service != null:
		return service.get_gamepad_bindings()
	return {}


func has_gamepad_binding(device_id: int) -> bool:
	if model != null:
		return model.gamepad_bindings.has(device_id)
	if service != null:
		return service.has_gamepad_binding(device_id)
	return false
