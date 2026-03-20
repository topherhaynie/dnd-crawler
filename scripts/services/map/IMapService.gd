extends Node
class_name IMapService

## Protocol: IMapService
##
## Base class for map lifecycle management. Extend this class for a concrete
## map loading and persistence implementation.

@warning_ignore("unused_signal")
signal map_loaded(map: Object)
@warning_ignore("unused_signal")
signal map_updated(map: Object)

func load_map_from_bundle(_bundle_path: String) -> Object:
	push_error("IMapService.load_map_from_bundle: not implemented")
	return null

func load_map(_map: Object) -> void:
	push_error("IMapService.load_map: not implemented")

func update_map(_map: Object) -> void:
	push_error("IMapService.update_map: not implemented")

func get_map() -> Object:
	push_error("IMapService.get_map: not implemented")
	return null

func save_map_to_bundle(_bundle_path: String) -> bool:
	push_error("IMapService.save_map_to_bundle: not implemented")
	return false

func get_map_rotation() -> int:
	push_error("IMapService.get_map_rotation: not implemented")
	return 0
