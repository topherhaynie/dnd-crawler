extends Node
class_name MapService

signal map_loaded(map: Object)
signal map_updated(map: Object)

@onready var _current_map: Object = null

func _ready() -> void:
    pass

func load_map_from_bundle(bundle_path: String) -> Object:
    var json_path := bundle_path.path_join("map.json")
    var fa := FileAccess.open(json_path, FileAccess.READ)
    if fa == null:
        push_error("MapService: cannot read '%s'" % json_path)
        return null
    var text := fa.get_as_text()
    fa.close()
    var parsed: Variant = JSON.parse_string(text)
    if not (parsed is Dictionary):
        push_error("MapService: invalid JSON in '%s'" % json_path)
        return null
    var d: Dictionary = parsed as Dictionary
    if d.has("image_path"):
        var img_ref: String = d["image_path"]
        if not img_ref.is_absolute_path() and not img_ref.begins_with("user://"):
            d["image_path"] = bundle_path.path_join(img_ref)
    var map := MapData.from_dict(d)
    load_map(map)
    return map

func load_map(map: Object) -> void:
    _current_map = map
    emit_signal("map_loaded", _current_map)

func update_map(map: Object) -> void:
    _current_map = map
    emit_signal("map_updated", _current_map)

func get_map() -> Object:
    return _current_map

func get_map_dict() -> Dictionary:
    if _current_map == null:
        return {}
    if _current_map.has_method("to_dict"):
        return _current_map.to_dict()
    return {}

func save_map_to_bundle(bundle_path: String) -> bool:
    if _current_map == null:
        return false
    var json_path := bundle_path.path_join("map.json")
    var fa := FileAccess.open(json_path, FileAccess.WRITE)
    if fa == null:
        push_error("MapService: cannot write '%s'" % json_path)
        return false
    var payload := get_map_dict()
    # Store image filename relative to bundle to match existing behaviour
    if payload.has("image_path") and payload["image_path"] is String:
        payload["image_path"] = str(payload["image_path"]).get_file()
    fa.store_string(JSON.stringify(payload, "\t"))
    fa.close()
    return true
