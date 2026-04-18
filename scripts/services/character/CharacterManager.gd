extends RefCounted
class_name CharacterManager

# ---------------------------------------------------------------------------
# CharacterManager — typed coordinator for the global character roster.
# Access via: registry.character
# ---------------------------------------------------------------------------

signal characters_changed()

var service: ICharacterService = null


func get_characters() -> Array:
	if service == null:
		return []
	return service.get_characters()


func get_character_by_id(id: String) -> StatblockData:
	if service == null:
		return null
	return service.get_character_by_id(id)


func add_character(statblock: StatblockData) -> void:
	if service == null:
		return
	service.add_character(statblock)
	service.save_characters()
	characters_changed.emit()


func remove_character(id: String) -> void:
	if service == null:
		return
	service.remove_character(id)
	service.save_characters()
	characters_changed.emit()


func save() -> void:
	if service == null:
		return
	service.save_characters()


func load() -> void:
	if service == null:
		return
	service.load_characters()
	characters_changed.emit()
