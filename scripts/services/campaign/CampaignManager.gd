extends RefCounted
class_name CampaignManager

# ---------------------------------------------------------------------------
# CampaignManager — typed coordinator for the campaign domain.
#
# Owned by ServiceRegistry.campaign.  All callers access campaign operations
# through manager methods — never via `registry.campaign.service` directly.
# ---------------------------------------------------------------------------

var service: ICampaignService = null


func get_active_campaign() -> CampaignData:
	if service == null:
		return null
	return service.get_active_campaign()


func new_campaign(p_name: String, p_ruleset: String) -> CampaignData:
	if service == null:
		return null
	return service.new_campaign(p_name, p_ruleset)


func open_campaign(path: String) -> CampaignData:
	if service == null:
		return null
	return service.open_campaign(path)


func save_campaign() -> bool:
	if service == null:
		return false
	return service.save_campaign()


func save_campaign_as(path: String) -> bool:
	if service == null:
		return false
	return service.save_campaign_as(path)


func close_campaign() -> void:
	if service == null:
		return
	service.close_campaign()


func list_campaigns() -> Array:
	if service == null:
		return []
	return service.list_campaigns()


func get_last_campaign_path() -> String:
	if service == null:
		return ""
	return service.get_last_campaign_path()


func add_to_bestiary(statblock: StatblockData) -> void:
	if service == null:
		return
	service.add_to_bestiary(statblock)


func remove_from_bestiary(statblock_id: String) -> void:
	if service == null:
		return
	service.remove_from_bestiary(statblock_id)


func get_bestiary() -> Array:
	if service == null:
		return []
	return service.get_bestiary()


func add_to_item_library(item: ItemEntry) -> void:
	if service == null:
		return
	service.add_to_item_library(item)


func remove_from_item_library(item_id: String) -> void:
	if service == null:
		return
	service.remove_from_item_library(item_id)


func get_item_library() -> Array:
	if service == null:
		return []
	return service.get_item_library()


func add_character(character_id: String) -> void:
	if service == null:
		return
	service.add_character(character_id)


func remove_character(character_id: String) -> void:
	if service == null:
		return
	service.remove_character(character_id)


func get_character_ids() -> Array:
	if service == null:
		return []
	return service.get_character_ids()


func has_character(character_id: String) -> bool:
	if service == null:
		return false
	return service.has_character(character_id)


func set_character_override(character_id: String, p_override: CharacterOverride) -> void:
	if service == null:
		return
	service.set_character_override(character_id, p_override)


func get_character_override(character_id: String) -> CharacterOverride:
	if service == null:
		return null
	return service.get_character_override(character_id)


func remove_character_override(character_id: String) -> void:
	if service == null:
		return
	service.remove_character_override(character_id)


func get_all_character_overrides() -> Dictionary:
	if service == null:
		return {}
	return service.get_all_character_overrides()


func resolve_character_portrait(character_id: String) -> String:
	if service == null:
		return ""
	return service.resolve_character_portrait(character_id)


func resolve_character_name(character_id: String) -> String:
	if service == null:
		return ""
	return service.resolve_character_name(character_id)


func update_settings(new_settings: Dictionary) -> void:
	if service == null:
		return
	service.update_settings(new_settings)


func get_setting(key: String) -> Variant:
	if service == null:
		return null
	return service.get_setting(key)


func add_map_path(path: String) -> void:
	if service == null:
		return
	service.add_map_path(path)


func remove_map_path(path: String) -> void:
	if service == null:
		return
	service.remove_map_path(path)


func get_map_paths() -> Array:
	if service == null:
		return []
	return service.get_map_paths()


func add_save_path(path: String) -> void:
	if service == null:
		return
	service.add_save_path(path)


func remove_save_path(path: String) -> void:
	if service == null:
		return
	service.remove_save_path(path)


func get_save_paths() -> Array:
	if service == null:
		return []
	return service.get_save_paths()


func get_campaign_dir() -> String:
	if service == null:
		return ""
	return service.get_campaign_dir()


func add_note(title: String, body: String, folder: String = "") -> String:
	if service == null:
		return ""
	return service.add_note(title, body, folder)


func update_note(note_id: String, title: String, body: String, folder: String = "") -> void:
	if service == null:
		return
	service.update_note(note_id, title, body, folder)


func delete_note(note_id: String) -> void:
	if service == null:
		return
	service.delete_note(note_id)


func get_notes() -> Array:
	if service == null:
		return []
	return service.get_notes()


func add_image(abs_path: String, copy_to_campaign: bool) -> Dictionary:
	if service == null:
		return {}
	return service.add_image(abs_path, copy_to_campaign)


func update_image(image_id: String, new_name: String, new_folder: String) -> void:
	if service == null:
		return
	service.update_image(image_id, new_name, new_folder)


func remove_image(image_id: String) -> void:
	if service == null:
		return
	service.remove_image(image_id)


func get_images() -> Array:
	if service == null:
		return []
	return service.get_images()


## Folder persistence
func get_note_folders() -> Array:
	if service == null:
		return []
	return service.get_note_folders()


func add_note_folder(folder_name: String) -> void:
	if service == null:
		return
	service.add_note_folder(folder_name)


func remove_note_folder(folder_name: String) -> void:
	if service == null:
		return
	service.remove_note_folder(folder_name)


func rename_note_folder(old_name: String, new_name: String) -> void:
	if service == null:
		return
	service.rename_note_folder(old_name, new_name)


func get_image_folders() -> Array:
	if service == null:
		return []
	return service.get_image_folders()


func add_image_folder(folder_name: String) -> void:
	if service == null:
		return
	service.add_image_folder(folder_name)


func remove_image_folder(folder_name: String) -> void:
	if service == null:
		return
	service.remove_image_folder(folder_name)


func rename_image_folder(old_name: String, new_name: String) -> void:
	if service == null:
		return
	service.rename_image_folder(old_name, new_name)
