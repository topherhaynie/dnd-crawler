extends Node
class_name IPersistenceService

"""
Protocol: IPersistenceService

Methods:
- func save_game(save_name: String, state: Dictionary) -> bool
- func load_game(save_name: String) -> Dictionary
- func list_saves() -> Array
- func delete_save(save_name: String) -> bool
- func export_to_path(save_name: String, dest_path: String) -> bool
- func copy_file(from_path: String, to_path: String) -> int

Signals:
- signal persistence_changed(save_name: String)

Notes:
- Minimal signatures only; implementations handle IO and platform specifics.
"""

signal persistence_changed(save_name: String)

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
