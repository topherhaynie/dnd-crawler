extends Node
class_name IPersistenceService

## Protocol: IPersistenceService
##
## Base class for JSON file persistence. Extend this class for a concrete
## save/load implementation.

@warning_ignore("unused_signal")
signal persistence_changed(save_name: String)

func save_game(_save_name: String, _state: Dictionary) -> bool:
	push_error("IPersistenceService.save_game: not implemented")
	return false

func load_game(_save_name: String) -> Dictionary:
	push_error("IPersistenceService.load_game: not implemented")
	return {}

func list_saves() -> Array:
	push_error("IPersistenceService.list_saves: not implemented")
	return []

func delete_save(_save_name: String) -> bool:
	push_error("IPersistenceService.delete_save: not implemented")
	return false

func export_to_path(_save_name: String, _dest_path: String) -> bool:
	push_error("IPersistenceService.export_to_path: not implemented")
	return false

func copy_file(_from_path: String, _to_path: String) -> int:
	push_error("IPersistenceService.copy_file: not implemented")
	return -1
