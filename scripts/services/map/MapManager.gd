extends RefCounted
class_name MapManager

## Map domain coordinator.
##
## Owns the current MapData model, exposes typed load/save operations, and
## emits signals for domain subscribers (DMWindow, BackendRuntime, etc.).
##
## MapService signals still fire for backward-compat; prefer connecting to
## this manager's signals in new code.
##
## Access via: get_node("/root/ServiceRegistry").map

signal map_loaded(map: MapData)
signal map_updated(map: MapData)
signal map_unloaded

var service: IMapService = null
var model: MapData = null


func load_from_bundle(bundle_path: String) -> MapData:
	## Load a .map bundle via the service, update model, and emit map_loaded.
	if service == null:
		return null
	var loaded := service.load_map_from_bundle(bundle_path) as MapData
	if loaded == null:
		return null
	model = loaded
	map_loaded.emit(model)
	return model


func load(map_data: MapData) -> void:
	## Assign a MapData directly, update model, and emit map_loaded.
	if service == null:
		return
	service.load_map(map_data)
	model = map_data
	map_loaded.emit(model)


func update(map_data: MapData) -> void:
	## Apply a MapData update, sync model, and emit map_updated.
	if service == null:
		return
	service.update_map(map_data)
	model = map_data
	map_updated.emit(model)


func get_map() -> MapData:
	return model


func save_to_bundle(bundle_path: String) -> bool:
	if service == null:
		return false
	return service.save_map_to_bundle(bundle_path)


func unload() -> void:
	model = null
	map_unloaded.emit()
