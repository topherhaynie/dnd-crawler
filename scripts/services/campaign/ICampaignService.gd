extends Node
class_name ICampaignService

# ---------------------------------------------------------------------------
# ICampaignService — protocol for campaign management.
# ---------------------------------------------------------------------------

@warning_ignore("unused_signal")
signal campaign_loaded(campaign: CampaignData)
@warning_ignore("unused_signal")
signal campaign_saved(campaign: CampaignData)
@warning_ignore("unused_signal")
signal campaign_closed
@warning_ignore("unused_signal")
signal bestiary_updated
@warning_ignore("unused_signal")
signal assets_changed
@warning_ignore("unused_signal")
signal notes_changed
@warning_ignore("unused_signal")
signal images_changed
@warning_ignore("unused_signal")
signal item_library_updated


func get_active_campaign() -> CampaignData:
	push_error("ICampaignService.get_active_campaign: not implemented")
	return null


func new_campaign(p_name: String, p_ruleset: String) -> CampaignData:
	push_error("ICampaignService.new_campaign: not implemented [%s, %s]" % [p_name, p_ruleset])
	return null


func open_campaign(path: String) -> CampaignData:
	push_error("ICampaignService.open_campaign: not implemented [%s]" % path)
	return null


func save_campaign() -> bool:
	push_error("ICampaignService.save_campaign: not implemented")
	return false


func save_campaign_as(path: String) -> bool:
	push_error("ICampaignService.save_campaign_as: not implemented [%s]" % path)
	return false


func close_campaign() -> void:
	push_error("ICampaignService.close_campaign: not implemented")


func list_campaigns() -> Array:
	push_error("ICampaignService.list_campaigns: not implemented")
	return []


func get_last_campaign_path() -> String:
	return ""


## Bestiary management
func add_to_bestiary(statblock: StatblockData) -> void:
	push_error("ICampaignService.add_to_bestiary: not implemented [%s]" % statblock)


func remove_from_bestiary(statblock_id: String) -> void:
	push_error("ICampaignService.remove_from_bestiary: not implemented [%s]" % statblock_id)


func get_bestiary() -> Array:
	push_error("ICampaignService.get_bestiary: not implemented")
	return []


## Item library management
func add_to_item_library(_item: ItemEntry) -> void:
	push_error("ICampaignService.add_to_item_library: not implemented")


func remove_from_item_library(_item_id: String) -> void:
	push_error("ICampaignService.remove_from_item_library: not implemented")


func get_item_library() -> Array:
	push_error("ICampaignService.get_item_library: not implemented")
	return []


## Character ID management (data lives in CharacterService)
func add_character(character_id: String) -> void:
	push_error("ICampaignService.add_character: not implemented [%s]" % character_id)


func remove_character(character_id: String) -> void:
	push_error("ICampaignService.remove_character: not implemented [%s]" % character_id)


func get_character_ids() -> Array:
	push_error("ICampaignService.get_character_ids: not implemented")
	return []


func has_character(character_id: String) -> bool:
	push_error("ICampaignService.has_character: not implemented [%s]" % character_id)
	return false


## Character overrides (campaign-scoped presentation layer for global characters)
func set_character_override(character_id: String, _override: CharacterOverride) -> void:
	push_error("ICampaignService.set_character_override: not implemented [%s]" % character_id)


func get_character_override(character_id: String) -> CharacterOverride:
	push_error("ICampaignService.get_character_override: not implemented [%s]" % character_id)
	return null


func remove_character_override(character_id: String) -> void:
	push_error("ICampaignService.remove_character_override: not implemented [%s]" % character_id)


func get_all_character_overrides() -> Dictionary:
	push_error("ICampaignService.get_all_character_overrides: not implemented")
	return {}


## Resolve the effective portrait path for a character in this campaign.
## Resolution: campaign override → global character portrait → empty string.
func resolve_character_portrait(character_id: String) -> String:
	push_error("ICampaignService.resolve_character_portrait: not implemented [%s]" % character_id)
	return ""


## Resolve the effective display name for a character in this campaign.
## Resolution: campaign override → global character name → empty string.
func resolve_character_name(character_id: String) -> String:
	push_error("ICampaignService.resolve_character_name: not implemented [%s]" % character_id)
	return ""


## Settings
func update_settings(new_settings: Dictionary) -> void:
	push_error("ICampaignService.update_settings: not implemented [%s]" % str(new_settings))


func get_setting(key: String) -> Variant:
	push_error("ICampaignService.get_setting: not implemented [%s]" % key)
	return null


## Map/save path management
func add_map_path(path: String) -> void:
	push_error("ICampaignService.add_map_path: not implemented [%s]" % path)


func remove_map_path(path: String) -> void:
	push_error("ICampaignService.remove_map_path: not implemented [%s]" % path)


func get_map_paths() -> Array:
	push_error("ICampaignService.get_map_paths: not implemented")
	return []


func add_save_path(path: String) -> void:
	push_error("ICampaignService.add_save_path: not implemented [%s]" % path)


func remove_save_path(path: String) -> void:
	push_error("ICampaignService.remove_save_path: not implemented [%s]" % path)


func get_save_paths() -> Array:
	push_error("ICampaignService.get_save_paths: not implemented")
	return []


func get_campaign_dir() -> String:
	push_error("ICampaignService.get_campaign_dir: not implemented")
	return ""


## Notes (stored in campaign.json: {id, title, body, folder, created_at, updated_at})
func add_note(title: String, _body: String, _folder: String) -> String:
	push_error("ICampaignService.add_note: not implemented [%s]" % title)
	return ""


func update_note(note_id: String, _title: String, _body: String, _folder: String) -> void:
	push_error("ICampaignService.update_note: not implemented [%s]" % note_id)


func delete_note(note_id: String) -> void:
	push_error("ICampaignService.delete_note: not implemented [%s]" % note_id)


func get_notes() -> Array:
	push_error("ICampaignService.get_notes: not implemented")
	return []


## Images (stored in campaign.json; optionally copied to .campaign/assets/)
func add_image(abs_path: String, _copy_to_campaign: bool) -> Dictionary:
	push_error("ICampaignService.add_image: not implemented [%s]" % abs_path)
	return {}


func update_image(image_id: String, _name: String, _folder: String) -> void:
	push_error("ICampaignService.update_image: not implemented [%s]" % image_id)


func remove_image(image_id: String) -> void:
	push_error("ICampaignService.remove_image: not implemented [%s]" % image_id)


func get_images() -> Array:
	push_error("ICampaignService.get_images: not implemented")
	return []


## Folder persistence (empty folders survive refresh/reload).
func get_note_folders() -> Array:
	push_error("ICampaignService.get_note_folders: not implemented")
	return []

func add_note_folder(_name: String) -> void:
	push_error("ICampaignService.add_note_folder: not implemented")

func remove_note_folder(_name: String) -> void:
	push_error("ICampaignService.remove_note_folder: not implemented")

func rename_note_folder(_old_name: String, _new_name: String) -> void:
	push_error("ICampaignService.rename_note_folder: not implemented")

func get_image_folders() -> Array:
	push_error("ICampaignService.get_image_folders: not implemented")
	return []

func add_image_folder(_name: String) -> void:
	push_error("ICampaignService.add_image_folder: not implemented")

func remove_image_folder(_name: String) -> void:
	push_error("ICampaignService.remove_image_folder: not implemented")

func rename_image_folder(_old_name: String, _new_name: String) -> void:
	push_error("ICampaignService.rename_image_folder: not implemented")
