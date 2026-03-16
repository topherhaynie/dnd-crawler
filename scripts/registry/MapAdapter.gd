extends Node
class_name MapAdapter

var _service: Object = null

func set_service(svc: Object) -> void:
    _service = svc

func load_map_from_bundle(bundle_path: String) -> Object:
    if _service and _service.has_method("load_map_from_bundle"):
        return _service.load_map_from_bundle(bundle_path)
    return null

func load_map(map: Object) -> void:
    if _service and _service.has_method("load_map"):
        _service.load_map(map)

func get_map() -> Object:
    if _service and _service.has_method("get_map"):
        return _service.get_map()
    return null

func save_map_to_bundle(bundle_path: String) -> bool:
    if _service and _service.has_method("save_map_to_bundle"):
        return _service.save_map_to_bundle(bundle_path)
    return false
