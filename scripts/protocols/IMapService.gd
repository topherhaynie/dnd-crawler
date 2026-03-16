extends Node
class_name IMapService

# Protocol interface for MapService
# Implementations should provide the following methods and signals.

@warning_ignore("unused_signal")
signal map_loaded(map: Object)
@warning_ignore("unused_signal")
signal map_updated(map: Object)

func load_map_from_bundle(_bundle_path: String) -> Object:
    return null

func load_map(_map: Object) -> void:
    return

func get_map() -> Object:
    return null

func save_map_to_bundle(_bundle_path: String) -> bool:
    return false
