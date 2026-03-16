extends Node
class_name GameStateAdapter

var _service: Node = null

func set_service(s: Node) -> void:
    _service = s

func _service_or_legacy() -> Node:
    return _service

func get_profile_by_id(id: String):
    var s := _service_or_legacy()
    if s == null:
        return null
    if s.has_method("get_profile_by_id"):
        return s.get_profile_by_id(id)
    return null
