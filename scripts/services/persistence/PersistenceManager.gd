extends RefCounted
class_name PersistenceManager

## Typed manager for the persistence service.
## Access via: get_node("/root/ServiceRegistry").persistence

var service: IPersistenceService = null


func save_game(save_name: String, state: Dictionary) -> bool:
	if service == null:
		return false
	return service.save_game(save_name, state)


func export_to_path(save_name: String, dest_path: String) -> bool:
	if service == null:
		return false
	return service.export_to_path(save_name, dest_path)


func delete_save(save_name: String) -> bool:
	if service == null:
		return false
	return service.delete_save(save_name)


func load_game(save_name: String) -> Dictionary:
	if service == null:
		return {}
	return service.load_game(save_name)


func copy_file(from_path: String, to_path: String) -> int:
	if service == null:
		return -1
	return service.copy_file(from_path, to_path)
