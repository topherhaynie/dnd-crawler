extends Node
class_name FogAdapter

var _service: Object = null

func set_service(svc: Object) -> void:
    _service = svc

func reveal_area(pos: Vector2, radius: float) -> void:
    if _service and _service.has_method("reveal_area"):
        _service.reveal_area(pos, radius)
        return
    push_error("FogAdapter: underlying Fog service not set or missing reveal_area")

func set_fog_enabled(enabled: bool) -> void:
    if _service and _service.has_method("set_fog_enabled"):
        _service.set_fog_enabled(enabled)
        return
    push_error("FogAdapter: underlying Fog service not set or missing set_fog_enabled")

func get_fog_state() -> PackedByteArray:
    if _service and _service.has_method("get_fog_state"):
        var res := _service.get_fog_state() as PackedByteArray
        if res != null:
            return res
    push_error("FogAdapter: underlying Fog service not set or missing get_fog_state")
    return PackedByteArray()


func set_fog_state(data: PackedByteArray) -> bool:
    if _service and _service.has_method("set_fog_state"):
        return bool(_service.set_fog_state(data))
    push_error("FogAdapter: underlying Fog service not set or missing set_fog_state")
    return false


func get_fog_state_size() -> Vector2i:
    if _service and _service.has_method("get_fog_state_size"):
        return _service.get_fog_state_size() as Vector2i
    push_error("FogAdapter: underlying Fog service not set or missing get_fog_state_size")
    return Vector2i(0, 0)


func capture_fog_state(viewport: SubViewport) -> PackedByteArray:
    if _service and _service.has_method("capture_fog_state"):
        return _service.capture_fog_state(viewport)
    push_error("FogAdapter: underlying Fog service not set or missing capture_fog_state")
    return PackedByteArray()
