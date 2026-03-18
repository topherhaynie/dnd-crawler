extends Node
class_name IMapService

"""
Protocol: IMapService

Methods:
- func load_map_from_bundle(bundle_path: String) -> Object
- func load_map(map: Object) -> void
- func get_map() -> Object
- func save_map_to_bundle(bundle_path: String) -> bool

Signals:
- signal map_loaded(map: Object)
- signal map_updated(map: Object)

Notes:
- Protocol defines map lifecycle hooks and minimal signatures.
"""

signal map_loaded(map: Object)
signal map_updated(map: Object)

func load_map_from_bundle(_bundle_path: String) -> Object:
    return null

func load_map(_map: Object) -> void:
    pass

func get_map() -> Object:
    return null

func save_map_to_bundle(_bundle_path: String) -> bool:
    return false
