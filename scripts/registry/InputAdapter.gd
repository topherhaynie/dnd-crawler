extends Node
class_name InputAdapter

var _service: Node = null

func set_service(svc: Node) -> void:
    _service = svc

func get_vector(player_id) -> Vector2:
    if _service != null and _service.has_method("get_vector"):
        return _service.get_vector(player_id)
    return Vector2.ZERO

func set_network_vector(player_id, vec: Vector2) -> void:
    if _service != null and _service.has_method("set_network_vector"):
        _service.set_network_vector(player_id, vec)

func set_gamepad_vector(player_id, vec: Vector2) -> void:
    if _service != null and _service.has_method("set_gamepad_vector"):
        _service.set_gamepad_vector(player_id, vec)

func set_dm_vector(player_id, vec: Vector2) -> void:
    if _service != null and _service.has_method("set_dm_vector"):
        _service.set_dm_vector(player_id, vec)

func bind_gamepad(device_id: int, player_id) -> void:
    if _service != null and _service.has_method("bind_gamepad"):
        _service.bind_gamepad(device_id, player_id)

func unbind_gamepad(device_id: int) -> void:
    if _service != null and _service.has_method("unbind_gamepad"):
        _service.unbind_gamepad(device_id)

func bind_peer(peer_id: int, player_id) -> void:
    if _service != null and _service.has_method("bind_peer"):
        _service.bind_peer(peer_id, player_id)

func clear_all_bindings() -> void:
    if _service != null and _service.has_method("clear_all_bindings"):
        _service.clear_all_bindings()

func get_gamepad_bindings() -> Dictionary:
    if _service != null and _service.has_method("get_gamepad_bindings"):
        return _service.get_gamepad_bindings()
    # fallback: try direct property access if available
    if _service != null and _service.has_method("has_method") and _service.has("gamepad_bindings"):
        return _service.get("gamepad_bindings")
    return {}

func has_gamepad_binding(device_id: int) -> bool:
    var bindings := get_gamepad_bindings()
    return bindings.has(device_id)
