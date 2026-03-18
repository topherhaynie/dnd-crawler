extends Node
class_name IPersistenceService

# Protocol for persistence service
# signal persistence_changed(save_name: String)

func save_game(_save_name: String, _state: Dictionary) -> bool:
    return false

func load_game(_save_name: String) -> Dictionary:
    return {}

func list_saves() -> Array:
    return []

func delete_save(_save_name: String) -> bool:
    return false

func export_to_path(_save_name: String, _dest_path: String) -> bool:
    return false

func copy_file(_from_path: String, _to_path: String) -> int:
    return -1
