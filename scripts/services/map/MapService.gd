extends IMapService
class_name MapService

const JsonUtilsScript = preload("res://scripts/utils/JsonUtils.gd")

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
	var parsed: Variant = JsonUtilsScript.parse_json_text(text)
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
	# Sync token state from the bundle into the TokenService.
	_sync_tokens_from_map(map)
	emit_signal("map_loaded", _current_map)

func update_map(map: Object) -> void:
	_current_map = map
	emit_signal("map_updated", _current_map)

func get_map() -> Object:
	return _current_map

func get_map_dict() -> Dictionary:
	if _current_map == null:
		return {}
	return _current_map.to_dict()

func save_map_to_bundle(bundle_path: String) -> bool:
	if _current_map == null:
		return false
	# Flush current token state back into the map model before serialising.
	_flush_tokens_to_map(_current_map)
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

func get_map_rotation() -> int:
	if _current_map == null or not (_current_map is MapData):
		return 0
	return (_current_map as MapData).camera_rotation

# ---------------------------------------------------------------------------
# Token sync helpers
# ---------------------------------------------------------------------------

## Load TokenData dicts from the map bundle into the TokenService (if present).
func _sync_tokens_from_map(map: Object) -> void:
	if not (map is MapData):
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null or registry.token.service == null:
		return
	registry.token.service.load_tokens((map as MapData).tokens)


## Serialise current TokenService state back into the map model for persistence.
func _flush_tokens_to_map(map: Object) -> void:
	if not (map is MapData):
		return
	var registry := get_node_or_null("/root/ServiceRegistry") as ServiceRegistry
	if registry == null or registry.token == null or registry.token.service == null:
		return
	var all_tokens: Array = registry.token.service.get_all_tokens()
	var serialised: Array = []
	for raw in all_tokens:
		var td: TokenData = raw as TokenData
		if td != null:
			serialised.append(td.to_dict())
	(map as MapData).tokens = serialised