extends Node
class_name PersistenceAdapter

var _service: Node = null

func set_service(svc: Node) -> void:
    _service = svc

func save_game(save_name: String, state: Dictionary) -> bool:
    if _service != null and _service.has_method("save_game"):
        return _service.save_game(save_name, state)
    return false

func load_game(save_name: String) -> Dictionary:
    if _service != null and _service.has_method("load_game"):
        return _service.load_game(save_name)
    return {}

func list_saves() -> Array:
    if _service != null and _service.has_method("list_saves"):
        return _service.list_saves()
    return []

func delete_save(save_name: String) -> bool:
    if _service != null and _service.has_method("delete_save"):
        return _service.delete_save(save_name)
    return false

func export_to_path(save_name: String, dest_path: String) -> bool:
    if _service != null and _service.has_method("export_to_path"):
        return _service.export_to_path(save_name, dest_path)
    return false

func copy_file(from_path: String, to_path: String) -> int:
    if _service != null and _service.has_method("copy_file"):
        return _service.copy_file(from_path, to_path)
    return FileAccess.get_open_error()
