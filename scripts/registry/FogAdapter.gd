extends Node
class_name FogAdapter

var _service: Object = null

func set_service(svc: Object) -> void:
    _service = svc

func reveal_area(pos: Vector2, radius: float) -> void:
    if _service and _service.has_method("reveal_area"):
        _service.reveal_area(pos, radius)
    else:
        push_error("FogAdapter: underlying service not set or missing reveal_area")

func set_fog_enabled(enabled: bool) -> void:
    if _service and _service.has_method("set_fog_enabled"):
        _service.set_fog_enabled(enabled)
    else:
        push_error("FogAdapter: underlying service not set or missing set_fog_enabled")

func get_fog_state() -> Dictionary:
    if _service and _service.has_method("get_fog_state"):
        return _service.get_fog_state()
    push_error("FogAdapter: underlying service not set or missing get_fog_state")
    return {}
