extends Node
class_name ISRDLibraryService

# ---------------------------------------------------------------------------
# ISRDLibraryService — protocol for the SRD reference library service.
# ---------------------------------------------------------------------------

@warning_ignore("unused_signal")
signal library_loaded
@warning_ignore("unused_signal")
signal image_prefetch_progress(current: int, total: int)
@warning_ignore("unused_signal")
signal image_prefetch_completed
@warning_ignore("unused_signal")
signal update_check_completed(has_update: bool, remote_version: String, message: String)


func load_library() -> void:
	push_error("ISRDLibraryService.load_library: not implemented")


func get_monsters(p_ruleset: String) -> Array:
	push_error("ISRDLibraryService.get_monsters: not implemented [%s]" % p_ruleset)
	return []


func get_monster(index: String, p_ruleset: String) -> StatblockData:
	push_error("ISRDLibraryService.get_monster: not implemented [%s, %s]" % [index, p_ruleset])
	return null


func get_spells(p_ruleset: String) -> Array:
	push_error("ISRDLibraryService.get_spells: not implemented [%s]" % p_ruleset)
	return []


func get_spell(index: String, p_ruleset: String) -> SpellData:
	push_error("ISRDLibraryService.get_spell: not implemented [%s, %s]" % [index, p_ruleset])
	return null


func get_equipment(p_ruleset: String) -> Array:
	push_error("ISRDLibraryService.get_equipment: not implemented [%s]" % p_ruleset)
	return []


func get_conditions(p_ruleset: String) -> Array:
	push_error("ISRDLibraryService.get_conditions: not implemented [%s]" % p_ruleset)
	return []


func get_classes(p_ruleset: String) -> Array:
	push_error("ISRDLibraryService.get_classes: not implemented [%s]" % p_ruleset)
	return []


func get_races(p_ruleset: String) -> Array:
	push_error("ISRDLibraryService.get_races: not implemented [%s]" % p_ruleset)
	return []


func get_feats(p_ruleset: String) -> Array:
	push_error("ISRDLibraryService.get_feats: not implemented [%s]" % p_ruleset)
	return []


func get_feat(index: String, p_ruleset: String) -> Dictionary:
	push_error("ISRDLibraryService.get_feat: not implemented [%s, %s]" % [index, p_ruleset])
	return {}


func search(query: String, category: String, p_ruleset: String) -> Array:
	push_error("ISRDLibraryService.search: not implemented [%s, %s, %s]" % [query, category, p_ruleset])
	return []


func get_version() -> String:
	push_error("ISRDLibraryService.get_version: not implemented")
	return ""


func get_monster_image_url(index: String) -> String:
	push_error("ISRDLibraryService.get_monster_image_url: not implemented [%s]" % index)
	return ""


func get_cached_monster_image(index: String) -> Image:
	push_error("ISRDLibraryService.get_cached_monster_image: not implemented [%s]" % index)
	return null


func prefetch_all_monster_images() -> void:
	push_error("ISRDLibraryService.prefetch_all_monster_images: not implemented")


func check_for_updates(version_url: String) -> void:
	push_error("ISRDLibraryService.check_for_updates: not implemented [%s]" % version_url)
