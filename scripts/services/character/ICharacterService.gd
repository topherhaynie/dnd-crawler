extends Node
class_name ICharacterService

## Protocol: ICharacterService
##
## Global, campaign-independent character roster.
## Characters are StatblockData objects persisted to user://data/characters.json.
## Campaigns reference characters by ID only.

@warning_ignore("unused_signal")
signal characters_changed()

func get_characters() -> Array:
	push_error("ICharacterService.get_characters: not implemented")
	return []

func get_character_by_id(_id: String) -> StatblockData:
	push_error("ICharacterService.get_character_by_id: not implemented")
	return null

func add_character(_statblock: StatblockData) -> void:
	push_error("ICharacterService.add_character: not implemented")

func remove_character(_id: String) -> void:
	push_error("ICharacterService.remove_character: not implemented")

func save_characters() -> void:
	push_error("ICharacterService.save_characters: not implemented")

func load_characters() -> void:
	push_error("ICharacterService.load_characters: not implemented")
